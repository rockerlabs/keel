---
description: Pre-PR polish pass — simplify + tests + depth-matched code-review + gate + open the PR
argument-hint: [--no-test]
---
<!-- MAINTAINER DEV-TOOLING — not installed for adopters. This is a Claude-Code-specific pre-PR flow that
pairs with tools/pre-pr-gate.sh; install.sh intentionally skips both (an adopter shouldn't get a command
whose gate isn't wired). It lives in the repo for the maintainer's own workflow + downstream consumers. -->

The final pass over the diff before a PR — run between implementation and `/wrap`. Goal: hand a human
reviewer an already-tidied diff and open the PR. It pairs with `tools/pre-pr-gate.sh`,
which blocks `gh pr create` until this command has run cleanly on the current HEAD.

Project context (test command, NFRs, conventions) lives in the project's `CLAUDE.md` — re-read only what you
need, not a full onboarding.

Steps, in order:

1. **Diff.** `git fetch --prune`, then `git diff origin/<default>...HEAD` (or the working-tree `git diff` if
   nothing is committed yet) — that is the scope of this pass. If there is no diff, say so and stop; leave the
   gate untouched.

2. **Simplify.** Invoke the `/simplify` skill — it runs the cleanup pass (duplication, dead code,
   over-complication, naming) and applies the fixes. Wait for it to finish before the next step.

3. **Tests — run them by default.** Take the test command from the project's `CLAUDE.md` and run it. Show the
   real output (green/red); never claim "passed" without it. **Exception:** if `$ARGUMENTS` contains
   `--no-test`, skip the run and say explicitly that tests were skipped by request (the human runs them before
   the PR).

4. **Pick a review depth — matched to the diff.** Gate this on the steps above being clean: proceed only
   if simplify left no open problems AND (tests are green OR were explicitly skipped). Otherwise report
   what is left and stop — do NOT write the sentinel. Then size the step-1 diff cheaply (lines changed,
   files touched, and whether it touches real logic vs docs/tests only) and open an `AskUserQuestion`
   dialog offering a `/code-review` depth, with the recommended level pre-selected from that sizing:
   - trivial / docs-only → **skip** (or `low`)
   - ordinary change → **medium**
   - logic-heavy / large → **high**
   - security- or invariant-sensitive / very large → **max** or **ultra**

   Always include a **skip** option — the point of the dialog is to spend review tokens deliberately, not
   by default. Recommend one level; let the human override.

5. **Run the chosen review — one terminal pass, no loop-back.** For `skip`, do nothing. For
   `low|medium|high|max`, invoke the `/code-review <level>` skill once and resolve any real findings. For
   `ultra` you cannot launch it yourself (cloud, billed, user-triggered) — print the exact `/code-review
   ultra` command, stop before the sentinel/PR, and let the human run it (they re-invoke `/polish` after).
   **This review is a single final pass: it must NOT re-invoke `/simplify` or loop back to step 4 — even
   if `--fix` changes files.** No infinite cycle.

6. **Re-run tests if the review touched code — once.** If step 5 changed any files (and tests weren't
   `--no-test`-skipped), re-run the test command a single time — review fixes can break something. Show the
   real output. If it went red, do NOT write the sentinel — report what broke and stop; the human fixes and
   re-invokes. **This is one bounded re-run, not a loop back to simplify or the review dialog.** If the
   review changed nothing (or tests were skipped), skip this step.

7. **Unlock the gate.** Now that the diff is final (reviewed and re-tested), write the current HEAD SHA:
   `git rev-parse HEAD > /tmp/pre-pr-gate-$(basename "$PWD")`. That releases the `gh pr create` block. The
   SHA is recorded *after* the review so it matches exactly what the PR will contain.

8. **Open the PR.** After the gate passes, run `gh pr create` — compose the title and body from the
   implementation context (what changed, why, a test plan). Return the PR URL.

9. **Summary.** Briefly: what `/simplify` tidied, the test status (including any post-review re-run), which
   review depth ran (or that it was skipped), and the PR URL.
