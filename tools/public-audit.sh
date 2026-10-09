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
#   public-audit.sh [DIR]            audit DIR (default: .); reads DIR/.public-audit if present
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
  public-audit.sh [DIR]            audit DIR (default: .); reads DIR/.public-audit if present
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

# Built-in public-safe email patterns (ERE). Real personal/corporate emails are deliberately absent.
# dir #106: the set lives in tools/lib/safe-emails.sh — doctor.sh sources the same file for its
# advisory commit-email nudge, so the two can't silently re-diverge.
_pa_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# --- gather config -------------------------------------------------------------------------------
tokens=()
[ "${#cli_tokens[@]}" -gt 0 ] && tokens+=("${cli_tokens[@]}")
allow_emails=()
allow_paths=()

cfg="${CONFIG:-$DIR/.public-audit}"
if [ -f "$cfg" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    val="$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$line" in
      ''|\#*)         ;;
      token:*)        tokens+=("$val") ;;
      allow-email:*)  allow_emails+=("$val") ;;
      allow-path:*)   allow_paths+=("$val") ;;
    esac
  done < "$cfg"
fi

# Bad ERE? Detect by stderr, not exit code: a valid pattern on empty input exits 1 (no match) with no
# stderr; a broken one prints an error. (busybox grep doesn't use exit 2 for a bad regex, so an
# exit-code check would pass a broken regex through.) Shared by the allow-email and personal-literal
# validation below — same idiom, only the case-sensitivity flag differs.
valid_ere() { local flag="$1" pat="$2"; [ -z "$(printf '' | grep "$flag" -- "$pat" 2>&1 >/dev/null)" ]; }

# Personal literals from the secret-guard's local file double as private tokens for this audit —
# they are precisely what must not ship when a repo goes public. Case-INSENSITIVE (unlike tokens).
# Invalid lines are counted and reported as a GAP, not just a WARN (without echoing them — the file's
# whole point is that its content stays off any pasteable output): unlike a bad allow-email entry
# (which fails open safely — worst case one extra false WARN), a bad personal-literal line means that
# literal goes completely unscanned, which is a detection-accuracy failure this audit's own GAP bar
# ("high-confidence leaks... painful to scrub after publishing") exists to catch, not just advise on.
PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-$HOME/.claude/secret-scan-personal}"
personal_re=""
bad_personal=0
# dir #148: the parse (read, CRLF, BOM, comments, whitespace) is tools/lib/personal-literals.sh's (capture
# rules in its header); only the per-line validation policy stays here. Its status is read at the GAP
# site below (dir #680): 3 = a line ends in a backslash (withheld by the parser; the other literals are
# still scanned), anything else non-zero = the file could not be read or parsed (coverage is ZERO).
personal_rc=0
personal_lines="$(personal_literals_parse "$PERSONAL_FILE")" || personal_rc=$?
while IFS= read -r line; do
  [ -n "$line" ] || continue   # an empty capture still yields one empty line
  if valid_ere -iE "$line"; then
    personal_re="${personal_re:+$personal_re|}$line"
  else
    bad_personal=$((bad_personal + 1))
  fi
done <<EOF_PERSONAL
$personal_lines
EOF_PERSONAL
# dir #746 (B7): decode_binary's built-in decoder runs only for a non-ASCII needle — a personal literal this
# audit scans with, or a token (an ASCII one already survives the NUL-strip pass).
decode_nonascii=""
case "$personal_re" in *[![:ascii:]]*) decode_nonascii=1 ;; esac
if [ "${#tokens[@]}" -gt 0 ]; then
  for t in "${tokens[@]}"; do
    case "$t" in *[![:ascii:]]*) decode_nonascii=1 ;; esac
  done
fi

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

# --- reporting -----------------------------------------------------------------------------------
exit_code=0
say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

is_git=0
git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 && is_git=1

