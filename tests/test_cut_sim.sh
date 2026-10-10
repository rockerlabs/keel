#!/usr/bin/env bash
# tools/self/cut-sim.sh (dir #744 slice 4, B18 / dir #722): run the suite on the CUT shape. The tool clones a
# repo's HEAD, runs the clone's changelog-cut.sh with 9999.0.0 and today's UTC date, commits that in the clone
# under a fixed identity and runs the clone's tests/run.sh. These cases drive it against small fixture repos
# (their own tests/run.sh stands in for the suite): a test that reads only the whole CHANGELOG passes, a test
# that pins a current [Unreleased] bullet fails, the source repo is byte-identical after both, the clone is
# gone on every exit path, and a tagless source is refused (exit 2) naming fetch-depth: 0.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

sim="$REPO_ROOT/tools/self/cut-sim.sh"
check_file "tools/self/cut-sim.sh exists" "$sim"

# The clones land under $TMPDIR; point it at a private dir so "no clone left behind" is checkable.
tmproot="$SANDBOX/simtmp"; mkdir -p "$tmproot"

# mk_src TESTBODY — a fixture repo with a CHANGELOG.md ([Unreleased] holds one legacy bullet, a fragment
# adds another), the real cut tool and its libs, a tests/run.sh that runs one test file whose body is
# TESTBODY, and a v1.0.0 tag. Prints its path.
mk_src() {
  local d; d="$(mktemp -d "$SANDBOX/src.XXXXXX")"
  mkdir -p "$d/tools/self" "$d/tools/lib" "$d/tests" "$d/changelog.d"
  cp "$REPO_ROOT/tools/self/changelog-cut.sh" "$REPO_ROOT/tools/self/changelog-fragments.sh" "$d/tools/self/"
  cp "$REPO_ROOT"/tools/lib/fence-blank.sh "$d/tools/lib/"
  printf '# Changelog\n\n## [Unreleased]\n\n- legacy bullet\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' > "$d/CHANGELOG.md"
  printf '# readme\n' > "$d/changelog.d/README.md"
  printf '%s\n' '- dir #1: a fragment bullet' > "$d/changelog.d/1-a.md"
  printf '#!/usr/bin/env bash\nexec bash "$(dirname "$0")/test_x.sh"\n' > "$d/tests/run.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$d/tests/test_x.sh"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.name=fx -c user.email=fx@example.invalid commit -qm seed
  git -C "$d" tag v1.0.0
  printf '%s' "$d"
}
# snap DIR — tracked content + status + HEAD, to prove the source is untouched.
snap() { printf '%s\n%s\n%s\n' "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" status --porcelain)" "$(cat "$1/CHANGELOG.md")"; }

run "$sim" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$sim" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$sim" --repo /no/such/dir
check_status "missing --repo directory -> exit 2" 2 "$STATUS"

# --- PASS: the test reads the whole file, as a cut-safe test must -----------------------------------
pass_src="$(mk_src 'grep -q "legacy bullet" CHANGELOG.md')"
before="$(snap "$pass_src")"
run env TMPDIR="$tmproot" bash "$sim" --repo "$pass_src"
check_status "a cut-safe suite -> exit 0" 0 "$STATUS"
check_contains "...prints PASS" "$OUT" "cut-sim (dir #722): the suite on the cut shape: PASS"
check_eq "...and the source repo is unchanged" "$before" "$(snap "$pass_src")"
check_eq "...and the clone is removed" "" "$(ls -A "$tmproot")"

# --- FAIL: the test pins the CURRENT [Unreleased] bullet, which the cut moves ------------------------
fail_src="$(mk_src 'awk "/^## \[Unreleased\]/{p=1;next} /^## \[/{p=0} p" CHANGELOG.md | grep -q "legacy bullet"')"
before="$(snap "$fail_src")"
run env TMPDIR="$tmproot" bash "$sim" --repo "$fail_src"
check_status "a suite pinning [Unreleased] -> exit 1" 1 "$STATUS"
check_contains "...prints FAIL" "$OUT" "cut-sim (dir #722): the suite on the cut shape: FAIL"
check_eq "...and the source repo is unchanged" "$before" "$(snap "$fail_src")"
check_eq "...and the clone is removed" "" "$(ls -A "$tmproot")"

# --- the clone really holds the CUT shape, committed, under the fixed identity ----------------------
probe_src="$(mk_src 'grep -q "^## \[9999.0.0\] — $(date -u +%Y-%m-%d)$" CHANGELOG.md && [ ! -e changelog.d/1-a.md ] && [ -z "$(git status --porcelain)" ] && [ "$(git log -1 --format=%an:%ae)" = "keel-cut-sim:cut-sim@example.invalid" ]')"
run env TMPDIR="$tmproot" bash "$sim" --repo "$probe_src"
check_status "the clone has a committed 9999.0.0 section dated today (UTC), no fragments, the cut-sim author" 0 "$STATUS"

# --- a signal removes the clone too ----------------------------------------------------------------
sig_src="$(mk_src 'exec sleep 61')"
env TMPDIR="$tmproot" bash "$sim" --repo "$sig_src" >/dev/null 2>&1 &
sim_pid=$!
n=0
while [ -z "$(ls -A "$tmproot")" ] && [ "$n" -lt "${KEEL_TEST_HANG_BOUND:-120}" ]; do sleep 1; n=$((n + 1)); done
check_nonempty_dir=""
[ -n "$(ls -A "$tmproot")" ] && check_nonempty_dir=1
check_eq "(fixture) the clone exists while the suite runs" "1" "$check_nonempty_dir"
kill -TERM "$sim_pid" 2>/dev/null || true
n=0
while kill -0 "$sim_pid" 2>/dev/null && [ "$n" -lt "${KEEL_TEST_HANG_BOUND:-120}" ]; do sleep 1; n=$((n + 1)); done
wait "$sim_pid" 2>/dev/null || true
# The fixture suite is exec'd all the way down to the sleep, so the tool's TERM reaches it directly.
check_eq "a TERM removes the clone" "" "$(ls -A "$tmproot")"

# --- refusals: no v* tag (a shallow/tagless checkout), not a git repo --------------------------------
notag_src="$(mk_src 'true')"
git -C "$notag_src" tag -d v1.0.0 >/dev/null
before="$(snap "$notag_src")"
run env TMPDIR="$tmproot" bash "$sim" --repo "$notag_src"
check_status "a source with no v* tag -> exit 2" 2 "$STATUS"
check_contains "...naming fetch-depth: 0" "$OUT" "fetch-depth: 0"
check_eq "...and the source repo is unchanged" "$before" "$(snap "$notag_src")"
check_eq "...and nothing was cloned" "" "$(ls -A "$tmproot")"
plain="$(mktemp -d "$SANDBOX/plain.XXXXXX")"
run env TMPDIR="$tmproot" bash "$sim" --repo "$plain"
check_status "a directory that is not a git repo -> exit 2" 2 "$STATUS"

summary
