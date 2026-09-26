#!/usr/bin/env bash
# Tests for tools/vendor-review.sh — dir #614: ships the scriptable cross-vendor reading leg as a
# tracked, adopter-usable pair (the orchestrator here, the client contract it dispatches to).
#
# No real vendor CLI is exercised — a fake client script stands in, satisfying the same contract
# (stdin, --system FILE, --raw-out FILE, exit non-zero on failure) that tools/vendor-review/agy.sh
# implements for real. The leak gate gets the most assertions, same emphasis as
# test_audit_packet_export.sh: a planted key-shaped secret must BLOCK (exit 3, nothing written,
# never the matched content) before the client is even invoked.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

TOOL="$REPO_ROOT/tools/vendor-review.sh"
AGY_CLIENT="$REPO_ROOT/tools/vendor-review/agy.sh"
check_file "vendor-review.sh exists" "$TOOL"
check_file "vendor-review/agy.sh exists" "$AGY_CLIENT"

# --- fixture: a fake client satisfying vendor-review.sh's --client contract ------------------------
mk_fake_client() {
  local f="$SANDBOX/fake-client.sh"
  cat > "$f" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
raw_out="" sys_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --system)  sys_file="$2"; shift 2 ;;
    --raw-out) raw_out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
msg="$(cat)"
[ -n "$raw_out" ] && printf '{"status":"SUCCESS","response":"fake reply","usage":{"input_tokens":42,"output_tokens":7}}' > "$raw_out"
printf 'fake reply to: %s (sys=%s)\n' "$msg" "$(basename "$sys_file")"
EOF
  chmod +x "$f"
  printf '%s' "$f"
}

mk_failing_client() {
  local f="$SANDBOX/failing-client.sh"
  printf '#!/usr/bin/env bash\necho "boom" >&2\nexit 7\n' > "$f"
  chmod +x "$f"
  printf '%s' "$f"
}

client="$(mk_fake_client)"
system="$SANDBOX/system.md"
bundle="$SANDBOX/bundle.md"
printf 'system prompt\n' > "$system"
printf 'bundle content\n' > "$bundle"
out="$SANDBOX/out-clean"

# --- basic success: round dir written, reply + raw.json readable ------------------------------------
run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label smoketest --out "$out"
check_status "vendor-review: clean run exits 0" 0 "$STATUS"
check_contains "vendor-review: reports round dir written" "$OUT" "round written to"
check_contains "vendor-review: reports leak gate clean" "$OUT" "leak gate clean"

round="$(find "$out" -maxdepth 1 -name 'round-*-smoketest' -type d | head -1)"
check_dir "vendor-review: round dir exists" "${round:-/nonexistent}"
check_file "vendor-review: reply.md written" "$round/reply.md"
check_file "vendor-review: raw.json written" "$round/raw.json"
check_contains "vendor-review: reply.md carries the client's reply" "$(cat "$round/reply.md" 2>/dev/null)" "fake reply to: bundle content"
check_contains "vendor-review: raw.json carries the client's raw response" "$(cat "$round/raw.json" 2>/dev/null)" '"status":"SUCCESS"'

# --- the leak gate: a key-shaped secret BLOCKS, path-only, never the matched content ----------------
bundle_secret="$SANDBOX/bundle-secret.md"
printf 'ghp_%s\n' "$(rep a 36)" > "$bundle_secret"
out2="$SANDBOX/out-secret"
run "$TOOL" --client "$client" --system "$system" --bundle "$bundle_secret" --label secrettest --out "$out2"
check_status "vendor-review: BLOCKS on a planted key-shaped secret" 3 "$STATUS"
check_contains "vendor-review: BLOCKED message names the offending path" "$OUT" "bundle-secret.md"
check_absent "vendor-review: BLOCKED message never repeats the secret's own text" "$OUT" "$(rep a 36)"
check_nodir "vendor-review: nothing written when the gate blocks" "$out2"

# --- the leak gate runs BEFORE the client — a client that would blow up never gets invoked ----------
failing="$(mk_failing_client)"
out3="$SANDBOX/out-secret-vs-failing"
run "$TOOL" --client "$failing" --system "$system" --bundle "$bundle_secret" --label gateorder --out "$out3"
check_status "vendor-review: gate blocks before a failing client ever runs" 3 "$STATUS"
check_absent "vendor-review: the failing client's own stderr never appears (never invoked)" "$OUT" "boom"

# --- a client that fails propagates its exit code, and the round dir stays for post-mortem ----------
out4="$SANDBOX/out-client-fail"
run "$TOOL" --client "$failing" --system "$system" --bundle "$bundle" --label clientfail --out "$out4"
check_status "vendor-review: propagates the client's own exit code" 7 "$STATUS"
check_contains "vendor-review: names the failing client and its exit code" "$OUT" "exit 7"
round4="$(find "$out4" -maxdepth 1 -name 'round-*-clientfail' -type d | head -1)"
check_dir "vendor-review: round dir kept on client failure (post-mortem)" "${round4:-/nonexistent}"

# --- argument validation: every required flag is checked, with --help named as the way out ----------
run "$TOOL" --system "$system" --bundle "$bundle" --label x --out "$out"
check_status "vendor-review: refuses with no --client" 2 "$STATUS"
check_contains "vendor-review: names --client as missing" "$OUT" "--client"

run "$TOOL" --client "$client" --bundle "$bundle" --label x --out "$out"
check_status "vendor-review: refuses with no --system" 2 "$STATUS"

run "$TOOL" --client "$client" --system "$system" --label x --out "$out"
check_status "vendor-review: refuses with no --bundle" 2 "$STATUS"

run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --out "$out"
check_status "vendor-review: refuses with no --label" 2 "$STATUS"

run "$TOOL" --client "$SANDBOX/does-not-exist.sh" --system "$system" --bundle "$bundle" --label x --out "$out"
check_status "vendor-review: refuses a --client that isn't executable" 2 "$STATUS"

run "$TOOL" --client "$client" --system "$SANDBOX/no-such-system.md" --bundle "$bundle" --label x --out "$out"
check_status "vendor-review: refuses a --system file that doesn't exist" 2 "$STATUS"

run "$TOOL" -h
check_status "vendor-review: --help exits 0" 0 "$STATUS"
check_contains "vendor-review: --help documents the --client contract" "$OUT" "read the user message on stdin"

summary
