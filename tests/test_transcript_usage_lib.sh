#!/usr/bin/env bash
# tests/test_transcript_usage_lib.sh — dir #313: tools/lib/transcript-usage.sh is the shared reader
# both dir #313's own tools/self/session-cost.sh and dir #314's adopter-facing report import, so its
# correctness is load-bearing for two tickets at once. Every fixture here is SYNTHETIC — no real
# transcript content from this machine's ~/.claude/projects ever enters a tracked file (CLAUDE.md's
# own rule); the shapes are copied by hand from what was verified live against real files during
# implementation (see the lib's own header comment for the empirical basis).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

lib="$REPO_ROOT/tools/lib/transcript-usage.sh"
check_file "tools/lib/transcript-usage.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

# Isolate every test from the operator's real transcripts: KEEL_HOME points tu_projects_root at a
# scratch tree instead of "$HOME/.claude" (dir #125's own isolation-env-from-the-start convention).
KEEL_HOME="$SANDBOX/keelhome"
export KEEL_HOME
mkdir -p "$KEEL_HOME"

# --- tu_projects_root / tu_project_slug ------------------------------------------------------------
check_status "tu_projects_root honors KEEL_HOME" "$KEEL_HOME/projects" "$(tu_projects_root)"

repo="$SANDBOX/repo"
mkdir -p "$repo/.claude/worktrees/wt-1"
slug_main="$(tu_project_slug "$repo")"
slug_wt="$(tu_project_slug "$repo/.claude/worktrees/wt-1")"
check_contains "tu_project_slug replaces every '/' with '-'" "$slug_main" "-repo"
check_absent "tu_project_slug leaves no '/' in the slug" "$slug_main" "/"
check_contains "tu_project_slug replaces the worktree path's '.' too (double-dash before claude)" \
  "$slug_wt" "repo--claude-worktrees-wt-1"

if slug_missing="$(tu_project_slug "$SANDBOX/does-not-exist" 2>/dev/null)"; then
  fail "tu_project_slug fails on a nonexistent directory" "got '$slug_missing'"
else
  pass "tu_project_slug fails on a nonexistent directory"
fi

# --- tu_repo_top: what every tu_session_files caller needs to resolve its REPO_TOP argument ----------
# Promoted here from a near-verbatim duplicate first written independently in dir #314's own
# token-report.sh (itself mirroring tools/lib/impact-store.sh's own chain) — one shared implementation
# instead of two, the same reasoning that keeps the dedupe logic in this file singular.
plain_repo="$(new_repo)"
# git reports a worktree's path at its PHYSICAL location (macOS: /tmp and /var/folders are themselves
# symlinks into /private) — compare against that, not new_repo()'s own unresolved mktemp path
# (reproduced live: this test failed on macOS before the fix, comparing the wrong form).
plain_repo_p="$(cd "$plain_repo" && pwd -P)"
check_status "tu_repo_top resolves a plain (non-worktree) repo to its own toplevel" \
  "$plain_repo_p" "$(tu_repo_top "$plain_repo")"

git -C "$plain_repo" commit --allow-empty -qm init
wt_dir="$SANDBOX/repo-worktree"
git -C "$plain_repo" worktree add -q "$wt_dir" -b wt-branch
check_status "tu_repo_top folds a worktree back to the MAIN checkout's top" \
  "$plain_repo_p" "$(tu_repo_top "$wt_dir")"

non_repo="$SANDBOX/not-a-repo"
mkdir -p "$non_repo"
non_repo_p="$(cd "$non_repo" && pwd -P)"
check_status "tu_repo_top falls back to DIR's own physical path outside any git repo" \
  "$non_repo_p" "$(tu_repo_top "$non_repo")"

# --- tu_session_files: own dir + worktree-prefixed siblings, never an unrelated project -------------
proj_root="$(tu_projects_root)"
mkdir -p "$proj_root/$slug_main" "$proj_root/${slug_main}--claude-worktrees-alpha" \
  "$proj_root/${slug_main}--claude-worktrees-beta" "$proj_root/-some-other-project"
: > "$proj_root/$slug_main/main-session.jsonl"
: > "$proj_root/${slug_main}--claude-worktrees-alpha/alpha-session.jsonl"
: > "$proj_root/${slug_main}--claude-worktrees-beta/beta-session.jsonl"
: > "$proj_root/-some-other-project/unrelated.jsonl"

