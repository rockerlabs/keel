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

# ======================================================================================================
# dir #662 — vendor-review hardening, agy.sh half (B3 platform cap, B4 denial, B5(b) empty stdin,
# B8 neutral cwd, B9 settings allow-rules). No real agy: every case is a fake CLI. Unlike the cases
# above, these need stdout and stderr APART (a forwarded stderr line is part of the contract), so
# a_run keeps them in two files.
# ======================================================================================================
a_run() {  # a_run STDIN_FILE CMD... — sets A_ST, A_OUT (stdout), A_ERR (stderr)
  local in="$1"; shift
  "$@" < "$in" > "$SANDBOX/a.out" 2> "$SANDBOX/a.err"; A_ST=$?
  A_OUT="$(cat "$SANDBOX/a.out")"; A_ERR="$(cat "$SANDBOX/a.err")"
}
in_hi="$SANDBOX/in-hi"; printf 'hi' > "$in_hi"

# --- B3: the cap fits the platform's per-argument limit (Linux: 131071) -----------------------------
# A fake agy records the byte count of its -p argument; a `uname` shim chooses the platform so the
# result does not depend on the host running the suite.
agy_count="$(mk_agy <<'SCRIPT'
printf '%s' "$2" | wc -c | tr -d ' ' > "${AGY_COUNT:?}"
printf '%s' '{"status":"SUCCESS","response":"ok"}'
SCRIPT
)"
uname_linux="$SANDBOX/uname-linux"; mkdir -p "$uname_linux"
printf '#!/bin/sh\necho Linux\n' > "$uname_linux/uname"; chmod +x "$uname_linux/uname"
uname_darwin="$SANDBOX/uname-darwin"; mkdir -p "$uname_darwin"
printf '#!/bin/sh\necho Darwin\n' > "$uname_darwin/uname"; chmod +x "$uname_darwin/uname"
cnt="$SANDBOX/agy-count"
# overhead: the combined prompt's bytes beyond the user text (system prompt + the fixed no-tools block)
printf 'x' > "$SANDBOX/in-x"
rm -f "$cnt"; a_run "$SANDBOX/in-x" env AGY_COUNT="$cnt" AGY_BIN="$agy_count" "$CLIENT" --system "$system"
overhead=$(( $(cat "$cnt" 2>/dev/null || echo 0) - 1 ))
mk_user_of() {  # mk_user_of TOTAL FILE — a user message making the combined prompt exactly TOTAL bytes
  head -c $(( $1 - overhead )) /dev/zero | tr '\0' 'x' > "$2"
}
mk_user_of 131071 "$SANDBOX/in-131071"; mk_user_of 131072 "$SANDBOX/in-131072"; mk_user_of 150000 "$SANDBOX/in-150000"

rm -f "$cnt"
a_run "$SANDBOX/in-131071" env PATH="$uname_linux:$PATH" AGY_COUNT="$cnt" AGY_BIN="$agy_count" "$CLIENT" --system "$system"
check_status "agy.sh B3: Linux, combined 131071 bytes → invoked, exit 0" 0 "$A_ST"
check_eq "agy.sh B3: Linux, 131071 → agy received exactly 131071 bytes" "131071" "$(cat "$cnt" 2>/dev/null)"
rm -f "$cnt"
a_run "$SANDBOX/in-131072" env PATH="$uname_linux:$PATH" AGY_COUNT="$cnt" AGY_BIN="$agy_count" "$CLIENT" --system "$system"
check_status "agy.sh B3: Linux, combined 131072 bytes → exit 2 (over the per-argument cap)" 2 "$A_ST"
check_nofile "agy.sh B3: Linux, 131072 → agy is never invoked" "$cnt"
check_contains "agy.sh B3: the refusal keeps the HARD STOP wording" "$A_ERR" "HARD STOP"
check_contains "agy.sh B3: ...names the Linux cap" "$A_ERR" "131071"
check_contains "agy.sh B3: ...names the platform" "$A_ERR" "Linux"
check_contains "agy.sh B3: ...and says to chunk the bundle" "$A_ERR" "hunk the bundle"
# non-Linux keeps the 185 KiB (189440-byte) cap: refusal above it works on every host; the "a 150000-byte prompt
# runs" half needs a kernel that really accepts a 150000-byte argument, so a real-Linux host (a `uname` shim
# cannot change the kernel's own limit) skips it.
mk_user_of 189441 "$SANDBOX/in-189441"
rm -f "$cnt"
a_run "$SANDBOX/in-189441" env PATH="$uname_darwin:$PATH" AGY_COUNT="$cnt" AGY_BIN="$agy_count" "$CLIENT" --system "$system"
check_status "agy.sh B3: non-Linux, combined 189441 bytes → exit 2 (over the 185 KiB cap)" 2 "$A_ST"
check_contains "agy.sh B3: ...the refusal names the 189440-byte cap" "$A_ERR" "189440"
check_nofile "agy.sh B3: ...agy is never invoked" "$cnt"
if [ "$(uname -s)" != Linux ]; then
  rm -f "$cnt"
  a_run "$SANDBOX/in-150000" env PATH="$uname_darwin:$PATH" AGY_COUNT="$cnt" AGY_BIN="$agy_count" "$CLIENT" --system "$system"
  check_status "agy.sh B3: non-Linux keeps the 185 KiB cap (a 150000-byte prompt runs)" 0 "$A_ST"
  check_eq "agy.sh B3: ...agy received all 150000 bytes" "150000" "$(cat "$cnt" 2>/dev/null)"
