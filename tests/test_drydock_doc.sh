#!/usr/bin/env bash
# test_drydock_doc.sh — dir #170: docs/drydock.md cites three sibling docs by section name, ships a
# tool by path, and hands its role prompts to agents as separate files. Same idiom as
# test_release_audit_doc.sh (fixed-string pins on BOTH legs of a naming coupling): a rename on either
# side would otherwise strand the citation silently — which is `broken-xref`, a finding class
# drydock.md itself defines. A doc that defines a defect class and then ships an instance of it is the
# one prose defect this repo should never merge twice.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/drydock.md"
audit="$REPO_ROOT/docs/release-audit.md"
rollout="$REPO_ROOT/docs/rollout-audit.md"
checklist="$REPO_ROOT/docs/publishing-checklist.md"
readme="$REPO_ROOT/README.md"
delegation="$REPO_ROOT/docs/delegation.md"
delta_audit="$REPO_ROOT/docs/delta-audit.md"
reference="$REPO_ROOT/docs/reference.md"
auditor="$REPO_ROOT/docs/drydock/auditor.md"
verifier="$REPO_ROOT/docs/drydock/verifier.md"
fixer="$REPO_ROOT/docs/drydock/fixer.md"
code_auditor="$REPO_ROOT/docs/drydock/code-auditor.md"

check_file "docs/drydock.md exists" "$doc"
check_file "docs/drydock/auditor.md exists" "$auditor"
check_file "docs/drydock/verifier.md exists" "$verifier"
check_file "docs/drydock/fixer.md exists" "$fixer"
check_file "docs/drydock/code-auditor.md exists" "$code_auditor"
check_file "tools/drydock/inventory.sh exists" "$REPO_ROOT/tools/drydock/inventory.sh"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ---------------
pin "README Docs section links docs/drydock.md" \
  "$readme" '[`docs/drydock.md`](docs/drydock.md)' \
  "expected the Docs section to list drydock.md the way it lists release-audit.md"

# --- the family cross-links, pinned on BOTH legs (the changelog claims they are two-way) ----------
pin "drydock.md links release-audit.md" "$doc" '](release-audit.md)' \
  "expected drydock.md to cite its release-readiness sibling"
pin "drydock.md links rollout-audit.md" "$doc" '](rollout-audit.md)' \
  "expected drydock.md to cite its rollout sibling"
pin "drydock.md links publishing-checklist.md" "$doc" '](publishing-checklist.md)' \
  "expected drydock.md to cite its publishing sibling"
pin "release-audit.md links drydock.md back" "$audit" '](drydock.md)' \
  "expected release-audit.md's family paragraph to name drydock as the fourth leg"
pin "rollout-audit.md links drydock.md back" "$rollout" '](drydock.md)' \
  "expected rollout-audit.md to point at the whole-tree prose pass its own insight implies"
pin "publishing-checklist.md links drydock.md back" "$checklist" '](drydock.md)' \
  "expected publishing-checklist.md's sibling paragraph to name drydock"

# --- the cited section of release-audit.md must keep its name ------------------------------------
# drydock.md rests its tier-1/tier-2 split on this heading twice; renaming it silently breaks both.
pin "release-audit.md still has the phase 0 heading drydock.md cites" \
  "$audit" '## Phase 0 — the state definition the whole flow rests on' \
  "drydock.md cites release-audit.md's phase 0 by name for the green-contracts state definition"

# --- the tool path the doc tells adopters to run -------------------------------------------------
pin "drydock.md names the inventory tool by its real path" \
  "$doc" 'tools/drydock/inventory.sh' \
  "expected the phase 0 command block to name the shipped script"
pin "docs/reference.md lists the inventory tool" \
  "$REPO_ROOT/docs/reference.md" '[`tools/drydock/inventory.sh`](../tools/drydock/inventory.sh)' \
  "expected the reference Tools table to carry the new shipped tool"

# --- the role prompts are reachable from the procedure -------------------------------------------
pin "drydock.md links the auditor prompt" "$doc" '](drydock/auditor.md)' \
  "expected the role-prompt section to link the auditor template"
pin "drydock.md links the verifier prompt" "$doc" '](drydock/verifier.md)' \
  "expected the role-prompt section to link the verifier template"
pin "drydock.md links the fixer prompt" "$doc" '](drydock/fixer.md)' \
  "expected the role-prompt section to link the fixer template"

