---
description: Wrap up the session — reconcile, then update changelog, backlog, and memory per the knowledge-base convention
---
Wrap up the session per "Project context-file structure" in `FRAMEWORK.md`. If there were no significant
changes — say so and write nothing. All knowledge-base documents are written in English.

**0. Reconcile against git first — before writing any status.** A wrap records *current* state, but the
session's in-context picture goes stale: a merge landed mid-session (or a parallel session moved the default
branch), and a long chat later the model still believes a PR "awaits merge" after it has landed — then
writes that stale status. So BEFORE the steps below: `git fetch --prune`, then read the truth from git, not
session memory — `git log --oneline origin/<default> -5`, and merged-PR state where the repo uses PRs. Set
every status to match git: a merged PR → its item moves to *Recently closed* / the changelog, **never** left
as "waiting on PR".

**1. Changelog** — in the project `CLAUDE.md` `## Changelog`: one line per milestone (`| YYYY-MM-DD | gist |`).
Don't retell details (they live in git/PR); keep only the last few here, older ones in the on-demand archive.

**2. Backlog** — update open items to one line each; mutable state (tests / PR / version) stays here only,
never in memory. **Archive with a cooldown:** a just-closed task goes into a small `## Recently closed`
buffer (≤2 one-liners with ✅), not straight to the archive — a just-closed task often spawns a follow-up.
**Red-flag sweep (P0 "capture is checked"):** scan THIS session for any idea / finding / decision /
loose-end that surfaced but isn't persisted — each becomes a backlog ticket, a promoted rule, a
`LEARNINGS.md` candidate (bump its `[n×]`; promote on the 2nd hit), or an explicit recorded drop. Never end
with floating chat-only ideas (the next session starts cold; the operator forgets); if any remain, flag them
prominently rather than closing silently.

**3. Memory** — only reusable invariants not present in code/git. One file = one topic; update the existing
file, don't spawn duplicates; the index carries a one-line hook, not a copy of the content.

**4. Footprint & drift-guard** — estimate `CLAUDE.md` size (or run `tools/doctor.sh <project>`); if it
outgrew ~8–10K tokens, propose moving the on-demand tier out (the **demote** signal). Mirror half — the
**promote** signal: did the session hit a *retrieval miss* (had to hunt for a fact that should have been
always-loaded, or drowned in noise)? If so, lift that fact into the right tier. When placing always-loaded
content, prefer cache-stability over raw minimality (P3): keep churning/mutable content behind an on-demand
pointer so the cached startup prefix stays stable.

**5. Writing** — keep edits surgical (parallel sessions can clobber a wholesale rewrite); for a gitignored
file with no git undo, back it up to a temp dir before a mass edit.

**6. Principles check (only if the session surfaced foundational friction)** — if anything contradicted or
strained a principle in `PRINCIPLES.md` (P0–P4 or a named tension), note or revise it there: the cheap
per-session arm of the revision ritual. Most sessions add nothing; skip silently if so.

**7. Persist** — stage the **explicit paths** this session changed (never `git add -A` in a shared
knowledge-base repo — it sweeps a sibling's in-flight work under your commit), re-run `git status` /
`git diff --staged` and confirm the staged set matches your commit message, then commit. The `secret-guard`
hook scans automatically on commit/push, so there's no manual scan step. Push, then **verify the push
landed** — `git push` returned 0 AND `git rev-parse HEAD` equals `git rev-parse origin/<default>` — if not,
the backup did NOT land (offline / auth / rejected): STOP and report it, don't claim it's backed up. For a
project that uses PRs, follow the feature-branch → PR flow instead of committing to the default branch.
