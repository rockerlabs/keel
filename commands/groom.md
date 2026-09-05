---
description: Assemble the next release from the backlog — retro first, pains from the operator, a fresh-reviewer round before the plan is trusted
argument-hint: [next-version]
---
You are running the grooming procedure for `$ARGUMENTS`, per [`docs/grooming.md`](../docs/grooming.md)
— the procedure. This command is a POINTER and an ordered checklist, never a restatement: G0-G9 stay in
the doc and are adopted by reference. Where this checklist's compression disagrees with the doc's own
text, the doc wins.
(On an install where the adopter already owns the `/groom` name, `install.sh`'s generic collision-alias
mechanism places this command under the prefixed name `keel-groom` instead — same file, same behavior.)

**Step 0 — read the doc, then resolve the target.**
Read [`docs/grooming.md`](../docs/grooming.md) WHOLE before anything else — the same structural-step
rule [`commands/manage-release.md`](manage-release.md) and [`commands/delta-audit.md`](delta-audit.md)
apply to their own docs. Resolve the backlog source the way [`commands/go.md`](go.md) resolves it.
`$ARGUMENTS`, where given, names the version the produced plan targets next; where omitted, groom
whatever the backlog's open, undecided slate needs next.

**G0 — retro first.**
Read the previous cycle's records before touching the plan: the releases cross-run record, the audits'
cross-run record rows, the previous release manager's final-numbers block, and every ticket the
previous cycle's managers filed. Where the project's read-trace tier-2 aggregate exists, it supplies a
dead-doc signal and a wrap-loss-scale signal too — consume by pointing at the tool that produces it,
never by citing its internal format; skip both in one line where the mechanism doesn't exist on this
project. Produce 2-3 process amendments and APPLY them directly into the procedure doc each corrects
(`docs/release-audit.md`, `docs/delta-audit.md`, `docs/drydock.md` each carry a self-revision clause
for exactly this) — a retro that only reports findings in chat has produced nothing. Confirm the
just-closed audit run's harvest here too (G4(c)).

**G1 — pains are the input.**
A release row answers a named, currently-felt operator pain, stated in the operator's own words. Propose
a cut against a stated pain; never invent a theme without one. A row with no pain behind it says so
("carried-over theme, not a sprint").

**G2 — read ticket bodies, not headings.**
Read every slate ticket's body before assigning it anywhere.

**G3 — derive, don't assert.**
Every list and count in the produced plan is regenerated from live heading tags, never hand-written and
never carried forward from an earlier cycle. Cite a ticket's release tag by number only — never assert
a specific tag in prose.

**G4 — the hygiene sweep.**
Call each mechanism another ticket owns, never reimplement it: pool report + drain trigger, where the
project's own mechanism exists (keel: `dir #360`); staleness marker + cap check, where the project has
one; archive re-sweep when the closed share crosses its threshold, carrying whatever traps that
mechanism has recorded against itself. Dedup/absorption with reproduced evidence, never a silent close.
Re-examine on merit any ticket carried by ≥2 consecutive mechanical re-tags. **Plus the accumulator
triage:** (a) re-read the project's standing list (keel: `## Standing list` in `BACKLOG.md`) — promote
a recurring line to a ticket, drop a mooted one with a reason; (b) a promote-or-drop pass over the
project's ideas file; (c) confirmed at G0, not repeated here.

**G5 — every release row, five-plus-two fields.**
Name, pain (G1), derived ticket list (G3), size against the project's own per-release band, named
risks — plus a budget estimate sized from the project's own cost-measurement data where it exists, and
a value claim stated plainly enough to be wrong in public. Design economics (design-session cost
against spec-return rate) is a report field, not a role — record it, judge it next cycle.

**G6 — fresh-reviewer adjudication is MANDATORY.**
Hand the produced plan to a reviewer with no shared context, told to read ticket bodies. Re-verify every
one of its findings against the live file before accepting it. Do not skip this round.

**G7 — the releases cross-run record.**
Append this cycle's row to the project's releases cross-run record (keel: `private/releases/RUNS.md`,
same genre as `private/audit/RUNS.md` — header on comparability, one row per release: slate size, PRs,
sessions, cost line, findings filed; `unmeasured` where the cost was never captured, never a fabricated
zero).

**G8 — cadence-bound, never a daemon.**
One groom before each release, plus on demand. Numeric bounds and a budget precondition on any heavy
sweep; hitting a bound stops and escalates in one line, never a silent retry.

**Portability (G9).** Backlog resolved the `/go` way; the slate and pool are the `→ <version>`/`→ pool`
tag convention; a release-plan table or section is optional enrichment, never required; every record's
location is per-project, with a sensible default named.

**What this command is not.** No new procedure — `docs/grooming.md` is the source and stays the single
point of truth; a rewrite here would only drift from it. No subagent orchestration — where this
procedure runs inside a managed release, the release manager's own worker rules apply; this command
does not invent a separate one.
