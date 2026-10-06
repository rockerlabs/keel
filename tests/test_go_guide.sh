#!/usr/bin/env bash
# test_go_guide.sh — dir #642 (`/go` round 3): pins commands/go-guide.md, the hidden implementer guide
# `commands/go.md` step 7 loads. Same shape as tests/test_go_command.sh: reads
# ${KEEL_GO_GUIDE_MD:-$REPO_ROOT/commands/go-guide.md}, every case below is shown red first by
# re-invoking THIS file against a mutated SCRATCH copy via that override — no tracked file is ever
# edited to prove a case. T5 (spec §5.4): every needle in case (f) must match exactly one line of the
# guide, asserted with `grep -cF` rather than mere presence — the false-negative class a needle shared
# with an unrelated clause belongs to (test_go_command.sh's own comment above its needle_texts).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

guide_md="${KEEL_GO_GUIDE_MD:-$REPO_ROOT/commands/go-guide.md}"

# Config for tests/lib.sh's shared scratch_copy/assert_case_turns_red (promoted there once this file
# needed the exact same idiom tests/test_go_command.sh had already defined for itself).
SCRATCH_COPY_PREFIX="go-guide-copy"
MUTATION_SCRIPT="$REPO_ROOT/tests/test_go_guide.sh"
MUTATION_SKIP_VAR="KEEL_GO_GUIDE_TEST_SKIP_MUTATIONS"

check_file "go-guide.md target exists" "$guide_md"

# --- (a) budget: GUIDE7 ≤ 1650 words -----------------------------------------------------------------
# Raised 1500 -> 1650 (operator decision F4, 2026-10-05, dir #668 spec docs/specs/668-go-seam-step.md):
# the Seams step and dir #401's checkpoint-note hunk both land in this file (macOS `wc -w` binds), so
# the constant moves once for both. Raising it again is an operator decision — never bump it here just
# to make a clause fit.
GUIDE_MD_WORD_BUDGET=1650
word_count="$(wc -w < "$guide_md" | tr -d ' ')"
if [ "$word_count" -le "$GUIDE_MD_WORD_BUDGET" ]; then
  pass "(a) budget: go-guide.md is <= $GUIDE_MD_WORD_BUDGET words (got $word_count)"
else
  fail "(a) budget: go-guide.md is <= $GUIDE_MD_WORD_BUDGET words" "got $word_count words"
fi

# --- (b) frontmatter carries user-invocable: false ---------------------------------------------------
pin "(b) frontmatter: user-invocable: false present" "$guide_md" 'user-invocable: false' \
  "expected the user-invocable: false frontmatter key"

# --- (c) the eight action labels I1-I8, distinct -------------------------------------------------------
label_count="$(grep -oE '\*\*I[1-8] — ' "$guide_md" | sort -u | wc -l | tr -d ' ')"
if [ "$label_count" -eq 8 ]; then
  pass "(c) eight distinct **I1 — ** .. **I8 — ** action labels present"
else
  fail "(c) eight distinct **I1 — ** .. **I8 — ** action labels present" "found $label_count in $guide_md"
fi

# --- (d) every I8 form field label present, one needle each -------------------------------------------
field_labels=(
  "Ticket:" "Readiness:" "Guide:" "Tests:" "Conform:" "Escapes:" "Outcome test:"
  "Recorded, not fixed:" "Seams:" "Handoff:" "Marker:" "Operator next:"
)
for label in "${field_labels[@]}"; do
  pin "(d) I8 form field: '$label' present" "$guide_md" "$label" \
    "expected the I8 form field label '$label' in $guide_md"
done

# --- (e) adopter-generic: the shipped guide names neither the personal KB path nor its file -----------
if grep -qF -- '.keel/kb' "$guide_md" || grep -qF -- 'REVIEW_HISTORY' "$guide_md"; then
  fail "(e) adopter-generic: go-guide.md names neither '.keel/kb' nor 'REVIEW_HISTORY'" \
    "found a personal-KB reference in $guide_md"
