#!/usr/bin/env bash
# test_pre_pr_gate_lexer.sh — what the pre-PR gate's hook reads out of a command line (dir #745).
#
# tools/pre-pr-gate.sh is a Claude Code PreToolUse(Bash) hook: it reads a JSON event on stdin and emits a JSON
# allow/deny decision (always exit 0; empty stdout = allow). This file holds the tests of its command READER —
# the dir #731 A18 block (the bypassed-push deny, moved here from tests/test_pre_pr_gate.sh), every verdict row
# of dir #745's case table (`hook:<id>`), the reader's own output through `pre-pr-gate.sh lex` (`lex:…`), its
# fail-closed paths (`shim:…`) and the header's residual list. It is the file tools/self/mutation-sweep.sh runs
# per mutant of tests/mutants/pre-pr-gate.tsv, so every clause of the reader must be killable from here alone.
# Every deny asserts its OWN reason text, not just "some deny": a mutant that makes a different rule deny must
# not count as caught.
#
# The hook is fed JSON events only — nothing here runs a push.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

gate="$REPO_ROOT/tools/pre-pr-gate.sh"
check_file "pre-pr-gate.sh exists" "$gate"
# Which awk read the commands: the reader must agree across macOS awk, busybox awk, mawk and gawk, so a CI log
# names the one each leg ran (captured, never piped into head — the dir #280 SIGPIPE race).
awk_path="$(type -P awk)"; awk_real="$(readlink -f "$awk_path" 2>/dev/null || printf '%s' "$awk_path")"
awk_ver="$(awk --version 2>&1)"; awk_ver="${awk_ver%%$'\n'*}"
pass "the reader runs under awk: $awk_real (${awk_ver:-no --version})"

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

# Drive the gate: $1 = command string, $2 = cwd, $3… extra `env` assignments. Captures OUT (stdout+stderr) and
# STATUS. (The same event shape as tests/test_pre_pr_gate.sh's gate_env(); the gate's other fixtures live in lib.sh.)
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

# --- dir #745: every row of the case table, through the hook --------------------------------------------------
# One record per command: `@ <id> <verdict>`, then the command's lines verbatim (trailing blanks are part of some
# commands — N24's `E ` — so keep them). Verdicts: push (the push deny's reason), refuse (the refusal's opening),
# pr (the receipt check's no-receipt deny, in a repo with no receipt), allow (no output). Ids: C… the case table,
# N… the rows the mutation leg added (C100–C121), P… leg 3's (P1 C122, P2 C123, P3 C124, P4/P10 C114b, P5 C56b,
# P6–P8 C77, P9 C73d, P11 C125). P3 (C124) is `push`, not the table's `refuse`: `${…}` closes at the first
# unquoted `}` (bash, busybox), so the push after it is a segment of its own, and a push outranks a refusal.
# P2 (C123) is `allow`, not the table's `refuse`: a heredoc-body line inside `$(…)` is refused only when its first
# non-blank character is `)` (bash 3.2 closes the `$(…)` there); `1) git push …` starts with `1`. Refusing every
# unbalanced `)` instead denied 390 habitual commit messages in the operator's corpus (wrapped parentheticals).
hd="$(mkrepo)"
rm -f "$(sentinel_for "$hd")"
verdict_of() {
  case "$OUT" in
    ""|*'"permissionDecision":"allow"'*) printf allow ;;
    *"pre-push secret scan"*) printf push ;;
    *"could not read this command reliably"*) printf refuse ;;
    *"the command reader failed"*) printf reader-failed ;;
    *"run /polish first"*) printf pr ;;
    *) printf 'other: %s' "$OUT" ;;
  esac
}
hook_case() {   # hook_case <id> <verdict> <command> [label prefix, default hook]
  gate "$3" "$hd"
  check_eq "${4:-hook}:$1 → $2" "$2" "$(verdict_of)"
}
case_id=""; case_v=""; case_cmd=""; case_open=0
while IFS= read -r line; do
  case "$line" in
    "@ "*)
      [ "$case_open" = 1 ] && hook_case "$case_id" "$case_v" "$case_cmd"
      line="${line#@ }"; case_id="${line%% *}"; case_v="${line#* }"; case_cmd=""; case_open=1; first=1
      ;;
    *)
      if [ "$first" = 1 ]; then case_cmd="$line"; first=0; else case_cmd="$case_cmd"$'\n'"$line"; fi
      ;;
  esac
done <<'CASES'
@ C1 push
VAR="x"y git push --no-verify
@ C2a pr
FOO="a"b gh pr create --fill
@ C2b pr
env FOO="a"b gh pr create --fill
@ C2c pr
PATH="$HOME/bin":$PATH gh pr create --fill
@ C3a push
HOME="$tmp"/x git push
@ C3b push
GIT_CONFIG_GLOBAL="$t/gc"/cfg git push
@ C3c push
a=$'x'y git push --no-verify
@ C4a push
git push "--no-verify"
@ C4b push
git push --no-"verify"
@ C4c push
git -c "core.hooksPath=/dev/null" push
@ C4d push
GIT_CONFIG_KEY_0="core.hooksPath" GIT_CONFIG_COUNT=1 git push
@ C4e push
env "GIT_CONFIG_GLOBAL=/dev/null" git push
@ C5 push
git commit -m "$(cat <<'X'
msg
X
)" && git push --no-verify
@ C6 pr
git commit -m "$(cat <<'X'
msg
X
)" && gh pr create --fill
@ C7a push
x=$((1<<2)); git push --no-verify
@ C7b push
x=$((1<<2))&&git push --no-verify
@ C7c pr
x=$((1<<2)); gh pr create --fill
@ C8a push
git commit -m "shift a << b" && git push --no-verify
@ C8b push
echo "<<" ; git push --no-verify
@ C8c push
echo "1 << 3 = 8"
git status
git push --no-verify
@ C9 push
cat <<A; git push --no-verify
x
A
@ C10a push
git push origin \
  --no-verify
@ C10b push
git \
 push --no-verify
@ C10c pr
gh pr \
 create --fill
@ C11a push
git push >&2 --no-verify
@ C11b push
git push 2>&1 --no-verify
@ C11c push
2>&1 git push --no-verify
@ C11d push
>/dev/null git push --no-verify
@ C11e push
git push &>/dev/null --no-verify
@ C12a push
echo "$(git push --no-verify)"
@ C12b push
cat <<E
$(git push --no-verify)
E
@ C13 pr
git commit -m "Run `gh pr create` after polish"
@ C14a pr
if gh pr create --fill; then :; fi
@ C14b pr
time gh pr create --fill
@ C14c pr
nohup gh pr create --fill
@ C14d pr
! gh pr create --fill
@ C14e pr
{ gh pr create --fill; }
@ C14f pr
env -u X gh pr create --fill
@ C15 push
cat <<E $(echo
git push --no-verify
)
body
E
@ C16 push
"git" push --no-verify
@ C20a allow
git commit -m "fix gate

git push --no-verify is now denied
"
@ C20b allow
echo "see:
git push --no-verify"
@ C20c allow
git commit -m 'x

git push --no-verify
'
@ C21 allow
git commit -m "x
gh pr create --fill
"
@ C22 allow
cat <<A <<B
a
A
git push --no-verify
B
@ C23 allow
"FOO=1" git push --no-verify
@ C24 allow
echo a # b; git push --no-verify
@ C25 allow
"if" gh pr create --fill
@ C32 push
HOME="/tmp/x" git push
@ C33 push
git commit -m "$(cat <<'X'
msg
X
)"
git push --no-verify
@ C34a allow
git commit -m 'git push --no-verify'
@ C34b allow
cat <<EOF
git push --no-verify
EOF
@ C34c allow
git commit -F - <<'EOM'
body
git push --no-verify
EOM
@ C35a allow
cat <<'E'
$(git push --no-verify)
E
@ C35b allow
cat <<-EOF
	git push --no-verify
	EOF
