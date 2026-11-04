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
pin "G1 labels a disclaimed pick a candidate, not a pain" \
  "$doc" 'is a candidate, not a pain' \
  "expected G1 to keep the candidate rule for a pick the operator cannot confirm (dir #542)"
pin "G1 candidate's first ticket is a live verification with a number per symptom" \
  "$doc" '**a number per symptom**' \
  "expected G1 to require a measured number per symptom before a slate (dir #542)"
pin "G1 a pick does not satisfy an 'operator has seen X' unpark condition" \
  "$doc" 'is **not** satisfied by a' \
  "expected G1 to keep a selection from offered labels from satisfying an observation-shaped unpark condition (dir #542)"
pin "G1 labels the candidate row and quotes the disclaimer" \
  "$doc" 'The row is labelled `candidate`' \
  "expected G1 to require the candidate label on the row (dir #542)"
pin "G1 re-cuts the candidate slate from the numbers" \
  "$doc" 'The next groom re-cuts it from those numbers' \
  "expected G1 to have the next groom re-cut the slate from the verification numbers (dir #542)"
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

pin "dir #807: grooming.md G5 names the lint without a RELEASES.md path argument" "$doc" 'tools/self/value-claim-lint.sh <version>` (dir #672)' "expected the lint invocation to take a lone version"
check_absent "dir #807: grooming.md no longer passes the relative RELEASES.md to the lint" "$(cat "$doc")" 'value-claim-lint.sh RELEASES.md'

# dir #538: a G6 finding written into a ticket body carries its anchor; unread behaviour is TO VERIFY.
pin "dir #538: G6 requires a verification anchor on a finding written into a ticket body" "$doc" \
  'carries its verification anchor and states only what was verified' "expected the G6 anchor rule"
pin "dir #538: G6 writes an unread behavioural claim as TO VERIFY" "$doc" \
  'is written as `TO VERIFY: <claim>`' "expected the TO VERIFY marker rule"

# dir #541: G0 checks the opened row for `_` placeholders and the harvest for its OWN dated header.
pin "dir #541: G0 checks the previous release's opened row carries no placeholder" "$doc" \
  'carries no `_` placeholder' "expected the G0 opened-row placeholder check"
pin "dir #541: G0 checks the previous audit run's harvest sits under its own dated header" "$doc" \
  "sits under its OWN dated header" "expected the G0 harvest-header check"
pin "dir #541: G4(c) restates the own-header check" "$doc" \
  'header, never appended to an earlier run'"'"'s block (dir #541)' "expected G4(c) to carry the header duty"

# dir #467: G3's derive-don't-assert covers a release row's value claim; G5 points back to it.
pin "dir #467: G3 re-derives the value claim in the same edit as a ticket/stage-list change" "$doc" \
  'claim from the new list in the same edit, and strikes the old claim' "expected G3 to require re-deriving the claim from the new list in the same edit"
pin "dir #467: G3 strikes the old value claim rather than replacing it silently" "$doc" \
  '(~~struck through~~) instead of' "expected G3 to require the old claim struck, not silently replaced"
pin "dir #467: G3 cites its ticket for the value-claim rule" "$doc" \
  'rather than derived (dir #467).' "expected the G3 value-claim paragraph to cite dir #467 like its neighbours"
pin "dir #467: G5 points the value claim back at G3" "$doc" \
  "The claim is derived from the row's current" "expected G5's value-claim sentence to point at G3's derivation rule"

# dir #471: every release-row field that states a fact is derived at groom time; the pain stays G1's.
pin "dir #471: G3 scopes the general rule to row fields that state a fact about the tree or slate" "$doc" \
  'states a fact about the tree or the slate is' "expected G3's general row rule scoped to fact-stating fields"
pin "dir #471: G3 leaves the pain to the operator (G1)" "$doc" \
  "the pain stays the operator's (G1)" "expected G3 to except the pain field, which G1 gives to the operator"
pin "dir #471: G3 retakes the measurement and keeps the struck old figure dated" "$doc" \
  'the old figure is struck and kept with its date' "expected G3 to require the size measurement retaken, old figure struck and dated"
pin "dir #471: G5 points the size measurement back at G3" "$doc" \
  'size measurement is retaken from the planned-from commit' "expected G5 to name the measurement as derived from the planned-from commit"

# dir #472: the groom's own run record is drafted BEFORE the G6 round and handed to the reviewer.
pin "dir #472: G6 puts the run record inside the round's scope" "$doc" \
  '**The run record is inside the round, not after it (dir #472).**' "expected G6 to scope the run record into the review round"