# Temp refs from the host-PR-ref scan (section 6) must never outlive the run. Clean them on EXIT/INT/TERM
# so a Ctrl-C mid-fetch — or a run against a repo with no GitHub remote — leaves nothing behind, and any
# orphan a prior interrupted run left is reaped on the next run's exit.
cleanup_pr_refs() {
  [ "$is_git" = 1 ] || return 0
  git -C "$DIR" for-each-ref --format='%(refname)' 'refs/keel-pr-audit/*' 2>/dev/null \
    | while IFS= read -r r; do [ -n "$r" ] && git -C "$DIR" update-ref -d "$r" 2>/dev/null || true; done
}
audit_tmp="$(mktemp -d)"
# dir #85 (code audit, finding 11): the INT/TERM handler must EXIT. Bash runs a trap handler for a
# caught signal and then RESUMES the script — so Ctrl-C used to tear down the fetched PR refs and the
# tmpdir and then keep auditing against the state it had just deleted, while the operator believed the
# run was cancelled. `exit 130` is the conventional 128+SIGINT status; the EXIT trap still fires after
# it (that is what actually performs cleanup), so the teardown is written once, not per-signal.
trap 'cleanup_pr_refs; rm -rf "$audit_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Decode ONE file's bytes (a committed blob written to a scratch path, or a working-tree file read
# directly) into concatenated ASCII/UTF-16/UTF-32/raw-printable views, for the regex scans that can't
# see into binary content directly. Shared by scan_binary_blobs (history + dir #509's working-tree
# pass) so there is exactly one place implementing this recipe inside this file — keep it IN SYNC with
# secret-guard/secret-scan.sh's own emit_blob() (each tool stands alone, so an encoding gap fixed there
# must be fixed here too; pinned by tests/test_secret_guard.sh, dir #681).
#
# dir #746 (S2-2): the decode never stops at an invalid unit — iconv -c, or the built-in od + awk decoder
# where the host's iconv cannot resume (musl) or is absent and a personal literal or a token is non-ASCII
# (decode_nonascii). secret-scan.sh's emit_blob() comment has the details. A pass that cannot run ends the
# group with its status, which this function returns.
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
    LC_ALL=C tr -d '\000' < "$src" || exit $?; echo              # ASCII-range UTF-16, no deps
    if command -v iconv >/dev/null 2>&1; then                     # non-ASCII UTF-16/UTF-32 (e.g. a Cyrillic name)
      iconv -c -f UTF-16LE -t UTF-8 "$src" 2>/dev/null || true; echo
      iconv -c -f UTF-16BE -t UTF-8 "$src" 2>/dev/null || true; echo
      # UTF-32: an ASCII literal survives the NUL-strip pass above (3-of-4 bytes are NUL), but a
      # NON-ASCII one (multi-byte code point) does not — decode it explicitly, symmetric with UTF-16.
      iconv -c -f UTF-32LE -t UTF-8 "$src" 2>/dev/null || true; echo
      iconv -c -f UTF-32BE -t UTF-8 "$src" 2>/dev/null || true; echo
    fi
    # the built-in decoder, only where iconv cannot resume and a personal literal is non-ASCII
    if [ -n "${decode_nonascii:-}" ] && { ! command -v iconv >/dev/null 2>&1 || [ "$(printf 'A\000\000\330B\000' | iconv -c -f UTF-16LE -t UTF-8 2>/dev/null)" != AB ]; }; then
      od -An -v -tu1 < "$src" | LC_ALL=C awk '
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
    LC_ALL=C tr -c '[:print:]\t\n' '\n' < "$src" || exit $?; echo  # raw printable runs
  } | LC_ALL=C tr -d '\000' > "$dst" || return $?
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
  local max; max="$(sanitize_nonneg_int "${KEEL_AUDIT_BLOB_MAX:-10485760}" 10485760)"
  local tmp="$audit_tmp/blob" dec="$audit_tmp/blob.dec"
  local otype osha osize opath h t skipped=0 reported_toks="" reported_personal=""
  local hit_home="" hit_email="" hit_cyr=""
  # A failed mktemp (full/unwritable TMPDIR) must not silently no-op the whole pass — the tool's job
  # is never to trust unscanned content. Surface it and bail.
  if [ ! -d "$audit_tmp" ]; then
    warn "binary-blob scan of $label SKIPPED — no usable temp dir (mktemp failed); result is INCOMPLETE"
    return 0
  fi
  # LC_ALL=C (dir #719 B13): under bash >= 5 + UTF-8 a committed name ending in an invalid byte makes `read`
  # drop the NEXT record, so a blob after it would never be decoded.
  while IFS='|' LC_ALL=C read -r otype osha osize opath; do
    [ "$otype" = "blob" ] && [ -n "$osha" ] || continue
    if [ "${osize:-0}" -gt "$max" ]; then skipped=$((skipped + 1)); continue; fi
    git -C "$DIR" cat-file blob "$osha" > "$tmp" 2>/dev/null || continue
    # binary = contains a NUL byte; text blobs are already covered by the text passes
    LC_ALL=C tr -d '\000' < "$tmp" | cmp -s - "$tmp" && continue
    decode_binary "$tmp" "$dec"
    if [ "${#tokens[@]}" -gt 0 ]; then
      for t in "${tokens[@]}"; do
        [ -z "$t" ] && continue
        case "$reported_toks" in *"|$t|"*) continue ;; esac       # one GAP per token per pass
        if [ -n "$(grep -aE -- "$t" "$dec" 2>/dev/null | head -n1 || true)" ]; then
          gap "private token /$t/ in a binary blob in $label — ${opath:-$osha}"
          reported_toks="$reported_toks|$t|"
        fi
      done
    fi
    if [ -n "$personal_re" ] && [ -z "$reported_personal" ]; then
      h="$(grep -aoiE -- "$personal_re" "$dec" 2>/dev/null | head -1 || true)"
      if [ -n "$h" ]; then
        gap "personal literal (secret-scan-personal) in a binary blob in $label — ${opath:-$osha}: $h"
        reported_personal=1
      fi
    fi
    if [ -z "$hit_home" ]; then
      h="$(grep -aoE "$HOME_RE" "$dec" 2>/dev/null | head -1 || true)"
      [ -n "$h" ] && hit_home="$h (${opath:-$osha})"
    fi
    if [ -z "$hit_email" ]; then
      h="$(grep -aoE "$EMAIL_RE" "$dec" 2>/dev/null | grep -vE "$safe_re" | head -1 || true)"
      [ -n "$h" ] && hit_email="$h (${opath:-$osha})"
    fi
    if [ -z "$hit_cyr" ]; then
      # Require ≥4 CONSECUTIVE Cyrillic chars, unlike the single-pair text heuristic: the NUL-strip
      # and raw-printable views of compressed data (a gif, a zip) match an isolated
      # [\xd0-\xd3][\x80-\xbf] pair by chance hundreds of times per MB — a real name is a run.
      h="$(LC_ALL=C grep -acE "(${cyr_pat}){4}" "$dec" 2>/dev/null || true)"
      [ "${h:-0}" -gt 0 ] && hit_cyr="${opath:-$osha}"
    fi
  done < <(git -C "$DIR" rev-list --objects "$@" 2>/dev/null \
           | git -C "$DIR" cat-file --batch-check='%(objecttype)|%(objectname)|%(objectsize)|%(rest)' 2>/dev/null)
  [ -n "$hit_home" ]  && warn "absolute home path in a binary blob in $label — e.g. $hit_home"
  [ -n "$hit_email" ] && warn "email in a binary blob in $label — e.g. $hit_email"
  [ -n "$hit_cyr" ]   && warn "Cyrillic text in a binary blob in $label — e.g. $hit_cyr"
  [ "$skipped" -gt 0 ] && warn "$skipped binary blob(s) over KEEL_AUDIT_BLOB_MAX (${max}B) skipped in $label — UN-audited; raise the cap to cover them"
  return 0
}

