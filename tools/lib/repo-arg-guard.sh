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
# The census (tests/test_git_env_guard.sh, dir #647) requires every git-reaching script to carry THIS
# file's unset as an inline line of its own, byte-identical to the one below — this file stays the single
# source of the variable list, and the census compares each script's copy to it at test time. Inline is
# every script's form, not a sourced guard: a missing, unreadable or 0-byte copy of this file is sourced
# silently and leaves the variables set (the reason pipeline-canary.sh once needed a result check after
# its source), and some scripts cannot source tools/lib/ at all (they are copied standalone, or run as
# POSIX sh from a pipe). tools/install-secret-guard.sh was the first to inline it, for the standalone
# reason — its own tests run scratch copies that carry no tools/lib/.
#
# The unset is process-wide: it also reaches every child the script spawns, a check command an operator
# declared included (tools/keel-check.sh's own call-site comment records why that is accepted rather than
# scoped down to the one resolver call — PR #467). The same acceptance now holds for every script the
# census covers.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's). keel_repo_arg_guard's `exit 2`
# on failure does NOT depend on the caller's `set -e` (correction, /code-review max, two independent
# passes): it fires unconditionally as the explicit right-hand side of `||`, the same way the inline
# check it replaces did — identical behavior whether or not the caller has `set -e`, and even from
# inside an `if`/`&&`/`||` (a `set -e`-exempted context, the exact trap class this project's own
# `install-secret-guard.sh:_isg_rollback` comment names for a sibling function). Do not "simplify" this
# to a `return` on the theory that the caller's `set -e` will catch it — a `return` value consumed
# inside any of those exempted contexts would silently swallow the failure instead.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE

# keel_repo_arg_guard REPO — exit 2 with "not a git repo: REPO" (unchanged wording — the exact message
# every caller printed before this file existed) if REPO is not a git repository. The env sanitizing
# that makes this check trustworthy already happened above, at source time, not here.
keel_repo_arg_guard() {
  local repo="$1"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
}
