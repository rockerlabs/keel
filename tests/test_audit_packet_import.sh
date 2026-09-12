#!/usr/bin/env bash
# Tests for tools/audit-packet/import.sh — dir #495 PR1: import an external auditor's replies back
# into drydock's ordinary file contract.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/audit-packet/import.sh"
check_file "import.sh exists" "$TOOL"

# A minimal MANIFEST.txt in the shape export.sh writes — enough for import.sh's own contract (it
# reads vendor:/baseline: and the "## chunks" path map, nothing else from this file).
mk_packet() {
  local d="$1"
  mkdir -p "$d/chunks"
  {
    printf '# audit-packet MANIFEST — packet-testvendor-2026-01-01-abc1234\n'
    printf 'remote: (no remote)\n'
    printf 'baseline: abc1234000000000000000000000000000000 (HEAD)\n'
    printf 'exporter: tools/audit-packet/export.sh | files scanned: 2\n'
    printf 'vendor: testvendor\n'
    printf 'disclosure-ack: test: fixture\n'
    printf 'generated: 2026-01-01T00:00:00Z\n'
    printf 'leak gate: clean (2 file(s) scanned)\n\n'
    printf '## chunks\n'
    printf 'chunk 01: files=2 bytes=10 sha256=deadbeef\n'
    printf '  PRINCIPLES.md\n'
    printf '  README.md\n'
    printf 'chunk 02: files=1 bytes=5 sha256=deadbeef\n'
    printf '  tool.sh\n'
  } > "$d/MANIFEST.txt"
}

# --- basic round-trip: two mapped paths in one chunk, an unmapped path in the same reply -----------
d1="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d1"
cat > "$d1/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## PRINCIPLES.md

### F1 — stale-claim — "the quoted line"
claim: asserts X
evidence: measured Y
confidence: high
verdict: accepted

## README.md

### F1 — overclaim — "another quoted line"
claim: overpromises
evidence: not backed
confidence: medium

## not/in/manifest.md

### F1 — contradiction — "orphan finding"
claim: bogus
evidence: bogus
confidence: low
EOF
cat > "$d1/reply-value.md" <<'EOF'
Opinion text — must never be imported as a finding.
EOF

out1="$SANDBOX/audit1"
mkdir -p "$out1"
run "$TOOL" "$d1" "$out1"
check_status "import: round-trip exits 0 on a clean reply" 0 "$STATUS"

check_file "import: PRINCIPLES.md-audit.md written" "$out1/PRINCIPLES.md-audit.md"
check_file "import: README.md-audit.md written" "$out1/README.md-audit.md"
check_nofile "import: reply-value.md never becomes an audit file" "$out1/reply-value.md-audit.md"
check_nofile "import: no tool.sh-audit.md (chunk 02 never replied)" "$out1/tool.sh-audit.md"

principles="$(cat "$out1/PRINCIPLES.md-audit.md" 2>/dev/null)"
check_contains "import: contract header names the path and baseline" "$principles" \
  "# drydock audit — PRINCIPLES.md @ abc1234000000000000000000000000000000"
check_contains "import: auditor line names external/<vendor>" "$principles" "auditor: external/testvendor"
check_contains "import: finding heading carries the quote, not a line number" "$principles" \
  '### F1 — stale-claim — "the quoted line"'
check_contains "import: ## claims marker present (drydock's completeness marker)" "$principles" \
  '## claims'
check_contains "import: claims line is the honest no-tool-access marker" "$principles" \
  "(external leg — claims not collected; no tool access)"
# mutation-proof: the model wrote "verdict: accepted" — import.sh must have STRIPPED it, not passed
# it through. A bare substring check for "verdict:" would pass even if the value leaked; assert the
# exact empty-field line instead, and separately that the model's own value is gone.
check_contains "import: verdict: is forced EMPTY (exact line, not the model's own value)" "$principles" \
  $'verdict:\n'
check_absent "import: the model's own 'verdict: accepted' does not survive" "$principles" "verdict: accepted"

readme="$(cat "$out1/README.md-audit.md" 2>/dev/null)"
check_contains "import: a second file in the same chunk imports independently" "$readme" \
  '### F1 — overclaim — "another quoted line"'

check_file "import: an unmapped path lands in EXTERNAL-UNMAPPED.md" "$out1/EXTERNAL-UNMAPPED.md"
unmapped="$(cat "$out1/EXTERNAL-UNMAPPED.md" 2>/dev/null)"
check_contains "import: EXTERNAL-UNMAPPED names the unmapped path" "$unmapped" "not/in/manifest.md"
check_nofile "import: an unmapped path never gets a fabricated slug" "$out1/not-in-manifest.md-audit.md"

