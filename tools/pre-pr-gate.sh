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
#   pre-pr-gate.sh handoff <level> <sha>   record step 5(b)'s stop so a re-invocation doesn't re-ask (dir #63)
#   pre-pr-gate.sh handoff-check           print+exit 0 if a handoff matches current HEAD, else exit 1 (dir #63)
#   pre-pr-gate.sh skill-trace             hook subcommand (see dir #63 section below) — not run by hand
#
# With no subcommand, it runs as the PreToolUse(Bash) hook: reads the tool-call JSON event on stdin,
# decides allow/deny for `gh pr create`.
#
# --- dir #63: making step 5's review outcome verifiable -------------------------------------------
# Hole A (a fabricated in-session review claim is unfalsifiable): `polish.5-review`'s receipt is a
# free-form string the model writes about itself, so a real in-session `/code-review <level>` pass and
# a session that only claims one are byte-identical. Fix: two ADDITIONAL hooks (same personal
# ~/.claude/settings.json as the PreToolUse gate above) write a mechanical, SHA-keyed trace line the
# model cannot author itself:
#   "PostToolUse":         [{ "matcher": "Skill",       "hooks": [{ "type": "command", "command": "bash ~/.claude/pre-pr-gate.sh skill-trace" }] }]
#   "UserPromptExpansion": [{ "matcher": "code-review", "hooks": [{ "type": "command", "command": "bash ~/.claude/pre-pr-gate.sh skill-trace" }] }]
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
# in-session run, so it must have left a trace for the current SHA or the gate denies.
# **Residual limit** (write this into any doc referencing the mechanism): the unavailable→inline-pass
# hand-off (commands/polish.md step 5(a)/(b)/(c)) leaves no trace by construction — its outcome
# (`-operator-run`/`-waived`) stays self-reported. The trace only makes ONE dishonesty channel checkable
# — "claims the skill ran when it didn't" — not the inline pass's own thoroughness.
#
# Hole B (the hand-off's only exit depended on session memory): step 5(c) used to exit only when "the
# session already shows they ran it" — gone after a compaction or a fresh session on the same branch, so
# a re-invocation would defer forever (`init` mints a fresh nonce by design, wiping that evidence, dir
# #49's replay fix). Fix: `handoff` writes `handoff\tpolish.5\t<level>\t<HEAD-sha>` into the SAME
# sentinel at step 5(b) stop time; `init` preserves any `handoff` line across its nonce reset (nothing
# else survives `init`); `receipt polish.5-review <outcome>` clears it once the real receipt lands.
# `handoff-check` on a re-invocation tells step 5(c) whether the question was already asked for this
# EXACT diff (same HEAD SHA) — a match means collect the answer without re-deferring; any new commit
# invalidates the match (same-SHA-only replay window, not open-ended).

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

sentinel_path() { printf '/tmp/pre-pr-gate-%s' "$(basename "$(main_top_for "$PWD")")"; }

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

# Strip any `handoff\t...` line from sentinel $1, in place (no-op if the file or the line is absent).
_strip_handoff() {
  local sentinel="$1" tmp
  [ -f "$sentinel" ] || return 0
  tmp="$sentinel.tmp.$$"
  awk -F'\t' '$1!="handoff"' "$sentinel" > "$tmp" 2>/dev/null && mv "$tmp" "$sentinel"
}

