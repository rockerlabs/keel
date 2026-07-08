#!/usr/bin/env bash
# Tests for tools/keel-impact.sh — the deterministic half of the impact score. The model's judgment (which
# events happened) is out of scope; we pin the machinery: the score is DERIVED from event counts by the
# fixed formula (never asserted), the confidence tier, header/row bookkeeping, the rolling trend, the honest
# cumulative signals, input validation, and table-safety escaping.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/keel-impact.sh"
LEDGER="$SANDBOX/ledger.md"
export KEEL_IMPACT_LEDGER="$LEDGER"

# --- empty state --------------------------------------------------------------------------------
run bash "$TOOL" rollup
check_status "rollup on missing ledger succeeds" 0 "$STATUS"
check_contains "rollup reports empty ledger" "$OUT" "no scored sessions yet"
check_file "rollup creates the ledger header" "$LEDGER"
check_contains "header carries the column row" "$(cat "$LEDGER")" "| date | score | conf |"
check_contains "header documents the formula" "$(cat "$LEDGER")" "round(100"

# --- score is DERIVED, not passed --------------------------------------------------------------
# a lone guardrail fire: HELP=3, COST=0 → 100
run bash "$TOOL" add --guard 1 --evidence "secret-guard blocked a key" --gap "none"
check_status "add derives from a guard event" 0 "$STATUS"
check_contains "guard-only derives score 100" "$OUT" "derived score 100/100"
check_contains "single event is low confidence" "$OUT" "conf low"
check_contains "row records the derived score+conf" "$(cat "$LEDGER")" "| 100 | low | 1 | 0 | 0 | 0 | 0 |"

# 2 fire + 1 miss: HELP=4, COST=2 → round(66.6)=67, 3 events → med
run bash "$TOOL" add --fire 2 --miss 1 --silent 3 --evidence "feature-branch flow" --gap "demote: lint silent"
check_contains "mixed help/cost derives 67" "$OUT" "derived score 67/100"
check_contains "three events is medium confidence" "$OUT" "conf med"
# row cols: date|score|conf|guard|fire|hit|miss|fric|silent → guard=0 fire=2 hit=0 miss=1 fric=0 silent=3
check_contains "silent count is recorded, not scored" "$(cat "$LEDGER")" "| 0 | 2 | 0 | 1 | 0 | 3 |"

# only a miss: HELP=0, COST=2 → 0 (Keel was net-negative — the honest floor, not a skip)
run bash "$TOOL" add --miss 1 --evidence "hunted the test cmd" --gap "promote: test cmd"
check_contains "cost-only derives score 0" "$OUT" "derived score 0/100"

# no events at all → "—" (nothing to measure), never a fake 0
run bash "$TOOL" add --silent 4 --evidence "inert session" --gap "demote: 4 rules idle"
check_contains "no events derives an em-dash score" "$OUT" "derived score —/100"
check_contains "no events is 'none' confidence" "$OUT" "conf none"

# high confidence at 6+ events
run bash "$TOOL" add --guard 1 --fire 2 --hit 3 --evidence "many cites" --gap "none"
check_contains "six events is high confidence" "$OUT" "conf high"

# --- rollup: mean skips the em-dash, cumulative signals are summed from events ------------------
run bash "$TOOL" rollup
check_contains "rollup counts every session" "$OUT" "5 session(s)"
check_contains "mean is over numeric scores only" "$OUT" "over 4 scored"
check_contains "trend shows numeric scores oldest-first" "$OUT" "100 → 67 → 0"
check_contains "cumulative guardrail fires summed" "$OUT" "2 guardrail fire(s)"
check_contains "cumulative retrieval misses summed" "$OUT" "2 retrieval miss(es)"

# --- free-text safety --------------------------------------------------------------------------
run bash "$TOOL" add --fire 1 --evidence "value | with pipe" --gap "none"
check_status "row with a pipe in free text succeeds" 0 "$STATUS"
check_contains "pipe in free text is escaped" "$(cat "$LEDGER")" 'value \| with pipe'

# --- validation --------------------------------------------------------------------------------
run bash "$TOOL" add --guard -1 --evidence x
check_status "negative count is rejected" 2 "$STATUS"
check_contains "negative count explains itself" "$OUT" "non-negative integer"

run bash "$TOOL" add --fire abc --evidence x
check_status "non-integer count is rejected" 2 "$STATUS"

run bash "$TOOL" add --guard 1 --bogus x
check_status "unknown flag is rejected" 2 "$STATUS"

# an add with no event flags is legal — it derives "—" (an honestly inert session)
run bash "$TOOL" add --evidence "nothing happened" --gap "none"
check_status "eventless add is legal" 0 "$STATUS"
check_contains "eventless add derives em-dash" "$OUT" "derived score —/100"

summary
