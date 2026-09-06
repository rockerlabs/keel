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

# --- a value cell already containing a literal `|` (e.g. a human's partial hand-fill) fails the
# strict 2-column shape harvest.sh rewrites by; assert it is left unmodified WITH a stderr warning,
# never silently dropped with no signal at all. Built directly with printf (never `sed -i`, whose
# GNU/BSD flag shape differs — a live cross-platform trap this project's own CLAUDE.md warns about)
# so mk_run's shared stub text stays the single source of truth for every OTHER row. ------------------
r3="$SANDBOX/run3-pipe-in-value"
mk_run "$r3"
{
  cat "$r3/run-record.md"
} | { grep -v '^| records | |$'; printf '| records | already: S1 | S2 |\n'; } > "$r3/run-record.md.new"
mv "$r3/run-record.md.new" "$r3/run-record.md"
run "$TOOL" "$r3"
check_status "pipe-in-value fixture -> exit 0 (a warning, not a failure)" 0 "$STATUS"
check_contains "warns on stderr that the malformed row was left unmodified" "$OUT" \
  "WARNING: the 'records' row has an unexpected shape"
out4="$(cat "$r3/run-record.md")"
check_contains "the malformed row's original value survives untouched" "$out4" \
  "| records | already: S1 | S2 |"

# --- awk failing partway through the final rewrite must refuse (exit 3) and leave the original
# run-record.md untouched, never overwrite it with a truncated/partial file. Forced by shadowing
# `awk` on PATH with a script that always fails — the only portable way to trigger this without
# editing the tool under test. ------------------------------------------------------------------------
r4="$SANDBOX/run4-awk-failure"
mk_run "$r4"
original_before="$(cat "$r4/run-record.md")"
mkdir -p "$SANDBOX/fakebin"
cat > "$SANDBOX/fakebin/awk" <<'FAKE'
#!/bin/sh
exit 2
FAKE
chmod +x "$SANDBOX/fakebin/awk"
run env PATH="$SANDBOX/fakebin:$PATH" "$TOOL" "$r4"
check_status "awk failure during the final rewrite -> exit 3 (refuse), not a silent overwrite" 3 "$STATUS"
after="$(cat "$r4/run-record.md")"
check_status "original run-record.md is untouched byte-for-byte after the refusal" 0 \
  "$([ "$original_before" = "$after" ] && echo 0 || echo 1)"

# --- integration: harvest.sh against derive.sh's REAL emitted run-record.md, not a hand-copied
# fixture — closes the drift-coverage gap a fresh-context review found: mk_run() above hand-types
# derive.sh's stub text, so a future wording change there could silently desync from harvest.sh's
# field-name match with nothing in this suite catching it. This test runs the actual pipeline. ------
DERIVE_TOOL="$REPO_ROOT/tools/delta-audit/derive.sh"
ir="$(new_repo)"
git -C "$ir" commit -q --allow-empty -m init
base="$(git -C "$ir" rev-parse HEAD)"
git -C "$ir" checkout -qb pr1
printf 'x\n' > "$ir/a.txt"
git -C "$ir" add -A && git -C "$ir" commit -qm "add a.txt"
git -C "$ir" checkout -q main
# A real merge-PR commit, not a plain fast-forward — derive.sh's own closure check (the union of
# every per-PR file list vs the range diff) refuses (exit 3) without one, even though it still
# writes run-record.md either way; using the real shape here keeps this integration fixture
# representative of an actual run instead of exercising derive.sh's degraded-output path.
git -C "$ir" merge -q --no-ff -m "Merge pull request #101 from someorg/pr1" pr1
head_sha="$(git -C "$ir" rev-parse HEAD)"
iout="$SANDBOX/derive-out"
mkdir -p "$iout"
run_in "$ir" "$DERIVE_TOOL" --out "$iout" "$base" "$head_sha"
check_status "derive.sh produces a real run-record.md for the integration fixture" 0 "$STATUS"

run "$TOOL" "$iout"
check_status "harvest.sh runs clean against derive.sh's REAL stub output -> exit 0" 0 "$STATUS"
iresult="$(cat "$iout/run-record.md")"
check_contains "harvest.sh recognised derive.sh's real 'records' row" "$iresult" \
  "| records | \`delta-files.txt\`, \`file-pr-map.tsv\`, \`ledger.md\` |"
check_contains "harvest.sh recognised derive.sh's real 'cost, per leg' row" "$iresult" \
  "| cost, per leg (sessions, tier+effort, tokens or \`unmeasured\`) | unmeasured"
check_contains "harvest.sh recognised derive.sh's real 'induced defects' row" "$iresult" \
  "| induced defects (induced / total) | unmeasured"
check_contains "derive.sh's own scope row survives harvest.sh untouched" "$iresult" "| scope | 1 files, 1 PRs |"

summary