case "${1:-}" in
  init)
    sentinel="$(sentinel_path)"
    # dir #63/Hole B: a handoff line records that step 5(b) already stopped to ask about THIS diff;
    # it must survive the nonce reset below (everything else — receipt lines from the prior run — is
    # meant to be discarded, that's the replay fix dir #49 built `init` for in the first place).
    handoff_line="$(awk -F'\t' '$1=="handoff"{print; exit}' "$sentinel" 2>/dev/null)"
    nonce="$(date -u +%Y%m%dT%H%M%S)-$$-$RANDOM"
    printf 'nonce\t%s\n' "$nonce" > "$sentinel"
    [ -n "$handoff_line" ] && printf '%s\n' "$handoff_line" >> "$sentinel"
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
    # dir #63/Hole B: the real receipt landing IS the answer step 5(b) was waiting on — the handoff's
    # job is done, so clear it rather than let a stale line linger past the question it recorded.
    [ "$step_id" = "polish.5-review" ] && _strip_handoff "$sentinel"
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
    sentinel="$(sentinel_path)"
    [ -f "$sentinel" ] || : > "$sentinel"
    _strip_handoff "$sentinel"
    printf 'handoff\tpolish.5\t%s\t%s\n' "$level" "$sha" >> "$sentinel"
    exit 0
    ;;
  handoff-check)
    sentinel="$(sentinel_path)"
    if [ -f "$sentinel" ]; then
      sha="$(git rev-parse HEAD 2>/dev/null)"
      line="$(awk -F'\t' -v sha="$sha" '$1=="handoff" && $4==sha{print}' "$sentinel")"
      if [ -n "$line" ]; then printf '%s\n' "$line"; exit 0; fi
    fi
    exit 1
    ;;
  skill-trace)
    # PostToolUse(Skill) or UserPromptExpansion(code-review) hook — see the dir #63 header section.
    # Never blocks or alters anything: silently no-ops (exit 0) on anything it can't parse or that
    # isn't a code-review invocation, since a missed trace is a residual limit, not a false deny.
    command -v jq >/dev/null 2>&1 || exit 0
    st_input=$(cat 2>/dev/null)
    st_event=$(printf '%s' "$st_input" | jq -r '.hook_event_name // empty' 2>/dev/null)
    st_cwd=$(printf '%s' "$st_input" | jq -r '.cwd // empty' 2>/dev/null)
    [ -n "$st_cwd" ] || st_cwd="$PWD"
    case "$st_event" in
      PostToolUse)
        [ "$(printf '%s' "$st_input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Skill" ] || exit 0
        st_skill=$(printf '%s' "$st_input" | jq -r '.tool_input.skill // empty' 2>/dev/null)
        st_level=$(printf '%s' "$st_input" | jq -r '.tool_input.args // empty' 2>/dev/null)
        ;;
      UserPromptExpansion)
        st_skill=$(printf '%s' "$st_input" | jq -r '.command_name // empty' 2>/dev/null)
        st_level=$(printf '%s' "$st_input" | jq -r '.command_args // empty' 2>/dev/null)
        ;;
      *) exit 0 ;;
    esac
    case "$st_skill" in
      code-review|*:code-review) ;;
      *) exit 0 ;;
    esac
    st_sha=$(git -C "$st_cwd" rev-parse HEAD 2>/dev/null)
    [ -n "$st_sha" ] || exit 0
    st_wt="$(basename "$(main_top_for "$st_cwd")")"
    printf '%s\t%s\n' "$st_sha" "$st_level" >> "/tmp/pre-pr-gate-trace-$st_wt"
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
wt=$(basename "$(main_top_for "$cwd")")
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
    if (missing == "") { print "PASS\t" val["polish.8-unlock"] "\t" val["polish.5-review"]; exit }
    if (replay != "") { print "REPLAY\t" missing; exit }
    print "MISSING\t" missing
  }
' "$sentinel")"

status="${result%%$'\t'*}"
rest="${result#*$'\t'}"
detail="${rest%%$'\t'*}"
review_outcome="${rest#*$'\t'}"

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
    # dir #63/Hole A: a BARE review outcome (no -operator-run/-waived suffix, not skip) claims a real
    # in-session /code-review run — cross-check the mechanically-written trace (skill-trace, above) so
    # that claim can't be satisfied by self-report alone. Trusted outcomes (skip, *-operator-run,
    # *-waived) need no trace — they already name a different, non-fabricable source (the human, or a
    # deliberate no-review choice).
    case "$review_outcome" in
      skip|*-operator-run|*-waived) ;;
      *)
        trace_path="/tmp/pre-pr-gate-trace-$wt"
        if [ ! -f "$trace_path" ] || ! awk -F'\t' -v sha="$current_sha" '$1==sha{f=1} END{exit !f}' "$trace_path"; then
          rm -f "$sentinel"
          log_event receipt-deny "review-trace-missing" "$cwd"
          deny "Pre-PR gate: step 5 recorded review outcome '$review_outcome' as an in-session /code-review run, but no matching trace was found for this commit. If the skill was genuinely unavailable, /polish's hand-off should have produced an -operator-run/-waived outcome instead. Run /polish again."
        fi
        ;;
    esac
    rm -f "$sentinel"
    log_event receipt-pass "" "$cwd"
    exit 0
    ;;
esac

# Fail-safe: any unrecognized status denies rather than silently allowing.
rm -f "$sentinel"
deny "Pre-PR gate: could not verify the receipt. Run /polish again."
