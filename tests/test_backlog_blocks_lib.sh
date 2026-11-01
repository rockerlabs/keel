#!/usr/bin/env bash
# test_backlog_blocks_lib.sh — dir #359/#360: tools/lib/backlog-blocks.sh is the one shared
# BACKLOG.md ticket-block scanner both tools/self/archive-sweep-check.sh and
# tools/self/pool-report.sh source (dir #142's coverage ratchet requires a NEW shipped script
# to be tested directly, not only exercised indirectly through its consumers). Pins both
# functions the lib exports: backlog_ticket_blocks() and backlog_root_for().
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/backlog-blocks.sh"
check_file "tools/lib/backlog-blocks.sh exists" "$lib"

# --- both known consumers source the shared lib, not a private copy -----------------------------
check_contains "archive-sweep-check.sh sources tools/lib/backlog-blocks.sh" \
  "$(cat "$REPO_ROOT/tools/self/archive-sweep-check.sh")" 'lib/backlog-blocks.sh'
check_contains "pool-report.sh sources tools/lib/backlog-blocks.sh" \
  "$(cat "$REPO_ROOT/tools/self/pool-report.sh")" 'lib/backlog-blocks.sh'

# shellcheck source=tools/lib/fence-blank.sh
. "$REPO_ROOT/tools/lib/fence-blank.sh"
# shellcheck source=/dev/null
. "$lib"

# --- backlog_ticket_blocks(): heading/body-span detection, closed-tag detection -----------------
d="$(new_repo)"
f="$d/BACKLOG.md"
printf '### dir #1 — an open ticket — R2 — → 0.9.0

body line
body line 2

### dir #2 — a closed ticket — R2 — ✅ DONE (2026-08-01, done)

closed body
' > "$f"

out="$(backlog_ticket_blocks "$f")"
row_count="$(printf '%s\n' "$out" | grep -c .)"
if [ "$row_count" = 2 ]; then
  pass "backlog_ticket_blocks emits one row per heading (2)"
else
  fail "backlog_ticket_blocks emits one row per heading (2)" "got $row_count"
fi
check_contains "open ticket's closed field is 0" "$out" "$(printf '\t0\t')"
check_contains "closed ticket's closed field is 1" "$out" "$(printf '\t1\t')"

# --- wrapped heading: the closure tag on a continuation line still counts as closed (dir #255) --
d2="$(new_repo)"
f2="$d2/BACKLOG.md"
printf '### dir #9 — a heading whose title wraps across more than one physical
source line before its own closure tag — R2 — ✅ DONE (2026-08-01, done)

body
' > "$f2"
out2="$(backlog_ticket_blocks "$f2")"
check_contains "MUTATION-PROOF: wrapped heading tag on a continuation line still counts closed" \
  "$out2" "$(printf '\t1\t')"

# --- F-04 (dir #267 fixer brief): the `closed` field must not absorb a DIFFERENT ticket's own
# closure tag, whether it arrives via a wrapped heading or via body text with no blank line before
# it — both shapes read the current block-extension rule as "just another non-blank continuation
# line". Four cases, matching the brief's own wrapped-heading and no-blank-line-body pairs. --------
d4="$(new_repo)"
f4="$d4/BACKLOG.md"
printf '### dir #900 An open ticket whose heading wraps onto a second
  line that happens to cite a sibling, superseding dir #901 — ✅ CLOSED as a duplicate

### dir #910 Open ticket, single-line heading, body starts immediately
Supersedes dir #911 — ✅ CLOSED, so this work is now unblocked.

### dir #920 Open ticket, single-line heading, blank line before body

Supersedes dir #921 — ✅ CLOSED, so this work is now unblocked.

### dir #930 — a genuinely closed control — R2 — ✅ CLOSED (2026-08-01, done)

closed body
' > "$f4"
out4b="$(backlog_ticket_blocks "$f4")"
# Each row is `start<TAB>end<TAB>closed<TAB>heading_block` — select by the ticket number inside
# heading_block (field 4), not by line position, then read that row's own `closed` field (3).
row_closed() { printf '%s\n' "$out4b" | awk -F'\t' -v n="dir #$1" '$4 ~ n {print $3; exit}'; }
check_status "MUTATION-PROOF: dir #900 (wrapped heading citing a sibling's closure) stays open" \
  0 "$(row_closed 900)"
check_status "MUTATION-PROOF: dir #910 (no-blank-line body citing a sibling's closure) stays open" \
  0 "$(row_closed 910)"
check_status "dir #920 (blank line before the sibling citation) already stayed open, still does" \
  0 "$(row_closed 920)"
check_status "control: a genuinely closed ticket with its OWN tag still reads closed" \
  1 "$(row_closed 930)"

