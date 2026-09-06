#!/usr/bin/env bash
# tests/test_token_report.sh — dir #314 (first slice): tools/token-report.sh is `keel tokens`, an
# adopter-facing report built on tools/lib/transcript-usage.sh (covered separately by
# test_transcript_usage_lib.sh). These tests pin the aggregation/diagnosis layer this script adds —
# the three patterns (fan-out, cold resumes, repeated reads), the accounting totals, the CLI modes
# (project / --session / --since / --json), and the isolation env vars. Every fixture is synthetic.
#
# The tool parses transcripts with jq, so most of this file needs jq. The busybox/Alpine CI leg
# installs it (dir #220), so this runs for real there too — the canonical green-skip guard
# (tests/test_pre_pr_gate.sh:17-23) is defence-in-depth, not the normal path.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

tool="$REPO_ROOT/tools/token-report.sh"
check_file "tools/token-report.sh exists" "$tool"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — token-report.sh tests skipped (the tool requires jq to parse transcripts)"
  summary; exit $?
fi

# --- usage / dispatch ----------------------------------------------------------------------------
run bash "$tool" -h
check_status "-h prints usage, exit 0" "0" "$STATUS"
check_contains "usage names every mode" "$OUT" "--session"
check_contains "usage names every mode" "$OUT" "--since"
check_contains "usage names every mode" "$OUT" "--json"

run bash "$tool" --bogus-flag
check_status "an unknown flag exits 2" "2" "$STATUS"

run bash "$tool" --session
check_status "--session with no value exits 2" "2" "$STATUS"

run bash "$tool" --since
check_status "--since with no value exits 2" "2" "$STATUS"

# --- dir #314 SPEC §5: jq-required degradation is LOUD, never a silent fail-open (unlike
# pre-pr-gate.sh's hook — a report that prints a confidently empty answer is worse than no report) ---
nojq="$SANDBOX/nojq-path"
path_farm "$nojq" jq
run env PATH="$nojq" bash "$tool"
check_status "jq missing exits non-zero" "1" "$STATUS"
check_contains "jq missing prints the exact spec-quoted message" "$OUT" "unavailable: keel tokens needs jq"

# --- fixtures: a project with two sessions --------------------------------------------------------
# Session A (primary + one subagent): a >=55min gap whose next turn's cache_creation exceeds its
# cache_read (the cold-resume signature, SPEC F5), and BACKLOG.md read 3 times (SPEC F7).
# Session B (primary only): plain, no gap, no subagent, one read of a different file.
repo="$(new_repo)"
# _tr_repo_top resolves via `git worktree list --porcelain`, which git reports at its PHYSICAL path
# (macOS: /tmp and /var are themselves symlinks into /private) — tools/lib/transcript-usage.sh's own
# tu_project_slug then slugs whatever it is handed. A fixture keyed off $repo's un-resolved mktemp form
# would silently mismatch on macOS (reproduced live), so the slug here is built from the same physical
# path the tool will actually resolve to.
repo_physical="$(cd "$repo" && pwd -P)"
root="$SANDBOX/transcripts"
slug="$(printf '%s' "$repo_physical" | tr '/.' '--')"
sessdir="$root/$slug"
mkdir -p "$sessdir"

cat > "$sessdir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl" <<'EOF'
{"type":"assistant","requestId":"r1","sessionId":"A","timestamp":"2026-09-01T10:00:00.000Z","gitBranch":"g","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/BACKLOG.md"}}],"usage":{"input_tokens":100,"cache_creation_input_tokens":5000,"cache_read_input_tokens":1000,"output_tokens":200}},"cwd":"/repo"}
{"type":"assistant","requestId":"r2","sessionId":"A","timestamp":"2026-09-01T11:30:00.000Z","gitBranch":"g","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/BACKLOG.md"}}],"usage":{"input_tokens":50,"cache_creation_input_tokens":20000,"cache_read_input_tokens":500,"output_tokens":100}},"cwd":"/repo"}
{"type":"assistant","requestId":"r3","sessionId":"A","timestamp":"2026-09-01T11:31:00.000Z","gitBranch":"g","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/BACKLOG.md"}}],"usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":30000,"output_tokens":50}},"cwd":"/repo"}
EOF
mkdir -p "$sessdir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/subagents"
cat > "$sessdir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/subagents/agent-1.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"requestId":"rs1","sessionId":"A","agentId":"agent-1","timestamp":"2026-09-01T10:05:00.000Z","message":{"model":"claude-sonnet-5","content":[],"usage":{"input_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":2000,"output_tokens":30}}}
EOF

cat > "$sessdir/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl" <<'EOF'
{"type":"assistant","requestId":"r4","sessionId":"B","timestamp":"2026-09-02T09:00:00.000Z","gitBranch":"g","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/README.md"}}],"usage":{"input_tokens":20,"cache_creation_input_tokens":10,"cache_read_input_tokens":500,"output_tokens":40}},"cwd":"/repo"}
EOF

export KEEL_TOKENS_PROJECTS_DIR="$root"

