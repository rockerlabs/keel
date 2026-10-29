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
pin "G1 records each pain's provenance: stated" \
  "$doc" '`stated`: the operator' \
  "expected G1 to name the stated provenance value (dir #819)"
pin "G1 records each pain's provenance: accepted-on-proposal" \
  "$doc" '`accepted-on-proposal`: the agent proposed' \
  "expected G1 to name the accepted-on-proposal provenance value (dir #819)"
pin "G1 records each pain's provenance: carried" \
  "$doc" '`carried`: no pain behind the row' \
  "expected G1 to name the carried provenance value (dir #819)"
pin "G0 reads accepted-on-proposal as weaker evidence" \
  "$doc" 'is weaker' \
  "expected G0 to discount an accepted-on-proposal pain against a stated one (dir #819)"
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
  "## G5 — every release row, seven fields and two report fields" \
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
  "$doc" 'Degrade cleanly when the read-trace aggregate does not exist yet' \
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
# --- dir #820: a plan item outside the slate names its launcher; a hand census persists its predicate ---------
pin "G5 requires a launcher on every plan item outside the slate" "$doc" \
  '**Every plan item outside a release'"'"'s slate names who launches it and when (dir #820).**' \
  "expected G5 to require a named launcher for a 'parallel, not in the slate' item (dir #820)"
pin "G5 names the launcher forms" "$doc" \
  '`operator: /go <n> now`, `manager: wave N worker`, or `next groom`' \
  "expected G5 to list the launcher forms (dir #820)"
pin "G3 persists the predicate of a hand-derived census" "$doc" \
  'and persist the predicate you used' \
  "expected G3 to require a hand-derived census to persist its predicate (dir #820)"

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
# dir #853: the recipe names FELT, the one-time init, the missing scan cursor and the ticket tag (delete one, test red)
g0_flat="$(flatten_ws <<<"$g0_doc")"
check_contains "docs/grooming.md G0 states FELT yes for a real session (dir #853)" "$g0_flat" 'FELT is `yes` for a real session'
check_contains "docs/grooming.md G0 names the one-time init on the data dir (dir #853)" "$g0_flat" 'accumulate.sh --dir "$(bypass-scan.sh data-dir)" init'
check_contains "docs/grooming.md G0 says scan keeps no cursor (dir #853)" "$g0_flat" '`scan` keeps no cursor'
check_contains "docs/grooming.md G0 passes --since the previous scan's date (dir #853)" "$g0_flat" 'scan --since <the date the previous G0 scan ran>'
check_contains "docs/grooming.md G0 files the due class as [model-decay] (dir #853)" "$g0_flat" 'tagged `[model-decay]`'
check_absent "docs/grooming.md G0 no longer implies a cursor (dir #853)" "$g0_flat" 'since the previous scan (a re-scan'
cmd_flat="$(flatten_ws < "$cmd")"
check_contains "groom.md G0 carries --since (dir #853)" "$cmd_flat" "scan --since <the previous G0 scan's date>"
check_contains "groom.md G0 says no cursor (dir #853)" "$cmd_flat" '(no cursor;'
check_contains "groom.md G0 carries FELT yes (dir #853)" "$cmd_flat" 'FELT `yes`'
check_contains "groom.md G0 carries the init (dir #853)" "$cmd_flat" 'a one-time `accumulate.sh init`'
check_contains "groom.md G0 carries the [model-decay] tag (dir #853)" "$cmd_flat" 'tagged `[model-decay]`'

# --- dir #860 A5: G5 scales a total by a measured counterfactual of a procedure change, and the command points at it -----
b5_needle='**A procedure change between the two releases scales that total'
pin "G5 scales the previous total by a procedure change's measured counterfactual (dir #860)" "$doc" "$b5_needle" \
  "expected G5 to carry the counterfactual-scaling rule after the audit paragraph"
b5="$(para_of "$doc" "$b5_needle")"
check_contains "G5's counterfactual rule says a counterfactual is re-based on a change that ran after it (dir #860)" "$b5" 're-based'
pin "groom.md G5 points at the measured-counterfactual rule (dir #860)" "$cmd" \
  'measured counterfactual (G5)' \
  "expected the command's G5 to point at the doc's counterfactual-scaling rule"

# --- dir #872: G5 prices the audit in two parts (a fixed part per run, a part per slate ticket), measured -------------
# Every check runs on whitespace-joined text (a para_of paragraph, or a section_body piped through `tr`), so a needle may
# wrap in the doc; only the para_of anchors below must each sit on one line. Whole clauses, not one-word needles: a
# reversed clause ("never under" for "expected under", the band's ends swapped) must fail here.
g5_872="$(section_body '## G5 — every release row, seven fields and two report fields' "$doc" | flatten_ws)"
check_contains "G5 carries the two-part audit price (dir #872)" "$g5_872" \
  '**Price the audit in two parts, a fixed part per run and a part per ticket'
