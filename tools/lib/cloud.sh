# shellcheck shell=bash
# tools/lib/cloud.sh — adopter-usable: the pieces tools/cloud-brief.sh and tools/cloud-land.sh share — the
# dispatch ledger, its lock, resolving a project's main checkout, reading a GitHub `owner/name` out of a remote
# URL, and the scanner's file mode (dir #900). The rules they serve live in docs/cloud.md. Sourced, not executed;
# no `set -e`/`set -u` assumption. The caller sources tools/lib/repo-top.sh, tools/lib/safe-write.sh and
# tools/lib/leak-gate.sh first.
#
# The ledger is one tab-separated file, a header line then one row per (repo, ticket), 15 cells:
#   built · repo · ticket · branch · model/effort · brief bytes · credit before · status · credit after ·
#   overlap · landed · landing exit · head SHA · PR · session
# (dir #913: the session cell is the one place a dispatch's session id is kept — never in the ticket. A ledger written
# before it has a 14-cell header and rows; its rows gain the cell when a dispatch sets it.)
# Status: built → dispatched → landed, or abandoned (set by hand). A cell never holds a tab or a newline.
# Values reach awk through ENVIRON, never `-v`, which would read a backslash in them as an escape; keys compare as
# strings (`($3 "") == (t "")`), since awk compares two numeric-looking values as numbers (`2.1` = `2.10`).

CLOUD_LEDGER_HEADER="$(printf 'built\trepo\tticket\tbranch\tmodel/effort\tbrief bytes\tcredit before\tstatus\tcredit after\toverlap\tlanded\tlanding exit\thead SHA\tPR\tsession')"
CLOUD_LOCK_WAIT=10        # seconds a second writer waits for the lock
CLOUD_LOCK_STALE_MIN=10   # minutes after which a held lock is named stale (never removed by a tool)
CLOUD_ERR=""              # why the last cloud_resolve_main or cloud_personal_file call failed

# cloud_absolutize_env — make the scanner's path-valued variables (tools/lib/leak-gate.sh's _LEAK_GATE_PATH_ENV:
# TMPDIR, HOME, the personal list, the impact log) absolute against the current directory, exported. Call it
# first thing, before any `mktemp`: the scan runs from another directory, where a relative value means another
# file (a relative TMPDIR would also make the tool's own work directory relative).
# rc 1 when tools/lib/leak-gate.sh is not loaded.
cloud_absolutize_env() {
  if ! command -v _leak_gate_absolutize_env >/dev/null 2>&1; then
    echo "cloud: tools/lib/leak-gate.sh is not loaded — the caller must source it first." >&2
    return 1
  fi
  _leak_gate_absolutize_env
}

# cloud_resolve_main REPO — set MAIN, the physical path of REPO's main checkout: keel_repo_top's answer (the first
# `git worktree list` entry, else — a bare main repository — REPO's own toplevel). rc 1 with CLOUD_ERR set when REPO is not a directory
# inside a git repository. Every `cd` here and in the tools runs with CDPATH empty: a CDPATH entry holding a
# same-named directory would win over the relative path, and `cd` would print it into the capture.
cloud_resolve_main() {
  local repo_dir top
  CLOUD_ERR=""
  [ -d "$1" ] || { CLOUD_ERR="no directory $1"; return 1; }
  repo_dir="$(CDPATH='' cd -- "$1" && pwd -P)" || { CLOUD_ERR="cannot enter $1"; return 1; }
  git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { CLOUD_ERR="$repo_dir is not inside a git repository"; return 1; }
  top="$(keel_repo_top "$repo_dir")"
  # shellcheck disable=SC2034  # read by the caller
  MAIN="$(CDPATH='' cd -- "$top" && pwd -P)" || { CLOUD_ERR="cannot resolve the main checkout of $repo_dir"; return 1; }
}

# cloud_github_slug URL — print `owner/name` for a github.com remote URL (https, ssh or scp form; a trailing
# `.git` or `/` dropped); rc 1 and no output for anything else.
cloud_github_slug() {
  local u="$1" s
  case "$u" in
    https://github.com/*) s="${u#https://github.com/}" ;;
    http://github.com/*) s="${u#http://github.com/}" ;;
    ssh://git@github.com/*) s="${u#ssh://git@github.com/}" ;;
    git@github.com:*) s="${u#git@github.com:}" ;;
    *) return 1 ;;
  esac
  s="${s%/}"
  s="${s%.git}"
  case "$s" in
    */*/*|/*|*/|'') return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  case "$s" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
  printf '%s' "$s"
}

