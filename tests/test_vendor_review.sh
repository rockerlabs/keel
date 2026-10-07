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
# dir #662 A4 (B2): the refusal text names no exemption mechanism — an agent reading it at the moment it is
# blocked must not be handed the way around the gate.
check_absent "vendor-review A4: BLOCKED text never names .secret-scan-allow" "$OUT" "secret-scan-allow"
check_absent "vendor-review A4: ...nor the inline secret-scan:allow marker" "$OUT" "secret-scan:allow"
check_contains "vendor-review A4: ...and still says there is no bypass flag" "$OUT" "no --force"

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

# ======================================================================================================
# dir #662 — vendor-review hardening, orchestrator half. B1 neutral-cwd gate, B2 no exemption mechanism
# named, B5(a)(c) empty bundle / empty reply refused, B6 default --out outside every repo, B7 stdout =
# the round path. Each case below failed against the pre-#662 tool before the fix.
# ======================================================================================================
# vr_split DIR CMD... — run CMD in DIR with stdout and stderr APART (run() merges them); sets V_OUT,
# V_ERR (files' text) and V_ST. The merged OUT of run() hides what B7 is about.
vr_split() {
  local d="$1"; shift
  ( cd "$d" && "$@" ) > "$SANDBOX/v.out" 2> "$SANDBOX/v.err" < /dev/null; V_ST=$?
  V_OUT="$(cat "$SANDBOX/v.out")"; V_ERR="$(cat "$SANDBOX/v.err")"
}
mk_marker_client() {  # mk_marker_client NAME — a client that records it ran, then behaves like the fake one
  local f="$SANDBOX/marker-client-$1.sh"
  printf '#!/usr/bin/env bash\n: > "%s"\nprintf "reply\\n"\n' "$SANDBOX/ran-$1" > "$f"
  chmod +x "$f"
  printf '%s' "$f"
}

# --- A1 (B1): the gate cannot be relaxed from the caller's cwd or the caller repo's root ---------------
# (i) a cwd .secret-scan-allow of "." plus a RELATIVE --bundle; (ii) the same file at the root of a
# scratch git repo, run from a subdirectory of it (a guard today — the scanner reads only ./ — pinning the
# outcome against a future root-anchored lookup).
a1_cl="$(mk_marker_client a1i)"
a1_dir="$SANDBOX/a1-cwd"; mkdir -p "$a1_dir"
printf 'ghp_%s\n' "$(rep a 36)" > "$a1_dir/leaky.md"
printf '.\n' > "$a1_dir/.secret-scan-allow"
printf 'system prompt\n' > "$a1_dir/sys.md"
rm -f "$SANDBOX/ran-a1i"
vr_split "$a1_dir" "$TOOL" --client "$a1_cl" --system sys.md --bundle leaky.md --label a1i --out "$SANDBOX/out-a1i"
check_status "vendor-review A1(i): a cwd .secret-scan-allow of '.' does NOT relax the gate (exit 3)" 3 "$V_ST"
check_nofile "vendor-review A1(i): ...the client is never invoked" "$SANDBOX/ran-a1i"
check_nodir "vendor-review A1(i): ...nothing is written" "$SANDBOX/out-a1i"
# the exit code alone cannot tell a BLOCKED finding from a scanner that failed to run (also exit 3): a
# relative path left unresolved would hand the scanner a file it cannot find from its empty cwd
check_contains "vendor-review A1(i): ...refused because the gate BLOCKED a finding (not because it failed to run)" "$V_ERR" "leak gate BLOCKED"
check_absent "vendor-review A1(i): ...and the gate did run (relative --bundle/--system were resolved before the cd)" "$V_ERR" "failed to run"
# the clean counterpart: the same relative arguments, no secret → the round runs
printf 'clean text\n' > "$a1_dir/clean.md"
vr_split "$a1_dir" "$TOOL" --client "$client" --system sys.md --bundle clean.md --label a1c --out "$SANDBOX/out-a1c"
check_status "vendor-review A1: a clean bundle given by RELATIVE path runs (exit 0)" 0 "$V_ST"