found="$(tu_session_files "$repo" | sort)"
check_contains "tu_session_files finds the main checkout's own session" "$found" "main-session.jsonl"
check_contains "tu_session_files finds a worktree's session (prefix glob)" "$found" "alpha-session.jsonl"
check_contains "tu_session_files finds a SECOND worktree's session too" "$found" "beta-session.jsonl"
check_absent "tu_session_files never returns an unrelated project's session" "$found" "unrelated.jsonl"
check_status "tu_session_files: exactly 3 files for this repo" "3" "$(tu_session_files "$repo" | wc -l | tr -d ' ')"

no_sessions_repo="$SANDBOX/never-run"
mkdir -p "$no_sessions_repo"
check_status "tu_session_files: a project with no sessions yields empty output, not an error" \
  "0" "$(tu_session_files "$no_sessions_repo" | wc -l | tr -d ' ')"

# --- tu_subagent_files -------------------------------------------------------------------------------
sess_dir="$proj_root/$slug_main"
sess_file="$sess_dir/11111111-1111-1111-1111-111111111111.jsonl"
: > "$sess_file"
check_status "tu_subagent_files: a session with no subagents yields empty output" \
  "0" "$(tu_subagent_files "$sess_file" | wc -l | tr -d ' ')"

mkdir -p "$sess_dir/11111111-1111-1111-1111-111111111111/subagents"
: > "$sess_dir/11111111-1111-1111-1111-111111111111/subagents/agent-aaa.jsonl"
: > "$sess_dir/11111111-1111-1111-1111-111111111111/subagents/agent-bbb.jsonl"
: > "$sess_dir/11111111-1111-1111-1111-111111111111/subagents/agent-aaa.meta.json"
sub_found="$(tu_subagent_files "$sess_file" | sort)"
check_contains "tu_subagent_files finds agent-aaa.jsonl" "$sub_found" "agent-aaa.jsonl"
check_contains "tu_subagent_files finds agent-bbb.jsonl" "$sub_found" "agent-bbb.jsonl"
check_absent "tu_subagent_files never returns the .meta.json sibling" "$sub_found" ".meta.json"
check_status "tu_subagent_files: exactly 2 agent transcripts" "2" "$(tu_subagent_files "$sess_file" | wc -l | tr -d ' ')"

