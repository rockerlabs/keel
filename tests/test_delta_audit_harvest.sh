#!/usr/bin/env bash
# Tests for tools/delta-audit/harvest.sh — dir #267's run-record.md mechanical-field harvester.
#
# Fixtures are synthetic, built by this file, never copied from private/audit/ (gitignored, may
# carry personal paths — project CLAUDE.md's rule for any private/ material). They deliberately
# reproduce the two real SHAPES this script depends on (derive.sh's run-record.md stub, and
# orchestrator-notes.md's own "| leg | ... | tokens | ... |" cost table, both read live from the real
# tree while designing this script) without touching real run content.
#
# What this suite pins, beyond ordinary output correctness:
#   1. The two hard constraints from dir #267's own ticket body: a cost this script cannot find is
#      the literal string `unmeasured`, never a fabricated `0`; and no cell anywhere sums tokens
#      across legs (assert the absence of the two legs' summed figure, not just the presence of the
#      separate ones — a regression that also computed a correct-looking sum alongside the correct
#      per-leg figures would pass a presence-only check and still violate the rule).
#   2. Every OTHER row in run-record.md — including one holding an existing hand-written value — is
#      copied through byte-for-byte, never touched.
#   3. The induced tally counts explicit `Mark:` lines only; report prose that merely CONTAINS the
#      words "induced" or "original" without that marker is not silently counted (the false-positive
#      case this design explicitly declined to guess at).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/delta-audit/harvest.sh"
check_file "harvest.sh exists" "$TOOL"

# mk_run DIR — a run directory carrying derive.sh's own run-record.md stub shape (copied from its
# real emission, not paraphrased), so this suite proves against the ACTUAL stub, not an invented one.
mk_run() {
  local d="$1"
  mkdir -p "$d"
  {
    printf '# Run record — a..b\n\n'
    printf 'Stub emitted by `tools/delta-audit/derive.sh`.\n\n'
    printf '| | |\n|---|---|\n'
    printf '| scope | 6 files, 2 PRs |\n'
    printf '| method | |\n'
    printf '| coverage | |\n'
    printf '| findings | |\n'
    printf '| behavioural defects in shipped code | |\n'
    printf '| diversity result | |\n'
    printf '| new classes vs instances of known ones | |\n'
    printf '| upstream gate that should have caught it | |\n'
    printf '| cost, per leg (sessions, tier+effort, tokens or `unmeasured`) | |\n'
    printf '| induced defects (induced / total) | |\n'
    printf '| records | |\n'
  } > "$d/run-record.md"
}

# --- refusals ----------------------------------------------------------------------------------
run "$TOOL"
check_status "no args -> exit 2" 2 "$STATUS"

run "$TOOL" "$SANDBOX/does-not-exist"
check_status "missing run-dir -> exit 3" 3 "$STATUS"

mkdir -p "$SANDBOX/no-record"
run "$TOOL" "$SANDBOX/no-record"
check_status "run-dir with no run-record.md -> exit 3" 3 "$STATUS"

run "$TOOL" "$SANDBOX/no-record" extra
check_status "too many args -> exit 2" 2 "$STATUS"

# --- the main fixture: two orchestrator-notes.md tables (one with a leg missing its tokens cell),
# two report files carrying explicit Mark: lines plus incidental prose use of the same words --------
r="$SANDBOX/run1"
mk_run "$r"

{
  printf '# notes\n\n## Cost per leg\n\n'
  printf '| leg | model / effort | tokens | tool calls | wall clock |\n'
  printf '|---|---|---|---|---|\n'
  printf '| S1 mechanical | mid tier | 169,130 | 64 | 18m |\n'
  printf '| S2 whole-read | mid tier | | 12 | 5m |\n'
  printf '\n## Cost, continued\n\n'
  printf '| leg | model / effort | tokens | tool calls | wall clock |\n'
  printf '|---|---|---|---|---|\n'
  printf '| S3 vendor | deepseek | 42000 | 9 | 3m |\n'
} > "$r/orchestrator-notes.md"

mkdir -p "$r/reports"
{
  printf 'Finding F1 was **induced** by an earlier round in the general sense of causing it, but this\n'
  printf 'sentence carries no Mark: line and must not be tallied.\n\n'
  printf 'Finding F2. **Mark:** `induced` — one sentence causal path to the prior fix.\n'
  printf 'Finding F3. **Mark:** `original`\n'
} > "$r/reports/S1.md"
printf 'Finding F4. **Mark:** `original`\n' > "$r/reports/S2.md"

run "$TOOL" "$r"
check_status "main fixture -> exit 0" 0 "$STATUS"

out="$(cat "$r/run-record.md")"

check_contains "unchanged scope row survives byte-for-byte" "$out" "| scope | 6 files, 2 PRs |"
check_contains "unchanged narrative rows stay empty (method)" "$out" "| method | |"
check_contains "unchanged narrative rows stay empty (upstream gate)" "$out" \
  "| upstream gate that should have caught it | |"

check_contains "cost row: S1's measured figure appears" "$out" "S1 mechanical: 169130 tokens"
check_contains "cost row: S2's blank cell becomes unmeasured, not 0" "$out" "S2 whole-read: unmeasured"
check_contains "cost row: S3's table, found via the second header, appears too" "$out" "S3 vendor: 42000 tokens"
check_absent "cost row never sums the three legs' tokens (211130 would be S1+S3)" "$out" "211130"
check_absent "cost row never emits a bare fabricated 0 for S2" "$out" "S2 whole-read: 0"

check_contains "induced row: exactly the three marked findings are tallied (1 induced / 3 total)" \
  "$out" "| induced defects (induced / total) | 1 induced / 3 marked |"
check_absent "induced tally does not count F1's prose use of the word with no Mark: line" "$out" "2 induced"

check_contains "records row lists both artifacts, sorted" "$out" \
  "| records | \`orchestrator-notes.md\`, \`reports/\` |"
check_absent "records row never lists itself" "$out" "run-record.md\`,"

# --- no orchestrator-notes.md, no reports/: both harvested rows fall back to unmeasured, not 0 or
# an empty cell ----------------------------------------------------------------------------------
r2="$SANDBOX/run2-empty"
mk_run "$r2"
run "$TOOL" "$r2"
check_status "no-artifacts fixture -> exit 0" 0 "$STATUS"
out2="$(cat "$r2/run-record.md")"
check_contains "cost falls back to unmeasured when no orchestrator-notes.md exists" "$out2" \
  "| cost, per leg (sessions, tier+effort, tokens or \`unmeasured\`) | unmeasured"
check_contains "induced falls back to unmeasured when no reports/ exists" "$out2" \
  "| induced defects (induced / total) | unmeasured"
check_contains "records still lists run-record.md's own stub-only directory honestly" "$out2" \
  "| records | (empty run directory) |"

# --- re-running harvest a second time on an already-harvested record is idempotent -----------------
run "$TOOL" "$r"
check_status "re-running on an already-harvested record -> exit 0" 0 "$STATUS"
out3="$(cat "$r/run-record.md")"
check_contains "second run reproduces the same cost row" "$out3" "S1 mechanical: 169130 tokens"
check_contains "second run reproduces the same induced row" "$out3" \
  "| induced defects (induced / total) | 1 induced / 3 marked |"

summary