else
  pass "(e) adopter-generic: go-guide.md names neither '.keel/kb' nor 'REVIEW_HISTORY'"
fi

# --- (f) one needle per rule clause (T5), each matching EXACTLY ONE line of the guide ------------------
# Two parallel arrays, not a delimited "rule|needle" string (a needle containing a literal "|" would
# silently truncate — the same reason test_go_command.sh's (g) needles use this shape).
needle_rules=(
  "GUIDE1 core wins on disagreement"
  "GUIDE2 checklist item per check"
  "GUIDE2 still tests: first"
  "GUIDE2 a passing-before-change test tests nothing"
  "GUIDE2 Impact map walk"
  "GUIDE3 missed dependency counts as an escape"
  "GUIDE4 one row per rule id"
  "GUIDE4 pending sign-off state"
  "GUIDE5 the no-git report"
  "GUIDE5 the no-git escapes line"
  "GUIDE6 no outcome test in spec"
  "SPEC2 the Status line's position"
  "SPEC3 never write the closing marker"
  "GUIDE8 seams heading"
  "GUIDE8 commit first"
  "GUIDE8 recount rule"
  "GUIDE8 consumer lists"
  "GUIDE8 cap"
  "GUIDE3 carve-out cite"
  "GUIDE8 pre-existing falsehood"
  "GUIDE8 report field"
  "GUIDE4 old item 3 kept"
  "GUIDE4 old item 4 kept"
)
needle_texts=(
  "\`go.md\` wins"
  "one checklist item per check"
  "still \`tests: first\`"
  "tests nothing"
  "Impact map"
  "count it as an escape"
  "One row per spec rule id"
  "pending — <who>"
  "Implementation report"
  "escapes line"
  "The spec names none"
  "sits under the file's first heading"
  "Never write"
  "Others' PRs merged while you built"
  "Commit your work,"
  "A different number is falsified"
  "is yours in it"
  "Read at most ten files"
  "in a managed release); do not fix it"
  "record it (I3) and count it on"
  "Seams: <none | skipped — why | fixed <n>, escape <n>, unchecked <n>>"
  "you wrote down in I1. Red"
  "Run the project's full test command"
)
i=0
while [ "$i" -lt "${#needle_rules[@]}" ]; do
  rule="${needle_rules[$i]}"
  needle="${needle_texts[$i]}"
  pin_exact "(f) needle [$rule]: '$needle' matches exactly one line" "$guide_md" "$needle" \
    "missing needle for $rule in $guide_md"
  i=$((i + 1))
done

# --- (g) I4's items are numbered 1-4 in order, Seams is item 2 (dir #668 B1) -------------------------
# A numbering slip (Seams as item 4, an old item lost, a duplicate number) passes every needle above.
i4_numbers="$(awk '/^\*\*I4 —/{f=1;next} /^\*\*I5 —/{f=0} f && /^[0-9]\. /{printf "%s", substr($0,1,1)}' "$guide_md")"
if [ "$i4_numbers" = "1234" ]; then
  pass "(g) I4 items are numbered 1-4 in order"
else
  fail "(g) I4 items are numbered 1-4 in order" "got '$i4_numbers' in $guide_md"
fi
pin_exact "(g) I4 item 2 is 'Seams.' (before the full test run)" "$guide_md" "2. Seams." \
  "expected item 2 of I4 to open with '2. Seams.'"

