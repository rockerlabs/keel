#!/usr/bin/env bash
# test_env_census.sh — the environment gate (dir #663 (a)). A shipped script that reads a KEEL_* variable
# from the caller's environment reads the OPERATOR's value when a test runs it, unless tests/lib.sh
# neutralizes it first. Felt once (0.13.0 delta audit S2-1): the suite ran an operator-exported
# KEEL_MACHINE_WATCH_NOTIFIER on test data and 13 assertions went red. The fix there was one `unset`; this
# file closes the class, so the next variable cannot be added to a tool and forgotten here.
#
# Two halves, because neither alone binds:
#   static  — derive, from the shipped scripts, every KEEL_* name read from the environment (below);
#   runtime — export each such name with a poison value, source tests/lib.sh in a child, and assert none
#             still holds the poison (unset, or redirected into the sandbox, both pass). A textual
#             mention in lib.sh would satisfy a grep (a comment does); only the child proves the effect.
#
# Axis, named: this binds the names a script spells out literally. It does not see a name built at run
# time (`"KEEL_${x}"`), a variable read only by a tests/ helper (KEEL_TEST_JOBS, a *_SKIP_MUTATIONS
# switch — those are the suite's own knobs, not tool reads), or one a tool reads under a non-KEEL_ name.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "test-suite environment gate (dir #663 (a))"