a1_repo="$(new_repo)"; mkdir -p "$a1_repo/sub"
printf '.\n' > "$a1_repo/.secret-scan-allow"
printf 'ghp_%s\n' "$(rep a 36)" > "$a1_repo/sub/leaky.md"
printf 'system prompt\n' > "$a1_repo/sub/sys.md"
a1_cl2="$(mk_marker_client a1ii)"; rm -f "$SANDBOX/ran-a1ii"
vr_split "$a1_repo/sub" "$TOOL" --client "$a1_cl2" --system sys.md --bundle leaky.md --label a1ii --out "$SANDBOX/out-a1ii"
check_status "vendor-review A1(ii): the caller repo's ROOT .secret-scan-allow does not relax the gate (exit 3)" 3 "$V_ST"
check_nofile "vendor-review A1(ii): ...the client is never invoked" "$SANDBOX/ran-a1ii"
check_nodir "vendor-review A1(ii): ...nothing is written" "$SANDBOX/out-a1ii"
check_contains "vendor-review A1(ii): ...refused because the gate BLOCKED a finding" "$V_ERR" "leak gate BLOCKED"
check_contains "vendor-review A1: the BLOCKED text names the path the caller passed (relative), not the resolved one" "$V_ERR" "leaky.md"

# --- A1b (0.14.0 delta audit S7-5): a RELATIVE path-valued scanner env var resolves against the CALLER's cwd -
# The scanner runs from the empty gate dir, so a relative SECRET_SCAN_PERSONAL_FILE (or a relative HOME that its
# default personal-file path hangs off) used to read "file not found" = "no personal literals" and the bundle
# scanned CLEAN — a fail-open in a documented no-bypass gate. Neutral stand-in literal; the bundle is otherwise
# innocuous so only the personal-literals class can fire.
a1b_dir="$SANDBOX/a1b-cwd"; mkdir -p "$a1b_dir/home/.claude"
printf 'zzq-personal-literal\n' > "$a1b_dir/pers"
cp "$a1b_dir/pers" "$a1b_dir/home/.claude/secret-scan-personal"
printf 'notes mentioning zzq-personal-literal here\n' > "$a1b_dir/leaky.md"
printf 'plain text\n' > "$a1b_dir/clean.md"
printf 'system prompt\n' > "$a1b_dir/sys.md"
a1b_case() {  # a1b_case NAME EXPECTED_STATUS BUNDLE ENV... — run from a1b_cwd with the given env; client must run iff status 0
  local n="$1" want="$2" b="$3"; shift 3
  rm -f "$SANDBOX/ran-a1b$n"
  vr_split "$a1b_dir" env "$@" "$TOOL" --client "$(mk_marker_client "a1b$n")" --system sys.md --bundle "$b" --label "a1b$n" --out "$SANDBOX/out-a1b$n"
  check_status "vendor-review A1b ($n): exit status" "$want" "$V_ST"
  if [ "$want" = 0 ]; then
    check_file "vendor-review A1b ($n): ...the client ran" "$SANDBOX/ran-a1b$n"
  else
    check_nofile "vendor-review A1b ($n): ...the client is never invoked" "$SANDBOX/ran-a1b$n"
    check_nodir "vendor-review A1b ($n): ...nothing is written" "$SANDBOX/out-a1b$n"
    check_contains "vendor-review A1b ($n): ...refused because the gate BLOCKED a finding (not because it failed to run)" "$V_ERR" "leak gate BLOCKED"
  fi
}
a1b_case rel-personal 3 leaky.md SECRET_SCAN_PERSONAL_FILE=./pers
a1b_case rel-personal-bare 3 leaky.md SECRET_SCAN_PERSONAL_FILE=pers
a1b_case abs-personal 3 leaky.md "SECRET_SCAN_PERSONAL_FILE=$a1b_dir/pers"
a1b_case rel-home-default 3 leaky.md HOME=home SECRET_SCAN_PERSONAL_FILE=
a1b_case rel-personal-clean 0 clean.md SECRET_SCAN_PERSONAL_FILE=./pers
a1b_case empty-personal-default 0 clean.md "HOME=$a1b_dir/home-none" SECRET_SCAN_PERSONAL_FILE=
# the same class, the side-effect path: a relative KEEL_IMPACT_LOG lands in the CALLER's cwd, not the removed gate dir
rm -f "$a1b_dir/impact.log"
a1b_case rel-impact-log 3 leaky.md SECRET_SCAN_PERSONAL_FILE=./pers KEEL_IMPACT_LOG=impact.log
check_file "vendor-review A1b: a relative KEEL_IMPACT_LOG is written against the caller's cwd (the guard event survives the gate dir)" "$a1b_dir/impact.log"

