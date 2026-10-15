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
| **Manager** | your own session, long-lived for the release | top tier, high | every phase, all arbitration, the single channel to the operator, **all** bookkeeping, and the merges where the project's policy says so (R14) |
| **Worker** | a real, gated session (a design session or a `/go` implementation) — **never a subagent** | mid tier, per ticket | one ticket's worth of the tree, through its own gates |
| **Operator** | human | — | genuine product forks, ticket-filing disputes, the tag and the release publish, each worker's model/effort selection at launch, the manager's own launch, and the review depth of a train (R14) and of the RC audit — every touchpoint here is a decision, one where a different answer changes what happens next; a touchpoint whose answer is always yes is the manager's |

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

**A body is the whole block, not the heading line.** Resolve a ticket by reading its heading plus every
continuation line down to the next heading. A grep for the heading line drops the indented continuation lines:
one release's manager (and the brief it wrote) resolved bodies that way, and two tickets lost the production
numbers and the absorb list their continuation lines carried, so the design session paid a second fork round
for a read it should never have had to repeat (caught only by that session's own review leg). The brief's
"State" item (below) names the block read, and the project's own `/go` resolution should use the same reader
(keel's is `tools/lib/backlog-blocks.sh`).

**Intake also prices the slate against the budget that actually remains, out loud, before wave 1.**
State two numbers together at intake — the slate's size and the remaining-window figure R11's
token-budget check already obtains (that check is [`docs/delegation.md`](delegation.md)'s session-limit
flow, not a second one this rule invents) — and say which one you are sizing to. The incident: a
17-item release train started on roughly a third of a usage window, hit 2% twice, and paid a pause
snapshot, two cold resumes and a wave held for the quota reset before it could finish; nobody had
decided the slate was worth that, because nobody had put the two numbers next to each other. This is
an intake check, never a cap this doc sets for you — an operator who sees both numbers and chooses
the larger slate has made a real decision, and that choice belongs on the release row as a named risk
rather than as a surprise mid-run.

## R2 — wave plan by file overlap, merges serialized

Cut waves by file overlap — a ticket whose surface is "every file matching X" (a citation sweep, a
rename, a header ratchet) has maximal overlap by construction and sorts **last in its wave** by the
same rule, rebased once at the end rather than once per sibling (one release placed such a sweep
mid-wave and only luck made its collision `CHANGELOG.md` alone; a manual ordering rule, since no
wave-planning tool exists to own it) — and **assume every PR collides in `CHANGELOG.md` at the
`[Unreleased]` anchor, unless the project keeps changelog fragments (keel does, dir #744: a PR adds its own
`changelog.d/` file instead)** — every PR across a real ten-PR release did, without exception, which the
manager's own test-file-range check structurally could not see (an insertion point isn't a line range). Merges
serialize as a consequence (strict up-to-date still forces it): one release-manager session, keeping to itself the fact that this is
where mutation actually threads a needle. Show the operator the wave plan before wave 1 starts — the
wave plan is a plan, not a report, and the operator's one intervention here is cheap compared to a
wave already in flight.

**Strict up-to-date makes every sequential merge cost an Update-branch and a CI cycle (0.16.0).** With a
strict base, merging N clean PRs one by one costs N of those cycles, because each merge moves the base under
the rest. Name that price in the wave plan. Where R14 applies, a wave's ready PRs land as one train (R14): the
serial cost is paid once per train. Where it does not (the project's policy leaves the merge with the
operator), put the train to the operator as a choice, never as a default.

**An integration PR or a train lands several clean PRs at once (0.16.0).** One release landed 19 PRs this way
where serial merging was priced at six to seven hours, and R14 owns the procedure: when a train is cut, how it
is built and reviewed, who merges it. **R5 holds for every constituent**: each head merged is the head its
worker froze and the forge reports, and every head is an ancestor of the branch's tip before the PR opens. The
branch's own fixes ride as separate commits the PR body names, never as edits inside a constituent.

**The operator's Update branch and a worker's rebase race (0.15.0).** Both move the PR head, and once a
worker's `--force-with-lease` replaced a head the button had already merged to an identical tree. So a
`REBASE` message starts with a fetch and a compare of the PR's head with the worker's own; when the trees are
already identical, nothing is pushed. The manager's own `gh pr update-branch` (R14) moves the head the same way
and falls under the same rule.

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

**There are two ways to launch a real worker, and they differ in who can set its model and effort — and
in what must be checked.** A direct launch (`start_session`) takes a `model` and an `effort`, so the
manager presets both at the launch (measured on the 0.14.0 release: every FIX and CUT worker launched
this way ran Sonnet from its first turn). A task chip or any hand-off the operator starts leaves the
setting to the operator, a manual gesture on the freshly spawned session (measured on the same release:
the chips ran Opus on 3 of 6 despite the picker). Either way the manager surfaces the recommendation and
**verifies what is actually running**, never what was requested: [`docs/delegation.md`](delegation.md)
states the launch-time verify rule — check actual model/effort against the recommendation right after
launch, flag a mismatch before the worker spends. That doc also names
which way the un-set default falls (the launcher's own tier — a top-tier manager makes every worker
top-tier by doing nothing), the order to verify in (running-tier evidence before session metadata), and
the hold: the worker sends a hello line and waits for the manager's go message, so a correction costs
nothing. A release's worker brief therefore tells each worker to hello, then stop.
**The verify's read, at the hello and before GO,** follows `docs/delegation.md`'s order: running-tier evidence
first, the commit trailer next (the model a commit's own Co-Authored-By line names as its author), session metadata last, because it
reports what is configured. The running-tier
evidence has two forms: the worker's session log found by its branch (`jq` over the assistant lines'
`.message.model` and `.perTurnEffort`, the branch in `.gitBranch`), which names what ran in each turn, and the
hello's quoted "You are powered by" line, which is true for the turn it was read in and stale after a switch (a
switch lands from the next turn), so after one the manager reads the next turn's log line or asks for a fresh quote.
The signals can all be right about different turns, so a disagreement is an
observation with its two alternatives named (a stale quote, or a configured value that has not taken effect yet),
recorded with both and settled by the log, never a finding against the worker. Felt: two hellos said Opus while
metadata said Sonnet, the manager released them on metadata, and the log showed the hold turn really ran on Opus; on
another release chip workers asked for their actual model quoted the app default they started on, while a metadata
read a minute later already showed the operator's switch. The brief therefore asks for the quote verbatim and the effort as the
metadata reads it now, never a paraphrase from memory.
**This is required, not advisory.** It binds any session that launches a real worker, not only a
release manager; this section instantiates it for a release with two additions of its own: fold `actual vs. rec` into the same one health-line report the launch already produces, at zero extra messages;
and **the requirement inherits wherever this R3 soft form is itself adopted by reference** — for
example, a release-candidate audit's Fixer-launch rule that cites this R3 by pointer inherits the
verify step too, with no separate edit needed on that surface.