say "● public-audit ($DIR)"
[ "$is_git" = 1 ] || say "       (not a git repo — git-history checks skipped)"

# annotated-tag message bodies, captured once for sections 2, 4 and 5 — a tag's message is neither a
# commit message nor a diff, so `git log` (any format) never shows it. Populated up here (moved off
# section 4, dir #509 F7) so the declared-token loop in section 2 can check it too.
tag_msgs=""
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  tag_msgs="$(git -C "$DIR" for-each-ref --format='%(contents)' refs/tags 2>/dev/null || true)"
fi

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
[ -n "$personal_re" ] && say "       (hunting the local secret-scan-personal literals as private tokens)"

# helper: first matching line of a tracked-tree grep, or empty
tree_grep() { git -C "$DIR" grep -nIE -- "$1" -- . "${excludes[@]}" 2>/dev/null; }

# --- 1. identities in git history (GAP) ----------------------------------------------------------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # A shallow clone only carries part of history, so every scan below sees an incomplete picture and a
  # clean result is not trustworthy. Warn loudly (visible even under --quiet, via the WARN stream).
  if [ "$(git -C "$DIR" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    warn "shallow clone — git-history scans are INCOMPLETE; run 'git fetch --unshallow' before trusting a clean result"
  fi
  ids="$( { git -C "$DIR" log --all --format='%ae%n%ce' 2>/dev/null;
            git -C "$DIR" for-each-ref --format='%(taggeremail)' refs/tags 2>/dev/null | tr -d '<>'; } \
          | sed '/^$/d' | sort -u )"
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    # A here-string, not a `printf | grep -q` pipe: under `set -o pipefail`, printf as a live writer
    # can be SIGPIPE'd by grep's own early exit on match, flipping a real "safe" match into a false
    # GAP under load (dir #280) — the same class the pr_hist scan below (S2) already fixes.
    grep -qE "$safe_re" <<< "$e" && continue
    gap "non-public-safe identity in git history: $e"
  done <<EOF