pin "vendor-review A1b: docs/vendor-review.md rail 1 says a relative scanner env path resolves against the caller's cwd" \
  "$REPO_ROOT/docs/vendor-review.md" 'is resolved against' \
  "rail 1 promises no working-directory bypass; the S7-5 fix's resolution rule must be stated there"
pin "vendor-review A1b: tools/lib/leak-gate.sh's header says a LEAK_GATE_CWD caller owns absolutizing path-valued scanner env" \
  "$REPO_ROOT/tools/lib/leak-gate.sh" 'owns absolutizing them' \
  "the header contract must name the caller's duty, not only SCAN_SCRIPT and FILE"

# --- A2 (B1): the scanner's cwd is a fresh empty dir under TMPDIR, removed on every exit path ---------
# A copy of tools/ whose scanner is a fake that records pwd -P and how many entries its cwd holds.
fx2="$SANDBOX/gate-cwd-fx"; rm -rf "$fx2"; mkdir -p "$fx2"; cp -R "$REPO_ROOT/tools" "$fx2/tools"
fx2_tool="$fx2/tools/vendor-review.sh"; fx2_scan="$fx2/tools/secret-guard/secret-scan.sh"
a2_rec="$SANDBOX/a2-rec"
set_fake_scanner() {  # set_fake_scanner MODE — MODE 0 clean, 1 BLOCKED (names the bundle), 2 failed to run
  { printf '#!/bin/sh\n{ pwd -P; ls -A | wc -l | tr -d " "; } > "%s"\n' "$a2_rec"
    case "$1" in
      1) printf 'echo "secret-scan: BLOCKED" >&2\nfor a in "$@"; do last="$a"; done\necho "  $last:1:x" >&2\n' ;;
      2) printf 'echo "scanner exploded" >&2\n' ;;
    esac
    printf 'exit %s\n' "$1"; } > "$fx2_scan"
  chmod +x "$fx2_scan"
}
tmp_a2="$SANDBOX/tmp-a2"; mkdir -p "$tmp_a2"; tmp_a2_p="$(cd "$tmp_a2" && pwd -P)"
decoy="$SANDBOX/a2-decoy"; mkdir -p "$decoy"; printf 'x\n' > "$decoy/occupant"
a2_case() {  # a2_case LABEL MODE CLIENT EXPECTED_STATUS
  rm -f "$a2_rec"; set_fake_scanner "$2"
  vr_split "$SANDBOX" env TMPDIR="$tmp_a2" LEAK_GATE_CWD="$decoy" "$fx2_tool" --client "$3" --system "$system" --bundle "$bundle" --label a2 --out "$SANDBOX/out-a2-$1"
  check_status "vendor-review A2 ($1): exit status" "$4" "$V_ST"
  local c; c="$(sed -n 1p "$a2_rec" 2>/dev/null)"
  case "$c" in "$tmp_a2_p"/vendor-review.*) pass "vendor-review A2 ($1): the scanner's cwd is a fresh vendor-review.* dir under TMPDIR (an inherited LEAK_GATE_CWD is ignored)" ;; *) fail "vendor-review A2 ($1): the scanner's cwd is a fresh vendor-review.* dir under TMPDIR" "recorded '$c', want $tmp_a2_p/vendor-review.*" ;; esac
  check_eq "vendor-review A2 ($1): ...and it held no entries" "0" "$(sed -n 2p "$a2_rec" 2>/dev/null)"
  check_eq "vendor-review A2 ($1): ...and TMPDIR holds no vendor-review.* entry after the run" "0" "$(find "$tmp_a2" -maxdepth 1 -name 'vendor-review.*' | wc -l | tr -d ' ')"
}
a2_case clean 0 "$client" 0
a2_case blocked 1 "$client" 3
a2_case scanner-failure 2 "$client" 3
a2_case client-failure 0 "$failing" 7
rm -f "$SANDBOX/ran-a2"; a2_mk="$(mk_marker_client a2)"
set_fake_scanner 0
vr_split "$SANDBOX" env TMPDIR=/nonexistent "$fx2_tool" --client "$a2_mk" --system "$system" --bundle "$bundle" --label a2 --out "$SANDBOX/out-a2-notmp"
check_status "vendor-review A2: TMPDIR=/nonexistent (no neutral dir can be made) → exit 3" 3 "$V_ST"
check_nofile "vendor-review A2: ...the client is never invoked" "$SANDBOX/ran-a2"
check_nodir "vendor-review A2: ...nothing is written" "$SANDBOX/out-a2-notmp"