git push origin main
@ C35c allow
cat << 'A'
git push --no-verify
A
@ C36a push
echo hi # it's fine
git push --no-verify
@ C36b push
git push --no-verify # c
@ C36c push
echo 'a\'; git push --no-verify
@ C36d push
echo "a\"b" && git push --no-verify
@ C37 allow
# git push --no-verify
@ C38a push
echo $(git push --no-verify)
@ C38b push
echo `git push --no-verify`
@ C38c push
diff <(git push --no-verify) x
@ C39 allow
git commit -m "$(cat <<'EOF'
Fix the gate.

It now denies `git push --no-verify`.
EOF
)" && git push origin main
@ C40 pr
gh pr create --title "x" --body "$(cat <<'EOF'
## Summary
- uses git push --no-verify nowhere
EOF
)"
@ C41 push
X=$(case a in a) git push --no-verify;; esac)
@ C42a allow
git commit --no-verify -m "push"
@ C42b allow
gh pr comment 12 --body "create"
@ C45a push
$HOME/bin/git push --no-verify
@ C45b push
"$HOME"/bin/git push --no-verify
@ C46a push
\git push --no-verify
@ C46b push
"nohup" git push --no-verify
@ C47 push
git push << '' --no-verify
@ C50 refuse
echo ok
echo "open
git push --no-verify
@ C51 allow
echo "open
@ C52 refuse
X="$(cat <<E
msg
E)" && git push --no-verify
@ C53 refuse
cat <<E
body
git push --no-verify
@ C54 allow
cat <<E
body
@ C55 push
cat << ; git push --no-verify
@ C56 refuse
echo `a \`git push --no-verify\``
@ C58 allow
echo $(ls
@ C59 push
echo $(cat <<E)
git push --no-verify
E
@ C60 refuse
cat <<E
body
E\

git push --no-verify
E
@ C61 refuse
v=; echo "${v:-'}"'}"; git push --no-verify
@ C70a allow
sh -c 'git push --no-verify'
@ C70b allow
eval "git push --no-verify"
@ C71a allow
sudo git push --no-verify
@ C71b allow
timeout 60 git push --no-verify
@ C71c allow
env -C d git push --no-verify
@ C71d allow
/usr/bin/env HOME=/x git push
@ C72a allow
export GIT_CONFIG_GLOBAL=/dev/null && git push
@ C72b allow
git config core.hooksPath /dev/null && git push
@ C73a allow
$G push --no-verify
@ C73b allow
gh "pr" create --fill
@ C73c allow
git "push" --no-verify
@ C74 refuse
echo "$(case a in a) git push --no-verify;; esac)"
@ C74b refuse
echo ${v:-$(case x in x) ;; esac; git push origin main --no-verify)}
@ C74c refuse
cat <<E
$(case a in a) git push --no-verify;; esac)
E
@ C74d refuse
cat <<E
$(case a in a) gh pr create --fill;; esac)
E
@ C74e refuse
echo "${v:-$(case x in x) ;; esac; git push --no-verify)}"
@ C74f allow
echo "$(case $x in a) echo 1;; esac)"
@ C74g allow
x=$(case $1 in a) echo 1;; esac); git status
@ C74h allow
echo "$(echo case a in b)" && git status
@ C74i refuse
echo "$(if true; then case a in a) git push --no-verify;; esac; fi)"
@ C74k allow
echo "$(case)" && git status
@ C74l allow
echo "$("case" a in b)" && git status
@ C74j push
X=$(case a in a) git push --no-verify;; esac)
@ C75 push
arr=(git push --no-verify)
@ C76 push
GIT_CONFIG_GLOBAL=/dev/null git config alias.p push
@ C80a allow

@ C80b allow
   
@ C80c allow
# only a comment
@ N1a allow
cat > notes.md <<'EOF' && git add notes.md && git commit -m "docs: x

body"
content
EOF
@ N1b push
cat <<'E' "
$(git push --no-verify)
E
"
@ N2 push
cat <<A <<'B'
$(git push --no-verify)
A
B
@ N3a allow
(cd /x && git commit -m "$(cat msg)") && git push origin main
@ N3b push
echo "$( (cd a && make) && git push --no-verify )"
@ N4 push
git commit -F - <<EOF
It now denies `git push --no-verify`.
EOF
@ N5 push
git commit -m fix#12 && git push --no-verify
@ N6a push
nohup env HOME=/tmp/x git push
@ N6b pr
command nohup gh pr create --fill
@ N7 push
if ! git push --no-verify; then :; fi
@ N8 push
env -uX git push --no-verify
@ N9 push
env HOME="$tmp"/x git push
@ N10a push
nohup time git push --no-verify
@ N10b push
env time git push --no-verify
@ N10c push
FOO=1 time git push --no-verify
@ N11 refuse
X="$(cat <<E
msg
E)" && gh pr create --fill
@ N12 refuse
gh pr create --fill && X="$(cat <<E
msg
E)" && git push --no-verify
@ N13a push
"/usr/bin/git" push --no-verify
@ N13b pr
"gh" pr create --fill
@ N13c push
git "-c" core.hooksPath= push
@ N14a pr
gh api "repos/o/r/pulls" -f head=x -f base=main
@ N14b pr
gh api repos/$R/pulls -f head=x
@ N17a push
> /dev/null git push --no-verify
@ N17b push
echo x >"$(git push --no-verify)"
@ N18a push
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hookspath GIT_CONFIG_VALUE_0= git push
@ N18b push
git --config-env=CORE.HOOKSPATH=X push
@ N19 push
HOME+=/x git push
@ N20a push
git push --no-\
verify
@ N20b push
git push "--no-\
verify"
@ N21a refuse
cat << ; git status
@ N21b refuse
echo $(cat <<E)
git status
E
@ N22a refuse
cat <<E
$(cat <<F
x
F
)
git status
E
@ N23a allow
git status; echo "open
@ N23b refuse
git commit -m "msg
@ N24 allow
cat <<E
E 
git push --no-verify
E
@ N25 allow
git commit -m $'it\'s fixed' && git push origin main
@ N29 allow
git log <<E
@ N31 push
{fd}>/dev/null git push --no-verify
@ N32 pr
x=$[1<<2]; gh pr create --fill
@ P1 refuse
((cd a && git push --no-verify) && (true))
@ P2 allow
MSG=$(cat <<'EOF'
1) git push --no-verify
EOF
)
@ P3 push
v=; echo ${v:-{}; git push --no-verify; echo }
@ P4 push
time -p git push --no-verify
@ P5 refuse
echo `echo "\`git push --no-verify\`"`
@ P6 allow
if [[ -n x ]] git push --no-verify
@ P7 allow
repeat 1 git push --no-verify
@ P8 allow
function f { git push --no-verify; }; f
@ P9 allow
/opt/homebrew/bin/gh pr create --fill
@ P10 push
a[1]=x git push --no-verify
@ N22c refuse
cat <<E
$(git status
E
@ P11 allow
git commit -m "$(cat <<'EOF'
Fix: don't break it
EOF
)" && git push origin main
CASES
[ "$case_open" = 1 ] && hook_case "$case_id" "$case_v" "$case_cmd"

