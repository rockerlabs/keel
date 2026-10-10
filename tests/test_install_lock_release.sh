#!/usr/bin/env bash
# test_install_lock_release.sh — dir #757 / dir #756 (b) (docs/specs/685-symlink-policy.md round 2, slice
# S5b, B18): install.sh's run lock is released on every exit after it is taken. One EXIT trap, in dir
# #692's completion-marker form, is armed right after the pid write and disarmed by the success-path
# release itself, so:
#   - a refusal or abort after the lock (a lib guard, a state-write refusal, a Verify failure) leaves no
#     lock and still exits non-zero;
#   - SIGTERM / SIGINT during the run remove the lock and exit 143 / 130;
#   - once released, our run can no longer remove a lock a sibling install took after ours.
# The `set -u` probes of the marker form itself live in tests/test_exit_trap_marker.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

install="$REPO_ROOT/install.sh"

# start_paused TAG CHECKPOINT [monitor] — start an install into "$SANDBOX/TAG/h" in the background, paused at
# CHECKPOINT (KEEL_TEST_PAUSE_AFTER); sets $h, $mk (the pause marker) and $pid, and returns wait_ready's
# answer. `monitor` starts it under `set -m`, in its own process group (the SIGINT row). Called in the test's
# own shell, so the install stays this shell's child for reap.
start_paused() {
  h="$SANDBOX/$1/h"; mk="$SANDBOX/$1.marker"; mkdir -p "$h"; : > "$mk"
  [ "${3:-}" = monitor ] && set -m
  KEEL_TEST_PAUSE_AFTER="$2" KEEL_TEST_PAUSE_MARKER="$mk" \
    "$install" --home "$h" --no-hooks > "$SANDBOX/$1.out" 2>&1 </dev/null &
  pid=$!
  set +m
  wait_ready "$mk"
}
# abandon PID LABEL — a paused install that never reached its checkpoint: kill it, reap it, fail the row.
abandon() {
  kill -9 "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true
  fail "$2: the install reached its pause checkpoint" "no $mk.ready"
}
# reap PID — a bounded wait for PID, its exit status in $REAPED. Called in the test's own shell, never
# inside `$( )`: a subshell cannot wait for its parent's child. A pid still alive after 120s is killed
# (status 137), so a build that ignores the signal fails its row instead of hanging the suite — 120s
# because a full install after the pause, under a parallel test wave's load, can take well past 30s.
reap() {
  local p="$1" dog
  ( trap 'kill "${s:-}" 2>/dev/null; exit 0' TERM; sleep 120 & s=$!; wait "$s"; kill -9 "$p" ) > /dev/null 2>&1 &
  dog=$!
  wait "$p"; REAPED=$?
  kill "$dog" 2>/dev/null || true; wait "$dog" 2>/dev/null || true
}

# --- scratch checkout for A31 (2): a copy of this tree (not a git repository) -----------------------
ck="$SANDBOX/ck"
tracked_tree_copy "$ck" || exit 1

# --- A31 (2): a REQUIRED lib guard still after the lock leaves no lock -------------------------------
: > "$ck/tools/lib/artifact-cksum.sh"
h="$SANDBOX/a31/h"; mkdir -p "$h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A31 a 0-byte artifact-cksum.sh → exit 1" 1 "$STATUS"
check_contains "A31 …naming that lib" "$OUT" "tools/lib/artifact-cksum.sh is missing or corrupted"
check_nodir "A31 …and no run lock is left" "$h/.install.lock"

# --- A32: two forced post-acquire failures, each non-zero with no lock left --------------------------
# (1) a state refusal: copy mode over a foreign CLAUDE.md (so the foreign-core marker is written) with a
# FIFO at the marker's path — keel_write_state refuses a non-regular target, and the run exits 1.
if command -v mkfifo >/dev/null 2>&1; then
  h="$SANDBOX/a32f/h"; mkdir -p "$h/.keel"
  printf '# my own CLAUDE.md\n' > "$h/CLAUDE.md"
  mkfifo "$h/.keel/foreign-core.claude"
  run "$install" --home "$h" --no-hooks
  check_status "A32 a FIFO at the foreign-core marker → exit 1" 1 "$STATUS"
  check_contains "A32 …refused as not a regular file" "$OUT" "is not a regular file"
  check_nodir "A32 …and no run lock is left" "$h/.install.lock"
fi
# (2) a verification failure: a shipped file reported missing at Verify.
h="$SANDBOX/a32v/h"
run env KEEL_TEST_REMOVE_BEFORE_VERIFY=INSTANCE.md "$install" --home "$h" --no-hooks
check_status "A32 a Verify MISS → exit 1" 1 "$STATUS"
check_nodir "A32 …and no run lock is left" "$h/.install.lock"

