#!/usr/bin/env bash
# test_attr_binary_lib.sh — dir #903: the `:(attr:-diff)` listing and the NUL test live in
# tools/lib/attr-binary.sh, shared by tools/public-audit.sh (dir #767) and tools/self/line-citations.sh.
# Pin the SOURCE level (both consumers source the lib; no second copy of the recipe), then the lib itself.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/attr-binary.sh"
check_file "tools/lib/attr-binary.sh exists" "$lib"
check_contains "public-audit.sh sources the lib" "$(cat "$REPO_ROOT/tools/public-audit.sh")" 'lib/attr-binary.sh'
check_contains "line-citations.sh sources the lib" "$(cat "$REPO_ROOT/tools/self/line-citations.sh")" 'lib/attr-binary.sh'
hits="$(grep -rlF ':(attr:-diff)' "$REPO_ROOT/tools" 2>/dev/null | grep -vF "$lib" || true)"
if [ -z "$hits" ]; then
  pass "no second copy of the attribute-binary listing outside the lib"
else
  fail "no second copy of the attribute-binary listing outside the lib" "found in: $hits"
fi

# shellcheck source=/dev/null
. "$lib"
d="$(new_repo)"
printf '*.svg -diff\n' > "$d/.gitattributes"
printf 'text\n' > "$d/t.svg"
printf 'a\000b\n' > "$d/n.svg"
printf 'x\n' > "$d/g[1].svg"
printf 'plain\n' > "$d/p.txt"
( cd "$d" && git add -A && git commit -q -m fixture )
rc=0; attr_binary_list "$d" > "$d/../nd.list" || rc=$?
check_status "attr_binary_list -> 0 when some file is attribute-binary" 0 "$rc"
out="$(attr_binary_nulless "$d" < "$d/../nd.list" | tr '\0' '\n' | LC_ALL=C sort)"
check_contains "keeps the NUL-less file" "$out" ':(literal)t.svg'
check_contains "keeps a glob-character name literally" "$out" ':(literal)g[1].svg'
case "$out" in *n.svg*) fail "drops the NUL-bearing file" "$out" ;; *) pass "drops the NUL-bearing file" ;; esac
case "$out" in *p.txt*) fail "ignores a plain text file" "$out" ;; *) pass "ignores a plain text file" ;; esac
d2="$(new_repo)"
printf 'x\n' > "$d2/p.txt"
( cd "$d2" && git add -A && git commit -q -m fixture )
rc=0; attr_binary_list "$d2" > /dev/null || rc=$?
check_status "attr_binary_list -> 1 when none (no match, not an error)" 1 "$rc"

summary
