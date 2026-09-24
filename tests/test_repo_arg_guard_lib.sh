#!/usr/bin/env bash
# test_repo_arg_guard_lib.sh — dir #644: sourcing tools/lib/repo-arg-guard.sh unsets GIT_DIR /
# GIT_COMMON_DIR / GIT_WORK_TREE / GIT_INDEX_FILE, unconditionally, and its `keel_repo_arg_guard` is
# the shared validity gate for a tool that resolves a caller-named <repo> via `git -C "$REPO"`. Before
# this ticket, an inherited value for any of the four could redirect that first `git -C "$REPO"` call
# — including the validity gate itself — into a different repository than the one named on the command
# line, up to and including making a NON-git $REPO falsely pass as valid (reproduced live, recorded in
# tools/install-secret-guard.sh's own comment at its call site). This pins the unset and the function
# directly, plus that tools/pipeline-canary.sh, tools/install-read-trace.sh and
# tools/install-pre-pr-gate.sh all source this file (tools/install-secret-guard.sh deliberately does
# NOT — see its own comment for why, and tests/test_secret_guard.sh's own dir #644 block for its
# coverage).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/repo-arg-guard.sh"
check_file "tools/lib/repo-arg-guard.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- sourcing unsets all four vars, unconditionally, before any caller does anything else — run in a
# CHILD process: this file already sourced $lib once above (before the export below could pollute
# anything), so re-observing the unset needs a fresh process that sources it AFTER the vars are set.
src_out="$(env GIT_DIR=/should-not-survive GIT_COMMON_DIR=/should-not-survive \
  GIT_WORK_TREE=/should-not-survive GIT_INDEX_FILE=/should-not-survive \
  bash -c '. "$1"; printf "GIT_DIR=[%s] GIT_COMMON_DIR=[%s] GIT_WORK_TREE=[%s] GIT_INDEX_FILE=[%s]\n" \
    "${GIT_DIR:-}" "${GIT_COMMON_DIR:-}" "${GIT_WORK_TREE:-}" "${GIT_INDEX_FILE:-}"' _ "$lib")"
check_status "sourcing repo-arg-guard.sh unsets all four vars unconditionally" \
  "GIT_DIR=[] GIT_COMMON_DIR=[] GIT_WORK_TREE=[] GIT_INDEX_FILE=[]" "$src_out"

# --- keel_repo_arg_guard itself, on a valid repo: succeeds (no exit) --------------------------------
r1="$(new_repo)"
run keel_repo_arg_guard "$r1"
check_status "keel_repo_arg_guard: a valid repo succeeds (exit 0)" 0 "$STATUS"

# --- a non-git repo: exits 2, "not a git repo: <repo>" (unchanged wording), no ambient var can rescue
# it — run in a CHILD process: keel_repo_arg_guard calls `exit 2` on failure (matching the inline check
# it replaces, which also ran at top level under `set -e`), which would otherwise exit this file too.
notrepo="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
run bash -c '. "$1"; keel_repo_arg_guard "$2"' _ "$lib" "$notrepo"
check_status "keel_repo_arg_guard: a non-git repo exits 2" 2 "$STATUS"
check_contains "keel_repo_arg_guard: names the repo as not a git repo (unchanged wording)" "$OUT" "not a git repo: $notrepo"

# --- the hijack itself: an ambient GIT_DIR naming a REAL repo must not make a non-git $REPO pass ----
decoy="$(new_repo)"; git -C "$decoy" commit -q --allow-empty -m init
decoy_gitdir="$(git -C "$decoy" rev-parse --git-dir)"
case "$decoy_gitdir" in /*) ;; *) decoy_gitdir="$decoy/$decoy_gitdir" ;; esac
run env GIT_DIR="$decoy_gitdir" bash -c '. "$1"; keel_repo_arg_guard "$2"' _ "$lib" "$notrepo"
check_status "keel_repo_arg_guard: an ambient GIT_DIR does not rescue a non-git repo (still exit 2)" 2 "$STATUS"
check_contains "keel_repo_arg_guard: still names it as not a git repo under the ambient hijack" "$OUT" "not a git repo: $notrepo"

# --- consumers: pipeline-canary.sh, install-read-trace.sh and install-pre-pr-gate.sh all source this
# file (the source-time unset alone is enough for pipeline-canary.sh, which never resolves a caller-
# named repo); install-secret-guard.sh deliberately inlines the same unset instead (see its own
# comment) — asserted here so a future edit that drops any of these doesn't go unnoticed by any test
# file.
for consumer in pipeline-canary.sh install-read-trace.sh install-pre-pr-gate.sh; do
  csrc="$(cat "$REPO_ROOT/tools/$consumer")"
  check_contains "tools/$consumer sources tools/lib/repo-arg-guard.sh" "$csrc" 'lib/repo-arg-guard.sh'
done
for consumer in install-read-trace.sh install-pre-pr-gate.sh; do
  csrc="$(cat "$REPO_ROOT/tools/$consumer")"
  check_contains "tools/$consumer's <repo> branch calls keel_repo_arg_guard" "$csrc" 'keel_repo_arg_guard "$repo"'
done
check_contains "tools/install-secret-guard.sh unsets the four vars inline (not sourced), at the top" \
  "$(cat "$REPO_ROOT/tools/install-secret-guard.sh")" 'unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE'

summary
