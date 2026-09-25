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

# --- (a) budget: GUIDE7 ≤ 1500 words -----------------------------------------------------------------
GUIDE_MD_WORD_BUDGET=1500
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
  "Recorded, not fixed:" "Marker:" "Operator next:"
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
)
i=0
while [ "$i" -lt "${#needle_rules[@]}" ]; do
  rule="${needle_rules[$i]}"
  needle="${needle_texts[$i]}"
  pin_exact "(f) needle [$rule]: '$needle' matches exactly one line" "$guide_md" "$needle" \
    "missing needle for $rule in $guide_md"
  i=$((i + 1))
done

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

summary