# --- tu_turns: the requestId dedupe (the ticket's own founding defect) ------------------------------
# One API response split across three JSONL lines (thinking/text/tool_use), sharing one requestId and
# byte-identical usage but different timestamps — the exact shape verified live against a real
# transcript (see the lib's header comment).
dedupe_file="$SANDBOX/dedupe.jsonl"
cat > "$dedupe_file" <<'EOF'
{"type":"assistant","isSidechain":false,"gitBranch":"claude/go-1-abc","requestId":"req_A","sessionId":"sess-1","effort":"high","attributionSkill":"go","timestamp":"2026-09-06T10:00:00.000Z","message":{"model":"claude-sonnet-5","content":[{"type":"thinking"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":5000,"output_tokens":50,"output_tokens_details":{"thinking_tokens":10},"cache_creation":{"ephemeral_1h_input_tokens":100,"ephemeral_5m_input_tokens":0}}}}
{"type":"assistant","isSidechain":false,"gitBranch":"claude/go-1-abc","requestId":"req_A","sessionId":"sess-1","effort":"high","attributionSkill":"go","timestamp":"2026-09-06T10:00:00.100Z","message":{"model":"claude-sonnet-5","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":5000,"output_tokens":50,"output_tokens_details":{"thinking_tokens":10},"cache_creation":{"ephemeral_1h_input_tokens":100,"ephemeral_5m_input_tokens":0}}}}
{"type":"assistant","isSidechain":false,"gitBranch":"claude/go-1-abc","requestId":"req_A","sessionId":"sess-1","effort":"high","attributionSkill":"go","timestamp":"2026-09-06T10:00:00.480Z","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":5000,"output_tokens":50,"output_tokens_details":{"thinking_tokens":10},"cache_creation":{"ephemeral_1h_input_tokens":100,"ephemeral_5m_input_tokens":0}}}}
{"type":"assistant","isSidechain":false,"gitBranch":"claude/go-1-abc","requestId":"req_B","sessionId":"sess-1","effort":"high","attributionSkill":"go","timestamp":"2026-09-06T10:00:01.000Z","message":{"model":"claude-sonnet-5","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":5100,"output_tokens":20,"output_tokens_details":{"thinking_tokens":0},"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}}}}
{"type":"user","sessionId":"sess-1"}
{"type":"attachment","sessionId":"sess-1"}
EOF

turns="$(tu_turns primary "$dedupe_file")"
n_turns="$(printf '%s\n' "$turns" | jq -s 'length')"
check_status "tu_turns: 4 assistant-with-usage lines dedupe to 2 turns (req_A once, req_B once)" "2" "$n_turns"

cache_read_sum="$(printf '%s\n' "$turns" | jq -s '[.[].cache_read_input_tokens] | add')"
check_status "tu_turns: dedup sum is 10100 (5000 once + 5100), not 5000*3+5100=20100" "10100" "$cache_read_sum"

first_ts="$(printf '%s\n' "$turns" | jq -s -r '.[] | select(.requestId=="req_A") | .timestamp')"
check_status "tu_turns: the surviving req_A record keeps the FIRST (earliest) timestamp" \
  "2026-09-06T10:00:00.000Z" "$first_ts"

check_contains "tu_turns exposes cache_creation TTL buckets" "$turns" '"cache_creation_1h":100'
check_contains "tu_turns exposes gitBranch/effort/attributionSkill" "$turns" '"gitBranch":"claude/go-1-abc"'
check_contains "tu_turns exposes gitBranch/effort/attributionSkill" "$turns" '"effort":"high"'
check_contains "tu_turns exposes gitBranch/effort/attributionSkill" "$turns" '"attributionSkill":"go"'
check_contains "tu_turns stamps the caller-supplied kind" "$turns" '"kind":"primary"'

# --- tu_turns: two DISTINCT requestId-less turns must never collide (dir #313 review — a code-review
# pass reproduced live that an earlier version of this dedupe coerced every missing requestId to the
# SAME "" key, silently dropping every requestId-less turn after the first) --------------------------
noreqid_file="$SANDBOX/noreqid.jsonl"
cat > "$noreqid_file" <<'EOF'
{"type":"assistant","message":{"usage":{"output_tokens":100,"cache_read_input_tokens":1000}}}
{"type":"assistant","message":{"usage":{"output_tokens":200,"cache_read_input_tokens":2000}}}
EOF
noreqid_turns="$(tu_turns primary "$noreqid_file")"
check_status "tu_turns: two requestId-less turns are NOT deduped against each other" \
  "2" "$(printf '%s\n' "$noreqid_turns" | jq -s 'length')"
check_status "tu_turns: both requestId-less turns' tokens survive (100+200=300, not 100)" \
  "300" "$(printf '%s\n' "$noreqid_turns" | jq -s '[.[].output_tokens] | add')"

# --- tu_turns: a requestId-less turn must never collide with a REAL requestId either, even an
# adversarially-chosen one (dir #313 delta review — an earlier fix fell back to a synthetic string
# key derived from array index, which was collision-proof against real data but not, in principle,
# against a requestId equal to that exact synthetic string; fixed by never deduping a requestId-less
# record against anything at all, removing the possibility instead of narrowing it) ------------------
adversarial_file="$SANDBOX/adversarial.jsonl"
cat > "$adversarial_file" <<'EOF'
{"type":"assistant","requestId":"noreqid:1","message":{"usage":{"output_tokens":1}}}
{"type":"assistant","message":{"usage":{"output_tokens":2}}}
{"type":"assistant","message":{"usage":{"output_tokens":3}}}
EOF
check_status "tu_turns: a requestId-less turn survives even beside a requestId matching its own old synthetic key" \
  "3" "$(tu_turns primary "$adversarial_file" | jq -s 'length')"

# --- tu_turns: selects on type=="assistant" WITH usage — never any other type, never a usage-less one
mixed_file="$SANDBOX/mixed.jsonl"
cat > "$mixed_file" <<'EOF'
{"type":"assistant","requestId":"req_ok","sessionId":"s","timestamp":"t","message":{"model":"m","content":[],"usage":{"output_tokens":5}}}
{"type":"assistant","requestId":"req_no_usage","sessionId":"s","timestamp":"t","message":{"model":"m","content":[]}}
{"type":"system","sessionId":"s"}
{"type":"totally-new-unseen-type","sessionId":"s"}
EOF
check_status "tu_turns ignores an assistant record with no usage" \
  "1" "$(tu_turns primary "$mixed_file" | jq -s 'length')"

# --- tu_self_check: the visible guard against a format that moves --------------------------------
sc="$(tu_self_check "$mixed_file")"
check_contains "tu_self_check counts total lines" "$sc" '"total":4'
check_contains "tu_self_check counts assistant-with-usage" "$sc" '"assistant_usage":1'
check_contains "tu_self_check counts assistant-without-usage separately" "$sc" '"assistant_no_usage":1'
check_contains "tu_self_check counts known-other types (system)" "$sc" '"known_other":1'
check_contains "tu_self_check names an unrecognized type instead of silently absorbing it" \
  "$sc" '"unrecognized_types":["totally-new-unseen-type"]'

sc_dedupe="$(tu_self_check "$dedupe_file")"
check_contains "tu_self_check: the dedupe fixture has 0 unrecognized types" "$sc_dedupe" '"unrecognized_types":[]'

# --- tu_tool_calls: NOT deduped, and normalizes file_path against the record's own cwd -------------
path_file="$SANDBOX/paths.jsonl"
cat > "$path_file" <<'EOF'
{"type":"assistant","requestId":"req_A","timestamp":"t1","cwd":"/repo/.claude/worktrees/wt-1","message":{"model":"m","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/.claude/worktrees/wt-1/docs/x.md"}}],"usage":{"output_tokens":1}}}
{"type":"assistant","requestId":"req_A","timestamp":"t2","cwd":"/repo/.claude/worktrees/wt-1","message":{"model":"m","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/.claude/worktrees/wt-1/docs/y.md"}}],"usage":{"output_tokens":1}}}
{"type":"assistant","requestId":"req_A","timestamp":"t3","cwd":"/repo/.claude/worktrees/wt-1","message":{"model":"m","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/Users/x/.keel/kb/notes.md"}}],"usage":{"output_tokens":1}}}
EOF
calls="$(tu_tool_calls primary "$path_file")"
n_calls="$(printf '%s\n' "$calls" | jq -s 'length')"
check_status "tu_tool_calls: 3 tool_use occurrences under ONE requestId are all counted, never deduped" "3" "$n_calls"
check_contains "tu_tool_calls normalizes a cwd-prefixed path to repo-relative" "$calls" '"file_path":"docs/x.md"'
check_contains "tu_tool_calls normalizes a second cwd-prefixed path too" "$calls" '"file_path":"docs/y.md"'
check_contains "tu_tool_calls leaves a path outside the session's own cwd absolute" \
  "$calls" '"file_path":"/Users/x/.keel/kb/notes.md"'

