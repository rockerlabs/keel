# Verification economics — when to stop auditing, what to file, and whether the method is improving

An agent generates code and prose faster than anyone can verify it. Every review round finds more,
so there is no visible line where stopping is safe, and the cost of looking has no natural ceiling.
This document draws that line — and says what to do with everything the line leaves on the floor.

## 1. What this is, and the boundary with its three siblings

Three documents in this repo say **how to run** a verification pass:

- [`docs/drydock.md`](drydock.md) — a whole-tree audit, prose and code, on a cadence of every few
  releases.
- [`docs/delta-audit.md`](delta-audit.md) — the release-candidate pass over one release range, its
  universe derived mechanically.
- [`docs/release-audit.md`](release-audit.md) — the release-readiness flow those two plug into.

This document says **when to stop one, what to file from it, and how to tell whether the method is
improving.** It is cited by all three and restates none of them. Where a rail here is also stated
operatively in one of them, that is deliberate: a session following a procedure needs the rule in
front of it, not a pointer — this doc owns the reasoning, they own the instruction.

One layer below sits [`FRAMEWORK.md`](../FRAMEWORK.md)'s "PR review" section, which answers the
*per-round* question inside a single review. The two extend each other; §3 says exactly how.

**A note on citations.** This repo's docs cite internal tickets as `dir #N`. Those are provenance
markers, not identifiers you need to resolve — a number can go stale, and in this repo one did: two
different tickets once carried the same number, so every citation of it outside the backlog meant one
of them while a reader resolving the number landed on the other. It was repaired by hand. So every
rule below **says what it rests on in the sentence itself**; the number, where it appears, sits beside
the claim rather than carrying it.

## 2. The two axes — read this before any rule

The intuitive model is *review until a round comes back clean.* It is wrong, and the replacement is
not a tuned version of it. Two datasets say so, they appear to contradict each other, and the
resolution is the foundation everything below rests on.

**Within one run, on one artifact: there is no convergence and no "clean."**
Eight review rounds ran on a single ~700-line document. **One reviewer ran the first five** and found
9 → 8 → 7 → 5 → 5. A *fresh-context* reviewer then read the **more**-reviewed state of that same
document and found **18** — running the same model as the author. (Two further legs, in parallel on
one state, found 3 and 7.) Find-rate tracks **reviewer novelty**, not artifact quality.

Scope that carefully, because unscoped it collides with the per-round rule in
[`FRAMEWORK.md`](../FRAMEWORK.md): it holds *at a fixed artifact state*. Novelty is
reviewer-relative-to-state, so a fix reaching into surface no earlier round examined makes even the
*same* reviewer novel again. That is FRAMEWORK.md's "new surface touched" signal, and it is why the
two rules extend rather than contradict each other.

**Across runs, in CLASS space: convergence is visible — as a floor, not yet a trend.**
Two delta audits in this repo: the first produced a rich crop of *new* defect classes; the second
produced mostly *instances* of classes already on the record, with one arguably-new class. Each
individual classification is scale-independent — a class is new to the record or it is not — which is
why new-vs-known is comparable across runs where raw finding counts are not.

**Name the confound rather than waving it off.** Those two runs differ in scale by roughly 2× in files
and 4× in pull requests. Fewer new classes in the smaller run is equally well explained by less new
surface to be novel in. Binary *classification* does not make a cross-run *rate* scale-independent.
Two points are enough to say the ratchet has not been falsified, and not enough to say it is working.

**The reconciliation, because a reader hitting both datasets will otherwise think one is wrong:**
convergence exists in class space across runs; it does not exist in finding-count space within a run.
Both datasets are true. Something does converge — just not what, and not where, the intuitive model
says.

## 3. The stopping rule — two clauses, because there are two axes

