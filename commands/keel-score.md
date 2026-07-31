---
description: Measure how much Keel shaped THIS session by counting cited events; the 0-100 score is DERIVED from them by tools/keel-impact.sh, never picked by hand
---
Measure how much **Keel** shaped *this* session and append one row to the impact ledger
(`docs/keel-impact.md`, or the project's own knowledge base). This is the *quantified* form of the wrap-time
promote/demote ritual in `FRAMEWORK.md` ("retrieval miss = promote signal"). Ledger content is English.

## What counts as an event — one citation per event; the score falls out of them

**You do not pick the score.** You pass **one citation per event** (repeat the flag); `tools/keel-impact.sh`
counts them and derives the 0-100 number by a fixed formula — a pure function of the evidence, not mood. So
*no citation → no count*, mechanically. Every citation MUST name a concrete artifact from *this* session, and
each is archived to the evidence trail (`.keel/evidence.md`), making the score a checkable record. Your one
job: keep the event list honest.

| Flag (repeat per event) | Event | What the citation must name |
|---|---|---|
| `--hold "…"` | keel **restrained the agent** from weakening/bypassing a rule or guardrail (its highest function — scores above guard) | what you tried to do + which rule/guardrail stopped you (e.g. a classifier that rejected your fix, the gate refusing a forged sentinel) |
| `--guard "…"` | a guardrail **blocked/caught bad content** (secret-guard, pre-pr-gate, public-audit) | **usually auto-ingested** — see below; pass `--guard` only for a fire not written to the log |
| `--fire "…"` | an always-loaded **rule/convention was concretely applied** | rule id + the diff line, **and** a counterfactual that passes the two-test fire bar below |
| `--hit "…"` | a needed **fact was pre-loaded and used** | where it lived (`CLAUDE.md` / memory) + where you used it |
| `--miss "…"` | you had to **hunt for a fact that should have been always-loaded** | what you hunted for — this is *cost*, it lowers the score (promote pressure) |
| `--friction "…"` | a **stale/noisy rule got in the way** | the rule + how it misled — *cost*, lowers the score (demote pressure) |
| `--silent N` | always-loaded rules that **did not fire** this session | a bare count (no citation); the demote-candidate list — recorded, **not** folded into the score |

**The `--fire` bar — two tests, both must pass, or the event is not a fire:**
1. **Reachable.** The claimed moment must be one a cold session actually reaches. A behavior that lives
   behind a keel-only mechanism (a command's built-in fork, a wrap ritual) or past the point where a cold
   session would have stopped is *capability*, not a counterfactual — if it mattered, name it in `--gap`
   prose; do not score it.
2. **Beyond orientation.** "A cold session would not have done this" must survive "any competent agent does
   this while orienting anyway" — reading the files it is about to edit, listing branches, running the test
   suite. Behavior indistinguishable from ordinary orientation is not a fire.

**Guardrail fires are collected for you.** In a tracked repo (an enabled `.keel/` marker — `keel-impact.sh
enable`, or `init-project` by default — or `$KEEL_IMPACT_LOG`), the guardrail hooks (`secret-guard`,
`pre-pr-gate`, `public-audit`) record each fire to a zero-token event log (metadata only, never the secret)
and `add` auto-ingests it into `--guard` — so normally omit `--guard`, passing it only for a fire the log
missed. Collection is honest about *count*, not about *valence* — a gate DENY is auto-ingested as `--guard`
even when it was a false fire, i.e. friction, not help (a fire only knows it blocked something, never whether
the block was deserved). Each event is stamped with its producer's own worktree top (dir #74's claim key),
so with several worktree sessions live on the repo at once, `add` only ingests events carrying ITS OWN
key — a fresh event from another worktree is left in the log (printed as `foreign-kept: ...`, not counted)
for that other session's own `add` to pick up later. **`foreign-kept:` lines are EXPECTED with parallel
sessions — not a bug.** **Check the printed `ingested: ...` lines against what actually happened this
session:** a same-directory residual (two sessions sharing one worktree, so the claim key can't tell them
apart — the case the age cap is still the only guard for; anything older than
`$KEEL_INGEST_MAX_AGE_HOURS` hours, default 12, is reported as `stale-skipped:` instead) or a false fire
does NOT stay counted as guard — rerun `add --no-ingest` and pass the corrected flags by hand (a false
fire this session actually suffered from is `--friction`, not `--guard`).

**How the number falls out** (so you can predict it, not target it): `HELP = 4·hold + 3·guard + 2·fire + hit`,
`COST = 2·miss + 2·friction`, `score = round(100·HELP/(HELP+COST))`. A hold (keel catching the agent) weighs
most, then objective guardrail fires; misses and friction pull it down. No events at all → `—` (nothing to
measure), not a fake 0. `conf` (none/low/med/high) comes from how many events back the score — one is weak.

## Steps

1. **Enumerate events with citations.** Walk what the session actually did — the diff, commands run,
   decisions, any guardrail output — and write one citation per event. Be adversarial with `--fire` — apply
   the two-test bar above and drop any event that fails either test. If nothing is citable, the honest
   result is `—` or a low score — let it be low.
2. **List the silent rules.** Which always-loaded rules/facts did *not* earn their place this session? Count
   them for `--silent`, and name the top one in `--gap`. Note any `--miss` as a promote candidate too.
3. **Append the row** — repeat a flag once per cited event; the tool counts, derives, and records.
   `tools/…` is your **Keel checkout's** copy, so spell it `<keel-checkout>/tools/keel-impact.sh` when
   the session's cwd is the project being scored — and it should be: the `.keel/` marker and ledger
   resolve from the cwd's repo, so a call made from the wrong directory silently scores that repo
   instead (or, if it carries no marker, appends to Keel's own dogfooding ledger):

   ```bash
   tools/keel-impact.sh add \
     --fire "rule-id | diff line | why a cold session would not have" \
     --fire "another applied rule | its artifact | its counterfactual" \
     --hit "fact @ CLAUDE.md | where you used it" \
     --miss "what you had to hunt for" \
     --silent N \
     --gap "one line: top demote/promote candidate, or 'none'"
   ```
   It prints the derived score, confidence, and refreshed trend, and archives every citation to the evidence
   trail (`rollup` recomputes without adding a row).
4. **Report** the derived score with its two strongest citations and the top silent-rule / retrieval-miss
   finding — so the number arrives with its "why" and a next action for Keel's tuning.

**If the session was trivial or Keel truly did nothing** — report `—` with no events, or write nothing at
all (mirror `/wrap`'s "no significant changes → write nothing"). A derived `—` beats a manufactured number.

**Scoring a past session (retro).** To score a session reconstructed from a transcript, add `--retro` (plus
`--asof YYYY-MM-DD` for its real date). Cite events from transcript lines — a guard counts only if the block
is visible in the text. Retro rows are *quarantined*: dropped one confidence tier, tagged `-retro`, and kept
out of the live trend (`rollup --retro` shows only them). This keeps rough estimates from inflating the live
signal.

> **Calibration (the only real counterfactual):** cited events still lean on *your* guess of what a cold
> session would do. To anchor that, occasionally run the same task twice — Keel-loaded vs cold — and compare
> outcomes. That delta is the ground truth these scores only estimate; distrust a long high-score trend
> until an A/B backs it. The first such A/B (2026-07) is what the two-test fire bar above encodes — and it
> also found the run's largest real keel-vs-cold delta (branch discipline) unclaimed by any event: an event
> list can over-claim at the margins and under-claim the core, so the score is a floor on the estimate's
> honesty, not a ceiling on Keel's effect.