# --- appending to an existing same-family audit file: numbering continued, existing claims kept ----
d2="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d2"
cat > "$d2/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## PRINCIPLES.md

### F1 — stale-claim — "the quoted line"
claim: asserts X
evidence: measured Y
confidence: high
EOF
out2="$SANDBOX/audit2"
mkdir -p "$out2"
cat > "$out2/PRINCIPLES.md-audit.md" <<'EOF'
# drydock audit — PRINCIPLES.md @ abc1234000000000000000000000000000000
auditor: sonnet + high | 2026-01-01

## findings
### F1 — duplication — L1-2
claim: repeats itself
evidence: measured
verdict: accepted

## claims
- a real claim from the same-family auditor
EOF
run "$TOOL" "$d2" "$out2"
check_status "import: append run exits 0" 0 "$STATUS"
appended="$(cat "$out2/PRINCIPLES.md-audit.md" 2>/dev/null)"
check_contains "import: pre-existing F1 (same-family) is untouched" "$appended" "duplication — L1-2"
check_contains "import: pre-existing verdict is untouched (not the external leg's to touch)" \
  "$appended" "verdict: accepted"
check_contains "import: external finding numbered F2 (continued, not restarted at F1)" "$appended" \
  '### F2 — stale-claim — "the quoted line"'
check_contains "import: appended under its own external-findings sub-heading" "$appended" \
  '## external findings'
check_contains "import: the pre-existing claims line survives verbatim" "$appended" \
  "a real claim from the same-family auditor"
check_count "import: exactly one ## claims section (never duplicated)" "$out2/PRINCIPLES.md-audit.md" \
  '^## claims$' 1

# --- a reply missing its own CHUNK-END is refused, other chunks still imported -------------------
d3="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d3"
cat > "$d3/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## PRINCIPLES.md

### F1 — stale-claim — "ok chunk"
claim: x
evidence: y
EOF
cat > "$d3/reply-02.md" <<'EOF'
Sorry, I ran out of room and could not finish this one.
## tool.sh
### F1 — optimization — "echo hi"
claim: x
evidence: y
EOF
out3="$SANDBOX/audit3"
mkdir -p "$out3"
run "$TOOL" "$d3" "$out3"
check_status "import: exits 1 when a chunk is truncated/off-format" 1 "$STATUS"
check_contains "import: names the FAILED chunk" "$OUT" "FAILED chunk 02"
check_file "import: the OTHER (valid) chunk still imports" "$out3/PRINCIPLES.md-audit.md"
check_nofile "import: the failed chunk writes nothing for its own file" "$out3/tool.sh-audit.md"

# --- a code-fenced reply is tolerated -------------------------------------------------------------
d4="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d4"
cat > "$d4/reply-01.md" <<'EOF'
```markdown
CHUNK-END 01 files=2 bytes=10

## PRINCIPLES.md

### F1 — stale-claim — "fenced ok"
claim: x
evidence: y
```
EOF
out4="$SANDBOX/audit4"
mkdir -p "$out4"
run "$TOOL" "$d4" "$out4"
check_status "import: a code-fenced reply still imports" 0 "$STATUS"
check_contains "import: fenced finding lands in the audit file" \
  "$(cat "$out4/PRINCIPLES.md-audit.md" 2>/dev/null)" '"fenced ok"'

# --- argument / refusal edges --------------------------------------------------------------------
run "$TOOL" "$SANDBOX/does-not-exist" "$out1"
check_status "import: refuses a reply-dir that does not exist at all" 3 "$STATUS"

run "$TOOL" "$d1"
check_status "import: refuses with only one positional argument" 2 "$STATUS"

run "$TOOL" --help
check_status "import: --help exits 0" 0 "$STATUS"
check_contains "import: --help prints usage" "$OUT" "<reply-dir> <audit-dir>"

# --- two distinct paths whose secfile_for() slug WOULD have collided (pre-fix) don't lose findings
# (code review high, Angle A/C): "docs/sub.md" and "docs_sub.md" both sanitize to the same string
# under a tr '/'->'_' scheme; secfile_for() is now index-based, never path-derived, so this can no
# longer collide by construction.
d5="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mkdir -p "$d5/chunks"
{
  printf 'vendor: testvendor\n'
  printf 'baseline: abc1234000000000000000000000000000000 (HEAD)\n\n'
  printf '## chunks\n'
  printf 'chunk 01: files=2 bytes=10 sha256=deadbeef\n'
  printf '  docs/sub.md\n'
  printf '  docs_sub.md\n'
} > "$d5/MANIFEST.txt"
cat > "$d5/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## docs/sub.md

