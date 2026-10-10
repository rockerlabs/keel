#!/usr/bin/env bash
# secret-scan — backstop scanner for key-shaped secrets and personal data.
#
# TWO detector classes:
#   1. key-SHAPED secrets — length-anchored patterns (a known prefix + a long body), case-SENSITIVE:
#      exactly what bots scrape repos for. Length anchoring means a bare prefix or this pattern list
#      itself never trips.
#   2. personal data — operator-specific literals (real name, device serials, personal drive labels,
#      personal emails) loaded as EREs, matched case-INSENSITIVELY, from a LOCAL file that is never
#      committed:
#        default path: ~/.claude/secret-scan-personal   (override with $SECRET_SCAN_PERSONAL_FILE)
#        one ERE per line; blank lines and `# comments` ignored; absent DEFAULT file → only class 1 runs.
#        A SET $SECRET_SCAN_PERSONAL_FILE that is not a regular file is exit 2 (dir #725); /dev/null is the
#        deliberate opt-out.
#      Put ONLY literals that must never appear in ANY repo. Do NOT list your bare home username —
#      it is a legitimate path component in a private knowledge base and would flag every home-path
#      reference. Starter: tools/secret-guard/secret-scan-personal.example
#
# Both classes are scanned over text AND over BINARY content: binary files/blobs are decoded via a
# NUL-strip pass (catches ASCII-range UTF-16/UTF-32 with no dependencies) plus iconv UTF-16 and UTF-32
# LE/BE when iconv is available (needed for non-ASCII literals, e.g. a Cyrillic name) plus a
# raw-printable pass — a real name inside a UTF-16/UTF-32 binary fixture is invisible to a plain-text grep.
# The decode resumes after an invalid unit (iconv -c; a slower built-in decoder where the host's iconv
# cannot, or where there is none). A UTF-16/UTF-32 payload that does not start on a unit boundary of the
# file is not decoded.
#
# It does NOT catch passwords, opaque/custom tokens, or base64 blobs: it is a backstop to .gitignore +
# env vars, NOT a complete DLP. Mark that boundary honestly (P1).
#
# Usage:
#   secret-scan.sh                 scan staged changes (added/modified), for a pre-commit hook
#   secret-scan.sh --staged        same as the default, spelled out (for callers outside the hook)
#   secret-scan.sh --range A..B    scan a commit range — introduced blobs, the commits' messages
#                                  (agent/session-metadata trailers), and annotated-tag message
#                                  bodies, for a pre-push hook
#   secret-scan.sh --tracked       detective audit: scan ALL tracked content (doctor / periodic review)
#   secret-scan.sh --selftest      verify the scanner catches what it claims (end-to-end child runs)
#   secret-scan.sh FILE...         scan specific files — a caller passing a file list it does not
#                                  fully control (e.g. tools/audit-packet/export.sh's caller-supplied
#                                  scope) should use `secret-scan.sh -- FILE...` instead: without the
#                                  `--`, a FIRST filename that happens to literally read "staged",
#                                  "--tracked", "--selftest", or start with "-" silently dispatches to
#                                  a DIFFERENT mode instead of being scanned (dir #495 code review).
#   secret-scan.sh -- FILE...      same as FILE... mode, but every argument after `--` is a literal
#                                  filename regardless of what it looks like — never re-dispatched
#
# SECRET_SCAN_LOCAL_PUSH=1 (env, --range only): set ONLY by the LOCAL pre-push hook (tools/secret-
#   guard/pre-push), NEVER by ci-scan.sh — tells the --range allowlist-baseline resolution it is safe
#   to also trust content already reachable via a remote-tracking ref (dir #518). Safe only pre-push,
#   where the range's own newly-introduced tip is not yet reachable from any local remote-tracking ref
#   by construction (interior commits brought in by a merge commonly already are — dir #569); unsafe
#   post-push (ci-scan.sh's own docstring explains why), so it must never be set there.
#

# Allowlist (for legit fixtures/example keys — be deliberate, real keys hide in tests too):
#   a repo-root .secret-scan-allow file:
#     <ERE>          drop any matched line from results
#     path:<glob>    exclude a path
#   or an inline  secret-scan:allow  comment on the offending line.
#
# Exit 0 = clean; 1 = a secret-shaped string or personal data found; 2 = usage/config error, or a read
# the scan could not complete (fails closed: `secret-scan: could not <step> … — refusing to report it clean`).

set -euo pipefail

# Length-anchored patterns: a bare prefix or this pattern list itself never trips them.
PATTERNS=(
  'gh[oprsu]_[A-Za-z0-9]{36}'           # GitHub token — PAT ghp_, OAuth gho_, user ghu_, server ghs_, refresh ghr_
  'github_pat_[A-Za-z0-9_]{60,}'        # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                    # AWS access key id
  'AIza[0-9A-Za-z_-]{35}'              # Google API key
  'sk-ant-[A-Za-z0-9_-]{20,}'          # Anthropic API key
  'sk-proj-[A-Za-z0-9_-]{20,}'         # OpenAI project key (the hyphen breaks the generic sk- rule)
  'sk-svcacct-[A-Za-z0-9_-]{20,}'      # OpenAI service-account key
  'sk-[A-Za-z0-9]{32,}'                # generic "sk-" secret key
  'sk_(live|test)_[A-Za-z0-9]{16,}'    # Stripe secret key (underscore form)
  'glpat-[A-Za-z0-9_-]{20,}'           # GitLab personal access token
  'npm_[A-Za-z0-9]{36}'                # npm access token
  'hf_[A-Za-z0-9]{34,}'                # Hugging Face user access token
  'xox[baprs]-[A-Za-z0-9-]{10,}'       # Slack token
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # PEM private key
  # age private key (dir #631): Bech32 with the HRP `AGE-SECRET-KEY-` (a post-quantum identity adds `PQ-`),
  # the separator `1`, then the Bech32 charset — 58 characters for an X25519 key. {58,} is a lower bound: the PQ
  # variant's length is not pinned here.
  'AGE-SECRET-KEY-(PQ-)?1[QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L]{58,}'
)

# Agent/session metadata in COMMIT and annotated-TAG MESSAGES — the per-session trailer an agent
# harness appends (a `Claude-Session` line with its session URL). Scanned by --range only: a
# message is not a blob, so no content pass above can see it, and the push is where it becomes
# effectively unpurgeable (a protected public history needs a rewrite). Mirrors public-audit.sh
# session_re — keep the two in sync (pinned by tests/test_secret_guard.sh, dir #681).
SESSION_META='([A-Za-z][A-Za-z0-9-]*-Session:|claude\.ai/code/session)'

ALLOW_FILE=".secret-scan-allow"
# set by the --staged dispatch arm to "HEAD" (dir #508 (a)); the same-change allowlist-provenance
# check below reads it as "which committed ref counts as pre-existing", empty = no check. A ref,
# not a bool, so a future --range fix can set its own baseline (the range's start commit, not
# HEAD) without a second flag or a second branch in the shared allowlist-parsing block below.
ALLOW_BASELINE_REF=""
# dir #518: --range's own baseline is not always ONE commit (unlike --staged's HEAD) — an ordinary
# `git merge origin/main` before push (ubiquitous workflow) makes `git rev-list --boundary` return
# TWO already-known ancestors (the old tip, and whatever the merge pulled in), not one, and both are
# equally legitimate "this existed before the push" evidence (max-review finding: an earlier design
# here required exactly one boundary commit and fell back to fail-closed on a plain merge, which
# would have false-blocked routine pushes on every pre-existing allowlist entry). ALLOW_BASELINE_REFS
# holds the full set to union; ALLOW_BASELINE_MODE="range" tells the shared compare block below to
# read that set instead of the scalar ALLOW_BASELINE_REF (which stays reserved for --staged) — a
# separate flag because an EMPTY set (no baseline resolves at all) must still mean "range mode, fail
# closed", not "no mode set, skip the check entirely" (--tracked/FILE mode's actual meaning).
ALLOW_BASELINE_REFS=()
ALLOW_BASELINE_MODE=""
PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-$HOME/.claude/secret-scan-personal}"

