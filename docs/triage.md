# Triage — turning the accumulator tiers into a rule, a ticket, or a recorded drop

Three places findings and ideas pile up before they earn a ticket: the learnings file
(`LEARNINGS.md`, workflow insights with a recurrence counter), the ideas file (`IDEAS.md`, raw
ideas), and the project's standing list (sub-bar findings that name a real defect). Each has a header
promising "promote on recurrence, prune when stale", and none of them has an owner that actually does it.
The failure is measurable: one real learnings file went from 716 to 3,555 lines in two months, with 158
of 184 entries still at `[1×]` and 26 at `[2×]` or more — entries the tier's own rule says were
already due for promotion and deletion — one of them marked "promoted, delete at the next pass" a month
earlier, with no such pass to run. The ideas file, by contrast, drained: [`grooming.md`](grooming.md)
G4 gave it a promote-or-drop pass each cycle, and two tickets came out of its first one.
[`../FRAMEWORK.md`](../FRAMEWORK.md)'s review signal 3 ("prune-tier health") describes the first
case exactly and used to name no responder.

**This is a doc, not a tool.** [`commands/triage.md`](../commands/triage.md) is a thin entrypoint over
it — a pointer and an ordered checklist; the doc is canonical and wins any disagreement. *(On an
install where the adopter already owns the `/triage` name, `install.sh`'s generic collision-alias
mechanism ships the command under the prefixed name keel-triage instead — same file, same behavior.)*

**Why a separate procedure, not a `/groom` step.** `/groom` never runs on a knowledge base (it has no
releases), so a groom-only owner leaves the one instance that rots unowned; a 180-entry pass does not fit
a groom session's budget (G8); and two prose copies of one procedure is the drift class this repo keeps
paying for. So [`grooming.md`](grooming.md) G4 and `/global-review` *call* this procedure by reference.

## The steps

**T0 — resolve inputs.** The backlog the `/go` way (`dir #N` for a project, `KB.x` for a knowledge
base). The three tiers come from the project's `CLAUDE.md` map: the learnings file, the ideas file, and
the standing list (keel: the `## Standing list` section of `BACKLOG.md`; another project names its own
durable re-read list, or `none`). An input that is absent → one line saying so, skip it; this pass never
creates a tier.

**T1 — order of work, bounded.** In this order: (1) every learnings entry at `[2×]` or more — the
promote-due set, highest value; (2) standing-list lines that recur across cycles; (3) ideas entries;
(4) `[1×]` learnings entries, oldest dated first; (5) undated entries last. A per-pass bound on entries
touched (default 40; `$ARGUMENTS` may raise it with `--limit N`) and a budget check before starting
(the G8 shape). Hitting the bound stops the pass with one line — "N remain, next pass starts at <entry>"
— never a silent partial.

**T2 — one verdict per entry, from exactly four.**

| verdict | when | action in THIS pass |
|---|---|---|
| `PROMOTE-RULE` | the landing surface is known AND the edit is at most one paragraph AND the surface lives in a repo this session may edit directly (a knowledge base's direct-to-default carve-out; a project's own `CLAUDE.md` or memory) | make the edit, delete the entry (learnings) or mark it (ideas), cite the entry in the commit message |
| `PROMOTE-TICKET` | needs mechanization, a test, a design pass, OR lands in a repo that needs a PR (keel's `FRAMEWORK.md`, `docs/`, `commands/`, `tools/`) | file a ticket in the LANDING repo's backlog now: heading carries `[promoted from <file> <date> [n×]]`, body = the entry verbatim plus the intended landing surface, readiness R2 or R3 (a design pass is the ticket's next step, not this one); then delete or mark the entry with the ticket number |
| `KEEP` | `[1×]`, younger than the horizon, still plausible | untouched; counted |
| `DROP` | mooted by a later change, OR `[1×]` older than the horizon and never bumped | learnings: delete when the file is git-tracked (history is the archive); where it is NOT tracked (an adopter's gitignored harness home) append the line to a `## Dropped` tail section instead, since a deletion there has no undo. Ideas: keep the entry with an inline `Dropped <date> — <reason>` (that file's own convention) |

The horizon is **60 days at `[1×]`**. The template's "~5 sessions" is unmeasurable after the fact, so it
is operationalized as a date. Calibrate it on the first real run against the live date distribution and
write the corrected figure back here if 60 is wrong. An undated entry predates the dating convention
and is treated as past the horizon — but it gets a read before a drop, never a mechanical delete.

**T3 — an entry never survives a promotion.** An entry never survives a promotion. "PROMOTED → X,
delete next pass" is the failure this procedure exists to remove. The delete or mark happens in the
same edit as the promotion — same commit as the rule, or same edit that files the ticket.

**T4 — record the pass, one line.** Counts per verdict plus the bound state, appended to the caller's
record: a `/groom` run → its G7 row; a `/global-review` run or a standalone knowledge-base run → that
base's dated review log (`REVIEW_HISTORY.md`); a standalone project run → the project's own releases
record if it has one, else the commit message. The location is per project, with that default named
(the G9 shape).

**T5 — write discipline.** Tier files are shared and have no worktree isolation: make surgical edits,
keep `old_string` windows small, and on a "modified since read" rejection re-read the section and retry
rather than rewriting around it. A knowledge base is direct-to-default; a tracked tier file in a repo
with a PR flow (keel's `IDEAS.md`) goes through the normal branch → `/polish` → PR flow.

**T6 — cadence, never a daemon.** Called from [`grooming.md`](grooming.md) G4 (each release cycle,
the project's tiers), from `/global-review` (the knowledge-base tiers), from `/wrap` only for the
in-session `PROMOTE-RULE` case, and on demand when [`../FRAMEWORK.md`](../FRAMEWORK.md)'s review
signal 3 fires — that signal names this procedure as its responder.

## Boundary with the memory directory

This procedure owns the three accumulator tiers only. It never writes the harness's memory directory
or its `MEMORY.md` index (a different surface with its own hygiene checks); an entry whose landing
surface is a memory file is a `PROMOTE-RULE` only when the project's own rules let a session write
there, otherwise a `PROMOTE-TICKET`. Where an implementation ever does write `MEMORY.md`, say so in
the PR body.