# cloud_cell_ok VALUE — rc 0 when VALUE can be a ledger cell (no tab, no newline).
cloud_cell_ok() {
  case "$1" in *$'\t'*|*$'\n'*) return 1 ;; esac
  return 0
}

# _cloud_safe_write_loaded — rc 0 when tools/lib/safe-write.sh is loaded, else rc 1 and one line on stderr.
_cloud_safe_write_loaded() {
  command -v keel_write_state >/dev/null 2>&1 && return 0
  echo "cloud: tools/lib/safe-write.sh is not loaded — the caller must source it first; nothing was written." >&2
  return 1
}

# cloud_ledger_init LEDGER — create the ledger (and its directory) with its header when absent, as a STATE write
# like cloud_ledger_put's: both refuse a ledger FILE that is a symlink into the Keel checkout (a ledger reached
# through a linked DIRECTORY is not refused — keel_write_state checks the file's own link only); rc 1 on failure.
cloud_ledger_init() {
  local f="$1"
  [ -f "$f" ] && return 0
  _cloud_safe_write_loaded || return 1
  mkdir -p "$(dirname "$f")" || return 1
  keel_write_state "$f" printf '%s\n' "$CLOUD_LEDGER_HEADER"
}

# cloud_ledger_lock LEDGER — take `<ledger dir>/ledger.lock` (a mkdir lock: portable, `flock` is absent on stock
# macOS). Waits up to CLOUD_LOCK_WAIT seconds; a lock older than CLOUD_LOCK_STALE_MIN minutes is named stale at
# once and left in place. rc 0 locked · rc 1 not locked (the reason on stderr).
cloud_ledger_lock() {
  local lock waited=0
  lock="$(dirname "$1")/ledger.lock"
  while ! mkdir "$lock" 2>/dev/null; do
    if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +"$CLOUD_LOCK_STALE_MIN" 2>/dev/null)" ]; then
      printf 'the ledger lock %s is stale (older than %s minutes) — remove it by hand once no dispatch is running\n' \
        "$lock" "$CLOUD_LOCK_STALE_MIN" >&2
      return 1
    fi
    if [ "$waited" -ge "$CLOUD_LOCK_WAIT" ]; then
      printf 'the ledger lock %s is held — waited %ss; retry once the other run ends\n' "$lock" "$waited" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 0
}

# cloud_ledger_unlock LEDGER — release the lock cloud_ledger_lock took.
cloud_ledger_unlock() {
  rmdir "$(dirname "$1")/ledger.lock" 2>/dev/null || true
}

# cloud_ledger_row LEDGER REPO TICKET — print the row for (REPO, TICKET); rc 1 when there is none.
cloud_ledger_row() {
  [ -f "$1" ] || return 1
  CL_R="$2" CL_T="$3" awk -F'\t' 'BEGIN { r = ENVIRON["CL_R"]; t = ENVIRON["CL_T"] }
    NR > 1 && ($2 "") == (r "") && ($3 "") == (t "") { print; found = 1; exit } END { exit !found }' "$1"
}

# cloud_ledger_cell ROW N — print cell N (1-based) of a row.
cloud_ledger_cell() {
  awk -F'\t' -v n="$2" '{ print $n; exit }' <<< "$1"
}

# cloud_ledger_put LEDGER REPO TICKET ROW — replace the (REPO, TICKET) row with ROW, or append ROW, as a STATE
# write (tools/lib/safe-write.sh: a rename, so a reader without the lock never sees half a file). Call it
# holding the lock. rc 1 on a write failure.
cloud_ledger_put() {
  _cloud_safe_write_loaded || return 1
  keel_write_state "$1" env CL_R="$2" CL_T="$3" CL_ROW="$4" awk -F'\t' '
    BEGIN { r = ENVIRON["CL_R"]; t = ENVIRON["CL_T"]; row = ENVIRON["CL_ROW"] }
    NR > 1 && ($2 "") == (r "") && ($3 "") == (t "") && !done { print row; done = 1; next }
    { print }
    END { if (!done) print row }' "$1"
}

# _cloud_set_cell N VALUE — the row on stdin with cell N set to VALUE.
_cloud_set_cell() {
  CL_N="$1" CL_V="$2" awk -F'\t' -v OFS='\t' '{ $(ENVIRON["CL_N"] + 0) = ENVIRON["CL_V"]; print }'
}

