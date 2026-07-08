# Keel impact ledger

One row per scored session. The score is **derived, not asserted**: `commands/keel-score.md` gathers counted,
cited events; `tools/keel-impact.sh` computes the 0-100 number from them by a fixed formula, so it is a pure
function of the evidence and cannot be inflated by vibe. This is the quantified form of the wrap-time
promote/demote ritual (`FRAMEWORK.md` → "retrieval miss = promote signal").

Columns: **score** = round(100·HELP/(HELP+COST)) where HELP=3·guard+2·fire+hit, COST=2·miss+2·friction
(`—` = no events, nothing to measure). **conf** = evidence-count tier (none/low/med/high) — a score behind
few events is weaker. Event counts: **guard** guardrail fired · **fire** rule applied · **hit** retrieval
hit · **miss** retrieval miss (promote pressure) · **fric** friction (demote pressure) · **silent**
always-loaded rules that did not fire (demote candidates; NOT folded into the score).

**guard** is collected deterministically: with `$KEEL_IMPACT_LOG` set, shell tools (e.g. `secret-guard`)
record each fire to a zero-token event log that `add` auto-ingests — the objective signal never depends on
the model counting it.

| date | score | conf | guard | fire | hit | miss | fric | silent | evidence | gap (demote/promote) |
|------|-------|------|-------|------|-----|------|------|--------|----------|----------------------|
