#!/usr/bin/env bash
# tools/self/pool-report.sh: --help/bad-args, the no-BACKLOG.md skip, the four reported figures
# (pool size, oldest age, R-level split, structurally-parked exclusion by rule), the
# `→ pool`-vs-prose-arrow extraction rule, --record idempotency, and the two-consecutive-minors
# growth trigger — must fire on a constructed fixture and must NOT fire on today's real
# BACKLOG.md baseline (dir #360's own done-criterion).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

pr="$REPO_ROOT/tools/self/pool-report.sh"

# --- --help / bad args -----------------------------------------------------------------------
run "$pr" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$pr" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"

# --- no BACKLOG.md -> silent skip, exit 0 -----------------------------------------------------
run "$pr" "$SANDBOX/no-such-backlog.md"
check_status "missing BACKLOG.md -> exit 0 (skip, not an error)" 0 "$STATUS"
check_contains "prints a skip line" "$OUT" "no readable BACKLOG.md"

# --- fixture builder ----------------------------------------------------------------------------
mk_backlog() {
  local d f
  d="$(mktemp -d "$SANDBOX/bl.XXXXXX")"
  f="$d/BACKLOG.md"
  printf '%s' "$1" > "$f"
  printf '%s' "$f"
}

# --- the four figures, and the prose-arrow exclusion (G3's own rule: only `→ pool` / `→ x.y.z`
# count as a release tag; "→ ask" is prose and must not be read as a pool member) --------------
backlog="### dir #1 — a pool ticket (found 2026-01-01) — R1 — → pool

body

### dir #2 — a scheduled ticket, not pool — R2 — → 0.9.0

body

### dir #3 — a pool ticket with a prose arrow inside its own body (found 2026-08-01) — R2 — → pool

this ticket also says → ask the operator before doing X, which must not be read as a tag

### dir #4 — closed, must not count toward the pool even if tagged pool in prose — R1 — ✅ DONE (2026-01-01, done) — → pool

body

### dir #5 — blocked pool ticket — R3 — ⛔ BLOCKED on an external event — → pool

body

### dir #6 — gated pool ticket — R3 — gate = next touch of a related file — → pool

body
"

f="$(mk_backlog "$backlog")"
run "$pr" --history "$SANDBOX/hist-empty.jsonl" "$f"
check_status "basic run -> exit 0" 0 "$STATUS"
check_contains "pool size excludes the non-pool and closed tickets" "$OUT" "pool size:                     4"
check_contains "R-level split reports R1/R2/R3" "$OUT" "R1=1 R2=1 R3=2"
check_contains "structurally-parked excluded by rule (2 of 4: blocked + gate)" "$OUT" \
  "excluding structurally-parked:  2 (of 4; 2 parked by rule"
check_contains "oldest entry is the earliest dated pool ticket" "$OUT" "d (dir #1)"

# --- structurally-parked wording variants: "⛔ PARKED" counts, "⛔ UNBLOCKED" does NOT --------------
# MUTATION-PROOF pair, both real shapes found live in BACKLOG.md: a narrower `⛔.*BLOCKED` match
# would silently miss "⛔ PARKED ..." tickets (dir #309/#410's own shape); a bare `⛔` match would
# wrongly count "⛔ UNBLOCKED ..." (BACKLOG.md reuses the glyph for the opposite meaning).
backlog_parked_wording="### dir #7 — parked, not the legend's literal BLOCKED wording — R3 — ⛔ PARKED on a named trigger — → pool

body

### dir #8 — no longer blocked, must NOT count as parked — R2 — ⛔ UNBLOCKED 2026-08-29: cleared — → pool

body
"
fp="$(mk_backlog "$backlog_parked_wording")"
run "$pr" --history "$SANDBOX/hist-wording.jsonl" "$fp"
check_contains "MUTATION-PROOF: '⛔ PARKED' wording still counts as structurally-parked" "$OUT" \
  "excluding structurally-parked:  1 (of 2; 1 parked by rule"

