# Grooming — assembling a release from the backlog, on a fixed cadence

This doc closes the manager family's loop: a design session writes a spec → `/go` implements it →
[`docs/release-management.md`](release-management.md)'s manager coordinates a release built from
those tickets → [`docs/delta-audit.md`](delta-audit.md) checks the release before it tags → this doc
assembles the *next* release from whatever the backlog now holds → which feeds another design session.
The grooming duties already existed before this doc did, scattered across tickets that each own one
mechanism and none of which owned the *cadence*: a pool report and drain trigger, a staleness marker,
an archive sweep that goes stale on its own, dedup and absorption practised by hand each time. This
doc is what gives that work one owner and one place to read it.

**This is a doc, not a tool.** [`commands/groom.md`](../commands/groom.md) is a thin entrypoint over
it — a checklist that resolves the target and runs the loop — the same split
[`docs/release-management.md`](release-management.md) and [`docs/drydock.md`](drydock.md) use for
their own procedure-plus-entrypoint shape. The doc is canonical; the command points at it. *(On an
install where the adopter already owns the `/groom` name, `install.sh`'s generic collision-alias
mechanism ships this command under the prefixed name keel-groom instead — same file, same behavior, no
separate wiring.)*

**No separate retrospective manager exists, on purpose.** The retro is this doc's own phase 0 (G0
below), because its inputs are already produced by contract by the other managers in the family — the
release manager's final-numbers block and cost line, the audit's cross-run record row — and a separate
retro session would pay one more full release's worth of context for what is, in substance, this
procedure's own pre-read.

**Why this compresses one practised run, not a design done on paper.** Every section below carries the
incident that paid for it, the same way [`docs/release-management.md`](release-management.md)'s R1-R13
do: this doc compresses the 2026-08-29 grooming pass and the 2026-09-03 release-plan groom — the
latter re-cut four sprints from four operator-stated pains, then caught its own headline failure (17
findings from a fresh reviewer, on a plan built from headings with bodies unread) in an adjudication
round. What follows is the procedure extracted from those two runs, not a specification of what a groom
*should* do in the abstract.

## G0 — retro first

Before touching the plan, read the previous cycle's records: the releases cross-run record (G7 below),
the audits' cross-run record rows, the release record a manager writes at close (keel's own instance is
the FINAL NUMBERS paragraph its `dir #367`-style ticket record carries — a project without a ticket
record of its own writes the equivalent wherever its release-manager procedure lands it), and every
ticket filed by the previous cycle's managers. Where the project's read-trace aggregate exists (keel:
`dir #387`), it supplies two more G0 inputs — a dead-doc signal and a wrap-loss-scale signal, the two
things that mechanism exists to surface. Consume it **by pointing at the tool that produces it**, never
by citing its internal format: no column names, no file path, no output shape — the tool's own doc is
where that lives, and it may change there without this doc needing an edit.

**Degrade cleanly when it does not exist yet**, or on a project that never installed it: skip both
inputs, proceed on the rest, and say so in one line rather than blocking the retro on a mechanism that
may not exist on this adopter at all.

**Output: 2-3 process amendments, applied, not reported.** Each amendment lands directly in the
procedure doc it corrects — `docs/release-audit.md`, `docs/delta-audit.md`, and `docs/drydock.md` each
carry a self-revision clause naming exactly this: a process doc that only one run ever shaped stops
being reusable the moment a second run's lessons don't fit it. A retro that writes its findings only
into a chat message or a ticket body has produced nothing a later cycle can find; the amendment is the
deliverable, not a description of one.

**The just-closed audit run's harvest confirmation happens here too.** This is G4(c) below, restated in
this phase because a doc author compressing G0 from a shorter read of this section alone must not drop
it: confirm that the just-closed delta-audit run's `no-action` leads and findings were harvested onto
the standing list (G4(a)) and that its own staged-tickets file is empty or filed. Older, already-closed
audit-run directories get one catch-up harvest the first time this procedure runs on a project, then
are archive, not backlog — no groom re-opens them a second time.

## G1 — pains are the input, and only the operator supplies them