$ids
EOF
fi

# --- 2. declared-private tokens, in tree AND history (GAP) ---------------------------------------
# The block also runs for personal literals alone (dir #719 B12): a binary holding one used to read clean.
# Each token loop keeps its own non-empty test — bash 3.2 under `set -u` aborts on "${tokens[@]}" when empty.
if [ "${#tokens[@]}" -gt 0 ] || [ -n "$personal_re" ]; then
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
  if [ "$is_git" = 1 ]; then
    if [ ! -d "$audit_tmp" ]; then
      warn "working-tree binary-token scan SKIPPED — no usable temp dir (mktemp failed); result is INCOMPLETE"
    else
      # Same cap as scan_binary_blobs (dir #196: sanitized against a non-numeric/overflowing override) —
      # an oversized file must be skipped-and-surfaced here too, not scanned unconditionally, or the
      # working-tree pass silently defeats the cap the history pass already enforces.
      wt_max="$(sanitize_nonneg_int "${KEEL_AUDIT_BLOB_MAX:-10485760}" 10485760)"
      # `git diff`/`git diff --cached` print paths relative to the repo ROOT even under `-C "$DIR"`,
      # while `git ls-files` prints paths relative to `$DIR` itself — a real divergence (verified live),
      # so every diff-sourced path needs `$DIR`'s own root-prefix stripped before it can be joined onto
      # "$DIR/..." like the ls-files-sourced ones already can be. Empty at the repo root (no-op).
      wt_prefix="$(git -C "$DIR" rev-parse --show-prefix 2>/dev/null || true)"
      if [ "$NO_HISTORY" = 1 ]; then
        # Every TRACKED file (matching tree_grep's own unscoped text coverage), plus untracked ones —
        # `ls-files` alone would silently drop the untracked case default mode still catches.
        wt_src() {
          git -C "$DIR" ls-files -z -- . "${excludes[@]}" 2>/dev/null
          git -C "$DIR" ls-files --others --exclude-standard -z -- . "${excludes[@]}" 2>/dev/null
        }
      else
        wt_src() {
          git -C "$DIR" diff --name-only -z --diff-filter=ACMR HEAD -- . "${excludes[@]}" 2>/dev/null \
            | while IFS= LC_ALL=C read -r -d '' _wp; do printf '%s\0' "${_wp#"$wt_prefix"}"; done
          git -C "$DIR" ls-files --others --exclude-standard -z -- . "${excludes[@]}" 2>/dev/null
        }
      fi
      # LC_ALL=C on both NUL reads (dir #719 B13): see scan_binary_blobs' read.
      while IFS= LC_ALL=C read -r -d '' f; do
        [ -L "$DIR/$f" ] && continue          # a symlink's tracked content is its link-text, not its target
        [ -f "$DIR/$f" ] || continue
        fsize="$(wc -c < "$DIR/$f" 2>/dev/null | tr -d ' ')"
        if [ "${fsize:-0}" -gt "$wt_max" ]; then wt_bin_skipped=$((wt_bin_skipped + 1)); continue; fi
        LC_ALL=C tr -d '\000' < "$DIR/$f" 2>/dev/null | cmp -s - "$DIR/$f" 2>/dev/null && continue
        decode_binary "$DIR/$f" "$audit_tmp/wt.dec"
        if [ "${#tokens[@]}" -gt 0 ]; then
          for t in "${tokens[@]}"; do
            [ -z "$t" ] && continue
            case "$wt_bin_reported" in *"|$t|"*) continue ;; esac
            if [ -n "$(grep -aE -- "$t" "$audit_tmp/wt.dec" 2>/dev/null | head -n1 || true)" ]; then
              gap "private token /$t/ in a binary file in the working tree — $f"
              wt_bin_reported="$wt_bin_reported|$t|"
            fi
          done
        fi
        if [ -n "$personal_re" ] && [ -z "$wt_personal_reported" ]; then
          h="$(grep -aoiE -- "$personal_re" "$audit_tmp/wt.dec" 2>/dev/null)"   # no `| head` under pipefail
          h="${h%%$'\n'*}"
          if [ -n "$h" ]; then
            gap "personal literal (secret-scan-personal) in a binary file in the working tree — $f: $h"
            wt_personal_reported=1
          fi
        fi
      done < <(wt_src)
      [ "$wt_bin_skipped" -gt 0 ] && warn "$wt_bin_skipped binary file(s) over KEEL_AUDIT_BLOB_MAX (${wt_max}B) skipped in the working tree — UN-audited; raise the cap to cover them"
    fi
  fi

  if [ "${#tokens[@]}" -gt 0 ]; then
    for t in "${tokens[@]}"; do
      [ -z "$t" ] && continue
      hit="$(tree_grep "$t" | head -1 || true)"
      [ -n "$hit" ] && gap "private token /$t/ in tracked tree — e.g. $hit"
      if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
        c="$(git -C "$DIR" log --all --oneline -G"$t" 2>/dev/null | head -1 || true)"
        m="$(git -C "$DIR" log --all --oneline --grep="$t" -E 2>/dev/null | head -1 || true)"
        [ -n "$c$m" ] && gap "private token /$t/ in git history — e.g. ${c:-$m}"
        # F7 (dir #509): an annotated-tag message body is neither a commit message nor a diff, so the
        # -G/--grep pair above never sees it; $tag_msgs was captured for this purpose.
        tg="$(printf '%s\n' "$tag_msgs" | grep -aE -- "$t" | head -1 || true)"
        [ -n "$tg" ] && gap "private token /$t/ in an annotated-tag message — e.g. $tg"
      fi
    done
  fi
