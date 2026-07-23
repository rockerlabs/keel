# Ideas — raw-idea staging tier

Keel's own instance of the tier `templates/IDEAS.md` describes: raw ideas about Keel itself, parked so
they aren't lost to a chat transcript, and kept out of the always-loaded surfaces and the backlog until
one earns a next step. Format: `- [date] idea — context (where it came from)`. Reviewed at `/wrap` /
periodic review — promote to the backlog once actionable, or drop explicitly. (Ideas != Backlog: a next
step may never materialize, and that's fine.)

## Ideas

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
  Keel's manual curation** — surfaced while triaging 6 repos from an Instagram post; the only one that
  overlapped with Keel's domain (the other 5 — claude-video, meetily, system_prompts_leaks, colibri,
  pocket-tts — are out of domain: video/meeting/TTS tools, a leaked-prompts dump, an LLM runtime; no
  action taken on those). OpenWiki synthesizes `CLAUDE.md`/`AGENTS.md` + a full wiki from the codebase and
  external sources (Notion, Gmail, X, HN) via an LLM agent, with CI-scheduled upkeep and Mermaid diagrams —
  vs. Keel's bet on deliberate human authorship (`PRINCIPLES.md` P0, accumulation). Possible next step:
  read `PRINCIPLES.md` / `ADAPTING.md` and decide whether (a) auto-draft-then-manually-refine is worth a
  `tools/` script (seed a first-pass CLAUDE.md from openwiki, hand off to Keel's normal flow), (b)
  CI-scheduled-upkeep or the Mermaid-diagram-map are worth borrowing standalone, or (c) the manual-only
  stance is deliberate and this gets dropped with that reasoning recorded. Promote to `BACKLOG.md` once
  one of these earns a real next step.
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
  "context" means scheduled auto-generation, making manual curation look archaic by association. Not a
  functional threat — they fill the file with derivable-from-code description, while Keel banks
  decisions, constraints, and felt incidents (what code cannot show), and the two even compose — but a
  positioning one: the adopter who believes the generated wiki *is* their context never hears the
  difference. By P0's own frame the trend is favorable — commoditizing the derivable layer raises the
  relative value of captured non-derivable capital — but only if the pitch says so out loud. Possible
  next step: make "Keel keeps what cannot be derived from the code" a load-bearing line in the README /
  pitch surfaces. Promote to `BACKLOG.md` once a concrete pitch-surface edit is picked.
