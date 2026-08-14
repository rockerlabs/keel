# Ideas — raw-idea staging tier

Keel's own instance of the tier `templates/IDEAS.md` describes: raw ideas about Keel itself, parked so
they aren't lost to a chat transcript, and kept out of the always-loaded surfaces and the backlog until
one earns a next step. Format: `- [date] idea — context (where it came from)`. Reviewed at `/wrap` /
periodic review — promote to the backlog once actionable, or drop explicitly. (Ideas != Backlog: a next
step may never materialize, and that's fine.)

## Ideas

- [2026-08-13] **A "release conductor" mode — orchestration guidance for running a release tail as
  many parallel sessions instead of one long serial slog** — surfaced live while working the v0.6.1
  tail (dir #85's audit descendants, ~25 tickets): a chat session ended up manually doing five
  things by hand, each time from scratch, that could be a documented (or partially mechanized)
  capability instead:
  1. **Parallel-launch advice** — given a batch of open tickets, recommend how many sessions can run
     concurrently right now, grouped by file-affinity (`docs/release-audit.md` phase 3 already names
     the principle; this idea is making it something a session can ask FOR, not just follow after the
     fact) — including catching real conflicts before launch, not after (felt: dir #142 vs the
     already-running dir #135 batch both touched `tools/self/doctor.sh`; dir #123's design vs dir
     #133's batch both touch `tools/pre-pr-gate.sh` — both caught by hand, by re-reading every open
     ticket's scope one at a time).
  2. **Blocker tracking** — a lightweight dependency notation beyond the existing `⛔ BLOCKED by
     <ref>` heading tag (which is per-ticket, static) for a whole batch's live state: what's waiting
     on what RIGHT NOW, updated as PRs merge, without re-deriving it from scratch each time by reading
     every heading in the file.
  3. **Launch-prompt authoring** — most of the v0.6.1 tail tickets were spec-ready but had no
     self-contained `/go` prompt attached (unlike dir #85's four audit-module tickets, which did); a
     session ended up hand-writing ~15 of them from the ticket body, each following the same shape
     (scope from the ticket + BOTH test legs + dir #127 review budget + sandbox mandate + batch-amend
     rule). That shape is mechanical enough to template — the ticket body has almost everything
     needed already.
  4. **Target-release tag distribution** — dir #143 built the `→ 0.6.1`-style label and the
     `/backlog` grouping; what's missing is the OTHER half: triaging a pile of untagged tickets against
     the current release line in one pass (this session did it for 13 tickets in one sweep, deciding
     `→ 0.6.1` vs `→ 0.7` vs "verify it isn't already subsumed" — dir #124 turned out to be closed
     by dir #125 and nobody had noticed).
  5. **Audit-surface estimation before tagging** — `docs/release-audit.md` phase 6 already scopes the
     RC pass to three narrow checks, but nothing estimates ahead of time how big that surface is
     getting as more tickets get tagged into a release line, so a maintainer can tell early whether a
     release is trending toward "narrow RC pass" or "week-long re-audit" and split the tail into two
     releases before it's too late — the whole reason dir #85's own campaign overran was exactly this,
     found out only after ~20 tickets had already piled up (phase 2's own felt-incident note).

  **Not actionable yet as one ticket** — items 1/2/4/5 are process/documentation extensions of
  `docs/release-audit.md` and `commands/backlog.md` (on-demand methodology, matching dir #126/#128's
  own "not a rails change" boundary); item 3 could be a small `tools/` helper (a launch-prompt
  template generator fed by a ticket's own Scope/Acceptance/Model-rec fields) or stay a documented
  convention. Possible next step: a `/design` pass scoping which of the five are worth mechanizing vs.
  worth writing down as `docs/release-audit.md` phase additions vs. worth leaving as this session's own
  proof that the manual version already works. Do not build straight from this entry — reconcile
  against `docs/release-audit.md`'s current phases first, several already partially cover this (phase
  3 for #1, phase 2's triage step for #4).
- [2026-07-20] **Contributor-docs line: agent commit trailers vs the SEC4 commit-message scan** — felt
  on PR #106: a coding harness's session-URL commit trailer matched the key-shape patterns and the CI
  scan blocked the push; resolved by stripping the trailer (no allowlist, per the gate's own rule). One
  line in contributor-facing docs would save the next agent session the rediscovery.
- [2026-07-20] **The ladder from the `--no-git` trim to real always-on modules** — from the PR #106
  design discussion: the strip-generation approach was chosen over two-module composition (CORE +
  `CORE-GIT.md`, one `@import` line each) to keep the majority path unchanged; if a *third* optional
  always-on module ever materializes, switch to composition — the `KEEL-GIT` markers already fix the
  module boundary, so the migration stays mechanical. Next module candidate: the Memory section
  (`ADAPTING.md` already tells tools without cwd-keyed auto-memory to drop it). Not actionable until a
  second real module shows demand.
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
  near the Loop model (L4) in `FRAMEWORK.md`.
- [2026-08-12] **Phase-based effort routing as a complement to task-difficulty routing** — same video
  triage. `FRAMEWORK.md`'s model-selection rail routes by task difficulty; their pipeline routes by
  *pipeline phase*: design/spec sessions run at high effort, ticket implementation at low effort —
  because a well-groomed ticket has all decisions pre-made, so implementation is execution, not
  reasoning — and independent review back at high effort / a strong model. The underlying claim is
  P3-flavored and worth stating even without adopting their pipeline: *decomposition quality is what
  buys the right to cheap implementation passes* — the better the grooming, the lower the effort tier a
  ticket needs. One added sentence in the model-selection section would carry it.
