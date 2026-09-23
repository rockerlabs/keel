# Delta audit — auditing one release range, universe derived mechanically

*This is a worked instantiation of [`docs/delegation.md`](delegation.md)'s capability-split pattern —
read that doc for the generalized roles, contracts, and rails behind everything below.*

## 1. What it is, and when

A delta audit is the release-candidate pass of a release, run against a **mechanically derived
universe**: every file the range actually touched, plus the file→PR seam map, instead of a
hand-picked scope chosen by judgment. Run it late, once a release candidate exists and its CI is
green, before the tag.

**[`commands/delta-audit.md`](../commands/delta-audit.md) is the entrypoint** — a thin `/delta-audit
<version>` checklist over this doc, so the procedure below is run as a structural step rather than
cited from memory (`dir #385`; on an install where the adopter already owns the `/delta-audit` name,
`install.sh`'s generic collision-alias mechanism ships it under the prefixed name `keel-delta-audit`
instead).

Three siblings, and the boundary with each:

- [`docs/release-audit.md`](release-audit.md) **phase 6 is the caller.** Its RC-pass mandate used to
  pick its own three-point scope by judgment; this doc is what phase 6 now delegates to, with the
  three points surviving as a **depth heuristic applied within** the derived universe, never as the
  rule that decides what's in scope at all.
- [`docs/drydock.md`](drydock.md) is the **same role machinery, scoped differently.** Drydock audits
  the whole tree — prose and code both, by default — on a cadence of "every few releases." A delta
  audit scopes to one release range, covers every class `derive.sh` classifies a file into (not
  prose alone), and ends in a GO/NO-GO a tag actually waits on — drydock ends in a ratchet, not a
  release gate.
- [`docs/delegation.md`](delegation.md) is the **fan-out contract underneath both.** The roles,
  the unit-output contract, the rails block, the session-limit flow — none of it is re-derived here;
  this doc instantiates it for one application (a release delta) the way `drydock.md` instantiates it
  for another (the whole tree).

## 2. Phase 0 — the anchor

Resolve two revisions **live**, never by quoting a plan file or a prior session's snapshot:

- **The previous release's tag** — the anchor's start.
- **The release-candidate SHA** — the anchor's end. This is the RC commit CI is green on, **not the
  eventual tag**: a tag can point at a different commit than the one a plan session named, once a
  fix round lands after the plan was written but before the tag is cut.

CI must be green at the anchor before anything else starts — an audit on a red tree cannot tell
prose or logic drift from a live bug, and every finding it produces inherits that ambiguity.

**The anchor stays FIXED as `origin/main` moves.** Commits after the anchor are expected — this is
the run's own fix round — and each must be listed per affected file in the run's ledger. A
post-anchor commit that is **not** an audit fix (new feature work landing mid-audit) means the
operator re-cuts the anchor; it does not mean the running audit silently widens its own scope to
cover it.

**Recommended default, with its price named: post-anchor work rides the NEXT release.** The paragraph
above says what the audit *does* once such a commit exists — the operator re-cuts the anchor, and the
run pays for the wider range. This clause is about the decision made one step earlier, before the
commit lands, and it does not change that remedy. The run that paid for it took five NO-GO verdicts,
and every one of them turned on late-arriving surface — never on coverage. Each new surface arriving
after the anchor re-triggers the diverse-pair rule, so the honest price of landing work now is **a
re-cut anchor for feature work, or at least one more Clause A round for anything else**, and the one
surface that never got its pair was rolled back out of the release anyway, which is the expensive way
to arrive at the same place. So when work becomes ready after the anchor, put that price to the
operator at the moment it wants to land, as a number: defer, or pay it. This is a recommendation the
orchestrator states, not a rule the audit enforces — an operator who pays with the cost in view has decided
something, which is the whole point of naming it.

## 3. Phase 1 — derive the universe

[`tools/delta-audit/derive.sh`](../tools/delta-audit/derive.sh) does this mechanically. Given
`<prev-rev> <head-rev>`, it emits:

| file | content |
|---|---|
| `delta-files.txt` | the range's file list — the universe |
| `file-pr-map.tsv` | file → PR seam map; a row with ≥2 PRs is a seam |
| `ledger.md` | one row per file, in **pinned read order** (see §6), with an empty verdict column |
| `run-record.md` | a stub for the cross-run record (§7's sizing table source) |

**The closure check is the headline feature, not a nicety.** It compares the union of every per-PR
file list against the range diff and **refuses (exit 3) on one direction of disagreement**: a path in
the range diff that no PR's file list claims (`only_in_delta`) fails closure, because that is the
guard against a squash- or rebase-merged PR silently under-counting the seam map — exactly the class
of gap that cost a real run a by-hand recount (24 PRs counted by hand, 31 the mechanical map actually
held) before this script existed. The other direction — a path a PR claims that the net range
diff no longer shows (`only_in_map`) — is reported as `transient in range` and does **not** fail
closure: added and then deleted, edited and then reverted, or any other shape whose touches net to
zero inside the range, its two endpoints agree by construction, so it says nothing about whether the
map is complete (dir #288). Read `--help` for the full refusal/exit-code contract and the tuning
environment variables (`DELTA_HISTORICAL`, `DELTA_INVARIANT_PATHS`, `DELTA_SESSION_FILES`).

## 4. The Protocol — 8 rules, binding for every session this run spawns

Both real runs behind this doc adopted these from a *private* plan file each rewrote from scratch.
This is the durable public referent a future run points at instead of re-deriving them:

1. **Read-only.** No commits, no fixes, no edits to tracked files. Output goes only to your own
   report file — never touch the shared ledger or another session's report (concurrent sessions
   colliding on a shared file is a known, repeated incident class).
2. **Whole files, not hunks.** Read every assigned file end to end before writing any verdict. A
   hunk-only read is not an audit of the file — a real run had four targeted checks come back clean
   on a file where a whole-file read then found an actual false claim.
3. **Verify claims against the tree, not memory or plausibility.** Every factual claim a file makes
   (a path exists, a count, a test name, "X does Y") gets checked with `grep`/`ls`/`git` against the
   current tree. If you can't check it, write `UNVERIFIED` — a blank beats a wrong guess. **This is
   also where [`docs/release-audit.md`](release-audit.md) phase 6's depth heuristic applies**: within
   your assigned files, spend the deepest verification on a cross-PR seam (rule 4), a phrase that may
   have drifted as another PR changed the surface it described, and whether the tree's own
   drift-detectors still run where the work actually happens — the same three points that heuristic
   names, applied here rather than left as prose in a different document. **This rule's own worked
   incident is dir #225**, generalized in [`docs/delegation.md`](delegation.md)'s "Execute the claim,
   don't re-read it" section — see there for applications beyond auditing that need the same rule.
4. **Seam duty.** For each of your files with ≥2 PRs in `file-pr-map.tsv`: read the final merged
   state AND each contributing PR's own diff; check no later PR silently falsified what an earlier
   PR (or the file's own prose) established.
5. **Sandbox every live probe.** Any run of an installer, a doctor script, or anything that writes
   state: from a scratch clone with `HOME`/tmpdir overridden. Never against the real `$HOME` or the
   orchestrator's own main checkout. **A leg whose mandate is to apply
   [`FRAMEWORK.md`](../FRAMEWORK.md)'s own mutation-test-the-guard's-own-negative-path rule live gets
   its own dedicated clone — at minimum one per leg with a mutation mandate, never one shared with a
   clone another leg reads as ground truth.** A clone shared between a reading leg and a mutating one
   means every quote and `grep` result the reading leg produces is unverifiable for as long as the
   mutation is live, whether or not the mutating leg restores cleanly afterward — the report would read
   as confidently grounded regardless (dir #485).
6. **Report contract** — your report must contain, in this order:
   - `## Surfaces checked` — every assigned file, with "read whole: yes/no" and which checks ran;
   - `## Verdicts` — one line per assigned file: `clean` | `FINDING-<id>` | `waived(<reason>)`;
   - `## Findings` — each with file:line, the exact stale or false text quoted, the evidence
     (command + output) proving it wrong, and a proposed disposition (fix-before-tag / ticket-next /
     known-issue-in-changelog / `no-action(<reason>)`). **`no-action` is a real disposition, not a
     silent drop** — it is what a finding gets when it does not clear
     [`docs/verification-economics.md`](verification-economics.md)'s filing bar. Record the reason
     here **and**, if the finding names a real defect, add it to the project's standing list: that
     doc is explicit that a record living only in a report body is unschedulable, so the list is what
     makes this a persist rather than a discard. Without this disposition a session has only "ticket
     it or lose it", which is how a run files one ticket per residual. **Mark each finding `induced`
     or `original`** per that doc's run-profile field 6: `induced` when it lands in a region an
     earlier wave's fix actually touched *and* you can state the causal path in one sentence,
     `original` otherwise — both halves required, or the mark over- or under-counts. A run's first
     wave has no prior fix to be induced from, so every finding there is trivially `original`; mark it
     anyway, since the run record's rate (`induced / total`) needs the denominator too. **Write the
     mark as a line containing the literal substring `Mark:` (case-insensitive) followed by `induced`
     or `original`** — e.g. `**Mark:** \`induced\` — one sentence causal path to the prior fix` —
     this exact shape, not a paraphrase, is what `tools/delta-audit/harvest.sh` tallies into the run
     record's `induced / total` rate; a differently-worded mark is invisible to it and silently
     undercounts. **ONE `Mark:` line per FINDING, in the leg's own report, never per file** — two
     consecutive runs' tallies had to be hand-corrected: once the marks sat in the verifier's file in
     a shape the tally does not read (1 counted for 7 findings), then the legs wrote one per FILE (21
     for 7, read `0 / 21` for a run whose true rate was `3 / 10`). Until the tally counts per finding
     and reads the verifier's reconciled marks wherever they sit (`dir #527` owns both), this
     sentence is the compensation;
   - `## NOT checked` — anything in scope you skipped or couldn't verify, stated plainly.
7. **Don't trust a plan's snapshot.** Re-derive counts and lists live at pickup — the repo may have
   moved since the plan was written. The anchor stays FIXED even as `origin/main` moves past it
   (§2); list any post-anchor commits your report's scope touches and note whether each is an audit
   fix.
8. **English, and no release verdict outside the verifier.** Every session up to the verifier reports
   findings; only the verifier session issues "ready or not."

## 5. Roles and legs

The same shape [`docs/delegation.md`](delegation.md) names generically, instantiated for this
application — same terminology (**orchestrator**, never "coordinator") and the same reasoning for why
verifiers outrank auditors on effort: finding something is cheaper than proving it right or wrong,
and a wrong verdict is the one thing nothing downstream re-checks.

| Role | Runs as | Model + effort | May touch |
|---|---|---|---|
| **Orchestrator** | your own session | top tier, high | phase 0 (the anchor), all arbitration, the verdict record, **all** bookkeeping |
| **S1 — mechanical baseline** | spawned subagent | mid tier, medium | read-only, plus its own report |
| **S2…Sn — whole-read + seam auditor** | spawned subagent, many in parallel | mid tier, high | read-only, plus its own report |
| **Diversity leg** | spawned subagent (different vendor), or a blind same-method pass | mid tier, high (or the vendor's own default) | read-only, plus its own report |
| **S-final — verifier** | spawned subagent | mid tier, **xhigh** | the ledger's verdict lines, the run's verdict record |
| **Fixer** | a real, operator-launched session — **never** a subagent | mid tier, medium | one PR's worth of the tree |

**The diversity leg is required, not optional** — either a different model vendor or a different
method (blind whole-read, reconciled against the same-family sessions' reports afterward) satisfies
it, but skipping it entirely does not. Skippable only by an explicit, recorded operator decision,
never the orchestrator's own judgment. [`docs/verification-economics.md`](verification-economics.md)
owns the doctrine this rail comes from — why diversity is what decorrelates a reviewer, why a named
leg is non-waivable by an orchestrator, and the run that proved it; the rail itself is stated here
because a session following this procedure needs the operative rule, not just a pointer.
The blind-then-reconcile method is the generalized [`docs/delegation.md`](delegation.md) shape this
leg instantiates — see its "Blind-then-reconcile" section for the two-phase reviewer contract stated
independently of this application.

**The orchestrator's bookkeeping (the table's own "all bookkeeping" cell) includes the run profile's
other during-the-run field.** [`docs/verification-economics.md`](verification-economics.md)'s
per-leg cost (field 5) is not something `run-record.md`'s stub reconstructs at verdict time — record
each leg's sessions spawned, model tier + effort, and token spend as it completes, or `unmeasured`
where the harness doesn't report it, never a fabricated zero. Same discipline as the
`induced`/`original` mark above, with one gap that mark alone can't close: a per-file auditor sees
only its own assigned files' post-anchor commits (Protocol rule 7), so it can mark a same-file induced
defect but not one caused by a fix to a *different* file. The orchestrator, who already knows every
accepted fix and where it landed, reconciles cross-file marks at synthesis, before they land in
`run-record.md`.

**Fixes are a separate, gated phase, not part of any audit session above.** Every role through
S-final is Protocol rule 1's read-only — a `fix-before-tag` disposition (§8's report contract) is a
finding, not a fix. The orchestrator batches accepted fix-before-tag findings thematically and hands
each batch to a real, operator-launched Fixer session — one PR's worth of the tree, strictly
serialized if your project's gate keeps a shared sentinel — the same way
[`docs/drydock.md`](drydock.md) phase 5 does for a whole-tree run; that phase's mechanics (thematic
batching, accepted-findings-only, escalation triggers) apply here unchanged, so they aren't restated.
Once a fix PR is in review, it is an ordinary PR under
[`docs/release-audit.md`](release-audit.md) phase 5's own round budget.

## 6. Read order and incremental writing

**Binding on every whole-read session prompt this procedure generates:**

> Take the seams and the invariant code first, the remaining tests next, prose and the historical
> log (a changelog, or any dated append-only record) last. Write each finding into the report AT THE
> MOMENT IT IS FORMED, with its evidence quoted then — never batch findings to the end of the read.

Two reasons, and the second is the one worth restating because it isn't obvious:

1. **Attention thins across a very long read**, so the highest-consequence surfaces should be read
   while it's freshest.
2. **A context compaction destroys exactly the quoted text and command output the report contract
   requires.** A session that reads everything and writes up at the end can silently lose its own
   evidence and not know it — the resulting report reads as confidently unsupported rather than
   visibly incomplete. Writing as you go makes the evidence durable at the moment it exists.

`derive.sh`'s own ledger emission already follows this order mechanically (§3) — the corollary this
rule adds is that the ordering belongs in the script, not left to each session prompt's author to
remember.

**The report path in every leg prompt is ABSOLUTE, and the leg's final message carries an `ls -la`
of it.** Reason 2 above has a second half, felt live: a whole-read leg finished — hundreds of
thousands of tokens, zero findings, "written to `reports/S2.md`" in its last line — and the file did
not exist anywhere the run reads; the relative path had resolved against some other cwd, or the write
was refused unnoticed. The verifier launched against a confidently-unsupported claim, and the report
was recovered only because the leg's context was still alive to be resumed. A relative path in a
subagent's final line is not evidence the file exists where the run reads it; the listing is. All
four §9 prompts carry both. This is a permanent limit, not a gap a ticket closes: the run cannot
assert a subagent's write from outside the subagent, so the listing in the leg's own final message
is the check.

## 7. Sizing — a range, not a target

*Re-derive every figure below from your own project's cross-run record (keel's own is
`private/audit/RUNS.md`, gitignored and keel-internal — not shipped) at reading time. This table is a
snapshot, not a source, and that file's own header explains why raw counts across runs of different
scale are not a quality signal.*

| | first delta audit | light run |
|---|---|---|
| scope | 63 files, 31 PRs, ~5,500 insertions | 33 files, 8 PRs, 1,503 insertions |
| method | 8 sessions: S1 mechanical, S2–S6 parallel whole-read+seams, S7 verifier, S8 cross-vendor | 3 legs: S1 mechanical, S2 whole-read+all seams (blind-then-reconcile), S3 cross-vendor (2 rounds) |

Two sessions is not a floor and eight is not a ceiling — size your own run from your own range's
file and PR counts, not from either row above as a target.

**Session limits use [`docs/delegation.md`](delegation.md)'s own flow unchanged** (ask the operator
for their live remaining-window percentage, pilot two sessions spanning the cost envelope, do the
arithmetic before spawning a wave, hard-stop planning at ~95%) — not restated here. The one
application-specific input that flow needs: for a delta audit, cost scales with **seam count and PR
density**, not raw file count, since seam duty (Protocol rule 4) is the expensive part of a whole-read
session — pilot on a seam-dense file, not just a large one, the same way
[`docs/drydock.md`](drydock.md) pilots on a claims-dense file rather than a long one.

