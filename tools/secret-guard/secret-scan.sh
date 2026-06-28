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
  'sk_(live|test)_[A-Za-z0-9]{16,}'    # Stripe secret key (underscore form)
  'glpat-[A-Za-z0-9_-]{20,}'           # GitLab personal access token
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
  done < <(grep -nIE "$joined" -- "$f" 2>/dev/null || true)   # -I: skip binary (per the backstop boundary)
}

# scan the added lines of one file's diff, emitting path-aware "path:content" records. No line number:
# the diff has already been reduced to a bare added-lines stream, so `grep -n` would number that stream,
# not the file — a misleading figure. The path + matched content is what's actionable.
emit_diff() {
  local path="$1"; shift   # remaining args = git diff args
  while IFS= read -r hit; do
    records+="$path:$hit"$'\n'
  done < <(git diff "$@" --unified=0 --no-color -- "$path" 2>/dev/null \
            | grep -E '^\+' | grep -vE '^\+\+\+' \
            | sed 's/^\+//' \
            | grep -E "$joined" || true)
}

mode="${1:-staged}"
case "$mode" in
  --range)
    shift
    rng="${1:?--range needs A..B}"
    # Scan every blob the push would INTRODUCE (objects reachable in the range), not the net endpoint
    # diff. A secret added in one pushed commit and removed in a later one is absent from both endpoint
    # trees, yet its blob still ships to the remote and stays recoverable — `git diff A..B` would miss
    # it. rng is a commit range (A..B) or rev-list args (a first push passes "<tip> --not --remotes"),
    # so word-splitting is intentional. Blobs already on the far side of the range are excluded, so this
    # scans only what is actually being pushed. -I skips binary; grep -n gives the real file line.
    while IFS=' ' read -r otype osha opath; do
      [ "$otype" = blob ] || continue
      while IFS= read -r hit; do
        records+="$opath:$hit"$'\n'
      done < <(git cat-file blob "$osha" 2>/dev/null | grep -nIE "$joined" || true)
    done < <(
      # shellcheck disable=SC2086  # rng intentionally word-split into rev-list args
      git rev-list --objects $rng 2>/dev/null \
        | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' 2>/dev/null || true
    )
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
    entry="${entry%$'\r'}"                 # tolerate a CRLF-saved allowlist (strip trailing CR)
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