# --- the wrapped-heading case F-04's own fix must not regress (dir #255, re-asserted here so a
# future edit to the F-04 guard cannot silently reintroduce the false negative it replaces) --------
d4b="$(new_repo)"
f4b="$d4b/BACKLOG.md"
printf '### dir #9 — a heading whose title wraps across more than one physical
source line before its own closure tag — R2 — ✅ DONE (2026-08-01, done)

body
' > "$f4b"
out4c="$(backlog_ticket_blocks "$f4b")"
check_contains "MUTATION-PROOF: a genuine wrapped heading (no sibling citation) still reads closed" \
  "$out4c" "$(printf '\t1\t')"

# --- MUTATION-PROOF: a wrapped heading whose OWN continuation line mentions a different ticket
# BEFORE reaching its own closure tag must still read closed — an earlier version of the F-04 fix
# stopped block extension at the first foreign `dir #<N>` reference and cut this case off too,
# trading one false-negative direction for another (found by a fresh-context altitude review of
# the fix itself). The genuine tag sits behind a SECOND em-dash after the foreign citation, unlike
# the "<citation> — ✅ <tag>" shape the other four cases above share. ------------------------------
d4d="$(new_repo)"
f4d="$d4d/BACKLOG.md"
printf '### dir #950 A followup fix that wraps onto a second
  line mentioning dir #267 fixer brief before its own closure tag — R2 — ✅ CLOSED (2026-09-01, done)

body
' > "$f4d"
out4d="$(backlog_ticket_blocks "$f4d")"
check_contains "MUTATION-PROOF: a wrapped title citing another ticket before its OWN tag still reads closed" \
  "$out4d" "$(printf '\t1\t')"

# --- MUTATION-PROOF: a legacy `### <n>.` heading's OWN closure tag must not be discarded just
# because `own_num` is empty for that heading shape. A fresh-context review found this live: the
# F-04 skip condition treated an empty `own_num` as "always foreign" rather than "no identity to
# compare against", so ANY `dir #N` mention adjacent to a legacy ticket's own tag (a real, common
# shape — attribution like "extracted from dir #4") discarded that ticket's own closure. Reproduced
# against this project's own real BACKLOG.md before fixing (dir #37: "### 37. SEC4 ... (extracted
# from dir #4; ...) — ✅ DONE" misread as open). -----------------------------------------------------
d4e="$(new_repo)"
f4e="$d4e/BACKLOG.md"
printf '### 37. Legacy ticket — extracted from dir #4 — ✅ DONE, PR #92 merged\n' > "$f4e"
out4e="$(backlog_ticket_blocks "$f4e")"
check_contains "MUTATION-PROOF: a legacy heading citing a dir #N for attribution still reads closed" \
  "$out4e" "$(printf '\t1\t')"

# --- MUTATION-PROOF: a citation elsewhere on the line, with NO tag adjacent to it, must not
# discard this ticket's OWN tag that appears earlier on the same line. Found live against this
# project's own real BACKLOG.md (dir #299: "### dir #299 — ✅ CLOSED ... — supersedes dir #297
# parts (b) and (c)" — the citation "supersedes dir #297" has no tag anywhere near it; it is just
# describing what #299 supersedes as part of its own history, not ceding its own tag to #297). ------
d4f="$(new_repo)"
f4f="$d4f/BACKLOG.md"
printf '### dir #299 — ✅ CLOSED (2026-08-30) — a ticket whose own description later mentions what it supersedes dir #297 parts (b) and (c)\n' > "$f4f"
out4f="$(backlog_ticket_blocks "$f4f")"
check_contains "MUTATION-PROOF: an own-tag ticket citing a sibling with no adjacent tag stays closed" \
  "$out4f" "$(printf '\t1\t')"

# --- MUTATION-PROOF: the citation-verb list must recognise "Superseded by" (past tense) and be
# case-insensitive on "Duplicate of" — a delta review round found this project's own real
# BACKLOG.md uses "superseded" far more than "supersedes" (29 vs. 8 occurrences), and that the
# original fix's "duplicate of" branch, unlike its "Supersedes" branch, had no case alternation. ---
d4g="$(new_repo)"
f4g="$d4g/BACKLOG.md"
printf '### dir #500 A ticket still open
Superseded by dir #900 — ✅ CLOSED as a duplicate.

### dir #501 A ticket still open
Duplicate of dir #901 — ✅ CLOSED as noted elsewhere.
' > "$f4g"
out4g="$(backlog_ticket_blocks "$f4g")"
check_status "MUTATION-PROOF: 'Superseded by dir #N' (past tense) is recognised as foreign" \
  0 "$(printf '%s\n' "$out4g" | awk -F'\t' '$4 ~ /dir #500/ {print $3; exit}')"
check_status "MUTATION-PROOF: capitalized 'Duplicate of' is recognised as foreign, not just lowercase" \
  0 "$(printf '%s\n' "$out4g" | awk -F'\t' '$4 ~ /dir #501/ {print $3; exit}')"