# Block-extract two copies of a shared, meant-to-be-identical passage and confirm they agree, with a
# diff on failure — shared by the audit-file contract below and the rails block further down, so a
# renamed, reordered, or deleted line can't hide behind independent substring-presence pins the way
# dir #209's finding showed (FINDING-S2-3: three drifts injected into one copy, one deleting a
# contract line outright, left the old per-field loop's 36 checks fully green — presence isn't
# agreement). "$a" empty and "$b" empty would otherwise match, hence the non-emptiness check too.
check_block_equal() {
  local label="$1" a="$2" b="$3"
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    pass "$label"
  else
    fail "$label" "block-extracted text differs or is empty — diff:
$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"
  fi
}

# --- the audit-file contract is stated in two places on purpose; the phrasing must agree ---------
# drydock.md documents it for the operator, auditor.md hands it to the agent — drydock.md:97-98 says
# "the phrasing is deliberately identical so a diff between them is visible."
contract_block() { awk '/^# drydock audit —/,/^- <every fact/' "$1"; }
doc_contract="$(contract_block "$doc")"
auditor_contract="$(contract_block "$auditor")"
check_block_equal "drydock.md's audit-file contract is byte-identical to auditor.md's" \
  "$doc_contract" "$auditor_contract"

# The verifier's footer line is part of the contract drydock.md documents, so both must name it.
pin "drydock.md documents the verifier footer" "$doc" 'verifier: <model + effort>' \
  "expected the file-contract section to name the footer phase 2 appends"
pin "verifier.md writes the footer drydock.md documents" "$verifier" 'verifier: <your model + effort>' \
  "expected the verifier template to specify the footer line it appends"

# --- doc <-> template coherence (an independent review found all three of these live) -------------
# The templates are what an agent actually executes, so a rule the procedure states and the template
# omits is not a documentation nit — it is a rail that does not fire.

# Bookkeeping ownership: drydock.md phase 5 says fixer sessions do none, so the fixer template must
# not instruct one to mark findings fixed (its session also ends before the merge it would wait for).
pin "drydock.md: bookkeeping belongs to the orchestrator" \
  "$doc" 'Fixer sessions do no' \
  "phase 5 must keep the fixed: marks with the orchestrator"
check_absent "fixer.md does not tell the fixer to mark findings fixed" \
  "$(cat "$fixer")" 'mark `fixed: PR'
check_absent "...nor to wait for its own PR to merge" "$(cat "$fixer")" '**After the PR merges**'

# The sandbox rail's read-only exception: drydock.md says the rail "inherits" it, so the template
# that carries the rail has to carry the exception too, or a verifier writes an inverted `rejected`.
pin "drydock.md states the sandbox rail's exception" "$doc" 'it inverts' \
  "phase 2's sandbox rail must keep its read-only-machine-state carve-out"
pin "verifier.md carries that exception too" "$verifier" 'it inverts' \
  "the shipped verifier template must state the exception, not just the absolute rail"

# Which phases the orchestrator owns, stated in two places that disagreed once.
pin "the roles table lists the orchestrator's phases" "$doc" 'phases 0, 4, 6, 7' \
  "the roles table must match GATE-4, which hands phases 6 and 7 back to the orchestrator"
pin "GATE-4 hands back the same phases" "$doc" 'the orchestrator runs phases 6 and 7' \
  "GATE-4 must match the roles table's phase list"

# The shipped sweeps must survive a path git cannot print literally, and must not report every
# mailto link as dead — both reproduced against the previous wording.
pin "sweep 1 enumerates NUL-delimited" "$doc" "git ls-files -z '*.md' | xargs -0" \
  "a C-quoted path is unopenable, so the file would go silently unswept"
pin "sweep 2 enumerates NUL-delimited" "$doc" "git ls-files -z '*.md' | while IFS= read -r -d ''" \
  "same reason as sweep 1"
pin "sweep 2's class does not stop at a colon" "$doc" '\]\([^)#]+' \
  "excluding ':' truncates mailto:you@example.com to 'mailto', reported as a dead relative link"

# --- dir #231 item 3: a comment is a claim, not evidence — execute what it describes (home: this doc,
# mirrored into the auditor/verifier templates it hands to agents) ---------------------------------
pin "drydock.md's phase 1 rail 5 states the execute-don't-read rule" "$doc" \
  'A claim about executable behavior is not evidence' \
  "expected a numbered auditor rail stating the rule, per the doc's own 'these are the ones with a story' convention"
