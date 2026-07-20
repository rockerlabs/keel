# Keel impact ledger

One row per scored session. The score is **derived, not asserted**: `commands/keel-score.md` gathers counted,
cited events; `tools/keel-impact.sh` computes the 0-100 number from them by a fixed formula, so it is a pure
function of the evidence and cannot be inflated by vibe. This is the quantified form of the wrap-time
promote/demote ritual (`FRAMEWORK.md` → "retrieval miss = promote signal").

Columns: **score** = round(100·HELP/(HELP+COST)) where HELP=4·hold+3·guard+2·fire+hit, COST=2·miss+2·friction
(`—` = no events, nothing to measure). **conf** = evidence-count tier (none/low/med/high) — a score behind
few events is weaker; a `-retro` suffix marks a quarantined retrospective score. Event counts: **guard**
guardrail blocked bad content · **hold** keel restrained the agent from bypassing a rule (its highest
function; scores above guard) · **fire** rule applied · **hit** retrieval hit · **miss** retrieval miss
(promote pressure) · **fric** friction (demote pressure) · **silent** always-loaded rules that did not fire
(demote candidates; NOT folded into the score).

**guard** is collected deterministically: in a tracked repo (an enabled `.keel/` marker, or `$KEEL_IMPACT_LOG`)
the guardrail hooks (`secret-guard`, `pre-pr-gate`, `public-audit`) record each fire to a zero-token event
log that `add` auto-ingests — the objective signal never depends on the model counting it.

Each count equals the number of cited events behind it; the **evidence** cell shows only the single strongest
citation, and the full per-event trail (every event → its citation) lives in `keel-impact-evidence.md`
next to this file (in an installed project's `.keel/` dir the same file is named `evidence.md`).

| date | score | conf | guard | hold | fire | hit | miss | fric | silent | evidence | gap (demote/promote) |
|------|-------|------|-------|------|------|-----|------|------|--------|----------|----------------------|
| 2026-07-20 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | SEC4 server-side secret-scan (CI run 29722488680, PR #104) blocked agent session-metadata trailers (Claude-Session:) in commit messages 1dfb7d0 + 1d30f73; fixed by history rewrite (filter-branch), not by allowlisting | none — session ran in a container with no always-on Keel layer, so only the mechanized tier could produce events |
| 2026-07-20 | 100 | med | 1 | 0 | 0 | 2 | 0 | 0 | 0 | SEC4 ci-scan blocked PR #106 push (secret-scan job, 2026-07-20): the coding harness's session-URL commit trailer in both commit messages matched the key-shape patterns; resolved by stripping the trailer via filter-branch (no allowlist added, per the gate's own rule), scan clean on re-push | contributor-docs candidate: agent commit trailers carrying session URLs trip the SEC4 commit-message scan — one line in contributor docs would save the next agent session the rediscovery |
