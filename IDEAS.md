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
