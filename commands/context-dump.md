# /context-dump

Onboard an existing, undocumented (or thinly-documented) codebase into Keel's structure by actually
**reading the code** — not guessing. For a fresh/empty project, use `/init-project` instead; for a small
or well-documented repo, `/keel-setup`'s shallow README/manifest draft (step 2) is enough. Reach for this
one when the repo is large, undocumented, or grew organically for years: it reads the actual source tree,
not just the front door, and it's the expensive step you pay once so future sessions don't re-scan the
whole project to figure out what's there.

## Preconditions

A project `CLAUDE.md` exists (`/init-project` has run). If `/keel-setup` already ran on this repo this
session, reuse the stack/version facts it already pulled from the manifest instead of re-reading them —
this step only needs to go deeper than that pass, not repeat it.

## Do, in order

1. **Scan in parallel, note the source as you go.** Warn the user this is the expensive step on a very
   large repo before starting. Read entry points, directory structure, the dependency manifest/lockfile,
   and a representative source sample as independent, batched reads — they don't depend on each other, so
   don't crawl them one at a time. Record the file/path behind each fact as it turns up, so citing it in
   step 3 doesn't mean re-opening files already scanned. Establish: real stack + versions (from the
   lockfile, never guessed), the architecture pattern actually in use (not the one stale docs claim), a
   folder-to-responsibility map, and existing reusable pieces (auth, a UID helper, a user repository,
   payment handling — anything a task would otherwise reinvent from scratch).

2. **Draft into the existing structure — don't invent parallel files.** Keel already has a place for each
   of these; fill them, don't create new ones:
   - **Overview / Stack & conventions** in `project-CLAUDE.md` — real versions from the lockfile, the
     architecture + folder map you actually observed.
   - **Roadmap / backlog** — every outdated dependency, dead pattern, or "works but don't copy this" spot
     you noticed goes in as a backlog line tagged `legacy`. This is where a standalone "tech-debt ledger"
     would otherwise live — Keel already has a backlog, so reuse it (single source of truth) instead of a
     second list that can drift from it.
   - **On-demand file**, only once the above pushes `CLAUDE.md` past ~8–10K tokens (`FRAMEWORK.md` →
     "Project context-file structure") — split then, not upfront.

3. **Cite what you found.** Every claim ("uses Postgres 15", "no auth layer exists", "`/api/v1` is dead
   code") needs the file/path noted in step 1 behind it. Couldn't verify something from the code? Mark it
   `<needs confirmation>` instead of guessing.

4. **Report and stop.** Show the diff to `project-CLAUDE.md`, list what you're not confident about, and
   wait for the human to confirm before any of it is treated as fact. Don't commit.

## Guardrails

- **Draft, don't decide** — facts come from the repo; judgment stays the human's.
- **Never invent** a version, a pattern, or a "best practice" the repo doesn't actually show — ask instead.
- **Never clobber** existing `CLAUDE.md` content; merge, don't overwrite.
- **Never commit/push.**
- **One-time-expensive by design** — re-run only when the repo has drifted enough that the drafted facts
  are stale, not every session.