## 8. The verdict contract

A release is tag-ready only when:

- **Every ledger row carries a verdict** — `clean` | `mechanical-only` | a finding disposition |
  `waived(<reason>)`. `mechanical-only` is load-bearing, not a placeholder: it means S1's mechanical
  checks covered the row and no whole-read session found anything to add — a real, disclosed
  coverage state, distinct from `clean` (a whole-read session actually read the file) and distinct
  from an unverified row.
- **The verifier re-resolves the GO SHA live.** The tag target can move mid-run as fix commits land
  — a real run moved twice — so the verifier names the exact SHA it verifies at verdict time, never
  the SHA a plan file named at the start.
- **CI is green on that exact SHA**, including every platform leg your project's CI runs (an
  Alpine/BusyBox leg found real defects a GNU-only pass missed, in this project's own history).
- **Suite evidence comes from a clean worktree or CI, never the operator's own main checkout** — a
  real run's own main checkout produced a false FAIL once, costing a diagnosis round mid-run.
- **A green CI leg cannot REFUTE an environment-sensitive claim** — a pristine runner with a fresh
  home, no sibling worktrees and no concurrent sessions is the one place an environment leak cannot
  manifest, so green there is what the leak hypothesis predicts, not evidence against it. A worker
  retracted an isolation-leak observation on that ground in one run and the manager declined the
  retraction; an earlier ticket's "investigated, not reproduced" record was created by the same move.
  Close such a claim by varying the environment it names, or record it as unresolved — never on a
  green run in the environment where it cannot appear.

