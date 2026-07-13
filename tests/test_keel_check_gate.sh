#!/usr/bin/env bash
# test_keel_check_gate.sh — the opt-in hard-veto hook (backlog dir #33, tier T1b). tools/keel-check-gate.sh
# is a Claude Code PreToolUse(Bash) hook: it reads a JSON event on stdin and emits an allow/deny decision
# (always exit 0; empty stdout = allow, a "permissionDecision":"deny" payload = block). It blocks a
# `git commit` / `gh pr create` ONLY when (a) enabled via $KEEL_CHECK_VETO and (b) keel-check.sh has left a
# red marker for the repo. We drive it end-to-end with the real shim so the marker is produced/cleared the
# way it is in practice, not hand-faked.
#
# The gate parses its input with jq; the busybox/Alpine CI job ships without jq, so skip cleanly there.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

CHECK="$REPO_ROOT/tools/keel-check.sh"
GATE="$REPO_ROOT/tools/keel-check-gate.sh"
check_file "keel-check-gate.sh exists" "$GATE"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — keel-check-gate tests skipped (gate requires jq to parse its event)"
  summary; exit $?
fi

# Shared state dir so the shim (marker writer) and the gate (marker reader) agree on paths.
export KEEL_CHECK_STATE_DIR; KEEL_CHECK_STATE_DIR="$(mktemp -d "$SANDBOX/kcgate.XXXXXX")"

# Drive the gate: $1=command, $2=cwd, $3=veto ("1" to enable). KEEL_CHECK_VETO is set only as a prefix on
# the external `bash` (never on a shell function — that would leak into later scenarios).
gate() {
  local json; json="$(jq -n --arg c "$1" --arg w "$2" '{tool_input:{command:$c}, cwd:$w}')"
  if [ "${3:-}" = "1" ]; then
    OUT="$(printf '%s' "$json" | KEEL_CHECK_VETO=1 bash "$GATE" 2>&1)"; STATUS=$?
  else
    OUT="$(printf '%s' "$json" | env -u KEEL_CHECK_VETO bash "$GATE" 2>&1)"; STATUS=$?
  fi
}

d="$(new_repo)"; git -C "$d" commit --allow-empty -qm init
flag="$SANDBOX/gate-flag"; rm -f "$flag"
CHK="test -f $flag"                       # a check we can flip: red while $flag is absent

# Make the repo's declared check RED (marker present).
run_in "$d" "$CHECK" "$CHK" >/dev/null 2>&1

# 1. Veto OFF (default) → a red check does NOT block a commit (WIP stays free).
gate "git commit -m wip" "$d" ""
check_status "veto off → hook exits 0" 0 "$STATUS"
check_absent "veto off by default → commit allowed despite a red check" "$OUT" "deny"

# 2. Veto ON + red check → commit is denied.
gate "git commit -m done" "$d" 1
check_status "deny path still exits 0 (hook always exits 0)" 0 "$STATUS"
check_contains "veto on + red check → deny decision" "$OUT" '"permissionDecision":"deny"'
check_contains "deny explains the check is still failing" "$OUT" "still failing"
# The message tells the agent what to do, never how to defeat the gate.
check_absent "deny names no bypass (env/marker) syntax" "$OUT" "KEEL_CHECK_VETO"

# 3. A non-artifact command is none of the gate's business → allowed even with veto on + red check.
gate "ls -la" "$d" 1
check_status "non-target command → exit 0" 0 "$STATUS"
check_absent "non-target command is allowed (no deny payload)" "$OUT" "deny"

# 4. gh pr create is also gated.
gate "gh pr create --fill" "$d" 1
check_contains "gh pr create + red check → denied" "$OUT" '"permissionDecision":"deny"'

# 5. A green re-run of the SAME check clears the marker → commit allowed.
: > "$flag"                                # flip the check green
run_in "$d" "$CHECK" "$CHK" >/dev/null 2>&1
gate "git commit -m done" "$d" 1
check_status "cleared check → exit 0" 0 "$STATUS"
check_absent "green check → commit allowed" "$OUT" "deny"

# 6. Veto on but NO check was ever declared (no marker) → allowed (the floor doesn't arm without a check).
d2="$(new_repo)"; git -C "$d2" commit --allow-empty -qm init
gate "git commit -m x" "$d2" 1
check_absent "no declared check → nothing to veto → allowed" "$OUT" "deny"

# 7. Impact instrumentation: a deny records ONE metadata-only guard event, on the log file only.
rm -f "$flag"; run_in "$d" "$CHECK" "$CHK" >/dev/null 2>&1     # red again
imp="$SANDBOX/gate-events.log"; : > "$imp"
json="$(jq -n --arg c "git commit -m done" --arg w "$d" '{tool_input:{command:$c}, cwd:$w}')"
out="$(printf '%s' "$json" | KEEL_CHECK_VETO=1 KEEL_IMPACT_LOG="$imp" bash "$GATE" 2>/dev/null)"
check_contains "deny still emits the deny payload on stdout" "$out" '"permissionDecision":"deny"'
check_absent "stdout is not polluted by the event line" "$out" "keel-check-gate	blocked"
check_contains "deny records a guard event when opted in" "$(cat "$imp" 2>/dev/null)" "	guard	keel-check-gate	blocked"

summary
