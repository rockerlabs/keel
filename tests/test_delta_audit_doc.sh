#!/usr/bin/env bash
# test_delta_audit_doc.sh — dir #207 PR2: docs/delta-audit.md adopts tools/delta-audit/derive.sh into
# a full procedure, docs/release-audit.md's phase 6 becomes its caller, and docs/drydock.md's
# "Incremental runs" section gains a cross-reference distinguishing the two scopes. Same idiom as
# test_drydock_doc.sh (fixed-string pins on BOTH legs of a naming coupling) — with ONE deliberate
# upgrade: the rails-block pin is a block-extract-and-diff, not a substring-presence check. dir #209
# found exactly that class of gap in test_drydock_doc.sh itself — three injected drifts, one deleting
# a contract line outright, all left that suite green — and this ticket's own spec says do it right
# the first time here rather than shipping the same gap into a second doc.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="$REPO_ROOT/docs/delta-audit.md"
delegation="$REPO_ROOT/docs/delegation.md"
release_audit="$REPO_ROOT/docs/release-audit.md"
drydock="$REPO_ROOT/docs/drydock.md"
reference="$REPO_ROOT/docs/reference.md"
derive="$REPO_ROOT/tools/delta-audit/derive.sh"

check_file "docs/delta-audit.md exists" "$doc"
check_file "docs/delegation.md exists" "$delegation"
check_file "tools/delta-audit/derive.sh exists" "$derive"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ---------------
pin "docs/reference.md Docs index links docs/delta-audit.md" \
  "$reference" '[`docs/delta-audit.md`](delta-audit.md)' \
  "expected docs/reference.md's Docs index to list delta-audit.md the way it lists drydock.md"

# --- phase 6 <-> delta-audit.md, pinned on BOTH legs -----------------------------------------------
pin "release-audit.md phase 6 names docs/delta-audit.md" \
  "$release_audit" '](delta-audit.md)' \
  "phase 6 must point at the doc it now delegates to"
pin "delta-audit.md names release-audit.md phase 6 back" \
  "$doc" '](release-audit.md)' \
  "expected delta-audit.md to name its caller"

# --- done-criterion 7: phase 6 no longer asserts an inclusion rule chosen by judgment --------------
check_absent "phase 6 no longer says its mandate picks scope by judgment (present tense)" \
  "$(cat "$release_audit")" 'scoped to exactly three checks'
pin "phase 6 states the inversion explicitly" \
  "$release_audit" 'never again the rule that' \
  "expected phase 6 to say what changed, not just link elsewhere"

# --- drydock.md's incremental-runs section distinguishes itself from this doc's scope --------------
pin "drydock.md's Incremental runs section cross-references delta-audit.md" \
  "$drydock" '](delta-audit.md)' \
  "expected the two incremental-scope shapes to be told apart in prose"
pin "delta-audit.md names drydock.md back" "$doc" '](drydock.md)' \
  "expected delta-audit.md to name its same-machinery sibling"

# --- the script this doc adopts, named by real path (also feeds doctor.sh's tool-wiring check) -----
pin "delta-audit.md names tools/delta-audit/derive.sh by its real path" \
  "$doc" 'tools/delta-audit/derive.sh' \
  "expected phase 1 to name the shipped script"

# --- the required-diversity-leg rail, cited not restated -------------------------------------------
# dir #230: this pin used to read 'dir #230' — a section anchor into a gitignored backlog no adopter
# can open. The doctrine now ships as a real doc, and BOTH legs of that coupling are pinned in
# tests/test_verification_economics_doc.sh, which declares itself the owner ("one link-pin per
# citer"). Not duplicated here: two files pinning the identical fixed string against the identical
# file add no coverage and give a rename two places to break — the same call, for the same reason,
# as the delegation.md coupling twenty lines below.

# --- the disclosure-only fix round's own hazard is stated, not just named --------------------------
pin "the disclosure-only round states the re-derive-don't-paraphrase hazard" \
  "$doc" 'inherits the imprecision of whatever it is written' \
  "expected section 10 to state its own hazard, not just name the round"

