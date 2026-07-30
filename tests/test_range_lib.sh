#!/usr/bin/env bash
# test_range_lib.sh — direct unit coverage for tools/secret-guard/range-lib.sh's zero-sha detection
# and range resolution. test_secret_guard.sh and test_ci_secret_scan.sh already cover
# resolve_range_local()/resolve_range_ci() indirectly through the pre-push hook and ci-scan.sh, both
# using a real repo's (SHA-1) all-zero sentinel. This file adds what a real-repo fixture can't easily
# exercise: a SHA-256 repo's 64-char all-zero sentinel, and secret_guard_is_zero_sha()'s own edge cases.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# shellcheck source=tools/secret-guard/range-lib.sh
. "$REPO_ROOT/tools/secret-guard/range-lib.sh"

zero40="$(rep 0 40)"
zero64="$(rep 0 64)"
sha40="$(rep a 40)"
sha64="$(rep a 64)"

# --- secret_guard_is_zero_sha: recognizes the sentinel regardless of hash-format length -----------
if secret_guard_is_zero_sha "$zero40"; then pass "40-zero sha (SHA-1) is recognized as zero"
else fail "40-zero sha (SHA-1) is recognized as zero" "returned false"; fi

if secret_guard_is_zero_sha "$zero64"; then pass "64-zero sha (SHA-256) is recognized as zero"
else fail "64-zero sha (SHA-256) is recognized as zero" "returned false"; fi

if secret_guard_is_zero_sha "$sha40"; then fail "a real 40-char sha is NOT zero" "returned true"
else pass "a real 40-char sha is NOT zero"; fi

if secret_guard_is_zero_sha "$sha64"; then fail "a real 64-char sha is NOT zero" "returned true"
else pass "a real 64-char sha is NOT zero"; fi

if secret_guard_is_zero_sha ""; then fail "an empty string is NOT treated as zero" "returned true"
else pass "an empty string is NOT treated as zero"; fi

# --- resolve_range_local: a SHA-256 repo's 64-zero BEFORE must resolve the same way a SHA-1 repo's
# 40-zero BEFORE does — this is the bug this file was added to catch: an exact-length compare against
# a fixed 40-char zero-sha literal would fall through to the else branch here and produce an
# unresolvable "before..after" range on a SHA-256 repo's first push --------------------------------
out="$(resolve_range_local "$zero64" "$sha64")"
check_contains "resolve_range_local: 64-zero before -> the new-ref (--not --remotes) shape" "$out" "--not --remotes"
check_contains "resolve_range_local: 64-zero before -> scans from the 64-char after sha" "$out" "$sha64"

out="$(resolve_range_local "$sha64" "$sha64")"
check_contains "resolve_range_local: non-zero 64-char before -> a before..after range" "$out" "$sha64..$sha64"

# --- resolve_range_ci: same length-agnostic requirement, different first-push shape ----------------
out="$(resolve_range_ci "$zero64" "$sha64")"
if [ "$out" = "$sha64" ]; then pass "resolve_range_ci: 64-zero before -> scans full history from after"
else fail "resolve_range_ci: 64-zero before -> scans full history from after" "got: $out"; fi

out="$(resolve_range_ci "$sha64" "$sha64")"
check_contains "resolve_range_ci: non-zero 64-char before -> a before..after range" "$out" "$sha64..$sha64"

summary
