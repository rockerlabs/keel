#!/usr/bin/env bash
# test_pipeline_canary.sh — tools/pipeline-canary.sh (backlog dir #64 tier 3): the sandbox setup/check
# cycle and the fully-automated seeded-bypass red demo. Everything here runs the REAL gate script
# (tools/pre-pr-gate.sh) against throwaway sandboxes — no live model, no network (the stub `gh` never
# shells out), and every canary state file is redirected under this test's own $SANDBOX so a run of this
# suite never touches a real, in-progress canary session on the machine.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

canary="$REPO_ROOT/tools/pipeline-canary.sh"
check_file "pipeline-canary.sh exists" "$canary"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — pipeline-canary tests skipped (the gate it drives requires jq)"
  summary; exit $?
fi

STATE="$SANDBOX/canary-state"

run env KEEL_CANARY_STATE="$STATE" bash "$canary" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "pipeline-canary.sh setup"

run env KEEL_CANARY_STATE="$STATE" bash "$canary" bogus-subcommand
check_status "unknown subcommand → exit 2" 2 "$STATUS"

run env KEEL_CANARY_STATE="$STATE" bash "$canary" check
check_status "check with no sandbox yet → exit 1" 1 "$STATUS"
check_contains "check with no sandbox yet → tells the operator to run setup" "$OUT" 'run "setup" first'

# --- demo-bypass: fully automated, no model needed -------------------------------------------------
run env KEEL_CANARY_STATE="$STATE" bash "$canary" demo-bypass
check_status "demo-bypass → exit 0 (the fabricated claim WAS denied, as it should be)" 0 "$STATUS"
check_contains "demo-bypass reports PASS" "$OUT" "PASS  demo-bypass"

# --- setup: builds the sandbox -----------------------------------------------------------------
run env KEEL_CANARY_STATE="$STATE" bash "$canary" setup
check_status "setup → exit 0" 0 "$STATUS"
check_file "setup writes a state file" "$STATE"

sandbox="$(awk -F'\t' '$1=="sandbox"{print $2}' "$STATE")"
repo="$(awk -F'\t' '$1=="repo"{print $2}' "$STATE")"
check_dir "setup's sandbox dir exists" "$sandbox"
check_dir "setup's toy repo exists" "$repo"
check_file "setup writes a settings.json" "$sandbox/settings.json"
check_file "setup writes a stub gh on PATH" "$sandbox/bin/gh"
check_contains "settings.json wires the PreToolUse gate" "$(cat "$sandbox/settings.json" 2>/dev/null)" "pre-pr-gate.sh"
check_contains "settings.json wires the SessionStart rollout-check" "$(cat "$sandbox/settings.json" 2>/dev/null)" "rollout-check"
check_contains "the toy repo is a real git repo" "$(git -C "$repo" rev-parse --is-inside-work-tree 2>&1)" "true"

# Two separate `setup` runs must not collide on the same /tmp sentinel — pre-pr-gate.sh keys purely off
# basename(toplevel), so a fixed toy-repo dir name would make every canary session share one sentinel.
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-2" bash "$canary" setup
repo2="$(awk -F'\t' '$1=="repo"{print $2}' "$SANDBOX/canary-state-2")"
check_absent "two setup runs get different toy-repo basenames (no shared /tmp sentinel)" "$(basename "$repo2")" "$(basename "$repo")"

# --- check before any run: reports the miss, non-zero exit -----------------------------------------
run env KEEL_CANARY_STATE="$STATE" bash "$canary" check
check_status "check before any run → non-zero (nothing happened yet)" 1 "$STATUS"
check_contains "check before any run → FAILs the gh-reached assertion" "$OUT" "FAIL  gh pr create never reached the stub"

# --- simulate a completed /polish run through the CLI subcommands (same calls /polish itself makes),
# then drive the gate's OWN hook mode (exactly what the real PreToolUse hook does before the harness
# lets `gh pr create` actually execute) and only then invoke the sandbox's stub `gh` — two separate
# steps, matching the real flow: the hook decides, the harness executes on ALLOW.
# write_full_receipt_review lives in lib.sh (shared with test_pre_pr_gate.sh) — expects $gate set.
gate="$REPO_ROOT/tools/pre-pr-gate.sh"
write_full_receipt_review "$repo" "low-operator-run"
# -u KEEL_IMPACT_LOG: lib.sh exports a sandbox-wide default for the whole test run, which would
# otherwise outrank the toy repo's own .keel/ marker — unset it so the event lands where `check` reads.
gate_decision="$(jq -n --arg c "gh pr create --fill" --arg d "$repo" '{tool_input:{command:$c}, cwd:$d}' | env -u KEEL_IMPACT_LOG bash "$gate")"
check_contains "the gate itself allows the simulated run" "$gate_decision" '"permissionDecision":"allow"'
"$sandbox/bin/gh" pr create --fill >/dev/null

run env KEEL_CANARY_STATE="$STATE" bash "$canary" check
check_status "check after a completed run → exit 0" 0 "$STATUS"
check_contains "check after a completed run → PASSes the gh-reached assertion" "$OUT" "PASS  gh pr create reached the stub"
check_contains "check after a completed run → PASSes the sentinel-consumed assertion" "$OUT" "PASS  no leftover receipt sentinel"
check_contains "check after a completed run → reports the receipt-pass provenance" "$OUT" "PASS  a receipt-pass event was recorded"
check_contains "check after a completed run → provenance names it self-reported" "$OUT" "review: low, operator-run (self-reported)"

# --- clean: removes the sandbox and the state file --------------------------------------------------
run env KEEL_CANARY_STATE="$STATE" bash "$canary" clean
check_status "clean → exit 0" 0 "$STATUS"
check_nofile "clean removes the state file" "$STATE"
if [ -d "$sandbox" ]; then fail "clean removes the sandbox dir" "still present: $sandbox"; else pass "clean removes the sandbox dir"; fi

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-2" bash "$canary" clean

summary
