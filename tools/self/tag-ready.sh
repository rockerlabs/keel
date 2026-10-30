#!/usr/bin/env bash
# tools/self/tag-ready.sh — keel-self-maintenance (dir #68): the pre-tag gate on a placeholder marker (dir #867).
# A cut PR may carry a `[PLACEHOLDER` marker in docs/release-history.md until the audit's GO record fills it
# (the 0.16.0 cut commit did), so no suite leg can reject it. The person who tags runs this on the exact
# commit about to be tagged (docs/release-audit.md Phase 7).
#
# Usage:
#   tools/self/tag-ready.sh [REV]      REV defaults to HEAD; run it from inside the repo
#   tools/self/tag-ready.sh -h | --help
#
# Reads COMMITTED content at REV (`git grep` on the tree, never the working copy) and fails while a
# `[PLACEHOLDER` marker (case-insensitive, fixed string) stands in docs/release-history.md or CHANGELOG.md.
# Exit 0 clean. Exit 1 a marker stands: each hit is printed as `path:line:text`. Exit 2 refused: a bad
# argument, not a git work tree, REV does not resolve, one of the two files is absent at REV, or git grep
# itself failed (it cannot say the tree is clean). Nothing is written. It tags nothing.
# So the gate cannot trip on its own description: never spell the marker with its opening bracket in those
# two files.
set -euo pipefail
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

marker='[PLACEHOLDER'
files=(docs/release-history.md CHANGELOG.md)

case "${1:-}" in
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  -*) printf 'tag-ready: unknown option %s\n' "$1" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { printf 'tag-ready: at most one REV\n' >&2; exit 2; }
rev=HEAD; [ "$#" -eq 1 ] && rev="$1"

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || { printf 'tag-ready: not inside a git work tree\n' >&2; exit 2; }
commit="$(git rev-parse --verify --quiet "$rev^{commit}")" || { printf 'tag-ready: %s is not a commit\n' "$rev" >&2; exit 2; }
for f in "${files[@]}"; do
  git cat-file -e "$commit:$f" 2> /dev/null || { printf 'tag-ready: %s is absent at %s; refusing to pass on a missing file\n' "$f" "$rev" >&2; exit 2; }
done

grc=0
hits="$(git grep -n -i -F -e "$marker" "$commit" -- "${files[@]}")" || grc=$?
[ "$grc" -le 1 ] || { printf 'tag-ready: git grep failed (exit %s); cannot say the tree is clean\n' "$grc" >&2; exit 2; }
if [ -n "$hits" ]; then
  printf 'tag-ready: a %s marker stands at %s; fill it from the audit GO record before tagging:\n' "$marker" "$rev" >&2
  printf '%s\n' "${hits//$commit:/}"
  exit 1
fi
printf 'tag-ready: no %s marker in %s at %s\n' "$marker" "${files[*]}" "$rev"
