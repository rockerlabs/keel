# shellcheck shell=bash
# tools/lib/repo-arg-guard.sh — keel_repo_arg_guard REPO (dir #644): the shared validity gate for a
# tool that resolves a caller-named <repo> positional via `git -C "$REPO"`. An inherited GIT_DIR /
# GIT_COMMON_DIR / GIT_WORK_TREE / GIT_INDEX_FILE in the environment redirects EVERY `git -C "$REPO"`
# call — including this gate itself — into a different repository than the one named on the command
# line: a foreign GIT_DIR alone binds to whatever it points at (git prefers it over -C's path
# resolution for the repo it operates on), and a foreign GIT_DIR paired with a GIT_COMMON_DIR that
# happens to equal a REAL repo's common dir is the sharper case (dir #318 residual N8, measured live
# in E19(c) of docs/specs/318-test-ref-isolation.md): `includeIf.gitdir` patterns key off GIT_DIR, not
# GIT_COMMON_DIR, so that combination is not caught by a git-config-based guard either, and the write
# lands in the real repo even when $REPO on the command line is not a git repository at all. Unsetting
# all four before the first git -C "$REPO" call closes the vector: once unset, -C is the only thing
# left that can select a repo for the rest of this process (and anything it spawns, since unset
# removes the var from the exported environment table, not just this shell's view of it).
#
# Resolver census (0.12.0 release manager, `git grep -n 'git -C "\$repo"' -- tools`): all four of
# tools/pipeline-canary.sh, tools/install-secret-guard.sh, tools/install-read-trace.sh and
# tools/install-pre-pr-gate.sh resolve a `$repo` this way. Two are named residuals, not folded in
# here: tools/pipeline-canary.sh's $repo is always a `mktemp -d` fixture the script creates itself,
# never a caller-supplied path, so it is outside this ticket's "caller-named repo" threat model;
# tools/install-secret-guard.sh is designed to be copied standalone alongside only its sibling
# secret-guard/ dir (its own tests run scratch copies that carry no tools/lib/), so it inlines the
# same two lines instead of gaining a new tools/lib/ dependency — see its own comment at the call
# site. tools/install-read-trace.sh and tools/install-pre-pr-gate.sh share this helper: both already
# depend on tools/lib/ unconditionally (sh-quote.sh).
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's, and the caller's own `set -e`
# is exactly what makes this function's `exit 2` on failure behave the same as the inline check it
# replaces).
#
# keel_repo_arg_guard REPO — unset the four vars, then exit 2 with "not a git repo: REPO" (unchanged
# wording — the exact message all three installers already printed) if REPO is not a git repository.
keel_repo_arg_guard() {
  local repo="$1"
  unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
}
