# Release history

A one-paragraph-per-release summary, newest first. Each entry is a condensed digest of its
`CHANGELOG.md` section — read that file for the full list of changes; this page exists so a reader
(or a future audit/RC pass) doesn't have to reconstruct "what actually shipped in each version" from
~3000 lines of dated detail. Companion to [`release-audit.md`](release-audit.md) (the process that
produces a release) and [`publishing-checklist.md`](publishing-checklist.md) (the mechanics of
cutting one) — this page is the record of what each one delivered.

## v0.8.0 — 2026-09-02

The audit-on-the-audit release. The RC pass's closing round re-audited its own prior fix round and
found two more bugs in `tools/keel-impact.sh`'s merge helpers: a lost file mode on every merge, and a
crash window the first fix left behind that could self-cement a widened mode — both closed by writing
the mode onto the temp file before the atomic rename rather than the target after it. Earlier in the
same pass, a legacy-log sweep that could double rows on a failed cleanup and a masked pipeline status
that could silently drop a merged row were fixed too, and two `tools/pre-pr-gate.sh` deny messages that
sent an operator toward a remedy that doesn't work now point at the one that does. Two hazards named in
the prior release also closed: neither `_impact_auto_migrate`'s completion marker (dir #289) nor
`cmd_migrate`/`impact_store_enable`'s (dir #304) can strand a partially-migrated project any longer.
Alongside the audit fixes: a review finding now classifies on blast radius and severity with an
explicit merge/round verdict (dir #197); the step-4 skip-dialog trace reads the operator's actual
answer instead of a marker's mere presence (dir #118); `/polish` tries the built-in
`Skill(code-review)` directly again now that the harness policy blocking it has lifted (dir #254); and
the test suite's fixture helpers guard against leaking a real git mutation outside their sandbox, with
a corruption canary to catch a recurrence (dir #318). Two known issues ship unfixed, disclosed in the
changelog, each carrying an open ticket (dir #323, dir #324).

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