# --- dir #420: a genuinely closed ticket whose OWN tag sits EARLIER on the same line than a
# citation to a different ticket's closure must not be over-discarded. The old shape tested one
# line at a time and `continue`d past the WHOLE line the instant the foreign citation matched,
# so the own tag that already matched earlier on that line was never reached. MUTATION-PROOF pair:
# dir #960 (own tag first, then a foreign citation on the SAME line) must read closed; dir #961
# (foreign citation only, no own tag anywhere) must stay open, the original F-04 case unchanged. --
d420="$(new_repo)"
f420="$d420/BACKLOG.md"
printf '### dir #960 — ✅ CLOSED — superseded by dir #965 — ✅ CLOSED\n\n### dir #970 An open ticket, single-line heading, body starts immediately\nSupersedes dir #975 — ✅ CLOSED, so this work is now unblocked.\n' > "$f420"
out420="$(backlog_ticket_blocks "$f420")"
row_closed420() { printf '%s\n' "$out420" | awk -F'\t' -v n="### dir #$1 " '$4 ~ n {print $3; exit}'; }
check_status "MUTATION-PROOF (dir #420): own tag before a same-line foreign citation still reads closed" \
  1 "$(row_closed420 960)"
check_status "control: the foreign-citation-only ticket (no own tag) stays open" \
  0 "$(row_closed420 970)"

# --- dir #432: the closure vocabulary widened beyond DONE/CLOSED to the other real shapes found
# live (ABSORBED, EXECUTED, SUPERSEDED, DUPLICATE, BUILT), and the `— ` separator made optional
# for the legacy headings that predate it — each verified against a real shape this project's own
# BACKLOG.md carries today, not invented. -------------------------------------------------------
d432="$(new_repo)"
f432="$d432/BACKLOG.md"
printf '### dir #1001 — a ticket closed via ABSORBED — R2 — ✅ ABSORBED (2026-08-01)\n\n### dir #1002 — a ticket closed via EXECUTED — R4 — ✅ EXECUTED (2026-08-01)\n\n### dir #1003 — a ticket closed via SUPERSEDED — R1 — ❌ SUPERSEDED (2026-08-01) by dir #1 re-scope\n\n### dir #1004 — a ticket closed via DUPLICATE — R1 — ❌ DUPLICATE of dir #2\n\n### 30. A legacy numbered ticket closed via BUILT (captured 2026-07-01) ✅ BUILT (2026-07-11)\n\n### 31. A legacy numbered ticket, DONE with no em-dash separator at all ✅ DONE, PR #1 merged\n' > "$f432"
out432="$(backlog_ticket_blocks "$f432")"
row_closed432() { printf '%s\n' "$out432" | awk -F'\t' -v n="$1" '$4 ~ n {print $3; exit}'; }
check_status "MUTATION-PROOF (dir #432): '✅ ABSORBED' reads closed" 1 "$(row_closed432 "dir #1001")"
check_status "MUTATION-PROOF (dir #432): '✅ EXECUTED' reads closed" 1 "$(row_closed432 "dir #1002")"
check_status "MUTATION-PROOF (dir #432): '❌ SUPERSEDED' reads closed" 1 "$(row_closed432 "dir #1003")"
check_status "MUTATION-PROOF (dir #432): '❌ DUPLICATE' reads closed" 1 "$(row_closed432 "dir #1004")"
check_status "MUTATION-PROOF (dir #432): legacy '✅ BUILT' with no em-dash reads closed" \
  1 "$(row_closed432 "30\\. A legacy")"
check_status "MUTATION-PROOF (dir #432): legacy '✅ DONE' with no em-dash reads closed" \
  1 "$(row_closed432 "31\\. A legacy")"

# --- dir #432: deliberately-excluded shapes stay open, checked live and found to be sub-status
# markers rather than whole-ticket closures — a real ticket's "PHASE 1 DONE" or "RUN 1 EXECUTED"
# must not be misread as the whole ticket closing. MUTATION-PROOF against future over-widening. --
d432b="$(new_repo)"
f432b="$d432b/BACKLOG.md"
printf '### dir #1010 — phase 1 of a multi-phase ticket — R2 — ✅ PHASE 1 DONE (PR #1)\n\n### dir #1011 — one run of a still-open ticket — R2 — ✅ RUN 1 EXECUTED (2026-08-01)\n\n### dir #1012 — a decision recorded, not necessarily executed — R2 — ✅ DECIDED (2026-08-01)\n\n### dir #1013 — in-progress marker, the opposite of closed — R3 — ⏳ IN FLIGHT\n' > "$f432b"
out432b="$(backlog_ticket_blocks "$f432b")"
row_closed432b() { printf '%s\n' "$out432b" | awk -F'\t' -v n="$1" '$4 ~ n {print $3; exit}'; }
check_status "control (dir #432): 'PHASE 1 DONE' is a sub-status, ticket stays open" \
  0 "$(row_closed432b "dir #1010")"
