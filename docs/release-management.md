# Release management — one manager session, gated worker sessions, a whole release

This doc sits in the gap between two docs that already exist. [`docs/delegation.md`](delegation.md)
covers fanning bulk **read-only** analysis out to parallel **subagent** workers behind a file
contract, keeping every gate in your own session. [`docs/parallel-sessions.md`](parallel-sessions.md)
covers the safety mechanics of 2+ sessions against one repo — what a worktree does and does not
isolate, and the failure catalog. Neither covers what a release actually needs: coordinating
**mutating peer sessions** — real design sessions and `/go` runs, each gated on its own — across a whole
release, with one manager session holding the context and the operator's single channel. Read both
docs above before this one; several of the rails below are generic concurrency safety restated for
this one application, and are linked rather than duplicated.

**This is a doc, not a tool.** [`commands/manage-release.md`](../commands/manage-release.md) is a
thin entrypoint over it — a checklist that resolves the release, loads this doc, and runs the loop —
the same split [`docs/drydock.md`](drydock.md) uses for its own procedure-plus-entrypoint shape. The
doc is canonical; the command points at it. *(On an install where the adopter already owns the
`/manage-release` name, `install.sh`'s generic collision-alias mechanism ships this command under the
prefixed name keel-manage-release instead — same file, same behavior, no separate wiring.)*

**Why this exists, and what it does not yet establish.** The shape below was run by hand across
several releases before anything here was written down — one long-lived manager session per release,
worker sessions doing one ticket each, the operator appearing only at decision points. What follows
is the procedure extracted from that practice, not a design done on paper: every numbered requirement
below carries the incident that paid for it. What it does **not** establish is that the pattern is
worth its own cost against a plain per-ticket flow — the cost is unmeasured, which is why R7 below
makes recording it part of every run rather than a one-time study.

## Roles

| Role | Runs as | Model + effort | May touch |
|---|---|---|---|
| **Manager** | your own session, long-lived for the release | top tier, high | every phase, all arbitration, the single channel to the operator, **all** bookkeeping |
| **Worker** | a real, gated session (a design session or a `/go` implementation) — **never a subagent** | mid tier, per ticket | one ticket's worth of the tree, through its own gates |
| **Operator** | human | — | genuine product forks, ticket-filing disputes, merges, the tag, the release, each worker's model/effort selection at launch, and the manager's own launch |

Two things about this table that aren't optional. **Workers are real sessions, not subagents**
(R3) — `docs/delegation.md`'s Mutator row already states why: a subagent that skips your project's
gates isn't a faster mutator, it's an ungated one, and a release is nothing but mutators end to end.
**The manager does all bookkeeping** — backlog markers, ticket filing, the cost line, the wrap — so
that no worker ever needs to know the release's ledger, and losing one worker session costs that
session's own unit of work, never the release's memory of it.

## R1 — intake is bodies plus re-verification, not headings

Read every slate ticket's **body**, and re-verify its claims and line citations against the live tree
before briefing anyone. A release-plan groom that assigns from headings with bodies unread is the
literal failure this rule closes — a real sprint-scope verification pass caught stale line citations
in two tickets that a headings-only read would have shipped as-is. Citations invalidated by an
intervening merge are not a hypothetical: two ticket bodies in one release had exactly this happen
between grooming and pickup.

## R2 — wave plan by file overlap, merges serialized

