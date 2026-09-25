---
description: Implement one backlog ticket — readiness-checked, autonomous, ask only on real forks
argument-hint: <task-id, spec path, or one sentence>
effort: high
---
Implement $ARGUMENTS autonomously; ask only at a real fork the code, the notes or common sense cannot
resolve. Load only the task's own context. A defect outside the ticket: record it
in the PR body or a new ticket; do not fix it. A project without git: `<root>` is the project
directory; `inflight-check`, `worktree` and the PR in `close` do not run — except a `⏳` marker not yours
still stops you first; the claim is still written; closing runs step 9's `conform` walk, reported by
hand. `[tag]` → `## Notes`.

**1. resolve.** Backlog source the way `/backlog` resolves it: `<root>/BACKLOG.md`, else the inline
open-work section of `<root>/CLAUDE.md`, where `<root>` is the MAIN checkout — the first entry of
`git worktree list`, also from a worktree.
- A task id (`34`, `dir #34`, `#34`, `KB.34`) → list the `^### ` headings and take the one carrying that
  id, whatever decorates it. [ids]
- A path to an existing `.md` file → the ticket whose `Spec:` line names it; none, or no backlog →
  the file is the ticket, its `Status:` line the heading of steps 2, 4 and 6.
- A phrase → one keyword grep. It names a ticket → continue with that id. It names none (ad-hoc work) →
  say in your first reply that steps 4 and 6 have nothing to act on.
- Not found → say so and stop; never guess.

**2. readiness.** Read the heading's markers against the backlog's legend
(`commands/backlog.md`). First match wins (`⏳` is step 4's):
- `✅` → stop: closed. `⛔ BLOCKED by <ref>` → stop, name the blocker.
- The current grade is unclear (conflicting grades, `📐` beside a lower one) → ask once which holds.
- R0 → stop: not an agent session. R1 → stop: parked; unparking is the operator's call.
- R2 → stop: it needs a design pass first — offer one (/design <id>, harness-provided).
- R3 → proceed; settle the one pre-decision its body names, in-session (a real fork → ask).
- R4 or `📐 SPEC-READY` → proceed. No grade → proceed; say so.
An explicit go-ahead from the operator in chat, or a managed-release brief assigning the ticket,
overrides only R1 and R2 — never `✅`, standing `⛔ BLOCKED`, or R0; name it in your first reply.

**3. read.** ONLY that ticket's section, the sections it cross-links, and its spec: the file its `Spec:`
line names (or a `docs/specs/` file the body names as its spec) — absent from your
worktree (a gitignored spec) → read it at `<root>`. Read only the memory files these name.
Before code, run every `TO VERIFY` the spec assigns to the implementer; one that breaks a
premise the design depends on: stop if fixing it changes a resolved fork or the Acceptance list, else
escape it (step 8) and continue. The spec overrides an older body; what either says about the live code
yields to the code.
Model: compare the ticket's model line (keel: `**Model rec:**`) with this session's tier and effort
where the harness exposes them; running below it → tell the operator once (raise the effort or
relaunch — a session cannot raise its own) and continue.

**4. inflight-check.** `git fetch --prune`. A `⏳` heading naming a live branch that is not yours →
STOP: report "in flight on `<branch>`"; offer to continue it or pick another. Fallback for an unclaimed
ticket: scan `git branch -a` for a live branch, not your own — `go` + the id first, decoration loose,
id exact — then a keyword grep of branch names against the title; a match → same stop. A `⏳` heading
whose branch is gone → if its PR merged, stop: done, the heading is stale.

**5. worktree.** Before any code, run `git branch --show-current` (first match wins):
- Default branch, a spent branch (PR merged), or a DIFFERENT ticket's branch → cut a fresh feature
  branch from the fresh default.
- A worktree's own branch for THIS ticket qualifies unless spent → keep it; create none.
- Any other branch with no commits past the default → keep it; it becomes this ticket's branch.
Re-check at every ticket; run every git write with `git -C <working-tree-path>`.

**6. claim.** Write `⏳ IN FLIGHT (YYYY-MM-DD, branch <name>)` onto the ticket's heading at `<root>`
(spec mode: its `Status:` line, added if absent; closed per the guide); `/wrap`'s closing sweep replaces it with ✅ on merge — never leave both. **Named override
inside a managed release (`dir #367` R8)** — or under any brief that names a single backlog writer: a
worker does NOT write the marker; request it through that writer.
This step as written is the standalone default. Once step 7 decides, extend the marker with
`, tests: first` or `, tests: infeasible — <reason>`. Write main-checkout files by absolute path.
Without git, `<name>` names the ticket.

**7. acceptance-tests.** First load the implementer guide — the `go-guide` skill (`keel-go-guide` if
aliased), else `go-guide.md` beside this file; it runs steps 7–9. Derive acceptance tests from the
ticket's `**Acceptance:**` line or its
spec's (else its done-criterion), write them, show them red, then implement to green (`FRAMEWORK.md`
design principles); no runnable surface → the guide's checklist, still `tests: first`. Record it twice: the PR test plan (`tests: first` / `tests: infeasible — <reason>`) and the claim marker.
Self-reported — like `/polish`'s `skipped:<reason>` receipts, with no receipt, no gate.

**8. escapes.** A ticket with a spec file: before closing, append one line to the end of the spec —
`Escapes at implementation (YYYY-MM-DD, <branch>): <n>` (`0` when none), then one line per escape —
and put the same lines in the PR body (or the report); the guide defines an escape. Inside a
managed release the spec write goes through the manager, as the claim does.

**9. conform.** Walk every spec rule by its id and every `**Acceptance:**` item, per the guide; paste
the results into the PR body (or the report); a red check → back to step 7 until green, or
escape if the check itself is wrong. `conform` always runs — the project-agnostic floor.

**10. close.** Close through `/polish` where installed — the pre-PR pass; it opens the PR itself, and
its gate, where wired, denies a bare `gh pr create`. A project whose `CLAUDE.md` records a
direct-to-default carve-out follows that instead. The merge is the operator's. Then report
in the guide's form.

## Notes
- **ids** — backlogs mix heading formats (`### 34.`, `### dir #34 —`, `### KB.34`); a format miss reads
  as a missing ticket and stops a task that exists.
