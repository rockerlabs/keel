#!/usr/bin/env bash
# test_suite_hygiene.sh — dir #744 B31 (A28): a test that waits for a background process to finish takes its
# bound from KEEL_TEST_HANG_BOUND (default 120 s) and steps it in whole seconds. A real hang is unbounded, so a
# long bound costs time only when the test already fails; a 10–30 s literal bound failed slow-but-finishing
# runs under load (E24: three such checks went red in full runs that passed alone). The lint is per line over
# tests/*.sh (this file and tests/run.sh excluded): a non-comment line holding `kill -0` together with
# `while`, `until`, `-lt`, `-le` or `break` must name KEEL_TEST_HANG_BOUND, and every `sleep` on it or the next
# 2 lines must be `sleep 1`.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# hang_lint FILE… — one `file:line: reason` per violation; nothing when clean.
hang_lint() {
  awk '
    FNR == 1 { for (k in pend) delete pend[k] }
    # a pending wait line: check the sleeps on its next 2 lines
    { for (k in pend) {
        if (FNR - k > 2) { delete pend[k]; continue }
        if (check_sleep($0)) { print pend[k] ": the wait steps a sub-second or non-1 s sleep"; delete pend[k] }
      }
    }
    /^[[:space:]]*#/ { next }
    /kill -0/ && /(while|until|-lt|-le|break)/ {
      where = FILENAME ":" FNR
      if ($0 !~ /KEEL_TEST_HANG_BOUND/) print where ": a kill -0 wait with a literal bound (use ${KEEL_TEST_HANG_BOUND:-120})"
      if (check_sleep($0)) print where ": the wait steps a sub-second or non-1 s sleep"
      else pend[FNR] = where
    }
    function check_sleep(l,   t) {
      t = l
      while (match(t, /sleep [^ ;)]+/)) {
        if (substr(t, RSTART, RLENGTH) != "sleep 1") return 1
        t = substr(t, RSTART + RLENGTH)
      }
      return 0
    }
  ' "$@"
}

# --- the lint catches each wrong shape (fixtures) ---------------------------------------------------------
fx="$SANDBOX/hang-fixtures.sh"
cat > "$fx" <<'FX'
while kill -0 "$p" 2>/dev/null && [ "$w" -lt 30 ]; do sleep 1; w=$((w + 1)); done
while kill -0 "$p" 2>/dev/null && [ "$w" -lt "$n" ]; do sleep 1; done
until ! kill -0 "$p" 2>/dev/null; do sleep 1; done
for i in 1 2 3; do kill -0 "$p" 2>/dev/null || break; sleep 1; done
while kill -0 "$p" && [ "$w" -lt "${KEEL_TEST_HANG_BOUND:-120}" ]; do
  sleep 0.2; w=$((w + 1))
done
while kill -0 "$p" && [ "$w" -lt "${KEEL_TEST_HANG_BOUND:-120}" ]; do sleep 1; w=$((w + 1)); done
# a comment naming kill -0 while waiting is not code
FX
out="$(hang_lint "$fx")"
check_contains "lint: a literal bound is caught" "$out" "hang-fixtures.sh:1: a kill -0 wait with a literal bound"
check_contains "lint: a variable bound that is not KEEL_TEST_HANG_BOUND is caught" "$out" "hang-fixtures.sh:2: a kill -0 wait"
check_contains "lint: an until loop is caught" "$out" "hang-fixtures.sh:3: a kill -0 wait"
check_contains "lint: a for ... || break wait is caught" "$out" "hang-fixtures.sh:4: a kill -0 wait"
check_contains "lint: a sub-second step on the next line is caught" "$out" "hang-fixtures.sh:5: the wait steps a sub-second"
check_absent "lint: the conforming one-line wait is clean" "$out" "hang-fixtures.sh:8:"
check_absent "lint: a comment line is not a wait" "$out" "hang-fixtures.sh:9:"

# --- the real suite is clean ------------------------------------------------------------------------------
targets=()
for f in "$REPO_ROOT"/tests/test_*.sh; do
  [ "$(basename "$f")" = test_suite_hygiene.sh ] && continue
  targets+=("$f")
done
real="$(hang_lint "${targets[@]}")"
check_eq "A28: every kill -0 wait in tests/*.sh takes KEEL_TEST_HANG_BOUND and steps 1 s" "" "$real"
# Non-vacuity: the eleven waits B31 converted are there (a lint matching nothing would pass the line above).
seen="$(grep -hE 'kill -0.*KEEL_TEST_HANG_BOUND' "${targets[@]}" | wc -l | tr -d ' ')"
if [ "$seen" -ge 11 ]; then
  pass "A28: the lint's subject exists ($seen KEEL_TEST_HANG_BOUND waits)"
else
  fail "A28: the lint's subject exists" "only $seen KEEL_TEST_HANG_BOUND waits (B31 converted 11)"
fi

summary
