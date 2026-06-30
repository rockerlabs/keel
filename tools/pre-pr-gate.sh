#!/usr/bin/env bash
# Pre-PR gate — the enforcement half of the /polish → PR flow.
#
# MAINTAINER DEV-TOOLING — pairs with commands/polish.md. This is a Claude-Code-specific pre-PR workflow
# gate for the maintainer's own use; install.sh deliberately does NOT ship it (or /polish) to adopters, so
# nobody gets a half-wired command. It lives here for the maintainer + downstream consumers. (Intentional —
# a future audit should read this as scoped, not as a half-shipped feature.)
#
# Wire it as a Claude Code PreToolUse(Bash) hook: it intercepts `gh pr create` and requires /polish
# (simplify + inline review + tests) to have run on the current HEAD. The bypass path is closed by
# content, not just presence: /polish writes the HEAD SHA to the sentinel, and the gate re-checks it
# against the live HEAD — so a bare `touch` (empty file) or a sentinel from an earlier commit both fail.
# Unlock: run /polish — it writes the sentinel automatically when it completes cleanly.

# Needs jq to parse the hook event. Without it the gate cannot tell `gh pr create` from any other Bash
# command, so it allows rather than block EVERY command — an explicit, documented choice: this is a
# WORKFLOW gate (a /polish reminder), not the secret boundary (that's secret-guard, which needs no jq).
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fast-exit: only care about `gh pr create`.
case "$cmd" in
  "gh pr create"*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
wt=$(basename "$cwd")
sentinel="/tmp/pre-pr-gate-$wt"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

if [ ! -f "$sentinel" ]; then
  deny "Pre-PR gate: run /polish first (simplify + inline review + tests). The gate unlocks automatically when /polish completes cleanly."
fi

# Content check: the sentinel must hold the current HEAD SHA. A bare touch (empty) or a stale SHA fails.
current_sha=$(git -C "$cwd" rev-parse HEAD 2>/dev/null)
sentinel_sha=$(tr -d '[:space:]' < "$sentinel" 2>/dev/null)

if [ -z "$current_sha" ] || [ "$sentinel_sha" != "$current_sha" ]; then
  rm -f "$sentinel"
  deny "Pre-PR gate: sentinel is stale (HEAD changed since /polish ran, or a manual bypass was attempted). Run /polish again."
fi

rm -f "$sentinel"
exit 0