# --- dir #745: what `lex` prints (the reader's observable form) -----------------------------------------------
# One line per segment in the order segments END (a nested one first): `<context>@<line>`, `d<depth>`,
# `s<scope>`, `p<offset>`, then `<classes>:<text>` per word (classes in the order u q x g); then one line per
# region the reader could not read alike in every shell. Fields are TAB-separated.
T=$'\t'
lex_out() { OUT="$(printf '%s' "$1" | bash "$gate" lex 2>&1)"; STATUS=$?; }   # lex_out <command> → OUT, STATUS
lex_is() {   # lex_is <label> <command> <expected output>
  lex_out "$2"
  check_eq "lex:$1" "$3" "$OUT"
}
lex_is "partly quoted prefix assignment" 'VAR="x"y git push' "TOP@1${T}d0${T}s0${T}p1${T}uq:VAR=xy${T}u:git${T}u:push"
lex_is "heredoc commit: the SUB segment ends first" "$(printf 'git commit -m "$(cat <<'"'"'X'"'"'\nm\nX\n)"')" \
  "SUB@1${T}d1${T}s0.1${T}p18${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:git${T}u:commit${T}u:-m${T}x:\$()"
lex_is "two groups" '(a); (b)' "TOP@1${T}d0${T}s0.1${T}p2${T}u:a"$'\n'"TOP@1${T}d0${T}s0.2${T}p7${T}u:b"
lex_is "nested groups" '( (a) )' "TOP@1${T}d0${T}s0.1.2${T}p4${T}u:a"
lex_is "a group's segments, then the next" '(cd /x && git init); git status' \
  "TOP@1${T}d0${T}s0.1${T}p2${T}u:cd${T}u:/x"$'\n'"TOP@1${T}d0${T}s0.1${T}p11${T}u:git${T}u:init"$'\n'"TOP@1${T}d0${T}s0${T}p22${T}u:git${T}u:status"
lex_is "an unclosed double quote" 'echo "open' "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}q:open"$'\n'"refuse${T}unclosed DQ${T}line 1${T}scope:no"
lex_is "--head taken from a substitution" 'gh pr create --head "$(git branch --show-current)"' \
  "SUB@1${T}d1${T}s0.1${T}p24${T}u:git${T}u:branch${T}u:--show-current"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:gh${T}u:pr${T}u:create${T}u:--head${T}x:\$()"
lex_is "a SUB inside a group" '(cd /x && git commit -m "$(cat msg)") && git push origin main' \
  "TOP@1${T}d0${T}s0.1${T}p2${T}u:cd${T}u:/x"$'\n'"SUB@1${T}d1${T}s0.1.2${T}p28${T}u:cat${T}u:msg"$'\n'"TOP@1${T}d0${T}s0.1${T}p11${T}u:git${T}u:commit${T}u:-m${T}x:\$()"$'\n'"TOP@1${T}d0${T}s0${T}p42${T}u:git${T}u:push${T}u:origin${T}u:main"
lex_is "an expansion glued to text" 'git -C $HOME/x status' "TOP@1${T}d0${T}s0${T}p1${T}u:git${T}u:-C${T}ux:\$HOME/x${T}u:status"
lex_is "a glob" 'ls *.md' "TOP@1${T}d0${T}s0${T}p1${T}u:ls${T}ug:*.md"
lex_is "a quoted expansion glued to a path" '"$HOME"/bin/git push' "TOP@1${T}d0${T}s0${T}p1${T}ux:\$HOME/bin/git${T}u:push"
lex_is "a quoted command word" '"git" status' "TOP@1${T}d0${T}s0${T}p1${T}q:git${T}u:status"
lex_is "backticks" 'echo `git status`' "BQ@1${T}d1${T}s0.1${T}p7${T}u:git${T}u:status"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"
lex_is "a TAB and a backslash print escaped" "echo \"a${T}b\" 'x\\y'" "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}q:a\\tb${T}q:x\\\\y"
lex_is "a terminator glued to ): two regions in source order" "$(printf 'X="$(cat <<E\nmsg\nE)" && git push --no-verify')" \
  "SUB@1${T}d1${T}s0.1${T}p6${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}ux:X=\$()"$'\n'"refuse${T}unclosed DQ${T}line 1${T}scope:yes"$'\n'"refuse${T}heredoc E not closed${T}line 2${T}scope:yes"
want_home="$(printf 'VAR="x"y git push' | bash "$gate" lex 2>&1)"
OUT="$(printf 'VAR="x"y git push' | env -u HOME bash "$gate" lex 2>&1)"; STATUS=$?
check_status "lex:HOME unset → exit 0" 0 "$STATUS"
check_eq "lex:HOME unset → the same output" "$want_home" "$OUT"
OUT="$(bash "$gate" lex extra </dev/null 2>&1)"; STATUS=$?
check_status "lex:an argument after lex → exit 2" 2 "$STATUS"
check_contains "lex:…with the usage on stderr" "$OUT" "usage: pre-pr-gate.sh lex"

# --- dir #745: the refusal names its reason; it is logged ----------------------------------------------------
gate "$(printf 'X="$(cat <<E\nmsg\nE)" && git push --no-verify')" "$hd"
check_contains "hook:C52 → the reason is the first refusing region" "$OUT" "unclosed DQ (line 1)"
check_contains "hook:C52 → the deny never says to bypass the gate; it says what to do" "$OUT" "run the git/gh step as its own Bash call"
gate 'v=; echo "${v:-'"'"'}"'"'"'}"; git push --no-verify' "$hd"
check_contains "hook:C61 → the reason" "$OUT" 'quote inside ${…} in double quotes (line 1)'
imp_log="$SANDBOX/impact-745.log"
gate_env "$(printf 'echo ok\necho "open\ngit push --no-verify')" "$hd" "KEEL_IMPACT_LOG=$imp_log"
check_eq "hook:C50 (with the impact log on) → refuse" refuse "$(verdict_of)"
check_contains "hook:C50 → a guard refused line in the impact log" "$(cat "$imp_log" 2>/dev/null)" "${T}guard${T}pre-pr-gate${T}refused${T}"

# --- dir #745: C44 on the receipt path — `--head` read from a quoted word; never from a substitution ------------
rd="$(mkrepo)"
rd_main="$(git -C "$rd" branch --show-current)"
git -C "$rd" branch feat-x >/dev/null 2>&1
git -C "$rd" checkout -q feat-x
write_full_receipt "$rd"
git -C "$rd" checkout -q "$rd_main"
gate 'gh pr create --head "feat-x" --title t' "$rd"
check_eq "rcpt:C44a → a full receipt for feat-x, cwd on another branch, --head \"feat-x\" → allow" allow "$(verdict_of)"
rm -f "$(sentinel_for "$rd")"
write_full_receipt "$rd"
gate 'gh pr create --head "$(git branch --show-current)"' "$rd"
check_eq "rcpt:C44b → a full receipt for the cwd's branch, --head from a substitution (no head taken) → allow" allow "$(verdict_of)"
rm -f "$(sentinel_for "$rd")"
# the head is the last PR-opening segment's: an earlier segment's --head never carries over to one with no head taken
rd="$(mkrepo)"
rd_main="$(git -C "$rd" branch --show-current)"
git -C "$rd" branch feat-x >/dev/null 2>&1
git -C "$rd" checkout -q feat-x
write_full_receipt "$rd"
git -C "$rd" checkout -q "$rd_main"
gate 'gh pr create --head feat-x --dry-run; gh pr create --head "$(git branch --show-current)" --fill' "$rd"
check_eq "rcpt:an earlier segment's --head feat-x, the last's from a substitution → the cwd's branch, no receipt → pr" pr "$(verdict_of)"
gate 'gh api repos/o/r/pulls -f head=feat-x; gh api repos/o/r/pulls -f head="$h" -f base=main' "$rd"
check_eq "rcpt:an earlier gh api head=feat-x, the last's head unreadable → the cwd's branch, no receipt → pr" pr "$(verdict_of)"
gate 'gh pr create --head feat-x --dry-run; gh pr create --head feat-x --fill' "$rd"
check_eq "rcpt:…and with the last segment's own --head feat-x → allow" allow "$(verdict_of)"

