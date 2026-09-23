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
# incident took (a BARE branch, created with plain `git branch`/`git branch -D` — exactly what dir
# #320's evidence names, and what tests/test_ref_guard.sh's RED scenario reproduces). (The reflog half
# needs no such scoping — HEAD's reflog is PRIVATE per worktree, logs/HEAD lives under
# .git/worktrees/<name>, never the common dir — so tests/run.sh compares it directly, via
# guard_reflog_count below.)
#
# NAMED RESIDUAL LIMIT (found by an independent /code-review high pass on this ticket's own diff,
# empirically reproduced): this scoping trusts CURRENT ownership, not the PROVENANCE of a ref's
# movement — it has no way to tell "a sibling worktree legitimately owns this branch" apart from "a
# fixture bug ran `git worktree add` against the real repo instead of its own sandbox, so its stray
# branch now LOOKS owned too." Both look identical in `git worktree list --porcelain`, and git records
# no operation-attribution to tell them apart. A leak shaped as a bare `git branch` (the historical
# incident's own shape) is still caught; a leak shaped as `git worktree add` — or one that force-moves
# an ALREADY-owned branch's tip via `update-ref` rather than a real commit — is not. Accepting this
# scoping necessarily means accepting that gap: the alternative (not excluding by ownership at all)
# reintroduces constant false trips from this repo's own fleet of concurrent worktree sessions, which
# is the failure mode this file exists to close. Tracked, not silently shipped — see the ticket's own
# checkpoint report for the follow-up.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's). Pure and side-effect-free:
# neither function touches HOME, cwd, or any file outside the repo passed in, so a caller (tests/run.sh
# itself, or a unit test) can source this file directly without pulling in tests/lib.sh's sandbox
# machinery.

# guard_owned_branches REPO_ROOT
# Lists every branch checked out by ANY worktree of the repo at REPO_ROOT, one name per line. No `-u`
# on the sort: every caller (guard_union, or guard_filter_unowned's OWNED_LIST argument) treats this as
# a set already, via an awk membership test or its own sort -u — a branch can be checked out by at
# most one worktree anyway, so there is nothing here to deduplicate.
guard_owned_branches() {
  git -C "$1" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p' | LC_ALL=C sort
}

# guard_refs_snapshot REPO_ROOT
# A "name sha" snapshot of every refs/heads ref in the repo at REPO_ROOT, one per line, explicitly
# sorted. Unlike guard_owned_branches's output (always re-sorted downstream before use), this snapshot
# is compared directly by string EQUALITY between a before- and an after-call (tests/run.sh) — pinning
# the order here, rather than trusting `for-each-ref`'s own default (undocumented, and not guaranteed
# stable across git versions or ref-storage backends such as reftable), is what makes that comparison
# correctness-bearing instead of order-dependent by accident.
guard_refs_snapshot() {
  git -C "$1" for-each-ref refs/heads --format='%(refname:short) %(objectname)' 2>/dev/null | LC_ALL=C sort
}

# guard_union LIST_A LIST_B
# The sorted, deduplicated union of two newline-lists (e.g. two guard_owned_branches snapshots).
guard_union() {
  printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort -u
}

# guard_reflog_count REPO_ROOT
# The number of entries in REPO_ROOT's HEAD reflog, as a plain integer. `git rev-list -g --count HEAD`
# is git's own dedicated form for this (one process, no trailing whitespace to strip), rather than
# `git reflog show HEAD | wc -l | tr -d ' '` (three processes, formatting each entry only to throw it
# away).
guard_reflog_count() {
  git -C "$1" rev-list -g --count HEAD 2>/dev/null
}

# guard_filter_unowned OWNED_LIST REFS_SNAPSHOT
# Excludes OWNED_LIST (one branch name per line, e.g. guard_owned_branches's output) from
# REFS_SNAPSHOT (a "name sha" refs/heads snapshot, e.g. guard_refs_snapshot's output), matching by
# first field. `printf '%s\n' "$1"` always emits at least one line (even for an empty string), so the
# NR==FNR arm always sees OWNED_LIST first regardless of whether it is logically empty — no
# empty-first-file join gotcha here. An empty REFS_SNAPSHOT is handled explicitly (rather than falling
# into the same always-emit-one-line printf): without this, `printf '%s\n' ""` would manufacture one
# synthetic blank line and awk would report it as an "unowned" ref — never observed against the real
# watched checkout (it always has branches), but a real contract wart for a repo with zero local
# branches, which this file's own header invites reuse against.
guard_filter_unowned() {
  [ -z "$2" ] && return 0
  awk 'FNR==NR{owned[$1]=1; next} !($1 in owned)' <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}
