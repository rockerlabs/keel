#!/usr/bin/env bash
# test_repo_arg_guard_lib.sh — dir #644: sourcing tools/lib/repo-arg-guard.sh unsets GIT_DIR /
# GIT_COMMON_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (and, since dir #661, GIT_OBJECT_DIRECTORY /
# GIT_ALTERNATE_OBJECT_DIRECTORIES / GIT_NAMESPACE), unconditionally, and its `keel_repo_arg_guard` is
# the shared validity gate for a tool that resolves a caller-named <repo> via `git -C "$REPO"`. Before
# this ticket, an inherited value for any of the first four could redirect that first `git -C "$REPO"` call
# — including the validity gate itself — into a different repository than the one named on the command
# line, up to and including making a NON-git $REPO falsely pass as valid (reproduced live, recorded in
# tools/install-secret-guard.sh's own comment at its call site). This pins the unset and the function
# directly, plus that tools/install-read-trace.sh, tools/install-pre-pr-gate.sh and
# tools/install-machine-watch.sh all source this file (tools/pipeline-canary.sh used to, and carries the
# inline unset instead since dir #647; tools/install-secret-guard.sh deliberately does NOT — see its own
# comment for why, and tests/test_secret_guard.sh's own dir #644 block for its coverage).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/repo-arg-guard.sh"
check_file "tools/lib/repo-arg-guard.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- sourcing unsets all seven vars, unconditionally, before any caller does anything else — run in a
# CHILD process: this file already sourced $lib once above (before the export below could pollute
# anything), so re-observing the unset needs a fresh process that sources it AFTER the vars are set.
src_out="$(env GIT_DIR=/should-not-survive GIT_COMMON_DIR=/should-not-survive \
  GIT_WORK_TREE=/should-not-survive GIT_INDEX_FILE=/should-not-survive \
  GIT_OBJECT_DIRECTORY=/should-not-survive GIT_ALTERNATE_OBJECT_DIRECTORIES=/should-not-survive \
  GIT_NAMESPACE=should-not-survive \
  bash -c '. "$1"; printf "GIT_DIR=[%s] GIT_COMMON_DIR=[%s] GIT_WORK_TREE=[%s] GIT_INDEX_FILE=[%s] GIT_OBJECT_DIRECTORY=[%s] GIT_ALTERNATE_OBJECT_DIRECTORIES=[%s] GIT_NAMESPACE=[%s]\n" \
    "${GIT_DIR:-}" "${GIT_COMMON_DIR:-}" "${GIT_WORK_TREE:-}" "${GIT_INDEX_FILE:-}" "${GIT_OBJECT_DIRECTORY:-}" \
    "${GIT_ALTERNATE_OBJECT_DIRECTORIES:-}" "${GIT_NAMESPACE:-}"' _ "$lib")"
check_block_equal "sourcing repo-arg-guard.sh unsets all seven vars unconditionally" \
  "GIT_DIR=[] GIT_COMMON_DIR=[] GIT_WORK_TREE=[] GIT_INDEX_FILE=[] GIT_OBJECT_DIRECTORY=[] GIT_ALTERNATE_OBJECT_DIRECTORIES=[] GIT_NAMESPACE=[]" "$src_out"

# --- keel_repo_arg_guard itself, on a valid repo: succeeds (no exit) --------------------------------
r1="$(new_repo)"
run keel_repo_arg_guard "$r1"
check_status "keel_repo_arg_guard: a valid repo succeeds (exit 0)" 0 "$STATUS"

# --- a non-git repo: exits 2, "not a git repo: <repo>" (unchanged wording), no ambient var can rescue
# it. No child process needed here (unlike the source-time probe above, which genuinely needs a fresh
# process to observe vars set BEFORE sourcing): keel_repo_arg_guard's `exit 2` on failure runs inside
# run()'s own command substitution, which is already a subshell — `exit` there only ends that subshell,
# never this file (verified live, /code-review max), so a plain `run keel_repo_arg_guard ...` is enough.
notrepo="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
run keel_repo_arg_guard "$notrepo"
check_status "keel_repo_arg_guard: a non-git repo exits 2" 2 "$STATUS"
check_contains "keel_repo_arg_guard: names the repo as not a git repo (unchanged wording)" "$OUT" "not a git repo: $notrepo"

