#!/usr/bin/env bash
# test_grooming_doc.sh — dir #386: docs/grooming.md is the procedure for assembling a release from
# the backlog on a fixed cadence, closing the manager family's loop (/design -> /go ->
# /manage-release -> /delta-audit -> /groom -> feeds /design again); commands/groom.md is its thin,
# /go-sized entrypoint. Same idiom as test_release_management_doc.sh and test_delta_audit_doc.sh
# (fixed-string pins on BOTH legs of a naming coupling, so a rename on either side strands the
# citation loudly instead of silently) — the family shape the ticket's own binding test names: the
# command names the doc, the doc names the command back, and the doc carries anchors for G0, G3 and
# G6 (the three requirements most likely to be silently dropped in a rewrite).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="$REPO_ROOT/docs/grooming.md"
cmd="$REPO_ROOT/commands/groom.md"

check_file "docs/grooming.md exists" "$doc"
check_file "commands/groom.md exists" "$cmd"

# --- the mutual-reference pair: command names the doc, doc names the command back ------------------
pin "commands/groom.md names docs/grooming.md" \
  "$cmd" '](../docs/grooming.md)' \
  "expected the entrypoint to point at the doc it is a thin wrapper over"
pin "docs/grooming.md names commands/groom.md back" \
  "$doc" '](../commands/groom.md)' \
  "expected the doc to name its own entrypoint, per the drydock/delta-audit/release-management mutual-reference precedent"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ----------------
pin "docs/reference.md Docs index links docs/grooming.md" \
  "$REPO_ROOT/docs/reference.md" '[`docs/grooming.md`](grooming.md)' \
  "expected docs/reference.md's Docs index to list the new doc the way it lists drydock.md/delta-audit.md/release-management.md"

# --- the family cross-links: the manager-family loop this doc closes -------------------------------
pin "grooming.md links release-management.md" "$doc" '](release-management.md)' \
  "expected the doc to name the release-manager sibling its plan feeds work into"
pin "grooming.md links delta-audit.md" "$doc" '](delta-audit.md)' \
  "expected the doc to name the release-candidate-audit sibling"

# --- the binding test's own three required anchors: G0, G3, G6 -------------------------------------
pin "G0 anchor: retro first" \
  "$doc" '## G0 — retro first' \
  "expected a named G0 section — the requirement most likely to be compressed into one line in a rewrite"
pin "G0 requires amendments to be APPLIED, not reported" \
  "$doc" 'applied, not reported' \
  "expected G0 to keep the apply-not-report distinction explicit"
pin "G3 anchor: derive, don't assert" \
  "$doc" "## G3 — derive, don't assert" \
  "expected a named G3 section"
pin "G3 states a ticket's release tag is never asserted in prose" \
  "$doc" 'Never assert a specific release tag in prose' \
  "expected G3 to carry the tag-citation rule, not just the count-regeneration rule"
pin "G6 anchor: fresh-reviewer adjudication is mandatory" \
  "$doc" '## G6 — a fresh-reviewer adjudication round is mandatory' \
  "expected a named G6 section"
pin "G6 states the round is not optional polish" \
  "$doc" 'not optional polish' \
  "expected G6 to state plainly that this round is required, not a nice-to-have on top of G0-G5"

# --- the other numbered requirements, so a wholesale drop of one doesn't pass silently --------------
for g in \
  "## G1 — pains are the input, and only the operator supplies them" \
  "## G2 — read ticket bodies, not headings" \
  "## G4 — the hygiene sweep" \
  "## G5 — every release row, five fields" \
  "## G7 — the releases cross-run record" \
  "## G8 — cadence-bound, never a daemon" \
  "## G9 — portability"
do
  pin "requirement heading present: ${g#\#\# }" "$doc" "$g" \
    "expected every numbered requirement (G0-G9) to survive compression as its own heading"
done

# --- G0's read-trace input degrades cleanly when the mechanism doesn't exist -------------------------
pin "G0 states the read-trace aggregate is consumed generically, by pointer" \
  "$doc" 'by pointing at' \
  "expected G0 to consume the read-trace aggregate by pointing at its tool, never by hardcoding a path or format"
pin "G0 states the read-trace input degrades cleanly when absent" \
  "$doc" 'Degrade cleanly when it does not exist yet' \
  "expected G0 to say explicitly what happens when the aggregate mechanism isn't installed"

# --- G4(a): the standing list is named, and its own filing-bar source is cited ----------------------
pin "G4(a) names the Standing list section" "$doc" '## Standing list' \
  "expected G4(a) to name keel's own instance of the standing list by its literal section heading"
pin "G4(a) cites the filing bar it satisfies" "$doc" 'verification-economics.md' \
  "expected G4(a) to cite the doc whose filing bar makes the standing list necessary"

# --- G7: the cross-run record names its per-project location and its audit-record sibling -----------
pin "G7 names keel's own releases cross-run record path" "$doc" 'private/releases/RUNS.md' \
  "expected G7 to name keel's own instance of the record, same as R7/A6 name private/audit/RUNS.md"
pin "G7 states cost may be recorded unmeasured, never fabricated" "$doc" 'never a fabricated zero' \
  "expected G7 to preserve the unmeasured-not-fabricated convention shared with the audit record"

# --- naming-collision acknowledgment (plain text, no backticked slash-command form — dir #385's own
# felt incident, a backtick-wrapped /keel-* citation trips doctor.sh's dir #129 dead-reference check)
# and portability (no keel-only absolute paths), looped over both files ------------------------------
for f in "$doc" "$cmd"; do
  label="${f#"$REPO_ROOT"/}"
  body="$(cat "$f")"
  check_contains "$label acknowledges the collision alias" "$body" "keel-groom"
  check_absent "$label never backtick-wraps the collision alias as a slash command" "$body" '`/keel-groom`'
  check_absent "$label carries no absolute keel-checkout path" "$body" '/Users/'
