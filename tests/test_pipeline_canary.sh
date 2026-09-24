#!/usr/bin/env bash
# test_pipeline_canary.sh — tools/pipeline-canary.sh (backlog dir #64 tier 3): the sandbox setup/check
# cycle and the fully-automated seeded-bypass red demo. Everything here runs the REAL gate script
# (tools/pre-pr-gate.sh) against throwaway sandboxes — no live model, no network (the stub `gh` never
# shells out), and every canary state file is redirected under this test's own $SANDBOX so a run of this
# suite never touches a real, in-progress canary session on the machine.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }
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

# --- demo-bypass: dir #478's `[ -n "$d" ] || exit 1` guard, exercised for real (dir #565) -----------
# path_farm (tests/lib.sh, the same technique tests/test_install_pre_pr_gate.sh's no-jq fixture uses)
# hides just `mktemp` from PATH so `d="$(mktemp -d)"` comes back empty — the guard's own exact failure
# mode, without needing to edit the script under test. Run from a throwaway cwd so a regression (the
# guard deleted, `d=""` falling through to `git -C "$d" init`) would be caught by checking that cwd
# stayed empty, not just by the exit code — `git -C ""` silently resolves to cwd (verified live), which
# is the dir #375/#478 class of bug this guard exists to stop.
mktemp_farm="$SANDBOX/mktemp-farm"
path_farm "$mktemp_farm" mktemp
nomktemp_cwd="$SANDBOX/nomktemp-cwd"
mkdir -p "$nomktemp_cwd"
# run_in (tests/lib.sh), not a hand-rolled `bash -c '...' _ arg1 arg2 ...` — it already does exactly
# "run a command from a throwaway cwd" (found by /simplify's own pass on this ticket).
run_in "$nomktemp_cwd" env PATH="$mktemp_farm" KEEL_CANARY_STATE="$STATE" bash "$canary" demo-bypass
check_status "demo-bypass with mktemp missing → non-zero (guard catches it, not a silent PASS)" 1 "$STATUS"
check_contains "demo-bypass with mktemp missing → names the mktemp failure" "$OUT" "mktemp -d failed"
check_nodir "demo-bypass with mktemp missing → no stray .git landed in the invocation directory" "$nomktemp_cwd/.git"

# --- demo-bypass under an ambient GIT_DIR (dir #644) — its own fixture creation (mktemp'd $d, then
# git init/config/commit against it) must not get redirected into whatever repo an inherited GIT_DIR
# names, the same class of hijack tools/lib/repo-arg-guard.sh closes for the other three consumers
# (/code-review max finding: this file had zero coverage of it despite already having the exact right
# idiom, one test block up, for a different pipeline-canary.sh guard). `decoy644` stands in for
# whatever repo an operator's already-exported GIT_DIR happens to name.
decoy644="$(new_repo)"; git -C "$decoy644" commit -q --allow-empty -m init
decoy644_gitdir="$(git -C "$decoy644" rev-parse --absolute-git-dir)"
decoy644_before="$(snapshot_tree_cksum "$decoy644/.git")"
run env GIT_DIR="$decoy644_gitdir" KEEL_CANARY_STATE="$STATE" bash "$canary" demo-bypass
check_status "demo-bypass under an ambient GIT_DIR → still exit 0 (unaffected, not redirected)" 0 "$STATUS"
check_contains "demo-bypass under an ambient GIT_DIR → still reports PASS" "$OUT" "PASS  demo-bypass"
check_block_equal "demo-bypass under an ambient GIT_DIR → the decoy repo is byte-identical before/after" \
  "$decoy644_before" "$(snapshot_tree_cksum "$decoy644/.git")"

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

# Two separate `setup` runs must not collide on the same sentinel — pre-pr-gate.sh keys off a
# basename-plus-hash-of-the-full-path (dir #481), so a fixed toy-repo dir name (even one whose full
# path would still differ per run, as mktemp's own random suffix already guarantees) would be one less
# thing standing between a bug in that hashing and two canary sessions silently sharing one sentinel.
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-2" bash "$canary" setup
check_status "a second, concurrent setup run does not collide with the first -> exit 0" 0 "$STATUS"

