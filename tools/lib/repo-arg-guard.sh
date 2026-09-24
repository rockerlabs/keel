# shellcheck shell=bash
# tools/lib/repo-arg-guard.sh (dir #644): sourcing this file unsets GIT_DIR / GIT_COMMON_DIR /
# GIT_WORK_TREE / GIT_INDEX_FILE, unconditionally, for the rest of the sourcing process and anything
# it spawns. An inherited value for any of these redirects EVERY `git -C "$X"` call the process makes
# — including a validity gate — into a different repository than the one named on the command line: a
# foreign GIT_DIR alone binds to whatever it points at (git prefers it over -C's path resolution for
# the repo it operates on), and a foreign GIT_DIR paired with a GIT_COMMON_DIR that happens to equal a
# REAL repo's common dir is the sharper case (dir #318 residual N8, measured live in E19(c) of
# docs/specs/318-test-ref-isolation.md): `includeIf.gitdir` patterns key off GIT_DIR, not
# GIT_COMMON_DIR, so that combination is not caught by a git-config-based guard either, and the write
# lands in the real repo even when the path named on the command line is not a git repository at all.
#
# Unconditional at SOURCE time, not inside a function a caller has to remember to invoke at exactly
# the right call site (altitude finding, dir #644's own /simplify pass): a guard gated behind "did
# something call keel_repo_arg_guard yet" is only as strong as every future edit's memory to do so at
# every git-touching branch — the same shape of gap that let dir #318's N8 go unnoticed the first
# time. tests/lib.sh already gets this right (its own unset is the first thing that runs after `set
# -uo pipefail`, load-bearing for every git call the file goes on to make, not just some of them); this
# file gives every OTHER script that sources it the same structural guarantee, for free, by the act of
# sourcing alone.
#
# Resolver census (0.12.0 release manager, `git grep -n 'git -C "\$repo"' -- tools`): all four of
# tools/pipeline-canary.sh, tools/install-secret-guard.sh, tools/install-read-trace.sh and
# tools/install-pre-pr-gate.sh resolve a `$repo` this way — and the vulnerability is about the
# PROCESS'S environment being unsanitized, not about where `$repo`'s value came from, so all four
# source this file (pipeline-canary.sh needs nothing beyond the source line itself: it never takes a
# caller-named repo, but its own fixture-creation calls are exactly as exposed to an inherited
# GIT_DIR/GIT_COMMON_DIR as any resolver this ticket fixes). tools/install-secret-guard.sh is the one
# exception, for an unrelated reason: it is designed to be copied standalone alongside only its
# sibling secret-guard/ dir (its own tests run scratch copies that carry no tools/lib/), so it inlines
# the same unset instead of gaining a new tools/lib/ dependency — see its own comment at the call site.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's, and the caller's own `set -e`
# is exactly what makes keel_repo_arg_guard's `exit 2` on failure behave the same as the inline check
# it replaces).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE

# keel_repo_arg_guard REPO — exit 2 with "not a git repo: REPO" (unchanged wording — the exact message
# every caller printed before this file existed) if REPO is not a git repository. The env sanitizing
# that makes this check trustworthy already happened above, at source time, not here.
keel_repo_arg_guard() {
  local repo="$1"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
}