fi
if [ "$(uname -s)" = Linux ]; then
  # the real-Linux leg (CI alpine): the per-argument limit is the kernel's own, not a shim's claim
  rm -f "$cnt"
  a_run "$SANDBOX/in-131071" env AGY_COUNT="$cnt" AGY_BIN="$agy_count" "$CLIENT" --system "$system"
  check_status "agy.sh B3 (real Linux): a 131071-byte combined prompt reaches agy, exit 0" 0 "$A_ST"
fi

# --- B3: an E2BIG from the exec (a platform with a smaller limit) is named, never "agy CLI call failed" ----
agy_e2big="$(mk_agy <<'SCRIPT'
echo "bash: line 1: /x/agy: Argument list too long" >&2
exit 126
SCRIPT
)"
a_run "$in_hi" env AGY_BIN="$agy_e2big" "$CLIENT" --system "$system"
check_status "agy.sh B3: exit 126 + 'Argument list too long' → exit 2" 2 "$A_ST"
check_contains "agy.sh B3: ...the message names the per-argument size limit" "$A_ERR" "per-argument"
check_contains "agy.sh B3: ...and says to chunk the bundle" "$A_ERR" "hunk the bundle"
check_absent "agy.sh B3: ...and never reports it as a plain agy CLI failure" "$A_ERR" "agy CLI call failed"

# --- B4: a denied tool call is a failure even when a reply came back ---------------------------------
agy_deny_reply="$(mk_agy <<'SCRIPT'
echo 'jetski: no output produced — a tool required the "read_file" permission' >&2
printf '%s' '{"status":"SUCCESS","response":"Based on what I could see, the verdict is clean."}'
SCRIPT
)"
a_run "$in_hi" env AGY_BIN="$agy_deny_reply" "$CLIENT" --system "$system"
check_status "agy.sh B4: a denial notice + a non-blank reply → exit 1" 1 "$A_ST"
check_eq "agy.sh B4: ...nothing on stdout" "" "$A_OUT"
check_contains "agy.sh B4: ...agy's denial line is forwarded on stderr" "$A_ERR" 'required the "read_file" permission'
check_contains "agy.sh B4: ...and the message says a tool call was denied" "$A_ERR" "denied"

agy_warn_reply="$(mk_agy <<'SCRIPT'
echo 'warning: quota at 80%' >&2
printf '%s' '{"status":"SUCCESS","response":"Based on what I could see, the verdict is clean."}'
SCRIPT
)"
a_run "$in_hi" env AGY_BIN="$agy_warn_reply" "$CLIENT" --system "$system"
check_status "agy.sh B4: other stderr + a reply → exit 0" 0 "$A_ST"
check_contains "agy.sh B4: ...the reply is on stdout" "$A_OUT" "verdict is clean"
check_contains "agy.sh B4: ...and the stderr line is forwarded, no longer dropped" "$A_ERR" "quota at 80%"