# All temp files live in one scratch dir, removed on ANY exit (set -e failures, Ctrl-C, TERM) —
# a hook that runs on every commit must not litter $TMPDIR with orphans.
#
# dir #682 — a COMPLETION MARKER on top of the `$?` capture, not a bare `rm -rf` trap: on bash 3.2 (macOS
# /bin/bash) a top-level FATAL shell error (a `.` of a missing file, a `set -u` unbound variable) leaves
# `$?` at 0 by the time the EXIT trap runs, so a bare trap turned that crash into exit 0 and the hook
# failed OPEN. `_scan_done` is set to 1 only on the legitimate exit-0 paths (the clean early return, the
# end of the scan, the end of selftest()); an exit that reaches the trap with status 0 and no marker is
# a crash and becomes 2 (this file's "cannot scan" status). An explicit non-zero `exit N` keeps its own.
# Every legitimate `exit 0` MUST set `_scan_done=1` first; one that forgets fails closed (the hook blocks).
_scan_done=""
_scan_exit() {
  _scan_rc=$?
  if [ -z "$_scan_done" ] && [ "$_scan_rc" -eq 0 ]; then
    _scan_rc=2
    echo "secret-scan: internal error — the scan did not complete; failing closed" >&2
  fi
  rm -rf "$SCRATCH"
  exit "$_scan_rc"
}
SCRATCH="$(mktemp -d)"
# absolute (dir #715): GNU/busybox mktemp returns a relative path under a relative $TMPDIR, and --staged
# changes to the top level before its later spools
case "$SCRATCH" in ''|/*) ;; *) SCRATCH="$PWD/$SCRATCH" ;; esac
trap _scan_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# _fail_closed STEP [STATUS [ERRFILE]] — dir #715: the one exit for a read the scan could not complete. A
# producer that failed, or a read that lost a record, must never look like a clean input ("nothing came
# back" read as "nothing found" — the class behind dir #508 (b), #693, #697, #680, #682, #280 and #715).
# ERRFILE lines get the `secret-scan:   ` prefix, never a bare two-space indent: kb-doctor and
# leak_gate_run read those as hit lines. Builtins only: a missing tool may be the very failure reported.
# Main shell only (an `exit` inside `$(…)` ends just that subshell): a function that runs inside one
# returns a status, and its caller hands it here — `cmd > "$spool" 2>"$err" || _fail_closed STEP $? "$err"`.
_fail_closed() {
  local l=""
  # a newline in STEP (it can embed a file name) is written as `\n`, so no continuation line can start with
  # two spaces
  printf 'secret-scan: could not %s%s — refusing to report it clean\n' "${1//$'\n'/\\n}" "${2:+ (exit $2)}" >&2
  if [ -n "${3:-}" ] && [ -r "$3" ]; then
    while LC_ALL=C IFS= read -r l || [ -n "$l" ]; do
      printf 'secret-scan:   %s\n' "$l" >&2
    done < "$3"
  fi
  exit 2
}
# a fresh spool file in $SCRATCH (removed with it on any exit)
spool() { mktemp "$SCRATCH/blob.XXXXXX"; }

# --- dir #148: the personal-literals parser, a small INLINE copy of tools/lib/personal-literals.sh --
# This file is VENDORED and may only source files vendored beside it, so it cannot source the shared
# lib; this twin's body is IDENTICAL to tools/lib/personal-literals.sh's personal_literals_parse, and
# tests/test_secret_guard.sh (the `dir #148` section) runs both on shared fixtures and asserts the two
# bodies are byte-identical — edit BOTH copies or that test goes red. Statuses: 0 ok; 2 the file exists
# but is unusable (unreadable, or a symlink to nothing); 3 a line ends in an odd run of backslashes
# (withheld); 4 the per-line sed failed; other non-zero: a read failure. The caller below captures it by
# a plain assignment and fails CLOSED on any non-zero (never `local x=$(…)`, never a process
# substitution — those hide the status).
_personal_literals_parse_inline() {
  [ -L "$1" ] && [ ! -e "$1" ] && return 2
  [ -f "$1" ] || return 0
  [ -r "$1" ] || return 2
  local _pl_t="" _pl_rc=0 _pl_run=""
  while IFS= read -r _pl_t || [ -n "$_pl_t" ]; do
    _pl_t="${_pl_t#$'\357\273\277'}"
    _pl_t="${_pl_t%$'\r'}"
    _pl_t="$(printf '%s' "$_pl_t" | sed 's/[[:space:]][[:space:]]*#.*$//; s/^[[:space:]][[:space:]]*//; s/[[:space:]][[:space:]]*$//')" || return 4
    case "$_pl_t" in
      ''|\#*) ;;
      *)
        _pl_run="${_pl_t##*[!\\]}"
        if [ $(( ${#_pl_run} % 2 )) -eq 1 ]; then
          _pl_rc=3
        else
          printf '%s\n' "$_pl_t"
        fi ;;
    esac
  done < "$1" || return $?
  return "$_pl_rc"
}

# Build a combined regex (class 1, case-sensitive).
joined=""
for p in "${PATTERNS[@]}"; do
  joined="${joined:+$joined|}$p"
done

# Class 2: operator literals from the local personal file (case-insensitive).
# dir #148: the parse is _personal_literals_parse_inline (defined above). Its status is acted on right
# here (dir #680): a personal file we cannot trust must fail CLOSED — silently scanning with fewer (or no)
# literals is the fail-open this gate must never have.
_personal_rc=0
# dir #725: the parser takes a path, so it cannot tell a path the operator SET from the built-in default —
# and to it a non-regular file means "no literals" (right for the default, which most machines lack, and
# for /dev/null, the explicit opt-out CI uses). A SET, non-empty variable naming anything else is a typo
# (or a path made wrong by a cwd change): scanning on would switch the personal half off without a word.
# Unset or empty keeps the default. A dangling symlink is left to the parser: it already exits 2 with its own,
# more specific message (a symlink to nothing, dir #680).
# (PERSONAL_FILE above equals the variable whenever it is set and non-empty.)
if [ -n "${SECRET_SCAN_PERSONAL_FILE:-}" ] && [ "$PERSONAL_FILE" != /dev/null ] && [ ! -f "$PERSONAL_FILE" ] \
   && ! { [ -L "$PERSONAL_FILE" ] && [ ! -e "$PERSONAL_FILE" ]; }; then
  echo "secret-scan: SECRET_SCAN_PERSONAL_FILE is set to $PERSONAL_FILE, which is not a regular file" >&2
  echo "(missing, a directory, ...) — personal-data detection would be silently disabled. Fix the path, unset the" >&2
  echo "variable to use the default, or set it to /dev/null to switch the personal half off on purpose." >&2
  exit 2
fi
_personal_lines="$(_personal_literals_parse_inline "$PERSONAL_FILE")" || _personal_rc=$?
case "$_personal_rc" in
  0) ;;
  3)
    echo "secret-scan: a line in $PERSONAL_FILE ends in a backslash — it would join the next line into a" >&2
    echo "pattern matching neither literal, silently disabling personal-data detection. Fix the file." >&2
    exit 2 ;;
  *)
    echo "secret-scan: cannot read or parse $PERSONAL_FILE (unreadable, a symlink to nothing, or a line" >&2
    echo "sed could not process) — personal-data detection would be silently disabled. Fix the file." >&2
    exit 2 ;;
esac
# dir #694 (spec 746 B3): one literal per line, none blank (the parser's contract), written to a pattern file
# that every personal grep reads with `-f` — one pattern per literal. Joined with `|` into one ERE, two lines
# fused: `zorb[` and `plugh]` became a valid pattern matching neither literal, and `(a)\1` + `(b)\1` matched
# only the first. A literal starting with `-` is a pattern too, never a grep option (S2-1). No literal → no
# file and no personal grep: `grep -f` over an empty file disagrees across BSD, GNU and busybox. The file
# lives in $SCRATCH (mktemp -d, mode 0700), which the EXIT trap removes on every exit.
# has_personal — at least one literal; personal_nonascii — one holds a non-ASCII byte, which skips --range's
# NUL-strip fast path and, through decode_nonascii (the name the recipe twin in public-audit.sh reads), turns on
# emit_blob's built-in decoder.
has_personal=""
personal_nonascii=""
personal_pat="$SCRATCH/personal.pat"
if [ -n "$_personal_lines" ]; then
  has_personal=1
  printf '%s\n' "$_personal_lines" > "$personal_pat" || _fail_closed "write the personal literals" $?
  case "$_personal_lines" in *[![:ascii:]]*) personal_nonascii=1 ;; esac
fi
decode_nonascii="$personal_nonascii"
# Fail CLOSED on a broken personal regex: a malformed ERE would make every personal grep exit 2,
# which reads as "no match" and would silently disable personal-data detection — a security gate
# must never fail open on its own config. grep exits >=2 only on a bad pattern; 1 (no match) is fine.
# The probe reads one input line (dir #694, B4): busybox grep compiles a pattern only when it reads input,
# so over empty input it passed every malformed ERE. It runs in both locales a personal grep runs in.
if [ -n "$has_personal" ]; then
  rc=0; printf 'x\n' | LC_ALL=C grep -iE -f "$personal_pat" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -lt 2 ]; then
    printf 'x\n' | grep -iE -f "$personal_pat" >/dev/null 2>&1 || rc=$?
  fi
  if [ "$rc" -ge 2 ]; then
    echo "secret-scan: invalid regex in $PERSONAL_FILE — personal-data detection would be" >&2
    echo "silently disabled. Fix the offending line (each line is an ERE)." >&2
    exit 2
  fi
fi

# --- gather the lines to scan as "path:line" records ---------------------------------------------------
records=""

# a file (or blob) is binary if it contains a NUL byte
is_binary_file() { ! LC_ALL=C tr -d '\000' < "$1" 2>/dev/null | cmp -s - "$1"; }

# match a text FILE against both classes; optional extra grep flag (e.g. -n) via $1, and an optional
# extra case-sensitive ERE OR'd into class 1 via $3 (e.g. $SESSION_META for messages, as count_matches).
# dir #715 (B7): a grep exit of 1 is "no match", >= 2 a failure (a bad pattern, an unreadable file, 127 = no
# grep at all) — the old `|| true` read every one of those as "no match". Each grep's status is captured
# on its own, and the group ends by exiting with a failing one: the group is a pipeline element, so a
# subshell (a variable set inside it never reaches this function), and `pipefail` carries its status —
# or a failed `sort` — out as this function's own. Callers spool the output and check that status.
# dir #740 (spec 746 B5): under a UTF-8 locale BSD and busybox grep stop matching a line at its first invalid
# byte, so a key after a stray Latin-1 byte read clean. Class 1 and the personal pass P-C therefore run under
# LC_ALL=C, which reads every byte; there P-C's `-i` folds ASCII only and its `.` is one byte, so every
# literal gets one more pass, P-U (pu_grep below), in the caller's locale — a non-ASCII literal for its case
# folding, an ASCII one whose `.` or bracket stands for a non-ASCII letter (`fran.ois`) for its characters.
# LC_ALL is never exported: each `LC_ALL=C` is a per-command prefix. A line holding an invalid byte may be
# reported twice (raw and sanitized).
match_text() {  # $1 = extra grep flags ('' for none), $2 = file to scan, $3 = extra ERE ('' for none)
  local flags="$1" f="$2" extra="${3:-}"
  {
    rc1=0; rc2=0; rc3=0
    # shellcheck disable=SC2086  # $flags intentionally word-split ('' → no extra flag)
    LC_ALL=C grep -aE $flags -e "${extra:+$extra|}$joined" "$f" 2>/dev/null || rc1=$?
    if [ -n "$has_personal" ]; then
      # shellcheck disable=SC2086
      LC_ALL=C grep -aiE $flags -f "$personal_pat" "$f" 2>/dev/null || rc2=$?
      pu_grep "$flags" "$f" || rc3=$?
    fi
    [ "$rc1" -le 1 ] || exit "$rc1"
    [ "$rc2" -le 1 ] || exit "$rc2"
    [ "$rc3" -le 1 ] || exit "$rc3"
  } | LC_ALL=C sort -u
}

# pu_grep FLAGS FILE — P-U (dir #740, B5 (c)): the personal grep in the caller's locale, over a copy of FILE
# with its invalid UTF-8 removed by `iconv -c` — padded with newlines first, so a file ending in an incomplete
# sequence still converts whole (unpadded, iconv exits 1 on macOS/glibc and truncates on musl); the padding
# adds lines after the last, so `-n` numbers hold. No iconv, or a sanitizer that fails → FILE itself (the
# pre-746 behaviour), never no pass. Returns grep's status. One copy at a time, overwritten in $SCRATCH:
# callers run one after another.
pu_grep() {
  local u8="$2"
  if command -v iconv >/dev/null 2>&1; then
    u8="$SCRATCH/u8"
    { cat "$2"; printf '\n\n\n\n'; } | iconv -c -f UTF-8 -t UTF-8 > "$u8" 2>/dev/null || u8="$2"
  fi
  # shellcheck disable=SC2086  # $1 intentionally word-split
  grep -aiE $1 -f "$personal_pat" "$u8" 2>/dev/null
}

