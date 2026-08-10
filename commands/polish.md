---
description: Pre-PR polish pass — simplify + tests + depth-matched code-review + gate + open the PR
argument-hint: [--no-test]
---
<!-- Installed by default (dir #68) — pairs with tools/pre-pr-gate.sh, a Claude-Code-specific hook that
install.sh never auto-wires (a hook changes what a session can do without asking each time): run
tools/install-pre-pr-gate.sh <repo> once, per project, to turn the gate below on. Without it, every
step here still runs and is worth doing — only the gh pr create block is inert. -->

The final pass over the diff before a PR — run between implementation and `/wrap`. Goal: hand a human
reviewer an already-tidied diff and open the PR. Once `tools/install-pre-pr-gate.sh` has wired the gate
for this repo, it also blocks `gh pr create` until this command has run cleanly on the current HEAD.

Project context (test command, NFRs, conventions) lives in the project's `CLAUDE.md` — re-read only what you
need, not a full onboarding.

**Where `tools/…` lives:** in your **Keel checkout**, not in the repo you are polishing — nothing is
copied into it (the hooks point at the checkout by absolute path, on purpose). So whenever the session's
cwd is another project, spell the calls below `<keel-checkout>/tools/pre-pr-gate.sh …`, and run them
**from the repo being polished** — the gate keys its receipt off the cwd, so the directory you call from
is what identifies the run, and the script's own location is irrelevant to it.

Each step below ends with a **receipt**: run `tools/pre-pr-gate.sh receipt <step-id> [outcome]` from the
repo root (default outcome `done`; a conditional step that didn't apply writes `skipped:<reason>` instead,
and a step that ran only in a degraded form says so the same way, `<how>:<reason>` — a skip and a
degradation are both executed decisions, so the id is still written). This is a completeness record, not
proof of work: `pre-pr-gate.sh` denies `gh pr create` unless every step id below is present for the current
run (dir #49). Never skip a receipt write even on a step that "obviously" ran. **If any receipt/log call
in the steps below triggers an unexpected permission prompt** (the harness's auto-mode classifier
flagging a plain `Bash` call it shouldn't), note it once per run with `tools/pre-pr-gate.sh log
receipt-friction classifier` — this is friction data for the pilot's own keep/drop review, not a step to repeat per-occurrence.

Steps, in order:

1. **Diff.** `git fetch --prune`, then `git diff origin/<default>...HEAD` (or the working-tree `git diff` if
   nothing is committed yet) — that is the scope of this pass. If there is no diff, say so and stop; leave the
   gate untouched (no receipt — nothing to unlock yet).

   Otherwise, start this run's receipt: `tools/pre-pr-gate.sh init` (mints a fresh nonce, discarding any
   earlier run's leftover receipt).

   **Convergence round?** If this invocation exists ONLY because step 5's own review found a real
   finding, you fixed it, committed it, and re-invoked `/polish` on the same branch — the step-1 diff
   above is the same one a prior run already diffed/simplified/tested/sized/self-checked, plus that one
   fix commit — run `tools/pre-pr-gate.sh receipt --recover` right now, before step 2. On success (it
   reports how many steps it restored) that call has re-stamped the prior run's receipts onto this run's
   fresh nonce, without overwriting anything this run already wrote (dir #96 — so the order of
   `--recover` against your own receipt calls does not matter):
   **treat steps 2, 4, and 7 below as DONE — do not invoke them again, and do
   not write fresh receipts for them.** A fresh write would silently overwrite the just-recovered one
   (last write for a given step id wins, per the gate's own parser) — pointless for 1/2/7 (their
   receipted outcome is just a completion marker) and actively wrong for `polish.4-depth`, whose sized
   level step 5 will be cross-checked against: overwriting it with a stale pre-fix-commit sizing would
   compare this round's real review against the wrong baseline.
   **One exception inside that set (dir #116): a `skip`-level step 4 is never recovered** — `--recover`'s
   closing note names it withheld when that happens. `skip` is the one depth that bypasses step 5
   outright, so inheriting it would hand the fix commit a review bypass the operator chose for a
   different diff. When the note names `polish.4-depth`, step 4 is NOT done: go re-size the diff there
   fresh (its own skip rule — dialog included — applies to this round's diff as usual).

   **Step 3 is NOT in that recovered-and-done set** (dir #96): its receipt names the sha the tests ran
   at, which after your fix commit is no longer the commit being shipped. **You always WRITE step 3's
   receipt** — it stays in the completeness set, so omitting it denies for a missing step id and costs
   you the whole round, and it must carry the new HEAD's sha: re-run the tests there. Don't plan on
   step 6's retest carrying the binding for you — it does satisfy the gate when it happens (a later
   commit, say a CHANGELOG entry, legitimately rebinds through step 6), but the normal convergence
   outcome is a clean delta re-review that changes no files, and step 6 then writes
   `skipped:no-file-changes`, which binds nothing. So: go to step 3, then step 5 for the delta
   re-review, then 6 and 8, which always need a fresh value. Only steps 2, 4 and 7 are genuinely done
   (step 4 minus the withheld-`skip` exception above).

   **Do NOT use `--recover`'s own output to decide whether this is a convergence round.** It reports
   success for any retired prior run — an interrupted run, a denied `gh pr create`, any second `init` —
   because `retire_sentinel` backs up on every invalidation path and its lineage guard compares a
   base-sha stamped at retirement time, which is *inside* `init` and therefore already past your fix
   commit. Only you know why you re-invoked. If nothing was retired at all it will say so, and that
   does tell you this is a fresh run — but the converse carries no information.

   Not a convergence round (the ordinary case): `tools/pre-pr-gate.sh receipt polish.1-diff`, then
   continue through every step below in order.

2. **Simplify.** *Skip entirely if step 1's convergence branch just recovered this step's receipt.*
   Invoke the `/simplify` skill — it runs the cleanup pass (duplication, dead code,
   over-complication, naming) and applies the fixes. Wait for it to finish before the next step.
   **Establish availability by *attempting* the call, never by inferring it from the skill listing** — a
   skill can be installed and still refuse model invocation, and only the attempt returns the reason.
   If it is genuinely unavailable, do ONE inline cleanup pass over the step-1 diff yourself, say what you
   tidied, and receipt the degradation rather than a bare `done` — a bare `done` reads as a real
   `/simplify` run, which is the substitution step 5 exists to stop, one step earlier.
   Receipt: `tools/pre-pr-gate.sh receipt polish.2-simplify` (or `... polish.2-simplify
   inline:no-simplify-skill`).

3. **Tests — run them by default.** *You may skip the RUN only if HEAD has not moved since the tests
   last passed — which in a convergence round it has, by definition (step 1's branch includes a fix
   commit); the case where this applies is an interrupted re-run. Either way you always WRITE this
   receipt: `--recover` never restores it.* Take the
   test command from the project's `CLAUDE.md` and run it. Show the
   real output (green/red); never claim "passed" without it. **Exception:** if `$ARGUMENTS` contains
   `--no-test`, skip the run and say explicitly that tests were skipped by request (the human runs them before
   the PR).
   Receipt: `tools/pre-pr-gate.sh receipt polish.3-tests "$(git rev-parse HEAD)"` (or `...
   polish.3-tests skipped:--no-test`, or `... polish.3-tests skipped:no-test-command` when the project
   genuinely ships no test command — the same escape step 7 has as `skipped:no-doctor`) — **the sha is
   the point** (dir #96): the gate unlocks only when
   some test run is bound to the commit being shipped, via this receipt or step 6's retest. After a fix
   commit the previous round's sha is no longer that commit, so either the tests re-run here or step 6
   binds the new HEAD. Only those two named literals waive it; an
   invented `skipped:<anything-else>` is denied, and a prior round's waiver is never carried over —
   `--recover` does not restore this step at all.

4. **Pick a review depth — matched to the diff, mostly automatic.** *Skip entirely if step 1's convergence
   branch just recovered this step's receipt* — reuse the recovered level as-is; do not re-size (the
   recovered `polish.4-depth` is the baseline step 5's delta re-review gets cross-checked against, and a
   fresh sizing pass here would silently replace it, per step 1). A recovered `skip` never arrives here
   (dir #116 — `--recover` withholds it and its note says so): if the prior round chose `skip`, this
   step runs fresh, skip dialog and all, for the round's own diff. Otherwise, gate this on the steps above
   being clean: proceed only if simplify left no open problems AND (tests are green OR were explicitly
   skipped). Otherwise report what is left and stop — do NOT write this step's receipt or the sentinel.

   **First check `tools/pre-pr-gate.sh handoff-check` — a match means step 5 already stopped to ask
   about THIS exact commit on an earlier invocation.** Reuse its recorded level as-is rather than
   re-sizing from scratch: the diff hasn't changed since the question was asked (same SHA), and a fresh
   sizing pass can land on a different bucket than the original one did on a borderline diff, which
   would make this step's own receipt disagree with the level the hand-off is about to resolve — the
   gate now denies exactly that mismatch. No match (no pending hand-off, or a different commit): size
   normally, below.

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
     this step's sizing is the model's own and unchecked. **This ask-dialog itself carries NO marker**
     — like every sizing dialog in this step. The marker lives ONLY in the follow-up confirm dialog
     below: a marker in the ask-dialog's own question would write the `dialog:skip` trace at
     answer time regardless of WHAT was answered, so an operator overriding to `medium` would still
     leave a skip credential for this sha (found by the operator's second-opinion review — the exact
     stale-line class dir #116 exists to close). **When the answer here is `skip`, open one follow-up
     confirm dialog whose question text carries the literal line `KEEL-DEPTH-DIALOG: level=<level>`
     with `<level>` replaced by the word `skip`** — plain text, no markdown formatting, the same
     literal-match and placeholder discipline as step 5(a)'s marker. This instruction deliberately
     never spells the composed line: the hook greps raw question text, so any dialog QUOTING a
     spelled-out marker (this file, a deny recap) would mint the trace credential without the skip
     question ever being asked — found and reproduced by the operator's third review pass; the `<...>`
     placeholder is exactly how step 5(a) avoids the same self-quote hole, and the composed line only
     ever exists inside a genuine confirm dialog. The gate denies a `skip` unlock unless that confirm
     dialog was answered for the exact commit being shipped. The token is deliberately DIFFERENT from
     step 5(a)'s `KEEL-REVIEW-DIALOG` — the trace leg accepts only `skip` on it, so no step-4 dialog
     can pre-satisfy step 5(a)'s own dialog check by construction. If the confirm answer is NOT skip
     (the operator changed their mind), the written trace line is stale for an honest flow — but an
     honest flow then records a non-skip depth, which the gate checks by its own legs; reading the
     answer itself and not writing the line at all is dir #118.
   - **`low`/`medium` on a diff that sits clearly inside one bucket → run that level automatically**,
     no dialog; state which level and why.
   - **Borderline (near a boundary, references present, mixed) → open the `AskUserQuestion` dialog** with
     the recommended level pre-selected and a **skip** option always present; let the human override.
     This dialog carries NO marker. **If the human picks `skip` here**, open the same marker-carrying
     confirm dialog the skip bullet above specifies — one extra click, and the only way the
     gate can tell "the operator chose skip for THIS diff" from an inherited or auto-selected one
     (dir #116; the trace records the question's marker, not the chosen answer, which is why the
     confirm dialog exists at all). **The same rule holds for EVERY dialog in this step whose answer
     lands on `skip`** — the high+/ultra dialog above included: an operator declining an expensive
     review down to no review at all is still choosing `skip`, and without the marker-carrying confirm
     dialog the gate will deny step 8 and ask for a question that was, from the operator's view,
     already answered. One confirm click closes that gap on every path.

   Receipt: `tools/pre-pr-gate.sh receipt polish.4-depth <level>:<what it was sized from>` — e.g.
   `low:+38-8,2f,docs` or `medium:+412-96,10f,code`. A bare level records the conclusion and throws away
   the evidence for it; the measurement is what makes a questionable call visible afterwards.

5. **Run the chosen review — one terminal pass, no loop-back.** For `skip`, do nothing — the decision
   already happened at step 4's skip dialog, which the gate cross-checks per commit (dir #116; a fix
   commit moving HEAD needs that dialog re-answered at step 4, not here). `ultra` you
   cannot launch at all (cloud, billed, user-triggered) — always go straight to (b), no automated
   alternative attempted. For `low|medium|high|max`, do NOT attempt `Skill(code-review)`: the built-in
   `/code-review` is not model-invokable in-session — a documented harness policy
   (`disable-model-invocation`, verified 2026-07-29 against the Claude Code docs) — so the automated path
   IS branch (a) directly, no attempt first. **Revisit trigger:** if a session ever observes the harness
   accepting a model invocation of `/code-review` (a docs/policy change, or the `skillOverrides` mechanism
   becoming applicable), restore attempt-first — the gate's Skill/UserPromptExpansion trace legs and the
   bare-`<level>` receipt outcome already cover a genuine in-session run natively, so nothing else needs
   rebuilding. Either way, do not substitute `/review` (a GitHub-PR command, not a working-diff review) and
   do not guess.

   **A genuine call here is no longer just a claim.** When `/code-review` is actually invoked (by you, or
   directly by the operator typing it), a harness hook mechanically records a trace to a side channel this
   flow doesn't otherwise write to — `tools/pre-pr-gate.sh`'s gate cross-checks it (same commit, same
   level) before unlocking. The independent-agent-review path below (a) leaves the same kind of mechanical
   trace, via a different hook. The gate also cross-checks EVERY outcome, including a hand-off's
   `-operator-run`/`-waived`, against the level step 4 actually recorded — `skip`ping the review while
   claiming a higher depth was sized doesn't unlock the gate either.
   **Residual limit:** only the LAST-resort inline pass — (a)'s own fallback, when the Agent tool itself is
   unavailable — still leaves no trace by construction; that path's outcome (`-operator-run`/`-waived`)
   stays self-reported. The trace only makes "claims a review ran when it didn't" checkable, not either
   reviewer's own thoroughness.

   - **(a) Go straight here for `low|medium|high|max` — an independent subagent reviews instead of you.**
     `/code-review` is not model-invokable in-session (the standing fact above, not a per-run refusal) — a
     DIFFERENT, independent reviewer has to run it. Spawn ONE fresh-context Agent-tool subagent,
     `subagent_type: "general-purpose"`. Its
     prompt must carry: the step-1 diff scope, the step-4 chosen depth, a correctness-focused review
     mandate, and an explicit **read-only instruction** — review only, no file edits, no live-environment
     reproduction (a prior incident: a full-Bash review subagent once overwrote real machine files while
     "empirically verifying" a bug in-place; memory `subagent-live-verification-risk`). It must also carry
     the ticket or spec this diff implements — when the session knows it (an id, or the done-criterion
     text itself) — with a **two-way conformance mandate**: the diff must realize that done-criterion, and
     nothing in it may silently exceed or contradict it. **When no ticket exists** (an ad-hoc diff with no
     tracked done-criterion), the prompt states that absence explicitly rather than leaving the reviewer to
     assume a spec it was never given, and the review stays correctness-only. The prompt MUST
     also require the subagent to end its final response with a line, alone, exactly
     `KEEL-AGENT-REVIEW: level=<level>` (the chosen depth) — **plain text, no markdown formatting**: not
     inside backticks, not inside a code fence, no trailing punctuation. The hook matches this line
     literally, so a stray backtick a subagent adds out of habit is enough to leave no trace even after a
     genuine review. A `SubagentStop` hook is the only way `tools/pre-pr-gate.sh` can observe this review
     at all (unlike a Skill call, a subagent event carries no `prompt`/call-argument field to read from —
     only the subagent's own final text), so an omitted or malformed marker line leaves no trace and the
     gate denies later, at step 8. Resolve any real findings
     the subagent reports, the same as a real `/code-review` pass, then receipt immediately:
     `polish.5-review agent:<level>` — unlike the pre-dir-#70 inline fallback, this receipt is written
     BEFORE any hand-off, because the review already happened and is independently, mechanically
     verifiable (the trace).

     **MANDATORY NEXT ACTION — open an `AskUserQuestion` dialog before touching step 6.** The gate now
     denies an `agent:*` unlock with no answered dialog for this commit (dir #88, once
     `tools/install-pre-pr-gate.sh` has wired the `AskUserQuestion` hook — see that file's own header):
     the question text MUST carry, verbatim and somewhere in the question, the literal line
     `KEEL-REVIEW-DIALOG: level=<level>` (the chosen depth) — plain text, no markdown formatting, same
     literal-match discipline as the `KEEL-AGENT-REVIEW` marker above, since the gate greps for it, not
     the human-facing wording. This fires every time execution reaches here, including a
     convergence-round re-review after a fix commit (see the terminal-pass note below). Each such round
     moves HEAD, and a hand-off note is same-SHA-only (per (c)), so an earlier round's dialog doesn't
     cover a later commit.

     **Frame this as ONE additive yes/no question, never as a choice between mechanisms** (dir #81): the
     agent review already ran and its receipt above already stands — nothing here reopens or discards it,
     whatever the answer. Report what the agent review checked and found, state plainly that this review
     already ran and stands regardless of the answer, then ask only whether to ADDITIONALLY run the
     stronger built-in `/code-review <level>` on top — the built-in pass is a multi-agent pipeline
     (parallel reviewers plus adversarial verification of their findings); one subagent is a real
     independent review, but likely stays weaker, so there is a genuine reason to want both. Phrase the
     options additively, never as accept-one-reject-the-other: "proceed — the agent review is enough for
     this diff" / "I'll run `/code-review <level>` too". Print the exact `/code-review <level>` command
     and open the dialog — the same real, pausing mechanism step 4 uses for its own dialog, not a
     rhetorical question the flow can talk itself past. Record the hand-off exactly as (b) does —
     `tools/pre-pr-gate.sh handoff <level> "$(git rev-parse HEAD)"` — so a re-invocation doesn't have to
     rely on session memory (see (c)).

     **On "proceed":** re-run `tools/pre-pr-gate.sh receipt polish.5-review agent:<level>` (the same
     outcome, written again) — idempotent, and its side effect is what clears the hand-off note; skipping
     this re-write leaves a stale hand-off note on disk that can force a spurious re-ask on a later
     re-invocation of this same commit.

     **On "I'll run `/code-review <level>` too": that command is the OPERATOR's to run, not yours — it is
     not model-invokable in-session.** Wait for them to run it (or report their findings — unchanged,
     still waits for the operator, dir #81 fork 4), then resolve what it reported and write the COMBINED
     outcome: `polish.5-review agent:<level>+operator-run` — a new, honest record naming BOTH reviews that
     ran, not an overwrite that erases the agent review the receipt above already established (whichever
     receipt is written LAST for this step wins — see (c)).

     **Anti-rebundle rule:** if a future edit ever makes the agent review itself optional or something to
     ask about, that must be its OWN separate question — never re-bundled with this one into a single
     dialog. This ticket (dir #81) exists because those two concerns were bundled once already.

     **Fallback within a fallback:** only if the Agent tool ITSELF is unavailable/refuses (establish this
     the same attempt-don't-infer way) does the pre-dir-#70 behavior apply — one inline review pass of the
     step-1 diff yourself (correctness-focused, same single-terminal-pass rule as below), say what you
     checked and found the way step 3 has to show real test output (an assertion with nothing to inspect
     is indistinguishable from a pass that didn't happen), then go to (b) below for real: no independent
     reviewer exists here at all, self-reported, in the same context that wrote the code.
   - **(b) Stop for real** — `ultra`, or (a)'s own Agent-tool-unavailable fallback. Report that no real
     review could be run in-session, print the exact `/code-review <level>` command, and open an
     `AskUserQuestion` dialog asking whether to run it or to proceed without. Do NOT write this step's
     receipt, do NOT write the sentinel, and do NOT open the PR on your own initiative. **The failure this
     closes:** continuing to a merged-ready PR and disclosing the substitution only in the closing
     summary, where the operator finds out by reading the transcript — or not at all. Record the hand-off
     so a re-invocation doesn't have to rely on session memory: `tools/pre-pr-gate.sh handoff <level>
     "$(git rev-parse HEAD)"`.
   - **(c)** Once they answer — or, on a re-invocation, check `tools/pre-pr-gate.sh handoff-check`: a
     match means a question from (a)'s reminder or (b)'s real stop was already raised for this EXACT
     commit (the check is same-SHA-only — any new commit invalidates it). The hand-off note carries only
     the level and sha, not which of (a)/(b) raised it nor the prior pass's findings — `init`'s nonce reset
     already discarded that receipt — so collect the operator's answer/evidence now (if not already given)
     and:
     - If they ran `/code-review <level>` themselves, **resolve any findings their review reported** (same
       bar as the in-session path; a review nobody acts on bought nothing). **If `level` is `ultra`, skip
       straight to the plain outcome** — `polish.5-review <level>-operator-run` — an `ultra` hand-off only
       ever came from (b) (same reasoning as the bullet below), so no agent review or trace can exist for
       it and trying the combined outcome first would only buy a guaranteed step-8 denial before falling
       back anyway. Otherwise, the common case is that this hand-off came from (a) — an agent review
       already ran and was independently receipted before the dialog ever opened — so try the COMBINED
       outcome first: `polish.5-review agent:<level>+operator-run` (this also clears the hand-off note).
       Only if step 8 later denies it for a missing/mismatched agent trace — meaning this hand-off actually
       came from (b), where no agent review ever ran — fall back to the plain outcome,
       `polish.5-review <level>-operator-run`. **A `review-dialog-missing` denial is a DIFFERENT deny
       (dir #88) and must NOT be treated as this fallback trigger:** it means the DIALOG, not the agent
       trace, is what's missing — the agent review itself is fine. The fix is to open/answer (a)'s
       `AskUserQuestion` dialog (with the `KEEL-REVIEW-DIALOG: level=<level>` marker) for current HEAD,
       then re-write the same combined outcome — never fall back to the plain `-operator-run` outcome for
       this deny, which would silently drop the agent review half (the exact dir #81 anti-pattern this
       combined outcome exists to prevent).
     - If they explicitly waived the review instead of running it, receipt `polish.5-review <level>-waived`
       (this also clears the hand-off note) — (a)'s dialog never offers a waive option, so this only ever
       resolves a (b) hand-off.
     - Otherwise, and **only when `level` is NOT `ultra`** (an `ultra` hand-off only ever came from (b) —
       `ultra` never reaches (a), so there is no agent review to fall back to; keep waiting on the
       operator's own decision instead), they want to proceed on an agent review, or the Agent tool is
       available again now: first re-try the CHEAP path — `tools/pre-pr-gate.sh receipt polish.5-review
       agent:<level>` — since the trace file (unlike the receipt sentinel) survives `init`'s nonce reset,
       so a genuine trace the original (a) pass already wrote for this exact commit is very likely still
       there and this bare receipt write may already satisfy the gate with no new subagent call. Only
       redo (a) fresh (a subagent call is cheap and self-contained, but not free) if step 8 later denies
       it as a missing/mismatched trace — meaning the original pass never actually produced one (e.g. a
       malformed marker line).
     **This is the branch's only exit.** The hand-off note lives in its own file, untouched by `init`'s
     nonce reset (which only discards the previous run's receipts), so a re-invoked `/polish` re-sizes the
     same diff and picks the same level — without `handoff-check`, it would defer again, and every time
     after that.
   - **(d)** Every outcome is load-bearing for step 10: the summary must name exactly which review
     mechanism ran — a genuine in-session `/code-review <level>`, an independent agent review, both (the
     combined outcome, dir #81), or (a)'s own last-resort inline self-review — never just the depth.
     "review: medium" reads identically to a genuine in-session pass, which is how any substitution stays
     invisible.

   **This review is a single terminal pass over its own findings: it must NOT re-invoke `/simplify` or
   loop back to step 4.** No infinite cycle. **A fix-commit moving HEAD afterward is expected, not a rule
   violation** — the gate's SHA/trace checks (step 8) are keyed to whatever HEAD ends up being, so fold a
   real finding's fix into the same commit where practical, then **converge, don't restart**: on the
   re-invocation this produces, step 1's own convergence branch (`receipt --recover`) already skipped
   steps 2 and 7 for you, and step 4 unless the prior round's depth was `skip` (never carried — dir
   #116, see step 1; NOT step 3 — it must bind this commit, see step 1) — arriving here, re-review only the DELTA the fix introduced, not the full step-1
   diff again, and stop as soon as a pass needs no further changes; park a non-blocking note (a style nit,
   a "consider later") in the step 10 summary instead of chasing it into another round. **"Stop" here
   means stop re-reviewing — it does NOT mean step 5 is done:** the MANDATORY dialog in (a) above still
   applies to this round's fresh receipt before moving to step 6, same as the first pass.
   Receipt: `tools/pre-pr-gate.sh receipt polish.5-review <level>` (e.g. `agent:medium` — the ordinary
   automated outcome — or `low`/`high` for a genuine operator-typed/revisit-triggered `/code-review` pass,
   `medium-operator-run`, `ultra-operator-run`, `medium-waived`, `skip`, or `agent:medium+operator-run` —
   the combined outcome (dir #81) when the operator additionally ran `/code-review` on top of an
   already-standing agent review).

6. **Re-run tests if the review touched code — once.** If step 5 changed any files (and tests weren't
   `--no-test`-skipped), re-run the test command a single time — review fixes can break something. **Files
   changed during the hand-off count as step-5 changes** — whether the human's own `--fix` run edited them
   or you did, resolving the findings their review reported. Those land between `/polish` invocations, so
   "did step 5 change files" is otherwise easy to read as "no", and the retest gets skipped after exactly
   the kind of edit it exists to cover. Show the
   real output. If it went red, do NOT write this step's receipt or the sentinel — report what broke and
   stop; the human fixes and re-invokes. **This is one bounded re-run, not a loop back to simplify or the
   review dialog.** If the review changed nothing (or tests were skipped), skip the re-run.
   Receipt: `tools/pre-pr-gate.sh receipt polish.6-retest "$(git rev-parse HEAD)"` (or `...
   polish.6-retest skipped:no-file-changes`) — the outcome IS the sha the retest ran at, same convention
   as step 8, not a bare `done`: step 6 is one of the four steps a convergence round must write itself
   (3, 5, 6, 8 — step 1's branch hands back only 2, 4 and 7), and its whole job is to catch a fix-commit
   breaking something. So the gate cross-checks it against current HEAD the same way it does steps 3 and
   8 — a bare `done` would mean a recovered, pre-fix-commit retest could otherwise satisfy completeness
   without the fix-commit ever having been re-tested.

7. **Self-check, if this repo ships one.** *Skip entirely if step 1's convergence branch just recovered
   this step's receipt.* If `tools/self/doctor.sh` exists at the repo root, run it —
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
   #49), not a step of the happy path — skip it when the gate never denies. **If the gate still denies
   after one clean re-`init`+re-receipt pass on a busy repo** (dir #80: the gate's sentinel is keyed by
   (repo, branch) — two worktrees of this repo on the SAME branch, or heavy concurrent `/polish` activity
   right at `init` time, can still race one slot): hand the exact `gh pr create --head <branch>` command to
   the operator to run from their own terminal — a manually-run command bypasses the PreToolUse hook
   pipeline entirely, so it isn't subject to the race at all. Last resort, after one honest retry.

9. **Open the PR.** After the gate passes, run `gh pr create --head <branch>` — **the `--head` flag is
   mandatory, not optional**: the gate keys its receipt by branch (dir #80), and the hook's event cwd may
   not be your worktree, so a bare `gh pr create` can resolve the wrong branch (or none) and false-deny.
   Compose the title and body from the implementation context (what changed, why, a test plan). **If step
   5's outcome was `agent:<level>`, the PR body must label the review as such** — e.g. "review: independent
   agent at `<level>` (built-in `/code-review` not model-invokable in-session)" — never presented as if
   `/code-review` itself ran. **If the outcome was the combined `agent:<level>+operator-run` (dir #81), the
   PR body must name BOTH** — the independent agent review AND the operator-run `/code-review` — never
   collapsed into just one. Return the PR URL. Invoking `/polish` IS the standing authorization to push the
   branch and run `gh pr create --head <branch>` at this step; do not re-ask. The merge stays the
   operator's.

10. **Summary.** Briefly: what `/simplify` tidied, the test status (including any post-review re-run and
    self-check result), which review depth ran (or that it was skipped), and the PR URL. **Name the exact
    review mechanism, never just the depth** — a genuine in-session `/code-review <level>`; an
    independent agent review (`review: <level>, independent agent review — built-in /code-review not
    model-invokable in-session`, matching the PR body's own label); **both, when the operator additionally
    ran `/code-review` on top of an already-standing agent review (the combined `agent:<level>+operator-run`
    outcome, dir #81)** — name BOTH mechanisms, e.g. `review: <level>, independent agent review +
    operator-run /code-review`, never collapsed into just one of them; or, if step 5 took the (b) hand-off,
    that no real review ran in-session and whether the human ran it (`-operator-run`) or waived it
    (`-waived`, leaving only (a)'s last-resort inline pass). A bare depth is indistinguishable from a
    genuine in-session review, so reporting one here would re-hide exactly what step 5 exists to surface.
