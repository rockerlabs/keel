---
description: Pre-PR polish pass — simplify + tests + depth-matched code-review + gate + open the PR
argument-hint: [--no-test]
---
<!-- Installed by default (dir #68) — pairs with tools/pre-pr-gate.sh, a Claude-Code-specific hook that
install.sh never auto-wires: run
tools/install-pre-pr-gate.sh <repo> once per project to turn the gate on. Without it, every
step here still runs — only the gh pr create block is inert. -->

The final pass over the diff before a PR — run between implementation and `/wrap`. Once `tools/install-pre-pr-gate.sh` wires the gate, it also blocks
`gh pr create` until this command has run cleanly on the current HEAD. `tools/…` lives in your **Keel checkout**: when the cwd is another project, spell the
calls `<keel-checkout>/tools/pre-pr-gate.sh …` and run them **from the repo being polished** — the gate keys
its receipt off the cwd.

Each step ends with a **receipt**: `tools/pre-pr-gate.sh receipt <step-id> [outcome]` from the repo root
(default outcome `done`; a conditional step that didn't apply writes `skipped:<reason>`, one that ran only in
a degraded form `<how>:<reason>`). The gate denies `gh pr create` unless every step id is present for the
current run — never skip a receipt write. An unexpected permission prompt on one: note it once with
`tools/pre-pr-gate.sh log receipt-friction classifier`.

**Ordering rule 1 — have the implementation committed by step 3**: step 3's receipt binds `git rev-parse HEAD` and step 5's
review trace binds the HEAD current when the review fires, so a late commit costs a re-receipt cycle.

**The guide.** The rare branches live in `polish-guide.md`, loaded when a step below names a trigger that
fired; never improvise one from memory. Where the guide and this file disagree, this file wins.

Steps, in order:

1. **Diff.** `git fetch --prune`, then `git diff origin/<default>...HEAD` (the working-tree `git diff` if
   nothing is committed yet) is this pass's scope. No diff → say so and stop; no receipt. Otherwise
   `tools/pre-pr-gate.sh init` (mints a fresh nonce), then `tools/pre-pr-gate.sh receipt polish.1-diff`.
   *Rare — a convergence round (you re-invoked after step 5's review or step 7's self-check found
   something), `--recover`:* load the `polish-guide` skill
   (`keel-polish-guide` if aliased), else `polish-guide.md` beside this file, § Step 1; guide unreachable →
   stop and report.

2. **Simplify.** Every changed file `*.md`, none a command, skill or runbook → load `polish-guide`, § Step 2.
   Otherwise invoke `/simplify` and wait; receipt `tools/pre-pr-gate.sh receipt polish.2-simplify`.
   Refused or unavailable → § Step 2. Guide unreachable → stop and report.

3. **Tests — run them by default.** Run the project's test command (from its `CLAUDE.md`), backgrounded with an explicit timeout past the suite's runtime, and show the real
   output; never claim "passed" without it. A cut-short run is not green: re-run the remainder. `--no-test` in the arguments → skip the run and say so. Receipt: `tools/pre-pr-gate.sh
   receipt polish.3-tests "$(git rev-parse HEAD)"` (or `skipped:--no-test`, or `skipped:no-test-command`) —
   the gate unlocks only on a test run bound to the commit being shipped.

4. **Pick a review depth — matched to the diff, mostly automatic.** Proceed only if simplify left no open
   problems and tests are green or explicitly skipped; otherwise report what is left and stop (no receipt).
   First run `tools/pre-pr-gate.sh handoff-check`: a match means step 5 already stopped on THIS commit —
   reuse its recorded level. Otherwise size the diff cheaply (lines changed, files, real logic vs docs/tests
   only, cross-references) into a **recommended level**:
   - pure docs/wording, no cross-references → **skip**
   - docs with cross-references, or trivial code → **low**
   - ordinary code → **medium**
   - logic-heavy / large → **high**
   - security- or invariant-sensitive / very large → **max** or **ultra**

   Bucket unclear (near a threshold, mixed docs+code, references present) → bias up one notch. **Auto vs
   ask:** `low`/`medium`/`high` clearly inside one bucket → run it automatically, saying which and why. Borderline, and ALWAYS for `skip`, `max` and `ultra`, → an `AskUserQuestion` dialog with the
   recommendation pre-selected and a `skip` option, ended by the literal line `KEEL-DEPTH-DIALOG`.
   Receipt: `tools/pre-pr-gate.sh receipt polish.4-depth <level>:<what it was sized from>`.
   *Rare — a `handoff-check` match, any of the max/ultra/skip/borderline dialogs and their marker rule:*
   load the `polish-guide` skill (`keel-polish-guide` if aliased), else `polish-guide.md` beside this file,
   § Step 4; guide unreachable → stop and report.

5. **Run the chosen review — one terminal pass, no loop-back.** `skip` → receipt `tools/pre-pr-gate.sh
   receipt polish.5-review skip` now, no dialog (step 4's dialog was the decision). `ultra` cannot be launched
   from here → guide § Step 5 (b). For `low|medium|high` the first attempt is K2 below; for `max`, and when
   K2's fallbacks send you here, ATTEMPT `Skill(code-review) <level>` directly (never `/review`) (establish availability by
   attempting, never from the skill listing). On success resolve its findings, receipt the bare
   `polish.5-review <level>` (a genuine `/code-review` pass, run here or by K2's subagent) and continue to
   step 6; no dialog. The gate cross-checks the call's trace against the commit and the recorded level (dir #488, decided by the
   gate's own diff check, never your say-so: a later fix commit that is wholly comment/blank-line changes to
   already-reviewed `.sh` files keeps the earlier trace at that level; anything else needs a fresh one). The
   two-way conformance mandate (step 5(a)'s): the diff must realize the ticket's done-criterion, and nothing
   in it may silently exceed or contradict it.

   **K2 — for `low|medium|high`, the FIRST attempt is a review run by a fresh-context subagent (dir #670);
   `max`, `ultra` and `skip` keep their paths below, unchanged.** It runs the same `/code-review` recipe in a
   context that has not seen how the diff was written — a reviewer who wrote the code finds less of what is
   wrong with it, and every review turn run in this session re-reads the whole session's context.
   - **Spawn.** `git status --porcelain --untracked-files=no` must print nothing: simplify's fixes and the
     implementation are committed (ordering rule 1), and untracked files are left alone, never swept into a
     commit. A tracked change still pending → commit exactly that work now, as its own commit; that commit
     moves HEAD past step 3's sha-bound test receipt, so step 6's retest is then REQUIRED even if the review
     changes nothing (one retest after the last change satisfies both this and any fix commit). A tree that
     cannot be committed → stop and report. Record `git rev-parse HEAD` and `git status --porcelain` right
     before the spawn. Then spawn ONE fresh-context Agent-tool subagent — step 5's review subagent:
     `subagent_type: "general-purpose"`, no `model` pin, so it runs this session's own model. A restricted
     reviewer type (dir #413's `keel-polish-reviewer`) replaces it here only if its tool set
     includes `Skill` and the read-only git verbs `diff`, `log`, `show` and `blame`.
   - **Its prompt.** The FIRST line is exactly `You are /polish step 5's review subagent.` (the cost tool
     `session-cost.sh tail` finds the subagent by it). Then: the diff scope `git diff
     origin/<default>...HEAD`; the step-4 level; the ticket or done-criterion this diff implements with
     step 5(a)'s two-way conformance mandate — or the explicit statement that none exists (the review then
     stays correctness-only); the Worker rails block of `docs/delegation.md` in the Keel checkout, verbatim,
     below; and these instructions. Your first action: invoke `Skill(code-review)` with the args `<level>
     origin/<default>...HEAD` — the level first (the gate reads the args' first word as the level), then the
     diff target. **The args are the only channel to the review itself:** invoked from a subagent,
     `/code-review` runs as a forked agent one level deeper whose whole prompt is the skill's recipe plus the
     args; this prompt and its rails never reach it (`docs/delegation.md`, "Keel's reach stops at the prompts
     keel writes"), and without the target in the args the fork picks its own scope (felt: `git diff HEAD~1`
     on a two-commit PR). The skill's own fork is not "a subagent of your own" under the rails' no-spawn
     line. Then: edit nothing, commit nothing; wait for the skill to finish, including any background agents
     it starts; restate every finding in your final message as `file:line — quoted text — failure scenario`,
     even after a `ReportFindings` call, and write `0 findings` explicitly when there are none; print no
     `KEEL-*` marker line.

     ```
     - You are read-only: no writes to the real repository's `.git/` or working tree, by any mechanism —
       not only edits to tracked files, but any plumbing that touches `.git/` without editing one (`git
       worktree add` against the real checkout registers state there even though it deletes nothing; dir
       #485). Your writes are limited to your own contract file(s) and any scratch clone that's your own —
       that clone's `.git/` is not the real repository's.
     - A dirty or uncommitted working tree in the repo you're checking is normal — it's the parent
       session's own work in progress, not corruption. Never run `git checkout`/`reset`/`clean`/`stash` (or
       anything else) to "restore" it, no matter how closely it resembles a known contamination pattern —
       these are illustrations of the property above, not its full extent. (A review subagent that lacked
       this line mistook a parent's mid-edit files for a known test-fixture-leak symptom and destroyed real
       work with `git checkout --`; dir #375.)
     - Do not spawn subagents of your own.
     - Any live or executable check runs ONLY in a scratch clone under a sandboxed tmpdir — never the real
       checkout, never the real $HOME. Redirect every variable that resolves a machine-global file, not only
       the home: set HOME and GIT_CONFIG_GLOBAL (and unset XDG_CONFIG_HOME) inside the one script or command
       that runs the check — an exported variable may not reach your next command — and after a denial
       re-run that same unit, never a shortened retype. (A past verifier session "empirically reproducing" a
       finding overwrote real machine-global git hooks and broke `git push` machine-wide until they were
       restored; a worker's denied command, retyped shorter, lost its HOME= prefix and rewrote the real git
       identity.)
     - One test device per concurrent session: a simulator or emulator you run tests on is yours alone —
       boot your own (on iOS, `xcrun simctl list devices available` then `xcrun simctl boot <UDID>`), pass its
       identifier to the test runner, and shut it down in your report; never use one another session has
       booted (`simctl clone` refuses a booted source). (Parallel legs sharing one booted simulator overwrote
       each other's installed test host; dir #608.)
     - Every git call against a clone goes through `git -C "<that clone's path>"`, never after a `cd` — a
       `cd` into a directory that no longer exists fails, and the git command chained after it with `;` then
       runs in the real worktree. (A verifier's `cd <deleted sandbox> && …; git checkout …` ran the checkout
       in the orchestrator's real worktree; dir #669.)
     - DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.
     ```

   - **The trace.** The subagent's `Skill(code-review)` call mints the gate's ordinary bare-level trace when
     the Skill call returns (for the forked review, as it launches) — the hook fires for a subagent's call too, and reads the args' first word as the
     level — so there is no marker line, no `SubagentStop` trace and no dialog on this path, and the receipt
     is the bare `polish.5-review <level>`.
   - **After it returns.** First compare `git rev-parse HEAD` and `git status --porcelain` with the values
     recorded at the spawn. Any difference → the review is void AND the run **stops**: report it to the
     operator, who decides; never restore the tree with `git checkout`/`reset`/`clean`/`stash` (dir #375),
     and never fall through to the in-session attempt on a tree the subagent changed. **A final message with
     neither a findings list nor an explicit `0 findings`** — it stopped halfway, errored, was interrupted
     (a subagent that never returns is interrupted by the operator and read the same way), or handed back
     while its own background work ran — **is void too**, even though the trace was already minted when the
     skill launched: go to the in-session attempt below. Otherwise verify every finding live against the
     file before acting (`FRAMEWORK.md` "Classifying a finding"), fix the accepted ones and commit; a
     finding that fails live verification is named as refuted, with why, in step 10's summary.
   - **Delta rounds.** A fix commit (or `--amend`) moves HEAD past the trace. Send a follow-up message to
     the SAME subagent (its agent id — dir #127's "same reviewer"), repeating the prompt's instructions
     with ONE change: the Skill args are `<level> <the HEAD the last review saw>..HEAD`, so the fork
     reviews the delta, never the full diff again; that call mints the trace at the new HEAD. Record HEAD
     and status again before each follow-up message; the compare above applies to every return. dir #127's
     budget and terminal condition below apply unchanged. If the fork's `git diff` is not the delta (a
     two-dot range not honoured), the round reviewed the full diff: say so, and count it as a full pass,
     which is not dir #127's terminal signal. dir #488's review-null exception applies unchanged. The
     subagent is gone (a later session, a refused message, "No transcript found") → spawn a fresh one with
     the same prompt, the delta as the args' target, and the earlier rounds' findings, and say so; it counts
     as the same round.
   - **Step 8 denies for a missing review trace.** HEAD moved since the HEAD the last review saw (the
     common cause — a commit after the review) → the delta round above, with the same subagent, never the
     in-session attempt — unless that review itself ran in-session (a fallback below), when no K2 subagent
     exists: then the in-session attempt again at the current HEAD, with the delta args `<level> <that
     sha>..HEAD`. HEAD unchanged (the trace is genuinely missing) → the in-session attempt below.
   - **Fallbacks, in order.** The Agent tool is unavailable, the subagent reports its Skill call was
     refused, the review was voided for a missing findings list (never for a changed tree — that stops), or
     the unchanged-HEAD case just above → today's in-session attempt, `Skill(code-review)` in this session
     with the SAME two-word args `<level> origin/<default>...HEAD` (after step 8's push the skill's own
     first scope, `@{upstream}...HEAD`, is empty); refused there too → the guide's (a) and (b).
   - **Disclosure.** Step 10's summary and the PR body name this mechanism as "`/code-review <level>` run
     by a fresh-context subagent". The receipt cannot carry it (a bare level); the prose does, as for every
     other mechanism (dir #183).

   **Fixes and delta rounds, the normal path.** Fold a finding's fix into one commit where practical; on
   `--amend`, re-read the commit message against the final diff (dir #244). dir #127: the full review runs
   once, then at most TWO delta rounds; only zero findings in a delta round ends the cycle (a clean full
   re-review does not). A second delta round still finding → file the residual, say so in the PR body, open
   the PR.

   *Rare — the direct attempt refused or the Agent tool unavailable, a void review, an add-on review, a second
   delta round still finding, the in-run `--amend` path:* load the `polish-guide` skill (`keel-polish-guide`
   if aliased), else `polish-guide.md` beside this file, § Step 5; guide unreachable → stop and report.

6. **Re-run tests if the review touched code — once.** If step 5 changed any files (hand-off edits count)
   or committed pending work, and tests weren't `--no-test`-skipped, re-run the test command once, showing the real output; red → no receipt,
   report what broke and stop. Nothing changed → skip the re-run (`skipped:no-file-changes`). **Never commit,
   amend or edit while a background suite run is alive** (dir #505): it trips `tests/run.sh`'s
   self-corruption canary as a false positive. Receipt: `tools/pre-pr-gate.sh receipt polish.6-retest "$(git rev-parse HEAD)"` (or
   `skipped:no-file-changes`/`skipped:--no-test`) — the outcome IS the sha the retest ran at, and after a fix commit or `--amend` it also re-binds step 3's receipt to the new HEAD.

7. **Self-check, if this repo ships one.** If `tools/self/doctor.sh` exists at the repo root, run it. A GAP
   (non-zero exit) is a red test: no receipt, report what it flagged, stop. Receipt:
   `tools/pre-pr-gate.sh receipt polish.7-selfcheck` (or `skipped:no-doctor`). A fix commit for what it flagged
   → re-invoke `/polish`: a convergence round (step 1's pointer).

8. **Unlock the gate.** Push the branch first (the gate checks that HEAD is reachable on the push remote),
   then `tools/pre-pr-gate.sh receipt polish.8-unlock "$(git rev-parse HEAD)"`. A deny says which case it is:
   "The chain is intact" → do the one thing it names and retry; "This has discarded the receipt chain" →
   `tools/pre-pr-gate.sh init`, then `tools/pre-pr-gate.sh receipt --recover`.
   *Rare — any deny, before you act on it:* load the `polish-guide` skill (`keel-polish-guide` if aliased), else `polish-guide.md`
   beside this file, § Step 8; guide unreachable → stop and report.

9. **Open the PR.** `gh pr create --head <branch>` — `--head` is mandatory. **Write every receipt in its own
   Bash call and invoke `gh pr create` alone in the next**. Compose the title and body (what changed,
   why, a test plan); if `<keel-checkout>/tools/read-trace.sh` exists,
   include the line `bash <keel-checkout>/tools/read-trace.sh docs-line` prints. The body names every review
   mechanism that ACTUALLY RAN, not only the receipt's one. Invoking `/polish` IS the authorization to push
   and open the PR; the merge stays the operator's. Return the PR URL. Waiting on CI: ONE backgrounded `gh pr checks <n> --watch` with a timeout; never wakeups, sleeps or short Monitors. *Rare — `gh pr create` fails (the PR
   is already open, or a non-gate failure that still spends the receipt chain), an add-on review's
   disclosure:* load the `polish-guide` skill (`keel-polish-guide` if aliased), else `polish-guide.md` beside
   this file, § Step 9 (§ Step 10 for the add-on summary forms); guide unreachable → stop and report.

10. **Summary.** Briefly: what `/simplify` tidied, the test status (any post-review re-run and the
    self-check), the PR URL, every fixed finding as `file:line` — what changed (never a bare "addressed"),
    step 9's `docs read:` line unchanged if it produced one, and the review depth
    with its exact mechanism, never the depth alone — `/code-review <level>` run by a fresh-context
    subagent, a genuine in-session `/code-review <level>`, an independent agent review, plus every add-on
    that also ran, or the hand-off outcome.
