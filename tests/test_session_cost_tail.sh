#!/usr/bin/env bash
# tests/test_session_cost_tail.sh — dir #670 (slice 1): `tools/self/session-cost.sh tail`, the per-PR
# tail measurement (B9) and its review-cost split (B10). Every fixture is SYNTHETIC — built here, inside
# the sandbox, in the shapes verified live against real transcripts (CLAUDE.md: no real transcript
# content enters a tracked file). One case per A2 item (i)-(ix); each was shown red against a wrong
# build first (the first-record-only reader must fail (i) — the exact bug the design's E5 records).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="$REPO_ROOT/tools/self/session-cost.sh"
check_file "tools/self/session-cost.sh exists" "$tool"

PRURL='https://github.com/example-org/example-repo/pull/42'
FIXED_LINE="You are /polish step 5's review subagent."

# --- fixture builders ------------------------------------------------------------------------------
# A time is "HH:MM:SS" on one fixed day; ISO strings of one format compare lexicographically.
T() { printf '2026-10-01T%s.000Z' "$1"; }

# rec_turn REQUEST_ID HH:MM:SS SKILL BRANCH CACHE_READ CONTENT_JSON — one assistant record
rec_turn() {
  jq -nc --arg rid "$1" --arg ts "$(T "$2")" --arg sk "$3" --arg br "$4" --argjson cr "$5" --argjson content "$6" '
    {type:"assistant", requestId:$rid, timestamp:$ts, gitBranch:(if $br=="" then null else $br end),
     attributionSkill:(if $sk=="" then null else $sk end),
     message:{model:"claude-sonnet-5-5", content:$content,
              usage:{input_tokens:1, output_tokens:1, cache_read_input_tokens:$cr}}}'
}
# bash_use ID COMMAND — a Bash tool_use content array
bash_use() { jq -nc --arg id "$1" --arg c "$2" '[{type:"tool_use", id:$id, name:"Bash", input:{command:$c}}]'; }
# rec_result HH:MM:SS TOOL_USE_ID IS_ERROR TEXT — a user record holding one tool_result
rec_result() {
  jq -nc --arg ts "$(T "$1")" --arg id "$2" --argjson err "$3" --arg t "$4" '
    {type:"user", timestamp:$ts,
     message:{role:"user", content:[{type:"tool_result", tool_use_id:$id, is_error:$err, content:$t}]}}'
}
# mk_session NAME — sets SF to a fresh primary transcript path (empty) with its subagents dir
mk_session() {
  SESS_ID="$(printf '%s' "$1" | tr -c 'a-z0-9' '0')-aaaa-bbbb-cccc-dddddddddddd"
  SDIR="$SANDBOX/proj-$1"
  mkdir -p "$SDIR/$SESS_ID/subagents"
  SF="$SDIR/$SESS_ID.jsonl"
  : > "$SF"
}
# mk_agent ID PARENT DEPTH HH:MM:SS FIRSTLINE CR... — a subagent transcript beside $SF: one prompt record at
# the given time, then one assistant turn per CR (cache-read) value, one second apart after it. PARENT "" = none.
mk_agent() {
  local id="$1" parent="$2" depth="$3" at="$4" first="$5"; shift 5
  local f="$SDIR/$SESS_ID/subagents/agent-$id.jsonl" n=0 cr
  jq -nc --arg ts "$(T "$at")" --arg p "$first"$'\nsecond prompt line' \
    '{type:"user", isSidechain:true, timestamp:$ts, message:{role:"user", content:$p}}' > "$f"
  for cr in "$@"; do
    n=$((n + 1))
    jq -nc --arg rid "req-$id-$n" --arg ts "$(T "$at")" --argjson cr "$cr" --arg id "$id" \
      '{type:"assistant", isSidechain:true, agentId:$id, requestId:$rid, timestamp:$ts,
        message:{model:"claude-sonnet-5-5", content:[], usage:{output_tokens:1, cache_read_input_tokens:$cr}}}' >> "$f"
  done
  if [ -n "$parent" ]; then
    printf '{"agentType":"general-purpose","parentAgentId":"%s","spawnDepth":%s}' "$parent" "$depth" > "${f%.jsonl}.meta.json"
  else
    printf '{"agentType":"general-purpose","spawnDepth":%s}' "$depth" > "${f%.jsonl}.meta.json"
  fi
}
# tail_json — run `tail --json` over $SF
tail_json() { run bash "$tool" tail --json "$SF"; }
# field: jq a value out of the NTH (1-based) JSON line of $OUT
field() { printf '%s\n' "$OUT" | sed -n "${1}p" | jq -r "$2"; }