# cloud_ledger_set LEDGER REPO TICKET N=VALUE... — set cells of the (REPO, TICKET) row in place. Call it holding
# the lock. rc 1 when there is no such row or the write fails.
cloud_ledger_set() {
  local f="$1" r="$2" t="$3" row a n v
  shift 3
  row="$(cloud_ledger_row "$f" "$r" "$t")" || return 1
  for a in "$@"; do
    n="${a%%=*}" v="${a#*=}"
    row="$(_cloud_set_cell "$n" "$v" <<< "$row")"
  done
  cloud_ledger_put "$f" "$r" "$t" "$row"
}

# cloud_personal_file — the personal-literals list both tools hand the scanner, fail-closed: exports
# SECRET_SCAN_PERSONAL_FILE (its value when set, else the scanner's default ~/.claude/secret-scan-personal),
# made absolute against the current directory because the scanner runs from another one, and rc 1 with
# CLOUD_ERR set when that path is not a regular file — unless it is /dev/null, the scanner's deliberate opt-out.
cloud_personal_file() {
  SECRET_SCAN_PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-${HOME:-}/.claude/secret-scan-personal}"
  case "$SECRET_SCAN_PERSONAL_FILE" in /*) ;; *) SECRET_SCAN_PERSONAL_FILE="$PWD/$SECRET_SCAN_PERSONAL_FILE" ;; esac
  export SECRET_SCAN_PERSONAL_FILE
  CLOUD_ERR=""
  [ "$SECRET_SCAN_PERSONAL_FILE" = /dev/null ] && return 0
  [ -f "$SECRET_SCAN_PERSONAL_FILE" ] && return 0
  # shellcheck disable=SC2034  # read by the caller
  CLOUD_ERR="no personal-literals list at $SECRET_SCAN_PERSONAL_FILE — the scan fails closed; set SECRET_SCAN_PERSONAL_FILE to your list (or to /dev/null to opt out)"
  return 1
}

# cloud_scan_file SCANNER FILE WORKDIR — run the scanner's file mode over FILE (an absolute path) with the inline
# allow marker off (SECRET_SCAN_NO_INLINE_ALLOW=1: a marker in the text would hide its own line, however it is
# spelled — one split by an invalid byte reads whole in the scanner's caller-locale personal pass), from an empty
# directory under WORKDIR (the file mode trusts a `./.secret-scan-allow` in its cwd). The scanner's stdout and
# stderr on stdout; its exit status, or 2 when the directory cannot be made.
cloud_scan_file() {
  mkdir -p "$3/scan-empty" || return 2
  (CDPATH='' cd -- "$3/scan-empty" && SECRET_SCAN_NO_INLINE_ALLOW=1 bash "$1" -- "$2" 2>&1)
}

# _cloud_rate_limited ERRFILE ENDPOINT — rc 0 when a 403 is a rate limit: "rate limit" in gh's message (the primary
# "API rate limit exceeded" and the secondary "exceeded a secondary rate limit" both say it), or the response's
# X-RateLimit-Remaining header at 0. gh prints no headers on an error unless asked, so the header is read from a
# second `gh api ENDPOINT --include` (stdout has the headers even when the call fails); the header name is matched
# in any case (HTTP/2 lowercases it).
_cloud_rate_limited() {
  local headers
  LC_ALL=C grep -qiE 'rate limit' "$1" && return 0
  headers="$(gh api "$2" --include 2>/dev/null || true)" # the call fails by design; a pipe would carry its status (pipefail)
  LC_ALL=C grep -qiE '^x-ratelimit-remaining:[[:space:]]*0[[:space:]]*$' <<< "$headers"
}

# cloud_gh_api ENDPOINT [ARGS...] — `gh api ENDPOINT ARGS...`, its stdout on stdout (the endpoint comes first: a 403
# is probed once more for its rate-limit header, through that endpoint alone). rc 0 ok · rc 4 GitHub answered 404, or
# 403 that is not a rate limit (the repository or ref is not readable) · rc 2 anything else: a rate limit (a 403
# too, but transient — retry later, dir #913), no network, not logged in, gh missing. stderr kept.
cloud_gh_api() {
  local out err rc=0
  err="$(mktemp)" || return 2
  out="$(gh api "$@" 2> "$err")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$err" >&2
    if grep -qE 'HTTP 403' "$err" && _cloud_rate_limited "$err" "$1"; then
      echo "cloud: GitHub answered 403 as a rate limit — transient, not a refusal; retry later" >&2
      rm -f "$err"; return 2
    fi
    if grep -qE 'HTTP 40[34]' "$err"; then rm -f "$err"; return 4; fi
    rm -f "$err"
    return 2
  fi
  rm -f "$err"
  printf '%s\n' "$out"
}
