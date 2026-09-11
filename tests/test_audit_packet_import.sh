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

summary