b872="$(para_of "$doc" '**Price the audit in two parts')"
while IFS= read -r n872; do
  [ -z "$n872" ] && continue
  check_contains "G5's two-part audit price carries: $n872 (dir #872)" "$b872" "$n872"
done <<'EOF'
grows more slowly
per-ticket part** is its whole-read legs' total over the slate tickets that release closed
counted once whatever its slices
not the delivered count G5's input-side rule divides by, because this line multiplies by a slate
fixed part** is the rest of its total
Both parts are of the audit session's own total, as the rule above prices it: a leg billed outside that session, such as another vendor's, is in neither
The legs' total is the sum of the whole-read legs' transcripts at the estimate's weights
session-cost.sh weighted
A harness's per-leg token count is the leg's final context, not its spend, and cannot stand in for it
The audit line is the previous audit's fixed part plus its per-ticket part times this slate's tickets
Its band runs from the smallest fixed part plus the smallest per-ticket part times that count to the largest of each, over the last three measured audits that can be split, or as many as exist
with one, the line is a point and says so
A slate smaller or larger than every measured one makes the line an extrapolation
A run whose whole-read legs' transcripts are not all found cannot be split: it stays out of the band, and if it is the previous audit, the line is its total per slate ticket times this slate's tickets, labelled unsplit, with no band
No measured audit at all → the line is unpriced, and the cell says so
A run that reaches GO in one pass is expected to come in under its line
EOF
# the retired floor's wording, and the run profile's rail (never publish a cross-leg cost-per-finding)
for n872 in 'never under' 'never below' 'a finding'; do
  check_absent "G5's two-part audit price does not carry: $n872 (dir #872)" "$b872" "$n872"
done
# B1 sits after the paragraph that prices from the previous session's total, so that paragraph's "next rule" points at it
la872="$(grep -n -F '**Price the audit from the previous audit session' "$doc" | head -1 | cut -d: -f1)"
lb872="$(grep -n -F '**Price the audit in two parts' "$doc" | head -1 | cut -d: -f1)"
if [ -n "$la872" ] && [ -n "$lb872" ] && [ "$lb872" -gt "$la872" ]; then
  pass "G5's two-part audit price sits after the previous-session paragraph (dir #872)"
else
  fail "G5's two-part audit price sits after the previous-session paragraph (dir #872)" "lines: previous-session=${la872:-none} two-part=${lb872:-none}"
fi
# the floor is gone, the previous-session paragraph changed and kept its subtraction
check_absent "G5 no longer carries the floor: Never scale the audit below (dir #872)" "$(flatten_ws < "$doc")" 'Never scale the audit below'
check_absent "G5 no longer carries the floor: smallest of the last three measured audit (dir #872)" "$(flatten_ws < "$doc")" 'smallest of the last three measured audit'
check_absent "groom.md no longer carries the floor (dir #872)" "$(flatten_ws < "$cmd")" 'never below the smallest of'
b1a872="$(para_of "$doc" '**Price the audit from the previous audit session')"
check_contains "G5's previous-session paragraph points at the split (dir #872)" "$b1a872" \
  'the next rule splits it into a fixed part and a part per ticket'
check_contains "G5's previous-session paragraph keeps its subtraction (dir #872)" "$b1a872" \
  'Subtract that total from the release total before the per-unit division above'
check_contains "groom.md's G5 prices the audit line from the two parts (dir #872)" "$(para_of "$cmd" '**G5 — every release row')" \
  "the audit line the previous audit's fixed part plus its per-ticket part times the slate's tickets"
# The paragraph's figures: the three totals, the fixed parts, the per-ticket parts, the two back-test misses
# (the `method tool` block of dir #872's price script over the 0.15.0-0.17.0 audits; a figure from its other
# blocks, or the per-ticket-only misses in place of the two-part ones, fails)
while IFS= read -r n872; do
  [ -z "$n872" ] && continue
  check_contains "G5's two-part audit price states: $n872 (dir #872)" "$b872" "$n872"
done <<'EOF'
Keel's three runs (65.4M, 126.7M and 87.9M, each with a second pass)
fixed parts 32.3M, 43.5M and 40.3M
per-ticket parts 1.44M, 1.51M and 1.83M (23, 55 and 26 slate tickets)
missed 0.16.0 by -12% and 0.17.0 by -6%
missed them by +23% and -32%
EOF

summary
