#!/usr/bin/env bash
# Tests for tools/keel-impact.sh — the deterministic half of the impact score. The model's judgment is
# out of scope here; we pin the bookkeeping: header creation, row append, axis parsing, the rolling
# trend, input validation, and the table-safety escaping of free-text cells.
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
check_contains "header carries the column row" "$(cat "$LEDGER")" "| date | score |"

# --- a first scored row -------------------------------------------------------------------------
run bash "$TOOL" add --score 72 --axes conv=18,retr=12,rework=15,guard=20,cmd=15 \
  --friction 8 --evidence "secret-guard blocked a key" --gap "demote: lint rule silent"
check_status "add a valid row succeeds" 0 "$STATUS"
check_contains "add echoes the score" "$OUT" "score 72/100"
check_contains "add prints the fresh mean" "$OUT" "mean score 72.0/100"
check_contains "row lands in the ledger" "$(cat "$LEDGER")" "| 72 | 18 | 12 | 15 | 20 | 15 | 8 |"

# --- a second row moves the mean and the trend --------------------------------------------------
run bash "$TOOL" add --score 15 --axes conv=6,retr=-4,cmd=8 --friction 5 \
  --evidence "/wrap reconciled stale PR" --gap "promote: test cmd hunted"
check_status "add a second row succeeds" 0 "$STATUS"
check_contains "mean is recomputed over both rows" "$OUT" "mean score 43.5/100"
check_contains "trend shows both scores oldest-first" "$OUT" "72 → 15"
# a blank axis becomes a dash, not a spurious 0
check_contains "unspecified axes render as dash" "$(cat "$LEDGER")" "| 15 | 6 | -4 | - | - | 8 | 5 |"

# --- free-text safety: a pipe in evidence must not break the table ------------------------------
run bash "$TOOL" add --score 40 --axes conv=10 --evidence "value | with pipe" --gap "none"
check_status "row with a pipe in free text succeeds" 0 "$STATUS"
check_contains "pipe in free text is escaped" "$(cat "$LEDGER")" 'value \| with pipe'

# --- validation ---------------------------------------------------------------------------------
run bash "$TOOL" add --axes conv=10
check_status "missing --score is rejected" 2 "$STATUS"
check_contains "missing --score explains itself" "$OUT" "--score is required"

run bash "$TOOL" add --score 140
check_status "out-of-range score is rejected" 2 "$STATUS"
check_contains "range error explains itself" "$OUT" "out of range"

run bash "$TOOL" add --score abc
check_status "non-integer score is rejected" 2 "$STATUS"

run bash "$TOOL" add --score 50 --bogus x
check_status "unknown flag is rejected" 2 "$STATUS"

# --- rollup after adds reflects all rows --------------------------------------------------------
run bash "$TOOL" rollup
check_contains "rollup counts every scored row" "$OUT" "3 session(s)"

summary