# fast-path hit count for one spooled scan FILE — the shared shape of every --range pre-check (blob
# stream, commit messages, tag bodies). ONE case-sensitive grep over class 1 (key shapes, optionally
# OR'd with an extra ERE like $SESSION_META for messages); only if that is clean, ONE case-insensitive
# grep over class 2 (personal literals). `grep -c` (count), NEVER `-q`: -q exits on the first match and
# SIGPIPEs the still-writing producer, which under `pipefail` reads as failure and drops the hit — a
# real intermittent scanner hole (flaked on macOS CI). -c consumes the whole stream → deterministic.
# Prints the count on stdout. dir #715 (B7): grep's exit 1 is a zero count; >= 2 (127 = no grep) is
# returned, never read as zero — the caller captures the count into a variable and checks the status.
# dir #740 (B5): the same passes as match_text — class 1 and P-C under LC_ALL=C, then P-U (the caller's
# locale, the sanitized copy) only while the count is still zero.
count_matches() {  # $1 = file, $2 = extra case-sensitive ERE OR'd into class 1 ('' for none)
  local f="$1" extra="${2:-}" n rc=0
  n="$(LC_ALL=C grep -acE -e "${extra:+$extra|}$joined" "$f")" || rc=$?
  [ "$rc" -le 1 ] || return "$rc"
  if [ "${n:-0}" -eq 0 ] && [ -n "$has_personal" ]; then
    n="$(LC_ALL=C grep -aciE -f "$personal_pat" "$f")" || rc=$?
    [ "$rc" -le 1 ] || return "$rc"
  fi
  if [ "${n:-0}" -eq 0 ] && [ -n "$has_personal" ]; then
    n="$(pu_grep -c "$f")" || rc=$?
    [ "$rc" -le 1 ] || return "$rc"
  fi
  printf '%s' "${n:-0}"
}

# collect_matches LABEL PREFIX FILE FLAGS [EXTRA] — the one path from a match pass to records (dir #715):
# match_text FILE (FLAGS, EXTRA as there), fail closed on its status (STEP `match 'LABEL'`), and append
# each hit as a "PREFIX<hit>" record. Main shell only, so the records+= appends land here. Records are
# newline-separated, so a newline inside a name is written as the two characters `\n`: a raw one split the
# record, and a `path:` allowlist glob matching the tail fragment exempted the hit (dir #715 review).
# dir #693 — the read carries `|| [ -n "$hit" ]`: under a UTF-8 locale bash 5.x `read -r` returns 1 for a
# FINAL line whose last byte is an invalid multibyte lead byte (the newline is swallowed into the incomplete
# sequence), though it did fill the variable — a bare `while read` dropped exactly the record carrying the
# key (found by CI's ubuntu leg: bash 5.2 + a key line ending in a stray 0xE9).
# dir #715 (B3) — the same swallow mid-stream drops or merges the NEXT record (a NUL-delimited name list
# too: `-z` alone does not help), so EVERY `read` in this file runs under LC_ALL=C, which reads bytes and
# never swallows a delimiter, on bash 3.2–5.2 (glibc and musl). The parser twin above is the one exemption.
collect_matches() {
  local label="$1" prefix="${2//$'\n'/\\n}" f="$3" m="$SCRATCH/matches" hit=""
  match_text "$4" "$f" "${5:-}" > "$m" || _fail_closed "match '$label'" $?
  while LC_ALL=C IFS= read -r hit || [ -n "$hit" ]; do
    [ -z "$hit" ] || records+="$prefix$hit"$'\n'
  done < "$m"
}

# decode binary bytes on stdin (NUL-strip + optional iconv UTF-16LE/BE + raw-printable), match both
# classes, and emit "label:(binary) MATCH" records. The decode recipe is deliberately duplicated in
# public-audit.sh scan_binary_blobs() (each tool stands alone) — keep the two in sync (pinned by
# tests/test_secret_guard.sh, dir #681).
#
# dir #746 (S2-2, spec 746 B7): the decode never stops at an invalid unit. A plain iconv stopped at the first
# one (a lone surrogate, a value past U+10FFFF), so a literal after it read clean; `-c` skips it and decodes
# the rest (macOS libiconv, glibc). musl's iconv stops anyway and ignores -c, so where the host's iconv does not
# resume — or there is none — and a personal literal is non-ASCII (an ASCII one already survives the NUL-strip
# pass), a built-in decoder (od + awk) decodes the four encodings unit by unit: an invalid unit becomes a newline,
# surrogates pair, code point 0 is dropped. It costs about 24 s per MiB on busybox and never runs on macOS or
# glibc. Every pass but the best-effort iconv ones ends `|| exit $?`: a missing od, awk or tr ends the group,
# and the caller exits 2 naming the file. A payload that does not start on a unit boundary is not decoded.
#
# The whole joined stream is NUL-stripped once, after every pass below (dir #250): decoding UTF-32
# data through the UTF-16LE/BE converters (needed so a non-ASCII UTF-32 literal decodes at all — see
# the comment below) interleaves a NUL after every code unit's high byte, e.g. "l\0e\0a\0d\0". A NUL
# ANYWHERE in the file makes BSD grep (`/usr/bin/grep` on macOS) silently miss a non-ASCII `-i`
# pattern on EVERY line of that file under a real UTF-8 locale (`LC_ALL=C` is unaffected) —
# reproduced live, dir #250. Stripping once, on the join, is locale-neutral, keeps `-i` folding
# non-ASCII literals under UTF-8 (pinning `LC_ALL=C` around the grep instead would fix the miss but
# lose that folding — C-locale `-i` only folds ASCII), and — unlike stripping after each individual
# pass — covers any pass added here later for free, with no line to remember to re-append.
emit_blob() {  # $1 = record label (path)
  local label="$1" tmp dec
  # its caller's `||` turns errexit off in here (emit_file), so each read returns its own status
  tmp="$(spool)" || return $?
  dec="$(spool)" || return $?
  cat > "$tmp" || return $?
  {
    LC_ALL=C tr -d '\000' < "$tmp" || exit $?; echo              # ASCII-range UTF-16, no deps
    if command -v iconv >/dev/null 2>&1; then                     # non-ASCII UTF-16/UTF-32 (e.g. a Cyrillic name)
      iconv -c -f UTF-16LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      iconv -c -f UTF-16BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      # UTF-32: an ASCII literal survives the NUL-strip pass above (3-of-4 bytes are NUL), but a
      # NON-ASCII one (multi-byte code point) does not — decode it explicitly, symmetric with UTF-16.
      iconv -c -f UTF-32LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      iconv -c -f UTF-32BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
    fi
    # the built-in decoder, only where iconv cannot resume and a personal literal is non-ASCII
    if [ -n "${decode_nonascii:-}" ] && { ! command -v iconv >/dev/null 2>&1 || [ "$(printf 'A\000\000\330B\000' | iconv -c -f UTF-16LE -t UTF-8 2>/dev/null)" != AB ]; }; then
      od -An -v -tu1 < "$tmp" | LC_ALL=C awk '
        function o(v, k) {
          if (v < 128) { if (v) s[k] = s[k] sprintf("%c", v) }
          else if (v < 2048) s[k] = s[k] sprintf("%c%c", 192 + int(v / 64), 128 + v % 64)
          else if (v < 65536) s[k] = s[k] sprintf("%c%c%c", 224 + int(v / 4096), 128 + int(v / 64) % 64, 128 + v % 64)
          else s[k] = s[k] sprintf("%c%c%c%c", 240 + int(v / 262144), 128 + int(v / 4096) % 64, 128 + int(v / 64) % 64, 128 + v % 64)
        }
        function u16(u, k) {
          if (u >= 55296 && u < 56320) { if (h[k]) s[k] = s[k] "\n"; h[k] = u; return }
          if (u >= 56320 && u < 57344) { if (h[k]) o(65536 + (h[k] - 55296) * 1024 + u - 56320, k); else s[k] = s[k] "\n"; h[k] = 0; return }
          if (h[k]) { s[k] = s[k] "\n"; h[k] = 0 }
          o(u, k)
        }
        function u32(u, k) { if (u > 1114111 || (u >= 55296 && u < 57344)) s[k] = s[k] "\n"; else o(u, k) }
        {
          for (i = 1; i <= NF; i++) {
            b[n % 4] = $i; n++
            if (n % 2 == 0) { u16(b[(n - 2) % 4] + 256 * b[(n - 1) % 4], 1); u16(256 * b[(n - 2) % 4] + b[(n - 1) % 4], 2) }
            if (n % 4 == 0) { u32(b[0] + 256 * b[1] + 65536 * b[2] + 16777216 * b[3], 3); u32(16777216 * b[0] + 65536 * b[1] + 256 * b[2] + b[3], 4) }
          }
          if (NR % 256 == 0) { m++; for (k = 1; k <= 4; k++) { q[k, m] = s[k]; s[k] = "" } }
        }
        END { m++; for (k = 1; k <= 4; k++) { q[k, m] = s[k]; for (j = 1; j <= m; j++) printf "%s", q[k, j]; printf "\n" } }
      ' || exit $?; echo
    fi
    LC_ALL=C tr -c '[:print:]\t\n' '\n' < "$tmp" || exit $?; echo  # raw printable runs
  } | LC_ALL=C tr -d '\000' > "$dec" || return $?
  collect_matches "$label" "$label:(binary) " "$dec" -o
  rm -f "$tmp" "$dec"
}

# route one unit of content by type: binary → the decode pass, text → line matching with line numbers.
# emit_file reads a spool file this script made; emit_stream spools stdin first — the path for anything
# else. A caller's own path never reaches cmp/grep: a name like `-v` would be read as an option there, and
# the spool is one snapshot of a file that may change mid-scan. Both run in this shell (never in a pipe or
# a `$(…)`), so the records+= appends land here.
emit_file() {  # $1 = record label (path), $2 = a spool file under $SCRATCH
  if is_binary_file "$2"; then
    emit_blob "$1" < "$2" || _fail_closed "decode '$1'" $?
  else
    collect_matches "$1" "$1:" "$2" -n
  fi
}
emit_stream() {  # $1 = record label (path); the content on stdin
  local stmp
  stmp="$(spool)"
  cat > "$stmp"
  emit_file "$1" "$stmp"
  rm -f "$stmp"
}

# an annotated tag's message body — everything after the first blank line of the raw tag object. Its
# status (`pipefail`: git's, or sed's) is checked at both call sites, git's stderr kept in $2 (dir #715).
tag_body() { git cat-file tag "$1" 2>"$2" | sed '1,/^$/d'; }