# dir #565: the basename-only check this replaced compared two `mktemp -d "$sandbox/repo.XXXXXX"`
# basenames, which differ by mktemp's own random suffix regardless of whether pre-pr-gate.sh's keying
# still separates them — it could not fail even if `_repo_key_from_path` (dir #481) reverted to
# basename-only hashing. Hold the basename FIXED instead and vary the containing dir, then compare the
# gate's own repo-key output (not a hand-rolled basename+hash — that would just re-test this file's own
# copy of the algorithm, not the gate's): two toy repos sharing one basename must still get distinct
# keys, or the hash half of dir #481's separation has silently stopped doing anything.
samebase_a="$SANDBOX/samebase-a/repo"
samebase_b="$SANDBOX/samebase-b/repo"
mkdir -p "$samebase_a" "$samebase_b"
git -C "$samebase_a" init -q
git -C "$samebase_b" init -q
key_a="$(bash "$REPO_ROOT/tools/pre-pr-gate.sh" repo-key "$samebase_a")"
key_b="$(bash "$REPO_ROOT/tools/pre-pr-gate.sh" repo-key "$samebase_b")"
check_ne "two same-basename toy repos still get distinct gate keys (dir #481 hash separation)" "$key_a" "$key_b"

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
# dir #398: the receipt WRITE must land under the SAME $HOME the gate's later READ resolves
# (gate_env below explicitly sets HOME="$sandbox/home", matching cmd_setup's own printed
# instructions for a real /polish session) — a plain root move exposed this: the old flat /tmp path
# was HOME-independent, so the write/read mismatch this subshell now closes was invisible before.
( export HOME="$sandbox/home"; write_full_receipt_review "$repo" "low-operator-run" )

# dir #102: with a full receipt written but the gate not yet asked to unlock, the sentinel is still
# on disk — `check`'s "still present" branch (as opposed to the "no leftover sentinel" PASS it asserts
# further below, once the hook run below has consumed it via retire_sentinel).
run env KEEL_CANARY_STATE="$STATE" env -u KEEL_IMPACT_LOG bash "$canary" check
check_contains "check with a not-yet-consumed sentinel → INFO, not PASS/FAIL" "$OUT" "INFO  a receipt sentinel is still present"

# dir #317 (was dir #290): HOME="$home" KEEL_HOME= KEEL_IMPACT_STORE= — matches how cmd_setup's printed
# instructions launch the real /polish session, so this simulated gate/ALLOW call writes its
# receipt-pass event into the canary's OWN sandboxed store, the same place `check` reads from.
# -u KEEL_IMPACT_LOG: lib.sh exports a sandbox-wide default for the whole test run, which would
# otherwise outrank that resolution — unset it so the event lands where `check` reads. (This event's
# resolution only depends on KEEL_IMPACT_LOG/KEEL_HOME/KEEL_IMPACT_STORE — the printed command's other
# blanked variables, KEEL_IMPACT_LEDGER/_EVIDENCE/KEEL_READ_TRACE_STORE, are exercised by A1/A5 below.)
gate_decision="$(gate_env "gh pr create --fill" "$repo" -u KEEL_IMPACT_LOG HOME="$sandbox/home" KEEL_HOME= KEEL_IMPACT_STORE=)"
check_contains "the gate itself allows the simulated run" "$gate_decision" '"permissionDecision":"allow"'
"$sandbox/bin/gh" pr create --fill >/dev/null

# dir #102: a trace file present (skill-trace fired at least once) → the "trace file exists" INFO
# branch, otherwise never exercised (every other fixture in this suite leaves no trace behind).
# trace_for() lives in lib.sh (shared with test_pre_pr_gate.sh) and ensures its own trace/
# subdirectory (gate_tmp_purpose_dir). dir #398: HOME="$sandbox/home" so this fabricated trace lands
# where `check` (HOME="$home" internally, same value) actually looks — the gate's trace root is
# $HOME-keyed now, unlike the old flat /tmp path.
printf '2026-01-01T00:00:00Z\tcode-review\thigh\n' > "$(HOME="$sandbox/home" trace_for "$repo")"

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
rm -f "$(HOME="$sandbox/home" trace_for "$repo")"

