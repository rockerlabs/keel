#!/usr/bin/env bash
# test_pre_pr_gate_merge.sh — the pre-PR gate's merge rule (dir #811, spec B6, acceptance A7 (a)–(k) and (m)).
#
# tools/pre-pr-gate.sh denies `gh pr merge` (and the `gh api …/pulls/<n>/merge` write) unless the session is this
# repository's release manager — listed in the manager file by the skill-trace leg when it launched /manage-release —,
# the main checkout's CLAUDE.md opts in with a KEEL-MANAGER-MERGES line, and the command pins the head as a merge
# commit. A7 (l), the installer's matcher, lives in tests/test_install_pre_pr_gate.sh. This file is the one
# tools/self/mutation-sweep.sh runs per mutant of tests/mutants/pre-pr-gate-merge.tsv (A8), so it stays small and
# every deny asserts its OWN reason text: a mutant that makes another check deny must not count as caught.
#
# A manager is listed only through the skill-trace leg (`list_as`), never by writing the file by hand: a
# writer/reader format mismatch would pass a hand-listed id and leave the feature dead. The hook is fed JSON events
# only; nothing here runs gh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

gate="$REPO_ROOT/tools/pre-pr-gate.sh"
check_file "pre-pr-gate.sh exists" "$gate"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — merge-rule tests skipped (the gate requires jq to parse its event)"
  summary; exit $?
fi

SHA="04d11fd5a6b7c8d9e0f1a2b3c4d5e6f708192a3b"   # 40 lower-case hex
MID="sess-mgr-0001"                               # the listed manager
OTHER="sess-wrk-0002"                             # never listed
DENY='"permissionDecision":"deny"'
R_ID="not a release-manager session"
R_GIT="not a git checkout"
R_POLICY="this project's policy keeps the merge with the operator"
R_PIN="pin the head: --match-head-commit <40-hex sha>"
R_NOMERGE="a merge commit only: add --merge"
R_DROP="a merge commit only: drop"
R_API="never the API"
R_SUB="a subagent never merges"

mkrepo() {
  local d; d="$(new_repo)"
  git -C "$d" commit --allow-empty -qm init
  printf '%s' "$d"
}

# ev_gate CMD CWD SID [EXTRA] — one PreToolUse(Bash) event. SID "-" leaves session_id out; EXTRA is a JSON object
# merged into the event (agent fields). Captures OUT (stdout+stderr) and STATUS.
ev_gate() {
  local json x="${4:-}"
  [ -n "$x" ] || x='{}'
  json="$(jq -cn --arg c "$1" --arg d "$2" --arg s "$3" --argjson x "$x" \
    '{tool_input:{command:$c}, cwd:$d} + (if $s == "-" then {} else {session_id:$s} end) + $x')"
  OUT="$(printf '%s' "$json" | bash "$gate" 2>&1)"
  STATUS=$?
}
# trace_ev JSON — feeds one event to the skill-trace leg.
trace_ev() { printf '%s' "$1" | bash "$gate" skill-trace >/dev/null 2>&1; }
# list_as CWD SID [SKILL] — the launch the release manager makes: Claude's Skill(manage-release) call.
list_as() {
  trace_ev "$(jq -cn --arg d "$1" --arg s "$2" --arg k "${3:-manage-release}" \
    '{hook_event_name:"PostToolUse", cwd:$d, session_id:$s, tool_name:"Skill", tool_input:{skill:$k, args:"0.17.0"}}')"
}
# allow LABEL CMD CWD SID [EXTRA] / deny LABEL REASON CMD CWD SID [EXTRA]
allow() {
  local label="$1"; shift
  ev_gate "$@"
  check_status "$label → exit 0" 0 "$STATUS"
  check_eq "$label → no decision (empty stdout)" "" "$OUT"
}
deny() {
  local label="$1" why="$2"; shift 2
  ev_gate "$@"
  check_status "$label → exit 0 (the hook always does)" 0 "$STATUS"
  check_contains "$label → deny" "$OUT" "$DENY"
  check_contains "$label → its own reason: $why" "$OUT" "$why"
}

P="$(mkrepo)"; printf '# project\nsome line\nKEEL-MANAGER-MERGES — the release manager merges (R14)\nlast line\n' > "$P/CLAUDE.md"
N="$(mkrepo)"; printf '# project without the policy line\n' > "$N/CLAUDE.md"
list_as "$P" "$MID"
list_as "$N" "$MID"
MERGE="gh pr merge 597 --merge --match-head-commit $SHA"