# require_git_repo CALLER_LABEL — exit 2 (caller error) when not inside a git repo. Modes that scan
# repo state (--staged, --tracked) must fail CLOSED here: every later read is status-checked (dir
# #715), but a non-repo must exit with its own message first.
require_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "secret-scan: $1 needs a git repo" >&2; exit 2; }
}

# exact-match array membership — same shape as tools/audit-packet/export.sh's and
# tools/drydock/inventory.sh's own array_contains() (each kept local rather than shared, since a
# vendored file may only source what ships beside it); named here for the same reason.
array_contains() {  # $1 = needle, remaining = haystack
  local needle="$1"; shift
  local x
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

# --- dir #251: impact-log resolution, a small INLINE copy of tools/lib/impact-store.sh ------------
# This file is VENDORED (install-secret-guard.sh `cp`s it into each repo's hooks dir) and may only
# source files vendored beside it (range-lib.sh is the precedent) — it cannot `source` the shared lib,
# so its one behaviour both implementations must agree on (the LOG path for a given cwd) is kept here
# as a small, self-contained pair of functions instead. tests/test_secret_guard.sh's own sync test
# runs both under identical env/fixtures and asserts byte-identical output, so this copy can't quietly
# drift from tools/lib/impact-store.sh's impact_log_path/impact_claim_key.
_impact_log_path_inline() {
  local dir="${1:-.}" klog="${KEEL_IMPACT_LOG:-}" store_root legacy_root top store
  if [ -n "$klog" ]; then printf '%s' "$klog"; return; fi
  top="$(git -C "$dir" worktree list --porcelain 2>/dev/null |
    awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"  # fail-open-ok: impact-log metadata, never the verdict
  [ -n "$top" ] || top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"  # fail-open-ok: impact-log metadata, never the verdict
  [ -n "$top" ] || top="$(cd "$dir" 2>/dev/null && pwd -P)" || top="$dir"
  # A file still physically present at its legacy in-tree location wins outright — mirrors
  # tools/lib/impact-store.sh's own fix (dir #251 review): the store DIRECTORY existing is not proof
  # THIS file lives there (a partial migrate can leave the log's siblings tracked and in place). This
  # branch, and the top-resolution above it, must run BEFORE $store_root is ever computed — dir #251
  # review round 3: the earlier version computed store_root (and its ${HOME:?...} hard-error) FIRST,
  # so a repo with a genuine legacy file but no $HOME/$KEEL_HOME/$KEEL_IMPACT_STORE set would crash
  # here instead of resolving the legacy path the shared lib resolves cleanly (empirically confirmed:
  # the two implementations diverged on exactly this input).
  [ -n "$top" ] && [ -f "$top/.keel/impact-events.log" ] && { printf '%s/.keel/impact-events.log' "$top"; return; }
  if [ -n "${KEEL_IMPACT_STORE:-}" ]; then
    store_root="$KEEL_IMPACT_STORE"
  else
    # dir #637 B2, inline: $HOME/.keel/impact when it is a directory; else the legacy store
    # (${KEEL_HOME:-$HOME/.claude}/.keel/impact) while that is a directory (the transition rung, until
    # install.sh moves it); else $HOME/.keel/impact. Must stay byte-agreeing with
    # tools/lib/state-root.sh's keel_store_root (tests/test_secret_guard.sh's sync cases).
    store_root="${HOME:?secret-scan: set HOME, or export KEEL_IMPACT_STORE}/.keel/impact"
    legacy_root="${KEEL_HOME:-$HOME/.claude}/.keel/impact"
    if ! [ -d "$store_root" ] && [ -d "$legacy_root" ]; then store_root="$legacy_root"; fi
  fi
  store="$store_root/$(printf '%s' "$top" | tr '/' '-')"
  if [ -d "$store" ]; then printf '%s/impact-events.log' "$store"; return; fi
  # Same review finding, step 4: a bare `.keel/` dir is not proof of a genuine old-style `enable` — a
  # role-3-only marker (D3's own doctor-accept/map-drift-baseline) must not resolve here either. The
  # positive signal is the EXACT gitignore line pre-#251 `enable` always wrote, byte-for-byte — NOT
  # `git check-ignore` (a second review round caught this): that asks "is this path ignored by
  # ANYTHING", which an unrelated pattern like `*.log` would also satisfy, reopening the same leak.
  [ -n "$top" ] && [ -f "$top/.gitignore" ] && grep -qxF -e '/.keel/impact-events.log' "$top/.gitignore" 2>/dev/null && \
    printf '%s/.keel/impact-events.log' "$top"
  return 0
}
_impact_claim_key_inline() { git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || true; }  # fail-open-ok: impact-log metadata

# scan the added lines of one file's diff, emitting path-aware "path:content" records. No line number:
# the diff has already been reduced to a bare added-lines stream, so `grep -n` would number that stream,
# not the file — a misleading figure. The path + matched content is what's actionable.
emit_diff() {
  local path="$1"; shift   # remaining args = git diff args
  local dtmp
  dtmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
  # `sed 's/^+//'`, NOT `'^\+'`: BRE has no standard meaning for `\+` (GNU sed's "one or more"
  # extension), and BusyBox sed (Alpine CI leg) treats it as literal backslash-then-plus — matching
  # nothing, so the leading '+' from the diff's added-line marker survives unstripped and leaks into
  # every emitted record. '+' needs no escaping in BRE to match itself.
  # The "--- a/<path>" / "+++ b/<path>" file-header pair is excluded by tracking the first HUNK
  # header ("@@ -.. +.. @@") instead of matching the file header's own shape (dir #508 (d)): an
  # earlier version of this fix matched "--- "/"+++ " text directly, which a same-line edit could
  # still spoof — delete a line shaped "-- x" and add one shaped "++ <secret>" and diff renders
  # exactly "--- x" / "+++ <secret>" back-to-back, indistinguishable from a real header by shape
  # alone (caught live by this ticket's own review). A hunk header has no +/- prefix at all — real
  # content lines always carry one (added: "+", removed: "-"), so the literal text "@@ " can never
  # appear as the FIRST character of a real content line no matter what the file contains: an added
  # line whose own text starts with "@@ " still renders as "+@@ ...", not "@@ ...". And the file's
  # "--- "/"+++ " header pair always precedes the FIRST hunk, never recurring after it — so any
  # "+"-prefixed line seen once a hunk header has appeared is unconditionally real content.
  # --literal-pathspecs: "$path" is a real filename, not a glob the caller intended — a file
  # literally named e.g. "*" would otherwise match every staged path, folding every OTHER staged
  # file's added lines into this one path's records (max-review sweep finding).
  #
  # dir #693 — the parse is BYTE-oriented and FAIL-CLOSED. (1) awk and sed run under LC_ALL=C: on macOS
  # BWK awk (and BSD sed) under a UTF-8 locale ONE invalid byte in a staged text file (a stray Latin-1 /
  # CP1251 byte) aborts the parser ("towc: multibyte conversion failure"), and the old trailing `|| true`
  # swallowed that, so the scan ended `clean` over a diff it never read — the commit hook silently off for
  # any such file. Bytes are what the scanner wants; `match_text` reads the spooled records with `grep -a`.
  # (2) a failed leg (git diff, awk or sed — `pipefail` folds all three into one status) is no longer
  # swallowed: it exits 2 (this file's "cannot scan" status) naming the path. This runs in the main shell
  # (a loop body reading a spool file, not a `$(...)`), so the `exit` reaches the EXIT trap, which keeps it.
  # dir #697 — `--no-ext-diff --no-textconv`: `git diff` otherwise runs the USER'S configured drivers. A
  # `diff.external` program replaces the patch with its own output (no `@@` header, so awk emits nothing)
  # and a `textconv` filter replaces the file's content with the converter's output — either one hid a
  # staged key (`clean`, exit 0). The scanner reads the staged bytes, whatever the git config says.
  # dir #746 (D1-1, spec 746 B6): `tr -d '\000'` before awk. git diffs a file as text when its first 8000 bytes
  # hold no NUL; a later NUL reached awk, which truncated the line there, so a key after it was never read. The
  # NULs are dropped from the scanned text, as the binary decode's NUL-strip pass drops them.
  local derr="$dtmp.err"
  git --literal-pathspecs diff "$@" --unified=0 --no-color --no-ext-diff --no-textconv -- "$path" 2>"$derr" \
    | LC_ALL=C tr -d '\000' | LC_ALL=C awk '
    /^@@ / { in_hunk=1; next }
    in_hunk && /^\+/ { print }
  ' | LC_ALL=C sed 's/^+//' > "$dtmp" || _fail_closed "parse the staged diff of '$path'" $? "$derr"
  collect_matches "$path" "$path:" "$dtmp" ''
  rm -f "$dtmp" "$derr"
}

# selftest — end-to-end verification via child runs of this same script in FILE mode, from a neutral
# cwd (so a repo's .secret-scan-allow can't mask a probe) with a fixture personal file. A guard you
# can't verify degrades silently — this is the check install/bootstrap scripts run after wiring.
#
# Scope (dir #524): this covers what an ADOPTER'S install needs re-verified on THEIR host — the two
# detector classes actually catch a shape (key/personal, text/binary/UTF-16/UTF-32, inline-allow,
# fail-closed-on-bad-regex) plus, below, the --range message/tag/allowlist-baseline passes and (dir
# #715) one --staged probe: the commit hook's own path, whose name parse depends on the host's bash
# version and locale (bash >= 5 under UTF-8 dropped the record after a name ending in an invalid byte).
# It does NOT re-run dir #508's four --staged diff-PARSING fixtures (a renamed binary, a hunk-header
# anchor, a literal-pathspec glob, a same-change allowlist entry): they already have full, mutation-proved
# regression coverage in tests/test_secret_guard.sh (dev-time, every change), and duplicating them here
# would tax EVERY adopter install (install-secret-guard.sh runs --selftest before copying, dir #250).
selftest() {
  local script dir rc=0 fake greprc trailer mrepo trepo arepo arbase srepo bad _v resume_lit
  # shared git identity for every probe repo's commits/tags below — a probe repo must not depend on
  # host config (max-review reuse finding: this pair used to be re-typed at each of 4 call sites).
  local id_flags=(-c user.name=keel -c user.email=keel@keel.invalid)
  # dir #647: the probe repos below are built with `git -C "$x" ...`; an inherited GIT_DIR (git exports one
  # to hooks, `!` aliases and `rebase --exec` in a worktree) would send those commits and tags into a REAL
  # repo. Dropped here, in selftest() only — never at top level: the hook modes run under git's own
  # GIT_DIR/GIT_INDEX_FILE for the commit being scanned, and dropping GIT_INDEX_FILE there scans nothing
  # (tests/test_git_env_guard.sh B4, tests/test_secret_guard.sh A6).
  unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
  # dir #715 (B10): every probe repo below, and every child run, is isolated from the user's git config —
  # a broken `diff.*` there made the --range probes WARN-skip, and would fail the --staged probe at its
  # enumeration (which, by design, exits 2 on a config git cannot read). GIT_CONFIG_GLOBAL wins over
  # $HOME on git >= 2.32 (HOME/XDG cover older git); GIT_CONFIG_COUNT/KEY_*/VALUE_* and
  # GIT_CONFIG_PARAMETERS inject config straight through, so they go too. The host's locale is kept on
  # purpose: it is what the --staged probe verifies.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$SCRATCH/selftest" XDG_CONFIG_HOME="$SCRATCH/selftest"
  export SECRET_SCAN_PERSONAL_FILE=/dev/null KEEL_IMPACT_LOG=''
  for _v in ${!GIT_CONFIG_KEY_@} ${!GIT_CONFIG_VALUE_@}; do unset "$_v"; done
  unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  # BASH_SOURCE, not $0: resolves the script's real location even when invoked as `bash secret-scan.sh`
  # from another cwd — a selftest that can't find itself would fail for the wrong reason.
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  dir="$SCRATCH/selftest"; mkdir -p "$dir"
  # %.0s prints zero chars of each of the 36 args → 'a' repeated 36 times, built at runtime so the
  # literal token body never sits in this file (the scanner must not trip on its own source).
  fake="ghp_$(printf 'a%.0s' {1..36})"
  printf 'SeekritPersonName\n' > "$dir/personal"

  probe() {  # $1 = expected exit, $2 = label, $3 = personal file, $4 = fixture path
    local want="$1" label="$2" pfile="$3" fixture="$4" got=0
    (cd "$dir" && SECRET_SCAN_PERSONAL_FILE="$pfile" "$script" "$fixture" >/dev/null 2>&1) || got=$?
    if [ "$got" -eq "$want" ]; then
      echo "selftest: OK   — $label"
    else
      echo "selftest: FAIL — $label (exit $got, want $want)" >&2; rc=1
    fi
  }

  printf '%s\n' "$fake" > "$dir/key.txt"
  probe 1 "caught a key-shaped string" /dev/null "$dir/key.txt"
  printf 'docs reference ghp_[A-Za-z0-9]{36} and sk-ant-[A-Za-z0-9_-]{20,}\n' > "$dir/doc.txt"
  probe 0 "ignored the anchored pattern doc (no self-match)" /dev/null "$dir/doc.txt"
  printf '%s secret-scan:allow\n' "$fake" > "$dir/allowed.txt"
  probe 0 "honored the inline allow pragma" /dev/null "$dir/allowed.txt"
  printf 'author: seekritpersonname\n' > "$dir/pers.txt"
  probe 1 "caught a personal literal in text (case-insensitive)" "$dir/personal" "$dir/pers.txt"
  # The fail-closed probe holds only where grep itself signals a malformed ERE (exit >= 2) — WARN honestly
  # on a grep that accepts one instead of failing the whole selftest on an otherwise-working host. The probe
  # reads one input line (dir #694): busybox compiles a pattern only when it reads input, so over empty input
  # it looked lenient and this probe was skipped there.
  greprc=0; printf 'x\n' | grep -iE -e 'unbalanced(paren' >/dev/null 2>&1 || greprc=$?
  if [ "$greprc" -ge 2 ]; then
    printf 'unbalanced(paren\n' > "$dir/badre"
    printf 'anything\n' > "$dir/any.txt"
    probe 2 "malformed personal regex fails CLOSED (config error, not a silent pass)" "$dir/badre" "$dir/any.txt"
  else
    echo "selftest: WARN — this grep does not flag a malformed ERE; the fail-closed guard is a no-op on this host" >&2
  fi
  if command -v iconv >/dev/null 2>&1; then
    printf 'lead-in SeekritPersonName trail' | iconv -f UTF-8 -t UTF-16LE > "$dir/fixture.bin"
    probe 1 "caught a personal literal inside a UTF-16LE blob" "$dir/personal" "$dir/fixture.bin"
    # UTF-32 with a NON-ASCII literal: a Cyrillic name (built from bytes so this source stays ASCII)
    # survives ONLY via the iconv UTF-32 pass — its multi-byte code points are garbage after NUL-strip.
    cyr="$(printf '\320\230\320\262\320\260\320\275')"           # "Ivan" (Cyrillic) in UTF-8
    # Guard on the UTF-32 converter specifically (some minimal iconv builds have UTF-16 but not
    # UTF-32) — otherwise the encode silently yields an empty fixture and the probe FAILs falsely.
    if printf '%s' "$cyr" | iconv -f UTF-8 -t UTF-32LE >/dev/null 2>&1; then
      printf '%s\n' "$cyr" > "$dir/personal32"
      printf 'lead %s trail' "$cyr" | iconv -f UTF-8 -t UTF-32LE > "$dir/fixture32.bin"
      probe 1 "caught a non-ASCII personal literal inside a UTF-32LE blob" "$dir/personal32" "$dir/fixture32.bin"
    else
      echo "selftest: WARN — iconv lacks a UTF-32 converter; the UTF-32 pass is degraded on this host" >&2
    fi
  else
    echo "selftest: WARN — iconv absent; the non-ASCII UTF-16/UTF-32 passes are degraded on this host" >&2
  fi
  # dir #746 (B8): the decode resumes after an invalid unit — a lone high surrogate, then `lead <Ivan> trail`
  # in UTF-16LE, written byte by byte (no iconv needed). Found through `iconv -c` on macOS and glibc, through
  # the built-in decoder on musl or with no iconv: a FAIL on any host means emit_blob's recipe regressed. The
  # literal has its own variable — $cyr above is set only where iconv exists.
  resume_lit="$(printf '\320\230\320\262\320\260\320\275')"   # "Ivan" (Cyrillic) in UTF-8
  printf '%s\n' "$resume_lit" > "$dir/personal-resume"
  printf 'AB\000\330l\000e\000a\000d\000 \000\030\004\062\004\060\004\075\004 \000t\000r\000a\000i\000l\000' > "$dir/resume.bin"
  probe 1 "caught a non-ASCII personal literal after an invalid UTF-16 unit" "$dir/personal-resume" "$dir/resume.bin"
  # a session trailer in a pushed commit MESSAGE and in an annotated TAG message (neither is a
  # blob — only the --range message/tag passes see them). The trailer is built by printf so this
  # source never holds the literal. --template= + --no-verify + explicit -c identity: a probe repo
  # must not depend on host hooks/config (--no-verify alone leaves a template-installed
  # prepare-commit-msg hook running) — the recipe lives once, shared by both probes.
  trailer="$(printf 'Claude-%s: https://claude.ai/code/%s_selftest' Session session)"
  probe_repo() {  # $1 = dir, $2 = optional second -m paragraph for the probe commit
    git init -q --template= "$1" 2>/dev/null || return 1
    if [ -n "${2:-}" ]; then
      git -C "$1" "${id_flags[@]}" -c commit.gpgsign=false \
        commit -q --no-verify --allow-empty -m probe -m "$2" 2>/dev/null
    else
      git -C "$1" "${id_flags[@]}" -c commit.gpgsign=false \
        commit -q --no-verify --allow-empty -m probe 2>/dev/null
    fi
  }
  repo_probe() {  # $1 = repo, $2 = label, remaining = the scan's arguments — expects the scan to BLOCK
    local repo="$1" label="$2" got=0
    shift 2
    (cd "$repo" && "$script" "$@" >/dev/null 2>&1) || got=$?
    if [ "$got" -eq 1 ]; then
      echo "selftest: OK   — $label"
    else
      echo "selftest: FAIL — $label (exit $got, want 1)" >&2; rc=1
    fi
  }
  mrepo="$dir/msgrepo"
  if probe_repo "$mrepo" "$trailer"; then
    repo_probe "$mrepo" "caught a session trailer in a pushed commit message" --range "HEAD --not --remotes"
  else
    echo "selftest: WARN — could not create the message-probe repo; the commit-message pass is unverified on this host" >&2
  fi
  # the tag probe's commit is CLEAN, so a hit can only come from the tag body
  trepo="$dir/tagrepo"
  if probe_repo "$trepo" \
     && git -C "$trepo" "${id_flags[@]}" -c tag.gpgsign=false \
          tag -a probe-tag -m "$(printf 'release\n\n%s' "$trailer")" 2>/dev/null; then
    repo_probe "$trepo" "caught a session trailer in a pushed annotated-tag message" --range "probe-tag --not --remotes"
  else
    echo "selftest: WARN — could not create the tag-probe repo; the tag-message pass is unverified on this host" >&2
  fi
  # dir #518: --range's allowlist BASELINE resolution (the part this ticket added) — a same-pushed-
  # range allowlist entry must not exempt the secret it was added to hide, dir #508(a)'s own
  # same-change rule now reaching --range's "A..B" shape too (an existing branch's ordinary push —
  # the common case a pre-push hook actually sees; range-lib.sh's OTHER shape, "<tip> --not
  # --remotes" for a brand-new ref, is covered by the ticket's own regression fixtures instead —
  # it needs a second git remote-tracking ref to set up, more than a per-install smoke probe earns).
  # $1 = repo, already probe_repo()'d — plants a key + a SAME-range allowlist entry and commits
  # them together; sets $arbase on success. A real function (not inline in the if-body, language-
  # pitfall finding): the sibling mrepo/trepo probes chain their own risky git call INTO the if's own
  # condition via `&&` specifically so a failure there is exempt from `errexit` and falls through to
  # the graceful WARN below — inline then-body statements are NOT exempt the same way, so a failure
  # here would previously have crashed the whole selftest (and thus install-secret-guard.sh) instead
  # of degrading like every other probe does.
  plant_range_allow() {
    arbase="$(git -C "$1" rev-parse HEAD)" || return 1
    printf '%s\n' "$fake" > "$1/key.txt" || return 1
    printf '%s\n' "$fake" > "$1/.secret-scan-allow" || return 1    # NEW entry, SAME pushed range as the key
    git -C "$1" add key.txt .secret-scan-allow || return 1
    git -C "$1" "${id_flags[@]}" -c commit.gpgsign=false \
      commit -q --no-verify -m "key + same-range allowlist entry" || return 1
  }
  arepo="$dir/rangeallow"
  if probe_repo "$arepo" && plant_range_allow "$arepo"; then
    repo_probe "$arepo" "caught a same-pushed-range allowlist entry ('A..B' baseline resolution)" --range "$arbase..HEAD"
  else
    echo "selftest: WARN — could not create the range-allowlist probe repo; the --range baseline pass is unverified on this host" >&2
  fi
  # dir #715 (B10): the commit hook's own path. A staged key file b-key.txt, and — where the filesystem
  # accepts the name — a clean a-caf<0xE9> sorting IMMEDIATELY before it: a name read that swallows the
  # delimiter after an invalid byte (bash >= 5 under UTF-8, without LC_ALL=C on the read) loses the key's
  # record, and this probe FAILs on that host. On a filesystem that refuses the name the plain probe runs.
  srepo="$dir/stagedrepo"
  bad="a-caf$(printf '\351')"
  if git init -q --template= "$srepo" 2>/dev/null \
     && printf '%s\n' "$fake" > "$srepo/b-key.txt" \
     && git -C "$srepo" add b-key.txt 2>/dev/null; then
    if (printf 'clean\n' > "$srepo/$bad") 2>/dev/null; then
      git -C "$srepo" add -- "$bad" 2>/dev/null || rm -f "$srepo/$bad"
    fi
    repo_probe "$srepo" "caught a staged key (--staged, this host's bash and locale)" --staged
  else
    echo "selftest: WARN — could not create the staged-probe repo; the --staged pass is unverified on this host" >&2
  fi
  _scan_done=1
  return $rc
}

# scan_file_args FILE... — FILE mode's own body, shared by the `--` and bare-FILE... dispatch arms
# below (one definition, dir #495 code review's own reuse finding on the first cut, which typed this
# loop out twice).
scan_file_args() {
  local f fspool ferr
  fspool="$(spool)"; ferr="$(spool)"
  for f in "$@"; do
    [ -f "$f" ] || { echo "secret-scan: no such file: $f" >&2; exit 2; }
    # a checked read into a spool (dir #715 review): an unreadable file exits 2 naming it, not 1 (the
    # "found" status, with no hit line for a caller to parse); the name never reaches cmp/grep
    cat < "$f" > "$fspool" 2>"$ferr" || _fail_closed "read '$f'" $? "$ferr"
    emit_file "$f" "$fspool"
  done
}

mode="${1:-staged}"
case "$mode" in
  --)
    # Force FILE mode regardless of what the first filename looks like — dir #495's audit-packet
    # exporter passes a CALLER-SUPPLIED file list positionally, and without this, a real tracked file
    # literally named "staged" (or starting with "-", or empty) as the FIRST entry silently redirects
    # to a completely different mode instead of being scanned: `secret-scan.sh staged` (no `--`)
    # dispatches to `staged|--staged|""`'s branch (the git-diff-cached scan) and reports "clean"
    # without ever reading the file — reproduced live with a real ghp_-shaped secret inside a file
    # named `staged`, dir #495 code review, Angle C. `--` shifts once and takes every remaining
    # argument as a literal filename, the same convention `--` carries in virtually every other CLI.
    shift
    scan_file_args "$@"
    ;;
  --range)
    shift
    rng="${1:?--range needs A..B}"
    # Scan every blob the push would INTRODUCE (objects reachable in the range), not the net endpoint
    # diff: a secret added in one pushed commit and removed in a later one is absent from both endpoint
    # trees yet its blob still ships and stays recoverable — `git diff A..B` would miss it. rng is a
    # commit range (A..B) or rev-list args (a first push passes "<tip> --not --remotes"), so the
    # word-split is intentional. Blobs already on the far side are excluded → only what's being pushed.
    #
    # Fast path (the common case — a clean push): stream ALL introduced blob contents through ONE grep
    # per class. If nothing matches we stop here, paying O(1) processes regardless of blob count. Only
    # on a hit do we re-scan per blob for the exact path/line. The stream is NUL-stripped so a literal
    # inside an ASCII-range UTF-16 binary is visible to the fast check too.
    #
    # `grep -c` (count), NOT `grep -q`: -q exits on the first match, the still-writing `git cat-file`
    # takes SIGPIPE (141), and under `pipefail` the whole pipeline reads as failed — the hit is thrown
    # away and the push scans CLEAN. That was a real intermittent scanner hole (flaked on macOS CI,
    # buffer/timing-dependent). -c consumes the whole stream, so the status is deterministic.
    #
    # rev-list's own exit status (via `set -o pipefail`, active file-wide) is checked directly on the
    # SAME pipe that streams objects to cat-file — a typo'd/unfetched rev must be exit 2 (config
    # error), not a silent "clean" that discards rev-list's stderr/status and scans zero blobs, fail
    # OPEN. This also resolves the range only once (no separate --max-count=0 probe beforehand), and
    # keeps the streaming pipe rather than materializing the object list to a temp file first.
    rangeerr="$(mktemp "$SCRATCH/blob.XXXXXX")"
    # shellcheck disable=SC2086  # rng intentionally word-split into rev-list args
    if ! objs="$(git rev-list --objects $rng 2>"$rangeerr" \
                   | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' 2>/dev/null)"; then
      echo "secret-scan: bad range '$rng' — not resolvable in this repo" >&2
      sed 's/^/  /' "$rangeerr" >&2
      rm -f "$rangeerr"
      exit 2
    fi
    rm -f "$rangeerr"
    # dir #715 (B6 (a)): a corrupt or absent object prints `<sha> missing` here with rc 0 — read as an
    # object of no type, it was silently skipped and the push scanned clean. Every line must be one of
    # the four object types. (A partial clone prints no such line: lazy fetch fills the blob.)
    bad_obj="$(awk 'NF && $1 != "commit" && $1 != "tree" && $1 != "blob" && $1 != "tag" { print $1 }' <<< "$objs")" \
      || _fail_closed "list the range's objects" $?
    [ -z "$bad_obj" ] || _fail_closed "read object ${bad_obj%%$'\n'*} (missing or corrupt)"
    blobs="$(awk '$1=="blob"' <<< "$objs")" || _fail_closed "list the range's blobs" $?
    range_hits=1                                    # default: run the detailed scan
    if [ -z "$blobs" ]; then
      range_hits=0
    else
      # a non-ASCII personal literal (e.g. a Cyrillic name) is invisible to the NUL-strip fast view of
      # UTF-16 bytes — skip the fast path and let the detailed scan's decode passes see it
      if [ -z "$personal_nonascii" ]; then
        rtmp="$(spool)"; rerr="$(spool)"
        awk '{print $2}' <<< "$blobs" \
          | git cat-file --batch 2>"$rerr" | LC_ALL=C tr -d '\000' > "$rtmp" \
          || _fail_closed "read the range's blobs" $? "$rerr"
        range_hits="$(count_matches "$rtmp")" || _fail_closed "count matches in the range's blobs" $?
        rm -f "$rtmp" "$rerr"
      fi
    fi
    if [ "${range_hits:-0}" -gt 0 ]; then
      btmp="$(spool)"; berr="$(spool)"
      while LC_ALL=C IFS=' ' read -r _otype osha opath || [ -n "$opath" ]; do   # dir #693/#715: see emit_blob's loop
        [ -n "$osha" ] || continue
        git cat-file blob "$osha" > "$btmp" 2>"$berr" || _fail_closed "read blob $osha ('$opath')" $? "$berr"
        emit_file "$opath" "$btmp"
      done <<< "$blobs"
      rm -f "$btmp" "$berr"
    fi
    # The push also introduces the commits' MESSAGES, which no blob pass sees. Felt (2026-07-10
    # audit): seven harness-appended session trailers reached the public main through merged PRs,
    # visible afterwards only as a post-hoc audit WARN. Scan the messages against ALL THREE classes
    # (key shapes + personal literals + session metadata) — a key or a personal literal pasted into
    # a commit message ships to the remote just as unpurgeably as a session trailer, and the tag
    # pass below already scans all three; a commit message must not be the weaker sibling. Same
    # fast-path shape as the blob/tag scans (`count_matches`, `-c` not `-q`), then re-walk per
    # commit on a hit to attribute the exact sha.
    msgtmp="$(spool)"; merr="$(spool)"
    # shellcheck disable=SC2086  # rng intentionally word-split into rev-list args
    git log --format=%B $rng > "$msgtmp" 2>"$merr" || _fail_closed "read the range's commit messages" $? "$merr"
    msg_hits="$(count_matches "$msgtmp" "$SESSION_META")" \
      || _fail_closed "count matches in the range's commit messages" $?
    if [ "$msg_hits" -gt 0 ]; then
      clist="$(spool)"; ctmp="$(spool)"
      # shellcheck disable=SC2086  # rng intentionally word-split into rev-list args
      git rev-list $rng > "$clist" 2>"$merr" || _fail_closed "list the range's commits" $? "$merr"
      while LC_ALL=C IFS= read -r csha; do
        [ -n "$csha" ] || continue
        git log -1 --format=%B "$csha" > "$ctmp" 2>"$merr" \
          || _fail_closed "read the message of commit ${csha:0:7}" $? "$merr"
        collect_matches "commit ${csha:0:7} message" "commit ${csha:0:7} message:" "$ctmp" '' "$SESSION_META"
      done < "$clist"
      rm -f "$clist" "$ctmp"
    fi
    rm -f "$msgtmp" "$merr"
    # An annotated TAG's own message is neither a blob nor a commit message, so both passes above
    # are blind to it — a pushed tag (pre-push passes "<tagsha> --not --remotes") would carry a
    # key, a personal literal, or a session trailer to the remote unscanned. The tag objects are
    # already in the batch-check stream captured above; scan each tag's message body against all
    # three matchers via the same `count_matches` fast-path shared with the blob/commit passes.
    tagshas="$(awk '$1=="tag"{print $2}' <<< "$objs")" || _fail_closed "list the range's tags" $?
    if [ -n "$tagshas" ]; then
      tagtmp="$(spool)"; terr="$(spool)"
      while LC_ALL=C IFS= read -r tsha; do
        [ -n "$tsha" ] || continue
        tag_body "$tsha" "$terr" || _fail_closed "read tag ${tsha:0:7}" $? "$terr"
      done <<< "$tagshas" > "$tagtmp"
      tag_hits="$(count_matches "$tagtmp" "$SESSION_META")" || _fail_closed "count matches in the range's tag messages" $?
      if [ "${tag_hits:-0}" -gt 0 ]; then
        while LC_ALL=C IFS= read -r tsha; do
          [ -n "$tsha" ] || continue
          tag_body "$tsha" "$terr" > "$tagtmp" || _fail_closed "read tag ${tsha:0:7}" $? "$terr"
          collect_matches "tag ${tsha:0:7} message" "tag ${tsha:0:7} message:" "$tagtmp" '' "$SESSION_META"
        done <<< "$tagshas"
      fi
      rm -f "$tagtmp"
    fi
    ;;
  staged|--staged|"")
    require_git_repo --staged
    # dir #715 (B4): from the repository's top level — numstat paths are root-relative, but emit_diff's
    # pathspec resolves against the cwd, so a run from a subdirectory read `clean` over a staged key; the
    # cwd-relative allowlist becomes the root one too, as for HEAD:.secret-scan-allow and --tracked. A no-op
    # for the pre-commit hook, which git runs at the top level.
    serr="$(spool)"
    top="$(git rev-parse --show-toplevel 2>"$serr")" || _fail_closed "find the repository's top level" $? "$serr"
    cd "$top" || _fail_closed "find the repository's top level" $?
    ALLOW_BASELINE_REF=HEAD
    # ONE enumeration, its flag set kept in ONE place on purpose: a second hand-kept copy of the flags is
    # how the dir #508 (b) class of drift recurs. --diff-filter=d (dir #508 (c), an
    # EXCLUDE-list: only Deleted is dropped, everything else — Added/Copied/Modified/Renamed/Type-changed —
    # passes): a positive allow-list like the prior "ACM" (or even "ACMR") reproduces this exact bug one
    # status letter at a time as git adds more; a deleted file can never introduce an added line worth
    # scanning, so excluding only D is complete by construction. --no-renames: a renamed BINARY file
    # would otherwise land here as "<old> => <new>", one combined field no path read can use; with it a
    # rename is a plain Delete (excluded above) plus an Add of the new path.
    # dir #715 (S7-1, S7-2): `-z` — git emits raw paths, never C-quoted, every record NUL-terminated, so a
    # name holding a tab, a quote, a backslash or a newline is read whole (the old newline-delimited
    # `--name-only` and `--numstat` passes skipped each such file). The status is checked: a `diff.*` config
    # git cannot read, or a corrupt index, exits 2 naming git's error — it used to empty the list → `clean`.
    slist="$(spool)"
    git diff --cached --no-renames --diff-filter=d --no-ext-diff --no-textconv --numstat -z \
      > "$slist" 2>"$serr" || _fail_closed "list the staged files" $? "$serr"
    sblob="$(spool)"
    tab=$'\t'
    while LC_ALL=C IFS= read -r -d '' rec || [ -n "$rec" ]; do
      # "<added>TAB<deleted>TAB<path>": the path is everything after the FIRST two tabs — a name may itself
      # begin or end with a tab, so never `IFS=$'\t' read`.
      f="${rec#*"$tab"*"$tab"}"
      [ -n "$f" ] || continue
      case "$rec" in
        "-$tab-$tab"*)
          # a binary file has no text diff — decode and scan its staged blob. `cat-file blob :0:<path>`, not
          # `git show :<path>`: show reads `1:x.bin` as stage 1 of `x.bin` (that file was silently skipped),
          # and only show can apply a textconv driver.
          git cat-file blob ":0:$f" > "$sblob" 2>"$serr" || _fail_closed "read the staged blob of '$f'" $? "$serr"
          emit_file "$f" "$sblob" ;;
        *) emit_diff "$f" --cached ;;
      esac
    done < "$slist"
    ;;
  --tracked)
    # Detective audit: scan ALL tracked content as it sits in the working tree — text with line
    # numbers, binaries through the decode pass. For a periodic review / doctor run, not a hook
    # (it is O(repo), not O(change)). Anchored to the repo root so a subdirectory invocation can
    # never silently audit only that subtree; the allowlist is the root one for the same reason.
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "secret-scan: --tracked needs a git repo" >&2; exit 2; }
    ALLOW_FILE="$top/.secret-scan-allow"
    # dir #715 (B5): `-z` (raw, NUL-terminated names — a tab, quote or newline in a name no longer skips
    # the file), the status checked (a corrupt index exits 2 instead of auditing zero files), every read
    # under LC_ALL=C (B3, emit_blob's loop).
    tlist="$(spool)"; terr="$(spool)"
    git -C "$top" ls-files -z > "$tlist" 2>"$terr" || _fail_closed "list the tracked files" $? "$terr"
    while LC_ALL=C IFS= read -r -d '' f || [ -n "$f" ]; do
      [ -n "$f" ] || continue
      if [ -L "$top/$f" ]; then
        # a tracked symlink's committed content IS its target string — scan that (it can carry a
        # personal path); the target file itself, if tracked, is scanned as its own entry. A failed
        # readlink read as an empty target, i.e. `clean` (dir #715).
        target="$(readlink "$top/$f")" || _fail_closed "read the tracked symlink '$f'" $?
        emit_stream "$f" <<< "$target"
      elif [ -f "$top/$f" ]; then
        if [ -r "$top/$f" ]; then
          emit_stream "$f" < "$top/$f"
        else
          # skip-and-warn, never abort: one unreadable file must not void the rest of the audit
          echo "secret-scan: WARN unreadable, skipped: $f" >&2
        fi
      fi
    done < "$tlist"
    ;;
  --selftest)
    selftest; exit $?
    ;;
  -*)
    echo "secret-scan: unknown option '$mode'" >&2; exit 2
    ;;
  *)
    scan_file_args "$@"
    ;;