> **This extends a rule the framework already ships; it does not replace it.**
> [`FRAMEWORK.md`](../FRAMEWORK.md)'s "PR review" section answers "is one more round worth it?"
> with two signals — **new surface touched** (a fix reaching into code earlier rounds never examined
> raises the next round's expected yield; the shape is a sawtooth, not a decay) and **class
> exhaustion** (when the same defect shape appears twice, sweep the class mechanically instead of
> patching sites). Those stay the per-round question and keep their home there. The clauses below are
> the layers above: per-run and per-release.

**Clause A — within a run.** Stop when **two independent diverse legs, run in parallel on the same
state,** together yield no behavioural findings and no new classes.

Three definitions, or the rule is not operable:

- **Diverse leg** — a leg differing from the main wave on at least one axis in §5: fresh context,
  different method, or different vendor. Two fresh-context legs on one state DO qualify. Two rounds
  by the same reviewer on the same state do not.
- **Behavioural** — a finding that changes what the shipped artifact *does* for its consumer, as
  opposed to what it *says about itself*.
- **New class** — new to your class registry **as it stands at that moment**, a registry that fills
  during the run itself. Without this scoping the rule is unsatisfiable on a project's first run,
  where every class is new in the absolute sense — see §8.

**Two legs, not one, and the reason is §5's own rule:** single-reviewer silence is not evidence, so a
single silent round cannot be the trigger either. Independent agreement is the signal; agreement that
there is *nothing* is still agreement.

**Be precise about what is and is not field-tested here.** What has never happened in this repo's
record is a diverse round returning *zero findings* — every one returned some. What HAS happened is
the rule firing on its real condition, no behavioural findings and **no new classes**: on one design
review, both cross-vendor hits were instances of a known class, so the chain stopped at two rounds.
The **one-leg** form is field-tested. The **two-leg** form required above is reasoned, not calibrated,
and you should know which is which.

**A guard-gap finding does not reset the clock.** §4's filing bar and this rule are deliberately not
the same test: a known-class instance on an invariant-bearing surface earns a ticket under that bar's
third criterion while leaving the stop condition satisfied. That criterion exists to catch *placement*
risk, not novelty.

**Nor does every behavioural finding — a severity/reachability carve-out, the same shape as the
guard-gap one above.** A behavioural finding does not reset the clock when **both** hold: (1) it is
reachable only under a condition the artifact's own stated design excludes, not one that occurs in its
actual operation, and (2) the diverse leg that found it — not the fix's own author, and not the round
being judged — gives it [`docs/delta-audit.md`](delta-audit.md) §8's own `ticket-next`,
`known-issue-in-changelog`, or `no-action` disposition, not `fix-before-tag`. Neither condition alone
is enough, and that is deliberate: reachability alone would license waving off a `fix-before-tag`
finding as "unlikely," and disposition alone would license waving off anything a reviewer chooses not
to mark `fix-before-tag`.

**Invoking condition (1) obliges the verifier to point at where the excluding design is stated — the
doc, header comment, or spec line the exclusion rests on — and to write it down if it is nowhere yet.**
"Stated" is there to block an unfalsifiable appeal to how the reviewer imagines the artifact works. When
no such line exists — the assumption has simply never been written anywhere — record it in the artifact
itself as part of the ruling, not only in the verdict prose. This is §8's own bootstrapping shape,
applied to the carve-out's own precondition rather than to the class registry: the first invocation on
a given artifact may have to write the design assumption down before it can rely on it; every later
invocation on that same artifact then finds it already checkable.

**Independence alone is not calibration, so weigh condition (2) by what else the same leg disposed this
run.** A leg that never disposes anything `fix-before-tag` satisfies condition (2) on paper while
licensing a stop regardless — the realistic failure mode. A non-`fix-before-tag` disposition from a leg
that has *also*, in this same run, disposed something `fix-before-tag` is the strong case: it has
demonstrably discriminated rather than defaulting away from the blocking disposition. The same
disposition from a leg with no `fix-before-tag` finding to its name yet is weaker — plausible, not
demonstrated. State which case applies; do not treat the two as equivalent. This is deliberately not a
hard requirement — a run whose only behavioural finding is the carved-out one leaves no earlier
`fix-before-tag` finding for any leg to have disposed, and requiring one would make the carve-out
unusable exactly where it is needed.

Read this the way you read the character test above — a judgement a human reads and states explicitly,
not a threshold a script computes. **Why the carve-out has to exist at all:** treating literally zero
behavioural findings, of any severity, as the bar makes Clause A unsatisfiable by construction for any
codebase a sufficiently thorough reviewer keeps re-reading — defeating its own purpose of saying when a
run gets to stop.

**A second trigger, alongside the two-leg condition — new surface touched.** Independently of what
the last round returned, another round is worth running when a fix has reached surface no earlier
round examined. This is [`FRAMEWORK.md`](../FRAMEWORK.md)'s field-tested signal, folded in here as a
peer of the two-leg condition rather than a footnote — **it is what repairs Clause A's weak spot.**
The two-leg silence condition is reasoned; this one is directional and tells you when *not* to stop
even though the condition looks met.

**And a corroborating signal, which licenses nothing on its own — the character test.** When a
round's findings stop being about the artifact and start being about its own *claims of
completeness* ("your exhaustive list isn't exhaustive", "your fixture doesn't bind", "that count is
now three"), the remaining defects are cheaper for the implementing session to hit than for a
reviewer to predict. This is a judgement a human reads, not a threshold a script computes; dressing
finding *character* as a number would be false precision. It **corroborates** Clause A. Crucially,
it does not independently license stopping. The two-leg condition is the rule; the character test
tells you the rule is about to be satisfiable.

**What Clause A explicitly does NOT license:** stopping because *a* round was clean, because the
budget ran out, because the same reviewer has now read it N times, or because
[`docs/delta-audit.md`](delta-audit.md) §8's verdict contract is satisfied — *coverage*, not
*stopping*, a different question from whether a diverse round has gone silent (that document's §8
states the distinction in its own words; this rail is the one it points back to). A felt case: a real
run's coverage bar read satisfied from the first closing round onward, while the run's only two induced
defects were caught by Clause A itself failing twice more on the rounds after that. Only a *diverse*
round's silence counts, and only on the current state.

**Clause B — across runs.** A run yielding only *instances* of known classes
**indicts the demotion pipeline**, not the review count.
The correct response is a demotion ticket — turn the class into a
mechanical check, and its marginal cost drops to zero forever — never "run more reviewers next time."
The worked case, stated with the honesty §2 requires of it: this repo's second delta audit found five
mutation-blind assertions and five self-referential figure drifts — all instances of classes already
recorded — plus **one arguably-new class**. So it is a near-miss on Clause B's trigger rather than a
clean instance of it, and the response was taken anyway: its largest resulting ticket was a standing
mutation check, not another round of reviewers. Read that as what the clause looks like in practice —
"only instances" is the trigger, and a run one borderline class away from it is already telling you
the same thing.

## 4. The filing bar, symmetric to the stopping rule

A finding earns a **ticket** only if it is (a) behavioural, (b) a **new class**, or
(c) a guard gap on an invariant-bearing surface.

**The bar's other half is disposition, not detection.** Saying what earns a ticket is only useful
alongside saying where everything *else* lands — because "recorded in a body" reads as persisted while
being **unschedulable**, and that is how a real, cheap, repeatedly-observed defect never gets done.

The worked case is not hypothetical. In this repo one ticket-number collision was noticed at least
three separate times over a month — a wrap sweep that named the correct fix and deferred it, a later
ticket's filing that added the symptom, a design pass after that — each notice living as an aside
inside an unrelated ticket's body. **Detection never failed. Disposition did, three times**, and every
session re-derived the problem at full cost while none could act on it.

So: a finding that does not clear the bar is dispositioned "no action — <reason>" in the report *and*,
if it names a real defect, goes onto **a named line in the project's standing list** — never a ticket
of its own. **That distinction is the whole point.** A sub-bar finding that may open its own ticket
means the bar restricts nothing, and an engineer reading both sentences either violates the bar to
save the defect or obeys it and loses the defect. The standing list is what makes "no action" a
persist. An aside in an unrelated ticket's body is neither a list nor a ticket.

**"The standing list" is not a new artifact to create** — same answer as the class registry in §8. It
is whichever durable, *re-read* list your project already keeps and actually works from: a `KNOWN
ISSUES` section, a "papercuts" ticket, a `LEARNINGS`-style staging file. The two properties that
matter are that it has a name someone can point at, and that something brings a reader back to it —
a list nobody re-reads is an aside with better formatting. If your project has no such list, that
absence is the first thing this bar surfaces, and starting one is cheaper than the alternative the
worked case above describes.

Two corollaries:

- **New classes apply FORWARD; backfill is targeted.** A newly-demoted check binds new code via your
  commit gate. Tree-wide backfill tickets are filed only for invariant-bearing surfaces — otherwise
  every method upgrade taxes the whole history and the backlog reads as a fix snowball.
- **A per-release debt budget.** A release is feature-first by default; its audit tail is a small
  fixed quota of tagged tickets, the rest staying an untagged background pool taken as passengers —
  deliberately, not as neglect. The snowball fear is measurable rather than felt: this repo's larger
  audit tail ran to roughly two dozen tickets and closed twenty of them in one day, and the following
  release's tail had zero behavioural findings.

## 5. Diversity — what actually decorrelates a reviewer

Order the axes cheapest-first.

1. **Fresh context** — the cheapest, and on the available evidence the strongest. The round that found
   18 in §2 ran the **same model as the author**, which points at an empty context with tool access
   rather than a different vendor as the decorrelating variable. **The confound, which must be
   stated:** the last same-family round before it was the first to examine that document's later
   sections at all, so its yield is entangled with completeness-of-read and does not cleanly isolate
   freshness. Treat this as a lead worth a cheap experiment, not a finding.
2. **Different method** — blind-then-reconcile: write findings *before* reading prior reports, then
   reconcile against them. Generalized in [`docs/delegation.md`](delegation.md); on one run it caught
   both a blind spot three same-family sessions shared and an error of its own.
3. **Different vendor** — still a first-class way to satisfy the required leg, and it has paid twice,
   its yield not shrinking with scale. It is no longer this doctrine's headline claim about *why*
   diversity works. **Note what is and is not mandatory:** a diverse leg is required; *this
   particular axis* is not — any one of the three satisfies it, and two fresh-context legs qualify.
   What is non-waivable is a leg your procedure has already named for a given run (see below).

Five operative rules on top:

- **Parallel, not sequential**, for independent reviewers. Two legs reading one document state were
  triaged in ONE fix round; sequential would have paid two fix rounds and shown the second reviewer a
  document already perturbed by the first one's fixes.
- **Independent agreement is a confidence signal; single-reviewer silence is not.** Two reviewers
  independently finding the same omission is usable evidence. One reviewer not finding it is not.
- **Diff a leg's quoted target against the live file before accepting its verdict.** On one spec
  review the cross-vendor leg **fabricated part of its own working copy** and reported findings
  against text that was never there. This is a hazard of the leg, not a reason to drop it.
- **Suspect the RELAY before the vendor — prefer a frozen artifact the leg reads itself.** The leg
  that fabricated was hand-relayed through a chat transcript. Legs reading a frozen snapshot directly
  with their own tools returned quotes verbatim with no fabrication, including the same vendor family
  that had fabricated when hand-relayed. **One paired observation, not proof** — the two runs reviewed
  different artifacts, so the comparison is uncontrolled. Enough to make "give every leg direct read
  access to a frozen copy, never a paraphrase" a cheap precaution worth taking; not enough to drop the
  diff-the-quote rail above.
- **Make the quote contract explicit and enforce it.** Require every finding to carry the exact text
  verbatim, say up front that a finding whose quote does not appear in the artifact is discarded
  unread, then actually diff them. It costs one script, and it is what makes the fabrication hazard
  detectable instead of merely feared.

**The non-waivable rail.** A named leg of a recorded procedure may be skipped only by an explicit
operator decision recorded in the run's plan file, **never by the orchestrator's own judgement.** One
run's orchestrator dropped the cross-vendor leg on its own judgement, was corrected only by an operator
question, and the restored leg then supplied three of that run's four disclosed residuals.

## 6. Fix rounds are a defect SOURCE, and cost accounting must charge them

**This claim is not new here.** [`FRAMEWORK.md`](../FRAMEWORK.md)'s "PR review" section already
grounds its stopping signals in review campaigns that converged not by shrinking severity but by
hitting the same defect *shape* again — *including a round's own fix causing the next round's
finding*. That sentence is this section's core claim, reached earlier and from a different corpus.
What is added here is the **rate** and the **cost accounting**.

Every fix round in the eight-round series from §2 introduced at least one new defect: round 2's fixes
caused three of round 3's seven findings; round 4's fix caused round 6's most serious; round 6's fix
caused round 8's most serious. A review's cost is therefore **the pass plus the fixes it causes**, and
a review whose findings are marginal can be net-negative. This is the strongest argument for §4's
filing bar and for parallel-over-sequential in §5 — both reduce fix-round count directly.

**The cheap mechanical companion: after any correction, grep the artifact for the phrases the
correction retired.** A withdrawn claim rarely lives in exactly one place — it has usually been
restated in an acceptance criterion, a model line, a summary, or a sibling document, and a pass that
rewrites the passage the claim came from leaves those standing, still asserting the withdrawn
conclusion. The worked case, and note where it happened: a correction to a note *about citations
surviving correction* rewrote two of its sections and left two downstream lines still demanding the
retired remedy. They were caught only by re-grepping that note for its own withdrawn phrases. That is
this section reproducing inside a fix round about this section, which is the strongest available
argument that the check should be mechanical rather than remembered. Cost: one grep per retired
phrase.

## 7. The shift-left ladder

Cheapest catch first: **generation** (rails in context) → **commit/PR** (the gate) → **release
audit**. Every catch at the last net should move a check upstream. The audit is a **class-discovery
factory, not a bug hunt.**

A defect the per-PR gate should have stopped, arriving at the release audit instead, is a shift-left
failure *regardless of count*. Worked case: one release's audit found seven tickets across three pull
requests with no changelog entry — five instances in one wave of a class with no mechanical floor,
after the same class had already been caught twice by humans mid-wave. That is not a review-depth
problem; it is a missing check one layer up.

## 8. Bootstrapping the class registry, if you have no history yet

Every rule that turns on "new class vs known class" — Clause A, Clause B, §4's second criterion —
presupposes a maintained registry of known classes to compare against. Every worked example in this
document is this repo's own. If you are starting from nothing:

- **Your first run's classes are all new, and that is correct, not a defect.** Clause A's "new to the
  registry as it stands at that moment" is what makes the rule satisfiable on run 1.
- **The registry is whatever durable list you already keep** — your ratchet tickets, your standing
  checks — not a new artifact to invent.
- **Until two runs exist, Clause B is not usable**, so the first run stops on Clause A alone.

State the honest consequence: this doctrine's cross-run half only starts paying at run 2. A version of
this document that implied otherwise would oversell itself to exactly the reader with the least to
compare against.

## 9. The run profile — the metric, and the scalar it replaces

**Retire the scalar.** "Severity-weighted findings per token" is not the metric. Its denominator goes
unrecorded in practice, and its shape is wrong per §2. Do not ship a weakened version of it either: a
single-number efficiency figure invites exactly the cross-run count comparison that scale confounds
make meaningless.

Replace it with a per-run **profile** — named fields, none of which is a count-trend.

| # | field | why it is comparable |
|---|---|---|
| 1 | behavioural defects in shipped code | a **floor**, not a trend — either the audit found something that changes what the tools do, or it did not |
| 2 | new classes vs instances of known ones | scale-independent; this is what Clause B turns on |
| 3 | which layer found what — same-family / fresh-context / method / vendor | the only way to tell whether a leg is still paying for itself |
| 4 | whether an upstream gate should have caught it | a shift-left failure is meaningful regardless of count |
| 5 | cost, per leg | so the question "is this leg worth running" has an artifact behind it |
| 6 | induced defects — findings in round N traceable to round N−1's fixes | §6's rate; without it a review's cost is systematically under-counted |

Fields 1–4 are field-tested: two runs have now been read against them. Fields 5 and 6 are new, and
each needs its definition written down or it will not be comparable across runs — which is the only
reason either exists.

**Field 5, defined.** Record per **leg**, not per run: sessions spawned, model tier and effort, and
token spend where the harness reports it — with an explicit **`unmeasured`** value permitted and
expected, **never a fabricated zero.** Two rails on its use:

- **What may eventually be published is a SINGLE LEG's cost-per-finding compared across runs —
  never a run-level or cross-leg aggregate.** This is the line between the permitted figure and the retired
  scalar, and it has to be drawn explicitly, because "retire the single number" and "a ratio becomes
  publishable" otherwise read as a contradiction. The retired claim was a whole-run efficiency score;
  what replaces it answers only "is *this leg* still paying for itself" — field 3's partner question.
  **The scale confound applies here exactly as it does to class rates:** a per-leg cost-per-*finding*
  still divides spend by a raw finding count, and raw counts are not comparable across runs of
  different size. So the figure may only ever be published alongside that run's scale row.
- **Even that waits for two runs** to have recorded a real, non-`unmeasured` figure for that leg. One
  point is a narrative, which is exactly how the retired claim went wrong.

**Field 6, defined.** At each round, the triaging session marks a finding `induced` when it is
traceable to a prior round's fix, `original` otherwise. **Attribution rule:** a finding is `induced`
when it lands in a region a prior round's fix actually touched, AND the triaging session can state the
causal path in one sentence. Both halves are required — file-overlap alone over-counts, and an
unfalsifiable causal story alone under-counts. **Home:** the mark sits on the finding in the run's own
report; the run record carries only the derived rate (`induced / total`), never the per-finding marks.

The eight-round series in §2 **illustrates** this rate; it does not derive it. Those attributions
exist only in that session's narrative, with no per-round artifacts to recompute them from. Field 6
starts accumulating from the next run rather than claiming a baseline.

## 10. The honest limit

Prose claim-truth is not fully mechanizable. Some share of what a document asserts about the world can
only be checked by a reader who knows the world, and no ladder of checks drives that residual to zero.

**The permanent residual is bounded by disclosure honesty, not by zero.** A named coverage boundary is
sellable; an unknown one is not. Everything above buys a smaller, better-mapped residual — never its
absence.

## 11. Self-revision clause

This document is subject to its own discipline: not a fixed verdict, a checklist to re-evaluate. If a
real run's findings don't fit these sections, or a rail here costs more than it catches, revise this
doc as part of that run's own synthesis phase — the same rule [`docs/drydock.md`](drydock.md),
[`docs/delta-audit.md`](delta-audit.md) and [`docs/release-audit.md`](release-audit.md) each state
about themselves, for the same reason: a process doc that only one run ever shaped stops being
reusable the moment a second run's lessons don't fit it.

## See also

- [`docs/delta-audit.md`](delta-audit.md) — the release-range pass; its required-diversity-leg rail is
  §5's non-waivable rule stated operatively.
- [`docs/drydock.md`](drydock.md) — the whole-tree pass; its ratchet is Clause B's demotion response.
- [`docs/release-audit.md`](release-audit.md) — the release flow both plug into; its review budget is
  where §3 lands per release.
- [`FRAMEWORK.md`](../FRAMEWORK.md) — "PR review" answers the per-round question this doc extends, and
  already carries §6's core claim.
- [`docs/delegation.md`](delegation.md) — the fan-out contract behind every parallel leg §5 asks for.
