#!/usr/bin/env bash
# Tests for tools/keel-check.sh — the stop-mode floor (backlog dir #33, tier T1a). We pin the machinery,
# not judgment: a pass exits 0 and resets the streak; the first failure warns but doesn't stop; the N-th
# consecutive failure of the SAME check fires the STOP banner; a pass between failures resets the streak;
# the threshold is tunable; two different checks keep independent counters; the check's own exit code
# passes through; and a STOP appends exactly one zero-token friction event when KEEL_IMPACT_LOG is set.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

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

# --- dir #398/#399/#637: the default root moved off shared /tmp to $HOME/.keel/tmp ------------------
# No KEEL_CHECK_STATE_DIR override this time — the counter must land under $HOME/.keel/tmp/keel-check,
# never in the real /tmp (this run's own $HOME is already the sandbox, dir #64).
run env -u KEEL_CHECK_STATE_DIR "$TOOL" "false"
check_status "no override: exit code still passes through" 1 "$STATUS"
check_dir "no override: the default root lands under \$HOME/.keel/tmp/keel-check" "$HOME/.keel/tmp/keel-check"

# HOME unset AND no override -> fail closed with a clear message, never a silent "/.keel/tmp".
run env -u KEEL_CHECK_STATE_DIR -u HOME "$TOOL" "false"
check_status "HOME unset, no override -> exit 1 (fail closed)" 1 "$STATUS"
check_contains "HOME unset, no override -> names the cause" "$OUT" '$HOME is unset'

# An explicit override still works even with HOME unset.
fresh_sd
run env -u HOME "KEEL_CHECK_STATE_DIR=$KEEL_CHECK_STATE_DIR" "$TOOL" "false"
check_status "HOME unset, explicit override -> exit code still passes through" 1 "$STATUS"
check_contains "HOME unset, explicit override -> still counts (FAIL #1)" "$OUT" "FAIL #1"

# --- dir #647 (S3 FINDING-S3-1): an inherited GIT_DIR+GIT_WORK_TREE naming a DECOY repo must not
# redirect the repo_top resolution away from the real repo — otherwise the counter (and, downstream,
# keel-check-gate.sh's red marker) is keyed to the wrong repo entirely. Live hijack scenario: a decoy
# repo's GIT_DIR paired with its own GIT_WORK_TREE, present in the environment BEFORE keel-check.sh
# sources tools/lib/repo-arg-guard.sh, must not make `git -C "$PWD" rev-parse --show-toplevel` answer
# for the decoy while $PWD is really inside the real repo. Mirrors
# tests/test_repo_arg_guard_lib.sh's own hijack pattern.
fresh_sd
real="$(new_repo)"; git -C "$real" commit -q --allow-empty -m init
decoy="$(new_repo)"; git -C "$decoy" commit -q --allow-empty -m init
decoy_gitdir="$(git -C "$decoy" rev-parse --absolute-git-dir)"
real_top="$(git -C "$real" rev-parse --show-toplevel)"
decoy_top="$(git -C "$decoy" rev-parse --show-toplevel)"
real_key="$(printf '%s' "$real_top" | cksum | tr -cd '0-9')"
decoy_key="$(printf '%s' "$decoy_top" | cksum | tr -cd '0-9')"
run_in "$real" env GIT_DIR="$decoy_gitdir" GIT_WORK_TREE="$decoy" "$TOOL" "false"
check_status "hijack: exit code still passes through" 1 "$STATUS"
check_dir "hijack: the REAL repo's key dir is created (not redirected to the decoy)" \
  "$KEEL_CHECK_STATE_DIR/keel-check/$real_key"
check_nodir "hijack: the decoy's key dir is never created" \
  "$KEEL_CHECK_STATE_DIR/keel-check/$decoy_key"

# --- dir #398 R5's empty-dir reap must not race a DIFFERENT concurrent invocation's just-created,
# still-empty repo_dir (found by this ticket's own /code-review high pass, angles A and B): the reap
# walks the WHOLE $state_dir/keel-check tree, not just this invocation's own repo, so an unconditional
# empty-dir rmdir could remove a sibling repo's dir the instant after it was mkdir'd but before its
# first counter write. Fixed by giving the directory reap the SAME -mtime +30 age floor as the file
# sweep — simulated here deterministically (no real race needed): a fresh, still-empty "other repo"
# dir must survive a forced prune pass, the same way a fresh file would.
fresh_sd
mkdir -p "$KEEL_CHECK_STATE_DIR/keel-check"
other_repo_dir="$KEEL_CHECK_STATE_DIR/keel-check/simulated-other-repo-key"
mkdir -p "$other_repo_dir"          # empty, freshly created — mtime is "now"
: > "$KEEL_CHECK_STATE_DIR/keel-check/.last-prune"
touch -t 202001010000 "$KEEL_CHECK_STATE_DIR/keel-check/.last-prune"   # force the rate-limit to fire
run "$TOOL" "false"                 # any check on any repo forces a prune pass under this state dir
check_dir "R5 prune: a fresh, still-empty sibling repo dir survives the reap" "$other_repo_dir"

summary