**This bar is coverage, not stopping.** It answers "is the run's bookkeeping complete" — every row
verdicted, on a re-resolved SHA, with CI green on clean evidence — not "was this run allowed to stop
where it did," which is [`docs/verification-economics.md`](verification-economics.md)'s Clause A: two
independent diverse legs, run in parallel on the same state, yielding no behavioural findings and no
new class. A run can satisfy every bullet above while still owing Clause A's second silent round; the
verifier checks both before declaring tag-ready, never the coverage bar alone.

**A GO verdict does not close the run — two records do, and a run that skips them leaves nothing a
later cycle can read.** Both are the **orchestrator's**, by the roles table above (§5: "**all**
bookkeeping"), not the verifier's: the verifier issues the verdict and stops, so a duty timed to the
verdict but owed by nobody named is the same ownerless duty one step earlier. So, before the
orchestrator records the GO verdict: **(a)** it OPENS the run's row in the project's cross-run record
from the `run-record.md` stub — opened, not completed, because some of the row's own fields are facts
about the tag (a prior run's row records the annotated tag peeling to the verified commit), which do
not exist yet; the row is completed at close, the same two-stage lifecycle the releases-side record
already practises. **Completing means REPLACING the opener's placeholder in place** — a tag field left
reading "pending" above an appended completion paragraph tells a reader who stops at the row's header
that the run never tagged (the 0.11.0 row did exactly that a day after its own tag; the next groom's
G0 is where it surfaced). **(b)** Every `no-action` finding that names a real defect (§4 rule 6) is moved onto
the project's standing list, and the run's staged-tickets file is empty or filed. *(Call (b) what it
is when you brief it — "**move the `no-action` findings to the standing list**". "Harvest" is already
the name of `tools/delta-audit/harvest.sh`, which fills this record's mechanically-derivable fields and
does nothing of the kind; a session told to "harvest" can run that script and believe the duty
discharged.)*

**A `ticket-next` finding is filed `→ pool` by default, never straight into the next release's tag
(operator decision 2026-09-20, at the 0.11.0 groom).** The exceptions are the two dispositions that
already carry their own urgency — `fix-before-tag` (fixed in this run) and a behavioural finding the
verdict names as such (the manager may slate it, saying so on the heading). Everything else waits for
the next groom's body read: [`docs/grooming.md`](grooming.md) G4's "re-examine on merit" is the gate a
ticket passes to enter a slate, and a manager filing nine audit tickets into the next tag on the day of
the cut bypasses it — the 0.10.2 close did exactly that and the following groom found the drain it was
supposed to size at 29 tickets against a plan of 14, six of them carrying an `R2` written at filing
(the audit itself grades nothing) that the backlog's legend reads as design-owed. The 0.10.2 run's
staged-tickets file already carried a `Suggested tag: → pool` line of its own; this paragraph is where
the rule lives, and a run's staging file states that line every time.

**Why the timing moved here at all.** One run paid for it twice over (2026-09-08; find its records by
the audit directory named for the range it covered, not by counting rows in a gitignored record no
adopter can read). Its `run-record.md` deferred the cross-run append to "the FINAL verdict, before the
tag"; the release then tagged, and **no row was ever appended** — the release's own cross-run row cites
an audit directory whose run is absent from the audit record. Two of that run's `no-action` findings
(an uncovered retry branch; an off-by-one count in a lib header, both re-verified live one cycle later
and both still true) were written up in its own verdict as belonging to the standing list, and never
reached it. **Neither loss was detectable from inside the run:** every ledger row carried a verdict and
the coverage bar above was satisfied throughout — which is the honest reading of that bar, not a
failure of it. [`docs/grooming.md`](grooming.md)'s G0 re-checks both a cycle later, and that is a
backstop, not a substitute: by then the run's session is gone and only what it wrote down survives.

**Both duties are still human discipline, and both are mechanizable — that is a gap, not a design.**
Nothing asserts that the row exists or that the standing list moved; `tools/delta-audit/harvest.sh`
already writes into `run-record.md` at the end of a run and is the obvious home for the assertion.
**So this clause is a compensation, and per [`docs/grooming.md`](grooming.md)'s G0 a compensation names
the ticket that removes it: `dir #462`.** Until that lands, the clause is the only thing standing
between a closed run and a lost record.

**The operator tags. No session in this procedure runs `git tag`.**

## 9. Session prompts

Copy-paste-ready skeletons, one per role. Every prompt below adopts the Protocol (§4) **by
reference** — restating all 8 rules in every prompt is exactly the bloat a reference avoids — but
**carries the rails block below verbatim, not by reference.** This is
[`docs/delegation.md`](delegation.md)'s own promise (its "Worker rails — verbatim, do not
paraphrase" section) applied honestly:
[`docs/drydock.md`](drydock.md)'s worker and verifier role templates (auditor, code-auditor, verifier)
now carry this block verbatim — dir #208 closed the gap a real run's own audit found in auditor and
verifier (code-auditor already carried it, from dir #204). The fixer, a mutator rather than a worker
or verifier, carries only the narrower DELEGATION RUN line per `docs/delegation.md`'s own template
split — a second template set repeating that gap is the one outcome this section exists to prevent.

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
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.
```

**S1 — mechanical baseline:**

```
You are S1 for a delta audit, <prev-rev>..<head-rev>.

Run `tools/delta-audit/derive.sh <prev-rev> <head-rev> --out <run-dir>`. Confirm the closure check
passes (exit 0) — if it refuses, STOP and report the refusal verbatim; do not proceed on an unclosed
universe. Then, for every row in the derived ledger, run whatever MECHANICAL checks this project
already ships (its test suite, doctor/self-check scripts, figure-accuracy checks) and record, IN YOUR
OWN REPORT, which rows those checks alone already cover — propose `mechanical-only` as that row's
verdict, per this procedure's verdict contract (docs/delta-audit.md §8). **Never write to the shared
ledger yourself** — you are read-only per Protocol rule 1, and only S-final consolidates verdicts into
it. Do not read file prose judgmentally; that is S2's job.

Follow the Protocol: docs/delta-audit.md §4, all 8 rules, binding.

Rails:
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
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.

Write your output to <ABSOLUTE path to this run's S1 report>, following the report contract in
Protocol rule 6. End your final message with the output of `ls -la <that path>` (§6).
```

**S2…Sn — whole-read + seam auditor:**

```
You are S<n> for a delta audit, <prev-rev>..<head-rev>. Your assigned files: <the read-order cluster
this session was batched, from the derived ledger>.

Read every assigned file WHOLE, in the order they're listed (docs/delta-audit.md §6's read-order
rule) — never in git's alphabetical order. Write each finding into your report the moment you form
it, evidence quoted then, per §6's second reason: don't batch findings to the end of the read.

For every file with ≥2 PRs in the seam map, additionally read each contributing PR's own diff (seam
duty, Protocol rule 4) — check no later PR silently falsified what an earlier one established.

