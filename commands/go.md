---
description: Start a backlog task with minimal context (autonomous, ask only on real forks)
argument-hint: <task-id or one sentence> [scope]
---
Do $ARGUMENTS. Details and notes live in the project `CLAUDE.md` and memory — re-read only the relevant
section, no full onboarding or summaries. Work autonomously: feature branch → tests → PR. Ask only if you
hit a real fork that can't be resolved from the code, the notes, or common sense.

**Worktree check (first step, before any code):**
Run `git branch --show-current` from the current cwd.

- If the cwd is inside a worktree dir (e.g. `.../worktrees/...`) — you are already on the session's feature
  branch. Do NOT create a branch. Run every git operation (`git add`, `git commit`, `git push`) with an
  explicit `-C <worktree-path>`, or after confirming the shell cwd is the worktree, not the main checkout.
- If the cwd is the main checkout — create a feature branch as usual.

Never rely on the implicit shell cwd as proof of which working tree you are in.
