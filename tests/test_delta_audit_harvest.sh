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

# --- F-01 (dir #267 fixer brief): the five shapes the shipped tally got wrong in four distinct
# ways. Each fixture necessarily CONTAINS the trigger it demonstrates — kept under $SANDBOX (a
# throwaway mktemp dir), never under a real run's reports/*.md glob, per the brief's own warning
# that the orchestrator hit this exact wall authoring its evidence file. -----------------------------

# Row 1 (control): a bare not-induced marker, no prose tail -> 0 induced / 1 marked.
r7a="$SANDBOX/f01-row1-control"
mk_run "$r7a"
mkdir -p "$r7a/reports"
printf 'Finding. **Mark:** `original`\n' > "$r7a/reports/S1.md"
run "$TOOL" "$r7a"
check_status "F-01 row1 (control) -> exit 0" 0 "$STATUS"
check_contains "F-01 row1: a bare original marker tallies 0 induced / 1 marked" \
  "$(cat "$r7a/run-record.md")" "| induced defects (induced / total) | 0 induced / 1 marked |"

# Row 2: a not-induced marker whose own descriptive tail contains the OTHER keyword -> must still
# read 0 induced / 1 marked, not 1 induced / 1 marked (the keyword-anywhere-later bug).
r7b="$SANDBOX/f01-row2-tail-keyword"
mk_run "$r7b"
mkdir -p "$r7b/reports"
printf 'Finding. **Mark:** `original` — not induced by this round\n' > "$r7b/reports/S1.md"
run "$TOOL" "$r7b"
check_status "F-01 row2 (tail contains other keyword) -> exit 0" 0 "$STATUS"
check_contains "MUTATION-PROOF: an original mark with an 'induced'-containing tail stays original" \
  "$(cat "$r7b/run-record.md")" "| induced defects (induced / total) | 0 induced / 1 marked |"

# Row 3: the word `benchmark:` in a sentence also containing "original" -> must find NO mark at
# all (unmeasured), not fabricate one from the unanchored label match.
r7c="$SANDBOX/f01-row3-benchmark"
mk_run "$r7c"
mkdir -p "$r7c/reports"
printf 'This is a benchmark: of the original approach, with no real Mark: line.\n' > "$r7c/reports/S1.md"
run "$TOOL" "$r7c"
check_status "F-01 row3 (benchmark: + original, no real marker) -> exit 0" 0 "$STATUS"
check_contains "MUTATION-PROOF: 'benchmark:' never fires the label match" \
  "$(cat "$r7c/run-record.md")" "| induced defects (induced / total) | unmeasured"

# Row 4: the word `remark:` in a sentence also containing "induced" -> same, unmeasured.
r7d="$SANDBOX/f01-row4-remark"
mk_run "$r7d"
mkdir -p "$r7d/reports"
printf 'A remark: induced confusion here, but no real Mark: line either.\n' > "$r7d/reports/S1.md"
run "$TOOL" "$r7d"
check_status "F-01 row4 (remark: + induced, no real marker) -> exit 0" 0 "$STATUS"
check_contains "MUTATION-PROOF: 'remark:' never fires the label match" \
  "$(cat "$r7d/run-record.md")" "| induced defects (induced / total) | unmeasured"

# Row 5: the convention quoted inside a fenced code block -> not tallied as a real finding.
r7e="$SANDBOX/f01-row5-fenced"
mk_run "$r7e"
mkdir -p "$r7e/reports"
{
  printf 'Methodology note, quoting the convention for illustration:\n\n'
  printf '```\n**Mark:** `induced` — one sentence causal path to the prior fix\n```\n'
} > "$r7e/reports/S1.md"
run "$TOOL" "$r7e"
check_status "F-01 row5 (marker quoted in a fenced block) -> exit 0" 0 "$STATUS"
check_contains "MUTATION-PROOF: a fenced-block example is blanked, not tallied" \
  "$(cat "$r7e/run-record.md")" "| induced defects (induced / total) | unmeasured"

# --- F-02 (dir #267 fixer brief): a failed final `mv` must refuse (exit 3), never exit 0 claiming
# success while run-record.md is left unchanged. Forced by shadowing `mv` on PATH, the same
# technique r4 above uses for awk. A distinctive exit code (42, not 1) proves the refusal message
# reports mv's REAL exit status rather than a fixed/wrong one — a `/code-review high` pass found
# `mv_status=$?` captured right after `if ! mv ...; then` reads the negated condition's own status
# (always 0 inside that branch), not mv's, so the message always claimed "mv exited 0" regardless
# of the actual failure; a bare exit-1 fake `mv` could not have distinguished the two. ---------------
r8="$SANDBOX/f02-mv-failure"
mk_run "$r8"
original_before_r8="$(cat "$r8/run-record.md")"
mkdir -p "$SANDBOX/fakebin-mv"
cat > "$SANDBOX/fakebin-mv/mv" <<'FAKE'
#!/bin/sh
exit 42
FAKE
chmod +x "$SANDBOX/fakebin-mv/mv"
run env PATH="$SANDBOX/fakebin-mv:$PATH" "$TOOL" "$r8"
check_status "MUTATION-PROOF: a failed final mv refuses (exit 3), not a false-success exit 0" 3 "$STATUS"
after_r8="$(cat "$r8/run-record.md")"
check_status "run-record.md is untouched byte-for-byte after the mv failure" 0 \
  "$([ "$original_before_r8" = "$after_r8" ] && echo 0 || echo 1)"
check_contains "MUTATION-PROOF: the refusal reports mv's REAL exit code (42), not always 0" \
  "$OUT" "mv exited 42"

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

# --- a 10+ digit token count must still be reported as a real figure, not silently degraded to
# unmeasured — a `/code-review` delta round on the fix above found the lib's own 10-digit default cap
# would misreport a legitimate large figure; harvest.sh must pass a larger explicit cap ----------------
r5="$SANDBOX/run5-large-token-count"
mk_run "$r5"
printf '# notes\n\n| leg | model / effort | tokens | tool calls | wall clock |\n|---|---|---|---|---|\n| S1 big | mid tier | 12345678901 | 1 | 1m |\n' \
  > "$r5/orchestrator-notes.md"
run "$TOOL" "$r5"
check_status "10+ digit token count fixture -> exit 0" 0 "$STATUS"
out5="$(cat "$r5/run-record.md")"
check_contains "an 11-digit token count is reported as a real figure, not degraded to unmeasured" \
  "$out5" "S1 big: 12345678901 tokens"

# --- a missing tools/lib/nonneg-int.sh must refuse (exit 3) with a clear message, never degrade
# silently into treating every cost as unmeasured while still exiting 0 -----------------------------
r6="$SANDBOX/run6-missing-lib"
mk_run "$r6"
lib_copy_dir="$SANDBOX/harvest-copy"
mkdir -p "$lib_copy_dir/delta-audit"
cp "$TOOL" "$lib_copy_dir/delta-audit/harvest.sh"
# lib/ deliberately absent alongside this copy, unlike the real tree's tools/lib/nonneg-int.sh
run "$lib_copy_dir/delta-audit/harvest.sh" "$r6"
check_status "a missing tools/lib/nonneg-int.sh -> exit 3 (refuse), not a silent degrade" 3 "$STATUS"
check_contains "the refusal names the missing lib, not a raw bash sourcing error" "$OUT" \
  "missing shared lib"

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