# --- tu_session_totals: primary and subagent kept separate, never folded into one number -----------
totals_sess_dir="$proj_root/${slug_main}"
totals_sess_uuid="22222222-2222-2222-2222-222222222222"
totals_sess_file="$totals_sess_dir/$totals_sess_uuid.jsonl"
cp "$dedupe_file" "$totals_sess_file"
mkdir -p "$totals_sess_dir/$totals_sess_uuid/subagents"
cat > "$totals_sess_dir/$totals_sess_uuid/subagents/agent-x.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"requestId":"req_sub_1","sessionId":"sess-1","agentId":"agent-x","timestamp":"t","message":{"model":"claude-sonnet-5","content":[],"usage":{"output_tokens":7,"cache_read_input_tokens":300}}}
EOF

totals="$(tu_session_totals "$totals_sess_file")"
check_contains "tu_session_totals reports a primary total" "$totals" '"primary":'
check_contains "tu_session_totals reports a SEPARATE subagent total" "$totals" '"subagent":'
primary_turns="$(printf '%s' "$totals" | jq '.primary.turns')"
check_status "tu_session_totals: primary turns match the deduped count (2)" "2" "$primary_turns"
subagent_output="$(printf '%s' "$totals" | jq '.subagent.output_tokens')"
check_status "tu_session_totals: subagent output_tokens is its own number, not merged into primary" "7" "$subagent_output"
primary_output="$(printf '%s' "$totals" | jq '.primary.output_tokens')"
check_status "tu_session_totals: primary output_tokens excludes the subagent's 7" "70" "$primary_output"

no_sub_file="$SANDBOX/no-sub.jsonl"
cp "$dedupe_file" "$no_sub_file"
no_sub_totals="$(tu_session_totals "$no_sub_file")"
check_absent "tu_session_totals: no 'subagent' key when a session spawned none" "$no_sub_totals" '"subagent"'

summary
