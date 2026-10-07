# Release history

A one-paragraph-per-release summary, newest first. Each entry is a condensed digest of its
`CHANGELOG.md` section — read that file for the full list of changes; this page exists so a reader
(or a future audit/RC pass) doesn't have to reconstruct "what actually shipped in each version" from
~3000 lines of dated detail. Companion to [`release-audit.md`](release-audit.md) (the process that
produces a release) and [`publishing-checklist.md`](publishing-checklist.md) (the mechanics of
cutting one) — this page is the record of what each one delivered.

**Starting at v0.9.0, each entry also carries a verification block** — a fixed-shape paragraph
appended after the digest, stating what was checked, by what, and what was not (dir #268). It is
written in the same cut-and-land PR as the digest entry itself, by hand — there is no generator. It
opens with the bold marker `**Verification.**`, followed by each field as a bold label and a colon:

- `**Scope:**` — files, PRs in range.
- `**Method:**` — how many review legs, of what kind.
- `**Coverage:**` — rows read out of the total, waived count.
- `**Findings:**` — fixed before tag / ticketed / shipped disclosed.
- `**Behavioural defects:**` — in shipped code, the floor figure.
- `**Which layer found what:**` — which leg found which class of finding.
- `**What was NOT checked:**` — the column this block exists for; the doc's own named coverage
  boundaries stated here, not smoothed over.
- `**Induced-defect rate:**` — defects the release's own fix rounds created, as a fraction of the
  total found.

The block never cites a `private/` path or a `dir #N` — its provenance is PR numbers, tags, and file
paths only, all of which a reader without access to the private audit ledger can open. **No block is
back-filled:** entries below v0.9.0 describe their verification only in the digest prose above and
were never recorded in this comparable shape.

## v0.14.0 — 2026-10-07

A managed release, groomed after the operator lifted the moratorium on keel work, with the delta audit run
before the tag. Its centre is the secrets path. A recipe for keeping secrets out of the working tree (SOPS and
age, with a `doctor` floor that names env-shaped files git tracks or would commit) ships with a scanner pattern
for an age private key (dir #631). The secret scanner no longer exits 0 after a crash on macOS bash 3.2 and no
longer reports `clean` over a staged file it could not read; the personal-literals file has one parser; the
installers and `doctor` agree on which hooks directory a guard lives in; and the installers close three more
ways past their never-clobber rule. `tools/vendor-review.sh` and its `agy.sh` client are hardened (dir #662).
Installs now place Keel's `docs/` beside `FRAMEWORK.md`, so the doc paths the rails and commands name resolve on
an adopter's machine (dir #650), and ship a read-only review agent, `keel-polish-reviewer`, that `/polish` runs
its fallback review as (dir #413). `/polish` split into a core and a hidden guide and now runs its review in a
fresh-context subagent first (dir #670); `/go` leaves a handoff note and checks its finished diff for seams
against PRs merged while it built (dir #401, dir #668); `/triage` is a new promote-or-drop command for the
accumulator tiers (dir #517). `doctor` gains a forgetting layer for the harness memory dir (dir #521) and no
longer passes an exposed `.claude/` because `CLAUDE.md` is ignored (dir #473); the test suite's canary sees a
leak that rewrites a file you were already editing, and the suite gates its environment and its leftovers in
the real temp dir (dir #664, dir #663). `SECURITY.md` gained a threat-model section (dir #89). The audit's
fix round then repaired the doc tests that would have turned the cut's own CI red, a leak gate that read clean over a
relative scanner path, a flaky census test, and three adopter-prose claims. Thirty-six merged PRs, #498–#533,
plus three audit fixes, #534–#536. Ten known issues ship disclosed in the CHANGELOG section, and its upgrade
note tells an existing install which installers to re-run.

**Verification.** **Scope:** 158 files across 36 merged PRs (#498–#533), range v0.13.0 (`31e32ec`) to the
release candidate `7d0fd60`, 191 commits, +12,322/−1,648; plus a fix round of three PRs (#534–#536), 13 files,
+149/−23, to the GO commit `62c71bb` — audit fixes, not feature work, so the anchor was not re-cut.
**Method:** a managed release; orchestrator Opus 5.5 at high effort. A mechanical baseline leg plus eleven
whole-read legs (Sonnet) over clusters cut by coupling, after a three-leg pilot; the diverse leg was DeepSeek's
chat model on eight coupled bundles (whole files, range diffs for five oversize files), no reasoning-model
rounds. The verifier (Sonnet) returned NO-GO at `7d0fd60`; on the operator's decision all six
fix-before-tag findings were fixed and the Clause A re-check was scoped to the fix round's new surface. Three
Fixer sessions — real sessions — merged as #534–#536. A re-check pair then read `62c71bb` in
parallel and blind to each other: a fresh same-family leg (whole-read of the 13 touched files, live closure runs
and mutation) and DeepSeek chat on two bundles. A second verifier pass, fresh from the written record, returned
GO. **Coverage:** 158 ledger rows, exactly one verdict each at both passes — pass 2: 84 clean, 74 finding, 0
mechanical-only, 0 waived (pass 1: 86 clean, 72 finding); the 13 rows on the fix surface were re-verdicted and
the other 145 are byte-identical to pass 1. CI run 37650500230, 6/6 on the exact GO commit by commit, including
the Alpine/busybox leg (the pass-1 candidate's run: 37551380137, 6/6). Suite evidence from sandboxed clones and
CI only, never the operator's own checkout: 9,517 passed, 0 failed, at the candidate; a simulated cut
(an emptied `[Unreleased]` above a dated heading) at the GO commit, 119 files, 9,543 passed, 0 failed, run
independently by the re-check leg and by the verifier. The verifier re-derived the six fix-before-tag findings
itself, live. **Findings:** 95 accepted across two passes — pass 1: 92 (89 leg findings plus 5 DeepSeek-derived,
less 2 merged duplicates); pass 2: 3, all low and non-behavioural. The six fix-before-tag findings were fixed in
the release: three doc tests' changelog assertions that read only the live `[Unreleased]` section and would have
turned the cut's own CI red, the leak gate reading clean over a relative scanner path, a census test's SIGPIPE
flake, and three adopter-prose items (a doc saying `doctor` deletes noise, the README's "updates it all at
once", and the section's upgrade note). Open at the GO: 38 behavioural findings, 24 ticketed and 14 recorded as no-action, all
filed in the backlog or on the standing list; the two passes put 39 lines on the standing list in all (37 from the
first, 2 from the second); the CHANGELOG section discloses ten known issues from
the audit's findings, and its closing sentence points at the rest. **Behavioural defects:** pass 1 accepted 39 behavioural
findings — 37 in product code and 2 in test infrastructure; of the 37, 14 were introduced by the range and 23
are baseline or further instances of known classes. One range-introduced defect failed open a documented
no-bypass gate (the leak gate and the relative path above), and it was fixed before the tag; no range-introduced
default-path crash was found. Pass 2 accepted none: the re-check pair and the verifier found no behavioural
finding. **Which layer found what:** the same-family legs found every fix-before-tag finding. DeepSeek's first
wave raised 53 numbered candidates and 6 were accepted (4 low baseline items in the secret scanner and the
suite canary, 1 corroboration of a same-family finding, 1 baseline no-action); 47 were refuted or left as leads,
mostly claims about code outside the changed hunks and busybox-portability claims refuted by container probes;
none was fix-before-tag or range-introduced. In the re-check pair, DeepSeek raised no accepted behavioural
finding and one claim refuted live (a stale `PWD` defeating the gate); the same-family leg found the three
pass-2 findings. Pass 1 named two new classes: a test that pins mutable release-flow state (the live
`[Unreleased]` text), and a path-valued environment variable re-resolved after the process changes directory.
No gate ran the suite on the cut shape; a check for that is filed. **What was NOT checked:** Clause A on the whole state. The verdicts ran NO-GO at `7d0fd60`, then GO
at `62c71bb` after one fix round, with Clause A satisfied on the fix round's surface under the operator's
scoping, not on the whole state: the re-check pair read only what the fix round newly reached and found no
behavioural finding and no new class, while the whole-state pair was not run and the 38 findings above remain
open. Beyond that: Linux, busybox and dash behaviour of the fix code was not re-run by the verifier — CI's
ubuntu and alpine legs are the only evidence, and the Linux flake rate of the repaired census test is
unmeasured; the simulated cut tests a shape, and the real cut also adds this history entry, which no test the
verifier ran has seen; the DeepSeek re-check bundles were not re-diffed byte for byte against the tree; the
pass-1 findings stand on pass-1 evidence, since nothing in the fix surface touches them; and the standing-list
lines were not re-read by the verifier. **Induced-defect rate:** 3 / 95 — the verifier's per-finding tally,
pass 1 0 / 92 and pass 2 3 / 3, all three low and none behavioural: an assertion widened to a whole file that
the fix's own changelog bullet satisfies, a list of path variables only half bound by tests, and a corrected
README sentence left unscoped beside the guard-hook copy it names. The automated tally counts marker lines and
reads 3 / 92, because DeepSeek-derived findings carry no marker line and two duplicates were merged; recorded
rather than smoothed. **Records:** the run's own audit directory, gitignored.

## v0.13.0 — 2026-10-03

The machine-safety slate, built ticket by ticket with `/go` under the operator's moratorium on keel
work — no groom and no managed release, one standalone delta audit before the tag. A new detector,
`tools/machine-watch.sh`, fingerprints the machine-global files a live check must never touch (git
global and system config, the global hooks dir, `~/.ssh/config`, the shell rc files) and reports a
change on the tool call that caused it, wired opt-in by `tools/install-machine-watch.sh`, with a native
OS notification so the operator sees it in the desktop app too (dir #437, dir #657). Keel's own durable
stores moved out of the harness home into one root, `$HOME/.keel`, so `rm -r ~/.claude` no longer takes
them along — a resolver first, then an `install.sh`-driven move that leaves a symlink per entry and
never overwrites (dir #637). Every git-reaching script, bar two named exceptions, now drops an
inherited `GIT_DIR` and its three siblings before its first git call, with a census test for future
scripts (dir #647). The two hook installers share one settings-merge core and append beside a foreign
hook on the same slot instead of refusing (dir #437, dir #468); `install-secret-guard.sh --force` no
longer overwrites an earlier saved hook (dir #625). `tests/run.sh`'s corruption canary survives a test
that overwrites the runner, watches the engine checkout too, and says so when git cannot read either
checkout, bar one nested layout disclosed as a known issue (dir #653). The cross-vendor reading leg
ships as `tools/vendor-review.sh` plus a worked `agy` client over a shared leak-gate lib (dir #614);
`/go` split into a small gate and a separate implementer guide, and gained a spec mode for projects
with no backlog (dir #642). The audit's five fix rounds then stopped the suite running an operator's
own notifier on test data, closed its residue in the real temp dir, pinned the negative paths of the
new guards with tests that turn red without them, and corrected prose the range had falsified.
Twenty-four merged PRs, #473–#496: seventeen build PRs and seven audit fixes. Seven known issues ship
disclosed in the CHANGELOG section.

**Verification.** **Scope:** 99 files across 17 merged PRs (#473–#489), range v0.12.0 to the anchor `06c5183`; plus seven audit-fix PRs (#490–#496) in five fix rounds, 104 files in v0.12.0..`0d9a892`, the GO commit and the merge of PR #496 — audit fixes, not feature work, so the anchor was not re-cut. **Method:** a standalone run, not a managed release (the operator's moratorium); orchestrator Opus 5.5. S1 mechanical baseline plus seven whole-read legs over clusters cut by coupling (machine-watch, hook installers, state root, git-env guard, the run.sh canary, go/vendor-review/leak-gate, cross-cutting prose), Sonnet; the diverse leg was DeepSeek by operator decision — its chat model on seven diff bundles, its reasoning model on four, all four of which returned empty at the vendor's ceiling. Clause A was applied strictly by operator decision: any behavioural finding from a re-check pair, known or not, resets it. Seven operator-launched Fixer sessions — real sessions, never subagents — in five fix rounds, checked by four re-check pairs, each run in parallel on a fix-round head: a fresh same-family leg plus DeepSeek chat on whole-file bundles (3, 4, 4 and 1 bundles). The S-final verifier ran five passes: the first two in one context, the last three fresh from the written record after the orchestrator's worktree was deleted. **Coverage:** 99 ledger rows, every row exactly one verdict at the anchor — 34 clean, 27 mechanical-only, 38 finding rows (17 fix-before-tag, 13 ticket-next, 7 no-action, 1 known-issue); none waived; carried through passes 2–5. The verifier read the whole range delta of the eight files the legs had read only in part; the unread remainder of those files is unchanged since v0.12.0 and its rows are mechanical-only, never clean. CI run 37127884060, 6/6 on the exact GO SHA by commit, including the Alpine/busybox leg. Suite evidence from scratch clones and CI only, never the operator's own checkout: the verifier's last run at the GO SHA passed 101 files, 7164 assertions, 0 failed, and a listing of the real temp dir around that run found no new entry of keel's. The verifier re-derived every finding and every fix itself — live wherever a probe was possible, by reading where it was not. **Findings:** 80 accepted across five passes (45 in the first wave, then 14, 10, 9 and 2 from the re-check rounds); 10 DeepSeek first-wave items refuted. The first wave's 12 fix-before-tag findings were fixed by the first three Fixer batches; the later batches fixed five more behavioural findings from the re-check rounds plus prose, and the last batch was prose only. Open at the GO: 30 behavioural — 17 ticket-next, filed at the run's close in 10 backlog tickets; 12 on the standing list as no-action; 1 a known issue — plus non-behavioural standing lines; the open defects an adopter can meet are disclosed as the CHANGELOG section's known issues. The last round's two low prose findings are imprecise clauses in known issue (7) itself, left as written: the cut changes no sentence. **Behavioural defects:** 30 ship open at the GO (split above). The first wave accepted 25, 17 introduced in this range and 8 baseline at v0.12.0; three were machine-safety paths introduced in range, all in the test harness or behind an environment variable — the suite running an operator's exported notifier on test data, probe directories left in the real temp dir, the engine half of the canary failing open and silent — and all three were fixed before the tag. The re-check rounds found 12 more, mostly baseline defects reached by deeper whole-file reads; among those fixed are both canary halves going silent when git cannot read the checkout they watch (one nested layout still skips silently, a known issue), the suite's residue in the real temp dir, and per-file logs sent to `/` when the temp-dir mint failed as root. One behavioural defect was induced by a fix round, low and fail-closed: a `TMPDIR` inside the watched checkout trips the canary on a clean run — induced on macOS, while on Linux the same trip predates the release — disclosed as part of known issue (7). None of the 30 open is a default-path write to the real machine or the destruction of a user file introduced by this range; the installers' never-clobber holes — `install-secret-guard.sh` overwriting a user's hook that merely mentions its marker, among them — are baseline, shipped already in v0.12.0, and now ticketed. **Which layer found what:** the same-family legs found every machine-safety item of the first wave and every fail-open shape of the canary. DeepSeek's first wave yielded one unique accepted finding, low, and corroborated one more; its machine-watch slice came back truncated, so at the first pass the release's largest new surface had no usable diverse read — one of the reasons Clause A was not met at that pass. From round 2, smaller whole-file bundles worked: DeepSeek found the install tests' symlink farms left in the real temp dir, which a diff bundle had missed, and three further accepted items. In round 5 it found nothing and missed the two prose imprecisions the same-family leg found. The verifier caught one orchestrator error at its first pass — the run's opening record cited a CI run for a different commit — and recorded its own upstream share of an induced finding: a fix brief that copied the verifier's imprecise wording carried the imprecision into the shipped sentence. **What was NOT checked:** Clause A on the whole state. The verdicts ran NO-GO, NO-GO, NO-GO, NO-GO, then GO at `0d9a892` — after four NO-GO passes, and with Clause A satisfied on the final fix round's surface under the operator's scoping, not on the whole state: by operator decision the last re-check pair read only the three CHANGELOG hunks the final fix batch changed, and on that surface it returned no behavioural finding and no new class. On the whole state the round-4 pair had returned six behavioural findings, and the 30 above remain open. The verifier's own judgement, recorded with the GO: the scoping is a sound operator decision, not a sound reading of Clause A as written, and the GO does not mean no behavioural finding remains. Beyond that, a selection from the run's own list: the private audit harness, gitignored and outside the universe; the `agy` client against a real `agy`, so two of its findings rest on reading alone; the two operator-drill claims behind the desktop notification, verified by no leg; the Linux behaviour of the round-5 canary probes, run on macOS only, with CI as the Linux evidence; which of the `KEEL_*` variables the suite leaves inherited name a path a test could write through, counted by a grep and never probed; the migrator's race with a live hook and a cross-filesystem move, read but not reproduced; and the procedure this run itself executes, which has no independent leg by design. **Induced-defect rate:** 18 / 80 — the verifier's per-finding tally: round 1 0 / 45, round 2 8 / 14, round 3 3 / 10, round 4 5 / 9, round 5 2 / 2 — one of them behavioural; most of the rest are imprecise sentences a prose fix wrote into the disclosures it added. The run's automated tally instead reads 16 / 76: it counts marker lines, so it counts two first-wave leads as findings and misses the verifier's later reconciliations. Recorded rather than smoothed. Records: the run's own audit directory and the cross-run audit record, both gitignored.

## v0.12.0 — 2026-09-25

The operator's one stated pain: «Тесты бьют по моей машине» —
tests hit my machine. The slate was cut at planning from forty-two tickets (eleven against
the pain, thirty-one carried over from an earlier lane) to the pain row's eleven alone, by
operator decision after the groom closed; the carried-over thirty-one returned to the pool
for a later sort. Every keel test file now fails closed without its own sandbox (dir #627);
the suite cannot write a ref into the real repository it runs from (dir #318); its config
writes are watched by a tripwire, widened to whole-config coverage in the RC's own fix round
(dir #630, dir #469); and the tools that resolve a repo path by `git -C` are no longer
redirectable to another repository by an inherited `GIT_DIR` (dir #644) — though the same
class stays open elsewhere, named at the cut as dir #647's own residue. The pre-PR gate's
sentinel and trace files left tens of thousands of files stranded in the shared `/tmp` —
about 31,000 when first found at the v0.8.3 close, still over 20,000 the day this release's
own fix merged — for a self-pruning `$HOME/.keel/tmp` root (dir #398, dir #399). The impact
store now tells a genuinely LOST entry from one that was simply never enabled, and refuses to
silently restart a trend it cannot actually see (dir #317, dir #630). The backlog's filing
bar became value-based, its first real use finding zero items worth a fresh ticket this run
(dir #635, its first PR only — a second PR and the backlog sort follow this tag). `/go`
itself was reworked three times in-release, plus a frontmatter fix (dir #636, dir #639, dir
#641, dir #645). Run as a managed release: one manager session, worker sessions each on a
single `/go <N>`, with a coordination-only overlay from the fourth wave on. Twenty merged
PRs, #451–#470.

**Verification.** **Scope:** 130 files across 20 merged PRs (#451–#470) — 16 in the original range v0.11.0..48a6569, plus a 4-PR fix round (#467–#470, 19 file-touches); the GO commit is `c1010d1`, PR #470's own merge — an audit fix, not feature work, so the anchor was not re-cut and the fix round's touched files carry their post-anchor commit on their own ledger rows. **Method:** managed release 0.12.0 (manager + orchestrator, Opus 5.5 + high). S1 mechanical baseline (Sonnet + medium) over all 130 files; five parallel blind whole-read legs over clusters cut by coupling (test harness 13 files, gate + installers 16, impact + read-trace 15, /go + filing bar 15, audit prose + CHANGELOG 7), each code file travelling with its test and the prose that pins it, at Sonnet + high; a cross-vendor wave on the same five clusters as diff bundles, blind, same SHA — GPT-OSS-120b, Gemini's quota exhausted. A first fix round (3 PRs, operator-widened) ran next, its own pair a same-family leg plus another GPT-OSS bundle; the verifier's own first pass issued a GO it could not support — on two facts the orchestrator's own re-derivation refuted — and, resumed with that evidence, ruled NO-GO on the resulting SHA over one finding. A second fix round (1 PR) closed it, checked by a fresh same-family leg plus a third GPT-OSS bundle. S-final verifier at the highest effort tier, one context resumed across three passes; every Linux/Alpine claim measured live in Docker, never inferred. **Coverage:** 130 ledger rows, every row exactly one verdict, resolved at the GO SHA — 56 clean, 4 ticket-next, 4 no-action, 2 fix-before-tag, 64 mechanical-only, 0 waived; every substantive row had one whole-read leg plus the mechanical pass. The two files a wave-1 leg had only partially read (`tests/test_pre_pr_gate.sh`, `tests/test_secret_guard.sh`) were closed by the verifier reading both whole, all 3680 and 1262 lines. CI 6/6 on the exact GO SHA, including the Alpine/busybox leg. Suite evidence from scratch clones and CI only, never the operator's own checkout. The verifier re-derived every finding and every refutation with its own live commands, in its own scratch clones, independent of the prior sessions' own runs. **Findings:** 9 accepted, 1 induced — a fix round's own new redaction code left a multi-line config value's continuation line unredacted. Six were fixed before the tag: an impact-store provenance writer that followed an inherited `GIT_DIR` into another repository's config; a new test-sandbox self-check that false-failed under a sibling worktree's ordinary commit; a gate veto with two unguarded `git -C` calls, baseline at v0.11.0; a misleading, though still fail-closed, deny message when `HOME` is a plain file; three previously-unpinned command-contract rules; and the induced redaction gap itself. Three were disclosed rather than fixed at the root: a known-class guard-coverage gap — the test sandbox's guard covers refs but not an arbitrary `git config` write, now at least detected by a widened tripwire though still unblocked at the write itself; one command doc's intro line still lacking a managed-release carve-out its own siblings carry; and the CHANGELOG's own stale test-file count, which this cut resolves. Zero items were filed as fresh BACKLOG tickets this run — every accepted finding was judged cheap and safe enough to fix or disclose in-release instead. **Behavioural defects:** 4 — two introduced in this range and fixed before the tag (the impact-store hijack, in the same release's own new provenance writer; the ref-guard self-check's false-trip, in the same release's own new self-check); one baseline at v0.11.0, also fixed here (the gate veto's own two unguarded `git -C` calls); and one a known-class test-sandbox guard-coverage gap, not a new regression — the guard covers refs but not an arbitrary `git config` write, disclosed via a widened detection tripwire rather than closed at the write. A fifth, the redaction gap, was induced by the first fix round itself and closed by the second. **Which layer found what:** the same-family legs found everything accepted; the vendor leg — GPT-OSS-120b, weaker than prior runs' Gemini — found nothing accepted. Two of its five first-wave bundles, the two safety-guard clusters, returned SHIP with zero findings and zero leads in about twenty seconds each, compensated by the verifier's own live re-derivation of three guard claims per cluster; its other three bundles raised five findings, every one refuted on execution — a transitive `source` chain read as absent, a shebang read as busybox, a documentation label read as a contradiction. The fix rounds' own same-family legs carried Clause A: the first found the run's only induced defect and the one finding that forced a second fix round; the second confirmed both fixes sound and found nothing new. The verifier itself needed one round of arbitration: its own first pass issued GO against its own "not satisfied" ruling on Clause A, resting on two facts it had gotten wrong, caught by the orchestrator's live re-probe and corrected to NO-GO before the second fix round resolved it for good. **What was NOT checked:** these are a selection from the run's own record. The private audit harness itself, gitignored and outside the universe the derivation tool's own git-diff scope can ever reach. The vendor leg's two thin bundles (the safety-guard clusters) were read only as a compensating check — three guard claims per cluster, re-derived live by the verifier — not independently re-read item by item the way the other three bundles' five findings were. One mechanical-pass leg disclosed a boundary it did not cross: the parts of `doctor.sh`'s and `citation-resolvability.sh`'s own checks that depend on the live main-checkout backlog rather than a scratch clone. The procedure this run itself executes has no independent leg, by design. **Induced-defect rate:** 1 / 9 — the verifier's own per-finding tally — a fix round's own new redaction code left one continuation line unredacted. The run's automated tally instead reads 2 / 11: one leg wrote two `Mark:` lines for a single finding, and a later leg's own below-bar prose note, not itself a finding, picked up a `Mark:` too. Recorded rather than smoothed; a ticket owns making the tally count per finding, not per marker line. Records: the run's own audit directory and the release ledger, both gitignored and named in the release manager's record.

## v0.11.0 — 2026-09-22

The drain. Every open backlog heading tagged for this version — thirty of them, fixed at planning
time and never grown — closed in one release, which is the whole point of a minor: the backlog's
0.11.0 lane reads zero open at the cut, measured by the census tool this same release shipped. Twenty
build PRs, plus the groom's and four the operator raised outside the slate. The spread is what a drain
looks like rather than a theme: a review-null fix commit no longer needs a fresh review trace to pass
the pre-PR gate; the delta-audit deriver's closure check learned which direction of disagreement
actually indicts the map and which is a path that nets to nothing inside the range; `doctor`'s body
scan stopped emitting ten warnings about its own accepted gaps; the pool report's re-grade arrows stop
being read as slate tags; a wrap's completion marker, the citation strip, the shell-quoting fallback,
the hook installers' uninstall pruning, and the secret-guard's own install path each lost a defect
that a previous cut had disclosed by number and left open. Run as a managed release — one manager
session, nineteen gated worker sessions across four waves cut by file overlap, with a pause of
about forty hours
in the middle when the budget check said wave four plus the audit plus the cut would not fit, and the
honest thing was to stop rather than start something that could not finish. The pattern's own costs
and defects — twelve or more rebases, a worktree-recycling near-collision, a review subagent that
reached the
real machine-global secret guard while reproducing a defect, and a CI wait that cost a session
thirty-plus no-op turns — are recorded in the release ledger, not here.

**Verification.** **Scope:** 59 files across 25 merged PRs (#424–#448), range v0.10.2 to the anchor `e36f46a`; the GO commit is `0d6a1bc`, the merge of the in-release fix PR #449 — an audit fix, not feature work, so the anchor was not re-cut and the three fixed files carry their post-anchor commit on their rows. **Method:** 8 same-family legs, count fixed at plan time and never grown, plus 14 vendor calls, in two waves — S1 mechanical baseline over all 59 files; five parallel blind whole-read legs over clusters cut by coupling (gate 12 files, secret-guard/installers 13, read-trace/self-tools 14, backlog instruments 13, prose/CHANGELOG 7), each code file travelling with its test and the prose that pins it; a cross-vendor wave on the same five clusters as diff bundles, blind, parallel, same SHA — two vendors, three models once a reasoning model's ceiling forced a reroute. A fix round then ran for the one behavioural finding: a gated Fixer session — a real session, never a subagent — with its own independent pair, one same-family leg and two cross-vendor ones, on the fix's own bundle. S-final verifier at the highest effort tier. **Coverage:** 59 ledger rows, every row exactly one verdict, resolved at the GO SHA — 49 clean, 8 ticket-next, 1 no-action, 1 fix-before-tag, 0 mechanical-only, 0 waived; every row had one whole-read leg plus the mechanical pass. CI 6/6 on that exact commit including the Alpine/busybox leg — in progress when the verifier launched and waited for, and the PR head's own green explicitly not inherited, a merge commit being a different commit. Suite evidence from scratch clones and CI only, never the operator's own checkout. The verifier re-read a sample of clean rows and re-derived every finding and every refutation with its own commands. **Findings:** 9 accepted, none induced by the run's own fix round — which is all the record's `original` mark asserts; two it additionally names as pre-existing, and the rest it does not date either way — 1 behavioural, fixed before the tag; 8 ticket-next or no-action, among them two coverage gaps, one a comment stating the opposite of what its code does, one a strip that misses a third punctuation shape of a family ticketed twice before, one a locale pin measured unreachable on both platforms keel targets, and one a documentation citation pointing at a section override that has never existed in any revision of the cited file. **Behavioural defects:** 1 — the secret-guard installer wrote its new run-scoped safety-net backup to the same path the `--force` branch uses for a permanent one, then deleted it on success, destroying a user's permanent backup on the next ordinary re-install. Introduced in this range, baseline-controlled against the previous tag, fixed with two distinct suffix constants and a regression test proved red by reverting the fix. It is the first behavioural defect in four audited releases, and the first one a delta audit caught that the release's own build reviews did not. **Which layer found what:** the cross-vendor leg found it, from the diff alone, and it was the run's only behavioural defect; the same-family whole-read of the very same file called it clean, because it verified the file through the shipped fixtures and every one of those is a failure-path case — the success path across two runs has no test at all. The converse held just as sharply: every mutation proof in the run required executing code, which a diff reader cannot do. The fix round is the cleanest illustration of the pair — the vendor leg predicted the new regression test was load-bearing by contrasting it with a neighbour that is not, and the same-family leg proved it by reverting the fix and watching the assertions go red. Neither could do the other's half. One vendor's reasoning model returned empty content at its ceiling on four of five first-wave bundles and was not relaunched; those four were routed to that vendor's non-reasoning model instead, which answered all four, so every bundle still carried two live diverse legs. The reasoning model's one completed bundle is where the behavioural defect came from. **What was NOT checked:** these are a selection from the run record's own longer list — the private audit harness, which is gitignored and outside the universe by construction; ten gate-cluster items from one vendor, read and spot-matched against an already-mutation-proved same-family read but not re-derived one by one, all of them that vendor's own "no defect" conclusions; six further vendor items across three bundles — a key-dedup overwrite, a byte-class check under a UTF-8 locale, a slug-collision fold, a test's pass-threshold looseness, a guard-ordering question already covered from another angle, and one stale prose rationale — read but not independently reproduced live, all latent or design-level rather than confirmed defects, and left to the standing pool reader's judgement rather than adjudicated at the cut; the procedure this run itself executes, which by design has no independent leg; and a local shellcheck reproduction, which returned output that did not match the command issued across three attempts and was discarded as untrustworthy rather than reported — CI's own shellcheck leg was the load-bearing one. **Induced-defect rate:** 0 induced / 9 total — the fix round's own independent pair came back clean on the fix. The run's automated tally instead read 0 of 23, because it counts marker lines across reports rather than findings, and one leg wrote fifteen of them on leads while its own report states zero findings — the same over-count class that needed hand-correction in each of the two preceding runs, here in a third shape. Recorded rather than smoothed, corrected by hand, and owned by a ticket that makes the tally count per finding. Records: the run's own audit directory and the release ledger, both gitignored and named in the release manager's record.

## v0.10.2 — 2026-09-19

The "close every known issue" patch, the second before the planned v0.11.0 drain, cut on one
operator-named pain: the previous cut had disclosed twenty-one open items by number, and a patch that
re-disclosed any of them unchanged would be the quietly-abandoned state the backlog's pool report
exists to make visible. Eighteen tickets, twelve PRs of their own (fourteen in the audited range, with
the groom's and one unslated docs PR), every one a located one- or two-file fix with its test — plus two that were not
small. The oldest was the shipped secret-guard missing a non-ASCII personal literal inside a UTF-32
blob under any ordinary UTF-8 locale, a live hole in a security tool that four earlier reconstructions
had failed to reproduce; the release manager isolated the mechanism live before briefing the worker,
the fix strips the offending bytes once in both tools that share the decode recipe, and the coupled
defect — a failing self-test that left the install half-wired — now verifies the vendored source
before any file is copied. The other was an environment-sensitive test discrepancy nobody could
reproduce; it closed the honest way its own acceptance clause allowed, "could not reproduce, here is
exactly what was varied", after five runs under live wave concurrency, and left behind the one
cheap instrument the ticket asked for: a failing suite run now keeps its per-file logs. In between:
the pre-PR gate keys its per-run files on the repository's full path instead of its basename and
anchors its test-relevant hash on the repository root instead of the invocation directory; the
installer no longer re-records an adopter's edited README as Keel-owned on a rerun; `doctor`'s own
recovery advice runs as written; both hook installers survive an apostrophe in the checkout path; the
pre-push secret scan resolves its allowlist baseline per pushed ref and fails closed when it cannot;
the test library's `run_in()` refuses an empty directory instead of silently running a test in the
real checkout, with a thirty-nine-site sweep of the same idiom recorded site by site. Run as a
managed release — one manager session, twelve gated worker sessions across four waves cut by file
overlap — with the pattern's own costs and defects recorded in the release ledger, not here.

**Verification.** **Scope:** 44 files across 14 merged PRs (#409–#422), range v0.10.1 to the anchor `ed62446`; the cut commit after it is prose only. **Method:** 6 legs, count fixed at plan time — S1 mechanical baseline; three whole-read legs over clusters cut by coupling (the security/installer cluster of 13 files, the gate/doctor/quoting cluster of 16, the self-tools/prose cluster of 15, so every changed file had exactly one whole read and each code file travelled with its test); a cross-vendor leg of two vendors on three diff bundles split by the same clusters (a Gemini reader on all three; a DeepSeek reasoner on two — it exhausted its 64k reasoning ceiling on the security bundle and was not relaunched, its captured reasoning mined for one lead instead); S-final verifier at the highest effort tier. No fix round was needed and no Fixer session ran. **Coverage:** 44 ledger rows, every row exactly one verdict — 34 `clean`, 8 `ticket-next` over six findings, 2 `no-action` on the standing list, 0 `fix-before-tag`, 0 `mechanical-only`, 0 waived. CI green on the GO SHA across all six legs, resolved live; suite evidence from scratch clones only. Clause A met with one named gap: the security cluster had a single live vendor read after the reasoner capped, compensated by the verifier's own highest-tier re-derivation of that cluster (the reachability scenario the new baseline logic guards was built and run live). **Findings:** 14 adjudicated — 10 accepted, 4 vendor claims refuted by execution (a claimed missing `pipefail` — present outside the hunk, the shipped broken-self-test stub run to prove it; a claimed bash 4.3+ over-escaping — identical output on seven bash versions in containers; a claimed missing grooming step — present; a claimed basename-only path match — the exact-match branch exists). Of the ten accepted: two coverage gaps (a guard with no test; a canary assertion that does not discriminate), one sync-twin drift between the two hook installers present since the previous release, one quoting edge on a no-jq fallback path, four comments or changelog sentences stating something false or over-stated (one re-derived in the cut commit itself under the whole-sentence rule), two no-action. **Behavioural defects:** none, in this release's code or in code an adopter had installed before it. **Which layer found what:** the same-family legs found the sync-twin drift and the untested guard; the vendor legs found four of the six ticketed items, all comment- or test-quality, and every one of their four behavioural-looking claims was refuted by running the code — the first run in this record where the diversity leg found no behavioural defect the same-family leg missed, on a range that had none to find. Bundling by coupling again produced zero cross-bundle false positives. **What was NOT checked:** the private audit harness (gitignored, outside the universe); the procedure this run executes had no independent leg, by design; the DeepSeek reasoner never read the security bundle; the local Alpine leg's network-dependent bootstrap assertions, which fail in this sandbox at a pristine baseline — CI's Alpine job was the load-bearing leg for every PR. **Induced-defect rate:** 0 / 14 — no fix round, so no fix-round defects; the release's own record counts three manager-brief text defects in the build phase, all caught by workers re-deriving before main. Records: the run's own audit directory and the release ledger, both gitignored and named in the release manager's record.

## v0.10.1 — 2026-09-15

The "two more vendors" patch, cut before the planned v0.11.0 drain on one operator-named pain: the Claude
usage window is the release bottleneck, and every behavioural defect the audits had ever found came from
the cross-vendor layer while an idle Google AI Pro quota and a colleague's OpenAI-family UI sat unused.
Two tickets, ten PRs of their own (eleven in the audited range, with the groom's). dir #495 shipped the **external audit leg**: `tools/audit-packet/export.sh` builds
a leak-gated packet from whatever file list the caller supplies (drydock's inventory or delta-audit's
derived universe), `import.sh` reads the vendor's replies back into drydock's ordinary file contract with
every `verdict:` empty for phase 2, and the drydock docs gained the fifth role template. The first run
turned the ticket's own premise on its head — the vendor was a coding agent with repo access, so run 1
went as a pinned-SHA brief, no chunks — and returned 17 findings, 16 verifier-accepted: six independent
bypasses of the two secret backstops (an allowlist trusted in the same commit as the secret it exempts,
non-ASCII filenames, renames, `++`-prefixed lines, binary blobs in the working tree, annotated-tag
bodies), all six fixed in this release (dir #508, #509) after the operator chose to fix rather than
disclose. dir #489 ran the **qualification ladder** for non-Claude generators: Gemini (via the
Antigravity CLI, headless, read-only by default) as the audit harness's second auditor, then three
mutator rungs — Gemini on a docs-only ticket and on one shell file, Freebuff's GUI on a docs-only ticket
— each diff reviewed and gated by a Claude session as the mutator of record, raw-diff corrections going
4 → 0 → 0 and reviewer cost at or below a plain Claude implementation (−18 %, −8 %; the third rung's
ticket was too small to compare). Two honest negatives ride with it: the ~185 KB inline cap is the CLI's
message path, not the model — a `read_file` mode reads a 556 KB bundle whole when asked a factual
question — but the model did not use the tool under a real audit prompt in three tries (dir #499), so
`auto` stays on the free inline path; and the Freebuff rung measured faithful application of a verbatim
spec, not authoring. This release's own RC audit then found the one behavioural defect of the range in
the new tool itself — `export.sh` embedded the `--known` file and the remote URL unscanned while the docs
promised no bypass — and it, too, came from the diverse pair.

**Verification.** **Scope:** 26 files across 11 merged PRs (#396–#406), range v0.10.0 to the anchor
`e7bbfdf`, plus the fix round's PR #407 (9 files) live-checked at the GO SHA `5333bf6`; the cut commit
after it is prose only. **Method:** 6 legs, count fixed at plan time — S1 mechanical baseline; S2
whole-read + seams over the code/test cluster (12 files, the 3-PR `import.sh` seam among them); S3
whole-read over the prose cluster (14 files, the 11-PR `CHANGELOG.md` seam); a cross-vendor leg of two
vendors on two diff bundles split **by coupling with a sibling manifest** (DeepSeek reasoner and Gemini
on bundle A; Gemini alone on bundle B after the reasoner exhausted its 64k completion budget twice — the
run's own counter-example to §11's "raise the floor"); S-final verifier at the highest effort tier;
one real Fixer session. The external OpenAI-family leg's 17 verdicts at `0396b4c` were carried into the
ledger as imported input, verified once by a separate Claude verifier, not re-run. **Coverage:** 26
ledger rows, every row exactly one verdict — 19 `clean`, 4 `fix-before-tag` closed by PR #407, 2
`ticket-next`, 1 `no-action(cosmetic)` on the standing list, 0 `mechanical-only`, 0 waived; 9 post-anchor
rows live-checked. CI green on the GO SHA across all six legs; suite evidence from scratch clones only.
Clause A satisfied on the anchor universe — S2/S3 and the two-vendor leg ran blind in parallel on one SHA
and the diverse pair found the one behavioural defect the same-family leg marked clean; on the fix
round's new surface two fresh-context reads ran sequentially (letter not met, spirit served — the
verifier advised against a third round, no open question remaining). **Findings:** 7 — 1 behavioural
(`export.sh`'s leak gate did not cover the `--known` file or the MANIFEST `remote:` URL; both vendors,
same line; fixed structurally by a second gate pass over the assembled packet), 2 stale claims
(`docs/delta-audit.md` §11's "three"/"four" and "via a raw API"; this changelog's own entry for the `--staged` scan fixes, item (d),
which named a mechanism the shipped code does not use — both re-derived from the tree under §10's
whole-sentence rule), 1 low (`import.sh`'s closing fence on a CRLF reply, batched), 2 coverage gaps
ticketed, 1 cosmetic. 3 refutations settled by execution (a bash-3.2 `${a[@]:-}`
claim, a `known`-class field, a fixture count). **Behavioural defects:** one, in this release's own new
tool, fixed before the tag; none in code an adopter had installed before this release. **Which layer found what:**
the same-family whole-read legs marked `export.sh` clean; both cross-vendor readers
flagged the same line — the eleventh consecutive run in which the diversity leg found what the
same-family leg did not. Bundling by coupling produced zero cross-bundle false positives, against three
in the previous run. The fix round then produced two induced defects of its own (a `#`-delimited sed
built from caller text; a cleanup trap that would remove a pre-existing packet dir), both caught by
the Fixer's own review before the PR opened. **What was NOT checked:** the private audit harness
(`agy.sh`, `run-audit.sh` — gitignored, outside the universe; a bash-3.2 regression there was found and
patched by the orchestrator mid-run); the procedure this run executes had no independent leg, by
design; DeepSeek never read bundle B. **Induced-defect rate:** 3 / 10 accepted findings (the two
Fixer-round defects and one low residual the Fixer's review parked and ticketed), all caught before
main. Records: the run's own audit directory and the release ledger, both gitignored and named in the
release manager's record.

## v0.10.0 — 2026-09-11

The "cost proportional to the task" release, run against two operator-named pains: a `/polish` gate
that ate review rounds, and shipped checks that were green in the presence of the exact defect they
named. On the first: the pre-PR gate's thirteen-hit "concurrent-session sentinel race" (dir #376)
turned out, under its design pass, never to have been a race at all — every deny path called
`retire_sentinel` *before* printing, so a single session's own deny destroyed its own receipt chain and
the message never said so; dir #80 had fixed the keying half while the cost sat in the lifecycle half.
Seven of fifteen retirement sites were removed, the change touching only destruction and never
acceptance, and all thirteen deny messages now say which of two states they report (dir #260, #346
remedies, #303, #336, #366) — with `agent:*+*` moved to the front of the unlock `case` so an add-on
token can never be captured by a trusted-suffix arm first. The review-trace ratchet dir #346 named was
measured six times inside its own release — every gate denial was the price of a review finding, and
the one worker whose review found nothing took none — and its design pass put a three-way fork to the
operator; C shipped as two free ordering rules in `commands/polish.md`, B-narrow is dir #488. On the
second pain: `doctor.sh`'s citation check now discriminates citation from credit via an author-supplied
`dir #N (ref)` marker applied symmetrically to both sides of its comparison, closing the false-positive
direction (dir #364) and the false-GREEN direction (dir #273) together, with the false GREEN
reproduced against real history first; its two single-definition drift checks no longer fail open on
brace placement (dir #380), and the fix's own review caught a silent false-OK it had just introduced;
`tests/test_install.sh`'s T21 now drives a real `install.sh` crash to a test-only checkpoint instead of
asserting about a fixture it built itself (dir #381); and `file:line` citations in comments are now
forbidden by a ratchet (`tools/self/line-citations.sh`, dir #382), the fork decided on a measurement —
16 of 32 in-tree citations were already wrong and zero of them were catchable by any plausibility
check. Two design passes declined to build: dir #344's twin-class sweep was measured against a real
release range before writing (7 fires, 0 true) and the class was found to be already mechanized three
times over by the one property that works; dir #479 was declined the same way. This release also
produced the project's first measured design-session cost lines.

**Verification.** **Scope:** 31 files across 12 merged PRs (#381, #384–#394), range v0.9.1 to the
cut. **Method:** 5 legs — S1 mechanical baseline; S2 whole-file-read + all 12 seams, run blind; S3
cross-vendor in two rounds on two ≤185 KB diff bundles, **with two vendors for the first time**
(DeepSeek reasoner, and Gemini via the Antigravity CLI); S-final verifier at the highest effort tier.
Leg count fixed at plan time. **Coverage:** 31 ledger rows, every row exactly one verdict — 26 `clean`,
5 carrying a finding, 0 `mechanical-only`, 0 waived. CI green on the RC SHA `81eb344` across all six
legs (shellcheck, self-check, secret-scan, ubuntu, macOS, alpine-busybox); suite evidence from scratch
clones only. Clause A satisfied: the whole-read and the two-vendor legs ran in parallel on the anchor
and jointly found no behavioural defect and no new class. **Findings:** the two vendors between them
raised 14 claims; the verifier accepted 8 (DS1-CV-3/4/5, DS2-CV-3/4, AG1-CV-1, AG2-CV-4/5) and rejected
6 with evidence. Of the 8: 1 fix-before-tag (a test comment with its ticket numbers swapped, folded
into this cut); 5 ticket-next, filed as four backlog tickets (the two grooming-doc invariant violations
as one); 2 no-action naming real defects, moved to the standing list together with one pre-existing
out-of-range item the mechanical leg surfaced. Three "one of them is wrong" disputes were settled by
execution rather than reading: the implementing worker was right and DeepSeek wrong on a bash-3.2
completion-marker (live-tested both ways); neither was wrong on a `${7-…}` contract; Gemini was right
about the test comment. **Behavioural defects:** none in shipped code. The one lead that outranked
everything — a worker's report of `gh pr create` succeeding right after `no active receipt` — was
live-reproduced benign in a scratch clone: the second create after a consumed sentinel is denied, and
the gate's accept path reads only the live sentinel, never its backup. **Which layer found what:** the
same-family whole-read leg reported zero findings across all 31 files; every accepted finding came
from the two cross-vendor diff readers, and the verifier's own adversarial sample of the whole-read
leg's `clean` rows found four low-severity misses among them — the tenth consecutive run in which the
diversity leg found what the same-family leg did not. The two vendors were themselves decorrelated:
DeepSeek dug into the new citation ratchet (five claims, two accepted); Gemini never touched it but
caught the two grooming-doc invariant violations DeepSeek missed. **What was NOT checked:** the
procedure this run itself executes had no independent leg, by design, same as the prior run; the
whole-read leg marked the release's most-rewritten file "read whole: yes, seam-focused" — a hedge the
verifier's sample, not an unqualified whole read, is what covers; and the cross-vendor readers saw a
diff, so the eight unchanged sentinel-retirement sites were visible only to the whole-read leg and the
verifier. Two procedure incidents inside the audit are recorded in its run directory rather than
smoothed: the whole-read leg's report never reached disk until the leg was resumed (a relative path in
its final line), and splitting the diff by file across the two bundles manufactured three cross-bundle
false positives in one vendor leg, discarded on that ground. **Induced-defect rate:** 0 of 8 accepted
findings — a first-wave figure, every finding `original` by construction; the one fix this run made
(a comment) is in this cut and had its neighbouring claims re-derived rather than paraphrased.

## v0.9.1 — 2026-09-08

The retro-and-audit-tail release: the v0.9.0 groom's five accepted retro proposals landed as
amendments to the procedure docs they correct (`docs/delta-audit.md`'s anchor-freeze clause,
`docs/release-management.md`'s pricing/worker-brief/closing-round updates, `docs/grooming.md`'s
sensor-coverage and pool-recording clauses), the deferred `docs/keel-ab/seed.sh` and `grade.sh`
re-landed with the review depth their post-anchor arrival skipped in v0.9.0 (all seven of that
deferral's audit findings fixed), and two read-trace fuse defects the v0.9.0 groom's own use of the
tier-2 aggregate surfaced were closed (a worktree path-normalization bug that fragmented per-doc
counts, and an 18-of-18 false-positive rate on the wrap fuse for centralized-wrap release workers).
The BACKLOG.md census family — `tools/lib/backlog-blocks.sh`, `tools/self/pool-report.sh`,
`tools/self/archive-sweep-check.sh` — had its own-tag-vs-citation bugs fixed and its duplicated strip
logic consolidated into one shared helper, and two duplicated git-main-checkout-resolution chains
merged into `tools/lib/repo-top.sh`. The `/keel-score` cost figure was re-derived through the deduped
transcript reader and confirmed to stand. This release's own release-candidate delta audit — run at
`e0b11a9` before this cut — found five more fix-before-tag defects, fixed as one batch: two test files
whose missing `summary` call let the full suite report `ALL TEST FILES PASSED` over a live failing
assertion; a re-derived `/keel-score` denominator ambiguity; a seam defect in
`docs/release-management.md`'s close-checklist cross-reference; `docs/grooming.md` telling a reader it
was still owed a ticket that had, in fact, already shipped in this same release; and a `tools/keel-impact.sh`
fix from the prior cycle (dir #409) that does not hold on bash ≥ 4.0, found only by the audit's blind
diversity leg and confirmed on both Linux CI legs.

**Verification.** **Scope:** 30 files across 10 merged PRs (#361, #369–#377), range v0.9.0 to the cut.
**Method:** 8 legs — S1 mechanical baseline; S2/S3/S4/S5 parallel whole-file-read + seam duty; D1 blind
diversity (a higher-tier model, plus a reconciliation pass); V1 cross-vendor (DeepSeek, scoped to 3
files, 2 rounds); S-final verifier. Leg count was fixed at plan time at 7 and corrected to 7+V1 before
the wave started, never grown mid-run. **Coverage:** 30 ledger rows, every row exactly one verdict;
`mechanical-only` used zero times — all 30 got a whole-file read (29 by an S-leg; `docs/delta-audit.md`
by D1 alone, single-leg by design since a leg must not certify the procedure it is executing); 0
waived. CI green on the RC SHA `e0b11a9` across all six platform/check legs (shellcheck, self-check,
ubuntu-24.04, alpine-busybox, macos-14, secret-scan) — for `tests/test_self_pool_report.sh` and
`tests/test_self_archive_sweep_check.sh`, "CI green" is materially weaker evidence than it reads (see
Behavioural defects). **Findings:** 5 fix-before-tag, fixed as one batch before this cut (PR #378) —
one behavioural defect in shipped code (`tools/keel-impact.sh`) and four seam/prose/test-coverage
defects. This audit's Part 1 filed **twelve tickets total**; **four are named individually in this
entry** — two gaps in this project's own gitignored audit-harness tooling, outside the ledger's 30-row
universe entirely (no shipped surface affected), a test-exemption blind spot in `commands/polish.md`,
and two disclosed defects — the `pool-report.sh` gate-matching defect (named again below) and the
wrong-mechanism claim (disclosed in `CHANGELOG.md`'s `[0.9.1]` known-issues paragraph, not repeated
here) — **the remaining eight are ticket-next dispositions from the ledger, counted without individual
description**; roughly 4 recorded on the standing no-action list; of 4 cross-vendor findings filed, 3
refuted (2 with positive controls) and 1 already covered by a standing disclosure, none accepted as
new; **4** leg verdicts overruled by the verifier — three marked OVERRULED in the ledger's own table
(`clean` on `tools/keel-impact.sh`; one entry of a `clean` cross-PR seam sweep on `CHANGELOG.md`;
`clean` on `docs/grooming.md`) plus a fourth the table does not carry at all (an earlier leg's
dismissal of a missing-`summary`-call finding as a mere formatting quirk). **Behavioural defects:** the
run's one CONFIRMED release-blocking behavioural defect — `tools/keel-impact.sh`'s
`_impact_merge_ledger_produce()` (bash ≥ 4.0
leaves an uninitialized `local` merely declared, not set-to-empty, so the prior cycle's EXIT-trap fix
leaked its own temp file and clobbered the exit status on both Linux CI legs; reproduced
independently, positive-controlled) — is fixed before this cut. **Three further behavioural
shapes are the floor beyond it, disclosed rather than fixed** (full wording in `CHANGELOG.md`'s
`[0.9.1]` known-issues paragraph): one live, in `docs/keel-ab/seed.sh`, an adopter-facing script; two
latent, in this project's own self-maintenance tooling (`tools/lib/backlog-blocks.sh`'s closure-tag
matching and `tools/self/pool-report.sh`'s parked-ticket matching), with no live occurrence on this
repository's own backlog today. **Which layer found what:** the run's one release-blocking behavioural
defect came from the blind diversity leg, not any same-family whole-read leg — the ninth consecutive
run of that pattern. The cross-vendor leg filed 4 findings, all refuted or already covered by a
standing disclosure; its one real contribution (the `pool-report.sh` defect above) surfaced only in a
round that returned no answer at all — recovered from that round's own discarded reasoning trace, not
from anything the leg stated. The verifier overruled 4 leg verdicts and independently re-derived the
two highest-stakes findings (`tools/keel-impact.sh`'s bash-version defect, and a full-suite `ALL TEST
FILES PASSED` reproduction) from scratch rather than relaying them. **What was NOT checked:** the
procedure `docs/delta-audit.md` this run itself executes had single-leg coverage, by design (a leg
must not certify the rules it operates under) — its diversity-leg findings have had no independent
second reader. Live probes ran on darwin only except where a finding specifically required a Linux
container (the bash-version premise above); a macOS-only-verified refutation of a flake comment's
causal claim is not established as platform-general. A pre-existing, untested retry branch in the
read-trace code (symlinked `$TMPDIR`) was found uncovered by any test and confirmed correct by
construction, not by a new test — recorded as a standing gap, not a defect. At the pre-tag
reconciliation above, Clause A's structural limb was not yet satisfied for the fix/release-cut range —
this file was surface no Part 1 leg had examined, and the orchestrator and that range's verifier had
read it sequentially rather than in parallel. A further round then satisfied it; see Induced-defect
rate below for what that round found and corrected. **On the release's own headline numbers:** PR
#373's four census figures (44 tickets flipped, 220 previously-closed, a 35→36% archive-share shift, a
pool size of 60) are quoted in that PR's own description and in the release manager's records, but
`BACKLOG.md` is gitignored with no git history, so the exact snapshot they were measured against no
longer exists and cannot be re-checked — as of this writing, running the PRE-#373 code against the
live `BACKLOG.md` reads 233 closed tickets, a 36→37% shift and a pool of 66, none matching the PR's own
figures, and a fourth source (`POOL-HISTORY.jsonl`) records a pool of 55 for the same release; the
audit found the file moved 448→451 ticket blocks within the single session that produced those
numbers. **What can still be checked, and was:** the differential effect of the code change itself,
reproduced by two audit legs from two different pre-#373 baselines against the same live backlog — 44
tickets flip from unflagged to flagged either way, 0 regressions either way, the same one-point
archive-share shift either way, pool size unchanged either way. That reproducible differential result
is this entry's only claim about those tools' effect; no absolute count above is asserted as a measured
fact. **Induced-defect rate:** 0 of 27 leg-level marks (as each leg filed them, before consolidation
into the dispositions above) — a first-wave figure only, describing Part 1's own audit before any fix
landed. The release's own fix round then proved that risk real: it shipped the false bash-boundary
claim corrected above (v0.8.0's record set the precedent — half that release's own defects were
created by its own audit's fix round). **Clause A's structural limb — two independent diverse legs
reading the same state in parallel — was satisfied** at the fix/release-cut range: a blind whole-read
leg, barred from opening any private audit record, and an independent cross-vendor leg ran in parallel
on this state and found no behavioural defect and no new failure class among the nine findings they
produced, the bash-boundary claim among them; a further review by the verifier itself, separately,
found this paragraph's own prior tense had been overtaken by that same result. Both are corrected in
this commit. The release-candidate audit ran in three parts. Part 1 covered the pre-fix range
(v0.9.0 → `e0b11a9`) and returned **NO-GO**, blocking on the 5 findings above; those fixes landed as
this cut's parent commit (`486f226`). Part 2 covered the fix and release-cut commits and returned
**NO-GO** on this block's ticket-provenance and leg-overrule counts, not the code; that reconciliation
landed as `c1a3637`, merged as `46f8bd8`. Part 3 covered `46f8bd8` and also returned **NO-GO** — again
not on the code, which it re-proved clean on every bash version tested, but on the bash-boundary claim
and this paragraph's own tense, both corrected here. What remains before the tag is a bounded re-check
on the resulting merge commit — the corrected text matching what Part 3 established, the suite green,
CI green across all six legs — which this entry does not itself assert as complete.

## v0.9.0 — 2026-09-07

The proof-of-value release: the sprint asked whether Keel earns its token budget, whether a session
can reach what shipped, and what happens when the answer is no — and closed all three with committed
numbers. What a unit of work costs on this project now has a measured, per-pipeline-stage answer from
deduplicated, subagent-inclusive transcripts (`docs/session-cost.md`, with the shared reader
`tools/lib/transcript-usage.sh` behind it and the `keel tokens` report giving any adopter the same
lens, PRs #353/#360). The always-on layer gained an eight-trigger index of shipped `docs/` procedures
— +194 tokens, measured not estimated, with a live demonstration of a session reaching a procedure it
was never told about (PR #349) — and its counterpart: a doctrine for retiring a shipped capability,
with a four-input evidence bar and a tail-risk exemption for safety rails (PR #354). The first
controlled Keel-vs-cold A/B ran and published keel-positive economy deltas with its honest symmetric
failure kept at full prominence (`docs/keel-ab.md`, PR #364; reproduction scripts deferred to 0.9.1
after the RC audit found them under-reviewed). The backlog now measures itself (archive-sweep and
pool-lane checks, PR #358), delegation safety was hardened twice over (a TL;DR for trivial spawns and
a dirty-tree discriminator propagated to every worker template, PRs #350/#356), and the release ran
end to end on the manager/audit toolchain v0.8.3 shipped — including a five-verdict RC audit whose
every NO-GO is part of this record.

**Verification.** **Scope:** 59 files across 22 merged PRs (#345–#367, excluding the deliberately
held #361), range v0.8.3 to the cut. **Method:** 21 legs (17 measured, 4 unmeasured) across five verdicts and three Clause A
closing rounds — a mechanical baseline, six whole-read/seam legs, a two-axis diversity layer (blind
and cross-vendor) and a verifier chain; ~3.77M measured subagent tokens, the cross-vendor rounds and
the orchestrator itself unmeasured. The fifth verdict closed on a single verifier pass with no fifth
diverse round — a knowingly lowered bar, taken as an explicit informed operator decision and recorded
with that caveat attached. **Coverage:** 59 ledger rows — 2 removed pre-tag with their
findings retained, not deleted (the deferred reproduction scripts), 57 live; every row exactly one
verdict; 0 waived, 0 mechanical-only. **Findings:** 8 fixed before tag (PRs #362, #367); 3 shapes shipped disclosed
(PRs #363, #366); 7 deferred to 0.9.1 with the scripts they live in; 5 ticketed next; 2 recorded on
the standing no-action list; 2 refuted with live platform controls. **Behavioural defects:** the
three disclosed shapes are the floor — all in self-maintenance census tooling, all in the under-count
direction, zero occurrences on this repository's own backlog at cut time; adopter backlogs are
unbounded, which is why they are disclosed rather than waved. **Which layer found what:** every
behavioural finding came from a diversity leg or an arbitrating role, none from a same-family
whole-read alone — the cross-vendor and blind legs each found what the other missed, the verifier
chain caught three misses the legs and the orchestrator shared, and the orchestrator's own
errors were each caught by a leg or an adjudication — including three figure errors in this block's
first draft, caught by the cut PR's review checking the block against the run record. **What was NOT checked:** the claim-truth
residual and model-family blindness beyond the one non-Anthropic family used; no diverse round ran
after the final three fixes (the lowered bar above); residual reachability was measured on this
repository's own backlog only. **Induced-defect rate:** 1 of 36 leg-level marks (as each
leg filed them, before consolidation into the dispositions above) — the release's own fix round
created one defect, disclosed above, caught by its closing round.

## v0.8.3 — 2026-09-06

The manager-toolchain release, shipped minimal-and-first so that v0.9.0 onward runs ON it. Four
sibling commands close the loop a release actually runs through — `/manage-release`
(`docs/release-management.md`, the release-manager pattern practised by hand across v0.8.0–v0.8.3 and
written down with its thirteen paid-for requirements), `/delta-audit` (a thin entrypoint making the
release-candidate audit a structural step instead of a memory — the loudest v0.8.2 failure closed),
`/groom` (the grooming manager: retro first, pains from the operator, derived lists, a mandatory
fresh-reviewer round), and the read-trace fuses (a silent hook mechanism logging what each session
actually read, a `docs read:` line on wraps and PRs, a dead-doc aggregate for the groom, and a
wrap-fuse flagging mutating sessions that never wrapped). Plus the removal-rail residue fix v0.8.2
disclosed: a crashed install's scratch no longer keeps `.keel` alive through an uninstall, and a kept
`.keel/` now names what kept it (dir #377). The release was itself run under the pattern it ships —
one manager session, five manager-launched worker sessions, serialized merges, a NO-GO RC audit whose
four tag-blocking findings were fixed and re-verified through a literal Clause-A closing round before
the tag (a different set of four from the residuals its changelog section discloses). Acceptance runs
for all four commands stay deliberately open into v0.9.0.

## v0.8.2 — 2026-09-04

The removal-rail release. v0.8.1 hardened `install.sh` against clobbering an adopter's files and
disclosed, in its own notes, that `uninstall.sh` carried the same gaps with deletion rather than
overwrite as the harm; this patch closes them and the residue around them. `uninstall.sh` now refuses
to claim ownership of a dest whose current form disagrees with its recorded kind, rejects the
self-equal unreadable-cksum sentinel that let a fail-open comparison authorise a removal, and checks a
symlink's provenance by reading the target the manifest now records — retiring the hand-maintained
path table an earlier fix had been forced to introduce (dir #347, dir #369). On the install side every
unguarded read of a possibly-non-regular dest is closed: a FIFO used to hang the run forever rather
than fail, and a directory is now declined explicitly instead of silently replaced (dir #351,
absorbing dir #356). `install.sh` gained a run-duration lock — an `mkdir` lock directory, no `flock`
dependency — so two installs into one home no longer race over whose records survive, and a manifest
it cannot read now stops the run before anything is placed rather than after, deliberately reverting
part of v0.8.1's own handling for that one case: a run that knows it cannot record what it places
should not place it (dir #350, folding in dir #348). Three hand-copied helper families were extracted
into shared libraries with a mechanical drift check, closing a class dir #278 had named a release
earlier (dir #362, dir #363). Smaller fixes: an ambiguity warning that fired on an ordinary supported
flow with a false premise and advice that would have undone the operator's own previous command (dir
#248); a dry-run preview under-reporting a directory that still held Keel content (dir #279); merge
helpers in `tools/keel-impact.sh` that moved a temp file inside a directory target and reported a
merge that never happened (dir #343, with dir #342's inode question resolved as a documented
assumption); and a test matching a bare token also present in a checkout's own path, so it was least
trustworthy exactly where it was most likely to run (dir #329). Reviews during the release found eleven
defects the tickets had not, including a TOCTOU race inside the new lock and a zero-byte-file hole in
every `bash -n` sourcing guard in the tree, two of which had already shipped. Four known issues ship
unfixed, each ticketed — the sharpest being that a crashed install leaves a scratch file that makes a
later uninstall's own cleanup silently fail (dir #377).

## v0.8.1 — 2026-09-03

The never-clobber-regression release. A release-candidate delta audit found nine issues, four
tag-blocking, fixed as one batch. The headline needed no `--force` at all: `keel_own_untouched`
checked only the RECORDED kind of a Keel-placed artifact, never its CURRENT kind, so an adopter who
replaced a Keel-placed file with a symlink or hard link back to the same bytes still passed the
"unedited copy" predicate — the next install then silently severed the link with no backup. The
predicate now refuses any dest whose current form disagrees with the recorded kind, unconditionally
in both copy and linked mode, and a new `stat_portable_nlink` check closes the hard-link twin the
same way. Two more regressions closed in the same batch: a manifest-snapshot `cp` that killed the
whole run on an unreadable (not just missing) manifest, and linked-mode `--force` advice that dropped
the `--home` suffix and could bootstrap a second Keel. Alongside the audit fixes: `install.sh --force`
takes over a drifted or refused Keel-owned file explicitly (dir #323, dir #324); `verification-economics.md`'s
Clause A gets a severity/reachability carve-out (dir #327); `changelog-section.sh --edit` warns when
release notes look copied rather than curated (dir #326); the portable-`stat` cache (two independent
reimplementations, dir #322) and the impact-ledger's atomic-write scaffold (three hand-rolled copies,
dir #345) are each extracted into one shared helper; and `tools/self/doctor.sh` now catches the
`${PIPESTATUS[0]}`-after-`pipefail` bug shape mechanically (dir #321). A disclosure-only round —
corrected twice after independent verification passes found false statements in its own prose — ships
two known issues unfixed: a concurrent install into the same home can still race two different ways
(dir #350), and `uninstall.sh`'s removal rail carries the same symlink-blindness and fail-open cksum
gaps the install-side fix just closed, scoped out of this release as its own ticket.

## v0.8.0 — 2026-09-02

The audit-on-the-audit release. The RC pass's closing round re-audited its own prior fix round and
found two more bugs in `tools/keel-impact.sh`'s merge helpers: a lost file mode on every merge, and a
crash window the first fix left behind that could self-cement a widened mode — both closed by writing
the mode onto the temp file before the atomic rename rather than the target after it. Earlier in the
same pass, a legacy-log sweep that could double rows on a failed cleanup and a masked pipeline status
that could silently drop a merged row were fixed too, and two `tools/pre-pr-gate.sh` deny messages that
sent an operator toward a remedy that doesn't work now point at the one that does. Two hazards named in
the prior release were also closed: neither `_impact_auto_migrate`'s completion marker (dir #289) nor
`cmd_migrate`/`impact_store_enable`'s (dir #304) can strand a partially-migrated project any longer.
Alongside the audit fixes: a review finding now classifies by blast radius and severity with an
explicit merge/round verdict (dir #197); the step-4 skip-dialog trace reads the operator's actual
answer instead of a marker's mere presence (dir #118); `/polish` tries the built-in
`Skill(code-review)` directly again now that the harness policy blocking it has lifted (dir #254); and
the test suite's fixture helpers guard against leaking a real git mutation outside their sandbox, with
a corruption canary to catch a recurrence (dir #318). Two known issues ship unfixed: an install-created
alias that forecloses ever refreshing a drifted `commands/polish.md` again, and an unwired `bin/keel`
whose only working remedy sits in a message neither of its own pointers reads (dir #323, dir #324).

## v0.7.2 — 2026-08-29

The external-store release. Keel's impact-scoring ledger moved out of every consuming project's
working tree into `$KEEL_HOME/.keel/impact/<project-id>/`, keyed by the main checkout's physical
path, so a linked worktree and its parent now resolve to one store instead of diverging, and
`keel-impact.sh enable` writes nothing into the project at all. A new `keel-impact.sh migrate` sweeps
legacy in-tree copies — merging untracked sources and deliberately refusing to touch a tracked one, a
case found live on two adopter repos. Alongside it, two additions adopters get and one they do not:
`docs/verification-economics.md` supplies the stopping rule and filing bar that `drydock.md`,
`delta-audit.md` and `release-audit.md` each assumed and none stated; drydock itself gained a
code-correctness module beside its prose one; and `tools/self/citation-resolvability.sh` — deliberately
keel-self-maintenance, never installed downstream — makes every `dir #N` cited under `docs/` resolve or
fail. It is also the first release whose RC pass had `tools/delta-audit/derive.sh`, a written stop rule
and that citation check all available at once, and that pass found behavioural defects in this
release's own migration code that the parallel whole-read wave did not: four were fixed before the
tag, and two failure windows in the auto-migration path shipped as-is, ticketed. Two
further known issues are disclosed in the changelog, each also carrying an open ticket.

## v0.7.1 — 2026-08-21

The audit-tail release. v0.7.0 shipped with a named list of six residuals it deliberately did not
hold its tag for; this release closes four of them rather than adding surface — the fenced-example
collision that could resolve the wrong introducing commit, a second `head -1`-under-`pipefail`
construct, the digit-shape numeric guard duplicated across seven files (now one shared
`tools/lib/nonneg-int.sh`), and the only behaviour-level one — `uninstall.sh` no longer reads a
stray same-named context file as proof of a live sibling install. Two more fixes came from that same
review round: a `git log -S` pickaxe that could abort a whole `self-check` run on an unborn HEAD, and
`--dry-run` over a manifest-less install now listing heuristically instead of refusing. Alongside
them, the release machinery got its own pass — `tools/changelog-section.sh --edit` folds the by-hand
release-note compose recipe into tested code, and the largest coverage hole v0.7.0's audit named is
closed at the source: the alpine-busybox CI leg installs `jq`, so the gate tests run there for the
first time (`tests/test_pre_pr_gate.sh` went from 2 to 469 assertions on that leg), and the leg's
"dubious ownership" workarounds were replaced by one container-level fix.

## v0.7.0 — 2026-08-20

The drydock release. Two arcs, plus the end of a migration window. First arc: **drydock** — a named,
reproducible whole-tree prose audit — went from an idea to a run to a shipped capability inside this
cycle: run 1 swept 33 markdown files and fixed 44 findings, the procedure and its tooling shipped as
`docs/drydock.md` + `tools/drydock/inventory.sh`, and the orchestration pattern behind it was
generalized into `docs/delegation.md`. Its ratchet — the rule that each run makes the next one
cheaper by demoting a finding class into a standing check — then produced four of them, including
`tools/self/prose-drift.sh`, which promotes run 1's throwaway sweep into `tools/self/doctor.sh`.
Second arc: release and review bookkeeping. The CHANGELOG↔tag check's release-in-preparation
allowance is now bounded by commit distance, so a forgotten tag stops reading green forever;
`tools/changelog-section.sh` makes cutting release notes one command; a step-5 receipt can name every
review that saw the commit and warns when a later round drops one; and `/polish` finally documents
its in-run convergence path. And the manifest migration window that v0.6.1 opened is closed: every
transitional `KEEL-LEGACY-NOMANIFEST` fallback is gone. Alongside both arcs, `docs/parallel-sessions.md`
shipped — the adopter-facing playbook for running two or more agent sessions against one repo.

## v0.6.1 — 2026-08-14

The release tail of the v0.6.0 audit — v0.6.0 shipped with a named list of known issues rather than
holding the tag for them; this release closed that list and the ~25 tickets around it. The install
manifest landed, so `install.sh`/`install-pre-pr-gate.sh`/`uninstall.sh`/`doctor.sh` read one
recorded state instead of re-deriving it heuristically at every site (dir #125); the `/polish` gate
learned the two checks v0.6.0 conceded it lacked — HEAD must actually be pushed before a PR can open,
and a convergence round no longer re-runs the whole test suite to re-bind a sha when nothing
test-relevant moved; and the review loop itself got a round budget, a delta-review protocol, a
terminal condition, and an in-session cross-model second opinion.

## v0.6.0 — 2026-08-12

The audit release. A global pre-release audit (dir #85) swept the whole project in four modules —
code, rails, docs, drift — producing ~73 findings, all eventually closed. The `/polish` pre-PR gate
got much harder to fool (a convergence round can no longer open a PR whose fix commit no test and no
review ever saw), and the three installers stopped disagreeing with each other — `install.sh`,
`install-pre-pr-gate.sh`, and `uninstall.sh` converged on one shared answer to "where does an install
live" and "what counts as its artifact."

## v0.5.0 — 2026-07-21

The first public global audit release: three independent external auditors (two repo-reading
sessions plus the DeepSeek harness) swept the whole public tree, and every confirmed finding was
either fixed or tracked as an explicit known issue.

## v0.4.0 — 2026-07-08

The "personal-data guard" release. `secret-guard` gained a second detector class — the operator's own
personal data (name, emails, drive labels, serials), read from a local never-committed file and
caught even inside UTF-16 binary fixtures — plus a determinism fix for a rare `--range` miss under
SIGPIPE, and `install.sh` re-runs started keeping Keel's own core in sync instead of freezing it at
first install.

## v0.3.1 — 2026-06-30

Audit-hardening and documentation release. A 4-report external audit drove a fix to a real
under-reporting bug in `doctor`/`public-audit` (a `pipefail`+SIGPIPE false-negative on large inputs),
plus a batch of new `doctor` checks and internal-consistency fixes across the docs.

## v0.3.0 — 2026-06-30

Onboarding and adoption release. The agent now finishes setup for you (`/keel-setup`), projects
self-register in `INSTANCE.md`, the user docs were rewritten in plain language with a concrete
non-Claude path, and a publishing checklist captured the go-public process end to end.

## v0.2.0 — 2026-06-29

Hardening release: eleven external audit rounds drove findings from a real PR-ref secret leak down to
cosmetic/UX nits, all fixed. The push guard started scanning the blobs a push actually introduces
(not the net diff), cross-platform CI (Alpine/busybox) started guarding portability, and every CLI
gained `--help`.

## v0.1.0 — 2026-06-27

First release: the durable foundation (`PRINCIPLES.md`, `FRAMEWORK.md`) plus a one-command,
self-verifying, demonstrable mechanized layer. Built and tested on Claude Code; the principles,
framework, and tools are harness-independent by design (see `ADAPTING.md`).
