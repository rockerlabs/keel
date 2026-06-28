#!/usr/bin/env bash
# public-audit — is this repo safe to publish? Scan tracked content AND git history for personal /
# instance-specific leakage before a private->public flip. The audit you run once, on demand — NOT a
# per-commit hook (scanning full history every commit is the wrong altitude).
#
#   GAP  (fails, exit 1): a declared-private token, or a commit/tag identity email that isn't
#        public-safe — high-confidence leaks that are painful to scrub after publishing.
#   WARN (advisory):      heuristic hits — absolute home paths, other emails in content, Cyrillic —
#        a human decides.
#
# Usage:
#   public-audit.sh [DIR]            audit DIR (default: .); reads DIR/.public-audit if present
#   public-audit.sh --token ERE ...  add a private token to hunt (repeatable; CLI, not committed)
#   public-audit.sh --no-history ... tree only (skip the git-history scan)
#   public-audit.sh --config FILE    use a specific config file
#   public-audit.sh --quiet ...      print only GAP/WARN lines
#
# Config (.public-audit) — ERE values, '#' comments:
#   token: <ERE>         a private string to flag in tree + history (an internal name, host, ...)
#   allow-email: <ERE>   an email/domain OK in history & content (added to the built-in noreply set)
#   allow-path: <glob>   a tracked path to skip in content scanning
#
# Note: a committed `.public-audit` literally contains its token strings. For a truly-secret token,
# pass it with --token (ephemeral) or keep the config gitignored, rather than committing it.
set -uo pipefail

QUIET=0
NO_HISTORY=0
CONFIG=""
DIR=""
cli_tokens=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet)      QUIET=1 ;;
    --no-history) NO_HISTORY=1 ;;
    --config)     shift; CONFIG="${1:?--config needs a FILE}" ;;
    --token)      shift; cli_tokens+=("${1:?--token needs an ERE}") ;;
    -*)           echo "public-audit: unknown option '$1'" >&2; exit 2 ;;
    *)            DIR="$1" ;;
  esac
  shift
done
DIR="${DIR:-.}"
[ -d "$DIR" ] || { echo "public-audit: not a directory: $DIR" >&2; exit 2; }

# Built-in public-safe email patterns (ERE). Real personal/corporate emails are deliberately absent.
SAFE_EMAILS=(
  '@users\.noreply\.github\.com'
  'noreply@anthropic\.com'
  'noreply@github\.com'
  '@example\.(com|org|net)'
  '@[A-Za-z0-9.-]*\.invalid'
)
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

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

# combined safe-email regex (built-ins + configured allow-email)
safe_re=""
for e in "${SAFE_EMAILS[@]}"; do safe_re="${safe_re:+$safe_re|}$e"; done
if [ "${#allow_emails[@]}" -gt 0 ]; then
  for e in "${allow_emails[@]}"; do [ -n "$e" ] && safe_re="${safe_re:+$safe_re|}$e"; done
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

say "● public-audit ($DIR)"
[ "$is_git" = 1 ] || say "       (not a git repo — git-history checks skipped)"

# helper: first matching line of a tracked-tree grep, or empty
tree_grep() { git -C "$DIR" grep -nIE "$1" -- . "${excludes[@]}" 2>/dev/null; }

# --- 1. identities in git history (GAP) ----------------------------------------------------------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  ids="$( { git -C "$DIR" log --all --format='%ae%n%ce' 2>/dev/null;
            git -C "$DIR" for-each-ref --format='%(taggeremail)' refs/tags 2>/dev/null | tr -d '<>'; } \
          | sed '/^$/d' | sort -u )"
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    printf '%s' "$e" | grep -qE "$safe_re" && continue
    gap "non-public-safe identity in git history: $e"
  done <<EOF
$ids
EOF
fi

# --- 2. declared-private tokens, in tree AND history (GAP) ---------------------------------------
if [ "${#tokens[@]}" -gt 0 ]; then
  for t in "${tokens[@]}"; do
    [ -z "$t" ] && continue
    hit="$(tree_grep "$t" | head -1 || true)"
    [ -n "$hit" ] && gap "private token /$t/ in tracked tree — e.g. $hit"
    if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
      c="$(git -C "$DIR" log --all --oneline -G"$t" 2>/dev/null | head -1 || true)"
      m="$(git -C "$DIR" log --all --oneline --grep="$t" -E 2>/dev/null | head -1 || true)"
      [ -n "$c$m" ] && gap "private token /$t/ in git history — e.g. ${c:-$m}"
    fi
  done
fi

# --- 3. heuristic content scans (WARN) -----------------------------------------------------------
home="$(tree_grep '/(Users|home)/[A-Za-z0-9._-]+' | head -1 || true)"
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

# --- verdict -------------------------------------------------------------------------------------
[ "$exit_code" = 0 ] && say "public-audit: no publication blockers found"
exit "$exit_code"
