# Drydock — auditing the prose your agent actually executes

*This is a worked instantiation of [`docs/delegation.md`](delegation.md)'s capability-split pattern —
read that doc for the generalized roles, contracts, and rails behind everything below.*

Your tests tell you the code still works. Nothing tells you the *prose* still does — the rails, the
docs, the command steps, the comments a model reads and acts on every single session. That prose
drifts in one direction only: it was true when written, then the surface it described moved, and
nothing failed. Drydock is the pass that goes looking for that drift on purpose — the whole tree, one
frozen commit, one finding per defect, and every run ending by making part of the next one
unnecessary.

It sits next to [`docs/rollout-audit.md`](rollout-audit.md) (checks a *model/harness upgrade* didn't
break your pipeline), [`docs/release-audit.md`](release-audit.md) (checks the *project* is ready to
tag), and [`docs/publishing-checklist.md`](publishing-checklist.md) (checks a repo *looks finished*).
Those three ask whether the project is ready; this one asks the question underneath them — **is what
the project says still true?** — on a cadence of "every few releases, or after a stretch where a lot
of prose moved," not "before every tag."

**What a run needs:** a git repo; an agent harness that can run several sub-sessions in parallel and
one gated session at a time for the fixes; a gitignored working directory for the run's own files;
and roughly an operator-day of wall-clock for a first full pass over a mid-size prose surface (see
[What a first run costs](#what-a-first-run-costs)). Everything below was field-tested end to end
before it was written down — the felt incidents are from that run, and each rail exists because
something went wrong without it.

## The two tiers, and why the ratchet is the point

- **Tier 1 — deterministic checks.** Your test suite, plus tests that pin *prose*: a figure quoted in
  a doc, a step count, a list that three files restate. Cheap, run on every commit, and once a class
  is here it never comes back.
- **Tier 2 — the model pipeline in this document.** Expensive, judgement-bearing, and the only thing
  that finds a class nobody has mechanized yet.

A green tier-2 run means **"this run found nothing"**, never "no defects exist" — the same rule
[`docs/release-audit.md`](release-audit.md)'s phase 0 states for reviews generally: an audit measures
the frontier of the unknown, it does not certify a state.

**The ratchet is what keeps this affordable: every run ENDS by demoting finding classes into tier-1
checks.** A demotion is only complete when a check exists that reds today on the run's own live case
and would have caught the class — a backlog ticket is the *commitment* to that check, not the
demotion itself. Without it, run 2 costs exactly what run 1 cost and finds the same shapes again.

Keel's run 1 demoted four classes this way (dir #166–#169), each ticket naming its live case as the
red-to-green test the check has to reproduce (see [Incremental runs](#incremental-runs) for what run 2
does with them). The gap between *filed* and *landed* is the one the next run always measures. **A run
that demotes nothing has not finished** — and a run whose demotions never land has only deferred the
cost.

Why the ratchet is the *response to a run's result*, and not just good hygiene:
[`docs/verification-economics.md`](verification-economics.md)'s Clause B — a run that yields only
*instances* of classes already on the record indicts this demotion pipeline, never the review count.
That doc also owns the bar a finding clears before it earns a ticket at all, applied at phase 6 and
again at phase 7's ratchet; it is not restated here.

**It does not, however, decide when a drydock run ends — this document does, at phase 6.** Keep the
two apart: drydock terminates structurally, on *one fix loop and only one*, because every fix is new
prose that could itself be audited. The doctrine's stopping rule answers a different question — whether
another audit *wave* over the same state is worth running — and its two-diverse-legs clause is written
for a run that fields several diverse legs, where drydock's own diversity requirement is one leg, on
scope C only. Neither rule overrides the other; they terminate different things.

## Roles — four of them, in separate contexts

| Role | Runs as | Model + effort | May touch |
|---|---|---|---|
| **Orchestrator** | your own session | top tier, high | everything: phases 0, 4, 6, 7, all arbitration, **all** bookkeeping |
| **Auditor** | spawned subagent, many in parallel | mid tier, high | read-only, plus its own audit files |
| **Verifier** | spawned subagent, a few in parallel | mid tier, **xhigh** | the `verdict:` lines of the audit files it was given, plus its own `verifier:` footer line |
| **Fixer** | a real, operator-launched session — **never** a subagent | mid tier, medium | one PR's worth of the tree |

Two of those assignments are load-bearing. **Verifiers get more effort than auditors**, not less:
finding a suspicious sentence is cheaper than proving it wrong, and a wrong `rejected` is the one
verdict nothing downstream re-checks. And **fixers are never subagents** — they have to pass through
the gates that exist to keep a human in the loop (a pre-PR gate's receipts, a review dialog, the PR,
the merge). A subagent that skips those isn't a faster fixer, it's an ungated one.

One qualifier scoped to scope C alone: an auditor batch containing an `INVARIANT`-marked file escalates
above this table's mid-tier-high row — see [Scope C — code](#scope-c--code)'s Model lines.

The orchestrator does **all** bookkeeping — marking findings fixed, updating the queue, writing the
run record. Workers stay stateless behind the file contract below, so a worker never has to know the
ledger, and a worker dying loses nothing but its own unit of work.

## The file contract

The run's working directory (gitignored — these are artifacts, not products) holds **one audit file
per audited file**, named `<slug>-audit.md` where the slug is the repo-relative path with `/`
replaced by `-`, so `docs/release-audit.md` becomes `docs-release-audit.md-audit.md`. The auditor
fills everything except the verdict:

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

Phase 2 appends one footer line per file it verifies —
`verifier: <model + effort> | <date> | sandbox: <path, or "none — prose-only">` — so a finished audit
file names both contexts that touched it. The shape above is reproduced verbatim in
[`docs/drydock/auditor.md`](drydock/auditor.md), which is the copy an agent is actually handed; if you
change one, change both, and the phrasing is deliberately identical so a diff between them is visible.
[`docs/drydock/code-auditor.md`](drydock/code-auditor.md) extends this same shape for scope C — see
[Scope C — code](#scope-c--code).

Two parts of the contract carry more weight than they look:

- **The empty `verdict:` line.** The agent that found a defect does not get to rule on it. Verdicts
  are appended by a *different* context in phase 2, which is what makes "I re-measured it and it's
  fine" a real signal rather than an author defending their own finding.
- **The closing `## claims` section**, which does double duty: it is the input to the cross-file pass
  (phase 3 reads *only* these, never the files again — that is what makes a whole-tree comparison
  affordable), and it is the **completeness marker**. An audit file without a `## claims` section is
  a dead agent's partial write, not a clean file with no claims. Respawn that unit; never fold a
  partial write into the run.

**The verdict is three-valued**, and the third value is the one that matters:

| Verdict | Means |
|---|---|
| `accepted` | reproduced empirically → goes to the fix queue |
| `rejected: <reason>` | reproduced and found wrong → the reason names what the verifier **measured**, never what it doubted |
| `known — <ticket id>` | an open or deferred ticket already owns this defect → record a pointer, **do not fix** |

Without the third value an audit quietly reverses decisions somebody already made on purpose. Run 1
met exactly one: a wording an operator had deliberately deferred, which drydock would otherwise have
"fixed" straight back into the tree.

## Phase 0 — freeze the baseline, and the scope

**Everything downstream is measured against one commit.** Fetch, pick the baseline (normally your
default branch's remote head), and measure it in a **clean tree at that exact SHA** — a dedicated
worktree, never your main checkout:

```bash
git fetch --prune && git worktree add ../drydock-baseline origin/main
```

Then generate the inventory from inside that frozen tree, writing the output back to the run's
working directory:

```bash
cd ../drydock-baseline
<keel-checkout>/tools/drydock/inventory.sh > <audit-dir>/inventory-$(git rev-parse --short HEAD).md
```

**The two paths in that block are deliberately different.** The script lives in your Keel checkout —
`install.sh` never copies `tools/` into your project — while the tree it measures is whatever
repository your **cwd** is in. So you invoke it by absolute path and stand inside the frozen worktree;
running it from the Keel checkout instead would measure Keel. (Auditing Keel itself is the one case
where `./tools/drydock/inventory.sh` happens to be both.)

**Felt incident — this is why the script has a guard and no `--force`.** Run 1's very first inventory
was launched with the cwd left at the main checkout, which happened to be sitting on a *peer
session's branch*, two commits off the baseline. It measured that tree and printed the numbers
without a murmur; the whole audit was scoped against a commit nobody had chosen, and it took a
re-measurement to notice. [`tools/drydock/inventory.sh`](../tools/drydock/inventory.sh) now refuses
outright (exit 3) rather than measure a tree it cannot vouch for. One rule, several guarded
conditions (see the script's own `refuse "` call sites for the exhaustive list) — **an inventory
that quietly disagrees with the tree is worse than no inventory**:

- **HEAD is not the baseline** — the run-1 case; the message names both SHAs and the `git worktree
  add` that fixes it.
- **The working tree is dirty** — the numbers would describe no commit at all. Gitignored files are
  not dirt, so the run's own output directory can live in the tree while it works.
- **An in-scope file cannot be read** — a sparse checkout, a dangling symlink. It refuses instead of
  omitting the file, because a partial inventory is indistinguishable from a small tree.
- **The scope could not be enumerated at all** — git itself failed. Nothing is measured; the
  alternative is reporting an empty repo at exit 0.

The escape hatch is `--baseline <rev>` — not a bypass, the opposite: you name the commit you meant,
and it goes in the output header where the next run can read it. There is no `--force`.

The inventory is **scope as code**. It measures three scopes — every tracked markdown file whole
(scope A), the comment prose of every tracked shell file (scope B), and the whole code of every
tracked shell file (scope C) — and derives the per-auditor batches from that measurement, so the run's
scope is a reproducible artifact rather than a hand-drawn list that silently disagrees with the tree.
A run covers all three by default; see [Scope C — code](#scope-c--code) below for the code module's
own boundary, cadence knob, and cost. Adjust for your repo's shape with the environment variables
documented in the script's own header (`DRYDOCK_SCOPE_A`, `DRYDOCK_SCOPE_B`, `DRYDOCK_SCOPE_C`,
`DRYDOCK_HISTORICAL`, `DRYDOCK_INVARIANT_PATHS`, and the four batch-size knobs).

**Precondition: the baseline's test suite and linters are green.** An audit on a red tree cannot tell
prose drift from a live bug, and every finding it produces inherits that ambiguity.

**Then run the mechanical sweeps once — their hits are LEADS handed to the auditors, never
conclusions.** Two signals earn their keep, and both are one-liners from the frozen tree:

```bash
# 1. anomalous line length — an unfinished edit shows up as one long line in a wrapped block
git ls-files -z '*.md' | xargs -0 awk 'length($0) > 110 { printf "%s:%d (%d ch)\n", FILENAME, FNR, length($0) }'
# 2. dead relative links — a markdown target that no longer resolves on disk
git ls-files -z '*.md' | while IFS= read -r -d '' f; do grep -oE '\]\([^)#]+' "$f" | cut -c3- | while IFS= read -r t; do
  case "$t" in http*|mailto:*|"") continue ;; esac
  [ -e "$(dirname "$f")/$t" ] || printf '%s -> %s\n' "$f" "$t"
done; done
```

Both sweeps enumerate with `-z` for the same reason the shipped tooling does: git C-quotes any path
it cannot print literally, and a quoted string is not a path `awk` or `grep` can open — the file's
own contents would then go unswept, silently, which is the one outcome a sweep must not have. And
sweep 2's character class excludes only `)` and `#`, deliberately not `:` — stopping at the colon
would truncate `mailto:you@example.com` to `mailto`, which then fails the scheme test below it and
gets reported as a dead relative link, once per mail link in your tree.

Signal 1 is worth more than it sounds: run 1's single most diagnostic mechanical hit was a 131-char
line inside a 103–106-char block — an edit that had been abandoned halfway. Signal 2 is the
markdown-link half of a class this repo already polices in prose:
[`tools/self/doctor.sh`](../tools/self/doctor.sh)'s dead-internal-reference check resolves
`tools/`, `commands/`, and `templates/` mentions anywhere in the adopter-facing docs, in link syntax
or not. The two are complementary, and keel's own dir #169 has since demoted this class to tier 1 —
as [`tools/self/prose-drift.sh`](../tools/self/prose-drift.sh), a second tool beside that check rather
than an extension of it: what shipped for signal 1 is block-relative, not the flat `>110` threshold
above (which the tool's own header records as mostly ordinary long lines, not defects), so the two
share no machinery. `tools/self/doctor.sh` invokes it as an orchestrated check, so a keel run now gets
both signals from the suite; the sweeps above stay the honest state for any class still undemoted, and
for the flat-threshold leads the shipped check deliberately drops.

## Scope C — code

Where scope B reads a shell file's **comment prose only**, scope C reads the same file **whole**,
auditing for the classes [`docs/drydock/code-auditor.md`](drydock/code-auditor.md)'s own Classes line
names — dir #85's module-1 rubric: dead code, duplication, missing coverage, correctness. A run
covers scope A, B, and C together by default; this section states the code module's boundary,
cadence, and cost, since it is the one scope that differs materially from the other two.

**Boundary vs. `/polish`'s per-PR review.** `/polish` step 5 already reviews every diff for
correctness at merge time. Scope C's value is the classes a diff-scoped review structurally cannot
see: dead code no PR happens to touch, duplication across files no PR ever diffs together, and
missing coverage nobody's PR was asked to add. It is a whole-tree, cross-file pass, not a slower
re-run of ordinary PR review.

**Boundary vs. scope B.** Scope B's and scope C's default file sets are identical by design — both
resolve through the same shell-file selection
([`tools/self/shellcheck-targets.sh`](../tools/self/shellcheck-targets.sh)): on keel's own tree, the
comment prose scope B reads is a real subset of the lines scope C also measures. A comment-prose
defect (a stale claim, a broken cross-reference) still belongs to scope B; the code auditor does not
re-file it — [`docs/drydock/code-auditor.md`](drydock/code-auditor.md)'s own method steers it toward
code defects instead.

**Method and rails.** [`docs/drydock/code-auditor.md`](drydock/code-auditor.md) is the copy-paste
template — its Method and Rails sections are the authoritative text, not restated here. One addition
that lives at the procedure level, not the template: **the verification bar is unconditional for
code, not comment-triggered** — [`docs/drydock/verifier.md`](drydock/verifier.md) states the bullet,
a code finding's verdict rests on a sandboxed execution, full stop.

**Claims, extended for code.** Phase 3 reads `## claims` sections only, never the files again — for a
code audit file, the extended field shapes (`defines: <name>`, `calls: <name>` with internal calls
included, named consumers, test-pin claims) are
[`docs/drydock/code-auditor.md`](drydock/code-auditor.md)'s own contract, not restated here. Phase 3
derives three code-specific classes from those fields: a name in some file's `defines:` that appears
in no file's `calls:` (a dead helper); the same name in a lib's `defines:` and a consumer's own
`defines:` (the shadowing hazard); and a contract statement with no matching test-pin claim (unpinned
behavior). **Cross-file duplication is NOT a phase-3 class** — code bodies never enter the claims
registry, so phase 3 structurally cannot see it;
[`docs/drydock/code-auditor.md`](drydock/code-auditor.md)'s Method section states where it's filed
instead.

**Cadence — `DRYDOCK_SCOPE_C`, same convention as scope B.** Unset or empty both mean the full
default selection, not a disable (scope C gates on `[ -n ... ]`, same as scope B); to run prose only,
name a pathspec that matches nothing rather than passing an empty string — canonically
`DRYDOCK_SCOPE_C=':!*'`, verified live to yield an empty scope at exit 0, not a refusal. `--prev`
incremental scoping applies to scope C exactly as it does to A and B.

**Cost.** Prose and code together, the new default, costs materially more than the prose-only figure
[What a first run costs](#what-a-first-run-costs) records (≈6.1M subagent tokens): re-run that
section's session-limit arithmetic fresh rather than reusing its number, and fall back to
`DRYDOCK_SCOPE_C=':!*'` (a prose-only run) when the wave doesn't fit. The batch **count** is
mechanical and already known — 14 directory-affinity batches on keel's own tree at the default
`DRYDOCK_CODE_BATCH_LINES` (live-measured, not the "roughly 4–6" an early estimate guessed before
directory affinity's per-directory forcing was accounted for). Per-batch **token** cost stays
unmeasured until the module's own first real run — no invented numbers here — and that run records
them in its own dated summary.

**Diversity.** Code batches inherit [`docs/delta-audit.md`](delta-audit.md) §5's required-diversity-leg
rule as-is: one leg differing by vendor or by method (blind-then-reconcile), skippable only by an
explicit, recorded operator decision — see that section for the operative rule, and
[`docs/verification-economics.md`](verification-economics.md) for the reasoning and the evidence
behind it; neither is restated here. Prose batches are unaffected; the requirement is scope C's own.

**Ratchet.** The ratchet's mechanism is unchanged for code: keel's own tier 1 for code already
executes (the test suite, shellcheck, [`tools/self/doctor.sh`](../tools/self/doctor.sh), all run in
CI), so a demoted code class lands the same way a demoted prose class does — a test, a
shellcheck-target rule, or a doctor check that reds on the class's own live case. The same noise guard
prose demotions need applies here too: a class that flags every instance of a common, benign pattern
is noise, not a check.

**Model lines.** Code auditors run at the same tier and effort as prose auditors: mid tier, high. Two
escalations, both routed off the inventory's own per-file markers, not a second query: a batch
containing a `DRYDOCK_INVARIANT_PATHS`-marked file goes to top tier or xhigh effort, and the verifier
stays xhigh regardless of scope, per the roles table above. The diversity leg (above) runs at a
different vendor's own default settings, or a blind same-method pass at mid tier, high.

## Phase 1 — per-file audits, in parallel

One auditor session per batch from the inventory, all read-only, all at once. The batching rules the
script already applies: a long file gets a session to itself; the rest pack by directory affinity up
to a per-session line budget; comment prose packs to a *larger* budget than doc prose, because
comments are terser units. **Scope C batches run under a separate template**,
[`docs/drydock/code-auditor.md`](drydock/code-auditor.md) — see [Scope C — code](#scope-c--code)
above; everything below this point is scope A/B's own auditor.

**The historical-prose rule.** A changelog (or any dated, append-only log) is audited differently and
always in its own batch: a dated section is checked for **internal consistency at its own date
only** — never against today's code, where every historical entry would read as a stale claim. Only
the unreleased section and the newest tagged one get a full stale-claim audit.

The auditor prompt's rails — most of which run 1 needed directly, one folded in from a later run of
the same shape (the full, copy-paste list is in [`docs/drydock/auditor.md`](drydock/auditor.md) — these
are the ones with a story):

1. **Read-only, and write only your own audit files.** No commits, no branch changes, no edits to any
   repo file.
2. **Do not read the ticket backlog.** Deduping a finding against an open ticket is the *verifier's*
   job; an auditor that has read the backlog reads the prose looking for what it already expects.
3. **Do not spawn subagents of your own.** One run-1 auditor did, then stalled waiting on the child
   it had spawned. (Recovery, if it happens anyway: message the stalled agent to finish the work
   itself — cheaper than a respawn, and it keeps the context it already paid for.)
4. **Any executable check runs in a scratch copy** — not the live tree, not the real home directory.
   This rail belongs in the *auditor* prompt, not just the verifier's: two run-1 auditors ran live
   repo scripts before it was there. No harm that time.
5. **A claim about executable behavior is not evidence.** Not a run-1 incident —
   [`docs/delegation.md`](delegation.md)'s "Execute the claim, don't re-read it" section states the
   rule and its felt incident (dir #225); applies to the verifier's re-derivation in phase 2 too — see
   below.

**Zero findings is a valid result** and should be reported plainly. Run 1's cleanest files were not
the short ones — they were the recently-reworked ones. Recency of maintenance, not file type or size,
is what predicts cleanliness.

## Phase 2 — verification, in parallel over disjoint sets

Each verifier gets a disjoint set of audit files and re-derives **every** finding empirically: re-read
the quoted prose in place at the baseline, re-measure every number, re-check every stale-claim against
the code. Then it deduplicates against the ticket ledger (grep it; do not read the whole thing) and
fills the empty verdict lines. It never edits the auditor's text. **For a scope-C audit file, the same
verifier handles it — no separate template — but the bar is unconditional**: see [Scope C —
code](#scope-c--code)'s "Method and rails" paragraph.

**The sandbox rail, with its incident stated verbatim in the prompt.** Live or executable checks run
only in a scratch clone under the agent's own temp directory — never the real checkout, never the real
`$HOME`. A review subagent once "empirically reproducing" a bug overwrote real machine-global git
hooks and broke `git push` on the machine until they were restored. Agents comply with a rail that
names its incident far more reliably than one that just says "be careful."

**Its one exception, which [`docs/rollout-audit.md`](rollout-audit.md) already states and this rail
inherits:** a check that only *reads* machine configuration has to face the real environment, because
under a redirected `$HOME` its verdict doesn't weaken, it inverts — a fully-guarded machine reports
"not wired." Sandbox anything that writes; never sandbox a read whose whole subject is the real
machine's state.

Three calibration notes: `rejected` requires a measurement, not a doubt — "I couldn't see how this would
be wrong" is not a rejection. A `readability`/`optimization`-class finding carries a *higher* bar
than a factual one, because it is the class most likely to be an agent restyling prose it merely
finds unfamiliar. And "reproduce" itself means execute, not re-read — phase 1's rail 5 states why.

## Phase 3 — the cross-file pass

One agent, over the extracted `## claims` sections only — never the files again. Four classes:

- **the same fact with two different values** in two files;
- **broken promise pairs** — file A says "as described in B", B describes something else;
- **dangling references** — a named file, section, or ticket that doesn't resolve;
- **multi-surface procedure skew** — three or more files each restating one procedure, drifted apart.

**Scope C adds three more, over its own extended `## claims` fields** (`defines:`, `calls:`, named
consumers, test-pin claims) — see [Scope C — code](#scope-c--code) above for the field shapes and why
cross-file duplication is deliberately NOT one of them.

**Felt incident:** run 1's per-file auditors caught a rail restated in three places being wrong in
*one* of them, and the auditor of the second file missed the same mismatch from its own side. The
cross-file pass found the third surface. Manual coherence across restated prose provably does not
hold — which is exactly why this class is also the first thing to demote to tier 1.

## Phase 4 — GATE-2: the orchestrator's own hands

Delegation stops here. Before assembling anything, spot-check, personally:

- **every `rejected` verdict** — the only verdict nothing downstream re-examines;
- **a sample of `accepted`** — enough to calibrate whether the wave was rigorous;
- **every territory a known ticket owns that falls inside this run's scope.**

**Felt incident — the third bullet is not optional.** Run 1's one *missed* defect surfaced only here:
the per-file auditor read the passage as matching the code and filed nothing, so the verifier never
got a finding to dedup against the deferred ticket that owned it, and the orchestrator's own read at
this gate is what caught it. Phase 4 is the only place in the pipeline where a defect that was never
*found* can still be caught.

Then assemble the fix queue.

## Phase 5 — fixes

**Group thematically, not per file — roughly 5–8 pull requests.** Run 1 had 24 files carrying
findings; 24 serialized PRs would have been merge-hostile, and the queue collapsed to 7 without any
of them growing large. (Eight PRs actually merged: one queue entry's own review found a third
instance of its class mid-fix and spun a follow-up. A queue entry is a plan, not a quota.)

- Each PR is one operator-launched session, given its audit files as input. If your pre-PR gate keeps
  a shared per-repo sentinel, **strictly one PR in flight at a time**.
- Fixers fix **accepted findings only**: no adjacent cleanups, no re-litigating a `rejected` or
  `known`. A fixer that starts improving what it passes turns a bounded queue into an unbounded one.
- **Test-pinned prose moves its pins in the same commit.** If a figure in a doc is asserted by a
  test, the fix is both edits or neither.
- Escalate to a deep, operator-run review on **two factors, either sufficient**: the surface is
  always-loaded or pipeline prose, **or** the diff is large. Once a fix PR is in review, it is an
  ordinary PR: the round budget and delta-review protocol in
  [`docs/release-audit.md`](release-audit.md) phase 5 govern it, and drydock adds nothing of its own
  there.
- The orchestrator marks `fixed: PR #n` against each finding as merges land. Fixer sessions do no
  bookkeeping and get no wrap — they hand back a PR URL and a per-finding fixed/skipped list.

## Phase 6 — the closing re-check

The orchestrator owns this phase and delegates exactly one agent to it, at the post-fix HEAD:
re-extract claims from the files the fixes changed, re-run the cross-file classes, and verify the
run's *recurring* classes are now coherent **everywhere**, not just where they were reported. (Owning
it and running it by hand are different things — as in phases 1–3, the reading is delegated while the
arbitration and the record stay with the orchestrator.)

**One fix loop, and only one: phase-6 findings feed the NEXT run, never this run's fixers.** Recorded,
ticketed, not fixed. Without this rule the run has no termination condition, since every fix is itself
new prose that can be audited.

**"Ticketed" is not automatic — apply the filing bar here**
([`docs/verification-economics.md`](verification-economics.md)): a finding earns a ticket when it is
behavioural, a new class, or a guard gap on an invariant-bearing surface. Anything else is recorded as
"no action — <reason>" in the run's summary and, if it names a real defect, added to a standing list
the project already keeps. "Recorded, ticketed" otherwise reads as *ticket everything*, and a run that
files one ticket per residual buries its own class tickets in one-off instances. (The bar applies again
at phase 7's ratchet, over a different population: these are this run's re-check residuals, those are
the run-wide demotions.)

**Felt incident:** run 1's re-check found two residuals — one of them on a surface that *four
separate fixes* had each touched and still left out of sync with its siblings. That residual is what
justified demoting the class rather than fixing it a fifth time.

## Phase 7 — summary, ratchet, extraction

1. **A dated entry in your review-history log** — per-class finding counts, token spend, models used,
   the baseline SHA. **Trends compare per class, never totals**: a total moves with scope, so a
   smaller number can mean a cleaner tree or a narrower run, and by itself tells you neither.
2. **The ratchet** — one ticket per demoted class, each carrying the run's live case as its
   red-to-green test. This is the step that makes the next run cheaper. **Which findings become
   tickets at all** is the filing bar in
   [`docs/verification-economics.md`](verification-economics.md); everything below it is
   dispositioned "no action — <reason>" in the run's report and, if it names a real defect, added to
   a standing list — not filed. Apply that bar here, or the ratchet's ticket-per-class discipline
   drowns in one-off instances.
3. **Procedure deltas back into this document** — including deviations you *took* and decided were
   right, not only mistakes. Every rail above got here that way.
4. **A consolidated changelog entry** for the run as a whole, not one per fix PR.

## The gates

Four control points where the orchestrator either hands off or takes back:

- **GATE-1** — baseline frozen, inventory generated and reconciled, preconditions green, sweep leads
  written, role prompts instantiated → **phases 1–3 are delegated**, orchestrator tokens go idle.
- **GATE-2** — every audit file of every batch carries verdicts → the orchestrator returns for phase 4.
  **For a run covering scope C**, GATE-2 additionally requires the diversity leg's own report present —
  or the recorded operator skip decision — before phase 4; see [Scope C — code](#scope-c--code)'s
  Diversity paragraph.
- **GATE-3** — fix queue assembled → **phase 5 is delegated** to fixer sessions, strictly serialized.
- **GATE-4** — all fix PRs merged → the orchestrator runs phases 6 and 7.

## Session limits — the flow that survives a quota

An agent cannot see your usage window; **it has to ask, and you have to answer with a number.** Before
each wave:

1. **Ask for the live remaining-window percentage.** Budget for the wave = remaining − ~5% held back
   as the orchestrator's own reserve (it still has to arbitrate and record after the wave lands).
2. **Pilot two agents spanning the cost envelope — and pilot on a LEADS-DENSE batch, not just on the
   biggest file.** **Felt incident:** run 1's pilot under-predicted the main wave's per-agent cost by
   roughly 50%, because cost scales with **claims-to-re-measure**, not with input lines. A short,
   dense, heavily cross-referenced file is more expensive than a long simple one, and a pilot chosen
   for size alone will tell you the wrong number with total confidence.
3. **Do the arithmetic before spawning:** measured per-agent cost × wave size < budget. If it doesn't
   fit, split at a **stage boundary** — a whole batch deferred to the next window, never a half-batch.
4. **Hard-stop planning at ~95%.** Not 100%: the last few percent are what you need to record where
   the run got to.

Running out mid-wave is survivable *by contract*, and this is what the completeness marker buys: an
interrupted run loses only its unfinished units, which are re-spawnable individually because every
audit file either has its `## claims` section or is visibly incomplete. Never restart a whole wave.

## Incremental runs

*Not the same shape as [`docs/delta-audit.md`](delta-audit.md): this section's incremental scope is
prose, keyed to the **previous drydock run's own baseline** — one whole-tree pass diffed against
another. A delta audit scopes to a **release range** instead, covers every class its own derivation
script classifies a file into (not prose alone), carries a seam map, and ends in a GO/NO-GO a tag
actually waits on.*

Run 1 is a full-tree run. Every run after it is **scoped by diff from the previous run's baseline**:

```bash
<keel-checkout>/tools/drydock/inventory.sh --prev <previous run's baseline sha> > <audit-dir>/inventory-<sha>.md
```

Files changed since that SHA are flagged `CHANGED`, and the derived batches cover **only** those
files. Two things you carry in by hand on top of the diff scope:

- **The previous run's phase-6 residuals** — recorded-not-fixed by the one-fix-loop rule, so they
  enter this run as seeded findings rather than being re-discovered.
- **The full claims registry for phase 3.** The cross-file pass still runs over *every* file's claims,
  not just the changed subset — the whole point of that pass is a changed file contradicting an
  unchanged one. The previous run's audit files are still on disk; that is the registry.

**Worked example — keel's own run 2.** Its baseline is run 1's post-fix HEAD, and it inherits exactly
the two phase-6 residuals above: **dir #166** (four surfaces restating one procedure's outcome set,
one of them still short an item after four separate fixes) and **dir #167** (a derived sum quoted in
prose disagreeing with the table it sums, plus two parallel tables that drifted in row set). Both were
*also* two of the four classes run 1's ratchet demoted, so run 2's cheapest early measurement is
simply: did those checks land, and do they now catch these two residuals mechanically instead of by
hand? Here the first half is already answered — both checks merged before run 2 begins — so only the
second half is open. Ask both halves anyway, every run: a demotion that shipped means the next run
never spends an auditor on that class again; one still sitting in the backlog means the ratchet was
written down but not paid. Either answer is worth having before the wave spawns — it is the cheapest
available measurement of whether the last run's phase 7 was real.

## What a first run costs

Keel's run 1, for calibration — a ~14K-line prose surface across 93 files (33 markdown files at 7,159
lines; 60 shell files at 6,442 comment lines, that run having scoped scope B to its tools and tests
where the shipped default takes *every* tracked shell file):

| | |
|---|---|
| Auditors | 18 sessions, 83–438K tokens each (median ~190K), ≈3.56M total |
| Verifiers | 4 sessions, 116–184K each, ≈0.63M total |
| Cross-file pass + re-check | 1 session, ~283K for the pass; ≈0.47M total once phase 6's closing re-check is folded in (the source records only the combined figure) |
| Whole run | ≈6.1M sonnet tokens, mid-tier model throughout — the source record's own stated total; its itemization above sums to ≈4.66M, and the ~1.4M gap is a disclosed residual the source doesn't reconcile (calling it "orchestrator turns" would contradict the roles table three rows up, which runs the orchestrator as a real session, never a subagent) |
| Findings | 45 confirmed — 44 fixed across 8 PRs, 1 `known` |
| Wall-clock | ~1 operator-day, including quota waits |

**Finding density: about 1 per 300 lines of doc prose and 1 per 320 lines of comment prose** — close
enough that you can size a first run from your line counts alone. The useful outlier: zero findings in
recently-reworked files and in mid-size test files, whose comments turn out to be load-bearing and
therefore actively maintained.

## The role prompts

Copy-paste-ready templates, one per delegated role — instantiate the `<angle-bracket>` placeholders
and hand them to the session:

- [`docs/drydock/auditor.md`](drydock/auditor.md) — phase 1, scope A and B
- [`docs/drydock/code-auditor.md`](drydock/code-auditor.md) — phase 1, scope C
- [`docs/drydock/verifier.md`](drydock/verifier.md) — phase 2 (and the cross-file pass, phase 3)
- [`docs/drydock/fixer.md`](drydock/fixer.md) — phase 5

## See also

The three sibling docs are introduced at the top of this page and not re-glossed here; the one
dependency worth naming twice is [`docs/release-audit.md`](release-audit.md)'s **phase 0**, whose
green-contracts definition of project state is what the tier-1/tier-2 split above rests on, and whose
**phase 5** owns the review budget every drydock fix PR is reviewed under.

**This document is subject to its own phase 7.** If a real run's findings don't fit these phases, or a
rail here costs more than it catches, revise it as part of that run's extraction step — the same rule
`release-audit.md` states about itself, for the same reason.
