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

# pin LABEL FILE PATTERN HINT — fixed-string, same helper shape as test_rails_honesty.sh's pin().
pin() {
  if grep -qF -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1" "$4"
  fi
}

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
if grep -qF '## Model & reasoning-effort selection' "$framework"; then
  pass "FRAMEWORK.md still carries the heading release-audit.md cites"
else
  fail "FRAMEWORK.md still carries the heading release-audit.md cites" \
    "renamed in FRAMEWORK.md? update docs/release-audit.md phase 4 too"
fi

pin "release-audit.md phase 7 cites publishing-checklist.md section 4" \
  "$audit" 'publishing-checklist.md`](publishing-checklist.md) §4' \
  "phase 7 names this section by number; if publishing-checklist.md's section 4 moved the citation is stale"
if grep -qE '^## 4\. ' "$checklist"; then
  pass "publishing-checklist.md still has a section 4 release-audit.md cites"
else
  fail "publishing-checklist.md still has a section 4 release-audit.md cites" \
    "renumbered in publishing-checklist.md? update docs/release-audit.md phase 7 too"
fi

# --- dir #140's own acceptance: every phase names its felt incident (a "Felt incident" tag), so a
# future edit can't quietly turn a phase back into unmotivated prose. Phase 0 is the one documented
# exemption (dir #140's own spec: it goes in near-verbatim, operator-ratified — a definition, not a
# design choice a felt incident shaped) — count it separately and require exactly one, rather than
# folding it into the felt-incident tally where its absence would be indistinguishable from a bug. ---
phase0_count=0
numbered_phase_count=0
while IFS= read -r line; do
  case "$line" in
    "## Phase 0 "*) phase0_count=$((phase0_count + 1)) ;;
    "## Phase "*) numbered_phase_count=$((numbered_phase_count + 1)) ;;
  esac
done < "$audit"
felt_count="$(grep -c 'Felt incident' "$audit")"

if [ "$phase0_count" -eq 1 ]; then
  pass "release-audit.md: phase 0 (the ratified state definition) is present"
else
  fail "release-audit.md: phase 0 (the ratified state definition) is present" \
    "found $phase0_count '## Phase 0' headings, expected exactly 1"
fi

if [ "$numbered_phase_count" -ge 7 ] && [ "$felt_count" -ge "$numbered_phase_count" ]; then
  pass "release-audit.md: every numbered phase (of $numbered_phase_count) names a felt incident ($felt_count tags)"
else
  fail "release-audit.md: every numbered phase names a felt incident" \
    "found $numbered_phase_count phase headings (excluding phase 0) but only $felt_count 'Felt incident' tags — dir #140's acceptance requires one per phase"
fi

summary