**A launch needs a turn the operator started (0.15.0, again 0.16.0).** On Claude Code the harness refuses
`start_session` on a turn that a worker's message began, so a manager that wakes on a worker's report cannot
launch anything overnight, whatever it was told. What worked: launch while the operator is present and
pre-stage the next launches then (a proposal card per worker, or the integration branch's session of R2
started early); give follow-up work to an idle finished author's session through a message, which keeps its
context (the 0.15.0 audit's fix round did exactly this); and list in the wave plan which launches wait for the
operator's next turn, so they are held on purpose and not stalled unnamed. The refusal is the harness's own
rate limit on the launches R11 bounds, so it is worked with, not around.

**The gate keys on who opened the turn, not on who decided.** A turn opened by a peer's message, an automated event
or a subagent's hand-back is refused even when the operator's decision arrived inside it through a question tool
(felt twice on one day in two projects: an overnight RC audit waited for a morning click). So a launch the manager
can make on its own is one made on a turn the operator opened. Any other launch is queued at once as a proposal card
(`initiation: own_initiative`) with one line to the operator, and the next wave's launches are queued BEFORE the
operator leaves. A second launch tool (a task chip) is no fallback to rely on: it vanished mid-session once, and a
missing tool is not a missing channel (R6).

## The worker brief — one shape, whether launched or handed over

Every worker brief (R3) and every close-checklist starting brief (R9) uses the same five-part shape,
proven live across this pattern's own worker briefs and its audit hand-offs — it is not two
conventions that happen to look similar, it's one convention applied at two points:

1. **State — re-derive, don't reuse.** Every figure in the brief is a sanity check, not a source: name
   the commands the worker re-runs to get its own numbers (`git fetch --prune`, then the project's
   own log/tag commands), not the numbers themselves as fact; a ticket the brief names is re-read as its whole
   block, heading plus continuation lines to the next heading (R1), never as the heading line. [`docs/parallel-sessions.md`](parallel-sessions.md)'s
   "a resumed session's picture is stale" rule is this same rule pointed at a brief's own author.
   **The manager's own brief text is a defect surface of its own, independent of staleness.** One
   release produced six text defects from one manager in one run: a PR map missing a PR (which then
   let ~180 lines of executable shell approach single-reader coverage), a file-class label —
   "docs-only" — asserted by hand about a diff that was not, a figure snapshot gone stale between
   measurement and use, a heading decapitated by an edit anchor, a rider contradicting the spec it
   rode on, and a provenance instruction that was already wrong when sent. Every one had the same shape:
   hand-compressed text diverging from the artifact it describes. So: a PR/file map is diffed against
   the tool that derives it before it enters a brief, a file-class label comes from `git diff --stat`
   and the diff's own modes rather than from the author's impression, and any figure carries the
   moment it was measured. Note what the record also shows — every one of those six was caught, and
   each by a *different* party than the last. Cheap machinery beats a more careful author — confirmed
   again the next release, four more propagated figures caught by three different parties (the
   release's own record carries the list). The cut's verification block is the last artifact every
   figure passes through, so a re-derivation there would catch the most. At the cut,
   `tools/self/changelog-claims.sh --section` re-derives the `CHANGELOG.md` section's bound numbers and, under
   `--strict`, makes every other digit number be sourced or dropped (dir #810); the verification block is not,
   yet, and that is the split-off ticket, dir #844.
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
   the source the moment either one is edited. **Include the keep-alive contract verbatim**, in
   whatever wording your project settles on — keel's is "a message that is exactly `ping` gets the
   fixed reply `ok`, zero tool calls." A manager holding several long-running sessions needs a
   liveness probe that costs nothing, and the reason a probe must name its own no-op reply is
   [`docs/token-economy.md`](token-economy.md)'s own sharp edge, not a separate finding: a ping phrased
   as anything status-shaped triggers real turns and re-prices the whole context. Felt here as well —
   a ping sent to an auditor mid-run set off a full status sweep of its own legs. What this rule adds
   is only *where* the contract has to appear: inline in the brief, verbatim, because the receiving
   session never reads this doc. **Include the CI-wait rule beside it**, the same way — keel's wording: "if you wait on CI or any
   external state, wait in ONE backgrounded command and let its completion notify you — `gh pr checks <n> --watch`
   (it ends on its own) or an `until` loop with an iteration cap; the host may have no `timeout` binary (macOS has
   none), so background the watch itself and never wrap it in `timeout` — never a scheduled wakeup, a foreground
   sleep chain or a short-interval monitor; end no turn 'waiting' without a live background task." (Felt in two
   projects: a `timeout …` wrapper exited 127 at once and the wait silently never happened.) On Claude Code the tools to
   name are `ScheduleWakeup` (for loop mode only) and `Monitor`; the bound is R11's, and the cost reason is
   [`docs/token-economy.md`](token-economy.md)'s. **Include the same-turn rule beside them** (dir #832): act on a
   subagent's hand-back in the same turn, and the checkpoint is part of the turn that opens the PR, so that turn never
   ends without it (R11's observed-state clause is the manager's side of the same rule). **Include the R13 `WRAP CENTRALIZED` marker verbatim here too**, for
   the same reason and the same mechanism — a session-end fuse that greps a transcript for a text
   convention cannot see a rule that never made it into the brief (see R13's own text for the exact
   line and the incident that named this requirement). **A brief whose workers run simulator- or
   device-backed tests also carries the "one test device per concurrent session" rule**, by pointer to
   [`docs/delegation.md`](delegation.md)'s rails block — concurrent workers on one booted simulator
   overwrite each other's installed test host (dir #608).
5. **Handed to you.** The line below which every judgment is the worker's own — wave sizing, whether a
   lead is real, anything genuinely open. Everything *above* that line is decided; everything *below*
   it is not, and the line itself is what keeps R4's two-way critique from reading as ambiguity about
   who owns what.

**A fix-round brief carries one more item: a pre-flight convention checklist, not left implicit in
"the repo's own convention."** dir #427's timed profile of RC Fixer E (PR #367) found that a missing
`CHANGELOG.md` entry — caught only after the PR was already open, by the manager's own review — cost
the fix round its entire second half: two more full test-suite reruns, two more amend/push cycles, a
PR-body correction, and a self-caught accuracy error along the way, roughly 11 of the round's 63
minutes. The fix itself was the same size wherever it was caught; catching it before the first push
costs one line read, catching it after costs the tail just described. Name the checklist explicitly
in the fix-round brief itself — a `CHANGELOG.md` entry present and citing the ticket's `dir #<N>` in
full, uncommented, plus whatever else the project's own pre-push gate independently checks.

**The checklist is read from the CI workflow at brief time, never copied from the last brief.** List every check the
workflow file runs, each with its local equivalent or an explicit "CI-only" note, and a cheap pre-push grep for that
check's class where one exists. One release's brief was copied from the one before and listed the linter and the
tests; the workflow's secret-scan job was missing from it, and a test literal shaped like a key failed CI. That scan
reads every commit of the PR, so a later fix commit could not clear it and the branch needed a sanctioned
force-push. The same list serves any brief whose worker opens a PR, not only a fix round's.

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

Three things this case establishes that no amount of manager diligence would have on its own: a fact
was right and its consequence was wrong; the failure class was already recorded in the manager's own
memory before this run and knowing the class did not prevent applying it wrongly at the moment of
decision; and the failure mode it would have shipped — a never-clobber rail silently overwriting an
adopter's file while reporting a backup — is the exact genre this pattern's own release existed to
close. That is why R4 is not etiquette — it is the one rail that catches an approval, not just a fact.

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
  the worker's next report before the worker had seen it. The fix is the same acknowledged-token
  facility named above, applied per amendment rather than per status update: an explicit **per-amendment ACK** — treat any brief amendment without an acknowledgment from its recipient as undelivered, and re-send or escalate rather than assuming a queued message was read.
  **The ACK gates a merge too (dir #823):** before a worker's merge is released (R14's precondition (c) names this check), compare the
  spec's modification time with the worker's start and require an explicit ACK of every amendment since. One worker
  built a step on the pre-amendment spec while the amendment queued behind its build turn, and the amendment's clauses
  were missing until a clause-by-clause re-read; launching a build in parallel with a design's last review leg costs a
  delta commit for the same reason.
- **Identity at first contact.** The generic rule lives in [`docs/delegation.md`](delegation.md)'s
  launch-time requirements, next to the post-launch model-verify rule it mirrors (same placement as
  R3): every address copied verbatim from the tool's live output, never retyped; the confirmation a
  named operator touchpoint where the harness's namespaces cannot cross-resolve; a worker's refusal on
  an unverifiable identity is correct behaviour, not friction. What a release adds: the manager's FIRST
  message to each worker carries its addresses, and the confirmation paste is counted among the
  release's operator touchpoints (R7's cost line) rather than arriving as a surprise. The felt case was
  a release's own fixer launch — the manager quoted a fabricated address fragment from the wrong
  namespace, and the worker rightly stopped. A later release's first contact quoted a session title
  that changed between two of the manager's own reads, and its briefs quoted a listing-tool name the
  messaging tool does not accept as a key — the session-id-first rule that came out of it is
  delegation.md's now, in that same clause; a release adds only that the brief marks the title
  volatile.
- **Budget the cross-session sends (0.16.0).** The harness caps the messages a session may send to other
  sessions at about ten per operator turn, then holds them until the operator types again. A ten-message
  broadcast spent the whole budget, and the correction sent last was never delivered; overnight the manager
  could receive but not send, so no GO, REBASE or ACK left it. So keep a reserve for those, and put what several
  workers must read in the shared brief file the briefs already point at, then send each worker a one-line
  pointer, instead of spending the budget on a broadcast a file can carry.
- **A manager change is a re-identification (0.16.0).** When the manager's session is replaced (its context
  is full), the outgoing manager writes a handover file: the ledger's location, each live worker's token,
  session id and task, the open PRs, the operator decisions still in force, and the tooling. The incoming one
  updates the manager's session id in the shared brief, then sends each live worker one line carrying its token
  and the new id, under the same ACK rule as any amendment. Workers report to the id in their brief, so until
  they are told, they report to a session that no longer reads. **The incoming manager also re-verifies the
  hand-off's tooling and environment claims** (keys, access, which tools exist) **with a probe before relying on
  them**, as it re-derives the hand-off's figures: one hand-off said a restart of the app would hand the agent sessions
  the new keys, and on that machine desktop sessions never inherit secrets by design. The successor probed first and
  found the per-command route instead of acting on the claim.

## R7 — the cost line

At release close, the manager derives the run's token/cost figure from whatever on-disk usage data
your project already has — summed at the weights the groom's estimate names (`docs/grooming.md` G5) — reads it against
[`docs/loading-and-cost.md`](loading-and-cost.md), and
**completes** the run's row in the releases cross-run record — **which now exists and has a path**, the
one [`docs/grooming.md`](grooming.md)'s G7 names (keel's own instance: `private/releases/RUNS.md`,
gitignored; per-project for adopters, per G9). **Completes, not creates:** the groom OPENS the row at
G7 with its own measured figures and the plan's estimate, and this role fills the run's own cells at
close, before the tag — a two-stage lifecycle the record has practised for two releases while neither
this rule nor G7 said so, which is how a manager ends up either duplicating a row or leaving the
groom's figures to be retold inside the next one. It is deliberately a DIFFERENT file from the record
audits keep: this rule's scope is the release-management run, the audit record's is the RC pass that
follows it. Until this clause pointed at G7 it named only the audit record, leaving a manager with a
genre and no path. Where the two share a file name (keel's are both `RUNS.md`), the close names this one
by its full path, and the release is not closed while its row still carries the groom's "completes this
at the tag" placeholder: the 0.16.0 manager wrote only the audit row and closed with this row's run
cells empty (the 0.17.0 groom). A rule of the procedure, not a compensation. **The manager is expensive
by construction: it holds the whole release's context, which is the same property that makes it useful.** The sharp edge is duration — a release
spanning more than one day, with breaks, means paying full input price on that context repeatedly
instead of reading it from cache, so a single-sitting release and a week-long one have completely
different economics for the same work. This is a real trade against convenience, not a free win, and
recording the figure every run is what eventually lets someone answer whether the trade is worth it —
never asserted from one run's feel. Where the estimate also names subscription-window points
([`docs/grooming.md`](grooming.md) G5), record beside the figure the points the run moved: the reading
taken before each wave already supplies them, so keep the last reading before each window reset the run
crosses and sum the segments. **Summing at the estimate's weights:** keel's `keel tokens` does it for one session, with
`KEEL_TOKENS_WEIGHTS` setting the estimate's own ([`docs/token-economy.md`](token-economy.md)); a release's
sessions are summed by `tools/self/session-cost.sh weighted`, found by branch as below. Write the weights and the session set beside the figure,
so the next groom can re-sum it.

**Record each worker's branch beside its row in the run's ledger at launch, and at close find its
session log by that branch — never by worktree directory or modification time (0.12.0).** Worktree
names get recycled, so a directory search found nothing and that release left its 23 workers
`unmeasured`. A modification-time window over-counts roughly thirty times, because a log touched
inside the window still carries its whole earlier history. Every transcript records the session's git
branch, and a branch match recovered the workers' cost afterwards. That match is one command:
`tools/self/session-cost.sh manifest <ledger>` turns the ledger's `TICKET<TAB>TIER<TAB>MODEL<TAB>BRANCH`
lines into the manifest, and `weighted` sums it (see [`docs/session-cost.md`](session-cost.md)). A branch
no session records is named, never dropped; fix that before writing the row.

## R8 — single writer to `BACKLOG.md` during the release

The manager writes every marker and ticket update; workers request writes through it rather than
touching the file themselves. This closes a real race: two writers on one shared, gitignored backlog
file during one release corrupted nothing only because a worker noticed and asked for the rule before
it did. **The project's memory directory is the same boundary** — [`docs/delegation.md`](delegation.md)'s
non-delegable set already reserves memory writes to the orchestrator for every delegation pattern —
and this doc adds only the route: a worker's memory-worthy finding rides in its checkpoint report
(R13) and the manager writes it at the single wrap. One release's worker wrote two entries itself;
both were good, and no brief had said where they go.

**The marker's WORD is part of the contract, not the writer's choice (applied 2026-09-20).** The
backlog's mechanisms read a fixed closure vocabulary, not the glyph alone — the 0.10.2 close wrote
`✅ FIXED` on all seventeen fixed headings and every consumer read them as still open. Write a word
the scanner already recognises — read the vocabulary from the scanner's own constant (keel:
`tools/lib/backlog-blocks.sh`'s `BB_CLOSURE_TAG_PATTERN`), never a second, hand-copied list here
(`dir #166`'s sync-drift class: a copy goes stale the next time the scanner widens) — or widen the
scanner in the same PR. `dir #581` is the remover: the scanner learns `FIXED`, and the closing write
is checked against the constant at write time — before writing each closure marker, run
`bash -c 'source tools/lib/backlog-blocks.sh; bb_closure_word_ok "✅ WORD (…)"'` on the exact text;
a non-zero exit means the word is not recognised, and the manager either writes a recognised word or
widens the constant in the same PR — so the next unlisted word is refused there rather than
discovered by the next census.

**A ticket the manager files carries a release tag on its heading, `→ pool` when nothing else fits
(the 0.17.0 groom).** Seven of the 0.16.0 manager's filings had none. The census lists them as
`untagged`, and the pool report counts only `→ pool`, so they sat outside every pool reading until a
groom tagged them. A rule of the procedure, not a compensation.

**This overrides a conforming `/go`'s own claim step.** `/go`'s own instructions have the worker write
its own `⏳ IN FLIGHT` marker directly onto the ticket heading — correct in a standalone run, and a
second writer during a managed release if followed literally. Every worker brief in a managed release
must say explicitly that backlog writes of any kind — a marker, a Log line, a new ticket, a closure — route
through the manager instead — see the cross-edit at the
bottom of this section in `commands/go.md` itself, which now names this exception rather than leaving
a silent contradiction between the two documents a worker could follow either of.

**The single writer needs a checked writer, for filings as much as markers (0.15.0).** A manager's own filing
script opened the backlog for writing before it read it, which empties the file: the backlog was truncated,
and only a backup could restore it. A script that touches
the backlog reads it whole, writes a temp file beside it, refuses when the result is shorter than the
original (a filing only adds), and renames over it; the closure-word check above rides in the same script. One such
writer serves markers, Log lines and new tickets alike. A manager without one writes it before wave 1.

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
"Handed to you" line below which every judgment is the auditor's own. File a finding that clears
[`docs/verification-economics.md`](verification-economics.md) §4's filing bar as a ticket promptly
rather than only when asked — below the bar it's a standing-list line, not a ticket, and a ticket whose
defect a standing line already names takes that line with it (§4)
(a `no-action(1b — …)` finding goes to its guard's known-bypass register instead — [`verification-economics.md`](verification-economics.md) §4); the non-delegable
set is unchanged from [`docs/delegation.md`](delegation.md) — the release itself (the tag, the publish), the
install and deletions stay the operator's; merges are the manager's under R14 where the project's policy allows
(keel does).

**An audit-heavy worker reaches `/polish`'s compaction stop at its fix loop (dir #828).** One RC-audit worker stood at
457k tokens of context at `/polish` step 1 (the threshold then was 250k) after four auditors and a thirteen-commit
fix loop, and a worker cannot type `/compact`: the pause cost a manager-to-operator round trip and a hand-written
hand-over file before the PR could open. R11's stop route is the answer (the worker writes its hand-over file and
sends `COMPACT`, the manager clears it and sends the continuation), so an audit worker's brief says that route
exists. A project without it runs the audit and its finding lists in one session and the fix loop plus `/polish` in a
fresh one started from the ledger.

**The version-identity bump has a named owner before wave 1 (dir #823).** The versioning rule hands the bump to "each
release", and a rule that names no row is carried by nobody: one project found its version key unbumped at the tag
block's derivation with GO already in hand and paid an extra worker session for it; its next release, run without a
manager, wrote "rides in the last PR" into the plan row, but a `/go` brief is built from the ticket's Acceptance and
not from the plan, so the bump went in a PR of its own after the audit. So the groom writes the bump into the last
build ticket's Acceptance (a standalone `/groom` to `/go` chain has no manager to carry it), and a managed release's
intake confirms that one ticket's Acceptance, or the cut, carries it.

**The cut PR can ride on the last fix PR (0.15.0).** Stacked on the final fix PR's branch, the cut gives one
merge for the audit's fix round and the cut together. Stacking changes what the audit's GO
conditions describe: they were established at the fix round's head, so they are restated for the stacked tip
(the fix head plus the cut commits and nothing else) and re-derived there before the merge (or, in R14's
fallback, before the paste block is handed over).

**"The operator's" means paste-and-run, not re-derivation.** Every operator action the manager hands
over — the tag, the release, the install — arrives as a copy-paste-ready command block with the
actual SHAs and versions substituted, re-derived live and never recited from a plan file. A merge is on that
list only as R14's fallback (a project without the policy line, a refused merge, a harness denial: R14 names which
refusals count).

**Where the project has a daily-use location for its build** (an application bundle, a deployed service, a
device install), **the close hands the operator one more paste-and-run block that installs the build from
the verified GO SHA there, and the wrap records the build's own identity string as seen from that
location** (an app: the version and SHA its menu or about box shows; a service: the version line its status endpoint reports). A tag
without that step ships nothing to the person the release was for: one real release was tagged, published
and wrapped while the operator kept running the previous version, the headline fix not actually running.
Where the location is a device the session cannot reach (a tablet installed over a cable tool), the block
is still composed, and the install is one of the operator touchpoints R7 counts.

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

**Rotate a per-cycle instrument's logs AFTER the next groom has read them, never at the tag.** Where
a project keeps a session-scoped log the grooming retro consumes (keel's own is the read trace, whose
rotation the tool's header USED to assign to this role as a wrap-time chore), rotating it at release
close leaves the next groom's retro reading a cycle that is hours old while the one it needs sits in an
archive. The cheapest correct order is: tag, then let the next groom run, then rotate — and since
2026-09-20 the step has an owner on the right side of that order: **the groom runs it at the close of
its G0 retro** ([`docs/grooming.md`](grooming.md) G0, dir #543), and this role runs it never. See that
section for the reading this protects, and its `dir #459` for the alternative fix (teaching the tool to
read a rotated cycle) — one or the other, not both.

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

**A seam plan names its resolution in BOTH merge orders (0.15.0).** The proposed merge order does not bind
whoever merges (the manager's train order, or the operator's in R14's fallback), and once the operator merged
out of it, which flipped a seam: the plan said only what the second PR does after the first, so the PR that
landed first had no instruction. For every seam handed to a worker, write both
branches: if you land first, do this; if the sibling lands first, rebase and re-check that.

**A repo-wide check landing mid-wave is a seam with every in-flight PR (0.16.0).** A new lint over all test
files, merged in a train, turned an in-flight PR red at its Update-branch although the PR had been green:
its new file was the first to be checked. The failure arrives as a red CI on someone else's PR, not as a
conflict, so when such a check lands, tell every in-flight worker in the same hour what it flags and how to
satisfy it.

**The worker's Seams step covers less than the manager's duty does (dir #668).** The step each worker runs
at its close counts changelog figures and newly sourced libraries. Two shapes it does not reach stay manual,
and so stay with the manager's read of each merging PR: a prose fact outside the changelog that a later PR
makes false, and a stale header or list of consumers that omits a new member.

**A seam can be cumulative, not pairwise: a release-wide effect no single PR produces.** One release's
`CHANGELOG.md` grew across ten PRs until the merge commit of one of them crossed a doc-figure floor
the suite pins — foreseeable from a worker's own report of how much its entry added, and not put in
the next brief. When a worker reports a figure that accumulates across the wave, carry the running
total into the next brief with the threshold it approaches.

**A refactor changes the SHAPE of what you count, so a count taken across it is not a check.** The
same release's manager nearly filed two false discrepancies: a bare grep for a function name after
that function had been wrapped (the wrappers absorbed the calls the grep no longer saw), and a
doctor run on a stale base read as a regression. Before comparing two counts, confirm both were taken
against the same shape of the tree; after a refactor, re-derive the counting command, not just the
number. A judgment call by nature — no tool can know which refactor changed what a grep means — so
this stays a manual rule, not a gap a ticket closes.

## R11 — bounded loops everywhere

Every automated cycle in this pattern carries an explicit numeric bound **and** a budget precondition:
max launch retries per worker, max review/fix rounds per PR (per your project's own round-budget
convention, where it ships one), sessions-per-wave fixed at wave-plan time and never grown mid-wave,
and a token-budget check before each wave — [`docs/delegation.md`](delegation.md)'s own session-limit
flow (ask the operator for the live remaining-window percentage, pilot two units spanning the cost
envelope, do the arithmetic before spawning) is that check, not a separate one this pattern invents.
**Hitting any bound means stop and escalate to the operator in one line — never silent continuation,
never a silent retry ladder.**

This is load-bearing, not decoration: R3's soft-form launching removes the natural rate limiter a
human typing every launch used to provide, and an unbounded manager reproduces at scale the exact
failure this project's own quota-burn incidents already showed can happen **with** a human in the
loop. Removing the human step without adding an explicit bound trades one risk for a worse one.

**A worker's row closes on an observed session state, never on a reported one.** Mark a worker done
when its session is actually idle or stopped — the harness's own liveness signal — not when its last
message said it was finishing. The two diverge in exactly the case that costs the most: a worker
wedged on an unguarded poll keeps a live session and sends nothing, so a ledger that reads "in
progress" and a ledger that reads "done" look identical from the manager's side. One release lost two
hours to precisely this, and the wedge was found by the operator's own eye rather than by anything
in the pattern. A row that cannot be closed against an observed state is a row to escalate on, under
this rule's own one-line-stop clause. **The observation is a scheduled sweep in the manager's loop, not
a question the operator asks.** The rule above was written and then not practised: a later release's
design worker sat idle-looking for about five hours holding a completed report that a transport
failure never delivered, and the manager noticed only while answering "what's left?". Sweep every
open row's live state at a fixed point in each loop iteration — before each wave, before each
merge — and treat "idle with no report received" as a row to probe, not a row still working.

**A turn-end note without its deliverable is a probe trigger (dir #832).** Compare every worker's turn-end note with
the deliverable that point in the work owes, and probe at once on a gap: a PR open with no checkpoint, a subagent's
hand-back with no next action. A worker that ends its turn right after a hand-back, or right after opening its PR, looks
identical to a working one, and it happened twice in one release (the fixer, both rounds, about 40 and 60 minutes
idle): the operator noticed the first, the manager's own state sweep the second. The worker's side is the brief's
same-turn rule in the worker brief's "Rules that bind you" item (dir #832).

**The sweep is load-bearing, because a worker's own "waiting" is never evidence (0.16.0).** One release saw
five wedges of this shape (a worker idle with no live background task, waiting on a notification no task could
send, or having ended its turn on a plan) and a lost sub-reviewer whose report never came. The brief already
carried the rule "end no turn waiting without a live background task", and it failed five times anyway; the
sweep found each wedge, the worker none, after an hour or more of idle time. So the sweep is the control, not a
courtesy, and it runs on a wall clock the manager sets. A host that sleeps delays that timer (one fired about
80 minutes late), so after a late wake the first act is a sweep, not a resume. A sub-reviewer that never
reports is probed like any worker; with the reports in hand the worker proceeds and discloses the gap.

**A worker's own stop needs a named blocker (0.16.0).** A worker read a long review loop as a safety signal and
stopped at round six with a serious finding fixed but unreviewed. The convergence rule is a round that finds
nothing serious, so a long loop is a reason to keep reviewing the fixes, and a stop is a named blocker the
worker reports in one line.

**Suite concurrency is a budget too (0.16.0).** The bound on sessions per wave does not bound the machine:
about seven full suites at once at the default cap (the host's CPU count outside CI) put the load average in the hundreds and every suite past
an hour, with timing flakes rising alongside. State a per-worker concurrency cap for the suite in the wave
plan (keel's: `KEEL_TEST_JOBS=2`), and keep a portability-leg container off the machine while the same worker's
suite runs.

**No branch cleanup while a wave runs (0.16.0).** A suite's branch-integrity canary (keel's dir #318) cannot
tell a deliberate cleanup from a leak: four times in one release a peer moving its branch, or a wrap sweep
deleting merged branches, tripped it in a worker's suite, about an hour a time (dir #768 tracks the remover).
So no session runs a branch-cleanup sweep while a wave's suites run — the wrap (R13) does it — and a canary trip is
re-run only after naming the ref that moved.

**A stop that waits for the operator is settled at wave-plan time (0.16.0).** Any step that blocks on the
operator is asked once per wave, and the answer is recorded in the shared brief with its date. Keel's example is
`/polish`'s compaction stop (dir #739), which used to ask the operator for `/compact`: every worker of one wave
reached it at step one within the same hour, and three idled until the operator returned. It no longer waits
(dir #845): the worker commits, writes its hand-over file and sends the manager `COMPACT <token> <absolute
hand-over file>`, then ends its turn; the manager clears that session once it reads idle and sends one self-contained
continuation message — the worker id, its overlay paths, and the call to invoke the `polish` skill with args
`after a compaction stop (dir #739): read <file> first` — which is the continued run. A clear the harness refuses
(a session pinned or open on screen) falls back to the two paste-ready lines for the operator, and the manager
reports the refusal. The threshold and any override are the operator's decision, never raised on the manager's
own authority.

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

This extends [`docs/delegation.md`](delegation.md)'s own `DELEGATION RUN` line — "wrap duties are
centralized... the orchestrator owns all bookkeeping" — from that doc's stateless subagents to the real,
gated sessions this pattern launches, for the same reason: an end-of-session nudge a harness runs will
otherwise steer every session toward its own wrap-style bookkeeping regardless of whether it's a
subagent or a real one. **One manager `/wrap` closes the manager and every worker.** Workers never run
their own wrap — that
would be a full reconcile-plus-sweep paid once per worker, and an operator step per session, for
material the manager already needs anyway. Instead, every worker's checkpoint report to the manager
must carry its wrap-relevant material inline: findings, lessons, incident signals (a force-push, a
redone command), and draft tickets, self-contained per R6 — nothing wrap-worthy is allowed to live
only in a worker's dying context, because context that dies with the session is gone, not deferred.

**Every worker brief must carry a literal marker naming this rule, verbatim, in its "Rules that bind
you" section (dir #431).** `tools/read-trace.sh`'s wrap fuse — the mechanism that catches a mutating
session ending with no `/wrap` — cannot see this rule from the code alone; it greps a session's own
transcript for a text convention, and R13's own workers used to carry none. The result was measured
live: 18 of 18 managed-release workers in the v0.9.0 cycle were flagged `no-wrap`, a 100% false-positive
rate on the one cycle this fuse has ever reported — the exact shape that trains an operator to ignore
the signal entirely. **This is deliberately NOT the `DELEGATION RUN` marker** — that line also forbids
*any* log/backlog/memory write, which R13 workers do not honor (R8 already sanctions a worker's own
pre-brief `BACKLOG.md` write); reusing it here would misrepresent what an R13 worker is actually
allowed to do. Include this line verbatim instead, in every worker brief (R3) and close-checklist
starting brief (R9) this pattern produces, the same way item 4 above already mandates the keep-alive
contract:

> WRAP CENTRALIZED (R13): this session's wrap is owned by the release manager — do not run /wrap;
> wrap-relevant material rides in your checkpoint report.
The manager, holding every insight from its own session and every worker's, runs one `/wrap` at
release close that folds all of it: the red-flag sweep runs across the whole release's sessions in one
pass, drafts fold once, memory writes land once, and the cost-line record (R7) lands once. The
operator's own wrap surface shrinks to exactly two gestures, total, for an entire release: wrap the
manager, or — when there was no manager and the operator judges a standalone session done — wrap that
session directly.

**Per-session scoring survives centralization by splitting where each half runs.** A project's own
per-session impact score (if it has one) is *derived* from events the session itself counted — only
the session that lived the context can count its own events, so the **counting** stays in each worker,
as its cited events in its final checkpoint report (kind, then one cite line per event; tens of tokens against an
already-cached context, orders cheaper than a per-worker wrap). The **scoring** — turning counted
events into a number and writing it to a ledger — centralizes in the manager, since a scoring tool is
typically a pure function over counts and costs nothing in context to run N+1 times. The manager's one
wrap thus produces one score per worker plus its own, each attributed to its own session in the
ledger (`add --session <worker id>` labels the row) — a release record that reports one averaged number instead of the per-session list hides
exactly the outlier worker a per-session score exists to surface. **The brief names the scoring tool's
own event vocabulary, or the counts come back in the wrong one.** A release whose briefs asked for
"an event-count block" received operational counts — denials, commits, subagents — from nine of ten
workers, and the scoring tool's fire/hit/miss cites from one; the manager could score two sessions of
eleven. State the exact event kinds the project's scoring tool consumes (keel's: `tools/keel-impact.sh`'s
`--fire`/`--hit`/`--miss` cites) in the brief's own text, the way the keep-alive contract and the
`WRAP CENTRALIZED` marker already ride there verbatim. The remover is the project's own brief
instance (the gitignored per-project file named under the brief section above) carrying that
vocabulary as a fixed line — a manager's edit at the next launch, not a ticket.

**Naming the kinds is not enough: the fixed line also shows one cited event (0.15.0).** That release's
overlay listed the event kinds, yet most of its workers' checkpoints still carried bare tallies such as
"Events hit 1, friction 1", which the scoring tool cannot count ([`docs/keel-impact.md`](keel-impact.md)),
so the manager scored four sessions and left the rest unscored. The line therefore carries the shape of
one event — its kind, then one line naming what fired or was caught and where — beside the list of kinds.
The scoring tool prints that shape itself (`tools/keel-impact.sh shape`: the kinds and one example line), so the
fixed line copies it instead of hand-typing it, and the manager's one wrap turns each worker's lines into one
`add --session <worker id>` call — a score attributed to the session it came from (`dir #732`).

## R14 — the release train, and the merge

Two things in one section, because they are one move: the unit that lands on the default branch, and who lands
it. In a managed release the operator used to click merge on every PR, and that click was never a gate: three of
keel's 594 closed PRs (counted 2026-10-10) ever closed unmerged, each withdrawn by its own author, and every revert was found by a session. Twice the click did harm: a PR merged
on green CI while the worker's granted review round was still running, and a cut PR merged past a correction
already in flight. The click is the touchpoint the Operator row's class rule (above) names as the manager's, so
this section moves it, and the train, which lands many PRs in one click, gets a procedure instead of a
hand-typed table.

**The policy: where the manager merges.** The manager merges every PR of a managed release, the trains below,
the cut PR, fix-round PRs and the groom PR when still open, **where the project's policy says so**: a line in
the project's own `CLAUDE.md` carrying the token `KEEL-MANAGER-MERGES` (keel's goes in its "Public repo"
paragraph). An adopter without the line keeps the hand-over of the fallback below. A manager's merge is the step
of a documented flow that `CORE.md`'s safety rail forbids pre-authorizing, unless the explicit human decision
exists, and here it does: the operator's standing decision, recorded as the project's policy, taken once per
project and not once per merge. The standing decision covers a managed release's manager only. A standalone
`/go` or any other session never merges: `commands/go.md` and `CORE.md` keep their words. The policy needs a
mechanical floor, since prose biases an agent rather than binds it (`SECURITY.md`): keel's design is a merge
rule in its pre-PR gate (a `gh pr merge` is denied when the session is not a listed manager, the project has no
policy line, `--merge` is missing, or the head pin is not a full sha), with `main`'s branch protection under it.
**The policy line is added last**, only after that floor is in place and the harness's own permission deny on
`gh pr merge` lifted (keel's order: the gate rule merged and pulled, the deny lifted, then the line). The line
is the operator's assertion that the floor is there, and nothing at intake can verify it without trying a real
merge: a line with a gate that is absent or not wired (nothing refuses anything, so the floor is simply missing)
is a defect of the setup, to be fixed there (the operator finds it with the floor's end-to-end check, made once
when adding the line, in which a merge attempt from a session that never ran the manager command, carrying
`--merge` and a full head pin so that only the identity rule can refuse it, is stopped by the gate itself, with
the gate's reason, and not by the harness; the gate's own tests do not stand in for it; the check must use a PR
number that does not exist, since a missing floor lets it merge; it is repeated after any gate re-install),
never a fallback case; a refusal the gate actually issues stays the fallback's case (2). The manager session
also runs in a permission mode in which a passed-through `gh pr merge` does not prompt, set by the operator at
its launch: a merge the operator answers a prompt for is an operator merge in the run record. **The mode is
known on day one, not discovered at the first denial:** intake reads the policy line, then greps the permission
settings for `gh pr merge`, and the R1 intake report names one mode, the first that applies, so a second
obstacle is not reported (re-run intake after each fix): the first that applies of
`merges: operator (no policy line)`, `merges: operator (deny in place)` or `merges: manager (deny lifted)`.
Those two checks are the fallback's absent-policy and harness-denial cases below; its case (2) arises at a
merge, never at intake.

**The preconditions: the manager's own checklist, every merge.** (a) CI green on the exact head: every required
check `success` on `headRefOid` (`gh pr view <N> --json headRefOid,statusCheckRollup`). (b) The freeze: the PR's
worker has replied literally `no more pushes; ok` (see the freeze below); for a train, every constituent's
worker, and every constituent's live `headRefOid` still equals the head merged into the train. (c) No correction
in flight: a correction the manager sent to a worker on an open PR holds that PR's merge until the worker's new
freeze, and so does a spec amendment the worker has not ACKed (R6). (d) The command is `gh pr merge <N> --merge --match-head-commit <the full 40-hex head from (a)>`: a
merge commit, the head pinned, and never `--squash`, `--rebase`, `--auto` or `--admin`. The remote branch is
deleted by the forge at the merge where the repo sets that, and `--delete-branch` is omitted because its local
half fails on a branch checked out in a worktree. (e) The merge is one health line on the R6 channel, after the
fact, always a statement and never a question: `MERGED #N as <sha> (train k: #a #b …)`,
`HELD #N: <why> (rebuild r/2)` when (a)–(c) or the train's head check holds a merge, or
`REFUSED #N: <gh's reason>` when `gh` exits non-zero (a moved head, a red check). A refusal is never retried
with `--admin` nor through another command shape (`gh api`, `sh -c`, `curl`, an alias): it is a "no" until the
operator says otherwise. R11's bound applies: two GitHub refusals on one PR stop and escalate in one line. A
first GitHub refusal is a rebuild or a wait (below), never a hand-over. A lone ready PR is never held for a
future train: it merges alone unless a train is open, and when it is BEHIND, the manager runs
`gh pr update-branch <N>` itself, waits for CI and the worker's new freeze on the new head, then merges.

**The freeze: what a worker does after its PR opens.** It sends its checkpoint, then holds. Once CI is green and
`gh pr view <n> --json mergeStateStatus` reads CLEAN (or BEHIND only), it sends the literal `no more pushes; ok`
and pushes nothing more: a push after that line takes the PR out of the train in progress. When the manager
sends `REBASE`, the worker first runs `git fetch` and compares the PR's head with its own (a head moved by the
manager's `gh pr update-branch`, or by the operator's Update branch, is not the worker's to overwrite; identical
trees mean nothing is pushed), then rebases on the default branch, re-runs what the rebase touched, pushes with
`--force-with-lease` and reports the new head. A worker never merges. The manager puts these lines in every
worker brief's rules (item 4 of the brief shape), by pointer to this section.

**The train: when.** Two or more PRs are ready (own CI green, review converged, worker frozen) while the base
requires up-to-date: the manager cuts a train, and one ready PR merges alone. A PR joins at most one train. A PR
whose own CI is still running joins only when its local suite was green and the body says so, and a red PR
never. A constituent whose own CI turns red after the cut leaves the train, which is a rebuild. **While a train
is open it is the merge unit** (R2's serialization applied to the train): no other PR of the release lands
between the cut and the merge, and a lone ready PR waits for this train or joins the next. A stalled open train
(a dialog unanswered in its worker's session) is the sweep's (R11): the manager drops the stalled constituent as
a rebuild, or escalates in one line, so a lone PR's wait ends with the train. If the base moves anyway (a
hotfix, another release's PR), the manager runs `gh pr update-branch <train>` (a merge commit made on the
forge), the train worker fetches and fast-forwards its worktree to that head, re-runs the verification there and
amends the body's sha, and that counts as a rebuild.

**The train: build.** The manager decides the composition (the `<N>=<sha>` list, from the freeze lines) and the
order (the seam plan's order, R10, else ascending PR number). The manager creates the worktree and builds the
train with one tool, `git fetch --prune origin`, then
`tools/self/release-train.sh build --branch claude/release-<version>-train<k> <N>=<sha>…` (it cuts the worktree
off `origin/main` under `.claude/worktrees/`, or at `--worktree <path>`, prints the path first and each step it
takes, and never touches the manager's checkout). Once the build is done it launches the train worker with that path as its working
directory, and early (R3): the pre-PR gate keys its traces off the session's working directory, so the session
that runs the pre-PR flow starts in that worktree. The worker then owns the worktree end to end, one writer per
worktree (R5), every later command `git -C <path>`. Once the worker is launched the manager builds nothing there and runs nothing else. The
tool does what the next sentences require, and they stay as the manager's by-hand fallback, run before the launch.
Before any merge, run
`git merge-tree --write-tree <sha-a> <sha-b>` over every pair of constituent heads (exit 1 is a conflict; the
tool exits 1 naming the pair and its files and creates nothing). A
conflicting pair is resolved by the LATER PR's worker on its own branch (whichever merges second rebases) before
the train is cut, or the manager leaves the later PR out of this train, or, when the fix is mechanical, by an
integration commit in the train. A merge that conflicts mid-build (three PRs that conflict only in combination,
a constituent against an integration commit already made) has a fixed pair of answers, never an improvisation
(the tool leaves that merge in progress, exit 1, the unmerged paths printed; this happens during the manager's build,
before the worker is launched, so the answer is the manager's; after the launch the worktree is the worker's alone, R5):
`git -C <path> merge --abort`, then either re-run that merge and resolve it as an integration commit (the
integration rule below applies; committing the resolution keeps the tool's `train:` subject, and
`release-train.sh build --continue --worktree <path> <N>=<sha>…` merges the heads still to go) or that PR leaves
the train, and either way it counts as a rebuild. Then merge
each head AS IS, in order: `git -C <path> merge --no-ff -m "train: #<N> (<sha>)" <sha>`, never rebased or
re-authored, so that a merge commit on the default branch marks every constituent merged. Then
`git -C <path> merge-base --is-ancestor <sha> HEAD` for every head. Integration commits are limited to conflict
resolutions and fixes for failures the integrated run exposes; each is listed in the body and reviewed at medium
by a fresh context. A simplification finding on a constituent's code goes to the manager (a follow-up for that
PR's worker, or a ticket), and is never applied in the train.

**The train: verification at its head**, by the train worker: the full suite, the project's lint over every
changed file, the portability leg where the project has one, and the ancestor check. The body carries each with
the HEAD sha. The manager never runs the suite in its own context.

**The train: the seam review.** Its read order is the seam list: files touched by two or more constituents (the
changelog file excluded; read each constituent's `git diff --name-only <base>...<sha>`, three dots, so files the
base changed since a constituent forked do not flood the list), every integration commit and the pairwise
result. The per-PR reviews already converged on each PR alone, so the whole diff stays formally in scope but is
not the point. The depth is the operator's decision (the Operator row): the train worker's `/polish` step-4
dialog is that touchpoint, once per train, with the manager's recommendation pre-selected and sized from the
seam. No seam files and no integration commit means `low`, seam files mean `medium`, and an integration commit
touching code means `high`. **This is a named carve-out of `/polish` step 4**, which sizes from the diff and
runs `low`, `medium` or `high` automatically on a diff clearly inside one bucket: a train is borderline by
definition (seam-sized, not diff-sized), so step 4 ALWAYS opens the dialog, with `<level>` pre-selected. The
brief carries that sentence verbatim, and it is the carve-out's only channel into a worker whose diff sits
clearly in one bucket: `/polish`'s own step 4 text is not edited (it sits at its word cap), and the guide's §
Step 4 only points here. The body discloses what the review read and what it did not. The manager posts one
health line when the worker reaches the dialog, `DIALOG train k: depth, in <worker session>`, so the operator
knows where the question waits (a release once stalled on exactly this: the dialog waits in the worker's session
and nothing says so). On a rebuild the review is redone only for the delta: a moved constituent's `old..new`
diff that touches no seam file and adds no integration commit needs no new dialog (the body says "delta
reviewed: outside the seam"), and anything else reopens step 4.

**The train: who runs it, and the body.** A train worker session (mid tier, medium), launched by the manager
(R3) with the five-part brief: (1) state, the base sha and the `<N>=<sha>` list to re-read with `gh pr view`, and the train worktree's path as
its launch working directory;
(2) the constituent table; (3) leads, the seam list and the recommended depth; (4) rules by pointer, including
the integration rule, the carve-out sentence above verbatim, the keep-alive and `WRAP CENTRALIZED (R13)` lines;
(5) handed to you, the verification and the body's wording (the manager has already built the worktree). It
verifies, runs `/polish` 1–9 on the train and opens the PR. The body: title "<version> train <k>: land #a–#z as one merge"; the constituent
table (PR, ticket, frozen head), written from `git log --first-parent` over the `train: #<N> (<sha>)` subjects,
never retyped (`release-train.sh body --branch <name>` prints the whole skeleton from that walk, the seam list
and the integration commits included, with `<fill>` where the worker states the rest); the pairwise result; the integration commits or "none"; the verification block with the sha; the
review disclosure (level, read, not read); and the line "Merge: create a merge commit — only a merge commit puts
the constituent heads on the default branch and closes each PR as merged".

**The train: the merge, and what follows it.** The preconditions above apply. Right before the command the
manager re-reads each constituent's live `headRefOid` (`release-train.sh check --branch <name> <N>=<sha>…` names
each one that differs from the train's last merge of it). A moved head waits when the new head has the merged one
as an ancestor (`git merge-base --is-ancestor <old> <new>`, a push on top) and the worker's new freeze arrives
within the wave: the train worker then appends one more `--no-ff` merge of the new head. Otherwise (a rewritten
branch, no freeze) that PR leaves the train. Either way it is a rebuild, **and a train is rebuilt at most
twice** (a dropped constituent, a red integrated run, a moved head): the third stop escalates in one line. A
rebuild never force-pushes the train branch: it appends merges on the same branch or opens a new branch and a
new train PR, closing the old one with a comment naming the new. A train with one constituent left merges as
that PR. After the merge, each constituent reads `MERGED` (`gh pr view <c> --json state`), the ledger and
backlog markers follow (R8), and one cumulative-seam duty applies (R10): a train that lands a repo-wide lint or
guard makes every in-flight PR a candidate red. The manager tells each open PR's worker what landed, BEFORE the
merge when a constituent's report names such a lint or guard, so the worker runs it over its own branch first.
Then the manager runs `gh pr update-branch <open>` itself on every frozen, conflict-free open PR and re-watches
its CI. A conflicting PR is its worker's rebase, an unfrozen PR is left to its worker, and the manager's update
commit does not break a freeze (the merge still waits for the worker's new `no more pushes; ok` on the new
head). The operator is not asked to click "Update branch", and a lint that fires falsely on an open PR is a
defect of the lint (a ticket or a fix PR, never a workaround in the open PR).

**The fallback: the operator merges.** Three cases only: (1) a project whose policy line is absent; (2) a merge
the gate refuses, or one escalated after two GitHub refusals (a gate denial of the manager's own missing
`--merge` or head pin is not this case: it is fixed and retried once per PR, and a second denial is this case);
(3) a harness denial still in place (the deny not lifted). In each the manager still cuts, builds and verifies
the train, and the seam review and the freeze are unchanged; only the merge itself is handed over, as R9's
copy-paste-ready block with the head sha pinned (`--match-head-commit`) and a merge commit. The preconditions
and the post-merge checks apply to a handed-over merge exactly as to the manager's own, and the hand-over
records which of the three cases applied. The fallback is never routed around (through `gh api`, `sh -c`, `curl`
or an alias): a refusal is a "no" until the operator or the gate says otherwise.

**In the fallback, every PR the manager reports carries exactly one of two shapes (dir #826, dir #827).** Either a ready
block (R9's paste-and-run), which lists the sibling PRs that must NOT be merged yet, by number, with the event each
waits for; or the literal line `do not merge — waiting on <named event>`. A bare status line ("PR #N is up") is
neither shape and is not sent. A hold has to ride inside the merge message itself: twice an operator merged a PR the
manager had said to hold, once because the hold was a separate sentence and the next message, a worker's "finished",
read as the gate that lifted it, so the verdict arrived after the merge. And a merge command handed while the PR that
had to take it in still owed an amendment put that amendment into a follow-up PR. Where the manager merges, the
`HELD #N: <why>` line of (e) is the same hold.

**What stays the operator's, unchanged:** the tag, the release publish, the install block, branch-protection
settings, deletions, and the review depth of a train and of the RC audit. The run record (R7) carries how many
merges the operator made, the trains cut, and what each seam review found.

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
