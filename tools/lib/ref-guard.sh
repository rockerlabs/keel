# shellcheck shell=bash
# tools/lib/ref-guard.sh (dir #333) — the refs/heads ownership-scoping helpers for tests/run.sh's
# real-checkout corruption canary (dir #318).
#
# dir #318's before/after compare (branch/HEAD/status) cannot see the two channels dir #320's own
# leak was actually found through: a stray BRANCH left behind in the real repo, or a REFLOG entry
# appended without moving HEAD (the 14 fixture branches that motivated dir #318, and the incident's
# own comment: found "once via `git reflog`"). A naive `git for-each-ref refs/heads` before/after
# snapshot would add the branch channel, but refs/heads lives in the git COMMON dir — shared by every
# worktree of a checkout — and this repo runs a whole fleet of them concurrently. A sibling session
# branching or deleting ITS OWN branch mid-run is ordinary concurrent work, not a leak from the suite
# whose canary is watching; an unscoped compare would trip on every one of them. These two functions
# let the canary exclude branches any worktree currently owns before comparing: a branch nobody owns
# that still appears, moves, or disappears has no such explanation and is exactly the shape the
# incident took. (The reflog half needs no such scoping — HEAD's reflog is PRIVATE per worktree,
# logs/HEAD lives under .git/worktrees/<name>, never the common dir — so tests/run.sh compares it
# directly, no helper needed.)
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's). Pure and side-effect-free:
# neither function touches HOME, cwd, or any file outside the repo passed in, so a caller (tests/run.sh
# itself, or a unit test) can source this file directly without pulling in tests/lib.sh's sandbox
# machinery.

# guard_owned_branches REPO_ROOT
# Lists every branch checked out by ANY worktree of the repo at REPO_ROOT, one name per line, sorted.
guard_owned_branches() {
  git -C "$1" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p' | LC_ALL=C sort -u
}

# guard_filter_unowned OWNED_LIST REFS_SNAPSHOT
# Excludes OWNED_LIST (one branch name per line, e.g. guard_owned_branches's output) from
# REFS_SNAPSHOT (a "name sha" refs/heads snapshot, e.g.
# `git for-each-ref refs/heads --format='%(refname:short) %(objectname)'`), matching by first field.
# `printf '%s\n' "$1"` always emits at least one line (even for an empty string), so the NR==FNR arm
# always sees OWNED_LIST first regardless of whether it is logically empty — no empty-first-file join
# gotcha here.
guard_filter_unowned() {
  awk 'FNR==NR{owned[$1]=1; next} !($1 in owned)' <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}