fi

# --- 2b. personal literals (local secret-scan-personal), in tree text (GAP) ----------------------
if [ -n "$personal_re" ]; then
  hit="$(git -C "$DIR" grep -inIE -- "$personal_re" -- . "${excludes[@]}" 2>/dev/null | head -1 || true)"
  [ -n "$hit" ] && gap "personal literal (secret-scan-personal) in tracked tree — e.g. $hit"
fi

# --- 3. heuristic content scans (WARN) -----------------------------------------------------------
home="$(tree_grep "$HOME_RE" | head -1 || true)"
[ -n "$home" ] && warn "absolute home path in tracked tree — e.g. $home"

emails="$(tree_grep "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
[ -n "$emails" ] && warn "email in tracked content — e.g. $emails"

# Cyrillic via UTF-8 lead bytes (0xD0-0xD3) + a continuation byte — portable across grep flavors,
# unlike `git grep -P '\x{0400}'` which isn't supported on every git build.
cyr_pat=$'[\xd0-\xd3][\x80-\xbf]'
# Subshell cd so ls-files' repo-relative paths resolve for grep (which runs in the current cwd).
cyr="$( cd "$DIR" && git ls-files -z -- . "${excludes[@]}" 2>/dev/null \
        | LC_ALL=C xargs -0 grep -lI "$cyr_pat" 2>/dev/null | head -1 || true)"
[ -n "$cyr" ] && warn "Cyrillic text in tracked file — e.g. $cyr"

