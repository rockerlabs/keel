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
check_contains "doctor.sh sources tools/lib/safe-emails.sh" \
  "$(cat "$REPO_ROOT/tools/doctor.sh")" 'lib/safe-emails.sh'
check_contains "public-audit.sh sources tools/lib/safe-emails.sh" \
  "$(cat "$REPO_ROOT/tools/public-audit.sh")" 'lib/safe-emails.sh'

# --- no re-duplicated copy of the pattern set anywhere else under tools/ -------------------------
# A marker substring from the set, unlikely to appear for any other reason. If it shows up outside
# the lib file, someone pasted a private copy instead of sourcing — the exact regression dir #106
# fixes. Backslashes are stripped from BOTH sides before matching (`tr -d '\\'`), so a re-duplicated
# copy that merely escapes its dots differently (`@users.noreply.github.com`, `@users\\.noreply...`,
# vs. the lib's own `@users\.noreply\.github\.com`) can't dodge this by re-spelling the same ERE —
# a plain literal-string grep on the lib's exact escaping was mutation-tested and found to miss
# exactly that (found in review). Four independent markers (of the array's 5 patterns — see below),
# not one, so a rewrite dropping/reordering any single pattern still gets caught by the others.
# The last pattern ('@[A-Za-z0-9.-]*\.invalid') has no marker: the only stable literal fragment in
# it is "invalid", which is an ordinary English word that already appears, unrelated to this array,
# in several other tools/ scripts (pre-pr-gate.sh, pipeline-canary.sh, secret-scan.sh) — a marker
# there would false-positive-fail on unrelated code. Accepted gap: a re-duplication of ONLY that one
# pattern in isolation goes uncaught; the far more likely failure mode (copy-pasting the whole array,
# per PR #43's actual history) is caught by any of the other four.
marker1="usersnoreplygithubcom"      # from '@users\.noreply\.github\.com'
marker2="noreplyanthropiccom"        # from 'noreply@anthropic\.com'
marker3="noreplygithubcom"           # from 'noreply@github\.com' (distinct from marker1: no "users" prefix)
marker4="examplecom"                 # from '@example\.(com|org|net)' — the "com" branch only; "org"/"net"
                                      # would need their own markers to close fully, not worth the added
                                      # false-positive surface for a partial-alternation duplication
hits=""
while IFS= read -r -d '' f; do
  [ "$f" = "$lib" ] && continue
  norm="$(tr -d '\\.@' < "$f" 2>/dev/null | tr -d '[:space:]')"
  for m in "$marker1" "$marker2" "$marker3" "$marker4"; do
    # A literal substring test, so a plain bash `case` glob (same idiom check_contains uses) rather
    # than `grep -F` — no subprocess, no pipe, structurally immune to the SIGPIPE race a
    # `printf | grep -q` gate has under load (dir #280; norm can be a whole large tools/ file here).
    case "$norm" in
      *"$m"*) hits="${hits:+$hits }$f"; break ;;
    esac
  done
done < <(find "$REPO_ROOT/tools" -type f -print0)
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
# match(), not a direct `printf | grep -q` pipe (dir #280 — see tests/lib.sh's match() for why).
if [ -n "$safe_email_re" ] && match 'noreply@github.com' -qE "$safe_email_re"; then
  pass "safe_email_re matches a known-safe address"
else
  fail "safe_email_re matches a known-safe address" "noreply@github.com did not match: $safe_email_re"
fi
if match 'someone@personal-domain.example' -qE "$safe_email_re" 2>/dev/null; then
  fail "safe_email_re rejects a non-safe address" "a made-up personal address incorrectly matched"
else
  pass "safe_email_re rejects a non-safe address"
fi

summary
