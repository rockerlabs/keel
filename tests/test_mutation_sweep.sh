#!/usr/bin/env bash
# test_mutation_sweep.sh — tools/self/mutation-sweep.sh (dir #745, A1b): the re-runnable mutation sweep, driven
# in the lib.sh sandbox on a scratch git repo — one file, a three-assertion test script that prints
# `<name>: N passed, M failed`, and a list with one mutant of each outcome. The tool and its `--check` mode are
# keel-self-maintenance; this file is also what keeps tools/self/doctor.sh's coverage ratchet (dir #142) green
# for it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

sweep="$REPO_ROOT/tools/self/mutation-sweep.sh"
check_file "tools/self/mutation-sweep.sh exists" "$sweep"

if ! command -v perl >/dev/null 2>&1; then
  pass "perl not available — mutation-sweep tests skipped (the sweep's timeout is a perl alarm)"
  summary; exit $?
fi

sweeptmp="$SANDBOX/sweeptmp"
mkdir -p "$sweeptmp"

# The fixture test script: three assertions on app.sh, a TIMEOUT trap (loops when loop_marker=yes), a CRASHED trap
# (exits before its summary when exit_marker=yes). `d=4` and `t=` are deliberately NOT asserted on, so a mutant of
# `d=4` survives.
fixture_test() {
  cat <<'EOS'
#!/usr/bin/env bash
p=0; f=0
chk() { if grep -q "$1" app.sh; then p=$((p + 1)); else f=$((f + 1)); fi; }
chk 'a=1'
chk 'b=2'
chk 'c=3'
if grep -q 'loop_marker=yes' app.sh; then while :; do :; done; fi
if grep -q 'exit_marker=yes' app.sh; then exit 3; fi
echo "t.sh: $p passed, $f failed"
EOS
}
# A fixture repo: prints its path. $1 = the test script's text (default: fixture_test).
mkfixture() {
  local d script="${1:-}"
  d="$(new_repo)"
  printf 'a=1\nb=2\nc=3\nd=4\nloop_marker=no\nexit_marker=no\ntab: x\ty\n' >"$d/app.sh"
  if [ -n "$script" ]; then printf '%s\n' "$script" >"$d/t.sh"; else fixture_test >"$d/t.sh"; fi
  git -C "$d" add app.sh t.sh
  git -C "$d" commit -qm fixture
  printf '%s' "$d"
}
# row ID FILE NEEDLE REPL NOTE — one TSV row, fields verbatim (printf %s keeps a literal \t two characters).
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
# sweep_in DIR ARGS… → OUT, STATUS (stdout + stderr merged)
sweep_in() {
  local dir="$1"; shift
  OUT="$(cd "$dir" && env TMPDIR="$sweeptmp" KEEL_SWEEP_TIMEOUT="${KEEL_SWEEP_TIMEOUT:-2}" bash "$sweep" "$@" 2>&1 </dev/null)"
  STATUS=$?
}
TAB="$(printf '\t')"

fx="$(mkfixture)"
{
  row m-killed app.sh 'a=1' 'a=9' 'asserted line'
  row m-survived app.sh 'd=4' 'd=5' 'unasserted line'
  row m-bad app.sh 'no such text' 'x' 'needle absent'
  row m-nochange app.sh 'c=3' 'c=3' 'replacement equals needle'
  row m-timeout app.sh 'loop_marker=no' 'loop_marker=yes' 'makes the test loop'
  row m-crashed app.sh 'exit_marker=no' 'exit_marker=yes' 'makes the test exit before its summary'
} >"$SANDBOX/all.tsv"
{ echo '# a comment, then a blank line'; echo; cat "$SANDBOX/all.tsv"; } >"$SANDBOX/all-commented.tsv"