A release row answers a named, currently-felt operator pain. The 2026-09-03 re-cut is the precedent:
four operator-stated pains became four sprints, each row citing the pain in the operator's own words
before naming what the backlog already had toward it. This procedure may propose a cut of the backlog
against a stated pain; it never invents a theme without one, and any genuine product fork stays the
operator's to resolve, never this procedure's to infer. A release row with no operator pain behind it
says so plainly on the row — "carried-over theme, not a sprint" is the wording a plan already uses for
exactly this case, and it stays visible rather than being dressed up as a sprint it is not.

## G2 — read ticket bodies, not headings

The 2026-09-03 groom's headline failure was assignment from headings and R-levels with bodies unread,
caught only by a 17-finding adjudication round (G6). A heading understates or overstates a ticket's
real size and scope often enough that a heading-only read mis-sizes the plan it produces — read the
body of every ticket entering the slate before it is assigned anywhere.

## G3 — derive, don't assert

Every list and count in the plan is regenerated from live heading tags at groom time, never
hand-written and never carried forward from a previous cycle's numbers. The 2026-09-03 pass's own
hand-written re-tag list was wrong for 11 of 16 tickets the moment it was checked against the live
file — the exact failure this rule exists to close. This includes any prose reference to a specific
ticket's release tag: cite the ticket by number and let the reader (or the next groom) resolve its
current tag live. Never assert a specific release tag in prose — a later re-tag leaves an asserted one
stale and silently wrong.

## G4 — the hygiene sweep

Everything below executes a mechanism another ticket owns; this procedure is the cadence that calls
each of them, not a reimplementation of any of them. Each mechanism's own shape (its exact fields, its
exact traps) lives in the ticket or tool that owns it — where that mechanism has not shipped yet, this
sweep names the gap and moves on rather than asserting an unshipped ticket's own proposed shape as
settled fact.

- **Pool report and drain trigger.** Where the project's pool-measurement mechanism exists, run it as
  part of this sweep: it reports the background pool's size and health, and names the signal for
  scheduling a drain release rather than letting filing continue unchecked. Keel's instance is `dir
  #360`; where it or its equivalent has not shipped, this sweep says so rather than reporting a number.
- **Staleness.** Where the project's `⚠ ERODING`-style staleness marker and its cap/staleness check
  exist (they may not — this is a per-project mechanism this procedure only calls), run it as part of
  this sweep.
- **Archive re-sweep.** Where the project's archive-sweep mechanism exists, re-run it when the
  closed-ticket share of the backlog file crosses its threshold again, carrying whatever traps that
  mechanism has already recorded against itself. Keel's instance is `dir #359`, which already records
  two: a cooldown/datability rule, and a wrapped-heading terminal-marker rule the sweep itself once
  violated and had to recover from. This procedure calls the sweep and points at its own record of its
  traps; it does not maintain a second copy of them here.
- **Dedup and absorption, never a silent close.** A ticket found to duplicate another is closed with
  reproduced evidence in the closing note — a re-run test, a live grep, a reproduction — never a bare
  "duplicate" marker with nothing to check it against.
- **Re-examine on merit.** A ticket carried by two or more consecutive mechanical re-tags (its release
  tag moved without anyone reading its body) gets one read-the-body pass rather than a third silent
  carry-forward.

**Plus the accumulator triage** — three places findings and ideas already pile up and, without a named
owner, never become anything:

- **(a) The standing list.** Sub-bar `no-action` findings that name a real defect
  (`docs/verification-economics.md` §4's filing bar) belong on a durable, re-read list, never only in
  an audit report body — that doc's own worked case is a defect noticed three separate times, in three
  different report bodies, and never once scheduled. Keel's instance is a `## Standing list` section in
  `BACKLOG.md` itself, the file this procedure already re-reads every cycle by contract.
  `commands/delta-audit.md`'s A6 already names that section and gives it its create-if-absent duty. A
  different project names its own durable, re-read list here instead — a `KNOWN ISSUES` section, a
  papercuts ticket, whatever it already keeps and actually reads from. Re-read it each cycle: a line
  that recurs across cycles promotes to a ticket; a line a later change moots gets dropped with a
  one-line reason rather than left standing.
- **(b) The ideas file.** A project's own free-form ideas/brainstorm file (where one exists) gets a
  promote-or-drop pass each cycle — its own header may already promise a periodic review that nothing
  currently owns; this procedure is the "periodically" that gets an owner.
- **(c) Closed audit-run directories.** Confirmed at G0 above, not repeated here as a separate step —
  see G0's own paragraph, which states it in full so a compressed read of this section cannot drop it.

## G5 — every release row, five fields

Name, the pain it answers (G1), a derived ticket list (G3), its size measured against the project's own
per-release band, and named risks are the baseline fields any release row needs. Two more, sized from
what a project's own cost-measurement work has already put on disk (where that work exists — see
`dir #313` for keel's own instance): a rough **budget estimate** for the release, and its **value
claim** stated plainly enough to be wrong in public. Design economics — the cost of the cycle's design
sessions against how often a spec is accepted as first submitted — is a **report field**, not a new
role of its own: record the data every cycle; the judgment about what it means is a later cycle's to
make once more than one data point exists.

## G6 — a fresh-reviewer adjudication round is mandatory

The cheapest, and on the available evidence the strongest, diversity axis
`docs/verification-economics.md` §5 names — fresh context — applied to the plan itself: hand it to a
reviewer with no shared context, told to read ticket bodies and nothing else, and re-verify every one
of its findings against the live file before accepting it — the bar is the channel that produced a
finding, never the reviewer's own authority. This is not optional polish on top of G0-G5; it is where
the 2026-09-03 groom's real defects were actually caught (17 findings, two trimmed on re-verification,
none of them mechanical — every one came from reading a ticket body or running a command, not from
re-reading the plan itself). A groom that skips this round is a groom that has not yet found its own
mistakes.

## G7 — the releases cross-run record

Audits already have a cross-run record; releases, until this doc, had none — a release manager's own
cost-line requirement said "append it to the run's record" without ever naming one. Keel's instance is
`private/releases/RUNS.md`, the same genre as `private/audit/RUNS.md`: a header stating what is and is
not comparable across runs of different scale, then one row per release carrying slate size, PR count,
session count, a cost line, and the count of findings filed. Record the cost as `unmeasured` where the
data was never captured — never a fabricated zero. A different project names its own per-project
location here — G9 states the portability rule this follows.

## G8 — cadence-bound, never a daemon

One groom before each release, plus on demand — never a background loop, never something that runs
without a session behind it. Every bounded-loop rule the release manager states for itself applies
here unchanged: a numeric bound on any repeated step, a budget precondition before any heavy sweep, and
a hit-the-bound outcome that stops and escalates in one line rather than retrying silently.

## G9 — portability

This procedure has to run on any adopter project, not only the one it was extracted from, using only
shipped conventions:

- **Backlog** resolved the way a project's own `/go` resolves it.
- **The slate and the pool** are the `→ <version>` and `→ pool` heading-tag convention a project's own
  `/backlog` already reads — the shipped mechanism, not any one project's enrichment on top of it.
- **A release-plan table or section** (keel keeps one inside `BACKLOG.md`) is that kind of enrichment:
  useful where it exists, never required infrastructure a groom depends on.
- **Every record's location** (the standing list in G4(a), the releases cross-run record in G7) is
  per-project, with a sensible default named — never a keel-only absolute path treated as the only
  valid location.

## Binding test

`tests/test_grooming_doc.sh` pins the family shape: [`commands/groom.md`](../commands/groom.md) names
this doc, this doc names the command back, and this doc carries findable anchors for G0, G3 and G6 —
the three requirements most likely to be silently dropped in a rewrite, since G0 is easy to compress
into a single line, G3 is easy to read as implied rather than stated, and G6 is the one a rewrite under
time pressure is most tempted to skip.

## Self-revision clause

This document is subject to its own G0: where a real groom's practice disagrees with what is written
here, the correction belongs in this doc, applied as part of that groom's own G0 phase — the same
retro discipline this doc asks of `docs/release-audit.md`, `docs/delta-audit.md` and `docs/drydock.md`,
applied to itself.

## See also

The sibling docs this procedure's loop runs through — [`docs/release-management.md`](release-management.md)
and [`docs/delta-audit.md`](delta-audit.md) — are introduced at the top of this page and not re-glossed
here. The one dependency worth naming that isn't: [`docs/verification-economics.md`](verification-economics.md)
§4, for the filing bar the standing list (G4(a)) exists to satisfy, and for the per-release debt-budget
doctrine the pool report (G4) makes measurable rather than asserted.
