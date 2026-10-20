#!/usr/bin/env bash
# tests/test_session_cost_manifest.sh — dir #654: a release ledger's worker branches -> the `table`
# manifest (tu_files_for_branches, tu_files_for_branch + `session-cost.sh manifest`), and the sum at the estimate's weights
# (`session-cost.sh weighted`). Every transcript here is synthetic and carries `gitBranch` the way a
# real one does; the layout mirrors the harness's (main dir + `--claude-worktrees-*` dirs).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="$REPO_ROOT/tools/self/session-cost.sh"
# shellcheck source=tools/lib/transcript-usage.sh
. "$REPO_ROOT/tools/lib/transcript-usage.sh"

repo="$SANDBOX/relrepo"
mkdir -p "$repo"; repo="$(cd "$repo" && pwd -P)"  # the harness slugs the PHYSICAL cwd (macOS: /var -> /private/var)
slug="$(tu_project_slug "$repo")"
proj="$(tu_projects_root)"
wt_a="$proj/${slug}--claude-worktrees-w1-aaaa"
wt_b="$proj/${slug}--claude-worktrees-w2-bbbb"
mkdir -p "$wt_a" "$wt_b" "$proj/$slug"

# turn LINE helper: one assistant record on BRANCH with input/write/read/output token counts
turn() { # turn BRANCH REQ INPUT WRITE READ OUT
  printf '{"type":"assistant","requestId":"%s","sessionId":"s","timestamp":"t","gitBranch":"%s","message":{"model":"claude-sonnet-5","content":[],"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$2" "$1" "$3" "$4" "$5" "$6"
}

# W1: ONE branch across TWO session files (a start/restart) in the same worktree dir, plus a subagent.
f1="$wt_a/11111111-1111-1111-1111-111111111111.jsonl"
f1b="$wt_a/11111111-2222-2222-2222-222222222222.jsonl"
{ turn claude/w1-x r1 10 100 1000 50; turn claude/w1-x r1 10 100 1000 50; turn claude/w1-x r2 20 0 2000 5; } > "$f1"
turn claude/w1-x r3 1 1 100 1 > "$f1b"
mkdir -p "$wt_a/11111111-1111-1111-1111-111111111111/subagents"
turn claude/w1-x rs 5 10 500 7 > "$wt_a/11111111-1111-1111-1111-111111111111/subagents/agent-s.jsonl"
# W2: a DIFFERENT branch that recycled the same worktree-name shape; its dir name says nothing about W1.
f2="$wt_b/22222222-2222-2222-2222-222222222222.jsonl"
turn claude/w2-y q1 100 0 10 1 > "$f2"
# a decoy: mentions W1's branch only as a prefix of another branch name, in the main dir
fd="$proj/$slug/33333333-3333-3333-3333-333333333333.jsonl"
turn claude/w1-x-extra d1 999 999 999 999 > "$fd"

# --- tu_files_for_branch ---------------------------------------------------------------------------
got="$(tu_files_for_branch "$repo" claude/w1-x | sort)"
check_contains "tu_files_for_branch finds the branch's first session file" "$got" "$f1"
check_contains "tu_files_for_branch finds its restart file in the same dir" "$got" "$f1b"
check_absent "tu_files_for_branch ignores a different worktree's session" "$got" "$f2"
check_absent "tu_files_for_branch matches the branch exactly, not as a prefix" "$got" "33333333"
check_eq "tu_files_for_branch: exactly 2 files for W1" "2" "$(printf '%s\n' "$got" | grep -c .)"
check_eq "tu_files_for_branch: an unknown branch yields nothing" "0" "$(tu_files_for_branch "$repo" claude/nope | grep -c .)"
check_eq "tu_files_for_branch: a branch with regex/glob chars matches literally" "0" "$(tu_files_for_branch "$repo" 'claude/w1-.' | grep -c .)"

# --- manifest ------------------------------------------------------------------------------------------
ledger="$SANDBOX/ledger.tsv"
printf '# comment\nW1\tR2\tsonnet\tclaude/w1-x\n\nW2\tR1\tsonnet\tclaude/w2-y\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest exits 0 when every branch matched" "0" "$STATUS"
check_contains "manifest emits the W1 row with both files comma-joined" "$OUT" "W1	R2	sonnet	"
check_contains "manifest row names the restart file" "$OUT" "$f1b"
check_contains "manifest emits the W2 row" "$OUT" "W2	R1	sonnet	$f2"

# the manifest feeds `table` as-is
mf="$SANDBOX/out-manifest.tsv"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf"
run bash "$tool" table "$mf"
check_status "table accepts the manifest's output" "0" "$STATUS"
check_contains "table sums W1 across both files (output 50+5+1=56)" "$OUT" "56"

