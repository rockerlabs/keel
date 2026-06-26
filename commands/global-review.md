---
description: Start a global / cross-project / meta session — review the knowledge base itself or work its meta-backlog
argument-hint: "[a meta-task id or a sentence — omit for a review/survey]"
---
Start a GLOBAL session: cross-project review and edits to the knowledge base itself — the global `CLAUDE.md`
conventions, `FRAMEWORK.md`, the tooling. This is the meta/global counterpart to a per-project task. All
knowledge-base documents are in English; chat stays in the user's language.

Startup (cheap + correct — do NOT re-onboard):
1. Trust the always-loaded layer: the thin global `CLAUDE.md` (safety rails + the map) is already in
   context. The conventions detail lives on demand in `FRAMEWORK.md` and the Projects table in
   `INSTANCE.md` — read those when the task needs them, not wholesale.
2. The project inventory comes from the **Projects table in `INSTANCE.md`**, NOT `ls` — the filesystem is
   full of test dirs and worktree noise. Touch a project's `CLAUDE.md` only when the task needs it.
3. Inspect the knowledge-base repo as the git repo it is: `git -C <knowledge-base-root> remote -v &&
   git -C <knowledge-base-root> status -sb`. Don't probe by guessing directory names — a search miss is a fact about
   your search, not about reality.

Then:
- **No argument → review/survey mode:** reconcile state (Projects table vs reality, the knowledge-base
  repo's git status, open meta items) and run `tools/doctor.sh --registry INSTANCE.md` to audit every
  project in the registry and surface baseline drift. **Principles pass:** re-read the tensions in `PRINCIPLES.md` and confirm each still has an
  enforcement that runs — surface any that drifted to "unenforced — risk" (the deeper, periodic arm of the
  principles revision ritual). Report what stands out and what's next; make no edits without direction.
- **An argument ($ARGUMENTS) → work mode:** do that meta item autonomously. For edits to gitignored files
  with no git undo, back them up first and edit surgically (parallel-session-safe). Persist at the end via
  `/wrap`.

**Persist before closing (red-flag sweep — P0 "capture is checked"):** ticket each surfaced idea/finding
into the backlog, stage workflow insights in `LEARNINGS.md` (promote on recurrence), or record an explicit
drop — never leave them chat-only. Also **prune** `LEARNINGS.md`: drop candidates that neither promoted nor
recurred in ~5 sessions.

Ask only at a real fork that can't be resolved from the conventions, the backlog, or sensible defaults.
