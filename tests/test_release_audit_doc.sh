#!/usr/bin/env bash
# test_release_audit_doc.sh — dir #140/#143: docs/release-audit.md and commands/backlog.md's
# target-release-label steps reference each other and two other docs' section headings by name.
# Same idiom as test_rails_honesty.sh (fixed-string pins) and test_doc_figures.sh's droppable-heading
# loop (pin BOTH legs of a naming coupling) — a rename on either side of any of these couplings would
# otherwise strand the citation silently, exactly the class of drift dir #85's docs layer audited for.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

audit="$REPO_ROOT/docs/release-audit.md"
backlog_cmd="$REPO_ROOT/commands/backlog.md"
framework="$REPO_ROOT/FRAMEWORK.md"
checklist="$REPO_ROOT/docs/publishing-checklist.md"
readme="$REPO_ROOT/README.md"

check_file "docs/release-audit.md exists" "$audit"
check_file "commands/backlog.md exists" "$backlog_cmd"
check_file "FRAMEWORK.md exists" "$framework"
check_file "docs/publishing-checklist.md exists" "$checklist"
check_file "README.md exists" "$readme"

# --- README discoverability: a new adopter-usable doc that isn't linked from the Docs index is as
# good as unshipped (same class dir #85's docs layer would have flagged). ------------------------
pin "README Docs section links docs/release-audit.md" \
  "$readme" '[`docs/release-audit.md`](docs/release-audit.md)' \
  "expected the Docs section to list release-audit.md the way it lists rollout-audit.md/going-public.md"

# --- commands/backlog.md carries the two new steps release-audit.md's phase 2 hands work to -------
pin "backlog.md: step 3b (target-release label) exists" \
  "$backlog_cmd" '**3b. Read the target-release label' \
  "expected a step 3b reading the trailing arrow label, cited by release-audit.md phase 2"
pin "backlog.md: step 6 (release-tail grouping) exists" \
  "$backlog_cmd" '**6. Group by target release' \
  "expected a step 6 grouping items by the target-release label, cited by release-audit.md phase 2"

# --- the label syntax itself must be quoted identically on both sides of the coupling — a rewrite of
# one side's example format (e.g. dropping the arrow, or renaming `next` to `unreleased`) would
# silently desync what an operator triages against what /backlog groups by. --------------------------
for label in '`→ 0.6.1`' '`→ next`'; do
  pin "backlog.md step 3b quotes the label syntax: $label" "$backlog_cmd" "$label" \
    "step 3b's example label format no longer matches release-audit.md phase 2"
  pin "release-audit.md phase 2 quotes the same label syntax: $label" "$audit" "$label" \
    "phase 2's example label format no longer matches backlog.md step 3b"
done

# --- release-audit.md phase 2 names the exact steps it hands off to, not just the file -------------
pin "release-audit.md phase 2 names backlog.md step 3b" \
  "$audit" 'step 3b reads' \
  "expected phase 2 to name the exact backlog.md step (3b) that reads the label it writes"
pin "release-audit.md phase 2 names backlog.md step 6" \
  "$audit" 'step 6 groups by' \
  "expected phase 2 to name the exact backlog.md step (6) that groups by the label it writes"

# --- cross-doc section citations: release-audit.md names sections of two OTHER docs by heading text;
# pin both legs (the citation's wording AND the heading actually existing) the same way
# test_doc_figures.sh pins keel-setup's droppable-heading quotes against the template. -------------
pin "release-audit.md phase 4 cites FRAMEWORK.md's model-selection heading" \
  "$audit" 'Model & reasoning-effort selection' \
  "phase 4 names this heading; if FRAMEWORK.md renamed it the citation is now stale"
pin "FRAMEWORK.md still carries the heading release-audit.md cites" \
  "$framework" '## Model & reasoning-effort selection' \
  "renamed in FRAMEWORK.md? update docs/release-audit.md phase 4 too"

pin "release-audit.md phase 7 cites publishing-checklist.md section 4" \
  "$audit" 'publishing-checklist.md`](publishing-checklist.md) §4' \
  "phase 7 names this section by number; if publishing-checklist.md's section 4 moved the citation is stale"
if grep -qE '^## 4\. ' "$checklist"; then
  pass "publishing-checklist.md still has a section 4 release-audit.md cites"
else
  fail "publishing-checklist.md still has a section 4 release-audit.md cites" \
    "renumbered in publishing-checklist.md? update docs/release-audit.md phase 7 too"
fi