# --- (j) the skill-trace leg writes the manager file ----------------------------------------------------------------
mf="$(manager_for "$P")"
check_file "(j) Skill(manage-release) writes the manager file" "$mf"
check_status "(j) ...one line" 1 "$(grep -c . "$mf" 2>/dev/null || true)"
line="$(cat "$mf" 2>/dev/null)"
if [[ "$line" =~ ^"$MID"$'\t'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  pass "(j) ...shaped <session_id><TAB><UTC time>"
else
  fail "(j) ...shaped <session_id><TAB><UTC time>" "got: $line"
fi
list_as "$P" "$MID"
check_status "(j) a second launch by the same session adds no line" 1 "$(grep -c . "$mf" 2>/dev/null || true)"
check_nofile "(j) a manage-release launch writes no review trace" "$(trace_for "$P")"
for shape in keel-manage-release /manage-release x:manage-release /keel-manage-release x:keel-manage-release; do
  d="$(mkrepo)"; list_as "$d" "$MID" "$shape"
  check_status "(j) the $shape shape lists the session" 1 "$(grep -c "^$MID	" "$(manager_for "$d")" 2>/dev/null || true)"
done
d="$(mkrepo)"; list_as "$d" "$MID" go
check_nofile "(j) Skill(go) lists nobody" "$(manager_for "$d")"
d="$(mkrepo)"; list_as "$d" "$MID" manage-releasex
check_nofile "(j) Skill(manage-releasex) lists nobody" "$(manager_for "$d")"
d="$(mkrepo)"
trace_ev "$(jq -cn --arg d "$d" --arg s "$MID" \
  '{hook_event_name:"UserPromptExpansion", cwd:$d, session_id:$s, expansion_type:"slash_command", command_name:"manage-release", command_args:"0.17.0", command_source:"user", prompt:"/manage-release 0.17.0"}')"
check_status "(j) the operator's typed /manage-release (UserPromptExpansion) lists the session" 1 "$(grep -c "^$MID	" "$(manager_for "$d")" 2>/dev/null || true)"
d="$(mkrepo)"
trace_ev "$(jq -cn --arg d "$d" --arg s "$MID" \
  '{hook_event_name:"PostToolUse", cwd:$d, session_id:$s, tool_name:"Skill", tool_input:{skill:"manage-release"}, agent_id:"a1", agent_type:"general-purpose"}')"
check_nofile "(j) a subagent's Skill(manage-release) lists nobody" "$(manager_for "$d")"
d="$(mkrepo)"
trace_ev "$(jq -cn --arg d "$d" --arg s "$MID" \
  '{hook_event_name:"PostToolUse", cwd:$d, session_id:$s, tool_name:"Skill", tool_input:{skill:"manage-release"}, agent_type:"Explore"}')"
check_nofile "(j) ...nor one carrying only agent_type" "$(manager_for "$d")"
d="$(mkrepo)"
trace_ev "$(jq -cn --arg d "$d" '{hook_event_name:"PostToolUse", cwd:$d, tool_name:"Skill", tool_input:{skill:"manage-release"}}')"
check_nofile "(j) an event with no session_id lists nobody" "$(manager_for "$d")"
# A session id that is not a plain token is never written: a newline in it would forge a second line.
d="$(mkrepo)"; list_as "$d" "$(printf 'x\nsess-forged')"
check_nofile "(j) a session id holding a newline lists nobody" "$(manager_for "$d")"
printf 'KEEL-MANAGER-MERGES\n' > "$d/CLAUDE.md"
deny "(j) ...so the id after the newline is not a manager" "$R_ID" "$MERGE" "$d" "sess-forged"
nd="$(mktemp -d "$SANDBOX/plain.XXXXXX")"; list_as "$nd" "$MID"
check_nofile "(j) a launch from a cwd that is no git checkout lists nobody" "$(manager_for "$nd")"
d="$(mkrepo)"
trace_ev "$(jq -cn --arg d "$d" --arg s "$MID" '{hook_event_name:"PostToolUse", cwd:$d, session_id:$s, tool_name:"Bash", tool_input:{skill:"manage-release"}}')"
check_nofile "(j) a PostToolUse of another tool lists nobody" "$(manager_for "$d")"
# Two managers in one repository: both listed, both allowed.
list_as "$P" "sess-mgr-0003"
check_status "(j) a second manager adds its own line" 2 "$(grep -c . "$mf" 2>/dev/null || true)"
allow "(j) the second manager merges" "$MERGE" "$P" "sess-mgr-0003"

# --- (a) the release manager, flags right ---------------------------------------------------------------------------
allow "(a) manager + --merge --match-head-commit <40>" "$MERGE" "$P" "$MID"
allow "(a) the =-form of the pin" "gh pr merge 597 --merge --match-head-commit=$SHA" "$P" "$MID"
allow "(a) -m" "gh pr merge 597 -m --match-head-commit $SHA" "$P" "$MID"
allow "(a) a short cluster holding m (-dm)" "gh pr merge 597 -dm --match-head-commit $SHA" "$P" "$MID"
allow "(a) --merge=true" "gh pr merge 597 --merge=true --match-head-commit $SHA" "$P" "$MID"
allow "(a) a flag before the subcommand (gh pr -R o/r merge)" "gh pr -R o/r merge 597 --merge --match-head-commit $SHA" "$P" "$MID"
# The shapes a manager's real command takes: a redirect, a pipe, a chained read, a quoted subject and body.
allow "(a) a redirect and a pipe" "$MERGE 2>&1 | tail -n 5" "$P" "$MID"
allow "(a) chained with a read of the PR" "$MERGE && gh pr view 597 --json state" "$P" "$MID"
allow "(a) a quoted subject and body" "$MERGE --subject \"0.17.0 train 1: land #601-#609\" --body 'no -s here' -d" "$P" "$MID"
allow "(a) GH_REPO=o/r env prefix" "GH_REPO=o/r $MERGE" "$P" "$MID"

# --- (b) identity ---------------------------------------------------------------------------------------------------
deny "(b) an unlisted session" "$R_ID" "$MERGE" "$P" "$OTHER"
deny "(b) a prefix of a listed id" "$R_ID" "$MERGE" "$P" "sess-mgr-000"
deny "(b) a listed id plus a suffix" "$R_ID" "$MERGE" "$P" "${MID}9"
deny "(b) no session_id at all" "$R_ID" "$MERGE" "$P" "-"
deny "(b) a session_id that is not a string" "$R_ID" "$MERGE" "$P" "-" '{"session_id":7}'
d="$(mkrepo)"; printf 'KEEL-MANAGER-MERGES\n' > "$d/CLAUDE.md"
deny "(b) no manager file for the repo" "$R_ID" "$MERGE" "$d" "$MID"
check_nofile "(b) ...and the deny creates none" "$(manager_for "$d")"
deny "(b) unlisted + no policy line → identity first" "$R_ID" "$MERGE" "$N" "$OTHER"
check_absent "(b) ...not the policy reason" "$OUT" "$R_POLICY"

# --- (c) policy before flags, then the pin and --merge -------------------------------------------------------------
deny "(c) manager, no --match-head-commit" "$R_PIN" "gh pr merge 597 --merge" "$P" "$MID"
deny "(c) manager, a pin with no value" "$R_PIN" "gh pr merge 597 --merge --match-head-commit" "$P" "$MID"
deny "(c) manager, no --merge" "$R_NOMERGE" "gh pr merge 597 --match-head-commit $SHA" "$P" "$MID"
deny "(c) manager, --merge=false" "$R_NOMERGE" "gh pr merge 597 --merge=false --match-head-commit $SHA" "$P" "$MID"
deny "(c) manager, no policy line, no pin → the policy reason" "$R_POLICY" "gh pr merge 597 --merge" "$N" "$MID"
check_absent "(c) ...not the pin" "$OUT" "$R_PIN"
deny "(c) a 6-hex sha" "$R_PIN" "gh pr merge 597 --merge --match-head-commit 04d11f" "$P" "$MID"

# --- (d) forbidden flags and malformed pins -------------------------------------------------------------------------
for f in --squash --squash=true -s --rebase -r -sd -rd -dr -ds --auto --auto=true --admin --admin=true -s=x --admin=false; do
  deny "(d) $f" "$R_DROP $f " "$MERGE $f" "$P" "$MID"
done
deny "(d) a forbidden flag before the subcommand" "$R_DROP --admin " "gh pr --admin merge 597 --merge --match-head-commit $SHA" "$P" "$MID"
deny "(d) a 39-hex sha" "$R_PIN" "gh pr merge 597 --merge --match-head-commit ${SHA%?}" "$P" "$MID"
deny "(d) --match-head-commit=<39-hex>" "$R_PIN" "gh pr merge 597 --merge --match-head-commit=${SHA%?}" "$P" "$MID"
deny "(d) a 41-hex sha" "$R_PIN" "gh pr merge 597 --merge --match-head-commit ${SHA}a" "$P" "$MID"
deny "(d) an upper-case 40-hex sha" "$R_PIN" "gh pr merge 597 --merge --match-head-commit $(printf '%s' "$SHA" | tr a-f A-F)" "$P" "$MID"
deny "(d) 40 characters, not all hex" "$R_PIN" "gh pr merge 597 --merge --match-head-commit ${SHA%?}g" "$P" "$MID"
deny "(d) a valid pin beside a bad one" "$R_PIN" "$MERGE --match-head-commit 04d11f" "$P" "$MID"
# The words read as gh reads them: a value flag takes the next word, so a pin there pins nothing, and a flag-shaped
# value is no flag.
deny "(d) -t eats the =-form pin" "$R_PIN" "gh pr merge 5 --merge -t --match-head-commit=$SHA" "$P" "$MID"
deny "(d) --subject eats the pin flag" "$R_PIN" "gh pr merge 5 --merge --subject --match-head-commit $SHA" "$P" "$MID"
deny "(d) a cluster ending in t (-dt) eats the pin" "$R_PIN" "gh pr merge 5 --merge -dt --match-head-commit=$SHA" "$P" "$MID"
deny "(d) --body eats --merge" "$R_NOMERGE" "gh pr merge 5 --body --merge --match-head-commit $SHA" "$P" "$MID"
allow "(d) -tX: a glued value, the pin after it counts" "gh pr merge 5 --merge -tX --match-head-commit $SHA" "$P" "$MID"
allow "(d) --subject -s: a value, not --squash" "$MERGE --subject -s" "$P" "$MID"
allow "(d) -b --admin: a value, not --admin" "$MERGE -b --admin" "$P" "$MID"
allow "(d) -R o/r before the pin" "gh pr merge 5 -R o/r --merge --match-head-commit $SHA" "$P" "$MID"
deny "(d) a flag-shaped pin value is the pin, not a flag" "$R_PIN" "gh pr merge 5 --merge --match-head-commit --squash" "$P" "$MID"
# Under xargs the command takes more words from stdin, which no flag check can read: a manager's merge there is denied.
deny "(d) manager: a merge under xargs" "under xargs" "printf -- '--admin\\n' | xargs $MERGE" "$P" "$MID"
deny "(d) manager: a merge under xargs with flags" "under xargs" "echo 5 | xargs -n1 gh pr merge --merge --match-head-commit $SHA" "$P" "$MID"
allow "(d) manager: exec -a x is read past (no stdin words)" "exec -a x $MERGE" "$P" "$MID"
deny "(d) -m=false is no --merge" "$R_NOMERGE" "gh pr merge 5 -m=false --match-head-commit $SHA" "$P" "$MID"
deny "(d) a forbidden flag wins over a missing pin" "$R_DROP --squash " "gh pr merge 597 --squash" "$P" "$MID"
# Two merges in one command: the first failing one decides, and the API shape outranks every other code.
allow "(d) two merges, both right" "$MERGE && gh pr merge 598 --merge --match-head-commit $SHA" "$P" "$MID"
deny "(d) the first of two merges carries --squash" "$R_DROP --squash " "$MERGE --squash && $MERGE" "$P" "$MID"
deny "(d) the second of two merges has no pin" "$R_PIN" "$MERGE && gh pr merge 598 --merge" "$P" "$MID"
deny "(d) an earlier flag code does not hide a later API merge" "$R_API" "$MERGE --squash; gh api -X PUT repos/o/r/pulls/5/merge" "$P" "$MID"

# --- (e) --help / -h ------------------------------------------------------------------------------------------------
for h in --help -h; do
  allow "(e) gh pr merge $h, manager" "gh pr merge $h" "$P" "$MID"
  allow "(e) gh pr merge $h, unlisted (a read)" "gh pr merge $h" "$P" "$OTHER"
done
allow "(e) manager: --subject -h is a flag value (a merge with the flags right)" "gh pr merge 5 --merge --match-head-commit $SHA --subject -h" "$P" "$MID"
deny "(e) unlisted: --subject -h is no read" "$R_ID" "gh pr merge 5 --merge --match-head-commit $SHA --subject -h" "$P" "$OTHER"
deny "(e) unlisted: -h after the number is no read" "$R_ID" "gh pr merge 5 -h" "$P" "$OTHER"
deny "(e) unlisted + no pin → the identity reason, not the pin" "$R_ID" "gh pr merge 5 --merge" "$P" "$OTHER"
check_absent "(e) ...not the pin" "$OUT" "$R_PIN"

# --- (f) the gh api merge shape: denied to the manager too ---------------------------------------------------------
for c in "gh api -X PUT repos/o/r/pulls/5/merge" "gh api --method PUT repos/o/r/pulls/5/merge" \
         "gh api --method=PUT repos/o/r/pulls/5/merge" "gh api -X put repos/o/r/pulls/5/merge" \
         "gh api -XPUT repos/o/r/pulls/5/merge" "gh api -X PUT /repos/o/r/pulls/5/merge" \
         "gh api -X PUT https://api.github.com/repos/o/r/pulls/5/merge" \
         "gh api repos/o/r/pulls/5/merge -f commit_title=x" "gh api repos/o/r/pulls/5/merge -F merge_method=merge" \
         "gh api repos/o/r/pulls/5/merge --field sha=$SHA" "gh api repos/o/r/pulls/5/merge --raw-field x=y" \
         "gh api repos/o/r/pulls/5/merge --input body.json" "gh api repos/o/r/pulls/5/merge --field=sha=$SHA" \
         "gh api -X POST repos/o/r/pulls/5/merge"; do
  deny "(f) manager: $c" "$R_API" "$c" "$P" "$MID"
done
deny "(f) unlisted: the API shape" "$R_API" "gh api -X PUT repos/o/r/pulls/5/merge" "$P" "$OTHER"
# Short clusters, as gh reads them: -iXPUT and -iX PUT are -i plus -X PUT; -ifx=1 is -i plus a field.
deny "(f) -iXPUT (a cluster)" "$R_API" "gh api -iXPUT repos/o/r/pulls/5/merge" "$P" "$OTHER"
deny "(f) -iX PUT (a cluster, the method in the next word)" "$R_API" "gh api -iX PUT repos/o/r/pulls/5/merge" "$P" "$OTHER"
deny "(f) -ifx=1 (a field in a cluster)" "$R_API" "gh api repos/o/r/pulls/5/merge -ifx=1" "$P" "$OTHER"
allow "(f) -H takes a value: an endpoint-shaped header is no endpoint" "gh api -H repos/o/r/pulls/5/merge -X PUT repos/o/r/issues/5/lock" "$P" "$OTHER"
allow "(f) -iX GET is a read" "gh api -iX GET repos/o/r/pulls/5/merge" "$P" "$OTHER"
allow "(f) -XGET is a read" "gh api -XGET repos/o/r/pulls/5/merge" "$P" "$OTHER"
allow "(f) -X=GET is a read" "gh api -X=GET repos/o/r/pulls/5/merge" "$P" "$OTHER"
allow "(f) --header takes a value too" "gh api --header repos/o/r/pulls/5/merge -X PUT repos/o/r/issues/5/lock" "$P" "$OTHER"
allow "(f) gh api …/pulls/5/merge (GET: is it merged)" "gh api repos/o/r/pulls/5/merge" "$P" "$OTHER"
allow "(f) gh api -X GET …/pulls/5/merge" "gh api -X GET repos/o/r/pulls/5/merge" "$P" "$OTHER"
allow "(f) gh api …/pulls (a list)" "gh api repos/o/r/pulls" "$P" "$OTHER"
allow "(f) a PUT on …/pulls/5/mergeable is no merge endpoint" "gh api -X PUT repos/o/r/pulls/5/mergeable" "$P" "$OTHER"

# --- (g) the shapes the create rule reads, for an unlisted session -------------------------------------------------
for c in "cd /tmp && $MERGE" "GH_TOKEN=x $MERGE" "foo; $MERGE" "env GH_PAGER= $MERGE" \
         "gh --repo o/r pr merge 5 --merge --match-head-commit $SHA" "gh pr -R o/r merge 5 --merge --match-head-commit $SHA" \
         "cat <<EOF && $MERGE" "$(printf 'git status\n%s' "$MERGE")" "echo \$($MERGE)" "x=\`$MERGE\`" \
         "echo 5 | xargs -n1 gh pr merge --squash --admin" "xargs -r -I{} $MERGE" "exec -a x $MERGE"; do
  deny "(g) unlisted: [$c]" "$R_ID" "$c" "$P" "$OTHER"
done
for c in "echo gh pr merge" "git commit -m 'wire gh pr merge'" "gh pr view 5 --json mergeable,mergeStateStatus" \
         "gh pr list --state merged" "grep -c 'gh pr merge' f" "gh pr merge" ; do
  case "$c" in
    "gh pr merge") deny "(g) a bare gh pr merge is a merge" "$R_ID" "$c" "$P" "$OTHER" ;;
    *) allow "(g) unlisted: [$c] is no merge" "$c" "$P" "$OTHER" ;;
  esac