# --- clean: removes the sandbox and the state file --------------------------------------------------
run env KEEL_CANARY_STATE="$STATE" bash "$canary" clean
check_status "clean → exit 0" 0 "$STATUS"
check_nofile "clean removes the state file" "$STATE"
if [ -d "$sandbox" ]; then fail "clean removes the sandbox dir" "still present: $sandbox"; else pass "clean removes the sandbox dir"; fi

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-2" bash "$canary" clean

# --- A5 (dir #317) — supersedes the earlier dir #64/operator-run /code-review high fix above: `check`
# now reads via impact_isolated (S1/S2), the SAME isolation the printed session command applies
# (cmd_setup, above) — so an ambient $KEEL_IMPACT_LOG can no longer redirect either side. Reproduces
# dir #64's exact fixture (an event written outside the sandbox, then `check` invoked with that same
# path exported) to prove the behaviour is now the OPPOSITE of the old fix: `check` must resolve INSIDE
# the sandbox and never follow the decoy, even with $KEEL_IMPACT_LOG exported. -------------------------
run env KEEL_CANARY_STATE="$SANDBOX/canary-state-3" bash "$canary" setup
sandbox3="$(awk -F'\t' '$1=="sandbox"{print $2}' "$SANDBOX/canary-state-3")"
repo3="$(awk -F'\t' '$1=="repo"{print $2}' "$SANDBOX/canary-state-3")"
home3="$sandbox3/home"
decoylog="$SANDBOX/a5-decoy-impact.log"; rm -f "$decoylog"
( export HOME="$home3"; write_full_receipt_review "$repo3" "low-operator-run" )
# Derived from IMPACT_ISOLATION_VARS, like cmd_setup's own printed command — not hand-typed, so a
# future addition to that one list is exercised here too instead of silently under-isolating this call
# the way dir #290/E11's hand-typed original did.
a5_isolation_args=(HOME="$home3")
for a5_isolate_var in $IMPACT_ISOLATION_VARS; do
  a5_isolation_args+=("$a5_isolate_var=")
done
gate_env "gh pr create --fill" "$repo3" "${a5_isolation_args[@]}" >/dev/null
"$sandbox3/bin/gh" pr create --fill >/dev/null

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-3" KEEL_IMPACT_LOG="$decoylog" bash "$canary" check
check_status "A5: check with KEEL_IMPACT_LOG exported to a decoy → exit 0" 0 "$STATUS"
check_contains "A5: check still finds the receipt-pass event, isolated the same way as the session" "$OUT" "PASS  a receipt-pass event was recorded"
check_nofile "A5: nothing was ever written to the decoy KEEL_IMPACT_LOG path" "$decoylog"

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
# A5 (dir #317): the printed command blanks every IMPACT_ISOLATION_VARS variable, not just
# KEEL_HOME/KEEL_IMPACT_STORE (dir #290's narrower original — the "old l.216 pin" this replaces).
for a5_var in $IMPACT_ISOLATION_VARS; do
  check_contains "setup's printed instructions blank \$$a5_var for the real session" "$OUT" "$a5_var="
done
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
# dir #398: HOME=$home6 for the write too (see the identical dir #398 note on the first
# write_full_receipt_review call above) — the gate's own sentinel/trace root is HOME-keyed now, so
# the write and the read below must share the same HOME to agree on one path.
( export HOME="$home6"; write_full_receipt_review "$repo6" "low-operator-run" )
gate_decision6="$(gate_env "gh pr create --fill" "$repo6" -u KEEL_IMPACT_LOG HOME="$home6" KEEL_HOME= KEEL_IMPACT_STORE=)"
check_contains "the gate allows the escape-scenario simulated run" "$gate_decision6" '"permissionDecision":"allow"'
"$sandbox6/bin/gh" pr create --fill >/dev/null

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-6" KEEL_IMPACT_STORE="$escape_store" env -u KEEL_IMPACT_LOG bash "$canary" check
check_status "check after the escape-scenario run → exit 0" 0 "$STATUS"
check_contains "check finds the receipt-pass event without escaping to KEEL_IMPACT_STORE" "$OUT" "PASS  a receipt-pass event was recorded"
check_nodir "the completed run must not have written into the operator's real KEEL_IMPACT_STORE" "$escape_store/$id6"

run env KEEL_CANARY_STATE="$SANDBOX/canary-state-6" KEEL_IMPACT_STORE="$escape_store" bash "$canary" clean

summary
