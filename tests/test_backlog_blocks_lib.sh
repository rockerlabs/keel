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