# --- dir #425: the ⛔-blocked exclusion is CLAUSE-scoped, not whole-block-scoped — a heading
# stating both a current ⛔ block and its own future-unblock clause in one line must still count
# as parked (the single-state phrasing already counts parked=1; this must match it). --------------
clause_scope_backlog="### dir #601 — blocked, with its own future unblock clause on the same line — R2 — ⛔ BLOCKED by X, no longer ⛔ once X lands — → pool

body

### dir #602 — single-state control, same blocking reason, no unblock clause — R2 — ⛔ BLOCKED by X — → pool

body
"
fclause="$(mk_backlog "$clause_scope_backlog")"
run "$pr" --history "$SANDBOX/hist-clause-scope.jsonl" "$fclause"
check_contains "MUTATION-PROOF (dir #425): a heading with both a block and its own unblock clause still counts parked (2 of 2, not 1)" \
  "$OUT" "excluding structurally-parked:  0 (of 2; 2 parked by rule"

# --- --record idempotency ------------------------------------------------------------------------
hist="$SANDBOX/hist-record.jsonl"
run "$pr" --record 0.9.0 --history "$hist" "$f"
check_status "--record appends -> exit 0" 0 "$STATUS"
check_contains "reports the append" "$OUT" "appended"
run "$pr" --record 0.9.0 --history "$hist" "$f"
check_contains "second --record for the same release is a no-op" "$OUT" "already recorded"
lines_after="$(wc -l < "$hist" | tr -d ' ')"
check_status "history file has exactly one row after two --record calls" "1" "$lines_after"

# --- growth trigger: MUST NOT fire on today's real BACKLOG.md baseline (dir #360's own
# done-criterion) — insufficient recorded history is the correct reason it can't fire yet. -----
if [ -f "$REPO_ROOT/BACKLOG.md" ]; then
  real_backlog="$REPO_ROOT/BACKLOG.md"
else
  real_backlog=""
fi
if [ -n "$real_backlog" ]; then
  run "$pr" --history "$SANDBOX/hist-real-baseline.jsonl" "$real_backlog"
  check_absent "real baseline: growth trigger does not fire (no recorded history yet)" "$OUT" "WARN"
fi

# --- growth trigger: MUST fire on a constructed fixture (three strictly-increasing pool sizes) -
grow_backlog_lines=""
for i in $(seq 1 25); do
  grow_backlog_lines="${grow_backlog_lines}### dir #${i} — grown ticket ${i} — R1 — → pool

body

"
done
fgrow="$(mk_backlog "$grow_backlog_lines")"
hist_grow="$SANDBOX/hist-grow.jsonl"
printf '{"release":"0.7.0","date":"2026-07-01","pool_size":10}\n{"release":"0.8.0","date":"2026-08-01","pool_size":20}\n' > "$hist_grow"
run "$pr" --history "$hist_grow" "$fgrow"
check_status "growth fixture -> exit 0 (advisory only)" 0 "$STATUS"
check_contains "MUTATION-PROOF: growth trigger fires on 10 -> 20 -> 25" "$OUT" "WARN"

# Shrinking the pool back down (25 -> 20 -> 10, i.e. same history but pool now smaller) must NOT
# fire — the mutation-proof pair for the growth-direction check.
small_backlog="### dir #1 — one — R1 — → pool

body
"
fsmall="$(mk_backlog "$small_backlog")"
run "$pr" --history "$hist_grow" "$fsmall"
check_absent "shrinking pool does not fire the growth trigger" "$OUT" "WARN"

