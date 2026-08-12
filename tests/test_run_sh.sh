#!/usr/bin/env bash
# test_run_sh.sh — tests/run.sh's own aggregation logic (dir #130), exercised against a throwaway
# fake tests/ directory (a copy of run.sh plus synthetic test_*.sh fixtures) rather than the real
# suite, so a fixture's deliberate failure never pollutes this suite's own pass/fail count.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

runner="$REPO_ROOT/tests/run.sh"
check_file "run.sh exists" "$runner"

# mkfakedir NAME — a throwaway tests/-shaped dir under $SANDBOX with its own copy of run.sh, so a
# fixture test_*.sh file inside it is the only thing run.sh's glob picks up.
mkfakedir() {
  local d; d="$(mktemp -d "$SANDBOX/faketests.XXXXXX")"
  cp "$runner" "$d/run.sh"
  chmod +x "$d/run.sh"
  printf '%s' "$d"
}

# --- all-pass: every fixture green -> exit 0, every file's own header printed --------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho slow-a; sleep 0.2\nexit 0\n'  > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho fast-b\nexit 0\n'             > "$d/test_b.sh"
printf '#!/usr/bin/env bash\necho slow-c; sleep 0.2\nexit 0\n'  > "$d/test_c.sh"
run env KEEL_TEST_JOBS=3 bash "$d/run.sh"
check_status "all-pass fixtures -> exit 0" 0 "$STATUS"
check_contains "all-pass reports ALL TEST FILES PASSED" "$OUT" "ALL TEST FILES PASSED"
check_contains "all-pass includes test_a.sh's own header" "$OUT" "=== test_a.sh ==="
check_contains "all-pass includes test_b.sh's own header" "$OUT" "=== test_b.sh ==="
check_contains "all-pass includes test_c.sh's own header" "$OUT" "=== test_c.sh ==="
check_contains "all-pass carries test_a.sh's own stdout" "$OUT" "slow-a"
check_contains "all-pass carries test_b.sh's own stdout" "$OUT" "fast-b"
check_contains "all-pass carries test_c.sh's own stdout" "$OUT" "slow-c"

# --- one failure among several -> non-zero exit, failure is named, others still ran --------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n'                                > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho boom-from-b\nexit 1\n'              > "$d/test_b.sh"
printf '#!/usr/bin/env bash\nexit 0\n'                                > "$d/test_c.sh"
run env KEEL_TEST_JOBS=3 bash "$d/run.sh"
check_status "one failing fixture -> exit 1" 1 "$STATUS"
check_contains "one failing fixture -> reports 1 TEST FILE(S) FAILED" "$OUT" "1 TEST FILE(S) FAILED"
check_contains "one failing fixture -> the failing file's own output survives" "$OUT" "boom-from-b"
check_contains "one failing fixture -> a passing sibling still ran" "$OUT" "=== test_a.sh ==="
check_contains "one failing fixture -> the other passing sibling still ran" "$OUT" "=== test_c.sh ==="

# --- KEEL_TEST_JOBS=1 (sequential fallback) -> same aggregation, still catches the failure --------
run env KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "KEEL_TEST_JOBS=1 still catches the failure -> exit 1" 1 "$STATUS"
check_contains "KEEL_TEST_JOBS=1 still names it" "$OUT" "boom-from-b"

# --- a non-numeric KEEL_TEST_JOBS falls back rather than erroring ---------------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_a.sh"
run env KEEL_TEST_JOBS=bogus bash "$d/run.sh"
check_status "KEEL_TEST_JOBS=bogus doesn't crash the runner -> exit 0" 0 "$STATUS"
check_contains "KEEL_TEST_JOBS=bogus still passes a green fixture" "$OUT" "ALL TEST FILES PASSED"

# --- every fixture actually ran, even with more fixtures than the concurrency cap -----------------
d="$(mkfakedir)"
for n in 1 2 3 4 5 6; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_$n.sh"
done
run env KEEL_TEST_JOBS=2 bash "$d/run.sh"
check_status "more fixtures than the jobs cap -> still exit 0" 0 "$STATUS"
for n in 1 2 3 4 5 6; do
  check_contains "fixture $n ran despite the concurrency cap" "$OUT" "=== test_$n.sh ==="
done

summary
