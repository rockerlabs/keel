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

# dir #318: a corruption canary for the checkout this suite itself runs from — every test file's
# fixtures are supposed to mutate only their own tests/lib.sh sandbox (mktemp'd HOME/repo dirs), never
# the real repo the process happened to start in. A rare, non-deterministic leak of that kind was found
# once via `git reflog` (fixture commit messages and branch names from test_pre_pr_gate.sh's own
# crossfork-PR fixtures, appended to a real feature branch) but was not reproduced under repeated single-
# file and full concurrent runs against a real worktree. Record this real checkout's branch/HEAD/working-
# tree status before the suite runs so a recurrence is caught loudly instead of silently, whether or not
# the individual test files themselves report a failure. The status snapshot is a before/after COMPARE,
# not an assert-clean — a developer may genuinely run this suite with uncommitted changes already
# present, and only a change in that snapshot (not its mere non-emptiness) means something moved.
guard_repo_root="$(cd "$here/.." && pwd)"
guard_before_branch="" guard_before_head="" guard_before_status=""
if git -C "$guard_repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  guard_before_branch="$(git -C "$guard_repo_root" branch --show-current 2>/dev/null || true)"
  guard_before_head="$(git -C "$guard_repo_root" rev-parse HEAD 2>/dev/null || true)"
  guard_before_status="$(git -C "$guard_repo_root" status --porcelain 2>/dev/null || true)"
fi

# KEEL_TEST_JOBS overrides the concurrency cap (e.g. `KEEL_TEST_JOBS=1 ./tests/run.sh` to force the
# old fully-sequential behavior for debugging a suspected cross-file interaction).
#
# Default: host CPU count, EXCEPT under CI ($CI, set by GitHub Actions and effectively every other
# CI provider) where it's capped at 2 regardless of the reported count. dir #153 found the
# alpine-in-docker leg's nproc-reported count didn't reflect the container's real share of the
# runner, and dir #154 confirmed the same fork-contention flake on a plain ubuntu-24.04 leg too —
# no file the flaking check reads is ever mutated during the suite, so it isn't a content race; it's
# many test files' own subprocess forking (git/awk/grep) stacking up under this runner's own
# concurrency, enough to starve a fork on a small hosted runner regardless of OS or container. One
# CI-wide default here means a future CI leg gets the safe cap for free instead of needing its own
# copy of this fix in .github/workflows/ci.yml (KEEL_TEST_JOBS stays available as the manual
# override for a local repro).
jobs_cap="${KEEL_TEST_JOBS:-}"
if [ -z "$jobs_cap" ]; then
  if [ -n "${CI:-}" ]; then
    jobs_cap=2
  else
    jobs_cap="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  fi
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

# Trip the canary set up above: if the real checkout's branch, HEAD, or working-tree status changed
# during the run, a test fixture leaked a real git mutation outside its sandbox — flag it loudly
# regardless of whether any individual test file reported a failure of its own. The status half catches
# a leak that dirties the tree/index without moving HEAD (a stray file write, a staged-but-uncommitted
# change) that the branch/HEAD compare alone would miss.
if [ -n "$guard_before_head" ]; then
  guard_after_branch="$(git -C "$guard_repo_root" branch --show-current 2>/dev/null || true)"
  guard_after_head="$(git -C "$guard_repo_root" rev-parse HEAD 2>/dev/null || true)"
  guard_after_status="$(git -C "$guard_repo_root" status --porcelain 2>/dev/null || true)"
  if [ "$guard_after_branch" != "$guard_before_branch" ] || [ "$guard_after_head" != "$guard_before_head" ] \
      || [ "$guard_after_status" != "$guard_before_status" ]; then
    printf '\n!!! TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #318) !!!\n'
    printf 'the real checkout this suite ran from changed during the run:\n'
    printf '  before: branch=%s head=%s\n' "$guard_before_branch" "$guard_before_head"
    printf '  after:  branch=%s head=%s\n' "$guard_after_branch" "$guard_after_head"
    if [ "$guard_after_status" != "$guard_before_status" ]; then
      printf '  working-tree/index status also changed (git status --porcelain differs from before the run)\n'
    fi
    printf 'a fixture helper mutated the real repo instead of its own sandbox — do not push this\n'
    printf 'branch until the real history is reconciled by hand.\n'
    failed=$((failed + 1))
  fi
fi

printf '\n========================================\n'
if [ "$failed" -eq 0 ]; then
  printf 'ALL TEST FILES PASSED\n'
  exit 0
fi
printf '%d TEST FILE(S) FAILED\n' "$failed"
exit 1
