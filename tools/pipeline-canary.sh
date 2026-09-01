#!/usr/bin/env bash
# tools/pipeline-canary.sh — operator-triggered sandbox ritual proving the /polish pipeline's artifacts
# (receipts, trace, hand-off, gate decisions) still behave correctly after a model/harness rollout
# (backlog dir #64 tier 3).
#
# Adopter-usable diagnostic (dir #68) — an advanced tool, not part of the everyday /polish flow: nothing
# wires it into a hook, and it never runs automatically. Trigger it by hand when dir #64 tier 1's
# rollout-check hook fires a drift banner, or before trusting the pipeline after any Claude Code rollout.
#
# --- TO VERIFY outcome, resolved 2026-07-27 (dir #64) ---------------------------------------------
# Whether a fully headless `claude -p` run reliably fires PreToolUse/PostToolUse/SessionStart hooks the
# same way an interactive session does. Claude Code's docs confirm: (a) `claude -p` without --bare/
# --safe-mode loads "the same context an interactive session would, including anything configured in ...
# ~/.claude" (headless-mode docs), and --bare's own description explicitly lists "skipping auto-discovery
# of hooks" as what it turns OFF, implying hooks fire by default otherwise; SessionStart/SessionEnd hook
# firing in print mode is stated explicitly. PreToolUse/PostToolUse firing specifically in -p mode is NOT
# explicitly confirmed anywhere in the docs — only inferred from the above. Given that residual gap, AND
# that dir #63's own two new hooks (skill-trace's PostToolUse/UserPromptExpansion legs) are not yet wired
# into this maintainer's own ~/.claude/settings.json (a separate manual follow-up noted in pre-pr-gate.sh's
# own dir #63 section), this script does not attempt a blind fully-automated live drive of the real
# /polish flow. It ships as the ticket's own documented fallback instead: an INTERACTIVE ritual — `setup`
# builds the sandbox and prints the exact command for the OPERATOR to run /polish inside it for real;
# `check` then script-asserts the resulting artifacts. The artifact assertions (the actual point of a
# canary, not the automation) keep their full value either way. `demo-bypass` needs no model at all — see
# below.
#
# Hard sandbox rule (memory `subagent-live-verification-risk`, felt PR #92): a prior live-verification run
# once overwrote the REAL ~/.claude/githooks-global and broke git push machine-wide. This script never
# touches the real HOME: `setup` builds a throwaway sandbox HOME and prints it explicitly in every
# instruction; setting HOME alone is also not treated as sufficient by itself (dir #24 finding: a
# user-level ~/.claude/CLAUDE.md can still leak into an "isolated" session) — the printed command also
# passes `--setting-sources project,local` to exclude the user scope, and forces $KEEL_HOME/
# $KEEL_IMPACT_STORE empty (dir #290 finding: both outrank HOME in tools/lib/impact-store.sh's own
# resolution, so either one being exported in the operator's real shell would otherwise redirect the
# canary's impact events into the operator's REAL store, keyed by the throwaway toy repo's path).
# The rule governs WRITES: a probe that only READS the machine's own configuration is exempt — see
# docs/rollout-audit.md's Layer 0 carve-out for when that read has to face the real environment
# (dir #97).
#
# Subcommands:
#   pipeline-canary.sh setup          build a fresh sandbox (toy repo, isolated HOME, stub `gh`, hooks
#                                      wired to THIS checkout's tools/pre-pr-gate.sh) and print the
#                                      operator's next command
#   pipeline-canary.sh check          script-assert the artifacts a completed sandbox run left behind
#   pipeline-canary.sh demo-bypass    fully automated, no model/operator needed: seed a fabricated step-5
#                                      claim and assert the gate still denies it — the canary's own proof
#                                      that it CAN fail (a canary that has never failed proves nothing)
#   pipeline-canary.sh clean          remove the sandbox and its state
#
# State: $KEEL_CANARY_STATE (default /tmp/pre-pr-gate-canary-state) records the sandbox path setup built,
# so `check`/`clean` find the same sandbox without the operator re-typing it. A single canary sandbox at
# a time — this is a one-operator dev ritual, not a concurrent-session mechanism.
set -u

CANARY_STATE="${KEEL_CANARY_STATE:-/tmp/pre-pr-gate-canary-state}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SELF_DIR/pre-pr-gate.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$SELF_DIR/lib/impact-store.sh"