check_status "control (dir #432): 'RUN 1 EXECUTED' is a sub-status, ticket stays open" \
  0 "$(row_closed432b "dir #1011")"
check_status "control (dir #432): 'DECIDED' is not a closure verb, ticket stays open" \
  0 "$(row_closed432b "dir #1012")"
check_status "control (dir #432): '⏳ IN FLIGHT' is in-progress, not closed" \
  0 "$(row_closed432b "dir #1013")"

# --- dir #581: the 0.10.2 release manager's closing word, minted at a scale (17 headings) no
# earlier vocabulary widening had to absorb — MUTATION-PROOF against the same class recurring. ---
d581="$(new_repo)"
f581="$d581/BACKLOG.md"
printf '### dir #1020 — a ticket closed via FIXED — R2 — ✅ FIXED (2026-09-19, verified)\n\n### dir #1021 — a release candidate cut, sub-status not closure — R2 — ✅ RC 1 (2026-09-19)\n' > "$f581"
out581="$(backlog_ticket_blocks "$f581")"
row_closed581() { printf '%s\n' "$out581" | awk -F'\t' -v n="$1" '$4 ~ n {print $3; exit}'; }
check_status "MUTATION-PROOF (dir #581): '✅ FIXED' reads closed" 1 "$(row_closed581 "dir #1020")"
check_status "control (dir #581): '✅ RC 1' is a sub-status, ticket stays open" \
  0 "$(row_closed581 "dir #1021")"

# --- bb_closure_word_ok(): dir #581 (c)'s write-time check — the manager runs this on the exact
# marker text before writing it, so an unlisted word is refused when it would be minted, not
# found by the next census. ------------------------------------------------------------------
bb_closure_word_ok '✅ FIXED (2026-09-19, verified)' >/dev/null 2>&1
check_status "bb_closure_word_ok: a recognised word ('✅ FIXED') exits 0" 0 "$?"
bb_closure_word_ok '✅ SHIPPED (2026-09-19)' >/dev/null 2>&1
check_status "bb_closure_word_ok: an unlisted word ('✅ SHIPPED') exits 1" 1 "$?"
err="$(bb_closure_word_ok '✅ SHIPPED' 2>&1 >/dev/null)"
check_contains "bb_closure_word_ok: the refusal names the rejected candidate" "$err" 'SHIPPED'

# --- dir #609: the word is case-folded and markdown emphasis may sit between the glyph and the word
# (a peer project's uniform closure form is `✅ **Done 2026-09-20**`), and the word ends at a
# boundary — `✅ FIXEDX` is not `✅ FIXED`. The writer-side check and the scanner share the one
# constant, so each case is asserted on both. -------------------------------------------------
for cand in '✅ **Done 2026-09-20**' '✅ Closed (2026-09-20)' '✅ __Fixed__' '❌ *Duplicate*' '✅ ** Done'; do
  bb_closure_word_ok "$cand" >/dev/null 2>&1
  check_status "MUTATION-PROOF: bb_closure_word_ok accepts '$cand'" 0 "$?"
done
for cand in '✅ FIXEDX (x)' '✅ done' '❌ duplicate detection fails' '✅ **Donezo**' '✅ **SHIPPED**' '✅ Doing'; do
  bb_closure_word_ok "$cand" >/dev/null 2>&1
  check_status "MUTATION-PROOF: bb_closure_word_ok refuses '$cand'" 1 "$?"
done
# The spelling is hand-written: every plain word must match UPPER and Title case, and not lower case.
for w in DONE CLOSED ABSORBED EXECUTED SUPERSEDED DUPLICATE BUILT FIXED; do
  lower="$(printf '%s' "$w" | tr 'A-Z' 'a-z')"
  title="$(printf '%s' "${w:0:1}")${lower:1}"
  for form in "$w" "$title"; do
    bb_closure_word_ok "✅ $form (x)" >/dev/null 2>&1
    check_status "bb_closure_word_ok accepts the vocabulary word '$form'" 0 "$?"
  done
  bb_closure_word_ok "✅ $lower (x)" >/dev/null 2>&1
  check_status "bb_closure_word_ok refuses the all-lowercase '$lower' (prose, not a closure)" 1 "$?"
done
d609="$(new_repo)"
f609="$d609/BACKLOG.md"
printf '### dir #601 — emphasis between glyph and word — R2 — ✅ **Done 2026-09-20**

body

### dir #602 — title-case word — R2 — ✅ Closed (2026-09-20)

body

### dir #603 — a word that only starts like a closure word — R2 — ✅ **Donezo**

body

### dir #605 — prose quoting the glyph before a plain word stays open — ❌ duplicate detection fails — R2 — → pool

body

### dir #604 — a sub-status stays open — R2 — ✅ RUN 1 EXECUTED