done

# --- (h) a cwd that is no git checkout ------------------------------------------------------------------------------
deny "(h) a non-git cwd" "$R_GIT" "$MERGE" "$nd" "$MID"

# --- (i) the create rule still runs after a merge that passes -------------------------------------------------------
deny "(i) a passing merge chained with gh pr create → the create rule still denies" "run /polish first" "$MERGE && gh pr create --fill" "$P" "$MID"
deny "(i) gh pr create alone, unchanged" "run /polish first" "gh pr create --fill" "$P" "$OTHER"

# --- (k) a subagent never merges ------------------------------------------------------------------------------------
deny "(k) manager id + agent_type" "$R_SUB" "$MERGE" "$P" "$MID" '{"agent_type":"general-purpose"}'
deny "(k) manager id + agent_id only" "$R_SUB" "$MERGE" "$P" "$MID" '{"agent_id":"a716fee1"}'
deny "(k) manager id + a non-string agent_id" "$R_SUB" "$MERGE" "$P" "$MID" '{"agent_id":12}'
# A session id holding the field separator reads as none: it cannot shift the subagent flag (or the cwd) after it.
deny "(k) a session_id holding the separator cannot forge the subagent flag" "$R_SUB" "$MERGE" "$P" "$(printf '%s\0370' "$MID")" '{"agent_type":"general-purpose"}'
allow "(k) agent_type null is no subagent" "$MERGE" "$P" "$MID" '{"agent_type":null}'
allow "(k) agent_type \"\" is no subagent" "$MERGE" "$P" "$MID" '{"agent_type":"","agent_id":""}'