# --- usage / dispatch (A1) -------------------------------------------------------------------------
run bash "$tool"
check_contains "usage names the tail subcommand" "$OUT" "tail"

run bash "$tool" tail
check_status "tail with no file exits 2" "2" "$STATUS"

run bash "$tool" tail --json "$SANDBOX/does-not-exist.jsonl"
check_status "tail on a missing file exits 2" "2" "$STATUS"

# --- (v) a transcript with no /polish: no window, empty output --------------------------------------
mk_session nopolish
{
  rec_turn R1 10:00:00 go b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:00:01 wrap b1 900 '[{"type":"text","text":"x"}]'
} > "$SF"
tail_json
check_status "(v) no /polish: exits 0" "0" "$STATUS"
check_eq "(v) no /polish: no output" "" "$OUT"

# --- A1 + (i): the tool call in the SECOND record of its requestId still closes the window -------------
mk_session second
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  # one API response logged as two records sharing requestId R2: the thinking block first, the tool_use second
  rec_turn R2 10:00:10 polish b1 1000 '[{"type":"thinking"}]'
  rec_turn R2 10:00:11 polish b1 1000 "$(bash_use toolu_pr1 'gh pr create --title t --body b')"
  rec_result 10:00:20 toolu_pr1 false "$PRURL"
} > "$SF"
tail_json
check_status "A1: tail --json exits 0" "0" "$STATUS"
check_eq "A1: one window object" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "A1: the output line is valid JSON" "0" "$(printf '%s\n' "$OUT" | jq -e . >/dev/null 2>&1; echo $?)"
check_eq "(i) a tool call in the second record of its requestId closes the window" "closed" "$(field 1 .status)"
check_eq "(i) the window costs its deduped primary turns (100 + 1000, not 100 + 2x1000)" "1100" "$(field 1 .cost)"
check_eq "(i) primary turns counted per requestId, not per record" "2" "$(field 1 .primary_turns)"
check_eq "(i) the window starts at its first polish turn" "$(T 10:00:00)" "$(field 1 .start)"
check_eq "(i) the JSON names the session" "$SESS_ID" "$(field 1 .session)"
check_eq "(i) the window carries a review_cost field (0 with no review subagent)" "0" "$(field 1 .review_cost)"

# --- the human form ----------------------------------------------------------------------------------
run bash "$tool" tail "$SF"
check_status "human tail exits 0" "0" "$STATUS"
check_contains "human tail names the session's first 8 chars" "$OUT" "${SESS_ID:0:8}"
check_contains "human tail shows the cost" "$OUT" "1100"
check_contains "human tail shows the window start" "$OUT" "$(T 10:00:00)"

# --- (ii) a gate-denied `gh pr create` leaves the window open; the later success closes it ----------
mk_session denied
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:00:10 polish b1 200 "$(bash_use toolu_a 'gh pr create --title t')"
  rec_result 10:00:12 toolu_a true "BLOCKED by the pre-PR gate: no receipt for this HEAD"
  rec_turn R3 10:00:20 polish b1 300 "$(bash_use toolu_b 'gh pr create --title t')"
  rec_result 10:00:22 toolu_b false "$PRURL"
} > "$SF"
tail_json
check_eq "(ii) a denied gh pr create then a success: one window" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(ii) closed by the later success" "closed" "$(field 1 .status)"
check_eq "(ii) the window includes the denied attempt's turn (100+200+300)" "600" "$(field 1 .cost)"

mk_session deniedonly
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:00:10 polish b1 200 "$(bash_use toolu_a 'gh pr create --title t')"
  rec_result 10:00:12 toolu_a true "BLOCKED by the pre-PR gate"
} > "$SF"
tail_json
check_eq "(ii) only a denied gh pr create: the window stays open" "open" "$(field 1 .status)"

# --- (ii-b) a NON-error Bash call whose command contains `gh pr create` but whose output names no PR URL
mk_session grepcmd
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:00:10 polish b1 200 "$(bash_use toolu_g "grep -n 'gh pr create' commands/polish.md")"
  rec_result 10:00:12 toolu_g false "412:  gh pr create --head <branch> --title ..."
  rec_turn R3 10:00:20 polish b1 300 "$(bash_use toolu_e "echo 'about to run gh pr create'")"
  rec_result 10:00:22 toolu_e false "about to run gh pr create"
} > "$SF"
tail_json
check_eq "(ii-b) a non-error gh-pr-create-mentioning call with no PR URL leaves the window open" "open" "$(field 1 .status)"

