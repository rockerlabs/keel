#!/usr/bin/env bash
# Pre-PR gate — the enforcement half of the /polish → PR flow.
#
# Ships to adopters (dir #68) — pairs with commands/polish.md, which install.sh installs unconditionally.
# This script itself is never auto-wired, though: it's a Claude-Code-specific hook, and a hook changes
# what a session can do without asking each time, so wiring it is a separate, explicit, opt-in step —
# tools/install-pre-pr-gate.sh <repo> (project scope, the default) or --global (every repo). Until that
# runs, /polish's steps still work; only the gh pr create block (below) is inert.
#
# Wired as a Claude Code PreToolUse(Bash) hook (tools/install-pre-pr-gate.sh does this for you): it
# intercepts `gh pr create` and requires /polish (simplify + inline review + tests) to have run on the
# current HEAD. The bypass path is closed by
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
#   pre-pr-gate.sh handoff <level> <sha>   record step 5(b)'s stop so a re-invocation doesn't re-ask (dir #63)
#   pre-pr-gate.sh handoff-check           print+exit 0 if a handoff matches current HEAD, else exit 1 (dir #63)
#   pre-pr-gate.sh skill-trace             hook subcommand (see dir #63 section below) — not run by hand
#   pre-pr-gate.sh rollout-check           SessionStart hook subcommand (dir #64 tier 1) — not run by hand
#   pre-pr-gate.sh sweep [K]               /wrap-time floor (dir #64 tier 2b): warn when the last K
#                                           polish runs closed without a trace-confirmed review (default K=3)
#
# With no subcommand, it runs as the PreToolUse(Bash) hook: reads the tool-call JSON event on stdin,
# decides allow/deny for `gh pr create`.
#
# --- dir #63: making step 5's review outcome verifiable -------------------------------------------
# Hole A (a fabricated in-session review claim is unfalsifiable): `polish.5-review`'s receipt is a
# free-form string the model writes about itself, so a real in-session `/code-review <level>` pass and
# a session that only claims one are byte-identical. Fix: two ADDITIONAL hooks (same settings.json as
# the PreToolUse gate above — tools/install-pre-pr-gate.sh wires all four together) write a mechanical
# trace line to a HOOK-OWNED side channel the model isn't expected to touch — a materially higher bar
# than getting one self-report right, though not literally unfakeable (the model still has Bash; see the
# residual limit below):
#   "PostToolUse":         [{ "matcher": "Skill",       "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh skill-trace" }] }]
#   "UserPromptExpansion": [{ "matcher": "code-review", "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh skill-trace" }] }]
# The PostToolUse leg fires when Claude itself calls Skill(code-review) — PostToolUse only fires after
# a tool call SUCCEEDS (a refused/unavailable call never reaches it, so an unavailable-skill run leaves
# no trace by construction — see the residual limit below). The UserPromptExpansion leg fires when the
# OPERATOR types `/code-review <level>` directly, which bypasses PostToolUse entirely (confirmed against
# Claude Code's hooks reference: "a PreToolUse hook matching the Skill tool fires only when Claude calls
# the tool, but typing /skillname directly bypasses PreToolUse" — PostToolUse matches the same tool-name
# set). Both write the same trace line via `skill-trace`, keyed like the sentinel (main_top_for), to
# /tmp/pre-pr-gate-trace-<repo>: "<HEAD-sha>\t<level-if-known>".
# The gate's PASS branch (hook mode, below) cross-checks this trace whenever `polish.5-review`'s
# outcome is a BARE level (no `-operator-run`/`-waived` suffix, not `skip`) — that shape claims a real
# in-session run, so it must have left a trace for the SAME sha AND the SAME level, or the gate denies
# (an honest `/code-review low` pass must not be able to vouch for a receipt claiming `max`). Separately,
# EVERY outcome shape — including the trusted `skip`/`-operator-run`/`-waived` ones, which need no trace
# — is cross-checked against `polish.4-depth`'s own recorded level: without this, a session could size
# the diff `medium` and then simply write `polish.5-review skip`, since `skip` was trusted unconditionally.
# **Residual limits** (write these into any doc referencing the mechanism):
# (1) the unavailable→inline-pass hand-off (commands/polish.md step 5(a)/(b)/(c)) leaves no trace by
#     construction — its outcome (`-operator-run`/`-waived`) stays self-reported; the trace only makes
#     ONE dishonesty channel checkable — "claims the skill ran when it didn't" — not the inline pass's
#     own thoroughness.
# (2) the trace records `git -C <event-cwd> rev-parse HEAD` at invocation time — if the session's
#     harness-tracked cwd for the Skill/slash-command event is a DIFFERENT checkout than the one the
#     eventual `gh pr create --head <branch>` targets (the split main-checkout/worktree pattern dir #61
#     hardened for the sentinel and gate-side SHA check), the trace can be keyed to the wrong commit —
#     a genuine review then false-denies rather than false-passing. Not fixable at trace-write time (the
#     eventual `--head` isn't known yet); same accepted trade-off as (3).
# (3) the hand-off file is repo-scoped like the sentinel, so two worktrees of the SAME repo mid-`/polish`
#     at the same time share one hand-off (and, if they land on the identical commit before either has
#     diverged, could overwrite each other's note) — an existing limitation of the sentinel's own
#     per-repo (not per-worktree) keying, not a new one this ticket introduces.
#
# Hole B (the hand-off's only exit depended on session memory): step 5(c) used to exit only when "the
# session already shows they ran it" — gone after a compaction or a fresh session on the same branch, so
# a re-invocation would defer forever (`init` mints a fresh nonce by design, wiping the receipt sentinel,
# dir #49's replay fix). Fix: `handoff` writes `polish.5\t<level>\t<HEAD-sha>` to its OWN file
# (`handoff_path()`, keyed like the sentinel) at step 5(b) stop time — a separate file, not a line folded
# into the sentinel, so `init`'s nonce reset never has to know it exists: it survives by construction,
# not by a special case. `receipt polish.5-review <outcome>` removes it once the real receipt lands.
# `handoff-check` on a re-invocation tells step 5(c) whether the question was already asked for this
# EXACT diff (same HEAD SHA) — a match means collect the answer without re-deferring; any new commit
# invalidates the match (same-SHA-only replay window, not open-ended).
#
# --- dir #64: a model/harness rollout must not break the pipeline silently ------------------------
# Generalizes dir #63's root cause: the Opus 5 rollout silently removed /code-review's model-invokability
# and nothing warned — the only way to learn it was reading a transcript. Three tiers, each independent:
#
# Tier 1 — rollout-check (this file, SessionStart hook, below). Wire as:
#   "SessionStart": [{ "matcher": "startup", "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh rollout-check" }] }]
# Records the session's `.model` (from the SessionStart hook JSON) + `claude --version` into a per-repo
# state file; on either changing since the last recorded session, appends a `pipeline-drift` impact-log
# event and emits a `systemMessage` banner. First-ever run for a repo just records a baseline (nothing to
# compare against yet) — never a false warning.
# **TO VERIFY, resolved 2026-07-27:** (1) the SessionStart hook JSON DOES carry a `model` field (per
# code.claude.com/docs/en/hooks.md) — may be omitted after `/clear`/recovery, handled as "nothing to
# compare" rather than "changed". (2) plain stdout from a SessionStart hook is NOT shown to the human
# operator — the docs are explicit that for SessionStart (like UserPromptSubmit/UserPromptExpansion),
# stdout is "added as context that Claude can see and act on", i.e. model-visible only. The
# human-visible channel is the separate `systemMessage` JSON field, which is what `rollout-check` uses.
#
# Tier 2 — provenance surfacing (this file, PASS branch + `sweep` subcommand, below).
#   (a) the gate's ALLOW decision now carries a `systemMessage`/`permissionDecisionReason` naming how
#       step 5's review was actually established — "review: skip", "review: <level>, trace-confirmed
#       in-session" (dir #63's mechanical trace matched), or "review: <level>, operator-run
#       (self-reported)" / "review: <level>, waived (self-reported)" for the hand-off outcomes dir #63
#       never traces. Visible at PR-creation time instead of only via transcript archaeology.
#   (b) `sweep [K]` reads the impact log's `receipt-pass` rows (now carrying that same classification as
#       their detail field) and warns when the last K (default 3) consecutive passes never read
#       "trace-confirmed" — a run of self-reported-only reviews, the exact pre-#63 blind spot. Read-only,
#       never blocks; wiring it into a `/wrap` step is a manual follow-up (same precedent as dir #63's
#       hook wiring into settings.json — see that section above).
#
# Tier 3 — tools/pipeline-canary.sh (separate file). A sandboxed operator ritual that builds a toy repo +
# isolated HOME + stubbed `gh` + this file's hooks wired in, then either drives a real `/polish` run
# (operator-triggered) or seeds a fabricated step-5 claim and asserts the gate still denies it (fully
# scripted, no model needed — the canary's own proof that it CAN fail). Full design + the TO VERIFY
# outcome on headless hook-firing → that file's own header.