# --- FINDING-CA3-1 (v0.9.0 RC audit, CA3 round): the RETRACTED exclusion (was line ~104) is
# whole-block scoped, same "whose tag is it" shape as the F-04 bug tools/lib/backlog-blocks.sh's
# closed-tag detection already fixed. A live, correctly `→ pool`-tagged ticket whose OWN body
# cites a genuinely-retracted sibling using the "Superseded by dir #N — RETRACTED" idiom must NOT
# be dropped from the pool census; the genuinely-retracted sibling itself must still be excluded.
# MUTATION-PROOF pair: dir #501 (citation only, must count) vs. dir #503 (own tag, must not
# count) — reverting the own-tag scoping back to a bare whole-block `grep` drops dir #501 too,
# undercounting the pool from 2 to 1 (the audit's own live-reproduced shape).
retracted_backlog="### dir #500 — a plain pool ticket (found 2026-01-01) — R2 — → pool

body

### dir #501 — a pool ticket that cites a retracted sibling (found 2026-01-01) — R1 — → pool
Superseded by dir #503 — RETRACTED for background; this ticket itself is still active.

### dir #503 — RETRACTED (2026-01-01, false positive) — a superseded idea — R1 — → pool

body
"
fret="$(mk_backlog "$retracted_backlog")"
run "$pr" --history "$SANDBOX/hist-retracted.jsonl" "$fret"
check_contains "MUTATION-PROOF: a ticket citing a sibling's retraction still counts toward the pool (2, not 1)" \
  "$OUT" "pool size:                     2"

# --- code-review medium (this fix's own review round, found live): a ticket that is BOTH
# genuinely retracted (its own tag) AND cites a different ticket's retraction must still be
# excluded — an if/elif/elif chain that stops at the first matched citation branch (regardless
# of whether that citation's cited number equals own_num) would shadow the own-tag check that
# would otherwise catch it, since being an `elif` means it never runs. MUTATION-PROOF: reverting
# to that if/elif/elif shape wrongly keeps dir #700 in the pool (2, not the correct 1).
own_plus_citation_backlog="### dir #700 — RETRACTED (2026-01-01) — superseded by dir #701 — RETRACTED for background too — R1 — → pool

body

### dir #701 — a plain pool ticket, unaffected (found 2026-01-01) — R2 — → pool

body
"
fopc="$(mk_backlog "$own_plus_citation_backlog")"
run "$pr" --history "$SANDBOX/hist-own-plus-citation.jsonl" "$fopc"
check_contains "MUTATION-PROOF: a ticket that is BOTH own-retracted AND cites a sibling's retraction is still excluded (1, not 2)" \
  "$OUT" "pool size:                     1"

# --- code-review medium delta round (found live): a ticket that cites TWO different retracted
# siblings, one via each recognised verb form ("Supersedes" and "Duplicate of"), but is not
# itself retracted, must still count toward the pool. A single if/elif strip only ever removes
# ONE foreign citation, leaving the second one's bare "— RETRACTED" behind to wrongly match.
# MUTATION-PROOF: reverting the two `while` loops back to a single `if`/`elif` pair wrongly drops
# dir #710 from the pool (0, not the correct 1).
two_citations_backlog="### dir #710 — cites two different retracted siblings, not itself retracted — R1 — → pool
Supersedes dir #711 — RETRACTED for background reasons. Duplicate of dir #712 — RETRACTED as well.

### dir #711 — RETRACTED (2026-01-01) — one of the cited siblings — R1 — → pool

body

### dir #712 — RETRACTED (2026-01-01) — the other cited sibling — R1 — → pool

body
"
ftwo="$(mk_backlog "$two_citations_backlog")"
run "$pr" --history "$SANDBOX/hist-two-citations.jsonl" "$ftwo"
check_contains "MUTATION-PROOF: a ticket citing two different retracted siblings (one per verb form) still counts toward the pool (1, not 0)" \
  "$OUT" "pool size:                     1"

