#!/usr/bin/env bash
# tests/test_repo_top_lib.sh — dir #415: direct unit coverage for tools/lib/repo-top.sh's
# keel_repo_main_top/keel_repo_top, the shared main-checkout-resolution chain both
# tools/lib/impact-store.sh's _impact_main_top/_impact_resolve_top and
# tools/lib/transcript-usage.sh's tu_repo_top now delegate to. Those two libs' own test suites
# (test_impact_store_lib.sh, test_transcript_usage_lib.sh) already exercise this chain transitively
# through their wrappers and stay green — this file pins the chain directly, at its own canonical
# home, so a future third consumer (or a change here) is caught at the source rather than only via
# whichever wrapper happens to still call it.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

lib="$REPO_ROOT/tools/lib/repo-top.sh"
check_file "tools/lib/repo-top.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

# --- keel_repo_main_top: the first `git worktree list --porcelain` entry, empty if bare/not-a-repo ---
plain_repo="$(new_repo)"
plain_repo_p="$(cd "$plain_repo" && pwd -P)"
check_status "keel_repo_main_top resolves a plain (non-worktree) repo to its own toplevel" \
  "$plain_repo_p" "$(keel_repo_main_top "$plain_repo")"

git -C "$plain_repo" commit --allow-empty -qm init
wt_dir="$SANDBOX/repo-top-worktree"
git -C "$plain_repo" worktree add -q "$wt_dir" -b repo-top-wt-branch
check_status "keel_repo_main_top folds a worktree back to the MAIN checkout's top" \
  "$plain_repo_p" "$(keel_repo_main_top "$wt_dir")"

non_repo="$SANDBOX/repo-top-not-a-repo"
mkdir -p "$non_repo"
check_status "keel_repo_main_top prints nothing outside any git repo" \
  "" "$(keel_repo_main_top "$non_repo")"

# --- keel_repo_top: keel_repo_main_top, else rev-parse --show-toplevel, else DIR's own physical path
check_status "keel_repo_top resolves a plain (non-worktree) repo to its own toplevel" \
  "$plain_repo_p" "$(keel_repo_top "$plain_repo")"

check_status "keel_repo_top folds a worktree back to the MAIN checkout's top" \
  "$plain_repo_p" "$(keel_repo_top "$wt_dir")"

non_repo_p="$(cd "$non_repo" && pwd -P)"
check_status "keel_repo_top falls back to DIR's own physical path outside any git repo" \
  "$non_repo_p" "$(keel_repo_top "$non_repo")"

summary