# --- self-revision clause: the same closing paragraph drydock.md and release-audit.md each carry ---
pin "delta-audit.md carries the self-revision clause" \
  "$doc" 'subject to its own phase-0 discipline: not a fixed verdict, a checklist to' \
  "expected the closing section to match drydock.md/release-audit.md's own self-revision wording"

# --- dir #231 items 1, 5, 6: lessons dir #207 already seeded into this doc — pinned here so the
# dir #231 retro doesn't reintroduce what already shipped (this doc is their canonical home) --------
pin "item 1 — the diversity leg is stated as required, not optional" \
  "$doc" 'The diversity leg is required, not optional' \
  "expected §5 to state the required-diversity-leg rail in these exact terms"
pin "item 5 — the universe is derived mechanically, not by judgment" \
  "$doc" ') does this mechanically' \
  "expected §3 to name the mechanical derivation the coverage ledger rests on"
pin "item 5 — every ledger row ends with exactly one verdict" \
  "$doc" 'Every ledger row carries a verdict' \
  "expected §8 to state the ledger-row completeness rule"
pin "item 6 — suite evidence excludes the operator's own main checkout" \
  "$doc" "Suite evidence comes from a clean worktree or CI, never the operator's own main checkout" \
  "expected §8 to state the clean-worktree-or-CI rail"

# --- dir #270: §8's coverage bar is reconciled with the doctrine's Clause A (a run can satisfy
# every ledger-completeness bullet while a diverse leg still owes Clause A's second silent round) --
pin "§8's coverage bar is distinguished from the doctrine's Clause A stopping rule" \
  "$doc" 'This bar is coverage, not stopping.' \
  "expected §8 to name which question the ledger bar answers and which it does not"

# --- dir #270: fields 5/6 (per-leg cost, induced/original) are during-the-run captures, assigned to
# the Protocol's report contract (rule 6) and the orchestrator's bookkeeping (§5), not left for
# run-record.md's stub to reconstruct at verdict time -----------------------------------------------
pin "Protocol rule 6 assigns the induced/original mark to each finding as it's written" \
  "$doc" 'Mark each finding `induced`' \
  "expected §4 rule 6 to capture field 6 during the run, not defer it to verdict time"
pin "§5 assigns per-leg cost bookkeeping to the orchestrator" \
  "$doc" "includes the run profile's" \
  "expected §5 to assign field 5's during-the-run capture, not leave it to run-record.md's stub"

# --- dir #231 item 2: this doc's diversity leg is the worked instance delegation.md's generalized
# blind-then-reconcile section points at. The reciprocal pin (this same fact, checked against this
# same file) lives in tests/test_delegation_doc.sh, not duplicated here (an efficiency review of the
# first draft found both files pinning the identical fixed string against the identical file for no
# added coverage) — that file already owns both legs of this coupling. --------------------------------

# --- dir #256: docs/reference.md's derive.sh row was on dir #207 PR2's own edit list and never got
# it — it still called this doc "not yet shipped" one release after it shipped. Pin both halves: the
# stale claim is gone, and the row now links the doc instead. ----------------------------------------
check_absent "reference.md's derive.sh row no longer calls delta-audit.md 'not yet shipped'" \
  "$(cat "$reference")" 'not yet shipped'
pin "reference.md's derive.sh row links delta-audit.md" \
  "$reference" '[delta-audit](delta-audit.md)' \
  "expected the derive.sh row to link the doc now that it has shipped, matching the drydock.md row's own inline-link shape"

# --- the rails block: BLOCK-EXTRACT every copy and diff against the canonical source, never a
# substring-presence check. dir #209's own finding against test_drydock_doc.sh's block-extract helper
# is the class
# this guards against: a substring pin can survive a drift that deletes or reorders a contract line,
# because "the text is somewhere in the file" says nothing about whether it is INTACT. -------------
# extract_rails_block/check_block_equal live in tests/lib.sh (dir #375): promoted once a third file
# needed the exact same awk range this file had defined independently alongside test_drydock_doc.sh.
canonical_rails="$(extract_rails_block "$delegation")"
check_contains "docs/delegation.md's own rails block is non-empty (sanity check on the extractor)" \
  "$canonical_rails" "DELEGATION RUN"