# --- dir #745: one skip set — both matchers start at cmd_start() (A9) -------------------------------------------
for fn in check_push check_segment; do
  body="$(awk "/^function $fn\\(/,/^}/" "$gate")"
  check_ne "skip set: $fn's body is found" "" "$body"
  check_contains "skip set: $fn calls cmd_start()" "$body" "cmd_start("
  check_absent "skip set: $fn has no skip loop of its own (is_shellword)" "$body" "is_shellword("
  check_absent "skip set: $fn names no wrapper itself (env)" "$body" '"env"'
  check_absent "skip set: $fn names no wrapper itself (command)" "$body" '"command"'
done

# --- dir #745: the reader fails closed — every malformed output denies git/gh and allows the rest (A10) ---------
# A PATH-shimmed `awk` stands in for the reader only (its program is recognised by a function name); every other
# awk call the gate makes reaches the real one.
real_awk="$(type -P awk)"
shim_case() {   # shim_case <label> <exit status> <printf format the fake reader prints>
  local dir="$SANDBOX/shim-$1"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\ncase "$*" in *lex_main*) printf '"'"'%s'"'"'; exit %s ;; esac\nexec %s "$@"\n' "$3" "$2" "$real_awk" >"$dir/awk"
  chmod +x "$dir/awk"
  gate_env 'git status' "$hd" "PATH=$dir:$PATH" "KEEL_IMPACT_LOG=$SANDBOX/shim-$1.log"
  check_contains "shim:$1 git status → denied, the reader failed (awk exit $2)" "$OUT" "the command reader failed (awk exit $2)"
  check_contains "shim:$1 git status → a guard reader-failed line" "$(cat "$SANDBOX/shim-$1.log" 2>/dev/null)" "${T}reader-failed${T}"
  gate_env 'gh pr create --fill' "$hd" "PATH=$dir:$PATH"
  check_contains "shim:$1 gh pr create → denied, the reader failed" "$OUT" "the command reader failed (awk exit $2)"
  gate_env 'ls' "$hd" "PATH=$dir:$PATH"
  check_eq "shim:$1 ls → allowed" "" "$OUT"
  gate_env 'grep -c x f' "$hd" "PATH=$dir:$PATH"
  check_eq "shim:$1 a command with a g but no git/gh → allowed" "" "$OUT"
}
shim_case exit2 2 ''
shim_case bogus 0 'bogus\037\037\n'
shim_case two-verdicts 0 'pr\037\037\npr\037\037\n'
shim_case silent-success 0 ''
shim_case line-with-exit1 1 'push\037\037\n'

# --- dir #745: the header's residual paragraph tells the truth (B18) -------------------------------------------
gate_head="$(sed -n '1,/^# CLI subcommands/p' "$gate")"
for kept in "\`sh -c '…'\`" '`eval "…"`' '`gh "pr" create`' "an array assignment's" '`repeat N cmd`' \
  '`function NAME { … }`' 'a path to `gh`' "bash 3.2's misreading" '`git push {--no-verify,}`' '`--no-verify$(true)`' \
  "a wrapper's own flags" '`noglob`' '`coproc`' '`{cmd}`' 'an env argument whose' '`sudo`' '`timeout`' '`env -C`' '`/usr/bin/env …`' '`exec -a x`' \
  '`xargs -r`' '`nohup --`' '`git "push"`' '`gh pr new`' '`gh api graphql`' 'a second PR-opening command' '`env -u HOME`' '`a[$i]=1 git …`' '`if [[ … ]] cmd`' 'a `git config` write' 'a variable exported earlier' 'REFUSES'; do
  check_contains "header: names the residual or rule [$kept]" "$gate_head" "$kept"
done
for dropped in "a \`case\` pattern's" 'backslash-newline continuation' 'partly quoted prefix assignment' 'docs/specs/717' 'the lexer fix is dir #745'; do
  check_absent "header: no longer names [$dropped]" "$gate_head" "$dropped"
done

# --- dir #745: the mutation net — one case per reader clause the case table does not reach alone ----------------
# Each is here so a single-clause mutant of tests/mutants/pre-pr-gate.tsv has a test to fail.
net() { hook_case "$1" "$2" "$3" net; }   # net <label> <verdict> <command>
net "quoted api is not the subcommand" allow 'gh "api" repos/o/r/pulls -f head=x'
net "a pulls list is a read" allow 'gh api repos/o/r/pulls'
net "-X POST" pr 'gh api -X POST repos/o/r/pulls'
net "--method POST" pr 'gh api --method POST repos/o/r/pulls'
net "--method=POST" pr 'gh api --method=POST repos/o/r/pulls'
net "-X GET with a field is a read" allow 'gh api -X GET repos/o/r/pulls -f state=open'
net "-F" pr 'gh api repos/o/r/pulls -F head=x'
net "--field" pr 'gh api repos/o/r/pulls --field head=x'
net "--raw-field" pr 'gh api repos/o/r/pulls --raw-field head=x'
net "--input" pr 'gh api repos/o/r/pulls --input body.json'
net "a field on one PR is not a create" allow 'gh api repos/o/r/pulls/123 -f body=x'
net "quoted create" allow 'gh pr "create" --fill'
net "pr before create" allow 'gh create pr'
net "env NAME with an expansion is the command" allow 'env $X=1 git push --no-verify'
net "time wrapper takes -p" push 'nohup time -p git push --no-verify'
net "\\\" in backticks inside double quotes is a quote" allow 'echo "`echo \"a && git push --no-verify\"`"'
net "( raises the arithmetic depth" pr 'x=$(( (1+2) )); gh pr create --fill'
net "a backslash in \${…} escapes" pr 'echo ${v:-\{}; gh pr create --fill'
net "a double quote in \${…}" pr 'echo ${v:-"}"}; gh pr create --fill'
net "an ANSI quote in \${…}" pr "echo \${v:-\$'}'}; gh pr create --fill"
net "a single quote in \${…} outside double quotes" pr "echo \${v:-'}'}; gh pr create --fill"
net "a substitution in \${…}" push 'echo ${v:-$(git push --no-verify)}'
net "an escaped \$ in a heredoc body" allow "$(printf 'cat <<E\n\\$(git push --no-verify)\nE')"
net "a redirect with no target" push 'echo > ; git push --no-verify'
net "a heredoc delimiter made of a substitution" push "$(printf 'cat <<$(x)\ntext\n$(x)\ngit push --no-verify')"
net "an unquoted { in \${…} refuses" refuse 'v=; echo ${v:-{}; gh pr create --fill'
net "a quoted delimiter part makes the body literal" allow "$(printf 'cat <<E"F"\n$(git push --no-verify)\nEF')"
net "a backslash in the delimiter makes the body literal" allow "$(printf 'cat <<\\E\n$(git push --no-verify)\nE')"
net "arithmetic inside a body" push "$(printf 'cat <<E\n$((1<<2)) $(git push --no-verify)\nE')"
net "a body ends at its own delimiter only" refuse "$(printf 'cat <<E\nX\ngit push --no-verify')"
net "a here-string is no heredoc" push 'cat <<<x; git push --no-verify'
net "a quoted backslash-newline" push "$(printf 'git push "--no-\\\nverify"')"

