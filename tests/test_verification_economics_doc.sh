#!/usr/bin/env bash
# test_verification_economics_doc.sh — dir #230: docs/verification-economics.md is the one referent
# for the stopping rule, the filing bar, the diversity doctrine and the run metric, which
# docs/delta-audit.md, docs/drydock.md, docs/release-audit.md and FRAMEWORK.md each state
# operatively and cite rather than restate.
#
# Same idiom as test_delta_audit_doc.sh / test_drydock_doc.sh: fixed-string pins on BOTH legs of a
# naming coupling. Two things are pinned here that a prose test usually is not, and both are
# load-bearing rather than stylistic:
#
#   1. The DOCTRINE INVARIANTS — the two-axis statement, the filing bar's three criteria, the three
#      diversity axes, the six metric fields. Each one is a claim another doc now depends on, and
#      each was contested during this ticket's design pass. A doc that quietly loses one collapses
#      back into a premise the ticket's own datasets falsified.
#   2. ONE LINK-PIN PER CITER, not just delta-audit.md's. dir #230's spec calls pinning one citer and
#      shipping three unpinned the partial guard test_doc_figures.sh's header warns about.
#
# ASSERT THE ACCEPT, NOT THE DENY (dir #257 dataset, item 6; memory rule). Every pin below asserts
# the presence of the form only a correct doc reaches. check_absent is used exactly twice, and in
# both cases the absent string is the RETIRED claim — a form that a correct doc cannot contain, not
# a fail-closed rejection that a broken doc would also satisfy.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/verification-economics.md"
delta="$REPO_ROOT/docs/delta-audit.md"
drydock="$REPO_ROOT/docs/drydock.md"
release_audit="$REPO_ROOT/docs/release-audit.md"
framework="$REPO_ROOT/FRAMEWORK.md"
readme="$REPO_ROOT/README.md"

check_file "docs/verification-economics.md exists" "$doc"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped --------------
pin "README Docs section links docs/verification-economics.md" \
  "$readme" '[`docs/verification-economics.md`](docs/verification-economics.md)' \
  "expected the Docs section to list verification-economics.md the way it lists delta-audit.md"

# --- D2: the two axes. The whole doc rests on this; without it every rule below inherits the ------
# --- falsified "review until clean" premise the ticket's datasets overturned. ---------------------
pin "the doc states the class-space axis of convergence" \
  "$doc" 'convergence exists in class space across runs' \
  "expected D2 to name the axis on which convergence IS visible"
pin "the doc states the finding-count axis where convergence does NOT exist" \
  "$doc" 'it does not exist in finding-count space within a run' \
  "expected D2 to state both halves of the reconciliation, not just the one that survived"
pin "the doc names find-rate as tracking reviewer novelty" \
  "$doc" 'reviewer novelty' \
  "expected D2 to name what find-rate actually tracks, the claim that replaces the falsified one"

# The retired scalar's ASSERTION must be absent. Note precisely what this does and does not check:
# the doc names the retired metric on purpose, in order to retire it ("Severity-weighted findings per
# token" is in §9), so the phrase itself is legitimate. What must never come back is the monotonic
# CLAIM about it. A check_absent whose target is a claim a correct doc cannot contain — not a
# fail-closed deny that both a correct and a broken doc would satisfy.
check_absent "the retired scalar's monotonic-fall claim is absent, not restated in weakened form" \
  "$(cat "$doc")" 'falling monotonically'

# --- D3: the stopping rule, both clauses, and the third trigger folded in from FRAMEWORK.md ------
pin "Clause A requires TWO independent diverse legs, not one clean round" \
  "$doc" 'two independent diverse legs' \
  "expected Clause A's two-leg condition; a single silent round is what D5 forbids reading into"
pin "Clause A scopes 'new class' to the registry as it stands at that moment" \
  "$doc" 'as it stands at that moment' \
  "without this scoping the rule is unsatisfiable on a project's first run (D7b)"