# --- (iii) straddlers: a subagent counts iff its FIRST record falls inside the window ---------------
mk_session straddle
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:10:00 polish b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:10:05 toolu_p false "$PRURL"
} > "$SF"
mk_agent inside "" 1 10:05:00 "Simplify review: reuse" 7000 8000
mk_agent before "" 1 09:50:00 "Some earlier agent" 70000
mk_agent after "" 1 10:30:00 "Some later agent" 90000
tail_json
check_eq "(iii) only the subagent that starts inside the window counts (100+200+7000+8000)" "15300" "$(field 1 .cost)"
check_eq "(iii) the window's subagent turns: the 2 of the one counted agent" "2" "$(field 1 .subagent_turns)"
check_eq "(iii) exactly one subagent row under the window" "1" "$(field 1 '.subagents | length')"
check_eq "(iii) the row names the agent that starts inside" "inside" "$(field 1 '.subagents[0].agent_id')"

# --- (iv) two PRs in one session -> two windows ----------------------------------------------------
mk_session twoprs
{
  rec_turn R1 10:00:00 polish branch-one 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:01:00 polish branch-one 200 "$(bash_use toolu_1 'gh pr create --title one')"
  rec_result 10:01:05 toolu_1 false "$PRURL"
  rec_turn R3 10:02:00 go branch-two 5000 '[{"type":"text","text":"x"}]'
  rec_turn R4 10:03:00 polish branch-two 300 '[{"type":"text","text":"x"}]'
  rec_turn R5 10:04:00 polish branch-two 400 "$(bash_use toolu_2 'gh pr create --title two')"
  rec_result 10:04:05 toolu_2 false "$PRURL"
} > "$SF"
tail_json
check_eq "(iv) two PRs in one session: two window objects" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(iv) first window cost" "300" "$(field 1 .cost)"
check_eq "(iv) second window cost excludes the go turn between them" "700" "$(field 2 .cost)"
check_eq "(iv) both closed" "closedclosed" "$(field 1 .status)$(field 2 .status)"

# --- (vi) a window never closed -> `open`, flagged in the human form (never a closed window) ---------------
mk_session neverclosed
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:01:00 polish b1 200 '[{"type":"text","text":"x"}]'
} > "$SF"
tail_json
check_eq "(vi) a session that never opened its PR: one window, open" "open" "$(field 1 .status)"
check_eq "(vi) the open window still reports its cost" "300" "$(field 1 .cost)"
run bash "$tool" tail "$SF"
check_contains "(vi) the human form flags an open window" "$OUT" "open"

# --- (vii) wrap and keel-score turns are never in a window's cost -----------------------------------
mk_session wrapturns
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:00:30 wrap b1 5000 '[{"type":"text","text":"x"}]'
  rec_turn R3 10:00:40 keel-score b1 9000 '[{"type":"text","text":"x"}]'
  rec_turn R4 10:01:00 polish b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:01:05 toolu_p false "$PRURL"
  rec_turn R5 10:02:00 wrap b1 6000 '[{"type":"text","text":"x"}]'
  rec_turn R6 10:02:10 keel-score b1 8000 '[{"type":"text","text":"x"}]'
} > "$SF"
tail_json
check_eq "(vii) wrap/keel-score turns inside a still-open window are not counted (100+200)" "300" "$(field 1 .cost)"
check_eq "(vii) the wrap/keel-score turns after the PR open no window" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(vii) primary turns exclude them too" "2" "$(field 1 .primary_turns)"

# --- (viii) a second /polish invocation while a window is open EXTENDS it; after a close, a re-run is open
mk_session extend
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:01:00 polish b1 200 '[{"type":"text","text":"x"}]'
  rec_turn R3 10:02:00 "" b1 400 '[{"type":"text","text":"operator turn between the rounds"}]'
  rec_turn R4 10:03:00 polish b1 800 '[{"type":"text","text":"second invocation"}]'
  rec_turn R5 10:04:00 polish b1 1600 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:04:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(viii) a second invocation before the PR exists: ONE window" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(viii) it covers both rounds and the turn between (100+200+400+800+1600)" "3100" "$(field 1 .cost)"
check_eq "(viii) closed by the later success" "closed" "$(field 1 .status)"

mk_session rerun
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:00:05 toolu_p false "$PRURL"
  rec_turn R2 10:00:10 polish b1 50 '[{"type":"text","text":"PR status, same chain: not a new invocation"}]'
  rec_turn R3 10:05:00 "" b1 10 '[{"type":"text","text":"operator prompt"}]'
  rec_turn R4 10:06:00 polish b1 300 "$(bash_use toolu_q 'gh pr create --title t')"
  rec_result 10:06:05 toolu_q true "a pull request for branch b1 already exists"
} > "$SF"
tail_json
check_eq "(viii) a re-run on a closed branch: two windows (the chain's tail turn opens none)" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(viii) the first window closed" "closed" "$(field 1 .status)"
check_eq "(viii) the re-run window stays open" "open" "$(field 2 .status)"
check_eq "(viii) the re-run window's cost" "300" "$(field 2 .cost)"

