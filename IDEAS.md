# Ideas — raw-idea staging tier

Keel's own instance of the tier `templates/IDEAS.md` describes: raw ideas about Keel itself, parked so
they aren't lost to a chat transcript, and kept out of the always-loaded surfaces and the backlog until
one earns a next step. Format: `- [date] idea — context (where it came from)`. Reviewed at `/wrap`'s
red-flag sweep (in its mechanized outcome set since PR #213) and periodically — promote to the
backlog once actionable, or drop explicitly. (Ideas != Backlog: a next step may never materialize,
and that's fine.)

## Ideas

- [2026-07-20] **Contributor-docs line: agent commit trailers vs the SEC4 commit-message scan** — felt
  on PR #106: a coding harness's session-URL commit trailer matched the key-shape patterns and the CI
  scan blocked the push; resolved by stripping the trailer (no allowlist, per the gate's own rule). One
  line in contributor-facing docs would save the next agent session the rediscovery.
  **Dropped 2026-09-06 (first `/groom` G4(b) pass) — mooted:** `SECURITY.md` now states that the
  guard blocks agent session-metadata trailers, and `docs/reference.md`'s secret-guard row says the
  same; there is no `CONTRIBUTING.md` to carry a third copy, and a third copy is the sync-drift class
  dir #166 names. Nothing left to write.
- [2026-07-20] **The ladder from the `--no-git` trim to real always-on modules** — from the PR #106
  design discussion: the strip-generation approach was chosen over two-module composition (CORE +
  `CORE-GIT.md`, one `@import` line each) to keep the majority path unchanged; if a *third* optional
  always-on module ever materializes, switch to composition — the `KEEL-GIT` markers already fix the
  module boundary, so the migration stays mechanical. Next module candidate: the Memory section
  (`ADAPTING.md` already tells tools without cwd-keyed auto-memory to drop it). Not actionable until a
  second real module shows demand. **Reviewed 2026-09-06 (first `/groom` G4(b) pass): trigger not
  fired — no second always-on module has been asked for; kept, with this stamp so the next pass can
  see it was judged rather than skipped.** **Re-reviewed 2026-09-11 (0.10.1 groom, G4(b)): still not
  fired; kept.** **Re-reviewed 2026-09-16 (0.10.2 groom, G4(b)): still not fired — `ADAPTING.md` names
  no second always-on module and no adopter has asked for one; kept.** **Re-reviewed 2026-09-20
  (0.11.0 groom, G4(b)): still not fired — `ADAPTING.md` unchanged on this point, no adopter request
  in the 0.10.2 cycle; kept.**
- [2026-07-23] **openwiki (langchain-ai/openwiki) — auto-generated CLAUDE.md/AGENTS.md, opposite bet from
  Keel's manual curation** — surfaced while triaging six repos from an Instagram post; the only one that
  overlapped with Keel's domain (the other five dropped without action). OpenWiki synthesizes
  `CLAUDE.md`/`AGENTS.md` + a full wiki from the codebase and external sources (Notion, Gmail, X, HN) via
  an LLM agent, with CI-scheduled upkeep and Mermaid diagrams —
  vs. Keel's bet on deliberate human authorship (`PRINCIPLES.md` P0, accumulation). Possible next step:
  read `PRINCIPLES.md` / `ADAPTING.md` and decide whether (a) auto-draft-then-manually-refine is worth a
  `tools/` script (seed a first-pass CLAUDE.md from openwiki, hand off to Keel's normal flow), (b)
  CI-scheduled-upkeep or the Mermaid-diagram-map are worth borrowing standalone, or (c) the manual-only
  stance is deliberate and this gets dropped with that reasoning recorded.
  **Decided 2026-07-23 — (c): nothing ported; the manual-curation stance is deliberate. Entry closed.**
  Checked against `PRINCIPLES.md` and `ADAPTING.md`; four independent reasons, any one sufficient:
  (1) an auto-draft script would be the first model-calling tool in `tools/`, whose documented contract
  is "plain Bash + git — they never call a model" (`ADAPTING.md`); breaking that breaks the layer's
  substrate-independence, which is its whole point. (2) The auto-draft-then-refine value already exists
  in Keel's own shape: `/init-project` scaffolds the skeleton and the session agent drafts from the live
  codebase with the human judging in the loop — same outcome, P1-compliant, no new tool; and no adopter
  has asked for a batch variant, so building one fails P4's felt-friction gate. (3) CI-scheduled
  regeneration makes the always-loaded context volatile and removes the human verifier — directly
  against P3 ("stability of the loaded set") and P1 ("the system that can hallucinate cannot be the
  sole judge"). (4) OpenWiki's product is a codebase *description* — derivable-from-code content Keel
  deliberately keeps OUT of curated context (a Keel `CLAUDE.md` banks decisions, constraints, and felt
  incidents — exactly what code cannot show); the Mermaid map falls under the same rule, derivable on
  demand by any session that needs it. Reopen trigger: a real second consumer (P0) asking for cold-start
  bootstrap of a large existing codebase — that is felt friction; revisit option (a) then.
- [2026-07-23] **Positioning: the derivable-context layer is commoditizing — sharpen the pitch around
  the non-derivable layer** — follow-up to the openwiki entry above. Auto-generation tools (openwiki
  and its kin) compete for the same `CLAUDE.md`/`AGENTS.md` slot and may teach the market that
  "context" means scheduled auto-generation. Not a functional threat — they fill the slot with the
  derivable layer while Keel banks the non-derivable one (reason (4) above), and the two even compose —
  but a positioning one: the adopter who believes the generated wiki *is* their context never hears the
  difference. By P0's own frame the trend is favorable — commoditizing the derivable layer raises the
  relative value of captured non-derivable capital — but only if the pitch says so out loud. Possible
  next step: make "Keel keeps what cannot be derived from the code" a load-bearing line in the README /
  pitch surfaces. Promote to `BACKLOG.md` once a concrete pitch-surface edit is picked.
  **Promoted 2026-09-06 (first `/groom` G4(b) pass) to dir #400** — the concrete edit is picked
  there (one load-bearing README line), and it sits in the value-pitch lane the v0.9.0 sprint is about.
- [2026-08-12] **Session-handoff artifact — a candidate fix for the named L4 mid-task-checkpoint gap** —
  from triaging a practitioner's agent-pipeline video (transcript supplied in chat; the pipeline builds
  on a public skills repo — grill/wayfinder/handoff — links live in the author's channel, repo not
  independently verified). Their `handoff` skill writes a small MD artifact on interruption or
  session/model switch: what was achieved, where work stopped, which artifacts carry forward — the
  explicit principle being *"between sessions, only artifacts pass"* (code + MD files), never raw
  context. This is precisely `FRAMEWORK.md`'s known gap "L4 has no mid-task checkpoint, so a
  long-running ticket interrupted mid-session loses its plan state" — and Keel already has a narrower
  cousin (`/polish`'s same-SHA hand-off note via `tools/pre-pr-gate.sh handoff`), so the shape is
  proven in-house. Possible next step: a ticket-level checkpoint convention (where the note lives, what
  three fields it carries, when `/go` writes and consumes it) — P2-native, no new tool required.
  **Promoted 2026-09-06 (first `/groom` G4(b) pass) to dir #401.**
- [2026-08-12] **Interview-loop refinements: frontier rounds, a closing shared-understanding gate, and
  prototype-resolved forks** — same video triage. Three mechanics their "grilling" skill adds over
  `FRAMEWORK.md`'s Interview loops section: (1) *frontier questions* — each round batches exactly the
  questions for which enough context has accumulated, then rebuilds the decision tree from the answers
  before computing the next round (a crisper operational rule than "sequential when branching, batched
  when independent" — it unifies the two); (2) the loop ends with an explicit *shared-understanding
  confirmation* — the agent restates the agreed behavior and the human confirms or reopens, so passive
  skim-and-agree on a generated plan is structurally prevented; (3) a fork that can't be resolved in
  text (UI layout, state-machine logic) is resolved by a *disposable prototype artifact answering one
  question* — 3–5 radically different variants, not one variant in three colors. All three are
  section-sized edits to the existing Interview loops rail, not new machinery.
  **Promoted 2026-09-06 (first `/groom` G4(b) pass) to dir #402, bundled with the two entries below
  from the same triage — one `FRAMEWORK.md` touch, three section-sized edits.**
- [2026-08-12] **Ticket decomposition rails: fits-one-fresh-session sizing, behavior-named vertical
  slices, and ticketed design stages** — same video triage. Their pipeline sizes every ticket to fit
  one fresh-context session *including tests, review, and report* (context budget as the splitting
  criterion — even asking the agent "will this ticket fit one context?" at grooming time); names
  tickets by the observable behavior they add, never by layer ("DB schema", "the API") — so every
  ticket lands as a verifiable vertical slice with blocking dependencies named; and when the *design
  itself* exceeds one session ("wayfinder"), the design questions are themselves ticketed and each gets
  its own interview session, converging into one spec with an explicit out-of-scope-with-reasons
  section. Keel's `/go` already assumes a groomed ticket with a done-criterion; these are the missing
  grooming-side rules that make that assumption hold. Candidate home: a short decomposition subsection
  near the Loop model (L4) in `FRAMEWORK.md`. **Promoted 2026-09-06 to dir #402 (bundled).**
- [2026-08-12] **Phase-based effort routing as a complement to task-difficulty routing** — same video
  triage. `FRAMEWORK.md`'s model-selection rail routes by task difficulty; their pipeline routes by
  *pipeline phase*: design/spec sessions run at high effort, ticket implementation at low effort —
  because a well-groomed ticket has all decisions pre-made, so implementation is execution, not
  reasoning — and independent review back at high effort / a strong model. The underlying claim is
  P3-flavored and worth stating even without adopting their pipeline: *decomposition quality is what
  buys the right to cheap implementation passes* — the better the grooming, the lower the effort tier a
  ticket needs. One added sentence in the model-selection section would carry it. **Promoted
  2026-09-06 to dir #402 (bundled).**
- [2026-08-17] **Capability-split delegation pipeline: read-only analysis fans out to cheap spawned
  subagents, gated mutation stays in serialized operator sessions** — surfaced designing drydock
  (dir #165) and field-tested by its run 1 the same day. **Promoted the same day to dir #171** —
  the run's empirics fired this entry's own promotion trigger; the pattern, the measured field test,
  the "wrap duties are centralized" worker-marker lesson, and the design mandate all live in that
  ticket now.
- [2026-09-20] **A "System One" leg for keel's triage layer — TypeSafe AI's Jev** — surfaced while
  reading the Jev launch (a non-autoregressive model: state + typed questions in, typed answers with
  calibrated probabilities out, ~70–500 ms, output tokens free; early access opened 2026-09-20). Keel's
  decision surface has three layers, and Jev fits exactly one: NOT the deterministic gates
  (`pre-pr-gate`, `doctor`, `secret-guard` must stay bash-only, offline, reproducible — a probabilistic
  network call there is a regression), NOT the deep review legs (find-rate tracks reviewer novelty and
  depth per `docs/verification-economics.md` §2, and Jev's output is itself a claim, never a
  verification), but the TRIAGE middle that today is either a noisy heuristic or a full LLM round.
  Candidates, best first: (A) finding triage in delta-audit/drydock — `{new|known class, class_id,
  severity, duplicate-of}` with a confidence, escalating below-threshold items to a human; past
  adjudications in `private/audit/` are labeled data, so the experiment is checkable; (B) escalation
  in the audit harness — a cheap "does this hunk plausibly carry a defect of class X?" pass to decide
  which files earn a `deepseek-reasoner` round (it exhausts its completion budget on reasoning), as
  prioritization, never a stopping rule; (C) a second-stage filter over `tools/self/prose-drift.sh`'s
  WARN signal, which self-describes as unable to tell a truncated edit from a long sentence.
  Weaker: `/wrap`'s red-flag classification (volume too low to matter), backlog duplicate detection
  (context size). NOT a candidate: `keel-impact` — the "model judges with citations, script counts"
  split is what makes the number honest; a cheaper judge loses the citations. Constraints: keel is
  publication-first and tool-independent, so any Jev use is an opt-in leg (like the Gemini G6 leg and
  the DeepSeek harness — `private/` or a flagged tool degrading to "as before" without a key), never
  in the always-on path or `install.sh`; key via env. Next step, per dir #344's lesson (measure a
  proposed checker's noise before building it): one evening's experiment on candidate (A) — run
  already-adjudicated findings through Jev, score agreement with the human verdict AND calibration
  (is p>0.9 right ~90 % of the time). Calibrated → (B) and (C) become near-free; not → close with a
  number, not an opinion. **Promoted 2026-09-21 to dir #613** (spec-ready, a design pass): the
  experiment as designed there, with the API verified live against an early-access key — `jev-latest`
  → `jev-1.13.0`, ~1 s per request, a 72 KB state accepted, a $5 monthly credit that covers the whole
  run ~500×.
  **Outcome (2026-09-21, dir #613 phase 1):** NOT calibrated — closed with the number, no phase-2
  ticket. 43 already-adjudicated findings from 4 delta runs, both state conditions (finding-only /
  finding+hunk): REFUTED-recall 0.636/0.545, REFUTED-precision 0.280/0.261, ECE 0.291/0.313 — below
  bar (≥0.70 / ≥0.60 / ≤0.10) on every axis, both conditions. `holds`'s class-conditional means are
  statistically indistinguishable (0.421 vs 0.448) — no signal, not a threshold problem. `severity`:
  0% exact agreement across 32 scored rows despite ≈95% stated confidence — confidently wrong rather
  than usefully uncertain. Candidates (B) and (C) inherit this result per this entry's own framing
  and are not separately tested. Full report:
  `private/audit-harness/jev/runs/20260921T122220Z/REPORT.md`; narrative:
  `private/audit/RUNS.md`'s Jev section.
