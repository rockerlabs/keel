#!/usr/bin/env bash
# tests/test_token_report.sh — dir #314 (first slice): tools/token-report.sh is `keel tokens`, an
# adopter-facing report built on tools/lib/transcript-usage.sh (covered separately by
# test_transcript_usage_lib.sh). These tests pin the aggregation/diagnosis layer this script adds —
# the three patterns (fan-out, cold resumes, repeated reads), the accounting totals, the CLI modes
# (project / --session / --since / --json), and the isolation env vars. Every fixture is synthetic.
#
# The tool parses transcripts with jq, so most of this file needs jq. The busybox/Alpine CI leg
# installs it (dir #220), so this runs for real there too — the canonical green-skip guard
# (tests/test_pre_pr_gate.sh's own `command -v jq` skip block) is defence-in-depth, not the normal
# path.
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
check_status "5-unrecognized-records run exits 0" "0" "$STATUS"
check_contains "5 records of ONE unrecognized type count as 5, not 1 (distinct-name count bug)" \
  "$OUT" '"unrecognizedTypeRecords":5'

# --- F-03 (dir #267 fixer brief): one malformed timestamp used to abort the WHOLE aggregation
# (exit 1, zero output, every session's data lost) — the corpus is live (this project's own
# commits 01977a8/a3b94f9 already treat a mid-write file as ordinary, not corruption), so this
# must degrade per-record instead. Both malformed shapes the brief reproduced, plus a control that
# a well-formed session still reports when a malformed one sits alongside it. ------------------------