set -u

EXPECTED_STEPS="polish.1-diff polish.2-simplify polish.3-tests polish.4-depth polish.5-review polish.6-retest polish.7-selfcheck polish.8-unlock"

# The `git worktree list --porcelain` main-entry projection, factored out so main_top_for() and
# resolve_impact_log() below (one file, two pre-dir-#61 and dir-#61 call sites) share the fragment
# instead of each inlining it — the awk is identical; only the surrounding fallback order differs, so
# only the fragment is extracted, not the two functions merged (dir #26 logs the wider idiom as
# duplicated across 5 TOOLS by design, no shared lib yet — that's a cross-tool constraint, unrelated to
# sharing one fragment within a single file).
_worktree_main_entry() {
  git -C "${1:-.}" worktree list --porcelain 2>/dev/null |
    awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true
}

# Resolve the main checkout's top for cwd $1 (dir #10/PR #67 discipline). Falls back to $1's own
# canonicalized toplevel when the main worktree entry is bare (no working tree) — this does NOT unify
# across a bare main's several worktrees (each still resolves to its own toplevel there); that's an
# accepted limitation shared with the established `_keel_main_top` idiom elsewhere, and keel's own
# worktrees are always cut from a non-bare checkout, so the dir #61 scenario below is unaffected. Falls
# back to $1 itself when it isn't a repo at all.
# dir #61: both the receipt writer (sentinel_path, below) and the hook reader key off THIS instead of
# a raw dirname/basename, so a receipt written from inside a (non-bare-main) worktree and a `gh pr
# create` hook event reporting a different checkout of the SAME repo (e.g. the harness's tracked
# session-root cwd) agree on one sentinel file — they always resolve to the same main-checkout path.
main_top_for() {
  local cwd="${1:-.}" main top
  main="$(_worktree_main_entry "$cwd")"
  if [ -n "$main" ]; then printf '%s' "$main"; return; fi
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then printf '%s' "$top"; return; fi
  printf '%s' "$cwd"
}