# --- (h) the handoff note's wiring (dir #401 A12): each action names its helper call ------------------
# Scoped to the action's own paragraph — "go-handoff.sh read" anywhere in the file would still pass
# after the call moved out of I1. The quote after the verb is part of each needle: an unquoted ticket
# reaches the tool as the bare word `dir` (`#401` is a shell comment), and the helper refuses it.
# action_text N — the text from the `**I<N> — ` label to the next label or `## ` heading.
action_text() {
  awk -v n="$1" '
    index($0, "**I" n " — ") == 1 { f = 1; print; next }
    f && (/^\*\*I[0-9]+ — / || /^## /) { f = 0 }
    f { print }
  ' "$guide_md"
}
handoff_needles=(
  '1|go-handoff.sh read "'
  '3|go-handoff.sh write "'
  '8|go-handoff.sh clear "'
  '8|Handoff:'
)
for spec in "${handoff_needles[@]}"; do
  n="${spec%%|*}"; needle="${spec#*|}"
  if action_text "$n" | grep -qF -- "$needle"; then
    pass "(h) I$n names '$needle'"
  else
    fail "(h) I$n names '$needle'" "no '$needle' inside I$n's own text in $guide_md"
  fi
done
# (c) counts distinct I1-I8 labels, so an I0 or I9 label would slip past it: count every label.
all_labels="$(grep -oE '\*\*I[0-9]+ — ' "$guide_md" | wc -l | tr -d ' ')"
if [ "$all_labels" -eq 8 ]; then
  pass "(h) exactly eight **I<n> — ** action labels (no I0, no I9)"
else
  fail "(h) exactly eight **I<n> — ** action labels (no I0, no I9)" "found $all_labels in $guide_md"
fi

# =======================================================================================================
# Mutation proof: each case above is shown red first — never on a tracked file (spec A1). scratch_copy,
# delete_line_containing, replace_in_line_containing, append_line and assert_case_turns_red are shared
# from tests/lib.sh (promoted there once this file needed the exact same idiom
# tests/test_go_command.sh had already defined for itself); the SCRATCH_COPY_PREFIX/MUTATION_SCRIPT/
# MUTATION_SKIP_VAR set above are this file's config for them. Every case re-invokes THIS file with
# KEEL_GO_GUIDE_MD pointed at a mutated scratch copy, so the positive checks above and their negative
# controls below share one definition of each case, never a second hard-coded copy.

# Indirect expansion (${!MUTATION_SKIP_VAR}) reads through the config var above rather than
# hardcoding its value a second time — a rename would otherwise silently desync this guard from what
# assert_case_turns_red actually sets (code-review high finding on this ticket's own diff).
if [ -n "${!MUTATION_SKIP_VAR:-}" ]; then
  summary
  exit $?
fi

# (a) budget — the mutation pad is computed from the live word count (leg 2 F5: a fixed 80-word pad
# never crosses the ceiling from ~1234 words; a pad derived from the live gap always does).
a_pad=$((GUIDE_MD_WORD_BUDGET - word_count + 80))
a_copy="$(scratch_copy "$guide_md" go-guide.md)"
append_line "$a_copy" "$(printf 'filler %.0s' $(seq 1 "$a_pad"))"
assert_case_turns_red "(a) budget mutation" \
  "(a) budget: go-guide.md is <= $GUIDE_MD_WORD_BUDGET words" "KEEL_GO_GUIDE_MD=$a_copy"

# (b) frontmatter — flip user-invocable's value.
b_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$b_copy" "user-invocable:" "false" "true"
assert_case_turns_red "(b) frontmatter mutation" \
  "(b) frontmatter: user-invocable: false present" "KEEL_GO_GUIDE_MD=$b_copy"

# (c) labels — drop the em-dash from one label, scoped to its own line.
c_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$c_copy" "**I4 — self-check.**" "I4 — self-check" "I4 self-check"
assert_case_turns_red "(c) labels mutation" \
  "(c) eight distinct **I1 — ** .. **I8 — ** action labels present" "KEEL_GO_GUIDE_MD=$c_copy"

# (d) I8 form field — drop every line naming Operator next: (the I8 field line, I6's cross-reference to
# it, and SPEC3's mention of the report's line — all three name the phrase, so all three must go for it
# to actually disappear from the file).
d_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$d_copy" "Operator next: <merge PR"
delete_line_containing "$d_copy" "which \`Operator next:\` then asks for"
delete_line_containing "$d_copy" "the report's \`Operator next:\` line"
assert_case_turns_red "(d) I8 form field mutation" \
  "(d) I8 form field: 'Operator next:' present" "KEEL_GO_GUIDE_MD=$d_copy"

# (e) adopter-generic — add a personal-KB path.
e_copy="$(scratch_copy "$guide_md" go-guide.md)"
append_line "$e_copy" "See also ~/.keel/kb for personal notes."
assert_case_turns_red "(e) adopter-generic mutation" \
  "(e) adopter-generic: go-guide.md names neither '.keel/kb' nor 'REVIEW_HISTORY'" "KEEL_GO_GUIDE_MD=$e_copy"

# (f) needle mutations — one per clause, each scoped to its own anchor so no other case collapses.

# GUIDE1 — the file wins, not go.md.
f1_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f1_copy" "disagree," "\`go.md\` wins" "this file wins"
assert_case_turns_red "(f) needle mutation: GUIDE1 core-wins clause removed" \
  "(f) needle [GUIDE1 core wins on disagreement]: '\`go.md\` wins' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f1_copy"

# GUIDE2 — "per check" dropped from the checklist-item clause.
f2_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f2_copy" "No runnable surface" "one checklist item per check" "one checklist item"
assert_case_turns_red "(f) needle mutation: GUIDE2 checklist-item-per-check clause removed" \
  "(f) needle [GUIDE2 checklist item per check]: 'one checklist item per check' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f2_copy"

# GUIDE2 — "still" dropped from the tests:-first clause.
f3_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f3_copy" "infeasible\` is only for a check" "still \`tests: first\`" "\`tests: first\`"
assert_case_turns_red "(f) needle mutation: GUIDE2 still-tests-first clause removed" \
  "(f) needle [GUIDE2 still tests: first]: 'still \`tests: first\`' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f3_copy"

# GUIDE2 — "tests nothing" reworded.
f4_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f4_copy" "rewrite it." "tests nothing" "tests ok"
assert_case_turns_red "(f) needle mutation: GUIDE2 tests-nothing clause removed" \
  "(f) needle [GUIDE2 a passing-before-change test tests nothing]: 'tests nothing' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f4_copy"

# GUIDE2 — the Impact-map walk line dropped entirely (both occurrences on that one line go with it).
f5_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$f5_copy" "Walk the spec's Impact map"
assert_case_turns_red "(f) needle mutation: GUIDE2 Impact-map-walk clause removed" \
  "(f) needle [GUIDE2 Impact map walk]: 'Impact map' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f5_copy"

# GUIDE3 — the missed-dependency escape clause dropped.
f6_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$f6_copy" "count it as an escape"
assert_case_turns_red "(f) needle mutation: GUIDE3 missed-dependency-escape clause removed" \
  "(f) needle [GUIDE3 missed dependency counts as an escape]: 'count it as an escape' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f6_copy"

# GUIDE4 — the one-row-per-rule-id clause reworded.
f7_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f7_copy" "conform table.**" "One row per spec rule id" "A row per rule"
assert_case_turns_red "(f) needle mutation: GUIDE4 one-row-per-rule-id clause removed" \
  "(f) needle [GUIDE4 one row per rule id]: 'One row per spec rule id' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f7_copy"

# GUIDE4 — the pending sign-off state dropped from its own line.
f8_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f8_copy" "person must pass" "pending — <who>" "pending"
assert_case_turns_red "(f) needle mutation: GUIDE4 pending-sign-off-state clause removed" \
  "(f) needle [GUIDE4 pending sign-off state]: 'pending — <who>' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f8_copy"

# GUIDE5 — the no-git report row dropped from the map.
f9_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$f9_copy" "Implementation report"
assert_case_turns_red "(f) needle mutation: GUIDE5 no-git-report clause removed" \
  "(f) needle [GUIDE5 the no-git report]: 'Implementation report' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f9_copy"

# GUIDE5 — the no-git escapes-line mapping row dropped.
f10_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$f10_copy" "escapes line"
assert_case_turns_red "(f) needle mutation: GUIDE5 no-git-escapes-line clause removed" \
  "(f) needle [GUIDE5 the no-git escapes line]: 'escapes line' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f10_copy"

# GUIDE6 — the "no outcome test in spec" clause reworded.
f11_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f11_copy" "outcome test: none in spec" "The spec names none" "No outcome test is named"
assert_case_turns_red "(f) needle mutation: GUIDE6 no-outcome-test-in-spec clause removed" \
  "(f) needle [GUIDE6 no outcome test in spec]: 'The spec names none' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f11_copy"

# SPEC2 — the Status line's position clause reworded.
f12_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f12_copy" "It carries the same legend tokens" \
  "sits under the file's first heading" "sits near the top of the file"
assert_case_turns_red "(f) needle mutation: SPEC2 Status-line-position clause removed" \
  "(f) needle [SPEC2 the Status line's position]: 'sits under the file's first heading' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f12_copy"

# SPEC3 — the never-write-the-marker rule dropped.
f13_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$f13_copy" "Never write"
assert_case_turns_red "(f) needle mutation: SPEC3 never-write-closing-marker clause removed" \
  "(f) needle [SPEC3 never write the closing marker]: 'Never write' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f13_copy"

# dir #668 — the Seams step's clauses, one mutation each (Appendix B of the spec). Each is scoped to its
# own clause on its own line so no other case collapses with it.

# GUIDE8 — the Seams item's opening sentence.
f14_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f14_copy" "Others' PRs merged while you built" "Others' PRs merged while you built" "Other work"
assert_case_turns_red "(f) needle mutation: GUIDE8 seams-heading clause removed" \
  "(f) needle [GUIDE8 seams heading]: 'Others' PRs merged while you built' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f14_copy"

# GUIDE8 — commit before the rebase.
f15_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f15_copy" "Commit your work," "Commit your work," "Save your work,"
assert_case_turns_red "(f) needle mutation: GUIDE8 commit-first clause removed" \
  "(f) needle [GUIDE8 commit first]: 'Commit your work,' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f15_copy"

# GUIDE8 — the recount rule.
f16_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f16_copy" "A different number is falsified" "A different number is falsified" "A different number is noted"
assert_case_turns_red "(f) needle mutation: GUIDE8 recount-rule clause removed" \
  "(f) needle [GUIDE8 recount rule]: 'A different number is falsified' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f16_copy"

# GUIDE8 — the consumer-list question.
f17_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f17_copy" "is yours in it" "is yours in it" "is a list kept"
assert_case_turns_red "(f) needle mutation: GUIDE8 consumer-lists clause removed" \
  "(f) needle [GUIDE8 consumer lists]: 'is yours in it' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f17_copy"

# GUIDE8 — the ten-file cap.
f18_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f18_copy" "Read at most ten files" "Read at most ten files" "Read the files"
assert_case_turns_red "(f) needle mutation: GUIDE8 ten-file-cap clause removed" \
  "(f) needle [GUIDE8 cap]: 'Read at most ten files' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f18_copy"

# GUIDE3 — the cite of go.md step 6's override at the out-of-ticket-defect clause.
f19_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f19_copy" "in a managed release); do not fix it" "in a managed release); do not fix it" "); do not fix it"
assert_case_turns_red "(f) needle mutation: GUIDE3 managed-release cite removed" \
  "(f) needle [GUIDE3 carve-out cite]: 'in a managed release); do not fix it' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f19_copy"

# GUIDE8 — a claim already false before the diff is recorded, not fixed.
f20_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f20_copy" "record it (I3) and count it on" "record it (I3) and count it on" "note it on"
assert_case_turns_red "(f) needle mutation: GUIDE8 pre-existing-falsehood clause removed" \
  "(f) needle [GUIDE8 pre-existing falsehood]: 'record it (I3) and count it on' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f20_copy"

# GUIDE8 — the report form's Seams line dropped (the whole line is the needle).
f21_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$f21_copy" "Seams: <none"
assert_case_turns_red "(f) needle mutation: GUIDE8 report-field line removed" \
  "(f) needle [GUIDE8 report field]: 'Seams: <none | skipped — why | fixed <n>, escape <n>, unchecked <n>>' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f21_copy"

# GUIDE4 — the renumbered old item 3 (I1's "unaffected" re-run) must keep its text.
f22_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f22_copy" "you wrote down in I1. Red" "you wrote down in I1. Red" "you listed. Red"
assert_case_turns_red "(f) needle mutation: GUIDE4 old item 3 text lost" \
  "(f) needle [GUIDE4 old item 3 kept]: 'you wrote down in I1. Red' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f22_copy"

# GUIDE4 — the renumbered old item 4 (the full test run) must keep its text.
f23_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$f23_copy" "Run the project's full test command" "Run the project's full test command" "Run the tests"
assert_case_turns_red "(f) needle mutation: GUIDE4 old item 4 text lost" \
  "(f) needle [GUIDE4 old item 4 kept]: 'Run the project's full test command' matches exactly one line" \
  "KEEL_GO_GUIDE_MD=$f23_copy"

# (g) numbering — Seams renumbered 2 -> 5: the 1-4 order check and the item-2 pin both go red.
g11_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$g11_copy" "2. Seams." "2. Seams." "5. Seams."
assert_case_turns_red "(g) numbering mutation: Seams not item 2" \
  "(g) I4 items are numbered 1-4 in order" "KEEL_GO_GUIDE_MD=$g11_copy"
assert_case_turns_red "(g) numbering mutation: Seams not item 2 (pin)" \
  "(g) I4 item 2 is 'Seams.' (before the full test run)" "KEEL_GO_GUIDE_MD=$g11_copy"

# (d) the new I8 field — drop its line.
d2_copy="$(scratch_copy "$guide_md" go-guide.md)"
delete_line_containing "$d2_copy" "Handoff: <none (reason)"
assert_case_turns_red "(d) I8 form field mutation: Handoff: removed" \
  "(d) I8 form field: 'Handoff:' present" "KEEL_GO_GUIDE_MD=$d2_copy"

# (h) wiring — each call loses its helper name, scoped to its own line.
h1_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$h1_copy" "go-handoff.sh read" "go-handoff.sh read" "go-handoff.sh peek"
assert_case_turns_red "(h) wiring mutation: I1 read call lost" \
  "(h) I1 names 'go-handoff.sh read \"'" "KEEL_GO_GUIDE_MD=$h1_copy"
h3_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$h3_copy" "go-handoff.sh write" "go-handoff.sh write" "go-handoff.sh put"
assert_case_turns_red "(h) wiring mutation: I3 write call lost" \
  "(h) I3 names 'go-handoff.sh write \"'" "KEEL_GO_GUIDE_MD=$h3_copy"
h8_copy="$(scratch_copy "$guide_md" go-guide.md)"
replace_in_line_containing "$h8_copy" "go-handoff.sh clear" "go-handoff.sh clear" "go-handoff.sh drop"
assert_case_turns_red "(h) wiring mutation: I8 clear call lost" \
  "(h) I8 names 'go-handoff.sh clear \"'" "KEEL_GO_GUIDE_MD=$h8_copy"
h9_copy="$(scratch_copy "$guide_md" go-guide.md)"
append_line "$h9_copy" "**I9 — extra.** A ninth action."
assert_case_turns_red "(h) wiring mutation: a ninth label" \
  "(h) exactly eight **I<n> — ** action labels (no I0, no I9)" "KEEL_GO_GUIDE_MD=$h9_copy"

summary
