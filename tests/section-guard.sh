# shellcheck shell=sh
# Keel test-section guard (dir #758) — the line right after the `lib.sh` source line of any draft test
# section (a scratch file a session writes and sources to try a fixture before it becomes a tests/test_*.sh
# file); the guard comes before the draft's first fixture or git call:
#
#   . "<checkout>/tests/section-guard.sh" || exit 1
#
# It exits the shell when tests/lib.sh's sandbox is not loaded, before the draft's first git call. Why it
# exists: a draft sourced with no lib.sh has no `new_repo`, so `r=""` and the fixture's `git -C "$r" …`
# reads `-C ""` as "stay in the current directory" and writes the repository the shell stands in — felt
# in 0.15.0, a `[diff]` section in the MAIN checkout's shared .git/config broke git in every worktree.
# dir #658's `git()` guard refuses an empty `-C`, but it lives in lib.sh, so it protects nothing a file
# that never loaded lib.sh runs.
#
# A real tests/test_*.sh does not need this: it sources lib.sh itself, fail-closed (dir #627).
# Load lib.sh first in the same shell, then this guard:
#   . "<checkout>/tests/lib.sh" || exit 1
#   . "<checkout>/tests/section-guard.sh" || exit 1
#
# What it checks is lib.sh's footprint, not one variable (a hand-set SANDBOX proves nothing): the shell is
# bash (lib.sh is bash — under zsh it half-loads, prints "BASH_SOURCE[0]: parameter not set", still returns
# 0, and leaves REPO_ROOT at the cwd's parent, so a zsh draft is refused outright), the sandbox dir exists,
# HOME is inside it, and `new_repo` and the `git` guard are shell FUNCTIONS (lib.sh defines both;
# `command -v` prints a bare name for a function, a path for a binary). The check itself is POSIX shell, so
# a non-bash shell can run it to refuse. A floor against the forgotten line, not a defence against
# deliberate fakery: a draft that defines its own `new_repo` and `git` stubs and sets SANDBOX by hand passes.
# `exit`, not `return`: a draft that drops its `|| exit 1` must still stop before its first git call.
# The guard makes no git call. Pinned by tests/test_section_guard.sh.
_section_guard_ok=1
[ -n "${BASH_VERSION:-}" ] || _section_guard_ok=0
[ -n "${SANDBOX:-}" ] && [ -d "${SANDBOX:-/nonexistent}" ] || _section_guard_ok=0
case "${HOME:-}" in "${SANDBOX:-/nonexistent}"/*) ;; *) _section_guard_ok=0 ;; esac
for _section_guard_fn in new_repo git; do
  [ "$(command -v "$_section_guard_fn" 2>/dev/null)" = "$_section_guard_fn" ] || _section_guard_ok=0
done
if [ "$_section_guard_ok" != 1 ]; then
  printf '%s\n' 'section-guard: tests/lib.sh is not loaded in this shell — refusing to run this test section (dir #758).' \
    '  A section without the sandbox runs `git -C ""` against the repository the shell stands in.' >&2
  if [ -n "${BASH_VERSION:-}" ]; then
    printf '%s\n' '  Source "<checkout>/tests/lib.sh" || exit 1 before this guard.' >&2
  else
    printf '%s\n' '  This shell is not bash (lib.sh is bash, and half-loads elsewhere): run the draft as a file under bash.' >&2
  fi
  exit 97
fi
unset _section_guard_ok _section_guard_fn