# --head on the receipt path: the value is taken only from a word with no expansion.
# An allowed PR command spends the receipt, so each case writes a fresh one: on feat-y (the cwd stays on the
# default branch, which has none) or on the cwd's own branch.
rd="$(mkrepo)"
rd_main="$(git -C "$rd" branch --show-current)"
git -C "$rd" branch feat-y >/dev/null 2>&1
rcpt() {   # rcpt <label> <verdict> <command> <feat-y|cwd>
  if [ "$4" = feat-y ]; then git -C "$rd" checkout -q feat-y; write_full_receipt "$rd"; git -C "$rd" checkout -q "$rd_main"
  else write_full_receipt "$rd"; fi
  gate "$3" "$rd"
  check_eq "rcpt:$1 → $2" "$2" "$(verdict_of)"
  rm -f "$(sentinel_for "$rd")"
  git -C "$rd" checkout -q feat-y; rm -f "$(sentinel_for "$rd")"; git -C "$rd" checkout -q "$rd_main"
}
rcpt "-H names the branch" allow 'gh pr create -H feat-y --fill' feat-y
rcpt "--head= names the branch" allow 'gh pr create --head=feat-y --fill' feat-y
rcpt "gh api head= names the branch, owner prefix stripped" allow 'gh api repos/o/r/pulls -f head=me:feat-y -f base=main' feat-y
rcpt "no --head: the cwd's branch, which has no receipt" pr 'gh pr create --fill' feat-y
rcpt "--head= from a substitution is not taken" allow 'gh pr create --head="$(git branch --show-current)" --fill' cwd
rcpt "gh api head= from a substitution is not taken" allow 'gh api repos/o/r/pulls -f head="$(git branch --show-current)"' cwd

# The reader's own output for each word class and each operator.
lex_is "tilde expansions" 'ls ~ ~/x ~user/y a=~/b:~/c a=b:~/c x~y' "TOP@1${T}d0${T}s0${T}p1${T}u:ls${T}x:~${T}ux:~/x${T}ux:~user/y${T}ux:a=~/b:~/c${T}ux:a=b:~/c${T}u:x~y"
lex_is "brace expansions" 'echo {a,b} {x} {1..3} {' "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}ug:{a,b}${T}u:{x}${T}ug:{1..3}${T}u:{"
lex_is "expansions keep their source text" 'echo $"a b" $1 $@ ${HOME}/x a$ $' "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}q:a b${T}x:\$1${T}x:\$@${T}ux:\${HOME}/x${T}u:a\$${T}u:\$"
lex_is "an arithmetic command is a word of its own; empty quotes are words" "((x++))y && echo \"\" ''" "TOP@1${T}d0${T}s0${T}p1${T}x:\$()${T}u:y"$'\n'"TOP@1${T}d0${T}s0${T}p13${T}u:echo${T}:${T}:"
lex_is "every separator ends a segment" "$(printf 'a;b;;c;&d;;&e&f&&g|h||i|&j\nk')" \
  "TOP@1${T}d0${T}s0${T}p1${T}u:a"$'\n'"TOP@1${T}d0${T}s0${T}p3${T}u:b"$'\n'"TOP@1${T}d0${T}s0${T}p6${T}u:c"$'\n'"TOP@1${T}d0${T}s0${T}p9${T}u:d"$'\n'"TOP@1${T}d0${T}s0${T}p13${T}u:e"$'\n'"TOP@1${T}d0${T}s0${T}p15${T}u:f"$'\n'"TOP@1${T}d0${T}s0${T}p18${T}u:g"$'\n'"TOP@1${T}d0${T}s0${T}p20${T}u:h"$'\n'"TOP@1${T}d0${T}s0${T}p23${T}u:i"$'\n'"TOP@1${T}d0${T}s0${T}p26${T}u:j"$'\n'"TOP@2${T}d0${T}s0${T}p28${T}u:k"
lex_is "redirection targets and fds are not words" 'x 2>f 3<>g <&4 >>h >|i >&5 &>j &>>k <l <<<m n' "TOP@1${T}d0${T}s0${T}p1${T}u:x${T}u:n"
lex_is "a brace group is no group" '{ a; }' "TOP@1${T}d0${T}s0${T}p1${T}u:{${T}u:a"$'\n'"TOP@1${T}d0${T}s0${T}p6${T}u:}"
lex_is "an unquoted { in \${…}" 'echo ${v:-{}' "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\${v:-{}"$'\n'"refuse${T}brace inside \${…}${T}line 1${T}scope:no"
lex_is "arithmetic and process substitutions" 'echo "$((1<<2))" <(a) >(b)' \
  "SUB@1${T}d1${T}s0.1${T}p20${T}u:a"$'\n'"SUB@1${T}d1${T}s0.2${T}p25${T}u:b"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()${T}x:\$()${T}x:\$()"
lex_is "a comment, and a mid-word #" "$(printf 'a#b # c d\ne')" "TOP@1${T}d0${T}s0${T}p1${T}u:a#b"$'\n'"TOP@2${T}d0${T}s0${T}p11${T}u:e"
lex_is "an escaped character, a backslash-newline, an ANSI quote" "$(printf '%s\n%s' '\g\' "it \$'a\\'b'")" "TOP@1${T}d0${T}s0${T}p1${T}uq:git${T}q:a'b"

net "a substitution in arithmetic" push 'x=$(( $(git push --no-verify) ))'
net "a single quote in arithmetic" pr "x=\$(( ')' )); gh pr create --fill"
net "a double quote in arithmetic" pr 'x=$(( ")" )); gh pr create --fill'
net "a backslash in arithmetic" pr 'x=$(( \) )); gh pr create --fill'
net "a single-quoted part glues to its word" push "git push --no-'verify'"
net "a single-quoted subcommand word" allow "gh 'pr' create --fill"
net "balanced parentheses in a body inside \$(…)" allow "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix (dir #1) in git\nEOF\n)"')"
net "a pipe" push 'echo x | git push --no-verify'
lex_is "(( re-read as nested subshells" '((cd a && git push --no-verify) && (true))' \
  "TOP@1${T}d0${T}s0${T}p1${T}x:\$()"$'\n'"refuse${T}(( read as nested subshells${T}line 1${T}scope:yes"$'\n'"refuse${T}unclosed ARITH${T}line 1${T}scope:yes"
lex_is "a heredoc that never started is an empty region" 'git log <<E' "TOP@1${T}d0${T}s0${T}p1${T}u:git${T}u:log"$'\n'"refuse${T}heredoc E not closed${T}line 1${T}scope:empty"
lex_is "a segment with no word is dropped" "$(printf 'a;\n\nb')" "TOP@1${T}d0${T}s0${T}p1${T}u:a"$'\n'"TOP@3${T}d0${T}s0${T}p5${T}u:b"

net "an ANSI quote in \${…} escapes its quote" pr "echo \${v:-\$'\\'}'}; gh pr create --fill"
net "\\\" in backticks inside double quotes opens a quote" allow 'echo "`echo \"a; git push --no-verify \"`"'
net "the reserved time comes before an assignment" push 'time HOME=/x git push'
lex_is "a \${…} counts once in its word" 'echo ${v:-"a"}' "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\${v:-\"a\"}"
lex_is "a heredoc inside a heredoc substitution" "$(printf 'cat <<E\n$(cat <<F\nx\nF\n)\ngit status\nE')" \
  "TOP@1${T}d0${T}s0${T}p1${T}u:cat"$'\n'"SUB@2${T}d1${T}s0.1${T}p11${T}u:cat"$'\n'"SUB@3${T}d1${T}s0.1${T}p19${T}u:x"$'\n'"SUB@4${T}d1${T}s0.1${T}p21${T}u:F"$'\n'"refuse${T}heredoc inside a heredoc substitution${T}line 2${T}scope:yes"