# owns_name NAME — reads code on stdin; exit 0 when some line ASSIGNS NAME (`NAME=` at a word start, not
# inside a quoted string: an even count of double and of single quotes before it — so `echo "… (KEEL_DIR=~/x)"`
# is prose, while `( cd "$d" && KEEL_X=1 ./run )` is an assignment). \047 is the single quote, spelled so
# the awk program can stay inside this shell's own single quotes.
owns_name() {
  awk -v n="$1" '
    {
      s = $0; off = 0
      while ((i = index(s, n "=")) > 0) {
        pos = off + i
        ok = 1
        if (pos > 1 && substr($0, pos - 1, 1) ~ /[A-Za-z0-9_]/) ok = 0
        pre = substr($0, 1, pos - 1)
        dq = gsub(/"/, "&", pre); sq = gsub(/\047/, "&", pre)
        if (ok && dq % 2 == 0 && sq % 2 == 0) { found = 1; exit }
        off = pos + length(n); s = substr($0, off + 1)
      }
    }
    END { exit found ? 0 : 1 }'
}

# inherited_reads ROOT... — the KEEL_* names the shipped scripts under the given files/dirs read from the
# environment, one per line, sorted. A READ is `$KEEL_X`, `${KEEL_X…}` or `ENVIRON["KEEL_X"]` on a
# non-comment line. A file that also ASSIGNS the name (`KEEL_X=…` at a word start — a script-owned
# variable, or an inline `KEEL_X=… awk` hand-off) is not reading the caller's value; the verdict is per
# file, so a read in one file is not excused by an assignment in another.
inherited_reads() {
  local root f name
  local -a files=()
  for root in "$@"; do
    if [ -d "$root" ]; then
      while IFS= read -r f; do files+=("$f"); done < <(find "$root" -type f | LC_ALL=C sort)
    elif [ -f "$root" ]; then
      files+=("$root")
    fi
  done
  for f in ${files[@]+"${files[@]}"}; do
    # non-comment lines only, so a name that appears in prose alone is not a read
    local code; code="$(grep -avE '^[[:space:]]*#' "$f" 2>/dev/null)"
    [ -n "$code" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      printf '%s\n' "$code" | owns_name "$name" && continue
      printf '%s\n' "$name"
    done < <(printf '%s\n' "$code" \
      | grep -aoE '(\$\{?|ENVIRON\["|printenv +)KEEL_[A-Z0-9_]+' | grep -aoE 'KEEL_[A-Z0-9_]+' | LC_ALL=C sort -u)
  done | LC_ALL=C sort -u
}

# --- non-vacuity of the static half: it flags what it should, and only that, on a planted tree --------------
plant="$(mktemp -d "$SANDBOX/plant.XXXXXX")"
{
  printf '%s\n' 'x="${KEEL_PLANT_BRACE:-d}"'
  printf '%s\n' 'echo "$KEEL_PLANT_BARE"'
  printf '%s\n' "awk '{print ENVIRON[\"KEEL_PLANT_ENV\"]}'"
  printf '%s\n' '# comment: ${KEEL_PLANT_COMMENT} only here'
  printf '%s\n' 'KEEL_PLANT_OWN=1; echo "$KEEL_PLANT_OWN"'
  printf '%s\n' "KEEL_PLANT_HAND=\"\$v\" awk '{print ENVIRON[\"KEEL_PLANT_HAND\"]}'"
  printf '%s\n' 'echo "$KEEL_PLANT_SPLIT"'
  printf '%s\n' 'echo "hint (KEEL_PLANT_PROSE=x)"; echo "$KEEL_PLANT_PROSE"'
  printf '%s\n' '( cd "$d" && KEEL_PLANT_SUBSHELL=1 ./run ); echo "$KEEL_PLANT_SUBSHELL"'
} > "$plant/a.sh"
printf '%s\n' 'KEEL_PLANT_SPLIT=assigned-in-the-OTHER-file' > "$plant/b.sh"
planted="$(inherited_reads "$plant")"
check_contains "a \${…} read is flagged" "$planted" 'KEEL_PLANT_BRACE'
check_contains "a bare \$ read is flagged" "$planted" 'KEEL_PLANT_BARE'
check_contains "an ENVIRON read with no assignment is flagged" "$planted" 'KEEL_PLANT_ENV'
check_absent "a name in a comment only is not flagged" "$planted" 'KEEL_PLANT_COMMENT'
check_absent "a script-owned variable is not flagged" "$planted" 'KEEL_PLANT_OWN'
check_absent "an inline hand-off (VAR=… awk … ENVIRON) is not flagged" "$planted" 'KEEL_PLANT_HAND'
check_contains "an assignment in ANOTHER file does not excuse a read (the verdict is per file)" "$planted" 'KEEL_PLANT_SPLIT'
check_contains "an assignment spelled inside a quoted message is prose, not ownership" "$planted" 'KEEL_PLANT_PROSE'
check_absent "an assignment after a quoted word in a subshell still counts as ownership" "$planted" 'KEEL_PLANT_SUBSHELL'
check_eq "exactly the five reads are reported" 5 "$(printf '%s\n' "$planted" | grep -c .)"
check_eq "an empty root reports nothing, not an error" "" "$(inherited_reads "$SANDBOX/no-such-root")"

# --- the runtime half -----------------------------------------------------------------------------------------
POISON='/keel-env-census-poison'

# unneutralized LIB NAME... — the names still holding POISON after a child sources LIB with every one of
# them exported poisoned. Prints one per line; prints FATAL and returns 99 when LIB cannot be sourced.
unneutralized() {
  local lib="$1" n out rc; shift
  local -a envargs=()
  for n in "$@"; do envargs+=("$n=$POISON"); done
  out="$(env ${envargs[@]+"${envargs[@]}"} bash -c '
    . "$1" || exit 99
    shift
    for v in "$@"; do
      [ "${!v-__unset__}" = "'"$POISON"'" ] && printf "%s\n" "$v"
    done
    exit 0' _ "$lib" "$@" 2>&1)"
  rc=$?
  printf '%s' "$out"
  return "$rc"
}

# non-vacuity of the runtime half: a lib that neutralizes nothing, then one that neutralizes one name
nolib="$(mktemp -d "$SANDBOX/nolib.XXXXXX")"
printf '%s\n' 'SANDBOX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; unset KEEL_PLANT_BRACE' > "$nolib/lib.sh"
res="$(unneutralized "$nolib/lib.sh" KEEL_PLANT_BRACE KEEL_PLANT_BARE)"
check_eq "a lib that unsets only one name leaves exactly the other one poisoned" "KEEL_PLANT_BARE" "$res"
printf '%s\n' 'export KEEL_PLANT_BARE=/somewhere/else' >> "$nolib/lib.sh"
check_eq "a lib that exports a different value counts as neutralized" "" "$(unneutralized "$nolib/lib.sh" KEEL_PLANT_BRACE KEEL_PLANT_BARE)"
printf '%s\n' 'return 7' > "$nolib/broken.sh"
unneutralized "$nolib/broken.sh" KEEL_PLANT_BRACE >/dev/null; rc=$?
check_ne "a lib that fails to source is a hard failure, not a clean 'nothing poisoned'" "$rc" 0

# --- the real tree --------------------------------------------------------------------------------------------
names="$(inherited_reads "$REPO_ROOT/tools" "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" \
  "$REPO_ROOT/bootstrap.sh" "$REPO_ROOT/keel")"
count="$(printf '%s\n' "$names" | grep -c .)"
# anchors: names tests/lib.sh handled BEFORE this gate existed — a scanner that cannot see them is blind
for anchor in KEEL_HOME KEEL_IMPACT_LOG KEEL_MACHINE_WATCH_NOTIFIER KEEL_LEDGER_FILE; do
  check_contains "the scan sees $anchor (so it is not vacuous on the real tree)" "$names" "$anchor"
done
check_ne "the scan found KEEL_* reads at all" "$count" 0

# shellcheck disable=SC2086  # word-splitting the newline-separated names is the point
leaked="$(unneutralized "$TESTS_DIR/lib.sh" $names)"; rc=$?
check_eq "sourcing lib.sh succeeds in the poisoned child" 0 "$rc"
if [ -z "$leaked" ]; then
  pass "every KEEL_* a shipped script reads from the environment is neutralized by tests/lib.sh ($count names)"
else
  fail "every KEEL_* a shipped script reads from the environment is neutralized by tests/lib.sh ($count names)" \
    "tests/lib.sh leaves an operator's value of these reaching the suite — add each to its unset block, or give it a sandbox default:
$leaked"
fi

# --- mutation proof: drop ONE name from a scratch copy of lib.sh and the gate must name exactly it ------------
SCRATCH_COPY_PREFIX=envcensus
victim=KEEL_CHECK_VETO
check_contains "the mutation victim ($victim) is one of the derived names" "$names" "$victim"
mut_lib="$(scratch_copy "$TESTS_DIR/lib.sh" lib.sh)"
delete_line_containing "$mut_lib" "$victim"
check_ne "the edit changed the copy of lib.sh" "$(cksum < "$mut_lib")" "$(cksum < "$TESTS_DIR/lib.sh")"
# shellcheck disable=SC2086
res="$(unneutralized "$mut_lib" $names)"
check_eq "lib.sh minus its $victim line: the gate reports $victim, and only it" "$victim" "$res"

summary
