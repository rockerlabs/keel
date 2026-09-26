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

check_file "docs/vendor-review.md exists" "$doc"
check_file "tools/vendor-review.sh exists and is executable" "$tool"
[ -x "$tool" ] && pass "tools/vendor-review.sh is executable" || fail "tools/vendor-review.sh is executable" "not +x"
check_file "tools/vendor-review/agy.sh exists" "$client"
[ -x "$client" ] && pass "tools/vendor-review/agy.sh is executable" || fail "tools/vendor-review/agy.sh is executable" "not +x"

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

summary
