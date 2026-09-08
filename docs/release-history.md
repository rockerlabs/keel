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
fix from the prior cycle (dir #409) that does not hold on bash ≥ 4.4, found only by the audit's blind
diversity leg and confirmed on both Linux CI legs.

**Verification.** **Scope:** 30 files across 10 merged PRs (#361, #369–#377), range v0.9.0 to the cut.
**Method:** 8 legs — S1 mechanical baseline; S2/S3/S4/S5 parallel whole-file-read + seam duty; D1 blind
diversity (a higher-tier model, plus a reconciliation pass); V1 cross-vendor (DeepSeek, scoped to 3
files, 2 rounds); S-final verifier. Leg count was fixed at plan time at 7 and corrected to 7+V1 before
the wave started, never grown mid-run. **Coverage:** 30 ledger rows, every row exactly one verdict;
`mechanical-only` used zero times — all 30 got a whole-file read (29 by an S-leg; `docs/delta-audit.md`
by D1 alone, single-leg by design since a leg must not certify the procedure it is executing); 0
waived. CI green on the RC SHA `e0b11a9` across all six platform/check legs (shellcheck, self-check,
ubuntu-24.04, alpine-busybox, macos-14, secret-scan) — for two of the thirty rows, "CI green" is
materially weaker evidence than it reads (see Behavioural defects). **Findings:** 5 fix-before-tag,
fixed as one batch before this cut (PR #378) — one behavioural defect in shipped code
(`tools/keel-impact.sh`) and four seam/prose/test-coverage defects; 3 further items filed as tickets
directly by the release manager rather than reported through this block — two file-scoping defects in
this project's own gitignored audit-harness tooling (no shipped surface affected), a pre-existing
`docs/delegation.md` citation drift that predates this release's own audit window, and the
`tools/self/pool-report.sh` gate-matching defect named below; roughly 9 more ticketed next; roughly 4
recorded on the standing no-action list; of 4 cross-vendor findings filed, 3 refuted (2 with positive
controls) and 1 already covered by a standing disclosure, none accepted as new; 3 leg verdicts
overruled by the verifier (a `clean` on `tools/keel-impact.sh`, a dismissal of a summary-omission
finding, a `clean` on `docs/grooming.md`). **Behavioural defects:** the run's one
CONFIRMED release-blocking behavioural defect — `tools/keel-impact.sh:577` (bash ≥ 4.4 leaves an
uninitialized `local` merely declared, not set-to-empty, so the prior cycle's EXIT-trap fix leaked its
own temp file and clobbered the exit status on both Linux CI legs; reproduced independently three
times, positive-controlled) — is fixed before this cut. **Three further behavioural shapes are the
floor beyond it, disclosed rather than fixed** (full wording in `CHANGELOG.md`'s `[0.9.1]`
known-issues paragraph): one live, in `docs/keel-ab/seed.sh`, an adopter-facing script; two latent, in
this project's own self-maintenance tooling (`tools/lib/backlog-blocks.sh`'s closure-tag matching and
`tools/self/pool-report.sh`'s parked-ticket matching), with no live occurrence on this repository's own
backlog today. **Which layer found what:** the run's one release-blocking behavioural defect came from
the blind diversity leg, not any same-family whole-read leg — the ninth consecutive run of that
pattern. The cross-vendor leg filed 4 findings, all refuted or already covered by a standing
disclosure; its one real contribution (the `pool-report.sh` defect above) surfaced only in a round
that returned no answer at all — recovered from that round's own discarded reasoning trace, not from
anything the leg stated. The verifier overruled 3 leg verdicts and
independently re-derived the two highest-stakes findings (`tools/keel-impact.sh`'s bash-version defect,
and a full-suite `ALL TEST FILES PASSED` reproduction) from scratch rather than relaying them.
**What was NOT checked:** the procedure `docs/delta-audit.md` this run itself executes had single-leg
coverage, by design (a leg must not certify the rules it operates under) — its diversity-leg findings
have had no independent second reader. Live probes ran on darwin only except where a finding
specifically required a Linux container (the bash-version premise above); a macOS-only-verified
refutation of a flake comment's causal claim is not established as platform-general. A pre-existing,
untested retry branch in the read-trace code (symlinked `$TMPDIR`) was found uncovered by any test and
confirmed correct by construction, not by a new test — recorded as a standing gap, not a defect. **On
the release's own headline numbers:** PR #373's four census figures (44 tickets flipped, 220 total
closed, a 35→36% archive-share shift, a pool size of 60) are quoted in that PR's own description and
in the release manager's records, but `BACKLOG.md` is gitignored with no git history, so the exact
snapshot they were measured against no longer exists and cannot be re-checked — as of this writing a
live read of `BACKLOG.md` shows 233 closed tickets, a 36→37% shift and a pool of 66, none matching the
PR's own figures, and a fourth source (`POOL-HISTORY.jsonl`) records a pool of 55 for the same release;
the audit found the file moved 448→451 ticket blocks within the single session that produced those
numbers. **What can still be checked, and was:** the differential effect of the code change itself,
reproduced by two audit legs from two different pre-#373 baselines against the same live backlog — 44
tickets flip from unflagged to flagged either way, 0 regressions either way, the same one-point
archive-share shift either way, pool size unchanged either way. That reproducible differential result
is this entry's only claim about those tools' effect; no absolute count above is asserted as a measured
fact. **Induced-defect rate:** 0 of 27 marked findings — a first-wave figure only, not yet informative
about the release's own fix round (v0.8.0's record: half that release's defects were created by its
own audit's fix round, with the coverage bar satisfied throughout — the same round is this release's
largest known risk, and is what Part 2 below exists to check). **This verdict is Part 1 of two, and is
NOT a release verdict.** The release-candidate audit ran in two parts: Part 1 covered the pre-fix range
(v0.9.0 → `e0b11a9`) and returned **NO-GO**, blocking on the 5 findings above. Those fixes landed as
this cut's parent commit (`486f226`). **Part 2 — covering the fix commit and this release-cut commit —
has not run as of this entry's writing** and is what actually gates the tag; this entry describes the
audit truthfully as of its own composition and asserts no GO.

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
