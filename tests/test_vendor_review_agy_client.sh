#!/usr/bin/env bash
# Tests for tools/vendor-review/agy.sh — dir #614, filed after a code-review pass found this client
# had ZERO direct test coverage: tests/test_vendor_review.sh only ever exercises a fake stand-in
# client, so a real bug in agy.sh itself (an exit-code-capture inversion that shipped and was only
# caught by a live smoke test, not by any automated test) had nothing to catch a regression of it.
# A fake `agy` CLI stands in via $AGY_BIN — no real Antigravity install or auth needed.
#
# agy.sh reads its user message from STDIN, and tests/lib.sh's run() always redirects stdin from
# /dev/null (by design, so no test can hang on an unfed read) — so every call here that needs to feed
# stdin builds its own two-line OUT/STATUS capture instead of using run(), the same idiom
# test_keel_check_gate.sh uses for the same reason (see run()'s own comment in lib.sh).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

CLIENT="$REPO_ROOT/tools/vendor-review/agy.sh"
check_file "vendor-review/agy.sh exists" "$CLIENT"

system="$SANDBOX/system.md"
printf 'system prompt\n' > "$system"

# mk_agy — writes a fake `agy` CLI from its own stdin (a quoted heredoc, so the caller's body is
# never touched by shell expansion), returns its path. A quoted heredoc is load-bearing here: a
# response value carrying '\n' must survive as the literal two characters (a valid JSON escape) —
# any shell-level backslash processing between the caller and the file would turn it into a real
# newline byte instead, producing invalid JSON no earlier revision of this file caught (it silently
# broke jq parsing, which read as "exits 1" — the right-looking exit code for the wrong reason).
mk_agy() {
  local f="$SANDBOX/agy-$$-$RANDOM"
  { printf '#!/usr/bin/env bash\n'; cat; } > "$f"
  chmod +x "$f"
  printf '%s' "$f"
}

# --- success: prints the reply, writes raw.json --------------------------------------------------
agy_ok="$(mk_agy <<'SCRIPT'
printf '%s' '{"status":"SUCCESS","response":"hello from agy"}'
SCRIPT
)"
raw1="$SANDBOX/raw1.json"
OUT="$(AGY_BIN="$agy_ok" "$CLIENT" --system "$system" --raw-out "$raw1" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: success exits 0" 0 "$STATUS"
check_contains "agy.sh: success prints the reply on stdout" "$OUT" "hello from agy"
check_file "agy.sh: success writes raw.json" "$raw1"
check_contains "agy.sh: raw.json holds the real response" "$(cat "$raw1" 2>/dev/null)" "hello from agy"

# --- multi-line replies keep their real newlines (not escaped, not collapsed) ----------------------
agy_multiline="$(mk_agy <<'SCRIPT'
printf '%s' '{"status":"SUCCESS","response":"line1\nline2\nline3"}'
SCRIPT
)"
raw_ml="$SANDBOX/raw-ml.json"
OUT="$(AGY_BIN="$agy_multiline" "$CLIENT" --system "$system" --raw-out "$raw_ml" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: multi-line reply exits 0" 0 "$STATUS"
out_lines="$(printf '%s' "$OUT" | wc -l | tr -d ' ')"
check_eq "agy.sh: a 3-line reply prints as 3 real lines, not one escaped line" "2" "$out_lines"

# --- a failing CLI: the real exit code is reported, never 0 (the bug this file exists to pin) -------
agy_fail="$(mk_agy <<'SCRIPT'
echo "boom stderr" >&2
exit 5
SCRIPT
)"
raw2="$SANDBOX/raw2.json"
OUT="$(AGY_BIN="$agy_fail" "$CLIENT" --system "$system" --raw-out "$raw2" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: a failing CLI call exits non-zero" 1 "$STATUS"
check_contains "agy.sh: names the CLI's REAL exit code, not 0" "$OUT" "exit 5"
check_contains "agy.sh: surfaces the CLI's own stderr" "$OUT" "boom stderr"

# --- a non-SUCCESS status fails loudly, never a silent empty verdict --------------------------------
agy_denied="$(mk_agy <<'SCRIPT'
printf '%s' '{"status":"DENIED","response":""}'
SCRIPT
)"
OUT="$(AGY_BIN="$agy_denied" "$CLIENT" --system "$system" --raw-out "$SANDBOX/raw3.json" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: non-SUCCESS status exits non-zero" 1 "$STATUS"
check_contains "agy.sh: names the non-SUCCESS status" "$OUT" "DENIED"

# --- a blank reply (whitespace-only, not just empty-string) is treated as a failure, not printed ----
agy_blank="$(mk_agy <<'SCRIPT'
printf '%s' '{"status":"SUCCESS","response":"   \n  "}'
SCRIPT
)"
OUT="$(AGY_BIN="$agy_blank" "$CLIENT" --system "$system" --raw-out "$SANDBOX/raw4.json" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: a whitespace-only reply exits non-zero" 1 "$STATUS"
check_contains "agy.sh: names it a blank .response" "$OUT" "blank .response"

agy_empty="$(mk_agy <<'SCRIPT'
printf '%s' '{"status":"SUCCESS","response":""}'
SCRIPT
)"
OUT="$(AGY_BIN="$agy_empty" "$CLIENT" --system "$system" --raw-out "$SANDBOX/raw5.json" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: a truly empty reply exits non-zero too" 1 "$STATUS"

# --- oversize hard stop: refuses BEFORE ever invoking the CLI ---------------------------------------
big="$SANDBOX/big.txt"
head -c 200000 /dev/zero | tr '\0' 'x' > "$big"
agy_should_not_run="$(mk_agy <<'SCRIPT'
echo "AGY WAS INVOKED" >&2
printf '%s' '{"status":"SUCCESS","response":"x"}'
SCRIPT
)"
OUT="$(AGY_BIN="$agy_should_not_run" "$CLIENT" --system "$system" --raw-out "$SANDBOX/raw6.json" 2>&1 < "$big")"; STATUS=$?
check_status "agy.sh: an oversize combined prompt exits 2 (hard stop)" 2 "$STATUS"
check_contains "agy.sh: names the hard-stop cap" "$OUT" "HARD STOP"
check_absent "agy.sh: the CLI is never invoked past the size cap" "$OUT" "AGY WAS INVOKED"

# --- missing/non-executable AGY_BIN is refused with an install hint --------------------------------
OUT="$(AGY_BIN="$SANDBOX/does-not-exist" "$CLIENT" --system "$system" --raw-out "$SANDBOX/raw7.json" 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh: a missing AGY_BIN exits non-zero" 1 "$STATUS"
check_contains "agy.sh: names the install command" "$OUT" "antigravity.google"

# --- --help (no stdin needed) ------------------------------------------------------------------------
run "$CLIENT" -h
check_status "agy.sh: --help exits 0" 0 "$STATUS"
check_contains "agy.sh: --help documents AGY_MODEL" "$OUT" "AGY_MODEL"

summary
