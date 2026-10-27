# shellcheck shell=bash
# tools/lib/cloud.sh — adopter-usable: the pieces tools/cloud-brief.sh and tools/cloud-land.sh share — the
# dispatch ledger, its lock, and reading a GitHub `owner/name` out of a remote URL (dir #900). The rules they
# serve live in docs/cloud.md. Sourced, not executed; no `set -e`/`set -u` assumption.
#
# The ledger is one tab-separated file, a header line then one row per (repo, ticket), 14 cells:
#   built · repo · ticket · branch · model/effort · brief bytes · credit before · status · credit after ·
#   overlap · landed · landing exit · head SHA · PR
# Status: built → dispatched → landed, or abandoned (set by hand). A cell never holds a tab or a newline.
# Values reach awk through ENVIRON, never `-v`, which would read a backslash in them as an escape.

CLOUD_LEDGER_HEADER="$(printf 'built\trepo\tticket\tbranch\tmodel/effort\tbrief bytes\tcredit before\tstatus\tcredit after\toverlap\tlanded\tlanding exit\thead SHA\tPR')"
CLOUD_LOCK_WAIT=10        # seconds a second writer waits for the lock
CLOUD_LOCK_STALE_MIN=10   # minutes after which a held lock is named stale (never removed by a tool)

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

# cloud_ledger_init LEDGER — create the ledger (and its directory) with its header when absent; rc 1 on failure.
cloud_ledger_init() {
  local f="$1"
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")" || return 1
  printf '%s\n' "$CLOUD_LEDGER_HEADER" > "$f"
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
    NR > 1 && $2 == r && $3 == t { print; found = 1; exit } END { exit !found }' "$1"
}

# cloud_ledger_cell ROW N — print cell N (1-based) of a row.
cloud_ledger_cell() {
  awk -F'\t' -v n="$2" '{ print $n; exit }' <<< "$1"
}

# cloud_ledger_put LEDGER REPO TICKET ROW — replace the (REPO, TICKET) row with ROW, or append ROW. Call it
# holding the lock. rc 1 on a write failure.
cloud_ledger_put() {
  local f="$1" tmp
  tmp="$(mktemp "$(dirname "$f")/.ledger.XXXXXX")" || return 1
  CL_R="$2" CL_T="$3" CL_ROW="$4" awk -F'\t' '
    BEGIN { r = ENVIRON["CL_R"]; t = ENVIRON["CL_T"]; row = ENVIRON["CL_ROW"] }
    NR > 1 && $2 == r && $3 == t && !done { print row; done = 1; next }
    { print }
    END { if (!done) print row }' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$f" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

# cloud_ledger_set LEDGER REPO TICKET N=VALUE... — set cells of the (REPO, TICKET) row in place. Call it holding
# the lock. rc 1 when there is no such row or the write fails.
cloud_ledger_set() {
  local f="$1" r="$2" t="$3" row a n v
  shift 3
  row="$(cloud_ledger_row "$f" "$r" "$t")" || return 1
  for a in "$@"; do
    n="${a%%=*}" v="${a#*=}"
    row="$(CL_N="$n" CL_V="$v" awk -F'\t' -v OFS='\t' '{ $(ENVIRON["CL_N"] + 0) = ENVIRON["CL_V"]; print }' <<< "$row")"
  done
  cloud_ledger_put "$f" "$r" "$t" "$row"
}

# cloud_personal_file — the personal-literals list both tools hand the scanner, fail-closed: exports
# SECRET_SCAN_PERSONAL_FILE (its value when set, else the scanner's default ~/.claude/secret-scan-personal) and
# rc 1 when that path is not a regular file — unless it is /dev/null, the scanner's deliberate opt-out.
cloud_personal_file() {
  SECRET_SCAN_PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-${HOME:-}/.claude/secret-scan-personal}"
  export SECRET_SCAN_PERSONAL_FILE
  [ "$SECRET_SCAN_PERSONAL_FILE" = /dev/null ] && return 0
  [ -f "$SECRET_SCAN_PERSONAL_FILE" ]
}

# cloud_gh_api ARGS... — `gh api ARGS`, its stdout on stdout. rc 0 ok · rc 4 GitHub answered 404 or 403 (the
# repository or ref is not readable) · rc 2 anything else (no network, not logged in, gh missing). stderr kept.
cloud_gh_api() {
  local out err rc=0
  err="$(mktemp)" || return 2
  out="$(gh api "$@" 2> "$err")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$err" >&2
    if grep -qE 'HTTP 40[34]' "$err"; then rm -f "$err"; return 4; fi
    rm -f "$err"
    return 2
  fi
  rm -f "$err"
  printf '%s\n' "$out"
}