pin "rail 5 cites its felt incident, the correct ticket (dir #225, not #223/#224)" "$doc" \
  'felt incident (dir #225)' \
  "expected the delta-audit run's diversity-leg incident to be named with its real ticket -- BACKLOG.md: dir #225 is delta audit S8 blind pass F1; #223/#224 are two unrelated cross-vendor findings"
pin "phase 2's calibration note points at the rule rather than restating it" "$doc" \
  'reproduce" itself means execute, not re-read' \
  "expected the verifier's re-derivation section to point at phase 1's rail 5, not independently restate the rule"
pin "auditor.md's rails carry the same rule" "$auditor" \
  'A comment or contract note describing behavior is a claim, not evidence' \
  "expected the shipped auditor template to carry the rule the procedure states"
pin "verifier.md's re-derivation carries the same rule" "$verifier" \
  'not read the comment again more carefully' \
  "expected the shipped verifier template to say execute-not-reread"

# --- the auditor-rails intro must not claim EVERY rail is run-1's own, since rail 5 explicitly isn't
# (an independent agent review caught this doc contradicting itself — the exact `contradiction` class
# it defines as a prose defect) ----------------------------------------------------------------------
check_absent "the auditor-rails intro no longer claims every rail is run-1's own" \
  "$(cat "$doc")" 'rails, each of which run 1 needed ('
pin "rail 5 states it is not a run-1 incident" "$doc" 'Not a run-1 incident' \
  "expected rail 5 to disclaim the run-1 framing the intro no longer makes absolute"

# --- dir #204 PR2: scope C (code) joins the procedure as a fourth role template plus a Scope C
# section, and every surface PR1 left saying "prose only" gets corrected -----------------------------

pin "drydock.md now measures three scopes, not two" "$doc" 'It measures three scopes' \
  "PR1 shipped scope C; the phase-0 scope paragraph must say three, not two"
check_absent "the stale two-scopes wording is gone" "$(cat "$doc")" 'It measures two scopes'

pin "drydock.md links the code-auditor prompt" "$doc" '](drydock/code-auditor.md)' \
  "expected the role-prompt section to link the fourth template"
pin "reference.md now counts four drydock role-prompt templates" \
  "$reference" 'four [`docs/drydock/`](drydock/) role-prompt templates' \
  "PR2 ships a fourth template; the Extras section's count must follow"
check_absent "reference.md no longer undercounts at three" \
  "$(cat "$reference")" 'three [`docs/drydock/`](drydock/) role-prompt templates'

# --- the Scope C section itself: boundary, cadence, cost, diversity, ratchet ------------------------
pin "drydock.md has a Scope C section" "$doc" '## Scope C — code' \
  "What ships §3 requires a named Scope C section"
pin "Scope C states its boundary vs /polish's per-PR review" "$doc" \
  "Scope C's value is the classes a diff-scoped review structurally cannot" \
  "expected the boundary-vs-/polish framing this module's whole rationale rests on"
pin "Scope C states its boundary vs scope B" "$doc" \
  'default file sets are identical by design' \
  "expected the scope-B/scope-C overlap to be stated explicitly, not left implicit"
pin "Scope C states the disable spelling" "$doc" "DRYDOCK_SCOPE_C=':!*'" \
  "expected the canonical prose-only disable spelling, per F2's resolved fork"
pin "Scope C states the empty-string trap" "$doc" \
  'Unset or empty both mean the full' \
  "expected the doc to warn DRYDOCK_SCOPE_C= is NOT a disable, unlike a naive reading of the A/B convention"
pin "Scope C's cost disclosure names the existing prose-only figure" "$doc" '6.1M tokens' \
  "expected the cost section to point at the existing cost table's number, not invent a new one"
pin "Scope C defers real code-run numbers to the module's first run" "$doc" \
  'token** cost stays' \
  "expected the doc to say per-batch token cost is unmeasured rather than invent a number"
pin "Scope C states the real, live-measured batch count" "$doc" '14 directory-affinity batches' \
  "the claim marker's own correction: the spec's 'roughly 4-6' estimate was stale, 14 is the real measured count"
pin "Scope C's diversity leg cites delta-audit.md §5, not restated" "$doc" \
  'delta-audit.md`](delta-audit.md) §5' \
  "F6: the code module inherits delta-audit.md §5's rule as-is, cited not restated"
pin "GATE-2 requires the diversity leg's report for a scope-C run" "$doc" \
  "the diversity leg's own report present" \
  "F6: 'integration is explicit, not implied' — GATE-2 itself must gate on it, not just the Diversity paragraph mentioning it exists"
