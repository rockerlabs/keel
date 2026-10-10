#!/usr/bin/env bash
# public-audit — is this repo safe to publish? Scan tracked content AND git history for personal /
# instance-specific leakage before a private->public flip. The audit you run once, on demand — NOT a
# per-commit hook (scanning full history every commit is the wrong altitude).
#
#   GAP  (fails, exit 1): a declared-private token, a personal literal from the local
#        secret-scan-personal file, or a commit/tag identity email that isn't public-safe —
#        high-confidence leaks that are painful to scrub after publishing.
#   WARN (advisory):      heuristic hits — absolute home paths, other emails in content, Cyrillic —
#        a human decides.
#
# Usage:
#   public-audit.sh [DIR]            audit DIR (default: .; DIR must be a git repository); reads
#                                    DIR/.public-audit if present
#   public-audit.sh --token ERE ...  add a private token to hunt (repeatable; CLI, not committed)
#   public-audit.sh --no-history ... tree only (skip the git-history + PR-ref scan)
#   public-audit.sh --config FILE    use a specific config file
#   public-audit.sh --quiet ...      print only GAP/WARN lines
#
# If the secret-guard's local personal file exists (~/.claude/secret-scan-personal, override with
# $SECRET_SCAN_PERSONAL_FILE — one ERE per line, never committed), its literals are hunted as
# case-insensitive private tokens in the tree, git history, and binary blobs: they are precisely
# what must not ship when a repo goes public. A SET $SECRET_SCAN_PERSONAL_FILE that is not a regular
# file is a GAP (dir #719; personal-literal coverage would be ZERO); /dev/null switches the personal
# half off on purpose.
#
# Env: KEEL_AUDIT_BLOB_MAX (bytes, default 10485760) — per-blob cap for the binary decode pass;
#      oversized blobs are skipped but SURFACED as un-audited.
#
# A git read or grep this audit could not complete is never read as "nothing found" (dir #738): it is a
# GAP `could not <step> (exit N) — the audit is INCOMPLETE`, the check it fed is skipped, the audit goes
# on, and the exit is 1. DIR must be a git repository: anything else exits 2. Needs git >= 2.28
# (`git diff --no-relative`); on an older git the changed-files step is a GAP, not a silent skip.
#
# Config (.public-audit) — ERE values, '#' comments:
#   token: <ERE>         a private string to flag in tree + history (an internal name, host, ...)
#   allow-email: <ERE>   an email/domain OK in history & content (added to the built-in noreply set)
#   allow-path: <glob>   a tracked path to skip in content scanning
#
# Note: a committed `.public-audit` literally contains its token strings. For a truly-secret token,
# pass it with --token (ephemeral) or keep the config gitignored, rather than committing it.
# Note: tokens are unanchored regexes — a short token also matches inside unrelated strings such as
# a commit hash. Prefer a specific token to avoid false positives.
set -uo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

QUIET=0
NO_HISTORY=0
CONFIG=""
DIR=""
cli_tokens=()
usage() {
  cat <<'EOF'
public-audit — is this repo safe to publish? Scan the tree AND git history (and host PR refs)
for personal / instance-specific leakage before a private->public flip.

Usage:
  public-audit.sh [DIR]            audit DIR (default: .; DIR must be a git repository); reads
                                   DIR/.public-audit if present
  public-audit.sh --token ERE ...  add a private token to hunt (repeatable; CLI, not committed)
  public-audit.sh --no-history     tree only (skip the git-history + PR-ref scan)
  public-audit.sh --config FILE    use a specific config file
  public-audit.sh --quiet          print only GAP/WARN lines
  public-audit.sh -h | --help

If ~/.claude/secret-scan-personal exists (override with $SECRET_SCAN_PERSONAL_FILE), its literals
are hunted as case-insensitive private tokens in the tree, git history, and binary blobs. A set
$SECRET_SCAN_PERSONAL_FILE that is not a regular file is a GAP; /dev/null switches the personal half off.

Env: KEEL_AUDIT_BLOB_MAX (bytes, default 10485760) caps the binary-blob decode pass;
     oversized blobs are skipped but surfaced as un-audited.
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet)      QUIET=1 ;;
    --no-history) NO_HISTORY=1 ;;
    --config)     shift; CONFIG="${1:?--config needs a FILE}" ;;
    --token)      shift; cli_tokens+=("${1:?--token needs an ERE}") ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "public-audit: unknown option '$1' (try --help)" >&2; exit 2 ;;
    *)            DIR="$1" ;;
  esac
  shift
done
DIR="${DIR:-.}"
[ -d "$DIR" ] || { echo "public-audit: not a directory: $DIR" >&2; exit 2; }
# dir #738 B13: every check below reads git, so a DIR that is not a git repository (or that git cannot read)
# is refused up front — it used to scan nothing and print "no publication blockers found". `rev-parse`, not a
# `.git` directory test: a linked worktree's `.git` is a file.
gd_rc=0
gd_err="$(git -C "$DIR" rev-parse --git-dir 2>&1 >/dev/null)" || gd_rc=$?
if [ "$gd_rc" -ne 0 ]; then
  echo "public-audit: $DIR is not a git repository (or git cannot read it) — this audit reads the tracked files and git history; run it on the repository" >&2
  [ -n "$gd_err" ] && echo "public-audit:   ${gd_err%%$'\n'*}" >&2
  exit 2
fi

# Built-in public-safe email patterns (ERE). Real personal/corporate emails are deliberately absent.
# dir #106: the set lives in tools/lib/safe-emails.sh — doctor.sh sources the same file for its
# advisory commit-email nudge, so the two can't silently re-diverge.
_pa_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # fail-open-ok: a failed cd makes the next `.` fail loudly
# shellcheck source=tools/lib/safe-emails.sh
. "$_pa_dir/lib/safe-emails.sh"
# EMAIL_RE / HOME_RE: the leaked-identifier content patterns, shared with self/doctor.sh's narrower
# GAP over FRAMEWORK.md/PRINCIPLES.md (dir #114) — same reuse reason as safe-emails.sh above.
# shellcheck source=tools/lib/leak-patterns.sh
. "$_pa_dir/lib/leak-patterns.sh"
# shellcheck source=tools/lib/nonneg-int.sh
. "$_pa_dir/lib/nonneg-int.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$_pa_dir/lib/impact-store.sh"
# shellcheck source=tools/lib/personal-literals.sh
. "$_pa_dir/lib/personal-literals.sh"
unset _pa_dir