pin "dir #472: G6 drafts the record row before the reviewer is handed the material" "$doc" \
  'is drafted before the reviewer is handed the material' "expected G6 to order the record draft before the hand-off"
pin "dir #472: G6 has the reviewer check the row's arithmetic against the file" "$doc" \
  "check the row's arithmetic against the file" "expected G6 to tell the reviewer to recount the record's numbers"
pin "dir #472: G7 points the row draft back at G6" "$doc" \
  'drafted before the G6 round (dir #472)' "expected G7 to place the row draft before the G6 round"

# dir #530: G6 records the two-vendor variant as an option, its three rails, the one-writer rule and two opposite data points.
pin "dir #530: G6 states the two-vendor variant is an option, not a default" "$doc" \
  'The two-vendor variant is an option, not a default (dir #530).' "expected G6 to keep the second vendor an operator-requested option"
pin "dir #530: G6 names the vendor-billed cost and the bundle leaving the machine" "$doc" \
  'a vendor round is vendor-billed and its bundle leaves the machine' "expected G6 to give the reason it is not a default"
pin "dir #530: G6 points the recipe at the project's cross-vendor harness, not a path" "$doc" \
  'cross-vendor harness; three rails hold' "expected G6 to name the harness generically"
pin "dir #530: G6 rail: bundle within the vendor's inline cap" "$doc" \
  "the bundle fits the vendor's inline cap" "expected the first of the recipe's three rails"
pin "dir #530: G6 rail: paths anonymized" "$doc" \
  'paths are anonymized' "expected the second of the recipe's three rails"
pin "dir #530: G6 rail: the leak gate runs over the bundle before it ships" "$doc" \
  'tools/secret-guard/secret-scan.sh -- <bundle>' "expected the third rail to name the scan command"
pin "dir #530: G6 one writer per round directory" "$doc" \
  '**One writer per round directory (dir #520).**' "expected the one-writer rule and its incident class"
pin "dir #530: G6 records the overwrite incident" "$doc" \
  'the relaunch overwrote the first run'"'"'s reply' "expected the incident that taught the rule"
pin "dir #530: G6 first data point: the second leg found text-level defects" "$doc" \
  'the second leg alone found two text-level defects' "expected the first data point"
pin "dir #530: G6 second data point: the second leg's accepted set was a subset" "$doc" \
  "the second leg's accepted findings were a strict subset of the first's" "expected the second data point"
pin "dir #530: G6 the second leg's value depends on the defect class" "$doc" \
  "the second leg's value depends on the defect class" "expected the non-complementarity statement"
pin "dir #530: G6 does not promote the variant on two runs" "$doc" \
  'Two runs do not make a pattern' "expected G6 to hold the option an option"
check_absent "dir #530: G6 no longer says the vendor round found more both times" "$(flatten_ws < "$doc")" 'had not, both times'
check_absent "dir #530: the doc cites no gitignored record for the two-vendor split" "$(flatten_ws < "$doc")" 'cut-readiness section'

# dir #535: an operator day-0 step carried undone across two consecutive grooms is re-asked as a three-way question.
pin "dir #535: G5 names the rule and forbids a third listing" "$doc" \
  'never listed a third time (dir #535).**' "expected G5 to carry the day-0 re-ask rule"
pin "dir #535: G5 defines a day-0 step" "$doc" \
  'A day-0 step is an operator action the plan puts' "expected G5 to define what a day-0 step is"
pin "dir #535: G5 records the incident's doubled weight" "$doc" \
  "meanwhile the step's weight had doubled" "expected G5 to name the re-sizing the carried step escaped"
pin "dir #535: G5 detects the carry with one grep over the previous plans' rows" "$doc" \
  "The check is one grep over the previous plans' rows for the step's name." "expected G5 to give the one-grep check"
pin "dir #535: G5 offers the three answers" "$doc" \
  '(1) do it now; (2) drop it from day 0 into a gated ticket; (3) re-assign it as an' "expected G5 to list the three answers"
pin "dir #535: G5 records the operator's answer and re-sizes the step" "$doc" \
  "records the operator's answer on the row, in the" "expected G5 to require a recorded answer, not a re-listed line"
pin "dir #535: G1 points at the rule as a question, not a list line" "$doc" \
  'is a question, not a list line (dir #535).' "expected G1 to point the operator-input rule at G5"

# dir #539: the budget field may mix units; `unmeasured` labels a part, never a whole row (G5, G7; R7 is the completing half).
pin "dir #539: G5 lets the budget field mix units" "$doc" \
  '**The budget field may mix units, and `unmeasured` labels a part, never a whole row (dir #539,' "expected G5 to allow mixed units in the budget field"
