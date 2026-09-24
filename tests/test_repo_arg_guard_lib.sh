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
check_block_equal "sourcing repo-arg-guard.sh unsets all four vars unconditionally" \
  "GIT_DIR=[] GIT_COMMON_DIR=[] GIT_WORK_TREE=[] GIT_INDEX_FILE=[]" "$src_out"

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

# --- consumers: pipeline-canary.sh, install-read-trace.sh and install-pre-pr-gate.sh all source this
# file (the source-time unset alone is enough for pipeline-canary.sh, which never resolves a caller-
# named repo); install-secret-guard.sh deliberately inlines the same unset instead (see its own
# comment) — asserted here so a future edit that drops any of these doesn't go unnoticed by any test
# file. One loop, one read per file (each file's content is read once, not once per check on it).
for consumer in pipeline-canary.sh install-read-trace.sh install-pre-pr-gate.sh; do
  csrc="$(cat "$REPO_ROOT/tools/$consumer")"
  check_contains "tools/$consumer sources tools/lib/repo-arg-guard.sh" "$csrc" 'lib/repo-arg-guard.sh'
  [ "$consumer" = pipeline-canary.sh ] ||
    check_contains "tools/$consumer's <repo> branch calls keel_repo_arg_guard" "$csrc" 'keel_repo_arg_guard "$repo"'
done
isg_src="$(cat "$REPO_ROOT/tools/install-secret-guard.sh")"
check_contains "tools/install-secret-guard.sh unsets the four vars inline (not sourced), at the top" \
  "$isg_src" 'unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE'
# ...and its validity-check line stays byte-identical to the shared lib's own — the two are duplicated
# on purpose (install-secret-guard.sh must stay copy-standalone), but nothing else pins them to the
# SAME text, so a future fix to one could silently drift from the other without either test file
# noticing (/code-review max finding).
check_contains "tools/install-secret-guard.sh's validity check matches keel_repo_arg_guard's, verbatim" \
  "$isg_src" 'git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }'

summary