usage() {
  cat <<'EOF'
pipeline-canary.sh — sandbox ritual for the /polish pipeline (dir #64 tier 3).

Usage:
  pipeline-canary.sh setup          build the sandbox, print the operator's next command
  pipeline-canary.sh check          assert the artifacts a completed sandbox run left behind
  pipeline-canary.sh demo-bypass    fully automated seeded-bypass red demo (no model needed)
  pipeline-canary.sh clean          remove the sandbox
  pipeline-canary.sh -h | --help
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# dir #290: the ONE place that knows what neutralizes tools/lib/impact-store.sh's isolation escape —
# $KEEL_IMPACT_STORE, then $KEEL_HOME, both checked by impact_store_root() BEFORE it ever falls back
# to $HOME. Used at every call into that lib below (cmd_setup's pre-create, cmd_check's read) so the
# two-variable knowledge is stated once, not re-derived at each site (the exact way this ticket's own
# bug happened: one call site had it, the other didn't).
_sandboxed_impact() { HOME="$1" KEEL_HOME='' KEEL_IMPACT_STORE='' "${@:2}"; }

# The authoritative repo-key resolution (worktree-aware — dir #61) lives in pre-pr-gate.sh itself;
# calling its own `repo-key` subcommand instead of re-deriving the algorithm here means this stays
# correct even if that resolution ever changes.
_repo_key_of() { bash "$GATE" repo-key "$1"; }
# dir #80: a caller (cmd_check, below) needing BOTH the repo-only and the (repo,branch) receipt key
# for the same dir uses this instead of calling the gate's `repo-key`/`receipt-key` subcommands
# separately — each would fork this whole script AND independently re-run `git worktree list
# --porcelain`/`git branch --show-current`; `keys` returns both from one such run. Sets
# $KEYS_REPO/$KEYS_RECEIPT in the caller's shell. Unlike `repo-key` (which never fails), `keys` CAN
# fail — the gate hard-errors on a detached HEAD (dir #80's writer-side discipline) — so this checks
# the exit status explicitly and returns non-zero itself rather than silently leaving $KEYS_REPO/
# $KEYS_RECEIPT empty (found by this ticket's own /code-review high pass: an unchecked failure here
# used to make `cmd_check` compare against the bogus path `/tmp/pre-pr-gate-`, which never exists, so
# it reported a false "PASS  no leftover receipt sentinel" instead of surfacing the real error).
_keys_of() {
  local out
  out="$(bash "$GATE" keys "$1")" || return 1
  IFS=$'\t' read -r KEYS_REPO KEYS_RECEIPT <<< "$out"
}

cmd_setup() {
  [ -f "$GATE" ] || { printf 'pipeline-canary: %s not found — run from a keel checkout\n' "$GATE" >&2; exit 1; }
  command -v git >/dev/null 2>&1 || { printf 'pipeline-canary: git is required\n' >&2; exit 1; }

  sandbox="$(mktemp -d)"
  home="$sandbox/home"; mkdir -p "$home"
  bin="$sandbox/bin"; mkdir -p "$bin"
  ghcalls="$sandbox/gh-calls.log"
  # A unique basename (not the fixed literal "repo") — pre-pr-gate.sh keys its /tmp sentinel/trace/
  # hand-off files off basename(toplevel), so a fixed name would collide across canary runs (and with
  # any real repo that happens to be named "repo").
  repo="$(mktemp -d "$sandbox/repo.XXXXXX")"

  # Stub `gh`: records every invocation instead of touching the network. `pr create` "succeeds" with a
  # fake URL so a real /polish run completes its final step; anything else is a harmless no-op success.
  cat > "$bin/gh" <<GHEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$ghcalls"
case "\$*" in
  *"pr create"*) printf 'https://example.invalid/keel-canary/pull/1\n' ;;
esac
exit 0
GHEOF
  chmod +x "$bin/gh"
  : > "$ghcalls"

  git init -q "$repo"
  HOME="$home" git -C "$repo" config user.email canary@keel.invalid
  HOME="$home" git -C "$repo" config user.name "Keel Canary"
  printf 'canary toy project\n' > "$repo/README.md"
  # dir #251: impact events now live in an EXTERNAL store, $KEEL_HOME/.keel/impact/<project-id>/, never
  # inside the repo itself. The real /polish session below runs sandboxed (see _sandboxed_impact, dir
  # #290) so its own store resolution lands inside this sandbox on its own — pre-create that store
  # entry (mirrors keel-impact.sh's own `enable`) so a real run's impact events land somewhere `check`
  # can read without extra env. `cmd_check` recomputes the identical path (search "impact_store_dir").
  mkdir -p "$(_sandboxed_impact "$home" impact_store_dir "$repo")"
  git -C "$repo" add README.md
  HOME="$home" git -C "$repo" commit -q -m "init"

  # A trivial, deliberately reviewable toy change — the "diff" a real /polish pass would size/simplify.
  printf 'def add(a, b):\n    return a + b\n' > "$repo/toy.py"
  git -C "$repo" add toy.py

  key="$(_repo_key_of "$repo")"
  settings="$sandbox/settings.json"
  cat > "$settings" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash $GATE" }] }
    ],
    "PostToolUse": [
      { "matcher": "Skill", "hooks": [{ "type": "command", "command": "bash $GATE skill-trace" }] }
    ],
    "UserPromptExpansion": [
      { "matcher": "code-review", "hooks": [{ "type": "command", "command": "bash $GATE skill-trace" }] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "bash $GATE rollout-check" }] }
    ],
    "SubagentStop": [
      { "matcher": "general-purpose", "hooks": [{ "type": "command", "command": "bash $GATE skill-trace" }] }
    ]
  }
}
EOF

  {
    printf 'sandbox\t%s\n' "$sandbox"
    printf 'repo\t%s\n' "$repo"
    printf 'key\t%s\n' "$key"
  } > "$CANARY_STATE"

  cat <<EOF