# The basename-of-main-checkout key every per-repo /tmp file below shares, factored out once dir #63
# added a second and third call site (skill-trace's own cwd, the hand-off note) beside the pre-existing
# hook-mode one — same rationale as _worktree_main_entry's own extraction, above.
_repo_key() { basename "$(main_top_for "${1:-$PWD}")"; }

sentinel_path()  { printf '/tmp/pre-pr-gate-%s' "$(_repo_key "$PWD")"; }
# dir #63: the review-invocation trace (skill-trace writes it, the gate's PASS branch reads it) and the
# step-5(b) hand-off note (handoff/handoff-check) each get their OWN file, keyed the same way as the
# sentinel — not lines folded into the sentinel itself. Keeping them separate means `init`'s nonce reset
# (the sentinel's job: wipe the PREVIOUS run's receipts, dir #49) never has to know the hand-off note
# exists at all: it lives elsewhere, so it survives by construction, not by a special case in `init`.
trace_path_for() { printf '/tmp/pre-pr-gate-trace-%s' "$(_repo_key "${1:-$PWD}")"; }
handoff_path()   { printf '/tmp/pre-pr-gate-handoff-%s' "$(_repo_key "$PWD")"; }
# dir #64 tier 1: the last-seen model/harness version per repo, keyed the same way — a fresh file, so
# `init`'s nonce reset (the sentinel's job) never touches it, same rationale as the trace/hand-off files.
rollout_state_path() { printf '/tmp/pre-pr-gate-rollout-%s' "$(_repo_key "${1:-$PWD}")"; }

