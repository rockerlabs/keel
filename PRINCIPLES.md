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

## P0 — Telos: invest in what doesn't devalue

The goal of the whole activity is to accumulate **non-depreciating capital**: transferable *judgment*
(problem decomposition, knowing what context a reasoner needs, verification/calibration,
information-architecture taste, domain modeling) + *captured domain knowledge* (the project memories and
decisions earned through real friction). These survive any change of model, harness, or tool.

- **Mechanism depreciates** — specific files, hooks, indexing schemes, token budgets tuned to today's
  harness. Keep it thin and disposable.
- **Devaluation risk is concentrated entirely in the mechanism layer.** The platform absorbing a
  mechanism (native memory/retrieval) is an *upgrade*, not a loss: your content and judgment port onto
  it. The platform cannot absorb *your* content (your specific projects and decisions).
- **Universality axes serve durability, not decoration.** Portability / scale-invariance /
  substrate-independence are how captured capital survives a platform shift. "Reusable by another person"
  is *optionality without sunk cost*: keep the reusable/personal seam clean so sharing is *possible*, but
  do not invest in distribution (docs, packaging, generalization) until a real second consumer exists.
- **Engine:** after any task done in a substrate-specific way, extract the substrate-independent lesson
  and capture *that* — the principle, not the recipe. Recipes depreciate; principles compound. This habit
  is what turns disposable mechanism into durable capital.

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

## P3 — Attention, not cost, is the binding constraint

Optimization is real but subordinate: below P1 it doesn't exist; above P1 it serves P2. The thing being
optimized is routinely misidentified — cost and latency are visible, but the real constraint is *attention
and signal-to-noise*. Two correctives:

- **Over-dense compression hurts retrieval** — a clearer, slightly longer statement the model gets right
  the first time is cheaper in effect than a compressed one that triggers a correction round-trip.
- **Stability of the loaded set often matters more than its size.** A smaller but volatile set that
  changes every session is worse than a slightly larger stable one — because every change busts whatever
  cache or warm state the runtime maintains. Prefer *stability* over raw minimality. *(On hosted models
  with prompt caching this is especially strong; on local models the same logic applies to context
  reuse and warm KV state.)*

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

*Most tensions above are honest habits or guidelines, not mechanisms — that is the normal state. Mechanize
a tension only when its absence has actually bitten (P4); a balance you've never seen fail doesn't yet need
a machine.*

**Revision ritual (the only improvement engine):**

- **Per-session (cheap):** if the session surfaced friction that contradicts a principle here, note or
  revise it; otherwise skip silently. Most sessions add nothing — that is correct.
- **Periodic (deeper):** re-read the tensions; for each, confirm its enforcement still exists and runs;
  surface any tension that has drifted to "unenforced — risk." This is where principles are actually
  edited.

---

*The durable principles here (working set / locality / retrieval, invest in judgment not tooling) predate
any specific model or framework — the occasion was applying them explicitly to long-running human–AI
knowledge work.*
