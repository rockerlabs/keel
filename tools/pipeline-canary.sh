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
# passes `--setting-sources project,local` to exclude the user scope, and blanks every
# tools/lib/impact-store.sh IMPACT_ISOLATION_VARS variable (dir #290 found the first two of these,
# KEEL_HOME/KEEL_IMPACT_STORE, outrank HOME in that file's own resolution; dir #317 generalized the fix
# to the whole list after E11 found KEEL_IMPACT_LOG was still leaking through dir #290's narrower
# version) — so any one of them being exported in the operator's real shell would otherwise redirect
# part of the canary's own writes into the operator's REAL store, keyed by the throwaway toy repo's path.
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
# State: $KEEL_CANARY_STATE (default $HOME/.keel/tmp/pre-pr-gate/canary-state, dir #398/#399/#637 —
# was /tmp/pre-pr-gate-canary-state) records the sandbox path setup built, so `check`/`clean` find the
# same sandbox without the operator re-typing it. A single canary sandbox at a time — this is a
# one-operator dev ritual, not a concurrent-session mechanism.
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SELF_DIR/pre-pr-gate.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$SELF_DIR/lib/impact-store.sh"
# shellcheck source=tools/lib/gate-paths.sh
. "$SELF_DIR/lib/gate-paths.sh"
# dir #644: sourcing this unsets an inherited GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE
# before this script's own fixture-creation git calls (setup's `git init`/`git -C "$repo"` …) can be
# redirected by them — see the lib's own header for the mechanism this closes. Explicitly guarded,
# unlike the two sibling `.` lines above: this script runs `set -u` only (no `-e`, same reasoning the
# mktemp guard below states for itself), so a failure here would otherwise let execution continue with
# the vars still exported, reopening dir #644 with NO later symptom anywhere (unlike impact-store.sh/
# gate-paths.sh, whose functions this script actually CALLS, so a failed source of either of those
# still fails loudly later at the call site; nothing here ever calls a function FROM repo-arg-guard.sh
# in this file, only its source-time side effect). The check is on the RESULT (all four vars actually
# gone), not merely on `.`'s own exit status: a `.` that "succeeds" (exit 0) but reads a truncated or
# otherwise malformed copy of the file — one that parses fine but never reaches its own `unset` line —
# would leave `|| { ...; exit 1; }` on the source line alone none the wiser (verified live,
# /code-review max: a 0-byte repo-arg-guard.sh sourced with exit 0 and no error). If none of the four
# were exported to begin with, this check trivially passes either way — correctly, since there is then
# nothing for a failed unset to have left behind, and nothing dir #644 protects against in that case.
# shellcheck source=tools/lib/repo-arg-guard.sh
. "$SELF_DIR/lib/repo-arg-guard.sh"
if [ -n "${GIT_DIR:-}${GIT_COMMON_DIR:-}${GIT_WORK_TREE:-}${GIT_INDEX_FILE:-}" ]; then
  echo "pipeline-canary: lib/repo-arg-guard.sh sourced but GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE are not all unset (dir #644's guard did not take effect — a missing, unreadable, or corrupted lib/repo-arg-guard.sh?) — refusing to continue" >&2
  exit 1
fi

# This runs before the -h/--help and subcommand dispatch below, so even `pipeline-canary.sh -h` or
# `... clean` now pays the cost of resolving $HOME — the same trade-off tools/pre-pr-gate.sh's own
# top-level guard makes and documents (accepted there since an unset $HOME is a rare, exceptional
# shell state); this file is a manual, low-frequency dev ritual, so the cost is smaller here still.
if [ -n "${KEEL_CANARY_STATE:-}" ]; then
  CANARY_STATE="$KEEL_CANARY_STATE"
else
  # gate_pre_pr_gate_root, not a hand-typed "$root/pre-pr-gate/..." — the "pre-pr-gate" segment name
  # has exactly one spelling, in tools/lib/gate-paths.sh, not a second one here (found by this
  # ticket's own /simplify pass, altitude angle).
  _pc_root="$(gate_pre_pr_gate_root)" || {
    printf 'pipeline-canary: $HOME is unset/empty and $KEEL_CANARY_STATE is not set — cannot resolve the state path\n' >&2
    exit 1
  }
  CANARY_STATE="$_pc_root/canary-state"
  unset _pc_root
fi

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

# dir #317: isolation now goes through tools/lib/impact-store.sh's own impact_isolated + its
# IMPACT_ISOLATION_VARS list (sourced above) — the two-variable knowledge dir #290's narrower
# `_sandboxed_impact` used to hand-carry here (and which E11 found still missed KEEL_IMPACT_LOG) is now
# stated in exactly one place, used at every call into that lib below (cmd_setup's pre-create, cmd_check's
# read) and by the printed session command's own derivation further down.

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
  # hand-off files off a basename-plus-hash-of-the-full-path (dir #481: the hash is what actually
  # separates two canary runs' /tmp files now, since two mktemp -d calls already differ in full path
  # regardless of basename), but a fixed literal would still read as though this toy repo IS a real
  # repo named "repo" in every log line and deny message the canary's own runs produce.
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
  # inside the repo itself. The real /polish session below runs sandboxed (see impact_isolated, dir
  # #317) so its own store resolution lands inside this sandbox on its own — pre-create that store
  # entry (mirrors keel-impact.sh's own `enable`) so a real run's impact events land somewhere `check`
  # can read without extra env. `cmd_check` recomputes the identical path (search "impact_store_dir").
  # dir #630 S5: routed through impact_store_create (mkdir + the S4 provenance record), the one entry
  # creator every site now uses — a bare `mkdir -p` here would leave this sandboxed repo's own entry
  # unrecorded, the one call site the spec names explicitly.
  impact_isolated "$home" impact_store_create "$repo" >/dev/null
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

  # dir #398: CANARY_STATE now lives under the keel-owned root instead of flat in /tmp — the parent
  # may not exist yet on a machine where the gate itself has never run. Shared idiom
  # (tools/lib/gate-paths.sh) instead of a third hand-copy of "mkdir -p, then chmod separately".
  gate_ensure_owner_dir "$(dirname "$CANARY_STATE")"
  {
    printf 'sandbox\t%s\n' "$sandbox"
    printf 'repo\t%s\n' "$repo"
    printf 'key\t%s\n' "$key"
  } > "$CANARY_STATE"

  # dir #317: DERIVED from IMPACT_ISOLATION_VARS (tools/lib/impact-store.sh, sourced above), not
  # hand-typed — a variable added to that one list is blanked here automatically, closing the exact
  # class of miss E11 found (KEEL_IMPACT_LOG left unblanked by dir #290's narrower, hand-typed version).
  blanked=""
  for _pc_var in $IMPACT_ISOLATION_VARS; do
    blanked="$blanked $_pc_var="
  done

  cat <<EOF