mk_session rerun2
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:00:05 toolu_p false "$PRURL"
  rec_turn R3 10:05:00 "" b1 10 '[{"type":"text","text":"operator prompt"}]'
  rec_turn R4 10:06:00 polish b1 300 "$(bash_use toolu_q 'gh pr create --title t')"
  rec_result 10:06:05 toolu_q false "$PRURL"
} > "$SF"
tail_json
check_eq "(viii) a same-branch re-run never closes, even on a result that names a PR URL" "open" "$(field 2 .status)"

# a never-closing re-run window must not swallow the NEXT PR's tail (a different branch, same session)
mk_session rerun3
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:00:05 toolu_p false "$PRURL"
  rec_turn R3 10:05:00 "" b1 10 '[{"type":"text","text":"operator prompt"}]'
  rec_turn R4 10:06:00 polish b1 300 "$(bash_use toolu_q 'gh pr create --title t')"
  rec_result 10:06:05 toolu_q true "a pull request for branch b1 already exists"
  rec_turn R5 10:10:00 go b2 5000 '[{"type":"text","text":"next ticket"}]'
  rec_turn R6 10:11:00 polish b2 700 "$(bash_use toolu_r 'gh pr create --title t2')"
  rec_result 10:11:05 toolu_r false "$PRURL"
} > "$SF"
tail_json
check_eq "(viii) a re-run window then a different branch's PR: three windows" "3" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(viii) closed, open (the re-run), closed" "closed open closed" "$(field 1 .status) $(field 2 .status) $(field 3 .status)"
check_eq "(viii) the next PR's window has its own cost (not folded into the re-run's)" "700" "$(field 3 .cost)"
check_eq "(viii) the re-run window keeps only its own turns" "300" "$(field 2 .cost)"

# --- (ix) review_cost: B2's fixed-first-line subagents plus every agent whose parent chain reaches one --
mk_session review
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:20:00 polish b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:20:05 toolu_p false "$PRURL"
} > "$SF"
mk_agent rev1 ""    1 10:05:00 "$FIXED_LINE" 1000
mk_agent fork1 rev1 2 10:05:10 "recipe header for the fork" 2000
mk_agent kid1 fork1 3 10:05:20 "a depth-3 child of the fork" 3000
mk_agent rev2 ""    1 10:10:00 "$FIXED_LINE" 4000
mk_agent fork2 rev2 2 10:10:10 "recipe header for the second fork" 5000
# a /simplify subagent whose prompt QUOTES the fixed line, but not on its first line
f="$SDIR/$SESS_ID/subagents/agent-simp.jsonl"
jq -nc --arg ts "$(T 10:12:00)" --arg p $'Simplify review: reuse\n'"$FIXED_LINE" \
  '{type:"user", isSidechain:true, timestamp:$ts, message:{role:"user", content:$p}}' > "$f"
jq -nc --arg ts "$(T 10:12:01)" \
  '{type:"assistant", isSidechain:true, requestId:"req-simp-1", timestamp:$ts, message:{model:"m", content:[], usage:{output_tokens:1, cache_read_input_tokens:7000}}}' >> "$f"
printf '{"agentType":"general-purpose","spawnDepth":1}' > "${f%.jsonl}.meta.json"
tail_json
check_eq "(ix) review_cost is exactly the five chained agents (1000+2000+3000+4000+5000)" "15000" "$(field 1 .review_cost)"
check_eq "(ix) the window cost counts the simplify agent too (300 + 15000 + 7000)" "22300" "$(field 1 .cost)"
check_eq "(ix) six subagent rows under the window" "6" "$(field 1 '.subagents | length')"
check_eq "(ix) the fork row names its parent and depth" "rev1/2" \
  "$(field 1 '.subagents[] | select(.agent_id=="fork1") | "\(.parent_agent_id)/\(.depth)"')"
check_eq "(ix) the row carries the prompt's first line" "$FIXED_LINE" \
  "$(field 1 '.subagents[] | select(.agent_id=="rev1") | .first_line')"
check_eq "(ix) the simplify agent is not review cost: its row says so" "false" \
  "$(field 1 '.subagents[] | select(.agent_id=="simp") | .review')"
check_eq "(ix) the depth-3 child is review cost" "true" \
  "$(field 1 '.subagents[] | select(.agent_id=="kid1") | .review')"
