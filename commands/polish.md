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

   **Convergence round?** If this invocation exists ONLY because a later step of a prior run found a
   real finding — step 5's review, or step 7's self-check (dir #119: a WARN you chose to fix, or a GAP
   that stopped that run) — and you fixed it, committed it, and re-invoked `/polish` on the same branch,
   then the step-1 diff above is the same one a prior run already
   diffed/simplified/tested/sized/self-checked, plus that one
   fix commit — run `tools/pre-pr-gate.sh receipt --recover` right now, before step 2. On success (it
   reports how many steps it restored) that call has re-stamped the prior run's receipts onto this run's
   fresh nonce, without overwriting anything this run already wrote (dir #96 — so the order of
   `--recover` against your own receipt calls does not matter):
   **treat steps 2, 4, and 7 below as DONE — do not invoke them again, and do
   not write fresh receipts for them** (step 4 minus the `skip` exception below, step 7 minus the GAP
   exception at the end of this branch). A fresh write would silently overwrite the just-recovered one
   (last write for a given step id wins, per the gate's own parser) — pointless for 1/2/7 (their
   receipted outcome is just a completion marker) and actively wrong for `polish.4-depth`, whose sized
   level step 5 will be cross-checked against: overwriting it with a stale pre-fix-commit sizing would
   compare this round's real review against the wrong baseline.
   **One exception inside that set (dir #116, narrowed by dir #236): a `skip`-level step 4 recovers only
   when it was decided against the commit that is STILL current HEAD** — i.e. nothing has shipped since,
   the case a missing step 5 receipt alone forced (dir #236's felt case), not a genuine fix commit.
   `--recover`'s closing note names it withheld whenever that's not true: `skip` is the one depth that
   bypasses step 5 outright, so inheriting it across an actual fix commit would hand that commit a review
   bypass the operator chose for a different diff. When the note names `polish.4-depth`, step 4 is NOT
   done: go re-size the diff there fresh (its own skip rule — dialog included — applies to this round's
   diff as usual).

   **Step 3 now also recovers, but only PROVISIONALLY (dir #123 — narrower than dir #96's original
   blanket exclusion)**: treat it as done for now — do not re-run the tests just because this is a
   convergence round — but do not fully trust it either. Its recovered receipt still names the sha the
   tests actually ran at, which after your fix commit is not the commit being shipped; what makes it
   still usable is a tree-relevant hash the gate stamped onto it at write time, which the final check at
   step 8 recomputes for the NEW HEAD and compares. **What counts as exempt is narrower than "any `.md`
   file"** (an earlier version of this ticket assumed that and shipped it, then an operator-run
   `/code-review high` reproduced it live as unsound: most of this repo's own `.md` surface — `CORE.md`,
   `templates/CLAUDE.md`, `commands/*.md`, `FRAMEWORK.md`, `docs/*.md`, `README.md`, even `CHANGELOG.md`
   itself — is read by a real test in `tests/`) — a `.md` file is exempt ONLY when no file under
   `tests/` mentions its basename at all (checked mechanically, not guessed; self-maintaining as tests
   are added). Concretely for this repo: a moved bullet in `BACKLOG.md` (gitignored, untracked, never in
   the tree at all) or a change to one of the handful of genuinely test-free docs is exempt; a CHANGELOG
   paragraph is, in THIS repo, actually NOT exempt (`tests/test_doc_figures.sh` checks its size), so
   don't expect that specific case to skip a test run here even though it motivated the ticket. If your
   fix commit touched nothing exempt, step 8's comparison matches and unlocks with no test run this
   round. If it touched anything else, step 8 denies with "no test suite run is bound to current HEAD" —
   that denial is the signal, not something to predict up front: at that point go back to step 3,
   actually run the tests, and write a fresh receipt carrying the new HEAD's sha
   (`tools/pre-pr-gate.sh receipt polish.3-tests "$(git rev-parse HEAD)"`), then continue on to step 8
   again. **A different denial — "missing receipt for step(s): polish.3-tests" instead of the sha-unbound
   one above — means the SAME thing but arrived a different way**: the prior round's step 3 was a
   `skipped:--no-test`/`skipped:no-test-command` waiver or a legacy bare sha (no stamped hash at all), so
   `--recover` never carried it forward in the first place (unchanged from dir #96 — a waiver must never
   silently re-apply to a round the operator didn't give it to). Same fix either way: go run the tests
   fresh. Don't plan on step 6's retest carrying the binding either way — it does satisfy the gate when
   it happens (a later commit, say a genuinely test-free doc entry, legitimately rebinds through step 6),
   but the normal convergence outcome is a clean delta re-review that changes no files, and step 6 then
   writes `skipped:no-file-changes`, which binds nothing on its own. So the ordinary round is
   5 (delta) → 6 → 8, with step 3 only re-entered if step 8 denies (either shape above); steps 2, 4 and 7
   are unconditionally done (step 4 minus the withheld-`skip` exception above; step 7 minus the GAP
   exception just below).

   **When step 7 was the trigger (dir #119), which of its two triggers it was decides one thing.** A
   WARN you chose to fix left the prior run's `polish.7-selfcheck` receipt written, so it recovers and
   step 7 stays done. **A GAP did not** — step 7 stops the run *before* writing its receipt, so the
   backup never held it and `--recover` cannot restore it (its count won't mention a step that was never
   there): in that case go run step 7 again this round and write the receipt fresh, or step 8 denies for
   a missing step id. So the round is 5 (delta) → 6 → 8 after a WARN trigger, and
   5 (delta) → 6 → **7** → 8 after a GAP one (either way, step 3 only re-enters if step 8 denies for a
   stale test binding, per above) — the sequence is the only thing the two differ in. And
   even where the receipt does recover, it attests the *prior* run's self-check, taken before your fix
   existed: re-run `tools/self/doctor.sh` by hand and confirm the finding is gone before unlocking. That
   hand-run is verification, not a step — no receipt, no change to the sequence. If it surfaces something
   new needing another fix commit, that is simply the next convergence round, entered here again.

   **Do NOT use `--recover`'s own output to decide whether this is a convergence round.** It reports
   success for any retired prior run — an interrupted run, a denied `gh pr create`, any second `init` —
   because `retire_sentinel` backs up on every invalidation path and its lineage guard compares a
   base-sha stamped at retirement time, which is *inside* `init` and therefore already past your fix
   commit. Only you know why you re-invoked. If nothing was retired at all it will say so — but that
   answer has a mirror-image trap too (dir #177): the identical `nothing to recover` message is also
   the correct, by-design result when a fix already went in via the in-run path below (resolve,
   `--amend`, and continue the same run without ever re-`init`-ing) and you only reach this branch
   later, for an unrelated reason — nothing was retired there either, yet a fix commit already sits
   ahead of `polish.3-tests`'s stamped sha. Read `nothing to recover` as telling you only that nothing
   was retired since the last `init` — never as telling you this is a fresh run.

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

3. **Tests — run them by default.** *Skip entirely if step 1's convergence branch just recovered this
   step's receipt (dir #123, provisional — see step 1) — do not invoke this step and do not write a
   fresh receipt, unless step 8 later denies for a stale test binding, at which point come back here.*
   Outside a convergence round, you may skip the RUN only if HEAD has not moved since the tests last
   passed (an interrupted re-run) — you still always WRITE this receipt in that case. Take the
   test command from the project's `CLAUDE.md` and run it. Show the
   real output (green/red); never claim "passed" without it. **Exception:** if `$ARGUMENTS` contains
   `--no-test`, skip the run and say explicitly that tests were skipped by request (the human runs them before
   the PR).
   Receipt: `tools/pre-pr-gate.sh receipt polish.3-tests "$(git rev-parse HEAD)"` (or `...
   polish.3-tests skipped:--no-test`, or `... polish.3-tests skipped:no-test-command` when the project
   genuinely ships no test command — the same escape step 7 has as `skipped:no-doctor`) — **the sha is
   the point** (dir #96): the gate unlocks only when
   some test run is bound to the commit being shipped, via this receipt (directly, or — dir #123 — via
   a still-matching tree-relevant hash carried over from a recovered receipt), or step 6's retest. Only
   the two named literals waive it; an invented `skipped:<anything-else>` is denied, and a prior round's
   *waiver* is never carried over on recovery — only a real sha's tree-relevant hash is.

4. **Pick a review depth — matched to the diff, mostly automatic.** *Skip entirely if step 1's convergence
   branch just recovered this step's receipt* — reuse the recovered level as-is; do not re-size (the
   recovered `polish.4-depth` is the baseline step 5's delta re-review gets cross-checked against, and a
   fresh sizing pass here would silently replace it, per step 1). Non-skip levels always recover (dir
   #72's convenience) and never reach this step's body at all. A `skip` level only recovers — `--recover`
   (dir #116, narrowed by dir #236) — when the commit it was decided against still matches current HEAD,
   i.e. nothing shipped since; a skip decided against an earlier commit still withholds and its note says
   so, same as before dir #236. So: **this step's body is reached only when the note names
   `polish.4-depth` as withheld** — a skip that didn't recover — and runs fresh (skip dialog and all) for
   the round's own diff. Otherwise, gate this on the steps above
   being clean: proceed only if simplify left no open problems AND (tests are green, or were explicitly
   skipped, or step 1 recovered step 3 provisionally per dir #123 — that provisional state is enough to
   proceed; step 8 is what actually re-verifies it). Otherwise report what is left and stop — do NOT
   write this step's receipt or the sentinel.

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
   - **`max` or `ultra` → always open an `AskUserQuestion` dialog, never auto-run.** (Raised from
     `high`-and-above by dir #254, 2026-08-26: the model can now run the review itself — see step 5 — so
     the ask threshold moves to just the two ends of the scale that spend the human's money or safety
     margin directly.) `ultra` is billed and `max` is the heaviest automated pass — spend either only on
     an explicit yes. (A fixed cost rule, not a live budget check: there is no token-budget signal.)
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
   - **`low`/`medium`/`high` on a diff that sits clearly inside one bucket → run that level automatically**
     (dir #254: an unasked `high` is now the EXPECTED behaviour here, not a failure), no dialog; state
     which level and why.
   - **Borderline (near a boundary, references present, mixed) → open the `AskUserQuestion` dialog** with
     the recommended level pre-selected and a **skip** option always present; let the human override.
     This dialog carries NO marker. **If the human picks `skip` here**, open the same marker-carrying
     confirm dialog the skip bullet above specifies — one extra click, and the only way the
     gate can tell "the operator chose skip for THIS diff" from an inherited or auto-selected one
     (dir #116; the trace records the question's marker, not the chosen answer, which is why the
     confirm dialog exists at all). **The same rule holds for EVERY dialog in this step whose answer
     lands on `skip`** — the max+/ultra dialog above included: an operator declining an expensive
     review down to no review at all is still choosing `skip`, and without the marker-carrying confirm
     dialog the gate will deny step 8 and ask for a question that was, from the operator's view,
     already answered. One confirm click closes that gap on every path.

   Receipt: `tools/pre-pr-gate.sh receipt polish.4-depth <level>:<what it was sized from>` — e.g.
   `low:+38-8,2f,docs` or `medium:+412-96,10f,code`. A bare level records the conclusion and throws away
   the evidence for it; the measurement is what makes a questionable call visible afterwards.

5. **Run the chosen review — one terminal pass, no loop-back.** For `skip`, there is no REVIEW to run —
   the decision already happened at step 4's skip dialog, which the gate cross-checks per commit (dir
   #116; a fix commit moving HEAD needs that dialog re-answered at step 4, not here). **This step's own
   RECEIPT is still required** (`tools/pre-pr-gate.sh receipt polish.5-review skip`, immediately, no
   dialog, no wait) — the gate's completeness check treats all eight steps as mandatory, `skip` included,
   and a missing step 5 receipt denies `gh pr create` on its own, independent of whether step 4's
   decision was sound (dir #236: "do nothing" describing the review was misread as "no receipt either,"
   and a forgotten receipt then forced a full re-ask of both step 4 dialogs on retry — recovering a
   same-commit skip is narrower now, see step 4's own note, but writing this receipt immediately is still
   the cheap way to never need that). `ultra` you
   cannot launch at all (cloud, billed, user-triggered) — always go straight to (b), no automated
   alternative attempted. For `low|medium|high|max`, ATTEMPT `Skill(code-review) <level>` directly
   first (dir #254, 2026-08-26): the harness policy that used to block this (`disable-model-invocation`)
   has LIFTED — observed live and independently reproduced across multiple sessions/machines
   (2026-08-25, 2026-08-26), not a single one-off canary. **Establish availability by attempting the
   call, never by inferring it from the skill listing** (the same attempt-don't-infer discipline step 2
   uses for `/simplify`) — a listed skill can still refuse invocation, and only the attempt returns the
   reason. On success, resolve any real findings it reports the same as any review pass (the delta-review
   budget/terminal-condition rules below govern this run too), then receipt
   `polish.5-review <level>` (bare — this IS the genuine in-session pass) and continue straight to step
   6: **no dialog required for this outcome** — the gate's dir #88 mandatory-reminder check only ever
   applies to `agent:*`-shaped outcomes (it exists to compensate for the fallback subagent's weaker
   quality, see (a) below), never to a bare `<level>` outcome, and a real built-in `/code-review` pass
   needs no such compensation. **If the attempt is refused, fall through to (a) below** — dir #70's
   subagent stays exactly as the fallback it already was, unaffected: same mechanism, same MANDATORY
   reminder dialog, same add-on literals, just reached on refusal now instead of unconditionally (this
   is the "subagent, then its existing dialog" choice among dir #254's open sub-question's candidates:
   the dialog exists to compensate for the subagent's weaker quality relative to a real
   `/code-review` pass, per dir #81/#141 — that gap is unaffected by WHY we ended up on the subagent
   path, so the dialog belongs wherever the subagent runs, refusal-triggered or not). Should the
   harness ever re-block model invocation, this attempt
   simply starts failing again and every run falls to (a) on its own — no revisit trigger or calendar
   re-check needed, since attempting first is now the standing behavior rather than an exception to
   restore. Either way, do not substitute `/review` (a GitHub-PR command, not a working-diff review) and
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

   - **(a) Fallback for `low|medium|high|max`, reached when the direct attempt above was refused for
     THIS run — an independent subagent reviews instead of you.** A DIFFERENT, independent reviewer has
     to run it. Spawn ONE fresh-context Agent-tool subagent,
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

     **Frame this as ONE additive question, never as a choice between mechanisms** (dir #81): the
     agent review already ran and its receipt above already stands — nothing here reopens or discards it,
     whatever the answer. Report what the agent review checked and found, state plainly that this review
     already ran and stands regardless of the answer, then ask only whether to ADDITIONALLY run one thing
     on top of it: the stronger built-in `/code-review <level>` (a multi-agent pipeline — parallel
     reviewers plus adversarial verification of their findings) or an in-session **cross-model second
     opinion** — one more Agent-tool subagent, pinned to a materially different model tier, reviewing the
     same diff at the same depth (dir #141; see the dedicated bullet below for the model pin and the
     subagent's own requirements). One subagent review is real and independent, but likely stays weaker
     than the built-in pipeline, so there is a genuine reason to want either add-on. Phrase the options
     additively, never as accept-one-reject-the-other: "proceed — the agent review is enough for this
     diff" / "run an in-session cross-model second opinion too" / "I'll run `/code-review <level>` too".
     Print the exact `/code-review <level>` command and open the dialog — the same real, pausing mechanism
     step 4 uses for its own dialog, not a rhetorical question the flow can talk itself past. **This is
     the anti-rebundle rule in practice** (below): a second add-on option extends this SAME dialog rather
     than opening a new one. Record the hand-off exactly as (b) does —
     `tools/pre-pr-gate.sh handoff <level> "$(git rev-parse HEAD)"` — only when the operator picks the
     built-in-review add-on, so a re-invocation doesn't have to rely on session memory (see (c)); the
     cross-model add-on needs no hand-off note, since it resolves immediately, in this same session, below.

     **On "proceed":** re-run `tools/pre-pr-gate.sh receipt polish.5-review agent:<level>` (the same
     outcome, written again) — idempotent, and its side effect is what clears the hand-off note; skipping
     this re-write leaves a stale hand-off note on disk that can force a spurious re-ask on a later
     re-invocation of this same commit.

     **On "run an in-session cross-model second opinion too" (dir #141):** spawn ONE fresh-context
     Agent-tool subagent, `subagent_type: "general-purpose"`, built the same way (a)'s own standing-review
     subagent was, with one deliberate difference — pin its `model` parameter to a tier materially
     different from the running session's own resolved model (visible in this session's own environment
     context; the Agent tool defaults to the session's tier when `model` is omitted, which is exactly what
     (a)'s own subagent did). Default mapping, simplest first: session on `opus` → pin `sonnet`; session
     on `sonnet` (or anything else) → pin `opus`. Skip `haiku`/`fable` for this role — the point is an
     independently-reasoning peer, not a cheaper or narrower one. Its prompt carries the SAME requirements
     as (a)'s own subagent prompt — the step-1 diff scope, the step-4 chosen depth, the correctness-focused
     mandate, the read-only/no-live-reproduction instruction, the ticket/done-criterion conformance mandate
     (or its explicit absence) — and the SAME literal `KEEL-AGENT-REVIEW: level=<level>` closing-line
     requirement, plain text, no markdown formatting (see (a) for the full list; nothing about the marker
     or the mandate changes here, only the model pin and the fact that a genuine independent review already
     stands before this second one even starts). **Verified against `tools/pre-pr-gate.sh`, not assumed
     (dir #141):** the `SubagentStop` trace leg matches on `agent_type == general-purpose` and the marker
     text alone — it has no way to see which subagent, prompt, or model tier produced a given trace line,
     so this second subagent's own marker line satisfies the exact same trace check (a)'s did; the trace
     mechanism itself needed no change. What DID need a small change is the receipt shape: an honest record
     must say a second, cross-model pass happened rather than silently reuse the bare `agent:<level>`
     outcome that already means "one agent review ran" — so `tools/pre-pr-gate.sh` gained one new outcome
     literal for this, `agent:<level>+second-opinion` (dir #81's own `+operator-run` pattern, mirrored).
     **Its provenance label marks the second-opinion half "(self-reported)", not "(trace-confirmed)"**
     (found by the operator's own `/code-review high` pass on this ticket): the trace only proves SOME
     general-purpose subagent wrote the marker for this commit+level, not that it happened TWICE — a
     receipt claiming this combined outcome after only the standing review's one real subagent run would
     pass the same trace check, the same ambiguity dir #81's own arm already resolves honestly for its
     operator-run half. Resolve any real findings this second subagent reports the same bar as (a)'s own findings — the SAME
     dir #127 budget/delta/trend rules govern the whole review cycle from here, not a fresh allowance per
     mechanism: a finding here is just this round's finding, folded into the same round count and the same
     trend line. On a later convergence round, re-engage this SAME second-opinion subagent with a
     follow-up message scoped to the fix delta — never a fresh spawn, per dir #127's "same reviewer" rule,
     extended to this subagent too. Once resolved (or if it reported nothing), receipt the combined
     outcome: `polish.5-review agent:<level>+second-opinion`.

     **The receipt carries AT MOST ONE add-on (dir #183).** The suffix is a single token validated
     against the gate's own allowlist, so an invented add-on still denies — and so does a comma-joined
     pair, which the gate reads as one unknown token. **When both add-ons genuinely applied to the
     commit you are shipping, `operator-run` wins the receipt slot**: it names a human pass, the rarer
     and more consequential event, and the one a reader is least able to infer from the rest of the
     record. **The one that loses the slot is not dropped from the RECORD — step 10's summary and the
     PR body must still name EVERY mechanism that reviewed this commit** (see step 10). That prose
     disclosure is where dir #81's honesty guarantee has always lived; dir #158 additionally put it in
     the receipt as a comma-separated set, and dir #183 removed that half — the set parser carried five
     live defects (dir #201/#214/#225/#226/#227) and deleting it retired all five structurally.

     **An add-on's unit is the SHIPPED COMMIT, not the round** — state it that way and nowhere else,
     since everything else in step 5 is per-commit (the trace is HEAD-keyed, the depth cross-check is
     per-commit, and dir #96 refuses to recover a review claim across a commit at all). So a mechanism
     is worth naming while the work it reviewed is still in HEAD, and each fix commit carries its
     predecessor's reviewed content forward. **`--recover` will not carry an add-on for you** —
     `polish.5-review` is deliberately never restored (dir #96), so an earlier round's add-on survives
     only in this session's own memory and has to be re-typed.

     **Nothing warns you when a re-typed receipt loses one (dir #183).** dir #161 added a stderr warning
     for exactly that, and dir #183 deleted it along with the set parser: it compared against the last
     RETIRED round, which is the wrong baseline on the in-run `--amend` path (dir #201), goes silent
     when an `--amend` orphans the retired round's lineage stamp (dir #214), and fires spuriously
     against an already-SHIPPED round while advising a review that never saw the commit (dir #226). It
     signalled unreliably in exactly the situations it existed for. **What replaces it is your own read
     of this run's earlier `polish.5-review` line, and the step-10 disclosure** — which is the record
     that matters anyway, since the receipt now holds one add-on by design.

     **Read this run's own earlier `polish.5-review` line out of the live sentinel
     (`/tmp/pre-pr-gate-$(tools/pre-pr-gate.sh receipt-key)`, last write wins) before writing a new
     one.** On the IN-RUN convergence path (resolve a finding, `--amend`, keep going without re-`init`-
     ing — the path named further down in this step) nothing is retired, so the live sentinel is the
     only place your own earlier add-on still exists. Read it; do not try to reason about what was
     carried forward from session memory.

     **On "I'll run `/code-review <level>` too": that command is the OPERATOR's to run, not yours — this
     run's own direct attempt above was refused, which is why we're on this fallback branch at all.**
     Wait for them to run it (or report their findings — unchanged,
     still waits for the operator, dir #81 fork 4), then resolve what it reported and write the COMBINED
     outcome: `polish.5-review agent:<level>+operator-run` — a new, honest record naming BOTH reviews that
     ran, not an overwrite that erases the agent review the receipt above already established (whichever
     receipt is written LAST for this step wins — see (c)). **If a cross-model second opinion also
     reviewed work still in this commit, `operator-run` still takes the receipt slot (dir #183) — and
     step 10's summary and the PR body must name the second opinion too.** The receipt holds one
     add-on; the prose holds every mechanism.

     **Anti-rebundle rule:** if a future edit ever makes the agent review itself optional or something to
     ask about, that must be its OWN separate question — never re-bundled with this one into a single
     dialog. This ticket (dir #81) exists because those two concerns were bundled once already; dir #141's
     cross-model add-on above follows the same discipline by extending this dialog's options rather than
     opening a second one.

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
       **If a cross-model second opinion also reviewed work still in this commit, `operator-run` keeps
       the receipt slot and the second opinion is named in step 10's summary and the PR body**
       (dir #183 — the receipt holds one add-on, the prose holds every mechanism). This branch is the
       ORDINARY hand-off path, so it is the one most likely to arrive last; what it must not do is let
       an earlier round's mechanism vanish from the prose record.
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
   steps 2 and 7 for you (step 7 unless a GAP stopped that run before its receipt — dir #119), and
   step 4 unless the prior round's depth was `skip` (never carried — dir
   #116, see step 1; step 3 recovers too now but only provisionally — dir #123, see step 1) — arriving here, re-review only
   the DELTA the fix introduced, not the full step-1
   diff again, and stop as soon as a pass needs no further changes (dir #127 below gives this "stop" a
   budget and a terminal condition; read the rest of this paragraph together with that block, not as two
   separate rules); park a non-blocking note (a style nit,
   a "consider later") in the step 10 summary instead of chasing it into another round. **"Stop" here
   means stop re-reviewing — it does NOT mean step 5 is done:** the MANDATORY dialog in (a) above still
   applies to this round's fresh receipt before moving to step 6, same as the first pass.

   **The IN-RUN path is the cheaper alternative when steps 6/7/8 are still ahead (dir #177): resolve
   the finding, fold the fix into the current commit with `--amend`, and simply continue this `/polish`
   run in place — no re-invocation, so step 1's convergence branch above never fires for this fix at
   all.** The sentinel is never retired on this path, so steps 1, 2, and 4's receipts — already written
   before you reached step 5 — stay live and valid, untouched by the amend (none of them is sha-bound),
   and step 5's own receipt for the finding you just resolved is written normally right after (a first
   write for this round, not a recovery — nothing special applies to it). What needs re-establishing
   before step 8, precisely:
   - **`polish.3-tests`**, the one PRE-EXISTING receipt that is already sha-bound at this point: after
     the amend it is still bound to the pre-amend commit — nothing else in this flow says so, and step
     8 denying it later against the new HEAD is the only, indirect way that surfaces. A fresh
     `polish.6-retest` receipt against the new HEAD satisfies it on its own — one test run after the
     last change, not two separate re-receipts (step 1 already describes this same OR).
   - **`polish.5-review`, if a LATER commit in the same run moves HEAD again after its receipt is
     already written** — but not via step 6 or step 7, which stop the run and require re-invoking
     `/polish` on any finding of their own; the reachable trigger is an add-on review arriving after
     the standing receipt (an operator-run `/code-review`, dir #81, or a cross-model second opinion,
     dir #141) reporting a finding you resolve in-run. When that happens, its trace-confirmed outcomes
     (`agent:<level>`, its add-on forms, and a bare `<level>` from a genuine in-session `/code-review`)
     go stale the same way `polish.3-tests` does — the trace is keyed to the sha it was written at —
     and need a fresh agent review or add-on, or a hand-off outcome that carries no trace-check at all.
     **On this exact trigger, read the live sentinel's own earlier `polish.5-review` line before
     re-writing the receipt** — nothing warns you if the re-write loses a mechanism (dir #183 removed
     dir #161's warning; see its own paragraph above), and the step-10 disclosure is what has to carry
     every mechanism forward.
   - **The MANDATORY review dialog (dir #88), on that same later-amend trigger** — per-commit too, but
     only for `agent:*` outcomes (and `skip`, step 4's own dialog): re-answer it for the new HEAD, an
     earlier round's answer does not carry over. The gate never checks it for a bare `<level>` outcome,
     so there is nothing to re-answer there. (Whether this SHA-binding should instead survive a clean
     delta round WAS an open design question, dir #180 — since SUPERSEDED by dir #254, which moved the
     dialog off the primary path: it now fires only on the refusal fallback, making the re-fire
     question a rare-path one. The SHA-binding holds exactly as described here.)

   If you run `tools/pre-pr-gate.sh receipt --recover` anyway to sanity-check state, its `nothing to
   recover` answer is correct and BY DESIGN here — not a signal that this isn't a convergence round;
   see the mirror-case note in step 1.

   **Delta-review protocol, round budget, and terminal state (dir #127) — refines the "converge, don't
   restart" paragraph above, same rule, three added specifics:**
   - **Same reviewer, not a fresh spawn.** "Re-review only the DELTA" (above) means: for the agent path
     (a), a follow-up message to the SAME Agent-tool subagent that ran the original pass, scoped to only
     the fix commit's diff — never a new spawn; for an operator-run `/code-review` hand-off, the operator
     re-running it on the delta the same way; for a cross-model second opinion (dir #141), a follow-up
     message to that SAME pinned-model subagent, same discipline. A fresh full pass is justified only when
     the fix touched surface the original review never examined (dir #126 signal 1) — name that reason if
     it happens.
   - **Budget: the full review runs once; after it, at most TWO delta rounds.** If a SECOND consecutive
     delta round still returns substantive findings (not a style nit — those still just park in step 10),
     stop fix-forward and do not attempt a third round. File the residual as a numbered backlog ticket,
     name it honestly in the PR body's own words (not just a code comment), and open the PR as-is — an
     executed decision, recorded the same deliberate way a `skipped:<reason>` receipt outcome is, never a
     silent abandon. **The step 5 receipt itself does not change shape for this exit**: write whatever
     outcome literal actually describes the review mechanism that ran this round (e.g. `agent:<level>`,
     same as any other round, per the Receipt line below) — the residual-ticket decision lives in the PR
     body and the backlog, not as a new gate-recognized outcome, so it carries no separate receipt syntax
     and needs no `pre-pr-gate.sh` change. If the two rounds' findings instead say "missing contract" (the
     same shape recurring, not shrinking), escalate to redesign instead of a third fix-forward attempt.
   - **Terminal condition, precisely: zero findings in a DELTA round** (not "a pass needs no further
     changes" read loosely) **— and a fresh FULL re-review returning zero is explicitly NOT this signal.**
     A full review is sampling and will always find something to say if repeated; treating a clean full
     re-review as done is what produced the 7- and 13-round loops this ticket closes. Only a clean delta
     round ends the cycle.
   - **Per-round trend line:** at the end of every convergence round (after its delta re-review
     completes, before deciding whether another round is needed), report one line to the operator:
     `round N: <count> findings, max severity <sev>, surface: same|new — <what>, class: named|exhausted,
     forecast: <1 more delta round | stop-rule triggers next round | done>` — visible progress instead of
     a silent count climbing toward a dreaded double-digit round.

   Receipt: `tools/pre-pr-gate.sh receipt polish.5-review <level>`. The shapes:
   - `agent:medium` — the ordinary automated outcome (an independent agent review).
   - `low`/`high` — a genuine operator-typed or revisit-triggered in-session `/code-review` pass.
   - `medium-operator-run`, `ultra-operator-run`, `medium-waived`, `skip` — the hand-off outcomes.
   - `agent:<level>+<addon>` — a standing agent review PLUS exactly one add-on (dir #183). The add-ons
     are `operator-run` (the operator additionally ran `/code-review`, dir #81) and `second-opinion` (an
     in-session cross-model subagent additionally reviewed, dir #141). **One per receipt: a
     comma-joined pair denies.** When both applied, `operator-run` takes the slot — and **step 10's
     summary and the PR body must name every mechanism that reviewed this commit, not just the one in
     the receipt.**

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
   as step 8, not a bare `done`: step 6 is one of the steps a convergence round must write itself —
   three ordinarily (5, 6, 8 — step 1's branch hands back only 2, 4 (unless the prior round's depth
   was `skip` decided against an earlier commit than current HEAD — dir #116, narrowed by dir #236, not
   carried) and 7 (unless a step-7 GAP stopped the prior run before its
   receipt — dir #119, never written, so never recovered)), four when that GAP forces a re-run (7
   joins the set, dir #138). Step 3 recovers too now, but only provisionally — dir #123, see step 1.
   Step 6's whole job is to catch a fix-commit
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

   **If fixing what it flagged takes a commit, you are in a convergence round** (dir #119) — a GAP that
   stopped the run and a WARN you decide to act on both move HEAD after steps 3/5/6/8 were receipted
   against the old commit. Fold the fix into the same commit where practical, then re-invoke `/polish`
   and take step 1's convergence branch, which carries the mechanics — including what a step-7 trigger
   changes.

8. **Unlock the gate.** Now that the diff is final (reviewed and re-tested), finalize the receipt with the
   current HEAD SHA: `tools/pre-pr-gate.sh receipt polish.8-unlock "$(git rev-parse HEAD)"`. That releases
   the `gh pr create` block. The SHA is recorded *after* the review so it matches exactly what the PR will
   contain. **Push the branch before you unlock** — the gate also checks that current HEAD is reachable on
   the branch's push remote (see the deny note below), and in a convergence round the fix commit is
   exactly the one that tends to still be local-only.

   **One deny is NOT a receipt problem, and re-running `/polish` alone will never clear it** (dir
   #133/#152): `current HEAD (<sha>) is not reachable on <remote>/<branch> — push the branch (git push)
   before opening the PR`. Every other check the gate runs is against the LOCAL repo, so a commit made
   after the branch's last push satisfies all of them and would open a PR that silently omits it. The
   remote it names is the branch's own configured `@{upstream}` (falling back to `origin/<branch>` when
   the branch has no upstream), not a hardcoded `origin`. Fix it by pushing, then re-run `/polish` and
   take step 1's convergence branch — this deny retires the sentinel like any other, so the receipts have
   to be rewritten either way.

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
   agent at `<level>` (direct `Skill(code-review)` invocation was refused this run — dir #254 fallback)" —
   never presented as if `/code-review` itself ran. **The PR body must name EVERY mechanism that reviewed
   this commit — read them off what ACTUALLY RAN, not off the receipt** (dir #183): the standing
   independent agent review, plus the operator-run `/code-review` if the operator ran one (dir #81),
   plus the in-session cross-model second opinion *naming its pinned model tier* if one ran (dir #141).
   **The receipt is no longer that list.** It carries at most one add-on, so a commit reviewed BOTH ways
   receipts `agent:<level>+operator-run` and the body still has to name three mechanisms. Reading the
   body off the receipt would silently drop the second opinion — which is precisely the honesty the
   receipt half was carrying until dir #183 removed it, so the burden is here now. Return the PR URL.
   Invoking `/polish` IS the standing authorization to push the
   branch and run `gh pr create --head <branch>` at this step; do not re-ask. The merge stays the
   operator's.

10. **Summary.** Briefly: what `/simplify` tidied, the test status (including any post-review re-run and
    self-check result), which review depth ran (or that it was skipped), and the PR URL. **Name the exact
    review mechanism, never just the depth** — a genuine in-session `/code-review <level>`; an
    independent agent review (`review: <level>, independent agent review — direct Skill(code-review)
    invocation was refused this run`, matching the PR body's own label); **plus, when an add-on review
    also ran, every mechanism that ran — read off what ACTUALLY RAN, not off the receipt (dir #183)**:
    append `+ operator-run /code-review` for an operator-run pass (dir #81) and `+ in-session
    cross-model second opinion (<model>)`, naming the pinned tier, for a cross-model second opinion
    (dir #141). So a commit reviewed BOTH ways reads `review: <level>, independent agent review +
    operator-run /code-review + in-session cross-model second opinion (<model>)` — three mechanisms,
    matching the PR body — even though its receipt names only `+operator-run`, which is the one add-on
    slot the receipt has;
    or, if step 5 took the (b) hand-off, that no real review ran in-session and whether the human ran it
    (`-operator-run`) or waived it (`-waived`, leaving only (a)'s last-resort inline pass). A bare depth is
    indistinguishable from a genuine in-session review, so reporting one here would re-hide exactly what
    step 5 exists to surface.
