# Keel impact ledger

**Frozen historical artifact.** Live scoring moved to `.keel/ledger.md` when this checkout got its own
impact-tracking marker (2026-07-20), and moved again with dir #251 (2026-08-22) to an external store —
`$KEEL_HOME/.keel/impact/<project-id>/ledger.md`, never inside the project's own tree. This file's rows
below are not updated any further; it is kept as a record of Keel's earliest dogfooding history. **One
exception:** dir #10's own decided plan calls for a one-off public snapshot of the (private, gitignored)
live ledger's aggregate once enough sessions accumulate — that snapshot is appended below as its own
dated section, not a resumption of the frozen rows above it.

One row per scored session. The score is **derived, not asserted**: `commands/keel-score.md` gathers counted,
cited events; `tools/keel-impact.sh` computes the 0-100 number from them by a fixed formula, so it is a pure
function of the evidence and cannot be inflated by vibe. This is the quantified form of the wrap-time
promote/demote ritual (`FRAMEWORK.md` → "Retrieval miss = the promote signal.").

Columns: **score** = round(100·HELP/(HELP+COST)) where HELP=4·hold+3·guard+2·fire+hit, COST=2·miss+2·friction
(`—` = no events, nothing to measure). **conf** = evidence-count tier (none/low/med/high) — a score behind
few events is weaker; a `-retro` suffix marks a quarantined retrospective score. Event counts: **guard**
guardrail blocked bad content · **hold** keel restrained the agent from bypassing a rule (its highest
function; scores above guard) · **fire** rule applied · **hit** retrieval hit · **miss** retrieval miss
(promote pressure) · **fric** friction (demote pressure) · **silent** always-loaded rules that did not fire
(demote candidates; NOT folded into the score).

**guard** is collected deterministically: in a tracked repo (an enabled external store entry, or
`$KEEL_IMPACT_LOG`) the guardrail hooks (`secret-guard`, `pre-pr-gate`, `public-audit`) record each fire to
a zero-token event log that `add` auto-ingests — the objective signal never depends on the model counting it.

Each count equals the number of cited events behind it; the **evidence** cell shows only the single strongest
citation, and the full per-event trail (every event → its citation) lives in `keel-impact-evidence.md`
next to this file (in an installed project's external store the same file is named `evidence.md`).

| date | score | conf | guard | hold | fire | hit | miss | fric | silent | evidence | gap (demote/promote) |
|------|-------|------|-------|------|------|-----|------|------|--------|----------|----------------------|
| 2026-07-20 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | SEC4 server-side secret-scan (CI run 29722488680, PR #104) blocked agent session-metadata trailers (Claude-Session:) in commit messages 1dfb7d0 + 1d30f73; fixed by history rewrite (filter-branch), not by allowlisting | none — session ran in a container with no always-on Keel layer, so only the mechanized tier could produce events |
| 2026-07-20 | 100 | med | 1 | 0 | 0 | 2 | 0 | 0 | 0 | SEC4 ci-scan blocked PR #106 push (secret-scan job, 2026-07-20): the coding harness's session-URL commit trailer in both commit messages matched the key-shape patterns; resolved by stripping the trailer via filter-branch (no allowlist added, per the gate's own rule), scan clean on re-push | contributor-docs candidate: agent commit trailers carrying session URLs trip the SEC4 commit-message scan — one line in contributor docs would save the next agent session the rediscovery |

## Public snapshot (v0.9.0, taken 2026-09-06)

The rows above are historical only. This section is the reviewed, one-off SNAPSHOT that dir #10's
2026-07-12 decision (this project's own backlog, not part of the public tree) called for once enough
sessions had accumulated: the live ledger
and its evidence file stay private and gitignored (`$KEEL_HOME/.keel/impact/<project-id>/`) — never
committed — this published aggregate is the exception. It covers keel's own dogfooding of itself, from
`.keel/` tracking going live on 2026-07-20 through 2026-09-06.

**Aggregate, recomputed live via `tools/keel-impact.sh rollup` against the current ledger:**

| metric | value |
|---|---|
| sessions scored | 55 |
| mean score | 87.9 / 100 |
| median score | 88 / 100 |
| range | 55 – 100 |
| cumulative guardrail fires | 61 |
| cumulative agent-holds | 31 |
| cumulative retrieval misses | 34 |
| recent trend (last 5, chronological) | 100 → 75 → 71 → 100 → 85 |

**What this score is, and isn't.** Per `commands/keel-score.md`'s own calibration note: *"cited events
still lean on your guess of what a cold session would do... distrust a long high-score trend until an
A/B backs it."* These 55 rows are in-session estimates with citations, not a controlled experiment — the
ground truth they were waiting on was dir #94's Keel-vs-cold A/B (four README-claimed properties, run
once by hand; iteration 1 measures three — accumulation is out of scope, see below). **It has now run**
— see [`docs/keel-ab.md`](keel-ab.md) (2026-09-07): a positive economy delta and a symmetric stability
miss both arms shared. **This does not change the calibration note's warning.** The run is N=1 — an
anchor, not statistics (`keel-ab.md`'s own limit L1) — so the trend above is still not backed by
repeated evidence; treat this snapshot with the same caution as before, now with one real data point
behind it instead of zero.

**One evidence excerpt, verbatim** (from `.keel/impact/<project-id>/evidence.md`, 2026-09-05, score
87/100, a release-manager session — no session or path identifiers beyond backlog ticket numbers, so
nothing here needed redaction):

> - hold: [v0.8.3 manager] R5 enforced twice against worker claims of unpushed work — refused GO until
>   branch on remote, preventing verification-by-report
> - fire: [v0.8.3 manager] R8 single-writer: all BACKLOG writes routed through manager across 8 sessions,
>   zero write races (vs 3 collisions on v0.8.2)
> - hit: [v0.8.3 manager] pre-pr-gate [24x] memory relayed into every worker brief (no-amend-after-receipts,
>   slot serialization) — workers avoided the worst class
> - miss: [v0.8.3 manager] no pre-loaded fact on how a manager launches real gated sessions in this
>   harness — discovered spawn_task path by tool enumeration mid-intake (R3 soft-form support)

**Cost, for context.** Ritual overhead is not free: a per-pipeline-stage measurement (dir #313's
investigation, two sessions' cache-read shares) found `/keel-score` itself costs **~12%** of a session's
cache-read volume — comparable to the implementation work it's measuring (`/go` at 10-12%).
