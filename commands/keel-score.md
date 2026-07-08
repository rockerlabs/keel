---
description: Measure how much Keel shaped THIS session by counting cited events; the 0-100 score is DERIVED from them by tools/keel-impact.sh, never picked by hand
---
Measure how much **Keel** shaped *this* session and append one row to the impact ledger
(`docs/keel-impact.md`, or the project's own knowledge base when scoring inside a Keel-managed project).
This is the *quantified* form of the wrap-time promote/demote ritual in `FRAMEWORK.md` ("retrieval miss =
promote signal"). Ledger content is English.

**The honesty rule that makes this worth anything: you do not pick the score.** You gather *counted, cited
events*; `tools/keel-impact.sh` derives the 0-100 number from them by a fixed formula. So the marketing
number is a pure function of the evidence — it cannot be inflated by a good mood. Your only job is to make
the event list honest.

## What counts as an event — and the citation each one owes

Every event you report MUST name a concrete artifact from *this* session. No artifact → it did not happen,
do not count it. Never round a count up on vibes.

| Flag | Event | The citation it owes |
|---|---|---|
| `--guard` | a guardrail **actually blocked/caught** something (secret-guard, pre-pr-gate, public-audit) | the block in the output — the strongest, most objective signal |
| `--fire` | an always-loaded **rule/convention was concretely applied** | rule id + the diff line, **and** why a cold session would *not* have done it (the counterfactual — if it would have anyway, this is not a fire) |
| `--hit` | a needed **fact was pre-loaded and used** | where it lived (`CLAUDE.md` / memory) + where you used it |
| `--miss` | you had to **hunt for a fact that should have been always-loaded** | what you hunted for — this is *cost*, it lowers the score (promote pressure) |
| `--friction` | a **stale/noisy rule got in the way** | the rule + how it misled — *cost*, lowers the score (demote pressure) |
| `--silent` | always-loaded rules that **did not fire** this session | count only; the demote-candidate list — recorded, but **not** folded into the score |

**How the number falls out** (so you can predict it, not target it): `HELP = 3·guard + 2·fire + hit`,
`COST = 2·miss + 2·friction`, `score = round(100·HELP/(HELP+COST))`. Guardrail fires dominate because they
are objective; misses and friction pull it down. No events at all → `—` (nothing to measure), not a fake 0.
`conf` (none/low/med/high) comes from how many events back the score — a number on one event is weak.

## Steps

1. **Enumerate events with citations.** Walk what the session actually did — the diff, commands run,
   decisions, any guardrail output — and tally each event type, keeping the one artifact that proves it.
   Be adversarial with `--fire`: drop any where a cold session would have done the same. If nothing is
   citable, the honest result is `—` or a low score — let it be low.
2. **List the silent rules.** Which always-loaded rules/facts did *not* earn their place this session? Count
   them for `--silent`, and name the top one in `--gap`. Note any `--miss` as a promote candidate too.
3. **Append the row** — the tool derives and records the score:

   ```bash
   tools/keel-impact.sh add \
     --guard N --fire N --hit N --miss N --friction N --silent N \
     --evidence "one line: the single strongest citation" \
     --gap "one line: top demote/promote candidate, or 'none'"
   ```
   It prints the derived score, the confidence tag, and the refreshed trend + cumulative honest signals
   (`tools/keel-impact.sh rollup` recomputes without adding a row).
4. **Report** the derived score with its two strongest citations and the top silent-rule / retrieval-miss
   finding — so the number arrives with the "why" and a concrete next action for Keel's own tuning.

**If the session was trivial or Keel truly did nothing** — report `—` with no events, or say so and write
nothing at all (mirror `/wrap`'s "no significant changes → write nothing"). A padded ledger is worse than a
short one, and a derived `—` is more honest than a manufactured number.

> **Calibration (the only real counterfactual):** self-reported events, even cited, still lean on *your*
> judgement of what a cold session would do. To anchor them in something measured, occasionally run the same
> task twice — once with Keel context loaded, once cold — and compare the outcomes. That measured delta is
> the ground truth these per-session scores only estimate; treat a long trend of high scores with suspicion
> until at least one A/B has backed it.