body
' > "$f609"
out609="$(backlog_ticket_blocks "$f609")"
row609() { printf '%s\n' "$out609" | awk -F'\t' -v n="dir #$1 " 'index($4, n) {print $3; exit}'; }
check_status "MUTATION-PROOF: '✅ **Done 2026-09-20**' reads closed" 1 "$(row609 601)"
check_status "MUTATION-PROOF: '✅ Closed (…)' reads closed" 1 "$(row609 602)"
check_status "MUTATION-PROOF: title prose '❌ duplicate detection fails' stays open (no lowercase folding)" 0 "$(row609 605)"
check_status "'✅ **Donezo**' stays open" 0 "$(row609 603)"
check_status "control: '✅ RUN 1 EXECUTED' stays open" 0 "$(row609 604)"

# --- bb_strip_foreign_citations(): the dir #426 shared helper, tested directly (dir #142's
# coverage ratchet requires a new exported function to be pinned on its own, not only exercised
# indirectly through backlog_ticket_blocks) --------------------------------------------------------
stripped="$(bb_strip_foreign_citations 'Supersedes dir #5 — ✅ CLOSED as a duplicate' '9' '(✅|❌)[[:space:]]*(DONE|CLOSED)')"
check_absent "bb_strip_foreign_citations strips a foreign citation clause" "$stripped" 'CLOSED'
kept="$(bb_strip_foreign_citations 'dir #9 — ✅ CLOSED — no citation here' '9' '(✅|❌)[[:space:]]*(DONE|CLOSED)')"
check_contains "bb_strip_foreign_citations leaves a non-citation tag untouched" "$kept" 'CLOSED'
own_cited="$(bb_strip_foreign_citations 'Supersedes dir #9 — ✅ CLOSED, this IS our own ticket' '9' '(✅|❌)[[:space:]]*(DONE|CLOSED)')"
check_contains "bb_strip_foreign_citations does not strip a citation to own_num itself" "$own_cited" 'CLOSED'

# --- code-review high (delta finding, dir #432's dash-optionality follow-on): dir #432 made the
# em-dash OPTIONAL in the bare own-tag test, but the citation regexes still required a mandatory
# dash — so a foreign citation that itself omits the dash was never recognised as a citation,
# never stripped, and the dash-optional bare-tag test then matched its tag as this heading's own.
# MUTATION-PROOF: an open ticket citing a closed sibling with NO em-dash before the sibling's tag
# must stay open. ------------------------------------------------------------------------------
d420b="$(new_repo)"
f420b="$d420b/BACKLOG.md"
printf '### dir #980 — an open ticket, still needs work — R2 — → 0.9.0\nDuplicate of dir #985 ✅ CLOSED, no em-dash before the tag here.\n' > "$f420b"
out420b="$(backlog_ticket_blocks "$f420b")"
check_status "MUTATION-PROOF: a no-em-dash foreign citation is still recognised, own ticket stays open" \
  0 "$(printf '%s\n' "$out420b" | awk -F'\t' '$4 ~ /### dir #980 / {print $3; exit}')"

# --- code-review high (delta finding): the citation regexes' internal whitespace gaps must NOT
# cross a newline — switching backlog-blocks.sh's own `closed` detection to a whole-block scan
# (dir #420) let a citation verb ending one line and a DIFFERENT ticket's tag on the very next
# line satisfy the "no gap wider than whitespace" rule, wrongly treating a heading's own, genuinely
# wrapped closure tag as a citation to that different ticket and stripping it. MUTATION-PROOF: a
# heading whose own wrapped tag sits on the line right after a line ending in a recognised
# citation verb + a DIFFERENT dir #N must still read closed, and the ticket actually named in that
# citation-shaped line must independently still read closed too (both real, unrelated tickets). ---
d420c="$(new_repo)"
f420c="$d420c/BACKLOG.md"
printf '### dir #990 — an active ticket whose own status wraps oddly\nSupersedes dir #995\n— ✅ CLOSED\n\n### dir #995 — a real, separately closed ticket\n— ✅ CLOSED\n' > "$f420c"
out420c="$(backlog_ticket_blocks "$f420c")"
check_status "MUTATION-PROOF: own wrapped tag survives a citation-shaped line right before it" \
  1 "$(printf '%s\n' "$out420c" | awk -F'\t' '$4 ~ /### dir #990 / {print $3; exit}')"
check_status "control: the separately-named ticket in that citation-shaped line is also closed" \
  1 "$(printf '%s\n' "$out420c" | awk -F'\t' '$4 ~ /### dir #995 / {print $3; exit}')"

