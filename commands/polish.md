---
description: Pre-PR polish pass — simplify + code-review + tests + gate + open the PR
argument-hint: [--no-test]
---
<!-- MAINTAINER DEV-TOOLING — not installed for adopters. This is a Claude-Code-specific pre-PR flow that
pairs with tools/pre-pr-gate.sh; install.sh intentionally skips both (an adopter shouldn't get a command
whose gate isn't wired). It lives in the repo for the maintainer's own workflow + downstream consumers. -->

The final pass over the diff before a PR — run between implementation and `/wrap`. Goal: hand a human
reviewer an already-tidied diff, find and fix bugs, and open the PR. It pairs with `tools/pre-pr-gate.sh`,
which blocks `gh pr create` until this command has run cleanly on the current HEAD.

Project context (test command, NFRs, conventions) lives in the project's `CLAUDE.md` — re-read only what you
need, not a full onboarding.

Steps, in order:

1. **Diff.** `git fetch --prune`, then `git diff origin/<default>...HEAD` (or the working-tree `git diff` if
   nothing is committed yet) — that is the scope of this pass. If there is no diff, say so and stop; leave the
   gate untouched.

2. **Simplify.** Invoke the `/simplify` skill — it runs the cleanup pass (duplication, dead code,
   over-complication, naming) and applies the fixes. Wait for it to finish before the next step.

3. **Code-review.** Invoke `/code-review --fix` — a local review pass over the diff that applies the bugs it
   finds. (`/code-review ultra` is the billed, cloud, user-triggered variant — do not invoke it here.)

4. **Tests — run them by default.** Take the test command from the project's `CLAUDE.md` and run it. Show the
   real output (green/red); never claim "passed" without it. **Exception:** if `$ARGUMENTS` contains
   `--no-test`, skip the run and say explicitly that tests were skipped by request (the human runs them before
   the PR).

5. **Unlock the gate — only if the steps above are clean.** If simplify + review left no open problems AND
   (tests are green OR were explicitly skipped) → `git rev-parse HEAD > /tmp/pre-pr-gate-$(basename "$PWD")`.
   That records the current HEAD SHA and releases the `gh pr create` block. If tests are red or review
   findings remain unresolved, do NOT write the sentinel — report what is left.

6. **Open the PR.** After the gate passes, run `gh pr create` — compose the title and body from the
   implementation context (what changed, why, a test plan). Return the PR URL.

7. **Summary.** Briefly: what `/simplify` tidied, what `/code-review` found and fixed, the test status, and
   the PR URL.
