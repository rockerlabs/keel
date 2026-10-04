#!/usr/bin/env bash
# test_range_lib.sh — direct unit coverage for tools/secret-guard/range-lib.sh's zero-sha detection
# and range resolution. test_secret_guard.sh and test_ci_secret_scan.sh already cover
# resolve_range_local()/resolve_range_ci() indirectly through the pre-push hook and ci-scan.sh, both
# using a real repo's (SHA-1) all-zero sentinel. This file adds what a real-repo fixture can't easily
# exercise: a SHA-256 repo's 64-char all-zero sentinel, and secret_guard_is_zero_sha()'s own edge cases.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

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

# a non-zero BEFORE that IS a commit here resolves to a before..after range. The SHA-256 half needs a
# real SHA-256 repo (dir #546: an unknown BEFORE no longer yields a range, so a made-up 64-char sha
# cannot stand in for one); a git that cannot make one skips the half, loudly.
r256="$(mktemp -d "$SANDBOX/r256.XXXXXX")"
if git -C "$r256" init -q --object-format=sha256 2>/dev/null; then
  git -C "$r256" commit -q --allow-empty -m one; git -C "$r256" commit -q --allow-empty -m two
  b256="$(git -C "$r256" rev-parse HEAD~1)"; a256="$(git -C "$r256" rev-parse HEAD)"
  out="$(cd "$r256" && resolve_range_local "$b256" "$a256")"
  check_eq "resolve_range_local: a known 64-char before -> a before..after range" "$b256..$a256" "$out"
  out="$(cd "$r256" && resolve_range_local "$sha64" "$a256")"
  check_eq "resolve_range_local: an unknown 64-char before -> the new-ref shape (dir #546)" "$a256 --not --remotes" "$out"
else
  pass "SKIP (git cannot make a SHA-256 repo here): the 64-char known/unknown before pair"
fi

# --- dir #546: an unknown (non-zero) BEFORE falls back to the zero-sha shape -------------------------
rk="$(new_repo)"
git -C "$rk" commit -q --allow-empty -m one; git -C "$rk" commit -q --allow-empty -m two
bk="$(git -C "$rk" rev-parse HEAD~1)"; ak="$(git -C "$rk" rev-parse HEAD)"
out="$(cd "$rk" && resolve_range_local "$bk" "$ak")"
check_eq "resolve_range_local: a known before commit -> before..after" "$bk..$ak" "$out"
out="$(cd "$rk" && resolve_range_local "$sha40" "$ak")"
check_eq "resolve_range_local: an unknown 40-char before -> the new-ref shape" "$ak --not --remotes" "$out"
blob="$(printf 'x' | git -C "$rk" hash-object -w --stdin)"
out="$(cd "$rk" && resolve_range_local "$blob" "$ak")"
check_eq "resolve_range_local: a before that is a blob, not a commit -> the new-ref shape" "$ak --not --remotes" "$out"
out="$(cd "$rk" && resolve_range_local "not-a-sha" "$ak")"
check_eq "resolve_range_local: a before that is no sha at all -> the new-ref shape" "$ak --not --remotes" "$out"
if (cd "$rk" && secret_guard_commit_known "$bk"); then pass "secret_guard_commit_known: a commit here -> true"
else fail "secret_guard_commit_known: a commit here -> true" "returned false"; fi
if (cd "$rk" && secret_guard_commit_known "$sha40"); then fail "secret_guard_commit_known: an unknown sha -> false" "returned true"
else pass "secret_guard_commit_known: an unknown sha -> false"; fi

# --- resolve_range_ci: same length-agnostic requirement, different first-push shape ----------------
out="$(resolve_range_ci "$zero64" "$sha64")"
if [ "$out" = "$sha64" ]; then pass "resolve_range_ci: 64-zero before -> scans full history from after"
else fail "resolve_range_ci: 64-zero before -> scans full history from after" "got: $out"; fi

out="$(resolve_range_ci "$sha64" "$sha64")"
check_contains "resolve_range_ci: non-zero 64-char before -> a before..after range" "$out" "$sha64..$sha64"

# dir #546: resolve_range_ci is NOT given the unknown-BEFORE fallback — a CI checkout has the old tip (or
# ci-scan.sh's own fetch/baseline degrade handles its absence), so an unknown BEFORE stays a plain range.
out="$(cd "$rk" && resolve_range_ci "$sha40" "$ak")"
check_eq "resolve_range_ci: an unknown before is left a before..after range (dir #546, unchanged)" "$sha40..$ak" "$out"

summary