### F1 — stale-claim — "first path finding"
claim: x
evidence: y

## docs_sub.md

### F1 — stale-claim — "second path finding"
claim: x
evidence: y
EOF
out5="$SANDBOX/audit5"
mkdir -p "$out5"
run "$TOOL" "$d5" "$out5"
check_status "import: colliding-slug fixture exits 0" 0 "$STATUS"
check_contains "import: docs/sub.md's own finding survives (not clobbered by docs_sub.md's)" \
  "$(cat "$out5/docs-sub.md-audit.md" 2>/dev/null)" "first path finding"
check_contains "import: docs_sub.md's own finding is present too" \
  "$(cat "$out5/docs_sub.md-audit.md" 2>/dev/null)" "second path finding"
check_absent "import: the two findings are not merged into one file" \
  "$(cat "$out5/docs-sub.md-audit.md" 2>/dev/null)" "second path finding"

# ==================================================================================================
# UNCHUNKED mode (mode B, manager amendments W2-A2/A3): a bare directory of reply*.md files, no
# MANIFEST.txt — a reader who cloned the whole repo directly, with tools, no chunks, no probe.
# ==================================================================================================

# --- --vendor is required (no MANIFEST.txt to read one from) -------------------------------------
d6="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d6/reply.md" <<'EOF'
BASELINE deadbeefdeadbeefdeadbeefdeadbeefdeadbeef

## a.md

### F1 — stale-claim — "x"
claim: x
evidence: y
EOF
out6="$SANDBOX/audit6"
mkdir -p "$out6"
run "$TOOL" "$d6" "$out6"
check_status "unchunked: refuses with no --vendor" 2 "$STATUS"
check_contains "unchunked: names --vendor as the fix" "$OUT" "--vendor"

# --- basic round-trip: BASELINE line captured, summary routed away, numbers preserved verbatim ---
# (NOT sequential from 1 — F1/F2 in the first file, then F7 in the second — proving genuine
# preservation rather than a renumber that happens to start at 1 by coincidence.)
d7="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d7/reply-01.md" <<'EOF'
BASELINE cafebabecafebabecafebabecafebabecafebabe

## a/b.md

### F1 — stale-claim — "first finding"
claim: x1
evidence: y1
confidence: high
verdict: accepted

### F2 — overclaim — "second finding"
claim: x2
evidence: y2

## c.sh

### F7 — optimization — "seventh finding, preserved as-is"
claim: x7
evidence: y7

## Summary

This project does X. Strongest idea: Y.
Weakest idea: Z.
EOF
out7="$SANDBOX/audit7"
mkdir -p "$out7"
run "$TOOL" --vendor codex "$d7" "$out7"
check_status "unchunked: basic round-trip exits 0" 0 "$STATUS"

ab_audit="$(cat "$out7/a-b.md-audit.md" 2>/dev/null)"
check_contains "unchunked: BASELINE line becomes the audit header's baseline" "$ab_audit" \
  "@ cafebabecafebabecafebabecafebabecafebabe"
check_contains "unchunked: auditor line names external/<vendor>, identical shape to chunked mode" \
  "$ab_audit" "auditor: external/codex"
check_contains "unchunked: F1 preserved exactly (not renumbered)" "$ab_audit" '### F1 — stale-claim — "first finding"'
check_contains "unchunked: F2 preserved exactly" "$ab_audit" '### F2 — overclaim — "second finding"'
check_contains "unchunked: verdict forced empty even though the model wrote 'accepted'" "$ab_audit" $'verdict:\n'
check_absent "unchunked: the model's own 'verdict: accepted' does not survive" "$ab_audit" "verdict: accepted"
check_contains "unchunked: ## claims marker present (drydock's completeness marker)" "$ab_audit" "## claims"

c_audit="$(cat "$out7/c.sh-audit.md" 2>/dev/null)"
check_contains "unchunked: F7 in the SECOND file preserved verbatim, not reset to F1" "$c_audit" \
  '### F7 — optimization — "seventh finding, preserved as-is"'
check_absent "unchunked: the second file does NOT get a renumbered F1" "$c_audit" '### F1'

