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
# dir #647: drop an inherited repo selector before the `repo_top` resolution below can be hijacked into
# answering for a different repo (the hijack shape is in keel-check.sh's comment on its copy of this line).
# Above `command -v jq` because this hook fires on EVERY Bash call: a builtin `unset` costs nothing there,
# a sourced guard that failed to load would fail silently (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# dir #511: shell-aware match. The first version compared the command's literal prefix, so `git -C . commit`
# or `true && git commit` slipped past while the check was red. kcg_artifact_cmd (below) walks the command
# as a shell would split it: quote-aware, a new simple command after an unquoted `;` `&` `|` `(` `)`
# backtick or newline, leading `VAR=val` words and common wrappers (`sudo`, `env`, `time`, `command` ...)
# skipped, `git`'s global options (`-C dir`, `-c k=v`, `--git-dir=...`) tolerated, and the verb read from
# the first real word. A command that only MENTIONS the words (`git log --grep="git commit"`,
# `echo "gh pr create"`) is not an artifact command and stays allowed.
#
# RESIDUAL (stated, not closed): this is a workflow floor that reads the command TEXT, not a sandbox. A
# command whose verb is built at run time (a variable, an alias, a git alias, text handed to another
# interpreter or `eval`) is not recognised. Closing that is the secret boundary's job, not this hook's.
# Likewise a command substitution inside double quotes (`out="$(git commit -m x)"`) is read as text, not
# walked, so it is not recognised either.
# In the other direction the walk errs toward blocking: a line inside a heredoc body that starts with the
# words reads as a command, because every newline starts a new simple command.

# kcg_artifact_cmd CMD — exit 0 when some simple command in CMD is `git commit` or `gh pr create`.
kcg_artifact_cmd() {
  local s="$1" i=0 n c q="" word="" inword=0 w
  local -a words=()
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    i=$((i + 1))
    if [ "$q" = "'" ]; then
      if [ "$c" = "'" ]; then q=""; else word="$word$c"; fi
      continue
    elif [ "$q" = '"' ]; then
      case "$c" in
        '"') q="" ;;
        \\) word="$word${s:$i:1}"; i=$((i + 1)) ;;
        *) word="$word$c" ;;
      esac
      continue
    fi
    case "$c" in
      "'") q="'"; inword=1 ;;
      '"') q='"'; inword=1 ;;
      \\)
        if [ "${s:$i:1}" = $'\n' ]; then i=$((i + 1)); else word="$word${s:$i:1}"; inword=1; i=$((i + 1)); fi ;;   # backslash-newline joins lines
      ' '|'	')
        if [ "$inword" = 1 ]; then words+=("$word"); word=""; inword=0; fi ;;
      ';'|'&'|'|'|'('|')'|'`'|'
')
        if [ "$inword" = 1 ]; then words+=("$word"); word=""; inword=0; fi
        if [ "${#words[@]}" -gt 0 ]; then
          kcg_simple_is_artifact "${words[@]}" && return 0
          words=()
        fi ;;
      *) word="$word$c"; inword=1 ;;
    esac
  done
  if [ "$inword" = 1 ]; then words+=("$word"); fi
  [ "${#words[@]}" -gt 0 ] && kcg_simple_is_artifact "${words[@]}" && return 0
  return 1
}

# kcg_simple_is_artifact WORD... — one simple command, already split into words.
kcg_simple_is_artifact() {
  local w tool="" stage=0
  for w in "$@"; do
    if [ -z "$tool" ]; then
      if [ "$stage" = skip ]; then stage=0; continue; fi
      case "$w" in
        [A-Za-z_]*=*) continue ;;                                  # VAR=val prefix
        '{'|'}'|'!'|then|do|else|elif|if|while|until|time|command|builtin|exec|sudo|env|nice|nohup) continue ;;
        -u|-g|-n|-C|-D|-U|-r|-t|-h|-S) stage=skip; continue ;;     # a wrapper option that takes a value
        -*) continue ;;                                            # a wrapper's own option
        git|*/git) tool=git ;;
        gh|*/gh) tool=gh ;;
        *) return 1 ;;
      esac
      continue
    fi
    if [ "$stage" = skip ]; then stage=0; continue; fi            # the value of -C / -c / -R / ...
    case "$tool:$w" in
      git:-C|git:-c|git:--git-dir|git:--work-tree|git:--namespace|git:--super-prefix|git:--config-env|git:--exec-path) stage=skip ;;
      git:-*) ;;                                                   # other global option, incl. --opt=value
      git:commit) return 0 ;;
      git:*) return 1 ;;
      gh:-R|gh:--repo|gh:--hostname) stage=skip ;;
      gh:-*) ;;
      gh:pr) tool=ghpr ;;
      gh:*) return 1 ;;
      ghpr:-R|ghpr:--repo) stage=skip ;;
      ghpr:-*) ;;
      ghpr:create) return 0 ;;
      ghpr:*) return 1 ;;
    esac
  done
  return 1
}

# Fast-exit: only the artifact-producing commands are the gate's business. The cheap substring test
# first (this hook fires on every Bash call). The shell-aware walk is the LAST decision, below: it runs
# only when the veto is on AND a red check exists, so a wired hook with the veto off (the default) never
# pays for it. COST of that last case: the walk is a per-character bash loop and quadratic in the
# command's length (each ${s:$i:1} copies the string) — measured 21-26 s on a 105 KB command containing
# the words (see the PR for dir #511). Only a very large command with a red check enforced is slow.
case "$cmd" in
  *commit*|*create*) ;;
  *) exit 0 ;;
esac

# OFF unless explicitly enabled for this session.
[ -z "${KEEL_CHECK_VETO:-}" ] && exit 0

# Sourced here, not at the top: this hook fires on EVERY Bash call in a wired repo, and the two
# fast-exits above already dispose of the overwhelming majority of invocations (any command without the
# words, and every command when the opt-in veto is off, its default) — paying for an
# extra file read/parse before either of those checks would tax every one of them for a lib only the
# rare surviving invocation needs (found by this ticket's own /simplify pass, efficiency angle).
_kcg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/gate-paths.sh
. "$_kcg_dir/lib/gate-paths.sh"
unset _kcg_dir

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
repo_top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
repo_key="$(printf '%s' "$repo_top" | cksum | tr -cd '0-9')"
# Fixed (not $TMPDIR) so this hook and keel-check.sh — separate processes with possibly different
# $TMPDIR — always resolve the same state path; a mismatch would make the veto silently never fire.
# dir #398/#399/#637: the default moved off shared /tmp to the keel-owned root, same as
# keel-check.sh. This hook is fail-OPEN by design (see the jq check above) — an explicit override
# still wins; a genuinely unresolvable default (HOME unset/empty) means "nothing to veto", not a
# denial, matching every other "can't tell" branch in this file.
if [ -n "${KEEL_CHECK_STATE_DIR:-}" ]; then
  state_dir="$KEEL_CHECK_STATE_DIR"
else
  state_dir="$(gate_state_root)" || exit 0
fi
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
  # dir #511: only now, with a red check to enforce, decide whether this is an artifact command.
  kcg_artifact_cmd "$cmd" || exit 0
  deny "keel-check gate: a check you declared for this repo is still failing. Re-run it green through keel-check before committing — repeated failure is a missing cause, not a missing attempt."
fi
exit 0