net "a )-led line in a heredoc body inside \$(…) refuses" refuse "$(printf 'MSG=$(cat <<'"'"'EOF'"'"'\n  ) git push --no-verify\nEOF\n)')"
net "a )-led line in a heredoc body outside \$(…) does not" allow "$(printf 'cat <<'"'"'EOF'"'"'\n) git push --no-verify\nEOF')"
net "a )-led line's region runs to the body's end (bash 3.2 runs the lines after it)" refuse "$(printf 'MSG=$(cat <<'"'"'EOF'"'"'\n)\ngit push --no-verify\nEOF\n)')"
net "a )-led line's region stops at the body's end" allow "$(printf 'MSG=$(cat <<'"'"'EOF'"'"'\n)\nx\nEOF\n); git status')"
# a substitution in a heredoc delimiter is a region (the shells find its end by readings of their own), and the word
# is read again as an ordinary word, so a push after it is still a segment
net "a \$(…) in a heredoc delimiter: the push after it is read" push 'cat <<$(echo {) ; git push --no-verify'
net "a \${…} in a heredoc delimiter: the push after it is read" push 'cat <<${x:-(} && git push --no-verify'
net "a \$(…) in a double-quoted heredoc delimiter: the push after it is read" push 'cat <<"$(echo ")")" ; git push --no-verify'
net "a backtick in a heredoc delimiter: the push after it is read" push 'cat <<`echo x` ; git push --no-verify'
net "a \$(…) heredoc delimiter never closed: the push inside it is read" push 'cat <<$(echo x ; git push --no-verify'
net "an escaped \$' in a \$(…) heredoc delimiter" refuse "cat <<\$(echo \\\$'x\\') ; git status ; echo ')'"
net "an escaped \${ in a \${…} heredoc delimiter" refuse 'cat <<${x:-\${} ; git status ; echo }'
net "a ( in a nested \"…\" in a \$(…) heredoc delimiter" refuse 'cat <<$(echo "$(echo "(")") ; git status # )'
net "a ( in backticks in a \$(…) heredoc delimiter" refuse 'cat <<$(echo `echo (`) ; git status # )'
net "a quote in a comment in a \$(…) heredoc delimiter" refuse "$(printf 'cat <<$(echo x # it'"'"'s\n) ; git status ; echo '"'"')'"'"'')"
net "a \$(…) heredoc delimiter inside backticks" refuse "echo \`cat <<\$(echo x) ; git status\`"
net "a \$ before a name in a heredoc delimiter is no substitution" allow "$(printf 'cat <<"E$x"\nbody\nE$x\ngit status')"
net "an escaped quote in a double-quoted heredoc delimiter" push "$(printf 'cat <<"E\\"x"\nbody\nE"x\ngit push --no-verify')"
net "a substitution delimiter is the operator's target, not a word of the segment" push '<<$(x) g"it" push --no-verify'
net "…after an assignment" push 'x=1 <<$(x) g"it" push --no-verify'
net "…a double-quoted one, before gh" pr '<<"$(x)" g"h" pr create --fill'
net "a substitution after other characters of a delimiter" refuse 'cat <<E$(x) ; git status'
net "a backtick after other characters of a delimiter" refuse 'cat <<E`x` ; git status'
net "a substitution after other characters inside double quotes" refuse 'cat <<"E$(x)" ; git status'
net "a \$' inside a double-quoted delimiter is two characters" allow "$(printf 'cat <<"E$'"'"'"\nbody\nE$'"'"'\ngit status')"
net "a substitution inside a double-quoted delimiter: the word is read again from its start" push 'cat <<"E$(x)" ; git push --no-verify'
net "a \$'…' delimiter" push "cat <<\$'\\'' ; git push --no-verify #'"
net "a \$\"…\" delimiter" push 'cat <<$"E" ; git push --no-verify'
net "a \$\"…\" delimiter: the shells disagree (bash and macOS sh end the body at E; zsh, dash and busybox read on)" push "$(printf 'cat <<$"E"\nE\ngit push --no-verify\n$E')"
net "a \$[…] delimiter" push "$(printf 'cat <<$[ ; x ]\n$[ ; x ]\ng"it" push --no-verify\n$[')"
net "a backslash-newline in a delimiter" push "$(printf 'cat <<E\\\nF\n$(git push --no-verify)\nEF')"
net "a backslash in a delimiter inside backticks (the shells read Ex, the body ends at line 2)" push "$(printf 'echo `cat <<E\\\\x\nEx\ngit push --no-verify\nE\\\\x`')"
net "a backslash in a single-quoted delimiter inside backticks" push "$(printf 'echo `cat <<'"'"'E\\$'"'"'\nE$\ngit push --no-verify\nE\\$`')"
net "an escaped backslash in a single-quoted delimiter inside backticks" refuse "$(printf 'echo `cat <<'"'"'E\\\\'"'"'\nE\\\ngit push --no-verify\nE\\\\`')"
net "zsh glob syntax glued to a delimiter: (" push "$(printf 'cat <<E(x)\nE(x)\ngit push --no-verify\nE')"
net "zsh glob syntax glued to a delimiter: <N-M> (zsh ends the body at E<1-2>)" push "$(printf 'cat <<E<1-2>\nE<1-2>\ngit push --no-verify\nE')"
net "a process substitution <(…) glued to a delimiter" push "$(printf 'cat <<E<(true)\nE<(true)\ngit push --no-verify\nE')"
net "a process substitution >(…) glued to a delimiter" push "$(printf 'cat <<E>(true)\nE>(true)\ngit push --no-verify\nE')"
d70="$(printf '%070d' 0)"
net "zsh's <N-M> glued to a delimiter, of any length" push "$(printf 'cat <<E<%s-2>x\nE<%s-2>x\ngit push --no-verify\nE' "$d70" "$d70")"
net "zsh's <-> glued to a delimiter" push "$(printf 'cat <<E<->\nE<->\ngit push --no-verify\nE')"
net "a < glued to a delimiter, a range with no closing >, is a redirection" allow "$(printf 'cat <<E<1-2\nbody\nE\ngit status')"
net "a < glued to a delimiter, digits and a > but no -, is a redirection" allow "$(printf 'cat <<E<1x2>out\nbody\nE\ngit status')"
net "a < glued to a delimiter, digits and a > but no -, is a redirection (<12>)" allow "$(printf 'cat <<E<12>out\nbody\nE\ngit status')"
net "a < glued to a delimiter, digits but no range, is a redirection" allow "$(printf 'cat <<E<12\nbody\nE\ngit status')"
net "a plain < glued to a delimiter is a redirection" allow "$(printf 'cat <<EOF<notes.txt\nbody\nEOF\ngit status')"
net "a second << glued to a delimiter is a heredoc" allow "$(printf 'cat <<A<<B\na\nA\nb\nB\ngit status')"
net "the delimiter word is read again from its start (a # there begins a comment)" refuse 'cat <<#$(git push --no-verify)'
net "a )-led line's region grows over the line's later heredoc bodies" refuse "$(printf 'MSG=$(cat <<'"'"'A'"'"' <<'"'"'B'"'"'\n)\nA\ngit push --no-verify\nB\n)')"
net "a )-led line's region does not grow over a later \$(…)'s bodies" allow "$(printf 'x=$(cat <<'"'"'A'"'"'\n)\nA\n); y=$(cat <<'"'"'B'"'"'\ngit is named\nB\n)')"

