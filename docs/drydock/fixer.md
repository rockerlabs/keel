# Drydock fixer prompt — phase 5

*Copy the block below into a fresh **operator-launched session** — never a subagent. A fixer commits,
opens a PR, and passes through whatever gates keep a human in the loop; a subagent that skips those
isn't a faster fixer, it's an ungated one. Model: mid tier, medium effort — the judgement was spent in
phases 1–4, this is scoped editing under gates. One session per queue entry, **strictly one PR in
flight at a time** if your pre-PR gate keeps a shared per-repo sentinel. Procedure:
[`docs/drydock.md`](../drydock.md).*

---

Fix the **`accepted`** findings in these audit files:

<one audit-file path per line, from the fix queue entry>

Theme of this PR: <what the grouped findings have in common>.

Nothing else: no adjacent cleanups, no re-litigating a `rejected` or `known — <ticket>` verdict, no
improving prose you happen to read on the way. The queue is bounded on purpose; a fixer that starts
improving what it passes makes it unbounded.

**Flow:** a fresh branch (or worktree) off `<default-branch>` → the fixes → `<pre-PR pass — on Keel,
/polish, which opens the PR itself at its last step, so do not follow it with a separate gh pr
create>` → the PR.

**Rails:**

- **Test-pinned prose moves its pins in the same commit.** If a figure, a step count, or a quoted
  phrase is asserted by a test, the fix is both edits or neither. Known pinned surfaces in this repo:
  <list them, or "none — grep the test suite for the phrase you are about to change">.
- **Generated or synced prose is edited at its source**, not at the copy. If a file is produced from
  another, change the origin and regenerate.
- **Any HEAD-moving fix — an amend included — invalidates commit-keyed gate state.** Re-establish it
  proactively in the same turn rather than discovering it as a denial later.
- **Run the full local gate before pushing** — the project's test command and its linter over every
  touched file. A comment-only change can still break a heredoc or a quoting boundary.
- Verify each fix against the evidence in the audit file, not against your reading of the finding's
  one-line claim.
- **Ask for a deeper, human-run review on either of two factors** — the surface you touched is
  always-loaded or pipeline prose, **or** the diff is large. Either one is sufficient; they do not
  have to coincide.

**After the PR merges**, mark `fixed: PR #<n>` next to each finding you fixed, in the audit files
under `<audit-dir>`.

Your final message: the PR URL, then one line per finding — fixed, or skipped with the reason. Do no
other bookkeeping: the changelog entry, the ticket updates, and the run record belong to the
orchestrator, which is holding the whole run's state and can write them once instead of eight times.
