#!/usr/bin/env bash
# test_leak_patterns_shared.sh — dir #114 (M4-1): the leaked-identifier content patterns (a home
# path, a real-looking email) started as a hand-copy in public-audit.sh, then self/doctor.sh's new
# FRAMEWORK.md/PRINCIPLES.md GAP check added a second one — the exact "keep in sync" hand-copy shape
# dir #106 already fixed once for the safe-email allowlist. Both now source
# tools/lib/leak-patterns.sh instead. Pinned at the SOURCE level (grep the scripts for a
# re-duplicated pattern), mirroring test_safe_emails_shared.sh's own approach.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/leak-patterns.sh"
check_file "tools/lib/leak-patterns.sh exists" "$lib"

# --- both known consumers source the shared lib, not a private copy -----------------------------
check_contains "public-audit.sh sources tools/lib/leak-patterns.sh" \
  "$(cat "$REPO_ROOT/tools/public-audit.sh")" 'lib/leak-patterns.sh'
check_contains "self/doctor.sh sources tools/lib/leak-patterns.sh" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" 'lib/leak-patterns.sh'

# --- no re-duplicated copy of HOME_RE anywhere else under tools/ --------------------------------
# The '(Users|home)' alternation is a distinctive enough fragment of HOME_RE that a hand-copy
# elsewhere would reproduce it; the lib file itself is excluded.
hits=""
while IFS= read -r -d '' f; do
  [ "$f" = "$lib" ] && continue
  grep -qF '(Users|home)' "$f" 2>/dev/null && hits="${hits:+$hits }$f"
done < <(find "$REPO_ROOT/tools" -type f -print0)
if [ -z "$hits" ]; then
  pass "no duplicated HOME_RE pattern outside tools/lib/leak-patterns.sh"
else
  fail "no duplicated HOME_RE pattern outside tools/lib/leak-patterns.sh" "found in: $hits"
fi

# --- the lib itself defines usable patterns ------------------------------------------------------
# shellcheck source=/dev/null
. "$lib"
# match(), not a direct `printf | grep -q` pipe (dir #280 — see tests/lib.sh's match() for why).
if match '/Users/exampleuser/repo' -qE "$HOME_RE"; then
  pass "HOME_RE matches a home-directory path"
else
  fail "HOME_RE matches a home-directory path" "did not match: $HOME_RE"
fi
if match 'someone@example-corp.com' -qE "$EMAIL_RE"; then
  pass "EMAIL_RE matches an email-shaped string"
else
  fail "EMAIL_RE matches an email-shaped string" "did not match: $EMAIL_RE"
fi

summary