Follow the Protocol: docs/delta-audit.md §4, all 8 rules, binding.

Rails:
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
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.

Write your output to <ABSOLUTE path to this session's report>, following the report contract in
Protocol rule 6. End your final message with the output of `ls -la <that path>` (§6).
```

**The diversity leg (vendor OR method):**

```
You are the diversity leg for a delta audit, <prev-rev>..<head-rev>. <Either: you are on a
DIFFERENT model vendor than every other session in this run — OR: you are running the SAME
whole-read method but BLIND to every S2..Sn report already written, to be reconciled afterward.>

Your assigned files: <the code and test rows the same-family sessions already covered — this leg's
value is concentrated where an earlier session accepted a claim from a well-written comment; a
diff-only reader structurally cannot reach some of what a blind whole-read leg finds, and vice versa>.

Read every assigned file WHOLE. Follow the Protocol: docs/delta-audit.md §4, all 8 rules, binding.
<If running blind-then-reconcile: after your own pass is complete and written, THEN read the
same-family reports and add a reconciliation section noting agreements, new findings, and any of
your own findings you now judge wrong in light of what the earlier sessions measured — self-correct
against them, don't just defer to them.>

Rails:
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
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.

Write your output to <ABSOLUTE path to this session's report>, following the report contract in
Protocol rule 6, plus your reconciliation section if applicable. End your final message with the
output of `ls -la <that path>` (§6).
```

**S-final — verifier, GO/NO-GO:**

```
You are the verifier for a delta audit, <prev-rev>..<head-rev>. You were given every S1..Sn and
diversity-leg report to merge.