pin "Scope C's ratchet note reuses the existing noise guard" "$doc" \
  'a common, benign pattern' \
  "F7: the ratchet mechanism is unchanged; state the same noise guard prose demotions already need"
pin "Scope C's Model lines resolve inventory.sh's own forward reference" "$doc" \
  '**Model lines.**' \
  "tools/drydock/inventory.sh's own header already says 'see docs/drydock.md's Model lines' — that text must resolve to something"
pin "Scope C's Model lines name the invariant-batch escalation" "$doc" \
  'DRYDOCK_INVARIANT_PATHS`-marked file goes to top tier or xhigh' \
  "expected the doc to state the escalation the inventory's own INVARIANT marker exists to drive"

# --- phase 3 gains code claim classes, cross-file duplication deliberately excluded ------------------
pin "phase 3 points at the Scope C code claim classes" "$doc" \
  'Scope C adds three more, over its own extended' \
  "What ships item 5: phase 3 gains code claim classes"
pin "phase 3 states why duplication is NOT a claims-derived class" "$doc" \
  'deliberately NOT one of them' \
  "code bodies never enter the claims registry, so phase 3 structurally cannot see duplication"

# --- code-auditor.md: the fourth role template, dir #85's taxonomy, no invented classes --------------
pin "code-auditor.md carries dir #85's taxonomy" "$code_auditor" 'dead-code' \
  "F3: the taxonomy is reused from dir #85 module-1, not invented"
pin "code-auditor.md's claims contract carries defines:" "$code_auditor" 'defines: <name>' \
  "item 5: the claims contract must extend with defines: for phase 3 to derive the dead-helper class"
pin "code-auditor.md's claims contract carries calls:" "$code_auditor" 'calls: <name>' \
  "item 5: calls: must include internal calls, or a used local helper reads as dead"
pin "code-auditor.md's claims contract explains why internal calls count" "$code_auditor" \
  'omitting it would make phase 3 flag that helper as dead' \
  "expected the template to state the false-positive class the cross-vendor review round caught"
pin "code-auditor.md routes duplication to phase 1, not the claims registry" "$code_auditor" \
  'the frozen tree yourself for the suspicious shape' \
  "duplication is a phase-1 finding, never a phase-3 claims-derived class"

# --- verifier.md's F5 bullet: unconditional for code, points at phase 1 rail 5, does not restate
# dir #225 inline (F5's own resolved fork) -------------------------------------------------------------
pin "verifier.md's code bullet states the unconditional bar" "$verifier" \
  'the bar is unconditional, not comment-triggered' \
  "F5: a code finding's verdict rests on execution regardless of whether it turns on a comment"
pin "verifier.md's code bullet points at phase 1 rail 5" "$verifier" \
  'drydock.md`](../drydock.md)'"'"'s phase 1 rail 5' \
  "F5: point at the existing rail rather than re-citing dir #225 inline"
check_absent "verifier.md's new bullet does not re-cite dir #225 inline" \
  "$(cat "$verifier")" 'dir #225'

# --- the rails block in code-auditor.md: block-extract and diff against the canonical source, never a
# substring-presence check (dir #209's own finding against this file's earlier pins was exactly a
# substring check that a block-level drift survives) --------------------------------------------------
extract_rails() { awk '/^- You are read-only:/,/^- DELEGATION RUN:/' "$1"; }
canonical_rails="$(extract_rails "$delegation")"
code_auditor_rails="$(extract_rails "$code_auditor")"
check_block_equal "code-auditor.md's rails block is byte-identical to docs/delegation.md's canonical text" \
  "$code_auditor_rails" "$canonical_rails"

# --- dir #208: delegation.md:189 promises this block is reproduced verbatim "in every worker and
# verifier prompt this pattern generates" — auditor.md and verifier.md are exactly that (code-auditor.md
# above is the fourth worker template), so they get the same block-diff treatment, not a substring pin --
auditor_rails="$(extract_rails "$auditor")"
check_block_equal "auditor.md's rails block is byte-identical to docs/delegation.md's canonical text" \
  "$auditor_rails" "$canonical_rails"
verifier_rails="$(extract_rails "$verifier")"
check_block_equal "verifier.md's rails block is byte-identical to docs/delegation.md's canonical text" \
  "$verifier_rails" "$canonical_rails"

# --- fixer.md is a MUTATOR, not a worker/verifier (an operator-launched session that commits and opens
# a PR) — delegation.md's own Mutator template carries only the DELEGATION RUN line, never the full
# read-only rails block, so fixer.md's fix is scoped to that one line, pinned verbatim --------------------
marker='DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.'
pin "fixer.md carries the centralized-wrap marker verbatim" "$fixer" "$marker" \
  "expected fixer.md (the mutator instantiation) to carry the same marker the Mutator template requires"

