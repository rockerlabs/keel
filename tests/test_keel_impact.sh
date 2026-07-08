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
# Isolate the event log from the very top: an absent path means the early add cases ingest nothing,
# so an ambient $KEEL_IMPACT_LOG in the runner's environment can't perturb the derived scores. The
# auto-ingest section below points this at a real log on purpose.
export KEEL_IMPACT_LOG="$SANDBOX/no-such-log"

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

# --- deterministic event log: producer API + auto-ingest ---------------------------------------
# A fresh, isolated ledger+log for the ingest cases (the cases above left rows in $LEDGER).
LEDGER="$SANDBOX/ledger2.md"; LOG="$SANDBOX/events.log"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG"

run bash "$TOOL" event guard secret-guard blocked
check_status "event records a guard line" 0 "$STATUS"
check_contains "event confirms the write" "$OUT" "recorded guard event"
check_contains "log line is well-formed TSV" "$(cat "$LOG")" "guard	secret-guard	blocked"

run bash "$TOOL" event bogus
check_status "unknown event type is rejected" 2 "$STATUS"

# a second guard event, then a score: the model passes NO --guard; both logged guards are auto-ingested.
run bash "$TOOL" event guard secret-guard blocked
run bash "$TOOL" add --fire 1 --evidence "flow" --gap "none"
check_status "add with pending log events succeeds" 0 "$STATUS"
check_contains "add reports the auto-ingest" "$OUT" "2 auto-ingested"
# HELP = 3*2(guard, from log) + 2*1(fire) = 8, COST=0 → score 100; guard col shows the ingested 2
check_contains "logged guards reach the derived score" "$(cat "$LEDGER")" "| 100 | med | 2 | 1 |"
check_contains "log is truncated after ingest" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# a subsequent score does NOT re-count the consumed events (no double counting)
run bash "$TOOL" add --hit 1 --evidence "later" --gap "none"
check_contains "consumed events are not re-ingested" "$OUT" "from 1 event(s)"

# --no-ingest leaves the log untouched and scores only the model's counts
run bash "$TOOL" event guard secret-guard blocked
run bash "$TOOL" add --fire 1 --no-ingest --evidence "manual only" --gap "none"
check_contains "--no-ingest ignores the log" "$OUT" "from 1 event(s)"
check_contains "--no-ingest preserves the log" "$(wc -l < "$LOG" | tr -d ' ')" "1"

# --- enable: opt a repo into tracking (the .keel/ marker the hooks look for) ---------------------
erepo="$(new_repo)"
run bash "$TOOL" enable "$erepo"
check_status "enable succeeds on a git repo" 0 "$STATUS"
check_dir "enable creates the .keel/ marker" "$erepo/.keel"
check_contains "enable gitignores /.keel/" "$(cat "$erepo/.gitignore" 2>/dev/null)" "/.keel/"
check_contains "enable confirms tracking is on" "$OUT" "impact tracking enabled"

# idempotent: a second enable doesn't duplicate the gitignore line
run bash "$TOOL" enable "$erepo"
check_status "second enable succeeds" 0 "$STATUS"
check_contains "gitignore has exactly one /.keel/ line" "$(grep -c '^/\.keel/$' "$erepo/.gitignore")" "1"

# end-to-end: an enabled repo records a guard event with NO env, and add auto-ingests it
export KEEL_IMPACT_LEDGER="$erepo/ledger.md"
run_in "$erepo" env -u KEEL_IMPACT_LOG bash "$TOOL" event guard secret-guard blocked
check_file "event lands in the enabled repo's .keel/ log" "$erepo/.keel/impact-events.log"

summary
