---
description: Run the release-candidate delta audit for one version, orchestrating docs/delta-audit.md's roles from your own session
argument-hint: <version>
---
You are the **orchestrator** for a delta audit of `$ARGUMENTS`, per
[`docs/delta-audit.md`](../docs/delta-audit.md) — the RC pass of a release, run against a mechanically
derived universe. This command is a POINTER and an ordered checklist, never a restatement: the
Protocol's 8 rules, the role table and the session prompts stay in the doc and are adopted by
reference. Where this checklist's compression disagrees with the doc's own text, the doc wins.

**A1 — read the doc, then the brief, then resolve the anchor.**
Read [`docs/delta-audit.md`](../docs/delta-audit.md) WHOLE before anything else — citing it unopened
is the exact v0.8.2 failure this command exists to close structurally. If the release manager (or the
operator) left a starting brief, read it second — the practised handoff shape is
`private/audit/<range>/BRIEF.md` (main checkout, gitignored): the state, the range with an order to
re-derive rather than reuse its figures, the PR→ticket→surface map, and seam suspicions marked "leads,
not findings" (some are expected to be wrong). Then resolve `<prev-rev>` and `<head-rev>` **live**, per
§2: the previous release's tag → the RC SHA CI is green on, never from a plan file. Red CI at the
anchor → stop.

**A2 — derive the universe mechanically.**
Run `tools/delta-audit/derive.sh --out <run-dir> <prev-rev> <head-rev>` (§3). A closure-check refusal
stops the run, verbatim — never proceed on an unclosed universe.

**A3 — budget flow BEFORE any wave.**
[`docs/delegation.md`](../docs/delegation.md)'s session-limit flow, not restated here: read the
token-SPEND side from whatever on-disk usage data your project already ships; ask the operator for the
live remaining-WINDOW percentage where that isn't derivable (delegation.md's own named-override note
for this amendment). Pilot on a seam-dense file, do the arithmetic before spawning a wave, hard-stop
planning at ~95%. This is a required checklist item, not advice — leg counts are fixed at plan time and
never grown mid-run; a leg that fails twice is reported to the operator, never relaunched in a loop.

**A4 — the diversity leg is non-waivable by you.**
§5's rail: either a different model vendor or a different method (blind whole-read, reconciled
afterward) satisfies it. Skippable only by an explicit, recorded operator decision — never your own
judgment.

**A5 — Fixers are real sessions, never subagents.**
§5's role table, serialized where the project's gate keeps a shared sentinel. Inside a MANAGED release,
`dir #367`'s R3 soft form extends here: you launch Fixers yourself, one health-line per launch, operator
can revoke. In a standalone audit (no manager), Fixers stay operator-launched per the doc's own row.

**A6 — the run record is part of the run, harvest included.**
Fill `run-record.md` and append the run's row to your project's cross-run record (keel's own:
`private/audit/RUNS.md`, gitignored, main-checkout root — `dir #249` owns this step). Then **harvest**:
every `no-action(<reason>)` disposition naming a real defect gets copied onto the project's standing
list (keel's instance: the `## Standing list` section of `BACKLOG.md` — create it per its own shape if
it doesn't exist yet, rather than a silent no-op). Verify `tickets-staged.md` is empty or filed before
leaving the run directory behind.

**A7 — you hand the operator the tag commands; you never run them.**
§8: no session in this procedure runs `git tag` or `gh release`. At GO, hand the operator ONE
copy-paste-ready command block — tag on the exact verified SHA, tag push, `gh release create` with the
notes file, the bootstrap stamping — each re-derived LIVE from
[`docs/publishing-checklist.md`](../docs/publishing-checklist.md) §4 with the version and SHA
substituted, never recited from memory and never replaced by a pointer to the checklist. The
`--notes-file` in that block points at a notes file YOU compose (or, inside a managed release, the
manager composes) from the tagged commit's `CHANGELOG.md` section, for the operator to review before
publishing — never an extract-and-curate-by-hand step handed back to them.

**Portability.** `<version>` resolves against the TARGET project's own backlog release tags
(`→ <version>` headings) and git tags — never keel's own release-plan table. A6's cross-run record is
per-project; use your own project's location, keel's `private/audit/RUNS.md` is keel's instance only.
Outside keel, invoke `tools/delta-audit/derive.sh` via the installed keel checkout's path, not the
target repo's own tree.

**What this command is not.** No new procedure — `docs/delta-audit.md` is the mature source and stays
the single point of truth; a rewrite here would only drift from it. No whole-tree dispatcher (that's
[`docs/drydock.md`](../docs/drydock.md)'s job). No automation of the legs themselves — the session
prompts in §9 stay copy-paste, per the doc.

**DELEGATION RUN inside a managed release:** wrap duties are centralized — this session does NOT run
`/wrap` and does NOT write any log/backlog/memory; the release manager owns all bookkeeping, per its own
brief. Standalone runs (no manager) close through the operator as usual.
