# Principles

Five durable principles for human–AI knowledge work. They are meant to outlive any specific model,
tool, or workflow — mechanisms change, these do not. P0 is the foundation (why this activity exists);
P1–P4 are operating principles in service of it.

*Open this when making a foundational decision, or when a decision feels like it trades one principle
against another.*

## How to read this

These are NOT a weighted checklist. **P0 is the *telos*** (why the whole activity exists); **P1–P4 are
operating principles in service of it.** They carry deliberate internal tension — each bounds the others,
so no single principle taken to its extreme wins (a purely lexicographic order is brittle;
tension-with-bounds is robust). When two pull apart in a concrete moment, that tension is the signal to
think, not a bug to remove. The named tensions and how each is held honest are in
"How these principles stay alive" at the end.

## Load-bearing terms

Only the terms the principles actually lean on — defined here so a reader (or a second consumer) doesn't
grab the wrong sense mid-decision.

- **Mechanism** — the disposable layer: files, hooks, indexing schemes, token budgets, prompts tuned to
  today's harness. Depreciates *by design*; keep it thin.
- **Judgment (core vs shell)** — transferable skill, but itself two-layered. *Core* is problem-/domain-facing
  (decompose, model the consumer's knowledge gap, verify, model the domain) and durable. *Shell* is
  consumer-calibrated (tuned to a specific model's current limits) and depreciates like mechanism — it dies
  when the model changes. The 10× test in P0 separates them.
- **Captured domain knowledge** — your specific projects, decisions, and memories earned through real
  friction. The one thing no platform can absorb.
- **Harness / substrate** — the runtime that hosts and drives the reasoner: the CLI/app, retrieval,
  caching, the context window. Used interchangeably; both name the *swappable* environment a model runs in.
- **Tiering** — splitting knowledge into a small, stable, always-loaded core plus an on-demand rest. A
  mechanism in service of P2/P3, not a principle itself.
- **Working set / loaded set** — what is actually in the reasoner's context at a given moment (the two
  phrases are synonyms across these principles).

## P0 — Telos: invest in what doesn't devalue

The goal of the whole activity is to accumulate **non-depreciating capital**: transferable *judgment*
(problem decomposition, knowing what context a reasoner needs, verification/calibration,
information-architecture taste, domain modeling) + *captured domain knowledge* (the project memories and
decisions earned through real friction). These survive any change of model, harness, or tool — with one
caveat the seam below makes precise: only their *problem-/domain-facing core* ports cleanly.

- **Mechanism depreciates** — specific files, hooks, indexing schemes, token budgets tuned to today's
  harness. Keep it thin and disposable.
- **Devaluation risk is concentrated *mostly* in the mechanism layer — but the seam runs through
  judgment too.** The platform absorbing a mechanism (native memory/retrieval) is an *upgrade*, not a
  loss: your content and judgment port onto it; the platform cannot absorb *your* content (your specific
  projects and decisions). The catch: *judgment is itself layered*. It has a durable **problem-/domain-facing
  core** (decompose, model the consumer's knowledge gap, verify, model the domain) and a depreciable
  **consumer-calibrated shell** (granularity tuned to a model's capability, "always include X because this
  model forgets it," a chunk size that fits today's retrieval). The shell is *called* judgment but behaves
  like mechanism — it dies when the model changes. Test: *would this still hold if the model were 10× more
  capable?* If not, it's shell, not core.
- **Universality axes serve durability, not decoration.** Portability / scale-invariance /
  substrate-independence are how captured capital survives a platform shift. "Reusable by another person"
  is *optionality without sunk cost*: keep the reusable/personal seam clean so sharing is *possible*, but
  do not invest in distribution (docs, packaging, generalization) until a real second consumer exists.
- **Engine:** after any task done in a substrate-specific way, extract the substrate-independent lesson
  and capture *that* — the principle, not the recipe. Recipes depreciate; principles compound. This habit
  is what turns disposable mechanism into durable capital — and it is the same move that distills the
  depreciable *shell* of a judgment into its durable *core*.

## P1 — Gate: calibrated correctness

A tool/approach is useful **iff** it produces *verifiably correct* results AND honestly marks the
boundary of its confidence. A confidently-wrong answer is worse than an honest "can't" — it costs a
wasted debugging cycle and erodes trust. Economy, speed, and elegance do not exist below this gate.

- "Solved" means *demonstrably* solved (test / reproduction / source). The system that can hallucinate
  cannot be the sole judge of its own correctness — verification must be external to the claim.
- **P1 is how P0 is kept honest.** "I'm building skill" is an unfalsifiable story unless the skill
  produces correct results; real capability is *proven* by demonstrable correctness, not asserted.

## P2 — Context serves correctness

Context/knowledge management exists to serve P1, not to save money. Curation, tiering, and
single-source-of-truth exist because *noise causes hallucination* (the model grabs a stale/wrong fact,
or drowns). The objective is to maximize the model's hit-rate on the needed fact while keeping the
always-loaded set small, stable, and clear. Token-saving is a side effect, not the goal.

## P3 — The binding constraint is the reasoner's attention, not the visible meters

Optimization is real but subordinate: below P1 it doesn't exist; above P1 it serves P2. The trap is
optimizing the *visible proxy* (token count, cost, latency) instead of the actual scarce resource: the
reasoner's attention and the signal-to-noise of what it must process. Whenever you shrink a visible
meter, ask whether you're spending *more* of the real constraint to save the proxy. Two correctives:

- **Compression past clarity is negative-sum.** A statement dense enough to misparse costs a correction
  round-trip — which consumes far more attention than the bytes it saved. Optimize for first-pass
  correctness, not minimal size: the cheapest message is the one the reasoner gets right once.
- **Stability of the loaded set is a self-standing asset, and its primary justification is epistemic, not
  performance.** A smaller but volatile set that changes every session is worse than a slightly larger
  stable one — because a context that shifts under you destroys reproducibility and makes any change of
  behavior un-attributable (your edit, or context drift?). Stability is what makes the system
  *diagnosable under P1*. *(Depreciable mechanism bonus: on substrates with prompt-caching / warm KV
  state, stability also buys a direct latency/cost win — a side effect, not the reason.)*

## P4 — Build from friction, not from completeness

Every element of this system — a rule, a file, a tool, a convention — must earn its place by solving a
real, felt problem. Don't add structure because it seems correct or complete in the abstract; add it when
its absence has demonstrably caused a problem.

**The prophylactic exception:** for failure modes that are irreversible or high-severity (a leaked
credential, a destructive git operation), build the guard before the first incident. Cost-of-first-failure
× irreversibility justifies prevention without prior friction. This is a narrow carve-out, not a general
license to build speculatively.

**Why this is a principle, not a guideline:** without it, any motivated reasoner can justify adding
anything. The felt-friction test is the only check that keeps the system lean as it grows.

## How these principles stay alive

This set is **not self-improving** — there is no closed loop inside the document. It improves only from an
*external* signal: real friction from use. A principle changes when reality contradicts it. The human +
reality close the loop; the document does not improve itself. (Trying to make principles perfect "in the
abstract" is recursive over-engineering — it violates P0 and must itself pass the felt-friction test.)

**The human's role is not optional.** The AI surfaces, proposes, and executes; the human judges what
constitutes real friction, decides what to persist, and verifies correctness. Any setup that removes the
human from the verification loop violates P1 structurally — the system that can hallucinate cannot be
the sole judge of its own output.

**What counts as friction here:** for a methodology project whose "use" *is* thinking-with-it, a
conceptual gap exposed by engaging a new idea is valid friction — not only an operational breakage. That
is exactly how a foundation like this gets born: a new idea exposes the absence of a foundation, and the
gap is the friction that justifies building one.

**Success test for this foundation:** the *next* seemingly-threatening concept — a shiny new idea that
appears to undermine the approach — should be absorbed *cheaply* (a parked note / a changelog row), NOT
trigger another foundational restructuring. The first such event correctly produces a foundation because
none existed; a *recurring* need for an existential rewrite per concept is the signal the foundation has
failed — and is itself the meta-trap above.

**Falsifiers — the outcomes this set must not be allowed to spin.** P0's reflexes (a poached mechanism is
an *upgrade*; a threatening idea is *friction*; a wrong principle is the *loop working*) can reframe almost
any single event as a win — which is exactly why the set needs tests that point-reframing cannot reach: a
*rate*, a *ledger*, a *measurement*. Three:

- **Net-negative ledger.** Capital captured must exceed the overhead to capture it (curation, red-flag
  sweeps, the ritual). If maintaining the system costs more attention than the judgment + knowledge it
  banks, the telos has failed — and "the upgrade ported your content" is no defense, because the apparatus
  cost more than its output. *Minimal instrument (guideline): at each periodic review, score the last
  stretch red/amber/green — did capture + maintenance cost more attention than the judgment/knowledge it
  banked returned? A rough rating is enough to catch a sustained red; a real denominator can wait until a
  red actually shows.*
- **Transfer failure.** P0's central promise — capital survives a change of model/harness/tool — is
  measurable: actually move substrates and check how much "durable" capital ports vs. how much was secretly
  consumer-calibrated *shell* (see the seam in P0). If most of it needs rewriting on transfer, the promise
  is falsified *by measurement*, not absorbed as an upgrade. *Minimal instrument (guideline):
  event-triggered — the next time you actually change model/harness, before re-explaining anything, write
  down what ported unchanged vs. what you had to rebuild. That delta is the measurement; no upfront tooling
  needed.*
- **Recurring existential rewrite.** Stated just above: one foundational rebuild is healthy; *every*
  concept forcing one is failure. *(The only falsifier currently written down.)*

Adding the first two is itself a friction-driven edit (P4), not a prophylactic one — the gap was surfaced
by engaging this critique, which is exactly the "conceptual gap exposed by a new idea" that counts as valid
friction here.

**Self-balancing is real only as far as each tension is mechanized.** Principles have no agency — they do
not enforce themselves. Each named tension below must be backed by a check or a ritual that actually runs;
an unenforced balance is a wish, not a mechanism.

**Capture is real only as far as it's checked.** P0's "capture the lesson" habit is itself a wish unless a
step confirms it happened. So every session should end with a **red-flag sweep**: anything surfaced in the
session — an idea, a finding, a decision, a loose-end — must be persisted (a backlog ticket / changelog /
memory) or explicitly dropped with its reason before closing; nothing stays chat-only (the next session
starts cold and won't recall it; the human forgets).

*Enforcement types — **mechanism**: automated, checked by tooling, runs without a human step;
**guideline**: a written convention applied at human judgment; **habit**: purely behavioral, no check
confirms it ran.*

| Tension | What it guards | Enforcement | Type |
|---|---|---|---|
| **P0 ↔ P1** | skill-building must not excuse a wrong/unverified result; correctness must not over-fit to ephemeral mechanism | an explicit verify-discipline convention + the P0 "extract the transferable lesson" habit | **habit + guideline** |
| **P1 ↔ P3** | economy/speed must never buy a wrong answer | "no optimization below the gate" — checked at review | **guideline** |
| **P2 ↔ P3** | minimizing tokens must not strip context that prevents hallucination | structural tiering that runs + is tooling-checked (the reusable/personal seam, a thin index that points rather than dumps, a startup-footprint budget); cache-aware placement + retrieval-miss capture as conventions | **mechanism** |
| **P0 ↔ P4** | accumulating capital must not become speculative building; friction-gating must not become an excuse to skip capturing what was genuinely earned | P4's prophylactic carve-out (irreversibility test) + P0's red-flag sweep at session end | **habit + guideline** |
| **P0 ↔ P1 (self-calibration)** | the set's reflexes (upgrade / friction / loop-working) must not let it spin every outcome into a win and become unfalsifiable | the three Falsifiers above — net-negative ledger, transfer failure, recurring existential rewrite (a *ledger*, a *measurement*, a *rate* — the tests point-reframing cannot reach) | **guideline** *(ledger + transfer carry minimal rituals; promote to mechanism only when one actually fires)* |

*Most tensions above are honest habits or guidelines, not mechanisms — that is the normal state. Mechanize
a tension only when its absence has actually bitten (P4); a balance you've never seen fail doesn't yet need
a machine.*

**Revision ritual (the only improvement engine):**

- **Per-session (cheap):** if the session surfaced friction that contradicts a principle here, note or
  revise it; otherwise skip silently. Most sessions add nothing — that is correct.
- **Periodic (deeper) — triggered, not calendar-based:** run this on any substrate change (model/harness),
  whenever a falsifier fires, or — absent either — no more than a couple of times a year. Re-read the
  tensions; for each, confirm its enforcement still exists and runs; surface any tension that has drifted to
  "unenforced — risk"; and run the ledger score. This is where principles are actually edited.

---

*The durable principles here (working set / locality / retrieval, invest in judgment not tooling) predate
any specific model or framework — the occasion was applying them explicitly to long-running human–AI
knowledge work.*

---

## Changelog

This is the "changelog row" the success test points to — the cheap place a new idea lands instead of
triggering a foundational rewrite. Each row: date, what changed, the friction that justified it.

- **2026-06-26** — P3 re-anchored on P1: "stability > size" now justified by reproducibility /
  attributability, not cache/KV-state; transformer specifics demoted to a labeled, depreciable mechanism
  bonus. *Friction: the principle's strongest claim rested on its most depreciable argument.*
- **2026-06-26** — P0: acknowledged the durable/depreciable seam runs *through* judgment (problem-/domain-facing
  core vs consumer-calibrated shell) + added the 10× test. *Friction: P0 banked as "non-depreciating" parts
  of judgment that actually die on a model change — including Keel's own core pitch.*
- **2026-06-26** — Added the **Falsifiers** block (ledger / transfer / recurrence) and the **P0 ↔ P1
  self-calibration** tension row. *Friction: the set's reflexes could spin any single outcome into a win,
  i.e. it was unfalsifiable — a P1 violation.*
- **2026-06-26** — Instrumented the ledger + transfer falsifiers to guideline-level rituals and gave the
  periodic review a trigger. *Friction: an uninstrumented falsifier is a "wish" by the doc's own line — and
  the changelog this list points to did not yet exist.*
- **2026-06-26** — Added a **Load-bearing terms** glossary. *Friction: P2 risk — load-bearing terms
  (judgment core/shell, mechanism, harness/substrate, tiering) were undefined, inviting a wrong-sense grab
  mid-decision, especially for a second consumer.*
