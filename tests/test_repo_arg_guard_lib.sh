#!/usr/bin/env bash
# test_repo_arg_guard_lib.sh — dir #644: tools/lib/repo-arg-guard.sh's `keel_repo_arg_guard` is the
# shared validity gate for a tool that resolves a caller-named <repo> via `git -C "$REPO"`. Before this
# ticket, an inherited GIT_DIR / GIT_COMMON_DIR / GIT_WORK_TREE / GIT_INDEX_FILE could redirect that
# first `git -C "$REPO"` call — including the validity gate itself — into a different repository than
# the one named on the command line, up to and including making a NON-git $REPO falsely pass as valid
# (reproduced live, recorded in tools/install-secret-guard.sh's own comment at its call site). This
# pins the function directly, plus that tools/install-read-trace.sh and tools/install-pre-pr-gate.sh
# both derive from it rather than keeping their own copy of the inline check (tools/install-secret-
# guard.sh deliberately does NOT — see its own comment for why, and tests/test_secret_guard.sh's own
# dir #644 block for its coverage).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/repo-arg-guard.sh"
check_file "tools/lib/repo-arg-guard.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- a valid repo: succeeds, and unsets the four vars for the rest of the calling process -----------
r1="$(new_repo)"
export GIT_DIR="/should-not-survive" GIT_COMMON_DIR="/should-not-survive" \
  GIT_WORK_TREE="/should-not-survive" GIT_INDEX_FILE="/should-not-survive"
keel_repo_arg_guard "$r1"
check_status "keel_repo_arg_guard: a valid repo leaves GIT_DIR unset afterward" "" "${GIT_DIR:-}"
check_status "keel_repo_arg_guard: a valid repo leaves GIT_COMMON_DIR unset afterward" "" "${GIT_COMMON_DIR:-}"
check_status "keel_repo_arg_guard: a valid repo leaves GIT_WORK_TREE unset afterward" "" "${GIT_WORK_TREE:-}"
check_status "keel_repo_arg_guard: a valid repo leaves GIT_INDEX_FILE unset afterward" "" "${GIT_INDEX_FILE:-}"

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

# --- consumers: install-read-trace.sh and install-pre-pr-gate.sh derive from it; install-secret-
# guard.sh deliberately inlines the same two lines instead (see its own comment) — asserted here so a
# future edit that drops one or the other doesn't go unnoticed by any test file.
for consumer in install-read-trace.sh install-pre-pr-gate.sh; do
  csrc="$(cat "$REPO_ROOT/tools/$consumer")"
  check_contains "tools/$consumer sources tools/lib/repo-arg-guard.sh" "$csrc" 'lib/repo-arg-guard.sh'
  check_contains "tools/$consumer's <repo> branch calls keel_repo_arg_guard" "$csrc" 'keel_repo_arg_guard "$repo"'
done
check_contains "tools/install-secret-guard.sh's <repo> branch unsets the four vars inline (not sourced)" \
  "$(cat "$REPO_ROOT/tools/install-secret-guard.sh")" 'unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE'

summary