# --- (m) the project's policy line, read from the MAIN checkout ----------------------------------------------------
deny "(m) manager, flags right, no KEEL-MANAGER-MERGES line" "$R_POLICY" "$MERGE" "$N" "$MID"
d="$(mkrepo)"; list_as "$d" "$MID"
deny "(m) no CLAUDE.md at all" "$R_POLICY" "$MERGE" "$d" "$MID"
wt="$SANDBOX/wt-merge"
git -C "$P" worktree add -q -b wt-merge "$wt" 2>/dev/null
printf 'KEEL-MANAGER-MERGES\n' > "$wt/CLAUDE.md"
mv "$P/CLAUDE.md" "$SANDBOX/claude-md-aside"
deny "(m) a worktree's own policy line does not stand in for the main checkout's" "$R_POLICY" "$MERGE" "$wt" "$MID"
mv "$SANDBOX/claude-md-aside" "$P/CLAUDE.md"; rm -f "$wt/CLAUDE.md"
allow "(m) from a worktree, the main checkout's line (mid-file) → no decision" "$MERGE" "$wt" "$MID"
w2="$SANDBOX/wt-merge-2"
git -C "$N" worktree add -q -b wt-merge-2 "$w2" 2>/dev/null
list_as "$w2" "sess-from-wt"
check_status "(m) a launch from a worktree lists the session for the main checkout's repo" 1 \
  "$(grep -c '^sess-from-wt	' "$(manager_for "$N")" 2>/dev/null || true)"

summary