# --- project mode: default weights (1.0 / 2.0 / 0.1) ------------------------------------------------
run_in "$repo" bash "$tool"
check_status "project mode exits 0" "0" "$STATUS"
check_contains "project mode reports both sessions" "$OUT" "2 session(s)"
check_contains "accounting: new input summed across both sessions (100+50+10+5+20=185)" "$OUT" "185"
check_contains "accounting: cache writes summed (5000+20000+100+100+10=25210)" "$OUT" "25210"
check_contains "accounting: cache reads summed (1000+500+30000+2000+500=34000)" "$OUT" "34000"
check_contains "accounting: weighted input-side total (185*1+25210*2+34000*0.1=54005)" "$OUT" "54005"
check_contains "fan-out pattern names the subagent share" "$OUT" "fan-out"
check_contains "fan-out worst names the session that spawned it" "$OUT" "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
check_contains "R7 disclosure is printed inline, not only in the doc" "$OUT" "R7"
check_contains "cold-resume pattern fires on the >=55min gap with a creation>read turn" "$OUT" "cold resumes"
check_contains "cold-resume tokens = the flagged turn's cache_creation (20000)" "$OUT" "20000"
check_contains "R6 heuristic disclosure is printed inline" "$OUT" "R6"
check_contains "repeated-reads names the corpus-wide top file" "$OUT" "BACKLOG.md was read 3 time"
check_contains "repeated-reads worst-session line" "$OUT" "Worst single session: 3 reads"
check_contains "footer states the weight vector and its ruler-not-price status" "$OUT" "NOT a price"

# --- --json: same corpus, machine-readable -----------------------------------------------------
run_in "$repo" bash "$tool" --json
check_status "--json exits 0" "0" "$STATUS"
check_contains "--json is valid JSON with the accounting block" "$OUT" '"input_side_total":54005'
check_contains "--json carries the fanout pattern" "$OUT" '"sessionsWithFanout":1'
check_contains "--json carries the cold-resume pattern" "$OUT" '"events":1'
check_contains "--json carries the repeated-reads pattern" "$OUT" '"topFile":"BACKLOG.md"'

# --- --session: one file directly, plus by bare UUID -------------------------------------------
run bash "$tool" --session "$sessdir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"
check_status "--session by direct path exits 0" "0" "$STATUS"
check_contains "--session by path reports exactly one session" "$OUT" "1 session(s)"
check_contains "--session by path excludes session B's tokens (new input 165, not 185)" "$OUT" "165"

run bash "$tool" --session aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
check_status "--session by bare UUID resolves under the transcript root" "0" "$STATUS"
check_contains "--session by UUID finds the same file" "$OUT" "165"

run bash "$tool" --session does-not-exist-uuid
check_status "--session with no matching file exits 2" "2" "$STATUS"
check_contains "--session failure names what was looked up" "$OUT" "does-not-exist-uuid"

# --- --since: whole-session filtering (SPEC: not a partial-session slice) ----------------------
run_in "$repo" bash "$tool" --since 2026-09-02
check_status "--since exits 0" "0" "$STATUS"
check_contains "--since 2026-09-02 keeps only session B (its one turn is on that date)" "$OUT" "1 session(s)"

run_in "$repo" bash "$tool" --since 2026-09-01
check_status "--since from session A's own start date keeps both sessions" "0" "$STATUS"
check_contains "--since 2026-09-01 keeps both A and B" "$OUT" "2 session(s)"

run_in "$repo" bash "$tool" --since 2099-01-01
check_status "--since far in the future exits 0, not an error" "0" "$STATUS"
check_contains "--since with no matching session reports zero, not a crash" "$OUT" "0 session(s)"
check_contains "zero-session report explains why, and names the harness boundary (R3)" "$OUT" "Claude Code transcripts"

# --- weight override (SPEC §5 KEEL_TOKENS_WEIGHTS) ----------------------------------------------
run_in "$repo" env KEEL_TOKENS_WEIGHTS=1,1,1 bash "$tool" --json
check_status "a custom weight vector exits 0" "0" "$STATUS"
check_contains "equal weights: input-side total = raw sum (185+25210+34000=59395)" "$OUT" '"input_side_total":59395'

run_in "$repo" env KEEL_TOKENS_WEIGHTS=bogus bash "$tool"
check_status "a malformed weight override still runs (falls back to defaults)" "0" "$STATUS"
check_contains "a malformed override warns rather than silently corrupting every figure" "$OUT" "malformed"

# --- no data at all: an empty transcript root, not a crash --------------------------------------
empty_root="$SANDBOX/empty-transcripts"
mkdir -p "$empty_root"
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$empty_root" bash "$tool"
check_status "an empty transcript root exits 0" "0" "$STATUS"
check_contains "an empty corpus reports zero sessions plainly" "$OUT" "0 session(s)"
check_contains "an empty corpus names the harness boundary (R3), not a bare zero" "$OUT" "Claude Code transcripts"

# --- self-check surfacing: an unrecognized record type should be visible, not silently absorbed --
weird_root="$SANDBOX/weird-transcripts"
weird_slug="$(printf '%s' "$repo_physical" | tr '/.' '--')"
mkdir -p "$weird_root/$weird_slug"
cat > "$weird_root/$weird_slug/cccccccc-cccc-cccc-cccc-cccccccccccc.jsonl" <<'EOF'
{"type":"assistant","requestId":"r5","sessionId":"C","timestamp":"2026-09-03T09:00:00.000Z","message":{"model":"m","content":[],"usage":{"input_tokens":1}}}
{"type":"never-seen-before","sessionId":"C"}
{"type":"never-seen-before","sessionId":"C"}
{"type":"never-seen-before","sessionId":"C"}
{"type":"never-seen-before","sessionId":"C"}
{"type":"never-seen-before","sessionId":"C"}
EOF
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$weird_root" bash "$tool"
check_status "an unrecognized record type does not crash the report" "0" "$STATUS"
check_contains "an unrecognized type is surfaced, not silently absorbed (SPEC §6 req 5)" "$OUT" "does not recognize"

# code-review high pass: the counter must count RECORDS, not distinct unrecognized TYPE NAMES — 5
# records sharing one unrecognized type name must report 5, not 1 (a `unique`-deduped count collapsed
# to 1 before this fix).
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$weird_root" bash "$tool" --json
check_contains "5 records of ONE unrecognized type count as 5, not 1 (distinct-name count bug)" \
  "$OUT" '"unrecognizedTypeRecords":5'

summary