pin "Clause B redirects known-class-only runs at the demotion pipeline" \
  "$doc" 'indicts the demotion pipeline' \
  "expected Clause B to name the pipeline, not 'run more reviewers next time'"
# Both needles below are deliberately NOT the phrase the assertion is named after. "new surface
# touched" occurs three times in the doc (§2, §3's prior-art blockquote, and the trigger paragraph
# itself), and "corroborates" occurs wherever the character test is merely mentioned — so either
# generic needle stays green even if the paragraph it guards is deleted outright. Each pin instead
# takes a string unique to the paragraph carrying the rule.
pin "the new-surface-touched trigger is present as a peer of the two-leg condition" \
  "$doc" 'it is what repairs Clause A'"'"'s weak spot' \
  "expected FRAMEWORK.md's field-tested signal folded into Clause A, per the EXTEND decision"
pin "the character test is scoped as corroborating, not independently licensing" \
  "$doc" 'it does not independently license stopping' \
  "expected the character test scoped as corroboration; character alone must not license stopping"

# --- dir #327: Clause A's severity/reachability carve-out, parallel to the guard-gap one ---------
# Needle pins the AND connective on purpose: flipping "both" to "either" turns a narrow, judged
# exception into a loophole that reopens the hole the carve-out exists to keep shut.
pin "the carve-out requires BOTH reachability and severity, not either alone" \
  "$doc" 'does not reset the clock when **both** hold' \
  "expected the two-condition AND; either condition alone is the loophole this carve-out must avoid"
pin "the carve-out's severity call comes from the diverse leg, not the fix's own author" \
  "$doc" 'not the fix'"'"'s own author, and not the round' \
  "expected the non-self-grading condition; a self-graded severity call is not independent"
pin "the carve-out states why it must exist: literal zero makes Clause A unsatisfiable" \
  "$doc" 'makes Clause A unsatisfiable by construction' \
  "expected the motivating ground; without it the carve-out reads as arbitrary generosity"
# The carve-out anchors to delta-audit.md §8's own disposition set rather than inventing a fresh
# "non-blocking" vocabulary that duplicates it — an altitude finding from this ticket's own /simplify
# pass. Needle pins the real enum, not a paraphrase, so a regression back to invented wording is caught.
pin "the carve-out's condition (2) uses §8's real disposition set, not invented vocabulary" \
  "$doc" 'own `ticket-next`,' \
  "expected condition (2) anchored to §8's ticket-next/known-issue/no-action set, per the altitude fix"
pin "the carve-out weighs condition (2) by demonstrated discrimination, not bare independence" \
  "$doc" 'Independence alone is not calibration' \
  "expected the calibration weighting; a leg that never disposes fix-before-tag trivially satisfies (2)"
# A peer review found the founding case (keel-impact.sh's single-operator exclusion) would fail
# condition (1) literally, since that design is stated nowhere in the tree — the fix makes stating
# it part of invoking the carve-out, rather than weakening "stated" into an unfalsifiable appeal.
pin "invoking condition (1) obliges the verifier to name where the design is stated" \
  "$doc" 'obliges the verifier to point at where the excluding design is stated' \
  "expected the verifier obligation; without it condition (1) can be invoked with nothing to check"
pin "condition (1)'s obligation extends to writing the assumption down when it is missing" \
  "$doc" 'never been written anywhere — record it in the artifact' \
  "expected the shift-left remedy for an artifact whose design was never written down anywhere"

# --- dir #327: §8's coverage bar is named in Clause A's own 'does NOT license' list --------------
pin "the doc names §8's verdict contract as NOT licensing a stop on its own" \
  "$doc" "delta-audit.md\`](delta-audit.md) §8's verdict contract is satisfied" \
  "expected the coverage bar named alongside the clean-round/budget/repeat-reviewer non-licenses"