pipeline-canary: sandbox ready at $sandbox

Run the real /polish scenario yourself, isolated from your real HOME/hooks:

  cd $repo
  HOME=$home${blanked} PATH=$bin:\$PATH claude --settings $settings --setting-sources project,local

(dir #317: every variable blanked above is IMPACT_ISOLATION_VARS, not decorative — any one of them
exported in your real shell would otherwise redirect part of the session's impact/read-trace writes at
your real store instead of this sandbox, HOME=$home alone notwithstanding.)

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

  # dir #251: the store entry lives at $home/.claude/.keel/impact/<project-id>/ — `home` is
  # deterministic from `sandbox` (cmd_setup always sets it to "$sandbox/home"), so it needs no
  # CANARY_STATE field of its own. Resolved here (not just below, where it was originally used only
  # for the impact log) because dir #398 needs it too: the gate's own sentinel/trace root is now
  # $HOME-keyed, and the REAL /polish session that wrote them ran with HOME=$home (cmd_setup's own
  # printed instructions), never the operator's ambient shell HOME running THIS `check` command.
  home="$sandbox/home"

  if ! _keys_of "$repo"; then
    printf 'FAIL  could not resolve the sandbox repo'"'"'s keys (the gate hard-errors on a detached HEAD — check the sandbox repo has a branch checked out)\n'
    fail=1
    key=""; receipt_key=""
  else
    key="$KEYS_REPO"; receipt_key="$KEYS_RECEIPT"
  fi
  # dir #398: resolved through the shared lib's gate_sentinel_path_for_key (tools/lib/gate-paths.sh,
  # already sourced above) instead of a hand-copied literal, so a root move (dir #637's later work)
  # only ever needs to change one file — HOME="$home" so this agrees with the sandboxed session that
  # actually wrote it (see the $home comment above). A direct in-process call, not a
  # `bash "$GATE" sentinel-path ...` shell-out: that would reparse this whole ~2900-line script just
  # to print one string (found by this ticket's own /simplify pass, efficiency + altitude angles).
  sentinel="$([ -n "$receipt_key" ] && HOME="$home" gate_sentinel_path_for_key "$receipt_key")"
  if [ -z "$receipt_key" ]; then
    : # already reported above; skip the sentinel/trace checks below, nothing meaningful to compare
  elif [ -f "$sentinel" ]; then
    printf 'INFO  a receipt sentinel is still present — the gate has not yet been asked to unlock (run gh pr create inside the sandbox session), or the last run was denied\n'
  else
    printf 'PASS  no leftover receipt sentinel — consistent with a consumed, successful pass\n'
  fi

  # dir #317: read via impact_isolated, the SAME way the printed session command (cmd_setup, above)
  # now blanks every IMPACT_ISOLATION_VARS variable for the real /polish session — so `check` and the
  # session it is checking always agree on where an event landed, regardless of what the operator's
  # own real shell happens to have exported. This supersedes an earlier, narrower fix (dir #64) that
  # made `check` deliberately FOLLOW an ambient $KEEL_IMPACT_LOG, back when the session still inherited
  # it too (resolve_impact_log() in pre-pr-gate.sh still does that un-isolated resolution — S3(e), it
  # has no isolation concept of its own); once the session stopped inheriting it, following it here
  # would have made `check` look in the wrong place instead (operator-run /code-review high pass).
  ilog="$(impact_isolated "$home" impact_log_path "$repo")"
  if [ -f "$ilog" ] && grep -q 'receipt-pass' "$ilog" 2>/dev/null; then
    printf 'PASS  a receipt-pass event was recorded: %s\n' "$(grep 'receipt-pass' "$ilog" | tail -n1)"
  else
    printf 'INFO  no receipt-pass event recorded yet in %s\n' "$ilog"
  fi

  # dir #398: same rationale as sentinel above — gate_trace_path_for_key, HOME="$home" for the same
  # reason.
  trace="$([ -n "$key" ] && HOME="$home" gate_trace_path_for_key "$key")"
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
  # dir #478: this script runs `set -u` only (no `-e`) — a failed mktemp would leave $d empty and
  # every `git -C "$d"`/`cd "$d"` below would silently act on the invocation directory instead.
  [ -n "$d" ] || { echo "pipeline-canary: mktemp -d failed" >&2; exit 1; }
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
  rm -f "$(gate_trace_path_for_key "$(_repo_key_of "$d")")"   # make certain no trace exists to (correctly) vouch for this

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