check_file "unchunked: ## Summary routed to SUMMARY.md" "$out7/SUMMARY.md"
check_contains "unchunked: SUMMARY.md carries the summary's own prose" \
  "$(cat "$out7/SUMMARY.md" 2>/dev/null)" "Strongest idea: Y"
check_nofile "unchunked: 'summary' never becomes a fabricated audit file" "$out7/Summary-audit.md"
check_nofile "unchunked: 'summary' never lands in EXTERNAL-UNMAPPED.md-shaped output" "$out7/summary-audit.md"

# --- no CHUNK-END check applies in unchunked mode: content that would FAIL chunked mode's own
# truncation detector imports fine here (nothing was chunked, so nothing can be truncated) --------
d8="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d8/reply.md" <<'EOF'
BASELINE 1111111111111111111111111111111111111111

## z.md

### F1 — stale-claim — "no CHUNK-END anywhere in this reply"
claim: x
evidence: y
EOF
out8="$SANDBOX/audit8"
mkdir -p "$out8"
run "$TOOL" --vendor codex "$d8" "$out8"
check_status "unchunked: no CHUNK-END needed, still exits 0" 0 "$STATUS"
check_file "unchunked: the finding still imports" "$out8/z.md-audit.md"

# --- a missing BASELINE line warns, falls back to 'unknown', never crashes -------------------------
d9="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d9/reply.md" <<'EOF'
## y.md

### F1 — stale-claim — "no baseline line at all"
claim: x
evidence: y
EOF
out9="$SANDBOX/audit9"
mkdir -p "$out9"
run "$TOOL" --vendor codex "$d9" "$out9"
check_status "unchunked: a missing BASELINE line warns, does not refuse" 0 "$STATUS"
check_contains "unchunked: '@ unknown' when BASELINE is missing, not an empty/broken header" \
  "$(cat "$out9/y.md-audit.md" 2>/dev/null)" "@ unknown"

# --- reply-value.md is still ignored in unchunked mode too -----------------------------------------
d10="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d10/reply.md" <<'EOF'
BASELINE 2222222222222222222222222222222222222222

## w.md

### F1 — stale-claim — "real finding"
claim: x
evidence: y
EOF
cat > "$d10/reply-value.md" <<'EOF'
Opinion text, not a finding.
EOF
out10="$SANDBOX/audit10"
mkdir -p "$out10"
run "$TOOL" --vendor codex "$d10" "$out10"
check_status "unchunked: reply-value.md alongside a real reply still exits 0" 0 "$STATUS"
check_nofile "unchunked: reply-value.md never becomes an audit file here either" "$out10/reply-value.md-audit.md"

# --- two replies at DIFFERENT baselines touching the same path: the second's own baseline must
# survive on its own "## external findings" block, not silently inherit the first reply's header
# baseline (code review high, Angle C, batch review round — reproduced live before this fix). -------
d11="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d11/reply-a.md" <<'EOF'
BASELINE aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

## shared.md

### F1 — issue-a — "from reply A"
claim: x
evidence: y
EOF
cat > "$d11/reply-b.md" <<'EOF'
BASELINE bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

## shared.md

### F1 — issue-b — "from reply B"
claim: x
evidence: y
EOF
out11="$SANDBOX/audit11"
mkdir -p "$out11"
run "$TOOL" --vendor test "$d11" "$out11"
check_status "unchunked: two different-baseline replies on one path exits 0" 0 "$STATUS"
shared_audit="$(cat "$out11/shared.md-audit.md" 2>/dev/null)"
check_contains "unchunked: the file's own header keeps the FIRST reply's baseline" "$shared_audit" \
  "@ aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
check_contains "unchunked: the appended external findings carry the SECOND reply's OWN baseline" \
  "$shared_audit" "baseline: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
check_absent "unchunked: the second reply's findings never silently inherit the first's baseline" \
  "$(section_body '## external findings' "$out11/shared.md-audit.md")" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# --- MANIFEST.txt present but unreadable is a REFUSAL, never a silent switch to unchunked mode ----
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  d12="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
  mkdir -p "$d12/chunks"
  printf 'vendor: t\nbaseline: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef (HEAD)\n\n## chunks\n' > "$d12/MANIFEST.txt"
  chmod 000 "$d12/MANIFEST.txt"
  out12="$SANDBOX/audit12"
  mkdir -p "$out12"
  run "$TOOL" "$d12" "$out12"
  check_status "unreadable (not absent) MANIFEST.txt -> exit 3, never silently unchunked" 3 "$STATUS"
  check_contains "names it as unreadable, not a missing-manifest/unchunked message" "$OUT" "not readable"
  chmod 644 "$d12/MANIFEST.txt"