# --- 4. agent tooling / session metadata (WARN) --------------------------------------------------
# The per-session trailers a coding agent appends to commits (and the same shape in tracked files).
# We hit this leak class ourselves and the audit missed it — so surface it on purpose.
# Mirrored by secret-guard/secret-scan.sh SESSION_META (the preventive pre-push block) — keep in sync
# (pinned by tests/test_secret_guard.sh, dir #681).
session_re='([A-Za-z][A-Za-z0-9-]*-Session:|claude\.ai/code/session)'
sess_tree="$(tree_grep "$session_re" | head -1 || true)"
[ -n "$sess_tree" ] && warn "agent/session metadata in tracked tree — e.g. $sess_tree"
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  sess_msg="$( { git -C "$DIR" log --all --format='%B' 2>/dev/null;
                 printf '%s\n' "$tag_msgs"; } | grep -aE "$session_re" | head -1 || true)"
  [ -n "$sess_msg" ] && warn "agent/session metadata in a commit or tag message — e.g. $sess_msg"
fi

# --- 5. history content heuristics (WARN) --------------------------------------------------------
# Section 3 scans the working tree only — so personal data in a commit-message body or a historical
# diff (an added-then-removed blob) would pass clean. Scan history content (messages + diffs in one
# `git log -p` pass) with the SAME regexes; reuse EMAIL_RE/HOME_RE/safe_re/cyr_pat. WARN, not GAP.
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # message bodies + diffs, AND annotated-tag message bodies (which `git log -p` omits).
  hist="$( { git -C "$DIR" log --all -p 2>/dev/null;
             printf '%s\n' "$tag_msgs"; } )"
  h="$(printf '%s\n' "$hist" | grep -nE "$HOME_RE" | head -1 || true)"
  [ -n "$h" ] && warn "absolute home path in git history — e.g. $h"
  h="$(printf '%s\n' "$hist" | grep -nIE "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
  [ -n "$h" ] && warn "email in git history content — e.g. $h"
  h="$(printf '%s\n' "$hist" | LC_ALL=C grep -n "$cyr_pat" | head -1 || true)"
  [ -n "$h" ] && warn "Cyrillic text in git history — e.g. $h"
fi

# --- 5a. personal literals (local secret-scan-personal), in git history text (GAP) ----------------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ] && [ -n "$personal_re" ]; then
  h="$(printf '%s\n' "$hist" | grep -aniE -- "$personal_re" | head -1 || true)"
  [ -n "$h" ] && gap "personal literal (secret-scan-personal) in git history — e.g. $h"
fi

# --- 5b. binary blobs — the decoded scan of what sections 3/5 cannot see (tree + history) ---------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  scan_binary_blobs "git history" --all
fi

# --- 6. host-side PR refs (GitHub refs/pull/*) ---------------------------------------------------
# These are served by the host but are NOT reachable from `git log --all`, so a leak in a closed PR's
# commits passes the local scan (a force-push of `main` does not purge them). When a remote is set
# (and not --no-history), fetch them and run the SAME checks: identity/token = GAP, heuristic = WARN.
# Offline / no PR refs / non-GitHub remote → a prominent NOTE (out of local scope — the only fix is
# delete-and-recreate; see docs/going-public.md). The network call is gated so the tool still runs offline.
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # Probe EVERY remote, not just the first: `git remote | head -1` could pick a non-GitHub mirror that
  # sorts ahead of the real GitHub remote and silently skip the PR-ref scan. Scan each remote that
  # exposes refs/pull/*; emit the OUT-OF-SCOPE note only if a remote exists but none did.
  any_remote=0; scanned_pr=0
  while IFS= read -r remote; do
    [ -n "$remote" ] || continue
    any_remote=1
    # Capture the first ref, don't gate on the pipeline status: under `pipefail`, `… | grep -q .`
    # makes ls-remote die with SIGPIPE on a busy remote (1000+ refs/pull/*), and the 141 would skip
    # the whole PR-ref scan for that remote. The captured-non-empty test can't be flipped by SIGPIPE.
    [ -n "$(git -C "$DIR" ls-remote --quiet "$remote" 'refs/pull/*' 2>/dev/null | head -n1)" ] || continue
    scanned_pr=1
    # Fetch both the PR tip (…/head) AND GitHub's synthetic merge (…/merge) — neither is reachable
    # from `git log --all`. Flat dest names keep them in one namespace for the scans below.
    git -C "$DIR" fetch -q "$remote" 'refs/pull/*/head:refs/keel-pr-audit/head-*' \
      'refs/pull/*/merge:refs/keel-pr-audit/merge-*' 2>/dev/null || true
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      # A here-string (dir #280) — see the git-history identity scan above for why not a
      # `printf | grep -q` pipe.
      grep -qE "$safe_re" <<< "$e" && continue
      gap "non-public-safe identity in a host PR ref (refs/pull/*): $e — purge via delete-and-recreate (going-public.md)"
    done <<EOF