# --- 1. one mutant of each outcome -----------------------------------------------------------------------------------
sweep_in "$fx" "$SANDBOX/all-commented.tsv" t.sh
check_status "all six outcomes: exit 1 (a survivor and two bad rows)" 1 "$STATUS"
check_contains "KILLED line: id, outcome, the suite's summary" "$OUT" "m-killed${TAB}KILLED${TAB}t.sh: 2 passed, 1 failed"
check_contains "SURVIVED line carries a zero-failure summary" "$OUT" "m-survived${TAB}SURVIVED${TAB}t.sh: 3 passed, 0 failed"
check_contains "BADNEEDLE line: third field '-'" "$OUT" "m-bad${TAB}BADNEEDLE${TAB}-"
check_contains "NOCHANGE line: third field '-'" "$OUT" "m-nochange${TAB}NOCHANGE${TAB}-"
check_contains "TIMEOUT line (a mutant that makes the test loop)" "$OUT" "m-timeout${TAB}TIMEOUT${TAB}-"
check_contains "CRASHED line (a mutant that exits before the summary)" "$OUT" "m-crashed${TAB}CRASHED${TAB}-"
last="$(tail -n 1 <<<"$OUT")"
check_eq "the total line" "1 killed, 1 survived, 1 timeout, 1 crashed, 2 bad" "$last"
check_eq "the sweep leaves the checkout's tree untouched" "" "$(git -C "$fx" status --porcelain)"
check_eq "the clone is removed at exit" "" "$(ls "$sweeptmp")"

# --- 2. without the survivor and the two bad rows: exit 0 -----------------------------------------------------------
{ row m-killed app.sh 'a=1' 'a=9' 'asserted line'
  row m-timeout app.sh 'loop_marker=no' 'loop_marker=yes' 'makes the test loop'
  row m-crashed app.sh 'exit_marker=no' 'exit_marker=yes' 'makes the test exit before its summary'
} >"$SANDBOX/ok.tsv"
sweep_in "$fx" "$SANDBOX/ok.tsv" t.sh
check_status "no survivor, no bad row (TIMEOUT and CRASHED are not survivors): exit 0" 0 "$STATUS"
check_eq "…and its total line" "1 killed, 0 survived, 1 timeout, 1 crashed, 0 bad" "$(tail -n 1 <<<"$OUT")"

# --- 3. a tracked change to a file the list names → refuse (exit 2); untracked files are ignored ----------------------
row m-killed app.sh 'a=1' 'a=9' 'asserted line' >"$SANDBOX/one.tsv"
printf 'extra\n' >>"$fx/app.sh"
sweep_in "$fx" "$SANDBOX/one.tsv" t.sh
check_status "an unstaged tracked change to the swept file: exit 2" 2 "$STATUS"
check_contains "…and the refusal names the file" "$OUT" "app.sh"
git -C "$fx" add app.sh
sweep_in "$fx" "$SANDBOX/one.tsv" t.sh
check_status "a staged-only change: exit 2" 2 "$STATUS"
git -C "$fx" reset -q --hard HEAD
printf 'x\n' >"$fx/untracked.txt"
sweep_in "$fx" "$SANDBOX/one.tsv" t.sh
check_status "an untracked file does not block the sweep" 0 "$STATUS"
printf 'x\n' >>"$fx/t.sh"
sweep_in "$fx" "$SANDBOX/one.tsv" t.sh
check_status "a tracked change to the TEST file: exit 2" 2 "$STATUS"
git -C "$fx" checkout -q -- t.sh

# --- 4. the good sample / the bad sample: remove the killed mutant's guarding assertion → that line flips to SURVIVED -
weak="$(fixture_test | grep -v "chk 'a=1'")"
fxw="$(mkfixture "$weak")"
sweep_in "$fxw" "$SANDBOX/one.tsv" t.sh
check_status "the weakened fixture suite no longer kills the mutant: exit 1" 1 "$STATUS"
check_contains "…the line flips to SURVIVED" "$OUT" "m-killed${TAB}SURVIVED${TAB}t.sh: 2 passed, 0 failed"

# --- 5. an unmutated baseline that fails or never finishes aborts (exit 2) -----------------------------------------------
fxf="$(mkfixture "$(fixture_test | sed 's/^chk .c=3.$/chk "c=NOPE"/')")"
sweep_in "$fxf" "$SANDBOX/one.tsv" t.sh
check_status "a fixture test that fails unmutated: exit 2 (abort)" 2 "$STATUS"
check_contains "…and says the baseline is broken" "$OUT" "broken baseline"
fxl="$(mkfixture 'while :; do :; done')"
KEEL_SWEEP_TIMEOUT=1 sweep_in "$fxl" "$SANDBOX/one.tsv" t.sh
check_status "a baseline run past KEEL_SWEEP_TIMEOUT: exit 2 (abort)" 2 "$STATUS"
check_contains "…and says it timed out" "$OUT" "timed out"
fxn="$(mkfixture 'echo no summary here')"
sweep_in "$fxn" "$SANDBOX/one.tsv" t.sh
check_status "a baseline with no summary line: exit 2 (abort)" 2 "$STATUS"

