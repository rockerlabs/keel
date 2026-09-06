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
