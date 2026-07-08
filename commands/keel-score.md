---
description: Score how much Keel's context (CLAUDE.md, memory, rules, commands, guardrails) actually shaped THIS session — evidence-first, two-sided, appended to the impact ledger
---
Score how much **Keel** shaped *this* session on a 0–100 scale, and append one row to the impact ledger
(`docs/keel-impact.md`, or the project's own knowledge base when scoring inside a Keel-managed project).
This is the *quantified* form of the wrap-time promote/demote ritual in `FRAMEWORK.md` ("retrieval miss =
promote signal") — a gut check turned into a tracked number plus the evidence behind it. Ledger content is
English. **The number is worthless without the evidence trail** — do not emit a score you cannot back with
concrete artifacts from this session.

## Three rules that keep the score honest

1. **No point without a citation.** Every sub-score must name a concrete artifact from *this* session — a
   rule id from `CLAUDE.md`, a diff line, a memory/`LEARNINGS.md` file, a `secret-guard` block, a lifecycle
   command you ran. A claim you cannot cite scores **0** on that axis. Never round up on vibes.
2. **Counterfactual, not absolute.** Score the *delta* a Keel-less cold session would show — what it would
   have gotten wrong, re-litigated, or hunted for. If a cold session would have done the identical thing,
   that axis earns nothing, however nice the rule is.
3. **Two-sided — subtract the friction.** Keel also *costs*: stale rules, noise, a retrieval miss (a fact
   you had to hunt for that should have been always-loaded). The final score is **help − friction**, not a
   highlight reel. A session where Keel got in the way should score *low* — that low score is the signal.

## Rubric — five axes, each 0–20, each cited

| Axis | What it credits | A valid citation looks like |
|---|---|---|
| **Convention adherence** | Followed a rule a cold session would not have known | "P-git: feature-branch→PR flow, not a commit to main" |
| **Retrieval hit − miss** | A needed fact was pre-loaded and used; **subtract** for facts you had to hunt for | +"found the deploy step in memory"; −"hunted 10 min for the test cmd — should be startup" |
| **Rework avoided** | A settled decision in memory kept you from re-opening it | "did not re-litigate the DB choice — recorded in LEARNINGS" |
| **Guardrails fired** | `secret-guard` / `pre-pr-gate` / `public-audit` actually caught something | "secret-guard blocked a key-shaped string in a fixture" |
| **Command leverage** | The session ran through Keel lifecycle commands | "`/go` scoped the task; `/wrap` reconciled state" |

Score each axis 0–20 from its evidence, sum to a raw 0–100, then **subtract a friction penalty** (0–20) for
the costs you found. Clamp to 0–100. An axis with no citation is 0 — do not average it away.

**Calibration anchors** (keep scores comparable across sessions):
- **0–20** — inert or in the way; a cold session would have gone the same or better.
- **21–50** — mild help: a convention or two applied, nothing decisive.
- **51–75** — clear cited leverage on multiple axes; meaningfully better for Keel.
- **76–100** — load-bearing: guardrails and/or settled decisions changed the outcome, well cited.

## Steps

1. **Gather evidence** — skim what the session did (diff, commands run, decisions) and collect the citations
   above. Nothing citable → the honest score is low; say so.
2. **Score each axis + friction**, noting the one citation you lean on for each.
3. **Name the silent rules** — always-loaded rules/facts that did *not* fire (demote candidates) and any
   retrieval miss (promote candidates). This is the actionable half.
4. **Append the row** via the helper so the maths and rollup stay deterministic:

   ```bash
   tools/keel-impact.sh add \
     --score <0-100> \
     --axes conv=<0-20>,retr=<-20-20>,rework=<0-20>,guard=<0-20>,cmd=<0-20> \
     --friction <0-20> \
     --evidence "one line: the single strongest citation" \
     --gap "one line: top demote/promote candidate, or 'none'"
   ```
   The tool stamps the date, appends the row, and prints the refreshed trend (`tools/keel-impact.sh rollup`
   recomputes the trend without adding a row).
5. **Report** the score, the two strongest citations, and the top silent-rule / retrieval-miss finding — so
   the number comes with the "why" and a concrete next action for Keel's own tuning.

**If the session was trivial or Keel truly did nothing** — say so and write nothing (mirror `/wrap`'s
"no significant changes → write nothing"). A padded ledger is worse than a short one.