pin "the doc distinguishes the verdict contract's coverage question from Clause A's stopping one" \
  "$doc" 'different question from whether a diverse round has gone silent' \
  "expected coverage and stopping named as two different questions, not treated as one"

# --- D4: the filing bar's three criteria, all present --------------------------------------------
pin "filing bar criterion (a) — behavioural" "$doc" 'it is (a) behavioural' \
  "expected the bar's first criterion stated verbatim as a criterion"
# The trailing ", or" is part of the needle on purpose: the bar is a UNION, and flipping that one
# connective to "and" silently inverts it to an intersection. Three presence-only pins would all stay
# green through that flip — the substring-survives-a-contract-drift gap dir #209 found in an earlier
# doc test. Pinning the connective with the criterion is what makes the flip red.
pin "filing bar criterion (b) — a new class, and the bar is a UNION not an intersection" \
  "$doc" '(b) a **new class**, or' \
  "expected the bar's second criterion AND the disjunctive connective that makes the three a union"
pin "filing bar criterion (c) — a guard gap on an invariant-bearing surface" \
  "$doc" '(c) a guard gap on an invariant-bearing surface' \
  "expected the bar's third criterion"
pin "the sub-bar disposition names a standing list, not a ticket of its own" \
  "$doc" 'a named line in the project'"'"'s standing list' \
  "without this the bar dissolves: a sub-bar finding that may open its own ticket restricts nothing"

# --- D5: the diversity axis names all THREE axes. A doc that drops back to vendor-only has -------
# --- regressed to the superseded 'method > model' framing. ---------------------------------------
pin "diversity axis 1 — fresh context" "$doc" '**Fresh context**' \
  "expected the cheapest axis, which the 2026-08-26 dataset points at"
pin "diversity axis 2 — different method" "$doc" '**Different method**' \
  "expected blind-then-reconcile as its own axis"
pin "diversity axis 3 — different vendor" "$doc" '**Different vendor**' \
  "expected the vendor axis kept as one of the three, though no longer the headline claim"
pin "the fabrication hazard's remedy is stated as diffing the quoted target" \
  "$doc" 'quoted target against the live file' \
  "expected the diff-the-quote rail, the hazard's only detection"

# --- D6: fix rounds as a defect source, citing FRAMEWORK.md as prior art -------------------------
# Needle is §6-unique on purpose. '](../FRAMEWORK.md)' occurs six times in the doc, so it would stay
# green with §6's prior-art citation deleted outright — the same not-binding-what-it-names class the
# two pins above were rewritten to avoid.
pin "§6 cites FRAMEWORK.md as prior art rather than reading as fresh doctrine" \
  "$doc" '**This claim is not new here.**' \
  "expected §6's prior-art disclaimer; the tree already ships this claim, and §6 must say so"

# --- The metric: all six fields present ----------------------------------------------------------
pin "metric field 1 — behavioural defects in shipped code" \
  "$doc" 'behavioural defects in shipped code' "expected metric field 1"
pin "metric field 2 — new classes vs instances" \
  "$doc" 'new classes vs instances of known ones' "expected metric field 2"
pin "metric field 3 — which layer found what" \
  "$doc" 'which layer found what' "expected metric field 3"
pin "metric field 4 — whether an upstream gate should have caught it" \
  "$doc" 'whether an upstream gate should have caught it' "expected metric field 4"
pin "metric field 5 — cost, per leg" "$doc" 'cost, per leg' \
  "expected metric field 5, this ticket's assigned definition"
pin "metric field 6 — induced defects" "$doc" 'induced defects' \
  "expected metric field 6, D6's rate"
pin "field 5 permits an explicit unmeasured value rather than a fabricated zero" \
  "$doc" 'unmeasured' \
  "expected the honest-absence value; a fabricated zero is how the retired claim went wrong"
