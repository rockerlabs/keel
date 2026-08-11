#!/usr/bin/env bash
# test_safe_emails_shared.sh — dir #106: the public-safe email allowlist used to be a hand-maintained
# copy in doctor.sh (advisory nudge) AND public-audit.sh (the GAP gate), behind "keep in sync"
# comments nothing enforced — and had already re-diverged once before (PR #43 consolidated them, then
# they drifted apart again). Now both source tools/lib/safe-emails.sh. Pin this at the SOURCE level
# (grep the scripts for a re-duplicated pattern), not the output level — an output-level check would
# only prove today's two callers happen to agree, not that a third copy can't reappear.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/safe-emails.sh"
check_file "tools/lib/safe-emails.sh exists" "$lib"

# --- both known consumers source the shared lib, not a private copy -----------------------------
if grep -qF 'lib/safe-emails.sh' "$REPO_ROOT/tools/doctor.sh"; then
  pass "doctor.sh sources tools/lib/safe-emails.sh"
else
  fail "doctor.sh sources tools/lib/safe-emails.sh" "no reference to lib/safe-emails.sh found"
fi
if grep -qF 'lib/safe-emails.sh' "$REPO_ROOT/tools/public-audit.sh"; then
  pass "public-audit.sh sources tools/lib/safe-emails.sh"
else
  fail "public-audit.sh sources tools/lib/safe-emails.sh" "no reference to lib/safe-emails.sh found"
fi

# --- no re-duplicated copy of the pattern set anywhere else under tools/ -------------------------
# A marker pattern from the set, unlikely to appear for any other reason. If it shows up outside the
# lib file, someone pasted a private copy instead of sourcing — the exact regression dir #106 fixes.
hits="$(grep -rlF 'users\.noreply\.github\.com' "$REPO_ROOT/tools" 2>/dev/null | grep -vF "$lib")"
if [ -z "$hits" ]; then
  pass "no duplicated safe-email pattern outside tools/lib/safe-emails.sh"
else
  fail "no duplicated safe-email pattern outside tools/lib/safe-emails.sh" "found in: $hits"
fi

# --- the lib itself defines a usable array and combined regex -----------------------------------
# shellcheck source=/dev/null
. "$lib"
if [ "${#SAFE_EMAILS[@]}" -gt 0 ]; then
  pass "SAFE_EMAILS is non-empty (${#SAFE_EMAILS[@]} patterns)"
else
  fail "SAFE_EMAILS is non-empty" "array is empty after sourcing the lib"
fi
if [ -n "$safe_email_re" ] && printf 'noreply@github.com' | grep -qE "$safe_email_re"; then
  pass "safe_email_re matches a known-safe address"
else
  fail "safe_email_re matches a known-safe address" "noreply@github.com did not match: $safe_email_re"
fi
if printf 'someone@personal-domain.example' | grep -qE "$safe_email_re" 2>/dev/null; then
  fail "safe_email_re rejects a non-safe address" "a made-up personal address incorrectly matched"
else
  pass "safe_email_re rejects a non-safe address"
fi

summary
