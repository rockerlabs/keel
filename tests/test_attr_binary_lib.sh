#!/usr/bin/env bash
# test_attr_binary_lib.sh — tools/lib/attr-binary.sh (dir #767 follow-up): the listing of tracked files a
# `-diff`/`binary` attribute marks binary (attr_nd_list) and the NUL-less filter that turns them into
# `:(literal)` pathspecs (attr_nd_filter). Its two consumers, tools/public-audit.sh and
# tools/self/line-citations.sh, are pinned at the source level, as test_fence_blank_lib.sh does for its lib.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/attr-binary.sh"
check_file "tools/lib/attr-binary.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

# specs DIR — the filtered pathspecs, one per line (NUL turned into a newline).
specs() { attr_nd_list "$1" | attr_nd_filter "$1" | tr '\0' '\n'; }

d="$(new_repo)"
printf 'plain\n' > "$d/p.txt"
( cd "$d" && git add -A && git commit -q -m plain )
rc=0; attr_nd_list "$d" >/dev/null || rc=$?
check_eq "no attribute-binary file: the listing exits 1 (none), not an error" "1" "$rc"
check_eq "and the filter yields nothing" "" "$(specs "$d")"

printf '*.svg -diff\n*.dat binary\n' > "$d/.gitattributes"
printf '<svg/>\n' > "$d/a.svg"
printf 'x\0y\n' > "$d/nul.svg"
printf 'data\n' > "$d/b.dat"
printf '<svg/>\n' > "$d/*.svg"
mkdir -p "$d/sub"; printf '<svg/>\n' > "$d/sub/c.svg"
ln -s a.svg "$d/link.svg"
( cd "$d" && git add -A && git commit -q -m attrs )
rc=0; attr_nd_list "$d" >/dev/null || rc=$?
check_eq "attribute-binary files present: the listing exits 0" "0" "$rc"
out="$(specs "$d")"
check_contains "a NUL-less -diff file is kept as a :(literal) pathspec" "$out" ":(literal)a.svg"
check_contains "the 'binary' macro counts as -diff" "$out" ":(literal)b.dat"
check_contains "a file in a subdirectory keeps its path" "$out" ":(literal)sub/c.svg"
check_contains "a glob-character name is kept literally" "$out" ":(literal)*.svg"
check_absent "a NUL-bearing file stays a binary" "$out" "nul.svg"
check_absent "a symlink is skipped" "$out" "link.svg"
check_absent "a file with no such attribute is not listed" "$out" "p.txt"

rm "$d/b.dat"
check_absent "a tracked file missing from the work tree is skipped" "$(specs "$d")" "b.dat"

check_absent "an extra pathspec is passed through (an exclude drops its file)" "$(attr_nd_list "$d" ':(exclude)a.svg' | tr '\0' '\n')" "a.svg"
rc=0; attr_nd_list "$SANDBOX/not-a-repo" >/dev/null 2>&1 || rc=$?
if [ "$rc" -gt 1 ]; then pass "a git failure is neither exit 0 nor 1 (the caller reports it)"
else fail "a git failure is neither exit 0 nor 1 (the caller reports it)" "got $rc"; fi

# --- the consumers source it ---------------------------------------------------------------------
check_contains "public-audit.sh sources the lib" "$(cat "$REPO_ROOT/tools/public-audit.sh")" 'lib/attr-binary.sh'
check_contains "line-citations.sh sources the lib" "$(cat "$REPO_ROOT/tools/self/line-citations.sh")" 'lib/attr-binary.sh'

summary