# unmatched: reported, never dropped
printf 'W1\tR2\tsonnet\tclaude/w1-x\nW9\tR1\tsonnet\tclaude/ghost\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest exits 1 when a branch matched no session" "1" "$STATUS"
check_contains "manifest names the unmatched ticket and branch" "$OUT" "UNMATCHED"
check_contains "manifest names the unmatched branch" "$OUT" "claude/ghost"
check_contains "manifest still emits the matched row beside the unmatched one" "$OUT" "W1	R2	sonnet	"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf" 2>/dev/null
run bash "$tool" table "$mf"
check_status "table skips the unmatched marker line (a comment)" "0" "$STATUS"

printf 'onlytwo\tR1\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest refuses a malformed ledger line" "2" "$STATUS"
run bash "$tool" manifest --repo "$repo" "$SANDBOX/nope.tsv"
check_status "manifest on a missing ledger exits 2" "2" "$STATUS"
run bash "$tool" manifest
check_status "manifest with no ledger exits 2" "2" "$STATUS"

# a file that records BOTH of two ledger branches would be priced under both tickets: marked SHARED, exit 1
f3="$wt_b/44444444-4444-4444-4444-444444444444.jsonl"
{ turn claude/w2-y z1 1 0 1 1; turn claude/w1-x z2 1 0 1 1; } > "$f3"
printf 'W1\tR2\tsonnet\tclaude/w1-x\nW2\tR1\tsonnet\tclaude/w2-y\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest exits 1 for a session file shared by two ledger branches" "1" "$STATUS"
check_contains "manifest marks the shared file" "$OUT" "# SHARED:"
check_contains "manifest names both branches on the shared file" "$OUT" "claude/w1-x, claude/w2-y"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf" 2>/dev/null
run bash "$tool" weighted "$mf"
check_status "weighted over a SHARED manifest exits 1 (the total double-counts)" "1" "$STATUS"
check_contains "weighted repeats the SHARED line" "$OUT" "# SHARED:"
rm -f "$f3"

# a branch on two ledger lines would price its files twice: refused before anything prints
printf 'W1\tR2\tsonnet\tclaude/w1-x\nR1\tR2\tsonnet\tclaude/w1-x\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest refuses a branch listed twice" "2" "$STATUS"
check_contains "manifest names the duplicate" "$OUT" "on two ledger lines"