# --- 6. \t decodes to a real TAB in the needle and the replacement -------------------------------------------------------
tabtest="$(fixture_test | sed '$d'; printf '%s\n' 'if grep -q "x$(printf '"'"'\t'"'"')y" app.sh; then p=$((p + 1)); else f=$((f + 1)); fi' 'echo "t.sh: $p passed, $f failed"')"
fxt="$(mkfixture "$tabtest")"
row m-tab app.sh 'x\ty' 'x\tz' 'a needle written with \t matches a real TAB' >"$SANDBOX/tab.tsv"
sweep_in "$fxt" "$SANDBOX/tab.tsv" t.sh
check_contains "a needle written with \\t matches a real TAB in the fixture (and the TAB-guarding assertion kills it)" "$OUT" "m-tab${TAB}KILLED"
row m-nl app.sh 'a=1\nb=2' 'a=1\nb=3' 'a needle written with \n spans two lines' >"$SANDBOX/nl.tsv"
sweep_in "$fx" "$SANDBOX/nl.tsv" t.sh
check_contains "a needle written with \\n spans two lines" "$OUT" "m-nl${TAB}KILLED"
row m-bs app.sh 'a\\' 'b' 'a doubled backslash decodes to one' >"$SANDBOX/bs.tsv"
sweep_in "$fx" "$SANDBOX/bs.tsv" t.sh
check_contains "\\\\ decodes to one backslash (no such text → BADNEEDLE)" "$OUT" "m-bs${TAB}BADNEEDLE"
row m-del app.sh 'd=4' '' 'a deletion mutant' >"$SANDBOX/del.tsv"
sweep_in "$fx" "$SANDBOX/del.tsv" t.sh
check_contains "an empty replacement is a deletion mutant (the file changes)" "$OUT" "m-del${TAB}SURVIVED"

# --- 7. a needle that occurs twice is BADNEEDLE ---------------------------------------------------------------------------
row m-twice app.sh '=' 'X' 'occurs more than once' >"$SANDBOX/twice.tsv"
sweep_in "$fx" "$SANDBOX/twice.tsv" t.sh
check_contains "a needle occurring more than once: BADNEEDLE" "$OUT" "m-twice${TAB}BADNEEDLE${TAB}-"
check_contains "…and the reason names the count on stderr" "$OUT" "occurs"