doc_rails_all="$(extract_rails_block "$doc")"
copies_in_doc="$(printf '%s\n' "$doc_rails_all" | grep -c '^- DELEGATION RUN:')"
if [ "$copies_in_doc" -eq 5 ]; then
  pass "delta-audit.md carries exactly 5 rails-block copies (1 canonical + 1 per of 4 prompts)"
else
  fail "delta-audit.md carries exactly 5 rails-block copies (1 canonical + 1 per of 4 prompts)" \
    "found $copies_in_doc"
fi

# Build the expected blob: the canonical block repeated once per copy actually found (so a MISSING
# copy is caught by the count check above, not silently accepted here by asking for fewer copies).
expected="$(for _ in $(seq 1 "${copies_in_doc:-0}"); do printf '%s\n' "$canonical_rails"; done)"
if [ "$doc_rails_all" = "$expected" ]; then
  pass "every rails-block copy in delta-audit.md is byte-identical to docs/delegation.md's canonical text"
else
  fail "every rails-block copy in delta-audit.md is byte-identical to docs/delegation.md's canonical text" \
    "block-extracted text differs — a substring pin would not have caught this; diff the two extractions by hand"
fi

# --- each of the 4 prompt templates individually carries a rails-block copy (catches a drift that
# drops the block from ONE prompt while leaving the total-count check above satisfied by accident,
# e.g. a copy-paste duplicating one prompt's block into another) ------------------------------------
for pair in \
  "S1:You are S1 for a delta audit" \
  "S2:You are S<n> for a delta audit" \
  "diversity leg:You are the diversity leg for a delta audit" \
  "S-final:You are the verifier for a delta audit"
do
  role="${pair%%:*}"; marker="${pair#*:}"
  prompt_block="$(awk -v m="$marker" -v RS='```' 'index($0, m) { print; exit }' "$doc")"
  check_contains "the $role prompt carries the DELEGATION RUN line" "$prompt_block" "DELEGATION RUN"
  check_contains "...and the read-only rail" "$prompt_block" "You are read-only"
done

# --- §10's narrower form, evidenced by two runs (v0.8.2 batch 1, v0.8.3 platform flip) --------------
pin "the disclosure-only round states the neighbouring-claim rule" "$doc" \
  'neighbouring claim in the same sentence it touches' \
  "expected section 10 to bind a correction to every claim in the sentence it edits, not only the fixed one"
pin "the disclosure-only round states the measuring-platform axis" "$doc" \
  'the platform it was measured on, or measures both' \
  "expected section 10 to require a platform-dependent correction to name or cover its platform"

# --- dir #724: the mutation mandate carries a size rule for per-mutant artifacts ---------------------
# A mutation leg that keeps one build artifact per mutant fills the disk (felt: 4-10 GB per leg, never
# deleted). Each clause is pinned separately so a trim of one cannot hide behind the others.
pin "mutation size rule: keep artifacts of SURVIVING mutants only" "$doc" \
  'artifacts of **surviving** mutants only' \
  "expected item 5 to bind a mutation leg to keep only surviving mutants' artifacts"
pin "mutation size rule: delete the killed mutants' artifacts per iteration" "$doc" \
  'deletes a killed mutant' \
  "expected item 5 to require per-iteration deletion of killed mutants' artifacts"
pin "mutation size rule: one shared build cache per leg" "$doc" \
  'one shared build cache per leg' \
  "expected item 5 to forbid a per-mutant build cache copy"
pin "mutation size rule: df floor before a leg starts" "$doc" \
  '`df` floor' \
  "expected item 5 to require a free-space check before a mutation leg starts"
pin "mutation size rule: the df floor is derived from what a leg was measured to leave (dir #760)" "$doc" \
  'floor is twice the largest total' \
  "expected item 5 to give the df floor a derivation, not a bare number"
pin "mutation size rule: the df floor names its fallback value, 20 GB until measured (dir #760)" "$doc" \
  'so 20 GB until' \
  "expected item 5 to give the df floor a value to use before a leg has been measured"