esac

[ -n "$records" ] || { echo "secret-scan: clean"; _scan_done=1; exit 0; }

# dir #518: resolve the --range allowlist same-change-provenance baseline (dir #508 (a) extended to
# --range too), but only now — AFTER we already know this push has something to check the allowlist
# against at all (max-review completeness finding: an earlier cut ran this unconditionally inside the
# --range arm whenever an allowlist file existed, paying a full boundary graph-walk, and printing its
# "no baseline" WARN, on every push to any repo carrying a .secret-scan-allow — including a fully
# clean push that never reaches this line). `[ -n "${rng:-}" ]` is `--range` mode's own marker: `rng`
# is set nowhere else.
#
# `git rev-list --boundary` gives the exact excluded frontier of WHATEVER rng already is, so one
# mechanism covers every pushed-ref shape without this scanner ever needing to know the remote's name
# or reconstruct a remote-tracking ref path: for "A..B" the boundary is A itself (dir #518's first
# fixture: an allowlist line predating the range is clean); for "<tip> --not --remotes" (a first push
# of a new local ref — resolve_range_local in range-lib.sh emits this shape when the pre-push hook's
# own remote sha is zero, or (dir #546) a non-zero sha that is no commit in this repo) the boundary is
# the merge-base with whichever remote-tracking ref(s) the tip forked from — none at all for the
# second spelling in a repo with no remote (a filter-repo'd clone), so every entry reads as new-this-push.
#
# UNION every boundary commit found, never require exactly one (max-review correctness finding,
# confirmed live: an earlier version of this fix required a single boundary commit and treated 2+ as
# ambiguous — but an ORDINARY `git merge origin/main` before push, the standard way a feature branch
# picks up upstream, makes `--boundary` return TWO already-known ancestors, one per parent line the
# merge commit brings in, not one; both are equally legitimate "existed before this push" evidence,
# and treating that routine case as unresolvable fail-closed every pre-existing allowlist entry on the
# single most common non-trivial `--range` shape there is). An entry is trusted if it existed in ANY
# boundary commit's committed allow file — reachable ONLY via already-known history, so the union can
# never include anything THIS push introduces: the security property (dir #508(a)'s own same-change
# rule) holds regardless of how many boundary commits there are. Zero boundary commits (no shared
# history at all — e.g. a brand-new branch with no upstream yet, dir #518's lead 1) unions to nothing:
# every current entry reads as new-this-push, the ticket's own named fail-closed fallback, reached via
# an empty set rather than a sentinel ref. **A third, disclosed shape reaches here too (max-review
# finding, confirmed live, pinned by tests/test_ci_secret_scan.sh):** ci-scan.sh's own force-push
# fallback (range-lib.sh's resolve_range_ci, zero-before branch) — as of dir #572, this is the LAST
# resort of a three-step degrade: ci-scan.sh first tries to fetch the orphaned before-sha by its own
# sha from origin, then the operator's SECRET_SCAN_CI_FORCE_PUSH_BASELINE hatch (also fetched by
# sha), and only when NEITHER resolves does it hand over a BARE ref with no exclusion side at all —
# the true pre-push remote state is exactly what's unreachable at THAT point, so there is no
# principled single baseline left to fall back to; it unions to nothing the same way, and that is
# accepted, not an oversight — safe (over-blocking on an already-rare, doubly-unrecovered force-push,
# never a silent pass), never silently unaccounted for.
#
# **A FOURTH gap, found by an in-session cross-model (Gemini) second opinion, fixed for the LOCAL
# pre-push hook only (mutation-proved, pinned by tests/test_secret_guard.sh): a boundary snapshot of
# THIS branch's own delta alone missed content already pushed elsewhere.** An entry that arrives
# INSIDE the pushed range via a merge, even one that genuinely predates the secret it exempts (each
# committed and pushed separately, and safely, on the branch it came from), was invisible to the union
# the same way a same-change entry correctly is — `main` legitimately adds an entry in one commit and
# the secret it exempts in a LATER commit (each individually clean against ITS OWN push-time baseline,
# already reviewed and pushed to `origin/main`); a feature branch then `git merge origin/main`s both in
# and pushes — the merge brought the pair INSIDE the range rather than leaving the entry at a boundary,
# so it read as new-this-push and an otherwise-legitimate LOCAL push falsely BLOCKED.
#
# Fixed the same way `resolve_range_local`'s OWN first-push shape ("<tip> --not --remotes") already
# excludes known-remote content: append `--not --remotes` to WHATEVER $rng already is, so a commit
# already reachable from ANY remote-tracking ref (by definition already known/reviewed, on any branch)
# resolves as a boundary commit in its own right. **But ONLY when `SECRET_SCAN_LOCAL_PUSH` says this
# call is the LOCAL pre-push hook — a second, independent max-review pass (same cross-model reviewer,
# a follow-up round) caught that applying this unconditionally is UNSAFE for `ci-scan.sh`'s caller:**
# its own `resolve_range_ci` docstring already explains why (a CI checkout runs AFTER the push landed,
# so the range's OWN TIP is typically already reachable from a remote-tracking ref too — reproduced
# live: appending `--not --remotes` there doesn't just tighten the boundary, it excludes the tip itself
# from the walk entirely, collapsing EVERY ordinary CI scan's baseline to nothing and fail-closing every
# pre-existing allowlist entry on every push, not just the merge case this was meant to fix). The local
# hook is the one caller where this is actually safe: it runs BEFORE the push transfers, so the
# range's own newly-introduced tip cannot yet be reachable from a remote-tracking ref by construction
# — interior commits merged in via `git merge origin/main` commonly already are, and it is that
# asymmetry `--not --remotes` above relies on. An attacker's own newly-pushed commit can never
# retroactively become "already known" this way, preserving the same-change security property
# regardless of which branch of this `if` runs (dir #569). Without the flag (ci-scan.sh, `--selftest`, a
# human running `--range` by hand), the union falls back to the THIRD gap's own plain-boundary behavior
# above — narrower, but exactly as safe as it was before this fourth gap was found.
#
# Still gated on the allowlist file existing too (a records hit with no .secret-scan-allow at all has
# nothing for a baseline to gate — the shared compare block below never reads these either way).
if [ -n "${rng:-}" ] && [ -f "$ALLOW_FILE" ]; then
  ALLOW_BASELINE_MODE="range"
  boundary_err="$(mktemp "$SCRATCH/blob.XXXXXX")"
  if [ -n "${SECRET_SCAN_LOCAL_PUSH:-}" ]; then
    boundary_rng="$rng --not --remotes"
  else
    boundary_rng="$rng"
  fi
  # shellcheck disable=SC2086  # boundary_rng intentionally word-split into rev-list args, same as elsewhere
  if ! boundary_out="$(git rev-list --boundary $boundary_rng 2>"$boundary_err")"; then
    # A real git-level failure walking $rng (e.g. a truncated/grafted clone) must not read
    # identically to "no shared history yet" (max-review language-pitfall finding: an earlier cut
    # discarded rev-list's own exit status here, unlike the --objects call above, which already
    # treats this same class of failure as the config error it is).
    echo "secret-scan: --range could not walk '$boundary_rng' to resolve its allowlist baseline — treating every .secret-scan-allow entry as new-this-push" >&2
    sed 's/^/  /' "$boundary_err" >&2
    rm -f "$boundary_err"
  else
    rm -f "$boundary_err"
    while LC_ALL=C IFS= read -r _bl; do
      case "$_bl" in
        -*) ALLOW_BASELINE_REFS+=("${_bl#-}") ;;
      esac
    done <<< "$boundary_out"
    if [ "${#ALLOW_BASELINE_REFS[@]}" -eq 0 ]; then
      echo "secret-scan: --range found no pre-push history to compare the allowlist against (e.g. the first push of a brand-new branch with no upstream) — every .secret-scan-allow entry is treated as new-this-push and will not exempt a match here; commit a legitimate allowlist entry by itself, pushed ahead of the commit(s) that need it" >&2
    fi
  fi