fi

# --- a "## summary" heading with stray whitespace (trailing space, doubled leading space) is still
# recognized — not silently dropped with zero trace anywhere (code review high, Angle A, batch
# review round — reproduced live before this fix: the WHOLE section vanished, no file, no warning).
d13="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
printf 'BASELINE cccccccccccccccccccccccccccccccccccccccc\n\n## a.md\n\n### F1 — x — "y"\nclaim: x\nevidence: y\n\n## Summary \n\nTrailing-space summary survives.\n' \
  > "$d13/reply.md"
out13="$SANDBOX/audit13"
mkdir -p "$out13"
run "$TOOL" --vendor test "$d13" "$out13"
check_status "unchunked: a trailing-space '## Summary ' heading still exits 0" 0 "$STATUS"
check_file "unchunked: SUMMARY.md is written despite the stray trailing space" "$out13/SUMMARY.md"
check_contains "unchunked: the summary's own prose survives" \
  "$(cat "$out13/SUMMARY.md" 2>/dev/null)" "Trailing-space summary survives"
check_nofile "unchunked: never fabricated as its own audit file instead" "$out13/Summary-audit.md"

# --- dir #504: CHUNKED mode's splitter has a "## summary" case too, matching unchunked mode (found
# live, code-review medium, PR2's own round: the chunked splitter had NO summary case at all — a
# reply's mandated "## summary" section was treated as an audit target with no "### F<n>" blocks in
# it, and render_findings() found nothing, so the section vanished with no file, no SUMMARY.md
# entry, no warning). Routes to SUMMARY.md under a "### chunk NN" sub-heading (per chunk, since a
# chunked reply is scoped to its own chunk, unlike unchunked's whole-repo single pass).
d14="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d14"
cat > "$d14/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## summary

This chunk's own summary prose.

## PRINCIPLES.md

### F1 — stale-claim — "the quoted line"
claim: asserts X
evidence: measured Y
confidence: high
EOF
out14="$SANDBOX/audit14"
mkdir -p "$out14"
run "$TOOL" "$d14" "$out14"
check_status "chunked: a '## summary' section exits 0" 0 "$STATUS"
check_file "chunked: SUMMARY.md is written for a chunked reply's summary section" "$out14/SUMMARY.md"
check_contains "chunked: SUMMARY.md sub-heading names the chunk it came from" \
  "$(cat "$out14/SUMMARY.md" 2>/dev/null)" "### chunk 01"
check_contains "chunked: the summary's own prose survives" \
  "$(cat "$out14/SUMMARY.md" 2>/dev/null)" "This chunk's own summary prose."
check_nofile "chunked: '## summary' never becomes its own fabricated audit file" "$out14/summary-audit.md"
check_nofile "chunked: no EXTERNAL-UNMAPPED.md created (no unmapped path in this reply)" \
  "$out14/EXTERNAL-UNMAPPED.md"
check_file "chunked: the real PRINCIPLES.md section still imports alongside the summary" \
  "$out14/PRINCIPLES.md-audit.md"

# --- dir #504: chunked mode's summary case tolerates the same stray whitespace unchunked mode does
# — both splitters now call the same shared trim_ws/is_summary_title helpers, not two copies. -----
d15="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d15"
cat > "$d15/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

##  Summary

Doubled-leading-space chunked summary survives.

## PRINCIPLES.md

### F1 — stale-claim — "the quoted line"
claim: asserts X
evidence: measured Y
confidence: high
EOF
out15="$SANDBOX/audit15"
mkdir -p "$out15"
run "$TOOL" "$d15" "$out15"
check_status "chunked: a '##  Summary' (doubled leading space) heading still exits 0" 0 "$STATUS"
check_contains "chunked: SUMMARY.md is written despite the doubled leading space" \
  "$(cat "$out15/SUMMARY.md" 2>/dev/null)" "Doubled-leading-space chunked summary survives."
check_nofile "chunked: never fabricated as its own audit file instead" "$out15/Summary-audit.md"

# --- dir #503: a "## <path>" section with a heading but no real "### F<n>" blocks under it is
# counted as skipped-empty, not imported (found live, dir #495 PR1's post-merge review, Angle A: the
# old single "imported N" counter incremented on every CALL to import_findings_into_contract(),
# regardless of whether it actually wrote anything). Mutation-proof: the combined-count substring
# ("imported 1, skipped-empty 1") cannot pass if either number is wrong, unlike checking each count
# in isolation (which "imported 10, skipped-empty 1" would also satisfy for the first check alone).
d16="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d16"
cat > "$d16/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## PRINCIPLES.md

