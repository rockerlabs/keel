---
description: Implement one backlog ticket — readiness-checked, autonomous, ask only on real forks
argument-hint: <task-id or one sentence> [scope]
---
Implement $ARGUMENTS autonomously; ask only at a real fork the code, the notes or common sense cannot
resolve. Load only the task's own context — no full onboarding. `[tag]` → Notes.

**1. resolve.** Backlog source the way `/backlog` resolves it: `<root>/BACKLOG.md`, else the inline
open-work section of `<root>/CLAUDE.md`, where `<root>` is the MAIN checkout — the first entry of
`git worktree list`, also from a worktree.
- A task id (`34`, `dir #34`, `#34`, `KB.34`) → list the `^### ` headings and take the one carrying that
  id, whatever decorates it. [ids]
- A phrase → one keyword grep; check the item's status first. It names a ticket → continue with that
  id. It names none (an external queue, ad-hoc work) → say in your first reply that steps 4 and 6 have
  nothing to act on — no collision guard runs.
- Not found → say so and stop; never guess.

**2. readiness.** Read the heading's markers against the backlog's legend (keel's:
`commands/backlog.md`). First match wins (`⏳` is step 4's):
- `✅` → stop: closed. `⛔ BLOCKED by <ref>` → stop, name the blocker.
- The current grade is unclear (conflicting grades, `📐` beside a lower one) → ask once which holds.
- R0 → stop: not an agent session. R1 → stop: parked; unparking is the operator's call.
- R2 → stop: it needs a design pass first — offer one (/design <id>, harness-provided).
- R3 → proceed; settle its one pre-decision in-session (a real fork → ask).
- R4 or `📐 SPEC-READY` → proceed. No grade → proceed; say so.
An explicit go-ahead from the operator in chat, or a managed-release brief assigning the ticket,
overrides a stop in this step; name it in your first reply.

**3. read.** ONLY that ticket's section, the sections it cross-links, and its spec: the file its `Spec:`
line names (or a `docs/specs/` file the body names as its spec), relative to the project root — absent
from your worktree (a gitignored spec) → read it at `<root>`. Skim project memory for what they
cross-link. Before code, run every `TO VERIFY` the spec assigns to the implementer; one that breaks a
premise the design depends on → stop and report. The spec overrides an older body; what either says
about the live code yields to the code. [reconcile]
Model: compare the ticket's model line (keel: `**Model rec:**`) with this session's tier and effort
where the harness exposes them; a mismatch → tell the operator once and continue.

**4. inflight-check.** `git fetch --prune`, then scan `git branch -a` for a live branch, not your own:
a name carrying `go` and the id first — decoration loose, id exact (`claude/go-issue-34-ab12cd` claims
34; `go-issue-340-…` does not) — then a keyword grep of branch names against the title. A match → STOP:
report "in flight on `<branch>`"; offer to continue it or pick another. A `⏳` heading whose branch is
gone → if its PR merged, stop: done, the heading is stale. [advisory]

**5. worktree.** Before any code, run `git branch --show-current`. On the default branch, a spent
branch (PR merged), or a DIFFERENT ticket's branch → cut a fresh feature branch from the fresh default. A
worktree's own branch for this ticket qualifies unless spent — create none. Re-check at every ticket; run
every git write with `git -C <working-tree-path>`. More: `FRAMEWORK.md` "Worktree
discipline"; with parallel sessions, `docs/parallel-sessions.md`.

**6. claim.** Write `⏳ IN FLIGHT (YYYY-MM-DD, branch <name>)` onto the ticket's heading in the backlog
at `<root>`; `/wrap`'s closing sweep replaces it with ✅ on merge — never leave both. **Named override
inside a managed release (`dir #367` R8)** — or under any brief that names a single backlog writer: a
worker does NOT write the marker; request it through that writer, per the brief.
This step as written is the standalone default. Once step 7 decides, extend the marker with
`, tests: first` or `, tests: infeasible — <reason>`. Write main-checkout files by absolute path.

**7. acceptance-tests.** First derive acceptance tests from the ticket's `**Acceptance:**` line or its
spec's (else its done-criterion), write them, show them red, then implement to green (`FRAMEWORK.md`
design principles). Where test-first is genuinely infeasible (no runnable surface), say so in one line
— an executed decision, never a silent skip. Record it twice: the PR test plan (`tests: first` /
`tests: infeasible — <reason>`) and the claim marker. It is self-reported — like `/polish`'s
`skipped:<reason>` receipts in spirit only, with no receipt, no gate, no trace behind it; never report
it as gate-checked.

**8. escapes.** A ticket with a spec file: before closing, append one line to the end of the spec —
`Escapes at implementation (YYYY-MM-DD, <branch>): <n>` (`0` when none), then one line per escape —
and put the same lines in the PR body. An escape is a spec defect you hit: a false premise, a missed
dependency, an undefined path — anything that made you depart from or complete the design. Inside a
managed release the spec write goes through the manager, as the claim does.

**9. close.** Close through `/polish` where installed — the pre-PR pass; it opens the PR itself, and
its gate, where wired, denies a bare `gh pr create`. A project whose `CLAUDE.md` records a
direct-to-default carve-out follows that instead. The merge is the operator's.

## Notes
- **ids** — backlogs mix heading formats (`### 34.`, `### dir #34 —`, `### KB.34`); a format miss reads
  as a missing ticket and stops a task that exists.
- **reconcile** — a spec is a snapshot; code moves after it is written.
- **advisory** — not a lock: two sessions starting the same minute still race.