# Resolve the impact log path for a given cwd ($1): $KEEL_IMPACT_LOG, else the repo's own .keel/ marker
# (falling back to the main checkout's marker from a linked worktree — the untracked marker isn't shared,
# so a linked worktree looks at the first `git worktree list` entry, skipped when bare). One resolution
# used everywhere a guard/receipt/log event is recorded (dir #49 folded three copies into this one).
resolve_impact_log() {
  local cwd="$1" klog="${KEEL_IMPACT_LOG:-}" top main
  if [ -z "$klog" ]; then
    top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ] && [ ! -d "$top/.keel" ]; then
      main="$(_worktree_main_entry "$cwd")"
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
  repo-key)
    # Exposes _repo_key() (the worktree-aware basename(main_top_for(...)) dir #61 resolution every
    # /tmp sentinel/trace/hand-off/rollout-state path is keyed by) to other tools — dir #64's own
    # pipeline-canary.sh uses this instead of hand-copying the algorithm, which would silently drop
    # the worktree resolution if it ever changes here.
    printf '%s\n' "$(_repo_key "${2:-$PWD}")"
    exit 0
    ;;
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
    # dir #63/Hole B: the real receipt landing IS the answer step 5(b) was waiting on — clear the
    # hand-off note rather than let it linger past the question it recorded.
    [ "$step_id" = "polish.5-review" ] && rm -f "$(handoff_path)"
    exit 0
    ;;
  log)
    ty="${2:?pre-pr-gate: log <type> [detail] — type required}"
    detail="${3:-}"
    log_event "$ty" "$detail" "$PWD"
    exit 0
    ;;
  handoff)
    level="${2:?pre-pr-gate: handoff <level> <sha> — level required}"
    sha="${3:?pre-pr-gate: handoff <level> <sha> — sha required}"
    printf 'polish.5\t%s\t%s\n' "$level" "$sha" > "$(handoff_path)"
    exit 0
    ;;
  handoff-check)
    hp="$(handoff_path)"
    if [ -f "$hp" ]; then
      sha="$(git rev-parse HEAD 2>/dev/null)"
      line="$(awk -F'\t' -v sha="$sha" '$3==sha{print}' "$hp")"
      if [ -n "$line" ]; then printf '%s\n' "$line"; exit 0; fi
    fi
    exit 1
    ;;
  skill-trace)
    # PostToolUse(Skill) or UserPromptExpansion(code-review) hook — see the dir #63 header section.
    # Never blocks or alters anything: silently no-ops (exit 0) on anything it can't parse or that
    # isn't a code-review invocation, since a missed trace is a residual limit, not a false deny. One
    # jq call for every field this needs — it fires on every Skill/slash-command event in every
    # session using this hook, so it's worth sparing the extra forks a call-per-field would cost.
    # Joined with \x1f (NOT tab): bash `read` collapses an EMPTY field sitting between two tab
    # delimiters regardless of IFS (the same class of bug the keel-impact log parser hit) — real here,
    # since a UserPromptExpansion event has no `tool_name` field at all, an empty middle field.
    command -v jq >/dev/null 2>&1 || exit 0
    st_input=$(cat 2>/dev/null)
    # `str` coerces every field to a plain string first — an unexpected shape (args as an object/array,
    # say) would otherwise make `join` throw and lose the WHOLE row, including the hook_event_name/skill
    # fields that were perfectly fine, turning one malformed field into total silence from this hook.
    IFS=$'\x1f' read -r st_event st_cwd st_tool st_skill st_level <<<"$(printf '%s' "$st_input" | jq -r '
      def str: if . == null then "" elif type == "string" then . else tostring end;
      [.hook_event_name, (.cwd|str), (.tool_name|str),
       (if .hook_event_name == "PostToolUse" then .tool_input.skill else .command_name end|str),
       (if .hook_event_name == "PostToolUse" then .tool_input.args else .command_args end|str)
      ] | join("\u001f")' 2>/dev/null)"
    [ -n "$st_cwd" ] || st_cwd="$PWD"
    case "$st_event" in
      PostToolUse) [ "$st_tool" = "Skill" ] || exit 0 ;;
      UserPromptExpansion) ;;
      *) exit 0 ;;
    esac
    case "$st_skill" in
      code-review|*:code-review|/code-review) ;;
      *) exit 0 ;;
    esac
    st_sha=$(git -C "$st_cwd" rev-parse HEAD 2>/dev/null)
    [ -n "$st_sha" ] || exit 0
    printf '%s\t%s\n' "$st_sha" "$st_level" >> "$(trace_path_for "$st_cwd")"
    exit 0
    ;;
  rollout-check)
    # SessionStart hook (dir #64 tier 1) — see the dir #64 header section above. Never blocks; any
    # parse failure or missing jq is a silent no-op rather than a false warning.
    command -v jq >/dev/null 2>&1 || exit 0
    rc_input=$(cat 2>/dev/null)
    # One jq call for both fields (same rationale as skill-trace's own field-parsing above — this fires
    # on every session start, worth sparing the extra fork). \x1f: same bash-`read`-collapses-an-empty-
    # tab-delimited-field pitfall skill-trace already documents, so a missing `.model` can't shift `.cwd`
    # into the wrong variable.
    IFS=$'\x1f' read -r rc_model rc_cwd <<<"$(printf '%s' "$rc_input" | jq -r '[(.model // ""), (.cwd // "")] | join("\u001f")' 2>/dev/null)"
    [ -n "$rc_cwd" ] || rc_cwd="$PWD"
    rc_version="$(claude --version 2>/dev/null | head -n1)"
    rc_state="$(rollout_state_path "$rc_cwd")"
    rc_prev_model=""; rc_prev_version=""
    if [ -f "$rc_state" ]; then
      IFS=$'\x1f' read -r rc_prev_model rc_prev_version <<<"$(awk -F'\t' -v SEP=$'\x1f' '
        $1=="model"{m=$2} $1=="version"{v=$2} END{print m SEP v}
      ' "$rc_state" 2>/dev/null)"
    fi
    # Only compare a field when BOTH sides are known — an empty reading (jq/claude unavailable this
    # run, or a `model`-less SessionStart event) means "can't tell", not "changed".
    rc_changed=""
    if [ -n "$rc_model" ] && [ -n "$rc_prev_model" ] && [ "$rc_model" != "$rc_prev_model" ]; then
      rc_changed="model ($rc_prev_model -> $rc_model)"
    fi
    if [ -n "$rc_version" ] && [ -n "$rc_prev_version" ] && [ "$rc_version" != "$rc_prev_version" ]; then
      [ -n "$rc_changed" ] && rc_changed="$rc_changed, "
      rc_changed="${rc_changed}harness ($rc_prev_version -> $rc_version)"
    fi
    # Persist a field only when this run actually read it — an empty reading (e.g. a `model`-less
    # SessionStart event) must NOT clobber the last-known-good baseline with "", or the NEXT session's
    # genuine change would compare against an erased value and silently pass the "can't tell" guard
    # above (found in the operator-run /code-review high pass on this ticket).
    {
      printf 'model\t%s\n' "${rc_model:-$rc_prev_model}"
      printf 'version\t%s\n' "${rc_version:-$rc_prev_version}"
    } > "$rc_state"
    if [ -n "$rc_changed" ]; then
      log_event pipeline-drift "$rc_changed" "$rc_cwd"
      rc_msg="model/harness changed since last session ($rc_changed) - pipeline commands may have silently degraded; watch /polish step 5, consider tools/pipeline-canary.sh"
      printf '{"systemMessage":"%s"}\n' "$rc_msg"
    fi
    exit 0
    ;;
  sweep)
    # dir #64 tier 2b — read-only /wrap-time floor, never blocks. Warns when the last K consecutive
    # receipt-pass rows in the impact log never read "trace-confirmed" (the pre-#63 blind spot: every
    # recent /polish run closed on a self-reported review only), OR when there are FEWER than K rows
    # total and every one of them is non-trace-confirmed (a new/low-volume repo shouldn't read as
    # "fine" just because it hasn't accumulated K runs yet — found in the operator-run /code-review
    # high pass on this ticket). Not wired into any hook by design (a sweep needs to run once per
    # /wrap, not per gate decision) — invoking it is a manual follow-up.
    sw_k="${2:-3}"
    case "$sw_k" in ''|*[!0-9]*) sw_k=3 ;; esac
    sw_log="$(resolve_impact_log "$PWD")"
    if [ -z "$sw_log" ] || [ ! -f "$sw_log" ]; then
      printf 'pre-pr-gate: sweep - no impact log found, nothing to check\n'
      exit 0
    fi
    # $5, not a regex over $4: the receipt-pass detail field ($4, `prov_label`) is HUMAN-DISPLAY prose;
    # $5 is the separate machine tag ("trace-confirmed"/"self-reported") the PASS branch now logs
    # alongside it, so a future rewording of the display text can't silently break this classification
    # (found in the same review pass — the tag/prose coupling was itself a finding).
    sw_result="$(awk -F'\t' -v k="$sw_k" '
      $2 == "receipt-pass" { rows[++n] = $5 }
      END {
        streak = 0
        for (i = n; i >= 1; i--) {
          if (rows[i] == "trace-confirmed") break
          streak++
        }
        if (streak >= k) { print "WARN"; exit }
        if (n > 0 && streak == n) { print "WARN"; exit }
        print "OK"
      }
    ' "$sw_log")"
    if [ "$sw_result" = "WARN" ]; then
      printf 'pre-pr-gate: sweep - %s+ consecutive /polish runs closed without a trace-confirmed code-review (self-reported only). Consider tools/pipeline-canary.sh or an operator-run /code-review.\n' "$sw_k"
      exit 1
    fi
    printf 'pre-pr-gate: sweep - recent runs look fine (a trace-confirmed review within the last %s)\n' "$sw_k"
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