# Shape 1: a non-ISO-8601 timestamp string ("t1", the brief's own reproduction).
bad_ts_root="$SANDBOX/bad-timestamp-nonISO"
bad_ts_slug="$(printf '%s' "$repo_physical" | tr '/.' '--')"
mkdir -p "$bad_ts_root/$bad_ts_slug"
cat > "$bad_ts_root/$bad_ts_slug/dddddddd-dddd-dddd-dddd-dddddddddddd.jsonl" <<'EOF'
{"type":"assistant","requestId":"r6","sessionId":"D","timestamp":"2026-09-04T09:00:00.000Z","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
EOF
cat > "$bad_ts_root/$bad_ts_slug/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.jsonl" <<'EOF'
{"type":"assistant","requestId":"r7","sessionId":"E","timestamp":"t1","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
EOF
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$bad_ts_root" bash "$tool"
check_status "MUTATION-PROOF: a non-ISO timestamp does not abort the report -> exit 0" "0" "$STATUS"
check_contains "both sessions still report (2 session(s)), not zero output" "$OUT" "2 session(s)"
check_contains "the malformed timestamp is surfaced, not silently absorbed" "$OUT" \
  "missing or non-ISO-8601 timestamp"

run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$bad_ts_root" bash "$tool" --json
check_status "non-ISO timestamp fixture --json exits 0" "0" "$STATUS"
check_contains "--json surfaces the malformed-timestamp count" "$OUT" '"malformedTimestamps":1'

# Shape 2: a turn with no `timestamp` field at all (the brief's second reproduction).
bad_ts_root2="$SANDBOX/bad-timestamp-missing"
mkdir -p "$bad_ts_root2/$bad_ts_slug"
cat > "$bad_ts_root2/$bad_ts_slug/ffffffff-ffff-ffff-ffff-ffffffffffff.jsonl" <<'EOF'
{"type":"assistant","requestId":"r8","sessionId":"F","timestamp":"2026-09-04T09:00:00.000Z","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
EOF
cat > "$bad_ts_root2/$bad_ts_slug/gggggggg-gggg-gggg-gggg-gggggggggggg.jsonl" <<'EOF'
{"type":"assistant","requestId":"r9","sessionId":"G","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
EOF
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$bad_ts_root2" bash "$tool"
check_status "MUTATION-PROOF: a missing timestamp field does not abort the report -> exit 0" "0" "$STATUS"
check_contains "both sessions still report when one turn has no timestamp at all" "$OUT" "2 session(s)"
check_contains "the missing timestamp is surfaced too" "$OUT" "missing or non-ISO-8601 timestamp"

# dir #421: the two shapes above each put their one malformed timestamp ALONE in its own session
# file — every fixture above has exactly one turn per file. safe_epoch's own try/catch guard is
# reached while COUNTING malformed timestamps regardless (that scan runs over $TURNS unconditionally),
# but the cold-resume gap computation this guard was actually written to protect
# (`$arr[.-1].timestamp | safe_epoch` / `$arr[.].timestamp | safe_epoch` feeding `($cur-$prev)/60`)
# only runs at all when `group_by(.sessionFile) | map(sort_by(.timestamp) as $arr | range(1;
# ($arr|length)) | ...)` has an `$arr` of length >= 2 — a single-turn file makes `range(1;1)` empty,
# so that subtraction never executes and a de-guarded safe_epoch would never be exercised by any
# fixture above (mutation-proved by the ticket's own finder: reverting the fix with the above tests
# kept still gives 5 failures, none of them on the abort behaviour). This fixture puts TWO turns of
# the SAME sessionId in ONE session file, one with a non-ISO timestamp, so the gap computation
# actually runs the subtraction over the malformed value — plus an unrelated well-formed session
# alongside it, so a re-regressed abort would be caught both by this file's own exit code and by the
# well-formed session going missing from the count. -------------------------------------------------
multi_turn_root="$SANDBOX/bad-timestamp-multiturn"
multi_turn_slug="$(printf '%s' "$repo_physical" | tr '/.' '--')"
mkdir -p "$multi_turn_root/$multi_turn_slug"
cat > "$multi_turn_root/$multi_turn_slug/iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii.jsonl" <<'EOF'
{"type":"assistant","requestId":"r12","sessionId":"I","timestamp":"2026-09-04T09:00:00.000Z","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
{"type":"assistant","requestId":"r13","sessionId":"I","timestamp":"t3","message":{"model":"m","content":[],"usage":{"input_tokens":5000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":0,"output_tokens":1}}}
EOF
cat > "$multi_turn_root/$multi_turn_slug/jjjjjjjj-jjjj-jjjj-jjjj-jjjjjjjjjjjj.jsonl" <<'EOF'
{"type":"assistant","requestId":"r14","sessionId":"J","timestamp":"2026-09-04T09:10:00.000Z","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
EOF
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$multi_turn_root" bash "$tool"
check_status "MUTATION-PROOF: a malformed timestamp alongside a well-formed one IN THE SAME session file does not abort -> exit 0" "0" "$STATUS"
check_contains "the well-formed session (J) still reports alongside the malformed one (I) — 2 session(s), not zero output" "$OUT" "2 session(s)"

run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$multi_turn_root" bash "$tool" --json
check_status "same-file multi-turn fixture --json exits 0" "0" "$STATUS"
check_contains "--json surfaces the one malformed timestamp (not more, not fewer)" "$OUT" '"malformedTimestamps":1'

# --- F-05 (dir #267 fixer brief): an assistant record with no usage object is correctly excluded
# from every total, but tu_self_check's own comment says this "should be zero; a warning sign,
# never silently dropped" — it must be visible, not invisible in both outputs. -----------------------
no_usage_root="$SANDBOX/no-usage-object"
no_usage_slug="$(printf '%s' "$repo_physical" | tr '/.' '--')"
mkdir -p "$no_usage_root/$no_usage_slug"
cat > "$no_usage_root/$no_usage_slug/hhhhhhhh-hhhh-hhhh-hhhh-hhhhhhhhhhhh.jsonl" <<'EOF'
{"type":"assistant","requestId":"r10","sessionId":"H","timestamp":"2026-09-04T09:00:00.000Z","message":{"model":"m","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
{"type":"assistant","requestId":"r11","sessionId":"H","timestamp":"2026-09-04T09:01:00.000Z","message":{"model":"m","content":[]}}
EOF
run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$no_usage_root" bash "$tool"
check_status "an assistant record with no usage object does not crash the report" "0" "$STATUS"
check_contains "the no-usage record is surfaced, not silently dropped" "$OUT" \
  "carried no usage object"

run_in "$repo" env KEEL_TOKENS_PROJECTS_DIR="$no_usage_root" bash "$tool" --json
check_status "no-usage-object fixture --json exits 0" "0" "$STATUS"
check_contains "--json surfaces the assistantNoUsage count" "$OUT" '"assistantNoUsage":1'

summary