# --- code-review high, delta round: making the RETRACTED bare-tag test's em-dash optional (to
# mirror dir #432's closure-tag fix) was tried and REVERTED — it reopened a title-prose
# false-positive: a heading whose TITLE merely mentions the bare word "retracted" (no tag intended
# at all) matched and was wrongly excluded from the pool census. MUTATION-PROOF: a genuinely open,
# un-tagged pool ticket whose title happens to contain the bare word "RETRACTED" must still count. -
prose_backlog="### dir #6 — investigate whether the RETRACTED ticket process needs revisiting — R1 — → pool

still open, needs work
"
fprose="$(mk_backlog "$prose_backlog")"
run "$pr" --history "$SANDBOX/hist-prose.jsonl" "$fprose"
check_contains "MUTATION-PROOF: a bare 'RETRACTED' in ordinary title prose does not exclude an open ticket from the pool" \
  "$OUT" "pool size:                     1"

# --- code-review medium delta round 2 (found live, coverage gap not a code defect): the case
# above only exercises ONE citation per verb form, so it would not catch a regression from
# `while` back to a single `if` on either loop (a single strip per form already suffices for that
# fixture). This fixture cites the SAME verb form ("Supersedes") twice, closing that gap.
# MUTATION-PROOF: reverting the Supersedes `while` loop back to a single `if` wrongly drops dir
# #720 from the pool (0, not the correct 1).
same_verb_twice_backlog="### dir #720 — cites two different retracted siblings via the SAME verb form, not itself retracted — R1 — → pool
Supersedes dir #721 — RETRACTED for one reason. Supersedes dir #722 — RETRACTED for another.

### dir #721 — RETRACTED (2026-01-01) — one of the cited siblings — R1 — → pool

body

### dir #722 — RETRACTED (2026-01-01) — the other cited sibling — R1 — → pool

body
"
fsame="$(mk_backlog "$same_verb_twice_backlog")"
run "$pr" --history "$SANDBOX/hist-same-verb-twice.jsonl" "$fsame"
check_contains "MUTATION-PROOF: a ticket citing two retracted siblings via the SAME verb form still counts toward the pool (1, not 0)" \
  "$OUT" "pool size:                     1"

# --- v0.9.0 RC audit, final fix round: the `⛔`-exclusion pattern (was `⛔[[:space:]]*UN`,
# case-insensitive) must name exactly the two documented shapes ("⛔ UNBLOCKED", "no longer ⛔"),
# not any ⛔-adjacent word starting "un". MUTATION-PROOF: reverting the pattern back to the bare
# `UN` prefix wrongly treats "⛔ unless a consumer asks" as the unblocked shape and drops it from
# the parked count (0 instead of 1).
unless_backlog="### dir #600 — a pool ticket blocked on a soft condition (found 2026-01-01) — R2 — ⛔ unless a consumer asks — → pool

body
"
fun="$(mk_backlog "$unless_backlog")"
run "$pr" --history "$SANDBOX/hist-unless.jsonl" "$fun"
check_contains "MUTATION-PROOF: '⛔ unless ...' still counts as structurally-parked (not read as UNBLOCKED)" \
  "$OUT" "excluding structurally-parked:  0 (of 1; 1 parked by rule"

# --- v0.9.0 RC audit, final fix round: a nonexistent BACKLOG_PATH must still hit the "no
# readable BACKLOG.md" skip and exit 0 — the `cd` deriving backlog_root from its dirname ran
# BEFORE the missing-file guard, so a nonexistent directory made `cd` fail under `set -e` and
# abort with exit 1 plus raw stderr instead of the documented silent skip. MUTATION-PROOF: moving
# the `cd` back above the guard reproduces exit 1 with a "No such file or directory" stderr line
# instead of this script's own advisory skip message.
run "$pr" "/no/such/dir/BACKLOG.md"
check_status "nonexistent BACKLOG_PATH directory -> exit 0 (advisory skip, not a crash)" 0 "$STATUS"
check_contains "prints the same skip line, not raw cd stderr" "$OUT" "no readable BACKLOG.md"
check_absent "no raw 'No such file or directory' stderr leaks through" "$OUT" "No such file or directory"

summary
