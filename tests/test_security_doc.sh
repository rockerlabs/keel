#!/usr/bin/env bash
# test_security_doc.sh — SECURITY.md must not hardcode a specific release version.
#
# The "Supported versions" line used to read "the most recent tag (currently `v0.2.0`)". That literal
# is duplicated mutable state (the real source of truth is the git tag list), so it silently drifted
# stale after v0.3.0 shipped. The fix removed the literal; this guard keeps a vN.N.N from creeping back
# in — single source of truth (FRAMEWORK "Knowledge & context upkeep").
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/SECURITY.md"
check_file "SECURITY.md exists" "$doc"

# A pinned vMAJOR.MINOR.PATCH literal anywhere in SECURITY.md re-introduces the drift class.
hit="$(grep -nE 'v[0-9]+\.[0-9]+\.[0-9]+' "$doc" || true)"
if [ -z "$hit" ]; then
  pass "SECURITY.md pins no specific release version (no drift surface)"
else
  fail "SECURITY.md hardcodes a release version — drifts stale on the next release" "$hit"
fi

summary