# --- code-review high, delta round: bb_strip_foreign_citations' internal gaps must recognise a
# real TAB character as whitespace, not just a literal space — an earlier form of the fix used
# `[\ \t]`, which bash's `[[ =~ ]]` parses as the bracket set {space, literal 't'} (backslash is
# not an escape inside a bracket expression, and bash's own tokenizing of the unquoted pattern
# drops the backslash before `\t` too) rather than "space or tab"; verified live that it silently
# failed to match a real tab and instead matched a stray literal "t". `[[:blank:]]` is the
# portable POSIX class that means exactly "space or tab, never newline". MUTATION-PROOF: a
# citation whose verb and `dir #N` are separated by a literal tab must still be recognised and
# stripped. -----------------------------------------------------------------------------------
d420d="$(new_repo)"
f420d="$d420d/BACKLOG.md"
printf '### dir #996 — an open ticket, still needs work — R2 — → 0.9.0\nDuplicate of\tdir #997 — ✅ CLOSED, a tab separates the verb from dir #.\n\n### dir #997 — a real, separately closed ticket\n— ✅ CLOSED\n' > "$f420d"
out420d="$(backlog_ticket_blocks "$f420d")"
check_status "MUTATION-PROOF: a tab-separated citation is recognised, citing ticket stays open" \
  0 "$(printf '%s\n' "$out420d" | awk -F'\t' '$4 ~ /### dir #996 / {print $3; exit}')"

# --- legacy numbered heading (### <n>.) is scanned too, unlike doctor.sh check 5's own scope ----
d3="$(new_repo)"
f3="$d3/BACKLOG.md"
printf '### 6. A legacy numbered ticket — → pool

body
' > "$f3"
out3="$(backlog_ticket_blocks "$f3")"
row3="$(printf '%s\n' "$out3" | grep -c .)"
if [ "$row3" = 1 ]; then
  pass "backlog_ticket_blocks scans legacy numbered headings too (1 row)"
else
  fail "backlog_ticket_blocks scans legacy numbered headings too (1 row)" "got $row3"
fi

