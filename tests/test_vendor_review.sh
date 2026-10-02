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

# --- the leak gate FAILS CLOSED: a scanner that errors, dies, is not executable or is missing refuses ----
# (audit S7-1: both refuse branches could be deleted with this suite still green). The tool resolves its
# scanner relative to its own location, so run a COPY of tools/ whose secret-guard/secret-scan.sh we swap.
# The bundle is CLEAN throughout — the refusal must come from the scanner failing, never from a finding.
fx="$SANDBOX/gate-fail-fx"
rm -rf "$fx"; mkdir -p "$fx"; cp -R "$REPO_ROOT/tools" "$fx/tools"
fx_tool="$fx/tools/vendor-review.sh"
fx_scan="$fx/tools/secret-guard/secret-scan.sh"
fx_n=0
gate_fail_case() {
  # $1 label, $2 expected message fragment
  fx_n=$((fx_n + 1))
  local o="$SANDBOX/out-gatefail-$fx_n" kc="$SANDBOX/gatefail-client-ran-$fx_n"
  printf '#!/usr/bin/env bash\n: > "%s"\nexit 0\n' "$kc" > "$SANDBOX/gatefail-client-$fx_n.sh"
  chmod +x "$SANDBOX/gatefail-client-$fx_n.sh"
  run "$fx_tool" --client "$SANDBOX/gatefail-client-$fx_n.sh" --system "$system" --bundle "$bundle" --label gatefail --out "$o"
  check_status "vendor-review: $1 → exit 3 (refuses)" 3 "$STATUS"
  check_contains "vendor-review: $1 → names the failure" "$OUT" "$2"
  check_nodir "vendor-review: $1 → nothing written" "$o"
  check_nofile "vendor-review: $1 → the client is never invoked" "$kc"
}

printf '#!/bin/sh\necho "scanner exploded" >&2\nexit 2\n' > "$fx_scan"; chmod +x "$fx_scan"
gate_fail_case "a scanner that exits 2 (failed to run)" "leak gate failed to run"
check_contains "vendor-review: …and carries the scanner's own exit status" "$OUT" "exited 2"
check_contains "vendor-review: …and its stderr" "$OUT" "scanner exploded"

printf '#!/bin/sh\nkill -9 $$\n' > "$fx_scan"; chmod +x "$fx_scan"
gate_fail_case "a scanner killed by SIGKILL (137)" "leak gate failed to run"
check_contains "vendor-review: …and carries the 137 status" "$OUT" "exited 137"

chmod 644 "$fx_scan"
gate_fail_case "a non-executable scanner" "missing or not executable"

rm -f "$fx_scan"
gate_fail_case "a missing scanner" "missing or not executable"

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

# --- --label is sanitized: it lands straight in a path, so '/' and '..' must be refused, not escaped ---
run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label "x/../../escaped" --out "$out"
check_status "vendor-review: refuses a --label containing '/'" 2 "$STATUS"
check_contains "vendor-review: names --label as the problem" "$OUT" "--label"
check_nodir "vendor-review: a slash-label never creates anything outside --out" "$SANDBOX/escaped"

run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label "has spaces" --out "$out"
check_status "vendor-review: refuses a --label with a space" 2 "$STATUS"

# a label using only the allowed charset (letters, digits, '_', '-') still works
out5="$SANDBOX/out-label-charset"
run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label "PR-473_v2" --out "$out5"
check_status "vendor-review: a letters/digits/_/- label is accepted" 0 "$STATUS"

# --- round-dir collision: two launches landing on the SAME round dir name refuse the second one -------
# vendor-review.sh names the round dir from `date -u +...` plus --label, at second granularity — a
# real two-process race is not reliably reproducible in a test, so a fake `date` ahead on PATH pins
# both launches to the identical timestamp, making the collision deterministic.
fake_date_dir="$SANDBOX/fake-date-bin"
mkdir -p "$fake_date_dir"
printf '#!/usr/bin/env bash\nprintf "19700101T000000Z"\n' > "$fake_date_dir/date"
chmod +x "$fake_date_dir/date"

out6="$SANDBOX/out-collision"
old_path="$PATH"
PATH="$fake_date_dir:$PATH"
run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label collide --out "$out6"
check_status "vendor-review: first launch at a pinned timestamp succeeds" 0 "$STATUS"
run "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label collide --out "$out6"
PATH="$old_path"
check_status "vendor-review: a second launch at the SAME pinned timestamp+label refuses (exit 3)" 3 "$STATUS"
check_contains "vendor-review: collision message names the round dir" "$OUT" "already exists"
check_contains "vendor-review: collision message names the round dir path itself" "$OUT" "round-19700101T000000Z-collide"
collide_dirs="$(find "$out6" -maxdepth 1 -name 'round-*-collide' -type d | wc -l | tr -d ' ')"
check_eq "vendor-review: exactly one round dir exists after the collision (never a second copy)" \
  "1" "$collide_dirs"

run "$TOOL" -h
check_status "vendor-review: --help exits 0" 0 "$STATUS"
check_contains "vendor-review: --help documents the --client contract" "$OUT" "read the user message on stdin"

summary