fi

# --- apply the allowlist ------------------------------------------------------------------------------
drop_res=()
path_globs=()
if [ -f "$ALLOW_FILE" ]; then
  # dir #508 (a): a legitimate human escape hatch must not be agent-usable in-band (FRAMEWORK.md
  # L701-702) — reject an allowlist entry added in the SAME staged change as the secret it would
  # exempt. Compare against a trusted baseline's committed copy, not the staged/working one: an
  # entry only new relative to that baseline exempts nothing THIS change adds. No baseline at all
  # (--tracked, FILE mode) → no check, every entry trusted as before. A baseline ref with no HEAD
  # yet (first ever commit) → head_allow_lines stays empty, so every current entry reads as
  # new-this-change. Read once into a plain array (not re-grepped per entry): bash 3.2 has indexed
  # arrays but no associative ones, and this file must run on macOS's stock bash.
  #
  # Two callers, two shapes (dir #518): --staged has exactly one trusted point (HEAD) → the scalar
  # ALLOW_BASELINE_REF. --range can have SEVERAL equally-legitimate ones (an ordinary merge before
  # push boundaries to more than one already-known ancestor — see the --range arm's own comment) →
  # the ALLOW_BASELINE_REFS array, unioned below when ALLOW_BASELINE_MODE="range"; an entry counts
  # as pre-existing if ANY one of them already had it committed.
  head_allow_lines=()
  if [ -n "$ALLOW_BASELINE_REF" ]; then
    # `|| [ -n "$hl" ]`: without it, a baseline file with no trailing newline loses its LAST line —
    # `read` fails on the final unterminated line, so that entry never joins the array and reads as
    # "new this change", false-blocking a legitimate commit over a pre-existing entry.
    while LC_ALL=C IFS= read -r hl || [ -n "$hl" ]; do
      head_allow_lines+=("${hl%$'\r'}")
    done < <(git show "$ALLOW_BASELINE_REF:$ALLOW_FILE" 2>/dev/null || true)  # fail-open-ok: a failed read makes every entry new — it over-blocks (dir #715 B8)
  elif [ "$ALLOW_BASELINE_MODE" = "range" ]; then
    for _bref in "${ALLOW_BASELINE_REFS[@]:-}"; do
      [ -n "$_bref" ] || continue
      while LC_ALL=C IFS= read -r hl || [ -n "$hl" ]; do
        head_allow_lines+=("${hl%$'\r'}")
      done < <(git show "$_bref:$ALLOW_FILE" 2>/dev/null || true)  # fail-open-ok: a failed read makes every entry new — it over-blocks (dir #715 B8)
    done
  fi
  # `|| [ -n "$entry" ]`: same reason as head_allow_lines above — an allowlist with no trailing
  # newline on its last line would otherwise silently lose that entry entirely (dropped from
  # drop_res/path_globs, not merely "new this change"), disabling it with no diagnostic at all.
  while LC_ALL=C IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%$'\r'}"                 # tolerate a CRLF-saved allowlist (strip trailing CR)
    [ -z "$entry" ] && continue
    case "$entry" in
      \#*) continue ;;                     # comment
    esac
    if { [ -n "$ALLOW_BASELINE_REF" ] || [ "$ALLOW_BASELINE_MODE" = "range" ]; } \
       && ! array_contains "$entry" "${head_allow_lines[@]:-}"; then
      # "this change" (not "this staged change"): dir #518 reuses this same check for --range, where
      # nothing is staged — the wording must hold for both callers.
      echo "secret-scan: ignoring an allowlist entry new in this change (put it in its own earlier commit, ahead of the secret it would exempt, and already pushed/committed before this change): $entry" >&2
      continue
    fi
    case "$entry" in
      path:*) path_globs+=("${entry#path:}") ;;
      *) drop_res+=("$entry") ;;
    esac
  done < "$ALLOW_FILE"
