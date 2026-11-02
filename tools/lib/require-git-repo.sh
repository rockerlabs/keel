# shellcheck shell=bash
# tools/lib/require-git-repo.sh (dir #591) — the ONE "is DIR a git checkout?" check, shared by every
# tool that must refuse a non-checkout up front instead of letting git abort later with its own raw,
# unlabeled `fatal: not a git repository`.
#
# Before this file each tool hand-rolled the check, and the copies had drifted into three different
# shapes, two of them subtly wrong (found by dir #240's review of tools/self/prose-drift.sh):
#   - an exit-status-only `git rev-parse --is-inside-work-tree`: that exits 0 and PRINTS "false" for a
#     bare repository (and for a path inside a `.git` dir), so a bare repo passed a gate whose callers
#     all need a work tree and went on to a silent, empty `git ls-files` scan;
#   - the output-checked variant assigned bare (`out="$(git ...)"`): under the caller's `set -e` a
#     failing git aborts the script silently on that assignment, before any labelled message prints.
# Both are fixed here once. The check reads git's STDOUT ("true"), never the exit status alone, and
# every function below is safe under `set -e`: nothing here aborts the caller, and the only `exit` is
# the explicit one in keel_require_git_work_tree.
#
# The env sanitizing that makes the check trustworthy (an inherited GIT_DIR redirects `git -C "$dir"` into
# another repository) is NOT done here: a lib-level unset changes every sourcer's behaviour (tests/
# test_git_env_guard.sh B5). Every script that sources this file already carries the inline unset line.
#
# Sourced, not executed — no shebang requirement, no `set -e` (inherits the caller's).
#
# keel_is_git_work_tree [DIR] — 0 iff DIR (default: cwd) is inside a git WORK TREE; 1 otherwise (not a
# repository, a bare repository, git cannot read it). Quiet. Use as `keel_is_git_work_tree "$d" || ...`
# or `if ! keel_is_git_work_tree "$d"; then`.
keel_is_git_work_tree() {
  local out
  out="$(git -C "${1:-.}" rev-parse --is-inside-work-tree 2>/dev/null)" || return 1
  [ "$out" = true ]
}

# keel_is_git_repo [DIR] — 0 iff DIR (default: cwd) is inside ANY git repository, a bare one included.
# For a tool that works from the git directory alone (branch listing), where a work tree is not required.
keel_is_git_repo() {
  git -C "${1:-.}" rev-parse --git-dir >/dev/null 2>&1 || return 1
}

# keel_require_git_work_tree DIR LABEL MESSAGE [EXIT_CODE] — return when DIR is a git work tree; else print
# one line to stderr and `exit` EXIT_CODE (default 2). The line is `LABEL: MESSAGE`, or just `MESSAGE` when
# LABEL is empty — except when git itself says the repository is "dubious ownership" (this project's
# documented Alpine/Docker CI trap): that is a different failure from "not a git repository" and sending a
# session to investigate the wrong one costs a round-trip, so git's own diagnostic goes through verbatim
# in MESSAGE's place. The `exit` is explicit and does not depend on the caller's `set -e`, so it holds
# from inside an `if`/`&&`/`||` context too — do not "simplify" it to a `return`.
keel_require_git_work_tree() {
  local dir="$1" label="$2" message="$3" rc="${4:-2}" diag
  keel_is_git_work_tree "$dir" && return 0
  diag="$(git -C "$dir" rev-parse --is-inside-work-tree 2>&1 || true)"
  case "$diag" in *"dubious ownership"*) message="$diag" ;; esac
  if [ -n "$label" ]; then echo "$label: $message" >&2; else echo "$message" >&2; fi
  exit "$rc"
}
