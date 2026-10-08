#!/usr/bin/env bash
# test_sandbox_escapes.sh — dir #720 S10-3: the two demo scripts that promise to touch nothing on the
# machine (examples/tour.sh, docs/demo/record-demo.sh) must neutralize an exported impact-store override.
# Both redirect HOME into a throwaway sandbox, but tools/lib/impact-store.sh resolves KEEL_IMPACT_STORE /
# KEEL_IMPACT_LOG / KEEL_HOME BEFORE HOME, so an operator's exported value would send the demo's writes
# into their REAL store. Hand each script such overrides and assert nothing lands there.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

store="$SANDBOX/real-store"; log="$SANDBOX/real-log.tsv"; khome="$SANDBOX/real-keel-home"

run env KEEL_IMPACT_STORE="$store" KEEL_IMPACT_LOG="$log" KEEL_HOME="$khome" bash "$REPO_ROOT/examples/tour.sh"
check_status "tour.sh with ambient impact overrides → exit 0" 0 "$STATUS"
check_nodir "tour.sh leaves the ambient KEEL_IMPACT_STORE untouched" "$store"
check_nofile "tour.sh leaves the ambient KEEL_IMPACT_LOG untouched" "$log"
check_nodir "tour.sh leaves the ambient KEEL_HOME untouched" "$khome"

run env KEEL_IMPACT_STORE="$store" KEEL_IMPACT_LOG="$log" KEEL_HOME="$khome" bash "$REPO_ROOT/docs/demo/record-demo.sh" --scenes
check_nodir "record-demo.sh --scenes leaves the ambient KEEL_IMPACT_STORE untouched" "$store"
check_nofile "record-demo.sh --scenes leaves the ambient KEEL_IMPACT_LOG untouched" "$log"
check_nodir "record-demo.sh --scenes leaves the ambient KEEL_HOME untouched" "$khome"

summary