net "a quoted span in \${…} in double quotes with no } or \" in it is plain text" allow "echo \"\${v:-'x'}\" && git status"
lex_is "a disagreeing quote in \${…} in double quotes: a region, the quote read as text" "echo \"\${v:-'}' '}'}\"" \
  "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}qx:\${v:-'}' '}'}"$'\n'"refuse${T}quote inside \${…} in double quotes${T}line 1${T}scope:no"

net "a substitution in an agreeing quoted span in \${…} in double quotes" push "echo \"\${v:-'\$(git push --no-verify)'}\""
net "backticks in such a span" push "echo \"\${v:-'\`git push --no-verify\`'}\""
net "gh in such a span (the region outranks pr)" refuse "echo \"\${v:-'\$(gh pr create --fill)'}\""
net "such a span in an expanding heredoc body" push "$(printf 'cat <<E\n${v:-'"'"'$(git push --no-verify)'"'"'}\nE')"
lex_is "two disagreeing quotes in one \${…}: one region" "echo \"\${v:-'\$x'\$y'}\"" \
  "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\${v:-'\$x'\$y'}"$'\n'"refuse${T}quote inside \${…} in double quotes${T}line 1${T}scope:no"
lex_is "a { in \${…} in double quotes is quoted: no brace region" "echo \"\${v:-{'}'}\"" \
  "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}qx:\${v:-{'}'}"$'\n'"refuse${T}quote inside \${…} in double quotes${T}line 1${T}scope:no"

net "an escaped \$ in \${…} inside backticks" refuse 'echo `echo ${v:-\$(git push --no-verify)}`'
net "an escaped backtick in \${…} inside backticks" refuse 'echo `echo ${v:-\`git push --no-verify\`}`'
net "an escaped \$ in double quotes inside backticks" refuse 'echo `echo "\$(git push --no-verify)"`'
net "an escaped backtick in arithmetic inside backticks" refuse 'echo `echo $(( \`git push --no-verify\` ))`'
net "an escaped \$ in an ANSI quote inside backticks stays literal" allow "echo \`echo \$'\\\$(git push)'\`"
net "a { in \${…} in double quotes is no region" allow 'echo "${v:-{}" && git status'
net "a region in an expanding body: scope from the operator's segment" refuse "$(printf 'git commit -F - <<E\n${v:-'"'"'}'"'"'\nE')"

