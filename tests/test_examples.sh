#!/usr/bin/env bash
# examples/tour.sh is part of the product — guard it so the demo can't rot as the tools evolve.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

tour="$REPO_ROOT/examples/tour.sh"

run bash "$tour"
check_status "tour runs end-to-end → exit 0" 0 "$STATUS"
check_contains "scaffolds via init-project" "$OUT" "CLAUDE.md created from template"
check_contains "doctor flags the secret-guard WARN first" "$OUT" "WARN secret-guard not wired"
check_contains "ends on a clean baseline (WARN cleared)" "$OUT" "structural baseline OK"
check_contains "secret-guard blocks the planted key" "$OUT" "BLOCKED"

summary
