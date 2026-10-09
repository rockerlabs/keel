#!/usr/bin/env bash
# test_pre_pr_gate_lexer.sh — what the pre-PR gate's hook reads out of a command line (dir #745).
#
# tools/pre-pr-gate.sh is a Claude Code PreToolUse(Bash) hook: it reads a JSON event on stdin and emits a JSON
# allow/deny decision (always exit 0; empty stdout = allow). This file holds the tests of its LEXER's verdicts —
# first the dir #731 A18 block (the bypassed-push deny), moved here from tests/test_pre_pr_gate.sh by dir #745
# so one file is the net the lexer rewrite is measured by, and the file tools/self/mutation-sweep.sh runs per
# mutant of tests/mutants/pre-pr-gate.tsv. Every deny here asserts the push rule's OWN reason text, not just
# "some deny": a mutant that makes a different rule deny must not count as caught.
#
# The hook is fed JSON events only — nothing here runs a push.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

gate="$REPO_ROOT/tools/pre-pr-gate.sh"
check_file "pre-pr-gate.sh exists" "$gate"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — pre-pr-gate lexer tests skipped (gate requires jq to parse its event)"
  summary; exit $?
fi

# A git repo with one commit; prints its path.
mkrepo() {
  local d; d="$(new_repo)"
  git -C "$d" commit --allow-empty -qm init
  printf '%s' "$d"
}

# Drive the gate: $1 = command string, $2 = cwd. Captures OUT (stdout+stderr) and STATUS. (The same two
# helpers as tests/test_pre_pr_gate.sh; the gate's other fixtures live in lib.sh.)
gate_env() {
  local json
  json="$(jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, cwd:$d}')"
  shift 2
  OUT="$(printf '%s' "$json" | env "$@" bash "$gate" 2>&1)"
  STATUS=$?
}
gate() { gate_env "$1" "$2"; }

# --- dir #731 A18 (docs/specs/717-machine-guard-truth.md B15): a `git push` segment that carries a bypass of
# the pre-push secret scan is denied in ANY repo, with or without a `gh pr create` in the command. The hook is
# fed JSON events only — nothing here runs a push. ---------------------------------------------------------
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")"
push_deny() {
  gate "$1" "$d"
  check_status "dir #731 A18: [$1] exits 0 (the hook always does)" 0 "$STATUS"
  check_contains "dir #731 A18: [$1] → deny" "$OUT" '"permissionDecision":"deny"'
  check_contains "dir #731 A18: [$1] → the push rule's own reason (dir #745)" "$OUT" "pre-push secret scan"
}
push_allow() {
  gate "$1" "$d"
  check_status "dir #731 A18: [$1] exits 0" 0 "$STATUS"
  check_eq "dir #731 A18: [$1] → allowed, no output" "" "$OUT"
}
push_deny 'git -c core.hooksPath= push origin main'
push_deny 'git push --no-verify origin main'
push_deny 'git -c CORE.HOOKSPATH=/dev/null push'
push_deny 'git --config-env=core.hooksPath=X push'
push_deny 'env A=1 git -c core.hooksPath= push'
push_deny 'git -C /x -c core.hooksPath push'
push_deny 'true && git push --no-verify'
push_deny 'git push --no-verif origin main'
push_deny 'git push --no-veri origin main'
push_deny 'git --config-env core.hooksPath=X push'
push_deny 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0= git push'
push_deny '/usr/bin/git push --no-verify'
push_deny 'GIT_CONFIG_GLOBAL=/dev/null git push origin main'
push_deny 'HOME=/tmp/x git push origin main'
push_deny 'if git push --no-verify; then :; fi'
push_deny '{ git push --no-verify; }'
push_deny 'time git push --no-verify'
push_deny 'env -u FOO git push --no-verify'
push_deny '! git push --no-verify'
push_deny 'git push --no-verify && gh pr create --fill'
# dir #745 A5 (S7-2): one deny per clause the baseline block left unguarded — each skip-set word, each wrapper,
# each redirecting variable — as the full shell command, so a mutant that drops the clause turns one red.
push_deny 'if true; then git push --no-verify; fi'
push_deny 'if false; then :; elif git push --no-verify; then :; fi'
push_deny 'if false; then :; else git push --no-verify; fi'
push_deny 'for x in a; do git push --no-verify; done'
push_deny 'while git push --no-verify; do :; done'
push_deny 'until git push --no-verify; do :; done'
push_deny 'nohup git push --no-verify'
push_deny 'exec git push --no-verify'
push_deny 'xargs git push --no-verify'
push_deny 'command git push --no-verify'
push_deny 'command -p git push --no-verify'
push_deny 'env GIT_CONFIG_GLOBAL=/dev/null git push'
push_deny 'env --unset FOO git push --no-verify'
push_deny 'GIT_CONFIG_SYSTEM=/dev/null git push'
push_deny 'GIT_CONFIG_NOSYSTEM=1 git push'
push_deny "GIT_CONFIG_PARAMETERS=\"'core.hookspath=/dev/null'\" git push"
push_deny 'XDG_CONFIG_HOME=/tmp/x git push'
gate "git push --no-verify" "$d"
check_contains "dir #731 A18: the deny reason names the pre-push secret scan" "$OUT" "pre-push secret scan"
push_allow 'git push origin main'
push_allow 'git -c core.hooksPath= commit -m x'
push_allow "$(printf 'cat <<EOF\ngit push --no-verify\nEOF')"
push_allow 'echo "git push --no-verify"'
push_allow "git commit -m 'git push --no-verify'"
push_allow 'git pull --no-verify'
push_allow 'git commit --no-verify -m x && git push origin main'
push_allow 'git push --no-ver'
push_allow 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=x git push'

summary
