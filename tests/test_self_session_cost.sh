#!/usr/bin/env bash
# tests/test_self_session_cost.sh — dir #313: tools/self/session-cost.sh is the method ("cost per
# ticket, by (R-tier, model) cell, on deduped tokens, reported as a median") built on top of
# tools/lib/transcript-usage.sh (covered separately by test_transcript_usage_lib.sh). These tests pin
# the aggregation/median layer this script adds; every fixture is synthetic.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

tool="$REPO_ROOT/tools/self/session-cost.sh"
check_file "tools/self/session-cost.sh exists" "$tool"

# --- usage / dispatch ---------------------------------------------------------------------------
run bash "$tool"
check_status "no args prints usage, exit 0" "0" "$STATUS"
check_contains "usage names every subcommand" "$OUT" "session"
check_contains "usage names every subcommand" "$OUT" "table"

run bash "$tool" bogus-command
check_status "an unknown command exits 2" "2" "$STATUS"

# --- fixtures: one requestId-duplicated primary session + one subagent sibling -------------------
sess_dir="$SANDBOX/session"
mkdir -p "$sess_dir"
sess_file="$sess_dir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"
cat > "$sess_file" <<'EOF'
{"type":"assistant","requestId":"req_1","sessionId":"s","timestamp":"t1","gitBranch":"claude/go-1-x","message":{"model":"claude-sonnet-5","content":[{"type":"text"}],"usage":{"output_tokens":100,"cache_read_input_tokens":1000}}}
{"type":"assistant","requestId":"req_1","sessionId":"s","timestamp":"t2","gitBranch":"claude/go-1-x","message":{"model":"claude-sonnet-5","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}],"usage":{"output_tokens":100,"cache_read_input_tokens":1000}}}
{"type":"assistant","requestId":"req_2","sessionId":"s","timestamp":"t3","gitBranch":"claude/go-1-x","message":{"model":"claude-sonnet-5","content":[{"type":"text"}],"usage":{"output_tokens":50,"cache_read_input_tokens":500}}}
EOF
mkdir -p "$sess_dir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/subagents"
cat > "$sess_dir/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/subagents/agent-x.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"requestId":"req_sub","sessionId":"s","agentId":"agent-x","timestamp":"t","message":{"model":"claude-sonnet-5","content":[],"usage":{"output_tokens":10,"cache_read_input_tokens":200}}}
EOF

# a second, subagent-less session for the same "ticket" (dir #147's multi-session lifecycle shape)
sess_file2="$sess_dir/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"
cat > "$sess_file2" <<'EOF'
{"type":"assistant","requestId":"req_3","sessionId":"s2","timestamp":"t4","gitBranch":"claude/go-1-x","message":{"model":"claude-sonnet-5","content":[{"type":"text"}],"usage":{"output_tokens":25,"cache_read_input_tokens":250}}}
EOF

# --- session: human-readable + --json --------------------------------------------------------------
run bash "$tool" session "$sess_file"
check_status "session (human) exits 0" "0" "$STATUS"
check_contains "session (human) reports deduped primary turns" "$OUT" "turns=2"
check_contains "session (human) reports the deduped output sum (100+50=150, not 250)" "$OUT" "output=150"
check_contains "session (human) reports the SEPARATE subagent line" "$OUT" "subagent:"
check_contains "session (human) subagent line carries its own numbers" "$OUT" "output=10"

run bash "$tool" session --json "$sess_file"
check_status "session --json exits 0" "0" "$STATUS"
check_contains "session --json is valid JSON with a primary key" "$OUT" '"primary":'
check_contains "session --json carries a subagent key too" "$OUT" '"subagent":'

run bash "$tool" session "$SANDBOX/does-not-exist.jsonl"
check_status "session on a missing file exits 2" "2" "$STATUS"

# --- ticket: sums across 1+ session files, keeps primary/subagent apart --------------------------
run bash "$tool" ticket R1 sonnet "$sess_file"
check_status "ticket exits 0" "0" "$STATUS"
check_contains "ticket reports tier/model as given" "$OUT" '"tier":"R1"'
check_contains "ticket reports tier/model as given" "$OUT" '"model":"sonnet"'
check_contains "ticket cost_tokens = deduped cache_read + output (1500+150=1650)" "$OUT" '"cost_tokens":1650'

run bash "$tool" ticket R1 sonnet "$sess_file" "$sess_file2"
check_contains "ticket sums MULTIPLE session files (a start/cancel/restart lifecycle)" "$OUT" '"turns":3'
check_contains "ticket sums MULTIPLE session files: cache_read 1500+250=1750" "$OUT" '"cache_read_input_tokens":1750'

run bash "$tool" ticket R1 sonnet
check_status "ticket with no FILE args exits 2" "2" "$STATUS"

# --- dir #313 review: model is parsed from the transcript already — cross-check it against the
# caller-supplied --model instead of silently trusting a possible typo ------------------------------
run bash "$tool" ticket R1 sonnet "$sess_file"
check_status "ticket: --model matching the transcript's shorthand succeeds quietly" "0" "$STATUS"
check_absent "ticket: no warning when --model is a substring of the recorded model (sonnet vs claude-sonnet-5)" \
  "$OUT" "does not match"

run bash "$tool" ticket R1 opus "$sess_file"
check_status "ticket: a genuine --model mismatch still succeeds (a warning, not a hard failure)" "0" "$STATUS"
check_contains "ticket: a genuine --model mismatch is flagged loudly" "$OUT" "does not match model(s) recorded"
check_contains "ticket: the mismatch warning names both the given and the recorded model" "$OUT" "claude-sonnet-5"

# --- selfcheck: passthrough to tu_self_check, non-zero exit on an unrecognized type ---------------
run bash "$tool" selfcheck "$sess_file"
check_status "selfcheck on a clean fixture exits 0" "0" "$STATUS"
check_contains "selfcheck reports zero unrecognized types" "$OUT" '"unrecognized_types":[]'

weird_file="$SANDBOX/weird.jsonl"
cat > "$weird_file" <<'EOF'
{"type":"assistant","requestId":"r","sessionId":"s","timestamp":"t","message":{"model":"m","content":[],"usage":{"output_tokens":1}}}
{"type":"never-seen-before","sessionId":"s"}
EOF
run bash "$tool" selfcheck "$weird_file"
check_status "selfcheck exits non-zero when a transcript carries an unrecognized type" "1" "$STATUS"
check_contains "selfcheck names the file whose format moved" "$OUT" "unrecognized record type"

# --- dir #313 review: selfcheck's exit code must be the WORST across every file, not last-write-wins
# (reproduced live: the same two files in opposite orders used to exit 1 and 2 for identical inputs) --
missing_file="$SANDBOX/does-not-exist-selfcheck.jsonl"
run bash "$tool" selfcheck "$missing_file" "$weird_file"
check_status "selfcheck: missing file (2) THEN unrecognized-type file (1) -> worst-of is 2" "2" "$STATUS"
run bash "$tool" selfcheck "$weird_file" "$missing_file"
check_status "selfcheck: unrecognized-type file (1) THEN missing file (2) -> worst-of is STILL 2" "2" "$STATUS"

# --- table: the (R-tier, model) cell median, and the per-ticket detail rows -----------------------
manifest="$SANDBOX/manifest.tsv"
cat > "$manifest" <<EOF
# comment lines and blanks are skipped

dirA	R1	sonnet	$sess_file
dirB	R1	sonnet	$sess_file2
EOF
run bash "$tool" table "$manifest"
check_status "table exits 0" "0" "$STATUS"
check_contains "table prints the per-ticket detail row" "$OUT" "dirA"
check_contains "table prints the per-ticket detail row" "$OUT" "dirB"
check_contains "table's median section names the cell" "$OUT" "R1"
check_contains "table's median section names the cell" "$OUT" "sonnet"
# n=2 cell: costs are dirA=1650, dirB=275 -> median = (275+1650)/2 = 962.5
check_contains "table computes the median (not the mean) for an even-n cell" "$OUT" "962.5"

run bash "$tool" table "$SANDBOX/no-such-manifest.tsv"
check_status "table on a missing manifest exits 2" "2" "$STATUS"

empty_manifest="$SANDBOX/empty.tsv"
: > "$empty_manifest"
run bash "$tool" table "$empty_manifest"
check_status "table on a manifest with no ticket rows exits 2, not a crash" "2" "$STATUS"

malformed_manifest="$SANDBOX/malformed.tsv"
printf 'onlyonefield\n' > "$malformed_manifest"
run bash "$tool" table "$malformed_manifest"
check_status "table refuses a malformed manifest line loudly" "2" "$STATUS"

# --- dir #313 review: a manifest line that repeats one session file must count it ONCE, not double
# its tokens — a plausible hand-editing slip, reproduced live before this fix as a silent 2x inflation
dup_manifest="$SANDBOX/dup-manifest.tsv"
printf 'dirDup\tR1\tsonnet\t%s,%s\n' "$sess_file" "$sess_file" > "$dup_manifest"
run bash "$tool" table "$dup_manifest"
check_status "table with a duplicated manifest file entry exits 0" "0" "$STATUS"
check_contains "table dedupes a repeated file: msgs stays 2 (the file's own turn count), not 4" "$OUT" "dirDup"
check_contains "table dedupes a repeated file: output stays 150 (100+50), not 300" "$OUT" "150"

summary