# --- dir #157: phase 7's description of the pending-release allowance vs. the code enforcing it ----
# Both halves shipped in dir #155's own PR and drifted anyway: phase 7 stated one condition, that PR's
# review then forced a second into tools/self/doctor.sh, and the paragraph was never revisited. Three
# delta rounds missed it (each sees only its own delta; the divergence opened between them); an
# operator-run /code-review caught it. Nothing coupled the two, so nothing could have.
#
# These three pins cover the DOC leg only; the code leg is covered behaviourally elsewhere — see the
# note below the pins for why that split is deliberate.
pin "release-audit.md phase 7 states the allowance's FIRST condition (newest heading)" \
  "$audit" 'it is the newest heading in the file' \
  "phase 7 must state both conditions self/doctor.sh enforces; see dir #157"
pin "release-audit.md phase 7 states the allowance's SECOND condition (version above every tag)" \
  "$audit" 'its version sorts above every existing tag' \
  "self/doctor.sh requires the pending section to out-sort every tag — if phase 7 stops saying so, a backport reader is told a rule the code does not implement (dir #157's felt incident)"
# Single-line fragment: the full sentence wraps across a line break, and these pins are fixed-string,
# so a longer phrase would fail on a reflow rather than a real deletion.
pin "release-audit.md phase 7 names the allowance's linear-release-line limit" \
  "$audit" 'linear release line' \
  "the version condition GAPs a legitimate backport cut below the newest tag; phase 7 must keep saying so, or the doc over-promises again"
# **The CODE leg is deliberately NOT pinned here** (decided by /simplify's altitude pass, verified
# empirically). A first version of this block also grepped `tools/self/doctor.sh` for the two conjuncts.
# It added no protection: `tests/test_self_doctor.sh` already covers both BEHAVIOURALLY, with the very
# fixture the review broke — deleting the version conjunct reds 3 of its assertions (measured). And it
# added real fragility, pinning expression SHAPE down to a trailing `&&`, so extracting the guard into a
# helper or reordering the conjuncts would red it while behaviour was identical — a second source of
# truth about the code's shape, the same smell `_addon_label`'s header in tools/pre-pr-gate.sh rejects.
# So: prose pinned here (nothing else covers it), behaviour pinned in test_self_doctor.sh, and a comment
# there naming this doc as the one that must agree.
#
# **Named limit of this guard, so nobody mistakes its reach:** these pins catch the DELETION of a stated
# condition, not the felt failure that motivated dir #157 — code GAINING a condition the doc never
# stated. Add a third conjunct to the allowance tomorrow and all three stay green while phase 7
# under-promises again. The real fix is the generated-embed shape this repo already uses for
# CORE.md ↔ templates/CLAUDE.md (tests/test_core_wrapper_sync.sh): have the conditions live once and
# transclude them into phase 7. Filed rather than built here — see dir #160.

# --- dir #140's own acceptance: every phase names its felt incident (a "Felt incident" tag), so a
# future edit can't quietly turn a phase back into unmotivated prose. Phase 0 is the one documented
# exemption (dir #140's own spec: it goes in near-verbatim, operator-ratified — a definition, not a
# design choice a felt incident shaped) — count it separately and require exactly one. Scoped PER
# PHASE SECTION, not as an aggregate count: an earlier version compared total "Felt incident" tags
# against total phase headings, which a phase with two tags and a phase with zero would both satisfy
# (found by review) — this walks each phase's own text, up to the next "## " heading, so a phase
# missing its own tag can't hide behind another phase's extra one.
phase0_count="$(grep -c '^## Phase 0 ' "$audit")"
numbered_phase_count="$(grep -c '^## Phase [1-9]' "$audit")"

if [ "$phase0_count" -eq 1 ]; then
  pass "release-audit.md: phase 0 (the ratified state definition) is present"
else
  fail "release-audit.md: phase 0 (the ratified state definition) is present" \
    "found $phase0_count '## Phase 0' headings, expected exactly 1"
fi

bare_phases="$(awk '
  /^## Phase [1-9]/ { if (phase != "" && !seen) print phase; phase = $0; seen = 0; next }
  /^## /            { if (phase != "" && !seen) print phase; phase = ""; next }
  /Felt incident/   { if (phase != "") seen = 1 }
  END               { if (phase != "" && !seen) print phase }
' "$audit")"

if [ "$numbered_phase_count" -ge 7 ] && [ -z "$bare_phases" ]; then
  pass "release-audit.md: every numbered phase (of $numbered_phase_count) names its OWN felt incident"
else
  fail "release-audit.md: every numbered phase names its own felt incident" \
    "phase(s) with no 'Felt incident' tag in their own section: ${bare_phases:-<none found — check numbered_phase_count=$numbered_phase_count>}"
fi

summary
