#!/usr/bin/env bash
# tests/test_session_cost_manifest.sh — dir #654: a release ledger's worker branches -> the `table`
# manifest (tu_files_for_branch + `session-cost.sh manifest`), and the sum at the estimate's weights
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

# --- weighted ------------------------------------------------------------------------------------------
printf 'W1\tR2\tsonnet\tclaude/w1-x\nW2\tR1\tsonnet\tclaude/w2-y\nW9\tR1\tsonnet\tclaude/ghost\n' > "$ledger"
bash "$tool" manifest --repo "$repo" "$ledger" > "$mf" 2>/dev/null
# W1 primary: input 10+20+1=31, write 100+0+1=101, read 1000+2000+100=3100; subagent: 5,10,500
#   at 1,2,0.1: primary 31+202+310=543; subagent 5+20+50=75; total 618.  W2: 100+0+1=101.  grand 719.
run bash "$tool" weighted "$mf"
check_status "weighted exits 0" "0" "$STATUS"
check_contains "weighted prices W1 primary at the default 1,2,0.1 (543)" "$OUT" "543"
check_contains "weighted prices W1's subagent separately (75)" "$OUT" "75"
check_contains "weighted totals W1 = primary + subagent (618)" "$OUT" "618"
check_contains "weighted grand total (719)" "$OUT" "719"
check_contains "weighted states its weights" "$OUT" "weights: input=1 write=2 read=0.1"
check_contains "weighted carries the unmatched line through" "$OUT" "UNMATCHED"

run bash "$tool" weighted --weights 1,1,1 "$mf"
# W1 primary 31+101+3100=3232; subagent 515; total 3747; W2 110; grand 3857
check_contains "weighted --weights overrides (grand 3857)" "$OUT" "3857"
check_contains "weighted echoes the overriding weights" "$OUT" "weights: input=1 write=1 read=1"

run env KEEL_TOKENS_WEIGHTS=1,1,1 bash "$tool" weighted "$mf"
check_contains "weighted honours KEEL_TOKENS_WEIGHTS like keel tokens" "$OUT" "3857"
run bash "$tool" weighted --weights 1,x,1 "$mf"
check_status "weighted rejects malformed --weights" "2" "$STATUS"
run env KEEL_TOKENS_WEIGHTS=garbage bash "$tool" weighted "$mf"
check_status "weighted falls back to defaults on a malformed env var, as keel tokens does" "0" "$STATUS"
check_contains "weighted names the fallback" "$OUT" "malformed"
check_contains "weighted fallback uses the defaults (719)" "$OUT" "719"

summary
