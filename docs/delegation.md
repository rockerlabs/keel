# Capability-split delegation

Most of a working session is read-only analysis — reconcile, reproduce, measure, draft — and none of
that needs a commit, a PR, a review dialog, or any of the other control points a project keeps a human
in the loop for. What's actually scarce is the gated mutation path and the operator's own review and
merge bandwidth. This doc names the pattern that follows from that split: fan the read-only bulk of a
session out to cheap, stateless, parallel workers behind a file contract, and keep every gated control
point inside one orchestrator session that never delegates it away.

The pattern was extracted from a field-tested run, not designed on paper — see
[`docs/drydock.md`](drydock.md)'s own cost table and felt incidents for the numbers and what went wrong
without each rail. That doc is this run's own worked instantiation — read it alongside this one for a
concrete, end-to-end example of every section below applied to one shape of work (auditing). This doc is
the generalization: the roles, contracts, and rails that hold regardless of what the units being
delegated actually analyze.

**This is a doc, not a tool.** No dedicated delegation command ships here — an orchestrator session
follows this doc by hand, the same way `/go`/`/polish`/`/wrap` are followed by hand until a project
wires its own automation around them. Mechanizing any part of this is later work, its own ticket.

## Roles — four of them, in separate contexts

| Role | Runs as | Model + effort | May touch |
|---|---|---|---|
| **Orchestrator** | your own session | top tier, high | everything: every phase, all arbitration, **all** bookkeeping |
| **Worker** | spawned subagent, many in parallel | mid tier, medium | read-only, plus its own unit-output file(s) |
| **Verifier** | spawned subagent, a few in parallel | mid tier, **high** (above Worker's) | the `verdict:` lines of the units it was given |
| **Mutator** | a real, operator-launched session — **never** a subagent | mid tier, medium | one unit of gated mutation |

Two of those assignments are load-bearing, and here's why: finding something worth flagging is cheaper
than proving it right or wrong, and a wrong verdict is the one thing nothing downstream re-checks — so
the higher effort goes to verification, not discovery. And a mutator is the only role that has to pass
through your project's own gates (commit receipts, a review dialog, the PR, the merge) — a subagent that
skips those isn't a faster mutator, it's an ungated one.

Verifiers are **default-on** whenever worker output carries judgment — a claim, a finding, a draft that
someone downstream will act on. They're skippable only for purely mechanical collection with nothing to
judge (a raw inventory listing, say). The orchestrator decides which applies, in writing, in the run's
freeze/scope file (see [Run directory and state](#run-directory-and-state-split) below) — not left
implicit per worker.

The orchestrator does **all** bookkeeping: assembling the fix/action queue, marking units resolved,
writing the run's summary. Workers and verifiers stay stateless behind the file contract, so neither
ever needs to know the ledger, and one dying loses nothing but its own unit of work.

## The non-delegable set — a rail, not a suggestion

Every operator gate and control point stays inside the orchestrator's own session, full stop, no matter
how mechanical the surrounding work looks:

- commits and PRs, and their receipts and review dialogs
- merges
- releases
- deletions
- backlog ticket-number assignment
- memory / knowledge-base writes
- the operator's own review and merge bandwidth — the true bottleneck, and the one thing no number of
  parallel workers can widen

These exist specifically to **not** be automated away. Delegation applies only to the read-only analysis
that sits in front of them. If you find yourself routing any item on this list through a subagent
because "it's just this once" or "the finding is obviously right," that's the pattern eroding — not a
shortcut.

## The generic phase skeleton

Drydock's own run generalizes to seven phases; phases marked optional are per-application, not part of
the invariant core. (Drydock itself numbers eight — one of its phases folds into item 3 below, explained
there.)

1. **Freeze + scope.** Measure a baseline (a commit SHA, a snapshot, whatever "the state this run
   analyzes" means for your application) in a clean copy of the tree — never your live working copy,
   which a peer session or your own in-progress edits can silently move out from under you. Derive the
   run's work units from that frozen state, as code where you can (a script's output is a reproducible
   scope; a hand-drawn list silently disagrees with the tree the moment either one changes).
2. **Parallel read-only work.** One worker per unit, all read-only, all at once.
3. **Verification** *(default-on — see the role rule above)*. Each verifier re-derives its assigned
   units' output independently and fills the empty verdict lines — including, for applications with
   enough units to make it worthwhile, a cross-unit dedup pass over what each unit claims (drydock's own
   phase 3: one agent, over extracted claims only, catching contradictions no single unit's verifier
   would see from its own side). Applications that add this pass need a claims-style field of their own
   in the unit-output contract below for it to read from — drydock's `## claims` section is the pattern
   to copy. A verifier can also run this step **blind-then-reconcile** instead of the plain shape just
   described — see that section, right below, for when the extra pass is worth it.
4. **Orchestrator arbitration.** Spot-check every rejection, a sample of accepted units, and every
   territory an already-open ticket claims to own. This is the one phase delegation never reaches: a
   unit can look clean to both its worker and its verifier and still be wrong in a way only the
   orchestrator's own read catches (see [`docs/drydock.md`](drydock.md)'s own field test for the one
   defect that slipped past both earlier roles and surfaced only here).
5. **Gated, serialized mutation** *(optional — only present in applications that mutate anything)*. One
   operator-launched mutator session per accepted unit (or per thematic batch of units), strictly
   serialized if your project's own gate keeps a single sentinel.
6. **Re-check** *(optional)*. One delegated read-only pass at the post-mutation state, confirming the
   mutations actually landed coherently.
7. **Summary + extraction.** A durable record of the run (see below), and — where the application has
   one — a ratchet step: what did this run learn that should get cheaper or more mechanical next time?

**One-loop invariant:** late findings — anything phase 6 turns up — feed the *next* run, never this
run's mutators. Without this rule a run has no termination condition, since every mutation is itself new
material the next pass could analyze.

## Blind-then-reconcile — an optional two-phase verifier shape

Step 3 above runs a verifier once, independently, against a worker's already-written output. Some
applications get more out of a two-phase variant: the verifier does its own pass **blind** — before
reading the worker's report at all — writes its own findings in full, and only then reads the worker's
report (and any sibling verifier reports already written) and appends a **reconciliation section**:
what both sides caught, what only each side caught, and — the part a plain re-check never produces —
any of the verifier's *own* findings it now judges wrong in light of what the other side measured.
Judge your own findings against what the other side measured; don't simply defer to it.

This is worth the extra pass specifically when a unit's judgment is hard enough that two independent
reads catch different things than one read plus a re-check would — step 3 above stays the default
shape; this is an opt-in variant of it, not a replacement. A field-tested instance is the diversity leg
of a delta audit: its own diversity-leg template is [`docs/delta-audit.md`](delta-audit.md) §9, but the
run that field-tested this shape is dir #207 — running the same whole-read method blind, then
reconciling, caught a shared blind spot every same-family session had missed and self-corrected the
leg's own misreading of a different finding, in the same run.

## Execute the claim, don't re-read it

A comment, docstring, or contract note describing behavior is a **claim, not evidence**. When the
input it describes is executable, verification means running it — not reading the same prose again,
however carefully. A field-tested incident: three review layers of a delta audit (the mechanical
baseline, the main-wave whole-read sessions, and their verifier) each read a script's contract comment
as evidence for what it did; only the diversity leg, which ran the described input instead of
re-reading the comment, caught that the comment was false (dir #225).

The rule this generalizes is [`docs/delta-audit.md`](delta-audit.md) §4 rule 3 ("verify claims against
the tree, not memory or plausibility") — that rule's own worked incident is this one, stated here
because auditing isn't the only application that needs it: any worker or verifier reading a claim about
executable behavior should run it, not just re-read it more carefully.

## The unit-output contract

Each unit of delegated work produces exactly one output file in the run's working directory. The header
and the closing section are invariant across every application; the body between them is the one part
that's genuinely per-application parameter.

```
# <capability> run — <unit id> @ <baseline>
worker: <model + effort> | <date>

<body — whatever this unit's work actually produces: findings, a draft, a measurement>

## <completeness-marker section — name it to fit your application>
verdict:
```

Two rules apply to every application, not just the shape above:

- **The closing section is the completeness marker, not decoration.** A unit file missing it is a dead
  worker's partial write, not a unit with genuinely nothing to report. Respawn that unit from scratch;
  never fold a partial write into the run as if it were a clean result.
- **Verifiers append; they never edit.** The `verdict:` line arrives empty from the worker and gets
  filled by a *different* context during verification — the agent that produced a claim doesn't get to
  rule on its own claim. The verdict is three-valued:

  | Verdict | Means |
  |---|---|
  | `accepted` | reproduced independently → goes to the orchestrator's arbitration |
  | `rejected: <what the verifier measured>` | reproduced and found wrong — the reason names a **measurement**, never a doubt |
  | `known — <ticket id>` | an open or deferred ticket already owns this → record the pointer, **take no action** |

  Skip the third value and delegation quietly re-opens decisions someone already made on purpose — a
  deliberately deferred item "fixed" straight back into the tree by a worker that never saw the ticket
  that deferred it.

## Run directory and state split

Working artifacts live in a gitignored working directory under your **main checkout** — not a
worktree's own equivalent directory, which never propagates back to the main checkout and strands the
run's output the moment that worktree goes away. `private/<run>/` is this doc's own naming convention
for that directory; adopt whatever gitignored location your project already reserves for this kind of
thing — [`docs/drydock.md`](drydock.md) uses a gitignored working directory the same way, under
whatever name your own setup gives it.

Split what the run produces in two, deliberately:

- **Working artifacts** — unit-output files, the freeze/scope file, intermediate notes. Re-derivable by
  re-running the phase that produced them. No backup contour: losing them costs hours, not history.
- **Durable output** — the run's summary, any trend data future runs compare against. Goes to a durable,
  dated history record *outside* the working directory: a changelog entry, a dated log file, whatever
  your project already keeps for this kind of practice. Losing this costs the practice itself, not just
  one run's worth of work — treat it like anything else you'd hate to lose.

## Worker rails — verbatim, do not paraphrase

The block below is reproduced **verbatim** in every worker and verifier prompt this pattern generates.
Copy it in exactly; do not summarize or reword it into "the spirit of" these rules — each line is a
direct countermeasure to something that went wrong without it during the field test, most of it recorded
in [`docs/drydock.md`](drydock.md)'s own felt incidents:

```
- You are read-only: no commits, no branch changes, no edits to any repo file. Your only writes are
  your own contract file(s).
- Do not spawn subagents of your own.
- Any live or executable check runs ONLY in a scratch clone under a sandboxed tmpdir — never the real
  checkout, never the real $HOME. (A past verifier session "empirically reproducing" a finding
  overwrote real machine-global git hooks and broke `git push` machine-wide until they were restored.)
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.
```

That last line matters more than it looks. An end-of-session nudge your harness runs (a Stop hook, or
anything equivalent) will otherwise steer every worker toward its own wrap-style bookkeeping — the field
test saw exactly this fire on every one of one run's mutator sessions. `/wrap` names this field test's own
harness convention; ship the line as-is regardless of what (if anything) your own harness calls its
equivalent — reproducing it exactly is what makes it a reliable countermeasure. It belongs in mutator
prompts too, not only worker and verifier ones — see the templates below.

## Disclosures — one canonical text, not mirrors

This pattern's own runs produce disclosures — a verifier's `known — <ticket id>` pointer, a fix
queue's residual note, a run's durable-output summary (see [Run directory and state
split](#run-directory-and-state-split) above) — and those are exactly the surfaces this rule protects,
even though the felt incident behind it happened outside this pattern.

A caveat, a known gap, or any other operator-facing disclosure that has to appear on more than one
surface (a gate's own message, a command doc, a changelog entry) is a **drift factory** the moment it's
written out in full on each surface with a "keep in sync" instruction attached. A real disclosure in
this repo's own history lived in three such mirrors (dir #201/#214) and desynced across three separate
fix rounds — one round's own fix removed a false claim from one mirror and introduced a new one in the
same commit, in the very header that mandated the sync.

Write it **once**, on the surface closest to where the disclosed condition actually lives, and have
every other surface **point at it** rather than restate it. A pointer can't drift out of sync with
itself; a second full copy always eventually will, no matter how carefully "keep in sync" is worded.
This is [`FRAMEWORK.md`](../FRAMEWORK.md)'s **Single source of truth** rule and its **sync smell**
corollary ("a 'keep in sync with X' comment... is a symptom, not a task"), applied specifically to a
disclosure instead of a fact, a status marker, or a shared value — same root cause as dir #166's
one-status-restated-on-N-surfaces class too.

**This does not apply to the worker rails block above.** That block has to be inlined verbatim into
every prompt an agent actually reads, because a subagent can't reliably dereference a cross-file
pointer mid-session the way a human reader can — which is exactly why it gets the opposite treatment,
verbatim copies plus a drift test, instead of a pointer. Minimize mirrors for anything a *human* reads
across documents; keep the verbatim-copy-plus-drift-test discipline for anything an *agent* has to read
inline in its own prompt.

## Failure and restart semantics

Units are interruption-proof **by contract** (the completeness-marker rule above): an interrupted run
loses only its unfinished units, and never restart a whole wave to recover from one lost unit.

The freeze/scope file (item 1's output) is the run's resume point: everything downstream regenerates
from it, which makes it the one working artifact worth treating as load-bearing even though the rest of
the working directory carries no backup contour.

**The session-limit flow**, ask-then-arithmetic, run before every wave:

1. **Ask the operator for their live remaining-window percentage.** The agent cannot see it — this is a
   number only the human can supply.
2. **Budget the wave** as remaining minus roughly 5%, held back as the orchestrator's own reserve — it
   still has to arbitrate and record after the wave lands.
3. **Pilot two units spanning the cost envelope, and pilot on a work-dense unit, not just a big one.**
   Cost scales with how much a unit's claims need re-measuring, not with its raw size; a pilot chosen
   for size alone will under-predict (see [`docs/drydock.md`](drydock.md)'s session-limits section for
   the felt incident behind this).
4. **Do the arithmetic before spawning:** measured per-unit cost × wave size < budget. If it doesn't
   fit, split at a **stage boundary** — defer a whole batch to the next window, never spawn half a
   batch.
5. **Hard-stop planning at ~95%, not 100%.** The last few percent are what you need to record where the
   run actually got to.

## Prompt templates

Generic skeletons — instantiate every `<...>` slot and hand the result to the session. The rails block
above is a verbatim-include in the worker and verifier templates below: copy it in unmodified, it is not
a paraphrase target.

**Worker:**

```
You are a delegation WORKER for <capability/run name>.

Your unit: <the specific slice of work this application delegates per unit — files, tickets, a range>

<application-specific task instructions: what to look for, draft, or measure>

Rails:
<the verbatim worker/verifier rails block from "Worker rails" above>

Write your output to <path to this unit's contract file>, using this shape:
<the unit-output contract shape from "The unit-output contract" above>
```

**Verifier:**

```
You are a delegation VERIFIER for <capability/run name>.

You were given these units to verify: <list of unit-output files>

For each unit, re-derive its output independently — do not trust the worker's claim, re-measure or
re-derive it yourself. Then fill the empty `verdict:` line: `accepted` | `rejected: <what you
measured>` | `known — <ticket id>` (an open or deferred ticket already owns this — record the pointer,
do not act on it).

Rails:
<the verbatim worker/verifier rails block from "Worker rails" above>

Never edit the worker's text — append only.
```

**Mutator:**

```
You are a delegation MUTATOR — a real, operator-launched session, not a subagent.

Your unit of gated mutation: <one accepted unit's worth of change — a PR, a backlog edit, whatever this
application mutates>

Act on accepted units only: no adjacent cleanups, and do not re-litigate a `rejected` or `known`
verdict.

DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.

Hand back: <the PR URL / commit / whatever this application's mutation produces>, plus a per-unit
resolved/skipped list.
```

## Application sketches

One paragraph each, non-normative — starting points, not prescriptions. All but the first are **not yet
field-tested**.

**Whole-tree audit.** The pattern's own origin. See [`docs/drydock.md`](drydock.md) for the full worked
instantiation: prose-defect auditors as workers, a re-measuring verification pass, a fix phase as gated
mutation.

**Grooming wave** *(not yet field-tested).* One worker per open ticket drafts a fully-specified,
implementer-ready version into a shared drafts directory. Verification (if used) checks each draft
against its own ticket's forks rather than re-deriving anything external. The operator resolves every
open fork across all drafts in one arbitration sitting instead of one ticket at a time, and the
orchestrator folds the resolved drafts back into the backlog — mutation here is backlog edits, staying
orchestrator-owned since backlog writes are on the non-delegable set above.

**Pre-implementation recon dossier** *(not yet field-tested).* Workers each build one piece of the
reconcile dossier a big ticket needs before implementation starts — existing code, prior art, related
tickets, open forks. No mutation or re-check phase: this application ends at arbitration, handing the
orchestrator (or the implementer) an assembled dossier rather than producing any change itself.

**Post-merge read-only sweep** *(not yet field-tested).* After a batch of merges, workers each sweep one
slice of the tree for regressions, dangling references, or drift the merges introduced — read-only, no
mutation phase of its own; findings feed the normal backlog rather than an in-run fix step.

## See also

Beyond the worked example itself, [`docs/drydock.md`](drydock.md) ships a full set of role-prompt
templates (auditor, verifier, fixer) — a second, audit-specific reference alongside the generic ones
above, worth a look if your application is close enough to auditing to start from theirs instead.
