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
# content, not just presence: each polish step appends a receipt line (see below), and the gate denies
# unless every expected step id is present AND the final step's recorded SHA matches live HEAD — so a
# bare `touch` (empty file), a partial run, or a sentinel from an earlier commit all fail.
# Unlock: run /polish — it writes the receipt automatically as it completes each step.
#
# --- receipt format (dir #49) ---------------------------------------------------------------------
# The sentinel is no longer a bare SHA — it's a small per-run receipt at the same path/keying:
#   nonce\t<run-id>                     (line 1, written by `init`)
#   <run-id>\t<step-id>\t<outcome>      (one per step, written by `receipt`, in any order)
# Only lines carrying the CURRENT run's nonce count — a leftover line from an earlier run (a different
# nonce) is invisible to the completeness check, so a stale receipt can't be replayed just because it
# happens to still list the right step ids. `polish.8-unlock`'s outcome IS the HEAD SHA, so its presence
# doubles as both the last step id and the existing SHA effect-check — no separate finalize step needed.
#
# CLI subcommands (used by commands/polish.md, so a step never needs a raw `echo >>`):
#   pre-pr-gate.sh init                    mint a fresh nonce, start a new receipt (run from repo root)
#   pre-pr-gate.sh receipt <step-id> [outcome]   append a receipt line for the current run (outcome default: done)
#   pre-pr-gate.sh log <type> [detail]     append a line to the impact log (same resolution as the guard event)
#
# With no subcommand, it runs as the PreToolUse(Bash) hook: reads the tool-call JSON event on stdin,
# decides allow/deny for `gh pr create`.

set -u

EXPECTED_STEPS="polish.1-diff polish.2-simplify polish.3-tests polish.4-depth polish.5-review polish.6-retest polish.7-selfcheck polish.8-unlock"

sentinel_path() { printf '/tmp/pre-pr-gate-%s' "$(basename "$PWD")"; }

# Resolve the impact log path for a given cwd ($1): $KEEL_IMPACT_LOG, else the repo's own .keel/ marker
# (falling back to the main checkout's marker from a linked worktree — the untracked marker isn't shared,
# so a linked worktree looks at the first `git worktree list` entry, skipped when bare). One resolution
# used everywhere a guard/receipt/log event is recorded (dir #49 folded three copies into this one).
resolve_impact_log() {
  local cwd="$1" klog="${KEEL_IMPACT_LOG:-}" top main
  if [ -z "$klog" ]; then
    top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ] && [ ! -d "$top/.keel" ]; then
      main="$(git -C "$cwd" worktree list --porcelain 2>/dev/null |
        awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
      if [ -n "$main" ] && [ -d "$main/.keel" ]; then top="$main"; fi
    fi
    if [ -n "$top" ] && [ -d "$top/.keel" ]; then klog="$top/.keel/impact-events.log"; fi
  fi
  printf '%s' "$klog"
}

# Append one event line, resolving the log path for cwd $3 (default $PWD). Writes to the log file only —
# never stdout, so a hook's JSON decision stays intact; with no log path resolved, this is a silent no-op.
log_event() {
  local ty="$1" detail="${2:-}" cwd="${3:-$PWD}" log
  log="$(resolve_impact_log "$cwd")"
  [ -n "$log" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ty" pre-pr-gate "$detail" >> "$log" 2>/dev/null || true
}

case "${1:-}" in
  init)
    sentinel="$(sentinel_path)"
    nonce="$(date -u +%Y%m%dT%H%M%S)-$$-$RANDOM"
    printf 'nonce\t%s\n' "$nonce" > "$sentinel"
    printf 'pre-pr-gate: receipt started (nonce %s)\n' "$nonce"
    exit 0
    ;;
  receipt)
    step_id="${2:?pre-pr-gate: receipt <step-id> [outcome] — step id required}"
    outcome="${3:-done}"
    sentinel="$(sentinel_path)"
    if [ ! -f "$sentinel" ]; then
      printf 'pre-pr-gate: no active receipt — run "pre-pr-gate.sh init" first\n' >&2
      exit 1
    fi
    nonce="$(awk -F'\t' 'NR==1 && $1=="nonce"{print $2}' "$sentinel")"
    if [ -z "$nonce" ]; then
      printf 'pre-pr-gate: receipt file has no nonce header — run "pre-pr-gate.sh init" first\n' >&2
      exit 1
    fi
    printf '%s\t%s\t%s\n' "$nonce" "$step_id" "$outcome" >> "$sentinel"
    exit 0
    ;;
  log)
    ty="${2:?pre-pr-gate: log <type> [detail] — type required}"
    detail="${3:-}"
    log_event "$ty" "$detail" "$PWD"
    exit 0
    ;;
esac

