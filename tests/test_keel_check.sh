#!/usr/bin/env bash
# Tests for tools/keel-check.sh — the stop-mode floor (backlog dir #33, tier T1a). We pin the machinery,
# not judgment: a pass exits 0 and resets the streak; the first failure warns but doesn't stop; the N-th
# consecutive failure of the SAME check fires the STOP banner; a pass between failures resets the streak;
# the threshold is tunable; two different checks keep independent counters; the check's own exit code
# passes through; and a STOP appends exactly one zero-token friction event when KEEL_IMPACT_LOG is set.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/keel-check.sh"
check_file "keel-check.sh exists" "$TOOL"

# Each scenario gets a fresh state dir so counters never leak between scenarios.
fresh_sd() { export KEEL_CHECK_STATE_DIR; KEEL_CHECK_STATE_DIR="$(mktemp -d "$SANDBOX/kc.XXXXXX")"; }

# --- a green check exits 0, announces PASS, and leaves no counter ---------------------------------
fresh_sd
run "$TOOL" "true"
check_status "green check passes through exit 0" 0 "$STATUS"
check_contains "green check announces PASS" "$OUT" "PASS"
check_absent "green check never shows the STOP banner" "$OUT" "keel-check: STOP"

# --- the first failure warns but does NOT stop ---------------------------------------------------
fresh_sd
run "$TOOL" "false"
check_status "first failure passes through the check's exit code" 1 "$STATUS"
check_contains "first failure is counted as #1" "$OUT" "FAIL #1"
check_absent "first failure does not fire STOP" "$OUT" "keel-check: STOP"

# --- the second consecutive failure of the SAME check fires STOP ---------------------------------
fresh_sd
run "$TOOL" "false"          # #1
run "$TOOL" "false"          # #2 -> STOP
check_status "second failure still passes through exit code" 1 "$STATUS"
check_contains "second consecutive failure fires the STOP banner" "$OUT" "keel-check: STOP"
check_contains "STOP names the failure count" "$OUT" "failed 2 times"
# The banner must tell the agent what to do, never how to bypass the check.
check_absent "STOP banner names no bypass syntax" "$OUT" "KEEL_CHECK_THRESHOLD"

# --- a pass between failures resets the streak (same check, controlled by a flag file) -----------
fresh_sd
flag="$SANDBOX/flag.$$"; rm -f "$flag"
check="test -f $flag"
run "$TOOL" "$check"         # fail #1 (flag absent)
: > "$flag"
run "$TOOL" "$check"         # pass -> reset
rm -f "$flag"
run "$TOOL" "$check"         # fail again -> should be #1, not STOP
check_contains "a pass resets the streak (back to #1)" "$OUT" "FAIL #1"
check_absent "reset means no STOP on the next first failure" "$OUT" "keel-check: STOP"

# --- the threshold is tunable: N=1 stops on the very first failure -------------------------------
fresh_sd
KEEL_CHECK_THRESHOLD=1 run "$TOOL" "false"
check_contains "threshold=1 stops on the first failure" "$OUT" "keel-check: STOP"

# --- two different checks keep independent counters ----------------------------------------------
fresh_sd
run "$TOOL" "false"          # check A, #1
run "$TOOL" "false #b"       # check B, its own #1 (different command string)
check_contains "a different check starts its own count at #1" "$OUT" "FAIL #1"
check_absent "a different check does not inherit A's streak" "$OUT" "keel-check: STOP"

# --- the check's own exit code passes through (not clobbered to 1) --------------------------------
fresh_sd
run "$TOOL" "exit 3"
check_status "the check's exit code passes through unchanged" 3 "$STATUS"

# --- no arguments -> usage, exit 2 ---------------------------------------------------------------
run "$TOOL"
check_status "no arguments exits 2" 2 "$STATUS"
check_contains "no arguments prints usage" "$OUT" "usage"

# --- a STOP appends exactly one friction event when KEEL_IMPACT_LOG is set ------------------------
fresh_sd
log="$SANDBOX/kc-impact.log"; : > "$log"
KEEL_IMPACT_LOG="$log" run "$TOOL" "false"   # #1, no stop -> no event
n1="$(grep -c keel-check "$log" 2>/dev/null || true)"
check_status "no friction event before the stop fires" 0 "$n1"
KEEL_IMPACT_LOG="$log" run "$TOOL" "false"   # #2 -> STOP -> one event
n2="$(grep -c keel-check "$log" 2>/dev/null || true)"
check_status "STOP appends exactly one friction event" 1 "$n2"
check_contains "the event is typed friction" "$(cat "$log")" "friction"

# --- dir #85 (code audit, finding 27): a hostile KEEL_CHECK_THRESHOLD degrades gracefully ---------
# The sanitizer exists precisely so a non-numeric or negative value falls back instead of crashing the
# `[ "$n" -ge "$threshold" ]` arithmetic — but nothing exercised it, so a regression there would surface
# as a crashed shim rather than a caught test. Each case: the shim still runs the check and passes its
# exit code through, and the fallback threshold still behaves (banner on the 2nd failure, or the 1st
# where the value clamps to 1).
# All four land on the SAME fallback of 2 — including the negative one, which the non-numeric arm
# catches first (a leading '-' is not [0-9]), never reaching the `-lt 1` clamp. Pinned as a set:
# either route is a graceful degrade, and this records which one actually fires for each.
# The 20-digit value (dir #196, the same overflow class dir #156 fixed in self/doctor.sh) is
# digit-SHAPED but overflows the shell's native integer range: `[ "99999999999999999999" -lt 1 ]`
# crashes with "integer expression expected" rather than comparing, silently defeating the guard
# were it not length-capped — reproduced live against the unguarded case arm before fixing it here.
for bad in abc '' -5 99999999999999999999; do
  fresh_sd
  KEEL_CHECK_THRESHOLD="$bad" run "$TOOL" "false"
  check_status "threshold '$bad': exit code still passes through" 1 "$STATUS"
  check_absent "threshold '$bad' falls back to 2 (no STOP on the 1st failure)" "$OUT" "keel-check: STOP"
  KEEL_CHECK_THRESHOLD="$bad" run "$TOOL" "false"
  check_contains "threshold '$bad' still STOPs on the 2nd failure" "$OUT" "keel-check: STOP"
done

# 0 IS numeric, so it reaches the `-lt 1` clamp and becomes 1 → the banner fires immediately.
fresh_sd
KEEL_CHECK_THRESHOLD=0 run "$TOOL" "false"
check_contains "zero threshold clamps to 1 → STOP on the very first failure" "$OUT" "keel-check: STOP"

summary
