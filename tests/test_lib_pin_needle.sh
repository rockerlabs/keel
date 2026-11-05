#!/usr/bin/env bash
# test_lib_pin_needle.sh (dir #937) — direct coverage for tests/lib.sh's one-line-needle rule on pin() and
# pin_exact(): `grep -F` reads each line of a multi-line pattern as an alternative, so a needle holding a
# newline passes when EITHER half is present and binds nothing. Both helpers must FAIL such a needle with a
# message naming the rule, and must keep passing a one-line needle that is there and failing one that is not.
# Each call runs in a subshell so its pass/fail counters never reach this file's own summary.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# probe CMD... — run it in a subshell; print its output, then the failures and passes IT added.
probe() { ( b_f=$_fail; b_p=$_pass; "$@"; echo "fails=$((_fail - b_f)) passes=$((_pass - b_p))" ); }

f="$SANDBOX/pin-needle.txt"
printf 'alpha line\nbeta line\n' > "$f"
nl_needle="alpha line
GONE half"

# A two-line needle whose FIRST half is in the file: grep -F alone would pass it (the vacuous shape).
check_eq "premise: grep -F alone accepts the two-line needle (the vacuity this rule closes)" \
  "$(grep -cF -- "$nl_needle" "$f")" "1"

out="$(probe pin "multi" "$f" "$nl_needle" "hint")"
check_contains "pin: a needle holding a newline fails" "$out" "FAIL  multi"
check_contains "pin: the failure names the rule" "$out" "needle holds a newline"
check_contains "pin: the failure says to use one physical line" "$out" "one physical line"
check_contains "pin: exactly one failure and no pass" "$out" "fails=1 passes=0"

out="$(probe pin_exact "multi-exact" "$f" "$nl_needle" "hint")"
check_contains "pin_exact: a needle holding a newline fails" "$out" "FAIL  multi-exact"
check_contains "pin_exact: the failure names the rule" "$out" "needle holds a newline"
check_contains "pin_exact: exactly one failure and no pass" "$out" "fails=1 passes=0"

# Both halves present on their own lines: still refused (the alternation passes on either half).
out="$(probe pin "both" "$f" "alpha line
beta line" "hint")"
check_contains "pin: a needle whose halves are both present is refused too" "$out" "fails=1 passes=0"

# One-line needles keep their old behaviour.
out="$(probe pin "one-ok" "$f" "beta line" "hint")"
check_contains "pin: a one-line needle that is present passes" "$out" "fails=0 passes=1"
out="$(probe pin "one-miss" "$f" "gamma line" "the hint")"
check_contains "pin: a one-line needle that is absent fails with the caller's hint" "$out" "the hint"
out="$(probe pin_exact "one-exact" "$f" "beta line" "hint")"
check_contains "pin_exact: a one-line needle on one line passes" "$out" "fails=0 passes=1"

summary