# --- hook mode: PreToolUse(Bash) on `gh pr create` -------------------------------------------------

# Needs jq to parse the hook event. Without it the gate cannot tell `gh pr create` from any other Bash
# command, so it allows rather than block EVERY command — an explicit, documented choice: this is a
# WORKFLOW gate (a /polish reminder), not the secret boundary (that's secret-guard, which needs no jq).
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fast-exit: only care about `gh pr create`. A substring match (not just a leading-prefix match,
# S6/backlog dir #4) so a chained/prefixed invocation — `cd repo && gh pr create`, `GH_TOKEN=x gh pr
# create`, `foo; gh pr create` — still gets caught instead of silently bypassing the gate. False
# positives (e.g. an unrelated command that happens to mention the phrase) just force an unneeded
# /polish reminder; a false negative is an actual bypass, so err toward catching more. Still lexical,
# not a real command parse — e.g. `gh --repo owner/name pr create` (a global flag before the
# subcommand) has no contiguous "gh pr create" substring and would still slip through. Closing that
# needs real argv-aware parsing, disproportionate for what the header above calls a WORKFLOW gate (a
# /polish reminder), not the secret boundary — left as a known residual gap, not a promise this is exhaustive.
case "$cmd" in
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
wt=$(basename "$cwd")
sentinel="/tmp/pre-pr-gate-$wt"

deny() {
  # Impact instrumentation (metadata only, opt-in per repo): record that this guardrail fired so keel-impact
  # can auto-ingest it — deterministic, zero-token. Writes to the log file, never stdout (the hook's JSON
  # stays intact); with no log path resolved, nothing is written and the gate's behaviour is unchanged.
  log_event guard blocked "$cwd"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

if [ ! -f "$sentinel" ]; then
  log_event receipt-deny "no-run" "$cwd"
  deny "Pre-PR gate: run /polish first (simplify + inline review + tests). The gate unlocks automatically when /polish completes cleanly."
fi

# Parse the receipt: line 1 must be the nonce header; every later line is <nonce>\t<step-id>\t<outcome>.
# Only lines whose nonce matches the header count toward completeness — a leftover line from an earlier
# run (different nonce) neither counts nor is silently accepted, so it surfaces as a replay, not a pass.
result="$(awk -F'\t' -v steps="$EXPECTED_STEPS" '
  BEGIN { n = split(steps, want, " "); for (i = 1; i <= n; i++) need[want[i]] = 1 }
  NR == 1 {
    if ($1 == "nonce" && $2 != "") { nonce = $2; next }
    malformed = 1; next
  }
  NF >= 3 {
    if (nonce != "" && $1 == nonce) { got[$2] = 1; val[$2] = $3 }
    else { foreign[$2] = 1 }
  }
  END {
    if (malformed || nonce == "") { print "MALFORMED\t"; exit }
    missing = ""; replay = ""
    for (s in need) {
      if (!(s in got)) {
        missing = (missing == "" ? s : missing "," s)
        if (s in foreign) replay = (replay == "" ? s : replay "," s)
      }
    }
    if (missing == "") { print "PASS\t" val["polish.8-unlock"]; exit }
    if (replay != "") { print "REPLAY\t" missing; exit }
    print "MISSING\t" missing
  }
' "$sentinel")"

status="${result%%$'\t'*}"
detail="${result#*$'\t'}"

case "$status" in
  MALFORMED)
    rm -f "$sentinel"
    log_event receipt-deny "malformed" "$cwd"
    deny "Pre-PR gate: receipt is malformed or empty (no nonce). Run /polish again."
    ;;
  MISSING)
    rm -f "$sentinel"
    log_event receipt-deny "$detail" "$cwd"
    deny "Pre-PR gate: /polish did not complete — missing receipt for step(s): $detail. Run /polish again."
    ;;
  REPLAY)
    rm -f "$sentinel"
    log_event receipt-replay-deny "$detail" "$cwd"
    deny "Pre-PR gate: receipt for step(s) $detail carries a stale nonce (replayed from an earlier run). Run /polish again."
    ;;
  PASS)
    current_sha=$(git -C "$cwd" rev-parse HEAD 2>/dev/null)
    if [ -z "$current_sha" ] || [ "$detail" != "$current_sha" ]; then
      rm -f "$sentinel"
      log_event receipt-deny "sha-mismatch" "$cwd"
      deny "Pre-PR gate: sentinel is stale (HEAD changed since /polish ran, or a manual bypass was attempted). Run /polish again."
    fi
    rm -f "$sentinel"
    log_event receipt-pass "" "$cwd"
    exit 0
    ;;
esac

# Fail-safe: any unrecognized status denies rather than silently allowing.
rm -f "$sentinel"
deny "Pre-PR gate: could not verify the receipt. Run /polish again."