pin "dir #539: G5 gives the mixed-unit form" "$doc" \
  '"≈1.2M subagent tokens + 2 waves × +15–30% window"' "expected G5 to show the mixed-unit form"
pin "dir #539: G5 names the harness usage report as the harness's own, not shipped" "$doc" \
  "keel ships no reader for it, it is the harness's own" "expected G5 to name the usage report without claiming keel ships it"
pin "dir #539: G5 never lets a row collapse to unmeasured while a part was measured" "$doc" \
  'while any part of it was measured' "expected G5 to forbid the whole-row default"
pin "dir #539: G5 never converts or sums across units" "$doc" \
  'Units are not converted into each other or summed' "expected G5 to keep one comparison per unit"
pin "dir #539: G5 keeps a subagent token count apart from the weighted audit total" "$doc" \
  'not the weighted total the audit-pricing rules above' "expected G5 to keep the two token notions apart"
pin "dir #539: G5 keeps the figure measured, never invented" "$doc" \
  'an absent source is `unmeasured`, never a zero or a guess' "expected G5 to bar a fabricated figure"
pin "dir #539: G7 narrows the unmeasured default to a part nothing captured" "$doc" \
  'Record the cost in the unit it was measured in (G5, R7); `unmeasured` marks only a' "expected G7 to narrow the unmeasured default"
pin "dir #539: G7 bars the whole-row default while a source exists" "$doc" \
  'part nothing captured, never the row'"'"'s default while any measured source exists' "expected G7 to bar the row-wide default"

# dir #545: a SIZE target for a cut is size - what moves out + what the cut writes back (G5 value claim; G3 makes it derived).
pin "dir #545: G5 derives a size target as size less what moves out plus what the cut writes back" "$doc" \
  'is derived as the size, less what moves out, plus' "expected G5 to give the size-target formula"
pin "dir #545: G5 forbids the subtraction alone" "$doc" \
  'never as the subtraction alone (dir #545).**' "expected G5 to forbid size minus the moved section"
pin "dir #545: G5 ties the size target to the subject-set rule and G3" "$doc" \
  'instance of the subject-set rule above, a derived field under G3' "expected G5 to cite the sibling rule and G3 rather than restate G3"
pin "dir #545: G5 records the measured miss" "$doc" \
  '37,478 − 10,751 = 26,727 bytes' "expected G5 to carry the felt case's arithmetic"
pin "dir #545: G5 records the shipped size" "$doc" \
  'the shipped file was 30,429 bytes' "expected G5 to carry the shipped size"
pin "dir #545: G5 names the add-backs on the row" "$doc" \
  'the row names the add-backs by name' "expected G5 to require the add-backs listed by name"
pin "dir #545: G5 makes the residue checkable" "$doc" \
  'so the residue between the claim and the shipped size is checkable' "expected G5 to give the reason for naming the add-backs"

# dir #553: the budget field's operator-step count and audit universe are derived by formulas (G5); R1's intake reads them.
pin "dir #553: G5 names the two counts and the formula rule" "$doc" \
  'The budget field'"'"'s two counts, operator steps and the audit universe, are derived by fixed formulas,' "expected G5 to derive the two counts by formula"
pin "dir #553: G5 cites its ticket and incident" "$doc" \
  'not judged (dir #553, reading an adopter'"'"'s 0.7.0 row).**' "expected G5 to cite dir #553"
pin "dir #553: G5 adds no field" "$doc" \
  'new fields: the mixed-unit rule above says how the field states its figures' "expected the counts to read as part of the budget field, not new fields"
pin "dir #553: G5 derived under G3 without restating it" "$doc" \
  'its counts are derived, and both counts are derived under G3.' "expected G5 to cite G3 rather than restate it"
pin "dir #553: G5 operator-step formula" "$doc" \
  '- **Operator steps** = the sum over classes of chip clicks (workers + fixer), merges (PRs +' "expected the operator-step formula"
pin "dir #553: G5 each term follows from the slate" "$doc" \
  'the slate'"'"'s own numbers (N workers, N clicks; N PRs, N merges), so it is counted, never guessed.' "expected the terms derived from the slate's numbers"
pin "dir #553: G5 design-level steps on a separate line" "$doc" \
  'Design-level steps (an account, a login, a decision) go on a separate line above the sum.' "expected design-level steps kept out of the sum"
pin "dir #553: G5 a carried day-0 step is the three-way question" "$doc" \
  'its class or on the design line; one carried undone is the three-way question below, and after' "expected the dir #535 seam"