fi

found=0
# LC_ALL=C (dir #715, B3): a key record ending in an invalid byte was merged with the NEXT record under
# bash >= 5 + UTF-8, and an allowlist hit on that second record dropped both.
while LC_ALL=C IFS= read -r rec; do
  [ -z "$rec" ] && continue
  # inline allow
  case "$rec" in *secret-scan:allow*) continue ;; esac
  # ERE allowlist
  skip=0
  for re in "${drop_res[@]:-}"; do
    [ -z "$re" ] && continue
    # A here-string, not a `printf | grep -q` pipe: under `set -o pipefail`, printf as a live writer
    # can be SIGPIPE'd by grep's own early exit on match, flipping a real allowlist match into a
    # false "not allowlisted" under load (dir #280) — a spurious finding, not a missed one, but still
    # unreliable evidence in a security-facing scanner. `-e` (dir #746 B2): an entry starting with `-` is a
    # pattern — `-e.` read positionally was the option -e with the pattern `.`, exempting every record. LC_ALL=C
    # (B5): bytes, as the records are; a non-ASCII entry using `.` or a bracket can only over-block.
    if LC_ALL=C grep -qE -e "$re" <<< "$rec"; then skip=1; break; fi
  done
  [ "$skip" = 1 ] && continue
  # path-glob allowlist (only meaningful for "path:line" records)
  recpath="${rec%%:*}"
  for g in "${path_globs[@]:-}"; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2053
    if [[ "$recpath" == $g ]]; then skip=1; break; fi
  done
  [ "$skip" = 1 ] && continue

  if [ "$found" = 0 ]; then
    echo "secret-scan: BLOCKED — secret-shaped string(s) or personal data detected:" >&2
    found=1
  fi
  echo "  $rec" >&2