done

pin "grooming.md names the -> <version> heading-tag convention" "$doc" \
  '`→ <version>`' \
  "expected G9 to name the portable release-slate convention, not keel's own release-plan table"
pin "grooming.md names the -> pool heading-tag convention" "$doc" \
  '`→ pool`' \
  "expected G9 to name the portable pool-lane convention"

# --- the entrypoint stays thin: a pointer-and-checklist, not a second copy of the procedure ----------
pin "groom.md states it is a pointer, never a restatement" "$cmd" \
  'never a restatement' \
  "expected the same never-a-restatement framing the sibling entrypoints use for their own docs"

# --- self-revision: grooming.md is subject to its own G0, same as release-audit/delta-audit/drydock --
pin "grooming.md carries a self-revision clause" "$doc" '## Self-revision clause' \
  "expected the doc to state it revises itself via its own G0, same discipline it asks of its siblings"

# --- first-run G0 amendments (2026-09-06): the two G0/G3 clauses the first /groom paid for ----------
pin "G0 distinguishes shipped from installed for an opt-in mechanism" "$doc" \
  'not a dead-doc signal' \
  "expected G0 to state that an opt-in mechanism's empty aggregate is a missing sensor, not a signal"
pin "G3 states the last-arrow tag-extraction rule" "$doc" \
  'token on the heading that names a release or the pool' \
  "expected G3 to name the extraction rule that removes phantom release tags from prose arrows"
pin "G3 names acceptance-leg tickets as obligations, never re-tagged" "$doc" \
  'acceptance obligation of' \
  "expected G3 to keep a just-shipped release's open acceptance legs out of the build count"

# --- dir #760: the command carries the 0.15.0 groom's G1/G5 amendments by pointer --------------------------
pin "groom.md G1 carries the picked-label rule" "$cmd" \
  'recorded as a picked label' \
  "expected the command's G1 to point at the doc's picked-label rule (dir #760)"
pin "groom.md G5 carries the estimate-weights rule" "$cmd" \
  'names its weights' \
  "expected the command's G5 to point at the doc's weighting rule (dir #760)"

# --- dir #823 items 3 and 5: the vendor round's order, vendor claims verified, self-referential counts -------------
pin "G3 re-measures a self-referential count after the groom's last edit" "$doc" \
  '**A count over a file the groom is itself editing is stale the moment the groom writes about it (dir #823).**' \
  "expected G3 to carry the re-measure-after-the-last-edit rule and its counting-rule clause (dir #823 item 5)"
pin "G3 states the counting rule beside the figure" "$doc" \
  'and state the counting rule beside the figure' \
  "expected G3 to require the counting rule next to the figure (dir #823 item 5)"
pin "G6 runs the vendor round AFTER the same-family round's fixes" "$doc" \
  "**Run it AFTER the same-family round's fixes are applied, never beside it (dir #823).**" \
  "expected G6 to order the vendor round after the same-family round (dir #823 item 3)"
pin "G6 verifies a vendor's severities and tool claims" "$doc" \
  '**Verify what a vendor says as you' \
  "expected G6 to require verifying vendor severities and claims about tools (dir #823 item 3)"
pin "G6 has the reviewer diff each decision against its table row" "$doc" \
  'diff every decision against the' \
  "expected G6 to carry the prose-versus-table check (dir #823 item 3)"

# --- dir #842 slice 4: G0 sweeps the guards' bypass registers ---------------------------------------------------
# The step's wiring (`accumulate.sh due --owner guards` and `bypass-scan.sh` in the doc's G0 section and the command's G0
# block) is pinned, with misplacement mutants, by tests/test_model_decay_wiring.sh (c'). Pinned here: what that does not
# cover — the data-dir surface, the closure order, the data-dir override and the candidate file's privacy.
g0_doc="$(section_body '## G0 — retro first' "$doc")"
check_contains "docs/grooming.md G0 names bypass-scan.sh data-dir" "$g0_doc" 'bypass-scan.sh data-dir'
check_contains "docs/grooming.md G0 names the data-dir override KEEL_GUARDS_ACCUM_DIR" "$g0_doc" 'KEEL_GUARDS_ACCUM_DIR'
check_contains "docs/grooming.md G0 names accumulate.sh closed (a promoted class is looked up in the backlog)" "$g0_doc" 'accumulate.sh closed'
check_contains "docs/grooming.md G0 names accumulate.sh fixed (without it a recurrence is never due)" "$g0_doc" 'accumulate.sh fixed'
check_contains "docs/grooming.md G0 keeps the scan's candidates out of every repository" "$g0_doc" 'outside every'

# --- dir #860 A5: G5 scales a total by a measured counterfactual of a procedure change, and the command points at it -----
b5_needle='**A procedure change between the two releases scales that total'
pin "G5 scales the previous total by a procedure change's measured counterfactual (dir #860)" "$doc" "$b5_needle" \
  "expected G5 to carry the counterfactual-scaling rule after the audit paragraph"
b5="$(para_of "$doc" "$b5_needle")"
check_contains "G5's counterfactual rule says a counterfactual is re-based on a change that ran after it (dir #860)" "$b5" 're-based'
pin "groom.md G5 points at the measured-counterfactual rule (dir #860)" "$cmd" \
  'measured counterfactual (G5)' \
  "expected the command's G5 to point at the doc's counterfactual-scaling rule"

summary
