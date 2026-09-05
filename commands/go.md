---
description: Start a backlog task with minimal context (autonomous, ask only on real forks)
argument-hint: <task-id or one sentence> [scope]
---
Do $ARGUMENTS. Work autonomously: feature branch → tests → PR. Ask only if you hit a real fork that
can't be resolved from the code, the notes, or common sense. **Close through `/polish` where it is
installed** — it *is* the pre-PR pass (simplify, tests, a depth-matched review) and it opens the PR
itself at its last step, so "→ PR" here means invoking it, not a bare `gh pr create`; where its gate is
wired, `gh pr create` is denied until it has run.

**Load only the task's own context — no full onboarding or summaries.** Resolve the project's **backlog
source** the way `/backlog` does: the first that exists of `<path>/BACKLOG.md` (the on-demand backlog a
project splits its `CLAUDE.md` map onto — it lives at the **main checkout root**, so resolve it there
even from a worktree) → the inline open-work section of `<path>/CLAUDE.md`. Then, by argument shape:

- **A task id (`34`, `dir #34`, `#34`)** → find the heading that carries that id and read ONLY that
  section, plus any section it explicitly cross-links (`dir #N`) — not the whole file. **Match the id,
  not one fixed heading format:** a backlog accumulates several over its life (`### 34.`, `### dir #34 —`,
  `### KB.34`), often side by side in the same file. So list the headings (`^### `), then pick the one
  whose id is the one you were given, whatever decorates it — a format miss is indistinguishable from a
  missing ticket, and the not-found rule below would then stop a task that exists.
- **A phrase** → one keyword grep to locate the item; check its status first — it may already be closed
  in a parallel session.
- **Heading / item not found** → say so and stop. Don't invent a task or guess which one was meant — a
  blank beats a wrong guess.

**In-flight check (before picking, after resolving ticket N):** `git fetch --prune`, then scan
`git branch -a` for a live branch already working this ticket — any name carrying `go` and the ticket id
first. Match the *decoration* loosely and the *id* exactly, the same way as the heading above: harnesses
prefix and suffix their own branch names, so `claude/go-issue-34-ab12cd` is the same claim as
`go-34-foo`, but `go-issue-340-…` is a different ticket and must not count — a substring hit fires the
hard STOP below on a ticket nobody has claimed. Then a keyword grep of branch names against the ticket
title. A match means another session is already on it (in progress, not closed — the
"closed in a parallel session" rail above doesn't cover this case).
**STOP: report "in flight on `<branch>`"** and do not re-pick; offer to continue that branch or pick a
different ticket instead. This is advisory, not a lock — two sessions starting in the same minute can
still race, and only sessions running this version of `/go` apply it.

Also skim the project memory for anything the section cross-links.

**Worktree check (first step, before any code):**
Run `git branch --show-current` from the current cwd.

- If the cwd is inside a worktree dir (e.g. `.../worktrees/...`) — you are already on the session's feature
  branch. Do NOT create a branch. Run every git operation (`git add`, `git commit`, `git push`) with an
  explicit `-C <worktree-path>`, or after confirming the shell cwd is the worktree, not the main checkout.
- If the cwd is the main checkout — create a feature branch as usual.

Never rely on the implicit shell cwd as proof of which working tree you are in.

**Claim step (right after cutting/confirming the feature branch):** write `⏳ IN FLIGHT (YYYY-MM-DD,
branch <name>)` onto the ticket's own heading line in the project's backlog file, resolved at the
**main checkout root** (per the `dir #34` worktree rule above). On merge, the closing sweep replaces
this with ✅ (existing convention) — don't leave both markers on the same heading. **Named override
inside a managed release (`dir #367` R8):** the release manager is the single writer to the backlog
file for the whole release — a worker inside a managed release does NOT write this marker itself;
request the write through the manager instead, per your brief. This step as written is the standalone
default. **Come back and
extend this marker** once the next rail decides — `, tests: first` or `, tests: infeasible — <reason>`:
the decision doesn't exist yet at claim time, so writing the field now would leave a placeholder
standing for the ticket's whole life, which is worse than the missing field.

**Acceptance tests first, when the ticket names a done-criterion.** Before writing implementation code,
derive acceptance tests from the ticket's own acceptance/done-criterion (a groomed ticket names one by
contract; others may too) and write them first — show them red, then implement to green, per
`FRAMEWORK.md`'s design-principles rail. Where test-first is genuinely infeasible for this ticket
(pure-wording change, no runnable surface to test against), say so explicitly in one line before
proceeding — an executed decision, never a silent skip.

**Write that decision down twice, and don't call it checked.** In the PR body's test plan —
`tests: first` or `tests: infeasible — <reason>` — which is the copy that outlives the ticket, and on
the claim marker above while the ticket is open, so a parallel session sees it. Why the writing matters:
this rail is in the spirit of `/polish`'s `skipped:<reason>` receipts but has none of the mechanism —
`/go` has no receipt, no gate, no trace, so an autonomous run can skip the tests AND the disclosure with
nothing noticing. Self-reported is the honest status; report it that way, never as gate-checked.