# A2 (exit paths): the NAMED handler, not the explicit rm after a normal gate, is what removes the dir when the
# run dies MID-gate. The fake scanner SIGTERMs the orchestrator (pid handed over through a file) and exits; bash
# runs its TERM trap once the scanner returns → exit 143 through the EXIT handler. (SIGINT cannot be driven here:
# a background job starts with SIGINT ignored, and an ignored-on-entry signal cannot be trapped. SIGKILL has no
# handler by design — the Cases table's "unhandled on purpose" row.)
pid_a2="$SANDBOX/a2-main-pid"; rm -f "$pid_a2"
printf '#!/bin/sh\nfor i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do [ -s "%s" ] && break; sleep 0.2; done\nkill -TERM "$(cat "%s")"\nexit 0\n' "$pid_a2" "$pid_a2" > "$fx2_scan"
chmod +x "$fx2_scan"
rm -f "$SANDBOX/ran-a2"
env TMPDIR="$tmp_a2" "$fx2_tool" --client "$a2_mk" --system "$system" --bundle "$bundle" --label a2term --out "$SANDBOX/out-a2-term" \
  > "$SANDBOX/a2term.out" 2> "$SANDBOX/a2term.err" < /dev/null &
a2_pid=$!
printf '%s' "$a2_pid" > "$pid_a2"
wait "$a2_pid"; a2_st=$?
check_status "vendor-review A2: SIGTERM mid-gate → exit 143" 143 "$a2_st"
check_eq "vendor-review A2: ...and the handler removed the neutral dir" "0" "$(find "$tmp_a2" -maxdepth 1 -name 'vendor-review.*' | wc -l | tr -d ' ')"
check_nofile "vendor-review A2: ...and the client never ran" "$SANDBOX/ran-a2"
check_eq "vendor-review A2: ...and stdout stayed empty" "" "$(cat "$SANDBOX/a2term.out")"

# --- A8 (B5): no round on an empty bundle or an empty reply ------------------------------------------
: > "$SANDBOX/bundle-empty.md"; printf ' \n\t\n' > "$SANDBOX/bundle-ws.md"
a8_cl="$(mk_marker_client a8)"
for b in bundle-empty.md bundle-ws.md; do
  rm -f "$SANDBOX/ran-a8"
  run "$TOOL" --client "$a8_cl" --system "$system" --bundle "$SANDBOX/$b" --label a8 --out "$SANDBOX/out-a8-$b"
  check_status "vendor-review A8: an empty/whitespace-only bundle ($b) → exit 2" 2 "$STATUS"
  check_nofile "vendor-review A8: ...the client is never invoked ($b)" "$SANDBOX/ran-a8"
  check_nodir "vendor-review A8: ...nothing is written ($b)" "$SANDBOX/out-a8-$b"
