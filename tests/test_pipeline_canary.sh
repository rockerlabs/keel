#!/usr/bin/env bash
# test_pipeline_canary.sh — tools/pipeline-canary.sh (backlog dir #64 tier 3): the sandbox setup/check
# cycle and the fully-automated seeded-bypass red demo. Everything here runs the REAL gate script
# (tools/pre-pr-gate.sh) against throwaway sandboxes — no live model, no network (the stub `gh` never
# shells out), and every canary state file is redirected under this test's own $SANDBOX so a run of this
# suite never touches a real, in-progress canary session on the machine.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$REPO_ROOT/tools/lib/impact-store.sh"

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
# gate_env: the same helper test_pre_pr_gate.sh/test_keel_check_gate.sh already define locally for a
# test that must FEED stdin (tests/lib.sh's own `run` redirects </dev/null, per its header comment) —
# $1 = command string, $2 = cwd, $3... = extra `env` assignments. One place builds the event JSON, so
# a change to the gate's input shape (or, dir #290, to what isolation an escape-scenario call needs)
# lands once instead of being re-typed at every call site in this file.
gate_env() {
  local json
  json="$(jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, cwd:$d}')"
  shift 2
  printf '%s' "$json" | env "$@" bash "$gate"
}
write_full_receipt_review "$repo" "low-operator-run"

# dir #102: with a full receipt written but the gate not yet asked to unlock, the sentinel is still
# on disk — `check`'s "still present" branch (as opposed to the "no leftover sentinel" PASS it asserts
# further below, once the hook run below has consumed it via retire_sentinel).
run env KEEL_CANARY_STATE="$STATE" env -u KEEL_IMPACT_LOG bash "$canary" check
check_contains "check with a not-yet-consumed sentinel → INFO, not PASS/FAIL" "$OUT" "INFO  a receipt sentinel is still present"

# dir #290: HOME="$home" KEEL_HOME= KEEL_IMPACT_STORE= — matches how cmd_setup's printed instructions
# now launch the real /polish session (fixed by this ticket), so this simulated gate/ALLOW call writes
# its receipt-pass event into the canary's OWN sandboxed store, the same place `check` (fixed below)
# now reads from. -u KEEL_IMPACT_LOG: lib.sh exports a sandbox-wide default for the whole test run,
# which would otherwise outrank that resolution — unset it so the event lands where `check` reads.
gate_decision="$(gate_env "gh pr create --fill" "$repo" -u KEEL_IMPACT_LOG HOME="$sandbox/home" KEEL_HOME= KEEL_IMPACT_STORE=)"
check_contains "the gate itself allows the simulated run" "$gate_decision" '"permissionDecision":"allow"'
"$sandbox/bin/gh" pr create --fill >/dev/null

# dir #102: a trace file present (skill-trace fired at least once) → the "trace file exists" INFO
# branch, otherwise never exercised (every other fixture in this suite leaves no trace behind).
# trace_for() lives in lib.sh (shared with test_pre_pr_gate.sh).
printf '2026-01-01T00:00:00Z\tcode-review\thigh\n' > "$(trace_for "$repo")"

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
rm -f "$(trace_for "$repo")"

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
gate_env "gh pr create --fill" "$repo3" KEEL_IMPACT_LOG="$extlog" >/dev/null
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

# --- dir #290: the sandbox must not escape when the OPERATOR's real shell has $KEEL_IMPACT_STORE or
# $KEEL_HOME exported — plausible, since those are exactly the two overrides this project's own docs
# tell an adopter to set. impact_store_root() checks both BEFORE it ever falls back to $HOME, so
# `HOME=$home` alone (the pre-fix code) does not stop either from redirecting the canary's own
# pre-created store entry, and its printed instructions, at the operator's REAL store.
escape_store="$SANDBOX/operator-real-store"
mkdir -p "$escape_store"
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-6" KEEL_IMPACT_STORE="$escape_store" bash "$canary" setup
check_contains "setup's printed instructions neutralize KEEL_HOME/KEEL_IMPACT_STORE for the real session" "$OUT" 'KEEL_HOME= KEEL_IMPACT_STORE='
sandbox6="$(awk -F'\t' '$1=="sandbox"{print $2}' "$SANDBOX/canary-state-6")"
repo6="$(awk -F'\t' '$1=="repo"{print $2}' "$SANDBOX/canary-state-6")"
home6="$sandbox6/home"
# impact_project_id (sourced above), not a hand-rolled tr '/' '-': the resolved top can differ from
# $repo6 itself (a macOS /var/folders temp path resolves through /private via git), so only the real
# function gives the id production actually uses.
id6="$(impact_project_id "$repo6")"
check_dir "setup's pre-created store entry lands inside the sandbox HOME, not the operator's KEEL_IMPACT_STORE" "$home6/.claude/.keel/impact/$id6"
check_nodir "setup's store entry must not exist under the operator's real KEEL_IMPACT_STORE" "$escape_store/$id6"

# Drive a full run the way the FIXED printed instructions actually tell the operator to (HOME=$home6,
# KEEL_HOME/KEEL_IMPACT_STORE forced empty) despite their real shell exporting $escape_store — and
# confirm both the write and the read (`check`, run below with $escape_store still ambient) land in,
# and agree on, the sandboxed location, never the operator's real store.
write_full_receipt_review "$repo6" "low-operator-run"
gate_decision6="$(gate_env "gh pr create --fill" "$repo6" -u KEEL_IMPACT_LOG HOME="$home6" KEEL_HOME= KEEL_IMPACT_STORE=)"
check_contains "the gate allows the escape-scenario simulated run" "$gate_decision6" '"permissionDecision":"allow"'
"$sandbox6/bin/gh" pr create --fill >/dev/null

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-6" KEEL_IMPACT_STORE="$escape_store" env -u KEEL_IMPACT_LOG bash "$canary" check
check_status "check after the escape-scenario run → exit 0" 0 "$STATUS"
check_contains "check finds the receipt-pass event without escaping to KEEL_IMPACT_STORE" "$OUT" "PASS  a receipt-pass event was recorded"
check_nodir "the completed run must not have written into the operator's real KEEL_IMPACT_STORE" "$escape_store/$id6"

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-6" KEEL_IMPACT_STORE="$escape_store" bash "$canary" clean

summary
