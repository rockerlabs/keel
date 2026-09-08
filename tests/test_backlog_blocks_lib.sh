#!/usr/bin/env bash
# test_backlog_blocks_lib.sh — dir #359/#360: tools/lib/backlog-blocks.sh is the one shared
# BACKLOG.md ticket-block scanner both tools/self/archive-sweep-check.sh and
# tools/self/pool-report.sh source (dir #142's coverage ratchet requires a NEW shipped script
# to be tested directly, not only exercised indirectly through its consumers). Pins both
# functions the lib exports: backlog_ticket_blocks() and backlog_root_for().
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

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

# --- bb_strip_foreign_citations(): the dir #426 shared helper, tested directly (dir #142's
# coverage ratchet requires a new exported function to be pinned on its own, not only exercised
# indirectly through backlog_ticket_blocks) --------------------------------------------------------
stripped="$(bb_strip_foreign_citations 'Supersedes dir #5 — ✅ CLOSED as a duplicate' '9' '(✅|❌)[[:space:]]*(DONE|CLOSED)')"
check_absent "bb_strip_foreign_citations strips a foreign citation clause" "$stripped" 'CLOSED'
kept="$(bb_strip_foreign_citations 'dir #9 — ✅ CLOSED — no citation here' '9' '(✅|❌)[[:space:]]*(DONE|CLOSED)')"
check_contains "bb_strip_foreign_citations leaves a non-citation tag untouched" "$kept" 'CLOSED'
own_cited="$(bb_strip_foreign_citations 'Supersedes dir #9 — ✅ CLOSED, this IS our own ticket' '9' '(✅|❌)[[:space:]]*(DONE|CLOSED)')"
check_contains "bb_strip_foreign_citations does not strip a citation to own_num itself" "$own_cited" 'CLOSED'

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

summary
