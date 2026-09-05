# Release history

A one-paragraph-per-release summary, newest first. Each entry is a condensed digest of its
`CHANGELOG.md` section — read that file for the full list of changes; this page exists so a reader
(or a future audit/RC pass) doesn't have to reconstruct "what actually shipped in each version" from
~3000 lines of dated detail. Companion to [`release-audit.md`](release-audit.md) (the process that
produces a release) and [`publishing-checklist.md`](publishing-checklist.md) (the mechanics of
cutting one) — this page is the record of what each one delivered.

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
