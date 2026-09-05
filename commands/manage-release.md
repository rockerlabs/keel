---
description: Run the release-manager pattern for one release — one manager session, gated worker sessions, a single channel to the operator
argument-hint: <version>
---
You are the **release manager** for `$ARGUMENTS`, per
[`docs/release-management.md`](../docs/release-management.md) — the procedure. This command is a
POINTER and an ordered checklist, never a restatement: the roles, the requirements (R1–R13), and the
worker-brief shape stay in the doc and are adopted by reference. Where this checklist's compression
disagrees with the doc's own text, the doc wins.
(On an install where the adopter already owns the `/manage-release` name, `install.sh`'s generic
collision-alias mechanism places this command under the prefixed name `keel-manage-release` instead —
same file, same behavior.)

**M1 — read the doc, then resolve the release.**
Read [`docs/release-management.md`](../docs/release-management.md) WHOLE before anything else — the
same structural-step rule [`commands/delta-audit.md`](delta-audit.md) applies to its own doc.
Resolve `$ARGUMENTS` against the project's own backlog source (the way
[`commands/go.md`](go.md) resolves it) for open tickets whose headings carry a `→ <version>` tag — a
release-plan table or section, where one exists, is optional enrichment, never the requirement. Not
found → say so and stop; a blank beats a wrong guess.

**M2 — intake (R1).**
Read every slate ticket's BODY and re-verify its claims and line citations against the live tree
before briefing anyone — never assign from headings alone.

**M3 — wave plan (R2).**
Cut waves by file overlap. Assume every PR collides in `CHANGELOG.md` at the `[Unreleased]` anchor —
merges serialize as a consequence. Show the operator the wave plan before wave 1 starts.

**M4 — launch workers (R3), one brief shape (see the doc's worker-brief section), single writer to
the backlog (R8).**
Where the harness can launch a real, gated session directly, launch it yourself — one health-line
report per launch, operator can revoke to manual at any time. State the model/effort call as the
FIRST line of the launch, not the brief's tail. Every brief states explicitly that ticket-marker
writes route through you, not through the worker's own `/go` claim step. Every brief carries: state to
re-derive, the ticket/coupling table, leads-not-findings, rules by pointer not paraphrase, and a
"handed to you" line.

**M5 — two-way critique and verification run throughout (R4, R5).**
You are not presumed right — evaluate worker pushback on its merits, decide, escalate to the operator
only when genuinely unsure. Verify claims against a worker's PUSHED commit, never its working tree;
where only the tree is available, report an observation with alternatives named, never a conclusion.

**M6 — the seams duty is active, not passive (R10).**
For every pair of slate tickets touching one file or one question, ask whether they agree. On a
contradiction, tell the affected workers and propose the resolution before two PRs collide — this is
your one irreducible job.

**M7 — bounded loops, budgeted waves (R11).**
Fixed sessions-per-wave at plan time, a budget check before each wave
([`docs/delegation.md`](../docs/delegation.md)'s session-limit flow), a numeric bound on every retry
and review round. Hitting a bound stops the loop and escalates in one line — never silent retries.

**M8 — close checklist (R9).**
Run your project's release-candidate delta audit — keel's own is `/delta-audit <version>` — before
cutting the tag; fall back to reading the release-readiness doc directly where the entrypoint doesn't
exist yet. Hand the auditor a starting brief in the same five-part shape M4 uses. Compose the release
notes yourself from the `CHANGELOG.md` section at the verified GO SHA, before the tag exists; hand the
operator every remaining action (merge, tag, publish) as one copy-paste-ready command block, re-derived
live. Append the run's cost line (R7) to your project's releases cross-run record.

**M9 — one wrap, at the end (R13).**
Workers never run their own wrap; each checkpoint report carries its wrap-relevant material
(findings, lessons, incident signals, draft tickets) plus a structured event-count block for its own
per-session score, self-contained per R6. You run exactly one `/wrap` at release close, folding all of
it.

**Portability (R12).** Backlog resolved the `/go` way; the slate is the `→ <version>` tag convention;
no project-specific absolute paths — a worked exemplar from one project's own instance is cited as an
exemplar, never a requirement; the cost-line location is per-project.

**What this command is not.** No new procedure — `docs/release-management.md` is the source and stays
the single point of truth; a rewrite here would only drift from it. No subagent orchestration —
workers are real, gated sessions per R3, never subagents; that boundary is
[`docs/delegation.md`](../docs/delegation.md)'s Mutator row, not this command's own invention.

**DELEGATION RUN does not apply to this session** — the manager is the orchestrator, not a delegation
worker, and owns wrap duties for the whole release (R13). Every worker session you launch or brief
DOES carry that line, per its own template in `docs/delegation.md`.