net "a doubled backslash inside backticks moves a quote" refuse 'echo `echo \\'"'"' ; git push --no-verify #'"'"'`'
net "a doubled backslash in an ANSI quote inside backticks" refuse 'echo `echo $'"'"'\\\'"'"' ; git push --no-verify #'"'"'`'
net "a doubled backslash in double quotes inside backticks" refuse 'echo `echo "\\\" ; git push --no-verify #"`'
net "a brace region in an expanding body scopes from the operator" refuse "$(printf 'git commit -F - <<E\n$(echo ${v:-{})\nE')"
net "a backtick region in an expanding body scopes from the operator" refuse "$(printf 'git commit -F - <<E\n`echo \\$x`\nE')"
net "an arithmetic region in an expanding body scopes from the operator" refuse "$(printf 'git commit -F - <<E\n$(( 1) ))\nE')"

# A backtick in a context nested inside backticks ends them where the shell does (the first unescaped backtick); the
# context left open there is a region, and the push after the backtick is judged at the top level.
net "a backtick inside a quote inside backticks ends them" push "echo \`echo 'a\`; git push --no-verify; echo 'b\`"
net "a backtick inside an ANSI quote inside backticks" push "echo \`echo \$'a\`; git push --no-verify; echo 'b\`"
net "a backtick inside \$(…) inside backticks" push 'echo `echo $(echo a`); git push --no-verify; echo `'
net "a backtick inside double quotes inside backticks" push 'echo `echo "a`; git push --no-verify; echo "b`'
net "a backtick inside \${…} inside backticks" push 'echo `echo ${v:-a`}; git push --no-verify; echo `'
net "a backtick in arithmetic inside backticks" push 'echo `echo $(( a`)); git push --no-verify; echo `'
net "a backtick region scopes from its own segment, not a heredoc nested in it" refuse "$(printf 'echo `git log $(cat <<E\n\\$y\nE\n)`')"

lex_has() {   # lex_has <label> <command> <text the output must contain>
  lex_out "$2"
  check_contains "lex:$1" "$OUT" "$3"
}
for ctx in 'echo `a $(b`)`' 'echo `a ${b:-c`}`' 'echo `a $(( b`))`' 'echo `a "b`"`' "echo \`a 'b\`'\`" "echo \`a \$'b\`'\`"; do
  lex_has "a backtick nested in backticks is a region [$ctx]" "$ctx" "refuse${T}backtick inside a nested context in backticks"
done

net "a comment inside backticks ends at their backtick" push "$(printf 'echo `true #`; git push --no-verify; echo `\n`')"
net "a literal heredoc body inside backticks ends at their backtick" push "$(printf "echo \`cat <<'E'\n\`; git push --no-verify; echo \`\nE\n\`")"
net "a region in a body that the backticks own scopes from the operator" refuse "$(printf 'echo `git commit -F - <<E\n\\$x\nE\n`')"
net "an escaped backtick inside a quote inside backticks ends nothing" allow "echo \`git log --format='%h\\\`'\`"
# A heredoc body that reaches its BQ's backtick without its delimiter ends there, as in every shell: no region; the
# lines after the backtick are commands.
lex_is "a heredoc body ends at its BQ's backtick" "$(printf "echo \`cat <<'E'\nx\`\nE\n\`")" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"$'\n'"TOP@3${T}d0${T}s0${T}p20${T}u:E"$'\n'"TOP@4${T}d0${T}s0${T}p22${T}x:\$()"$'\n'"refuse${T}unclosed BQ${T}line 4${T}scope:no"

lex_is "the character after a BQ that ends inside an unclosed delimiter quote is read" "x=\`cat <<'E\`;echo hi" \
  "BQ@1${T}d1${T}s0.1${T}p4${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}ux:x=\$()"$'\n'"TOP@1${T}d0${T}s0${T}p14${T}u:echo${T}u:hi"$'\n'"refuse${T}heredoc E not closed${T}line 1${T}scope:empty"
net "a heredoc body clamped at its BQ's end: lines after the backtick are commands" allow "$(printf '(x=`echo $(cat <<E\na`\n) ; git status\nE')"
lex_is "an unclosed BQ holding a closed heredoc is one region" "$(printf 'echo `cat <<E\nx\nE')" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"$'\n'"refuse${T}unclosed BQ${T}line 1${T}scope:no"
lex_is "a BQ that ends inside a nested context closes it there" 'echo `a "b` c' \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:a${T}q:b"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()${T}u:c"$'\n'"refuse${T}backtick inside a nested context in backticks${T}line 1${T}scope:no"

net "a heredoc delimiter line cut by its BQ's backtick closes the body" allow "$(printf 'git commit -m "`cat <<'"'"'E'"'"'\nmsg\nE`"')"
lex_is "a heredoc pending when a BQ closes has an empty body" 'x=`cat <<E`; git status' \
  "BQ@1${T}d1${T}s0.1${T}p4${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}ux:x=\$()"$'\n'"TOP@1${T}d0${T}s0${T}p14${T}u:git${T}u:status"$'\n'"refuse${T}heredoc E not closed${T}line 1${T}scope:empty"
lex_is "after an expanding body ends, the enclosing BQ's end still bounds the reads" "$(printf 'echo `cat <<E\nx\nE\n` ; echo z')" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"$'\n'"TOP@4${T}d0${T}s0${T}p23${T}u:echo${T}u:z"

lex_is "a heredoc delimiter line cut by its BQ's backtick: no region" "$(printf 'git commit -m "`cat <<'"'"'E'"'"'\nmsg\nE`"')" \
  "BQ@1${T}d1${T}s0.1${T}p17${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:git${T}u:commit${T}u:-m${T}x:\$()"

lex_is "after a BQ closes, its end no longer bounds the reads" 'echo `a` $(b)' \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:a"$'\n'"SUB@1${T}d1${T}s0.2${T}p12${T}u:b"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()${T}x:\$()"
lex_is "a second heredoc after a delimiter cut by the backtick has an empty body" "$(printf 'echo `cat <<E <<F\nx\nE` ; echo z')" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"$'\n'"TOP@3${T}d0${T}s0${T}p26${T}u:echo${T}u:z"$'\n'"refuse${T}heredoc F not closed${T}line 1${T}scope:empty"
net "a heredoc pending when its BQ closes is never refused" allow 'x=`git log <<E`'

lex_is "the body scan stops at its BQ's end (an empty delimiter does not match a line past it)" "$(printf "echo \`cat <<''\nx\` ; echo z\n\necho w")" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"$'\n'"TOP@2${T}d0${T}s0${T}p21${T}u:echo${T}u:z"$'\n'"TOP@4${T}d0${T}s0${T}p29${T}u:echo${T}u:w"

lex_is "a backslash join stops at its BQ's backtick" "$(printf 'echo `cat <<E\nE\\\n`x')" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}ux:\$()x"
lex_is "a )-line region ends at its BQ's backtick" "$(printf 'echo `x=$(cat <<E\n) y` gh\nE\n)`')" \
  "SUB@1${T}d2${T}s0.1.2${T}p11${T}u:cat"$'\n'"BQ@1${T}d1${T}s0.1${T}p7${T}ux:x=\$()"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()${T}u:gh"$'\n'"TOP@3${T}d0${T}s0${T}p27${T}u:E"$'\n'"TOP@4${T}d0${T}s0${T}p30${T}x:\$()"$'\n'"refuse${T}backtick inside a nested context in backticks${T}line 1${T}scope:no"$'\n'"refuse${T}) line in a heredoc body inside \$(…)${T}line 2${T}scope:no"$'\n'"refuse${T}unclosed BQ${T}line 4${T}scope:no"
net "a body with no delimiter inside backticks ends at the backtick" allow "$(printf 'x=`git log <<E\ny`')"
net "a \$(…) heredoc region inside backticks ends at the backtick" allow 'x=`echo $(cat <<E)` ; git status'

lex_is "an expanding heredoc body ends at its BQ's backtick" "$(printf 'echo `cat <<E\nb`c\nE\n`')" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}ux:\$()c"$'\n'"TOP@3${T}d0${T}s0${T}p19${T}u:E"$'\n'"TOP@4${T}d0${T}s0${T}p21${T}x:\$()"$'\n'"refuse${T}unclosed BQ${T}line 4${T}scope:no"

lex_is "a second heredoc past a cut delimiter line has an empty body, more lines after" "$(printf 'echo `cat <<E <<F\nx\nE` ; echo z\necho w')" \
  "BQ@1${T}d1${T}s0.1${T}p7${T}u:cat"$'\n'"TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}x:\$()"$'\n'"TOP@3${T}d0${T}s0${T}p26${T}u:echo${T}u:z"$'\n'"TOP@4${T}d0${T}s0${T}p33${T}u:echo${T}u:w"$'\n'"refuse${T}heredoc F not closed${T}line 1${T}scope:empty"

net "a heredoc inside a body substitution scopes from the body's operator" refuse "$(printf 'git commit -F - <<E\n$(cat <<F\nx\nF\n)\nE')"
lex_has "a \$(…) in a heredoc delimiter is a region" 'cat <<$(echo x) ; echo hi' "refuse${T}substitution or escape in a heredoc delimiter${T}line 1${T}scope:no"
lex_has "a ( right after the operator is no delimiter (B10(c)), not zsh glob syntax" 'cat << (x)' "refuse${T}heredoc operator without a delimiter${T}line 1"
lex_has "zsh glob syntax glued to a delimiter has its own reason" 'cat <<E(x)' "refuse${T}zsh glob glued to a heredoc delimiter${T}line 1"
net "a backslash join that meets its delimiter only on a line cut at its BQ's backtick is no disagreement" allow "$(printf 'x=`cat <<gitE\ngit\\\nE`; git status')"
lex_out "$(printf 'echo `x $(cat <<")"\n)`')"
check_contains "lex:a delimiter line cut at its BQ's backtick (the run reads it)" "$OUT" "refuse${T}backtick inside a nested context in backticks${T}line 1${T}"
check_absent "lex:a delimiter line cut at its BQ's backtick is the delimiter, not a )-led body line" "$OUT" ") line in a heredoc body"
OUT="$(printf 'echo "x\n\n' | bash "$gate" lex 2>&1)"
check_eq "lex:takes the text through \$(…) as the hook does (trailing newlines dropped)" "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}q:x"$'\n'"refuse${T}unclosed DQ${T}line 1${T}scope:no" "$OUT"
# A closed stdin would hang lex's $(…) (dir #691: its pipe takes fd 0). The shell must START with fd 0 closed, and a
# backgrounded kill is the bound (alpine has no perl, macOS no timeout(1)): a hang dies as 137. `set -m` gives the job
# its own process group, so the kill reaches the hung grandchild too.
lexerr="$SANDBOX/lex-closed-stdin.err"
set -m
( exec "${BASH:-bash}" -c 'exec <&-; exec "${BASH:-bash}" "$0" lex' "$gate" ) >/dev/null 2>"$lexerr" &
lexpid=$!
( sleep 20; kill -9 -- "-$lexpid" 2>/dev/null ) >/dev/null 2>&1 &
lexwd=$!
set +m
wait "$lexpid"; STATUS=$?
kill -- "-$lexwd" 2>/dev/null; wait "$lexwd" 2>/dev/null
check_status "lex:a closed stdin reads as empty, never hangs (a watchdog kill is 137)" 0 "$STATUS"
check_eq "lex:…with nothing on stderr" "" "$(cat "$lexerr")"
OUT="$(printf 'echo "a\000b' | bash "$gate" lex 2>&1)"
check_eq "lex:a NUL byte goes, as through the hook's \$(…), with no shell warning" "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}q:ab"$'\n'"refuse${T}unclosed DQ${T}line 1${T}scope:no" "$OUT"
OUT="$(bash "$gate" lex < / 2>&1)"; STATUS=$?
check_status "lex:an unreadable stdin (a directory) → exit 2" 2 "$STATUS"
lex_has "a bare { in a \${…} heredoc delimiter is a region (zsh counts it)" 'cat <<${x:-{} ; echo hi' "refuse${T}brace inside \${…}${T}line 1${T}scope:no"
lex_has "a git ending at the region's last character is in scope" 'echo "x gh' "refuse${T}unclosed DQ${T}line 1${T}scope:yes"
lex_has "a )-led line's region starts at the first such line" "$(printf 'MSG=$(cat <<'"'"'EOF'"'"'\nx\n)\n)\nEOF\n)')" \
  "refuse${T}) line in a heredoc body inside \$(…)${T}line 3${T}"
lex_is "a word of many braces is read in one pass" "echo {a,{b,c}} {{x}" "TOP@1${T}d0${T}s0${T}p1${T}u:echo${T}ug:{a,{b,c}}${T}u:{{x}"

summary