# --- the hijack itself: an ambient GIT_DIR naming a REAL repo, present BEFORE the lib is sourced,
# must not make a non-git $REPO pass. This is a DIFFERENT property from the two checks above, and
# genuinely needs the child process + re-source: keel_repo_arg_guard's own unset ran once already, at
# THIS file's own source time (line 20) — calling the function again later, in this same process,
# tests nothing about an ambient var, since there is none left to test against. The real question is
# whether a FRESH process that inherits GIT_DIR from ITS environment is protected once it sources this
# file — i.e. the same property the source-time probe above already established, exercised here
# through the actual validity-gate function rather than a printf.
decoy="$(new_repo)"; git -C "$decoy" commit -q --allow-empty -m init
decoy_gitdir="$(git -C "$decoy" rev-parse --absolute-git-dir)"
run env GIT_DIR="$decoy_gitdir" bash -c '. "$1"; keel_repo_arg_guard "$2"' _ "$lib" "$notrepo"
check_status "keel_repo_arg_guard: an ambient GIT_DIR does not rescue a non-git repo (still exit 2)" 2 "$STATUS"
check_contains "keel_repo_arg_guard: still names it as not a git repo under the ambient hijack" "$OUT" "not a git repo: $notrepo"

# --- consumers: install-read-trace.sh, install-pre-pr-gate.sh and install-machine-watch.sh source this
# file for keel_repo_arg_guard (their <repo> branch calls it); every other script inlines the unset instead
# (dir #647 — tests/test_git_env_guard.sh is the census), and install-secret-guard.sh was the first to
# (it is copied standalone, see its own comment) — asserted here so a future edit that drops either
# doesn't go unnoticed by any test file. One loop, one read per file (each file's content is read once,
# not once per check on it).
for consumer in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
  csrc="$(cat "$REPO_ROOT/tools/$consumer")"
  # The executable source line itself, whole-line — a bare substring would also match the `# shellcheck
  # source=` comment above it, so deleting the actual `. "$here/lib/repo-arg-guard.sh"` stayed green.
  check_status "tools/$consumer sources tools/lib/repo-arg-guard.sh (the source line, not just its comment)" 1 \
    "$(printf '%s\n' "$csrc" | grep -cxF '. "$here/lib/repo-arg-guard.sh"')"
  check_contains "tools/$consumer's <repo> branch calls keel_repo_arg_guard" "$csrc" 'keel_repo_arg_guard "$repo"'
done
isg_src="$(cat "$REPO_ROOT/tools/install-secret-guard.sh")"
check_contains "tools/install-secret-guard.sh unsets the seven vars inline (not sourced), at the top" \
  "$isg_src" 'unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE'
# ...and its validity-check line stays identical (modulo indentation — the two live at different
# nesting depths) to the shared lib's own — the two are duplicated on purpose (install-secret-guard.sh
# must stay copy-standalone). Read directly out of $lib rather than a literal frozen into this test
# (/code-review max, round 2: the first version pinned a hand-typed copy of the line, which caught
# install-secret-guard.sh drifting away from it but NOT keel_repo_arg_guard's own body changing — a
# one-directional pin); this way EITHER file changing without the other breaks this check, not just
# one direction of the drift.
lib_check_line="$(grep -F 'rev-parse --is-inside-work-tree' "$lib")"
lib_check_line="${lib_check_line#"${lib_check_line%%[! ]*}"}"
check_contains "tools/install-secret-guard.sh's validity check matches keel_repo_arg_guard's, verbatim" \
  "$isg_src" "$lib_check_line"

summary