pin "field 5's permitted-ratio boundary is drawn at a single leg" \
  "$doc" 'never a run-level or cross-leg aggregate' \
  "expected the line between the permitted figure and the retired scalar, stated explicitly"

# --- D7b: the adopter with no history. Every new-vs-known rule presupposes a registry. -----------
pin "the doc says a first run's classes are all new, and that this is correct" \
  "$doc" 'first run'"'"'s classes are all new, and that is correct' \
  "expected the bootstrapping section; without it a new adopter is handed an infinite loop"

# --- D8: the honest limit ------------------------------------------------------------------------
pin "the residual is bounded by disclosure honesty, not by zero" \
  "$doc" 'disclosure honesty, not by zero' \
  "expected D8; it is what keeps the doc from reading as a completeness claim"

# --- Deliverable 4: ONE LINK-PIN PER CITER, both legs of every coupling ---------------------------
# Scope of these six, stated so a later maintainer does not over-trust them: each asserts that the
# named file carries AT LEAST ONE resolving link to its counterpart. Several citers link from more
# than one site, so no individual site is guarded here — losing one of drydock's four links leaves
# this green. Guarding a specific site needs a needle unique to that site's prose, the way the §6
# prior-art pin above does.
pin "delta-audit.md links the doctrine doc" \
  "$delta" '](verification-economics.md)' \
  "expected at least one resolving link; the diversity-leg rail is the load-bearing one"
pin "the doctrine doc names delta-audit.md back" \
  "$doc" '](delta-audit.md)' "expected D1's sibling boundary to name delta-audit.md"

pin "drydock.md links the doctrine doc" \
  "$drydock" '](verification-economics.md)' \
  "expected at least one resolving link; the ratchet and phase 6 are the load-bearing ones"
pin "the doctrine doc names drydock.md back" \
  "$doc" '](drydock.md)' "expected D1's sibling boundary to name drydock.md"

pin "release-audit.md links the doctrine doc" \
  "$release_audit" '](verification-economics.md)' \
  "expected at least one resolving link; phase 5 is the load-bearing one"
pin "the doctrine doc names release-audit.md back" \
  "$doc" '](release-audit.md)' "expected D1's sibling boundary to name release-audit.md"

pin "FRAMEWORK.md links the doctrine doc as the layer above its two signals" \
  "$framework" '](docs/verification-economics.md)' \
  "the EXTEND decision requires FRAMEWORK.md to point at the layer above, keeping its own text"
pin "the doctrine doc names FRAMEWORK.md back as the per-round layer" \
  "$doc" '](../FRAMEWORK.md)' \
  "expected the doc to link its prior art, per the EXTEND decision"

# --- Deliverable 4: BOTH of delta-audit.md's dir #230 section anchors are gone --------------------
# The retired form, absent. Same reasoning as the retired-scalar check above: a correct file cannot
# contain this string, so the assertion has a direction only a correct file reaches.
# Needle is the bare ticket number, NOT 'dir #230 §4'. The two removed references were written
# differently — "dir #230 §4 owns the doctrine..." and "dir #230's own §4 owns the reasoning..." —
# so the spaced form binds only the first, and restoring the See-also bullet verbatim would keep an
# assertion named "BOTH" green. The bare number binds both, and is now absent from the file entirely.
check_absent "delta-audit.md no longer cites the backlog ticket at all — BOTH anchors gone" \
  "$(cat "$delta")" 'dir #230'

# --- The EXTEND decision: FRAMEWORK.md KEEPS its two signals, they were not moved out ------------
pin "FRAMEWORK.md still owns the per-round question" \
  "$framework" 'is one more round worth it?' \
  "EXTEND, not supersede: FRAMEWORK.md's two signals stay home; only a pointer was added"

# --- Self-revision clause, the same one its three siblings each carry ----------------------------
pin "the doc carries the self-revision clause" \
  "$doc" 'not a fixed verdict, a checklist to' \
  "expected the closing section to match its siblings' own self-revision wording"

summary