done
mk_empty_reply_client() {  # mk_empty_reply_client NAME PRINTF-ARG
  local f="$SANDBOX/empty-reply-$1.sh"
  printf '#!/usr/bin/env bash\nprintf %s\n' "$2" > "$f"; chmod +x "$f"
  printf '%s' "$f"
}
for kind in "empty:''" "whitespace:'  \\n \\t\\n'"; do
  name="${kind%%:*}"; arg="${kind#*:}"
  er="$(mk_empty_reply_client "$name" "$arg")"
  run "$TOOL" --client "$er" --system "$system" --bundle "$bundle" --label a8r --out "$SANDBOX/out-a8r-$name"
  check_status "vendor-review A8: a client exiting 0 with a $name reply → exit 1" 1 "$STATUS"
  check_contains "vendor-review A8: ...the message says 'empty reply'" "$OUT" "empty reply"
  check_contains "vendor-review A8: ...and names the client" "$OUT" "$(basename "$er")"
  check_dir "vendor-review A8: ...the round dir is kept for post-mortem ($name)" "$(find "$SANDBOX/out-a8r-$name" -maxdepth 1 -name 'round-*-a8r' -type d | head -1)"
done

# --- A9 (B6): the default --out is outside every repo; an explicit --out never needs HOME --------------
a9_repo="$(new_repo)"
vr_split "$a9_repo" "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label a9
check_status "vendor-review A9: no --out, run from a scratch repo → exit 0" 0 "$V_ST"
case "$V_OUT" in "$HOME/.keel/vendor-review/round-"*-a9) pass "vendor-review A9: the round dir is under \$HOME/.keel/vendor-review/" ;; *) fail "vendor-review A9: the round dir is under \$HOME/.keel/vendor-review/" "stdout was '$V_OUT'" ;; esac
check_eq "vendor-review A9: ...and the caller repo stays clean (git status --porcelain empty)" "" "$(git -C "$a9_repo" status --porcelain)"
pin "vendor-review A9: state-root.sh's names list carries vendor-review" \
  "$REPO_ROOT/tools/lib/state-root.sh" '#              vendor-review' "expected the in-use names list to name the new store"
run env HOME= "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label a9
check_status "vendor-review A9: HOME empty and no --out → exit 2" 2 "$STATUS"
check_contains "vendor-review A9: ...the message names --out" "$OUT" "--out"
: > "$SANDBOX/empty-personal"
run env HOME= SECRET_SCAN_PERSONAL_FILE="$SANDBOX/empty-personal" "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label a9h --out "$SANDBOX/out-a9-nohome"
check_status "vendor-review A9: HOME empty with an explicit --out → runs, exit 0" 0 "$STATUS"
a9_home="$SANDBOX/a9-home"; mkdir -p "$a9_home/.keel"; printf 'not a dir\n' > "$a9_home/.keel/vendor-review"
a9_cl="$(mk_marker_client a9)"; rm -f "$SANDBOX/ran-a9"
run env HOME="$a9_home" "$TOOL" --client "$a9_cl" --system "$system" --bundle "$bundle" --label a9f
check_status "vendor-review A9: \$HOME/.keel/vendor-review is a regular file → exit 3 (refuse)" 3 "$STATUS"
check_nofile "vendor-review A9: ...the client is never invoked" "$SANDBOX/ran-a9"

# --- A10 (B7): stdout is exactly the round path; the status sentence is stderr's ---------------------
vr_split "$SANDBOX" "$TOOL" --client "$client" --system "$system" --bundle "$bundle" --label a10 --out "$SANDBOX/out-a10"
check_status "vendor-review A10: clean run exits 0" 0 "$V_ST"
check_eq "vendor-review A10: stdout is exactly one line" "1" "$(printf '%s\n' "$V_OUT" | wc -l | tr -d ' ')"
check_dir "vendor-review A10: ...and that line is a directory that exists" "$V_OUT"
case "$V_OUT" in *-a10) pass "vendor-review A10: ...ending in -<label>" ;; *) fail "vendor-review A10: ...ending in -<label>" "stdout was '$V_OUT'" ;; esac
check_contains "vendor-review A10: stderr carries the leak-gate status sentence" "$V_ERR" "leak gate clean"
vr_split "$SANDBOX" "$TOOL" --client "$failing" --system "$system" --bundle "$bundle" --label a10f --out "$SANDBOX/out-a10f"
check_eq "vendor-review A10: on a client failure stdout is empty" "" "$V_OUT"

run "$TOOL" -h
check_status "vendor-review: --help exits 0" 0 "$STATUS"
check_contains "vendor-review: --help documents the --client contract" "$OUT" "read the user message on stdin"

summary
