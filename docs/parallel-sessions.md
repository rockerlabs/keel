# Parallel sessions — keeping two or more agent sessions from colliding

Running two or more agent sessions against the same repository — a few worktrees, several terminal
tabs, a dashboard driving a fleet of them — gives you parallelism. It does not, on its own, give you
safety. The thing that bites is not two sessions editing the same function; a merge handles that fine.
It's one session's repo-wide operation reaching into another session's work: a cleanup pass, a reset, a
stash, run without any idea that something else is in flight.

This sits next to [`getting-started.md`](getting-started.md), which covers setup, and
[`rollout-audit.md`](rollout-audit.md), which checks a pipeline after a model or harness upgrade — this
one is the check for *concurrency*: what to know before you point more than one session at a shared
repo, and what to do the moment two of them collide.

## What a worktree isolates — and what it doesn't

A git worktree gives each session its own checked-out branch and its own working tree — the files a
session edits, and the `HEAD` it's on, don't leak into any other session. That's real isolation, and
it's usually where the safety story stops too early. At minimum, these are **not** isolated per
worktree:

- **The shared `.git` directory.** Every worktree of a checkout shares one object store, one ref
  namespace, and one stash. Another session's `branch -D`, `stash`, or `reset` isn't "somewhere else" —
  it's the same store your session is reading from. (One exception worth knowing up front: `HEAD`'s own
  reflog is per-worktree; a *branch's* reflog is shared — the Recovery tiers section below says what that
  means for finding a peer session's lost work.)
- **Any file symlinked in from outside the tree.** Gitignored project context (a private `CLAUDE.md`,
  a backlog, session notes) is commonly symlinked into every worktree so a fresh session isn't blind.
  Two sessions then write the *same physical file* through two different paths, with no lock between
  them.
- **Any file reached by absolute path.** A command that names a path outside the worktree leaves the
  worktree's protection entirely, whatever the shell's cwd happens to say.
- **Gitignored files that were never linked at all.** A fresh worktree gets a copy, or nothing — an
  edit there doesn't collide with another session, it **strands**: invisible to the main checkout and
  lost the moment the worktree is pruned. The mirror-image failure of the symlink case, same root
  cause — a file git doesn't track has no per-worktree story at all.
- **Shared out-of-tree state keyed by repo.** Lockfiles, sentinels, caches, and scratch files a tool
  keys by repo path rather than by worktree are shared across every session touching that repo, worktree
  or not.

Before trusting a worktree to protect a session, answer three questions about your own repo: *which of
my files are gitignored? which of those are symlinked into a worktree? which tool of mine writes
outside the tree by absolute path?* A yes to any of them is outside worktree protection.

## The failure catalog

Four modes, drawn from independent field reports. Each is a symptom, why worktree isolation didn't cover
it, which rail below would have caught it, and which recovery tier gets you back — the commands
themselves live in the recovery-tiers section, not here.

- **F1 — the confident cleanup.** A parallel session's "clean up the unused files" cleanup pass deleted
  a database migration another session had written three minutes earlier; every session exited green,
  and the loss surfaced only later, recovered from the reflog. Why isolation didn't help: an agent's
  cleanup scope is *the repo*, not its own change-set — nothing about running in a worktree narrows
  "delete what's unused" down to "what I made." Rail: none of the git rails below reach this by
  themselves — the guard is discipline: scope any cleanup pass to your own change-set, never a
  repo-wide sweep. Recovery: preemptive, or the reflog floor.
- **F2 — the shared working-directory wipe.** A second session wiped uncommitted changes out of a
  working directory another session was actively using. Why isolation didn't help: **uncommitted work
  has no owner.** Any session's `checkout`, `clean`, or `stash` reaches it, and losing it leaves no
  reflog entry of its own — a *staged* file can sometimes be pulled back out of the object store with
  `git fsck --lost-found`, but nothing indexes it by name, so treat that as a last resort, not a plan.
  This is the mode that turns "commit early" from hygiene advice into a safety rail. Rail: your own
  worktree, taken before the checkout gets busy. Recovery: preemptive is the only tier that reliably
  helps here.
- **F3 — the reset to the default branch.** A session reset a shared repo to `origin/main` and dropped
  two commits that had already been built and had passing tests; the reflog was the only way back. Why
  isolation didn't help: a session's idea of a "clean slate" is repo-global, not scoped to its own
  branch. Rail: never treat a shared checkout's working tree as disposable. Recovery: the reflog floor.
- **F4 — the silent race on a file outside the tree.** Keel's own case, live and reproducible today:
  gitignored project context symlinked into every worktree, so two sessions edit the same physical file
  through different paths and the second write wins — no error, no conflict, no signal that anything
  happened. Its branch-level sibling is the same mode one layer up: a concurrent session's commits land
  on whatever branch *you* happen to have checked out in a shared checkout, and a later `git push` can
  answer `Everything up-to-date` while your actual work never reached the remote. Rail: your editing
  tool's stale-file refusal, and push-verify. Recovery: your editing tool's own conflict detector for the
  file case; the retroactive tier for the branch case.

## The rails

Five of these already exist in Keel's own rails files — `CORE.md` (loaded every session) and
`FRAMEWORK.md` (read on demand) — linked below, not restated, so a rename on either side breaks the link
instead of drifting silently:

| Rail | Where it lives |
|---|---|
| `git fetch --prune` + `git branch --show-current` before **every** commit | [`CORE.md`](../CORE.md) — *Git — mandatory rails* |
| Never commit or push to the default branch; feature branch → PR → delete | [`CORE.md`](../CORE.md) — *Git — mandatory rails* |
| Force-push only a **named** branch, reconciled with upstream first | [`CORE.md`](../CORE.md) — *Git — mandatory rails* |
| Reconcile first: fetch **before** reading log/PR state, and again before *reporting* status | [`CORE.md`](../CORE.md) — *Before writing code — reconcile first* |
| Worktree discipline: explicit `git -C <worktree-path>`, verify the branch per working copy — the cwd drifts silently | [`FRAMEWORK.md`](../FRAMEWORK.md) — *Worktree discipline* |

The other three aren't stated as a general rail in `CORE.md`, `FRAMEWORK.md`, or elsewhere in `docs/`
yet — they're stated here in full, as this doc's own rails, not links:

- **Push-verify.** `git push` reporting success is not proof the remote has your work. Compare
  `git rev-parse HEAD` against `git rev-parse origin/<branch>` right after every push — this is the rail
  for F4's branch-level sibling above, where the push silently no-ops and looks identical to a real one.
- **A merged branch is spent; a resumed session's picture is stale.** Once a PR has merged, its branch
  is dead — any new commit on it strands, invisible from the default branch. The same staleness hits a
  session resumed after a gap, or one running alongside a parallel session: before adding to a branch,
  fetch and re-read that branch's actual current state rather than trusting what the session remembers
  from when it started.
- **Your editing tool's stale-file refusal is your only conflict detector for files outside git's own
  merge machinery — never route around it.** When a tool refuses to write because the file changed since
  it last read it, that refusal *is* the collision being caught in real time. In Claude Code this is the
  "file modified since read" error; other harnesses raise the equivalent under a different name. Re-read
  the exact region and retry with fresh content — never fall back to a blind append or a shell rewrite to
  route around the refusal, since that skips the one check that just worked and can silently clobber a
  real concurrent write. Keep each edit's match window narrow, so an unrelated change elsewhere in the
  file doesn't force a retry you didn't need.

## Recovery tiers

One shared set, cheapest first — every failure mode above resolves through one of these, and the earlier
you notice, the cheaper the tier.

- **Preemptive.** Before touching a checkout that might be busy, take your own worktree on your own
  branch off the default branch. An order of magnitude cheaper than any of the tiers below, because
  nothing collided yet.
- **Pre-commit.** `git branch --show-current` immediately before any commit or push. On someone else's
  branch: check `git status` first — `reset --hard` below discards uncommitted work exactly like F2's
  `checkout`/`clean`/`stash`, with the same no-reflog-entry loss, so stash anything you find
  (`git stash push -u`) rather than let the reset take it. Then capture your own commits onto a ref —
  `git branch rescue-mine HEAD` — and reset that branch back to the commit before yours with
  `git reset --hard <sha>` (check `git log --oneline` for the actual SHA rather than counting commits
  blindly: a peer's own commit can have landed on the tip after yours). A plain `reset --soft` instead
  would leave your work only staged in the shared checkout's index, not on a ref of its own — the
  peer's next ordinary commit there would silently absorb it. Continue your own work from `rescue-mine`
  in a throwaway worktree instead of switching branches out from under them; pop the stash back for
  whoever it belonged to once you're clear.
- **Retroactive.** Foreign commits have already piled onto your branch — don't push it as-is. Cherry-pick
  only your own SHAs onto a fresh branch cut from a freshly-fetched default branch; rescue any orphaned
  foreign commit onto its own throwaway branch rather than dropping it; re-verify anything you numbered
  against a shared file's *remote* version (`git show origin/<default>:<path>`), since the remote may
  have claimed that number while you weren't looking; finish with push-verify.
- **The floor: `git reflog`.** Name it plainly — it recovered two of the four incidents in the catalog
  above (F1 and F3), it's local-only, and it expires. **Bare `git reflog` reads your own worktree's `HEAD` reflog
  only** — to find commits a *peer* session dropped, check that branch's own reflog instead:
  `git reflog show <branch>`, which every worktree shares. Pair it with `git stash list` and
  `git fsck --lost-found` as the last stop before calling something actually gone.
- **The tier that doesn't exist.** A raced file *outside* git — F4's symlink case — has no reflog and no
  recovery. That's why its rail is prevention, not repair. Say it plainly: there is no undo here, which
  is exactly why the stale-file refusal above is never something to route around.

## The 60-second pre-flight

**Once per session start:**

```bash
git fetch --prune
git worktree add ../my-feature -b my-feature origin/main
```

**Before every commit and push:**

```bash
git fetch --prune
git branch --show-current
git push -u origin HEAD && test "$(git rev-parse HEAD)" = "$(git rev-parse origin/$(git branch --show-current))" && echo "push verified" || echo "PUSH DID NOT LAND"
```

If the branch shown isn't the one you expect, or you see `PUSH DID NOT LAND`, stop and work through the
recovery tiers above before doing anything else.

## What this doc deliberately is not

No daemon, no session manager, no wrapper CLI — the tooling half of "run many agent sessions at once" is
already well covered by other projects. This doc is the other half: the safety rails that hold regardless
of which orchestration tool, if any, you use to launch your sessions.
