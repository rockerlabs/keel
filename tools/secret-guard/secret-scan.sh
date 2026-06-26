#!/usr/bin/env bash
# secret-scan — backstop scanner for key-shaped secrets.
#
# Catches key-SHAPED strings only (a known prefix + a long body) — exactly what bots scrape repos for.
# It does NOT catch passwords, opaque/custom tokens, or base64 blobs: it is a backstop to .gitignore +
# env vars, NOT a complete DLP. Mark that boundary honestly (P1).
#
# Usage:
#   secret-scan.sh                 scan staged changes (added/modified), for a pre-commit hook
#   secret-scan.sh --range A..B    scan the diff of a commit range, for a pre-push hook
#   secret-scan.sh FILE...         scan specific files
#
# Allowlist (for legit fixtures/example keys — be deliberate, real keys hide in tests too):
#   a repo-root .secret-scan-allow file:
#     <ERE>          drop any matched line from results
#     path:<glob>    exclude a path
#   or an inline  secret-scan:allow  comment on the offending line.
#
# Exit 0 = clean; 1 = a secret-shaped string found; 2 = usage error.

set -euo pipefail

# Length-anchored patterns: a bare prefix or this pattern list itself never trips them.
PATTERNS=(
  'ghp_[A-Za-z0-9]{36}'                 # GitHub personal access token
  'github_pat_[A-Za-z0-9_]{60,}'        # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                    # AWS access key id
  'AIza[0-9A-Za-z_-]{35}'              # Google API key
  'sk-ant-[A-Za-z0-9_-]{20,}'          # Anthropic API key
  'sk-[A-Za-z0-9]{32,}'                # generic "sk-" secret key
  'xox[baprs]-[A-Za-z0-9-]{10,}'       # Slack token
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # PEM private key
)

ALLOW_FILE=".secret-scan-allow"

# Build a combined regex.
joined=""
for p in "${PATTERNS[@]}"; do
  joined="${joined:+$joined|}$p"
done

# --- gather the lines to scan as "path:line" records ---------------------------------------------------
records=""

emit_file() {
  # $1 = path on disk; scan its current content
  local f="$1"
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    records+="$f:$line"$'\n'
  done < <(grep -nE "$joined" -- "$f" 2>/dev/null || true)
}

# scan the added lines of one file's diff, emitting path-aware "path:n:content" records
emit_diff() {
  local path="$1"; shift   # remaining args = git diff args
  while IFS= read -r hit; do
    records+="$path:$hit"$'\n'
  done < <(git diff "$@" --unified=0 --no-color -- "$path" 2>/dev/null \
            | grep -E '^\+' | grep -vE '^\+\+\+' \
            | sed 's/^\+//' \
            | grep -nE "$joined" || true)
}

mode="${1:-staged}"
case "$mode" in
  --range)
    shift
    rng="${1:?--range needs A..B}"
    while IFS= read -r f; do
      [ -n "$f" ] && emit_diff "$f" "$rng"
    done < <(git diff --name-only --diff-filter=ACM "$rng" 2>/dev/null || true)
    ;;
  staged|"")
    while IFS= read -r f; do
      [ -n "$f" ] && emit_diff "$f" --cached
    done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
    ;;
  -*)
    echo "secret-scan: unknown option '$mode'" >&2; exit 2
    ;;
  *)
    for f in "$@"; do emit_file "$f"; done
    ;;
esac

[ -n "$records" ] || { echo "secret-scan: clean"; exit 0; }

# --- apply the allowlist ------------------------------------------------------------------------------
drop_res=()
path_globs=()
if [ -f "$ALLOW_FILE" ]; then
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    case "$entry" in
      \#*) ;;                              # comment
      path:*) path_globs+=("${entry#path:}") ;;
      *) drop_res+=("$entry") ;;
    esac
  done < "$ALLOW_FILE"
fi

found=0
while IFS= read -r rec; do
  [ -z "$rec" ] && continue
  # inline allow
  case "$rec" in *secret-scan:allow*) continue ;; esac
  # ERE allowlist
  skip=0
  for re in "${drop_res[@]:-}"; do
    [ -z "$re" ] && continue
    if printf '%s' "$rec" | grep -qE "$re"; then skip=1; break; fi
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
    echo "secret-scan: BLOCKED — key-shaped secret(s) detected:" >&2
    found=1
  fi
  echo "  $rec" >&2
done <<< "$records"

if [ "$found" = 1 ]; then
  echo "" >&2
  echo "If this is a legit fixture, add it to $ALLOW_FILE or an inline 'secret-scan:allow' — don't weaken the scanner." >&2
  exit 1
fi

echo "secret-scan: clean"
exit 0
