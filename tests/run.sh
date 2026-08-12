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

# Wait for and report every job in active_* whose process has already exited, compacting the
# arrays down to only the ones still running. Called both to throttle launches (loop until a slot
# frees) and, at the end, to drain everything that's left.
reap_finished() {
  local new_pids=() new_files=() new_logs=()
  local i pid rc
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
  done
  active_pids=("${new_pids[@]+"${new_pids[@]}"}")
  active_files=("${new_files[@]+"${new_files[@]}"}")
  active_logs=("${new_logs[@]+"${new_logs[@]}"}")
}

for t in "$here"/test_*.sh; do
  base="$(basename "$t")"
  log="$logdir/$base.log"
  bash "$t" >"$log" 2>&1 &
  active_pids+=("$!")
  active_files+=("$base")
  active_logs+=("$log")
  while [ "${#active_pids[@]}" -ge "$jobs_cap" ]; do
    reap_finished
    [ "${#active_pids[@]}" -ge "$jobs_cap" ] && sleep 0.1
  done
done
while [ "${#active_pids[@]}" -gt 0 ]; do
  reap_finished
  [ "${#active_pids[@]}" -gt 0 ] && sleep 0.1
done

printf '\n========================================\n'
if [ "$failed" -eq 0 ]; then
  printf 'ALL TEST FILES PASSED\n'
  exit 0
fi
printf '%d TEST FILE(S) FAILED\n' "$failed"
exit 1
