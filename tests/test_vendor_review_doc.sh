#!/usr/bin/env bash
# Tests for docs/vendor-review.md — dir #614: the doc must be discoverable (README, reference.md) and
# the four sibling docs it displaces an "unnamed harness" reference in must point at it by name.
# Same idiom as test_delta_audit_doc.sh: fixed-string pins on both legs of each cross-reference.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="$REPO_ROOT/docs/vendor-review.md"
readme="$REPO_ROOT/README.md"
reference="$REPO_ROOT/docs/reference.md"
delta_audit="$REPO_ROOT/docs/delta-audit.md"
grooming="$REPO_ROOT/docs/grooming.md"
drydock="$REPO_ROOT/docs/drydock.md"
tool="$REPO_ROOT/tools/vendor-review.sh"
client="$REPO_ROOT/tools/vendor-review/agy.sh"

check_executable() { [ -x "$2" ] && pass "$1 is executable" || fail "$1 is executable" "not +x"; }

check_file "docs/vendor-review.md exists" "$doc"
check_file "tools/vendor-review.sh exists" "$tool"
check_executable "tools/vendor-review.sh" "$tool"
check_file "tools/vendor-review/agy.sh exists" "$client"
check_executable "tools/vendor-review/agy.sh" "$client"

# --- discoverability: README and reference.md both list it -----------------------------------------
pin "README Docs section links docs/vendor-review.md" \
  "$readme" '[`docs/vendor-review.md`](docs/vendor-review.md)' \
  "expected the Docs section to list vendor-review.md the way it lists drydock.md"
pin "reference.md Tools table lists tools/vendor-review.sh" \
  "$reference" '[`tools/vendor-review.sh`](../tools/vendor-review.sh)' \
  "expected the Tools table to name the shipped script"
pin "reference.md names the agy client too" \
  "$reference" '[`tools/vendor-review/agy.sh`](../tools/vendor-review/agy.sh)' \
  "expected the Tools table row to name the worked client"

# --- delta-audit.md §11 points at the shipped pair, on both legs -----------------------------------
pin "delta-audit.md §11 names docs/vendor-review.md" \
  "$delta_audit" '](vendor-review.md)' \
  "expected §11's intro to point at the shipped doc instead of an unnamed harness"
pin "vendor-review.md names delta-audit.md back" \
  "$doc" '](delta-audit.md)' \
  "expected vendor-review.md to name the harness-lessons sibling"
check_absent "delta-audit.md §11 no longer calls it a private harness path" \
  "$(cat "$delta_audit")" 'naming any private harness path'

# --- grooming.md G6 names the tool as an optional second axis --------------------------------------
pin "grooming.md G6 names docs/vendor-review.md" \
  "$grooming" '](vendor-review.md)' \
  "expected G6 to point at the vendor-review tool as an optional second axis"
pin "vendor-review.md names grooming.md back" \
  "$doc" '](grooming.md)' \
  "expected vendor-review.md to name G6, the round it was built for"

# --- drydock.md's external-leg section cross-links the scriptable sibling --------------------------
pin "drydock.md's external-leg section names docs/vendor-review.md" \
  "$drydock" '](vendor-review.md)' \
  "expected the external-leg intro to disambiguate the two vendor-leg classes"
pin "vendor-review.md names drydock.md back" \
  "$doc" '](drydock.md)' \
  "expected vendor-review.md to name the unscriptable-leg sibling"

# --- dir #662 (B10): the prose states the hardened rails, and the retired claims are gone --------------
check_absent "vendor-review.md: rail 1's retired 'applies unconditionally here' limitation is gone" \
  "$(cat "$doc")" 'applies unconditionally here'
check_absent "vendor-review.md: Usage no longer writes rounds to the dir an agy allow-rule covered" \
  "$(cat "$doc")" '--out private/audit-harness/out'
check_absent "agy.sh's header no longer claims 'The model has NO tool access' unqualified" \
  "$(cat "$client")" 'The model has NO tool access'
pin "vendor-review.md states the Linux per-argument cap (131071)" "$doc" '131071' \
  "expected Usage/the rails to state B3's Linux cap"
pin "vendor-review.md states the default --out (.keel/vendor-review)" "$doc" '.keel/vendor-review' \
  "expected Usage to state B6's default round location"
pin "vendor-review.md states the agy allow-rule refusal (permissions.allow)" "$doc" 'permissions.allow' \
  "expected a rail for B9"
pin "vendor-review.md states B9's scope limit (MCP servers / plugins are not checked)" "$doc" 'MCP' \
  "expected the O-2 limit in the docs, never 'no tool access' unqualified"
# The whole file PLUS the changelog.d/ fragments (dir #744), never the live [Unreleased] section and never
# one fragment: the release cut empties that section and deletes the fragments.
check_contains "CHANGELOG carries a bullet citing dir #662" \
  "$(cat "$REPO_ROOT/CHANGELOG.md"; bash "$REPO_ROOT/tools/self/changelog-fragments.sh" --repo "$REPO_ROOT")" 'dir #662'

summary
