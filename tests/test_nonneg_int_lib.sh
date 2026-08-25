#!/usr/bin/env bash
# test_nonneg_int_lib.sh — dir #242: tools/lib/nonneg-int.sh (dir #196) claims to be "the ONE
# non-negative-integer sanitizer, shared by every tool that clamps a numeric env-var/arg override",
# but had zero dedicated test coverage — the coverage ratchet (dir #142, tools/self/doctor.sh) reported
# it "test-covered" on nothing more than a bare filename mention inside a comment at
# tests/test_install_pre_pr_gate.sh:309. This file gives the lib the direct unit coverage the repo's
# three other shared libs already have (test_range_lib.sh, test_manifest_lib.sh,
# test_fence_blank_lib.sh), and pins its two real consumers (tools/self/doctor.sh's
# pending_max_commits, tools/keel-impact.sh's require_count) at the source level, the same way
# test_fence_blank_lib.sh pins fence-blank.sh's consumers.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/nonneg-int.sh"
check_file "tools/lib/nonneg-int.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- _nonneg_int_valid: the basic shape ------------------------------------------------------------
if _nonneg_int_valid "0"; then pass "_nonneg_int_valid: 0 is valid"
else fail "_nonneg_int_valid: 0 is valid" "returned invalid"; fi

if _nonneg_int_valid "40"; then pass "_nonneg_int_valid: 40 is valid"
else fail "_nonneg_int_valid: 40 is valid" "returned invalid"; fi

if _nonneg_int_valid ""; then fail "_nonneg_int_valid: empty string is invalid" "returned valid"
else pass "_nonneg_int_valid: empty string is invalid"; fi

if _nonneg_int_valid "-1"; then fail "_nonneg_int_valid: a negative number is invalid" "returned valid"
else pass "_nonneg_int_valid: a negative number is invalid"; fi

if _nonneg_int_valid "12a"; then fail "_nonneg_int_valid: trailing garbage is invalid" "returned valid"
else pass "_nonneg_int_valid: trailing garbage is invalid"; fi

if _nonneg_int_valid "3.5"; then fail "_nonneg_int_valid: a decimal is invalid" "returned valid"
else pass "_nonneg_int_valid: a decimal is invalid"; fi

# --- _nonneg_int_valid: the actual defect this lib exists to close (dir #156) — digit-shape alone
# accepts an arbitrarily long all-digit string that can overflow the shell's native integer range and
# silently defeat a later numeric comparison. The default MAX_DIGITS (10) must reject a 10-digit
# string and accept a 9-digit one -------------------------------------------------------------------
nine_digits="123456789"
ten_digits="1234567890"
if _nonneg_int_valid "$nine_digits"; then pass "_nonneg_int_valid: 9 digits is valid at the default cap"
else fail "_nonneg_int_valid: 9 digits is valid at the default cap" "returned invalid"; fi

if _nonneg_int_valid "$ten_digits"; then
  fail "_nonneg_int_valid: 10 digits overflows the default cap -> invalid" "returned valid"
else
  pass "_nonneg_int_valid: 10 digits overflows the default cap -> invalid"
fi

# --- _nonneg_int_valid: an explicit MAX_DIGITS narrows the cap accordingly --------------------------
if _nonneg_int_valid "999" 3; then
  fail "_nonneg_int_valid: MAX_DIGITS=3 rejects a 3-digit value" "returned valid"
else
  pass "_nonneg_int_valid: MAX_DIGITS=3 rejects a 3-digit value"
fi

if _nonneg_int_valid "99" 3; then pass "_nonneg_int_valid: MAX_DIGITS=3 accepts a 2-digit value"
else fail "_nonneg_int_valid: MAX_DIGITS=3 accepts a 2-digit value" "returned invalid"; fi

# --- sanitize_nonneg_int: valid input passes through, invalid falls back to the default -------------
out="$(sanitize_nonneg_int "7" "40")"
check_contains "sanitize_nonneg_int: valid value passes through" "$out" "7"

out="$(sanitize_nonneg_int "" "40")"
check_contains "sanitize_nonneg_int: empty value falls back to the default" "$out" "40"

out="$(sanitize_nonneg_int "not-a-number" "40")"
check_contains "sanitize_nonneg_int: non-digit value falls back to the default" "$out" "40"

out="$(sanitize_nonneg_int "$ten_digits" "40")"
check_contains "sanitize_nonneg_int: overlong value falls back to the default" "$out" "40"

# --- both known consumers source the shared lib, not a private inline copy of the digit-shape guard -
check_contains "tools/self/doctor.sh sources tools/lib/nonneg-int.sh" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" 'lib/nonneg-int.sh'
check_contains "tools/self/doctor.sh calls sanitize_nonneg_int for pending_max_commits" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" 'sanitize_nonneg_int "$pending_max_commits" 40'
check_contains "tools/keel-impact.sh sources tools/lib/nonneg-int.sh" \
  "$(cat "$REPO_ROOT/tools/keel-impact.sh")" 'lib/nonneg-int.sh'
check_contains "tools/keel-impact.sh's require_count calls _nonneg_int_valid" \
  "$(cat "$REPO_ROOT/tools/keel-impact.sh")" '_nonneg_int_valid "$val"'

# --- keel-impact.sh's require_count: extracted straight out of the real script (not re-typed here),
# so this fixture tracks the shipped function verbatim rather than a hand-copied guess -------------
# (dir #242 Half B): require_count used to accept an arbitrarily long all-digit --flag value; it must
# now reject one via _nonneg_int_valid's magnitude cap, while '' still defaults to 0 and a genuinely
# small count still passes through untouched. Extracted rather than sourcing keel-impact.sh whole:
# the real script's top-level dispatch runs `_impact_auto_migrate` as a side effect of being loaded at
# all, which this unit test must not trigger.
impact_sh="$REPO_ROOT/tools/keel-impact.sh"
require_count_src="$(sed -n '/^require_count() {/,/^}/p' "$impact_sh")"
if [ -z "$require_count_src" ]; then
  fail "require_count() located in tools/keel-impact.sh" "no function definition found"
else
  eval "$require_count_src"

  out="$(require_count silent "5")"
  check_contains "require_count: a small in-range value passes through" "$out" "5"

  out="$(require_count silent "")"
  check_contains "require_count: empty value defaults to 0" "$out" "0"

  out="$(require_count silent "$ten_digits" 2>&1)"; ec=$?
  check_status "require_count: a 10-digit overlong value now exits 2 (dir #242 fix, not a regression)" 2 "$ec"

  out="$(require_count silent "abc" 2>&1)"; ec=$?
  check_status "require_count: non-digit value still exits 2" 2 "$ec"
fi

summary