run bash "$tool" tail "$SF"
check_contains "(ix) the human form prints a subagent row with its first line" "$OUT" "$FIXED_LINE"
check_contains "(ix) the human form prints the review cost" "$OUT" "15000"

# --- a fork whose parent is OUTSIDE the window is not review cost (chain must reach a B2 agent in it) --
mk_session orphan
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:20:00 polish b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:20:05 toolu_p false "$PRURL"
} > "$SF"
mk_agent notrev "" 1 10:05:00 "Some other agent" 1000
mk_agent child notrev 2 10:05:10 "its child" 2000
tail_json
check_eq "a subagent chain that never reaches a B2 agent is no review cost" "0" "$(field 1 .review_cost)"

# --- several files: each file's windows, in file order -----------------------------------------------
mk_session multi_a
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:00:05 toolu_p false "$PRURL"
} > "$SF"
fa="$SF"
mk_session multi_b
{
  rec_turn R1 11:00:00 polish b9 700 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 11:00:05 toolu_p false "$PRURL"
} > "$SF"
run bash "$tool" tail --json "$fa" "$SF"
check_eq "two files: one window each" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "two files: costs in file order" "100/700" "$(field 1 .cost)/$(field 2 .cost)"

# --- A1b: the tail path reads transcripts only through the shared reader -------------------------------
body="$(sed -n '/^cmd_tail()/,/^}/p' "$tool")"
check_contains "A1b: cmd_tail exists" "$body" "cmd_tail"
for fn in tu_turns tu_tool_calls tu_tool_results tu_subagent_meta; do
  check_contains "A1b: cmd_tail reads transcripts through $fn" "$body" "$fn"
done
check_absent "A1b: cmd_tail never hands a transcript file to jq itself" "$body" 'jq -c -s'

# --- dir #707: the second open signal (init's own output line) and the branch-bound window ---------
# INIT_OUT is the shape `tools/pre-pr-gate.sh init` prints; case (x7) below runs the real one.
INIT_OUT="$(printf 'pre-pr-gate: receipt %s (nonce %s)' started "$(date -u +%Y%m%dT%H%M%S)-4242-17")"   # built at run time: no tracked line looks like init's output

# --- (x1) a window opens on the init output when the Skill was not re-invoked ---------------------
mk_session x1
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:01:00 polish b1 200 "$(bash_use toolu_p1 'gh pr create --title t')"
  rec_result 10:01:05 toolu_p1 false "$PRURL"
  rec_turn R3 10:10:00 "" b2 5000 '[{"type":"text","text":"next ticket, no Skill call"}]'
  rec_turn R4 10:20:00 "" b2 400 "$(bash_use toolu_i 'B=tools/pre-pr-gate.sh; bash $B init 2>&1|tail -1')"
  rec_result 10:20:05 toolu_i false "$INIT_OUT"
  rec_turn R5 10:30:00 "" b2 600 "$(bash_use toolu_p2 'gh pr create --title t2')"
  rec_result 10:30:05 toolu_p2 false "$PRURL"
} > "$SF"
tail_json
check_eq "(x1) Skill once + init by text: two windows" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(x1) both closed" "closed closed" "$(field 1 .status) $(field 2 .status)"
check_eq "(x1) the init-opened window starts at the init turn" "$(T 10:20:00)" "$(field 2 .start)"
check_eq "(x1) its cost is its own two turns (400 + 600)" "1000" "$(field 2 .cost)"
check_eq "(x1) the first window is Skill-opened, the second init-opened" "skill init" "$(field 1 .opened_by) $(field 2 .opened_by)"

# --- (x2) the init signal needs init's own output line, in a Bash call's result -------------
mk_session x2
{
  rec_turn R1 10:00:00 "" b1 100 "$(bash_use toolu_g "grep -n 'receipt started' tools/pre-pr-gate.sh")"
  rec_result 10:00:05 toolu_g false "gate.sh:12:    printf 'pre-pr-gate: receipt started (nonce %s)\\n' \"\$nonce\"
pre-pr-gate: receipt started (nonce %s)"
  rec_turn R3 10:02:00 "" b1 100 '[{"type":"tool_use","id":"toolu_r","name":"Read","input":{"file_path":"/x/log.txt"}}]'
  rec_result 10:02:05 toolu_r false "$INIT_OUT"
  rec_turn R4 10:03:00 "" b1 100 "$(bash_use toolu_d 'tools/pre-pr-gate.sh init')"
  rec_result 10:03:05 toolu_d false "pre-pr-gate: cannot key the receipt — detached HEAD; check out the PR branch first"
  rec_turn R5 10:04:00 "" b1 100 "$(bash_use toolu_c 'gh pr create --title t')"
  rec_result 10:04:05 toolu_c false "$PRURL"
} > "$SF"
tail_json
check_eq "(x2) no real init output anywhere (grep of the source, a Read result, init's failure message): no window" "" "$OUT"