pin "dir #553: G5 audit-universe formula" "$doc" \
  '- **Audit universe** = the code files the spec or the ticket bodies name + one test module per code' "expected the audit-universe formula"
pin "dir #553: G5 fix-batch reserve" "$doc" \
  'file + the prose files touched + a fix-batch reserve of about 30% of that subtotal.' "expected the fix-batch reserve"
pin "dir #553: G5 priced at the nearest-sized run's per-file cost" "$doc" \
  'priced at the per-file cost of the nearest-sized measured run (its audit total over its own universe,' "expected the per-file pricing"
pin "dir #553: G5 cross-check, never a second line" "$doc" \
  'cross-check on the line the two-part rule above produces, stated beside it and never a second line;' "expected the per-file price reconciled with the two-part rule"
pin "dir #553: G5 R1 reads the same two counts" "$doc" \
  'R1'"'"'s intake check reads the same two counts.' "expected G5 to point at R1"

# dir #554: G5's design-economics report field carries two figures per spec and stays one field.
pin "dir #554: G5 carries two figures per spec" "$doc" \
  '**Design economics carries two figures per spec, because "accepted as first submitted" measures the' "expected G5 to name the two-figure rule"
pin "dir #554: G5 accepted-without-return and the design-level count" "$doc" \
  'spec: (1) accepted without return, yes or no; (2) the count of release-candidate-audit findings the' "expected G5 to list both figures"
pin "dir #554: G5 reads the count from the row's field, never memory" "$doc" \
  '`design-level findings, per spec` field ([`docs/delta-audit.md`](delta-audit.md) §8), mechanically,' "expected G5 to point at the row field in delta-audit section 8"
pin "dir #554: G5 reads the Escapes line beside it" "$doc" \
  'spec file, [`commands/go.md`](../commands/go.md)) is the implementation-time count of spec defects and' "expected G5 to read the escapes line beside the audit's"
pin "dir #554: G5 judges the mechanism on the second figure" "$doc" \
  'is read beside the audit'"'"'s. The judgment about the design-session mechanism is made on the second figure,' "expected G5 to move the judgment onto the second figure"
pin "dir #554: G5 stays one report field" "$doc" \
  'adds no field to the row.' "expected G5 to keep the field count"
pin "dir #554: commands/groom.md carries the two figures in its design-economics line" "$cmd" \
  "against two figures per spec: returned or not, and the audit's design-level findings" "expected the entrypoint to match G5's two figures"

# dir #555: G0's adopter-side reading of 'apply amendments directly into the procedure doc'.
pin "dir #555: G0 names the adopter-side reading and says doing both applies the amendment" "$doc" \
  'has applied its amendment (dir #555).** The procedure docs live in the engine, a checkout of a foreign' "expected G0 to name the adopter-side reading"
pin "dir #555: G0 says the practice settled across grooms and adopters" "$doc" \
  'session is a cross-repository change the groom is not scoped to open. One practice settled across ten' "expected G0 to call nine-plus grooms a practice, not a deviation"
pin "dir #555: G0 puts the project half in the adopter's own convention" "$doc" \
  'grooms on two adopters, and it is the rule: the PROJECT half of an amendment goes into the adopter'"'"'s own' "expected G0 to place the project half in the adopter's convention"
pin "dir #555: G0 files the generic half at the engine" "$doc" \
  'convention, the procedure doc that adopter actually reads; the GENERIC half is filed at the engine as a' "expected G0 to file the generic half at the engine"
pin "dir #555: G0 cites the project incident in the engine ticket" "$doc" \
  'ticket citing the project incident. A groom that does both has applied its amendment, and records the' "expected G0 to require the project incident in the ticket"
pin "dir #555: G0 keeps the direct landing where the engine is the project" "$doc" \
  'Where the engine is the project' "expected G0 to keep the direct landing for the engine's own grooms"

# dir #563: G2 reads the artifact before any record about it; G9 keeps the tag namespace a version and aligns a binary's version string.
pin "dir #563: G2 reads the artifact itself before any record about it" "$doc" \
  'string, a deployed config), the artifact itself, read with a tool, before any record about it. A' "expected G2 to put the artifact before the records"
pin "dir #563: G2 says records can agree and be wrong together" "$doc" \
  'all carry the same misreading of one string and agree with each other perfectly: in a downstream' "expected G2 to name the shared-misreading failure"
pin "dir #563: G2 records the incident outcome" "$doc" \
  'identifier. Four sources, one artifact, the artifact won. Records tell you where to look; they are' "expected G2 to carry the incident's outcome"