pin "mutation size rule: the report states what the leg left and hands over the rm -rf" "$doc" \
  'hands the operator the `rm -rf`' \
  "expected item 5 to make the leg report what it left and give the operator the cleanup command"

# --- dir #759: the two leg rails ride every rails-block copy, byte-identical ------------------------
# They follow each copy's DELEGATION RUN line (outside extract_rails_block's range, so docs/delegation.md's
# canonical block and its other verbatim copies stay untouched). Block-extract and diff, as above.
leg_rails_all="$(awk '/^- Write only under your own scratch/,/shared daemon; dir #759/' "$doc")"
leg_copies="$(printf '%s\n' "$leg_rails_all" | grep -c '^- Write only under your own scratch')"
if [ "$leg_copies" -eq "${copies_in_doc:-0}" ] && [ "$leg_copies" -eq 5 ]; then
  pass "every one of delta-audit.md's 5 rails-block copies carries the leg rails (dir #759)"
else
  fail "every one of delta-audit.md's 5 rails-block copies carries the leg rails (dir #759)" \
    "found $leg_copies leg-rails copies vs ${copies_in_doc:-0} rails-block copies"
fi
leg_first="$(printf '%s\n' "$leg_rails_all" | awk 'NR>1 && /^- Write only under your own scratch/{exit} {print}')"
leg_expected="$(for _ in $(seq 1 "${leg_copies:-0}"); do printf '%s\n' "$leg_first"; done)"
if [ -n "$leg_first" ] && [ "$leg_rails_all" = "$leg_expected" ]; then
  pass "every leg-rails copy in delta-audit.md is byte-identical to the first (dir #759)"
else
  fail "every leg-rails copy in delta-audit.md is byte-identical to the first (dir #759)" \
    "leg-rails text differs between copies — diff them by hand"
fi
check_contains "leg rails: a per-leg scratch subdirectory" "$leg_first" "named for your leg"
check_contains "leg rails: never stop/kill/remove what you did not create" "$leg_first" "you did not create yourself"

pin "release-audit.md's cut step: the history entry states only events already on record (dir #759)" \
  "$release_audit" '**The entry states only events already on record.**' \
  "expected the cut step to forbid a history entry that states a waiver, GO or tag not yet recorded"