# --- (x3) S11-2 — an abandoned start does not swallow another branch's PR (Skill re-invoked) -------
mk_session x3
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"polish started, then abandoned"}]'
  rec_turn R2 10:05:00 "" b1 50 '[{"type":"text","text":"x"}]'
  rec_turn R3 10:10:00 "" b2 90000 '[{"type":"text","text":"another ticket entirely"}]'
  rec_turn R4 10:50:00 polish b2 300 '[{"type":"text","text":"x"}]'
  rec_turn R5 10:55:00 polish b2 400 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:55:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x3) two windows, not one mixed window" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(x3) the abandoned one is open and ends where the other branch's signal fires" \
  "open $(T 10:50:00)" "$(field 1 .status) $(field 1 .end)"
check_eq "(x3) the abandoned window keeps its own turns only (100 + 50 + 90000)" "90150" "$(field 1 .cost)"
check_eq "(x3) the second branch's window is closed with its own turns (300 + 400)" "closed 700" "$(field 2 .status) $(field 2 .cost)"

# --- (x3b) the same with init as the second branch's signal -------------------------------------------
mk_session x3b
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"polish started, then abandoned"}]'
  rec_turn R3 10:10:00 "" b2 90000 '[{"type":"text","text":"another ticket entirely"}]'
  rec_turn R4 10:50:00 "" b2 300 "$(bash_use toolu_i 'tools/pre-pr-gate.sh init')"
  rec_result 10:50:05 toolu_i false "$INIT_OUT"
  rec_turn R5 10:55:00 "" b2 400 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:55:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x3b) init on the other branch also ends the abandoned window: open then closed" "open closed" "$(field 1 .status) $(field 2 .status)"
check_eq "(x3b) the second window is init-opened with its own cost" "init 700" "$(field 2 .opened_by) $(field 2 .cost)"

# --- (x4) a PR created on another branch neither closes nor ends this branch's window --------------------
mk_session x4
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:10:00 "" b2 5000 "$(bash_use toolu_p 'gh pr create --title other')"
  rec_result 10:10:05 toolu_p false "$PRURL"
  rec_turn R3 10:20:00 "" b1 400 "$(bash_use toolu_q 'gh pr create --title mine')"
  rec_result 10:20:05 toolu_q false "$PRURL"
} > "$SF"
tail_json
check_eq "(x4) one window: the foreign PR closed nothing and did not end the window" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
check_eq "(x4) b1's own PR then closes it, the b2 turn counted (100 + 5000 + 400)" "closed 5500 3" "$(field 1 .status) $(field 1 .cost) $(field 1 .primary_turns)"

# --- (x5) a detached HEAD turn and unsignalled foreign-branch turns do not end a window -------------
mk_session x5
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:01:00 "" HEAD 200 '[{"type":"text","text":"mid-rebase"}]'
  rec_turn R3 10:02:00 "" b2 300 '[{"type":"text","text":"a turn from another worktree"}]'
  rec_turn R4 10:03:00 "" b1 400 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:03:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x5) one closed window holding all four turns" "closed 1000 4" "$(field 1 .status) $(field 1 .cost) $(field 1 .primary_turns)"

mk_session x5b
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:00:05 toolu_p false "$PRURL"
  rec_turn R2 10:05:00 "" b1 10 '[{"type":"text","text":"operator prompt"}]'
  rec_turn R3 10:06:00 polish b1 300 '[{"type":"text","text":"re-run on the open PR"}]'
  rec_turn R4 10:07:00 "" HEAD 50 '[{"type":"text","text":"mid-rebase"}]'
  rec_turn R5 10:08:00 "" b1 70 '[{"type":"text","text":"x"}]'
} > "$SF"
tail_json
check_eq "(x5b) a re-run window survives a detached-HEAD turn (300 + 50 + 70), still open to the end" \
  "open 420 null" "$(field 2 .status) $(field 2 .cost) $(field 2 .end)"

# --- (x6) opened_by: attribution wins when both signals share a turn ------------------------------------
mk_session x6
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_i 'tools/pre-pr-gate.sh init')"
  rec_result 10:00:05 toolu_i false "$INIT_OUT"
  rec_turn R2 10:01:00 polish b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:01:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x6) one window, opened by the Skill when both fire on one turn" "1 skill" "$(printf '%s\n' "$OUT" | grep -c .) $(field 1 .opened_by)"

