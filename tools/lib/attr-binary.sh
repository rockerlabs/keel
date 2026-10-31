# shellcheck shell=bash
# tools/lib/attr-binary.sh — adopter-usable (dir #68): shared by tools/public-audit.sh and tools/self/line-citations.sh. Sourced, not executed — no shebang, no set -e (inherits the caller's). Bash 3.2 + `set -u` safe.
#
# attr-binary.sh (dir #903, extracted from tools/public-audit.sh's dir #767 recipe): `git grep -I` trusts a
# tracked file's `-diff`/`binary` attribute over its bytes, so a text file under e.g. `*.svg -diff` (no NUL)
# is skipped and reads clean. A caller that greps the tracked tree with `-I` adds a second leg, `-a`, over
# the files these two functions name. The legs are disjoint: `-I` skips exactly the attribute-binary files.
# Kept here so the security-adjacent recipe has ONE copy, not one per scanner.
#
# Known limit: a `diff=<driver>` with `diff.<driver>.binary=true` set only in git CONFIG (not a tracked
# .gitattributes) is not seen by the `:(attr:-diff)` pathspec.

# attr_binary_list REPO [PATHSPEC…] — NUL-separated names of every tracked file marked `-diff`/`binary`,
# on stdout. Runs under -a (git drops attribute-binary files otherwise). Exit status is git grep's own:
# 0 = some, 1 = none (a normal outcome), anything else = error — the caller keeps 1 apart from the rest.
attr_binary_list() {
  local repo="$1"
  shift
  git -C "$repo" grep -l -z -a -e '' -- ':(attr:-diff)' "$@"
}

# attr_binary_nulless REPO — filter a NUL-separated name list on stdin down to the regular files (a missing
# file or a symlink is skipped) that hold no NUL byte, printed as `:(literal)<name>` pathspecs, NUL-separated
# (`:(literal)` keeps a glob-character name from widening to a sibling). A NUL-bearing file stays a binary.
attr_binary_nulless() {
  local repo="$1" f
  while IFS= LC_ALL=C read -r -d '' f; do
    [ -f "$repo/$f" ] && [ ! -L "$repo/$f" ] || continue
    if LC_ALL=C tr -d '\000' 2>/dev/null < "$repo/$f" | cmp -s - "$repo/$f" 2>/dev/null; then
      printf ':(literal)%s\0' "$f"
    fi
  done
}