# Temp refs from the host-PR-ref scan (section 6) must never outlive the run. Clean them on EXIT/INT/TERM
# so a Ctrl-C mid-fetch — or a run against a repo with no GitHub remote — leaves nothing behind, and any
# orphan a prior interrupted run left is reaped on the next run's exit.
cleanup_pr_refs() {
  git -C "$DIR" for-each-ref --format='%(refname)' 'refs/keel-pr-audit/*' 2>/dev/null \
    | while IFS= LC_ALL=C read -r r; do [ -n "$r" ] && git -C "$DIR" update-ref -d "$r" 2>/dev/null || true; done   # fail-open-ok: teardown — an orphan is reaped by the next run
}
# dir #738 B13: no usable temp dir means no spools, so no audit — refuse rather than run with an empty one.
audit_tmp="$(mktemp -d)" && [ -n "$audit_tmp" ] || { echo "public-audit: could not create a temp dir" >&2; exit 2; }
# absolute (dir #738 B3): GNU/busybox mktemp returns a relative path under a relative $TMPDIR, and
# `git -C "$DIR" grep -f "$audit_tmp/…"` would then open the wrong file.
case "$audit_tmp" in /*) ;; *) audit_tmp="$PWD/$audit_tmp" ;; esac
# dir #85 (code audit, finding 11): the INT/TERM handler must EXIT. Bash runs a trap handler for a
# caught signal and then RESUMES the script — so Ctrl-C used to tear down the fetched PR refs and the
# tmpdir and then keep auditing against the state it had just deleted, while the operator believed the
# run was cancelled. `exit 130` is the conventional 128+SIGINT status; the EXIT trap still fires after
# it (that is what actually performs cleanup), so the teardown is written once, not per-signal.
trap 'cleanup_pr_refs; rm -rf "$audit_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- reporting -----------------------------------------------------------------------------------
exit_code=0
say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

# --- the producer rule (dir #738 B14) ------------------------------------------------------------
# A git read or a grep whose output a check reads runs in the MAIN shell, spools its output under
# $audit_tmp and has its status checked: a non-zero status is a GAP `could not <step> (exit N) — the audit
# is INCOMPLETE`, and the check that read fed is skipped (no verdict from partial output). Status-blind
# forms — a process substitution, `2>/dev/null`, `|| true`, `| head` — are what let a corrupt index or a
# failing `git log` print "no publication blockers found"; tests/test_public_audit.sh holds the register.
personal_pat="$audit_tmp/personal.pat"
has_personal=0
decode_nonascii=""
pa_line=""
pa_hit=""
pa_u8=""
# pa_first FILE — pa_line = FILE's first line, or empty. No `| head`: a closed pipe would turn a match into
# a SIGPIPE status (dir #280).
pa_first() { pa_line=""; { IFS= LC_ALL=C read -r pa_line || [ -n "$pa_line" ]; } < "$1" || pa_line=""; }
# pa_fail STEP RC OUT CMD… — the GAP for a failed read, plus the first line of OUT.err beneath it. A step
# whose command reads the personal-literal file prints the GAP WITHOUT that line: git and busybox grep quote
# the offending pattern in their error, and this audit never echoes a literal.
pa_fail() {
  local step="$1" rc="$2" out="$3" a quiet=0
  shift 3
  gap "could not $step (exit $rc) — the audit is INCOMPLETE"
  for a in "$@"; do [ "$a" = "$personal_pat" ] && quiet=1; done
  if [ "$quiet" = 0 ]; then
    pa_first "$out.err"
    [ -n "$pa_line" ] && echo "         $pa_line"
  fi
  return 1
}
# pa_read STEP OUT CMD… — run CMD, stdout → OUT, stderr → OUT.err. A non-zero status is a GAP and returns 1.
pa_read() {
  local step="$1" out="$2" rc=0
  shift 2
  "$@" </dev/null > "$out" 2> "$out.err" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  pa_fail "$step" "$rc" "$out" "$@"
}
# pa_match STEP OUT CMD… — the same for a command whose exit 1 means "no match" (grep, git grep).
pa_match() {
  local step="$1" out="$2" rc=0
  shift 2
  "$@" </dev/null > "$out" 2> "$out.err" || rc=$?
  [ "$rc" -le 1 ] && return 0
  pa_fail "$step" "$rc" "$out" "$@"
}
# pa_c CMD… — CMD under LC_ALL=C, so a byte-class grep reads every byte (dir #740: BSD grep and busybox stop
# matching at an invalid byte under a UTF-8 locale). A function, so it can sit after pa_read/pa_match.
pa_c() { LC_ALL=C "$@"; }
# pa_sanitize FILE — pa_u8 = a copy of FILE with invalid UTF-8 dropped (the caller-locale passes read it, so a
# non-ASCII literal is still found after an invalid byte), or FILE itself where iconv is absent or fails. The
# four trailing newlines are load-bearing: a file ending in an incomplete sequence makes `iconv -c` stop.
pa_sanitize() {
  local f="$1" u8="$audit_tmp/u8"
  pa_u8="$f"
  command -v iconv >/dev/null 2>&1 || return 0
  { cat "$f"; printf '\n\n\n\n'; } | iconv -c -f UTF-8 -t UTF-8 > "$u8" 2>/dev/null && pa_u8="$u8"
  return 0
}
# pa_grep2 STEP USE_U FILE GREP-ARGS… — pa_hit = the first line of FILE that `grep GREP-ARGS -- FILE` selects,
# or empty; 1 when a grep itself failed. Pass C reads every byte under LC_ALL=C. Pass U (only when USE_U is
# non-empty) runs in the caller's locale over the sanitized copy, where a non-ASCII literal still folds and
# matches after an invalid byte; it runs only when pass C found nothing.
pa_grep2() {
  local step="$1" use_u="$2" f="$3"
  shift 3
  pa_hit=""
  pa_match "$step" "$audit_tmp/g2.c" pa_c grep "$@" -- "$f" || return 1
  pa_first "$audit_tmp/g2.c"; pa_hit="$pa_line"
  if [ -z "$pa_hit" ] && [ -n "$use_u" ]; then
    pa_sanitize "$f"
    pa_match "$step" "$audit_tmp/g2.u" grep "$@" -- "$pa_u8" || return 1
    pa_first "$audit_tmp/g2.u"; pa_hit="$pa_line"
  fi
  return 0
}
# pa_token_first STEP TOKEN FILE — pa_hit = the first line of FILE a declared token matches. A token is a user
# ERE and may be non-ASCII: its caller-locale pass runs when the token holds a non-ASCII byte. Case-sensitive.
pa_token_first() {
  local use_u=""
  case "$2" in *[![:ascii:]]*) use_u=1 ;; esac
  pa_grep2 "$1" "$use_u" "$3" -aE -e "$2"
}
# pa_personal_first STEP FLAGS FILE — pa_hit = the first line of FILE a personal literal matches (FLAGS is the
# grep flag cluster, e.g. -aoiE). Pass U runs when $decode_nonascii. The caller checks $has_personal first.
pa_personal_first() { pa_grep2 "$1" "$decode_nonascii" "$3" "$2" -f "$personal_pat"; }
# pa_report LEVEL STEP OUT TEXT CMD… — run CMD (exit 1 = no match); on a first output line, LEVEL "TEXT — e.g. LINE".
pa_report() {
  local level="$1" step="$2" out="$3" text="$4"
  shift 4
  pa_match "$step" "$out" "$@" || return 1
  pa_first "$out"
  [ -n "$pa_line" ] && "$level" "$text — e.g. $pa_line"
  return 0
}
# pa_report_email LEVEL STEP OUT TEXT FLAGS FILE — the two-stage email filter over a spool: EMAIL_RE, then the
# lines no safe pattern covers.
pa_report_email() {
  local level="$1" step="$2" out="$3" text="$4" flags="$5" f="$6"
  pa_match "$step" "$out.1" pa_c grep "$flags" -e "$EMAIL_RE" -- "$f" || return 1
  pa_report "$level" "$step" "$out.2" "$text" pa_c grep -vE -e "$safe_re" -- "$out.1"
}
# pa_check_ids FILE LABEL SUFFIX — a GAP for each identity in FILE that no safe pattern covers.
pa_check_ids() {
  local e id_rc
  while IFS= LC_ALL=C read -r e; do
    [ -z "$e" ] && continue
    # A here-string, not a `printf | grep -q` pipe: under `set -o pipefail`, printf as a live writer can be
    # SIGPIPE'd by grep's own early exit on match, flipping a real "safe" match into a false GAP (dir #280).
    id_rc=0
    LC_ALL=C grep -qE -e "$safe_re" <<< "$e" || id_rc=$?
    [ "$id_rc" -eq 0 ] && continue
    if [ "$id_rc" -ge 2 ]; then
      gap "could not match the identities in $2 (exit $id_rc) — the audit is INCOMPLETE"
      return 1
    fi
    gap "non-public-safe identity in $2: $e$3"
  done < "$1"
}
# pa_tree PATTERN — git grep -nIE over the tracked tree (caller's locale: git grep is not affected).
pa_tree() { git -C "$DIR" grep -nIE -e "$1" -- . "${excludes[@]}"; }
# pa_log_p ARGS… — `git log -p` for the content greps, NUL-stripped. --text/--no-textconv/--no-ext-diff: a
# `-diff` attribute or a textconv driver otherwise replaces the bytes (a literal behind one reads 0 hits).
# The NUL strip keeps `grep -I`-free greps reading a history that holds one NUL (a bash variable dropped it).
pa_log_p() { git -C "$DIR" log "$@" -p --text --no-textconv --no-ext-diff | LC_ALL=C tr -d '\000'; }
# pa_blob_list REV-LIST-ARGS… — "type|sha|size|path" for every object reachable from the revs.
pa_blob_list() {
  git -C "$DIR" rev-list --objects "$@" | git -C "$DIR" cat-file --batch-check='%(objecttype)|%(objectname)|%(objectsize)|%(rest)'
}
# pa_ids_merge COMMIT-IDS TAG-IDS — the de-duplicated, non-empty identities of both lists.
pa_ids_merge() {
  { LC_ALL=C cat "$1"; LC_ALL=C tr -d '<>' < "$2"; } | LC_ALL=C sed '/^$/d' | LC_ALL=C sort -u
}
# pa_uniq FILE — FILE's non-empty lines, de-duplicated.
pa_uniq() { LC_ALL=C sed '/^$/d' "$1" | LC_ALL=C sort -u; }

# --- gather config -------------------------------------------------------------------------------
tokens=()
[ "${#cli_tokens[@]}" -gt 0 ] && tokens+=("${cli_tokens[@]}")
allow_emails=()
allow_paths=()

cfg="${CONFIG:-$DIR/.public-audit}"
cfg_rc=0
if [ -f "$cfg" ]; then
  # The value's whitespace is trimmed with parameter expansions (no sed to fail unseen).
  while IFS= LC_ALL=C read -r line || [ -n "$line" ]; do
    val="${line#*:}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$line" in
      ''|\#*)         ;;
      token:*)        tokens+=("$val") ;;
      allow-email:*)  allow_emails+=("$val") ;;
      allow-path:*)   allow_paths+=("$val") ;;
    esac
  done < "$cfg" || cfg_rc=$?
fi

# Bad ERE? Detect by stderr AND exit code: a valid pattern on one input line exits 1 (no match) with no stderr;
# a broken one prints an error. The probe reads ONE input line (dir #738 B4): busybox grep compiles its pattern
# only when it reads input, so an empty probe never saw a broken ERE. The pattern is compiled in both locales
# the audit greps in — under LC_ALL=C (every byte) and in the caller's (the personal literals' second pass).
# Shared by the allow-email and personal-literal validation below — same idiom, only the case flag differs.
valid_ere() {
  local flag="$1" pat="$2" err rc
  rc=0; err="$(printf 'x\n' | LC_ALL=C grep "$flag" -e "$pat" 2>&1 >/dev/null)" || rc=$?
  [ -z "$err" ] && [ "$rc" -le 1 ] || return 1
  rc=0; err="$(printf 'x\n' | grep "$flag" -e "$pat" 2>&1 >/dev/null)" || rc=$?
  [ -z "$err" ] && [ "$rc" -le 1 ] || return 1
  return 0
}

# Personal literals from the secret-guard's local file double as private tokens for this audit —
# they are precisely what must not ship when a repo goes public. Case-INSENSITIVE (unlike tokens).
# Invalid lines are counted and reported as a GAP, not just a WARN (without echoing them — the file's
# whole point is that its content stays off any pasteable output): unlike a bad allow-email entry
# (which fails open safely — worst case one extra false WARN), a bad personal-literal line means that
# literal goes completely unscanned, which is a detection-accuracy failure this audit's own GAP bar
# ("high-confidence leaks... painful to scrub after publishing") exists to catch, not just advise on.
# dir #738 B3: the accepted lines are written ONE PER LINE to $personal_pat and every personal grep reads
# `-f` — each line is its own pattern, so two literals never fuse into one ERE that matches neither. No
# file is written when nothing was accepted (`grep -f <empty file>` disagrees across platforms), and a blank
# line never reaches it (the parser drops them; a blank pattern would match every line).
PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-$HOME/.claude/secret-scan-personal}"
bad_personal=0
personal_wr_rc=0
# dir #148: the parse (read, CRLF, BOM, comments, whitespace) is tools/lib/personal-literals.sh's (capture
# rules in its header); only the per-line validation policy stays here. Its status is read at the GAP
# site below (dir #680): 3 = a line ends in a backslash (withheld by the parser; the other literals are
# still scanned), anything else non-zero = the file could not be read or parsed (coverage is ZERO).
personal_rc=0
personal_lines="$(personal_literals_parse "$PERSONAL_FILE")" || personal_rc=$?
while IFS= LC_ALL=C read -r line; do
  [ -n "$line" ] || continue   # an empty capture still yields one empty line
  if valid_ere -iE "$line"; then
    printf '%s\n' "$line" >> "$personal_pat" || personal_wr_rc=$?
    has_personal=1
    case "$line" in *[![:ascii:]]*) decode_nonascii=1 ;; esac
  else
    bad_personal=$((bad_personal + 1))
  fi
done <<EOF_PERSONAL
$personal_lines
EOF_PERSONAL
# dir #746 (B7): the non-ASCII needle flag — set above for a personal literal, here for a token (an ASCII one
# already survives decode_binary's NUL-strip pass). It gates pass U.
if [ "${#tokens[@]}" -gt 0 ]; then
  for t in "${tokens[@]}"; do
    case "$t" in *[![:ascii:]]*) decode_nonascii=1 ;; esac
  done
fi
# A pattern file that could not be written is no coverage at all: report it, and run no personal grep.
[ "$personal_wr_rc" -ne 0 ] && has_personal=0

# combined safe-email regex (built-ins + configured allow-email). Seed from the lib's own pre-joined
# safe_email_re instead of re-deriving the SAFE_EMAILS join here too — dir #106 shared the pattern
# LIST; re-deriving the joiner would leave that half still duplicated by eyeball.
safe_re="$safe_email_re"
# A configured allow-email is user input — a broken ERE would make every later `grep -E "$safe_re"`
# spew "bad regex" and silently drop the content-leak WARNs. Validate each before trusting it; collect
# the bad ones to report once the WARN helper is defined below.
bad_allow_emails=()
if [ "${#allow_emails[@]}" -gt 0 ]; then
  for e in "${allow_emails[@]}"; do
    [ -n "$e" ] || continue
    if valid_ere -E "$e"; then
      safe_re="${safe_re:+$safe_re|}$e"
    else
      bad_allow_emails+=("$e")
    fi
  done
fi

# pathspec exclusions for content scans (the config file always; plus any allow-path globs)
excludes=( ":(exclude).public-audit" )
if [ "${#allow_paths[@]}" -gt 0 ]; then
  for g in "${allow_paths[@]}"; do [ -n "$g" ] && excludes+=( ":(exclude)$g" ); done
fi

# Decode ONE file's bytes (a committed blob written to a scratch path, or a working-tree file read
# directly) into concatenated ASCII/UTF-16/UTF-32/raw-printable views, for the regex scans that can't
# see into binary content directly. Shared by scan_binary_blobs (history + dir #509's working-tree
# pass) so there is exactly one place implementing this recipe inside this file — keep it IN SYNC with
# secret-guard/secret-scan.sh's own emit_blob() (each tool stands alone, so an encoding gap fixed there
# must be fixed here too).
#
# The whole joined stream is NUL-stripped once, after every pass (dir #250, mirrored from
# secret-scan.sh's emit_blob() — see its comment for the full mechanism): decoding UTF-32 data
# through the UTF-16LE/BE converters interleaves a NUL after every code unit's high byte, and a NUL
# ANYWHERE in the file makes BSD grep silently miss a non-ASCII `-i` pattern on EVERY line under a
# real UTF-8 locale (`LC_ALL=C` is unaffected) — reproduced live. Stripping once, on the join, is
# locale-neutral, keeps `-i` folding non-ASCII literals under UTF-8, and covers any pass added here
# later for free.
decode_binary() {  # $1 = source file, $2 = destination file for the decoded views
  local src="$1" dst="$2"
  {
    LC_ALL=C tr -d '\000' < "$src"; echo                        # ASCII-range UTF-16/UTF-32, no deps
    if command -v iconv >/dev/null 2>&1; then                   # non-ASCII UTF-16/UTF-32 (e.g. a Cyrillic name)
      iconv -f UTF-16LE -t UTF-8 "$src" 2>/dev/null || true; echo
      iconv -f UTF-16BE -t UTF-8 "$src" 2>/dev/null || true; echo
      iconv -f UTF-32LE -t UTF-8 "$src" 2>/dev/null || true; echo
      iconv -f UTF-32BE -t UTF-8 "$src" 2>/dev/null || true; echo
    fi
    LC_ALL=C tr -c '[:print:]\t\n' '\n' < "$src"; echo          # raw printable runs
  } | LC_ALL=C tr -d '\000' > "$dst"
}

# --- binary-blob decode scan (shared by sections 5b and 6) ----------------------------------------
# The text passes cannot see INSIDE a binary: tree_grep's -I skips binary files, and `git log -p`
# renders a binary change as "Binary files … differ" — so personal data encoded in a binary blob (the
# felt leak class: a real name UTF-16-encoded inside a fixture) passes every text check above. This
# decodes each binary blob reachable from the given revs (NUL-strip + iconv UTF-16/UTF-32 LE/BE when
# available + raw-printable) and re-runs the same regex set: declared tokens + personal literals =
# GAP, heuristics = WARN — one example per category per pass, like the text sections. KEEL_AUDIT_BLOB_MAX (bytes, default 10MB)
# bounds the per-blob cost; oversized blobs are counted and SURFACED, never silently trusted.
scan_binary_blobs() {  # $1 = label for messages; the rest = rev-list args (e.g. --all)
  local label="$1"; shift
  # Sanitized (dir #196 — see tools/lib/nonneg-int.sh): a non-numeric OR overflowing override falls
  # back to 10485760 rather than crashing the later `-gt` size comparison.
  local max; max="$(sanitize_nonneg_int "${KEEL_AUDIT_BLOB_MAX:-10485760}" 10485760)"   # fail-open-ok: pure shell
  local tmp="$audit_tmp/blob" dec="$audit_tmp/blob.dec" list="$audit_tmp/blob.list"
  local otype osha osize opath t skipped=0 reported_toks="" reported_personal=""
  local hit_home="" hit_email="" hit_cyr="" shown
  # The blob listing is spooled and its status checked (dir #738): a failing rev-list/cat-file pair used to
  # end the loop as if there were no blobs.
  pa_read "list the blobs of $label" "$list" pa_blob_list "$@" || return 0
  # LC_ALL=C (dir #719 B13): under bash >= 5 + UTF-8 a committed name ending in an invalid byte makes `read`
  # drop the NEXT record, so a blob after it would never be decoded.
  while IFS='|' LC_ALL=C read -r otype osha osize opath; do
    [ "$otype" = "blob" ] && [ -n "$osha" ] || continue
    if [ "${osize:-0}" -gt "$max" ]; then skipped=$((skipped + 1)); continue; fi
    shown="${opath:-$osha}"
    if ! pa_read "read blob ${osha:0:7} of $label" "$tmp" git -C "$DIR" cat-file blob "$osha"; then continue; fi
    # binary = contains a NUL byte; text blobs are already covered by the text passes
    LC_ALL=C tr -d '\000' < "$tmp" | cmp -s - "$tmp" && continue
    decode_binary "$tmp" "$dec" || { gap "could not decode '$shown' in $label (exit $?) — the audit is INCOMPLETE"; continue; }
    if [ "${#tokens[@]}" -gt 0 ]; then
      for t in "${tokens[@]}"; do
        [ -z "$t" ] && continue
        case "$reported_toks" in *"|$t|"*) continue ;; esac       # one GAP per token per pass
        if pa_token_first "match /$t/ in $shown" "$t" "$dec" && [ -n "$pa_hit" ]; then
          gap "private token /$t/ in a binary blob in $label — $shown"
          reported_toks="$reported_toks|$t|"
        fi
      done
    fi
    if [ "$has_personal" = 1 ] && [ -z "$reported_personal" ]; then
      if pa_personal_first "match the personal literals in $shown" -aoiE "$dec" && [ -n "$pa_hit" ]; then
        gap "personal literal (secret-scan-personal) in a binary blob in $label — $shown: $pa_hit"
        reported_personal=1
      fi
    fi
    if [ -z "$hit_home" ]; then
      pa_match "match home paths in $shown" "$audit_tmp/b.home" pa_c grep -aoE -e "$HOME_RE" -- "$dec" \
        && { pa_first "$audit_tmp/b.home"; [ -n "$pa_line" ] && hit_home="$pa_line ($shown)"; }
    fi
    if [ -z "$hit_email" ]; then
      pa_match "match emails in $shown" "$audit_tmp/b.em1" pa_c grep -aoE -e "$EMAIL_RE" -- "$dec" \
        && pa_match "match emails in $shown" "$audit_tmp/b.em2" pa_c grep -vE -e "$safe_re" -- "$audit_tmp/b.em1" \
        && { pa_first "$audit_tmp/b.em2"; [ -n "$pa_line" ] && hit_email="$pa_line ($shown)"; }
    fi
    if [ -z "$hit_cyr" ]; then
      # Require ≥4 CONSECUTIVE Cyrillic chars, unlike the single-pair text heuristic: the NUL-strip
      # and raw-printable views of compressed data (a gif, a zip) match an isolated
      # [\xd0-\xd3][\x80-\xbf] pair by chance hundreds of times per MB — a real name is a run.
      pa_match "match Cyrillic in $shown" "$audit_tmp/b.cyr" pa_c grep -acE -e "(${cyr_pat}){4}" -- "$dec" \
        && { pa_first "$audit_tmp/b.cyr"; [ "${pa_line:-0}" -gt 0 ] && hit_cyr="$shown"; }
    fi
  done < "$list"
  [ -n "$hit_home" ]  && warn "absolute home path in a binary blob in $label — e.g. $hit_home"
  [ -n "$hit_email" ] && warn "email in a binary blob in $label — e.g. $hit_email"
  [ -n "$hit_cyr" ]   && warn "Cyrillic text in a binary blob in $label — e.g. $hit_cyr"
  [ "$skipped" -gt 0 ] && warn "$skipped binary blob(s) over KEEL_AUDIT_BLOB_MAX (${max}B) skipped in $label — UN-audited; raise the cap to cover them"
  return 0
}

say "● public-audit ($DIR)"

# annotated-tag message bodies, captured once for sections 2, 4 and 5 — a tag's message is neither a
# commit message nor a diff, so `git log` (any format) never shows it. Populated up here (moved off
# section 4, dir #509 F7) so the declared-token loop in section 2 can check it too.
tag_msgs="$audit_tmp/tag_msgs"
tag_ok=0
if [ "$NO_HISTORY" = 0 ]; then
  pa_read "read the annotated-tag messages" "$tag_msgs" git -C "$DIR" for-each-ref --format='%(contents)' refs/tags && tag_ok=1
fi

[ "$cfg_rc" -ne 0 ] && gap "could not parse $cfg (exit $cfg_rc) — the audit is INCOMPLETE"
for e in "${bad_allow_emails[@]:-}"; do
  [ -n "$e" ] && warn "ignoring invalid allow-email regex in .public-audit: $e"
done
# dir #719 B14 (dir #725's predicate): the parser reads a missing/non-regular file as "no literals", so a SET
# override naming one (a typo, a cwd change) would print "no publication blockers found" with ZERO personal
# coverage. Unset/empty keeps the default; /dev/null is the deliberate opt-out; a dangling symlink is left to
# the parser's own, more specific "could not be read or parsed" GAP below (one GAP, not two).
if [ -n "${SECRET_SCAN_PERSONAL_FILE:-}" ] && [ "$PERSONAL_FILE" != /dev/null ] && [ ! -f "$PERSONAL_FILE" ] \
   && ! { [ -L "$PERSONAL_FILE" ] && [ ! -e "$PERSONAL_FILE" ]; }; then
  gap "SECRET_SCAN_PERSONAL_FILE is set to $PERSONAL_FILE, which is not a regular file — personal-literal coverage is ZERO; fix the path, unset it to use the default, or set it to /dev/null to switch it off on purpose"
fi
case "$personal_rc" in
  0) ;;
  3) gap "one or more lines in $PERSONAL_FILE end in a backslash and were ignored — personal-literal coverage is INCOMPLETE, fix the file and re-run" ;;
  *) gap "$PERSONAL_FILE could not be read or parsed (unreadable, a symlink to nothing, or a line sed could not process) — personal-literal coverage is ZERO or INCOMPLETE, fix it and re-run" ;;
esac
[ "$bad_personal" -gt 0 ] && gap "$bad_personal invalid regex line(s) in $PERSONAL_FILE ignored — personal-literal coverage is INCOMPLETE, fix the file and re-run"
[ "$personal_wr_rc" -ne 0 ] && gap "could not write the personal literals (exit $personal_wr_rc) — the audit is INCOMPLETE"
[ "$has_personal" = 1 ] && say "       (hunting the local secret-scan-personal literals as private tokens)"

# --- 1. identities in git history (GAP) ----------------------------------------------------------
if [ "$NO_HISTORY" = 0 ]; then
  # A shallow clone only carries part of history, so every scan below sees an incomplete picture and a
  # clean result is not trustworthy. Warn loudly (visible even under --quiet, via the WARN stream).
  pa_read "check whether the clone is shallow" "$audit_tmp/shallow" git -C "$DIR" rev-parse --is-shallow-repository \
    && { pa_first "$audit_tmp/shallow"; [ "$pa_line" = "true" ] && warn "shallow clone — git-history scans are INCOMPLETE; run 'git fetch --unshallow' before trusting a clean result"; }
  ids_ok=1
  pa_read "read the commit identities" "$audit_tmp/ids.c" git -C "$DIR" log --all --format='%ae%n%ce' || ids_ok=0
  pa_read "read the tag identities" "$audit_tmp/ids.t" git -C "$DIR" for-each-ref --format='%(taggeremail)' refs/tags || ids_ok=0
  if [ "$ids_ok" = 1 ] && pa_read "sort the identities" "$audit_tmp/ids" pa_ids_merge "$audit_tmp/ids.c" "$audit_tmp/ids.t"; then
    pa_check_ids "$audit_tmp/ids" "git history" ""
  fi
fi

# --- 2. declared-private tokens, in tree AND history (GAP) ---------------------------------------
# The block also runs for personal literals alone (dir #719 B12): a binary holding one used to read clean.
# Each token loop keeps its own non-empty test — bash 3.2 under `set -u` aborts on "${tokens[@]}" when empty.
if [ "${#tokens[@]}" -gt 0 ] || [ "$has_personal" = 1 ]; then
  # F6 (dir #509): tree_grep's `git grep -I` skips binary files entirely, so a token only present in a
  # binary file's DECODED bytes is invisible to the loop below. Not gated on NO_HISTORY: this is a TREE
  # check, same altitude as tree_grep, not a history one. In default mode, scoped to files the history
  # pass (scan_binary_blobs --all, section 5b) does NOT already reach — staged, unstaged-modified, or
  # untracked — since an unmodified tracked file's current bytes are exactly its HEAD blob, which --all
  # already walks; re-decoding it here would just repeat that work. In --no-history mode there is no
  # history pass to lean on, so the scope widens to every tracked file (matching tree_grep's own,
  # unscoped, text-check coverage) — narrowing it to "dirty" files there would leave a long-committed,
  # untouched binary's token invisible under --no-history the way a text token never is.
  wt_bin_reported=""
  wt_personal_reported=""
  wt_bin_skipped=0
  # Same cap as scan_binary_blobs (dir #196: sanitized against a non-numeric/overflowing override) —
  # an oversized file must be skipped-and-surfaced here too, not scanned unconditionally, or the
  # working-tree pass silently defeats the cap the history pass already enforces.
  wt_max="$(sanitize_nonneg_int "${KEEL_AUDIT_BLOB_MAX:-10485760}" 10485760)"   # fail-open-ok: pure shell
  # The file lists are three spools (dir #738 B14), read in turn: the tracked files (--no-history, and a
  # repository with no commit yet, where there is no history pass to lean on), the files changed against
  # HEAD (default mode), and the untracked ones. `git diff` prints paths relative to the repo ROOT even under
  # `-C "$DIR"` — `--no-relative` pins that against a user's diff.relative=true — while `ls-files` prints
  # paths relative to `$DIR` itself, so ONLY the diff spool has `$DIR`'s root-prefix stripped (empty at the
  # repo root). An unborn HEAD (`git diff … HEAD` exits 128) is not a failure.
  wt_spool_files=()
  wt_spool_kinds=()
  wt_prefix=""
  if [ "$NO_HISTORY" = 1 ]; then
    pa_read "list the tracked files" "$audit_tmp/wt.tracked" git -C "$DIR" ls-files -z -- . "${excludes[@]}" \
      && { wt_spool_files+=("$audit_tmp/wt.tracked"); wt_spool_kinds+=(tracked); }
  elif git -C "$DIR" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    pa_read "find the audited directory's prefix" "$audit_tmp/wt.prefix" git -C "$DIR" rev-parse --show-prefix \
      && { pa_first "$audit_tmp/wt.prefix"; wt_prefix="$pa_line"; } \
      && pa_read "list the changed files" "$audit_tmp/wt.diff" git -C "$DIR" diff --no-relative --name-only -z --diff-filter=ACMR HEAD -- . "${excludes[@]}" \
      && { wt_spool_files+=("$audit_tmp/wt.diff"); wt_spool_kinds+=(diff); }
  else
    pa_read "list the tracked files" "$audit_tmp/wt.tracked" git -C "$DIR" ls-files -z -- . "${excludes[@]}" \
      && { wt_spool_files+=("$audit_tmp/wt.tracked"); wt_spool_kinds+=(index); }
  fi
  pa_read "list the untracked files" "$audit_tmp/wt.untracked" git -C "$DIR" ls-files --others --exclude-standard -z -- . "${excludes[@]}" \
    && { wt_spool_files+=("$audit_tmp/wt.untracked"); wt_spool_kinds+=(untracked); }
  wt_i=0
  while [ "$wt_i" -lt "${#wt_spool_files[@]}" ]; do
    wt_file="${wt_spool_files[$wt_i]}"
    wt_kind="${wt_spool_kinds[$wt_i]}"
    wt_i=$((wt_i + 1))
    # LC_ALL=C on the NUL read (dir #719 B13): see scan_binary_blobs' read.
    while IFS= LC_ALL=C read -r -d '' f; do
      [ "$wt_kind" = diff ] && f="${f#"$wt_prefix"}"
      [ -L "$DIR/$f" ] && continue          # a symlink's tracked content is its link-text, not its target
      if [ ! -e "$DIR/$f" ]; then
        # A tracked file removed from the working tree but not from HEAD: git grep and this pass both skip it,
        # while HEAD — what would be published — still holds it. Default mode reads HEAD in the history pass.
        [ "$wt_kind" = tracked ] && gap "tracked file '$f' is missing from the working tree — its committed content was not audited (restore it or commit the removal)"
        continue
      fi
      [ -f "$DIR/$f" ] || continue          # a directory (a submodule's gitlink), a fifo…
      fsize="$(wc -c 2>/dev/null < "$DIR/$f")" || { gap "could not read '$f' in the working tree (exit $?) — the audit is INCOMPLETE"; continue; }
      fsize="${fsize//[[:space:]]/}"
      if [ "${fsize:-0}" -gt "$wt_max" ]; then wt_bin_skipped=$((wt_bin_skipped + 1)); continue; fi
      LC_ALL=C tr -d '\000' < "$DIR/$f" 2>/dev/null | cmp -s - "$DIR/$f" 2>/dev/null && continue
      decode_binary "$DIR/$f" "$audit_tmp/wt.dec" || { gap "could not decode '$f' in the working tree (exit $?) — the audit is INCOMPLETE"; continue; }
      if [ "${#tokens[@]}" -gt 0 ]; then
        for t in "${tokens[@]}"; do
          [ -z "$t" ] && continue
          case "$wt_bin_reported" in *"|$t|"*) continue ;; esac
          if pa_token_first "match /$t/ in $f" "$t" "$audit_tmp/wt.dec" && [ -n "$pa_hit" ]; then
            gap "private token /$t/ in a binary file in the working tree — $f"
            wt_bin_reported="$wt_bin_reported|$t|"
          fi
        done
      fi
      if [ "$has_personal" = 1 ] && [ -z "$wt_personal_reported" ]; then
        if pa_personal_first "match the personal literals in $f" -aoiE "$audit_tmp/wt.dec" && [ -n "$pa_hit" ]; then
          gap "personal literal (secret-scan-personal) in a binary file in the working tree — $f: $pa_hit"
          wt_personal_reported=1
        fi
      fi
    done < "$wt_file"
  done
  [ "$wt_bin_skipped" -gt 0 ] && warn "$wt_bin_skipped binary file(s) over KEEL_AUDIT_BLOB_MAX (${wt_max}B) skipped in the working tree — UN-audited; raise the cap to cover them"

  if [ "${#tokens[@]}" -gt 0 ]; then
    for t in "${tokens[@]}"; do
      [ -z "$t" ] && continue
      pa_report gap "search the tracked tree for /$t/" "$audit_tmp/tok.tree" "private token /$t/ in tracked tree" pa_tree "$t"
      if [ "$NO_HISTORY" = 0 ]; then
        c=""; m=""
        pa_read "search the history for /$t/" "$audit_tmp/tok.g" git -C "$DIR" log --all --oneline --text --no-textconv --no-ext-diff -G"$t" \
          && { pa_first "$audit_tmp/tok.g"; c="$pa_line"; }
        pa_read "search the history for /$t/" "$audit_tmp/tok.m" git -C "$DIR" log --all --oneline --grep="$t" -E \
          && { pa_first "$audit_tmp/tok.m"; m="$pa_line"; }
        [ -n "$c$m" ] && gap "private token /$t/ in git history — e.g. ${c:-$m}"
        # F7 (dir #509): an annotated-tag message body is neither a commit message nor a diff, so the
        # -G/--grep pair above never sees it; the tag-message spool was captured for this purpose.
        if [ "$tag_ok" = 1 ] && pa_token_first "match /$t/ in the tag messages" "$t" "$tag_msgs" && [ -n "$pa_hit" ]; then
          gap "private token /$t/ in an annotated-tag message — e.g. $pa_hit"
        fi
      fi
    done
  fi
fi

# --- 2b. personal literals (local secret-scan-personal), in tree text (GAP) ----------------------
if [ "$has_personal" = 1 ]; then
  pa_report gap "search the tracked tree for the personal literals" "$audit_tmp/per.tree" "personal literal (secret-scan-personal) in tracked tree" \
    git -C "$DIR" grep -inIE -f "$personal_pat" -- . "${excludes[@]}"
fi

# --- 3. heuristic content scans (WARN) -----------------------------------------------------------
pa_report warn "search the tracked tree for home paths" "$audit_tmp/s3.home" "absolute home path in tracked tree" pa_tree "$HOME_RE"

pa_match "search the tracked tree for emails" "$audit_tmp/s3.em1" pa_tree "$EMAIL_RE" \
  && pa_report warn "match emails in the tracked tree" "$audit_tmp/s3.em2" "email in tracked content" pa_c grep -vE -e "$safe_re" -- "$audit_tmp/s3.em1"

# Cyrillic via UTF-8 lead bytes (0xD0-0xD3) + a continuation byte — portable across grep flavors,
# unlike `git grep -P '\x{0400}'` which isn't supported on every git build. `git grep` under LC_ALL=C reads
# the bytes; an `xargs grep` pipeline maps grep's "no match" to 123, so its status could not be read.
cyr_pat=$'[\xd0-\xd3][\x80-\xbf]'
pa_report warn "search the tracked tree for Cyrillic" "$audit_tmp/s3.cyr" "Cyrillic text in tracked file" \
  pa_c git -C "$DIR" grep -lI -e "$cyr_pat" -- . "${excludes[@]}"

# --- 4. agent tooling / session metadata (WARN) --------------------------------------------------
# The per-session trailers a coding agent appends to commits (and the same shape in tracked files).
# We hit this leak class ourselves and the audit missed it — so surface it on purpose.
# Mirrored by secret-guard/secret-scan.sh SESSION_META (the preventive pre-push block) — keep in sync.
session_re='([A-Za-z][A-Za-z0-9-]*-Session:|claude\.ai/code/session)'
pa_report warn "search the tracked tree for session metadata" "$audit_tmp/s4.tree" "agent/session metadata in tracked tree" pa_tree "$session_re"
if [ "$NO_HISTORY" = 0 ]; then
  sess_msg=""
  pa_read "read the commit messages" "$audit_tmp/msgs" git -C "$DIR" log --all --format='%B' \
    && pa_match "match session metadata in the commit messages" "$audit_tmp/s4.msg" pa_c grep -aE -e "$session_re" -- "$audit_tmp/msgs" \
    && { pa_first "$audit_tmp/s4.msg"; sess_msg="$pa_line"; }
  if [ -z "$sess_msg" ] && [ "$tag_ok" = 1 ]; then
    pa_match "match session metadata in the tag messages" "$audit_tmp/s4.tag" pa_c grep -aE -e "$session_re" -- "$tag_msgs" \
      && { pa_first "$audit_tmp/s4.tag"; sess_msg="$pa_line"; }
  fi
  [ -n "$sess_msg" ] && warn "agent/session metadata in a commit or tag message — e.g. $sess_msg"
fi

# --- 5. history content heuristics (WARN) --------------------------------------------------------
# Section 3 scans the working tree only — so personal data in a commit-message body or a historical
# diff (an added-then-removed blob) would pass clean. Scan history content (messages + diffs in one
# `git log -p` pass) with the SAME regexes; reuse EMAIL_RE/HOME_RE/safe_re/cyr_pat. WARN, not GAP.
# The spool is NUL-stripped and every grep over it takes -a (never -I): one NUL in a text file would
# otherwise make `grep -I` skip the whole history.
hist="$audit_tmp/hist"
hist_ok=0
if [ "$NO_HISTORY" = 0 ]; then
  # message bodies + diffs, AND annotated-tag message bodies (which `git log -p` omits).
  if pa_read "read the history (log -p)" "$hist" pa_log_p --all; then
    hist_ok=1
    if [ "$tag_ok" = 1 ] && ! cat "$tag_msgs" >> "$hist"; then
      gap "could not append the annotated-tag messages to the history spool — the audit is INCOMPLETE"
      hist_ok=0
    fi
  fi
fi
if [ "$hist_ok" = 1 ]; then
  pa_report warn "match home paths in the history" "$audit_tmp/h.home" "absolute home path in git history" pa_c grep -anE -e "$HOME_RE" -- "$hist"
  pa_report_email warn "match emails in the history" "$audit_tmp/h.em" "email in git history content" -anE "$hist"
  pa_report warn "match Cyrillic in the history" "$audit_tmp/h.cyr" "Cyrillic text in git history" pa_c grep -an -e "$cyr_pat" -- "$hist"
fi

# --- 5a. personal literals (local secret-scan-personal), in git history text (GAP) ----------------
if [ "$hist_ok" = 1 ] && [ "$has_personal" = 1 ]; then
  if pa_personal_first "match the personal literals in the history" -aniE "$hist" && [ -n "$pa_hit" ]; then
    gap "personal literal (secret-scan-personal) in git history — e.g. $pa_hit"
  fi
fi

# --- 5b. binary blobs — the decoded scan of what sections 3/5 cannot see (tree + history) ---------
if [ "$NO_HISTORY" = 0 ]; then
  scan_binary_blobs "git history" --all
fi

# --- 6. host-side PR refs (GitHub refs/pull/*) ---------------------------------------------------
# These are served by the host but are NOT reachable from `git log --all`, so a leak in a closed PR's
# commits passes the local scan (a force-push of `main` does not purge them). When a remote is set
# (and not --no-history), fetch them and run the SAME checks: identity/token = GAP, heuristic = WARN.
# Offline / no PR refs / non-GitHub remote → a prominent NOTE (out of local scope — the only fix is
# delete-and-recreate; see docs/going-public.md). The network call is gated so the tool still runs offline.
if [ "$NO_HISTORY" = 0 ]; then
  # Probe EVERY remote, not just the first: `git remote | head -1` could pick a non-GitHub mirror that
  # sorts ahead of the real GitHub remote and silently skip the PR-ref scan. Scan each remote that
  # exposes refs/pull/*; emit the OUT-OF-SCOPE note only if a remote exists but none did.
  any_remote=0; scanned_pr=0
  if pa_read "list the remotes" "$audit_tmp/remotes" git -C "$DIR" remote; then
    while IFS= LC_ALL=C read -r remote; do
      [ -n "$remote" ] || continue
      any_remote=1
      # Capture the first ref, don't gate on the pipeline status: under `pipefail`, `… | grep -q .`
      # makes ls-remote die with SIGPIPE on a busy remote (1000+ refs/pull/*), and the 141 would skip
      # the whole PR-ref scan for that remote. The captured-non-empty test can't be flipped by SIGPIPE.
      [ -n "$(git -C "$DIR" ls-remote --quiet "$remote" 'refs/pull/*' 2>/dev/null </dev/null | head -n1)" ] || continue   # fail-open-ok: offline or no PR refs is the documented OUT OF SCOPE note below
      scanned_pr=1
      # Fetch both the PR tip (…/head) AND GitHub's synthetic merge (…/merge) — neither is reachable
      # from `git log --all`. Flat dest names keep them in one namespace for the scans below.
      if ! pa_read "fetch the host PR refs of $remote" "$audit_tmp/fetch.out" git -C "$DIR" fetch -q "$remote" 'refs/pull/*/head:refs/keel-pr-audit/head-*' 'refs/pull/*/merge:refs/keel-pr-audit/merge-*'; then
        cleanup_pr_refs
        continue
      fi
      if pa_read "read the identities of the host PR refs" "$audit_tmp/pr.ids.raw" git -C "$DIR" log --glob='refs/keel-pr-audit/*' --format='%ae%n%ce' \
         && pa_read "sort the identities of the host PR refs" "$audit_tmp/pr.ids" pa_uniq "$audit_tmp/pr.ids.raw"; then
        pa_check_ids "$audit_tmp/pr.ids" "a host PR ref (refs/pull/*)" " — purge via delete-and-recreate (going-public.md)"
      fi
      pr_hist="$audit_tmp/pr_hist"
      if pa_read "read the host PR refs (log -p)" "$pr_hist" pa_log_p --glob='refs/keel-pr-audit/*'; then
        if [ "${#tokens[@]}" -gt 0 ]; then
          for t in "${tokens[@]}"; do
            [ -z "$t" ] && continue
            # Capture-then-test, not `grep -qE … && gap`: with a token that matches EARLY in a large
            # pr_hist, `printf | grep -q` SIGPIPEs printf, and `pipefail` makes the pipeline 141 — so the
            # `&& gap` never fires and a real leak passes clean. The captured hit can't be lost to SIGPIPE.
            if pa_token_first "match /$t/ in the host PR refs" "$t" "$pr_hist" && [ -n "$pa_hit" ]; then
              gap "private token /$t/ in a host PR ref (refs/pull/*) — purge via delete-and-recreate"
            fi
          done
        fi
        if [ "$has_personal" = 1 ]; then
          if pa_personal_first "match the personal literals in the host PR refs" -aniE "$pr_hist" && [ -n "$pa_hit" ]; then
            gap "personal literal (secret-scan-personal) in a host PR ref (refs/pull/*) — e.g. $pa_hit — purge via delete-and-recreate"
          fi
        fi
        # Same heuristic set the local-history pass (sections 4-5) applies, over PR-ref content. WARN.
        pa_report_email warn "match emails in the host PR refs" "$audit_tmp/pr.em" "email in a host PR ref (refs/pull/*)" -anE "$pr_hist"
        pa_report warn "match home paths in the host PR refs" "$audit_tmp/pr.home" "absolute home path in a host PR ref (refs/pull/*)" pa_c grep -anE -e "$HOME_RE" -- "$pr_hist"
        pa_report warn "match Cyrillic in the host PR refs" "$audit_tmp/pr.cyr" "Cyrillic text in a host PR ref (refs/pull/*)" pa_c grep -an -e "$cyr_pat" -- "$pr_hist"
        pa_report warn "match session metadata in the host PR refs" "$audit_tmp/pr.sess" "agent/session metadata in a host PR ref (refs/pull/*)" pa_c grep -anE -e "$session_re" -- "$pr_hist"
      fi
      # Binary blobs a PR ref carries that local history does not. The exclusion must NOT be a bare
      # `--not --all`: --all includes the refs/keel-pr-audit/* temp refs themselves (fetched above), so
      # the include-set would be a subset of the exclude-set and the scan a silent no-op — --exclude
      # carves the temp namespace out of the --all that follows it. A leak in a closed PR's binary
      # fixture is exactly as recoverable as a text one.
      scan_binary_blobs "a host PR ref (refs/pull/*)" \
        --glob='refs/keel-pr-audit/*' --not --exclude='refs/keel-pr-audit/*' --all
      cleanup_pr_refs   # reap this remote's temp refs before the next iteration (also runs on EXIT)
    done < "$audit_tmp/remotes"
  fi
  if [ "$any_remote" = 1 ] && [ "$scanned_pr" = 0 ]; then
    say "       NOTE: host PR refs (refs/pull/*) are OUT OF SCOPE of this local scan (offline, none,"
    say "       or a non-GitHub remote). A repo with closed PRs must purge them via delete-and-recreate"
    say "       before going public — git log --all does NOT cover them. See docs/going-public.md."
  fi
fi

# --- verdict -------------------------------------------------------------------------------------
[ "$exit_code" = 0 ] && say "public-audit: no publication blockers found"

# Impact instrumentation (metadata only, opt-in per repo): a GAP is a real publication blocker caught —
# record the guardrail fire so keel-impact can auto-ingest it (deterministic, zero-token). Only on GAP
# (exit 1), never on a clean run or advisory WARNs. Resolved via tools/lib/impact-store.sh (dir #251):
# $KEEL_IMPACT_LOG, else the audited repo's external store entry, else a legacy in-tree marker; with
# none of those, nothing is written.
if [ "$exit_code" != 0 ]; then
  _klog="$(impact_log_path "$DIR")"   # fail-open-ok: impact-log metadata, written after the verdict
  if [ -n "$_klog" ]; then
    _kclaim="$(impact_claim_key "$DIR")"   # fail-open-ok: impact-log metadata, written after the verdict
    # dir #251 review: the resolver's legacy-marker fallback can name a path whose parent .keel/
    # doesn't physically exist yet (a fresh clone carrying the committed gitignore line but never
    # recreating the untracked dir) — without this, the append's own failed redirect leaks a raw error
    # and silently drops the event.
    mkdir -p "$(dirname "$_klog")" 2>/dev/null || true   # fail-open-ok: impact-log metadata, written after the verdict
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" guard public-audit blocked "$_kclaim" \
      >> "$_klog" 2>/dev/null || true   # fail-open-ok: impact-log metadata, written after the verdict
  fi
fi
exit "$exit_code"