# --- (x7) the predicate matches what the real `init` prints (the shared contract) ---------------------
cr="$SANDBOX/init-coupling-repo"; mkdir -p "$cr"; git -C "$cr" init -q
real_init="$(cd "$cr" && bash "$REPO_ROOT/tools/pre-pr-gate.sh" init 2>&1)"
mk_session x7
{
  rec_turn R1 10:00:00 "" b1 100 "$(bash_use toolu_i 'tools/pre-pr-gate.sh init')"
  rec_result 10:00:05 toolu_i false "$real_init"
  rec_turn R2 10:01:00 "" b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:01:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x7) the real init's output opens a window" "closed init 300" "$(field 1 .status) $(field 1 .opened_by) $(field 1 .cost)"


# --- (x11) an init chained with a failing command (is_error result) still ran: it opens the window --------
mk_session x11
{
  rec_turn R1 10:00:00 "" b1 100 "$(bash_use toolu_i 'tools/pre-pr-gate.sh init && tools/pre-pr-gate.sh receipt --recover')"
  rec_result 10:00:05 toolu_i true "Exit code 1
$INIT_OUT
pre-pr-gate: nothing to recover — no receipt was retired since the last init"
  rec_turn R2 10:01:00 "" b1 200 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:01:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x11) an init whose call errored afterwards opens a window" "closed init 300" "$(field 1 .status) $(field 1 .opened_by) $(field 1 .cost)"

# --- (x12) a grep/diff/cat that PRINTS the line inside other text opens nothing; init's own whole line does ---------
mk_session x12
{
  rec_turn R1 10:00:00 "" b1 100 "$(bash_use toolu_g "grep -n 'receipt' tests/test_session_cost_tail.sh")"
  rec_result 10:00:05 toolu_g false "343:INIT_OUT='$INIT_OUT'
344:+  rec_turn R1 10:00:00 \"\" b1 100 \"$INIT_OUT\""
  rec_turn R2 10:10:00 "" b1 50000 '[{"type":"text","text":"implementing"}]'
  rec_turn R3 10:20:00 polish b1 300 '[{"type":"text","text":"x"}]'
  rec_turn R4 10:30:00 "" b1 400 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:30:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x12) a printed look-alike opens nothing: the Skill turn opens the window (300 + 400)" "closed skill 700" \
  "$(field 1 .status) $(field 1 .opened_by) $(field 1 .cost)"

# --- (x8) a window opened on a turn with no real branch is unbound: it adopts no branch, so a signal on b3 after a b2 turn abandons nothing ----
mk_session x8
{
  rec_turn R1 10:00:00 polish "" 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:10:00 "" b2 5000 '[{"type":"text","text":"x"}]'
  rec_turn R3 10:20:00 polish b3 300 '[{"type":"text","text":"x"}]'
  rec_turn R4 10:30:00 polish b3 400 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:30:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x8) an unbound window is never abandoned: one closed window of all four turns" "1 closed 5800" \
  "$(printf '%s\n' "$OUT" | grep -c .) $(field 1 .status) $(field 1 .cost)"

# --- (x9) an init inside an open window (a convergence round's re-init) does not restart it ----------------
mk_session x9
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:10:00 "" b1 200 "$(bash_use toolu_i 'tools/pre-pr-gate.sh init')"
  rec_result 10:10:05 toolu_i false "$INIT_OUT"
  rec_turn R3 10:20:00 "" b1 300 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:20:05 toolu_p false "$PRURL"
} > "$SF"
tail_json
check_eq "(x9) one window from the Skill turn, holding the re-init round" "1 closed $(T 10:00:00) 600 skill" \
  "$(printf '%s\n' "$OUT" | grep -c .) $(field 1 .status) $(field 1 .start) $(field 1 .cost) $(field 1 .opened_by)"

# --- (x10) an init after a window closed on the same branch is a re-run: its window never closes ---------
mk_session x10
{
  rec_turn R1 10:00:00 polish b1 100 "$(bash_use toolu_p 'gh pr create --title t')"
  rec_result 10:00:05 toolu_p false "$PRURL"
  rec_turn R2 10:05:00 "" b1 10 '[{"type":"text","text":"operator prompt"}]'
  rec_turn R3 10:06:00 "" b1 300 "$(bash_use toolu_i 'tools/pre-pr-gate.sh init')"
  rec_result 10:06:05 toolu_i false "$INIT_OUT"
  rec_turn R4 10:07:00 "" b1 400 "$(bash_use toolu_q 'gh pr create --title t')"
  rec_result 10:07:05 toolu_q true "a pull request for branch b1 already exists"
} > "$SF"
tail_json
check_eq "(x10) closed, then an init-opened re-run window that stays open" "closed open init 700" \
  "$(field 1 .status) $(field 2 .status) $(field 2 .opened_by) $(field 2 .cost)"


