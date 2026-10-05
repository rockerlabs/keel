#!/usr/bin/env bash
# test_wrap_footprint_rule.sh — dir #628: pins the `/wrap` step 4 ("Footprint & drift-guard") obligation —
# a project over its startup-token budget with no live exception either trims in THAT wrap or writes a
# dated exception row; own project only; the row carries an expiry date and a ticket/note; an expired
# row is no longer live. Reads ${KEEL_WRAP_MD:-$REPO_ROOT/commands/wrap.md}; every case is shown red by
# re-invoking THIS file against a mutated SCRATCH copy via that override (no tracked file is edited).
# Each needle is ONE line of wrap.md (pin() is line-mode `grep -F`).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

wrap_md="${KEEL_WRAP_MD:-$REPO_ROOT/commands/wrap.md}"
SCRATCH_COPY_PREFIX="wrap-fp-copy"
MUTATION_SCRIPT="$REPO_ROOT/tests/test_wrap_footprint_rule.sh"
MUTATION_SKIP_VAR="KEEL_WRAP_FP_SKIP_MUTATIONS"

check_file "wrap.md target exists" "$wrap_md"

N_ACT='no live exception covers it'
N_TRIM='trim its `CLAUDE.md`/`MEMORY.md` in this wrap'
N_ROW='write a DATED exception row before finishing'
N_HOME='`## Footprint exceptions`'
N_SHAPE='`| Expires (YYYY-MM-DD) | Ticket/note |`'
N_OWN='its own project only'
N_FLEET='never a fleet-wide sweep'
N_EXPIRED='An expired row is not live'

pin "act: over budget with no live exception"  "$wrap_md" "$N_ACT"     "step 4 must name the 'no live exception' trigger"
pin "act: trim in this wrap"                     "$wrap_md" "$N_TRIM"    "step 4 must offer trimming CLAUDE.md/MEMORY.md in this wrap"
pin "act: or a dated exception row"              "$wrap_md" "$N_ROW"     "step 4 must offer the dated exception row"
pin "home: the exceptions section heading"       "$wrap_md" "$N_HOME"    "step 4 must name where the row lives"
pin "shape: Expires + Ticket/note columns"       "$wrap_md" "$N_SHAPE"   "step 4 must give the row shape (expiry + ticket)"
pin "scope: own project only"                    "$wrap_md" "$N_OWN"     "step 4 must scope the rule to the wrap's own project"
pin "scope: never a fleet-wide sweep"            "$wrap_md" "$N_FLEET"   "step 4 must forbid a fleet-wide sweep"
pin "expiry: an expired row is not live"         "$wrap_md" "$N_EXPIRED" "step 4 must say an expired row stops covering"

if [ -n "${!MUTATION_SKIP_VAR:-}" ]; then
  summary
  exit $?
fi

# Mutation proof: delete the line carrying each needle from a scratch copy; the suite must go red on it.
m_case() {
  local tag="$1" needle="$2" fail_label="$3" copy
  copy="$(scratch_copy "$wrap_md" wrap.md)"
  delete_line_containing "$copy" "$needle"
  assert_case_turns_red "mutation ($tag)" "$fail_label" "KEEL_WRAP_MD=$copy"
}
m_case act     "$N_ACT"     "act: over budget with no live exception"
m_case trim    "$N_TRIM"    "act: trim in this wrap"
m_case row     "$N_ROW"     "act: or a dated exception row"
m_case home    "$N_HOME"    "home: the exceptions section heading"
m_case shape   "$N_SHAPE"   "shape: Expires + Ticket/note columns"
m_case own     "$N_OWN"     "scope: own project only"
m_case fleet   "$N_FLEET"   "scope: never a fleet-wide sweep"
m_case expired "$N_EXPIRED" "expiry: an expired row is not live"

summary
