# Drydock code-auditor prompt — phase 1, scope C

*Copy the block below into a fresh subagent session, replacing every `<placeholder>`. Model: mid
tier, high effort — top tier or xhigh for a batch containing an `INVARIANT`-marked file. One session
per inventory scope-C batch, all in parallel, all read-only. Procedure: [`docs/drydock.md`](../drydock.md),
[Scope C — code](../drydock.md#scope-c--code).*

---

Audit these files for code defects — **whole file, not comment prose**: <one repo-relative path per
line, with its line count, from the run's inventory>

Read each file **whole, end to end**, before writing any finding. Leads from the mechanical sweep, if
any: <the sweep hits for these files, or "none"> — leads are suspicions, not conclusions; confirm or
drop each one on its merits. <If this batch contains a file marked `INVARIANT` in the inventory, name
it here and hold it to the highest care in this prompt — it is invariant-bearing.>

**Classes** (dir #85's module-1 rubric, unchanged): `dead-code` (unreachable branch, an unused
function) · `duplication` (the same logic in two places, vs. a shared-helper opportunity) ·
`missing-coverage` (a named behavior with no test, or a test whose assertion doesn't match its own
name — a guard that proves nothing) · `correctness` (a defect an adversarial review would catch,
including cross-platform BSD/GNU/BusyBox constructs and the lib-sourcing function-shadowing hazard).
No style, size, or `TODO` classes — those get their own ticket, not a finding here.

**Method:**

- **Verify a header's or a comment's contract by grepping its actual consumers** — never by
  re-reading the comment a second time. A well-written comment has passed as proof of behavior before
  and been wrong.
- **A comment or contract note describing behavior is a claim, not evidence.** If what it describes
  is executable, run it — in a sandboxed copy, per the rail below — rather than accepting the prose.
- **Assertion-vs-name audit every test file in scope**: does the test's assertion actually prove what
  its name and surrounding comments claim? Spot-break it in a sandboxed copy (mutate the code under
  test, confirm the test goes red) as your evidence, not a read of the assertion alone.
- **Cross-platform constructs** (a GNU-only flag, a BSD-only flag, a bashism outside a `#!/usr/bin/env
  bash` file) are checked live, in a Docker probe, not by reading the syntax and guessing.
- **Duplication is filed here, in phase 1** — not phase 3. Cross-file duplication never enters the
  `## claims` registry (code bodies don't), so the cross-file pass structurally cannot see it; grep
  the frozen tree yourself for the suspicious shape.

**Rails:**

- You are read-only: no commits, no branch changes, no edits to any repo file. Your only writes are
  your own contract file(s).
- Do not spawn subagents of your own.
- Any live or executable check runs ONLY in a scratch clone under a sandboxed tmpdir — never the real
  checkout, never the real $HOME. (A past verifier session "empirically reproducing" a finding
  overwrote real machine-global git hooks and broke `git push` machine-wide until they were restored.)
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.
- **Do not consult the ticket backlog.** Deduping a finding against an open ticket is the verifier's
  job, and reading open tickets first would bias what you notice.
- Measure in the frozen tree you were given (`<frozen-worktree-path>`); write output to `<audit-dir>`.
  Never the reverse.

**Audit-file contract** — fill exactly this shape, and leave the `verdict:` line EMPTY for the
verifier:

```
# drydock audit — <repo-relative path> @ <baseline-sha>
auditor: <your model + effort> | <date>
## findings
### F<n> — <class> — <line numbers>
claim: <what the code asserts, or what is defective>
evidence: <the quote, plus the measured or observed fact that contradicts it — a sandboxed run, a
spot-break, a grep of consumers>
verdict:
## claims
- <the header contract's own statements, one per line, with its line number>
- defines: <name> — one per function this file defines, locals included
- calls: <name> — one per function call this file makes, internal calls included (a call to a local
  helper counts — omitting it would make phase 3 flag that helper as dead)
- <each named consumer of this file>
- <each "test X pins behavior Y" claim this file makes or that a paired test file makes about it>
```

End **every** audit file with its `## claims` section, even a zero-finding one: it feeds the
cross-file pass (see [`docs/drydock.md`](../drydock.md)'s Phase 3 section for the three code claim
classes it derives from these fields), and its presence is how the orchestrator tells a finished file
from a partial write.

Your final message: one line per audit file written — path plus finding count. **Zero findings is a
valid result** — say so plainly rather than reaching for something to report.