pipeline-canary: sandbox ready at $sandbox

Run the real /polish scenario yourself, isolated from your real HOME/hooks:

  cd $repo
  HOME=$home KEEL_HOME= KEEL_IMPACT_STORE= PATH=$bin:\$PATH claude --settings $settings --setting-sources project,local

(dir #290: KEEL_HOME= and KEEL_IMPACT_STORE= are not decorative — if either is exported in your real
shell, HOME=$home alone would NOT stop the session's impact events from landing in your real store.)

Then, inside that session: make a small edit (toy.py is already staged as a starter diff), run /polish
for real through to \`gh pr create\` (the stubbed gh above accepts it without touching the network), and
exit. Come back here and run:

  $0 check

to script-assert what the run actually left behind.
EOF
}

cmd_check() {
  [ -f "$CANARY_STATE" ] || { printf 'pipeline-canary: no sandbox — run "setup" first\n' >&2; exit 1; }
  sandbox="$(awk -F'\t' '$1=="sandbox"{print $2}' "$CANARY_STATE")"
  repo="$(awk -F'\t' '$1=="repo"{print $2}' "$CANARY_STATE")"
  [ -d "$repo" ] || { printf 'pipeline-canary: sandbox repo missing (%s) — run "setup" again\n' "$repo" >&2; exit 1; }

  fail=0
  ghcalls="$sandbox/gh-calls.log"
  if [ -f "$ghcalls" ] && grep -q 'pr create' "$ghcalls" 2>/dev/null; then
    printf 'PASS  gh pr create reached the stub — the gate ALLOWED it (receipts complete, review outcome matched depth, trace check satisfied)\n'
  else
    printf 'FAIL  gh pr create never reached the stub — either /polish was not run to completion, or the gate denied it (re-run inside the sandbox session and check its transcript)\n'
    fail=1
  fi

  if ! _keys_of "$repo"; then
    printf 'FAIL  could not resolve the sandbox repo'"'"'s keys (the gate hard-errors on a detached HEAD — check the sandbox repo has a branch checked out)\n'
    fail=1
    key=""; receipt_key=""
  else
    key="$KEYS_REPO"; receipt_key="$KEYS_RECEIPT"
  fi
  sentinel="/tmp/pre-pr-gate-$receipt_key"
  if [ -z "$receipt_key" ]; then
    : # already reported above; skip the sentinel/trace checks below, nothing meaningful to compare
  elif [ -f "$sentinel" ]; then
    printf 'INFO  a receipt sentinel is still present — the gate has not yet been asked to unlock (run gh pr create inside the sandbox session), or the last run was denied\n'
  else
    printf 'PASS  no leftover receipt sentinel — consistent with a consumed, successful pass\n'
  fi

  # resolve_impact_log() in pre-pr-gate.sh prefers $KEEL_IMPACT_LOG over the repo's own store entry —
  # match that precedence here (via _sandboxed_impact, dir #290, which leaves $KEEL_IMPACT_LOG alone
  # on purpose), or an operator with that env var set (plausible if they use it for their real repos,
  # and it's inherited into the sandboxed `claude --settings ...` session) would see a fully successful
  # canary run misreported as "no receipt-pass event recorded" (found in the operator-run /code-review
  # high pass on this ticket). dir #251: the store entry itself lives at
  # $home/.claude/.keel/impact/<project-id>/ — `home` is deterministic from `sandbox` (cmd_setup always
  # sets it to "$sandbox/home"), so it needs no CANARY_STATE field of its own.
  home="$sandbox/home"
  ilog="$(_sandboxed_impact "$home" impact_log_path "$repo")"
  if [ -f "$ilog" ] && grep -q 'receipt-pass' "$ilog" 2>/dev/null; then
    printf 'PASS  a receipt-pass event was recorded: %s\n' "$(grep 'receipt-pass' "$ilog" | tail -n1)"
  else
    printf 'INFO  no receipt-pass event recorded yet in %s\n' "$ilog"
  fi

  trace="/tmp/pre-pr-gate-trace-$key"
  if [ -f "$trace" ]; then
    printf 'INFO  a code-review trace file exists (skill-trace fired at least once): %s\n' "$(tail -n1 "$trace")"
  else
    printf 'INFO  no trace file — either no in-session /code-review ran, or the hand-off/-operator-run path was used (expected, not a failure)\n'
  fi

  exit "$fail"
}

cmd_demo_bypass() {
  # Fully automated, no live model needed: seeds a receipt that BARE-claims a real in-session review
  # (no -operator-run/-waived suffix) with NO matching trace file, then asserts the gate still denies it.
  # This is the canary's own proof that it can fail — a canary that has never failed proves nothing.
  d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email canary@keel.invalid
  git -C "$d" config user.name "Keel Canary"
  git -C "$d" commit -q --allow-empty -m init

  ( cd "$d" && bash "$GATE" init
    bash "$GATE" receipt polish.1-diff
    bash "$GATE" receipt polish.2-simplify
    # dir #96: sha-bound like steps 6 and 8 — this receipt must be valid in every respect EXCEPT the
    # one thing under test (the fabricated review claim with no trace to back it). A bare `done` here
    # would make the gate deny for an unbound test run instead, i.e. the canary would pass for the
    # wrong reason and stop probing what it exists to probe.
    bash "$GATE" receipt polish.3-tests "$(git rev-parse HEAD)"
    bash "$GATE" receipt polish.4-depth "high:fabricated"
    bash "$GATE" receipt polish.5-review high
    bash "$GATE" receipt polish.6-retest "skipped:no-file-changes"
    bash "$GATE" receipt polish.7-selfcheck "skipped:no-doctor"
    bash "$GATE" receipt polish.8-unlock "$(git rev-parse HEAD)"
  ) >/dev/null 2>&1
  rm -f "/tmp/pre-pr-gate-trace-$(_repo_key_of "$d")"   # make certain no trace exists to (correctly) vouch for this

  out="$(jq -n --arg c "gh pr create --fill" --arg d "$d" '{tool_input:{command:$c}, cwd:$d}' 2>/dev/null | bash "$GATE" 2>&1)"
  status=$?

  # `<<<` here-strings, not `printf | grep -q` pipes: this file has no `pipefail` today, so the SIGPIPE
  # race dir #280 fixes elsewhere can't flip these two conditions yet — but the fix is free, and the
  # rest of this repo's tools/*.sh files do set pipefail, so leaving the pipe form here is one stray
  # `set -o pipefail` away from reintroducing it.
  if [ "$status" -eq 0 ] && grep -q '"permissionDecision":"deny"' <<< "$out" && grep -q 'no trace matching' <<< "$out"; then
    printf 'PASS  demo-bypass: a fabricated in-session review claim (no matching trace) was correctly DENIED\n'
    ec=0
  else
    printf 'FAIL  demo-bypass: the fabricated claim was NOT denied — the gate is not doing its job, fix before trusting any other canary result\n'
    printf '      gate output: %s\n' "$out"
    ec=1
  fi
  rm -rf "$d"
  exit "$ec"
}

cmd_clean() {
  if [ -f "$CANARY_STATE" ]; then
    sandbox="$(awk -F'\t' '$1=="sandbox"{print $2}' "$CANARY_STATE")"
    [ -n "$sandbox" ] && [ -d "$sandbox" ] && rm -rf "$sandbox"
    rm -f "$CANARY_STATE"
    printf 'pipeline-canary: sandbox removed\n'
  else
    printf 'pipeline-canary: no sandbox to remove\n'
  fi
}

case "${1:-}" in
  setup)        cmd_setup ;;
  check)        cmd_check ;;
  demo-bypass)  cmd_demo_bypass ;;
  clean)        cmd_clean ;;
  *) usage >&2; exit 2 ;;
esac