# --- 7b. a row naming a tracked symlink (or a file under one) is BADNEEDLE: the write would leave the clone ---------------
mkdir -p "$SANDBOX/outside"
printf 'a=1\n' >"$SANDBOX/outside/target.txt"
outside_before="$(cksum <"$SANDBOX/outside/target.txt")"
fxs="$(mkfixture)"
ln -s "$SANDBOX/outside/target.txt" "$fxs/link.sh"
ln -s "$SANDBOX/outside" "$fxs/ldir"
git -C "$fxs" add link.sh ldir
git -C "$fxs" commit -qm links
{ row m-link link.sh 'a=1' 'a=9' 'a leaf symlink'; row m-dirlink ldir/target.txt 'a=1' 'a=9' 'under a symlinked directory'; } >"$SANDBOX/link.tsv"
sweep_in "$fxs" "$SANDBOX/link.tsv" t.sh
check_contains "a tracked symlink: BADNEEDLE" "$OUT" "m-link${TAB}BADNEEDLE${TAB}-"
check_contains "a file under a tracked symlinked directory: BADNEEDLE" "$OUT" "m-dirlink${TAB}BADNEEDLE${TAB}-"
check_contains "…and the reason names the symlink" "$OUT" "lies under, a symlink"
check_eq "nothing outside the clone was written" "$outside_before" "$(cksum <"$SANDBOX/outside/target.txt")"
sweep_in "$fxs" --check "$SANDBOX/link.tsv"
check_status "--check agrees with the sweep: exit 1 on both symlink rows" 1 "$STATUS"
check_contains "…naming the leaf symlink" "$OUT" "m-link: link.sh is, or lies under, a symlink"
check_contains "…and the directory one" "$OUT" "m-dirlink: ldir/target.txt is, or lies under, a symlink"
# a link deeper than the first component, and a doubled slash that must not hide one
mkdir "$fxs/sub"
ln -s "$SANDBOX/outside" "$fxs/sub/dl"
git -C "$fxs" add sub/dl
git -C "$fxs" commit -qm nested
{ row m-nested sub/dl/target.txt 'a=1' 'a=9' 'a link on the second component'; row m-double ldir//target.txt 'a=1' 'a=9' 'a doubled slash'; } >"$SANDBOX/nested.tsv"
sweep_in "$fxs" "$SANDBOX/nested.tsv" t.sh
check_contains "a symlink on the SECOND path component: BADNEEDLE" "$OUT" "m-nested${TAB}BADNEEDLE${TAB}-"
check_contains "…named by id and file" "$OUT" "m-nested: sub/dl/target.txt is, or lies under, a symlink"
check_contains "a doubled slash does not hide the link: BADNEEDLE" "$OUT" "m-double${TAB}BADNEEDLE${TAB}-"
check_eq "…and still nothing outside the clone was written" "$outside_before" "$(cksum <"$SANDBOX/outside/target.txt")"

# --- 7c. overlapping occurrences count: `aa` in `aaa` is two matches, not one ------------------------------------------
printf 'aaa\n' >"$fx/over.txt"
git -C "$fx" add over.txt
git -C "$fx" commit -qm over
row m-over over.txt 'aa' 'bb' 'overlapping' >"$SANDBOX/over.tsv"
sweep_in "$fx" --check "$SANDBOX/over.tsv"
check_status "--check: a needle matching at two overlapping offsets is not 'exactly once'" 1 "$STATUS"
check_contains "…it occurs twice" "$OUT" "m-over: needle occurs 2 times in over.txt, want 1"

# --- 8. usage, refusals --------------------------------------------------------------------------------------------------
sweep_in "$fx"
check_status "no arguments: usage, exit 2" 2 "$STATUS"
sweep_in "$fx" "$SANDBOX/no-such-list.tsv"
check_status "a missing list: exit 2" 2 "$STATUS"
KEEL_SWEEP_TIMEOUT=abc sweep_in "$fx" "$SANDBOX/one.tsv" t.sh
check_status "a non-numeric KEEL_SWEEP_TIMEOUT: exit 2" 2 "$STATUS"
row m-abs /etc/passwd 'a' 'b' 'an absolute path' >"$SANDBOX/abs.tsv"
sweep_in "$fx" "$SANDBOX/abs.tsv" t.sh
check_status "a list naming an absolute path: exit 2" 2 "$STATUS"
row m-dots ../x 'a' 'b' 'a parent path' >"$SANDBOX/dots.tsv"
sweep_in "$fx" "$SANDBOX/dots.tsv" t.sh
check_status "a list naming a .. path: exit 2" 2 "$STATUS"
sweep_in "$fx" --check "$SANDBOX/abs.tsv"
check_contains "--check applies the same path rule (absolute)" "$OUT" "m-abs: /etc/passwd must be a path relative to the top level without '..'"
sweep_in "$fx" --check "$SANDBOX/dots.tsv"
check_contains "--check applies the same path rule (..)" "$OUT" "m-dots: ../x must be a path relative to the top level without '..'"
sweep_in "$fx" "$SANDBOX/one.tsv" no-such-test.sh
check_status "a missing test file: exit 2" 2 "$STATUS"
printf 'm-four\tapp.sh\ta=1\ta=9\n' >"$SANDBOX/four.tsv"
sweep_in "$fx" "$SANDBOX/four.tsv" t.sh
check_contains "a four-field row is BADNEEDLE" "$OUT" "m-four${TAB}BADNEEDLE"
: >"$SANDBOX/empty.tsv"
sweep_in "$fx" "$SANDBOX/empty.tsv" t.sh
check_status "a list with no rows: exit 2 (nothing to sweep)" 2 "$STATUS"

# --- 9. --check: the list is current against the working tree (no test run) -------------------------------------------
sweep_in "$fx" --check "$SANDBOX/ok.tsv"
check_status "--check on a sound list: exit 0" 0 "$STATUS"
check_eq "…and prints nothing" "" "$OUT"
sweep_in "$fx" --check "$SANDBOX/all.tsv"
check_status "--check on a list with a missing needle: exit 1" 1 "$STATUS"
check_contains "…naming the row and the count" "$OUT" "m-bad: needle occurs 0 times in app.sh, want 1"
check_contains "…and a replacement equal to its needle" "$OUT" "m-nochange: replacement equals needle"
sweep_in "$fx" --check
check_status "--check without a list: exit 2" 2 "$STATUS"

summary
