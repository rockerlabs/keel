#!/usr/bin/env bash
# keel-check-gate.sh — the OPT-IN hard-veto half of the stop-mode floor (backlog dir #33, tier T1b).
#
# MAINTAINER / OPT-IN DEV-TOOLING — pairs with tools/keel-check.sh. A Claude Code PreToolUse(Bash) hook:
# it reads a JSON event on stdin and, when enabled, BLOCKS a `git commit` / `gh pr create` while a check
# the agent declared through keel-check.sh is still RED (a marker is present). This is the "no artifact
# below the gate" floor (PRINCIPLES.md P1): CORE.md's rail nudges, keel-check.sh interrupts on the N-th
# red, and this refuses to let a confident "done" reach a commit while that same check is failing. A
# green re-run through keel-check.sh clears the marker and the commit proceeds.
#
# OFF BY DEFAULT — enable per session with $KEEL_CHECK_VETO, so a deliberate work-in-progress commit on a
# red test is never blocked unless you asked for it. install.sh does NOT auto-register this in an
# adopter's settings.json (that adopter auto-wiring is a separate, deferred tier); a maintainer wires it
# as a PreToolUse(Bash) hook by hand. (A per-repo `.keel/stop-mode-veto` enable marker + the worktree ->
# main-checkout fallback that keel-impact.sh uses are a deferred parity item — see backlog dir #33.)
#
# Needs jq to parse the hook event (like pre-pr-gate.sh). Without it the hook can't tell a commit from any
# other Bash call, so it allows rather than blocks everything — an explicit, documented choice: this is a
# workflow floor, not the secret boundary (that's secret-guard, which needs no jq).
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fast-exit: only the artifact-producing commands are the gate's business.
case "$cmd" in
  "git commit"*|"gh pr create"*) ;;
  *) exit 0 ;;
esac

# OFF unless explicitly enabled for this session.
[ -z "${KEEL_CHECK_VETO:-}" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
repo_top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
repo_key="$(printf '%s' "$repo_top" | cksum | tr -cd '0-9')"
state_dir="${KEEL_CHECK_STATE_DIR:-${TMPDIR:-/tmp}}"
repo_dir="$state_dir/keel-check/$repo_key"

deny() {
  # Impact instrumentation (metadata only, opt-in via $KEEL_IMPACT_LOG): record the block so keel-impact
  # can auto-ingest it. Log file only — never stdout (the hook's JSON decision must stay intact).
  if [ -n "${KEEL_IMPACT_LOG:-}" ]; then
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" guard keel-check-gate blocked \
      >> "$KEEL_IMPACT_LOG" 2>/dev/null || true
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Any marker under the repo dir => a declared check is still failing => refuse the artifact. Says WHAT to
# do (make the check pass), never HOW to defeat the gate (FRAMEWORK.md "Enforcement mechanics").
if [ -d "$repo_dir" ] && [ -n "$(ls -A "$repo_dir" 2>/dev/null)" ]; then
  deny "keel-check gate: a check you declared for this repo is still failing. Re-run it green through keel-check before committing — repeated failure is a missing cause, not a missing attempt."
fi
exit 0