# --- A33 / K29a: SIGTERM and SIGINT during the run ---------------------------------------------------
# Paused at merge-write (well after the lock is taken). SIGINT is sent to a job started under `set -m`:
# a non-interactive shell starts a plain background job with SIGINT ignored, and a signal ignored on
# entry cannot be trapped, so only a job in its own process group sees the INT the way a terminal's
# Ctrl-C reaches a foreground install.
# A signal ignored when this file started (tests/run.sh starts each file as a background job of a
# non-interactive shell, so SIGINT arrives here ignored) cannot be trapped or reset by this file or by any
# install.sh under it — the INT row then has nothing to observe, and is skipped with that reason. Run
# standalone (`bash tests/test_install_lock_release.sh`), or from a terminal, it runs.
int_probe=0
( set -m; bash -c 'trap "exit 7" INT; kill -INT $$; exit 0' ) || int_probe=$?
for sig in TERM INT; do
  # TERM goes to the install's own pid; INT to its whole process group, as a terminal's Ctrl-C does (bash
  # treats an INT its foreground child survived as handled, so an INT to the shell alone proves nothing).
  case "$sig" in
    TERM) want=143; target="$sig" ;;
    INT)  want=130; target="-$sig"
          if [ "$int_probe" != 7 ]; then
            pass "A33/K29a SIGINT row skipped — SIGINT is ignored in this test's environment (ignored on entry, so untrappable)"
            continue
          fi ;;
  esac
  if start_paused "a33-$sig" merge-write monitor; then
    check_dir "A33 $sig fixture: the paused run holds the lock" "$h/.install.lock"
    if [ "$target" = TERM ]; then kill -TERM "$pid"; else kill -INT -- -"$pid"; fi
    reap "$pid"
    check_status "A33/K29a SIG$sig during the run → exit $want" "$want" "$REAPED"
    check_nodir "A33/K29a …and no run lock is left" "$h/.install.lock"
  else
    abandon "$pid" "A33 $sig fixture"
  fi
done

# --- review: a lock taken over mid-run is not ours to remove ----------------------------------------
# Two runs recovering one stale lock at once (or a sibling whose `kill -0` met EPERM) can leave a live run
# whose lock now names another process. Staged: pause a run holding the lock, rewrite the pid file to a
# live process (this test's own shell), then TERM the run — its exit must leave that lock in place.
if start_paused r-takeover merge-write; then
  printf '%s\n' "$$" > "$h/.install.lock/pid"
  kill -TERM "$pid"
  reap "$pid"
  check_status "takeover: the interrupted run exits 143" 143 "$REAPED"
  check_eq "takeover: …and the lock that now names another live process is left in place" "$$" \
    "$(cat "$h/.install.lock/pid" 2>/dev/null)"
else
  abandon "$pid" "takeover fixture"
fi

# …and the success path's release reads the same pid file: a run that finishes normally leaves a
# taken-over lock in place too.
if start_paused r-takeover-ok merge-write; then
  printf '%s\n' "$$" > "$h/.install.lock/pid"
  rm -f "$mk"
  reap "$pid"
  check_status "takeover (success path): the run finishes → exit 0" 0 "$REAPED"
  check_eq "takeover (success path): …and leaves the lock that now names another live process" "$$" \
    "$(cat "$h/.install.lock/pid" 2>/dev/null)"
else
  abandon "$pid" "takeover (success path) fixture"
fi

# …and a pid file that names this run without a final newline is still read as this run's: released.
if start_paused r-nonl merge-write; then
  printf '%s' "$pid" > "$h/.install.lock/pid"
  rm -f "$mk"
  reap "$pid"
  check_status "own pid, no final newline: the run finishes → exit 0" 0 "$REAPED"
  check_nodir "own pid, no final newline: …and releases its lock" "$h/.install.lock"
else
  abandon "$pid" "own-pid fixture"
fi

# --- A34 / K30: after our release, a sibling's lock is never ours to remove --------------------------
# The first install pauses right after its success-path release; a second install then takes the lock
# and pauses holding it; the first finishes. A trap still armed at the first's exit would delete the
# second's lock.
h="$SANDBOX/a34/h"; mkdir -p "$h"
mk1="$SANDBOX/a34-first.marker"; mk2="$SANDBOX/a34-second.marker"; : > "$mk1"; : > "$mk2"
KEEL_TEST_PAUSE_AFTER=lock-released KEEL_TEST_PAUSE_MARKER="$mk1" \
  "$install" --home "$h" --no-hooks > "$SANDBOX/a34-first.out" 2>&1 </dev/null &
p1=$!
if wait_ready "$mk1"; then
  check_nodir "A34 fixture: the first run has released its lock" "$h/.install.lock"
  KEEL_TEST_PAUSE_AFTER=merge-write KEEL_TEST_PAUSE_MARKER="$mk2" \
    "$install" --home "$h" --no-hooks > "$SANDBOX/a34-second.out" 2>&1 </dev/null &
  p2=$!
  if wait_ready "$mk2"; then
    check_dir "A34 fixture: the second run holds the lock" "$h/.install.lock"
    rm -f "$mk1"
    reap "$p1"
    check_status "A34/K30 the first run finishes → exit 0" 0 "$REAPED"
    check_dir "A34/K30 …and the second run's lock directory is still there" "$h/.install.lock"
    check_file "A34/K30 …with its pid file" "$h/.install.lock/pid"
    rm -f "$mk2"
    reap "$p2"
    check_status "A34 the second run then finishes → exit 0" 0 "$REAPED"
    check_nodir "A34 …and releases its own lock" "$h/.install.lock"
  else
    rm -f "$mk1" "$mk2"
    kill -9 "$p2" 2>/dev/null || true; wait "$p2" 2>/dev/null || true
    wait "$p1" 2>/dev/null || true
    fail "A34 fixture: the second install reached its pause checkpoint" "no $mk2.ready"
  fi
else
  rm -f "$mk1" "$mk2"
  kill -9 "$p1" 2>/dev/null || true; wait "$p1" 2>/dev/null || true
  fail "A34 fixture: the first install reached its post-release checkpoint" "no $mk1.ready"
fi

summary