agy_unquoted="$(mk_agy <<'SCRIPT'
echo 'a tool required the read_file permission' >&2
printf '%s' '{"status":"SUCCESS","response":"Based on what I could see, the verdict is clean."}'
SCRIPT
)"
a_run "$in_hi" env AGY_BIN="$agy_unquoted" "$CLIENT" --system "$system"
check_status "agy.sh B4 (changed format, no quoted tool name): not matched → exit 0 (fail-visible, pinned)" 0 "$A_ST"
check_contains "agy.sh B4: ...the reply is on stdout" "$A_OUT" "verdict is clean"
check_contains "agy.sh B4: ...and the line stays visible on stderr" "$A_ERR" "required the read_file permission"

# --- B5(b): no round on empty input ------------------------------------------------------------------
agy_mark="$(mk_agy <<'SCRIPT'
: > "${AGY_MARK:?}"
printf '%s' '{"status":"SUCCESS","response":"x"}'
SCRIPT
)"
mark="$SANDBOX/agy-mark"
rm -f "$mark"; a_run /dev/null env AGY_MARK="$mark" AGY_BIN="$agy_mark" "$CLIENT" --system "$system"
check_status "agy.sh B5: empty stdin → exit 2" 2 "$A_ST"
check_nofile "agy.sh B5: ...agy is never invoked" "$mark"
printf '  \n\t \n' > "$SANDBOX/in-ws"
rm -f "$mark"; a_run "$SANDBOX/in-ws" env AGY_MARK="$mark" AGY_BIN="$agy_mark" "$CLIENT" --system "$system"
check_status "agy.sh B5: whitespace-only stdin → exit 2" 2 "$A_ST"
check_nofile "agy.sh B5: ...agy is never invoked" "$mark"

# --- B8: agy runs from a fresh empty directory, not the caller's tree -------------------------------
agy_rec="$(mk_agy <<'SCRIPT'
{ pwd -P; ls -A | wc -l | tr -d ' '; } > "${AGY_REC:?}"
printf '%s' '{"status":"SUCCESS","response":"ok"}'
SCRIPT
)"
tmp11="$SANDBOX/tmp-b8"; mkdir -p "$tmp11"; tmp11_p="$(cd "$tmp11" && pwd -P)"
rec="$SANDBOX/agy-rec"; rm -f "$rec"
printf 'caller-tree context\n' > "$SANDBOX/AGENTS.md"   # a file agy would load from ITS cwd
a_run "$in_hi" env TMPDIR="$tmp11" AGY_REC="$rec" AGY_BIN="$agy_rec" "$CLIENT" --system "$system"
check_status "agy.sh B8: run with TMPDIR at a sandbox dir → exit 0" 0 "$A_ST"
rec_cwd="$(sed -n 1p "$rec" 2>/dev/null)"
case "$rec_cwd" in "$tmp11_p"/agy.*) pass "agy.sh B8: agy's cwd is a fresh agy.* dir under TMPDIR" ;; *) fail "agy.sh B8: agy's cwd is a fresh agy.* dir under TMPDIR" "recorded '$rec_cwd', want $tmp11_p/agy.*" ;; esac
check_eq "agy.sh B8: ...and it held no entries (so no AGENTS.md/GEMINI.md to load)" "0" "$(sed -n 2p "$rec" 2>/dev/null)"
check_eq "agy.sh B8: ...and it is gone after the run" "0" "$(find "$tmp11" -maxdepth 1 -name 'agy.*' | wc -l | tr -d ' ')"
# a relative AGY_BIN / --system / --raw-out are resolved BEFORE the cd
rm -f "$rec" "$SANDBOX/raw-rel.json"
OUT="$(cd "$SANDBOX" && env TMPDIR="$tmp11" AGY_REC="$rec" AGY_BIN="./$(basename "$agy_rec")" "$CLIENT" --system system.md --raw-out raw-rel.json 2>&1 <<< "hi")"; STATUS=$?
check_status "agy.sh B8: a relative AGY_BIN / --system / --raw-out still works" 0 "$STATUS"
check_file "agy.sh B8: ...--raw-out lands relative to the CALLER, not agy's cwd" "$SANDBOX/raw-rel.json"
rm -f "$mark"
a_run "$in_hi" env TMPDIR=/nonexistent AGY_MARK="$mark" AGY_BIN="$agy_mark" "$CLIENT" --system "$system"
check_status "agy.sh B8: TMPDIR=/nonexistent (no neutral dir) → exit 1" 1 "$A_ST"
check_nofile "agy.sh B8: ...agy is never invoked" "$mark"