Just prose, no finding blocks here at all.

## README.md

### F1 — overclaim — "a real finding"
claim: x
evidence: y
confidence: high
EOF
out16="$SANDBOX/audit16"
mkdir -p "$out16"
run "$TOOL" "$d16" "$out16"
check_status "chunked: mixed empty+real sections still exits 0" 0 "$STATUS"
check_contains "chunked: stdout reports exactly 1 imported, 1 skipped-empty" "$OUT" \
  "imported 1, skipped-empty 1"
check_nofile "chunked: the empty section never fabricates an audit file" "$out16/PRINCIPLES.md-audit.md"
check_file "chunked: the real section still imports" "$out16/README.md-audit.md"

# --- dir #503 (unchunked mode): the same imported vs skipped-empty distinction applies there too --
d17="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d17/reply.md" <<'EOF'
BASELINE dddddddddddddddddddddddddddddddddddddddd

## empty/path.md

Just prose, no finding blocks here at all.

## real/path.md

### F7 — overclaim — "a real finding"
claim: x
evidence: y
confidence: high
EOF
out17="$SANDBOX/audit17"
mkdir -p "$out17"
run "$TOOL" --vendor test "$d17" "$out17"
check_status "unchunked: mixed empty+real sections still exits 0" 0 "$STATUS"
check_contains "unchunked: stdout reports exactly 1 imported, 1 skipped-empty" "$OUT" \
  "imported 1, skipped-empty 1"
check_nofile "unchunked: the empty section never fabricates an audit file" "$out17/empty-path.md-audit.md"
check_file "unchunked: the real section still imports" "$out17/real-path.md-audit.md"

# --- dir #503: append_unmapped's own call site had the identical call-counted-not-write-counted
# bug (found live, this round's own code-review medium delta round) — an unmapped path whose section
# rendered no real findings must not bump "unmapped", since EXTERNAL-UNMAPPED.md gets nothing for it.
d18="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d18"
cat > "$d18/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## not/in/manifest.md

Just prose, no finding blocks here at all.

## PRINCIPLES.md

### F1 — overclaim — "a real finding"
claim: x
evidence: y
confidence: high
EOF
out18="$SANDBOX/audit18"
mkdir -p "$out18"
run "$TOOL" "$d18" "$out18"
check_status "chunked: an empty unmapped section still exits 0" 0 "$STATUS"
check_contains "chunked: stdout reports exactly 1 imported, 1 skipped-empty, 0 unmapped" "$OUT" \
  "imported 1, skipped-empty 1 into $out18, 0 unmapped"
check_nofile "chunked: EXTERNAL-UNMAPPED.md is never created for an empty unmapped section" \
  "$out18/EXTERNAL-UNMAPPED.md"

# --- dir #503: a "## summary" section holding only blank line(s) is NOT content — no spurious
# sub-heading with nothing under it (found live, this round's own code-review medium delta round;
# `[ -n "$summary_body" ]` treated a bare "\n" as non-empty). Covers both modes since both splitters
# share the same has_content() guard.
d19="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
mk_packet "$d19"
cat > "$d19/reply-01.md" <<'EOF'
CHUNK-END 01 files=2 bytes=10

## summary


## PRINCIPLES.md

### F1 — overclaim — "a real finding"
claim: x
evidence: y
confidence: high
EOF
out19="$SANDBOX/audit19"
mkdir -p "$out19"
run "$TOOL" "$d19" "$out19"
check_status "chunked: a blank '## summary' section still exits 0" 0 "$STATUS"
check_nofile "chunked: a blank summary never writes SUMMARY.md at all" "$out19/SUMMARY.md"

d20="$(mktemp -d "$SANDBOX/pkt.XXXXXX")"
cat > "$d20/reply.md" <<'EOF'
BASELINE eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee

## summary


## real/path.md

### F1 — overclaim — "a real finding"
claim: x
evidence: y
confidence: high
EOF
out20="$SANDBOX/audit20"
mkdir -p "$out20"
run "$TOOL" --vendor test "$d20" "$out20"
check_status "unchunked: a blank '## summary' section still exits 0" 0 "$STATUS"
check_nofile "unchunked: a blank summary never writes SUMMARY.md at all" "$out20/SUMMARY.md"

summary