Cut waves by file overlap, and **assume every PR collides in `CHANGELOG.md` at the `[Unreleased]`
anchor** — every PR across a real ten-PR release did, without exception, which the manager's own
test-file-range check structurally could not see (an insertion point isn't a line range). Merges
serialize as a consequence: one release-manager session, keeping to itself the fact that this is
where mutation actually threads a needle. Show the operator the wave plan before wave 1 starts — the
wave plan is a plan, not a report, and the operator's one intervention here is cheap compared to a
wave already in flight.

## R3 — worker launches, soft form

Where the harness can launch a real, gated session directly, **the manager launches worker sessions
itself**, instead of handing prompts to the operator to paste one by one. Ten of eleven sessions on
one release were launched this way; the manager's own launch stays the operator's, since a manager
launching itself has no operator left to appear as bounded. Two conditions keep this "soft":

- **Every launch is reported to the operator as one status line** on the R6 health channel — a launch
  is not silent just because it no longer needs the operator's fingers.
- **The operator can revoke to manual launching at any time.**

The gates are untouched by who typed the launch: a manager-launched real session passes through the
exact same `/polish`/gate/PR flow a human-launched one would. What
[`docs/delegation.md`](delegation.md)'s Mutator row actually protects is **gatedness**, not who typed
the command that started the session — see the cross-edit at the bottom of this doc's R3 section in
`docs/delegation.md` itself, which now states this exception by name.

**Model recommendations belong at launch, not buried in a brief's tail** — a practice note, not its own
numbered requirement: state the model/effort call as the first line of the launch gesture, since a
recommendation the operator only sees after reading the rest of the brief is one that arrived too late
to change anything.

**Setting the model and effort is always the operator's own gesture on the freshly spawned session —
the manager surfaces the recommendation, it cannot preset it.** What the manager (or anyone launching
in this soft form) *can* and must do is verify: immediately after launch, check the session's actual
model and effort against the recommendation — via harness session metadata where the harness exposes
it, else by asking the operator to confirm — and fold `actual vs. rec` into the same one health-line
report the launch already produces, at zero extra messages. On a mismatch, flag the operator at once,
before the worker spends anything. **This is required, not advisory** —
[`docs/delegation.md`](delegation.md)'s own canonical statement, stated there because it binds any
session that launches a real worker, not only a release manager; this section instantiates it for a
release. A run that skips the check is not hypothetical — two workers came up on a harness default
nobody had asked for, caught only by the operator's own eye after real spend. **The requirement
inherits wherever this R3 soft form is itself adopted by reference** — for example, a
release-candidate audit's Fixer-launch rule that cites this R3 by pointer inherits the verify step
too, with no separate edit needed on that surface.

## The worker brief — one shape, whether launched or handed over

Every worker brief (R3) and every close-checklist starting brief (R9) uses the same five-part shape,
proven live across this pattern's own worker briefs and its audit hand-offs — it is not two
conventions that happen to look similar, it's one convention applied at two points:

1. **State — re-derive, don't reuse.** Every figure in the brief is a sanity check, not a source: name
   the commands the worker re-runs to get its own numbers (`git fetch --prune`, then the project's
   own log/tag commands), not the numbers themselves as fact. [`docs/parallel-sessions.md`](parallel-sessions.md)'s
   "a resumed session's picture is stale" rule is this same rule pointed at a brief's own author.
2. **The slate/coupling table.** For a whole-wave brief: ticket, surface, coupling with siblings. For
   a single-worker brief: the ticket plus the neighboring tickets it touches a file or a question with.
   Either way, the point is naming coupling explicitly rather than trusting a worker to notice it from
   inside its own ticket.
3. **Leads, not findings.** Seams the manager suspects but hasn't verified — numbered, with an
   explicit "expect some of these to be wrong." This is R10's seam duty crossing the handoff: it hands
   a *starting read order*, never a conclusion, and a worker that treats a lead as settled has
   defeated the reason it was marked one.
4. **Rules that bind you — pointers, not paraphrases.** Cite the requirement numbers and one clause
   each; never restate a rule's own reasoning inline, since a paraphrase is exactly what drifts from
   the source the moment either one is edited.
5. **Handed to you.** The line below which every judgment is the worker's own — wave sizing, whether a
   lead is real, anything genuinely open. Everything *above* that line is decided; everything *below*
   it is not, and the line itself is what keeps R4's two-way critique from reading as ambiguity about
   who owns what.

Keel's own instance of this shape for a release brief lives at a per-project gitignored path (its own
audit equivalent is named in R9 below); cite your own project's convention there, never a keel-only
absolute path.

## R4 — two-way critique, verbatim from the record

**The manager is not presumed right.** A worker sees the full context of its own ticket — where the
real code, the prose, and the spec disagree — and is expected to push back on both its brief and the
spec that produced it. The manager evaluates that pushback critically, may take it to the operator,
and then decides: the decision is the manager's privilege, doubly so when the brief came from the
operator in the first place. **Last word: the manager. Escalation when the manager is genuinely
unsure: the operator.**

**The canonical warning — the manager's error was in the APPROVAL, not the information, and a
hierarchy without upward review ships exactly this.** A release folded a `force_backup` call into an
`elif` test position. The manager reviewed that shape and cited bash's `set -e` exemption for a
tested command as the reason it was safe — a real exemption, correctly named. What the manager missed
is that suspending `errexit` for a command in test position suspends it for that **function's entire
body**, so the `cp` inside `force_backup` stopped being protected: a `cp` failure (permission denied,
disk full) would no longer abort, execution would fall through to the trailing `echo`, the function
would report success, and the caller would go on to overwrite the adopter's real file believing a
backup existed. A worker's own review caught it, reproduced live against a read-only directory, and
fixed it with an explicit exit-status check rather than ambient `set -e`.

