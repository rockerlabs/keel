#!/usr/bin/env bash
# tools/self/cut-sim.sh — keel-self-maintenance (dir #68): run the whole suite on the CUT shape of the
# changelog. There is no consumer-facing counterpart and install.sh never ships this file. dir #744 slice 4
# (B18, dir #722): the 0.14.0 delta audit found three tests that pinned `## [Unreleased]` shipping to the
# release candidate because no gate ran the suite after the cut moved that text under a dated heading; the
# prose sentence in docs/release-audit.md Phase 7 is not a gate, this is.
#
# Usage:
#   tools/self/cut-sim.sh [--repo DIR]
#   tools/self/cut-sim.sh -h | --help
#
# DIR defaults to the repo this script lives in. The script clones DIR's HEAD (committed content only —
# a dirty working tree is not simulated) into a fresh `${TMPDIR:-/tmp}/keel-cut-sim.XXXXXX` directory, runs
# the CLONE's `tools/self/changelog-cut.sh 9999.0.0 <today, UTC>` (the version under test is the clone's, not
# DIR's working copy), commits the result in the clone as keel-cut-sim <cut-sim@example.invalid> (a real cut
# lands as a commit, and doctor treats an uncommitted cut section as a GAP), then runs the clone's
# `tests/run.sh` and prints `cut-sim (dir #722): the suite on the cut shape: PASS` or `...: FAIL`.
#
# Exit 0 the suite passed on the cut shape. Exit 1 it failed (or the cut itself refused: the cut shape is
# then not even producible). Exit 2 refused before cloning: a bad argument, DIR is not a git work tree, or DIR
# is shallow or has no `v*` tag — a shallow or tagless checkout (CI's default) makes the history- and
# tag-reading tests red before any cut; check out with `fetch-depth: 0`. DIR is never written to. The clone
# is removed on every exit path, including a signal: the suite is TERMed, waited for (bounded, then KILLed)
# and only then is the clone removed, so no test is still writing into it. Both verdict lines go to stdout.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$self_dir/../.." && pwd)"

die_args() { echo "cut-sim.sh: $1" >&2; echo "usage: cut-sim.sh [--repo DIR]" >&2; exit 2; }
refuse() { echo "cut-sim.sh: refused — $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    --repo)
      [ $# -ge 2 ] || die_args "--repo needs a directory"
      repo_dir="$2"; shift 2 ;;
    *) die_args "unknown argument '$1'" ;;
  esac
done
[ -d "$repo_dir" ] || die_args "no such directory: $repo_dir"
repo_dir="$(cd "$repo_dir" && pwd)"

# --repo may name any directory inside a work tree; simulate that work tree's root, not the subdirectory.
top="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null)" || refuse "$repo_dir is not inside a git work tree"
repo_dir="$top"
shallow="$(git -C "$repo_dir" rev-parse --is-shallow-repository 2>/dev/null)" || shallow=unknown
[ "$shallow" != "true" ] || refuse "$repo_dir is a shallow checkout — the history- and tag-reading tests would fail before any cut (in CI: actions/checkout with fetch-depth: 0)"
# Capture, then test: a producer piped into `grep -q` under pipefail is the dir #280 SIGPIPE race.
tags="$(git -C "$repo_dir" tag -l 'v*')"
[ -n "$tags" ] || refuse "$repo_dir has no v* tag — a tagless checkout makes the tag-reading tests fail before any cut (in CI: actions/checkout with fetch-depth: 0)"

work=""
child=""

# Remove the clone, once, on every path. The suite is TERMed and waited for first: its tests are the clone's
# writers, and an rm racing them ends in "Directory not empty". One retry after that: a git writer that is
# still finishing can make the first rm fail (dir #744 R2-6); a second failure is a NOTE, never a hidden leak.
cleanup() {
  local rc=$? n=0
  trap - EXIT
  trap '' INT TERM HUP   # a second Ctrl-C / TERM during the wait below must not abandon the clone
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
    # The suite runs as its own process-group leader (set -m at the launch), so the signal reaches every
    # descendant a test file spawned, not only tests/run.sh (whose own handler stops its direct children).
    kill -TERM -- "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null || true
    while kill -0 "$child" 2>/dev/null && [ "$n" -lt 30 ]; do sleep 1; n=$((n + 1)); done
    if kill -0 "$child" 2>/dev/null; then kill -KILL -- "-$child" 2>/dev/null || kill -KILL "$child" 2>/dev/null || true; fi
    wait "$child" 2>/dev/null || true
  fi
  case "$work" in
    */keel-cut-sim.*)
      if ! rm -rf "$work" 2>/dev/null; then
        sleep 1
        rm -rf "$work" 2>/dev/null || echo "cut-sim.sh: NOTE: could not remove $work" >&2
      fi ;;
  esac
  exit "$rc"
}
# The traps come BEFORE the mktemp, so a signal in between cannot leave a directory the handler does not know.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

work="$(mktemp -d "${TMPDIR:-/tmp}/keel-cut-sim.XXXXXX")"
clone="$work/clone"
head_sha="$(git -C "$repo_dir" rev-parse HEAD)"
dirty="$(git -C "$repo_dir" status --porcelain --untracked-files=no)"
[ -z "$dirty" ] || echo "cut-sim: NOTE: $repo_dir has uncommitted changes — only the committed HEAD is simulated" >&2
git clone -q --no-hardlinks "$repo_dir" "$clone"
git -C "$clone" checkout -q --detach "$head_sha"

fail() { echo "cut-sim (dir #722): the suite on the cut shape: FAIL"; exit 1; }

# maintenance.auto/gc.auto off: no detached writer may still be in the clone when the cleanup removes it.
cs_git() { git -C "$clone" -c maintenance.auto=false -c gc.auto=0 -c user.name=keel-cut-sim -c user.email=cut-sim@example.invalid -c commit.gpgsign=false "$@"; }

echo "cut-sim: cutting 9999.0.0 in a clone of $head_sha"
if ! bash "$clone/tools/self/changelog-cut.sh" --repo "$clone" 9999.0.0 "$(date -u +%Y-%m-%d)"; then
  echo "cut-sim: the clone's changelog-cut.sh refused — the cut shape cannot be produced"
  fail
fi
cs_git add -A
cs_git commit -q -m "cut-sim: 9999.0.0"

echo "cut-sim: running the clone's tests/run.sh on the cut shape"
# Background + wait, never a foreground child: bash defers a trap until the foreground command exits, so a
# TERM would otherwise leave the suite running (and the clone in place) until it finished by itself.
set -m
(cd "$clone" && exec bash tests/run.sh) &
child=$!
set +m
rc=0
wait "$child" || rc=$?
child=""
if [ "$rc" -eq 0 ]; then
  echo "cut-sim (dir #722): the suite on the cut shape: PASS"
  exit 0
fi
fail
