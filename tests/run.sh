#!/usr/bin/env bash
# Keel test runner — execute every tests/test_*.sh in its own process and aggregate.
# Each test file sets up (and tears down) its own isolated sandbox HOME (tests/lib.sh), so files
# run independently of each other — that's what makes concurrent execution below safe. The one
# externally-shared resource any file touches, tools/pre-pr-gate.sh's /tmp sentinel (dir #80), is
# keyed off a repo basename that every fixture mints via `mktemp -d "$SANDBOX/repo.XXXXXX"`
# (tests/lib.sh's new_repo(), and pipeline-canary.sh's own toy-repo setup) — randomized per
# process, so two files running at once cannot collide on it either (dir #130).
#
# Portable to bash 3.2 (macOS's shipped /bin/bash) on purpose — no `wait -n`, no associative
# arrays: a poll loop over tracked PIDs stands in for both.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# KEEL_TEST_JOBS overrides the concurrency cap (e.g. `KEEL_TEST_JOBS=1 ./tests/run.sh` to force the
# old fully-sequential behavior for debugging a suspected cross-file interaction).
jobs_cap="${KEEL_TEST_JOBS:-}"
if [ -z "$jobs_cap" ]; then
  jobs_cap="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi
case "$jobs_cap" in (*[!0-9]*|'') jobs_cap=4 ;; esac
[ "$jobs_cap" -ge 1 ] || jobs_cap=1

logdir="$(mktemp -d)"
trap 'rm -rf "$logdir"' EXIT

failed=0
active_pids=()
active_files=()
active_logs=()

# Concurrency amplifies the blast radius of an interrupt: an orphaned `bash "$t"` leaves its own
# sandbox HOME (tests/lib.sh) behind uncleaned, AND — unlike the old sequential runner, which
# streamed each test's output straight to the terminal as it ran — an interrupted test's already-
# buffered-but-not-yet-printed log would otherwise be silently lost (killed before reap_finished
# ever cats it, then the EXIT trap deletes $logdir on the way out). Print every still-active test's
# log before killing it, so an operator interrupting a hung run still gets the same diagnostic
# trail the old runner gave for free (found by an operator-run /code-review high pass, dir #130).
# Doesn't reach a grandchild subprocess a test file itself spawned (no process-group kill) — a
# known, currently-unreachable gap: every test's git/gh/curl usage today is local-only or stubbed.
on_interrupt() {
  local i
  for i in "${!active_pids[@]}"; do
    printf '\n=== %s (interrupted) ===\n' "${active_files[$i]}"
    cat "${active_logs[$i]}" 2>/dev/null
  done
  # ${active_pids[@]+...} guards an empty array under `set -u` (bash 3.2 treats an empty array's
  # [@] expansion as unbound), same idiom reap_finished uses below.
  kill "${active_pids[@]+"${active_pids[@]}"}" 2>/dev/null
  exit 130
}
trap on_interrupt INT TERM

# Wait for and report every job in active_* whose process has already exited, compacting the
# arrays down to only the ones still running. Prints how many it reaped (as $?) so a caller can
# skip the poll sleep on a pass that just freed a slot instead of idling out the rest of it.
reap_finished() {
  local new_pids=() new_files=() new_logs=()
  local i pid rc reaped=0
  for i in "${!active_pids[@]}"; do
    pid="${active_pids[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
      new_pids+=("$pid")
      new_files+=("${active_files[$i]}")
      new_logs+=("${active_logs[$i]}")
      continue
    fi
    wait "$pid"
    rc=$?
    printf '\n=== %s ===\n' "${active_files[$i]}"
    cat "${active_logs[$i]}"
    [ "$rc" -eq 0 ] || failed=$((failed + 1))
    reaped=$((reaped + 1))
  done
  active_pids=("${new_pids[@]+"${new_pids[@]}"}")
  active_files=("${new_files[@]+"${new_files[@]}"}")
  active_logs=("${new_logs[@]+"${new_logs[@]}"}")
  return "$reaped"
}

# Block until at most $1 jobs remain active, reaping (and printing) each as it finishes. Used both
# to throttle launches (wait for a free slot) and, with 0, to drain everything at the end.
wait_until_at_most() {
  while [ "${#active_pids[@]}" -gt "$1" ]; do
    reap_finished && sleep 0.1  # reap_finished's $? is how many it reaped — 0 means still full, poll again
  done
}

# Room to keep for the job about to launch, so the loop below caps steady-state concurrency at
# jobs_cap rather than jobs_cap+1: throttling post-launch (the original shape) let one extra job
# run for the instant between a launch and its own throttle check — with KEEL_TEST_JOBS=1 that
# meant two jobs overlapping instead of the true one-at-a-time the env var promises (found by an
# operator-run /code-review high pass, dir #130).
launch_cap=$((jobs_cap - 1))
for t in "$here"/test_*.sh; do
  wait_until_at_most "$launch_cap"
  base="$(basename "$t")"
  log="$logdir/$base.log"
  bash "$t" >"$log" 2>&1 &
  active_pids+=("$!")
  active_files+=("$base")
  active_logs+=("$log")
done
wait_until_at_most 0

printf '\n========================================\n'
if [ "$failed" -eq 0 ]; then
  printf 'ALL TEST FILES PASSED\n'
  exit 0
fi
printf '%d TEST FILE(S) FAILED\n' "$failed"
exit 1
