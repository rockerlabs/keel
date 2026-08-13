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

# --- fixtures actually overlap in wall clock under concurrency, not just "all eventually ran" ------
# (found by the /polish high-depth review agent: the assertions above would still pass a regression
# to a sequential-only implementation, since none of them measure wall clock.) Four 1s-sleep fixtures
# serially cost >=4s; under KEEL_TEST_JOBS=4 they should overlap and finish well under that.
d="$(mkfakedir)"
for n in 1 2 3 4; do
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/test_$n.sh"
done
t0=$(date +%s)
run env KEEL_TEST_JOBS=4 bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "timing: 4x 1s fixtures, jobs=4 -> exit 0" 0 "$STATUS"
if [ "$elapsed" -le 3 ]; then
  pass "timing: 4x 1s fixtures overlap under jobs=4 (${elapsed}s, serial would be >=4s)"
else
  fail "timing: 4x 1s fixtures overlap under jobs=4" "took ${elapsed}s, expected <=3s if truly concurrent"
fi

# --- SIGTERM mid-run: exits 130, kills the still-running children, and — unlike a naive kill-and-
# exit — still surfaces each interrupted fixture's own buffered output rather than silently
# dropping it (found by an operator-run /code-review high pass, dir #130: the old sequential
# runner streamed output live, so an interrupt never lost anything; the new concurrent one buffers
# per-file until reap time, which needed its own interrupt-time flush). ------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho hello-from-int-a\nsleep 5\nexit 0\n' > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho hello-from-int-b\nsleep 5\nexit 0\n' > "$d/test_b.sh"
int_out="$(mktemp)"
t0=$(date +%s)
env KEEL_TEST_JOBS=2 bash "$d/run.sh" >"$int_out" 2>&1 &
rpid=$!
# Poll for both fixtures' own echo instead of a fixed sleep, so the SIGTERM lands reliably once
# both children are actually up rather than racing a guessed delay.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if grep -q "hello-from-int-a" "$int_out" 2>/dev/null && grep -q "hello-from-int-b" "$int_out" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
kill -TERM "$rpid"
wait "$rpid"
int_status=$?
t1=$(date +%s)
int_out_text="$(cat "$int_out")"
check_status "SIGTERM mid-run -> exit 130" 130 "$int_status"
check_contains "SIGTERM mid-run -> test_a's output survives the kill" "$int_out_text" "hello-from-int-a"
check_contains "SIGTERM mid-run -> test_b's output survives the kill" "$int_out_text" "hello-from-int-b"
check_contains "SIGTERM mid-run -> names the interrupted files" "$int_out_text" "(interrupted)"
if [ "$((t1 - t0))" -le 3 ]; then
  pass "SIGTERM mid-run -> the 5s sleeps were actually killed, not waited out ($((t1 - t0))s)"
else
  fail "SIGTERM mid-run -> the 5s sleeps were actually killed, not waited out" "took $((t1 - t0))s, expected <=3s"
fi
rm -f "$int_out"

# --- $CI caps the default at 2, overriding a host reporting more cores (dir #154) -----------------
# tests/run.sh's own default now checks $CI before falling back to nproc/sysctl — the new branch had
# no coverage at all (found by an operator-run /code-review medium pass): every case above pins
# KEEL_TEST_JOBS explicitly, so a regression in the $CI branch itself would pass silently. A fake
# `nproc` on PATH decouples this from the real host's core count on purpose — this suite exists to
# fight resource-contention flakiness, so a timing assertion tied to the ACTUAL host's CPU count
# would risk reintroducing exactly that class of flake.
d="$(mkfakedir)"
for n in 1 2 3 4 5 6; do
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/test_$n.sh"
done
fakebin="$(mktemp -d "$SANDBOX/fakebin.XXXXXX")"
printf '#!/usr/bin/env bash\necho 9\n' > "$fakebin/nproc"
chmod +x "$fakebin/nproc"

# CI unset -> falls through to the (mocked, high) nproc default, all 6 overlap -> well under serial 6s
t0=$(date +%s)
run env -u KEEL_TEST_JOBS -u CI PATH="$fakebin:$PATH" bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "CI unset: nproc-default fixtures -> exit 0" 0 "$STATUS"
if [ "$elapsed" -le 2 ]; then
  pass "CI unset: 6x 1s fixtures run at the mocked nproc=9 default, not capped (${elapsed}s)"
else
  fail "CI unset: 6x 1s fixtures run at the nproc default" "took ${elapsed}s, expected <=2s under the mocked nproc=9"
fi

# CI=true -> caps at 2 regardless of the (mocked, high) nproc value -> 3 batches of 2, ~3s
t0=$(date +%s)
run env -u KEEL_TEST_JOBS PATH="$fakebin:$PATH" CI=true bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "CI=true: capped fixtures -> exit 0" 0 "$STATUS"
if [ "$elapsed" -ge 2 ] && [ "$elapsed" -le 5 ]; then
  pass "CI=true: 6x 1s fixtures cap at 2 despite a high mocked nproc (${elapsed}s, ~3 batches)"
else
  fail "CI=true: 6x 1s fixtures cap at 2" "took ${elapsed}s, expected roughly 3 batches (2-5s)"
fi

# --- KEEL_TEST_JOBS still overrides $CI's default (dir #154) ---------------------------------------
run env PATH="$fakebin:$PATH" KEEL_TEST_JOBS=1 CI=true bash "$d/run.sh"
check_status "KEEL_TEST_JOBS=1 under CI=true still runs -> exit 0" 0 "$STATUS"
check_contains "KEEL_TEST_JOBS=1 under CI=true still passes all fixtures" "$OUT" "ALL TEST FILES PASSED"

summary