# Fast-exit: only care about `gh pr create` in real command position (backlog dir #58 — replaces the
# earlier substring match, S6/backlog dir #4, which false-fired on any command merely CONTAINING the
# phrase: a KB write whose heredoc/quoted TEXT mentioned it, a commit message, a grep for the phrase
# itself). A small lexer over $cmd: strips heredoc bodies, strips quoted spans, splits on command
# separators (`;` `&` `|` `&&` `||` `(` `)` backtick, `$(`, newline), then per segment skips leading
# `VAR=value` assignments and `env`/`command` wrappers (incl. their own flags/assignments) and matches
# iff the first remaining token is exactly `gh`, followed later by `pr`, followed later by `create` —
# any tokens in between. That also closes the `gh --repo owner/name pr create` bypass (a global flag
# before the subcommand, no longer a residual gap) that the old substring match missed.
#
# A second command shape opens a PR without that subcommand at all: `gh api repos/O/R/pulls -f head=…`
# (found 2026-07-26 auditing the dir #57 rework — the natural reach once `gh pr create` is denied). It's
# matched when it is a genuine WRITE to a pulls collection: an endpoint ending in `/pulls` PLUS either
# an explicit `POST` or — absent any named method — a field/input flag, since gh itself defaults to POST
# once fields are supplied. An explicit method always wins over that inference, so `-X GET …/pulls -f
# state=open` (fields become query parameters on a GET) stays a read. Reads stay allowed on purpose —
# `.../pulls` with no write flag (list), `.../pulls/123` (one PR), `.../pulls/123/comments -f body=…`
# (commenting on an existing PR): this gate blocks OPENING a PR, not looking at or annotating one, and a
# gate that denies status checks teaches the next session to route around it. The branch is read out of
# `-f head=…` for the same dir #61 reason the `pr create` path reads `--head`.
#
# Still lexical, not a real shell parse: within this model it errs toward catching — an unstripped
# exotic heredoc form, or prose that happens to sit at a real command position, falls through as a
# false positive (an unneeded /polish reminder, not a bypass). Known accepted residuals (this is a
# WORKFLOW gate, not the secret boundary — that's secret-guard): `sh -c 'gh pr create'` / `eval "gh pr
# create"` (quoted → stripped, invisible to the lexer — a conscious regression from the old substring
# match, which DID catch these); `gh "pr" create` (quoting the bare subcommand splits it out of the
# token stream); a `gh` alias/wrapper-script rename; `env -u VAR gh pr create` (an `env` flag that
# takes its own separate value token, e.g. `-u VAR`, is not itself a flag or a `VAR=value` assignment,
# so the skip-loop stops on the value token instead of reaching `gh` — a flag-arity table to handle
# this generically is disproportionate for a workflow gate; the plain-prefix `VAR=value gh pr create`
# and `env VAR=value gh pr create` shapes above remain caught).
IFS= read -r -d '' PPG_AWK_PROG <<'PPG_AWK_EOF' || true
function flush_tok() {
  if (buf != "") { ntok++; tok[ntok] = buf; buf = "" }
}
function is_assign(t) {
  return (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/)
}
function check_segment(   i,j,k,found_pr,found_api,ep_pulls,writes,has_field,method) {
  i = 1
  while (i <= ntok) {
    if (is_assign(tok[i])) { i++; continue }
    if (tok[i] == "env" || tok[i] == "command") {
      i++
      while (i <= ntok && (substr(tok[i], 1, 1) == "-" || is_assign(tok[i]))) i++
      continue
    }
    break
  }
  if (i <= ntok && tok[i] == "gh") {
    # dir #63 sibling fix: `gh api repos/O/R/pulls -f head=…` creates a PR without ever using the
    # `pr create` subcommand, so the token scan below never saw it — the natural thing to reach for
    # once `gh pr create` is denied. Matched only when it's genuinely a WRITE to a pulls collection:
    # an endpoint ending in `/pulls` plus an explicit POST or any field/input flag. A plain
    # `gh api repos/O/R/pulls` (list) or `.../pulls/123` (read) stays allowed — this gate blocks
    # opening a PR, not looking at one.
    found_api = 0; ep_pulls = 0; has_field = 0; method = ""
    for (j = i + 1; j <= ntok; j++) {
      if (tok[j] == "api") found_api = 1
      else if (tok[j] ~ /(^|\/)pulls$/) ep_pulls = 1
      else if (tok[j] == "-X" || tok[j] == "--method") {
        if (j + 1 <= ntok) method = toupper(tok[j + 1])
      }
      else if (tok[j] ~ /^--method=/) { method = toupper(substr(tok[j], 10)) }
      else if (tok[j] == "-f" || tok[j] == "-F" || tok[j] == "--field" ||
               tok[j] == "--raw-field" || tok[j] == "--input") has_field = 1
    }
    # A field flag implies a write ONLY when no method was named — that's just gh's own default
    # (fields present ⇒ POST). An explicit method always wins: `-X GET … -f state=open` sends the
    # fields as query parameters and is a read, so inferring "write" from the flag alone would deny
    # exactly the listing this gate promises to leave alone.
    if (method != "") writes = (method == "POST")
    else writes = has_field
    if (found_api && ep_pulls && writes) {
      # Same purpose as the --head scan in the pr-create branch below (dir #61): name the branch the
      # PR is actually FOR, so the SHA check still resolves when the hook's event cwd isn't that
      # branch's own checkout. Here the branch arrives as a field, `-f head=branch`; a cross-fork
      # `head=owner:branch` carries an owner prefix that is not part of the ref.
      for (k = i + 1; k <= ntok; k++) {
        if (tok[k] ~ /^head=/) { head_out = substr(tok[k], 6); sub(/^[^:]*:/, "", head_out) }
      }
      matched = 1
      return
    }

    found_pr = 0
    for (j = i + 1; j <= ntok; j++) {
      if (!found_pr) {
        if (tok[j] == "pr") found_pr = 1
      } else if (tok[j] == "create") {
        matched = 1
        # dir #61: an explicit --head/-H names the branch the PR is actually FOR — the hook uses this
        # (instead of a bare HEAD) so the SHA check still works when the event cwd isn't that branch's
        # own checkout (e.g. `gh pr create --head <branch>` run from the main checkout's session root).
        for (k = i + 1; k <= ntok; k++) {
          if (tok[k] == "--head" || tok[k] == "-H") { if (k + 1 <= ntok) head_out = tok[k + 1] }
          else if (tok[k] ~ /^--head=/) { head_out = substr(tok[k], 8) }
        }
        return
      }
    }
  }
}
function end_segment() {
  flush_tok()
  if (ntok > 0) check_segment()
  ntok = 0
}
{
  line = $0
  if (in_hd) {
    check = line
    if (hd_strip) { while (substr(check, 1, 1) == "\t") check = substr(check, 2) }
    if (check == hd_delim) { in_hd = 0 }
    next
  }
  p = index(line, "<<")
  kept = line
  if (p > 0 && substr(line, p, 3) != "<<<") {
    rest = substr(line, p + 2)
    idx = 1
    strip = 0
    if (substr(rest, idx, 1) == "-") { strip = 1; idx++ }
    while (substr(rest, idx, 1) == " ") idx++
    q = substr(rest, idx, 1)
    quote = ""
    if (q == "'" || q == "\"") { quote = q; idx++ }
    start = idx
    rlen = length(rest)
    while (idx <= rlen) {
      c = substr(rest, idx, 1)
      if (quote != "") { if (c == quote) break } else { if (c == " " || c == "\t") break }
      idx++
    }
    delim = substr(rest, start, idx - start)
    if (delim != "") {
      if (quote != "") idx++
      # Only the "<<[-]DELIM" token itself is heredoc syntax — trailing same-line content (e.g. a
      # chained `&& real-command`) is NOT part of the heredoc and must stay in scope for scanning.
      kept = substr(line, 1, p - 1) substr(rest, idx)
      in_hd = 1; hd_delim = delim; hd_strip = strip
    }
  }
  n = length(kept)
  pos = 1
  while (pos <= n) {
    c = substr(kept, pos, 1)
    if (c == "\\") {
      if (pos < n) { buf = buf substr(kept, pos + 1, 1); pos += 2 } else { pos++ }
      continue
    }
    if (c == "'") {
      flush_tok(); pos++
      while (pos <= n && substr(kept, pos, 1) != "'") pos++
      pos++
      continue
    }
    if (c == "\"") {
      flush_tok(); pos++
      while (pos <= n) {
        cc = substr(kept, pos, 1)
        if (cc == "\\" && pos < n) { pos += 2; continue }
        if (cc == "\"") { pos++; break }
        pos++
      }
      continue
    }
    if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "`") {
      end_segment()
      pos++
      continue
    }
    if (c == " " || c == "\t") { flush_tok(); pos++; continue }
    buf = buf c
    pos++
  }
  end_segment()
}
END { if (matched) { print head_out; exit 0 }; exit 1 }
PPG_AWK_EOF