# a comma in a session path cannot ride a comma-joined FILE column; refused before any row prints
wt_c="$proj/${slug}--claude-worktrees-w3,comma"
mkdir -p "$wt_c"
turn claude/w3-c c1 1 0 1 1 > "$wt_c/55555555-5555-5555-5555-555555555555.jsonl"
printf 'W1\tR2\tsonnet\tclaude/w1-x\nW3\tR1\tsonnet\tclaude/w3-c\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest refuses a session path containing a comma" "2" "$STATUS"
check_contains "manifest names the comma problem" "$OUT" "contains a comma"
check_absent "manifest prints no row of a refused ledger (no truncated manifest)" "$OUT" "R2	sonnet"
rm -f "$wt_c"/*.jsonl

# --- weighted ------------------------------------------------------------------------------------------
printf 'W1\tR2\tsonnet\tclaude/w1-x\nW2\tR1\tsonnet\tclaude/w2-y\n' > "$ledger"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf"
# W1 primary: input 10+20+1=31, write 100+0+1=101, read 1000+2000+100=3100; subagent: 5,10,500
#   at 1,2,0.1: primary 31+202+310=543; subagent 5+20+50=75; total 618.  W2: 100+0+1=101.  grand 719.
run bash "$tool" weighted "$mf"
check_status "weighted exits 0 on a complete manifest" "0" "$STATUS"
check_contains "weighted prices W1 primary at the default 1,2,0.1 (543)" "$OUT" "543"
check_contains "weighted prices W1's subagent separately (75)" "$OUT" "75"
check_contains "weighted totals W1 = primary + subagent (618)" "$OUT" "618"
check_contains "weighted grand total (719)" "$OUT" "719"
check_contains "weighted states its weights as given" "$OUT" "weights: input=1.0 write=2.0 read=0.1"

run bash "$tool" weighted --weights 1,1,1 "$mf"
# W1 primary 31+101+3100=3232; subagent 515; total 3747; W2 110; grand 3857
check_contains "weighted --weights overrides (grand 3857)" "$OUT" "3857"
check_contains "weighted echoes the overriding weights" "$OUT" "weights: input=1 write=1 read=1"
run bash "$tool" weighted --weights 1,2,0.1234567 "$mf"
check_contains "weighted echoes a long weight unchanged (no reformatting)" "$OUT" "read=0.1234567"

run env KEEL_TOKENS_WEIGHTS=1,1,1 bash "$tool" weighted "$mf"
check_contains "weighted honours KEEL_TOKENS_WEIGHTS like keel tokens" "$OUT" "3857"
run bash "$tool" weighted --weights 1,x,1 "$mf"
check_status "weighted rejects malformed --weights" "2" "$STATUS"
run env KEEL_TOKENS_WEIGHTS=garbage bash "$tool" weighted "$mf"
check_status "weighted falls back to defaults on a malformed env var, as keel tokens does" "0" "$STATUS"
check_contains "weighted names the fallback" "$OUT" "malformed"
check_contains "weighted fallback uses the defaults (719)" "$OUT" "719"

# TOTAL is the sum of the printed (rounded) rows: with read weight 0.5, W1 primary 3100*0.5+... rounds per row
run bash "$tool" weighted --weights 1,1,0.55 "$mf"
# W1 primary 31+101+1705=1837 ; subagent 5+10+275=290 ; W2 100+0+5.5=105.5 -> 106 ; total column 1837+290+106=2233
check_contains "weighted TOTAL sums the rounded rows (2233)" "$OUT" "2233"

# an incomplete manifest: the total is printed, the unmatched line repeated, and the exit says incomplete
printf 'W1\tR2\tsonnet\tclaude/w1-x\nW9\tR1\tsonnet\tclaude/ghost\n' > "$ledger"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf" 2>/dev/null
run bash "$tool" weighted "$mf"
check_status "weighted on a manifest with an UNMATCHED line exits 1" "1" "$STATUS"
check_contains "weighted repeats the unmatched line" "$OUT" "UNMATCHED"
check_contains "weighted still prints the partial total" "$OUT" "TOTAL"

# --- dir #848: one bad line skips only itself, never the whole file ------------------------------------------
# A session still being written ends in a truncated line; a transcript can also carry a line that is valid JSON
# but not an object. Either used to abort jq for the WHOLE file, so a real worker read as unmatched.
wt_t="$proj/${slug}--claude-worktrees-w5-tolerant"
mkdir -p "$wt_t"
ft="$wt_t/66666666-6666-6666-6666-666666666666.jsonl"
{
  printf '"just a string"\n'
  turn claude/w5-z t1 1 0 1 1
  printf '42\n[1,2]\nnull\nnot json at all\n'
  turn claude/w5-z t2 1 0 1 1
  printf '{"type":"assistant","requestId":"cut","gitBranch":"claude/w5-trunc'
} > "$ft"
got="$(tu_files_for_branches "$repo" claude/w5-z)"
check_contains "a file with non-object and malformed lines still resolves its branch" "$got" "$ft"
check_eq "...and yields one pair, not one per bad line" "1" "$(printf '%s\n' "$got" | grep -c .)"
check_eq "a branch that only a truncated last line names is no match" "0" "$(tu_files_for_branches "$repo" claude/w5-trunc | grep -c .)"
printf 'W5\tR3\tsonnet\tclaude/w5-z\n' > "$ledger"
run bash "$tool" manifest --repo "$repo" "$ledger"
check_status "manifest resolves a worker whose transcript has bad lines" "0" "$STATUS"
check_contains "manifest row names the tolerant file" "$OUT" "$ft"
printf 'W5\tR3\tsonnet\tclaude/w5-z\n' > "$ledger"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf" 2>/dev/null
run bash "$tool" weighted "$mf"
check_contains "weighted prices the tolerant file" "$OUT" "W5"
rm -f "$ft"

# --- dir #852: the same bad lines in the PRICING readers (weighted/table/session/selfcheck/tail) -------------
# dir #848 fixed only the branch resolver; the readers slurped the file and died on the first bad line, so the
# dirty twin below used to exit 1 (the `weighted prices the tolerant file` check above passed on the FAILURE text).
wt_d="$proj/${slug}--claude-worktrees-w6-dirty"
mkdir -p "$wt_d"
fclean="$wt_d/77777777-7777-7777-7777-777777777777.jsonl"
fdirty="$wt_d/88888888-8888-8888-8888-888888888888.jsonl"
{ turn claude/w6-d t1 3 5 7 11; turn claude/w6-d t2 13 17 19 23; } > "$fclean"
{
  turn claude/w6-d t1 3 5 7 11
  printf '42\n[1,2]\nnull\n"str"\nnot json at all\n'
  turn claude/w6-d t2 13 17 19 23 | sed 's/$/\r/'
  printf '{"type":"assistant","requestId":"cut","gitBranch":"claude/w6-trunc'
} > "$fdirty"
printf 'D1\tR3\tsonnet\t%s\n' "$fclean" > "$mf.clean"
printf 'D1\tR3\tsonnet\t%s\n' "$fdirty" > "$mf.dirty"
run bash "$tool" weighted "$mf.clean"
clean_status="$STATUS"; clean_out="$OUT"
check_status "weighted on the clean twin exits 0" "0" "$clean_status"
run bash "$tool" weighted "$mf.dirty"
check_status "weighted on a file with truncated, non-object and CRLF lines exits 0" "0" "$STATUS"
check_eq "...and prices it at the clean twin's number" "$(grep '^TOTAL' <<<"$clean_out")" "$(grep '^TOTAL' <<<"$OUT")"
run bash "$tool" table "$mf.dirty"
check_status "table on the dirty file exits 0" "0" "$STATUS"
run bash "$tool" session --json "$fdirty"
check_status "session --json on the dirty file exits 0" "0" "$STATUS"
check_contains "...and counts both real turns" "$OUT" '"turns":2'
run bash "$tool" selfcheck "$fdirty"
check_status "selfcheck on the dirty file exits 0" "0" "$STATUS"
check_contains "selfcheck REPORTS the skipped-line count (5 non-object/bad + 1 truncated)" "$OUT" '"skipped_lines":6'
run bash "$tool" selfcheck "$fclean"
check_contains "selfcheck on a clean file reports zero skipped" "$OUT" '"skipped_lines":0'

# a tool_use whose cwd or file_path is not a string used to abort `startswith()` for the whole file (tail --json)
ftail="$wt_d/99999999-9999-9999-9999-999999999999.jsonl"
{
  printf '{"type":"assistant","requestId":"a1","cwd":5,"timestamp":"t","message":{"content":[{"type":"tool_use","id":"u1","name":"Read","input":{"file_path":"/x/y"}}],"usage":{"output_tokens":1}}}\n'
  printf '{"type":"assistant","requestId":"a2","cwd":"/x","timestamp":"t","message":{"content":[{"type":"tool_use","id":"u2","name":"Read","input":{"file_path":7}}],"usage":{"output_tokens":1}}}\n'
  printf '{"type":"user","message":"plain string, not an object"}\n{"type":"user","message":{"content":"x"}}\n'
  printf '{"type":"assistant","requestId":"a3","message":"str"}\n{"type":"assistant","requestId":{"x":1},"message":{"usage":5}}\n'
  printf '{"type":"assistant","requestId":"a4","timestamp":"t","message":{"content":[{"type":"tool_use","id":"u4","name":"Bash","input":"not an object"}],"usage":{"output_tokens":2}}}\n'
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"u4","content":"ok"}]}}\n'
} > "$ftail"
run bash "$tool" tail --json "$ftail"
check_status "tail --json survives a non-string cwd / file_path" "0" "$STATUS"
calls="$(tu_tool_calls primary "$ftail" 2>/dev/null)"
check_status "tu_tool_calls reads every call past a non-string field" "0" "$?"
check_eq "...three calls, the one with a non-object input kept" "3" "$(printf '%s\n' "$calls" | grep -c .)"
check_eq "tu_tool_results reads past a non-object message" "1" "$(tu_tool_results primary "$ftail" 2>/dev/null | grep -c .)"
check_eq "tu_turns keeps the 3 real turns past a non-object message, a non-object usage and an object requestId" "3" "$(tu_turns primary "$ftail" 2>/dev/null | grep -c .)"
run bash "$tool" selfcheck "$ftail"
check_status "selfcheck survives a non-object message" "0" "$STATUS"
check_contains "...counting the two usage-less assistant records and the bad lines" "$OUT" '"assistant_no_usage":2'
check_eq "tu_turns keeps the first turn's tokens intact" "1" "$(tu_turns primary "$ftail" 2>/dev/null | jq -s '[.[] | select(.requestId == "a1")] | .[0].output_tokens')"

# a manifest line that resolves no file is priced as zero with a note, never an abort (bash 3.2 empty-array expansion)
printf 'Z1\tR1\tsonnet\t,\n' > "$mf.empty"
run /bin/bash "$tool" weighted "$mf.empty"
check_status "weighted on a manifest line resolving no file exits 0 (bash as /bin/bash)" "0" "$STATUS"
check_contains "...with a note saying it was priced as zero" "$OUT" "no session file"
check_contains "...and still prints a total" "$OUT" "TOTAL"
rm -f "$fclean" "$fdirty" "$ftail" "$mf.clean" "$mf.dirty" "$mf.empty"

summary