Merge every session's verdicts into the ledger — every row must end with exactly one verdict per
docs/delta-audit.md §8's verdict contract. Adversarially re-verify a SAMPLE of `clean`/
`mechanical-only` rows yourself (don't just transcribe), and re-derive every `FINDING` independently
before accepting it. Resolve the GO SHA LIVE — re-check `origin/main` at verdict time, not the SHA
this run started against — and confirm CI is green on that exact SHA, including every platform leg.
Confirm suite evidence came from a clean worktree or CI, never the operator's own main checkout. Then,
separately from that coverage bar, confirm Clause A itself — two independent diverse legs, run in
parallel on the same state, together finding no behavioural findings and no new class — before
declaring GO; a fully-verdicted ledger is not by itself permission to stop (docs/delta-audit.md §8).

Follow the Protocol: docs/delta-audit.md §4, all 8 rules, binding — including rule 8: only THIS
session issues a release verdict.

Rails:
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
- DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.

Issue GO or NO-GO, naming the exact verified SHA, in <ABSOLUTE path to this run's verdict record>
(end your final message with the output of `ls -la <that path>`, §6). The
operator tags; you do not run `git tag`.
```

## 10. The disclosure-only fix round

A round distinct from an ordinary code fix round: when a late session re-scopes an **already-
disclosed** residual rather than finding new breakage, the honest pre-tag action is prose-only —
widen the disclosure, ticket the code fix for later, don't code a fix under tag-day time pressure for
something already named as a known gap.

**This round has its own hazard.** A correction inherits the imprecision of whatever it is written
FROM. Every claim in a disclosure-only round must be re-derived from the tree at writing time, never
paraphrased from an earlier report or a ticket's own body — a real run shipped two successive wrong
claims about the same mechanism into review because each was paraphrased from its source rather than
re-derived from the code. **This round gets a real review pass, not a rubber stamp for "it's only
prose."**

**The rule is narrower than "re-derive the claim being fixed," and two consecutive runs evidenced the
narrower form while following the paragraph above correctly.** A correction must re-derive **every
neighbouring claim in the same sentence it touches** — one run's first disclosure batch corrected four
findings and introduced one new defect, two false claims inside a single corrected sentence, a 25%
induced rate on prose alone. And a correction inherits the imprecision of its **measuring platform**,
not only of its source. The next run's orchestrator corrected a cross-vendor leg's wrong mechanism
claim from a live macOS reproduction — and one part of that corrected characterization flipped on
Linux until the verifier measured it there: what lost a row on one platform created a junk directory
at the filesystem root on the other. A correction that describes platform-dependent behaviour names
the platform it was measured on, or measures both — "reproduced live" on one platform is one data
point, not the mechanism.

**Re-derive every claim the correction TOUCHES, not only the claim it FIXES — and expect the induced
defect to land in the sentence being edited, because that is where it has landed.** A round did exactly
what this section asks for four claims under correction, and introduced **two new false claims into the
same sentence**, in the neighbouring material it had to rewrite to make the correction read: it renamed
the ticket that owned a review pass, and republished a correctly-scoped count of seven as "seven …
tree-wide" when tree-wide was nine. **Neither was a claim under correction; both were collateral.** A
disclosure-only round's blast radius is the sentence, not the clause — so the re-derivation duty has to
cover the sentence too, or the round trades one wrong claim for two.

## 11. The cross-vendor leg — four harness lessons, as classes

If your diversity leg uses a different model vendor — via a raw API, or through an unscriptable
packet hand-off (class 4 below) — rather than an in-session subagent, four transferable lessons from
real runs, stated as classes rather than naming any private harness path:

1. **A reasoner's reply may embed its JSON object mid-prose.** Extract it with a balanced-brace scan
   — never assume a clean JSON body or anchor on a leading `{`. A parse failure here reads as "the
   round produced nothing," which is a worse failure than a slow one because it's silent.
2. **A transient transport error on a large payload is not evidence of a size limit.** Diagnose it
   against a second in-flight round before retrying blind, and raise the vendor's max-token setting
   to a NUMBER, not merely upward — a reasoning model can spend its entire default budget on reasoning
   tokens and return empty content, which looks identical to a hung request from the caller's side.
   **The floor: 64k for a reasoning model on a delta bundle.** This is stated as a figure because the
   earlier wording ("raise it explicitly") was read and followed and still failed: a run raised the
   harness default 8192 to **16384**, and BOTH first-attempt rounds came back with empty `content` and
   a full `reasoning_content` — two wasted rounds, the exact silent failure this lesson exists to
   prevent. 64000 then worked for all four subsequent rounds. "Raise it" is satisfied by any increase,
   and that run's increase was satisfied and insufficient. **And 64k is the vendor's CEILING, not a
   floor you can stand on (2026-09-15):** the next run set it and one bundle came back empty TWICE,
   identically, with `reasoning_tokens` = 64000 = the hard cap, on a 23.8K-token prompt — the
   reasoner's spend is not a function of prompt size, so a round the cap cannot rescue is not fixed by
   narrowing the bundle either. When the ceiling is met and `content` is still empty, report the leg
   per R11 and let the sibling vendor cover that bundle, or route it to the vendor's non-reasoning
   model — a vendor limit, not a gap a ticket closes; do not relaunch. **A later run
   added the other half of this lesson:** capture the raw reply, `reasoning_content` included — one
   round's reasoning carried the correct analysis of a finding its own answer then stated backwards,
   and it was recoverable only because a raw-capture option happened to have shipped days earlier.

3. **Bundle a diff by COUPLING, or tell each reader what the sibling bundle holds.** A vendor's
   input cap forces a large diff into several bundles, and splitting it by file manufactures
   findings: one run's second bundle held a changelog, a command doc and tests that described code
   sitting in the first bundle, and the reader — following the prose-vs-code rule its own prompt
   gave it — flagged three `high` mismatches against code it could not see. Three false positives in
   one leg, discarded on that ground and not on merit. Keep a file with the prose and tests that
   describe it; where the cap makes that impossible, prefix each bundle with a manifest of what the
   sibling bundles contain, so an absence reads as "elsewhere," not "missing." This rule is mechanized
   in two forms now: keel's own harness (`dir #489`, phase 1's bundling rule for its second auditor)
   for a scriptable API vendor, and `tools/audit-packet/export.sh`'s `CHUNK-MANIFEST` line (dir #495)
   for the unscriptable leg below — one clause, applied by hand wherever neither has shipped yet.

4. **An unscriptable or non-integrated vendor is still a diversity leg — it just arrives through a
   packet, not an API call.** Feed `derive.sh`'s file list to `tools/audit-packet/export.sh`, hand
   the packet (or, for a tooled reader with repo access, a short pinned-SHA brief) to whoever runs
   that vendor, and import the reply with `import.sh` into drydock's ordinary file contract — the
   orchestrator then carries accepted findings into the run's ledger the same way it carries a
   same-family cross-vendor round's. Full procedure, both modes: [`docs/drydock.md`](drydock.md),
   "The external leg."

A delta bundle being a **diff**, not the whole file, is what makes this leg affordable to run at all
against a payload-limited or per-token-billed vendor.

## 12. Self-revision clause

This document is subject to its own phase-0 discipline: not a fixed verdict, a checklist to
re-evaluate. If a real run's findings don't fit these 12 sections, or a rail here costs more than it
catches, revise this doc as part of that run's own synthesis phase — the same rule
[`docs/drydock.md`](drydock.md) and [`docs/release-audit.md`](release-audit.md) each state about
themselves, for the same reason: a process doc that only one run ever shaped stops being reusable the
moment a second run's lessons don't fit it.

## See also

- **[`docs/release-audit.md`](release-audit.md) phase 6** — the caller. Its three points (cross-PR
  seams, whole-delta stale-phrase sweep, residual-ledger check) survive here as the depth heuristic
  §5's whole-read sessions apply within the derived universe.
- **[`docs/drydock.md`](drydock.md)** — the same role machinery, scoped to the whole tree (§1's prose
  and code both, not one release range); its "Incremental runs" section cross-references this doc for
  the release-range shape.
- [`docs/verification-economics.md`](verification-economics.md) — the reasoning behind the
  diversity-leg skip-requires-an-operator-decision rail (§5 states the rail itself), and the home of
  the stopping rule and filing bar this procedure's runs are governed by. Neither restated here.
- **dir #249** — owns the procedural step that requires `run-record.md`'s stub (§3) to be filled in
  and appended to the cross-run record; this doc's script emits only the stub.
