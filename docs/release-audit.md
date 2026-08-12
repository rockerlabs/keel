# Release audit — the repeatable release-readiness flow

The v0.6.0 campaign (dir #85) invented its own process live: module sweeps, synthesis into tickets,
batching by file-affinity, a model tier per batch, a narrow release-candidate (RC) pass, tail-triage.
Every piece of it worked, but none of it was written down — it existed only in session transcripts, so
the next release would have re-derived all of it from scratch. This doc is that write-up: seven phases,
each carrying the felt incident from v0.6.0 that shaped it, so the next campaign runs off it instead of
reinventing it.

It sits next to [`docs/rollout-audit.md`](rollout-audit.md) (checks a *model/harness upgrade* didn't break
your pipeline) and [`docs/publishing-checklist.md`](publishing-checklist.md) (checks a repo *looks
finished*) — this one is the third leg: checks the *project itself* is ready to tag, code and rails and
docs and drift together, on a cadence of "before every release" rather than "after an upgrade."

## Phase 0 — the state definition the whole flow rests on

*(operator-ratified 2026-08-12 — carried near-verbatim; every phase below is downstream of this
paragraph.)*

> The project's state = what its **green contracts** assert (tests, doctor, public-audit) + the ticket
> ledger. Everything else is unknown-by-design until audited. A review measures the **frontier** of the
> unknown, not the state — its output is new contracts and tickets, never a "quality verdict." Zero
> findings on a fresh full review is unreachable in principle (reviews sample an unbounded expectation
> space; each fix moves the frontier) and is **not** the flow's goal; the reachable targets are: zero
> divergence from recorded contracts, zero known-untracked defects, and low-severity-only findings against
> contracted surfaces (the observed maturity signal: on the gate surface, round 1 found unlock bypasses,
> round 4 found a dead assert in a test). Confidence questions therefore resolve to a checklist — contract
> coverage share (dir #142), last-audit date per surface (this doc), open tickets by severity and target
> (dir #143) — not to another review.

The practical consequence: don't run this flow hoping to reach "zero findings." Run it to move the
frontier and to make the checklist above answerable without re-running anything.

## Phase 1 — module audit sweeps

Split the sweep into independent modules and hand each one a *concrete* rubric — an unscoped "audit
everything" invites a generic style pass, not a targeted one. **Felt incident:** dir #85 ran four modules
(code, rails+commands wording, docs, drift) across three branches and produced 73 findings; the two
modules that shared files (rails wording and drift) were ordered, not parallelized, while the two that
didn't (code and docs) ran independently. Give each module its own file list and defect rubric up front
(dir #85's own per-module table is the template), not a vague scope — that's what let the wording module's
pass avoid reproducing an earlier audit's early false starts, by having the defect classes spelled out
rather than inferred.

## Phase 2 — synthesis: dedupe, file tickets, rank blockers vs. tail up front

Collect every module's findings before filing anything (a genuine barrier — two modules reading the same
rails text can surface the same defect from two angles), dedupe against prior audits' tables, then file.
**Felt incident — the missing step that caused this campaign's mid-flight frustration:** dir #85 filed 20 findings as
tickets without ranking which were release-blocking versus which could tail past the tag — so its own
resolution ended up queuing *all* non-trivial findings ahead of the tag, pushing v0.6.0 out by many
sessions (recorded live in the audit's own operator-fork log). Rank blockers vs. tail **at synthesis
time**, not after the ticket count is already known.

**Triage step (new, closes the gap dir #143 found):** every ticket filed at synthesis time gets a
target-release label in the same motion — append `→ 0.6.1` (or `→ next`) to its heading's status tail per
the convention [`commands/backlog.md`](../commands/backlog.md) step 3b reads and step 6 groups by.
Labeling at filing time is what keeps the tail visible without a retroactive re-read of every ticket the
way v0.6.0's ~20-ticket tail needed.

## Phase 3 — batch by file-affinity

Group filed tickets into batches that touch disjoint files; disjoint batches can run as parallel sessions,
tickets that share a file within a batch fold into one launch prompt instead of racing each other's
commits. **Felt incident:** this is exactly how v0.6.0's own tail was worked — one batch touching only
`commands/polish.md`, one touching only the installer/doctor surface, one touching only the
CHANGELOG/backlog drift-check surface, one touching only this document's own tickets — four disjoint
batches, each closable independently, none of them stepping on another's commits.

## Phase 4 — per-batch model tier

Match the model tier to what the batch actually asks for, not one tier for the whole campaign.
**Felt incident:** dir #85's own model recommendation split the same way — mid-tier + medium for the code
sweep (mechanical, tool-assisted) and every mechanical fix PR, strong model + high effort for the
wording/precedence and drift layers (literal-reading conflict-finding and claim-vs-behavior comparison are
the hard-reasoning parts). Generalized: **mechanics = mid-tier**, **review/wording/drift = high-tier**,
**genuine design forks = top-tier**. (Full rubric: `FRAMEWORK.md`'s "Model & reasoning-effort selection.")

## Phase 5 — review budget

Cap convergence rounds and re-review deltas only, not the whole diff, each round. **Felt incident:** two
v0.6.0 loops ran "fresh full review each round" with no stop rule — one ran roughly seven rounds, another
thirteen — before a delta-review protocol (verify only the fix's own delta, same reviewer carried across
rounds) proved a fraction of the cost per round. Full mechanics, including the zero-findings-in-a-delta-
round termination rule and the per-round trend line: dir #127 — cross-linked here, not restated.

## Phase 6 — RC pass with a narrow, three-point mandate

Run one release-candidate pass late, scoped to exactly three checks, and fix only what's release-critical
inline — everything else is a ticket, not a delay. **Felt incident — the mandate is exactly what v0.6.0's
own RC pass found, generalized:**

1. **Cross-PR seams** — where independently-reviewed PRs disagree at the boundary. Found: dir #134
   (`doctor.sh --install` never learned the `--codex` mode a separate PR shipped) and dir #136
   (`uninstall.sh` has no reverse operation for a hook `install-pre-pr-gate.sh` installs).
2. **Whole-delta stale-phrase sweep** — a comment or count that was true when written, then drifted as
   *other* PRs changed the surface it described. Found: dir #137 (a header comment claims three candidate
   paths, the code checks four) and dir #138 (`commands/polish.md` still says a convergence round writes
   "FOUR steps"; the with-GAP branch writes five).
3. **Residual-ledger check** — does the tree's own record of its known gaps (a drift-detector, a
   known-issues list) still run where the work actually happens? Found: dir #135 (`self/doctor.sh`'s
   backlog heading-drift check is skipped in every worktree and impossible in CI — the exact place v0.6.0's
   own tickets were being closed).

Each of these findings landed in exactly one of the three buckets — the mandate isn't a guess, it's what
an unscoped "review everything again" pass would have taken far longer to reach the same findings by.

## Phase 7 — tag

Follow [`docs/publishing-checklist.md`](publishing-checklist.md) §4 (version tag, GitHub release, stamped
`bootstrap.sh` asset) and carry the tail from phase 2 into the release notes as a **Known issues**
paragraph — don't silently drop what didn't make the cut. **Felt incident:** `CHANGELOG.md`'s `[0.6.0]`
entry does exactly this — a one-paragraph "Known issues" block naming the `--codex` doctor gap, the
`hooksPath`-in-XDG-config blind spot, and the round-budget-less review loop dir #127 exists to fix, each
traceable to a still-open ticket. A release with an unticketed known gap is indistinguishable from a
release nobody checked.

## Deliverable

Log a dated entry in your own review-history log (or equivalent) — surfaces checked per module, the
findings table, the tickets filed — the same durable-record convention dir #85's own run follows. An audit
with no inventory of what it checked reads as "checked everything," even when it didn't.

## See also

- **dir #126** — the two measurable signals for *when to stop reviewing* (new surface touched, class
  exhaustion), which phase 5's review-budget rounds apply on each pass.
- **dir #127** — the review-round budget and delta-review protocol phase 5 hands off to.
- **dir #128** — contract-first for invariant-bearing surfaces and the "sync comment is a missing
  contract" smell; phase 0's green-contracts state definition is this idea applied project-wide.
- [`commands/backlog.md`](../commands/backlog.md) — reads and groups the target-release label phase 2's
  triage step writes.
