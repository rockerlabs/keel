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
check_contains "check before any run → no receipt-pass event yet (dir #102)" "$OUT" "INFO  no receipt-pass event recorded yet"
check_contains "check before any run → no trace file yet (dir #102)" "$OUT" "INFO  no trace file"

# --- simulate a completed /polish run through the CLI subcommands (same calls /polish itself makes),
# then drive the gate's OWN hook mode (exactly what the real PreToolUse hook does before the harness
# lets `gh pr create` actually execute) and only then invoke the sandbox's stub `gh` — two separate
# steps, matching the real flow: the hook decides, the harness executes on ALLOW.
# write_full_receipt_review lives in lib.sh (shared with test_pre_pr_gate.sh) — expects $gate set.
gate="$REPO_ROOT/tools/pre-pr-gate.sh"
write_full_receipt_review "$repo" "low-operator-run"

# dir #102: with a full receipt written but the gate not yet asked to unlock, the sentinel is still
# on disk — `check`'s "still present" branch (as opposed to the "no leftover sentinel" PASS it asserts
# further below, once the hook run below has consumed it via retire_sentinel).
run env KEEL_CANARY_STATE="$STATE" env -u KEEL_IMPACT_LOG bash "$canary" check
check_contains "check with a not-yet-consumed sentinel → INFO, not PASS/FAIL" "$OUT" "INFO  a receipt sentinel is still present"

# -u KEEL_IMPACT_LOG: lib.sh exports a sandbox-wide default for the whole test run, which would
# otherwise outrank the toy repo's own .keel/ marker — unset it so the event lands where `check` reads.
gate_decision="$(jq -n --arg c "gh pr create --fill" --arg d "$repo" '{tool_input:{command:$c}, cwd:$d}' | env -u KEEL_IMPACT_LOG bash "$gate")"
check_contains "the gate itself allows the simulated run" "$gate_decision" '"permissionDecision":"allow"'
"$sandbox/bin/gh" pr create --fill >/dev/null

# dir #102: a trace file present (skill-trace fired at least once) → the "trace file exists" INFO
# branch, otherwise never exercised (every other fixture in this suite leaves no trace behind).
_repo_key_for_check="$(bash "$gate" repo-key "$repo")"
printf '2026-01-01T00:00:00Z\tcode-review\thigh\n' > "/tmp/pre-pr-gate-trace-$_repo_key_for_check"

# -u KEEL_IMPACT_LOG here too: cmd_check now follows the same $KEEL_IMPACT_LOG-outranks-.keel/-marker
# precedence as resolve_impact_log() (the fix under test further below) — since the event above was
# written with that env var unset (landing in the repo's own .keel/ marker), `check` must read it the
# same way, or it would look at lib.sh's ambient sandbox-wide default instead and miss it.
run env KEEL_CANARY_STATE="$STATE" env -u KEEL_IMPACT_LOG bash "$canary" check
check_status "check after a completed run → exit 0" 0 "$STATUS"
check_contains "check after a completed run → PASSes the gh-reached assertion" "$OUT" "PASS  gh pr create reached the stub"
check_contains "check after a completed run → PASSes the sentinel-consumed assertion" "$OUT" "PASS  no leftover receipt sentinel"
check_contains "check after a completed run → reports the receipt-pass provenance" "$OUT" "PASS  a receipt-pass event was recorded"
check_contains "check after a completed run → provenance names it self-reported" "$OUT" "review: low, operator-run (self-reported)"
check_contains "check after a completed run → reports the trace file (dir #102)" "$OUT" "INFO  a code-review trace file exists"
rm -f "/tmp/pre-pr-gate-trace-$_repo_key_for_check"

# --- clean: removes the sandbox and the state file --------------------------------------------------
run env KEEL_CANARY_STATE="$STATE" bash "$canary" clean
check_status "clean → exit 0" 0 "$STATUS"
check_nofile "clean removes the state file" "$STATE"
if [ -d "$sandbox" ]; then fail "clean removes the sandbox dir" "still present: $sandbox"; else pass "clean removes the sandbox dir"; fi

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-2" bash "$canary" clean

# --- dir #64/operator-run /code-review high fix: `check` must respect $KEEL_IMPACT_LOG precedence,
# same as pre-pr-gate.sh's own resolve_impact_log() — an operator with that env var set (plausible for
# their real repos) would otherwise see a fully successful run misreported as "no event recorded". ---
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-3" bash "$canary" setup
sandbox3="$(awk -F'\t' '$1=="sandbox"{print $2}' "$SANDBOX/canary-state-3")"
repo3="$(awk -F'\t' '$1=="repo"{print $2}' "$SANDBOX/canary-state-3")"
extlog="$SANDBOX/external-impact.log"; rm -f "$extlog"
write_full_receipt_review "$repo3" "low-operator-run"
jq -n --arg c "gh pr create --fill" --arg d "$repo3" '{tool_input:{command:$c}, cwd:$d}' |
  KEEL_IMPACT_LOG="$extlog" bash "$gate" >/dev/null
"$sandbox3/bin/gh" pr create --fill >/dev/null

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-3" KEEL_IMPACT_LOG="$extlog" bash "$canary" check
check_status "check with KEEL_IMPACT_LOG set → exit 0" 0 "$STATUS"
check_contains "check follows KEEL_IMPACT_LOG precedence, finds the event in the external file" "$OUT" "PASS  a receipt-pass event was recorded"
check_nofile "the repo's own .keel/ marker never got the event (env var outranked it, as production does)" "$repo3/.keel/impact-events.log"

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-3" bash "$canary" clean

# --- dir #102: cmd_check's "sandbox repo missing" branch — the state file survives but the repo dir
# it points at was removed out from under it (a stale canary-state from an earlier, since-wiped sandbox).
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-4" bash "$canary" setup
sandbox4="$(awk -F'\t' '$1=="sandbox"{print $2}' "$SANDBOX/canary-state-4")"
repo4="$(awk -F'\t' '$1=="repo"{print $2}' "$SANDBOX/canary-state-4")"
rm -rf "$repo4"
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-4" bash "$canary" check
check_status "check with the sandbox repo dir gone → exit 1" 1 "$STATUS"
check_contains "check names the missing repo and points at setup again" "$OUT" 'sandbox repo missing'
rm -rf "$sandbox4" "$SANDBOX/canary-state-4"

# --- dir #102: _keys_of's own failure path (its own /code-review high finding: an unchecked failure
# here used to leave $receipt_key empty and report a false PASS instead of surfacing the real error).
# Reproduced the same way the gate itself hard-errors: a detached HEAD, so `bash "$GATE" keys` fails.
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-5" bash "$canary" setup
repo5="$(awk -F'\t' '$1=="repo"{print $2}' "$SANDBOX/canary-state-5")"
git -C "$repo5" checkout -q --detach HEAD
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-5" bash "$canary" check
check_status "check against a detached-HEAD sandbox repo → exit 1" 1 "$STATUS"
check_contains "check surfaces the _keys_of failure, not a false PASS" "$OUT" "FAIL  could not resolve the sandbox repo's keys"
check_absent "a false PASS never slips through for the unresolved sentinel/trace checks" "$OUT" "PASS  no leftover receipt sentinel"
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-5" bash "$canary" clean

# --- dir #102: cmd_clean's "no sandbox to remove" branch — no state file at all (never set up, or
# already cleaned) is a normal, harmless call, not an error.
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-never-existed" bash "$canary" clean
check_status "clean with no state file → exit 0" 0 "$STATUS"
check_contains "clean reports nothing to remove" "$OUT" "no sandbox to remove"

summary
