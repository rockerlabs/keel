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
# then not even producible). Exit 2 refused before cloning: a bad argument, DIR is not a git repo, or DIR has
# no `v*` tag — a shallow, tagless checkout (CI's default) makes the tag-reading tests red before any cut;
# check out with `fetch-depth: 0`. DIR is never written to. The clone is removed on every exit path,
# including a signal.
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

git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || refuse "$repo_dir is not a git repository"
# Capture, then test: a producer piped into `grep -q` under pipefail is the dir #280 SIGPIPE race.
tags="$(git -C "$repo_dir" tag -l 'v*')"
[ -n "$tags" ] || refuse "$repo_dir has no v* tag — a shallow, tagless checkout makes the tag-reading tests fail before any cut (in CI: actions/checkout with fetch-depth: 0)"

work="$(mktemp -d "${TMPDIR:-/tmp}/keel-cut-sim.XXXXXX")"
[ -n "$work" ] || exit 2
child=""

# Remove the clone, once, on every path. One retry: a git writer that is still finishing can make the first
# rm fail with "Directory not empty" (dir #744 R2-6); a second failure is a NOTE, never a hidden leak.
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then kill -TERM "$child" 2>/dev/null || true; fi
  case "$work" in
    */keel-cut-sim.*)
      if ! rm -rf "$work" 2>/dev/null; then
        sleep 1
        rm -rf "$work" 2>/dev/null || echo "cut-sim.sh: NOTE: could not remove $work" >&2
      fi ;;
  esac
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

clone="$work/clone"
head_sha="$(git -C "$repo_dir" rev-parse HEAD)"
git clone -q --no-hardlinks "$repo_dir" "$clone"
git -C "$clone" checkout -q --detach "$head_sha"

fail() { echo "cut-sim (dir #722): the suite on the cut shape: FAIL" >&2; exit 1; }

# maintenance.auto/gc.auto off: no detached writer may still be in the clone when the cleanup removes it.
cs_git() { git -C "$clone" -c maintenance.auto=false -c gc.auto=0 -c user.name=keel-cut-sim -c user.email=cut-sim@example.invalid "$@"; }

echo "cut-sim: cutting 9999.0.0 in a clone of $head_sha"
if ! bash "$clone/tools/self/changelog-cut.sh" --repo "$clone" 9999.0.0 "$(date -u +%Y-%m-%d)"; then
  echo "cut-sim: the clone's changelog-cut.sh refused — the cut shape cannot be produced" >&2
  fail
fi
cs_git add -A
cs_git commit -q -m "cut-sim: 9999.0.0"

echo "cut-sim: running the clone's tests/run.sh on the cut shape"
# Background + wait, never a foreground child: bash defers a trap until the foreground command exits, so a
# TERM would otherwise leave the suite running (and the clone in place) until it finished by itself.
(cd "$clone" && exec bash tests/run.sh) &
child=$!
rc=0
wait "$child" || rc=$?
child=""
if [ "$rc" -eq 0 ]; then
  echo "cut-sim (dir #722): the suite on the cut shape: PASS"
  exit 0
fi
fail
