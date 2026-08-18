# Drydock verifier prompt — phase 2

*Copy the block below into a fresh subagent session, replacing every `<placeholder>`. Model: mid
tier, **xhigh** effort — deliberately more than the auditors got, because proving a finding wrong is
harder than noticing it, and a wrong `rejected` is the one verdict nothing downstream re-checks. One
session per disjoint set of audit files. Procedure: [`docs/drydock.md`](../drydock.md).*

*The cross-file pass (phase 3) uses the same rails — see the variant at the end.*

---

Verify the findings in these audit files:

<one audit-file path per line>

For each finding, **reproduce the evidence empirically**: re-read the quoted prose in place in the
frozen tree at `<baseline-sha>`, re-measure every number, re-check every stale-claim against the code
it describes. A finding you cannot reproduce is not thereby wrong — say what you measured.

**Sandbox rail:** any live or executable check that WRITES runs **only** in a scratch clone under
your own temp directory — never the real checkout, never the real `$HOME`. This is not boilerplate: a
review subagent once "empirically reproducing" a bug overwrote real machine-global git hooks and
broke `git push` on that machine until they were restored.

**Its one exception, and it matters as much as the rail:** a check that only *reads* machine
configuration must face the REAL environment. Under a redirected `$HOME` such a verdict does not
weaken, it inverts — a fully-guarded machine reports "not wired" — so sandboxing that read would make
you write a confident `rejected` that is itself false, and `rejected` is the one verdict nothing
downstream re-checks. Sandbox what writes; never sandbox a read whose whole subject is the real
machine's state.

Then **deduplicate against the ticket ledger** (`<backlog-path>` — grep it, don't read it whole). A
defect that an already-open or already-deferred ticket owns gets `known — <ticket id>`, **not**
`accepted`: append a one-line pointer to that ticket and leave the prose alone. Deferrals are
decisions somebody made on purpose, and an audit that "fixes" them is reversing them silently.
<If the run has a known case in scope, name it here: "One live case you will meet: <the defect>,
owned by <ticket id> — resolve it `known`.">

Fill the empty `verdict:` line of each finding with exactly one of:

- `accepted`
- `rejected: <reason>` — the reason must name **what you measured**, never what you doubted.
- `known — <ticket id>`

**Never edit or delete the auditor's text** — you append verdicts, nothing else. Hold
`optimization`-class findings to a higher bar than factual ones: reject unless the gain is plain, since
that class is the one most likely to be an agent restyling prose it merely finds unfamiliar.

Then append this footer to each audit file you verified:

```
verifier: <your model + effort> | <date> | sandbox: <path, or "none — prose-only">
```

Your final message: one line per audit file — accepted / rejected / known counts.

---

## Variant — the cross-file pass (phase 3)

Same rails, one session, different input: read **only** the `## claims` sections of every audit file
in `<audit-dir>` — not the source files. You are looking for defects that no single-file reader could
see, in four classes:

- **the same fact carrying two different values** in two files;
- **broken promise pairs** — file A says "as described in B", and B describes something else;
- **dangling references** — a named file, section, ticket, or count that doesn't resolve;
- **multi-surface procedure skew** — three or more files each restating one procedure, drifted apart.

You are **self-verifying**: reproduce each candidate against the frozen tree before writing it, and
write findings straight into `<audit-dir>/cross-file-audit.md` with verdicts already filled, using the
same numbering (`X1`, `X2`, …) and the same audit-file shape.