# --- B9: no tool access is enforced — any agy allow-rule refuses, an unreadable policy refuses -------
settings_dir="$HOME/.gemini/antigravity-cli"; settings="$settings_dir/settings.json"
mkdir -p "$settings_dir"
set_settings() { rm -f "$settings"; printf '%s' "$1" > "$settings"; }
b9_run() {  # b9_run [extra env...] — a run of the marker agy; sets A_ST/A_ERR, $mark says whether agy ran
  rm -f "$mark"
  a_run "$in_hi" env "$@" AGY_MARK="$mark" AGY_BIN="$agy_mark" "$CLIENT" --system "$system"
}
set_settings '{"permissions":{"allow":["read_file(/x/)"]}}'
b9_run
check_status "agy.sh B9: one allow-rule → exit 1" 1 "$A_ST"
check_nofile "agy.sh B9: ...agy is never invoked" "$mark"
check_contains "agy.sh B9: ...the message names the settings file" "$A_ERR" "settings.json"
check_contains "agy.sh B9: ...and the number of rules" "$A_ERR" "1 permissions.allow rule"
check_absent "agy.sh B9: ...and never the rule itself (rules carry paths)" "$A_ERR" "read_file(/x/)"
check_absent "agy.sh B9: ...and carries no imperative to edit the file" "$A_ERR" "remove the"
for ok_json in '{"permissions":{"allow":[]}}' '{}' '{"permissions":{}}'; do
  set_settings "$ok_json"; b9_run
  check_status "agy.sh B9: $ok_json → proceeds, exit 0" 0 "$A_ST"
  check_file "agy.sh B9: ...agy was invoked" "$mark"
done
rm -f "$settings"; b9_run
check_status "agy.sh B9: no settings file → proceeds, exit 0" 0 "$A_ST"
check_file "agy.sh B9: ...agy was invoked" "$mark"
for bad_json in 'not json' '{"permissions":{"allow":"read_file(/x/)"}}' '{"permissions":"x"}' '[]' ''; do
  set_settings "$bad_json"; b9_run
  check_status "agy.sh B9: unparseable/odd settings ($bad_json) → exit 1 (fail closed)" 1 "$A_ST"
  check_nofile "agy.sh B9: ...agy is never invoked" "$mark"
done
set_settings '{"permissions":{"allow":["read_file(/x/)"]}}'; chmod 000 "$settings"
b9_run
check_status "agy.sh B9: an unreadable one-rule settings file → exit 1" 1 "$A_ST"
check_nofile "agy.sh B9: ...agy is never invoked" "$mark"
if [ "$(id -u 2>/dev/null)" != 0 ]; then   # chmod 000 is a no-op for root (CLAUDE.md Linux-leg trap 2)
  check_contains "agy.sh B9: ...the message says the permissions could not be read" "$A_ERR" "could not be read"
fi
chmod 600 "$settings"
farm_nojq="$SANDBOX/nojq-bin"; path_farm "$farm_nojq" jq
b9_run PATH="$farm_nojq"
check_status "agy.sh B9: jq absent (one-rule file) → exit 1 (fail closed)" 1 "$A_ST"
check_nofile "agy.sh B9: ...agy is never invoked" "$mark"
# the call shape never widens agy's grants
agy_argv="$(mk_agy <<'SCRIPT'
printf '%s\n' "$@" > "${AGY_ARGV:?}"
printf '%s' '{"status":"SUCCESS","response":"ok"}'
SCRIPT
)"
rm -f "$settings"
argv_f="$SANDBOX/agy-argv"
a_run "$in_hi" env AGY_ARGV="$argv_f" AGY_BIN="$agy_argv" "$CLIENT" --system "$system"
check_absent "agy.sh B9: agy's argv never carries --add-dir" "$(cat "$argv_f" 2>/dev/null)" "--add-dir"
check_absent "agy.sh B9: ...nor --dangerously-skip-permissions" "$(cat "$argv_f" 2>/dev/null)" "--dangerously-skip-permissions"
rm -rf "$HOME/.gemini"

# --- --help (no stdin needed) ------------------------------------------------------------------------
run "$CLIENT" -h
check_status "agy.sh: --help exits 0" 0 "$STATUS"
check_contains "agy.sh: --help documents AGY_MODEL" "$OUT" "AGY_MODEL"

summary
