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

Each step below ends with a **receipt**: run `tools/pre-pr-gate.sh receipt <step-id> [outcome]` from the
repo root (default outcome `done`; a conditional step that didn't apply writes `skipped:<reason>` instead —
the skip is itself an executed decision, so the id is still written). This is a completeness record, not
proof of work: `pre-pr-gate.sh` denies `gh pr create` unless every step id below is present for the current
run (dir #49). Never skip a receipt write even on a step that "obviously" ran. **If any receipt/log call
above triggers an unexpected permission prompt** (the harness's auto-mode classifier flagging a plain `Bash`
call it shouldn't), note it once per run with `tools/pre-pr-gate.sh log receipt-friction classifier` — this
is friction data for the pilot's own keep/drop review, not a step to repeat per-occurrence.

Steps, in order:

1. **Diff.** `git fetch --prune`, then `git diff origin/<default>...HEAD` (or the working-tree `git diff` if
   nothing is committed yet) — that is the scope of this pass. If there is no diff, say so and stop; leave the
   gate untouched (no receipt — nothing to unlock yet).

   Otherwise, start this run's receipt: `tools/pre-pr-gate.sh init` (mints a fresh nonce, discarding any
   earlier run's leftover receipt). Then `tools/pre-pr-gate.sh receipt polish.1-diff`.

2. **Simplify.** Invoke the `/simplify` skill — it runs the cleanup pass (duplication, dead code,
   over-complication, naming) and applies the fixes. Wait for it to finish before the next step.
   Receipt: `tools/pre-pr-gate.sh receipt polish.2-simplify`.

3. **Tests — run them by default.** Take the test command from the project's `CLAUDE.md` and run it. Show the
   real output (green/red); never claim "passed" without it. **Exception:** if `$ARGUMENTS` contains
   `--no-test`, skip the run and say explicitly that tests were skipped by request (the human runs them before
   the PR).
   Receipt: `tools/pre-pr-gate.sh receipt polish.3-tests` (or `... polish.3-tests skipped:--no-test`).

4. **Pick a review depth — matched to the diff, mostly automatic.** Gate this on the steps above being
   clean: proceed only if simplify left no open problems AND (tests are green OR were explicitly skipped).
   Otherwise report what is left and stop — do NOT write this step's receipt or the sentinel.

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
   - **`skip` → also always ask, never auto-select.** The two ends of the scale are exactly where the
     model's own judgement shouldn't be final: one spends the human's money, the other spends their
     safety margin. `skip` is also the only depth that bypasses step 5 outright — hand-off included — so
     leaving it auto-selectable gives back, in one word, the decision step 5 stops to obtain. Whenever
     the review is expensive or unavailable, sizing the diff down is the cheapest way out of it, and
     this step's sizing is the model's own and unchecked.
   - **`low`/`medium` on a diff that sits clearly inside one bucket → run that level automatically**,
     no dialog; state which level and why.
   - **Borderline (near a boundary, references present, mixed) → open the `AskUserQuestion` dialog** with
     the recommended level pre-selected and a **skip** option always present; let the human override.

   Receipt: `tools/pre-pr-gate.sh receipt polish.4-depth <level>:<what it was sized from>` — e.g.
   `low:+38-8,2f,docs` or `medium:+412-96,10f,code`. A bare level records the conclusion and throws away
   the evidence for it; the measurement is what makes a questionable call visible afterwards.

5. **Run the chosen review — one terminal pass, no loop-back.** For `skip`, do nothing. For
   `low|medium|high|max`, invoke the `/code-review <level>` skill once and resolve any real findings.
   **Establish availability by *attempting* the call, never by inferring it from the skill listing** — a
   skill can be installed and still refuse model invocation, and only the attempt returns the reason.

   **Two cases hand the review back to the human, and both follow the same hand-off below.** `ultra` you
   cannot launch at all (cloud, billed, user-triggered). `/code-review` being unavailable to you —
   missing from the skill list, or refusing with `disable-model-invocation` — is the other; there, do not
   substitute `/review` (a GitHub-PR command, not a working-diff review) and do not guess.
   - **(a)** In the *unavailable* case only, perform ONE inline review pass of the step-1 diff at the
     chosen depth (correctness-focused, same single-terminal-pass rule as below) and resolve any real
     findings, so cheap issues never reach the human. For `ultra`, go straight to (b) — that depth was
     chosen precisely because a cheap pass isn't the answer. **Say what you checked and what you found**,
     the way step 3 has to show real test output: an assertion that a pass happened, with nothing to
     inspect, is indistinguishable from one that didn't.
   - **(b) Then stop.** Report that the real review could not be run, print the exact
     `/code-review <level>` command, and ask whether to run it or to proceed without. Do NOT write this
     step's receipt, do NOT write the sentinel, and do NOT open the PR on your own initiative. An inline
     pass is a courtesy, never a substitute for the human's decision about review depth: it is one pass,
     in the same context that wrote the code, with no independent reviewer. **The failure this closes:**
     continuing to a merged-ready PR and disclosing the substitution only in the closing summary, where
     the operator finds out by reading the transcript — or not at all.
   - **(c)** Once they answer — or, on a re-invocation, once the session already shows they ran it —
     **resolve any findings their review reported** (same bar as the in-session path; a review nobody
     acts on bought nothing), then record the outcome and continue: receipt
     `polish.5-review <level>-operator-run`, or `<level>-waived` if they explicitly chose to proceed
     without. **This is the branch's only exit.** `init` mints a fresh nonce that discards the previous
     run's receipts, so a re-invoked `/polish` re-sizes the same diff and picks the same level — without
     recognising the review the human already ran, it would defer again, and every time after that.
   - **(d)** Both outcomes are load-bearing for step 10: the summary must say the real review did not run
     in-session and name what stood in for it, never just the depth. "review: medium" reads identically
     to a genuine in-session pass, which is how the substitution stays invisible.

   **This review is a single final pass: it must NOT re-invoke `/simplify` or loop back to step 4 — even
   if `--fix` changes files.** No infinite cycle.
   Receipt: `tools/pre-pr-gate.sh receipt polish.5-review <level>` (e.g. `low`, `high`,
   `medium-operator-run`, `ultra-operator-run`, `medium-waived`, or `skip`).

6. **Re-run tests if the review touched code — once.** If step 5 changed any files (and tests weren't
   `--no-test`-skipped), re-run the test command a single time — review fixes can break something. **Files
   changed during the hand-off count as step-5 changes** — whether the human's own `--fix` run edited them
   or you did, resolving the findings their review reported. Those land between `/polish` invocations, so
   "did step 5 change files" is otherwise easy to read as "no", and the retest gets skipped after exactly
   the kind of edit it exists to cover. Show the
   real output. If it went red, do NOT write this step's receipt or the sentinel — report what broke and
   stop; the human fixes and re-invokes. **This is one bounded re-run, not a loop back to simplify or the
   review dialog.** If the review changed nothing (or tests were skipped), skip the re-run.
   Receipt: `tools/pre-pr-gate.sh receipt polish.6-retest` (or `... polish.6-retest skipped:no-file-changes`).

7. **Self-check, if this repo ships one.** If `tools/self/doctor.sh` exists at the repo root, run it —
   it's the repo's own structural self-audit (dead references, ship-skip-list sync, tool wiring, doc
   staleness — distinct from the test suite). A GAP (non-zero exit) is treated the same as a red test: do
   NOT write this step's receipt or the sentinel, report what it flagged, and stop.
   Receipt: `tools/pre-pr-gate.sh receipt polish.7-selfcheck` (or, if the project has no `tools/self/doctor.sh`,
   `... polish.7-selfcheck skipped:no-doctor`).

8. **Unlock the gate.** Now that the diff is final (reviewed and re-tested), finalize the receipt with the
   current HEAD SHA: `tools/pre-pr-gate.sh receipt polish.8-unlock "$(git rev-parse HEAD)"`. That releases
   the `gh pr create` block. The SHA is recorded *after* the review so it matches exactly what the PR will
   contain.

   **On any receipt-deny from the gate** (a blocked `gh pr create` naming missing step ids): before
   re-running `/polish`, honestly check whether the named step's work actually happened and was simply not
   receipted, or was genuinely skipped — then log one verdict line: `tools/pre-pr-gate.sh log receipt-verdict
   "true-catch <step-id>"` (a real skip — the gate did its job) or `"false-fire <step-id>"` (the step ran,
   only the receipt write was missed). This is instrumentation for the pilot's own keep/drop review (dir
   #49), not a step of the happy path — skip it when the gate never denies.

9. **Open the PR.** After the gate passes, run `gh pr create` — compose the title and body from the
   implementation context (what changed, why, a test plan). Return the PR URL.

10. **Summary.** Briefly: what `/simplify` tidied, the test status (including any post-review re-run and
    self-check result), which review depth ran (or that it was skipped), and the PR URL. **If step 5 took
    the hand-off branch, say so explicitly** — that the real review did not run in-session, and whether
    the human ran it (`-operator-run`) or waived it (`-waived`, leaving only the inline pass). A bare
    depth is indistinguishable from a genuine in-session review, so reporting one here would re-hide
    exactly what step 5 stops to surface.