done <<< "$records"

if [ "$found" = 1 ]; then
  # Impact instrumentation (metadata only, opt-in per repo): record that a guardrail fired so keel-impact
  # can auto-ingest it — a deterministic, zero-token signal. NEVER the matched secret; only the fact of a
  # block. Resolved by the inline copy above (dir #251): $KEEL_IMPACT_LOG, else this repo's external
  # store entry, else a legacy in-tree marker; with none of those, nothing is written and the hook's
  # behaviour is unchanged. `|| true` (dir #251 review): under this script's own `set -e`, this bare
  # assignment WOULD trip errexit if the resolver's `${HOME:?...}` fires (no override, no $HOME at all)
  # — aborting the whole script before the remediation guidance below ever prints, even though a real
  # secret WAS already found and reported. Degrading to empty (this metadata step's own "not enabled"
  # signal) instead keeps the block's actual job — stopping the commit, showing remediation — intact.
  _klog="$(_impact_log_path_inline .)" || true  # fail-open-ok: metadata only, after the block is decided
  if [ -n "$_klog" ]; then
    _kclaim="$(_impact_claim_key_inline .)"
    # dir #251 review: the resolver's legacy-marker fallback (a genuine old-style-`enable`d repo, proven
    # by its .gitignore line) can name a path whose parent .keel/ doesn't physically exist yet — a fresh
    # clone that carries the committed gitignore line but never recreated the untracked dir. Without
    # this, the append's own failed redirect leaks a raw "No such file or directory" onto stderr (NOT
    # suppressed by the `2>/dev/null` below — that only covers the command's own stderr, not a failed
    # redirection setup) and silently drops the guard event.
    mkdir -p "$(dirname "$_klog")" 2>/dev/null || true  # fail-open-ok: impact-log metadata
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" guard secret-guard blocked "$_kclaim" \
      >> "$_klog" 2>/dev/null || true  # fail-open-ok: impact-log metadata
  fi
  echo "" >&2
  # Say WHAT to do (remove the secret), not HOW to bypass the check: the exact allowlist syntax is
  # deliberately kept OUT of this block message so an agent optimizing to get unblocked can't follow it as
  # a recipe (an agent under test on Cursor did exactly that). A genuine fixture is a human, out-of-band
  # decision — the mechanism is documented in this script's header. See FRAMEWORK.md "Enforcement mechanics".
  echo "This looks like a real secret — remove it (use an env var or a secret manager), then re-commit." >&2
  echo "A genuine test fixture is a rare exception a human allowlists deliberately (see this script's header); an agent must NOT add an allowlist entry just to get a commit through." >&2
  echo "Operator-specific literals live in the local, never-committed \$SECRET_SCAN_PERSONAL_FILE." >&2
  exit 1
fi

echo "secret-scan: clean"
_scan_done=1
exit 0