# --- dir #783: the delta-audit verifier's default mutation mandate (dir #673 (b)) ---------------------
# S-final carries a mutation mandate by default: one sweep range per verifier pass, GO through the §8
# dispositions only, one pin-gap ticket per run. Every needle is checked INSIDE the §5 paragraph (its bold
# heading line to the first blank line, flattened), never file-wide: "operator decision", "filing bar" and
# `fix-before-tag` already occur elsewhere in the doc, so a file-wide pin would pass on an unchanged doc.
# A needle that wraps across lines goes through the flattened paragraph, never `pin` (line-mode grep -F).
polish_md="$REPO_ROOT/commands/polish.md"
mm_para="$(awk '/^\*\*The verifier'"'"'s default mutation mandate \(dir #673\)\.\*\*/{f=1} f && /^$/{exit} f' "$doc" | tr '\n' ' ' | tr -s ' ')"
check_ne "the §5 mutation-mandate paragraph exists (dir #783)" "" "$mm_para"
for needle in \
  'carries the mandate by default' \
  'adds or changes a filter, threshold, guard or exclusion rule' \
  $'not only the ledger\'s `code` class' \
  'in its own mutation clone (§4 rule 5)' \
  'Each verifier pass sweeps its own range — the commits no earlier pass swept:' \
  '(from `<prev-rev>` when there is none yet)' \
  'from the end of the last `Mutation sweep:` line in the verdict record' \
  'fixed as `origin/main` resolves when the sweep starts' \
  '— unswept (GO moved during the pass)' \
  'no commit is swept twice' \
  $'listing each rule swept as `file:line — what it decides` with each mutant\'s outcome' \
  '≤ 4 mutants per rule and ≤ 40 per pass' \
  'the mutants whose survival would let through what the rule exists to stop come first, then diff order' \
  'recorded `unswept` with its count' \
  $'never carried into a later pass\'s list' \
  'Outside the bound, two more runs:' \
  'every `fix-before-tag` pin-gap finding still open in the record — a survivor, or a gap a leg proved — has its mutant re-run' \
  'every `Mutation candidate:` line in the reports written since the last `Mutation sweep:` line' \
  'a pin claim a leg filed as a finding with no executed mutant is read as one' \
  'gets one mutant' \
  'A rule no test pins is one finding, not one per mutant' \
  'the verifier records it in the verdict record and the orchestrator adds the row' \
  'a survivor in a safety guard, for one, is its condition 1' \
  'it bears on GO only as any finding does' \
  'An `unswept` count never blocks GO, and neither does a `killed` outcome taken at an earlier SHA' \
  'closes like any `fix-before-tag` finding (§8)' \
  $'the verifier\'s own reading of the rewritten rule and its tests, recorded with the reason' \
  'keeps the same finding open, never a new one' \
  'not a behavioural finding for Clause A' \
  'equivalent mutant' \
  'does not put that rule back on a list' \
  'What the mandate stops filing:' \
  'every pin-gap finding of one run dispositioned `ticket-next`' \
  'is staged in ONE ticket' \
  'filed `→ pool`' \
  'never a ticket per rule or per cluster' \
  'a `no-action` one goes to the standing list (§8), and any other disposition takes its own route' \
  '— nothing to sweep' \
  '— unswept (GO moved with no verifier pass)' \
  $'never the orchestrator\'s' \
  '— skipped (operator decision, <date>)' \
  'it ends that range' \
  $'reports the mandate\'s spend in its record' \
  $'a NO-GO leaves those commits to the next pass\'s range' \
  $'Every re-run and candidate outcome goes into that pass\'s `Mutation sweep:` line' \
  'no open `fix-before-tag` pin gap, no candidate' \
  'a `fix-before-tag` one is fixed in the run'
do
  check_contains "mutation mandate paragraph: $needle" "$mm_para" "$needle"
done
# A5: retired drafts' phrases must not return to the paragraph.
for retired in \
  'only when its brief asks for it' \
  'once per run' \
  'every earlier survivor' \
  'only if' \
  'candidates come first' \
  'killing test file' \
  'at most half' \
  'as a second line' \
  '— no qualifying rule`' \
  "in this pass's reports" \
  'sees every mutant of the rewritten rule' \
  'issues its verdict on a later SHA'
do
  check_absent "mutation mandate paragraph: retired phrase stays out: $retired" "$mm_para" "$retired"
done
# A2: §4 rule 6's `## NOT checked` bullet carries the candidate contract.
rule6="$(awk '/^6\. \*\*Report contract\*\*/{f=1} f && /^7\. /{exit} f' "$doc" | tr '\n' ' ' | tr -s ' ')"
for needle in \
  'is a finding only with an executed mutant' \
  'outcome in its evidence' \
  'starting `Mutation candidate:`' \
  "the verifier's sweep runs it (§5)"
do
  check_contains "§4 rule 6: candidate contract: $needle" "$rule6" "$needle"
done
# A3: the S-final prompt carries the range-and-candidates sentence and not the retired one-sweep clause.
sfinal_prompt="$(awk -v m='You are the verifier for a delta audit' -v RS='```' 'index($0, m) { print; exit }' "$doc")"
sfinal_flat="$(printf '%s' "$sfinal_prompt" | tr '\n' ' ' | tr -s ' ')"
for needle in \
  'Before you merge verdicts, run the default mutation mandate over your own range' \
  'every `Mutation candidate:` line written since the last `Mutation sweep:` line included' \
  'file each new survivor as a finding'
do
  check_contains "S-final prompt: $needle" "$sfinal_flat" "$needle"
done
check_absent "S-final prompt: the retired one-sweep-per-run clause is gone" "$sfinal_flat" "already carries this run's sweep"
# A4: the clone clause, the roles-table cells, and /polish's trigger (both legs pinned, so the two cannot drift).
pin "§4 rule 5: a leg that both reads and mutates keeps a separate mutation clone (dir #783)" "$doc" \
  'keeps a mutation clone used for nothing else, apart from what it reads' \
  "expected rule 5 to separate a leg's mutation clone from the clone it reads as ground truth"
sfinal_row="$(grep -F '| **S-final — verifier** |' "$doc")"
s2_row="$(grep -F '| **S2…Sn — whole-read + seam auditor** |' "$doc")"
div_row="$(grep -F '| **Diversity leg** |' "$doc")"
check_contains "S-final roles row: may touch its own mutation clone (dir #783)" "$sfinal_row" 'its own mutation clone'
check_contains "S2…Sn roles row: a mutation clone of its own (dir #783)" "$s2_row" 'a mutation clone of its own (§4 rule 5)'
check_contains "diversity roles row: a mutation clone of its own (dir #783)" "$div_row" 'a mutation clone of its own (§4 rule 5)'
pin "polish.md step 3 keeps the trigger phrase delta-audit.md reuses (dir #783)" "$polish_md" \
  'adds or changes a filter, threshold, guard or exclusion rule' \
  "expected commands/polish.md's mutation-pass trigger, the definition delta-audit.md's verifier mandate shares"

# --- dir #810: section 10 (the disclosure-only fix round) hands a correction's numbers to the claim lint --------
sec10="$(awk '/^## 10\. /{p=1; next} /^## 11\. /{p=0} p' "$doc")"
check_contains "section 10 names tools/self/changelog-claims.sh (dir #810)" "$sec10" "changelog-claims.sh"
check_contains "section 10 states the pre-cut pass condition (--strict --fragment)" "$sec10" "--strict --fragment"

# --- dir #872: section 7 says what a leg's cost follows and what a merge trades; section 5 records where a leg's transcript is
# Every check runs on whitespace-joined text, so a needle may wrap in the doc. Whole clauses, so a reversed clause fails.
s7_872="$(section_body '## 7. Sizing — a range, not a target' "$doc" | flatten_ws)"
while IFS= read -r n872; do
  [ -z "$n872" ] && continue
  check_contains "section 7 carries: $n872 (dir #872)" "$s7_872" "$n872"
done <<'EOF'
**no static measure of a cluster predicted its leg's cost.**
the leg's own turn count tracked its cost in both
suggested sessions (§3) set how many legs there are
pilot on a work-dense unit as that flow says, and let the pilots' measured spend, not a size rule, set what the legs cost
**A merge of clusters trades verification depth for cost.**
saves about the removed leg's cost, by spending fewer turns on each file
Price a merge as that range, from your own measured legs, put it into the plan, and let the operator pick it for the run
compares different releases and content, so it is no price
EOF
# the retired seam-count claim (unmeasured, contradicted by the legs), and the run profile's rail
for n872 in 'seam count and PR' 'seam-dense' 'expensive part of a whole-read' 'a finding'; do
  check_absent "section 7 does not carry: $n872 (dir #872)" "$s7_872" "$n872"
done
s5_872="$(section_body '## 5. Roles and legs' "$doc" | flatten_ws)"
check_contains "section 5's per-leg record names the transcript and sums spend from it (dir #872)" "$s5_872" \
  "token spend and where its transcript is (keel's own: the subagent's agent id) as it completes — spend summed from that transcript, since a harness's per-leg token count is the leg's final context"
check_contains "section 5's per-leg record keeps its unmeasured clause (dir #872)" "$s5_872" \
  "or \`unmeasured\` where the harness doesn't report it, never a fabricated zero"

# dir #815: Clause B's demotion ticket is staged by the verdict, so (b)'s harvest files it.
cb_815="$(awk '/^\*\*Clause B.s demotion ticket is staged by the verdict/{f=1} f && /^$/{exit} f' "$doc" | tr '\n' ' ' | tr -s ' ')"
for needle in \
  'never addressed to "the groom" in prose' \
  'or one class has now recurred across three or more runs' \
  'stages the demotion ticket in the run'"'"'s staged-tickets file like any other ticket draft' \
  'files it with no new step' \
  'is never weighed'
do
  check_contains "Clause B demotion-ticket paragraph: $needle (dir #815)" "$cb_815" "$needle"
done

summary