Three things this case establishes that no amount of manager diligence would have on its own: the
error was in the **approval**, not merely in the information cited — a fact was right and its
consequence was wrong; the failure class was already recorded in the manager's own memory before this
run and knowing the class did not prevent applying it wrongly at the moment of decision; and the
failure mode it would have shipped — a never-clobber rail silently overwriting an adopter's file while
reporting a backup — is the exact genre this pattern's own release existed to close. A hierarchy in
which the manager has the last word and no worker reviews upward ships this. That is why R4 is not
etiquette — it is the one rail that catches an approval, not just a fact.

The manager is fallible in ordinary, cheaper ways too, and workers should expect it: a claimed check
slot turned out to be taken because the manager's own grep couldn't see a section-header format it
didn't know to look for; a claimed behavior change for a decline branch didn't exist, disproved by a
single grep from the worker side; a claimed absence of file overlap across a wave's PRs missed the one
collision point (`CHANGELOG.md`'s `[Unreleased]` anchor) that every PR actually hit. None of these are
signs the pattern doesn't work — they're the reason it has a second reviewer built in at all.

## R5 — verify against pushed commits, never a worker's working tree

**A working tree is a torn read.** The manager's habit of verifying claims by reading a worker's
worktree files directly, rather than trusting the report, produced exactly one false discrepancy: a
worker was mid-way through manually splitting its diff into two commits — it had restored two files to
base and was re-applying one half's hunks — and the manager read precisely inside that window, saw the
second half absent, and reported it missing. That state was nobody's intent; it existed for a few
minutes on the way to a real one.

**What kept it cheap was the form of the report, not the read itself.** The manager stated three
possible explanations, said it could not distinguish them from outside, named the two commands that
would settle it, and asked — naming the specific plausible bad case (a recent subagent revert) so the
worker could check its own reflog first. Cost: one exchange. Asserted as a finding instead, it would
have been a false accusation against a session that had done nothing wrong, and the correction would
have cost more than the check.

**The practice this establishes:** verify against a commit — a worker's **pushed** branch head — not
its working tree, which belongs to the worker and is not a stable artifact. When the tree is the only
thing available, report what was observed as an observation, with its alternatives named, never as a
conclusion.

## R6 — transport is a requirement set, never a tool

The channel between manager and worker, and between manager and operator, is described here by what
it must do — **never by naming a specific product**, since the transport that exists today is
incidental and has already broken mid-release once.

- **Self-contained messages.** What to check, what to decide, what changed — never "as I said above."
  The channel queues against each side's own turns rather than preserving order, so a report and a
  review of an earlier report can cross; a message that leans on prior context is unreadable the
  moment that happens. This isn't theoretical — it happened twice in one release with the same
  session, and the self-contained rule is what kept both crossings merely confusing instead of
  actually wrong.
- **Self-healing.** A failed send is not an answer. Attempt another transport before concluding no
  channel exists — "the tool I had is missing" is not the same fact as "no channel exists," and a
  release was nearly derailed by exactly that conflation: a second transport existed the whole time
  and was found only after the operator pushed back on being offered as a courier between two agents.
  **Never propose the operator as a relay** — that converts a tool failure into human labor in the one
  place this pattern exists to remove it.
- **Health reporting, in both directions, as one cheap status line.** The operator must be told the
  transport is up and traffic is flowing, or that it is down and needs a retry — a silent channel and
  a healthy one look identical from the operator's seat, and the whole value of this pattern rests on
  the operator watching one channel instead of several sessions. Know that "send returned success" is
  not "delivered," and "delivered" is not "processed" — a status built on send-status alone reports
  green through exactly the failure it exists to catch. Keep it to one line per health check, not a
  note per message, or the transport chatter eats the low-noise property that's the point.
- **Explicit turn discipline.** Do not restate status while a reply is outstanding — a style rule
  alone will keep paying the crossed-message toll; a project with a facility for it should carry an
  acknowledged token or a sequence number instead. **Queued is not processed, and this needs its own
  countermeasure, not just the style rule above.** A manager amendment sent while a worker is mid-build
  can queue behind that worker's whole build turn and go silently unprocessed for the length of it —
  this happened twice inside one release's own build of this very requirement, each amendment crossing
  the worker's next report before the worker had seen it. The fix is an explicit **per-amendment ACK**:
  treat any brief amendment without an acknowledgment from its recipient as undelivered, and re-send or
  escalate rather than assuming a queued message was read.

## R7 — the cost line

At release close, the manager derives the run's token/cost figure from whatever on-disk usage data
your project already has, reads it against [`docs/loading-and-cost.md`](loading-and-cost.md), and
appends it to the releases cross-run record — the run-record genre audits already have
(`private/audit/RUNS.md` in keel's own instance, gitignored, per-project location for adopters), now
named for releases too. **The manager is expensive by construction: it holds the whole release's
context, which is the same property that makes it useful.** The sharp edge is duration — a release
spanning more than one day, with breaks, means paying full input price on that context repeatedly
instead of reading it from cache, so a single-sitting release and a week-long one have completely
different economics for the same work. This is a real trade against convenience, not a free win, and
recording the figure every run is what eventually lets someone answer whether the trade is worth it —
never asserted from one run's feel.

## R8 — single writer to `BACKLOG.md` during the release

The manager writes every marker and ticket update; workers request writes through it rather than
touching the file themselves. This closes a real race: two writers on one shared, gitignored backlog
file during one release corrupted nothing only because a worker noticed and asked for the rule before
it did.

**This overrides a conforming `/go`'s own claim step.** `/go`'s own instructions have the worker write
its own `⏳ IN FLIGHT` marker directly onto the ticket heading — correct in a standalone run, and a
second writer during a managed release if followed literally. Every worker brief in a managed release
must say explicitly that marker writes route through the manager instead — see the cross-edit at the
bottom of this section in `commands/go.md` itself, which now names this exception rather than leaving
a silent contradiction between the two documents a worker could follow either of.

## R9 — close checklist

Run the project's release-candidate delta audit — keel's own is `/delta-audit <version>` — **before**
cutting the tag, as a structural step rather than a memory a manager has to remember to open. The
worked incident behind this rule: a manager cited its project's own release-readiness doc in tickets
all day without ever opening it, and was saved from tagging with no RC audit at all only by the
operator noticing. Where the entrypoint command doesn't exist yet, fall back to reading the
release-readiness doc directly rather than skipping the step.

**Hand the auditor a starting brief**, in the five-part shape this doc names above under [The worker
brief](#the-worker-brief--one-shape-whether-launched-or-handed-over) — state to re-derive, the range,
the PR→ticket→surface map, the manager's own seam suspicions marked "leads, not findings," and a
"Handed to you" line below which every judgment is the auditor's own. File findings as tickets
promptly rather than only when asked; the non-delegable set is unchanged from
[`docs/delegation.md`](delegation.md) — merges, the release itself, and deletions stay the operator's.

**"The operator's" means paste-and-run, not re-derivation.** Every operator action the manager hands
over — a merge queue, the tag, the release — arrives as a copy-paste-ready command block with the
actual SHAs and versions substituted, re-derived live and never recited from a plan file.

**The release notes are the manager's to write, the operator's to read.** The manager composes the
notes file itself, from the `CHANGELOG.md` section **at the verified GO SHA** (read via the tagged
commit, never a working tree) — the same from-what discipline any changelog-derived artifact needs,
since a stale checkout composing notes from the wrong commit is the exact hazard this guards against.
**On timing:** this composition happens **before** the tag exists, deliberately — a
`--notes-file`-composing tool's "tag not there yet" warning at this point is a known, expected notice
here, not a failure; the point of reading from the pinned GO SHA rather than the working tree is
precisely to replace the staleness hazard that warning is guarding against, one release phase earlier
than where the tool's own warning was written to fire. The operator reviews the composed notes before
running the actual release-publish command — publishing is an irreversible outward action, so the
**read** stays human even though the write no longer does.

## R10 — the seams duty, active not passive

**This is the manager's one irreducible job.** Everything else in this doc is coordination that could
in principle be scripted; this cannot, because the manager is the only participant who sees where two
tickets' surfaces **meet**. For every pair of slate tickets touching one file or one question, ask
whether they answer it identically. On a contradiction, tell the affected workers and propose the
resolution — **don't wait for two PRs to collide.** Real instances from one release: two tickets about
to ship two different answers to what a non-regular target means; an advice string in one ticket
describing behavior a sibling ticket was removing; a guard fixed one function short of its own twin; a
fallback safe in the script that wrote it and unsafe in the script that later reads it; a fix
re-creating duplication a sibling ticket had just removed. None of these were visible from inside one
ticket, and none would have been caught by an ordinary per-PR review — a per-PR reviewer sees one
diff, never the pair. If this doc says nothing else well, it has to say this well.

## R11 — bounded loops everywhere

Every automated cycle in this pattern carries an explicit numeric bound **and** a budget precondition:
max launch retries per worker, max review/fix rounds per PR (per your project's own round-budget
convention, where it ships one), sessions-per-wave fixed at wave-plan time and never grown mid-wave,
and a token-budget check before each wave. **Hitting any bound means stop and escalate to the operator
in one line — never silent continuation, never a silent retry ladder.**

This is load-bearing, not decoration: R3's soft-form launching removes the natural rate limiter a
human typing every launch used to provide, and an unbounded manager reproduces at scale the exact
failure this project's own quota-burn incidents already showed can happen **with** a human in the
loop. Removing the human step without adding an explicit bound trades one risk for a worse one.

## R12 — portability

This pattern has to run against any adopter project, not just the one it was extracted from — using
only shipped conventions:

- **Backlog source** resolved the way a project's own `/go` resolves it.
- **The release slate** is the set of open tickets whose headings carry a `→ <version>` tag — the
  convention a project's own `/backlog` command already reads. A release-plan table or section is
  optional enrichment some projects add on top; never treat it as required infrastructure.
- **No project-specific absolute paths** in the doc or the command — a worked exemplar from one
  project's own instance is cited as an exemplar, never as the only valid location.
- **The run-record/cost-line location (R7) is per-project**, with a sensible default named, not
  hard-coded.

## R13 — the wrap is centralized

**One manager `/wrap` closes the manager and every worker.** Workers never run their own wrap — that
would be a full reconcile-plus-sweep paid once per worker, and an operator step per session, for
material the manager already needs anyway. Instead, every worker's checkpoint report to the manager
must carry its wrap-relevant material inline: findings, lessons, incident signals (a force-push, a
redone command), and draft tickets, self-contained per R6 — nothing wrap-worthy is allowed to live
only in a worker's dying context, because context that dies with the session is gone, not deferred.
The manager, holding every insight from its own session and every worker's, runs one `/wrap` at
release close that folds all of it: the red-flag sweep runs across the whole release's sessions in one
pass, drafts fold once, memory writes land once, and the cost-line record (R7) lands once. The
operator's own wrap surface shrinks to exactly two gestures, total, for an entire release: wrap the
manager, or — when there was no manager and the operator judges a standalone session done — wrap that
session directly.

**Per-session scoring survives centralization by splitting where each half runs.** A project's own
per-session impact score (if it has one) is *derived* from events the session itself counted — only
the session that lived the context can count its own events, so the **counting** stays in each worker,
as a short structured event-count block in its final checkpoint report (tens of tokens against an
already-cached context, orders cheaper than a per-worker wrap). The **scoring** — turning counted
events into a number and writing it to a ledger — centralizes in the manager, since a scoring tool is
typically a pure function over counts and costs nothing in context to run N+1 times. The manager's one
wrap thus produces one score per worker plus its own, each attributed to its own session in the
ledger — a release record that reports one averaged number instead of the per-session list hides
exactly the outlier worker a per-session score exists to surface.

## What this pattern deliberately is not

No daemon, no autonomous release loop, no removal of the operator from decisions. **The routine load
drops; the decision load does not, and gets denser** — a version of this pattern that stops escalating
genuine forks to the operator is a worse pattern, not a better one. The rails above exist to keep the
manager honest about which of those two loads it's actually reducing.

## See also

[`docs/delegation.md`](delegation.md) for the read-only subagent fan-out this pattern deliberately
does not use for mutation, and [`docs/parallel-sessions.md`](parallel-sessions.md) for the generic
concurrency rails (worktree isolation, push-verify, recovery tiers) every worker session in a release
still needs regardless of who launched it. [`docs/drydock.md`](drydock.md) and
[`docs/delta-audit.md`](delta-audit.md) are this same procedure-plus-entrypoint shape applied to
auditing rather than release coordination — worth a look for the file-contract and role-prompt
mechanics this doc leaves to those siblings rather than re-deriving.

This document is subject to its own R4: where a real run's practice disagrees with what's written
here, the correction belongs in this doc, proposed by whoever ran into the disagreement — the same
two-way critique this doc asks of every manager and every worker, applied to itself.
