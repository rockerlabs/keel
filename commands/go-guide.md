---
description: The implementer guide /go loads at its step 7 — numbered actions for building a ready ticket well, the git → no-git map, and the final report's form
user-invocable: false
---
`/go` sent you here from its step 7. `/go`'s steps stay the gate; this file is HOW to do its steps 7–9
and the final report. Do the actions below in order. Each one names what to do, the result to check
before moving on, and when to stop. Where this file and `go.md` disagree, `go.md` wins.

## Map — when there is no git, or no runnable surface

Read this table once; from then on, every word in the left column means its right-hand entry.

| With git and code | Without git, or with no runnable surface |
|---|---|
| a feature branch | none — work in the project directory |
| `branch <name>` in the claim marker, `<branch>` in the escapes line | the ticket's id or file name |
| an automated test | a checklist item: the check, plus the evidence it needs |
| the PR body | the report: a dated `## Implementation report (YYYY-MM-DD)` section appended to the spec file (no spec → to the ticket), and the same text in chat |
| `/polish` | action I6's self-check, done by you |
| the operator merges | the operator signs the report off in chat |

**Evidence** means something another person can check without trusting you: a test's output, a
`file:line`, a link or path to the produced document with the passage that meets the check, a
screenshot path, a named person's sign-off. "Done", "looks right" and "should work" are not evidence.

## Actions

**I1 — reconcile.** Before you change anything:
1. Read every live file the spec names. The spec is a snapshot; where it and the live file disagree,
   the file is the truth and the gap is an escape (I5).
2. Walk the spec's Impact map, row by row (no Impact map → skip this item; say so). "changed in the same PR" (or in a PR this ticket names) → put it on your change list.
   "unaffected" → write down the check that proves it stays unaffected (you run it in I4).
   "follow-up" → not yours; leave it.
3. Before writing any new function, section or file, search for one that already does the job
   (`grep -rn` for its name and its purpose). Found → extend it; never add a second copy.
Result: a change list, one line per item. Stop: a row whose live state breaks a premise the design
depends on → `go.md` step 3's stop-or-escape rule.

**I2 — acceptance checks first.**
1. Write one test per `**Acceptance:**` item (no Acceptance line → per done-criterion clause).
2. Run them. Each must fail for the reason the item names; paste that failing output into the test
   plan. A test that passes before you change anything tests nothing — rewrite it.
3. No runnable surface → one checklist item per check, naming the evidence it will need; this is
   still `tests: first`. `infeasible` is only for a check that cannot be performed at all; write why.
   A check only a named person can pass (a sign-off) is neither: it stays open, `pending` (I6).
Result: every Acceptance item has a red test or an open checklist item.

**I3 — build, one item at a time.**
1. Take the next change-list item; make only that change.
2. Re-run the checks it touches. Red → fix before the next item.
3. Touch only files on the change list. A file you now need that is not on it → add it with the
   reason, and count it as an escape (a missed dependency). A defect you notice outside the ticket →
   record it (PR body or a new ticket); do not fix it.
Result: every change-list item done, its checks green.

**I4 — self-check.** After the last item, before conform:
1. Re-read the spec's rules one by one. A rule nothing in your change implements → back to I3.
2. Run every "unaffected" check you wrote down in I1. Red → back to I3.
3. Run the project's full test command (its `CLAUDE.md` names it); no command → skip, say so.
Result: all green, or each red named with its next action.

**I5 — escapes.** An escape is a spec defect you hit: a false premise, a missed dependency, an
undefined path, a rule that contradicts another rule or a pinned test — anything that made you depart
from the design or complete it. A sign-off still to come is not an escape (I6). Count each once; one line each, in the format `go.md` step 8 gives.
None → the count is `0`; still write the line.

**I6 — conform table.** One row per spec rule id, then one row per `**Acceptance:**` item:
`| <id> | done — <file:line or evidence> |`, `| <id> | escape <n> |`, or — only for a check a named
person must pass — `| <id> | pending — <who> |`, which `Operator next:` then asks for. A spec without rule ids → one
row per section of its Rules. A red row → back to I3 until green, or an escape if the check itself is
wrong. (I3 is part of `go.md` step 7, so this is its "back to step 7".) Without `/polish`, this table plus I4 is the whole pre-close review — do not skip a row.

**I7 — outcome test.** The spec's Class & outcome section names an outcome test (it worked), apart
from the done-criterion (it's built).
- Runnable now → run it; paste the result.
- Needs time or other people → copy it into the report with its owner and due date, status `pending`.
- The spec names none → write `outcome test: none in spec`.

**I8 — final report.** Fill this form, every line, in this order; `none` beats a blank:

```text
Ticket: <id or spec path> · branch: <name | none> · PR: <URL | none>
Readiness: <grade read> · override: <none | who gave it>
Guide: go-guide I1–I8 followed
Tests: first | infeasible — <reason>
Conform: <r> rules + <a> Acceptance items — <d> done, <e> escape, <p> pending
<the I6 table>
Escapes: <n> (as appended to the spec)
Outcome test: <result | pending — owner, due | none in spec>
Recorded, not fixed: <out-of-ticket defects | none>
Marker: <the claim marker as it now reads | requested from <writer>>
Operator next: <merge PR <URL> | sign off this report | answer: <question>>
```

Where it goes: the PR body and chat (git); the report section and chat (no git, see the map).

## Spec mode — a spec file is the ticket

`go.md` step 1 sends a spec-file path here when no backlog ticket names it.
- The `Status:` line sits under the file's first heading. It carries the same legend tokens a backlog
  heading does, for example `Status: 📐 SPEC-READY`.
- Claim: append the marker to that line — `Status: 📐 SPEC-READY — ⏳ IN FLIGHT (YYYY-MM-DD, branch
  <name>)`. No `Status:` line → add one holding only the marker.
- No closing sweep reaches a spec file. Leave `⏳` in place; the report's `Operator next:` line asks the
  operator to replace it with `✅` at merge or sign-off. Never write `✅` yourself.
