#!/usr/bin/env bash
# Tests for tools/audit-packet/export.sh — dir #495 PR1: the leak-gated audit-packet exporter.
#
# The leak gate is the safety rail this whole ticket exists for, so it gets the most assertions here:
# a planted key-shaped secret and a planted personal literal both must BLOCK (exit 3, nothing
# written), and — the specific bug this suite pins, caught live while writing export.sh — the
# BLOCKED message must carry ONLY the offending path, never the matched content (a from-the-end strip
# tried first leaked a content fragment; see export.sh's own comment on `${rec%%:*}`).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/audit-packet/export.sh"
check_file "export.sh exists" "$TOOL"

# --- fixture -----------------------------------------------------------------------------------
# One prose file, one nested prose file, one code file, one historical file (CHANGELOG.md) — enough
# to exercise the *.md-first / code-second / historical-own-chunk ordering rule without needing a
# large tree.
mk_repo() {
  local d
  d="$(new_repo)"
  printf '# Principles\nSome prose about the project.\n' > "$d/PRINCIPLES.md"
  mkdir -p "$d/docs/drydock"
  printf '# Sub\nmore prose\n' > "$d/docs/sub.md"
  printf '#!/usr/bin/env bash\necho hi\n' > "$d/tool.sh"
  printf '# Changelog\n## v1.0.0\n- initial\n' > "$d/CHANGELOG.md"
  printf '# External auditor prompt\n\nAudit files at <baseline-sha> in <repo-name>, chunk <chunk-id>.\n' \
    > "$d/docs/drydock/external-auditor.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m init
  printf '%s' "$d"
}

files_list() { printf 'PRINCIPLES.md\ndocs/sub.md\ntool.sh\nCHANGELOG.md\n'; }

# --- basic success: correct chunking, MANIFEST, PROMPT.md, leak gate clean ----------------------
r="$(mk_repo)"
sha="$(git -C "$r" rev-parse HEAD)"
sha7="${sha:0:7}"
fl="$SANDBOX/files-basic.txt"
files_list > "$fl"

run_in "$r" "$TOOL" --vendor astra --baseline HEAD --out out --disclosure-ack "test: fixture" --files "$fl"
check_status "export: clean fixture exits 0" 0 "$STATUS"
check_contains "export: reports leak gate clean" "$OUT" "leak gate clean"

pkt="$(find "$r/out" -maxdepth 1 -name 'packet-astra-*' -type d | head -1)"
check_dir "export: packet dir written" "${pkt:-/nonexistent}"
check_file "export: MANIFEST.txt written" "$pkt/MANIFEST.txt"
check_file "export: README-operator.md written" "$pkt/README-operator.md"
check_file "export: PROBE.md written" "$pkt/PROBE.md"
check_file "export: PROMPT.md written" "$pkt/PROMPT.md"
check_contains "export: PROBE.md ends in PROBE-END" "$(cat "$pkt/PROBE.md" 2>/dev/null)" "PROBE-END"
check_contains "export: PROMPT.md substitutes baseline sha" "$(cat "$pkt/PROMPT.md" 2>/dev/null)" "$sha"
check_absent "export: PROMPT.md has no leftover <baseline-sha> placeholder" \
  "$(cat "$pkt/PROMPT.md" 2>/dev/null)" "<baseline-sha>"

# chunk 01 = the two markdown files (packed together, *.md first); chunk 02 = the code file;
# chunk 03 = CHANGELOG.md, alone, in its own trailing chunk (the --historical rule).
check_file "export: chunks/01.txt written" "$pkt/chunks/01.txt"
check_file "export: chunks/02.txt written" "$pkt/chunks/02.txt"
check_file "export: chunks/03.txt written (CHANGELOG own chunk)" "$pkt/chunks/03.txt"
check_nofile "export: no chunks/04.txt (exactly 3 chunks)" "$pkt/chunks/04.txt"
check_contains "export: chunk01 holds PRINCIPLES.md" "$(cat "$pkt/chunks/01.txt" 2>/dev/null)" "FILE: PRINCIPLES.md @ $sha7"
check_contains "export: chunk01 holds docs/sub.md" "$(cat "$pkt/chunks/01.txt" 2>/dev/null)" "FILE: docs/sub.md @ $sha7"
check_contains "export: chunk02 holds tool.sh" "$(cat "$pkt/chunks/02.txt" 2>/dev/null)" "FILE: tool.sh @ $sha7"
check_contains "export: chunk03 holds CHANGELOG.md, alone" "$(cat "$pkt/chunks/03.txt" 2>/dev/null)" "FILE: CHANGELOG.md @ $sha7"
check_absent "export: chunk03 does NOT also hold tool.sh (historical gets its own chunk)" \
  "$(cat "$pkt/chunks/03.txt" 2>/dev/null)" "FILE: tool.sh"

# every chunk ends in its own CHUNK-END line (mutation-proof: assert the EXACT line, not a substring
# that a truncated/renumbered chunk could still satisfy).
check_contains "export: chunks/01.txt ends CHUNK-END 01" "$(tail -1 "$pkt/chunks/01.txt" 2>/dev/null)" "CHUNK-END 01 files=2"
check_contains "export: chunks/02.txt ends CHUNK-END 02" "$(tail -1 "$pkt/chunks/02.txt" 2>/dev/null)" "CHUNK-END 02 files=1"
check_contains "export: chunks/03.txt ends CHUNK-END 03" "$(tail -1 "$pkt/chunks/03.txt" 2>/dev/null)" "CHUNK-END 03 files=1"