# --- dir #839: a heading with NO blank line after it must not take its body lines into the heading
# block. The 0.17.0 groom folded twenty tickets whose first body line sat directly under a finished
# heading (`— R2 — → 0.17.0`); a body line reading "Builds on item 51 (✅ DONE: …)" then closed the
# OPEN ticket for the census and the pool report. A heading is FINISHED once it shows its tail (an
# R grade, a release/pool arrow or a status glyph); after that it takes no further line. Rows are
# selected by the ticket number inside field 4, never by line. ---------------------------------
d839="$(new_repo)"
f839="$d839/BACKLOG.md"
printf '### dir #881 — an open ticket, prose body right under the heading — R2 — → 0.17.0
Builds on item 51 (✅ DONE: shipped in PR #5), so this one is unblocked.

### dir #882 — an open ticket, a dashed body line right under the heading — R2 — → pool
Shipped earlier — ✅ DONE in PR #6, this follow-up is not.

### dir #883 — an open ticket, a Log line right under the heading — R2 — → 0.17.0
Log: 2026-10-12 — filed after the audit — ✅ DONE for the first half only.

### dir #884 — an open ticket, a bold lead right under the heading — R2 — → 0.17.0
**Found 2026-10-12 — ✅ DONE earlier by hand**, the rest is still open.

### dir #885 — a heading with no grade yet, a Draft slug line right under it
Draft slug: `x` — ✅ DONE as a draft, not as a ticket.

### dir #887 — an open lane ticket (the `next` lane arrow, grade R5 shape) — R5 — → next
Builds on item 51 (✅ DONE: shipped in PR #7), this one is not.

### dir #886 — a genuinely closed control — R2 — ✅ DONE (2026-10-01, done)
Closed body with no blank line before it.
' > "$f839"
out839="$(backlog_ticket_blocks "$f839")"
row839() { printf '%s\n' "$1" | awk -F'\t' -v n="$2" -v c="$3" 'index($4, n) {print $c; exit}'; }
for n in 881 882 883 884 885 887; do
  check_status "MUTATION-PROOF: dir #$n (body line directly under the heading) stays open" \
    0 "$(row839 "$out839" "dir #$n " 3)"
done
check_status "control: a closed heading with a body line right under it still reads closed" \
  1 "$(row839 "$out839" "dir #886 " 3)"

# The body-span end is unchanged: the ticket still owns its no-blank body lines up to the next heading.
check_status "dir #881's span still runs to the line before dir #882" \
  "$(( $(row839 "$out839" "dir #882 " 1) - 1 ))" "$(row839 "$out839" "dir #881 " 2)"

# A FINISHED heading takes no further line, whatever the line looks like: a dash-led line, even one
# opening with a status glyph, is a glued body line here, and so is the line after a dash-ended heading.
d839c="$(new_repo)"
f839c="$d839c/BACKLOG.md"
printf '### dir #861 — a finished open heading, a dash-led glyph line glued under it — R2 — → pool
— ✅ DONE for the first half only, the second half is still open.

### dir #862 — a finished open heading, a dash-led R-grade line glued under it — R2 — → pool
— R20 audit pending (✅ DONE for the survey).

### dir #863 — a graded heading that ends in a dash, a glued body line under it — R2 —
Builds on item 51 (✅ DONE: shipped in PR #5), this one is not.

### dir #864 — a graded heading whose closure tag wraps onto its own line — R2 —
— ✅ CLOSED (2026-10-01, done)
' > "$f839c"
out839c="$(backlog_ticket_blocks "$f839c")"
# The accepted residual (dir #864 above), recorded: a closure tag wrapped onto the line after a
# FINISHED first line stays out of the block and reads open (bb_heading_continues' header names it,
# and this assertion flips with any change that makes it read closed). A title that wraps BEFORE its
# tail still reads closed (dir #9/#900/#950 above).
check_status "accepted residual: a closure tag wrapped after a finished first line reads open" \
  0 "$(row839 "$out839c" "dir #864 " 3)"
for n in 861 862 863; do
  check_status "MUTATION-PROOF: dir #$n (finished heading, glued line of any shape) stays open" \
    0 "$(row839 "$out839c" "dir #$n " 3)"
done

# --- dir #839: the standing-list shapes (legacy `### <n>.` headings, tag on the heading line, body
# directly underneath) keep their verdicts — #11/#21 closed, #5/#10 open. -----------------------
d839b="$(new_repo)"
f839b="$d839b/BACKLOG.md"
printf '### 11. First fresh-adopter install feedback (captured 2026-07-11 — ✅ CLOSED same day, PR #61)
Findings were folded into the install flow.
### 21. Install-flow redesign — make adoption dead-simple (captured 2026-07-12) ✅ DONE
Shipped as PR #70.
### 5. Token-usage tracing mode (captured 2026-07-03) — → 0.13.0
Earlier attempt (✅ DONE for the feasibility half) — the build itself is still open.
### 10. Impact-track keel itself (captured 2026-07-10) — R1 — → 0.9.0
Phase one ✅ DONE; phase two open.
' > "$f839b"
out839b="$(backlog_ticket_blocks "$f839b")"
check_status "legacy #11 (tag on the heading line, body right under it) reads closed" 1 "$(row839 "$out839b" "### 11. " 3)"
check_status "legacy #21 (dashless tag on the heading line) reads closed" 1 "$(row839 "$out839b" "### 21. " 3)"
check_status "MUTATION-PROOF: legacy #5 (no tag, body glyph right under it) reads open" 0 "$(row839 "$out839b" "### 5. " 3)"
check_status "MUTATION-PROOF: legacy #10 (graded, body glyph right under it) reads open" 0 "$(row839 "$out839b" "### 10. " 3)"

# --- no readable file -> silent empty output, not an error --------------------------------------
out4="$(backlog_ticket_blocks "$d/no-such-file.md")"
if [ -z "$out4" ]; then
  pass "no readable BACKLOG.md -> empty output, not an error"
else
  fail "no readable BACKLOG.md -> empty output, not an error" "got: $out4"
fi

# --- a readable file with NO matching heading/boundary line at all -> empty output, not a crash --
# MUTATION-PROOF: bash 3.2 (macOS's stock /bin/bash) throws "unbound variable" expanding an
# EMPTY array under `set -u` instead of iterating zero times — a prose-only file (no `### dir
# #N`/`### <n>.`/`## ` line anywhere) leaves `boundary_raw` empty and reproduces it without the
# `[ -gt 0 ]` guard around the array-expanding `for`.
d6="$(new_repo)"
f6="$d6/BACKLOG.md"
printf 'just some prose, no ticket headings and no level-2 sections at all\n' > "$f6"
run bash -c '. "'"$REPO_ROOT"'/tools/lib/fence-blank.sh"; . "'"$lib"'"; backlog_ticket_blocks "'"$f6"'"'
check_status "a heading-less file does not crash the scanner -> exit 0" 0 "$STATUS"
check_absent "no unbound-variable error leaks to stderr" "$OUT" "unbound variable"
if [ -z "$OUT" ]; then
  pass "a heading-less file -> empty output"
else
  fail "a heading-less file -> empty output" "got: $OUT"
fi

# --- backlog_root_for(): the MAIN checkout's own repo root resolves to itself -------------------
# `cd ... && pwd` on both sides, not a raw string compare: macOS symlinks $TMPDIR under
# /var -> /private/var, and `git worktree list` resolves that symlink while the raw mktemp
# path handed in does not — comparing resolved paths is what the function actually promises.
d5="$(new_repo)"
resolved="$(backlog_root_for "$d5")"
resolved_real="$(cd "$resolved" && pwd -P)"
d5_real="$(cd "$d5" && pwd -P)"
if [ "$resolved_real" = "$d5_real" ]; then
  pass "backlog_root_for on a plain single-checkout repo resolves to itself"
else
  fail "backlog_root_for on a plain single-checkout repo resolves to itself" "got $resolved_real, want $d5_real"
fi


# --- bb_heading_end (dir #916): the one wrapped-heading walk ---------------------------------------------------
# Unit: an unfinished title takes its wrapped lines up to the line that finishes it; a finished heading takes none;
# a blank line, a body opener and the 50-line cap each end the walk; <last_index> bounds it.
hl=("### dir #1 — a title that wraps" "across two lines — R2 — → pool" "Log: a body opener" "")
bb_heading_end hl 0 3
check_eq "bb_heading_end: a wrapped title ends after its finishing line" "$BB_HEADING_END" "2"
check_eq "bb_heading_end: the block joins the lines with newlines" "$BB_HEADING_BLOCK" "### dir #1 — a title that wraps"$'\n'"across two lines — R2 — → pool"
hl=("### dir #2 — done — R2 — ✅ DONE (2026-08-01)" "glued body line" "")
bb_heading_end hl 0 2
check_eq "bb_heading_end: a finished heading takes no further line" "$BB_HEADING_END" "1"
hl=("pad" "### dir #3 — unfinished" "second" "third" "")
bb_heading_end hl 1 2
check_eq "bb_heading_end: last_index bounds the walk" "$BB_HEADING_END" "3"
bb_heading_end hl 1 4
check_eq "bb_heading_end: a blank line ends the walk" "$BB_HEADING_END" "4"
hl=("### dir #4 — endless")
for i in $(seq 1 60); do hl+=("wrapped $i"); done
bb_heading_end hl 0 60
check_eq "bb_heading_end: at most 50 lines past the heading" "$BB_HEADING_END" "51"

# Census: no second copy of the walk. bb_heading_continues is called from bb_heading_end only, so no other tool
# decides which following lines belong to a heading (a comment may still name it).
census="$(grep -rnE '^[^#]*bb_heading_continues' "$REPO_ROOT/tools" --include='*.sh' | grep -v '/tools/lib/backlog-blocks\.sh:' || true)"
check_eq "no tool but the lib calls bb_heading_continues (no second heading walk)" "$census" ""
for c in tools/lib/backlog-blocks.sh tools/self/doctor.sh tools/self/accumulate.sh tools/cloud-brief.sh; do
  check_contains "$c walks a heading through bb_heading_end" "$(cat "$REPO_ROOT/$c")" 'bb_heading_end '
done

# --- dir #448: two false-`closed=1` shapes in the closure helpers (both latent; no live instance) --------------
# (1) bb_strip_foreign_citations must reach a FIXED POINT: a self-citation (own_num) ahead of a foreign one
# used to halt the loop, leaving the foreign citation's tag in the block for the bare-tag test to read as own.
# Checked with a non-closure tag too (the caller's tag_pattern is a parameter): `RETRACTED` here.
blk448=$'### dir #448 — an open ticket — R2 — → pool\nSupersedes dir #448 — RETRACTED once; Supersedes dir #9 — RETRACTED.'
got448="$(bb_strip_foreign_citations "$blk448" 448 'RETRACTED')"
check_contains "dir #448: the self-citation survives the strip" "$got448" 'Supersedes dir #448 — RETRACTED'
check_status "MUTATION-PROOF: dir #448: a foreign citation BEHIND a self-citation is stripped (fixed point)" \
  1 "$([[ "$got448" == *'dir #9'* ]] && echo 0 || echo 1)"
blk448=$'Duplicate of dir #448 ✅ DONE; Duplicate of dir #9 ✅ DONE; Duplicate of dir #8 ✅ DONE'
got448="$(bb_strip_foreign_citations "$blk448" 448 "$BB_CLOSURE_TAG_PATTERN")"
check_eq "dir #448: Duplicate form, self then two foreign -> only the self citation remains" \
  'Duplicate of dir #448 ✅ DONE;  ' "$got448"
# (2) BB_CLOSURE_TAG_PATTERN's internal gaps are same-line whitespace: a glyph at EOL and the word at BOL of
# the next line is NOT one closure tag. `[[:space:]]` bridged the newline. The census over the real file is
# byte-identical either way, so only this fixture tells the two apart.
tagmatch448() { if [[ "$1" =~ ${BB_CLOSURE_TAG_PATTERN}([^a-zA-Z]|$) ]]; then echo 1; else echo 0; fi; }
check_status "MUTATION-PROOF: dir #448: glyph at EOL + word at BOL is not a closure tag" \
  0 "$(tagmatch448 $'title ends ✅\nDONE starts the next line')"
check_status "MUTATION-PROOF: dir #448: glyph, newline, emphasis, word is not a closure tag" \
  0 "$(tagmatch448 $'title ends ❌\n**Closed** next line')"
check_status "dir #448: glyph + space + word still closes" 1 "$(tagmatch448 'x ✅ DONE (2026-08-01)')"
check_status "dir #448: glyph + tab + word still closes" 1 "$(tagmatch448 $'x ✅\tDONE')"
check_status "dir #448: glyph + emphasis + word still closes" 1 "$(tagmatch448 'x ✅ **Done 2026-09-20**')"
check_status "dir #448: glyph directly followed by word still closes" 1 "$(tagmatch448 'x ✅DONE')"

summary