pin "dir #563: G2 says records are not the check" "$doc" \
  'not the check. The plan states the diff'"'"'s numbers and the rule applied, so a reader can tell a' "expected G2 to say a record is not the check"
pin "dir #563: G2 asks an operator-only premise in the same sitting" "$doc" \
  "G0's list of operator decisions (second flavour) is also where a premise only the operator can confirm" "expected G2 to route an operator-only premise to G0's decisions list"
pin "dir #563: G2 keeps archived bodies verbatim" "$doc" \
  'an argument for keeping archived bodies verbatim rather than summarised.' "expected G2 to argue for verbatim archive bodies"
pin "dir #563: G9 makes the tag namespace a version even without tags" "$doc" \
  'The tag namespace is a version (`0.N.0`), also on a project that has never tagged and runs no release' "expected G9 to keep the tag namespace a version"
pin "dir #563: G9 calls a sprint label a second convention" "$doc" \
  'manager: a sprint label (`S1`, `S2`) is not a scoped-down version, it is a second convention that the' "expected G9 to refuse sprint labels"
pin "dir #563: G9 starts a shipped binary's first release at its version string" "$doc" \
  'first release is aligning the binary'"'"'s own version string with the plan, and the groom reads that' "expected G9 to align the binary's version string first"
# dir #635 PR2: G7 carries the meta-share field for an infrastructure project, G0 reads the previous value.
pin "dir #635: G7's first field list gains the meta share and ledger colour" "$doc" \
  'groom with its ledger colour (the paragraph below).' "expected G7's row field list to name the meta-share field"
pin "dir #635: G7's release-less field list gains the meta share and ledger colour" "$doc" \
  'for an infrastructure project the meta share and ledger colour), and' "expected the release-less field list to carry the field too"
pin "dir #635: G7 names the field and restricts it to an infrastructure project" "$doc" \
  '**The meta-share field — for a project that is infrastructure for other projects, and only for it.**' "expected a G7 paragraph scoped to infrastructure projects"
pin "dir #635: G7 names the ledger colour rule and the PRINCIPLES ledger" "$doc" \
  'threshold: green at or under it, red above it. This is the net-negative ledger of' "expected the colour rule tied to the net-negative ledger"
pin "dir #635: G7 names the tool" "$doc" \
  '`tools/effort-share.sh --meta <repos> --product <repos> --since <previous groom'"'"'s ref or date>`: the' "expected G7 to name the instrument and its inputs"
pin "dir #635: G7 says the groom passes the repository lists" "$doc" \
  'groom passes both repository lists, and the tool hard-codes none.' "expected the groom, not the doc, to supply the repo lists"
pin "dir #635: G7 leaves the field out of a non-infrastructure project and makes the threshold project-set" "$doc" \
  'the field out. The threshold is set by the project, never by this doc. **Two consecutive readings' "expected the threshold to be project-set"
pin "dir #635: two readings above the threshold restrict the next release to conditions 1 to 4 of the bar" "$doc" \
  '([`docs/verification-economics.md`](verification-economics.md) §4), so no capability row that clears' "expected the restriction to cite the filing bar"
pin "dir #635: the restriction names which two readings count and cites conditions 1 to 4" "$doc" \
  'plans:** it takes only rows that meet one of conditions 1 to 4 of the filing bar' "expected the two readings and the condition range to be explicit"
pin "dir #635: G0 reads the previous row's meta-share value" "$doc" \
  "project only: the previous row's reading and this groom's own, both above the project's threshold," "expected G0 to read the previous meta-share reading"
pin "dir #635: the bar numbers condition 4 as Severe (the doc cites conditions 1 to 4)" "$REPO_ROOT/docs/verification-economics.md" \
  '4. **Severe:**' "expected the filing bar to still number Severe as condition 4"
pin "dir #635: the bar numbers condition 5 as Requested (excluded by the restriction)" "$REPO_ROOT/docs/verification-economics.md" \
  '5. **Requested:**' "expected the filing bar to still number Requested as condition 5"
check_absent "dir #635: the doc cites no personal registry file" "$(flatten_ws < "$doc")" 'INSTANCE.md'
check_absent "dir #635: the doc cites no personal knowledge-base path" "$(flatten_ws < "$doc")" '.keel/kb'

check_absent "dir #563: the doc names no other adopter project by name (sidecast)" "$(flatten_ws < "$doc")" 'sidecast'
check_absent "dir #563: the doc names no other adopter project by name (traverse)" "$(flatten_ws < "$doc")" 'traverse'
check_absent "dir #563: the doc cites no other project's ticket id" "$(flatten_ws < "$doc")" 'B.13'

summary
