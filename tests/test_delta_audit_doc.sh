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
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/delta-audit.md"
delegation="$REPO_ROOT/docs/delegation.md"
release_audit="$REPO_ROOT/docs/release-audit.md"
drydock="$REPO_ROOT/docs/drydock.md"
reference="$REPO_ROOT/docs/reference.md"
readme="$REPO_ROOT/README.md"
derive="$REPO_ROOT/tools/delta-audit/derive.sh"

check_file "docs/delta-audit.md exists" "$doc"
check_file "docs/delegation.md exists" "$delegation"
check_file "tools/delta-audit/derive.sh exists" "$derive"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ---------------
pin "README Docs section links docs/delta-audit.md" \
  "$readme" '[`docs/delta-audit.md`](docs/delta-audit.md)' \
  "expected the Docs section to list delta-audit.md the way it lists drydock.md"

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
# substring-presence check. dir #209's own finding against test_drydock_doc.sh:70-75 is the class
# this guards against: a substring pin can survive a drift that deletes or reorders a contract line,
# because "the text is somewhere in the file" says nothing about whether it is INTACT. -------------
extract_rails() {   # $1 = file -> the rails block(s) it contains, back to back, one line each
  awk '/^- You are read-only:/,/^- DELEGATION RUN:/' "$1"
}
canonical_rails="$(extract_rails "$delegation")"
check_contains "docs/delegation.md's own rails block is non-empty (sanity check on the extractor)" \
  "$canonical_rails" "DELEGATION RUN"

doc_rails_all="$(extract_rails "$doc")"
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

summary
