# shellcheck shell=bash
# tools/lib/attr-binary.sh — the tracked files a `-diff`/`binary` gitattribute marks binary though their bytes
# hold no NUL (dir #904, follow-up of dir #767). `git grep -I` trusts the attribute over the bytes and
# skips such a file (e.g. `*.svg -diff`), so a tree grep run with -I reads it as clean. A caller runs its
# -I grep over the tree, then a second `-a` grep over attr_nd_filter's pathspecs; the two legs are disjoint.
#
# Sourced, not executed — no shebang, no `set -e` (inherits the caller's). Two steps, so the caller keeps its
# own error reporting around the git call (public-audit.sh's pa_match, line-citations.sh's exit 2):
#   attr_nd_list DIR [PATHSPEC…] > LIST        every tracked file with `diff` unset, NUL-separated. The
#       listing runs under -a (git drops attribute-binary files otherwise). Status 0 = some, 1 = none (a normal
#       outcome), other = a git failure (stderr untouched).
#   attr_nd_filter DIR < LIST > PATHSPECS      of those, the regular files (not a symlink, not missing) with no
#       NUL byte, as `:(literal)<name>` pathspecs, NUL-separated. A NUL-bearing file stays a binary. `:(literal)`
#       keeps a glob-character name from widening to a sibling. Always status 0.
# Read the result into an array with `read -r -d ''`; guard `${#arr[@]}` before expanding it (bash 3.2 + `set
# -u`: an empty array is unbound). Known limit: a `diff=<driver>` with `diff.<driver>.binary=true` set only in
# git CONFIG (not a tracked file) is not seen.
attr_nd_list() {
  local dir="$1"
  shift
  git -C "$dir" grep -l -z -a -e '' -- ':(attr:-diff)' "$@"
}
attr_nd_filter() {
  local dir="$1" f
  while IFS= LC_ALL=C read -r -d '' f; do
    [ -f "$dir/$f" ] && [ ! -L "$dir/$f" ] || continue
    if LC_ALL=C tr -d '\000' < "$dir/$f" 2>/dev/null | cmp -s - "$dir/$f" 2>/dev/null; then
      printf ':(literal)%s\0' "$f"
    fi
  done
  return 0
}