$(git -C "$DIR" log --glob='refs/keel-pr-audit/*' --format='%ae%n%ce' 2>/dev/null | sed '/^$/d' | sort -u)
EOF
    pr_hist="$(git -C "$DIR" log --glob='refs/keel-pr-audit/*' -p 2>/dev/null || true)"
    if [ "${#tokens[@]}" -gt 0 ]; then
      for t in "${tokens[@]}"; do
        [ -z "$t" ] && continue
        # Capture-then-test, not `grep -qE … && gap`: with a token that matches EARLY in a large
        # pr_hist, `printf | grep -q` SIGPIPEs printf, and `pipefail` makes the pipeline 141 — so the
        # `&& gap` never fires and a real leak passes clean. The captured hit can't be lost to SIGPIPE.
        if [ -n "$(printf '%s\n' "$pr_hist" | grep -E -- "$t" | head -n1 || true)" ]; then
          gap "private token /$t/ in a host PR ref (refs/pull/*) — purge via delete-and-recreate"
        fi
      done
    fi
    if [ -n "$personal_re" ]; then
      ph="$(printf '%s\n' "$pr_hist" | grep -aniE -- "$personal_re" | head -1 || true)"
      [ -n "$ph" ] && gap "personal literal (secret-scan-personal) in a host PR ref (refs/pull/*) — e.g. $ph — purge via delete-and-recreate"
    fi
    # Same heuristic set the local-history pass (sections 4-5) applies, over PR-ref content. WARN.
    ph="$(printf '%s\n' "$pr_hist" | grep -nIE "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
    [ -n "$ph" ] && warn "email in a host PR ref (refs/pull/*) — e.g. $ph"
    ph="$(printf '%s\n' "$pr_hist" | grep -nE "$HOME_RE" | head -1 || true)"
    [ -n "$ph" ] && warn "absolute home path in a host PR ref (refs/pull/*) — e.g. $ph"
    ph="$(printf '%s\n' "$pr_hist" | LC_ALL=C grep -n "$cyr_pat" | head -1 || true)"
    [ -n "$ph" ] && warn "Cyrillic text in a host PR ref (refs/pull/*) — e.g. $ph"
    ph="$(printf '%s\n' "$pr_hist" | grep -naE "$session_re" | head -1 || true)"
    [ -n "$ph" ] && warn "agent/session metadata in a host PR ref (refs/pull/*) — e.g. $ph"
    # Binary blobs a PR ref carries that local history does not. The exclusion must NOT be a bare
    # `--not --all`: --all includes the refs/keel-pr-audit/* temp refs themselves (fetched above), so
    # the include-set would be a subset of the exclude-set and the scan a silent no-op — --exclude
    # carves the temp namespace out of the --all that follows it. A leak in a closed PR's binary
    # fixture is exactly as recoverable as a text one.
    scan_binary_blobs "a host PR ref (refs/pull/*)" \
      --glob='refs/keel-pr-audit/*' --not --exclude='refs/keel-pr-audit/*' --all
    cleanup_pr_refs   # reap this remote's temp refs before the next iteration (also runs on EXIT)
  done <<EOF_REMOTES
$(git -C "$DIR" remote 2>/dev/null)
EOF_REMOTES
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
  _klog="$(impact_log_path "$DIR")"
  if [ -n "$_klog" ]; then
    _kclaim="$(impact_claim_key "$DIR")"
    # dir #251 review: the resolver's legacy-marker fallback can name a path whose parent .keel/
    # doesn't physically exist yet (a fresh clone carrying the committed gitignore line but never
    # recreating the untracked dir) — without this, the append's own failed redirect leaks a raw error
    # and silently drops the event.
    mkdir -p "$(dirname "$_klog")" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" guard public-audit blocked "$_kclaim" \
      >> "$_klog" 2>/dev/null || true
  fi
fi
exit "$exit_code"
