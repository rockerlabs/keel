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

4. **Pick a review depth — matched to the diff, mostly automatic.** Gate this on the steps above being
   clean: proceed only if simplify left no open problems AND (tests are green OR were explicitly skipped).
   Otherwise report what is left and stop — do NOT write the sentinel.

   Size the step-1 diff cheaply — lines changed, files touched, real logic vs docs/tests only, and whether
   it touches cross-references/links. From that, form a **recommended level**:
   - pure docs/wording, no cross-references → **skip**
   - docs with cross-references, or trivial code → **low** (a cheap safety net beats skip)
   - ordinary code → **medium**
   - logic-heavy / large → **high**
   - security- or invariant-sensitive / very large → **max** or **ultra**

   When the bucket is unclear (near a size threshold, mixed docs+code, references present), bias the
   recommendation **up** one notch — uncertainty favours more review.

   Then decide **auto vs ask**:
   - **`high` or above → always open an `AskUserQuestion` dialog, never auto-run.** High+ is expensive
     (`ultra` is billed) and may be unwanted or out of budget — spend it only on an explicit yes. (A fixed
     cost rule, not a live budget check: there is no token-budget signal.)
   - **`skip`/`low`/`medium` on a diff that sits clearly inside one bucket → run that level automatically**,
     no dialog; state which level and why. Auto-**skip** only for a clearly pure-docs, reference-free
     change — never auto-skip a diff that touches code or cross-references.
   - **Borderline (near a boundary, references present, mixed) → open the `AskUserQuestion` dialog** with
     the recommended level pre-selected and a **skip** option always present; let the human override.

5. **Run the chosen review — one terminal pass, no loop-back.** For `skip`, do nothing. For
   `low|medium|high|max`, invoke the `/code-review <level>` skill once and resolve any real findings. For
   `ultra` you cannot launch it yourself (cloud, billed, user-triggered) — print the exact `/code-review
   ultra` command, stop before the sentinel/PR, and let the human run it (they re-invoke `/polish` after).
   **If the `/code-review` skill is not available in this session** (missing from the skill list, or
   present but blocked from model invocation), do not substitute `/review` or guess — instead perform
   ONE inline review pass of the step-1 diff at the chosen depth (correctness-focused, same
   single-terminal-pass rule as below), resolve any real findings, and say in the summary that the
   review ran inline because the skill wasn't available.
   **This review is a single final pass: it must NOT re-invoke `/simplify` or loop back to step 4 — even
   if `--fix` changes files.** No infinite cycle.

6. **Re-run tests if the review touched code — once.** If step 5 changed any files (and tests weren't
   `--no-test`-skipped), re-run the test command a single time — review fixes can break something. Show the
   real output. If it went red, do NOT write the sentinel — report what broke and stop; the human fixes and
   re-invokes. **This is one bounded re-run, not a loop back to simplify or the review dialog.** If the
   review changed nothing (or tests were skipped), skip this step.

7. **Self-check, if this repo ships one.** If `tools/self/doctor.sh` exists at the repo root, run it —
   it's the repo's own structural self-audit (dead references, ship-skip-list sync, tool wiring, doc
   staleness — distinct from the test suite). A GAP (non-zero exit) is treated the same as a red test: do
   NOT write the sentinel, report what it flagged, and stop. Silently skip this step for any project that
   doesn't have the script.

8. **Unlock the gate.** Now that the diff is final (reviewed and re-tested), write the current HEAD SHA:
   `git rev-parse HEAD > /tmp/pre-pr-gate-$(basename "$PWD")`. That releases the `gh pr create` block. The
   SHA is recorded *after* the review so it matches exactly what the PR will contain.

9. **Open the PR.** After the gate passes, run `gh pr create` — compose the title and body from the
   implementation context (what changed, why, a test plan). Return the PR URL.

10. **Summary.** Briefly: what `/simplify` tidied, the test status (including any post-review re-run and
    self-check result), which review depth ran (or that it was skipped), and the PR URL.