# --- docs/delta-audit.md §1 and docs/reference.md's inventory row: both called drydock "prose only"
# and PR2's own Done criterion requires the claim corrected (the dir #256 class) --------------------
check_absent "delta-audit.md §1 no longer calls drydock prose-only" \
  "$(cat "$delta_audit")" 'the whole tree, prose only'
pin "delta-audit.md §1 now says prose and code" "$delta_audit" 'prose and code both, by default' \
  "expected §1's drydock comparison to reflect the shipped scope-C default"
check_absent "reference.md's inventory row no longer calls it a prose-audit run" \
  "$(cat "$reference")" 'prose-audit run'
pin "reference.md's inventory row now says prose and code surface" "$reference" \
  'tracked prose and code surface' \
  "expected the Tools table row to reflect scope C"

# --- /code-review medium findings: three more stale/missing surfaces the fourth template exposed ----
pin "the file contract section points at code-auditor.md's extension" "$doc" \
  'code-auditor.md`](drydock/code-auditor.md) extends this same shape for scope C' \
  "The file contract section names auditor.md verbatim but never mentioned code-auditor.md extends it"
check_absent "delegation.md's role-prompt enumeration no longer undercounts at three" \
  "$(cat "$delegation")" 'templates (auditor, verifier, fixer)'
pin "delegation.md's role-prompt enumeration now names all four" "$delegation" \
  'templates (auditor, code-auditor, verifier, fixer)' \
  "delegation.md's own See-also enumeration went stale the moment code-auditor.md shipped, same class doctor.sh's dir #256 check exists to catch on other surfaces"
pin "verifier.md's cross-file variant states the scope-C classes an agent actually running it needs" \
  "$verifier" 'three more classes apply' \
  "the executable phase-3 template, not just drydock.md's narrative doc, must name the code claim classes or an agent running it on a scope-C batch never looks for them"

# --- dir #270: phase 7 step 1's review-history entry uses the doctrine's run profile as its field
# list, and treats cost/induced-defect marks as during-the-run captures, not a verdict-time guess ---
pin "phase 7 step 1 links the doctrine's run profile" "$doc" \
  '](verification-economics.md)'"'"'s run profile as the field list' \
  "expected step 1's field list to be the doctrine's six-field profile, not an ad hoc list"
pin "phase 7 step 1 states cost/induced marks are during-the-run captures" "$doc" \
  'the entry reconstructs from memory' \
  "expected step 1 to say when fields 5/6 are captured, not just that they exist"

# --- dir #270 follow-up: an independent /simplify pass found phase 7's "capture during, don't
# reconstruct after" discipline lived only in the orchestrator-facing narrative at the bottom of the
# doc — a spawned auditor/verifier session, which reads only its own role-prompt template
# (docs/drydock/*.md), never sees phase 7's text. delta-audit.md's own equivalent fix put the
# induced/original mark directly in Protocol rule 6 (the report contract every spawned session binds
# to) rather than leaving it as narration; these pins require drydock's verifier.md to carry the same
# operative instruction, not just point at it -------------------------------------------------------
pin "verifier.md instructs marking accepted findings induced/original at triage time" "$verifier" \
  'For every `accepted` finding, also mark `induced` or `original`' \
  "expected the operative rule to live in verifier.md itself — the file a spawned verifier session actually reads — not only in phase 7's narrative"
pin "verifier.md's induced/original mark cites verification-economics.md's field 6" "$verifier" \
  "field 6: \`induced\` when it lands in" \
  "expected verifier.md to point at the doctrine's attribution rule rather than inventing its own"
pin "verifier.md tells the verifier how to record the mark on the verdict line" "$verifier" \
  '`accepted — induced` or `accepted — original`' \
  "expected a concrete instruction for where the mark goes, not just that one exists"
pin "drydock.md's roles section ties per-phase cost tallying to gate returns, not phase 7" "$doc" \
  'as each of GATE-1 through GATE-4 is reached' \
  "expected the roles section (part of the orchestrator's own procedure, read well before phase 7) to say cost is recorded as each phase finishes"
pin "phase 2's narrative points at verifier.md for the induced/original operative rule" "$doc" \
  'gets marked `induced` or `original` at this triage step' \
  "expected phase 2's own description of what verifiers do to name the mark, not just verifier.md and phase 7"

summary
