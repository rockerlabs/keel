#!/usr/bin/env bash
# test_pre_pr_gate.sh — the pre-PR gate's allow/deny decision and its bypass-prevention logic.
#
# tools/pre-pr-gate.sh is a Claude Code PreToolUse(Bash) hook: it reads a JSON event on stdin and emits
# a JSON allow/deny decision (always exit 0; an empty stdout = allow, a "permissionDecision":"deny"
# payload = block). It is meant to be unbypassable by a bare `touch` — the sentinel must carry the live
# HEAD SHA — so the deny paths are security-adjacent and were entirely untested.
#
# The gate parses its input with jq, so these tests need jq. The busybox/Alpine CI job installs only
# bash+git; there, skip cleanly. Without jq the gate now exits early by an EXPLICIT, documented choice
# (`command -v jq || exit 0`) — it can't tell `gh pr create` from any other Bash call, so it allows rather
# than block everything; it's a workflow reminder, not the secret boundary (that's secret-guard, no jq).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

gate="$REPO_ROOT/tools/pre-pr-gate.sh"
check_file "pre-pr-gate.sh exists" "$gate"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — pre-pr-gate tests skipped (gate requires jq to parse its event)"
  summary; exit $?
fi

# A git repo with one commit; prints its path.
mkrepo() {
  local d; d="$(new_repo)"
  git -C "$d" commit --allow-empty -qm init
  printf '%s' "$d"
}

sentinel_for() { printf '/tmp/pre-pr-gate-%s' "$(basename "$1")"; }

# Drive the gate: $1 = command string, $2 = cwd. Captures OUT (stdout+stderr) and STATUS.
gate() {
  local json
  json="$(jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, cwd:$d}')"
  OUT="$(printf '%s' "$json" | bash "$gate" 2>&1)"
  STATUS=$?
}

# 1. A command that is NOT `gh pr create` is none of the gate's business → allow (empty out, exit 0).
d="$(mkrepo)"
gate "ls -la" "$d"
check_status "non-target command → exit 0" 0 "$STATUS"
check_absent "non-target command is allowed (no deny payload)" "$OUT" "deny"
rm -f "$(sentinel_for "$d")"

# 2. `gh pr create` with NO sentinel → deny, telling the user to run /polish.
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")"          # ensure no stale sentinel from a prior run
gate "gh pr create --fill" "$d"
check_status "no sentinel → exit 0 (hook always exits 0)" 0 "$STATUS"
check_contains "no sentinel → deny decision" "$OUT" '"permissionDecision":"deny"'
check_contains "no sentinel → tells the user to run /polish" "$OUT" "run /polish first"

# 3. THE bypass case: a bare `touch` (empty sentinel) must NOT unlock the gate — empty != HEAD SHA.
d="$(mkrepo)"
: > "$(sentinel_for "$d")"            # the `touch` bypass attempt
gate "gh pr create --fill" "$d"
check_contains "empty sentinel (bare touch) → still denied" "$OUT" '"permissionDecision":"deny"'
check_contains "empty sentinel → reported as stale/bypass" "$OUT" "stale"
check_nofile "a rejected sentinel is removed" "$(sentinel_for "$d")"

# 4. A sentinel holding a STALE SHA (an earlier commit) → deny; the live HEAD has moved on.
d="$(mkrepo)"
old="$(git -C "$d" rev-parse HEAD)"
git -C "$d" commit --allow-empty -qm second      # HEAD advances past $old
printf '%s' "$old" > "$(sentinel_for "$d")"
gate "gh pr create --fill" "$d"
check_contains "stale-SHA sentinel → denied" "$OUT" '"permissionDecision":"deny"'
check_nofile "stale sentinel is removed" "$(sentinel_for "$d")"

# 5. A sentinel holding the CURRENT HEAD SHA (what /polish writes) → allow, and consume the sentinel.
d="$(mkrepo)"
git -C "$d" rev-parse HEAD > "$(sentinel_for "$d")"
gate "gh pr create --fill" "$d"
check_status "matching sentinel → exit 0" 0 "$STATUS"
check_absent "matching sentinel → allowed (no deny payload)" "$OUT" "deny"
check_nofile "the sentinel is consumed (one-shot, removed after a pass)" "$(sentinel_for "$d")"

# 6. Edge: a matching-looking request whose cwd is not a git repo → HEAD SHA is empty → deny (fail safe).
d="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
printf 'whatever' > "$(sentinel_for "$d")"
gate "gh pr create --fill" "$d"
check_contains "non-git cwd → denied, never silently allowed" "$OUT" '"permissionDecision":"deny"'
rm -f "$(sentinel_for "$d")"

summary