awk_out="$(awk "$PPG_AWK_PROG" <<< "$cmd")"
awk_status=$?
if [ "$awk_status" -ne 0 ]; then
  exit 0
fi
head_branch="$awk_out"

# dir #61: resolve the sentinel by the REPO's main checkout, not the raw event cwd — a receipt written
# from inside a worktree and a hook event reporting a different checkout of the same repo (the
# harness's tracked session-root cwd, which does not track an in-command `cd`) must land on one file.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
wt=$(_repo_key "$cwd")
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
result="$(awk -F'\t' -v steps="$EXPECTED_STEPS" -v SEP=$'\x1f' '
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
    if (malformed || nonce == "") { print "MALFORMED" SEP; exit }
    missing = ""; replay = ""
    for (s in need) {
      if (!(s in got)) {
        missing = (missing == "" ? s : missing "," s)
        if (s in foreign) replay = (replay == "" ? s : replay "," s)
      }
    }
    if (missing == "") {
      print "PASS" SEP val["polish.8-unlock"] SEP val["polish.5-review"] SEP val["polish.4-depth"]; exit
    }
    if (replay != "") { print "REPLAY" SEP missing; exit }
    print "MISSING" SEP missing
  }
' "$sentinel")"

# \x1f (NOT tab) joins these fields: bash `read` collapses an EMPTY field sitting between two tab
# delimiters regardless of what IFS is set to (the same bug fixed in skill-trace, above) — a genuinely
# reachable shape here too (e.g. a malformed polish.8-unlock outcome), so use the same safe delimiter.
IFS=$'\x1f' read -r status detail review_outcome depth_outcome <<<"$result"

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
    # dir #61: an explicit --head/-H names the branch being PR'd — compare against ITS tip (a shared
    # ref, resolvable from any checkout of the repo) rather than assuming $cwd is that branch's own
    # checkout. No --head: unchanged, bare HEAD of $cwd (the pre-dir-#61 behaviour, still correct there).
    target_ref="HEAD"
    [ -n "$head_branch" ] && target_ref="${head_branch##*:}"
    current_sha=$(git -C "$cwd" rev-parse "$target_ref" 2>/dev/null)
    if [ -z "$current_sha" ] || [ "$detail" != "$current_sha" ]; then
      rm -f "$sentinel"
      log_event receipt-deny "sha-mismatch" "$cwd"
      deny "Pre-PR gate: sentinel is stale (HEAD changed since /polish ran, or a manual bypass was attempted). Run /polish again."
    fi
    # dir #63/Hole A: cross-check step 5's review outcome against step 4's OWN recorded depth — without
    # this, "skip"/"-operator-run"/"-waived" (the outcomes exempt from the trace check below) were
    # trusted unconditionally, so a session could size the diff `medium`, then write `polish.5-review
    # skip` regardless. ONE case statement below is the only place that knows the trusted-suffix set —
    # it strips the suffix (to compare against step 4's level), decides whether a trace is required,
    # AND builds the dir #64 tier 2a provenance label + tag (below) from the same match, so a future
    # third suffix only needs adding here, not kept in sync across separate mechanisms. $prov_tag is a
    # STABLE machine value ("trace-confirmed"/"self-reported") separate from $prov_label's human prose,
    # so `sweep` (below) can classify without depending on display wording (found in the operator-run
    # /code-review high pass on this ticket — sweep used to regex-match the prose directly).
    depth_level="${depth_outcome%%:*}"
    trusted=0
    case "$review_outcome" in
      skip)             outcome_level="skip";                       trusted=1
                         prov_label="review: skip";  prov_tag="self-reported" ;;
      *-operator-run)   outcome_level="${review_outcome%-operator-run}"; trusted=1
                         prov_label="review: $outcome_level, operator-run (self-reported)"; prov_tag="self-reported" ;;
      *-waived)         outcome_level="${review_outcome%-waived}";       trusted=1
                         prov_label="review: $outcome_level, waived (self-reported)"; prov_tag="self-reported" ;;
      *)                outcome_level="$review_outcome"
                         prov_label="review: $outcome_level, trace-confirmed in-session"; prov_tag="trace-confirmed" ;;
    esac
    if [ "$outcome_level" != "$depth_level" ]; then
      rm -f "$sentinel"
      log_event receipt-deny "review-depth-mismatch" "$cwd"
      deny "Pre-PR gate: step 5's review outcome ('$review_outcome') doesn't match the depth step 4 recorded ('$depth_level'). Run /polish again."
    fi
    # A BARE review outcome (trusted=0 above: no -operator-run/-waived suffix, not skip) claims a real
    # in-session /code-review run — cross-check the mechanically-written trace (skill-trace, above) so
    # that claim can't be satisfied by self-report alone. The trace's OWN recorded level must match too
    # — otherwise a genuine `/code-review low` pass would vouch for a receipt claiming `max`. Trusted
    # outcomes need no trace — they already name a different, non-fabricable source (the human, or a
    # deliberate no-review choice) and are covered by the depth check above instead.
    if [ "$trusted" -eq 0 ]; then
      trace_path="/tmp/pre-pr-gate-trace-$wt"
      if [ ! -f "$trace_path" ] || ! awk -F'\t' -v sha="$current_sha" -v lvl="$review_outcome" \
          '$1==sha && $2==lvl{f=1} END{exit !f}' "$trace_path"; then
        rm -f "$sentinel"
        log_event receipt-deny "review-trace-missing" "$cwd"
        deny "Pre-PR gate: step 5 recorded review outcome '$review_outcome' as an in-session /code-review run, but no trace matching both this commit AND that level was found. If the skill was genuinely unavailable, /polish's hand-off should have produced an -operator-run/-waived outcome instead. Run /polish again."
      fi
    fi
    # dir #64 tier 2a: $prov_label/$prov_tag were already built above (the same case statement dir #63's
    # cross-check uses) — visible at PR-creation time instead of only via transcript archaeology. The
    # logged detail carries BOTH, tab-joined ($4 = prov_label prose, $5 = prov_tag) — `sweep` reads $5,
    # never $4, so it never depends on the display wording.
    rm -f "$sentinel"
    log_event receipt-pass "$prov_label"$'\t'"$prov_tag" "$cwd"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' "$prov_label" "$prov_label"
    exit 0
    ;;
esac

# Fail-safe: any unrecognized status denies rather than silently allowing.
rm -f "$sentinel"
deny "Pre-PR gate: could not verify the receipt. Run /polish again."
