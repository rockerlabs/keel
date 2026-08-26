# Drydock auditor prompt — phase 1, scope A and B

*Copy the block below into a fresh subagent session, replacing every `<placeholder>`. Model: mid
tier, high effort. One session per inventory scope-A/B batch, all in parallel, all read-only.
Procedure: [`docs/drydock.md`](../drydock.md). (Scope C has its own template,
[`docs/drydock/code-auditor.md`](code-auditor.md).)*

---

Audit these files for prose defects:

<one repo-relative path per line, with its line count, from the run's inventory>

Read each file **whole, end to end**, before writing any finding. Leads from the mechanical sweep:
<the sweep hits for these files, or "none"> — leads are suspicions, not conclusions; confirm or drop
each one on its merits.

For every number, count, or figure the prose asserts, **re-measure it against the tree at
`<baseline-sha>`** — never trust the prose, and never trust your own memory of this repo. For dated,
append-only prose (a changelog): check a dated section for internal consistency **at its own date
only**; never flag a historical entry against today's code. For shell files: audit **comment blocks
and headers only** — prose defects, not code review.

**Classes:** `contradiction` (the file disagrees with itself) · `stale-claim` (prose vs. the actual
code or tree, empirically checked) · `unfinished-edit` (mechanical residue: a dangling half-sentence,
an anomalously wrapped line) · `duplication` · `broken-xref` (names a file, section, or count that
doesn't resolve) · `overclaim` (a promise stronger than the implementation) · `optimization`
(verbosity or structure — use sparingly; it carries a higher acceptance bar downstream).

**Rails:**

- You are **read-only**: no commits, no branch changes, no edits to any repo file. Your only writes
  are your own audit files under `<audit-dir>` — one per audited file, named `<slug>-audit.md`, where
  the slug is the repo-relative path with `/` replaced by `-` (so `docs/release-audit.md` →
  `docs-release-audit.md-audit.md`).
- **Do not consult the ticket backlog.** Deduping a finding against an open ticket is the verifier's
  job, and reading open tickets first would bias what you notice.
- **Do not spawn subagents of your own** — do the work in this session.
- Any **live or executable check runs in a scratch copy** under your own temp directory — never the
  real checkout, never the real `$HOME`.
- Measure in the frozen tree you were given (`<frozen-worktree-path>`); write output to
  `<audit-dir>`. Never the reverse.
- **A comment or contract note describing behavior is a claim, not evidence.** If the input it
  describes is executable, run it rather than accepting the prose — a well-written comment has passed
  as proof of behavior before and been wrong.

**Audit-file contract** — fill exactly this shape, and leave the `verdict:` line EMPTY for the
verifier:

```
# drydock audit — <repo-relative path> @ <baseline-sha>
auditor: <your model + effort> | <date>
## findings
### F<n> — <class> — <line numbers>
claim: <what the prose asserts, or what is defective>
evidence: <the quote, plus the measured or observed fact that contradicts it>
verdict:
## claims
- <every fact, number, promise, or cross-file reference this file asserts — one per line, with its line number>
```

End **every** audit file with its `## claims` section, even a zero-finding one: it feeds the
cross-file pass, and its presence is how the orchestrator tells a finished file from a partial write.

Your final message: one line per audit file written — path plus finding count. **Zero findings is a
valid result** — say so plainly rather than reaching for something to report.