# --- dir #707 (A6): the doc and the tool's header comment state the second signal and the branch binding ---
doc_folded="$(tr '\n' ' ' < "$REPO_ROOT/docs/session-cost.md" | tr -s ' ')"
check_contains "A6: the doc names the init line as the second signal" "$doc_folded" "receipt started"
check_contains "A6: the doc lists opened_by in the --json fields" "$doc_folded" "opened_by"
check_contains "A6: the doc's open-window bullet names an abandoned start" "$doc_folded" "abandoned"
check_absent "A6: the doc no longer states the Skill-only window rule" "$doc_folded" "attributed to \`polish\` that follows a turn attributed otherwise, and closes at the primary turn"
hdr="$(sed -n '/^# --- tail/,/^SC_REVIEW_FIRST_LINE=/p' "$tool" | grep '^#')"
check_contains "A6: the header comment names SC_INIT_LINE_RE" "$hdr" "SC_INIT_LINE_RE"
check_contains "A6: the header comment binds a window to its branch" "$hdr" "branch it opened on"
check_absent "A6: the header comment no longer states the Skill-only open rule" "$hdr" "A window opens at the first primary turn attributed"

# --- dir #737: the human form ends with ONE coverage line — PRs created vs windows, naming each PR outside any window ---
PRURL2='https://github.com/example-org/example-repo/pull/77'
mk_session cov
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:05:00 polish b1 200 "$(bash_use toolu_a 'gh pr create --title mine')"
  rec_result 10:05:05 toolu_a false "$PRURL"
  rec_turn R3 11:00:00 "" b2 300 "$(bash_use toolu_b 'gh pr create --title orphan')"
  rec_result 11:00:05 toolu_b false "$PRURL2"
  rec_turn R4 11:10:00 "" b3 300 "$(bash_use toolu_c 'gh pr create --title denied')"
  rec_result 11:10:05 toolu_c true "gate denied: no receipt"
} > "$SF"
run bash "$tool" tail "$SF"
check_status "(737) tail with a PR outside any window exits 0" "0" "$STATUS"
check_eq "(737) exactly one coverage line" "1" "$(printf '%s\n' "$OUT" | grep -c '^coverage:')"
check_contains "(737) the line counts both successful PRs (the denied one is not a PR) and the one closed window" "$OUT" "pr-create=2 closed-windows=1 outside-any-window=1"
check_contains "(737) the line names the PR outside any window" "$OUT" "$PRURL2"
check_absent "(737) the covered PR is not named anywhere in the output" "$OUT" "$PRURL"
check_contains "(737) the line carries the full session id" "$OUT" "coverage: $SESS_ID "
tail_json
check_absent "(737) --json stays one object per window: no coverage line" "$OUT" "coverage:"

mk_session covpar
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:05:00 polish b1 200 "$(jq -nc --arg u1 'gh pr create --title a' --arg u2 'gh pr create --title b' '[{type:"tool_use",id:"toolu_a",name:"Bash",input:{command:$u1}},{type:"tool_use",id:"toolu_b",name:"Bash",input:{command:$u2}}]')"
  rec_result 10:05:05 toolu_a false "$PRURL"
  rec_result 10:05:06 toolu_b false "$PRURL2"
} > "$SF"
run bash "$tool" tail "$SF"
check_contains "(737) two PRs on one closing turn: one window, so one is outside any window" "$OUT" "pr-create=2 closed-windows=1 outside-any-window=1"

mk_session covwarn
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 11:00:00 "" b2 200 "$(bash_use toolu_a 'gh pr create --title orphan')"
  rec_result 11:00:05 toolu_a false "warning: see $PRURL for the template
$PRURL2"
} > "$SF"
run bash "$tool" tail "$SF"
check_contains "(737) a result quoting another PR first: the LAST URL (the new PR) is named" "$OUT" "outside-any-window=1 $PRURL2"

mk_session covok
{
  rec_turn R1 10:00:00 polish b1 100 '[{"type":"text","text":"x"}]'
  rec_turn R2 10:05:00 polish b1 200 "$(bash_use toolu_a 'gh pr create --title mine')"
  rec_result 10:05:05 toolu_a false "$PRURL"
} > "$SF"
run bash "$tool" tail "$SF"
check_contains "(737) every PR in a window: outside-any-window=0" "$OUT" "pr-create=1 closed-windows=1 outside-any-window=0"

summary