# --- packing never exceeds --chunk-bytes unless a single file must (OVERSIZE) --------------------
# A fresh fixture, not $r again: $r's tree now has an untracked out/ from the run above, which would
# trip the dirty-tree guard — caught live writing this suite (the exact "dirty tree" class this
# script's own guard exists to catch, one repo over).
r2b="$(mk_repo)"
fl2b="$SANDBOX/files-oversize.txt"
files_list > "$fl2b"
run_in "$r2b" "$TOOL" --vendor small --baseline HEAD --out out2 --chunk-bytes 5 --disclosure-ack "t" --files "$fl2b"
check_status "export: tiny --chunk-bytes still succeeds (OVERSIZE, not a refusal)" 0 "$STATUS"
pkt2="$(find "$r2b/out2" -maxdepth 1 -name 'packet-small-*' -type d | head -1)"
check_count "export: MANIFEST marks every chunk OVERSIZE at chunk-bytes=5" "$pkt2/MANIFEST.txt" 'OVERSIZE' 4
check_file "export: still 4 separate chunks at chunk-bytes=5 (one file per chunk)" "$pkt2/chunks/04.txt"

# --- refusals: dirty tree, wrong HEAD ------------------------------------------------------------
echo dirty >> "$r/PRINCIPLES.md"
run_in "$r" "$TOOL" --vendor x --baseline HEAD --disclosure-ack "t" --files "$fl"
check_status "export: refuses a dirty tree" 3 "$STATUS"
check_contains "export: dirty-tree message names the reason" "$OUT" "dirty working tree"
git -C "$r" checkout -q -- PRINCIPLES.md

git -C "$r" commit -q --allow-empty -m second
run_in "$r" "$TOOL" --vendor x --baseline "$sha" --disclosure-ack "t" --files "$fl"
check_status "export: refuses when HEAD is not --baseline" 3 "$STATUS"
check_contains "export: wrong-HEAD message says so" "$OUT" "HEAD is not the baseline"
git -C "$r" reset -q --hard "$sha"

# --- the leak gate: a key-shaped secret BLOCKS, path-only, never content ------------------------
r2="$(mk_repo)"
printf 'ghp_%s\n' "$(rep a 36)" >> "$r2/tool.sh"
git -C "$r2" add -A
KEEL_IMPACT_LOG='' git -C "$r2" commit -q -m "plant a key-shaped secret" --no-verify
fl2="$SANDBOX/files-secret.txt"
files_list > "$fl2"
run_in "$r2" "$TOOL" --vendor x --baseline HEAD --out out --disclosure-ack "t" --files "$fl2"
check_status "export: BLOCKS on a planted key-shaped secret" 3 "$STATUS"
check_contains "export: BLOCKED message names the offending path" "$OUT" "tool.sh"
check_absent "export: BLOCKED message never repeats the secret's own text" "$OUT" "$(rep a 36)"
check_nodir "export: nothing written when the gate blocks" "$r2/out"

# --- the leak gate: a personal literal (class 2) BLOCKS too, from the sandboxed HOME's file --------
r3="$(mk_repo)"
printf 'contact: definitely-a-personal-marker@example.invalid\n' >> "$r3/docs/sub.md"
git -C "$r3" add -A
KEEL_IMPACT_LOG='' git -C "$r3" commit -q -m "plant a personal literal" --no-verify
fl3="$SANDBOX/files-personal.txt"
files_list > "$fl3"
personal_file="$SANDBOX/secret-scan-personal-fixture"
printf 'definitely-a-personal-marker@example\\.invalid\n' > "$personal_file"
( cd "$r3" && SECRET_SCAN_PERSONAL_FILE="$personal_file" "$TOOL" --vendor x --baseline HEAD --out out \
    --disclosure-ack "t" --files "$fl3" > "$SANDBOX/personal.out" 2>&1 )
pstatus=$?
check_status "export: BLOCKS on a planted personal literal" 3 "$pstatus"
check_contains "export: personal-literal block names the path" "$(cat "$SANDBOX/personal.out")" "docs/sub.md"
check_absent "export: personal-literal block never repeats the literal itself" \
  "$(cat "$SANDBOX/personal.out")" "definitely-a-personal-marker"
check_nodir "export: nothing written on a personal-literal block" "$r3/out"

# --- an unreadable listed file: refused, not silently skipped — root-reader guard (CLAUDE.md's
# 2nd Alpine trap: chmod 000 is a no-op for a root reader, so the content-based half of this
# assertion can only hold for a non-root test runner). The exit-code half is unconditional: an
# unreadable-to-the-caller file must never make the gate quietly pass.
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  r4="$(mk_repo)"
  chmod 000 "$r4/tool.sh"
  fl4="$SANDBOX/files-unreadable.txt"
  files_list > "$fl4"
  run_in "$r4" "$TOOL" --vendor x --baseline HEAD --disclosure-ack "t" --files "$fl4"
  check_status "export: refuses (does not silently skip) an unreadable listed file" 3 "$STATUS"
  chmod 644 "$r4/tool.sh"
fi

# --- --disclosure-ack required for a non-keel repo; keel's own remote defaults it ----------------
r5="$(mk_repo)"
fl5="$SANDBOX/files-ack.txt"
files_list > "$fl5"
run_in "$r5" "$TOOL" --vendor x --baseline HEAD --files "$fl5"
check_status "export: refuses a non-keel repo with no --disclosure-ack" 2 "$STATUS"
check_contains "export: names --disclosure-ack as the fix" "$OUT" "disclosure-ack"

summary
