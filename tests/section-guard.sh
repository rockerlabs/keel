# shellcheck shell=sh
# Keel test-section guard (dir #758) — the FIRST line of any draft test section (a scratch file a session
# writes and sources to try a fixture before it becomes a tests/test_*.sh file):
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
# What it checks is lib.sh's footprint, not one variable (a hand-set SANDBOX proves nothing): the sandbox
# dir exists, HOME is inside it, and `new_repo` and the `git` guard are shell FUNCTIONS (lib.sh defines
# both; `command -v` prints a bare name for a function, a path for a binary). POSIX only — it is sourced
# by whatever shell the session has, and the Bash tool's shell can be zsh, where lib.sh itself never loads.
# `exit`, not `return`: a draft that drops its `|| exit 1` must still stop before its first git call.
# The guard makes no git call. Pinned by tests/test_section_guard.sh.
_section_guard_ok=1
[ -n "${SANDBOX:-}" ] && [ -d "${SANDBOX:-/nonexistent}" ] || _section_guard_ok=0
case "${HOME:-}" in "${SANDBOX:-/nonexistent}"/*) ;; *) _section_guard_ok=0 ;; esac
for _section_guard_fn in new_repo git; do
  [ "$(command -v "$_section_guard_fn" 2>/dev/null)" = "$_section_guard_fn" ] || _section_guard_ok=0
done
if [ "$_section_guard_ok" != 1 ]; then
  printf '%s\n' 'section-guard: tests/lib.sh is not loaded in this shell — refusing to run this test section (dir #758).' \
    '  A section without the sandbox runs `git -C ""` against the repository the shell stands in.' \
    '  Source "<checkout>/tests/lib.sh" || exit 1 first, then this guard; or run the section as a file under tests/.' >&2
  exit 97
fi
unset _section_guard_ok _section_guard_fn
