---
description: Start a backlog task with minimal context (autonomous, ask only on real forks)
argument-hint: <task-id or one sentence> [scope]
---
Do $ARGUMENTS. Work autonomously: feature branch → tests → PR. Ask only if you hit a real fork that
can't be resolved from the code, the notes, or common sense.

**Load only the task's own context — no full onboarding or summaries.** Resolve the project's **backlog
source** the way `/backlog` does: the first that exists of `<path>/BACKLOG.md` (the on-demand backlog a
project splits its `CLAUDE.md` map onto — it lives at the **main checkout root**, so resolve it there
even from a worktree) → the inline open-work section of `<path>/CLAUDE.md`. Then, by argument shape:

- **A task id (`34`, `dir #34`, `#34`)** → grep the source for the heading `^### 34\.` and read ONLY that
  section, plus any section it explicitly cross-links (`dir #N`) — not the whole file.
- **A phrase** → one keyword grep to locate the item; check its status first — it may already be closed
  in a parallel session.
- **Heading / item not found** → say so and stop. Don't invent a task or guess which one was meant — a
  blank beats a wrong guess.

Also skim the project memory for anything the section cross-links.

**Worktree check (first step, before any code):**
Run `git branch --show-current` from the current cwd.

- If the cwd is inside a worktree dir (e.g. `.../worktrees/...`) — you are already on the session's feature
  branch. Do NOT create a branch. Run every git operation (`git add`, `git commit`, `git push`) with an
  explicit `-C <worktree-path>`, or after confirming the shell cwd is the worktree, not the main checkout.
- If the cwd is the main checkout — create a feature branch as usual.

Never rely on the implicit shell cwd as proof of which working tree you are in.
