# Changelog

All notable changes to Keel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). It is an experimental
probe, so pre-1.0 minor releases may still carry breaking changes.

## [Unreleased]

### Changed

- **The impact-scoring ledger (`ledger.md`/`evidence.md`/`impact-events.log`) no longer lives inside a
  consuming project's own working tree** (dir #251). It moved to an external store,
  `$KEEL_HOME/.keel/impact/<project-id>/`, keyed by the project's main-checkout physical path — the
  same shape KB.16 already used to fix the identical failure class for `kb-memory`. `keel-impact.sh
  enable` now creates nothing inside the project tree (no `.keel/` marker, no `.gitignore` line, and
  the old "commit .keel/ledger.md and .keel/evidence.md" advice is retracted); a linked worktree
  resolves to the identical store entry as its main checkout, closing the whole worktree-divergence
  bug class dir #181 patched around (dir #181 closes as subsumed — this ticket removes the
  architecture that made its bug possible). `add`/`rollup` on a never-enabled repo now refuse with a
  named message instead of the old silent fallback onto Keel's own `docs/keel-impact.md`. A new
  `keel-impact.sh migrate [dir] [--dry-run]` subcommand sweeps a legacy in-tree copy (main checkout +
  every linked worktree) into the store: untracked sources are merged in and removed; a tracked
  source (found live on two adopter repos, which had committed Keel-internal scoring data into their
  own git history) is left in place with the remediation choice printed, never touched automatically.
  `doctor.sh`'s `W-EVENTLOG-TRACKED`/`W-KEEL-SPLIT` WARNs collapse into one `W-KEEL-LEGACY`, naming
  `migrate` as the fix. `tools/secret-guard/secret-scan.sh` changed too: it is vendored (copied whole
  into each consuming repo's hooks dir) and cannot `source` the new shared `tools/lib/impact-store.sh`,
  so it carries a small inline copy of the log-path resolver instead (option (a) — keeps the vendored
  file count unchanged; a byte-identical-output sync test in `tests/test_secret_guard.sh` guards
  against drift). **Every already-vendored copy on the fleet is stale until re-vendored** — until then
  it still resolves the pre-#251 way (a `.keel/` marker only), so its guard events keep landing in the
  project tree rather than the store.
- `docs/delegation.md`, `docs/drydock.md`, and `docs/delta-audit.md` fold in method lessons from the
  v0.7.0 delta audit retro (dir #231). Three of the seven lessons the retro named were already seeded
  into `docs/delta-audit.md` by dir #207 and are pin-tested here rather than reintroduced; a fourth (a
  stopping-rule citation) was deferred until dir #230's doctrine doc existed, and lands with it in the
  Added entry below. `docs/delegation.md`
  gains two new generalized sections: **Blind-then-reconcile**, a reusable two-phase verifier shape (an
  independent blind pass, then a reconciliation section against the worker's own report) instantiated by
  the delta audit's diversity-leg pattern; and **Execute the claim, don't re-read it** — a comment or
  contract note describing behavior is a claim, not evidence, generalized from `docs/delta-audit.md`
  §4 rule 3's own worked incident (dir #225) rather than left as a drydock-only special case (a gap
  a `/simplify` altitude review caught: the first draft generalized the reconcile lesson correctly but
  bolted this one onto `docs/drydock.md` alone, in four places, none pointing back to the rule or the
  doc it originated in). `docs/drydock.md`'s auditor rails gain a fifth rule stating and citing that
  generalized section rather than re-narrating its incident; `docs/drydock/auditor.md` and
  `docs/drydock/verifier.md` keep their own self-contained copies of the rule, since those are prompts
  handed to an agent that can't be expected to dereference a doc mid-session. `docs/delegation.md` also
  gains a **Disclosures** section naming the one-canonical-text-plus-pointer rule for any operator-facing
  caveat restated across surfaces — scoped explicitly to what this pattern's own runs produce (a
  verifier's `known` pointer, a fix queue's residual note, a run's durable-output summary), cross-linked
  to `FRAMEWORK.md`'s existing Single-source-of-truth / sync-smell rule rather than restating it
  standalone (a `/simplify` reuse-review catch), and stated alongside an explicit carve-out for the rails
  block's own deliberate verbatim-copy-plus-drift-test discipline, so the two don't read as contradicting
  each other. Both new sections sit right after "The generic phase skeleton" (a `/code-review high`
  finding: an earlier placement right after "Roles" forward-referenced the skeleton three sections
  early), and the phase skeleton's own step 3 now points forward at Blind-then-reconcile, closing what
  had been a one-way link. That same review pass also caught the "Execute the claim" lesson citing the
  wrong ticket throughout (`dir #223/#224` — two unrelated cross-vendor findings from the same audit)
  instead of its real source, `dir #225` (delta audit S8 blind pass F1); fixed in `docs/delegation.md`,
  `docs/delta-audit.md`, and `docs/drydock.md` alike, and `docs/delta-audit.md`/`docs/drydock.md`'s own
  restatements of the rule were trimmed to bare pointers at the same time, since a `/simplify` pass and
  the same review both separately flagged the rule being independently restated in five places with no
  drift test as the exact "keep in sync" pattern the new Disclosures section itself warns against. All
  seven lessons are pin-tested across `tests/test_delegation_doc.sh`, `tests/test_drydock_doc.sh`, and
  `tests/test_delta_audit_doc.sh` — each
  new pin verified live to fail against the pre-fix docs.
- `docs/delta-audit.md`, `docs/release-audit.md`, and `docs/drydock.md` wire the three remaining
  verification-economics decision points dir #230's own PR left unwired (dir #270). `delta-audit.md`
  §8's tag-ready bar now says explicitly that it is a coverage check, not the doctrine's Clause A
  stopping rule — a run can satisfy every ledger-completeness bullet while still owing a diverse leg's
  second silent round. `release-audit.md` phase 2's "file tickets" step now cites the doctrine's
  filing bar, so a synthesis pass doesn't ticket every sub-bar finding the way dir #85's campaign did.
  `drydock.md` phase 7 step 1's review-history entry now uses the doctrine's six-field run profile as
  its field list instead of an ad hoc one. A fourth gap dir #270 found separately — fields 5 (per-leg
  cost) and 6 (induced/original) were defined only as verdict-time fields in `run-record.md`'s stub,
  with no upstream capture step telling a session to mark them during the run — is closed in
  `delta-audit.md`'s Protocol (rule 6 now marks each finding `induced`/`original` as it's written) and
  its roles section (the orchestrator now tallies per-leg cost as each leg completes); `drydock.md`
  phase 7 step 1 points at the same discipline (dir #276 makes that pointer land somewhere a spawned
  session actually reads — see below). Pin-tested across `tests/test_delta_audit_doc.sh`,
  `tests/test_release_audit_doc.sh`, and `tests/test_drydock_doc.sh`.

### Added

- **[`docs/verification-economics.md`](docs/verification-economics.md) — when to stop auditing, what
  to file from a run, and how to tell whether the verification method is improving** (dir #230). The
  three audit docs (`docs/drydock.md`, `docs/delta-audit.md`, `docs/release-audit.md`) each say how
  to *run* a pass;
  none said when a pass is *done*, so the stop rule and filing bar existed only as prose inside a
  gitignored backlog ticket that `docs/delta-audit.md` cited by a section anchor resolving to nothing.
  The doc replaces the founding claim it was specced from rather than restating it: "severity-weighted
  findings-per-token, falling monotonically" is retired, not weakened — its denominator was never
  recorded by any run, and its shape is contradicted by the newer of the two datasets. What replaces
  it is a **two-axis** premise: convergence exists in *class space across runs*, and does not exist in
  *finding-count space within a run* (one reviewer went 9→8→7→5→5 on one document; a fresh-context
  reviewer running the **same model as the author** then found 18 on the more-reviewed state — find-rate
  tracks reviewer novelty, not artifact quality). On that premise: a stopping rule in two clauses
  (within-run: two independent diverse legs in parallel yielding no behavioural findings and no new
  classes, with "new" scoped to the registry *as it stands at that moment* so the rule is satisfiable
  on a project's first run; across-run: a known-instances-only run indicts the demotion pipeline, not
  the review count), a **filing bar** whose sub-bar findings land on a named standing line rather than
  a ticket of their own, a diversity axis reordered **fresh context → method → vendor**, a section on
  fix rounds as a measurable defect source, the shift-left ladder, a bootstrapping section for an
  adopter with no class registry yet, and a six-field run **profile** replacing the retired scalar.
  Wired into all four citers: `FRAMEWORK.md`'s "PR review" **keeps** its two signals as the per-round
  question and gains a pointer to the layer above (its "Full pass or cheap delta?" trend signal is
  rescoped to the reviewer rather than the artifact); `docs/delta-audit.md`'s two `dir #230 §N` anchors
  become links; `docs/drydock.md` cites it from four sections (the two-tiers/ratchet framing, Scope C's
  diversity paragraph, phase 6's ticketing decision, and phase 7's ratchet), and
  `docs/release-audit.md` from phase 5 and its See-also. `tools/delta-audit/derive.sh`'s
  `run-record.md` stub gains rows for the profile's four added fields, so a field the doctrine defines
  is one a run actually records. New `tests/test_verification_economics_doc.sh` (41 assertions) pins
  the doctrine invariants and one link per citer, every assertion mutation-proven;
  `tests/test_delta_audit_doc.sh`'s pin on the literal `dir #230` is removed rather than retargeted —
  both legs of that coupling are owned by the new test file, and duplicating them would give a rename
  two places to break — and `tests/test_delta_audit_derive.sh` covers the new stub rows.
  **Closes dir #258 as absorbed** — this is the only PR in which the link target exists, so it is the
  only one that could convert those citations and stay green. #258's one out-of-scope note (every
  `dir #N` in `docs/` resolves only to a gitignored backlog, so no adopter can follow one) was moved
  out to **dir #269** *before* #258 closed, rather than dying inside an absorbed ticket. Also closes
  **dir #231's item 4**, its last open dependency. Three sites where the doctrine belongs but the edit
  would change what an audit session *does* are filed as **dir #270**, and the deferred metric-harvest
  script as **dir #267** — neither is in this diff.
- `tools/self/doctor.sh` now cross-checks every `dir #N` referenced in commit messages since the
  previous release tag against CHANGELOG.md's own `[Unreleased]` section, WARNing on any ticket
  present in commits but absent from `[Unreleased]` — per-ticket, not per-file, so a PR that touches
  CHANGELOG.md for a *different* ticket still trips it. Closes the class the v0.7.0 → v0.7.1 delta
  audit found five times, three of them undetected until the audit itself (dir #237).
- `tools/delta-audit/derive.sh` mechanically derives a release delta audit's universe from git
  history (dir #207, PR1 of 2): the range's file list, a file→PR seam map, an empty-verdict ledger
  skeleton in pinned read order (seams and behaviour-with-a-rail code first, prose last), and a
  run-record stub. Promotes the one-off script the v0.7.0→v0.7.1 light run used, into a tested,
  adopter-facing tool. Its closure check — comparing the range diff against the union of every
  per-PR file list — refuses when a squash- or rebase-merged PR leaves files unattributed, closing
  the hand-derivation gap that under-counted the first delta audit's own PR total (24 vs 31) until a
  session caught it by hand. Reproduces both real prototype datasets byte-identically, verified
  live on macOS, Alpine/BusyBox, and Debian/GNU. `docs/delta-audit.md`, the doc that adopts this
  script into a full procedure, is dir #207's PR2.
- `docs/delta-audit.md` (dir #207, PR2 of 2): the full procedure that adopts `tools/delta-audit/
  derive.sh` — the 8-rule Protocol, roles and legs (including the required diversity leg, skippable
  only by an explicit operator decision, never the orchestrator's own judgment), the read-order and
  incremental-writing rule, a sizing range from two real runs, the verdict contract, copy-paste
  session prompts (each carrying `docs/delegation.md`'s rails block verbatim — dir #208 later fixed
  the sibling template set that didn't), the disclosure-only fix round, and the cross-vendor leg's
  two harness lessons. `docs/release-audit.md` phase 6 is rewritten into this doc's caller: its
  three-point mandate survives as a depth heuristic applied within the derived universe, no longer
  the rule that chooses the universe itself. `docs/drydock.md`'s "Incremental runs" section gains a
  cross-reference distinguishing its own prose-only, previous-run-baseline scope from this doc's
  release-range scope.
- `tests/test_ci_alpine_safe_directory.sh` pins `.github/workflows/ci.yml`'s alpine leg to a
  `--system` (not `--global`) `safe.directory` write ordered before `bash tests/run.sh` (dir #246).
  Nothing previously covered that one line — it's YAML, so shellcheck never reaches it, and neither
  prose-drift nor doctor.sh's shellcheck mirror reads workflow files — so reverting `--system` to
  `--global`, or reordering the write after the test run, reds nothing locally; only the alpine-busybox
  CI leg itself would go red, after the fact. Verified live: the new test goes red against a
  `--global`-reverted copy of the real file and green again once restored, plus three synthetic-fixture
  mutation cases (revert, reorder, missing write) to prove the guard itself can fail.
- `tools/drydock/inventory.sh` gains scope C: a third measured surface, whole-file shell code, over
  the identical file selection scope B already uses by default (dir #204, PR1 of 2) — the scanning
  mechanism a future code-correctness audit module plugs into. Same shape as scope A/B (a
  `DRYDOCK_SCOPE_C` pathspec override, unset-or-empty meaning the full default selection, a
  `DRYDOCK_CODE_BATCH_LINES` packing cap default ~4500), plus one new marker: `DRYDOCK_INVARIANT_PATHS`
  (default: the repo's own install/uninstall/gate/secret-guard scripts) flags a file per-line and
  per-batch-line, so a downstream orchestrator can route an invariant-bearing batch to higher review
  effort without a second query. Disabling scope C for a prose-only run uses the same pathspec
  convention as A/B — a pattern matching nothing, canonically `DRYDOCK_SCOPE_C=':!*'` — verified live
  to yield an empty scope at exit 0, not a refusal. The role template and procedure docs that adopt
  this scope are dir #204's PR2, sequenced after this one so they can cite its real shipped output
  rather than a plan.
- Drydock adopts scope C into its procedure docs, closing dir #204 (PR2 of 2): `docs/drydock.md`
  gains a "Scope C — code" section (the module's boundary vs. `/polish`'s per-PR review, its boundary
  vs. scope B, the `DRYDOCK_SCOPE_C` cadence knob and its `':!*'` disable spelling, a cost disclosure,
  a diversity-leg pointer, and the ratchet/model-effort notes `tools/drydock/inventory.sh`'s own
  header already forward-referenced), and phase 3 gains three code-specific claim classes (a dead
  helper, the lib-sourcing shadowing hazard, unpinned behavior) derived from an extended `## claims`
  contract (`defines:`/`calls:` fields) — cross-file duplication is deliberately NOT one of them,
  since code bodies never enter the claims registry; it's filed by the auditor in phase 1 instead.
  `docs/drydock/code-auditor.md` ships as the fourth role template, reusing dir #85's own module-1
  taxonomy (dead code, duplication, missing coverage, correctness) and carrying the delegation rails
  block verbatim (dir #208, closed below, later fixed the three existing templates that didn't — this
  one wasn't a fourth instance of that gap). `docs/drydock/verifier.md` gains an unconditional
  verification bar for code findings (a sandboxed execution, not just a re-read), extending its
  existing comment-triggered rule rather than duplicating it. `docs/delta-audit.md`'s §1 and
  `docs/reference.md`'s inventory-tool row, both of which called drydock "prose only", are corrected
  to name the code scope too.

### Fixed

- `uninstall.sh --dry-run`'s manifest-less heuristic listing treated a `keel/` directory or symlink at
  the home root as Keel-owned by existence alone, misreporting "would remove keel" for an unrelated
  user directory that merely shared the name (dir #233). It now checks `keel/CORE.md` ownership
  (a symlink, or a regular file carrying the `KEEL-NOGIT` token) — the same signal `install.sh` itself
  uses to recognize its own linked home. Explicitly out of scope (dir #278, dir #279): the identical
  existence-only imprecision in `home_has_keel_content()`, and the resulting duplication of this
  ownership predicate across `install.sh`/`uninstall.sh`/`tools/doctor.sh`.
- `docs/drydock.md` phase 7 said cost and induced/original-defect marks are captured *during* a run,
  not reconstructed afterward (dir #270) — but that instruction lived only in phase 7's own narrative,
  at the bottom of the doc, which the orchestrator's own session reads (it runs the whole procedure
  directly) but a spawned auditor/verifier subagent never does (it is handed only its own role-prompt
  template file). `docs/delta-audit.md`'s equivalent fix had already put the induced/original mark
  directly in its Protocol rule 6 — the report contract every spawned session binds to — leaving
  `drydock.md`'s version inconsistent with its own sibling doc (dir #276). `docs/drydock/verifier.md`
  now carries the operative instruction itself (mark every `accepted` finding `induced` or `original`,
  citing `docs/verification-economics.md`'s field 6, in the concrete form `accepted — induced` /
  `accepted — original`); `docs/drydock.md`'s roles section ties per-phase cost tallying to the
  orchestrator's own bookkeeping, since the orchestrator needs no separate wiring to read it. Pin-tested
  in `tests/test_drydock_doc.sh`, mutation-verified (red without the fix, green with it).
- `tools/lib/nonneg-int.sh` (dir #196) claimed to be "the ONE non-negative-integer sanitizer, shared
  by every tool that clamps a numeric env-var/arg override", but two sites still carried their own
  inline copy of the digit-shape-only guard it exists to replace (dir #242). `tools/self/doctor.sh`'s
  `pending_max_commits` now calls `sanitize_nonneg_int`; `tools/keel-impact.sh`'s `require_count` now
  calls `_nonneg_int_valid` and, as a result, gains a magnitude cap it never had — a 10+ digit
  all-digit `--<flag>` value that used to pass silently now exits 2 (a fix, not a regression). The
  coverage ratchet (dir #142) also reported the lib "test-covered" on nothing more than a bare
  filename mention inside a `tests/*.sh` **comment** (leading OR trailing); the ratchet now strips
  both comment shapes before counting a mention as coverage, and `tests/test_nonneg_int_lib.sh` gives
  the lib the direct unit coverage the repo's other shared libs already have. An operator-run
  cross-model second-opinion review of this fix caught a real bug in an earlier draft: the
  comment-stripping used `grep -v`, which exits 1 (no matching lines) when a `tests/*.sh` file is made
  entirely of comment lines — under `tools/self/doctor.sh`'s `set -e`, that silently aborted the whole
  self-check with no error message, indistinguishable from every later check simply never having run.
  Fixed by switching to a `sed` substitution, which never fails on all-comment input; both the crash
  and the trailing-comment loophole now have dedicated regression fixtures.
- `docs/reference.md`'s `tools/delta-audit/derive.sh` row called the procedure that adopts the script,
  `docs/delta-audit.md`, "not yet shipped — a separate, sequenced follow-up" (dir #256) — true when
  dir #207's PR1 wrote it, false the moment PR2 shipped the doc in the same release; PR2's own edit
  list owed this file and skipped it. Dropped the stale parenthetical and linked the doc instead,
  matching the shape `docs/drydock.md` already uses in this same table (an inline link inside its
  tool's row, no dedicated row of its own) — `docs/delta-audit.md` needs no new row either. Pinned on
  both halves in `tests/test_delta_audit_doc.sh`: the stale claim is gone, and the row links the doc.
- `tools/drydock/inventory.sh`'s `trap 'rm -rf "$scratch"' EXIT` silently reported exit 0 for a genuine
  `set -u` "unbound variable" abort (dir #264) — verified live on this repo's target bash (3.2.57) that
  `$?` is already lost by the time an EXIT trap runs for that one failure class specifically, so even
  the seemingly-obvious `trap 'st=$?; ...; exit $st' EXIT` fix does not work either. Replaced with an
  `ok` completion marker, set only on the script's true last line, plus a named `on_exit()` function
  (a named function avoids a shellcheck SC2154 false positive the inline form triggers) that forces a
  nonzero exit whenever the script didn't genuinely reach that line. `refuse()`/`die_args()`'s own exit
  codes (2/3) and an ordinary `set -e` command failure were already reporting correctly and are
  unaffected. Pinned with a regression test that extracts the real fix from the script (not a
  hardcoded copy) and runs it in a harness that reproduces the crash, mutation-tested against the
  pre-fix file. The same bare-trap hazard was found live and reachable (not just latent) in
  `tools/delta-audit/derive.sh` via `DELTA_HISTORICAL`/`DELTA_INVARIANT_PATHS` — filed as dir #265
  rather than expanding this fix's scope.
- `tests/test_drydock_doc.sh`'s check on the audit-file contract shared by `docs/drydock.md` and
  `docs/drydock/auditor.md` pinned only 3 of the contract's 6 fields, and only as independent
  substring presence — never that the two copies actually agree (dir #209). Mutation-proven: three
  injected drifts, including deleting a contract line outright, all left the 36-check suite fully
  green. Replaced the per-field loop with a `check_block_equal()` helper that block-extracts both
  copies (`awk` between the contract's opening and closing anchor lines) and diffs them, verified
  against the same three mutations plus the anchor-line-deleted-from-both-sides edge case. The
  pre-existing rails-block check further down the same file (`code-auditor.md` vs `delegation.md`)
  now shares this helper too, instead of its own near-duplicate inline comparison.
- Three prose-only drifts in `docs/drydock.md` from the delta audit (dir #210): **"Four conditions,
  one rule"** under-counted `tools/drydock/inventory.sh`'s refuse conditions — 11 call sites, but
  only 7 distinct conditions once the three per-scope enumeration failures and the two
  unrepresentable-path (tab/newline) sites are each counted once. Rather than commit to a number
  that drifts every time a guard is added or grouped differently, dropped the definite count and
  pointed readers at the script's own `refuse` call sites, which `tests/test_drydock_inventory.sh`
  already pins in full. The **run-cost table**'s "Whole run | ≈6.1M subagent tokens" row
  didn't reconcile against its own itemized rows; re-derived from the source record
  (`~/.claude/REVIEW_HISTORY.md:480-481`), which itself only reconciles to ≈4.66M
  (auditors 3.56M + verifiers 0.63M + cross-file pass/re-check 0.47M) against its own stated ≈6.1M
  total, and split into a new "Cross-file pass + re-check" row. The source's own "+ orchestrator
  turns" clause is not usable to explain the ~1.4M gap without contradicting the roles table three
  rows up (the orchestrator runs as a real session, never a subagent, so its turns can't be part of
  a "subagent tokens" figure) — so the Whole run row now discloses the gap as an unreconciled
  residual in the source record rather than inventing an attribution for it. The
  **roles table**'s Verifier "May touch" cell named only the `verdict:` lines, omitting the
  `verifier:` footer line phase 2 also requires — same shape PR #219's review already fixed once in
  this table.
- Three more exhaustive-enumeration drifts from the delta audit, fixed together as one batch (dir
  #208, dir #211, dir #212 — [PR #267](https://github.com/rockerlabs/keel/pull/267)). `docs/delegation.md`
  promises its worker-rails block is reproduced verbatim in every worker and verifier prompt this
  pattern generates; `docs/drydock/auditor.md` and `docs/drydock/verifier.md` didn't carry it
  (`code-auditor.md` already did, from dir #204) — now block-diffed against the canonical text
  (mutation-proven), never a substring pin. `docs/drydock/fixer.md` is a mutator, not a
  worker/verifier — per `delegation.md`'s own Mutator template, it gets only the `DELEGATION RUN:`
  marker line, not the full read-only rails, which would misdescribe a session that commits and opens
  PRs. `commands/wrap.md`'s FLAG description named only one of `tools/branch-cleanup.sh`'s two FLAG
  reasons and never named `--live-hours`, the flag governing the other — now names both.
  `commands/init-project.md` enumerated two registration-failure reasons as exhaustive; a third
  (`INSTANCE.md` present but missing a Projects table) was silent because `tools/init-project.sh`
  discarded `register-project.sh`'s stderr — now captured and surfaced in the follow-up message, and
  the doc names the third reason. A related drift the fix exposed but didn't cause —
  `docs/delegation.md:233` states the verbatim-rails scope more broadly than `:189` does — is filed
  separately as dir #272.
- `tools/self/doctor.sh`'s dir #237 check ("commit `dir #N` tickets vs CHANGELOG.md's `[Unreleased]`
  section") extracted ticket references with a bare `grep -oE 'dir #[0-9]+'`, which only matches a
  fully-spelled reference — a shorthand commit-message list like "dir #208, #211, #212" (one `dir`
  prefix, then bare `#N` for the rest) left every trailing ticket outright invisible to the check's own
  candidate set, not merely unflagged (dir #273; the felt case was this repo's own PR #267 commit,
  which silently dropped #211/#212). Replaced both call sites (the commit-range scan and the
  `[Unreleased]`-body scan) with a shared `_extract_dir_tickets` helper that first captures the whole
  comma/whitespace-joined run starting at a `dir #N` anchor, then pulls every `#N` out of it — so a
  shorthand list, a fully-spelled list, and a lone reference all resolve to their complete ticket sets.
  The helper also ends its own pipeline in `|| true`, matching the self-contained-under-`set -euo
  pipefail` convention the neighboring `_release_tag_versions` helper already uses — the earlier draft
  relied on both call sites to guard it externally (which they do today), but that left it a latent
  trap for any future caller that doesn't (found by an operator-run `/code-review medium` pass).
  Mutation-proven: a fixture citing a three-ticket shorthand list with none of them entered flags all
  three (confirmed red against the pre-fix extraction, green after); a second fixture with all three
  properly entered under `[Unreleased]` stays silent. **Narrower than "fixed", stated precisely:** the
  extraction now recognizes a comma/whitespace-joined run, and only that — a list joined by "and", `;`,
  `/`, or a numeric range (`dir #104-107`) still drops every trailing ticket the same silent way gap 2
  did, and every one of these shapes has real precedent in this repo's own history: the commits closing
  dir #100-103 and dir #104-107 (range), and — found by an operator-run `/code-review medium` pass on
  this very PR — this repo's own commit `1515d7a`, whose title is itself an unrecognized slash-separated
  instance ("...dir #208/#211/#212..."). Neither the mutation proof above nor the new fixtures exercise
  any of these shapes. Left as a
  named residual, filed as dir #274, rather than folded in here, to keep this fix mechanical and
  scoped. Scoped to this one gap only — the ticket's other, harder gap (a bare mention anywhere in
  `[Unreleased]` satisfying the check even when it's a stale citation, not a fresh entry) is left for a
  separate design pass, per the ticket's own stated preference.

## [0.7.1] — 2026-08-21

The audit-tail release. v0.7.0 shipped with a named list of six residuals it deliberately did not
hold its tag for; this release closes four of them rather than adding surface. Fixed: the
fenced-example collision that could resolve the wrong introducing commit (dir #194); the second
`head -1`-under-`pipefail` construct (dir #195); the digit-shape numeric guard that stood duplicated
and unfixed across seven files, now one shared `tools/lib/nonneg-int.sh` (dir #196); and the only
behaviour-level one of the six — `uninstall.sh` no longer reads a stray same-named context file as
proof of a live sibling install (dir #190). The two that remain are not open work: one is the
release-in-preparation window, an accepted design bound rather than a defect, and the other is a
warning that the v0.8.0 gate rewrite removes outright (dir #201, dir #186).

Two more fixes came from that same review round rather than from the disclosed list: the `git log -S`
pickaxe that could abort a whole `self-check` run on an unborn HEAD (dir #213), and `--dry-run` over
a manifest-less install now listing heuristically instead of refusing (dir #228, which deliberately
reverses part of v0.7.0's own "Changed" entry).

Alongside them, the release machinery this project leans on got its own pass —
`tools/changelog-section.sh --edit` folds the by-hand release-note compose recipe into tested code
(dir #189, dir #223), and `docs/release-audit.md` phase 7 now names the open-floor recheck as a step
instead of leaving it to a human happening to notice a passing test's note (dir #202, dir #203). And
the largest coverage hole v0.7.0's audit named is closed at the source: the alpine-busybox CI leg
installs `jq`, so the gate tests run there for the first time — `tests/test_pre_pr_gate.sh` went from
**2 to 469 assertions** on that leg (dir #220), and the leg's "dubious ownership" workarounds were
replaced by one container-level fix (dir #191).

Known issues: four residuals ship unfixed, each with an open ticket, and none of them changes what
the tools do. Two are in `tools/self/prose-drift.sh`, which is keel-self-maintenance and is never
installed for adopters: it hard-GAPs a link whose anchor names a heading containing a non-ASCII
**letter**, because its slugger strips bytes above ASCII while GitHub keeps them (em-dashed headings,
which this project uses everywhere, are unaffected); and it now aborts with git's raw error, instead
of degrading, when pointed at a directory that is not a git repository — an input its own header
still advertises as supported (both: backlog dir #240). Third, five test assertions were found by
live mutation to pin a weaker proxy than their names promise, among them the sweep that checks no
shipped file spells a gate marker, which passes whenever `git grep` fails for any reason; the shipped
behaviour is correct at every site, so these are gaps in the guards rather than defects (backlog
dir #239, with dir #238 for the standing mutation check that would have caught them). Fourth, the
`uninstall.sh` warning described under dir #190 above (backlog dir #248).

On how these were found, since it bears on how much the list is worth: three of the four came at
least in part from a cross-vendor review layer, run after this project's own same-family passes had
already read the same files and called them clean. One of the three was found by both layers
independently.

### Added
- **`tools/changelog-section.sh --edit <version> <notes-file>`** (dir #189): folds the release-note
  compose recipe — extract, open in `$EDITOR`, copy on success only — into tested code instead of
  the hand-typed shell prose that used to live in `docs/publishing-checklist.md` §4 (every real bug
  found across dir #162's own review rounds lived in that untested prose, never in the tested
  extraction code). `docs/publishing-checklist.md` §4 collapses to one command.

### Fixed
- **`docs/loading-and-cost.md`'s `commands/*.md` row no longer hides `commands/polish.md`'s real size
  behind an open `~250–1,450+ each` ceiling** (dir #203): `polish.md` measures ~15,074 tok, ~7x the
  next-largest command, and the trailing `+` made the row's own understatement unfalsifiable by
  `tests/test_doc_figures.sh`. Split into a tightened `~250–2,100+ each` ordinary-command range plus a
  dedicated `commands/polish.md ~14,000+` open-floor row, each independently pinned by the test.
- **`docs/release-audit.md` phase 7 now names re-checking `docs/loading-and-cost.md`'s open-floor
  figures as an explicit release step**, at the "cut, land" moment before the tag (dir #202): the
  `CHANGELOG.md` floor had been hand-bumped five releases running — 25k → 40k → 50k → 60k → 70k —
  always triggered by a human happening to notice `tests/test_doc_figures.sh`'s non-failing drift
  `note` during a release pass, never by a test failure.
- **`tools/changelog-section.sh` now honors the cross-tool `-h`/`--help` and exit-code contract**
  its two sibling tools from the same release already follow (`tools/drydock/inventory.sh`,
  `tools/self/prose-drift.sh`): `-h`/`--help` prints usage and exits 0, and a malformed-invocation
  error exits 2 rather than 1 (dir #223). A data miss (no matching CHANGELOG section) still exits 1.
- **Five bugs found by an operator-run `/code-review high` pass on dir #156's own diff, plus two
  cheap passengers found by a delta audit** (dir #213/#194/#195/#196, dir #219/#215). `doctor.sh`'s
  `_pending_release_intro_commit()` `git log -S` pickaxe could abort the whole run silently on an
  unborn HEAD (fresh `git init`, an orphan branch, a `filter: blob:none` partial clone with an
  unreachable promisor) — guarded with `|| true`, and `filter: blob:none` dropped from the CI
  `self-check` job, whose own rationale for it (blob content never read) stopped being true once
  that pickaxe landed (dir #213). The same pickaxe had no concept of "inside a fenced code block", so
  a fenced CHANGELOG.md example reusing a real version heading could resolve the wrong introducing
  commit — fixed by checking each pickaxe candidate's fence-blanked content against its parent's,
  walking to the next-newest candidate on a fence-only occurrence change (dir #194, an open fork the
  operator resolved mid-session). The dead-slash-command-reference scan's `grep -F ... | head -1` carried
  the same SIGPIPE-under-`pipefail` shape dir #156 had already fixed elsewhere in the file — replaced
  with a here-string `grep -m 1` (dir #195). The digit-shape-only numeric env-var guard was duplicated,
  unfixed, across six other files; swept, then consolidated into a shared
  `tools/lib/nonneg-int.sh` (`sanitize_nonneg_int` / `_nonneg_int_valid`), each call site passing its
  own digit-cap (`tools/branch-cleanup.sh`'s raw unix-epoch mtime comparison needs 14, not the usual
  10) (dir #196). Passengers: a stray `Deleted tag ...` line no longer leaks into test suite output
  (`git tag -d` now redirects to `/dev/null`, dir #219); three stale self-referential figures/pointers
  in delta-added comments corrected, comment-only (dir #215).
- The alpine-busybox CI leg now installs `jq`, so `tests/test_pre_pr_gate.sh` and its
  install-side siblings (`test_install_pre_pr_gate.sh`, the gate half of
  `test_install_manifest.sh`) actually run there instead of skipping cleanly for want of it. Before
  this, "alpine-busybox: success" was not evidence about `tools/pre-pr-gate.sh` — the single
  largest shell surface in the repo — on its one non-GNU CI leg (dir #220).
- **`uninstall.sh`'s `artifact_shared_with_other()` no longer reads a stray same-named context file, or
  the ordinary both-modes home's own surviving one, as proof of a live sibling install** (dir #190,
  0.7.0's sixth Known-issue). Its no-usable-other-manifest fallback now requires `has_keel_rails` on the
  other mode's context file OR a manifest-independent sentinel (`.keel/foreign-core.<mode>`, written by
  `install.sh` whenever it detects a foreign-core install and cleared otherwise) — plain existence alone
  no longer counts. The ordinary both-modes home (dir #124) is removable in sequence again, as it was in
  v0.6.1 — with one caveat this note owes you: the second uninstall still announces each shared artifact
  as an unconfirmed guess (`no evidence CLAUDE.md is gone … removing anyway`) before removing it, because
  the first uninstall stripped the sibling context file's rails and an ordinary install leaves no
  sentinel. It removes the right files; the warning's premise is wrong and its suggested `install.sh`
  recovery would undo the mode you just removed. Ignore it on this flow (backlog dir #248).
  dir #150's original foreign-core fix (a genuinely unmanifested foreign-core install
  must not have its shared half stripped) stays intact via the sentinel. Pinned by five new
  `tests/test_uninstall.sh` fixtures — B23 (the regression), B24 (the stray-file scenario), B25A (the
  sentinel's own clear branch on a fresh, non-foreign re-install), B25B (both modes foreign-core,
  uninstalled in sequence) — alongside the pre-existing B22 (dir #150's own foreign-core case). The
  checkout-side ledger's own pruning (near uninstall.sh's manifest housekeeping) now also counts a
  surviving `foreign-core.*` sentinel, not just a surviving manifest, before dropping a home — an
  operator-run `/code-review high` pass live-reproduced the ledger silently losing track of a still-live,
  sentinel-only-protected install otherwise. **Named residual, not fully closed:** the sentinel is
  forward-only — an install placed by a Keel checkout that predates it has neither a sentinel nor rails,
  so if its manifest is later lost, this fallback still can't tell it apart from an unrelated stray file
  and — unlike every other ambiguous-ownership case in this file — resolves that ambiguity by stripping
  rather than refusing or asking (the same `/code-review high` pass live-reproduced this too). No signal
  on disk can close it for pre-existing installs without new evidence going forward; re-running
  `install.sh` for that mode records one. Filed as a residual to `uninstall.sh`'s own header, not a
  separate ticket, since it's the direct continuation of dir #190/dir #150's own arc.
- **`uninstall.sh --dry-run` over a manifest-less install now falls through to a heuristic advisory
  listing instead of refusing** (dir #228, operator-decided; reverses part of 0.7.0's "Changed" entry
  above, which shipped the refusal deliberately as an open fork). A dry run removes nothing, so the
  refusal's own "can't guess what to remove" rationale doesn't apply to it; the listing is explicitly
  labeled heuristic (content-sniffed, not manifest-confirmed) and now also says outright that a real
  (non-dry) run in the same state refuses rather than removing — dropping `--dry-run` here does not
  perform the listed removals (an operator-run `/code-review high` pass live-reproduced the two
  disagreeing). The real, non-dry refusal is untouched. Pinned by `tests/test_uninstall.sh`'s new B15D
  fixture.
- **`commands/polish.md`'s dated verification claim about `disable-model-invocation` now reads as a
  last-checked marker rather than a freshness guarantee** (dir #221), and leans on the existing
  event-based Revisit trigger for staleness instead of implying a calendar cadence that never existed.
  Adopter-visible: `commands/` is installed into every keel home.
- **`tools/self/prose-drift.sh`'s signal 2 stops passing links a real reader would find broken**
  (dir #217, dir #218, dir #224). Dead in-document `#anchor` links were an uncovered class entirely —
  the signal now validates them against GitHub-flavored heading slugs. Link resolution is
  sibling-relative only: an undocumented repo-root fallback used to call a link green that GitHub
  itself resolves to nothing, while GitHub's own leading-slash convention (`[x](/CHANGELOG.md)`) gets
  an explicit rule instead of being swept into the removal. And the extractor no longer truncates at
  the first `)`, so a target with one level of balanced parens or percent-encoding stops false-GAPping.
  *Known limitation, see Known issues below: a heading containing a non-ASCII letter false-GAPs.*
- **The alpine-busybox CI leg no longer works around "dubious ownership" per call site** (dir #191).
  The leg bind-mounts the whole checkout, so every git call any script makes inside it was blocked
  unless configured otherwise — previously patched with narrow `|| true` guards at individual call
  sites. The container now does `git config --system --add safe.directory '*'` once, before any test
  runs. **`--system` is load-bearing and a future change must not "simplify" it to `--global`:**
  `tests/lib.sh` redirects `GIT_CONFIG_GLOBAL` per test file, which shadows a `--global` write
  entirely, so only `--system` reaches every git call in the suite. As part of the same cleanup
  `tools/self/prose-drift.sh` lost its own `|| true` guard — see Known issues.
- **`tests/run.sh` no longer reports a false FAIL on a real checkout** (dir #222). One
  `tests/test_pre_pr_gate.sh` assertion scanned the working tree with `grep -r` rather than tracked
  files, so any gitignored file that happened to quote a gate marker — an operator's own backlog or
  notes — turned the suite red while CI and clean worktrees stayed green. It now uses `git grep`.
- Two `tests/test_keel_impact.sh` assertions that named coverage they did not have were replaced with
  fixtures that actually exercise the code, mutation-proven (dir #216). Test-internal; no shipped
  behaviour changes.

## [0.7.0] — 2026-08-20

The drydock release. Two arcs, plus the end of a migration window. First arc: **drydock** — a named,
reproducible whole-tree prose audit — went from an idea to a run to a shipped capability inside this cycle: run 1
swept 33 markdown files and fixed 44 findings (dir #165), the procedure and its tooling shipped as
`docs/drydock.md` + `tools/drydock/inventory.sh` (dir #170), and the orchestration pattern behind it
was generalized into `docs/delegation.md` (dir #171). Its **ratchet** — the rule that each run makes
the next one cheaper by demoting a finding class into a standing check — then produced four of them:
sweep-outcome coherence across the four red-flag surfaces (dir #166), derived-figure arithmetic and
parallel-table parity in the docs (dir #167), a live-run diff against `examples/README.md`'s console
transcript (dir #168), and `tools/self/prose-drift.sh`, which promotes run 1's throwaway sweep into
`tools/self/doctor.sh` (dir #169). Second arc: **release and review bookkeeping**. The CHANGELOG↔tag
check's release-in-preparation allowance is now bounded by commit distance, so a forgotten tag stops
reading green forever (dir #156); `tools/changelog-section.sh` makes cutting release notes one command
(dir #162); a step-5 receipt can name every review that saw the commit and warns when a later round
drops one (dir #158, dir #161); and `/polish` finally documents its in-run convergence path (dir #177).
And the manifest migration window that v0.6.1 opened is closed: every transitional
`KEEL-LEGACY-NOMANIFEST` fallback is gone — `uninstall.sh` and `tools/doctor.sh` now require an
install manifest rather than re-deriving state heuristically — while three audited sites that turned
out not to be transitional at all were deliberately kept and relabeled (dir #150). Alongside both
arcs and that closure, `docs/parallel-sessions.md` — the adopter-facing playbook for running two or
more agent sessions against one repo (dir #172).

Known issues: six residuals ship unfixed, deliberately not held for the tag — five carry open
tickets, and the first is a recorded design bound rather than a ticket. The release-in-preparation
allowance is now **bounded, not closed** — inside its 40-commit window a forgotten or deleted topmost
tag still reads as a green "release in preparation" line rather than a GAP. That window is the
operator-chosen accept recorded in dir #156, which is closed; nothing tracks it as open work. Three
more came out of that same fix's own review: its `git log -S` pickaxe searches raw file history
rather than fence-filtered content, so a future fenced `## [x.y.z]` example could resolve the wrong
introducing commit (backlog dir #194); a second `| head -1`-under-`pipefail` construct of the shape
that fix removed still stands elsewhere in `tools/self/doctor.sh` (backlog dir #195); and the
digit-shape-only numeric env-var guard it added is duplicated, unfixed, in six other files (backlog
dir #196). Of those three, dir #195 is the one to weigh: it is not documentation debt but a latent
whole-run abort — an unguarded `head -1` inside a `var=$(…)` assignment under this script's own
`set -euo pipefail`, the identical shape dir #156 reproduced crashing. dir #194 is latent and
unreachable on today's tree; dir #196 is single-source-of-truth debt. The fifth residual: dir #161's
add-on-drop warning cannot see the path dir #177 blessed — an in-run `--amend`
round retires nothing, so the check never compares against this run's own earlier step-5 receipt, only
against whatever the last retired round held. An add-on gained and dropped inside one run therefore
goes unannounced, and when the older round happens to carry it the warning fires about that round
instead — wrong baseline either way. A third outcome neither of those covers: an in-run `--amend` of
the very commit the last retirement stamped as `base-sha` orphans that sha, so the lineage guard
discards the comparison entirely and the check is SILENT on that path too, rather than firing the
"false catch" about an older round. All three are verified live — the third only after this entry first
claimed the pair was exhaustive. All three are documented in `commands/polish.md` and in the check's own
header rather than fixed in code, because v0.8.0's gate-surface rewrite removes the warning outright
(ticketed as backlog dir #201 and dir #214; the rewrite is dir #186). The sixth is the only
behaviour-level one, and Fixed carries its account: `uninstall.sh` now reads any file merely sharing the
other mode's context filename as evidence of that install. The trigger is the ORDINARY both-modes home
dir #124 supports, not a stray `AGENTS.md` nobody installed. Uninstall never deletes the context file,
by design, so removing the first mode always leaves the other mode's `CLAUDE.md`/`AGENTS.md` on disk;
the second uninstall's fallback then reads that survivor as proof of a live sibling install and keeps
the shared half (`FRAMEWORK.md`, `PRINCIPLES.md`, `bin/keel`) permanently. The advised
re-record-then-uninstall recovery loops instead of removing, and the printed reason ("shared with the
claude install") is false at a point where no manifest for that mode exists anywhere in the home. That
is a regression on a supported flow: v0.6.1 completed the same sequence cleanly, A/B-proven against the
tag. It ships anyway because it errs toward keeping files rather than stripping ones another install
still needs, and every kept artifact is named in the run's own output (backlog dir #190).

### Added
- **A step-5 `/polish` receipt that drops a prior round's review add-on now warns on stderr, naming
  it** (dir #161, PR #236). Closes a gap dir #158 left open: the receipt could already SAY a combined
  review add-on set (`agent:<level>+operator-run,second-opinion`), but nothing pressured a session to
  keep saying it after a fix commit — a re-typed-from-memory receipt could silently lose one, the
  dir #155 incident. The check fires only at the ordinary `receipt polish.5-review` write path (never
  `--recover`, never the gate's own allow/deny decision), compares the immediately-prior round's
  add-on set against the new one, and never affects the write or the exit code either way — advisory
  only, since only the session knows whether a fix commit genuinely removed the reviewed work.
  `commands/polish.md` step 5 now also states the warning must be actively read, not skimmed past, and
  the check leaves a durable trail via the existing impact-log primitive alongside its stderr print.
- **`tests/test_sweep_outcome_coherence.sh`** (dir #166, drydock run 1 ratchet). CORE.md's Persist
  rail, `commands/wrap.md`, `commands/global-review.md`, and `FRAMEWORK.md` each restate, in prose,
  the set of outcomes a red-flag-sweep finding can land in (a backlog ticket, a committed/promoted
  rule, the `LEARNINGS.md` staging tier, the `IDEAS.md` staging tier, or an explicit drop) — manual
  coherence across four independent surfaces provably does not hold: phase 6's closing re-check
  (`private/audit/phase6-recheck.md`, finding P6-1) found `commands/global-review.md` still missing
  the rule outcome — PR #213 had fixed a different gap in the same paragraph (a missing `IDEAS.md`
  outcome) without catching this one. The new test extracts each surface's own sweep
  paragraph and checks it names all five canonical tokens, extended (P6-3) to two more files that
  describe their own place in the sweep (`IDEAS.md`, `templates/LEARNINGS.md`) after PRs #212 and
  #213 landed individually-correct fixes that contradicted each other within a day. Fixed P6-1 in the
  same PR (`commands/global-review.md` now names the rule outcome). Mutation-tested: an independent
  agent review and a cross-model second opinion both found the initial token patterns too loose —
  `commands/global-review.md`'s sweep paragraph was immediately followed, same paragraph, by an
  unrelated `LEARNINGS.md`-pruning sentence that incidentally contained the words "LEARNINGS.md" and
  "drop", so removing the real outcome mentions didn't red the suite. A later `/code-review` pass found
  the test-side truncation this was first fixed with was itself a bandaid — `commands/global-review.md`
  was the only one of the four surfaces with an unrelated sentence trailing its outcome paragraph with
  no blank line, so the paragraph is now split in two (matching the other three surfaces' shape) and
  the shared extraction helper handles all four surfaces uniformly, no per-file truncation logic
  needed. The P6-3 header checks also moved from a fixed 10-line window to an anchor-based extraction
  (everything before the first `## ` heading) after a mutation showed a legitimate header-prose grow
  could push the real content out of a fixed window.
- **`docs/parallel-sessions.md`** (dir #172, captured after four independent first-person loss reports
  in one week — a deleted migration, a wiped working directory, a reset that dropped built-and-tested
  commits, and keel's own silent race on a symlinked file). A worktree gives you parallelism, not
  safety; this doc names the boundary (what's isolated per worktree and what isn't — the shared `.git`
  directory, symlinked or absolute-path files, unlinked gitignored files, out-of-tree state keyed by
  repo), a four-mode failure catalog, the rails (five linked out of `CORE.md`/`FRAMEWORK.md`, three
  stated here as a general rail for the first time — push-verify, spent-branch/stale-resume, and
  treating your editing tool's stale-file refusal as the only real conflict detector), one shared
  recovery-tiers section, and a five-command pre-flight. Doc-only; linked from the README docs index;
  its own doc-coupling test is `tests/test_parallel_sessions_doc.sh`.
- **Drydock — the whole-tree prose audit, promoted from a run-validated procedure to a shipped
  capability** (dir #170). Tests tell you the code still works; nothing tells you the *prose* still
  does — and the rails, docs, command steps, and comments are what a model reads and acts on every
  session. [`docs/drydock.md`](docs/drydock.md) is the repeatable pass that measures that drift: the
  two-tier split (deterministic tier-1 checks under a model tier-2 pipeline) and the **ratchet** that
  makes each run cheaper than the last by demoting finding classes into tier-1 checks; four roles in
  separate contexts with their model and effort recommendations (fixers are never subagents — they
  have to pass through the gates that keep a human in the loop); the audit-file contract, whose
  closing `## claims` section doubles as the completeness marker that makes an interrupted wave
  re-spawnable per unit; the three-valued verdict, whose third value (`known — <ticket>`) is what
  stops an audit from silently reversing a deferral somebody made on purpose; the four delegation
  gates; and the incremental-run mechanics. The three role prompts ship as copy-paste templates
  ([`docs/drydock/`](docs/drydock/)), and the family cross-links are now explicit in both directions
  — this is the fourth "how do you know it's still true?" doc, running underneath the other three.
  Also written down: the session-limit flow, because an agent cannot see your quota and has to ask for
  it. Its rule — pilot on a *leads-dense* batch, not just the biggest file — comes from run 1's pilot
  under-predicting the main wave's per-agent cost by ~50%: cost scales with claims-to-re-measure, not
  with input lines.
  Five defects in that shipped prose were caught by an independent review before the feature landed,
  and four of the five sat in the role templates or in the doc's own copy-pasteable commands — the
  half of this capability that agents actually execute, where a rule the procedure states and a
  template omits is a rail that never fires. [`docs/drydock/verifier.md`](docs/drydock/verifier.md)
  carried the sandbox rail absolutely, without the read-only-machine-state exception `drydock.md`
  says it inherits: a verifier that sandboxes such a read measures a fully-guarded machine as "not
  wired" and writes a confident `rejected`, which is the one verdict nothing downstream re-checks.
  [`docs/drydock/fixer.md`](docs/drydock/fixer.md) told the fixer to mark `fixed: PR #<n>` once its
  PR merges — contradicting phase 5, the roles table, and its own next paragraph, and asking a
  session to act after it has already handed back; that mark belongs to the orchestrator, which is
  still around when the merge lands. The roles table gave the orchestrator "phases 0, 4, 7" while
  GATE-4 handed it 6 and 7, with phase 6 itself not saying which — now 0, 4, 6, 7, and phase 6
  states that it owns the phase and delegates only the reading. And sweep 2 of the doc's own
  mechanical sweeps enumerated without `-z`, so a C-quoted path reached `grep` unopenable and that
  file's own links went unswept, silently — the same class the `Fixed` entry below records for
  `tools/self/shellcheck-targets.sh`, present a second time here in the doc's command block, sweep 1
  having already enumerated NUL-delimited — while that same sweep's character class also excluded
  `:`, truncating `mailto:you@example.com` to `mailto`, which then failed the scheme test beside it
  and was reported as a dead relative link, once per mail link in the tree. Ten pins in
  `tests/test_drydock_doc.sh` now hold the doc/template couplings and both of sweep 2's fixes, and
  they are mutation-proven: restoring the fixer contradiction reds two, restoring the colon-stopping
  class reds one.
- **`tools/drydock/inventory.sh`** — drydock phase 0's scope-as-code generator: measures the tracked
  prose surface at one baseline commit and derives the per-auditor batches, so a run's scope is a
  reproducible artifact instead of a hand-drawn list that quietly disagrees with the tree. The guard
  is the point. Run 1's very first inventory was launched with the cwd left at the main checkout,
  which was sitting on a peer session's branch two commits off the baseline; it measured that tree and
  printed the numbers without a murmur, scoping the whole audit against a commit nobody had chosen.
  The shipped script refuses (exit 3) on any of four conditions rather than measure a tree it cannot
  vouch for: HEAD is not the baseline (naming both SHAs and the `git worktree add` that fixes it), the
  tree is dirty, an in-scope file cannot be read (a sparse checkout, a dangling symlink — it refuses
  instead of omitting the file), or the scope could not be enumerated at all. The last two came from
  the independent review of this very diff, which found the first implementation dropping an
  unreadable file from the artifact at exit 0 — a partial inventory being indistinguishable from a
  small tree is precisely the failure the guard exists to prevent, so it had to refuse rather than
  under-report. There is deliberately **no `--force`**; the escape hatch is `--baseline <rev>`, which
  is the opposite of a bypass: you name the commit you meant and it lands in the output header.
  `--prev <sha>` is the incremental-run mechanism, flagging what changed since a prior run's baseline
  and scoping the derived batches to it. All three enumerations — scope A, scope B, and the changed
  set — are NUL-delimited and status-checked, which is a correctness requirement rather than a
  flourish: git C-quotes any path it cannot print literally, and a quoted string is not a path anyone
  can open, so the guard used to refuse a healthy tree over a filename containing a backslash and
  blame a sparse checkout for it. A path carrying a tab or a newline is still refused, explicitly,
  because the artifact's own tab-separated record cannot represent one. Batch sizes and scope
  pathspecs are environment-tunable for a repo shaped differently from Keel's. Scope B defaults to
  *every tracked shell script*, not to the `*.sh` pathspec — it calls
  `tools/self/shellcheck-targets.sh`, the repo's existing canonical answer to "which tracked files are
  shell scripts", rather than minting a third copy of that selection. The difference is not cosmetic:
  on Keel's own tree the pathspec misses `keel` (the adopter-facing CLI entry point, 48 comment lines)
  and both secret-guard hooks — 55 lines of shipped prose that would have sat permanently outside
  every run's scope, invisible because an inventory reports totals, not omissions.
  A second silent-under-report of the same family was found by review after that guard landed, and
  it was not in the enumeration at all but in the measurement: the path went to `awk` as a bare
  operand, and `awk` reads an operand shaped `name=value` as a variable assignment rather than a
  file — so a tracked file called `a=b.md` was never opened, `NR` stayed 0, and it was listed as an
  EMPTY file at exit 0, with `[ -r ]` passing all the while because the file is perfectly readable.
  The operand is now `./$f`: paths are repo-relative and cwd is the repo root, so the prefix always
  resolves, and the record still prints the path unprefixed. An under-report that looks plausible is
  worse than the visible error it replaces — the same reason the unreadable-file case above refuses
  instead of omitting.
- **Capability-split delegation, generalized from drydock into a standalone, adopter-usable pattern**
  (dir #171). [`docs/delegation.md`](docs/delegation.md) names what drydock's own field test proved out:
  most of a working session is read-only analysis — delegable to cheap, stateless, parallel workers
  behind a file contract — while the gated mutation path (commits, PRs, merges, releases, deletions,
  backlog and memory writes) and the operator's own review bandwidth stay non-delegable, named
  explicitly as a rail rather than left to erode. Four roles in separate contexts (orchestrator, worker,
  verifier, mutator — mutators are never subagents); a generic 7-phase skeleton; the unit-output
  contract with its three-valued verdict; the run-directory/durable-history state split; the worker and
  verifier rails as a literal, do-not-paraphrase block, including the centralized-wrap marker line that
  countered drydock run 1's Stop-hook nudging every fixer session toward a spurious `/wrap`; the
  session-limit ask-then-arithmetic flow; inline worker/verifier/mutator prompt templates; and three
  application sketches beyond auditing (a grooming wave, a pre-implementation recon dossier, a
  post-merge sweep — labeled not-yet-field-tested, unlike the audit sketch, which points at
  [`docs/drydock.md`](docs/drydock.md) as the worked instantiation). `docs/drydock.md` now opens with a
  line naming itself that instantiation, and `FRAMEWORK.md` gains a 4-line pointer to the pattern from
  its "Loop model" section.
- **`tools/self/prose-drift.sh`** — drydock run 1's throwaway mechanical sweep
  (`private/audit/bin/sweep.sh`, dir #165) promoted into a standing `tools/self/doctor.sh` check (dir
  #169). Two signals: a dead relative markdown link (GAP — zero legitimate exceptions) and a line
  running well past the other lines in its own wrapped block — a paragraph, a wrapped list item, a
  comment run (WARN — advisory, "leads not verdicts" per sweep.sh's own framing). The design point
  was the second signal's precision: a flat >110-char threshold produced ~200 leads on the tree as it
  then stood, almost all ordinary table rows, fenced examples, and plain sentences that just run a
  little long. Comparing a line only against the OTHER lines in its own block — never a global
  threshold — plus excluding fenced code, GFM tables, YAML frontmatter, standalone link lines, and any
  line carrying a literal URL, cuts that to 16 genuine leads on dir #169's own branch tip and 18 from
  its merge through the v0.7.0 tag, all advisory. Both counts track the tree; nothing pins either.
  Every exclusion is
  mutation-tested against the same content presented as plain wrapped prose instead (dir #110's
  lesson: fired != catches) — a table row, a fenced line, a frontmatter value, and a 2-line paragraph
  each pair a "does not fire" case with a "the same content, unwrapped, DOES fire" case, so a
  passing negative test can't just mean the checker is blind to that content.
- **`tests/test_tour_transcript.sh`** (dir #168) — mechanizes the class of drift behind 5 of drydock
  run 1's `examples/README.md` findings (a stale console transcript, silently out of date against the
  live tools). Runs `examples/tour.sh` sandboxed and byte-compares its normalized output against the
  README's own fenced transcript, normalizing only per the README's own disclosed rules (path
  abbreviation, key masking) plus one mechanical fence-capture trim and one host-grep-capability
  variance rule — all five documented in the test's own header so the comparison is verifiably fair,
  not lossy. An operator-run `/code-review medium`, verified live against real `alpine:3.21` and
  `ubuntu:24.04` containers (the macOS-only local run couldn't surface these), found and fixed two more
  cross-platform bugs in the test itself before it shipped — see Fixed, below, for the third, a
  pre-existing bug in `secret-scan.sh` the same review surfaced.
- **`tools/changelog-section.sh`** (dir #162, PR #228) — prints one released version's `## [x.y.z]`
  section body out of a repo's own `CHANGELOG.md`, so `docs/publishing-checklist.md` §4's "go find
  and copy the section out" step has a deterministic replacement instead of a hand-scroll through a
  file this long. `--digest` prints only the section opener plus its `### ` heading lines, for
  skimming. Adopter-usable (dir #68): the changelog is resolved relative to the script's own
  location, with nothing keel-specific hardcoded. Scope correction the ticket itself made: printing
  the section is an INPUT to release notes, not the notes — the curation stays the operator's work
  and the tool only removes the fetching (the measurement behind that rescope is in the dir #159
  entry under Fixed). Pinned by `tests/test_changelog_section.sh`.

### Changed
- **`uninstall.sh`/`tools/doctor.sh` now require an install manifest to remove or report on Keel
  content — the pre-manifest (`KEEL-LEGACY-NOMANIFEST`) heuristic fallbacks dir #125 kept for a
  transitional window are gone at 0.7, per that ticket's own filed follow-up (dir #150).** A home with
  no usable manifest (a pre-0.7 install, or one whose manifest is corrupt/unversioned) gets a clear,
  actionable refusal from `uninstall.sh` naming `install.sh --home <dir>` as the fix, never a silent
  content-sniffed removal. That refusal is unconditional, `--dry-run` included: a dry run against such a
  home now prints it and exits 2, where 0.6.1 printed a "would remove" listing — that listing was itself
  the content-sniffed guess this change retires. Whether `--dry-run` should instead fall through to an
  advisory listing is an open fork (backlog dir #228); this entry declares the shape that ships.
  Three of the audited sites turned out NOT to be transitional fallbacks and
  were deliberately kept, just relabeled (token dropped, comment corrected): `tools/doctor.sh`'s and
  `uninstall.sh`'s gate-hooks default settings-path probe is the only possible path for a global/
  home-scope gate install (never a guess among candidates); `tools/pre-pr-gate.sh`'s four static
  dialog-arming candidates are the sole arming mechanism for PROJECT-scope `/polish` gate installs,
  which structurally never get a manifest (`install-pre-pr-gate.sh <repo>`, the documented default) —
  removing them would have silently disabled the dir #88 mandatory-review-dialog check for the common
  case forever, not just for pre-0.7 installs; and `keel`'s own checkout-recovery advice keeps sniffing
  `AGENTS.md`-vs-`CLAUDE.md` when no manifest is present — dir #125's own design notes named this site
  an explicit exception ("keep the sniff as legacy"), since this is advisory recovery text for an
  already-broken CLI, not a destructive action, and a confidently-wrong claude-mode default would be a
  worse silent behavior change than the guess it replaces. A genuine narrowing, not a "kept" exception:
  `uninstall.sh`'s `other_mode_hint` lost its own default-leaf probe along with the sweep — a leftover
  other-mode install at the conventional default leaf that was never ledger-recorded (a pre-0.7
  install.sh run there, never re-run since) no longer gets named at all; a ledger-recorded leftover
  (any install.sh run, default location included) still does. Re-running that install's own install.sh
  restores the hint.
  `tests/test_install_manifest.sh`'s acceptance test 20 now asserts the token is ABSENT from every
  audited site instead of asserting it's present; `tests/test_uninstall.sh`'s B15/B18B now pin the
  refusal where they used to pin a successful heuristic removal.
- **A `new_repo_with_origin()` fixture helper in `tests/lib.sh`** (dir #173). The "sandbox repo plus a
  bare origin, pushed and fetched" idiom was hand-rolled five times past `pin()`'s own promotion rule
  ("once a SECOND test file needs the exact same idiom") before this: `tests/test_public_audit.sh`
  (~10 copies), `tests/test_pre_pr_gate.sh`, `tests/test_ci_secret_scan.sh`,
  `tests/test_branch_cleanup.sh`, and `tests/test_drydock_inventory.sh`'s own `mk_bare()`/`mk_repo()`
  pair. The newest two consumers (`test_drydock_inventory.sh`, `test_pre_pr_gate.sh`) now use the
  shared helper; the rest are left for a later ticket, since they push specific refspecs or
  deliberately diverge local from `origin/<branch>` and don't fit the exact idiom. A successful `git
  push` already updates the local `origin/<branch>` tracking ref, so the helper (and its
  `new_bare_origin()` building block) skips the redundant `git fetch` every hand-rolled copy carried.
- **`FRAMEWORK.md`'s PR-review section now covers what kind of review round to run, not just whether to
  run one** (dir #174, promoted from a 2nd-hit `LEARNINGS.md` entry). The existing "When to stop
  reviewing" answers *whether* another round is worth it; the new "Full pass or cheap delta?" answers
  what kind, once it is — severity trend and where findings land (code migrating to prose-only) read
  together are the tell that the substantive surface is exhausted, producing a defensible "run one
  cheap delta instead of a full pass" call rather than an arbitrary round cap or an open-ended
  "run it again to be sure." The two sections cross-link.
- **A step-5 receipt can now name EVERY review that saw the commit, not just the last one** (dir #158).
  `polish.5-review`'s add-on suffix was two hardcoded literals — `+operator-run` (dir #81) and
  `+second-opinion` (dir #141) — one per `case` arm, while step 5 holds a single value. So a commit that
  genuinely got both add-ons had to drop one from the mechanical record. Felt on dir #155, whose own PR
  got the standing agent review, an operator-run `/code-review high` that found a real bug three agent
  rounds had missed, and a cross-model second opinion. `commands/polish.md` had named only the
  same-*round* version of this as a residual (its dialog is single-select); the cross-*round* version —
  add-ons accumulating across fix commits on one branch — looked resolvable from inside and wasn't. The
  suffix is now a comma-separated set (`agent:<level>+operator-run,second-opinion`), parsed once and
  validated element-wise, replacing both arms with one. Backward compatible: every existing single-add-on
  outcome behaves identically, and all 420 prior gate assertions passed unchanged. An invented add-on
  still denies, by the same level cross-check that caught an invented suffix before — proven by mutation
  (making the allowlist accept anything reds four assertions). An independent high review then found the
  first implementation accepted `agent:<level>+,` — an empty element word-split to zero add-ons, so nothing
  was found invalid and a receipt naming NO mechanism was allowed, with the stronger `(trace-confirmed)`
  label; the set is now walked by parameter expansion only (no word splitting, no IFS, no globbing) and an
  empty element is denied by the allowlist itself. The allowlist is deliberately the
  label function itself rather than a separate list: a first draft had both and shellcheck caught the
  list as unused, i.e. two sources of truth for one fact — the sync-comment smell `FRAMEWORK.md`'s
  contract-first section names. **Named residual, filed as dir #161:** this makes the receipt able to
  *say* the whole set, but not to *get* it said — `polish.5-review` is deliberately never restored by
  `receipt --recover` (dir #96), so an earlier round's add-on must be re-typed from session memory, and
  nothing denies or warns if it isn't. The set's unit is the shipped commit, not the round: an add-on
  belongs in it while the work it reviewed is still in HEAD.

### Fixed
- **`tools/self/doctor.sh`'s release-in-preparation allowance permanently downgraded a forgotten tag to
  a standing green line, with no time bound** (dir #156, found by dir #155's own `/polish` altitude
  pass; spec designed and reproduced live 2026-08-19). The allowance's two existing conditions —
  untagged section is the newest heading, and its version sorts above every existing tag — make a
  section that was cut and genuinely never tagged indistinguishable from a **deleted** tag that was the
  topmost section's own, with no remaining tag left above it: a live recurrence of this check's own
  founding incident (dir #115/PR #118), arriving through the door the allowance itself opened.
  Reproduced live before any code was written: sections `[0.6.0]`/`[0.5.0]`/`[0.4.0]`, tags
  `v0.4.0`/`v0.5.0`/`v0.6.0`, delete `v0.6.0` — `self/doctor.sh` prints `OK '## [0.6.0]' is cut but not
  tagged yet — release in preparation` and fires no GAP at all. Fixed with a THIRD conjunct, ANDed onto
  the whole allowance: the untagged newest section stays exempt only while HEAD is no more than
  `KEEL_PENDING_RELEASE_MAX_COMMITS` commits (env-overridable, default 40 — ~2.9× the worst observed
  real cut→tag distance of 14) past the commit that introduced its `## [x.y.z]` heading, resolved via
  `git log -S'## [x.y.z]' --format=%H -n 1 -- CHANGELOG.md`. Boundary is `>`, not `>=`. Fails OPEN — keeps
  the allowance and says so in the announcement — only when that pickaxe genuinely returns nothing (an
  untracked/uncommitted CHANGELOG.md), never as a way to dodge a real GAP. Strictly narrowing: every
  input that GAPed before still GAPs; the only new failure mode is a false GAP, which is loud, names
  the section, and states the remedy. Also corrected an overclaim in `tools/self/doctor.sh`'s own
  comments and in `docs/release-audit.md` phase 7: the version condition was credited with stopping "a
  deleted tag" in general — it stops a section sorting below some *remaining* tag, not a deleted tag
  that was the topmost section's own, which is what the new bound now covers. **Two operator-run
  `/code-review high` rounds** on this same diff each found real bugs, both fixed: round 1 found the
  pickaxe resolving the OLDEST commit that ever added/removed the heading text (`tail -1`) instead of
  its most recent (re-)introduction — a version cut, reverted, and later genuinely re-cut with the same
  number would measure distance from the stale original cut, not zero — fixed to resolve the newest
  match; round 1 also found the `KEEL_PENDING_RELEASE_MAX_COMMITS` guard rejected non-digit input but
  not excessive magnitude, letting a 10+-digit override overflow the shell's integer range and silently
  fail-open the bound check, fixed with a length cap. Fixing the first of those two live introduced a
  THIRD bug caught by round 2: resolving the newest match via `git log -S... | head -1` reproducibly
  SIGPIPEs the whole script under `set -o pipefail` on a long enough match list — fixed by using git's
  own `-n 1` flag instead of piping. New coverage in `tests/test_self_doctor.sh` (7 fixtures: legit-pending
  within bound, over-bound, the `>`/`>=` boundary, the residual-case-2 reproduction with a dedicated GAP,
  the fail-open path, a pin on the shipped default, and a cut/revert/re-cut fixture locking in both the
  stale-match and SIGPIPE fixes together) and a fourth prose-coupling pin in `tests/test_release_audit_doc.sh`
  (dir #157's own comment had predicted this exact class of drift — a conjunct gained in code without
  phase 7 being updated in the same commit — as a named limit of that guard). Discharges drydock run 1's
  `known — dir #156` finding (dir #165). **Three named residuals, filed as dir #194/#195/#196** (found
  across both review rounds): `_pending_release_intro_commit`'s pickaxe searches CHANGELOG.md's raw
  history, not fence-blanked like this same check's other heading extraction, confirmed latent
  (dir #194); the identical SIGPIPE-under-pipefail shape this ticket fixed in one function also exists,
  untouched, in an unrelated pre-existing check at `tools/self/doctor.sh:326` (dir #195); the identical
  digit-shape-only-no-magnitude-cap numeric guard this ticket fixed in one place is duplicated, unfixed,
  across six other `tools/*.sh` files (dir #196). Sequencing: dir #160, a related doc↔code coupling gap,
  rebases on top of this ticket next, now with a live three-conjunct specimen to build its guard
  against.
- **`uninstall.sh`'s `artifact_shared_with_other()` misjudged a foreign-core install as unshared**
  (found live by an operator-run `/code-review max` pass on dir #150's own diff, in code adjacent to —
  but pre-dating — that ticket's changes). Its fallback for an unmanifested other-mode install tested
  `has_keel_rails` on the other mode's context file — but `install.sh`'s foreign-core path (installing
  over a pre-existing user `CLAUDE.md`/`AGENTS.md`) never writes a rails marker into that file even
  though the install is completely real, so the rails test always read a genuinely-installed but
  unmanifested foreign-core mode as "not shared." Reproduced live: `install.sh` then `install.sh
  --codex` over the same foreign `CLAUDE.md`, delete the claude manifest to simulate a pre-dir-125
  half, then follow the mismatch refusal's own advised `uninstall.sh --codex` — it stripped `bin/keel`,
  `FRAMEWORK.md` and `PRINCIPLES.md` still needed by the un-migrated claude half. Fixed by testing
  plain existence of the other mode's context file instead — the same, narrower "did the other mode's
  install genuinely happen here" question the cross-mode mismatch guard a few lines up already asks,
  independent of whether that file happens to carry rails. New coverage: `tests/test_uninstall.sh`'s
  B22 (the foreign-core mixed-generation case) and B15C (the `--codex` no-manifest refusal, previously
  untested under that flag). **Named residual, filed as dir #190:** the fix trades that false negative
  for a false positive in the opposite (safe) direction — any file merely sharing the other mode's
  context filename now reads as "shared" and survives, leaving the home's shared half unremovable via
  the documented path. That is not confined to an unrelated same-named file, as this entry first said:
  the ordinary both-modes home reaches it too, because uninstall never deletes the context file, so the
  first mode's removal always leaves the other mode's file behind for the second run to read. Known
  issues above carries the full account and the A/B against v0.6.1. Every kept artifact is still named
  in the output, so this isn't silent, but it isn't automatically recoverable either.
- **`secret-scan.sh`'s `emit_diff()` leaked a stray `+` into every BLOCKED diagnostic built from a
  staged-diff scan (the normal `git commit` hook path) on Alpine/BusyBox** (dir #168, found by an
  operator-run `/code-review medium` verifying `tests/test_tour_transcript.sh` live in an
  `alpine:3.21` container). The line-stripping `sed 's/^\+//'` relies on GNU sed's non-portable `\+`
  extension ("one or more of the preceding atom") to match a literal leading `+`; BusyBox sed has no
  such extension, so the pattern matches nothing and the `+` survives into the printed record —
  e.g. `config.txt:+aws_key = "..."` instead of `config.txt:aws_key = "..."`. Pre-existing on every
  CI leg since the hook shipped, invisible until a test byte-compared the exact diagnostic text.
  Fixed to the portable `sed 's/^+//'` (no escaping needed for a literal `+` in BRE); verified live
  on both `alpine:3.21` and `ubuntu:24.04`.
- **`tools/self/shellcheck-targets.sh` dropped non-ASCII paths and returned 1 on a healthy repo**
  (found by dir #170's independent review, which made this script a consumer for the first time).
  Two defects, both invisible while every caller ignored the output's completeness and its exit
  status. (1) It listed files with a plain `git ls-files`, so a tracked path containing a non-ASCII
  byte arrived C-quoted (`"r\303\251sum\303\251.sh"`); that string matches neither the `*.sh` arm nor
  `head`'s idea of a filename, so the file was silently absent from the selection — from CI's
  shellcheck job and `tools/self/doctor.sh` too, meaning an unlinted shell script with no signal that
  anything was skipped. Now `ls-files -z` with a NUL-delimited read: `-c core.quotePath=false` was the
  first attempt and covers only the non-ASCII half, since git quotes a backslash or a double quote in
  a path regardless of that setting — the operator's own `/code-review high` on this PR caught the
  narrower fix being claimed as the whole one. (2) Its exit status was whatever the last loop
  iteration returned, so a repo whose alphabetically-last tracked file is not a shell script exited 1
  purely because the final shebang `grep -q` found nothing — reproduced on a two-file repo. Each
  iteration now succeeds on its own (`if … then … fi` instead of `grep -q … && printf`); a trailing
  `exit 0` would NOT have worked, since `set -e` exits at the failing pipeline before ever reaching
  it — which the review caught after a first attempt shipped exactly that. **This was live CI
  exposure, not a hypothetical:** `.github/workflows/ci.yml`'s shellcheck job runs this script under
  `bash -e`, so Keel would have gone red — with no diagnostic pointing here — the day anyone added a
  top-level tracked file sorting after `uninstall.sh`. The existing test passed only by accident of
  its fixture's sort order; the fixture now ends in a non-script file, and both cases are
  mutation-pinned.
- **drydock run 1 — the whole tree's prose audited, 44 findings fixed across PRs #210–#217**
  (dir #165). First run of the named prose-audit framework: 33 markdown files (7,159 lines) plus the
  comment prose of all 60 shell files (6,442 comment lines), audited against frozen baseline
  `12a7a79` by a three-role pipeline — parallel auditors, empirical verifiers (every number
  re-measured, live claims reproduced in scratch sandboxes), orchestrator arbitration. 45 confirmed
  findings: stale console transcripts in `examples/README.md`, a self-contradicting "one hard
  guarantee" pair in `README.md`, a `commands/polish.md` step-count enumeration dir #123 re-broke one
  day after dir #138 had fixed the class, comment claims measured false against their own code, and a
  round-count figure in `FRAMEWORK.md` that bled in from a different review campaign. 44 fixed; the
  one survivor is the operator-deferred dir #156 overclaim, recorded `known` and left to its ticket.
  A closing cross-file re-check found two residual mismatches, seeded into run 2 (dir #166/#167)
  rather than fixed in-loop. The run's ratchet demoted four finding classes to ticketed deterministic
  checks (dir #166–#169); promotion of the framework itself to a shipped doc is dir #170. Run record:
  `private/audit/run-1-freeze.md`.
- **`docs/release-audit.md` phase 7 and `tools/self/doctor.sh` are now mechanically coupled** (dir #157).
  The felt incident is the cleanest available for this class: both halves shipped in dir #155's own PR and
  drifted anyway. Phase 7's paragraph stated one condition for the release-in-preparation allowance; that
  PR's own review then forced a second condition into the code (the pending version must out-sort every
  tag); the paragraph was never revisited. Three delta rounds of the same reviewer missed it — each saw
  only its own delta, and the divergence opened *between* deltas — and an operator-run `/code-review high`
  caught it by reproducing a backport shape that satisfies the doc and GAPs in the code. Four pins in
  `tests/test_release_audit_doc.sh` now hold the DOC leg: it must state both conditions and the
  linear-release-line limit (the fourth arrived later in this same release, with dir #156's
  commit-distance bound — see that entry above). The CODE leg is pinned behaviourally in
  `tests/test_self_doctor.sh` instead of by grepping the expression — a first version did grep it, and
  `/simplify`'s altitude pass showed that added no protection (deleting the conjunct already reds 3
  behavioural assertions, measured) while adding refactor fragility, since it pinned expression shape
  down to a trailing `&&`. **Named residual, filed as dir #160:** presence-pins catch a DELETED
  condition, not the direction that actually failed here — code *gaining* a condition the doc never
  states. The generated-embed shape this repo already uses for `CORE.md` ↔ `templates/CLAUDE.md` is the
  real fix.
- **`docs/publishing-checklist.md` §4 no longer prescribes a release with no title** (dir #159). It showed
  `gh release create <tag> --notes-from-tag …` with no `--title`; followed literally for v0.6.1 that
  published a release whose title was the empty string and whose body was the 25-character tag message,
  while every earlier release carried a headline and real notes — those had been written by hand *in
  addition to* the checklist, which never said so. §4 now passes `--title` explicitly, points at the
  freshly-cut `CHANGELOG.md` section as the source of the notes, and says to verify with
  `gh release view <tag> --json name,body,assets`, since an empty title is invisible from the command that
  created it. The line's `[auto]` marker is corrected to `[you]`: producing the notes file is still by
  hand, which is the very step whose omission caused this. **§4 also now says the notes are CURATED from
  that section rather than copied from it** — found while hand-writing v0.6.1's own notes, where the
  section ran ~31KB against a ~4KB house length (a prose opener, three or four highlight sections, a
  Known-issues paragraph), so "notes come from the section" read literally produces a release note eight
  times too long. A helper to make that step one paste was filed as dir #162, which the same measurement
  rescoped: printing the section is not enough, since the curation is the work — it shipped inside
  this same release as `tools/changelog-section.sh` (see Added). Whether a doctor leg should
  WARN on a published release with an empty title (the ticket's own "ideally a check") is the remaining
  question, and `tools/self/doctor.sh` already reconciles CHANGELOG sections against git tags and already
  calls `gh` best-effort, so it is the natural home — not built here, so the live v0.6.1 release still
  needs the operator's own `gh release edit`.
- **`docs/publishing-checklist.md` §4 (above) also never said HOW the tag is created, and the sibling
  recipe could create it at the wrong commit** (the v0.6.1→v0.7.0 delta audit's Batch A, PR #240).
  The step named a version tag as the outcome and carried no command for creating one, so the only
  tag-creating command anywhere in §4 was a bare `gh release create` in its stamped-bootstrap bullet —
  which, with no tag already on the remote, tags **the default branch's head at execution time**. That
  silently disagrees with `docs/release-audit.md` phase 7, whose whole job is to stop at "tag ready to
  cut" and *name the exact SHA* — the two agree only while nothing lands in between, which is the
  window phase 7 exists to describe. §4 now prescribes the annotated-tag-on-the-named-SHA shape v0.6.1
  actually used, pushed before `gh` runs, with `--target <sha>` as the alternative — and a reciprocal
  pin pair in `tests/test_release_audit_doc.sh` couples §4's new quotation to phase 7's wording in both
  directions, since a citation pinned on neither side is how the original drift opened. Two other sites
  could reach the same trap and are closed too: `docs/going-public.md`'s delete-and-recreate recipe
  chained `git push origin <tag> ; gh release create …` with `;`, so a failed tag push still reached
  `gh` (now `&&`, the chained-on-success-only idiom `docs/publishing-checklist.md` states for its own
  commands), and `tools/stamp-release-bootstrap.sh`'s wire-into-a-release example showed `gh release
  create` with no tag step before it — that one found by the review of THIS entry, which had claimed
  going-public.md was the only site, and fixed alongside it.
- **`docs/loading-and-cost.md` was missing an `IDEAS.md` row its own "File by file" table should have
  had** (dir #167, the drydock run-1 phase-6 re-check's P6-2). The same PR #211 batch had added an
  `IDEAS.md` row to `docs/getting-started.md`'s parallel table but never the matching row here, and
  nothing checked the two tables named the same file set. Also unguarded: the "one-off ~16.4K for one
  decision" line derived from the table's own FRAMEWORK.md + PRINCIPLES.md figures — a prior version
  said "~12K" against the same table's own ~16,450, hand-fixed in PR #211 with the arithmetic itself
  left unchecked. `tests/test_doc_figures.sh` now re-derives that sum from the table's own quoted
  addends and asserts the two tables' file sets match; both checks are mutation-proven (perturbing the
  quoted sum, or dropping the `IDEAS.md` row, independently red the suite).
- **`commands/polish.md`'s convergence prose only covered the RE-INVOKED round** (dir #177, felt during
  this file's own changelog-delta `/polish` run). Step 5 said a fix commit moving HEAD was expected,
  then routed every reader through re-invoking `/polish` and step 1's `receipt --recover` branch — but
  resolving a step-5 finding IN-RUN (`--amend`, keep going, never re-invoke) is the cheaper path when
  steps 6/7/8 are still ahead, and the doc never named it. On that path the sentinel is never retired,
  so it lands in a state the prose didn't describe: `polish.3-tests` silently goes stale, still bound
  to the pre-amend commit, with step 8 denying later the only way to find out; and `receipt --recover`'s
  `nothing to recover` answer is correct and by design there too, not proof the round wasn't a
  convergence round — the mirror image of the dir #96 misreading step 1 already warned against. Step 5
  now names the in-run path explicitly, states which receipt needs re-establishing before step 8 and
  how, and step 1's own `--recover` warning got the mirror-case caveat added. Two operator-run
  `/code-review medium` passes on the fix itself then caught three real errors in the new prose before
  it shipped: an example wrongly claiming steps 6/7 can also resolve in-run (both mandate stopping and
  re-invoking on any finding of their own), an instruction to re-receipt two receipts where the gate's
  own check is an OR satisfied by either one, and — in the second pass — a follow-on claim that the
  MANDATORY review dialog (dir #88) needs re-answering for every `polish.5-review` outcome shape,
  overreaching to a bare `<level>` outcome the gate never actually checks it for. A third pass then
  restructured the two dense paragraphs holding those fixes into a lead-in plus a bulleted list — by
  then they held four separate "re-establish X after a later same-run amend" facts, run together at
  equal visual weight, the same shape the file already bullets two sections below for its own dir #127
  additions — and trimmed one remaining redundant clause. Six pins in `tests/test_rails_honesty.sh`
  hold the paragraph's key phrases.
- **Three findings from this release's own RC pass** (dir #192). The first two are one shape: a claim
  true when the PR that wrote it merged, false once a LATER PR in the same tail moved what it
  describes. (1) `commands/polish.md` called the SHA-binding of the mandatory review dialog an open
  design question under dir #180 — superseded hours later by dir #183, which removes that dialog
  outright rather than relaxing when it re-fires; the paragraph now points there and says the binding
  holds as described until it lands. (2) This file's own `tools/self/prose-drift.sh` entry pinned the
  check's output at a single lead count, which had already moved when that branch merged `main`; it
  now names both measurements and the fact that nothing pins either. Neither drift was catchable by
  the two checks this same tail shipped for the class — dir #169's sweep reads line SHAPE, not claims,
  and dir #167's arithmetic guard covers the docs' figure tables, not `CHANGELOG.md` prose. (3)
  `docs/loading-and-cost.md`'s `CHANGELOG.md` floor went `~60,000+` → `~70,000+`, this release's own
  entries having pushed the file past the 25%-above-floor mark where `tests/test_doc_figures.sh`
  starts asking for a restatement — the same bump v0.6.1 made from `~50,000+`, and the fifth by hand
  in this file's history, now ticketed for mechanization (backlog dir #202).
- **`docs/drydock.md` still described its own ratchet as unpaid in the very release that paid it**
  (dir #205, found by an end-to-end read of the drydock/delegation/parallel-sessions trio). The doc
  said run 1's four demoted classes (dir #166–#169) were, in full, *"at the time of writing … filed
  and not yet landed, which is precisely the gap the next run measures"* — and that hedge kept the
  sentence literally true after all four merged (PRs #227, #230–#232), every one inside this release.
  The defect is what the hedge did not reach: the run-2 worked example 340 lines downstream inherited
  the claim with no time-scope at all, framing *"did those checks land?"* as run 2's open question
  when the answer already existed. So the release disagreed with itself — this changelog listing the
  four checks as shipped, the drydock doc reading as though they were still owed. The landed status now
  lives in the run-2 example alone, with the concept section keeping only the durable rule and a
  pointer to it — a status restated on two surfaces is dir #166's own class, and an earlier draft of
  this very fix reintroduced it before review caught that. **Why the RC pass above missed it:** its
  stale-phrase sweep did reach this file, but only mechanically — `tools/self/prose-drift.sh` reads
  line shape and dead links, never claims, and dir #166's coherence check reads outcome tokens in six
  named rails files that do not include this one. The manual half was a targeted grep for tail-ticket
  references. Nothing in that step reads a paragraph and asks whether it is still true, which is the
  one thing that catches this class.

## [0.6.1] — 2026-08-14

The release tail of the v0.6.0 audit. v0.6.0 shipped with a named list of known issues rather than
holding the tag for them; this release closes that list and the ~25 tickets around it. Three arcs:
the install manifest landed, so `install.sh`/`install-pre-pr-gate.sh`/`uninstall.sh`/`doctor.sh` read
one recorded state instead of re-deriving it heuristically at every site (dir #125); the `/polish`
gate learned the two checks v0.6.0 conceded it lacked — HEAD must actually be pushed before a PR can
open (dir #133, dir #152), and a convergence round no longer re-runs the whole suite to re-bind a sha
when nothing test-relevant moved (dir #123); and the review loop itself got a budget, a delta
protocol, and a terminal condition (dir #127), plus an in-session cross-model second opinion (dir
#141). The rest is standing bookkeeping — a coverage ratchet, CHANGELOG/tag reconciliation, backlog
heading-drift, a written-down release-audit flow — turning things this project had been checking by
hand into checks that run on their own.

Known issues: three residuals from this tail are ticketed and deliberately not held for the tag. The
composed dialog-marker name list (`KEEL-DEPTH-DIALOG` / `KEEL-REVIEW-DIALOG` / `KEEL-AGENT-REVIEW`)
is still hardcoded separately in `tools/pre-pr-gate.sh` and `tests/test_pre_pr_gate.sh`, so a fourth
marker can be added to one without the other noticing — the exact shape dir #146 in this release was
(backlog dir #147). `tools/public-audit.sh`'s personal-literals loader duplicates
`tools/secret-guard/secret-scan.sh`'s near-verbatim and uncredited, so a fix to one silently misses
the other (backlog dir #148). And the install manifest ships with its pre-manifest heuristics still
in place behind `KEEL-LEGACY-NOMANIFEST` fallback blocks, deliberately, so an install predating the
manifest keeps working — removing them is dir #125's own closing instruction, targeted at 0.7
(backlog dir #150). Nothing there is a correctness gap in a shipped path; all three are
single-source-of-truth debt with a named ticket. A fourth residual is introduced by this release's
own RC pass: the CHANGELOG↔tag reconciliation now has to allow the newest section to sit untagged
while its release-prep PR is in flight, and that allowance is unbounded in time — so a release whose
tag was simply forgotten reads as a green "release in preparation" line rather than a GAP. It is
announced on every full run rather than silent, and bounding it is backlog dir #156.

### Added
- **`FRAMEWORK.md` gains a "when to stop reviewing" test and a contract-first design section**
  (dir #126, dir #128). The two measured signals for ending a review round — new surface touched,
  class exhaustion — replace the disproven "findings are getting smaller" heuristic (three separate
  review campaigns converged by hitting the same defect shape twice, not by severity trending down).
  A new "Contract-first for invariant-bearing surfaces" section states six rules distilled from those
  same campaigns: contract-first design, the sync-comment smell, class → mechanical floor (plus the
  floor needing its own mutation-tested proof), no-contract-no-ship, and rationale-lives-in-the-file.
  Both are on-demand methodology only — nothing lands in `CORE.md`.
- **An install manifest, recorded instead of re-derived** (dir #125, PR 1/3). `install.sh` and
  `tools/install-pre-pr-gate.sh` now write a flat `key=value` manifest under
  `<home>/.keel/install-manifest.<claude|codex|gate>` — mode, layout, every Keel-owned artifact (with
  cksum provenance for upgrade precision), and a checkout-side ledger
  (`<checkout>/.keel/installed-homes`, gitignored) indexing every recorded home. State, not action: a
  re-run whose files are all up to date, or whose drift prompt was declined, still lists every
  artifact — carrying forward its recorded cksum rather than re-deriving from possibly user-edited
  disk bytes. This PR is schema + writers only; `uninstall.sh` doesn't consume the manifest yet.
  `tools/doctor.sh` gains two new read-only findings: `W-MANIFEST-MISSING` (no manifest — legacy
  heuristics still apply, `KEEL-LEGACY-NOMANIFEST`) and `W-MANIFEST-DRIFT` (a present manifest
  contradicts the filesystem). Why: the dir #98/#108/#109 batch took ~9 review rounds because
  `uninstall.sh`/`doctor.sh` guess install state per-site instead of reading one recorded contract —
  a missing contract, not a bug list.
- **`uninstall.sh` now consumes the install manifest** (dir #125, PR 2/3). Per-artifact ownership is
  cksum-precision now (bytes must match the RECORDED cksum, not the current checkout — the old
  cmp-to-checkout was blind to upgrades: an older release's untouched file differs from a newer
  checkout and was wrongly kept). Cross-manifest refcount closes dir #124's structural gap: an
  artifact also listed in the OTHER mode's manifest at the same home is shared, kept, and named — no
  invocation silently strips the shared half of a both-modes home. The mode/home mismatch refusal and
  `other_mode_hint` (now ledger-driven, naming a retargeted `--home` install the old `$HOME/<leaf>`
  probe couldn't see) and `gate_hooks_hint` (quoting the gate manifest's recorded settings path) are
  all manifest-driven, each keeping the old heuristic as an unchanged `KEEL-LEGACY-NOMANIFEST`
  fallback for a manifest-less home. Also handles a MIXED-generation both-modes home (one side
  installed by an old, pre-dir-125 checkout with no manifest, the other by the current one) without
  either falsely refusing or letting the manifested mode's uninstall strip content the unmanifested
  mode still needs, and never backs up/consumes a manifest whose `keel_manifest_version` it doesn't
  understand — treated as absent for reads, left untouched on disk either way.
- **`_dialog_leg_armed`/gate-manifest consumers close the install manifest's B2 gap** (dir #125, PR
  3/3, the final leg). `tools/pre-pr-gate.sh`'s `_dialog_leg_armed` (the check gating the dir #88
  mandatory-review-dialog deny) now also walks the checkout-side ledger and, for every home whose gate
  manifest is present and at `keel_manifest_version=1`, adds that manifest's recorded `settings=` path
  to its arming candidates — closing B2: an `install-pre-pr-gate.sh --home DIR` wire wasn't among the
  four static candidates, so a genuinely wired mandatory-dialog hook there silently read as UNARMED and
  the deny silently no-op'd, the same class PR #165 closed for `KEEL_HOME` and PR #173's `--home` flag
  reopened. `tools/doctor.sh`'s gate-wired check now agrees with the gate manifest (a new
  `W-GATE-MANIFEST-MISSING`/`W-GATE-MANIFEST-DRIFT` pair, deliberately distinct ids from the
  install-manifest's own `W-MANIFEST-DRIFT` so `.keel/doctor-accept`'s bare-id matching can't collapse
  an accepted install-manifest drift into silently swallowing an unrelated gate one) instead of blindly
  assuming `$ihome/settings.json`, mirroring `uninstall.sh`'s own `gate_hooks_hint`. `keel`'s
  severed-checkout advice now prefers the recorded install manifest for mode detection over sniffing
  `AGENTS.md`/`CLAUDE.md`. Every `KEEL-LEGACY-NOMANIFEST` fallback across the ticket's consumers is
  marked consistently, closing the ticket; the fallback removal itself ships as its own `→ 0.7` ticket.
- **A test-coverage ratchet in `tools/self/doctor.sh`** (dir #142). Its "tool wiring" check now maps
  every shipped `tools/*.sh` script (already crossing subdirectories, so `tools/secret-guard/*.sh`
  and `tools/lib/*.sh` were already in scope) plus the installed `keel` CLI against `tests/test_*.sh`
  coverage; a script with zero coverage is now a hard GAP unless it is listed, by name, in the new
  `tools/self/legacy-untested.txt` (soft, visible debt — currently empty). Why: v0.6.0's coverage was
  carried reactively by review pressure (dir #100–#103 were exactly "no coverage at all" findings);
  this turns "an element without a contract shouldn't be in the project" into a standing, mechanized
  check instead of something only a review catches. Investigated real branch-coverage tooling (kcov)
  for a tier-2 follow-up and closed it as not worth it — kcov is Linux/ptrace-only and doesn't run on
  macOS or reliably under Alpine/musl, so it could only ever cover one of this project's three CI
  legs; the decision and its reasoning are recorded in `BACKLOG.md`'s dir #142.
- **`docs/release-audit.md`: the v0.6.0 campaign's release-readiness process, written down as a
  repeatable seven-phase flow** (dir #140). Module audit sweeps, synthesis-time dedupe with an
  up-front blocker-vs-tail ranking, batching by file-affinity, a model tier per batch, a review-round
  budget, a narrow three-point RC-pass mandate (cross-PR seams, whole-delta stale-phrase sweep,
  residual-ledger check), then tag — each phase citing the felt incident from v0.6.0 that shaped it,
  so the next release runs off the doc instead of re-deriving the process live.
- **A target-release label for backlog tickets, and `/backlog` support for it** (dir #143). A
  ticket's heading can carry a trailing `→ 0.6.1` (or `→ next`) tag, assigned at synthesis time
  (`docs/release-audit.md` phase 2); `commands/backlog.md` reads it (step 3b) and renders one grouped
  "Release tail" table per target value (step 6), so "what's slated for X?" is answerable without a
  re-read of every ticket the way v0.6.0's ~20-ticket tail needed one. New test coverage in
  `tests/test_release_audit_doc.sh` pins the doc/command cross-references against drift.
- **Two standing bookkeeping checks in `tools/self/doctor.sh`** (dir #135, dir #139).
  - **The `BACKLOG.md` heading-drift check now runs from a worktree, not just the main checkout**
    (dir #135). It previously resolved `BACKLOG.md` against whatever checkout it was invoked
    from — the worktree, in the one place `/polish` step 7 actually runs it — so it silently
    skipped itself everywhere except a manual main-checkout run (a live consequence: dir #96 sat
    unclosed for two days before an unrelated audit caught it). It now resolves the main checkout
    the same way `tools/doctor.sh`'s `unit_top` does. A second, independent check was added
    alongside it: a `⏳`/`IN REVIEW` heading citing a PR that `gh` reports MERGED is flagged as
    stale regardless of whether the body agrees — the tag-staleness check above it only catches a
    *missing* tag, not a well-formed one that's since gone wrong. Best-effort: no `gh`, no
    network, or no auth all degrade to a silent skip rather than a false GAP or a crash.
  - **A new check reconciles `CHANGELOG.md`'s release sections against git's own tags, both
    directions, plus a section-count invariant** (dir #139, the durable fix for the dir #115
    class). v0.5.0's section was cut correctly at release and then silently clobbered by the very
    next commit — invisible for three weeks until an unrelated audit tripped over it, because
    nothing re-derives the fact from git itself. `tools/self/doctor.sh` now GAPs if a release tag
    has no matching `## [x.y.z]` section, if a section has no matching tag, or if the section
    count doesn't equal tags + `[Unreleased]` (catching a duplicated or refolded section neither
    directional check alone would). Degrades to a silent skip on a shallow clone, where the tags
    this check needs aren't present even though the working tree is fine; the `self-check` CI job
    now fetches full history so the check actually runs there.
- **`public-audit.sh` now hunts the secret-guard's local personal-literals file, not just declared
  `--token`s** (dir #145). Re-derived from a 2026-07-07 branch that stranded before the tool's binary-blob
  scanning (dir #101) landed independently — its own value was the missing piece: a real name in the
  local `~/.claude/secret-scan-personal` file (override with `$SECRET_SCAN_PERSONAL_FILE`) is now hunted
  case-insensitively in the tracked tree, git history, and binary blobs, the same three surfaces
  declared tokens already cover. A bad regex line in the personal file is a GAP, not a silent drop — the
  literal it would have hunted goes unscanned, and unlike a bad `allow-email` entry (which fails open
  safely) that's a detection-accuracy failure this audit's own bar exists to catch.
- **`/polish` step 5 can now get a second opinion from a DIFFERENT model tier in-session, without the
  operator acting as message bus** (dir #141). The step 5(a) dialog gains a third option alongside the
  standing agent review and the operator-run `/code-review` add-on: spawn ONE fresh-context subagent
  pinned to another model tier, reviewing the same diff at the same depth. The combined receipt outcome
  is `agent:<level>+second-opinion` (mirroring dir #81's `+operator-run` shape rather than opening a
  second dialog), and both the PR body and the step 10 summary must name BOTH mechanisms and the pinned
  tier — never collapse them into one. Its provenance half is labelled `(self-reported)`, not
  `(trace-confirmed)`: the `SubagentStop` trace leg confirms a `general-purpose` subagent ran, not which
  model answered. **Residual, named rather than dropped:** the dialog is single-select, so the
  cross-model and operator-run add-ons can't both be chosen in the same round.

### Changed
- **`/polish`'s review loop gets a round BUDGET, a delta-review protocol, and a precise terminal
  condition** (dir #127, with dir #137/#138 folded into the same batch). Three specifics refine the
  existing "converge, don't restart" rule: (1) *same reviewer, not a fresh spawn* — a convergence round
  sends a follow-up message to the SAME subagent (or the operator re-runs `/code-review` on the delta),
  a fresh full pass being justified only when the fix touched surface the original review never saw;
  (2) *the full review runs once, then at most TWO delta rounds* — if a second consecutive delta round
  still returns substantive findings, stop fix-forward, file the residual as a numbered ticket, name it
  in the PR body, and open the PR as-is (an executed decision, not a silent abandon; the receipt shape
  is unchanged, so no `pre-pr-gate.sh` change); (3) *the terminal condition is zero findings in a DELTA
  round* — a fresh FULL re-review returning zero is explicitly NOT the signal, since a full review
  samples and will always find something if repeated, which is what produced the 7- and 13-round loops
  this closes. Every round now also reports a one-line trend (findings, max severity, surface
  same/new, class named/exhausted, forecast) instead of a silent count climbing toward a dreaded
  double-digit round.
- **`tools/keel-impact.sh`'s ledger columns now come from one ordered array instead of being
  hand-listed independently in three places** (dir #151). The writer (`cmd_add`'s row-printf), the
  reader (`_ledger_parse`'s awk field indices), and the markdown table header each separately
  hand-listed the same 12 ledger columns, kept in sync only by a "keep in sync" comment plus a test
  that caught drift after the fact but didn't prevent it. `_LEDGER_COLS` is now the single source of
  truth: `cmd_add` builds its row by iterating it, `_ledger_parse` derives its awk field positions via
  `_ledger_col_pos` (failing loudly on a lookup miss instead of silently degrading), and the table
  header is generated from it, deferred to only build when a ledger file actually needs creating. No
  behavior change — the ledger's data rows and header are byte-identical to before; bash 3.2 (macOS
  default, no associative arrays) compatibility preserved throughout.
- **`tests/run.sh` now runs test files concurrently instead of one at a time** (dir #130,
  keel-self-maintenance — internal to the test harness, not adopter-facing). A full local pass
  measured at ~229s sequential (`test_pre_pr_gate.sh` at ~53s, `test_self_doctor.sh` ~36s,
  `test_doctor.sh` ~25s, and `test_install.sh` ~24s the four biggest single files — install/uninstall
  alone were NOT the dominant cost the ticket started from, measurement corrected that assumption).
  Safe because every `tests/test_*.sh` already sets up its own throwaway sandbox `HOME` via
  `tests/lib.sh`, and the one cross-file shared resource any of them touch —
  `tools/pre-pr-gate.sh`'s `/tmp` sentinel (dir #80) — is keyed off a repo basename every fixture
  mints via `mktemp -d`, so two files running at once can't collide on it either. The runner caps
  concurrency at the CPU core count by default (override with `KEEL_TEST_JOBS`, e.g. `=1` to force
  the old sequential behavior), via a bash-3.2-compatible poll loop (no `wait -n`, portable to
  macOS's shipped `/bin/bash`) — full local run now ~90-100s. No test file's coverage or `HOME`
  isolation changed; `tests/test_run_sh.sh` is a new file covering the runner's own aggregation
  logic (concurrent pass/fail counting, a `KEEL_TEST_JOBS` override, more fixtures than the
  concurrency cap).

### Fixed
- **`doctor.sh --install` didn't understand `--codex` — a healthy codex install got a false GAP whose
  advice would have installed a second mode into the same home** (dir #134, one of 0.6.0's own known
  issues). It gets an explicit `--codex` flag, mirroring `uninstall.sh`'s own (dir #109): the rails file
  checked is mode-aware (`AGENTS.md` vs `CLAUDE.md`), the commands-wired check is skipped under `--codex`
  (Codex never gets Keel's `commands/` dir), a mode/home mismatch redirects to the correctly-moded
  re-run — with the redirect's `--home` flag computed against the OTHER mode's default, not this one's,
  a second bug an independent review caught before this shipped — instead of cascading wrong-mode advice
  on top, and `H-FOOTPRINT`'s global-footprint sum now auto-detects `CLAUDE.md`/`AGENTS.md` instead of
  assuming `CLAUDE.md` only.
- **`uninstall.sh` left the 6 `/polish` pre-PR-gate hooks dangling in `settings.json` with no word and
  no reverse operation** (dir #136, the other known issue). `tools/install-pre-pr-gate.sh` gets a mirror
  `--uninstall` flag that removes only a hook byte-identical to what it would currently wire, never a
  differing/foreign one; `uninstall.sh`'s closing summary now names any leftover gate hooks and the
  removal command, the same treatment the secret-guard note already gets, at every summary exit.
- **`tools/pre-pr-gate.sh`'s `receipt <step-id> <outcome>` silently accepted a step-id or outcome with
  the two combined into one quoted string, writing a malformed sentinel line that only surfaced later as
  a misleading "missing receipt" deny** (dir #144, re-derived from a stranded 2026-08-05 branch that was
  never PR'd). Both fields now reject an embedded TAB/newline at write time with an actionable message —
  step-id rejects any whitespace (no real step id contains any), outcome only TAB/newline (a real outcome
  routinely contains spaces).
- **`tools/pre-pr-gate.sh`'s `receipt <step-id>` guard (dir #144, above) only caught a whitespace-carrying
  step-id — a typo'd but space-free one (e.g. `polish.4-depht`) still wrote silently, the same deferred,
  misleading "missing receipt" deny for a different malformation shape** (dir #149). A step-id is now
  checked against the complete `EXPECTED_STEPS` list at write time, at both entry points that append to
  the sentinel — `receipt`'s own write and `receipt --recover`'s replay of a retired sentinel.
- **`doctor.sh`'s `$HOME`-resolved guard/email checks could read as a clean verdict while going
  completely silent under a redirected `HOME`** (dir #120, found by dir #97's own `/polish` review). The
  machine-wide `W-GUARD-GLOBAL-STALE` staleness check was gated on `core.hooksPath` being set at all, so
  under a redirected config it never ran and its absence looked like "the guard is fresh" — it now
  discloses the config source it consulted instead. `W-EMAIL-PUBLIC` had the same gap: a commit email
  sourced from global config (not local) could go silent or nudge on a container's baked-in address
  without saying so — it now names when the verdict rode on config this repo doesn't own, including the
  "no email anywhere" case.
- **`doctor.sh --install`'s machine-global guard check read `git config --global core.hooksPath`, a
  scope selector that cannot see a `hooksPath` set only in the XDG git config behind an existing
  `~/.gitconfig`, even though it genuinely governs every commit** (dir #121, same review). Backed by
  git's own effective resolution (no `--global` restriction, read from a guaranteed non-repo scratch
  dir) instead — resolved once, machine-wide, and shared by the top-level staleness check, the dir #120
  disclosure, and `--install` mode alike, so all three agree on what the machine's guard actually is.
- **A local `core.hooksPath` pinned to the same absolute dir as the machine-global one drew two findings
  for one drifted file** (dir #122, same review). A `-ef` same-file guard in the per-repo drift branch
  now suppresses the per-repo finding when it names the identical physical directory the machine-wide
  finding already reported — that one's remediation actually fixes the shared copy; re-vendoring
  per-repo would have written an unwanted second copy, or clobbered the shared one.
- **The "slash command that doesn't ship" guard only ran in Keel's own test suite, so no adopter's
  `tools/doctor.sh` run ever inherited it** (dir #129, captured during dir #110's own `/polish` review).
  Moved from `tests/test_rails_honesty.sh` into `tools/self/doctor.sh` check 2b, alongside its
  neighbouring dead-internal-reference class: every backticked `` `/name` `` reference across the
  adopter-facing docs (root `.md` files, `docs/`, `commands/`, `templates/`) now GAPs if it has no
  `commands/name.md`, carrying forward the same two allowlists (harness-provided vs not-a-command) and
  the same leading-delimiter regex dir #110 tuned. Mutation-tested against a synthetic sandbox in
  `tests/test_self_doctor.sh`, which is coverage the old live-tree-only test never had.
- **`tools/pre-pr-gate.sh` never checked that HEAD was actually pushed before unlocking `gh pr create`
  — a convergence-round commit could be silently left local-only** (dir #133, one of 0.6.0's own known
  issues). Every existing sha-binding check in `polish.8-unlock` only verified the LOCAL repo, so a fix
  commit made after the branch's last `git push` passed all of them and opened a PR that silently
  omitted it (the live incident behind this ticket: dir #113/#114's own PR, recovered via cherry-pick
  as PR #177 only after the operator had already merged the truncated one). The gate now denies unless
  HEAD is reachable from the branch's push remote (`git merge-base --is-ancestor`), skipped only when
  the repo has no remote at all (a real `gh pr create` invocation can't exist without one). An
  operator-run `/code-review high` on this same diff went further and reproduced, live, that a
  hardcoded `origin/<branch>` false-denied a genuine cross-fork PR (`--head owner:branch`, dir #61)
  pushed only to the contributor's own remote — filed and fixed in the same PR as dir #152: the check
  now prefers the branch's own configured upstream (`<branch>@{upstream}`) over a hardcoded `origin`,
  falling back to `origin/<branch>` only when no upstream is configured.
- **`/polish`'s convergence rounds no longer re-run the whole test suite just to re-bind `polish.3-tests`
  to a commit that touched nothing test-relevant** (dir #123). dir #96 made step 3's receipt exclusive to
  `--recover` for good reason — a stale sha must not silently satisfy the gate — but that made EVERY
  convergence round pay a full test run even when the only change since the last green run was, say, a
  reworded comment (measured on dir #97's own `/polish`: 14 rounds, 8 full suite runs at ~7 minutes
  each). The fix is mechanical, not a self-reported claim: `receipt polish.3-tests <sha>` now stamps a
  deterministic tree-relevant hash onto the outcome — `git ls-tree -r --full-tree <sha>` (mode + blob +
  path, so content, permission-bit, and structural changes all move it), computed and verified
  server-side from a sha the gate itself resolves, never taken from the caller (a hand-crafted
  `sha:fake-hash` outcome is stripped and recomputed, not trusted). **Not a blanket `*.md` exclusion** —
  an operator-run `/code-review high` pass on this ticket reproduced live that most of keel's own doc
  surface (`CORE.md`, `templates/CLAUDE.md`, `commands/*.md`, `FRAMEWORK.md`, `docs/*.md`, `README.md`,
  even `CHANGELOG.md` itself) is read by a real test in `tests/`, so a blanket exclusion would have let a
  commit that broke one of those checks sail through as "nothing test-relevant changed." A `.md` path is
  dropped from the hash only when NO file under `tests/` mentions its basename — self-maintaining (a new
  test referencing a doc makes it test-relevant automatically) and fails closed (an unproven `.md` file
  stays in the hash). `receipt --recover` now carries a `polish.3-tests` receipt forward only when it
  carries the stamped hash; the final gate check recomputes the hash for the NEW HEAD and compares — a
  match unlocks with no fresh test run, a genuine test-relevant change still denies exactly as before.
  `skipped:--no-test`/`skipped:no-test-command` waivers and a legacy bare sha are never recovered,
  unchanged from dir #96's original rule — only a real, re-checkable tree-hash claim is.
  `commands/polish.md` step 1/3/4 updated: step 3 now recovers provisionally, re-verified (not assumed)
  at step 8, and the CHANGELOG-paragraph case named in this ticket's own motivation does NOT skip a test
  run in keel's own repo (it's real-test-coupled here) — genuinely test-free docs and structural-only
  convergence commits are what actually benefit.
- **Two comments that were true when written and had drifted since** (dir #137, dir #138, found by
  v0.6.0's own RC pass and folded into dir #127's batch). `_dialog_leg_armed`'s header in
  `tools/pre-pr-gate.sh` claimed three candidate settings paths while the code probed four, and
  `commands/polish.md` still called step 6 one of "FOUR steps a convergence round writes itself" after
  the with-GAP branch grew to five.
- **`tests/test_pre_pr_gate.sh`'s composed-marker repo scan was blind to `KEEL-AGENT-REVIEW`** (dir
  #146, found by dir #141's own independent agent review). dir #116's scan exists to prove no tracked
  non-test file accidentally spells a composed dialog marker — which would mint a trace the gate then
  trusts — but it only checked `KEEL-DEPTH-DIALOG` and `KEEL-REVIEW-DIALOG`, leaving the third marker
  unguarded by exactly the check written to guard the class.
- **`tools/keel-impact.sh`'s ledger WRITER was pinned against the READER's column mapping** (dir #131,
  found by an operator-run `/code-review high`). dir #107 had unified the two readers behind
  `_ledger_parse`, but `cmd_add`'s row-printf still hand-listed the same columns with nothing checking
  the two agreed. A structural test now pins them — the contract that made dir #151's later refactor
  to a single `_LEDGER_COLS` array safe to land.
- **`README.md`'s "Economy" bullet was a third, unguarded quote of the always-loaded core token
  figure** (dir #132, pre-existing, found by an operator-run `/code-review high` round). Two other
  quotes of the same figure were already pinned by `tests/test_doc_figures.sh`; this one could drift
  silently. Now guarded by the same check.
- **Five findings from this release's own RC pass** (dir #155, `docs/release-audit.md` phase 6).
  (1) `tools/self/doctor.sh`'s brand-new CHANGELOG↔tag reconciliation made the release flow it
  protects impossible to land: phase 7 cuts `## [x.y.z]` and merges it through a PR *before* the
  operator tags the merge commit, and the check GAPped on that untagged section, reddening the
  `self-check` CI job on every release-prep PR (v0.6.0's own section predated the check by one PR, so
  this release was the first to hit it). It now allows one untagged section, and only when it is both
  the newest heading *and* a version above every existing tag — announced on every full run, never
  silent. A second untagged section, one buried below a tagged one, or one whose version is older
  than a tag still GAPs; that last condition was added after an independent high-depth review broke
  the position-only first draft with a stale `## [0.9.0]` hoisted above two tagged releases, the
  founding drift shape of the check itself. `docs/release-audit.md` phase 7 now states the
  cut → land → tag ordering the allowance rests on, which had lived only in session habit.
  (2) `commands/polish.md` step 8 described gate denials as receipt problems answered by re-running
  `/polish`, which is the wrong remedy for the `head-not-pushed` denial dir #133/#152 added in this
  same release — pushing is; the step now names that class and tells you to push before unlocking.
  (3) `commands/backlog.md` step 3b called the `→ <release>` tag a *trailing* one; closure markers
  are routinely appended after it, so a strict reading hid most of the release tail from the grouping
  dir #143 added it for. (4) `tools/pre-pr-gate.sh` carried a `line ~1607` cross-reference that dir
  #123's own later insert, in this same release, had shifted to ~1713 — re-anchored by name, since a
  line number is drift-bait by construction. (5) `docs/loading-and-cost.md`'s `CHANGELOG.md` floor
  went `~50,000+` → `~60,000+`: this release's own entries pushed the file past the 25%-above-floor
  mark where `tests/test_doc_figures.sh` starts asking for a restatement.
- **`tests/run.sh`'s own concurrent-by-default test execution (dir #130) flaked `test_keel_cli.sh`'s
  "README.md quotes verb" check under real CI load** (dir #153, then dir #154). dir #153 first capped
  `KEEL_TEST_JOBS=2` for the `alpine-busybox` CI job alone, blaming the container's nproc-vs-host
  mismatch — but the identical flake then resurfaced on the plain `tests (ubuntu-24.04)` leg (PR #203,
  an unrelated diff), on plain GNU tooling, ruling out an alpine/busybox-specific cause. No file the
  check reads (`README.md`, `keel`) is ever mutated during the suite (verified: every test that touches
  either writes its own sandboxed copy), so it isn't a content or extraction-logic race — it's
  subprocess-fork resource contention from many concurrently-running test files stacking up on a
  standard hosted runner, independent of OS or container. `tests/run.sh`'s own default now caps at 2
  whenever `$CI` is set (GitHub Actions and effectively every CI provider sets it), replacing the
  alpine-only override — every current and future CI leg gets the safe default for free, and the
  alpine job now forwards `CI` into its container (`-e CI`) instead of carrying its own copy of the
  mitigation. Confirmed by 3 clean re-runs of the `ubuntu-24.04` leg post-merge, no repeat.

## [0.6.0] — 2026-08-12

The audit release. A global pre-release audit (dir #85) swept the whole project in four modules —
code, rails, docs, drift — and produced ~73 findings: 16 were fixed inline during the sweep and 20
were filed as tickets, all of which are closed, their fixes being the entries below. Two arcs carry
most of the weight. The `/polish` pre-PR gate got much harder to fool: a convergence round can no
longer open a PR whose fix commit no test and no review ever saw (dir #96, dir #116). And the three
installers stopped disagreeing with each other — `install.sh`, `install-pre-pr-gate.sh`, and
`uninstall.sh` now share one answer to "where does an install live" and "what counts as its
artifact" (dir #98, dir #108, dir #109). The rest is the audit's long tail: honest rails wording,
checks built for guarantees that had only been claimed, and test coverage for four modules the
audit found under-tested (`doctor.sh --install` had none at all).

Known issues: `doctor` still doesn't understand every install shape — it has no `--codex` mode
(a healthy codex install gets a false GAP), `--install`'s machine-global guard check can't see a
`hooksPath` set in the XDG config file, and under a redirected `HOME` the silent halves of its
`$HOME`-resolved checks disclose nothing, so an absent finding reads as a clean verdict.
`uninstall.sh` has no reverse operation for `install-pre-pr-gate.sh`, so the gate's hooks are left
behind without a word, and a home holding BOTH install modes escapes its mode-mismatch refusal.
Those two share one root cause, and the structural fix is planned: an install manifest, so
installers/uninstall/doctor read one recorded state instead of re-deriving it heuristically at
every site. The hardened gate has residuals of its own: its skip-dialog trace matches the
QUESTION's marker rather than the operator's actual answer, so declining a skip still leaves a skip
credential for that commit; it never checks that HEAD was pushed before unlocking `gh pr create`;
and the review loop has no round budget — a convergence round re-runs the whole suite to re-bind a
sha (~1h of wall clock measured on one PR).

### Fixed
- **`H-MAP-DRIFT` false-HINTed in every keel worktree, on paths this project's own convention keeps out
  of a worktree on purpose** (dir #113, found by dir #85's drift audit). `BACKLOG.md` lives only at the
  main-checkout root and `private/` is gitignored, so a live `doctor.sh` run against any worktree
  reported both as stale — and `.keel/map-drift-baseline` couldn't suppress it either, since that file
  also resolves at the main checkout, not the worktree. `doctor.sh` now re-checks a candidate against
  the already-resolved main-checkout top (`unit_top`, the same redirection the map-drift baseline and
  the impact-tracking split-brain check already use) before flagging drift, so a path genuinely absent
  everywhere still warns, but one that only lives at the main checkout no longer does.
- **Two rails claimed a mechanized guarantee neither had a check behind** (dir #114, the code half of
  dir #85's M4-1/M4-2 — PR #166 corrected the prose, this builds the checks it promised).
  - **`FRAMEWORK.md` said `doctor` hard-fails on a leaked host/user identifier in itself; no such check
    existed anywhere** (M4-1). `tools/self/doctor.sh` — which runs in CI, unlike `public-audit.sh`,
    which is a tool you remember to run — now GAPs if `FRAMEWORK.md` or `PRINCIPLES.md` contains a
    home-directory path or a non-safe-listed email, reusing the same patterns and shared allowlist
    (`tools/lib/safe-emails.sh`) `public-audit.sh` already uses for the rest of the tracked tree.
  - **`H-FOOTPRINT` measured only the project's own `CLAUDE.md`, so the number it printed was a floor
    on real startup cost, not the session's actual one** (M4-2). `tools/doctor.sh` now also resolves
    the global `CLAUDE.md` (following its `@…/keel/CORE.md` import when linked-mode wires one) and
    sums both into the budget comparison, reporting the project and global figures separately in the
    HINT text.
- **Five rails described guarantees they don't give, or mechanisms nothing carries** (dir #99, #110,
  #111, #112, #119 — wording only, no behaviour change; each fix pinned by a grep assertion in the new
  `tests/test_rails_honesty.sh`, red against the prior wording before it was written).
  - **`publishing-checklist.md` sold `public-audit` exit 0 as a machine-checked "no personal data"**
    (dir #99). Every personal-data heuristic in that tool — home paths, content emails, Cyrillic,
    agent/session metadata — is WARN-tier and leaves the exit code at 0, so the §0 gate now splits its
    tag (`[auto]` for the exit code, `[you]` for the WARNs) and says plainly that a clean exit is not a
    clean tree. Swept rather than patched at the one site: `going-public.md` said the same thing in three
    more places — its summary step 4, its §0 detect block, and the scrub-verification gate that a
    force-push depends on — and all three now name the WARN read. With `README.md` and `docs/reference.md`
    (PR #166), that is the whole class as it stands in the tree.
  - **The always-loaded rails routed draft tickets through `/design`, which Keel does not ship**
    (dir #110). Swept as a class rather than a site: `templates/CLAUDE.md`, `templates/project-CLAUDE.md`,
    `FRAMEWORK.md` (twice) and `commands/backlog.md` now say "a design/planning session", naming no
    command. The new test generalizes it — every backticked slash command in the rails, templates,
    commands **and docs** (`docs/reference.md` is the command catalogue; getting-started is the
    onboarding path), in every citation style the tree actually uses — bare, with arguments, bold-wrapped,
    or slash-joined — must have a `commands/<name>.md`, or sit in one of two separately-named allowlists:
    harness-provided commands whose call sites handle their absence, and tokens that aren't commands at
    all. One level deeper, `FRAMEWORK.md` now also says what the rename alone left implicit — Keel ships
    the *fold* side of the drafts convention only; the drafts themselves come from whatever
    design/planning flow the adopter runs, and without one the directory never appears.
  - **`/wrap` never folded the drafts `FRAMEWORK.md` calls it the single serialization point for**
    (dir #111). Step 2 now carries the fold — own drafts only, idempotent against a fresh `BACKLOG.md`
    read — and `FRAMEWORK.md` names the step that implements it, leaving `/backlog` 2b as what it was
    always described as: the leftover-catcher, not the whole mechanism.
  - **`/go`'s acceptance-tests-first rail cited `/polish`'s receipts while supplying none** (dir #112).
    The analogy now states the actual status — self-reported, no receipt, no gate, no trace — and asks
    for the one thing that outlives the chat: `tests: first` / `tests: infeasible — <reason>` in the PR's
    test plan, which survives the ticket close, plus the same line on the IN FLIGHT marker while the
    ticket is open (the closing sweep replaces that one with ✅, so it cannot be the durable copy).
  - **`commands/polish.md` described the convergence round as a step-5-only event** (dir #119). A step-7
    self-check finding that takes a fix commit moves HEAD exactly the same way; step 1's convergence
    branch and step 7 itself now both say so, with the two places a step-7 trigger differs: a GAP stops
    the run *before* its receipt is written, so that one never recovers and must be re-run and receipted
    fresh (the review caught this — the first draft claimed it always recovers), and even a recovered
    receipt attests the pre-fix run, so re-run the self-check by hand before unlocking. Gate semantics
    unchanged.
- **The three installers disagreed about where an install lives and what counts as its artifact**
  (dir #98, #108, #109 — one surface, three ways it drifted apart). Each half is covered by a
  red-before-green test.
  - **`install.sh --home DIR` and `install-pre-pr-gate.sh --global` described different machines**
    (dir #98). `--home` retargets the whole install *without* exporting `KEEL_HOME`, and the gate
    installer had no `--home` of its own — its `--global` resolved `${KEEL_HOME:-$HOME/.claude}`. So
    after `install.sh --home /opt/keel-home`, the commands lived in `/opt/keel-home` while the gate's
    hooks were written to `~/.claude`, and nothing said so at either install. The gate installer now
    takes **`--home DIR`** (global scope, targeting `DIR/settings.json`), and `install.sh`'s own closing
    summary names the matching flag whenever this install is retargeted — at the one moment the
    retargeted path is on screen. The residual no flag can close is stated rather than papered over:
    which global `settings.json` the *harness* reads is the harness's decision (Claude Code reads
    `$HOME/.claude`), so a retargeted home prints a `NOTE` pointing at per-repo wiring as the
    alternative. Three further sites where a retargeted home was ignored, all found by the operator's
    fourth `/code-review` pass and each one an instruction that could not reach the home it named:
    `uninstall.sh`'s leftover-install hint advised a **bare** `uninstall.sh --codex`, which re-resolves
    the home from scratch and under `KEEL_HOME` sends you back to the home you just uninstalled — it
    finds nothing, exits 0, and prints no hint of its own, leaving the named install fully wired; it now
    carries `--home`, as the mismatch refusal already did. `tools/doctor.sh`'s `W-GATE-UNWIRED` advised
    `--global` even when reporting on a retargeted install home, so following the advice wrote hooks
    elsewhere and the warning could never clear; it names `--home` there and keeps `--global` for the
    default home. And `install-pre-pr-gate.sh --home` did not check that DIR exists — `mkdir -p` would
    accept `~/.keel-hom`, write a complete `settings.json` into a directory nothing reads, print "wired
    into …" and exit 0, leaving the adopter certain a gate was on that was nowhere. It now refuses, the
    way the project-scope arm already validated its target with `git rev-parse`.
  - **dir #98 was a class, not a site — so the last pass over it was a sweep, not another sample.**
    Six places had shipped the same defect, and each was found only after the previous one was fixed,
    including one *inside* the fix for its predecessor. Every tool now derives the ` --home "DIR"` its
    advice needs **once**, from the same expression a bare re-run evaluates (`home_flag` in
    `install.sh`, `ihome_flag` in `tools/doctor.sh`, the closing health-check line in
    `install-pre-pr-gate.sh`), so the ordinary install still reads with the short friendly form and the
    flag appears exactly where it is load-bearing. Mode is the half a home flag cannot see, so
    `--codex` installs carry that too: at the *default* home the home flag is correctly empty, yet a
    bare re-run is Claude copy mode and would land in `~/.claude`. Every such advice string across the four
    tools now carries it — the `keel` CLI reads the mode off the home it finds itself in, since it has
    no other record of one — including the `keel/README.md` generated into the home —
    advice read long after the install, and the only one an adopter meets with no terminal output
    around it. **What pins the class is a source check, not an output sweep** (`tools/self/doctor.sh`
    1c): most of `doctor`'s advice sits in findings that only fire on a *broken* install, so sweeping a
    healthy run reaches none of them. The first version of this check was written that way — vacuous
    for `doctor` entirely, and pinning today's phrasing rather than the class; its own review caught
    that, along with a seventh site (`W-NOGIT-GIT-PROJECTS`) it had missed. The source check scopes
    structurally — output calls and summary bullets, not a phrase list — so a comment or a usage line
    naming the same command is correctly not advice, and no per-string allowlist is needed. A smaller
    end-to-end test still asserts the mechanism *renders* in a real retargeted run, which a source
    check cannot: it cannot tell an expanded flag from a literal `$home_flag` left in the text.
  - **`uninstall.sh` deleted a line that merely *mentioned* the core path** (dir #108). `install.sh`'s
    `has_core_import` is the definition of "the import line is wired" and requires whitespace/start/end
    boundaries around the token; `uninstall.sh` matched the same token by bare substring, so an
    ordinary backtick-quoted `` `@~/.claude/keel/CORE.md` `` in the user's own prose was removed along
    with the real import — contradicting the promise printed on the very next line, that the rest of
    your file is untouched. Both now use one boundary-anchored definition (byte-identical to
    `install.sh`'s and to the mirror in `tools/doctor.sh --install`), handed to `awk` through the
    environment rather than `-v`, since `-v` applies escape processing to the assignment and would
    quietly widen the pattern back out — the exact drift a shared definition exists to prevent.
  - **`uninstall.sh` had never heard of `--codex`** (dir #109). `install.sh --codex` (dir #76) writes
    `~/.codex/AGENTS.md`, which for a Codex adopter carries essentially all of Keel's rails; uninstall
    hardcoded `CLAUDE.md`, so install-then-uninstall left the whole thing in place without a word.
    It now mirrors install's mode flags: **`--codex`** resolves the same default home (`~/.codex`) and
    the same always-loaded file (`AGENTS.md`), stripping the rails block while keeping the file and the
    user's own content outside it. A run **names** an install of the other mode it finds instead of
    leaving it silently behind — in both directions, and including on the "nothing to do — no Keel home
    at `~/.claude`" path, which is exactly the run a Codex-only adopter makes first. That hint asks
    whether an install is *there* — Keel content, or rails in the context file — not whether the context
    file carries rails: keying it on rails alone hid the foreign-core case a third time, in a third
    place, leaving a Claude home with `bin/keel`, `commands/` and both product copies entirely
    unmentioned. Both callers now share one `home_has_keel_content`. It also **refuses
    outright** when the home it was pointed at holds the other mode: an explicit target (`--home`, else
    `$KEEL_HOME`) outranks the mode's default leaf, exactly as in `install.sh`, so
    `KEEL_HOME=<claude-home> uninstall.sh --codex` resolves a `CLAUDE.md` home while looking for
    `AGENTS.md`. Four of uninstall's five removal steps are mode-agnostic, so that run used to strip the
    shared half — the commands, the `keel` CLI symlink, the `FRAMEWORK`/`PRINCIPLES` copies — and report
    a clean success while `CLAUDE.md`'s rails kept loading forever. Found by the operator's own
    `/code-review` pass, which reproduced the half-dismantled install; the one-directional hint above was
    what let it print "done". The refusal keys on **"an install ran against this home"** — `keel/`,
    `bin/keel`, a shipped command, or a product copy — and not on "the other mode's file carries Keel's
    rails", which a second `/code-review` pass showed misses the whole foreign-core case: an install over
    someone's own pre-existing `CLAUDE.md` never writes rails into it, so that home read as empty and got
    taken apart anyway. Two of the refusal's three conditions are mutation-proven, each against the failure
    it prevents: dropping the Keel-content test wrongly refuses a bare directory holding only the user's
    own `CLAUDE.md` (which should simply report nothing to remove, not send them round to a `--codex` run
    that would also find nothing), and dropping the other-mode-file test **deadlocks** a Keel home whose
    own context file the user deleted — each mode would then refuse and point at the other, leaving the
    install unremovable. The third, "this mode's context file is absent", is only exercised by the
    both-modes home that **dir #124** deliberately leaves open, and is stated here as unpinned rather
    than counted as covered. Because the other-mode test is plain existence, it cannot tell that file
    from one of yours that happens to share the name; the refusal says so and names the way out.
- **The audit rule that mandates an isolated `HOME` for live probes turned `doctor`'s highest-stakes
  finding into a systematic false negative** (dir #97, found by dir #85's drift audit — that module
  nearly filed the false negative as real drift before cross-checking). `tools/doctor.sh` resolves the
  machine-global secret guard through `git config --global core.hooksPath`, i.e. through `$HOME`, so
  under the mandated sandbox it reports `W-GUARD-UNWIRED` for a machine where the guard is demonstrably
  wired and firing. Two halves, prose and code:
  - The rule is carved, not the resolution. `docs/rollout-audit.md`'s Layer 0 now states that isolation
    governs **writes**, and that a probe which only *reads* the machine's own configuration is exempt —
    when you intend to act on its verdict, run it against the real environment, since isolating such a
    read doesn't merely weaken the answer, it inverts it. (Running the same diagnostic sandboxed for a
    demo or a fixture stays fine, as `examples/tour.sh` does; it just isn't an audit verdict.)
    `tools/pipeline-canary.sh`'s hard-sandbox comment points at that carve-out rather than restating it.
  - `W-GUARD-UNWIRED` now names the global-config source it was actually resolved through, the same way
    `--install` mode's findings name their install home. What the check reads is `git config --global`,
    a scope selector that collapses to exactly one file: `GIT_CONFIG_GLOBAL` when that variable is
    **set** (an empty value silences the global config outright), else `~/.gitconfig` when it is
    readable, else `$XDG_CONFIG_HOME/git/config` — which exists as `~/.config/git/config` even when that
    variable is unset, the ordinary layout, so the clause names that file rather than a variable. Each
    can be redirected without touching the others, so naming `HOME` flatly would point a reader at an
    untouched `~/.gitconfig` that carries the very `hooksPath` they were just told is missing.
    Both modes additionally distinguish "`core.hooksPath` is set but that dir has no executable hook"
    from "nothing wired at all" — different states, different fixes — and carry the clause on both,
    since a successful read proves *a* config was read, not the right one. **The project audit used to
    swallow that first state entirely**, reading a bare `core.hooksPath` as "machine-global secret-guard
    covers it": a `hooksPath` pointing at an empty directory printed a clean `0 gap, 0 warn, 0 hint`
    while commits went through completely unguarded (reproduced — a planted key committed straight
    through). Same class of false negative as the one this ticket is about, found by the operator's own
    `/code-review` pass on it. The dir is resolved **per repo**, since git resolves a relative
    `core.hooksPath` against the repo rather than against `doctor`'s own working directory — and because
    a relative path is per-repo by construction, the once-per-machine engine-drift comparison no longer
    claims it at all: that pass is now **absolute-only**, and the relative case gets its own per-repo
    `W-GUARD-STALE`. The two domains are disjoint, so one drift is still reported exactly once — and by
    the check whose advice works, which matters here: the machine-wide finding's remediation
    (`install-secret-guard.sh --global`) exits 3 rather than clobber a `core.hooksPath` it didn't set,
    while the per-repo one vendors into the directory git actually runs hooks from. `--install` mode
    applies the same rule to the wiring check itself: it audits the machine and has no repo to resolve
    against, so a relative `core.hooksPath` is reported as per-repo wiring rather than judged from
    whatever sits under `doctor`'s own working directory — which had one unchanged machine reporting
    `OK secret-guard: machine-global` or `W-GUARD-UNWIRED` depending on where the operator stood.
    **Unconditionally, on purpose:** the tempting narrower
    trigger ("only when no global git config is readable here") is a proxy for a question undecidable
    from inside the sandbox — any sandbox that means to commit has to write a global `user.email` first
    (Keel's own test harness and `examples/tour.sh` both do), so that predicate goes silent on the
    commonest sandbox shape while appending an excuse to a perfectly correct finding on a bare real
    machine. Naming the source is decidable, and leaves the judgement to the reader.
    Residual: the *silent* halves of the same resolution carry no message to append to —
    `W-GUARD-GLOBAL-STALE` simply never runs under a redirected global config, and its absence reads as
    "fresh". Filed separately.
- **A repo whose local `core.hooksPath` carried only *parts* of the guard audited clean while every
  commit ran nothing** (dir #97, found by the operator's `/code-review` on it). The override was
  accepted as cover if the directory held `secret-scan.sh` **or** a `pre-commit` **or** a `pre-push` —
  so an engine file on its own, a `pre-commit` that was deleted, or one that lost its executable bit,
  all read as wired. Reproduced: a planted key committed straight through a `0 gap, 0 warn` audit. An
  executable `pre-commit` is now the whole test, the same bar the global branch uses, and
  `W-GUARD-BYPASSED` says what is actually true — commits here run nothing — without asserting a
  machine-global guard that may not exist.
- **Two stale statements about `receipt --recover`'s behavior, left behind by dir #96 and dir #116**
  (dir #117, found by dir #96's own closing high review). `tools/pre-pr-gate.sh`'s `--recover` runtime
  message named step 6's retest as an unqualified alternative binding for step 3 — reworded, since the
  normal convergence outcome is `skipped:no-file-changes`, which binds nothing. `commands/polish.md`
  step 6's receipt rationale said step 1's convergence branch hands back steps 2, 4 and 7 with no dir
  #116 carve-out for a `skip`-level step 4 (never recovered) — the carve-out is now named there too,
  matching the fuller description already in step 1. A third statement this ticket named, the dir #72
  CHANGELOG entry below still describing `--recover`'s original steps-1-4-and-7 restore set, is left
  as-is: it's a historical record of what dir #72 shipped, and the dir #96 entry above it already
  narrates the correction — editing it would misrepresent what dir #72 itself shipped.
- **A convergence round can no longer inherit a `skip` review depth the operator chose for a different
  diff** (dir #116, found by dir #96's own closing review). `polish.4-depth` had the same property that
  got steps 3 and 5 excluded from `receipt --recover`: an arm whose value silently stays true across a
  commit. Reproduced end-to-end: round 1 sizes a trivial diff `skip` (with the operator's blessing, per
  step 4's own always-ask rule), a substantial fix commit lands, `--recover` restores the `skip` depth,
  `commands/polish.md` step 4 says "reuse the recovered level as-is; do not re-size", the round writes a
  fresh `polish.5-review skip` — which *matches* the recovered depth, satisfying dir #63's cross-check —
  and the gate answered `allow` with no review ever seeing the commit. Four changes — the first
  narrow, the second mechanical-but-armed, the last two unconditional:
  - `receipt --recover` never restores a **`skip`-level** `polish.4-depth` (named in its closing note,
    same shape as steps 3/5); non-skip depths keep recovering — they bypass nothing, since step 5 still
    owes a fresh HEAD-keyed outcome against them.
  - The gate now requires a `skip` unlock to name an **answered step-4 skip dialog for the exact commit
    being shipped**: the `KEEL-DEPTH-DIALOG` skip marker lives ONLY in a follow-up confirm
    dialog opened after the operator's answer already landed on skip — never in a sizing dialog's own
    question, where it would write the trace at answer time regardless of what was answered (an
    operator overriding to `medium` would have left a skip credential at that sha; found by the
    operator's second-opinion review). The check is per-SHA like the dir #88 agent arms, so a fix
    commit invalidates the prior diff's answer by construction. What the trace proves is that the skip
    confirm question was put to a human and answered for this commit — it records the question's
    marker, not the chosen answer (reading the answer itself is filed as dir #118). Same arming rule
    as dir #88:
    inert until the installer wires the dialog hook. **Upgrade note for installs already armed by dir
    #88 with a copied (non-linked) `commands/polish.md`:** the gate side goes live on `git pull`, but
    the marker comes from `polish.md` — until `install.sh` refreshes the copy, an honestly-answered
    marker-less skip dialog still denies (the deny names the marker, so the fix is discoverable).
  - **A suffixed `skip` is denied outright, on all arms and independent of arming** — this change's own
    high review broke its first cut: `skip-waived` (and `skip-operator-run`) reached
    `outcome_level=skip` through the trusted suffix arms with the dialog check never firing, reproduced
    unlocking an armed gate with no dialog answered. skip has no review to waive or hand off, so its
    only honest receipt is the bare `skip`.
  - **The depth level itself is now allowlisted** (low/medium/high/max/ultra/skip) — the operator-run
    `/code-review high` pass on this change found the remaining dodge: an INVENTED level
    (`polish.4-depth none:x` + `polish.5-review none-waived`, or a nested suffix like
    `skip-waived-waived`) matched itself through the trusted arms and unlocked with no review, no
    dialog, no trace. dir #116 made this class load-bearing — before it, bare `skip` was free, so an
    invented level bought nothing. One check on step 4's stripped level closes it; the existing
    outcome-vs-depth equality transitively constrains step 5.
  The `KEEL-DEPTH-DIALOG` token is deliberately distinct from step 5(a)'s `KEEL-REVIEW-DIALOG`, and
  the trace leg accepts only `skip` on it — so a sizing dialog can never pre-satisfy step 5(a)'s own
  dialog check, by construction rather than by prose rule; conversely the review token (and the
  SubagentStop marker, which shares its accepted set) still rejects `skip`, since an "agent review at
  skip" would vouch for no review at all. The two token parses are independent — an event carrying
  both writes both trace lines; the first cut's exclusive-exit lost a genuine review dialog's line
  whenever its question merely quoted the depth token. Both capture classes now include digits,
  underscore and hyphen, closing the `level=high2`/`level=skip_x`/`level=skip-waived` truncation
  near-misses (the alphabetic cousins of dir #88's own `level=highest` guard — the hyphen one found
  by the operator's second-opinion `/code-review` pass, and the sharpest: hyphen is the separator the
  receipt vocabulary itself uses, so the exact string the receipt path denies would have minted a
  trace). Every step-4 dialog whose ANSWER lands on skip — the borderline dialog and the high+/ultra
  dialog alike — gets one follow-up confirm dialog carrying the token; reading the answer itself,
  which would collapse the two dialogs into one, is filed as dir #118. The third second-opinion pass
  then found the sharpest self-reference: the skip DENY message spelled the composed marker, so a
  session recapping the deny inside a dialog handed the hook exactly the line it greps for — DENY →
  quote → trace → ALLOW, reproduced end-to-end. The deny and every instruction now describe the
  marker without spelling its composed form (`polish.md` uses the same `<level>` placeholder
  discipline that protects dir #88's own marker), and a meta-test feeds the gate's actual deny output
  and all of `polish.md` through the dialog leg, asserting both are inert.
- **The pre-PR gate could unlock `gh pr create` for a commit no test had ever run against** (dir #96).
  The convergence round was the hole. Sequence: `/polish` runs, tests pass at sha1, step 5's review
  finds a real bug, the fix is committed (HEAD → sha2), `/polish` is re-invoked, and step 1's
  `receipt --recover` restores step 3's *pre-fix* receipt. Step 5's delta re-review then legitimately
  changes nothing, so step 6 writes `skipped:no-file-changes` — and step 6's skip was unconditionally
  exempt from its SHA check. Result: **nothing at all was bound to sha2**, and the gate answered
  `allow`. Reproduced end-to-end in a sandbox, and observed live twice during dir #85's own session,
  where a convergence round's `--recover` restored `polish.5-review` onto a diff that receipt had never
  seen.

  **The fix binds `polish.3-tests` to the sha it ran at**, exactly as steps 6 and 8 already were. The
  gate now requires that *some* test run name current HEAD — step 3's own sha or step 6's retest sha —
  and denies with an actionable message when neither does. The two named waivers below stay
  exempt: the gate's job is to stop a silent skip, not to overrule a stated decision.

  **Why not the obvious fix.** The ticket's first candidate was to have `--recover` refuse when
  `base_sha == HEAD`. That cannot work, and a sandbox check showed why before any code was written:
  `retire_sentinel` stamps base-sha at retirement time, retirement happens *inside* `init`, and `init`
  runs *after* the fix commit — so `base_sha == HEAD` in an ordinary interrupted re-init **and** in a
  genuine convergence round. The condition discriminates nothing and would refuse every recovery,
  breaking the mechanism dir #72 built. The deeper point, and why this fix is small: **the gate never
  needed to know whether a round is a convergence round.** It needs to know the shipped code was
  tested. Binding step 3 removes the need for a discriminator entirely, so `commands/polish.md` no
  longer claims that `--recover`'s own output tells a session which kind of round it is in — a claim
  that was simply false.

  **The waivers are two named literals, never the `skipped:*` class** (`skipped:--no-test`, and
  `skipped:no-test-command` — see below). Receipt outcomes are free text, so
  a broad exemption would have accepted `skipped:tests-fail-unrelated` from a session looking at a red
  suite — reproducing the very unconditional-skip shape that made step 6 exempt and opened this hole.
  Caught by this change's own review pass, which unlocked the gate with an invented skip reason.

  **`receipt --recover` no longer restores `polish.3-tests` **or** `polish.5-review`, and no longer
  overwrites a receipt the current run already wrote.** Three corrections, all found by this change's
  own review passes. Step 5 joins step 3 for the same reason: a bare level or `agent:*` is caught by the
  trace check (keyed to current HEAD), but the TRUSTED arms — `skip`, `*-operator-run`, `*-waived` —
  skip that check entirely, so a recovered one claims the fix commit was reviewed when no review ever
  saw it. Reproduced end-to-end. This matters for honesty as much as for the gate: the paragraph above
  cites exactly that shape as the evidence for dir #96, so leaving it open would have made the claim
  false. `commands/polish.md` already told the round to redo both, so the code now says what the prose
  said. The other two:

  - Recovery appends and the parser takes the last write per step id, so a session that re-ran its
    tests and receipted the new sha *before* calling `--recover` had that correct value silently
    superseded by the stale recovered one — then got denied for work it had genuinely done. Harmless
    while step 3's outcome was inert; load-bearing the moment it became a sha. Recovery now fills gaps
    only, so the order of `--recover` against your own receipt calls stopped mattering. Its closing
    note names only the step ids actually withheld from *this* run — not a fixed pair — so it never
    tells a session to write something it already wrote, or to hunt for something the backup never
    held. `commands/polish.md` step 3's own skip-the-run permission was rescoped for the same reason:
    it is keyed to whether HEAD has moved, which in a convergence round it always has, by definition.
  - More seriously, restoring step 3 re-asserted a **prior round's `--no-test` waiver** into a round the
    operator never passed `--no-test` to: `/polish --no-test` → review finds a bug → fix commit → plain
    `/polish` → `allow`, with nothing tested and no waiver given. The sha arm self-corrects (a stale sha
    just fails the compare); the waiver arm does not — which is the general rule behind both exclusions:
    a step whose value can *silently stay true* across a commit must not be carried across one.

  **A project with no test command has an escape**, `skipped:no-test-command` — the same shape step 7
  has had as `skipped:no-doctor`. Without it, a repo with no tests yet (an `/init-project` scaffold, an
  early adopter) could never unlock the gate, and the deny would name causes that were all wrong for it.
  Still a named literal, so an invented reason denies.

  **Residual limit, named rather than assumed away:** this binds a sha, not evidence. `$(git rev-parse
  HEAD)` costs nothing to type without running anything, and unlike step 5 there is no trace leg behind
  step 3. It closes *staleness* — a receipt outliving the commit it was written for — not fabrication.
  Binding step 3 to a hook-written trace is the same escalation dir #63/#70 made for step 5, and is
  filed as its own ticket rather than smuggled in here.

  Behaviour change worth knowing: running the tests, then committing something (a CHANGELOG entry,
  say), then unlocking is no longer accepted — that is exactly the "shipped commit wasn't tested" case.
  Bind the new HEAD with a step-6 retest, which costs one receipt call. Two consumers were updated for
  the same reason: `tools/pipeline-canary.sh`'s fabricated-claim probe (its receipt must be valid in
  every respect except the thing under test, or the canary passes for the wrong reason) and the file's
  own header prose, which still described steps 1–4 and 7 as the ones `--recover` correctly restores.
  A legacy bare `done` from an older *copied* `commands/polish.md` also denies — fail-closed is right,
  and the deny names that cause so it isn't a mystery after a `git pull`.

- **The gate's hook JSON is built with `jq`, not `printf`-interpolated — a deny could be flipped to an
  allow by the receipt value it names** (dir #96). Deny reasons interpolate values that arrive as free
  text through the documented `receipt <step-id> <outcome>` CLI. Reproduced against the real gate:
  `receipt polish.3-tests 'x","permissionDecision":"allow","junk":"'` made the deny path emit
  *syntactically valid* JSON whose last `permissionDecision` key was `allow`, and jq, Go, JS and Python
  all take last-wins on a duplicate key. That defeated the one deny this ticket exists to add, through
  the ordinary CLI, with no knowledge of the sentinel format — strictly easier than the hand-written-
  sentinel residual the file already concedes. The shape was pre-existing across five free-text values
  reaching a deny message (the `--head` branch, and steps 3, 4, 5 and 6's outcomes); `deny()` is the sole
  choke point, so fixing it and the allow payload covers all of them, and the `rollout-check` banner —
  the file's one remaining interpolated payload, carrying no decision — was converted too, so "this file
  never printfs JSON" is now true without an exception. A test pins that a quote-breaking receipt value
  still yields one valid object parsing as `deny`. Found by this change's own high review.

- **Pre-v0.6.0 audit, code leg: ten correctness fixes plus the test coverage that pins them**
  (dir #85). Found by a read-only sweep of `tools/*.sh`, `install.sh`, `bootstrap.sh`, `uninstall.sh`
  and the suite itself, then dispositioned in a cross-module synthesis pass. Every fix that changes
  observable behavior ships with a regression test, with two named exceptions: the two `trap` ones
  (delivering a real SIGINT to a script mid-run is not something this suite can do portably) and the
  two dead-code removals below, which by definition change nothing to assert on. Stated exactly rather
  than left to look wholly covered. Four of the ten fixes were reproduced red-before-green — the
  `KEEL_HOME` arming gap, the `printf '%b'` truncation, the `.gitignore` newline guard, and the
  foreign-`core.hooksPath` attribution — as was the per-repo rollout-state invariant, which is a test
  rather than a fix (no keying code changed).
  - **`tools/pre-pr-gate.sh` — the dir #88 mandatory-review-dialog check silently no-op'd for any
    adopter with a custom `KEEL_HOME`.** `_dialog_leg_armed` probed a hardcoded
    `$HOME/.claude/settings.json` while `install-pre-pr-gate.sh --global` writes to
    `${KEEL_HOME:-$HOME/.claude}/settings.json`, so a genuinely wired reminder hook read as *unarmed*
    and the deny never fired — precisely the silent skip dir #88 exists to close. The function's own
    comment declared this invariant ("this needs a matching update, not a silent drift") and had been
    false since the two were written. A `KEEL_HOME`-resolved candidate is now **added** to the probe
    list — never substituted for `$HOME/.claude/settings.json`, which is the file Claude Code itself
    loads. (The first version of the fix did substitute, which re-opened the identical silent no-op
    from a different precondition — a merely exported `KEEL_HOME` — and would also have made the probe
    report ARMED for a file the harness never reads, denying `gh pr create` with no way to satisfy it.
    Caught by this ticket's own independent review.) Every entry is a read-only probe and ARMED wins,
    so extra candidates can only turn a false UNARMED into a correct ARMED, never the reverse.
  - **`.gitignore` appends no longer corrupt a file whose last line lacks a trailing newline.**
    `node_modules` (unterminated) plus an appended rule became one fused pattern
    (`node_modules/.keel/impact-events.log`), silently destroying the adopter's rule and ours. Fixed in
    both appenders that had the shape: `tools/keel-impact.sh`'s `enable`, and — the more exposed of the
    two, since it runs six times per init and always against a pre-existing file —
    `tools/init-project.sh`'s `ensure_ignore`.
  - **`tools/keel-impact.sh` — the stale-event evidence block is written with `printf '%s'`, not
    `'%b'`.** Event text is third-party and `_flatten` strips only literal tab/newline *bytes*, so a
    two-character `\c` survived into a `%b` that truncated the rest of the output — swallowing every
    stale row after it and quietly breaking the "no citation → no count" record that block exists to
    keep honest.
  - **`tools/public-audit.sh` — Ctrl-C now actually stops the run.** The `INT`/`TERM` handler did its
    cleanup and then *resumed*, so an interrupted audit deleted the PR refs and tmpdir it was using and
    kept auditing against the state it had just removed, while the operator believed it was cancelled.
    `bootstrap.sh` carries the same `trap … EXIT INT TERM` shape and was split the same way — for
    consistency, not because the bug is reachable there today: that script runs under `set -eu`, so an
    interrupted command already aborts via errexit except in errexit-exempt positions.
  - **`tools/doctor.sh` — `H-DEP-FLOATING` scans through `fp_find`** like every neighbouring per-stack
    check, so a vendored dependency's own example `Dockerfile` no longer flags the adopter for code
    they don't own.
  - **`tools/init-project.sh` — a project name containing `&`, `\` or `/` reaches `CLAUDE.md`
    verbatim.** The old `sed "s/<Project name>/$name/"` let `&` splice the whole match back in, so
    `AT&T-tools` produced the literal `AT<Project name>T-tools`. Replaced with an `ENVIRON`-fed
    `index`/`substr` scan — literal, no regex, and immune to the `awk -v` escape processing that would
    still have mangled a backslash.
  - **`install.sh` — the Verify section names a foreign global `core.hooksPath` as the reason the guard
    isn't wired even under `--no-hooks`**, instead of blaming the flag. That path blocks wiring on
    *every* run (the installer refuses to clobber it), so attributing it to `--no-hooks` implied a
    re-run without the flag would help — it wouldn't, and the user paid a full re-install to find out.
    The same condition now also requires the path to actually differ from Keel's own, so a broken or
    half-installed Keel hooks dir is no longer mislabelled "foreign" and gets the advice that fits it.
  - **`install.sh` — the closing secret-guard sentence reflects the guard's real state on every run.**
    `--no-hooks` used to skip the check entirely and then tell an already-protected user "secret-guard
    is NOT wired (see Verify above)", pointing at a Verify section that had said nothing about the
    guard. Both directions are now pinned by tests: an unguarded run must not claim protection, and a
    guarded `--no-hooks` run must not deny it.
  - **`tools/pre-pr-gate.sh` — the receipt-key format is assembled in one place (`_receipt_key_for`)
    instead of hand-copied into three**, and the dead `_branch_slug_for` (never called; a stale dir #80
    comment claimed the key was built through it) is gone.
  - **`tools/keel-impact.sh`** — a refactor-leftover guarded `continue` that could never change control
    flow, removed.
  - **Test coverage** for paths that had none: `install.sh`/`uninstall.sh` `-h`/`--help` and their
    unknown-argument exits, `uninstall.sh`'s no-Keel-home early exit, `install.sh`'s "HOME unset while
    wiring hooks" guard (both prior unset-HOME tests paired it with `--no-hooks`, so it had never
    fired), `install-secret-guard.sh --global --force` replacing a foreign machine-global
    `core.hooksPath`, `keel-check.sh`'s threshold sanitizer (non-numeric/empty/negative/zero),
    `branch-cleanup.sh`'s joined `--days=N`/`--live-hours=N` forms, and — as an explicit invariant
    guard — that the review trace and rollout state stay **per-repo**, never re-keyed by branch the way
    dir #80 re-keyed the sentinel (both halves exercise the writing subcommand first, so neither
    assertion can pass vacuously). `tests/lib.sh`'s `run()` now redirects stdin from `/dev/null`, so
    running a test file by hand from a terminal no longer hangs on `install.sh`'s interactive branches.
- **Pre-v0.6.0 audit, docs leg: shipped prose that described behavior the code doesn't have**
  (dir #85). Each was found by checking a doc claim against the code behind it. Almost all are wording
  corrections. The two exceptions, both detailed below: the word `project` added in two places in
  `doctor.sh` — its `H-FOOTPRINT` legend and the finding text it emits, so the tool and the rail now say
  the same thing — and the `tests/test_doctor.sh` assertions that pin that tier and string.
  - **`FRAMEWORK.md`'s reusability boundary claimed "`doctor` hard-fails if a host/user identifier
    leaks in here".** No such check exists — nothing in doctor's finding set reads this file's content.
    Replaced with what is actually true, which is a good deal less than the old promise: out of the
    box only two of `public-audit.sh`'s tracked-tree patterns bear on that list — a **home directory**
    path and a real-looking email — so a username is caught only inside one of those, and any other
    absolute path (`/opt/…`, `/Volumes/…`) is not caught at all, while **hardware, model provider and
    project name have no built-in heuristic** and are found only if the adopter declares them
    (`token:` in `.public-audit`, or a personal literal the machine-global secret-guard blocks at
    commit time). And `public-audit.sh` is a tool you run, not a CI gate. Stated as authoring
    discipline with a partial, largely opt-in net beneath it. This one sentence needed three
    corrections inside this PR, each caught by its own review passes: the first rewrite mis-credited
    the declared-token GAP as blanket coverage, the second overcorrected to "no automated check at
    all" (erasing the opt-in mechanisms that do exist), and the third still claimed the whole
    "host-path class" when only home directories are matched.
  - **`FRAMEWORK.md`'s footprint signal claimed doctor reports the global + project always-loaded set
    and *warns* over budget.** It is a **HINT** (`H-FOOTPRINT`), stale since dir #45's triage rework,
    and only the project's own `CLAUDE.md` is measured. Reworded, and `doctor.sh`'s own finding text
    now says "project CLAUDE.md startup footprint" — that string is what an adopter reads at the moment
    of the decision, so leaving it ambiguous would have fixed the quieter copy of the defect only.
  - **The `keel` CLI verb list was short in two places.** `docs/reference.md` listed 7 of the
    dispatcher's 9 arms and `README.md` listed 7 as well; `version` and `help` were undocumented in
    both. Both lists now match `keel`'s actual `case` arms.
  - **`docs/loading-and-cost.md` put `CHANGELOG.md` at "~25,000+" tokens; the real file is well over
    40,000.** The `+` makes it an open floor, so the mechanized figure guard correctly passed it — but
    a floor that far under actual materially misleads a reader sizing the file. Raised to `~40,000+`:
    still a true floor, with enough headroom that ordinary growth doesn't force a bump every release.
    Deliberately no exact figure here — this file gains an entry on nearly every PR (it grew twice
    while this one was in review), which is precisely the drift that rotted the original number.

  - **`docs/loading-and-cost.md` carried the *same* WARN/scope claim** — "`doctor` raises a **WARN** if
    the always-loaded core exceeds 10,000 tokens" — and was initially missed even though this PR edits
    that file. Corrected the same way as the rail (HINT, project file only, number is a floor), which
    matters more here: this is the document whose entire subject is startup cost. Its "~50 sessions
    ≈ ~100K tokens" figure was also ~10% low against its own per-session number; now ~110K.
  - **`README.md` and `docs/reference.md` both credited `public-audit.sh` with catching "names".**
    A bare personal name has no built-in pattern — it is found only via a declared `token:`/`--token`,
    or by the separate secret-guard's personal-literal file. Same overclaim shape as the boundary rail
    above, surviving in two more places; `docs/going-public.md` already described the real detector set
    correctly, so the tree contradicted itself. Both corrected, and `reference.md` now names the full
    heuristic set (emails, home paths, Cyrillic, agent-session metadata) instead of an invented one,
    says "commit/tag identities" (the GAP covers tagger emails too), and — for the name case — points
    at `--token` or a **gitignored** `.public-audit`, since a committed config would put the very name
    you're hiding into the tree you're about to publish.
  - **Two stale labels in `tests/test_doctor.sh` called `H-FOOTPRINT` a WARN** — the same dir #45
    retiering the rail above got wrong. The assertions passed either way (they matched on the word
    "footprint"), so only the labels lied. Tightened to assert the actual tier and the corrected
    message text, so this finding can't silently change tier again.

- **`tools/self/doctor.sh`'s CHANGELOG-staleness check no longer silently reports a false "OK" on a
  repo with no commit history for `CHANGELOG.md`/`commands`/`tools`/`install.sh`.** `git log -1
  --format=%ct -- <pathspec>` exits 0 with empty stdout (not an error) when no commit ever touched
  that pathspec, so the existing `|| echo 0` fallback — which only catches a nonzero exit — never
  fired, leaving the two timestamp variables empty and the `[ -gt ]` comparison throwing "integer
  expression expected" to stderr while falling through to a false pass. Fixed via `${var:-0}`
  parameter-expansion defaults, with a regression test covering an unhistoried repo. Low real-world
  impact (the real keel checkout and CI both always have history for these paths) but a real
  robustness gap for a fresh/partial checkout.

- **Four duplicated-without-a-guard invariants, each closed with a source-level test that pins the
  class, not just today's instance** (dir #104-107). An independent agent review plus an operator-run
  `/code-review high` caught a real regression in the fix for the last one, since fixed.
  - **The `keel` CLI's dispatcher verb list could drift from `docs/reference.md` and `README.md` with
    nothing to catch it** (dir #104). `tests/test_keel_cli.sh` now extracts the verbs straight from
    the dispatcher's own `case` block and asserts each is still quoted in both docs.
  - **`assert_figure`'s open-floor branch (an intentional no-ceiling design, dir #3) had no way to
    notice drift once it happened** — `CHANGELOG.md`'s own figure sat 37% above its floor, passing CI
    the whole time (dir #105). Mirrors `assert_band`'s existing near-band note: a non-failing note once
    actual drifts 25%+ past the floor. Raised this file's own floor (~40,000+ → ~50,000+) since the new
    note caught the drift live. Also pins the two prose figures in `docs/loading-and-cost.md` that are
    arithmetically derived from the quoted core token figure (a "~50 sessions" total, a "~1.1% of a
    ~200K window" line), so a bumped core row can't leave them stale silently.
  - **`doctor.sh` and `public-audit.sh` each hand-maintained a copy of the public-safe email
    allowlist behind "keep in sync" comments nothing enforced** — already re-diverged once before, per
    PR #43 (dir #106). Extracted to `tools/lib/safe-emails.sh`, sourced by both (`doctor.sh` once,
    before its per-project scan loop, not per-iteration; `public-audit.sh` reuses the lib's own
    pre-joined regex instead of rebuilding it).
  - **`keel-impact.sh`'s `rollup` and the cross-project `_ledger_stats` each re-derived the ledger
    table's column indices independently, against the file's own "keep in sync" warning** (dir #107).
    Extracted to a shared `_ledger_parse`; both now delegate to it. The review caught a real regression
    in this refactor: `rollup()`'s new `read -r ... <<EOF $(_ledger_parse ...) EOF` pattern discarded
    the command substitution's exit status (a heredoc always supplies a trailing newline, so `read`
    "succeeds" on an empty line even when the substitution failed silently) — a genuinely unreadable
    ledger was reported as "0 session(s), no numeric scores yet" at exit 0 instead of surfacing the
    read failure, a regression the old, un-refactored `rollup()` did not have. Fixed by capturing into
    a variable (`parsed="$(...)" ||`, which does carry the real exit status).

### Added
- **`tools/self/doctor.sh` gains a WARN for stale `BACKLOG.md` ticket headings** (dir #87, found 3×
  by later sessions' own `/wrap` — a closed ticket's `### dir #N` heading kept its open-status tag
  even after the ticket's own body already recorded `✅ CLOSED (PR #…)`). The new check flags any
  `### dir #N` heading whose own line carries no `✅`/`⏳`/`RETRACTED` tag while the body below it
  (up to the next `##`/`###` heading) already records `CLOSED`/`DONE`/`RETRACTED` next to a checkmark
  — a WARN, not a GAP, matching the ticket's own "low-severity/cosmetic" framing of this bug class.
  Inline-code spans and fenced ` ``` `/`~~~` blocks (indented or not, matching `tools/doctor.sh`'s
  own established fence regex) are blanked first so a prose example of the pattern (as this very
  changelog entry's ticket does) can't flag its own documentation; the heading-tag match requires
  every marker (`✅`, `⏳`, `RETRACTED`) to follow the `— ` separator every real tag uses, so the
  bare glyph/word showing up in a heading's own title text doesn't count as a tag. `BACKLOG.md` is
  gitignored and not every checkout carries one (a worktree, a fresh clone, most consumer
  projects) — a missing or unreadable file is a clean pass, not a finding. New test coverage in
  `tests/test_self_doctor.sh` (16 cases). Caught one real, still-live instance on this run: dir
  #75's own heading. **Documented, accepted residual limitations** (a cheap heuristic on free-form
  prose, not a parser): a body line cross-referencing a *different* ticket's status, or negating its
  own ("NOT DONE yet"), can still false-positive; a wrong tag (heading says `⏳ IN FLIGHT` while the
  body says `✅ CLOSED`) isn't flagged, only a missing one, per the ticket's own scope; an unbalanced
  fence marker blanks the rest of the file. Review: independent agent (`medium`, 1 real bug fixed —
  an unguarded `while read` silently dropping a file's final line if it lacked a trailing newline) +
  6 rounds of operator-run `/code-review medium` (7 more real bugs found and fixed across 4 of those
  rounds — the GAP/WARN severity mismatch, a fenced-code-block content gap, a RETRACTED
  word-boundary gap, heading/boundary detection reading the raw file instead of the fence-blanked
  copy, a too-narrow fence regex, an unreadable-file crash, and an asymmetric ✅/⏳ tag-detection
  gap; a separate attempted fix — a same-line cross-reference filter, tried in one round — was
  itself found to introduce two worse bugs the very next round and reverted
  rather than patched further).

- **The pre-PR gate's receipt sentinel/prev-sentinel/hand-off files are now keyed by `(repo, branch)`
  instead of repo alone, and `keel-impact.sh`'s shared event-log rewrite is now subtractive instead of
  a snapshot write-back** (dir #80, dir #82). Concurrent `/polish` sessions on different branches of
  the same repo used to race and wipe each other's receipts (felt on dir #62/#79's own `/polish` runs,
  PRs #147 and #148) — `tools/pre-pr-gate.sh`'s `_require_receipt_key` now combines the repo key with
  the invoking branch, hook mode resolving the branch via `--head`/`-f head=` first and falling back to
  the event cwd's own checked-out branch, denying with an actionable message when neither resolves (a
  malformed `--head` also now fails closed instead of silently keying onto the wrong branch).
  `commands/polish.md` step 9 makes `--head <branch>` mandatory in `gh pr create`. Separately,
  `tools/keel-impact.sh`'s `cmd_add` used to read the shared multi-worktree event log once, decide what
  to ingest, then write back a snapshot of the survivors — blind to any line a concurrent producer
  appended in between, silently discarding it. The rewrite is now subtractive: it re-reads the log
  fresh at rewrite time and removes only the specific lines this run actually consumed, via a
  byte-exact awk count-map, so a concurrent append now survives. Both an independent agent review and
  an operator-run `/code-review high` pass ran on this diff; the operator pass found two critical,
  empirically-verified bugs in the initial dir #80 implementation — a naive `"$repo-$branch"` string
  join was ambiguous (two different `(repo, branch)` pairs could concatenate to the same key), and the
  branch-name sanitizer collapsed distinct branches (`feature/foo` and `feature-foo` sanitized
  identically) — both fixed by hashing the `(repo-key, raw branch)` pair via `cksum` (the same house
  pattern `keel-check.sh`/`keel-check-gate.sh` already use) instead of naively joining sanitized
  components.
- **The pre-PR gate now mechanically checks step 5(a)'s MANDATORY review-reminder dialog, closing the
  gap dir #79 left as wording-only** (dir #88). That dialog ("agent review already ran — additionally
  run the stronger built-in `/code-review <level>`?") was silently skipped 3x in practice (felt on dir
  #62/PR #147) because nothing enforced it beyond prose. `tools/pre-pr-gate.sh` gains a 3rd trace leg
  (same class as dir #63/#70): a new `PostToolUse`/`AskUserQuestion` hook greps the dialog's raw event
  JSON for a `KEEL-REVIEW-DIALOG: level=<level>` marker and writes a `dialog:<level>` trace line; the
  gate's PASS branch now requires a matching, current-commit trace line whenever `polish.5-review`'s
  outcome is `agent:*`-shaped (both the plain and dir #81 combined forms), denying with
  `review-dialog-missing` otherwise. `tools/install-pre-pr-gate.sh` wires this as its 6th hook. The check
  stays inert (armed) only once that hook is actually present in the resolvable settings.json — an
  unconditional check would false-deny every `agent:*` unlock in the window between a `git pull` picking
  up this gate logic and the next `tools/install-pre-pr-gate.sh` re-run. `commands/polish.md` step 5(a)
  now states this and requires the marker; step 5(c)'s combined-outcome fallback gained a clause so a
  `review-dialog-missing` deny is answered by opening the dialog, not by silently dropping the agent
  review half (the exact dir #81 anti-pattern).
- **`/go` now derives failing acceptance tests from a ticket's done-criterion before implementing, and
  `/polish` step 5(a)'s independent-reviewer prompt now carries a two-way conformance mandate against
  the ticket** (dir #78, found by comparing keel's `/design → /go → /polish` conveyor against the
  operator's published workflow schema — two stages the video's schema had that keel's own pipeline was
  missing). `commands/go.md` gains a step: when a ticket names a done-criterion, write acceptance tests
  from it FIRST — show them red, then implement to green — with an explicit infeasible-say-so escape
  hatch for pure-wording tickets with no runnable surface, in the same spirit as `/polish`'s
  `skipped:<reason>` receipts. `commands/polish.md` step 5(a)'s subagent prompt now also carries the
  ticket/spec the diff implements (id or done-criterion text) with a two-way mandate — the diff must
  realize it, and must not silently exceed or contradict it — with an explicit no-ticket fallback for
  ad-hoc diffs (stays correctness-only). `FRAMEWORK.md` gains one generic cross-link sentence on its
  existing tests-before-or-alongside design principle (no keel-internal references — that doc is
  adopter-facing). New `tests/test_conveyor_stages.sh` pins all three additions, written before the
  implementation and confirmed red first, the same grep-based idiom `test_doc_figures.sh` already uses.
  Scope is deliberately this pair only — the video's other three stages (frozen-spec semantics, parallel
  per-module executors, mutation testing) are explicitly rejected for keel per the ticket's resolved
  forks. Also felt again: the shared `/tmp/pre-pr-gate-*` sentinel (still-open dir #80) collided with a
  concurrent session's own `/polish` run mid-pass; recovered by re-`init`+receipt+`gh pr create` in one
  tight sequence.
- **`BACKLOG.drafts/` isolates parallel `/design` sessions from racing a shared `BACKLOG.md`** (dir #83,
  felt 2026-08-02, affiliate-lab — several concurrent design sessions saw each other's half-written
  edits and collided on ticket numbers). A design session whose target backlog may have concurrent
  writers now writes its finished ticket as an unnumbered draft file, keyed by slug, in `BACKLOG.drafts/`
  and only folds it into `BACKLOG.md` (assigning a real number) at its own wrap — the single
  serialization point; `/backlog` folds any draft still there idempotently — whether its owning session
  crashed or just hasn't wrapped yet — and lists whatever it can't fold as an unnumbered "Draft" row.
  Full convention, including the (separate, unaffected)
  sequencing rule for two designs' *implementations* → `FRAMEWORK.md`'s backlog/persist section.
  `commands/backlog.md` gains the fold/list step; `templates/CLAUDE.md` and `templates/project-CLAUDE.md`
  point new projects at the convention.
- **`AGENTS.md` is now a first-class vendor sibling of `CLAUDE.md`, symlinked and status-inheriting**
  (dir #75, found in dir #69's wrap: keel's own root `AGENTS.md` was an untracked, stale, unignored copy
  of `CLAUDE.md`). `init-project.sh` now creates `AGENTS.md` as a symlink to `CLAUDE.md` (never-clobber,
  same idiom as the `CLAUDE.md` branch) and gitignores it by default. `doctor.sh` gains three new checks,
  firing only when `AGENTS.md` exists: `G-AGENTSMD-CONTEXT` (unignored + untracked — same treatment as
  `CLAUDE.md`'s own gap), `G-AGENTSMD-INHERIT` (its tracked/ignored status doesn't match `CLAUDE.md`'s —
  the rule is status inheritance, not a fixed status; both tracked is a deliberate public fork, not a
  gap), and `W-AGENTSMD-DRIFT` (a regular-file copy, not a symlink, has drifted from `CLAUDE.md`). Keel's
  own main-checkout `AGENTS.md` is now gitignored and a symlink to `CLAUDE.md`. Scope is per-project only
  — the global `~/.codex/AGENTS.md` installer wrapper is split off to dir #76. Whether Codex/Cursor
  resolve a *symlinked* `AGENTS.md` (validated only for a regular file in dirs #30/#31) is a carried
  TO VERIFY; the symlink ships regardless since the fallback (a stale/absent file) is strictly worse.
- **`install.sh --codex` generates the global `~/.codex/AGENTS.md` wrapper Codex reads verbatim** (dir
  #76, split from dir #75 — the global-level half of that ticket's scope). Copy mode only (Codex has no
  `@import` mechanism; `--codex --link` is a usage error): a fresh install strips the `templates/CLAUDE.md`
  `(TEMPLATE)`/"copy this" prose the same way the linked-mode wrapper already does and embeds the core
  block directly (no new template file — the byte-pin in `test_core_wrapper_sync.sh` is untouched); a
  re-run compares the installed `KEEL-CORE` block against the current `CORE.md` and offers to refresh
  just the block on drift (interactive y/N, default no; non-interactive → WARN with the fix) — currency
  copy-mode Claude Code doesn't get today. `commands/` is deliberately not wired (Codex reads skills from
  `~/.codex/skills/<name>/SKILL.md`, converted per `ADAPTING.md`'s existing note); `doctor.sh --install`
  stays Claude-home-scoped by design (the installer's own end-of-run verify covers the `--codex` result).
  `ADAPTING.md` and `README.md` name the new one-liner.
- **The shared, multi-worktree impact-event log is now claim-keyed, so parallel `/keel-score` sessions
  don't steal each other's guardrail fires** (dir #74, felt in dir #69's wrap in both directions: a
  session losing its own fire to another session's `add`, and a session inheriting fires it never
  triggered). `tools/pre-pr-gate.sh`, `tools/secret-guard/secret-scan.sh`, `tools/public-audit.sh`, and
  `tools/keel-impact.sh`'s own `event` subcommand now stamp a 5th TSV field — the producer's own
  worktree top, captured before any main-checkout log-path fallback — on every logged event.
  `keel-impact.sh add` only auto-ingests events carrying its own key; a fresh event from a different
  worktree is left in the log (printed `foreign-kept:`) for that worktree's own `add` to claim later.
  Legacy 4-field lines still ingest as before, and stale events keep dir #59's archive-and-remove
  semantics regardless of key. The ingest loop's tab-collapse trap (an empty middle TSV field silently
  swallowed by `IFS=$'\t' read`) is now reachable for real since detail can sit before the new key field,
  fixed via the same awk-then-`\x1f`-read idiom already used elsewhere in `pre-pr-gate.sh`.
  `commands/keel-score.md` documents that `foreign-kept:` lines are expected, not a bug, with parallel
  sessions. A subsequent operator-run `/code-review high` pass found and fixed three further gaps:
  `cmd_add`'s log-rewrite and its read loop both used constructs (`A && B` as a bare statement; a bare
  process-substitution read) that are silently exempt from bash's `set -e`, so a write or read failure
  on the shared log used to fall through instead of failing loud; and a foreign-kept-only rewrite was
  silently dropping co-existing non-scored housekeeping lines (`receipt-pass` etc.) — now preserved
  verbatim (the raw original line, not a 5-field reconstruction, so a line with more than 5 real tab
  fields — like `receipt-pass`'s own embedded-tab `detail` — round-trips intact instead of being quietly
  truncated), and the rewrite is skipped entirely when nothing needs removing. A convergence-round delta
  review caught the truncation risk the first pass at "preserve" introduced. The still-open gap — no
  locking around the log's shared read-modify-write cycle, so two genuinely concurrent `add` runs can
  still race — is real but out of scope for a portable (macOS/Alpine-safe) fix here, tracked separately
  as dir #82.
- **`tests/test_doc_figures.sh`'s ±10% guard now warns before it fails** (dir #73, felt in dir #69's
  rails edit). A figure that has drifted to within ~3% of actual (i.e. consumed >~70% of the ±10%
  half-band) used to pass silently — the next PR to touch that same file, for any reason, would then
  red-lite CI on a figure it never touched, as happened to `templates/CLAUDE.md` and README's guarded
  mermaid label in dir #69. `assert_band` now prints a one-line, non-failing `note` when a passing figure
  is that close to its edge, naming the file and its remaining headroom so the PR causing the drift is
  the one that restates the figure. New meta-test `tests/test_doc_figures_near_band.sh` pins both
  directions on a real run of the guard, via a plain `cp`/`tar`-copied tree (no git clone, so the Alpine
  `safe.directory` trap doesn't apply): a figure nudged into the warn zone (still inside ±10%) prints the
  note, and an untouched tree stays note-free. Scoped to plain `~N,NNN` figure rows only — the
  growth-tolerant `~N,NNN+` floor rows (CHANGELOG) and `assert_commands_range` are unaffected by design.
- **`/polish` step 5(a)'s code-review reminder dialog restructured to be much harder to skip** (dir #62's
  own `/polish` run, felt for the 3rd time). The `AskUserQuestion` reminder that must follow every
  independent-agent review — "accept this agent review, or run the stronger built-in `/code-review`?" —
  was silently skipped across three review rounds in production use before the operator flagged it. Root
  causes: the step's only mechanically-checked artifact (the `polish.5-review` receipt) was written
  BEFORE the reminder, so nothing forced a stop, and the reminder itself was buried mid-paragraph. The
  reminder is now a standalone bolded "MANDATORY NEXT ACTION" line immediately after the receipt write,
  styled after step 4's own dialog-trigger convention, with an explicit note that it fires every
  convergence round (not just the first pass) since a hand-off note is same-SHA-only. A proper
  gate-level check — denying the receipt without a recorded hand-off/waiver — is tracked separately as
  dir #79; this fix is deliberately wording-only.
- **That same reminder dialog reframed as one additive yes/no question instead of an either/or choice**
  (dir #81, operator-raised). The dialog used to read as "accept this agent review, OR run the stronger
  `/code-review`" — and picking the operator pass **overwrote** the receipt, silently erasing the record
  that an independent agent review had already run and been mechanically trace-confirmed. It's now framed
  as: the agent review already ran and stands regardless of the answer; the only question is whether to
  *additionally* run `/code-review` on top. `tools/pre-pr-gate.sh` gained a new combined outcome,
  `agent:<level>+operator-run`, so both provenances are recorded honestly instead of one clobbering the
  other — the agent half stays mechanically trace-checked even in the combined shape. An anti-rebundle
  sentence guards against re-bundling this with a future "is the agent review itself optional" question.
- **`/polish` step 5 no longer attempts the doomed `Skill(code-review)` call before falling back to the
  independent-subagent review** (dir #71). Every `low|medium|high|max` run used to open with an attempt
  that failed every single time — `/code-review` ships `disable-model-invocation: true`, a documented
  harness policy (confirmed against the Claude Code docs during dir #70's design), not a per-session
  accident — so the attempt only produced a visible error on every run with nothing learned from it. Step
  5 now states the standing fact and goes straight to the dir #70 independent-subagent path; a revisit
  trigger documents restoring attempt-first if the harness policy ever changes (the existing
  Skill/UserPromptExpansion trace legs and bare-`<level>` receipt outcome already cover that case
  natively). Step 2's own attempt-don't-infer rule (for `/simplify`) was made self-contained, dropping a
  now-dangling cross-reference to step 5.
- **`/polish`'s review gate gained a convergence rule for a review-fix commit, plus `receipt --recover`
  to make re-receipting cheap** (dir #72, felt three times in one run closing dir #69/PR #145). dir #70's
  `SubagentStop` trace and dir #63's SHA check are both keyed to HEAD at fire time, so fixing a real
  step-5 finding and committing it moves the goalposts the gate checks against — but the flow never said
  so, reading as a contradiction ("one terminal pass, no loop-back" vs. a SHA rule that demands another
  pass). `commands/polish.md` step 5 now states the rule outright: fold the fix into the same commit
  where practical, re-review the delta only, stop once a pass needs no further changes. Because `init`
  mints a fresh nonce on every invocation, a fix-commit round still needs its receipts rewritten — but
  steps 1-4 and 7 didn't change, so `tools/pre-pr-gate.sh` gained `receipt --recover`, which re-stamps
  whatever the immediately-prior (now-retired) run already receipted for those steps onto the fresh nonce
  in one call. Every sentinel-invalidating event (a gate deny, a successful unlock, or `init`'s own
  overwrite) now routes through one `retire_sentinel()` helper that backs the live sentinel up to a
  single-slot backup before clearing it, instead of the previous scattered `rm -f` calls — recover reads
  from that backup. The gate's own completeness/SHA/trace checks are entirely unchanged: a
  recovered-but-stale value (e.g. a stale `polish.8-unlock` sha) still denies exactly as before, since any
  step that actually changed gets a fresh `receipt` call afterward that supersedes the recovered line for
  that step id. An independent review of this ticket's own `/polish` pass caught a real ordering bug in
  the first draft: the doc called `--recover` from step 5, by which point steps 1-4/7 had already written
  FRESH receipts for the round — recovering afterward would have silently overwritten them with stale
  ones (harmless for the completion-marker steps, actively wrong for `polish.4-depth`'s cross-checked
  level). Fixed by moving the recover call to step 1, immediately after `init`, with steps 2/3/4/7 made
  explicitly conditional on it. Filed dir #77 as a narrow follow-up: `--recover` restores every step id in
  the prior sentinel but doesn't report *which* ones, so a step that was never receipted upstream (an
  aborted mid-run) can't be told apart from one genuinely recovered. **An operator-run `/code-review high`
  pass on this same PR found and fixed 7 further issues**, all in `tools/pre-pr-gate.sh` (`commands/polish.md`
  step 6 updated to match): (1) `polish.6-retest`'s receipt was a bare completion marker with NO
  value-level check — unlike step 5 (trace-matched) and step 8 (sha-matched) — so a recovered stale
  retest receipt could satisfy completeness for a fix-commit that was never actually re-tested, making the
  "any step that actually changed gets a fresh receipt" safety claim above false specifically for step 6;
  it now records the sha it ran at (same convention as step 8) and is cross-checked the same way. (2) the
  single backup slot had no history — ANY subsequent invalidation (a retried `gh pr create`, a second
  `init`, a concurrent worktree of the same repo) silently overwrote a not-yet-recovered backup, in the
  worst case with an unrelated run's receipts. (3) `receipt --recover` had no check tying the recovered
  backup to the current diff's lineage at all. (2) and (3) are now addressed together: `retire_sentinel()`
  stamps each backup with the cwd's HEAD sha at retirement time, and `--recover` refuses (fails closed)
  unless that base sha is a verified ancestor of current HEAD — an unrelated worktree/branch's backup, or
  one made stale by a rebase/amend, is now a loud refusal instead of a silent wrong recovery. (4) a failed
  `mv` inside `retire_sentinel` was entirely silent (stderr discarded, exit status unchecked) — now logged.
  (5) a malformed/corrupted backup and a genuinely-empty one reported the identical "nothing to recover"
  message — now distinguished. (6)/(7) two lower-severity cleanups: the nonce/step parsing idiom shared
  between `--recover` and the completeness parser is now cross-referenced in comments rather than silently
  duplicated (kept as two blocks on purpose — reviewed and found that forcing a shared primitive would add
  more complexity than the ~6 duplicated lines cost, since the completeness parser needs foreign-nonce
  bookkeeping `--recover` has no use for); and `retire_sentinel`/`init`/`receipt --recover` no longer
  re-derive the repo key (`_repo_key`, which forks `git worktree list`) when the caller already resolved
  it moments earlier.
- **`/polish` step 5 spawns an independent subagent review when `/code-review` isn't model-invokable in
  session, instead of falling back to a same-context self-review** (dir #70). `/code-review` ships
  `disable-model-invocation: true`, so a session can never call it on its own; every unavailable-case
  `/polish` run used to fall to an inline pass — the author reviewing its own diff — standing in for a
  real review. Step 5 now spawns ONE fresh-context Agent-tool subagent (`subagent_type:
  "general-purpose"`) with a correctness-focused mandate and an explicit read-only instruction (no file
  edits, no live-environment reproduction — see memory `subagent-live-verification-risk`), resolves any
  real findings, and receipts `agent:<level>` immediately — before any hand-off, since the review already
  happened and is independently, mechanically verifiable. The hand-off dialog's purpose shifts from "the
  real review couldn't run" to a REMINDER that the built-in multi-agent `/code-review` pipeline stays
  stronger and is one command away; `ultra`, and the case where the Agent tool itself is also
  unavailable, keep the original blocking hand-off. `tools/pre-pr-gate.sh` gained a fifth hook,
  `SubagentStop`/`general-purpose`, wired by `tools/install-pre-pr-gate.sh` (now 5 hooks, idempotently
  upgrading an already-wired repo) and by `tools/pipeline-canary.sh`'s sandbox. The design ticket assumed
  a `PostToolUse` hook keyed on a "Task"/"Agent" tool name, mirroring the Skill leg — checked against
  Claude Code's hooks reference at implementation time, no such tool-call hook exists for subagent
  spawning (`TaskCreate` is a different, unrelated feature: the background-task queue). The real
  mechanism is a dedicated `SubagentStop` lifecycle event, matched on `agent_type`, carrying
  `last_assistant_message` — the ONLY field a subagent event exposes an outcome through, since unlike a
  Skill call it has no `tool_input`/prompt field. The review subagent's prompt is required to end its
  final response with a bare marker line, `KEEL-AGENT-REVIEW: level=<level>`; `skill-trace` parses it out
  of `last_assistant_message` and writes `<sha>\tagent:<level>` to the same trace file the Skill/
  UserPromptExpansion legs use — the sha is always the hook's own `git rev-parse HEAD` at fire time, never
  self-reported. Found and fixed during implementation: bash `read` stops at the first embedded newline
  regardless of `IFS`, so an early draft that joined `last_assistant_message` into the same
  `IFS=$'\x1f' read` line as the other (single-line) fields silently truncated every real, multi-line
  review write-up to its first line, above the marker — fetched via its own separate `jq` call instead.
  The gate's PASS branch gained an `agent:*` outcome case (still `trusted=0`, cross-checked against the
  trace and against `polish.4-depth`'s own recorded level, same bar as a bare in-session claim) and a
  provenance label distinct from a genuine `/code-review` run — the PR body and closing summary must
  name it "independent agent review", never presented as if the built-in reviewer ran. `sweep` (dir #64
  tier 2b) now treats an `agent-confirmed` pass the same as `trace-confirmed` when judging a
  self-reported-only streak. A pre-check confirmed the docs' `skillOverrides` setting only controls skill
  *visibility* (on/name-only/user-invocable-only/off) — it cannot re-enable model invocation of a skill
  whose frontmatter sets `disable-model-invocation: true`, so no simpler fix existed. New fixtures cover
  trace parsing, marker validation, the multi-line-newline regression, the full PASS/deny matrix, and the
  `sweep` classification (including a legacy-log regression: a pre-dir-64 `receipt-pass` row with no
  5th field at all must still count toward `sweep`'s self-reported streak, not read as verified just
  because it isn't literally `self-reported` — a real defect an adversarial review caught in an earlier
  draft of the streak check above) in `tests/test_pre_pr_gate.sh`, plus `tests/test_install_pre_pr_gate.sh`
  coverage for the fifth hook.
- **The `/polish` pre-PR gate pipeline ships to adopters, not just the maintainer** (dir #68 — the audit
  behind it found this cluster the tree's only violator of the adopter/self-maintenance dichotomy).
  `commands/polish.md` now installs unconditionally (`install.sh` dropped it from its skip list); its
  enforcement stays opt-in on purpose, since a hook changes what a session can do without asking each
  time. New `tools/install-pre-pr-gate.sh <repo>` (project scope, the default) or `--global` wires all
  four Claude Code hooks (`PreToolUse`/`gh pr create`, `SessionStart`/rollout-check,
  `PostToolUse`+`UserPromptExpansion`/skill-trace) into `.claude/settings.json`, pointing at the KEPT
  checkout's `tools/pre-pr-gate.sh` directly — no copy, closing the stale-copy failure mode the
  maintainer's own prior wiring had. Same never-clobber discipline as `install-secret-guard.sh`: a
  foreign hook on the same event+matcher is refused and named, `--force` backs up `settings.json` first;
  no `jq` on PATH degrades to a printed ready-to-paste snippet rather than a partial write.
  `tools/doctor.sh --install` gained a pairing check (`W-GATE-UNWIRED`) so a shipped-but-inert gate is
  visible instead of only discovered when `gh pr create` doesn't unlock. Docs: a new README section
  (peer of secret-guard's), a `getting-started.md` walkthrough (what changes, costs, the residual
  self-reported-hand-off limit), `reference.md` rows for the gate + installer + `pipeline-canary.sh` (now
  documented as an adopter-usable diagnostic, not just maintainer tooling), an `ADAPTING.md` "does not
  port" note (Claude-Code-hooks-specific), and a `loading-and-cost.md` actor-labeled full-loop
  walkthrough making the "operator's whole loop is 3 real touches" claim concrete and honest for every
  adopter, not just the maintainer. That `--install`-mode check only ever sees the machine-global
  `settings.json`, so it structurally cannot see project-scope wiring (the documented default) — an
  adopter who did exactly what the docs recommend got a `W-GATE-UNWIRED` WARN on every single run with
  no way to confirm they'd actually wired it right (the message already conceded this, which was itself
  the smell). Gave doctor the missing per-project half, mirroring how it already double-checks
  secret-guard at both scopes: the per-project loop now inspects `$d/.claude/settings.json` for the same
  load-bearing hook (`gate_hook_wired`, factored out and shared with the `--install` check so the two
  structural tests can't drift apart). Plain absence stays silent at any tier — the gate is opt-in and
  most projects legitimately never wire it, so nagging every project about it would trade one false
  alarm for a noisier one. The one state that IS flagged (`W-GATE-PARTIAL`) is the secret-guard-shaped
  one: some hook already references `pre-pr-gate.sh` (the repo engaged with the installer) but the
  load-bearing `PreToolUse`/`Bash` hook specifically is missing — a rail that looks wired but doesn't
  actually enforce anything, same shape as `W-GUARD-BYPASSED`. 3 new cases in
  `tests/test_install_pre_pr_gate.sh` cover all three project-scope states (silent, OK, `W-GATE-PARTIAL`).
- **`skill-trace`'s hook field-name assumptions, verified** (dir #68 follow-up — its own shipping-audit
  flagged `tools/pre-pr-gate.sh`'s `skill-trace` subcommand as parsing Claude Code's `PostToolUse`/
  `UserPromptExpansion` hook JSON on unverified field-name guesses, unlike its sibling `rollout-check`,
  which already carried a resolved TO-VERIFY note). Checked against the current hooks reference:
  `UserPromptExpansion`'s `command_name`/`command_args` fields are confirmed against the docs' own
  literal example (and, live, against a real trace a genuine in-session `/code-review` run produced);
  `PostToolUse(Skill)`'s `tool_input.skill`/`tool_input.args` have no dedicated worked example but follow
  the same tool-input-mirrors-its-own-parameters convention every documented tool uses. No field names
  needed changing — both held up. Written into the script's header as its own resolved TO-VERIFY block,
  and the `UserPromptExpansion` test fixture now carries the full documented field set instead of a
  partial guess.
- **A model/harness rollout must not break the `/polish` pipeline silently — three independent guard
  tiers** (dir #64, generalizing dir #63's root cause: the Opus 5 rollout silently removed
  `/code-review`'s model-invokability and nothing warned). Prose commands can't be unit-tested, but a
  rollout's *effect on them* can be watched three ways. **Tier 1** — `tools/pre-pr-gate.sh` gained a
  `rollout-check` subcommand wired as a `SessionStart` hook: it records the session's model id (from the
  hook's own JSON input) + `claude --version` per repo, and on either changing since the last recorded
  session, prints a `systemMessage` banner and logs a `pipeline-drift` event. Two facts this needed
  settling first, now written into the script's header: SessionStart's JSON *does* carry a `model`
  field, but plain stdout from a SessionStart hook is model-visible only — the human-visible channel is
  the separate `systemMessage` field, which is what the banner uses. **Tier 2** — the gate's ALLOW
  decision now carries a one-line provenance classification of how step 5's review was actually
  established ("review: skip" / "…, trace-confirmed in-session" / "…, operator-run (self-reported)" /
  "…, waived (self-reported)"), visible at PR-creation time instead of only via transcript archaeology;
  the same classification is now the `receipt-pass` impact-log event's detail field, which a new `sweep
  [K]` subcommand reads to warn when the last K (default 3) consecutive `/polish` runs never closed on a
  trace-confirmed review — read-only, never blocks. **Tier 3** — `tools/pipeline-canary.sh` (new):
  `setup` builds an isolated sandbox (throwaway HOME, a toy repo, a stubbed `gh` that never touches the
  network, this checkout's gate wired into a scratch `settings.json`) and prints the operator's command
  to drive a real `/polish` run inside it; `check` then script-asserts what the run left behind; `clean`
  tears it down. `demo-bypass` needs no model at all — it seeds a fabricated step-5 claim with no
  matching trace and asserts the gate still denies it (a canary that has never failed proves nothing).
  Whether a fully headless `claude -p` run reliably fires `PreToolUse`/`PostToolUse` hooks the same way
  an interactive session does turned out to be under-documented (SessionStart/SessionEnd firing in print
  mode is explicit; the other two are only inferred from "loads the same context an interactive session
  would") — tier 3 ships as the ticket's own documented fallback, an interactive ritual rather than a
  blind automated drive; the artifact assertions keep their value either way. `/code-review` was
  genuinely unavailable in the building session (the exact felt trigger this ticket generalizes from),
  so an inline pass caught one bug (a raw, invisible control byte in a jq call — fixed to match the
  existing escaped-literal convention) before the operator ran `/code-review high` directly, which found
  four more real ones: `rollout-check` was unconditionally overwriting its state file even when a field
  came back empty, silently erasing the last-known-good baseline so a genuine NEXT-session model change
  could go undetected; `sweep` fell through to "OK" whenever a repo had fewer than K total runs on
  record, even if every one of them was self-reported-only — exactly the blind spot it exists to catch,
  worst when there's least history; `sweep` classified "trace-confirmed" by regex-matching the
  human-display provenance prose rather than a stable tag, so a future rewording could silently break it
  (fixed by logging a separate machine tag alongside the prose); and `pipeline-canary.sh`'s `check`
  ignored `$KEEL_IMPACT_LOG` precedence, so an operator with that env var set would see a fully
  successful canary run misreported as "no event recorded". All four fixed, with new regression
  coverage. 35 new cases in `tests/test_pre_pr_gate.sh` (rollout-check, the provenance line, the sweep,
  the four fixes) and a new `tests/test_pipeline_canary.sh` (32 cases) cover all three tiers. Wiring the
  new `SessionStart` hook into `~/.claude/settings.json` is a manual follow-up, same precedent as dir
  #63's two hooks.
- **`/polish` step 5's review outcome is now mechanically verifiable, closing the two holes dir #57's
  rework filed** (dir #63, adversarial pass on that rework). The step-5 receipt used to be a free-form
  string the model wrote about itself — a genuine in-session `/code-review <level>` pass and a session
  that only *claimed* one were byte-identical. `tools/pre-pr-gate.sh` gained a `skill-trace` hook
  subcommand, wired as a `PostToolUse(Skill)` + `UserPromptExpansion(code-review)` pair (documented in
  the script's own header) — the former fires only when Claude's own `Skill(code-review)` call actually
  succeeds (a refused/unavailable call never reaches `PostToolUse`, confirmed empirically and against
  Claude Code's hooks reference), the latter when the operator types `/code-review <level>` directly
  (a path that bypasses `PostToolUse` entirely). Both append a SHA-keyed trace line the model cannot
  author itself. The gate's PASS branch now cross-checks that trace whenever `polish.5-review`'s
  outcome is a bare level (not `skip`/`-operator-run`/`-waived`) — a fabricated claim, or a trace from
  an older commit, is denied. **Residual limit, written into `commands/polish.md` and the gate header:**
  the unavailable-skill → inline-pass hand-off still leaves no trace by construction; that path's
  outcome stays self-reported.
  Second hole: the hand-off's only exit used to depend on session memory ("the session already shows
  they ran it"), gone after a context compaction or a fresh session on the same branch — a re-invoked
  `/polish` would defer forever, since `init` mints a fresh nonce by design (dir #49's replay fix). New
  `handoff`/`handoff-check` subcommands write and read a `<level>\t<sha>` line to its OWN file (keyed
  like the sentinel, per a new shared `_repo_key` helper factoring out a fragment the sentinel/trace/
  hand-off paths all now share) rather than folding it into the sentinel — so `init`'s nonce reset never
  has to special-case it at all; it's removed once the real `polish.5-review` receipt lands. The replay
  window is same-SHA only — any new commit invalidates it. 17 new cases in `tests/test_pre_pr_gate.sh`
  cover both mechanisms — an adversarial `/simplify` pass over the first draft caught a real bug in the
  attempt to fan `skill-trace`'s field-parsing into one `jq` call: bash's `read` collapses an EMPTY field
  sitting between two tab delimiters regardless of what `IFS` is set to (the same class of bug already
  logged against the keel-impact log parser), which silently shifted every field for a
  `UserPromptExpansion` event (no `tool_name` key to fill that slot) — fixed by joining on a `\u001f` unit separator
  instead of a tab, a delimiter outside bash's hardcoded whitespace-collapse class. The `handoff`/
  `handoff-check`/existing gate logic go live once this merges and the maintainer's `~/.claude` pulls
  main (the gate's existing symlink-consumption trap); the trace side needs one additional manual step
  beyond that — wiring the two new hooks into the maintainer's personal `~/.claude/settings.json`
  (documented in the script's own header) — since nothing in this repo edits that file automatically.

  **`/code-review` was itself unavailable for this session (`disable-model-invocation`) — the exact felt
  incident dir #63 exists to fix, reproducing live** — so an independent agent stood in for the real
  `high`-depth pass per `commands/polish.md`'s step 5(a). It found two genuine bypasses in the first
  draft, both fixed here: (1) the trusted outcomes (`skip`, `-operator-run`, `-waived`) were exempt from
  the trace check by design, but nothing cross-checked them against what `polish.4-depth` actually
  recorded — a session could size the diff `medium` and simply write `polish.5-review skip`, unlocking
  the gate on one word regardless of the real depth; (2) the trace check matched only the commit SHA,
  never the level, so a genuine `/code-review low` pass could vouch for a receipt claiming `max`. Both
  closed by one cross-check: every `polish.5-review` outcome (trusted or bare) must now share `polish.4-
  depth`'s own recorded level, and a bare-level trace match now requires the SAME level, not just the
  same commit. The review also caught a second instance of the tab-collapse `read` bug (this time in the
  PASS-branch's own result parsing) and a jq `join` that would throw — and lose the whole parsed row,
  not just the bad field — on a non-string `args`/`command_args`; both hardened the same way as the
  first fix. Two narrower, accepted limitations are now documented in the gate's own header rather than
  silently left uncovered: the trace's SHA can be wrong under the same split main-checkout/worktree
  pattern dir #61 hardened for the sentinel (fails closed — a false deny, not a bypass); the hand-off
  file is repo- not worktree-scoped, same as the sentinel's own existing keying. The header's "the model
  cannot author itself" framing was also overclaiming — softened to "a side channel the model isn't
  expected to touch," since nothing stops the model writing to `/tmp` directly. 6 more test cases added
  (101 total for this file); full suite + shellcheck + self-doctor green.

  **The operator then typed `/code-review high` directly — confirming the `UserPromptExpansion` path
  this same ticket relies on actually works, live.** The real pass (8 finder angles, 1-vote verify) found
  five more issues, all fixed: a redundant repo-key recomputation in the trace check when the value was
  already held from the sentinel resolution (efficiency); the test file's `trace_for`/`handoff_for`
  duplicating the `basename` pattern `_repo_key` was factored out to consolidate (reuse); the trusted-
  suffix set (`-operator-run`/`-waived`) encoded independently in the depth-check and the trace-exemption
  case, now unified into one `case` that both strips the suffix and decides whether a trace is required
  (altitude); `commands/polish.md` step 4 didn't check for a pending hand-off before re-sizing, so a
  borderline diff sized differently across two invocations could trip the new depth-mismatch check on a
  legitimate hand-off completion — step 4 now checks `handoff-check` first and reuses its frozen level
  (correctness, narrow); and a missing worktree-split test for the new trace/hand-off paths, mirroring
  dir #61's existing sentinel coverage. One reviewer-agent claim — that `UserPromptExpansion`'s real
  field is `command_input`, not `command_args` — was checked against a fresh `curl` of the live Claude
  Code hooks docs and refuted; `command_args` is correct. 106 test cases now; full suite + shellcheck +
  self-doctor green.

- **`/polish` step-receipt gate** (dir #49, maintainer dev-tooling pilot). `tools/pre-pr-gate.sh` gained
  `init`/`receipt`/`log` CLI subcommands: each `/polish` step now appends a receipt line
  (`<run-nonce>\t<step-id>\t<outcome>`) instead of the gate trusting a bare HEAD-SHA sentinel. The
  `gh pr create` hook denies unless every expected step id is present under the *current* run's nonce
  (a leftover line from an earlier run doesn't count — closes a stale-receipt-replay gap) and the final
  step's recorded SHA matches live HEAD. Deny naming the missing id(s), a stale-nonce replay, and a clean
  pass are each logged to `.keel/impact-events.log` (`receipt-deny` / `receipt-replay-deny` /
  `receipt-pass`) alongside the existing `guard` event, so the pilot can be measured and dropped later if
  it doesn't earn its keep — decision rule and review window are in `BACKLOG.md` #49. This is a
  completeness check over self-reported receipts, not proof of execution — an honest limit recorded in
  the ticket and worth restating here.

- **Release-pinned install one-liner** (dir #56, operator-raised post-v0.5.0). Release branches were
  rejected — a manually-moved `stable` pointer under a solo maintainer guarantees drift — in favor of
  attaching a stamped `bootstrap.sh` to each GitHub release: `tools/stamp-release-bootstrap.sh <tag>`
  bakes `KEEL_DEFAULT_REF="<tag>"` into a copy of `bootstrap.sh` (the tracked copy always ships
  `KEEL_DEFAULT_REF=""`, so it keeps tracking main), so
  `curl -fsSL https://github.com/rockerlabs/keel/releases/latest/download/bootstrap.sh | sh` always
  installs the last tagged (audited) release, not whatever's on main — `KEEL_REF` still overrides it.
  `KEEL_REF` unset + no stamp keeps installing latest `main`, unchanged.

- **FRAMEWORK.md "Verify gates" section** (dir #60, field-demand promotion — three independent
  agent-tooling builders converged on done-claim verification the same week). Documents the
  claim→record principle behind Keel's own practice and generalizes the receipt pattern from the dir
  #49 entry above (per-step lines under a fresh nonce, gate denies on a missing id or a state mismatch)
  — no new tool, doc-only, no CORE.md or tooling changes.

- **`docs/rollout-audit.md`** (dir #66, captured after a model rollout silently broke part of the
  pipeline — see the dir #63/#65 entries elsewhere in this file). A public, tool-agnostic three-layer
  checklist (mechanized floor → harness integration, verified by attempting the thing, never inferred
  from a listing → model-behaviour scenario probes) for auditing a pipeline after any model or harness
  rollout, including a plain upgrade — the doc's own generalizing point is that a stronger model
  re-weights rule-following rather than uniformly helping, which turns pre-existing wording debt into a
  visible behaviour change. Doc-only; linked from the README docs index.

### Changed
- **`CORE.md`'s confirm-actions exception is now general prose instead of a named `/polish` carve-out**
  (dir #69, found by dir #67's wording audit). The Decisions bullet's exception read "when an invoked,
  documented flow's own written steps instruct pushing a feature branch and opening its PR (e.g.
  `/polish`'s final step)" — a specific enumeration bolted onto a general clause, which is the exact
  construct dir #65 (the ticket that added it) was itself filed about: every future command/rail
  collision would need its own bolt-on, and the tool-independent rails named one harness's command. It
  now states the rule once, generally: invoking a documented flow pre-authorizes the outward-facing
  actions its own written steps specify — publishing a work branch and opening its PR being the ordinary
  case — and reaches no further: not to actions the steps don't name, and never past the safety rails
  above (a merge, release, deletion, force-push among them), which need an explicit human decision
  no matter who wrote the step. That last clause is what keeps the general form from becoming a blank
  cheque where a precedence *rank* for command prose would have been one: command files are the
  most-edited layer, so no command can reach a **gated** action by writing it into a step. It is a
  deliberate widening in the other direction, and worth naming: the permission half now covers any
  outward-facing-but-reversible action a flow's steps specify (the old text pre-authorized exactly
  push-a-branch + open-a-PR), which is what the ticket's chosen option asked for — the rails trade a
  narrower grant for one that doesn't need a new carve-out per command.
  Both halves are deliberately concrete after an earlier draft failed review in each direction: a purely
  abstract carve-back ("anything irreversible") left a session free to class an ordinary branch push as
  irreversible and stop to ask — reinstating the every-run friction dir #65 existed to remove — while a
  bare closed list would quietly pre-authorize every outward-facing action nobody thought to enumerate,
  the same enumeration failure one level down. Naming the permitted shape, and the gated set as instances
  ("among them") of the open category the Precedence section already carries, closes both. `/polish`
  step 9's own standing-authorization line is unchanged and still resolves — from the rails alone now,
  with no exception naming it. `templates/CLAUDE.md` re-synced (byte-pinned).
  `tests/test_core_wrapper_sync.sh` gained a guard that keeps the rails general: for every file in
  `commands/`, `CORE.md` must not name that command — derived from the directory, so a new command is
  covered automatically and a re-bolted enumeration fails the suite instead of shipping. Matched as a
  whole slash-command token rather than a substring, so an ordinary branch-name example (`claude/go-69-…`)
  can't false-fire the `/go` case; the leading slash stays required for the mirror-image reason (a bare
  word match would fire on ordinary English — "a final polish pass"). The loop also counts what it
  checked and fails on zero, since an empty glob (`commands/` renamed or nested) would otherwise assert
  nothing and still report green — a guard that silently stops guarding. `docs/loading-and-cost.md`'s
  `CORE.md` figure re-stated ~1,540 → ~1,720: the guarded ±10% band caught the added clause pushing an
  already-drifting figure out of tolerance, which is exactly what that guard is for. The
  `templates/CLAUDE.md` figure (~2,010 → ~2,210) and everything derived from it were refreshed in the
  same pass — the same +174 chars landed there too, leaving it 23 tokens inside its band, so the next
  rails edit of any size would have red-lit CI on a figure this change had already made stale. `README.md`'s
  own two `~2K` mentions of the same core (one of them separately guarded, down to 11 tokens of headroom)
  went to `~2.2K` for the same reason.

- **`/keel-score`'s `--fire` event now has an explicit two-test bar** (dir #24, anchored by the first
  A/B calibration run). A fire citation must name a counterfactual that is (1) *reachable* — a moment
  a cold session actually gets to; behavior behind a keel-only mechanism or past the cold endpoint is
  capability, not a counterfactual — and (2) *beyond orientation* — indistinguishable-from-ordinary-
  orientation behavior (listing branches, reading files) never clears the bar. The A/B found fire
  over-credit concentrated in exactly those two shapes, while the largest real keel-vs-cold delta
  (branch discipline) went unclaimed — so the calibration note now records the score as a floor on the
  estimate's honesty, not a ceiling on Keel's effect. Wording only; the score formula is unchanged.

- **README now explains the internal citation shorthand** (dir #55, first public audit finding).
  Code comments cite the maintainer's backlog using shorthand (`dir #N`, `KB.n`, `SEC4`) — the
  README's Docs section now includes a brief note that these are internal development trace and
  the public explanation is always in the surrounding text.
- **`CORE.md`'s git rails now carry a per-commit fetch+branch-check floor** (dir #52,
  operator-decided). Before every commit: `git fetch --prune` + `git branch --show-current` —
  refresh refs and confirm you're on your own, expected branch at the moment a stale picture
  would do damage (non-blocking: a failed fetch never blocks a local commit). Placed alongside,
  not inside, the existing reconcile-first rule, which stays the session-start/step-level check.
  Mirrored into `templates/CLAUDE.md` (byte-pinned by `test_core_wrapper_sync.sh`).

- **`CORE.md`'s confirm-before-push rule no longer contradicts `/polish` step 9** (dir #65,
  root-caused after the Opus 5 rollout: the general "confirm any outward-facing action (push,
  merging a PR...)" rail and step 9's explicit "run `gh pr create`" instruction disagreed, and the
  more literal-reading model started asking every time before opening a PR). The confirm-list now
  names only the actions that genuinely need a fresh yes (merging a PR, release, deletion,
  force-push, an ad-hoc push), with an explicit exception: when an invoked, documented flow's own
  written steps instruct the push and PR-open (e.g. `/polish`'s final step), that instruction is
  itself the authorization — the merge stays the operator's, unchanged. `commands/polish.md` step 9
  states the same for its own step. An adversarial review of the first draft found the "invoked,
  documented flow" carve-out was unscoped enough that a downstream project's agent could
  self-servingly apply it to any task it considered "documented" — tightened to require the flow's
  own written steps to instruct the push, not just resemble one. Mirrored into `templates/CLAUDE.md`
  (byte-pinned by `test_core_wrapper_sync.sh`).

- **`/polish` step 5 handles `/code-review` being unavailable — and now stops instead of carrying on**
  (dir #57, felt 2026-07-21 as the 5th occurrence, reworked 2026-07-26 on the 6th). The skill isn't
  always present or invocable — missing from the session's skill list, or gated behind
  `disable-model-invocation` — and each hit improvised the same fix (one inline review pass at the
  chosen depth, no loop-back). That fallback is spelled out in `commands/polish.md` itself so future
  sessions don't have to reinvent it, and no longer guess a substitute like `/review` (which mis-parses
  a review level as a PR number).

  **The 6th occurrence showed documenting the fallback wasn't enough.** It read "do the inline pass and
  continue", so the session went on to unlock the gate and open the PR by itself, disclosing that the
  real review never ran only in the closing summary — the operator found out by reading the transcript,
  and would not have otherwise. The unavailable case now behaves like `ultra` already did: inline pass
  first (so cheap findings never reach the human), then **stop before the receipt, the sentinel and the
  PR**, print the exact `/code-review <level>` command, and let the operator run it or explicitly waive
  it — recorded as `<level>-operator-run` / `<level>-waived` so a re-invoked `/polish` doesn't stall at
  the same step forever. Availability must also be established by *attempting* the call rather than
  inferred from the skill listing: the same session concluded "unavailable" from the listing and reached
  for the forbidden `/review` substitute anyway, and the unambiguous refusal surfaced only once the call
  was finally tried.

  **An adversarial pass over that rework found six more holes; four are fixed here, two are filed as
  dir #63** (they can't be closed at the instruction layer: the step-5 receipt is a free-form string the
  model writes about itself, and the hand-off's only exit depends on session memory that a context
  compaction erases). Fixed: **`skip` is no longer auto-selectable** — it joins `high+` in always asking,
  since the two ends of the scale are where the model's own judgement shouldn't be final, and `skip` was
  the one depth that bypassed step 5 and its hand-off outright, so sizing the diff down was the cheapest
  way out of being stopped. **Step 4's receipt now records what the depth was sized from**
  (`low:+38-8,2f,docs`), because a bare level keeps the conclusion and discards the evidence.
  **The inline pass must show what it checked and found**, the same bar step 3 sets for test output.
  **Files changed during the hand-off count as step-5 changes** for step 6's retest trigger — they land
  between `/polish` invocations, so "did step 5 change files" otherwise reads as "no" and the retest is
  skipped after exactly the edits it exists to cover.

### Fixed
- **`secret-scan.sh`'s `--range` mode validated a push range twice** — a throwaway
  `git rev-list --max-count=0 $rng` probe purely to fail closed on a bad/unfetched range, then a second,
  separate `git rev-list --objects $rng | git cat-file --batch-check=...` to do the real object walk,
  discarding that pipe's own exit status. Now a single streaming pipe is used, with `set -o pipefail`
  (already active file-wide) surfacing `rev-list`'s failure directly — same fail-closed guarantee, one
  invocation instead of two. Also factored the `--staged` mode's "not a git repo" guard into a shared
  `require_git_repo()` helper (`--tracked` keeps its own inline check — it needs the toplevel path, not
  just a boolean, so the split is deliberate). An initial pass also "fixed" the `shellcheck source=`
  comment in `pre-push`/`ci-scan.sh` from a repo-root-relative path to a bare filename; `/code-review
  high` caught that this was backwards for this repo — shellcheck resolves `source=` relative to the
  invoking CWD, not the referring script's directory, and this repo's CI runs it from the repo root with
  repo-relative paths, so the original path was already correct (verified empirically both ways) — that
  part was reverted.

- **Static wording audit of the shipped command prose — seven literal-reading defects fixed** (dir #67,
  the static counterpart to dir #66's dynamic rollout audit; scope: the always-on rails × the pipeline
  commands, correctness only). The defect class is prose an older model resolved charitably and a
  literal-reading one executes as written.
  - **`tools/…` paths in `/polish`, `/wrap`, `/global-review`, `/keel-score` resolved nowhere for an
    adopter.** The gate ships wired to the KEPT checkout by absolute path and is deliberately never
    copied into the target repo — so `tools/pre-pr-gate.sh receipt …` "from the repo root", read
    literally from any repo other than the Keel checkout, is a command-not-found on step 1. Each command
    now says the paths are its checkout's and must be spelled `<keel-checkout>/tools/…`, while still
    being *run from* the repo being polished/scored (both tools key their state off the cwd — the gate's
    receipt, `keel-impact`'s `.keel/` marker — so calling from the wrong directory silently scores the
    wrong project). `/global-review`'s `tools/doctor.sh --registry INSTANCE.md` was unresolvable at both
    ends at once (tool in the checkout, registry in the knowledge base) and now spells out both.
  - **`/wrap` step 8 instructed committing straight to the default branch, with the PR flow as a
    trailing exception** — an inversion of CORE.md's mandatory git rail, in the one file most likely to
    be read at the moment a session is about to push. The step now defers the branch choice to the rail
    (feature branch → PR, always; direct-to-default only under a written carve-out) and its push-verify
    compares against the branch actually pushed rather than always `origin/<default>`.
  - **`/go`'s task-id lookup hard-coded one heading format** (`^### 34\.`), which the project's own
    backlog has since outgrown (`### dir #34 —` and `### 34.` now sit in one file). A format miss is
    indistinguishable from a missing ticket, so the not-found rule would stop a task that exists — felt
    live while running this very audit. Matching is now by id across formats — loose on what decorates
    the id, exact on the id itself; the in-flight branch scan got the same treatment (harnesses decorate
    branch names, so `go-<n>-` missed `claude/go-issue-<n>-…`, while a bare substring match would have
    fired that rule's hard STOP on the unrelated ticket `<n>0`).
  - **`/backlog` didn't know the `⏳ IN FLIGHT` marker** that dir #40 taught `/go` to write, so a claimed
    ticket rendered as an ordinary pickable Next-up — the display half of the double-pick guard was
    missing. Added as its own status, ordered right after Active, carrying the claiming branch.
  - **`/polish` step 2 invoked `/simplify` with no unavailability path** while step 5 mandates
    attempt-don't-infer for `/code-review` — the dir #57/#63 lesson applied to one of the two skill
    call-sites. Step 2 now attempts the call, degrades to a named inline pass, and receipts the
    degradation (`inline:no-simplify-skill`) instead of a bare `done` that reads as a real run.
  - **`/polish`'s preamble pointed "above" at receipt calls that are below it.**
- **Pre-PR gate now catches `gh api repos/O/R/pulls -f head=…`, which opened a PR without ever using
  the `pr create` subcommand** (found 2026-07-26 while auditing the dir #57 rework). The command-position
  lexer added in dir #58 scans for `gh` → `pr` → `create` tokens, so an `api` call carrying the REST
  endpoint slipped past the fast-exit entirely — and it is precisely what gets reached for once
  `gh pr create` is denied, which made it the highest-value remaining bypass rather than a theoretical
  one. Matched only as a genuine write to a pulls collection: an endpoint ending in `/pulls` plus an
  explicit `POST` or — absent any named method — a field/input flag, since gh itself defaults to POST
  once fields are supplied. An explicit method wins over that inference, so `-X GET …/pulls -f state=open`
  stays a read: for a GET, fields are query parameters, and inferring "write" from the flag alone denied
  exactly the listing this catch promises to leave alone. Reads stay allowed by design and are pinned by
  tests — `.../pulls` with no write flag (list), `.../pulls/123` (one PR), `.../pulls/123/comments -f
  body=…` (commenting on an existing PR), and both explicit-GET forms: the gate blocks *opening* a PR, not
  looking at or annotating one, and one that denied status checks would just teach the next session to
  route around it. The branch is read out of `-f head=…` (owner prefix stripped for cross-fork heads) for
  the same dir #61 reason the `pr create` path reads `--head` — without it a fully-polished worktree PR
  opened this way would be denied as an ambiguous branch.

- **Pre-PR gate no longer false-denies a `/polish` run whose receipts were written from inside a
  linked worktree** (dir #61, felt 2026-07-23). `tools/pre-pr-gate.sh` keyed its receipt sentinel and
  its unlock-SHA check by the raw basename of a cwd — the receipt writer's own `$PWD` on one side, the
  `gh pr create` hook event's reported cwd on the other. When the two disagreed (the harness's tracked
  event cwd doesn't track an in-command `cd`, so it can report a different checkout of the same repo,
  e.g. the main checkout while the actual polish work happened in a worktree), the hook looked at the
  wrong sentinel file and compared against the wrong checkout's HEAD — denying every worktree-session
  PR outright. Both sides now resolve the repo's main-checkout top first (mirrors the `dir #10`/PR #67
  discipline already used for `.keel/` log resolution — logged in `dir #26` as a duplicated idiom with
  no shared lib yet), so a receipt written in a worktree and a hook event reporting the main checkout
  converge on one sentinel; an explicit `gh pr create --head <branch>` (or `-H`/`--head=`) is now
  parsed by the same awk lexer that finds `gh pr create`, so the SHA check compares against that
  branch's own tip (a ref shared across the repo's worktrees) instead of assuming the reported cwd is
  that branch's checkout. Without `--head`, behavior is unchanged (bare HEAD of the reported cwd) — a
  genuine ambiguity, correctly still denied. 14 new regression tests (worktree + main-checkout sentinel
  convergence, `--head`/`-H`/`--head=` forms, the no-`--head` denial, and the ordinary same-cwd case
  unaffected); existing 52 gate tests unchanged.
- **`keel-impact.sh add` no longer mis-attributes stale unconsumed log events to whoever's `add` runs
  next, and no longer credits a false guardrail fire as help** (dir #59, felt 2026-07-22 — the #58
  wrap's false-fire DENYs sat unconsumed in `.keel/impact-events.log` and silently landed in the next
  session's row, inflating its counts and its confidence tier; hand-corrected once by editing the
  ledger row + evidence note directly). Auto-ingest now age-caps: anything strictly older than
  `KEEL_INGEST_MAX_AGE_HOURS` hours (default 12; portable epoch→ISO cutoff conversion, BSD/GNU/busybox
  fallback chain, fails OPEN — ingests everything uncapped, with a warning — rather than crash or drop
  events on an unrecognized `date`) is stale: excluded from every count, archived to the evidence trail
  under a dated note instead of a citation, and still consumed (log truncated) so it never resurfaces.
  `--since ISO-TS` overrides the cutoff explicitly. Every ingested/stale-skipped event now prints to
  stdout, and `commands/keel-score.md`'s ritual gained the matching check: a foreign or falsely-fired
  `ingested:` line does not stay counted as `--guard` — correct it by hand (a false fire this session
  actually suffered is `--friction`, not `--guard`). Valence (whether a DENY was deserved) still isn't
  machine-decidable at gate time, so that half of the fix is the visibility + ritual, not a formula
  change.
- **Pre-PR gate's `gh pr create` match no longer false-fires on commands that merely CONTAIN the
  phrase** (dir #58, felt 2026-07-21 — hours after PR #125 merged, twice in one `/wrap`: two KB
  writes whose heredoc/quoted TEXT mentioned the phrase were denied as PR-creation attempts, each
  also swallowing the rest of its `&&` chain). The substring match added for dir #4/S6 (above) fixed
  the chained/prefixed-invocation miss but over-corrected into matching the phrase anywhere in the
  string. `tools/pre-pr-gate.sh`'s fast-exit is now a small awk lexer over the command: strips
  heredoc bodies, strips quoted spans, splits on command separators, then per segment skips leading
  `VAR=value` assignments and `env`/`command` wrappers and matches iff the first remaining token is
  exactly `gh`, followed later by `pr`, followed later by `create` — in real command position, not
  anywhere in the string. This also closes dir #4/S6's documented residual gap: `gh --repo owner/name
  pr create` (a global flag before the subcommand) is now caught too. Accepted residuals (a WORKFLOW
  gate, not the secret boundary): `sh -c 'gh pr create'` / `eval "gh pr create"` (quoted → stripped —
  a conscious regression from the substring match, which did catch these), `gh "pr" create`, a `gh`
  alias/wrapper-script rename, `env -u VAR gh pr create` (an `env` flag with its own separate value
  token). Inline `/polish` review (no `/code-review` skill in-session, so a single high-depth pass ran
  directly on the diff) caught one real gap before merge: a command chained AFTER a same-line heredoc
  marker (`cat <<EOF && gh pr create`) was being dropped along with the heredoc body instead of staying
  in scope — only the `<<[-]DELIM` token itself is heredoc syntax, not the rest of the line.
- **Audit-consolidation NITs batch (S4/S6/S7/S8, backlog dir #4).** The last actionable remainder of
  the audit-consolidation residue ticket (everything else in it is either already folded into other
  tickets, or a maintainer-only philosophy call — see `BACKLOG.md` #4):
  - **Pre-PR gate no longer misses a chained/prefixed `gh pr create` (S6).** `tools/pre-pr-gate.sh`'s
    PreToolUse(Bash) hook matched `gh pr create` only as a leading prefix, so `cd repo && gh pr
    create` or `FOO=bar gh pr create` fell through as "not our business" and skipped the /polish
    gate entirely — now a substring match. Residual, documented gap: a `gh` global flag before the
    subcommand (`gh --repo owner/name pr create`) still breaks contiguity and would still slip
    through; this stays a workflow reminder, not the secret boundary (that's secret-guard).
  - **CI's `shellcheck` job now pins an exact, checksum-verified version (S7)** instead of floating
    with whatever the runner image happens to ship — mirrors the SHA-pinned `actions/checkout`
    already used in every job.
  - **`install.sh`'s own Verify section now asserts `commands/keel-setup.md` landed (S8)** — the
    very command its closing summary tells the adopter to run next — instead of only `doctor.sh
    --install`'s separate audit catching a silently-skipped wiring bug.
  - **`bootstrap.sh` error paths gained regression coverage (S4):** missing git for `--link`,
    `--link` over an existing non-Keel directory, missing git+curl+wget, and a missing `bash` itself
    — each already failed loudly and correctly; now pinned by tests.
- **`branch-cleanup.sh` no longer offers to delete a merged worktree that's still a live parallel
  session** (dir #51, felt 2026-07-20). A merged, git-clean worktree used to grade ASK purely on
  commit age/name — but a session between its PR merge and the end of its own `/wrap` is
  clean-but-attached, invisible to that check, and got offered a destructive `git worktree remove`
  command. A new `--live-hours` mtime probe (default 6h) grades any file (or the `.git` link file)
  touched within the window as FLAG instead, regardless of age or cleanliness; `--live-hours 0`
  disables it. Portable across GNU/BSD/busybox (`stat -c`/`-f` fallback, plain `find` predicates).
- **`curl … | sh` copy-mode install no longer ships a dangling `keel` CLI** (v0.5.0's named known
  issue, the first public audit's one broken-functionality finding). Bootstrap's copy mode installs
  from a temp clone that is deleted right after the run, so the `bin/keel` symlink it used to wire
  pointed into a reaped directory (`keel help` → exit 127) and the closing summary promised
  `keel uninstall` and "KEEP this keel clone" for a clone that was already gone. Bootstrap now tells
  `install.sh` the checkout is ephemeral (`KEEL_EPHEMERAL=1`); the install skips the CLI symlink
  (announced, not silent), the verify step no longer grades it, and the closing summary honestly
  points every checkout-backed verb (the CLI, `keel uninstall`, tool-backed commands) at `--link`
  or a kept clone instead. Linked mode and clone-then-install keep wiring the CLI exactly as
  before; regression tests cover both sides.
- **secret-guard's zero-sha detection is now length-agnostic (SHA-256 repos).** `tools/secret-guard/range-lib.sh`,
  `ci-scan.sh`, and `pre-push` all detected git's all-zero "no commit" sentinel (a brand-new ref, or a
  branch/ref deletion) by comparing a sha against a hardcoded 40-char `SECRET_GUARD_ZERO_SHA` literal. On a
  repo using `git init --object-format=sha256`, that sentinel is 64 zero chars, so the exact-length compare
  would miss it, fall through to the "existing ref" branch, and hand `secret-scan.sh` an unresolvable range
  — a confusing blocked push rather than a correct scan (fail-closed, not a security bypass; no repo in the
  fleet currently uses SHA-256). Replaced with a shared `secret_guard_is_zero_sha()` helper in
  `range-lib.sh` that pattern-matches "all zero digits" regardless of length, used at all three call sites;
  the now-vestigial `SECRET_GUARD_ZERO_SHA` constant was removed. New direct unit coverage in
  `tests/test_range_lib.sh` for both the 40- and 64-zero cases.

## [0.5.0] — 2026-07-21

The first public global audit release: three independent external auditors (two repo-reading
sessions + the DeepSeek harness) swept the whole public tree; every confirmed finding is either
fixed below or tracked as an explicit known issue. Known issue: the `curl … | sh` copy-mode
install leaves the `keel` CLI symlink dangling (the bootstrap tmp-clone is reaped) — `keel help`
exits 127 on that path until the fix lands; linked mode (`--link`) and clone-then-install are
unaffected.

### Fixed
- **First public global audit (dir #50) — the verified findings of three independent external
  auditors, fixed in one pass.** Two Claude sessions (repo-reading) and the DeepSeek harness audited
  the public tree; every finding was adversarially re-verified against the live repo before any fix.
  Guard/installer correctness: `install-secret-guard.sh` now honors an **absolute** local
  `core.hooksPath` (it used to vendor into a junk dir under the repo while reporting success — guard
  silently inactive; mirrors `doctor.sh`'s handling) and rejects a surplus repo-path argument instead
  of silently dropping the first; `secret-scan.sh --range` with an unresolvable range and `--staged`
  outside a git repo now exit 2 per their own contract instead of failing OPEN as "clean";
  `install.sh`'s closing summary claims "secret-guard already guards your commits" only when the
  verify step actually proved it (after `--no-hooks`, a refused foreign hooksPath, or a wiring
  failure it now says the guard is NOT wired); `ci-scan.sh` handles the force-push topology the
  fail-closed `--range` exposed — an orphaned "before" sha (absent from the CI clone) now degrades
  to a full-history scan of "after" instead of reading as an error (or, before this release,
  silently as "clean"). Each fix carries a regression test.
  Doc↔reality corrections across README / `docs/`: the `keel` CLI is in `~/.claude/bin`, not
  magically "on your PATH"; "never touches a file you own" qualified with linked mode's one
  announced append; the CI platform list (three, incl. Alpine/busybox) and `keel help` verb list
  completed; `reference.md` inventory completed (bootstrap, install-secret-guard, keel-check,
  branch-cleanup, IDEAS template, maintainer-tooling note) and its `keel-impact` "off by default"
  corrected (init-project tracks by default); stale token figures refreshed (core ~2K, CHANGELOG
  ~25,000+, FRAMEWORK+PRINCIPLES ~12K); `keel-impact-evidence.md`'s worked example now matches its
  own formula (80/med, was 82/high); dead `evidence.md` pointer, doctor tier legend (+HINT),
  shellcheck in doctor's linter-gate list, `keel-impact.sh` usage (+`hold`), and two typos.

### Added
- **`docs/tier-growth.svg` — an animated companion figure for `docs/loading-and-cost.md`** (dir #44,
  PR #113). The "Three tiers" table states the tiering discipline at one instant; this figure shows it
  over time — a hand-authored, CSS-keyframe-animated SVG (same theme-aware, `prefers-reduced-motion`-safe
  technique as the `docs/session-start.svg` hero) cycling through session 1 → 10 → 30: the on-demand
  files grow, with `BACKLOG.md` visibly shrinking once as tickets close, while the always-on core bars
  and the "loaded at session start" token gauge never move.
- **`FRAMEWORK.md` — interview-loop discipline for a genuine multi-question elicitation.** CORE's
  "Decisions & forks" rail covers a single fork; the new "Interview loops" section is the operational
  elaboration for a decision-tree interview: check whether an answer is discoverable from code/docs/
  environment before asking (only put genuine judgment calls to the user), go sequential when a later
  question depends on an earlier answer but batch independent questions (deliberately not a blanket
  "one at a time" — that's a chat-interview convention, not a universal), always attach a recommended
  answer, and an explicit line that this doesn't lower CORE's bar for opening a fork in the first
  place. Names the thin-orchestrator/reusable-interview-skill split as a future idiom, gated the same
  way as the `git worktree list --porcelain` dedup (#26) — built only once a second command needs it,
  not speculatively. Sourced from reading a third-party Claude skill (`grill-me`/`grilling`) during an
  unrelated `/design` session; two of its ideas (ask-vs-look-up, always-recommend) generalized cleanly
  to Keel's own methodology.
- **`FRAMEWORK.md` — two knowledge-upkeep practices made explicit: the staleness check and
  decision capture.** "Delete what became wrong" gained its missing detection half — the pull-side
  note-age-vs-code-age check (compare `git log -1 --format=%cs` of a note against the code it
  describes when the note gets read; older note ⇒ suspect), with its limits stated honestly (lazy,
  per-file; no push triggers or dependency graphs by design). And the CORE persist rail's
  "record the fork" line gained its visible workflow: draft the one-line record (choice + dated why)
  the moment a fork settles, human ratifies the wording, the wrap red-flag sweep as the net —
  a process, not a record format. Both were told as raw practice for weeks; field demand
  (independent practitioners asking for exactly these mechanisms) promoted documenting them.
- **`tools/doctor.sh` — triaged output: GAP → WARN → HINT, stable IDs, an accept file, a tail summary.**
  A brownfield adopter's first `keel doctor` run used to be a flat, unordered stream of every advisory
  finding, jargon-heavy and un-triaged — alarm fatigue risked drowning the few WARNs that actually
  protect the adopter (leak risk, rails not wired) among convention nudges (missing lint gates,
  floating dependency versions). Findings now print ordered by severity — GAP (fails the audit) → WARN
  (safety/integrity) → HINT (engineering-convention nudge, the new third tier) — each carrying a stable
  ID (`G-*`/`W-*`/`H-*`) referenceable in docs and issues. `.keel/doctor-accept` (main checkout, one ID
  per line, `#` comments) suppresses a listed WARN/HINT class; a GAP can never be suppressed. Every run
  ends with a tail summary (`doctor: X gap, Y warn, Z hint (N accepted hidden)`), on both clean and
  dirty runs. `--quiet` now hides HINTs (the tier a quiet run wants gone) while `--all` reveals anything
  `.keel/doctor-accept` suppressed. `--install` mode's findings gained the same ID scheme (GAP/WARN
  only — it has no HINT tier).
- **`install.sh --no-git` — trim the code/git rails from a linked install's always-on core.**
  `CORE.md` now fences its two code/git-specific sections ("Git — mandatory rails", "Before writing
  code — reconcile first") in `KEEL-GIT` markers, and `install.sh --link --no-git` generates
  `keel/CORE.md` as a trimmed copy of the shipped core (marked blocks removed) instead of the symlink —
  keeping the one `@import` line and pull-through for everything else. Closes the gap where a
  linked-mode no-git user could only trim by de-linking into copy mode. The trim is deliberately
  install-time, not load-on-demand: for anyone who DOES use git, the safety rails must sit in context
  before the first git command. Three detectors guard the risky no-git → git transition: the trim
  leaves a constant always-on breadcrumb telling the assistant to restore the rails before any git
  work; `doctor.sh --install` warns when the trimmed copy is stale against the checkout, when
  `keel/CORE.md` is a regular file without the `KEEL-NOGIT` marker, and when a registered project
  lives in git under a trimmed core; and `/keel-setup` now handles both directions of the transition.
  The trim is sticky — a plain re-run keeps it and refreshes the generated copy (healing staleness);
  restoring is explicit via `--with-git`.
- **README — "What Keel brings": the four result-properties as the front-door answer to "why".**
  A short section right after the hook naming what Keel aims to bring to work with any model —
  economy, stability, constraint, and accumulation — ordered from the most immediately felt to the
  project's telos (P0), each labeled with the force it holds at (structural / nudge / mechanical),
  cross-linked to the existing "what runs by itself vs what only nudges" honesty split. Complements
  the "three plain ideas" (how it's built) with the properties of the result (what you get).
- **`docs/mcp-decision.md` — MCP analyzed and deliberately not adopted.** Examines three roles MCP
  could play (Keel as an MCP server, Keel managing MCP config, docs-only acknowledgement) against
  P0–P4 and rejects the first two: the always-on core needs *injected* text while MCP delivery is
  agent-requestable (the Cursor `.cursor/rules` failure mode as normal operation), an MCP server
  breaks the zero-dependency boundary, and wrapping the git-level tools as MCP tools would trade
  zero-token mechanized enforcement for a callable the model must remember to use. MCP servers stay
  an `INSTANCE.md` environment fact; the doc names the three felt-friction triggers that would
  reopen the decision. The cheap-absorption move `PRINCIPLES.md`'s success test calls for — a parked
  note, not a restructuring.
- **`doctor.sh` — Bash/ShellCheck as a fourth per-stack lint gate (#100).**
  Extends the existing Java→Checkstyle / Python→Ruff / Swift→SwiftLint gate with Bash: a repo with
  first-party `*.sh` files is flagged unless it carries a first-party `.shellcheckrc`, or invokes
  `shellcheck` somewhere under `.github/workflows`. The second signal exists because, unlike the other
  three tools, shellcheck runs perfectly well with zero configuration — a bare "config file present"
  check would false-positive on any repo (this checkout included, which runs `shellcheck` straight in
  `ci.yml` with no rc file) that adopted the gate without ever needing a config.
- **"Loop model" section in `FRAMEWORK.md`.** Documents the KB's four operational loops — Session,
  Wrap, Global review, and Dev — each with its input, work, carry-forward, termination, frequency, and
  observability, plus their coupling and known gaps. Gives future cadence/convergence work a stable
  shared vocabulary instead of ad-hoc reasoning about "the review process."
- **`/go` in-flight discipline (backlog dir #40).** Before picking a ticket, `/go` now scans
  `git branch -a` (after `git fetch --prune`) for a live branch already working it — the installed
  `go-<n>-` branch pattern first, then a keyword grep of branch names against the ticket title. A
  match stops with "in flight on `<branch>`" instead of re-picking, offering to continue that branch
  or pick another. Right after cutting its own branch, `/go` now also claims the ticket by writing a
  `⏳ IN FLIGHT (YYYY-MM-DD, branch <name>)` marker onto its backlog heading, which the closing sweep
  replaces with ✅ on merge. Closes a gap the existing "already closed in a parallel session" rail
  didn't cover: a ticket already *in progress*, not yet closed (felt when a grooming session appended
  spec notes to a ticket mid-implementation by a parallel `/go` session).
- **`doctor.sh` map-drift check (backlog dir #39, T1).** A new advisory WARN: a backtick-spanned
  path/filename in a project's live `CLAUDE.md` (never `CLAUDE-archive.md`/`BACKLOG.md`, which
  legitimately name historical paths) that no longer resolves on disk — the map goes stale as code
  moves, and an agent that trusts it confidently follows a dead path. Precision is built in, not
  post-hoc tuned: only backtick spans count (the author's own "literal identifier" marker), a span's
  trailing args/flags are stripped to its first token, and placeholders/globs/env-vars/`~`-paths/
  absolute paths (including the KB's neutral stand-ins) are skipped as unverifiable by design. An
  accepted mention lands in a gitignored `.keel/map-drift-baseline` (one path per line) and never
  warns again; for a linked worktree the baseline resolves to the MAIN checkout's `.keel/`, never a
  worktree-local one, so accepting a mention never tempts anyone into creating the split-brain `.keel/`
  the existing impact-tracking check already flags. `init-project.sh` now gitignores the baseline path
  up front. Report is capped at 5 named paths plus an "and K more" tail.
- **Unified `keel` CLI — one entry point over the lifecycle tools (backlog dir #2, phase 1).** A single
  zero-dependency POSIX `keel` script at the repo root, put on your PATH by `install.sh` (as a symlink
  into the checkout, under `<home>/bin/`, never over a file you own). It dispatches
  `keel install [--link]` → `install.sh`, `keel sync` → git pull + re-wire, `keel doctor [--install]`,
  `keel audit` → `public-audit.sh`, `keel init` → `init-project.sh`, `keel check` → `keel-check.sh`,
  `keel uninstall`, and `keel version`/`keel help`. Every verb is a rename of an existing script's
  invocation — no new capability except `uninstall` — so the tools finally work from **any** directory,
  not only from inside the clone (the felt D1 papercut: installed commands referenced `tools/*.sh` by
  repo-relative paths unresolvable from a user's own project, hit live with the first external adopter).
  The dispatcher resolves its own checkout by following the PATH symlink (portable, no `readlink -f`),
  and passes each child's exit code straight through; an unknown verb prints usage and exits 2.
- **`uninstall.sh` — reverse `install.sh`, backing up what it removes (backlog dir #13, via #2).** The
  mirror image of the install write-list: it removes only Keel-owned content (the linked `keel/`
  consumption dir, the one `@import` line / embedded `KEEL-CORE` block in the global `CLAUDE.md`, the
  command symlinks + `keel-<name>` collision aliases, the `bin/keel` PATH symlink, and any copy-mode
  `FRAMEWORK`/`PRINCIPLES` it placed). Refuse-to-clobber in reverse: a command or on-demand file that
  *differs* from what Keel ships is treated as yours and left in place; `INSTANCE.md`/`LEARNINGS.md`/
  `IDEAS.md` are never touched; the machine-global secret-guard is kept (a shared safety net — its
  removal is a separate, announced one-liner). Everything it removes is **moved** into a timestamped
  backup dir under the home (nothing hard-deleted), so an uninstall is reversible. `--dry-run` previews;
  `--yes` is required when not run from a terminal. `tools/doctor.sh --install` now also reports the CLI's
  presence (and flags a dangling or foreign-checkout `bin/keel`). Covered by `tests/test_keel_cli.sh`
  (dispatch table, exit pass-through, self-resolution, the orphaned-`keel` guard) and
  `tests/test_uninstall.sh` (a real install→uninstall round-trip in both modes, no-clobber, dry-run,
  backup, idempotence).
- **Server-side `secret-scan` CI job (SEC4, backlog dir #37).** A new `secret-scan` leg in `ci.yml` runs
  `secret-scan.sh --range` on every pull request and every push to `main` — the security floor the guard
  was missing: previously the scan ran only in the local `pre-commit`/`pre-push` hooks, so a contributor
  without the hook installed (or a hand-crafted push) shipped unscanned into the public repo. The range
  is resolved by the new `tools/secret-guard/ci-scan.sh` (a PR's `base..head`, or a push's
  `before..after`) — no new detection logic, reuses the existing scanner as-is. The job checks out with
  `fetch-depth: 0` + `filter: blob:none` (full commit ancestry for the range walk, blob content fetched
  lazily only for what the scan actually reads) and needs no repo secrets, so it runs safely on fork PRs
  too. Only key shapes and agent session-metadata trailers are checked in CI — the personal-literal list
  stays local-only by design (`$SECRET_SCAN_PERSONAL_FILE`, gitignored) and is never sent to a CI runner.
  SECURITY.md notes the new floor.

  The first-push all-zero-`before` case moved into a new shared `tools/secret-guard/range-lib.sh` — but
  as two distinct functions, not one: `resolve_range_local()` (the pre-push hook's existing `--not
  --remotes` trick, valid there because the hook runs *before* git updates the remote-tracking refs for
  its own push) and `resolve_range_ci()` (a CI checkout runs *after* the push already landed, so its
  remote-tracking refs reflect post-push state — reusing the `--not --remotes` trick there would exclude
  the very commits it should scan and silently pass a brand-new ref's first push as clean; the CI
  variant scans the full history reachable from `after` instead). `ci-scan.sh` also explicitly skips a
  ref-deletion push (`after` is the all-zero sha) rather than let an unresolvable range fail silently,
  and a missing/unrecognized event or env var is a clean exit 2 (config error), never the exit-1 code
  `secret-scan.sh` reserves for "a secret was found". `tools/install-secret-guard.sh` now vendors
  `range-lib.sh` alongside `pre-push` (it was missing it, which would have broken every freshly
  installed hook's first real push). Regression tests in `tests/test_ci_secret_scan.sh` (16 cases,
  including a real bare-repo-push-then-clone reproduction of the CI remote-state gap) and
  `tests/test_secret_guard.sh` (an end-to-end run of the *installed* `pre-push` hook, not just
  `secret-scan.sh`'s own `--selftest`) cover the above.

### Changed
- **`commands/keel-setup.md` — step 3's scope question and step 4's report are now unconditional
  (backlog dir #20).** Felt incident: `/keel-setup` on a fully-configured machine produced zero output,
  reading as broken. The spec already mandated a scope question and a checked/skipped/why report even
  when nothing changes, but the bullets weren't structured to guarantee either — restructured so the
  scope question always fires (independent of the template-fill / linked-install / pre-existing-file
  bullets) and step 4 always ends with a visible report, explicitly covering the nothing-to-do case.
  Docs-only, no script changes.
- **`secret-guard` — the `--range` commit-message pass now scans all three detector classes (backlog
  dir #12).** Previously a pushed *commit* message was checked only for agent session-metadata trailers,
  while the annotated-*tag* message pass already checked key shapes and personal literals too — so a
  `ghp_…` key or a personal literal in a commit message shipped uncaught while the identical text in a
  tag message blocked. The commit-message pass now matches key shapes, personal literals, and session
  metadata, converging the two message passes. The three near-identical fast-path count idioms in the
  `--range` arm (blob stream, commit messages, tag bodies) fold into one shared `count_matches` helper
  that preserves the `grep -c` (not `-q`) SIGPIPE/pipefail discipline. Regression tests: a key and a
  personal literal in a pushed commit message both block. No new false positives — the sanctioned
  `noreply` co-author trailer still passes.
- **`README.md` — body restructured for scannability (phase 2 of the README rework).** Install now leads
  with one recommended path (`git clone … && ./install.sh --link`); the alternatives (curl one-liner,
  agent-install prompt, the install-flows table, version pinning, the no-git fallback) fold into a single
  collapsible "Other ways to install". "The idea" and the "How it loads" diagram merge into one *How it
  works* section (pinned token figures unchanged). The 16-row "what's in the box" table moves to a new
  grouped, one-line-per-row [`docs/reference.md`](docs/reference.md); the README gains a short *Docs*
  pointer section instead. Tests/Scope/License collapse into one closing section; stale `#quickstart`
  anchors in `docs/getting-started.md` and `examples/README.md` fixed. No install-flow behavior changed —
  a density pass only.
- **`README.md` — install alternatives ranked, diagram labels sharpened (phase-2 follow-up).** The
  collapsed "Other ways to install" block gains a real heading (linkable anchor), Install points at it
  explicitly, and the flows are ranked **#1 → #3 simplest-first** (ask your agent → curl one-liner →
  manual clone) so a newcomer picks by fit instead of weighing four equal rows. The *How it works*
  diagram's always-on label now says the ~1.8K figure is the thin core alone (the project file adds its
  own), and the zero-token tools list is marked as non-exhaustive.
- **`commands/go.md` — `/go` now reads a project's on-demand `BACKLOG.md` first (backlog dir #34).** A
  project can split its backlog out of the always-loaded `CLAUDE.md` into a separate `BACKLOG.md` at the
  main checkout root; `/go` now resolves that source the way `/backlog` already does (`BACKLOG.md` →
  inline `CLAUDE.md` section) and loads only the addressed item — a task id greps the `### N.` heading and
  reads just that section plus its cross-links, a phrase does one keyword grep, and a heading that isn't
  found makes `/go` stop instead of inventing a task. Keeps a `/go` session's warm-up cost flat as the
  backlog grows.
- **`tools/init-project.sh` / `tools/doctor.sh` — impact-tracking marker creation and split-brain
  detection now mirror PR #67's worktree discipline (backlog dir #10 residue).** `init-project.sh`
  previously did a raw `mkdir -p .keel` at the CWD; run from a linked worktree, that planted a stray
  local marker invisible to every other worktree (untracked dirs aren't shared). It now delegates to
  `keel-impact.sh enable`, which always resolves to the MAIN checkout's top first. `doctor.sh` gains a
  matching WARN for markers `enable` created before this fix (or any other leftover worktree-local
  `.keel/`): it fires from either side — a worktree carrying its own marker next to the main checkout's,
  or a main checkout whose linked worktrees carry their own — since PR #67's resolvers try the current
  top first, and a leftover local marker silently diverts that worktree's events into its own ledger
  while the main-top ledger undercounts. `keel-impact.sh enable` also regains the idempotent
  "already enabled" (vs. "enabled") distinction the old inline code had, restoring the `=`/`+` reporting
  convention `init-project.sh`'s other steps still follow — a code-review pass on this PR caught that the
  delegation had silently dropped it.
- **`tools/branch-cleanup.sh` — a merged worktree is now graded by LIVENESS instead of always being
  FLAGged.** Previously every merged branch checked out in a worktree went to FLAG (manual review), even a
  long-idle one holding nothing — so worktrees never got auto-cleaned and piled up (this repo hit 12). A new
  `worktree_state` check inspects the worktree: **clean** (no tracked/untracked work; only provably
  disposable gitignored state — a `CLAUDE.md` symlink into the main checkout, the worktree's `.claude/`,
  `.DS_Store`, regenerable build dirs) + old + ephemeral name → **AUTO**, removed with `git worktree remove`
  (never `--force`) and its branch deleted, exactly like a confident free branch; **keep-ignored** (holds
  non-disposable gitignored content such as `private/`, a local `.env`) or recent/off-pattern → **ASK**;
  **dirty** (uncommitted or untracked-non-ignored work, which `git worktree remove` would refuse) → **FLAG**,
  surfaced for review with no destructive command. `--prune-safe` now removes the dead-worktree AUTO tier
  too. The current/own worktree and `KEEL_KEEP_WORKTREE` are still never touched; `commands/wrap.md`'s step-0
  tier description is updated to match.

### Added
- **`CORE.md` — new always-on Verify rail: "stop the spiral" (backlog dir #33, tier T0).** After the same
  declared check fails twice, stop and diagnose what you misunderstood instead of emitting a third variant on
  hope — repeated failure is a missing *cause*, not a missing attempt. Felt: an operator observation that no
  model — not even the weakest — ever says "I can't" or "I don't understand"; a result *always* exists, but it
  may be non-working, and the model then circles through ever-new "this time it'll work" variants, burning
  time for zero benefit. This is the cheapest tier (a nudge in the always-loaded core) of a planned
  anti-hallucination *floor*: the model-independent enforcement (a `keel check` shim + a hook that hard-blocks
  an artifact while the declared check is red and interrupts on the N-th red) is the follow-up tier T1. The
  rail complements the adjacent "a blank beats a wrong guess" line. Mirrored byte-equal into
  `templates/CLAUDE.md` (the copy-path wrapper); no token-figure bump — it fits inside the existing ±10% band.
- **`tools/keel-check.sh` — the stop-mode floor, model-independent half (backlog dir #33, tier T1a).** Run
  a task's declared verification command through this shim (`keel-check.sh "npm test"`, or an argv form
  `keel-check.sh go test ./...`) and repeated failure becomes a *mechanical* signal: it counts consecutive
  failures of the same check and, on the 2nd (tunable via `KEEL_CHECK_THRESHOLD`), prints a
  STOP-and-diagnose banner instead of letting the agent spiral into a third variant on hope. A pass resets
  the streak; the check's own exit code passes through (callers/CI see the real result); zero dependencies
  (POSIX `cksum` keys the per-task counter, busybox-safe). Where the `CORE.md` rail above only *nudges*,
  this *holds* — the banner fires off the exit code no matter the model's strength. Optional: appends one
  zero-token friction event to `KEEL_IMPACT_LOG` on a stop, mirroring the other guardrails. The banner says
  *what* to do (diagnose), never *how* to defeat the check (applies the "Enforcement mechanics" convention
  below). The opt-in HARD veto — block a commit/PR while the declared check is still red — is the follow-up
  tier T1b.
- **`tools/keel-check-gate.sh` — the opt-in HARD veto for the stop-mode floor (backlog dir #33, tier T1b).**
  A Claude Code `PreToolUse(Bash)` hook (the same proven shape as `pre-pr-gate.sh`): while a check the agent
  declared through `keel-check.sh` is still RED, it blocks `git commit` / `gh pr create` — the "no artifact
  below the gate" half of the anti-hallucination floor (`PRINCIPLES.md` P1). Where the `CORE.md` rail nudges
  and the shim's banner interrupts, this *refuses* to let a confident "done" reach a commit while that same
  check is failing; a green re-run through `keel-check.sh` clears the marker and the commit proceeds. OFF by
  default — enable per session with `KEEL_CHECK_VETO`, so a deliberate work-in-progress commit on a red test
  is never blocked unless you asked for it. The deny message says *what* to do (make the check pass), never
  *how* to defeat the gate (applies the "Enforcement mechanics" convention below); a zero-token guard event
  goes to `KEEL_IMPACT_LOG` on a block. To support it, `keel-check.sh`'s per-task counter moved under a
  per-repo directory so the gate can answer "is any declared check for this repo still red?" cheaply.
  Maintainer-registered like `pre-pr-gate` — `install.sh` does NOT auto-wire it into an adopter's
  `settings.json` (that adopter auto-registration, plus a per-repo `.keel/stop-mode-veto` enable marker with
  the worktree→main-checkout fallback, are a deferred tier). 16 offline tests, jq-gated so they skip cleanly
  on the busybox CI leg.
- **`FRAMEWORK.md` — new convention "Enforcement mechanics — never name the bypass in the error text".** An
  enforcement mechanism (commit hook, gate, guard, CI check) is read by an *agent*, not just a human, so any
  bypass instruction printed in its block/error message becomes a step-by-step exploit the agent follows to
  get unblocked. Felt twice: `pre-pr-gate` once printed the literal `touch …` unlock command → the agent ran
  exactly that; `secret-guard`'s block message names `.secret-scan-allow` → an agent (being tested on Cursor)
  wrote that allowlist to commit a secret-shaped key. The rule: say *what* is wrong and *what* to do at the
  task level, never *how* to defeat the check; keep a legitimate human escape hatch out-of-band and not
  agent-usable in-band; the guard, not its prose, is the enforcement. (Surfaced while validating Keel's rails
  on non-Claude tools; the `secret-guard` message is hardened to match — see Security below.)

### Security
- **`secret-guard`'s block message no longer prints the allowlist bypass syntax.** It used to say "add it to
  `.secret-scan-allow` or an inline `secret-scan:allow`" — a ready-made bypass an agent optimizing to get
  unblocked will follow, and one did: while validating the rail on Cursor, an agent hit the guard on a fake
  AWS key, read that line, wrote the allowlist, and committed the key. The message now states *what* is wrong
  ("remove it — use an env var or a secret manager") and notes a genuine test fixture is a deliberate human,
  out-of-band decision, with an explicit "an agent must NOT add an allowlist entry just to get a commit
  through." The allowlist mechanism is unchanged — a real human fixture still works; only the block message
  stops advertising the bypass. Regression test added. Applies the new `FRAMEWORK.md` "Enforcement mechanics"
  convention above.
- **`commands/wrap.md` opens with a composed-component banner** (backlog dir #27). If you layer your own
  `/wrap` (extra persist/backup steps) on top of Keel's base, an agent that reads this base to "wrap the
  session" can run it standalone and silently skip your wrapper's steps — a real footgun hit while
  dogfooding. A banner at the top of the base now redirects to the composing `/wrap` when one exists, with
  an explicit carve-out for the correct case (a wrapper that told the agent to read+execute the base).
  Benefits any adopter who composes over the base, not just Keel's own setup.
- **`tools/branch-cleanup.sh` — a confidence classifier for post-merge branch/worktree cleanup, wired
  into `/wrap` step 0** (backlog dir #25). CORE.md's git rails promise "merge → delete the branch", but
  nothing closed the loop: merged local branches and their worktrees piled up (this repo hit 12 live
  worktrees, several on already-merged branches). The tool reads only git facts — zero-dependency,
  network-free — and grades every local branch by how safe deletion *provably* is, never a blanket
  delete: **AUTO** (merged into `origin/<default>`, no worktree, ≥7 days old, ephemeral name — a
  redundant pointer whose commits all survive on the default branch, so deletion loses nothing),
  **ASK** (merged but recent or an off-pattern name that may be long-lived like `staging`/`release-*` —
  surfaced for confirmation, never auto-deleted), and **FLAG** (merged but checked out in a worktree —
  reported with `git worktree remove <path>`, never auto-removed since a worktree can hold uncommitted
  or gitignored work). The current session's branch/worktree and any unmerged branch are always left
  alone. `--prune-safe` deletes the AUTO tier; default is a non-destructive report. "Merged" = the tip
  is an ancestor of `origin/<default>` (assumes the `git fetch --prune` `/wrap` already runs), so a
  squash-merge workflow leaves its branches unlisted rather than risk a false delete — the honest
  zero-dep boundary (`gh`-based squash detection is left to the future unified CLI). 33 checks in
  `test_branch_cleanup.sh` pin every tier, the age gate, current-branch/worktree protection, the
  `origin/<default>` base path, and that `--prune-safe` deletes only AUTO.
- **`bootstrap.sh` gets a permanent-clone linked mode, a no-git tarball fallback, and an
  agent-install prompt** (closes backlog dir #21, flows 1/2b/2c). Previously `--link` refused
  outright — the one-liner's clone lived in a reaped temp dir, so every symlink would dangle on exit.
  Now `bootstrap.sh --link` clones into a **permanent** dir (`KEEL_DIR`, default `~/keel`), never reaps
  it, and re-running the same line over that checkout updates it in place instead of re-cloning (a
  `git fetch` + `checkout` when `KEEL_REF` is set, otherwise a fast-forward `git pull`) — collapsing
  clone + `cd` + `--link` into one pasted line. A non-Keel directory already occupying `KEEL_DIR` is
  refused, never clobbered. **No git?** The copy-mode default now falls back to downloading a source
  tarball (`${REPO%.git}/archive/${KEEL_REF:-main}.tar.gz`, or `KEEL_TARBALL` for a URL or local file)
  via curl/wget, installs the **prose rails + commands only** (`--no-hooks` forced — secret-guard is a
  git hook, so it's skipped and announced up front rather than failing on a bare "git not found").
  Version selection (`KEEL_REF=<tag>`, no flag = latest `main`) works identically on every path. The
  README also gains a one-sentence **"let your assistant install it"** prompt — paste it into Claude
  Code and it clones, picks linked-vs-copy for the machine, and points you at `/keel-setup`. 18 new
  checks across `test_install.sh` (`KEEL_TARBALL` path, a PATH-farm that hides git) and
  `test_install_link.sh` (permanent-clone, in-place re-run, refuse-foreign-dir); a review pass caught
  one bug before merge — a re-run ignored `KEEL_REF` and silently kept the old version, fixed
  (fetch + checkout) with a regression test. Live network download isn't CI-tested (CI runs offline) —
  covered by inspection and the local-`KEEL_TARBALL` path instead. Flow 4 (a git-free `.dmg`/download
  package) stays deferred until real no-terminal demand appears.

### Changed
- **`/wrap` gains a `-s` flag that makes the Impact step run `/keel-score` unconditionally.** Step 7 (Impact)
  was optional-by-judgment — the agent decided whether the session "leaned on Keel enough" to score. Passing
  `-s` (surfaced via `argument-hint`) removes that judgment: the wrap runs `/keel-score` for the session even
  a light one, so a run you want tracked can't be silently skipped. Without the flag the behavior is
  unchanged (optional, by judgment).
- **`ADAPTING.md` rewritten around the first live cross-tool validation** (closes backlog dir #30/#31/#32).
  Until now the doc's honesty caveat was "the author only tested Claude Code"; Keel has since been run live on
  three substrates and the doc now reflects it. The tool table gains a `Tested?` column and splits **Codex in
  the ChatGPT desktop app** (`~/.codex/AGENTS.md`, a skills system rather than prompts, its own native memory)
  from the standalone **Codex CLI**. The **Cursor** row now points at project-root **`AGENTS.md`**, not
  `.cursor/rules/*.mdc` — in testing an `alwaysApply: true` `.mdc` loaded as *agent-requestable on demand* so
  the rails silently didn't fire (the agent committed straight to `master`), while the identical core in
  `AGENTS.md` injected as always-on and fired; a warning callout documents this, plus an "`AGENTS.md` is the
  emerging cross-tool standard" note (the same file worked on both Codex and Cursor). A new callout records
  that skills systems (Codex, Cursor) convert Keel commands 1:1 — autopilot, not paste-by-hand. The honest
  boundary gains: Codex's native memory means dropping the Memory section, and the prose nudge **scales with
  model strength** — weak and unreliable on a small local model, with the git-level `secret-guard` the only
  model-independent floor. `docs/loading-and-cost.md`'s `ADAPTING.md` figure bumped ~1,650 → ~2,300 to match.
- **`README.md` reworked for usability — a first-screen a newcomer can actually parse** (closes backlog
  dir #28). The old front door stacked three competing intros before any action and pushed
  objection-handling above the install. Now it leads with one hook (*"Context isn't free — and most of
  yours is clutter"*) aimed at the real 2026 pain — a bloated `CLAUDE.md` and junk-drawer `.claude/`
  reloading as context ballast every session — then a plain what/who/win lead that names the target
  adopter, then an animated before/after hero (`docs/session-start.svg`, theme-aware with a
  `prefers-reduced-motion` fallback) that shows the *product* (the always-on context layer), not a
  single tool. Install now sits right after the hero; the honest "runs by itself vs advice that nudges"
  split is lifted up as **What you actually get**; the long capabilities table is demoted to
  **Reference: what's in the box**; the objection blockquotes are folded into a **Good to know** section
  at the end. The secret-guard `demo.gif` moved down beside **Just want the git hook?** (it demos one
  tool, so it no longer occupies the most valuable real estate). The pinned mermaid token figures
  (`~1.8K` / `FRAMEWORK.md ~5.0K` / `PRINCIPLES.md ~5.1K`) are unchanged — `test_doc_figures.sh` stays
  green.
- **The `CORE.md` decision rail now explicitly discourages over-asking.** The "small things with an
  obvious default" bullet gained a sharp clause: *don't ask to confirm a documented flow or a default
  you'd pick anyway — a prompt whose answer wouldn't change what you do is friction, not diligence;
  reserve a question for a real fork.* The rail already said "pick something reasonable and move on," but
  the soft wording didn't counter an agent that reflexively confirms established flows (e.g. an open-a-PR
  step with a documented default). Naming the anti-pattern in the always-loaded core gives every session
  an explicit brake. ~48 tokens; `CORE.md` stays inside the 10% figure band and the wrapper embed stays
  byte-equal (`test_core_wrapper_sync.sh` + `test_doc_figures.sh` green).

### Fixed
- **The `commands/*.md` token band no longer forces a doc bump every time a command grows** (closes the
  recurring papercut, backlog dir #3b — felt four times). `docs/loading-and-cost.md` quoted a hard
  `[LO, HI]` band and `test_doc_figures.sh` asserted every command file fell inside it, so growing any
  command past `HI` tripped CI and needed a manual figure bump (or a trim to fit). The HI now carries a
  trailing `+` (`~250–1,450+ each`) making the upper bound an **open floor** — the same growth-tolerant
  semantics the monotonic CHANGELOG row already uses (dir #3). Understating your own ceiling behind an
  explicit `+` is never an overclaim of cheapness; the LO floor stays enforced so the quoted minimum
  can't drift above the smallest command. This unblocked adding the dir #27 banner to `wrap.md` (which
  pushed it past the old ceiling) in the same PR.
- **`install.sh --link` refuses to link the checkout into itself** (closes backlog dir #23). If the
  consumption dir resolves to the checkout itself — e.g. `--link --home "$HOME"` while the checkout
  sits at `$HOME/keel` (bootstrap's default `KEEL_DIR`) — the old code let `sync_product` see source
  and destination as the same inode and "upgraded" the checkout's own `CORE.md`/`FRAMEWORK.md`/
  `PRINCIPLES.md` into symlinks pointing at themselves, corrupting every file the links resolved to.
  A `[ "$link_dir" -ef "$root" ]` guard now refuses that invocation (exit 2, checkout untouched) with
  a message pointing `--home` at your Claude home instead. Near-zero real-world likelihood (the
  `--home "$HOME"` needed contradicts the docs) but silently destructive — surfaced by the dir #21
  install-flows review. Regression test in `test_install_link.sh`.
- **Impact tracking now works from linked worktrees** (felt on keel's own dogfooding, backlog dir #10:
  the `.keel/` marker is an untracked dir, so a linked worktree's top never carries it — guard events
  from worktree sessions silently vanished and self-scores undercounted). All four resolution sites —
  the guardrail snippets in `secret-scan.sh` / `pre-pr-gate.sh` / `public-audit.sh` and
  `keel-impact.sh`'s `_keel_top` — now fall back to the MAIN checkout's top (first `git worktree list`
  entry; equals the current top in a plain repo, and the awk reads its whole input, so no
  SIGPIPE-under-pipefail regression). `keel-impact.sh enable` run from a worktree likewise targets the
  main checkout instead of creating an ephemeral in-worktree marker. Regression tests: worktree
  event/add/enable resolution in `test_keel_impact.sh`, an in-worktree block recording to the main log
  in `test_secret_guard.sh`.

- **`install-secret-guard.sh <repo>` no longer silently overwrites your own git hook** (closes audit
  finding SEC1's pre-commit-clobber half). A pre-existing `pre-commit`/`pre-push` that isn't Keel's own
  (detected by the `Keel secret-guard` marker) is treated as higher-precedence user data: the install
  now **refuses by default** with a message on how to proceed, leaving the file untouched. Pass
  `--force` to back it up to `<hook>.pre-keel.bak` and replace. The same guard covers the machine-global
  slot — a foreign `--global core.hooksPath` is not replaced without `--force` (matching what `install.sh`
  already did before delegating). Re-vendoring Keel's own hook stays silent and idempotent. This makes
  the "never clobber user data" rule `install.sh` already followed hold in the low-level tool too.
  Regression tests: refuse/`--force`/backup/no-false-refusal in `test_secret_guard.sh`.
- **`tools/branch-cleanup.sh` no longer FLAGs the session's own worktree for removal** (backlog dir #25
  follow-up). The "never touch the current worktree" guard compared the branch name of the *invoking*
  cwd (`git rev-parse --abbrev-ref HEAD`), so when the tool ran from a different directory than the
  session's worktree — e.g. `/wrap` reconciling from the main checkout — the session's own worktree
  (usually already merged, since you reuse it after its PR lands) was mistaken for a stale one and
  printed with `git worktree remove <its own path>` every session. The guard is now **path-based**
  (`git rev-parse --show-toplevel`, compared with `-ef` so symlinked temp dirs match), and a new
  `KEEL_KEEP_WORKTREE=<path>` env var lets a caller that must run from elsewhere name the worktree to
  protect — `commands/wrap.md` step 0 now documents running from the session worktree or exporting it.
  Two regression tests pin it: running *inside* a merged worktree never flags that worktree (while a
  *different* merged worktree still FLAGs), and `KEEL_KEEP_WORKTREE` shields a named worktree from a run
  elsewhere.

### Added
- **`tools/self/doctor.sh` — a structural self-audit of the keel repo itself**, distinct from
  `tools/doctor.sh` (which audits a *consumer's* project or install). Native checks: `install.sh`'s
  command ship-skip list agrees with `doctor.sh --install`'s mirror of it, every
  `tools/`/`commands/`/`templates/` path referenced in tracked docs and scripts resolves on disk,
  every `tools/*.sh` script is referenced somewhere and covered by a test, `CHANGELOG.md` isn't stale
  relative to the last `commands/`/`tools/`/`install.sh` change. It deliberately *orchestrates* rather
  than duplicates — folding `tests/test_doc_figures.sh`, `tests/test_core_wrapper_sync.sh`, and a
  shellcheck sweep into one report instead of re-implementing their logic. Shellcheck's own
  file-selection logic moved out of `ci.yml` into a shared `tools/self/shellcheck-targets.sh`, used by
  both. Wired into CI as a 4th job (`self-check`) and into `/polish` (a new step 7: a GAP blocks the PR
  gate the same as a red test, skipped silently for any project that doesn't ship the script). Caught
  three real bugs on itself during its own `/simplify` + `/code-review high` pass — including a live
  one already on this branch: a plain bash glob doesn't cross `/`, so the tracked
  `tools/secret-guard/secret-scan.sh` was invisible to its own tool-wiring check. 34 regression tests
  across `tests/test_self_doctor.sh` + `tests/test_shellcheck_targets.sh`.

- **Linked install — `install.sh --link` makes the checkout the installation** (closes backlog dir #17,
  stages 2–3; dissolves audit finding D1's confusing-leftover-clone half). Instead of copying, `--link`
  wires Keel by reference: a `<home>/keel/` consumption dir of symlinks into the checkout
  (`CORE.md`/`FRAMEWORK.md`/`PRINCIPLES.md` + a generated README), **one `@…/keel/CORE.md` import
  line** in the global `CLAUDE.md`, and the commands as symlinks — so `git pull` refreshes every
  consumer at once, and removal is mechanically enumerable (the dir, the line, the links — the
  reverse-list backlog dir #13 was missing). The one seam between the modes is a `place`/`in_sync`
  pair inside the same `sync_product` decision tree, so never-clobber, collision aliases
  (`keel-<name>`, resolved-state semantics), and tty/non-tty behavior are shared, not re-implemented.
  Mode specifics: a fresh home gets a thin generated wrapper (template minus the embedded core, import
  line in its place, map re-pointed at `keel/*`); an existing **foreign** `CLAUDE.md` gets the single
  import line appended (announced, reversible — closing the copy-path "rails NOT merged in" gap); a
  **copy-mode** home migrates losslessly (a byte-identical embedded block is swapped for the import
  line, identical command copies upgrade to symlinks, anything edited is left alone and flagged);
  re-runs are idempotent and self-heal dangling links. `bootstrap.sh` refuses `--link` (its temp clone
  is reaped on exit). Honest constraints shipped with the feature, not after: a pull refreshes
  *content, never composition* — so **`doctor.sh --install`** audits wired-vs-shipped completeness
  (dangling symlink/dead import = hard GAP; a missing command = advisory, declining is legitimate;
  "X of Y shipped commands wired"); docs state plainly that a pull changes the next session's rails
  without review (pull deliberately, or pin a tag), and that `@import`/symlinks are Claude Code/Unix
  mechanisms — the copy path stays the tool-independent default (ADAPTING.md, getting-started §1).
  Covered end-to-end by `tests/test_install_link.sh`.

### Security
- **`secret-scan` learns six more key shapes** (closes audit finding SEC2): GitHub OAuth/user/server/
  refresh tokens (`gho_`/`ghu_`/`ghs_`/`ghr_`, folded with the existing `ghp_` into one
  `gh[oprsu]_[A-Za-z0-9]{36}` pattern), npm access tokens (`npm_…`), and Hugging Face user tokens
  (`hf_…`). All length-anchored like the rest, so a bare prefix or this list itself never trips; one
  block test per shape. These are common CI/registry credentials the prefix backstop previously waved
  through.
- **Binary decode passes now cover UTF-32, closing a non-ASCII blind spot** in both `secret-guard`
  (`secret-scan.sh` `emit_blob`) and `public-audit` (`scan_binary_blobs`). The blob decoders ran
  `iconv` for UTF-16LE/BE but not UTF-32, so a **non-ASCII** personal literal (e.g. a Cyrillic name)
  encoded in UTF-32LE/BE passed both scanners: the dependency-free NUL-strip pass recovers an *ASCII*
  string from UTF-32 (3-of-4 bytes are NUL) but not a multi-byte code point, and the raw-printable
  pass sees only isolated bytes. Added `iconv -f UTF-32LE/BE` steps symmetric with the existing UTF-16
  ones (same `command -v iconv` guard; a host without iconv degrades honestly, as before). ASCII
  secrets/names in UTF-32 were already caught via NUL-strip — this specifically closes the
  non-ASCII-in-UTF-32 case, the same felt leak class as a real name inside a UTF-16 binary fixture.
  `--selftest` gains a non-ASCII UTF-32LE probe; regression tests in `test_secret_guard.sh`
  (`--range`) and `test_public_audit.sh` (binary WARN), both iconv-guarded. Found by the DeepSeek
  audit-loop (L3). Also documented in `secret-scan-personal.example`: keep personal EREs simple
  (avoid nested quantifiers that can backtrack on some BSD/busybox greps).

### Added
- **`CORE.md` — the always-on rails split out as a placeholder-free consumable file** (closes backlog
  dir #16). The always-on template used to be one file, so a linked consumer (an `@import` line in the
  adopter's own `CLAUDE.md` pointing into the checkout — the maintainer's setup) carried the
  `(TEMPLATE)` header, the "Copy this…" blockquote, and the `<your preference>` placeholder into every
  session (~100 tokens of noise), and editing around them meant editing inside the checkout — pull
  conflicts waiting to happen. Now the rails (precedence, git, secrets, reconcile-first, verify,
  forks, persist, memory — ~1,350 tok) live in root `CORE.md` next to `FRAMEWORK.md`/`PRINCIPLES.md`,
  and `templates/CLAUDE.md` becomes a thin wrapper: the file map + communication placeholders + the
  core embedded **verbatim** between `KEEL-CORE-BEGIN/END` markers. The copy path is untouched —
  `install.sh`, the by-hand copy, and ADAPTING's non-Claude recipe still take the single wrapper file.
  The embed is hand-maintained duplication, so `tests/test_core_wrapper_sync.sh` pins it: byte
  equality of the marked blocks, single-line markers appearing exactly once, and no template
  artifacts in `CORE.md`. Honest boundary in ADAPTING.md: `@import` is a Claude Code adapter
  mechanism; copying stays the tool-independent default. Groundwork for the linked-install mode
  (dir #17). Docs figures re-synced (wrapper ~1,810; `CORE.md` row added and guarded in
  `test_doc_figures.sh`).

### Changed
- **The core gains a precedence rule — nearest scope wins on a conflict** (`templates/CLAUDE.md`, after
  the map): live user instruction > session > project `CLAUDE.md` > the global core. Behavior on a
  contradiction between layers was previously undefined — the model guessed or asked. The rule also
  tells exceptions where to live (a project carve-out belongs in the project's file, not carried by the
  always-loaded core every session — an anti-bloat mechanism, felt: a single repo's
  direct-to-default-branch carve-out living globally). Two limits ride with it: safety rails (secrets,
  personal data, irreversible actions) yield only to an explicit human decision, never silently to a
  nearer file; and an applied override must be named — a contradiction may be staleness, not a
  deliberate exception.
- **Collision-aware command install** (closes backlog dir #9): when a command name is already taken by
  the adopter's *own* file (a pre-existing `/go` is likely — the name is generic), `install.sh` no
  longer poses overwrite-or-nothing, where both answers lose something (yes destroys their command,
  breaking the "never touches a file you own" promise in spirit; no silently drops Keel's).
  `sync_product` gains an optional alongside resolution for commands: keep theirs and install Keel's as
  `keel-<name>` — interactively `[u]pdate / [a]longside / [N]either` (default: leave untouched);
  non-interactively (curl|sh, CI) the alias is installed **automatically** — creating a brand-new
  `keel-<name>` touches nothing the user owns, and the bootstrap path would otherwise re-warn on every
  re-run with `cp` hints pointing into a temp clone it reaps on exit, never delivering the command. Once
  `keel-<name>` exists the collision is **resolved state**: the unprefixed name is the user's for good —
  re-runs never touch or re-create it (even if later deleted, or byte-identical to the shipped file) and
  the drift check routes to the alias, so the question is paid once, not on every
  `git pull && ./install.sh`. Commands already shipped as `keel-*` keep plain drift handling (no
  `keel-keel-*` noise), and a shipped `keel-<name>` is never repurposed as a collision alias for
  `<name>`. The naming rule this leans on is now codified in `ADAPTING.md`: unprefixed = lifecycle verbs
  that become yours; `keel-` prefix = commands about Keel itself, doubling as the collision fallback.
  Covered in `tests/test_install.sh`.
- **Two install-scenario gaps answered docs-level** (from a scenario audit: fresh vs pre-existing
  context, coding vs chat-only):
  - `ADAPTING.md`: an adopter who already has tuned rules on another tool (`.cursorrules`, `AGENTS.md`,
    a conventions file) is told to *keep their file* and lift only what they want from the template —
    usually the map plus missing rails — instead of replacing it; the `tools/` work regardless. Keel
    previously answered "run Keel on another tool" but not "coexist with the context already there".
  - `docs/getting-started.md`: a no-git / chat-style user gets the honest boundary stated plainly —
    the advice layer still applies, but the mechanized layer is git-based and won't fire without
    repositories: advice that nudges, not guarantees that run. (The matching `/keel-setup` trim is the
    droppable-rails entry below.)
- **The git/code rails become droppable-as-a-unit for non-coding adopters — trimmed at setup, not
  hedged in the core** (felt 2026-07-11: a real adopter who writes scripts and documents, no git,
  carries the two git/code sections — roughly a quarter of the always-loaded core — as pure dead weight every
  session). The fix costs zero core tokens: `/keel-setup` step 3 asks one plain-words scope question
  (*coding projects in git, or mostly documents and texts?*) and, on a clear "no code", offers to
  remove "Git — mandatory rails" and "Before writing code — reconcile first" from the user's copy;
  unsure/mixed keeps both (the safe default), and the "read the project's `CLAUDE.md` first" rail
  survives in the map either way. `ADAPTING.md`'s honest-boundary section documents the same trim for
  non-Claude tools. The secrets and personal-data rules that shared the git section's roof now live in
  their own **"Secrets & personal data"** section, which the trim never touches — a no-git adopter keeps
  those rails (they apply to knowledge-base files regardless of git; caught in review: the trim as first
  drafted would have silently dropped them, exactly what the same branch's precedence rule forbids).
  With the block droppable, it can also serve its primary audience better: the core's git rails gain the
  **force-push guard** (only a named branch, reconciled with upstream first — never `--force --all`),
  promoted from `FRAMEWORK.md`'s on-demand tier because a model won't open FRAMEWORK mid-push and the
  felt incident (a `--force --all` that rolled back main and dropped three merged PRs) is an
  irreversible loss class.
- **The core exports two felt rules that had never actually shipped** (`templates/CLAUDE.md`):
  - **No personal data in committed artifacts — anonymize at authoring time** (the "Secrets & personal
    data" section). The product
    ships the *mechanism* for this leak class (secret-guard's personal-literal scan, its README
    differentiator) but the primary *rule* — neutral stand-ins in code/commits/fixtures/examples, strip
    real-device data before the first commit — existed only in the author's private KB, explicitly
    marked "Keel-exportable" there and never exported. The felt leak: golden test fixtures generated
    from a real device shipped their owner's real name, caught only at a pre-OSS audit.
  - **"A blank beats a wrong guess"** (Verify discipline): don't assert an unchecked fact; flag a guess
    as a guess. Generalized into the every-session rails from `/keel-setup`'s guardrails, where it
    applied only at install time.

  Core grows to ~1,590 tokens at this entry; the branch's later additions (the force-push guard and
  the precedence rule) take the final core to ~1,760 — about 18% of the 10K startup budget — and the
  figures in `docs/loading-and-cost.md` and the README diagram track that final state, enforced by
  `test_doc_figures.sh`, which failed on each stale figure exactly as designed.
- **The core's Verify discipline gains the verification *method*, not just the honesty rule**
  (`templates/CLAUDE.md`): prefer a narrow, deterministic check (a test, a script assertion) over
  eyeballing — it can't hallucinate and costs zero context; a check you'd repeat by hand is a candidate
  to mechanize; and a fast negative result is a valid result, reported as plainly as a pass. The
  mechanized tier already *practices* this (secret-guard, doctor, the narrow test suite) — now the
  always-loaded rails *say* it, so the model is biased to build gates instead of trusting its own
  eyes. ~65 tokens added to the core at this entry (final size after the branch's later additions:
  ~1,760, about 18% of the startup budget).
- **Token-figure honesty extended to the README** (felt 2026-07-11: README's "How it loads" diagram
  still said `FRAMEWORK.md (~4.2K)` after the file had grown to ~5.0K — the loading-and-cost.md table
  is guarded by `test_doc_figures.sh`, but the README's separate mermaid figures weren't). Fixed the
  stale figure, added the missing `/keel-score` + `tools/keel-impact.sh` rows to "What's in the box",
  and mechanized the gap: `test_doc_figures.sh` now asserts the README's FRAMEWORK / PRINCIPLES /
  always-loaded-core figures within the same ±10% band.
- **Two honest-boundary notes for adopters** (both felt 2026-07-11):
  - `ADAPTING.md`: the Memory section of `templates/CLAUDE.md` assumes a persistent auto-memory keyed
    to the session/cwd (Claude Code's mechanism) — on a tool without one, drop that section when
    copying the file over.
  - `docs/getting-started.md`: a macOS tip for adopters without git — `xcode-select --install` gets
    git alone; no need for the longer Homebrew detour (felt: a non-coding adopter's install spent half
    the session on Homebrew-then-git).
- **The install path answers a first-time adopter's three stumbles** (felt 2026-07-11: the first
  completely fresh external user — macOS, Claude desktop app, clone install — walked through setup;
  the first live-user feedback since going public). Docs-and-echo only, no behavior change:
  - `install.sh` announces the secret-guard step in plain language *before* wiring it, so the AI
    tool's permission dialog for the global git-config change reads as expected instead of as a bug;
    `docs/getting-started.md` gains the matching "what you'll be asked" note.
  - `/keel-setup` no longer assumes a project exists: step 2 first asks whether the current directory
    is a project the user wants Keel on, and skips gracefully when there is none (the machine-wide
    steps still run) — a fresh user with zero projects previously got a half-run project setup. The
    machine-now / projects-later split is mirrored in the install "Next:" text and the docs.
  - The docs now say what to do with the keel clone after installing: keep it (the commands call its
    `tools/`), park it out of the way, don't register it as a project, `git pull && ./install.sh` to
    update. The underlying clone dependency is audit finding D1; its real fix is the unified CLI
    direction on the backlog.

### Fixed
- **Annotated-tag message bodies no longer bypass the outward secret boundary.** A tag object is
  neither a blob nor a commit, so `secret-scan --range` (the pre-push path) scanned neither its
  content passes nor its message pass over it — pushing `git tag -a v1.0 -m "<key / personal
  literal / Claude-Session trailer>"` shipped the tag message to the remote uncaught. The range
  scan now also extracts each introduced annotated tag's message body (the tag objects already
  appear in the same `rev-list --objects` stream) and matches it against all three detector sets —
  key shapes, personal literals, and session metadata — with the same batched fast-path/SIGPIPE
  discipline as the blob and commit-message passes. `public-audit`'s session-metadata check
  (section 4) had the matching blind spot while its history heuristics (section 5) already covered
  tag messages; it now scans annotated-tag `%(contents)` too, keeping the two mirrored `session_re`
  / `SESSION_META` checks consistent. `--selftest` gains a matching end-to-end tag probe, so an
  installed guard can prove the new pass works on its own host.

### Added
- **`secret-scan --range` (the pre-push path) now also scans the pushed commits' MESSAGES for
  agent/session metadata.** A commit message is not a blob, so every content pass — staged diff,
  range blobs, the binary decode — is structurally blind to it; felt (2026-07-10 self-audit):
  seven `Claude-Session` trailers auto-appended by an agent harness reached the public `main`
  through merged PRs, where a protected history makes them effectively unpurgeable, and
  `public-audit` could only report them as a post-hoc WARN. The pattern mirrors `public-audit`'s
  `session_re` (cross-referenced, kept in sync); the sanctioned noreply `Co-Authored-By` trailer
  does not trip it. Wired into the engine (not the hook), so an installed guard picks the check
  up on the next engine re-sync — expect `doctor`'s one-time drift WARN and re-run
  `install-secret-guard.sh --global` to clear it. `--selftest` verifies the new pass end-to-end;
  deliberate bypass unchanged (`--no-verify`). Note the same first-push semantics as the blob scan
  (deliberately no special-casing): a first push to a brand-new remote enumerates the whole
  reachable history, so pre-existing trailer history — including this repo's own — will block
  there and needs the deliberate `--no-verify`; incremental pushes to an established remote
  grandfather it naturally via the `remote..local` range.
- **`public-audit` decodes binary blobs; `doctor` catches installed-guard drift** (third batch of the
  KB-on-Keel migration — both close felt gaps from the maintainer's own audits):
  - **Binary-blob pass (`public-audit`).** The text passes cannot see inside a binary: the tree grep
    skips binaries and `git log -p` renders a binary change as "Binary files … differ" — so personal
    data encoded in a binary blob (the felt class: a real name UTF-16-encoded inside a fixture) passed
    every check. Now every binary blob reachable from any ref — plus a host PR ref's exclusive blobs —
    is decoded (NUL-strip + iconv UTF-16LE/BE + raw-printable) and re-scanned with the same regex set:
    declared tokens = GAP, home-path/email/Cyrillic = WARN. An added-then-removed blob is still caught
    (the scan walks blobs, not the final tree). `KEEL_AUDIT_BLOB_MAX` (default 10 MB) bounds the
    per-blob cost; oversized blobs are counted and surfaced as UN-audited, never silently trusted.
  - **Installed-guard drift check (`doctor`).** Presence is not freshness: a wired secret-guard copy
    that has drifted from the engine this checkout ships runs old detection while looking fine (felt:
    an engine upgrade reached some installed copies but not others — days of degraded detection).
    `doctor` now compares the machine-global copy (once) and each repo's wired local-override /
    hooks-dir copy (per project) against `tools/secret-guard/secret-scan.sh` and WARNs with the exact
    re-sync command on any mismatch. *(Expect a one-time WARN on machines with an already-installed
    guard after any engine-touching release — that's the check working; re-run
    `install-secret-guard.sh --global` to clear it.)*
- **`secret-scan` grows three verification/audit modes** (second batch of the KB-on-Keel migration —
  the modes the maintainer's KB tooling depends on, upstreamed so the private fork can collapse onto
  Keel's engine):
  - **`--selftest`** — end-to-end verification via child runs of the scanner from a neutral cwd (a
    repo's allowlist can't mask a probe): key-shape caught, no self-match on the pattern doc, inline
    allow honored, a personal literal caught in text and inside a UTF-16LE blob, and a malformed
    personal ERE fails *closed*. A guard you can't verify degrades silently.
  - **`--tracked`** — detective audit of ALL tracked content (text + binary decode pass) for
    `doctor`-style periodic reviews; **`--staged`** — the default pre-commit mode, spelled out.
  - `install-secret-guard.sh` now runs the **installed copy's** `--selftest` after wiring (a failing
    gate fails that script), and `install.sh`'s Verify step re-checks it functionally — so a
    wired-but-broken gate is failed or flagged instead of degrading silently. Host-dependent probes
    (no `iconv`, a lenient busybox grep) degrade to an honest WARN, not a false FAIL.
- **Three field-tested gotchas upstreamed from the maintainer's own knowledge base** (the first batch of
  the KB-on-Keel migration — the maintainer's KB now consumes Keel as its base, and generic lessons flow
  upstream instead of accumulating in a private fork):
  - **`FRAMEWORK.md` — "Service managers run with an empty environment":** a `set -u` script referencing
    a bare `$HOME` passes every manual test (even under `sudo`) and then dies on the first real
    timer/service fire, because systemd starts services with `$HOME`/`$USER` unset. Nounset-safe forms,
    the `Environment=` escape hatch, and *test via `systemctl start`, not by hand*.
  - **`FRAMEWORK.md` — worktree discipline hardened:** the shell cwd drifts silently after any `cd` /
    `git -C <other-checkout>` op, so a later `git checkout -b` lands in the wrong working tree — prevent
    it with an explicit `git -C <worktree-path>` per repo op; also sweep the per-worktree session-memory
    dir at teardown, and a predictable memory-file naming scheme in the upkeep section.
  - **`/wrap` — the red-flag sweep now names incident signals:** a `git push --force`, a
    `revert`/`reset --hard`, or a command that failed and was redone differently — mechanical traces of a
    lesson the sweep must surface.
- **`/context-dump` — onboard an existing, undocumented codebase.** `/keel-setup`'s project-`CLAUDE.md`
  draft only reads the README and manifest files, which isn't enough for a real legacy repo grown without
  docs. `/context-dump` reads the actual source tree instead — real stack/versions from the lockfile, the
  architecture pattern actually in use, existing reusable pieces (auth, a user repo, …) — and drafts into
  Keel's existing structure rather than new file types: `project-CLAUDE.md`'s Overview/Stack, plus a
  `legacy`-tagged backlog line for every outdated dependency or risky pattern it found, each cited to a
  file. Same draft-only contract as `/keel-setup`: never invents a fact, never clobbers, never commits.
  *Friction: the maintainer's own legacy projects still needed this onboarding done by hand — reviewing an
  external AI-dev workflow video surfaced the gap, but the friction it named was already real:
  `/init-project` only scaffolds, `/keel-setup` only skims.*
- **Impact score is now an auditable trail, with a `hold` signal and retrospective scoring.** Three
  refinements to the (still-unreleased) impact score:
  - **Auditable counts (per-event evidence).** The score is no longer built from bare counts. `keel-score`
    passes **one cited event per flag** (repeat `--fire "…"` / `--hit "…"` / `--miss "…"` / `--friction "…"`);
    the count is the number of citations, so *no citation → no count*, mechanically — the same "derived, not
    asserted" honesty the score already had, pushed down to the counts. Every citation (including each
    auto-ingested guardrail fire, cited by its `source | detail`) is archived to a durable, trackable
    `.keel/evidence.md` next to the ledger, so a score is a checkable record rather than a number to trust.
    The ledger's `evidence` cell is auto-filled with the single strongest citation. **Breaking** for the
    unreleased `add` interface: the `--guard N …` integer flags and `--evidence` are replaced by repeatable
    citation flags (`--silent N` stays a bare count).
  - **`hold` — keel's highest function, scored above guard.** A new event type for when keel *restrained the
    agent* from weakening or bypassing a rule/guardrail (vs `guard`, which blocks bad content). It weighs
    highest: `HELP = 4·hold + 3·guard + 2·fire + hit`. It gets its own ledger column and cumulative signal.
    **Schema change:** the ledger gains a `hold` column after `guard`.
  - **Retrospective scoring, quarantined.** `add --retro [--asof YYYY-MM-DD]` records a score reconstructed
    from a past session (e.g. a chat transcript) without contaminating the live signal: it never touches the
    live event log, its row is conf-tagged `-retro` and dropped one tier, and the live `rollup` excludes it
    (`rollup --retro` shows only these). Transcript→events extraction stays a manual, opt-in step.

  Covered by `tests/test_keel_impact.sh` (89 cases). A/B calibration remains documented-only (the sole true
  counterfactual is not zero-cost, so it is deliberately not automated).
- **Cross-project impact rollup + a doctor hygiene check.** `keel-impact.sh rollup --registry FILE` sweeps
  every project in an `INSTANCE.md` Projects table (the same parser as `doctor --registry`) and reports each
  one's mean score from its own `.keel/ledger.md`, plus a grand total and the cumulative guardrail-fire /
  retrieval-miss signals — the cross-project "usefulness of Keel" view. It lives in the impact tool, **not**
  in `doctor`: `doctor` stays a baseline audit and does not gain an impact-status line (that would be false
  drift for an optional feature). To make the sweep coherent, `keel-impact.sh` now resolves the ledger (and
  the event log) from the tracked repo's `.keel/` marker, so a project's sessions score into
  `.keel/ledger.md` with no env — the same out-of-the-box resolution the guardrails use. Only the ephemeral
  event log is gitignored; **`.keel/ledger.md` (the durable score history) stays trackable**, so a project
  can commit it and keep a shareable, cross-clone record. `doctor` gains one narrow, justified check: a WARN
  (not a GAP) when a `.keel/` marker exists but its event log (`.keel/impact-events.log`) isn't gitignored,
  so scratch can't leak into history — mirroring its existing unignored-private-context check, and targeting
  the log specifically so it never flags the committable ledger. It never nags a project to *enable*
  tracking. Covered by `tests/test_keel_impact.sh` and `tests/test_doctor.sh`.
- **Impact tracking works out of the box, per project, with no env.** Guardrail-fire recording is now gated
  on a repo-local `.keel/` marker (resolved from the git top level), so the loop needs no exported variable
  and works in any commit context (git hook, IDE, CI): the hooks write events into the tracked repo's
  `.keel/impact-events.log` and `keel-impact.sh add` reads them there. `keel-impact.sh enable [dir]` opts an
  existing repo in (creates the `.keel/` marker and gitignores only the event log); `init-project.sh` enables
  it by default for new projects (`--no-impact` to skip). `$KEEL_IMPACT_LOG` remains an explicit override. The
  test harness pins `KEEL_IMPACT_LOG` into its sandbox so a suite run never records into a maintainer's real
  `.keel/`; every
  guardrail test now covers all three enable paths (override / marker-only / neither → nothing written).
- **Keel impact score** — an optional way to quantify how much Keel shaped a session, built around one
  honesty rule: **the score is derived, not asserted.** `/keel-score` (`commands/keel-score.md`) does not
  pick a number — it enumerates *counted, cited events* (guardrail fires, rule fires, retrieval
  hits/misses, friction), each owing a concrete artifact from the session. `tools/keel-impact.sh` then
  computes the 0–100 score by a fixed formula — `HELP = 4·hold + 3·guard + 2·fire + hit`,
  `COST = 2·miss + 2·friction`, `score = round(100·HELP/(HELP+COST))` — so the marketing number is a pure function of the evidence and
  cannot be inflated by vibe. Guardrail fires (objective blocks) dominate; retrieval misses and friction pull
  it down; a session with no events derives `—` (nothing to measure), never a fake 0. Each row carries a
  `conf` tier from the event count (a score behind one event is visibly weak) and a `silent`-rules count
  (always-loaded rules that did not fire — demote candidates, recorded but deliberately *not* folded into the
  score). Rollup skips `—` rows from the mean and surfaces the honest cumulative signals (total guardrail
  fires, total retrieval misses = standing promote pressure). The command also documents the only real
  counterfactual — an occasional A/B (same task with Keel vs cold) — as the ground truth these self-reported
  scores estimate. Wired as an optional step 7 in `/wrap`; append-only ledger at `docs/keel-impact.md`.
  Portable by design (a Markdown command + a POSIX-ish Bash tool, not a Claude-only skill).
- **Impact events — the objective signal, collected in the shell at zero token cost.** The most objective
  input to the score (a guardrail actually firing) is now captured deterministically instead of counted by
  the model: all three guardrails — `secret-guard` (on a block), `pre-pr-gate` (on a deny), `public-audit`
  (on a GAP) — append a metadata-only event (never the matched secret) to a session-local log
  (`$KEEL_IMPACT_LOG`, default `.keel/impact-events.log`, gitignored), and `keel-impact.sh add` auto-ingests
  any logged events into the score, then truncates the log so nothing is double-counted (`--no-ingest` opts
  out). A new `keel-impact.sh event TYPE [source] [detail]` is the producer entry point for any shell tool.
  The instrumentation is opt-in (each hook writes only when `$KEEL_IMPACT_LOG` is set), so default hook
  behaviour is byte-identical, and it writes to the log file only — never stdout, so `pre-pr-gate`'s JSON
  decision stays intact. Covered by `tests/test_keel_impact.sh` (40), `tests/test_secret_guard.sh`,
  `tests/test_pre_pr_gate.sh`, and `tests/test_public_audit.sh` (each: metadata-only + no-leak +
  off-by-default; `public-audit` also asserts a clean run records nothing).
- README **demo GIF** (`docs/demo.gif`) — a ~40s real, sandboxed secret-guard run near the top of the
  README: hook install → an API key blocked on commit → the owner's name blocked inside a UTF-16 binary
  fixture. Nothing mocked: the frames are the hook's actual output. Recorded by the committed, reproducible
  `docs/demo/record-demo.sh` (asciinema + agg; HOME and the global git config are redirected into a temp
  sandbox, so recording touches nothing on the machine). Closes the "the README asks to be believed" gap —
  the demonstrable tool is now demonstrated (project backlog #6, T2).

## [0.4.0] — 2026-07-08

"Personal-data guard" release. `secret-guard` grows a second detector class — your own personal data
(name, emails, drive labels, serials), read from a local never-committed file and caught even inside
UTF-16 binary fixtures — plus a determinism fix for a rare `--range` miss under SIGPIPE. `install.sh`
re-runs now keep Keel's own core in sync instead of freezing it at first install. The README gains a
tools-first entry door ("Just want the git hook?") and answers the obvious objection up front. No
breaking changes; without a personal-literals file, secret-guard behaves exactly as before.

### Added
- `secret-guard` — a second detector class: **personal data**. Operator-specific literals (real name,
  device serials, personal drive labels, personal emails) are read as EREs from a **local, never-committed**
  file (`~/.claude/secret-scan-personal`, override `$SECRET_SCAN_PERSONAL_FILE`; starter:
  `tools/secret-guard/secret-scan-personal.example`) and matched case-insensitively. Both classes now also
  scan **binary content** — staged binary files, binary blobs in a pushed range, and binary FILE arguments
  are decoded (NUL-strip with no dependencies; iconv UTF-16LE/BE when available for non-ASCII literals;
  raw-printable) — a real name inside a UTF-16 binary fixture is invisible to a plain-text grep, which is
  exactly how such a leak shipped in practice. A malformed personal ERE **fails closed** (exit 2) instead
  of silently disabling detection. Absent file → key-only behavior, exactly as before.

### Fixed
- `secret-guard` — the `--range` fast path could **intermittently miss a real secret** (the macOS CI
  flake): `grep -q` exits on the first match, the still-writing `git cat-file --batch` takes SIGPIPE, and
  under `pipefail` the whole pipeline reads as failed — the hit was discarded and the push scanned clean,
  timing/buffer-dependent. The fast check now uses `grep -c`, which consumes the whole stream, making the
  result deterministic; a regression test plants a key early in a large pushed range.

### Changed
- `README.md` — repositioned for a reader who arrives cold: a **"Just want the git hook?"** section right
  after the Quickstart sells `secret-guard` + `public-audit` as standalone products (one-command install,
  the real leak story that motivated the personal-data class), and the TL;DR now answers the most likely
  objection head-on ("isn't this just a well-written CLAUDE.md?"). The "already have your own conventions"
  block now points at the new section instead of duplicating it. Rationale: the pitch sold the methodology
  first, but the tools are the demonstrable entry door (project backlog #6 — split the pitch, not the repo).
- `install.sh` — a re-run now **keeps Keel's own core in sync** instead of leaving every already-installed
  copy frozen at its first-install version. Files you own (`CLAUDE.md`, `INSTANCE.md`, `LEARNINGS.md`) are
  still never touched; Keel-owned files (`FRAMEWORK.md`, `PRINCIPLES.md`, `commands/*.md`) that have
  **drifted** from the shipped version are offered for update — an interactive `y/N` prompt (default *no*,
  so a copy is never lost without a yes) when run from a terminal, or a WARN with the exact `cp` to run when
  non-interactive (`curl|sh`, CI). The non-interactive path never blocks on input. Previously a `git pull`
  in the clone plus a re-run delivered no updates at all to the installed commands or core; now it does.
  `README.md` + `docs/getting-started.md` reworded from the old blanket "never overwrites a file you already
  have" to this accurate split (your files vs Keel's own).
- `commands/wrap.md` — the step-0 *"sync installed artifacts"* sub-step dropped a maintainer-specific detail
  (`commands/*.md` symlinked into `~/.claude/commands/`, a `git -C <main-checkout> pull`) that both leaked a
  personal-setup mechanism into the tool-independent product and was inaccurate for adopters (Keel *copies*
  commands, it doesn't symlink, and the bootstrap clone leaves no persistent checkout to pull). It now points
  at the tool-independent "re-run the install/sync step" — which the `install.sh` change above makes real.

## [0.3.1] — 2026-06-30

Audit-hardening & documentation release. A 4-report external audit drove a fix to a real under-reporting
bug in `doctor` / `public-audit` (a `pipefail` + SIGPIPE false-negative on large inputs), a batch of new
`doctor` checks, and internal-consistency + claim-accuracy fixes across the docs. No breaking changes.

### Changed
- `tools/doctor.sh` + `tools/public-audit.sh` — single-sourced the **public-safe email** set. doctor's
  commit-email nudge used a loose hand-rolled pattern (`noreply|@example\.|\.invalid`) that drifted from
  public-audit's canonical `SAFE_EMAILS`; the two could disagree on whether an address is safe (e.g. a
  deceptive `dev@noreply.corp.com` was waved through by doctor but not by the audit). doctor now mirrors
  the canonical anchored patterns, with a cross-reference comment in both files (public-audit is the source;
  doctor is its advisory mirror). A test locks it (a github-noreply draws no nudge; a `noreply`-substring
  corporate address now does).
- `FRAMEWORK.md` — removed two in-file duplications that violated its own single-source rule ("a fact lives
  in one place; everywhere else is a pointer"). The squash/rebase "merged" caveat and the dependency-
  versioning rule each appeared **twice** — a full bold paragraph under *Git/Code conventions* and a
  dedicated section lower down. Kept the dedicated sections (*Git branch lifecycle*, *Dependency
  versioning*) as canonical; the earlier mentions are now one-line gist + pointer, so the rule can't drift
  between two copies.
- `tests/test_doc_figures.sh` — a `~N,NNN+` token figure in `docs/loading-and-cost.md` is now read as an
  open-ended **floor** (assert the real size is *at least* it, no upper bound) instead of a ±10% band. The
  `CHANGELOG.md` row uses it: a monotonically-growing reference file no longer forces a figure bump on every
  PR that touches it, while the figure stays honest (it never overclaims the cost). Stable files keep the
  exact ±10% check.
- `commands/polish.md` + `tools/pre-pr-gate.sh` are now scoped as **maintainer dev-tooling** —
  `install.sh` no longer ships `/polish` to adopters. Its `pre-pr-gate` hook is never wired by the
  installer, so shipping the command handed adopters an inert feature; both now stay in the repo for the
  maintainer + downstream consumers, with the rationale documented in-tree (so it reads as scoped, not
  half-shipped). A test asserts `/polish` is not installed.
- `tools/pre-pr-gate.sh` — a missing `jq` is now handled explicitly (`command -v jq || exit 0`): the gate
  can't parse its event without it, so it allows rather than block every command — a documented choice for
  a workflow gate (not the secret boundary), no longer a silent fail-open.
- `FRAMEWORK.md` — three generic refinements: a fallback model "falls back, it doesn't route" note (a
  fallback is for provider unavailability, not task difficulty); a monorepo note (nested `CLAUDE.md` per
  subtree); and a "fork a plugin-shipped skill/command, don't edit it in place" durability gotcha
  (in-place edits are lost on the next plugin update and absent on a fresh machine).
- `tools/doctor.sh` — the secret-guard check no longer assumes a machine-global `core.hooksPath` covers a
  repo: it now detects a **local** `core.hooksPath` override that carries no guard hook, which silently
  bypasses the global secret-guard for that repo (git runs the local path instead). A real gotcha — a repo
  with its own hooks dir loses the global guard without warning. Advisory WARN, exit unchanged.
- `tools/doctor.sh` — **per-stack lint-gate checks** (FRAMEWORK "Code conventions"): flags a project whose
  stack is detected but its native linter config is absent — Java→Checkstyle (and no wildcard imports),
  Python→Ruff (`[tool.ruff]` / `ruff.toml`), Swift→SwiftLint — plus a Java wildcard-import check. Build-output
  and vendored-dependency trees are pruned, so a dependency's sources or configs never trip the gate.
  Advisory WARN; busybox/Alpine-safe (find-only, no `grep --include`).
- `tools/doctor.sh` — **worktree CLAUDE.md bridge check** (FRAMEWORK "Worktree discipline"): a private-fork
  project gitignores `CLAUDE.md`, so `git worktree add` checks it out without one and that worktree's session
  starts blind to the project context. doctor now WARNs when a live linked worktree is missing the bridge.
  Public-fork (committed `CLAUDE.md`) is exempt. Advisory WARN.
- `docs/getting-started.md` — itemized what `doctor` actually checks (private-context gitignore, `CLAUDE.md`
  presence + startup budget, secret-guard wiring incl. the local `core.hooksPath` bypass, dependency pinning,
  per-stack lint gates, the worktree bridge) and noted the `--registry` fleet sweep — the checks added this
  cycle weren't reflected in the walkthrough.
- README: new **"Already have your own conventions?"** door, alongside "Not using Claude Code?". Reframes
  adoption for readers who already run a tuned setup — take the **ideas** (`PRINCIPLES`/`FRAMEWORK`), the
  **standalone tools** (`secret-guard`/`public-audit`, plain Bash + git, no Keel core needed), or one
  command/template à la carte, rather than installing the whole thing. States the positioning in one line:
  *a method and a few tools you graft onto what you have — not a framework you adopt whole.*

### Fixed
- `PRINCIPLES.md` — three internal-consistency fixes. (1) **Term collision on "mechanism":** the word named
  both the disposable layer (glossary/P0) *and* the automated tier of the enforcement taxonomy, so
  "each tension is **mechanized**" (any enforcement that runs) read straight into "most tensions are **not
  mechanisms**" (automated only) two paragraphs later. The enforcement tier is renamed **"automated check"**,
  reserving "mechanism" for the single disposable-layer sense. (2) **P1 logic:** "useful **iff**
  correct + calibrated" overstated — a correct, calibrated tool can still be useless (irrelevant, slow,
  redundant); the gate is necessary, not sufficient → "useful **only if**". (3) A stale parenthetical called
  the recurring-rewrite falsifier "the only falsifier currently written down" while sitting in a list of
  three; corrected to "the original falsifier; the two above were added later".
- `tools/doctor.sh` + `tools/public-audit.sh` — a `set -o pipefail` + SIGPIPE false-negative made both
  audit tools **silently under-report on large inputs**. The pattern `producer | grep -q .` (and `… && gap`)
  gates on the pipeline's exit status: once `grep -q` matches and closes the pipe, the still-writing
  producer dies with SIGPIPE (141), `pipefail` propagates the 141, and the gate flips to false. So
  `doctor`'s per-stack lint check skipped a real stack on a big tree (no WARN), and `public-audit`'s
  PR-ref scan could pass a private-token leak clean when the token matched early in a large history.
  Both now capture the first match (`[ -n "$(producer | head -n1)" ]`) instead of gating on the pipeline
  status — SIGPIPE can no longer flip a real hit into a clean result. Added scale regressions to
  `tests/test_doctor.sh` and `tests/test_public_audit.sh` (each fails on the pre-fix code).
- `docs/going-public.md` — the scrub runbook ran `tools/public-audit.sh … .` from *inside* the throwaway
  `git clone <url> scrub` (cwd is the scrub clone), where `tools/` doesn't exist — the gate command failed
  for any non-Keel repo. Now referenced as `<keel>/tools/public-audit.sh` (run Keel's auditor against the
  scrub clone, not from it).
- `docs/getting-started.md` — the bootstrap "Express" note listed only `doctor` / `public-audit` as needing
  the clone, omitting `init-project` — so a `curl | sh` adopter was steered to `/keel-setup` (and
  `/init-project`) with no hint that the tool those commands drive isn't installed by bootstrap. The note now
  says so. (The deeper gap — installed commands referencing `tools/` by a repo-relative path — is a layout
  decision left to the maintainer; see the deferred list.)
- `README.md` — three claim-accuracy fixes. (1) The tour line said secret-guard blocks "a real key"; it
  plants the canonical AWS *example* key, so it's now "a key-shaped secret" — matching the careful
  "key-shaped" wording used everywhere else. (2) `public-audit`'s description implied it *catches* every
  personal leak; in fact a committer identity or a declared `--token` is a hard stop (GAP/exit 1), while
  names, emails and home paths in content are advisory WARNs (exit 0, a human decides). The README now
  draws that line instead of lumping "names, private tokens" together as if both block. (3) "catches" →
  "flags" in the standalone-tools blurb, for the same reason.
- `SECURITY.md` — the "Supported versions" line hardcoded `(currently `v0.2.0`)`, which silently went
  stale once `v0.3.0` shipped. Dropped the duplicated literal — the most recent tag is single-sourced in
  git, not restated in prose (FRAMEWORK "Knowledge & context upkeep"). Added `tests/test_security_doc.sh`
  to keep a `vN.N.N` literal from creeping back into `SECURITY.md`.

### Added
- `tests/test_pre_pr_gate.sh` — coverage for `tools/pre-pr-gate.sh`, which previously had none. Exercises
  the allow path (non-`gh pr create` commands, and a sentinel holding the live HEAD SHA) and every deny
  path: no sentinel, a bare-`touch` empty sentinel (the bypass attempt), a stale-SHA sentinel, and a
  non-git cwd. Asserts a rejected sentinel is removed and a passing one is consumed (one-shot). The gate
  parses its event with `jq`; the test skips cleanly where `jq` is absent (the busybox/Alpine CI job).
- `/polish` command (`commands/polish.md`) — the pre-PR polish pass: `git diff` scope → `/simplify` →
  `/code-review --fix` → run the project's tests → unlock the gate → `gh pr create`. Hands a human reviewer
  an already-tidied, bug-hunted diff. Runs between implementation and `/wrap`.
- `tools/pre-pr-gate.sh` — the enforcement half of the polish flow: a Claude Code `PreToolUse(Bash)` hook
  that blocks `gh pr create` until `/polish` has run cleanly on the current HEAD. The sentinel is
  content-checked against the live HEAD SHA, so a bare `touch` (empty file) or a sentinel from an earlier
  commit both fail — the bypass path is closed by content, not just presence.

## [0.3.0] — 2026-06-30

Onboarding & adoption release. The agent now finishes setup for you (`/keel-setup`), projects self-register
in your `INSTANCE.md`, the user docs are rewritten in plain language with a concrete non-Claude path, and a
publishing checklist captures the go-public process end to end.

### Added
- `/keel-setup` command (`commands/keel-setup.md`) — an agent procedure that finishes the install `install.sh` can't:
  auto-fills the `INSTANCE.md` **environment** from the machine (`uname`/`sysctl`/`$SHELL`), **drafts a
  project's `CLAUDE.md` from its actual code** (stack/build/test from real files; roadmap stubbed), and
  fills/merges the always-loaded rails. It drafts and the human reviews — never clobbers, never commits,
  never invents a fact. Turns the content steps from authoring into reviewing.
- `tools/register-project.sh <path>…` — adds project root(s) to the `INSTANCE.md` Projects registry, one
  table row each (name = dir basename, Path = absolute path), idempotent. Mechanizes the registry upkeep
  that was hand-editing a markdown table; `doctor --registry` reads exactly these rows.
- `init-project.sh` now **auto-registers** the project it scaffolds in `INSTANCE.md` (best-effort; skip
  with `--no-register`) — so a new project lands in the registry without a second step.
- `docs/publishing-checklist.md` — the "is it finished and presentable?" list (README/LICENSE/CHANGELOG/
  SECURITY, About metadata, CI + branch protection, release, social preview), each item marked **[auto]**
  (a `gh`/tool command answers it) or **[you]**, plus an explicit "decide, don't default" section for the
  community files Keel deliberately defers. The **presentation** companion to `going-public.md`'s **safety**
  flip; the two now cross-link. Captures a repeatedly hand-walked process so it goes fast next time.
- `ADAPTING.md` → **"Help map your tool"** — an explicit, low-ceremony call for users who run Keel on
  another AI tool to contribute their recipe (which file auto-loads, where the core went, how commands were
  wired, what was wrong) via a short PR/issue. The honest answer to a "model-agnostic" claim the author has
  only verified on Claude Code.

### Changed
- Onboarding clarity (novice-eyed pass): `install.sh`'s `Done. Next:` now leads with `/keel-setup` as the
  easiest path (matching the README's two-step promise) instead of opening with hand-editing — the manual
  route stays as an explicit fallback. README and getting-started now say to run `/keel-setup` inside
  **your own project, not the `keel` clone**, with the session **restart** (commands load only at session
  start) promoted from a fallback footnote into the step itself; the README Quickstart states the
  `bash` + `git` requirement up front.
- Plain-language pass over the user docs (README, `docs/getting-started.md`, `ADAPTING.md`): dropped the
  in-house jargon a newcomer can't parse — "harness", "rails", "tiering", "clobber", "depreciate",
  "mechanized vs needs-you", bare P-numbers — for everyday words ("your AI tool", "ground rules", "load a
  little always", "overwrite", "runs by itself vs up to you"). Meaning, structure, links, and the honest
  boundaries are unchanged; the reference core (`PRINCIPLES.md`, `FRAMEWORK.md`) is left precise on purpose.
- `ADAPTING.md` rewritten around a concrete **non-Claude quickstart** (3 steps + a where-do-instructions-live
  table for Cursor/Codex/Aider/Continue/plain-API) and now states up front that only Claude Code is
  author-tested. README gained a short "Not using Claude Code?" pointer.

## [0.2.0] — 2026-06-29

Hardening release: eleven external audit rounds drove findings from a real PR-ref secret leak down to
cosmetic/UX nits, all fixed. Notable: the push guard now scans the blobs a push introduces (not the net
diff), cross-platform CI (Alpine/busybox) guards portability, and every CLI has `--help`.

### Added
- One-line install: `curl -fsSL …/bootstrap.sh | sh` (`bootstrap.sh`) clones Keel to a temp dir, runs
  `install.sh`, and cleans up — collapsing clone+cd+install into a single command. POSIX `sh` (checks
  for `bash`/`git`); passes flags through (`… | sh -s -- --no-hooks`); pin with `KEEL_REF`.
- `install.sh` now wires the lifecycle commands too — it copies `commands/*.md` into `<home>/commands/`,
  so `/wrap`, `/go`, `/init-project`, … are slash commands on Claude Code with no manual copy step.
- `install.sh` detects a **pre-existing, non-Keel `CLAUDE.md`** and says so loudly (a `Verify` WARN +
  a `diff` to merge from), instead of silently leaving the always-loaded rails un-applied — the exact
  trap an existing Claude Code user hit. (Your file is still never clobbered.)
- `-h`/`--help` for **every** tool — `doctor.sh`, `init-project.sh`, `public-audit.sh`, and
  `install-secret-guard.sh` (matching `install.sh`). A newcomer's reflex `--help` previously hit raw
  `basename: illegal option` / `mkdir: illegal option` / `unknown option` / `not a git repo: --help`
  errors that looked like a crash; the tools now print usage and exit 0, and an unknown flag is a clean
  usage error (exit 2) instead of being treated as a path.
- CI now runs the test suite under **Alpine/busybox** (in addition to Ubuntu + macOS), guarding against
  GNU-only constructs on a non-GNU userland — the durable regression net for portability.

### Fixed
- `doctor.sh` floating-dependency check used `grep -r --include=…`, which **busybox grep doesn't support**
  (Alpine): the option errored, was swallowed, and the WARN silently never fired. Replaced with a portable
  `find … -exec grep` that works across GNU/BSD/busybox. (This is what the new Alpine CI leg would have
  caught.)
- `doctor.sh` no longer leaks `[: integer expected` when `KEEL_STARTUP_WARN_TOKENS` is non-numeric — it
  falls back to the default.
- `public-audit.sh` validates each `allow-email` regex from `.public-audit`: a broken ERE now yields a
  clear "invalid allow-email regex" WARN instead of repeated `grep: bad regex` spew + silently dropped
  content WARNs. (The identity GAP already failed closed; this restores the WARN layer + clarity.)
- `init-project.sh` now prints its resolved target ("scaffolding <path>") so the no-arg cwd default —
  which performs writes — is never silent.

### Docs
- `docs/getting-started.md` states the `bash` (3.2+) and `git` prerequisite — minimal images (Alpine,
  distroless) need `bash` first. Without it the hooks fail *closed* (a commit/push is blocked), but
  nothing runs; the dependency was previously unstated.
- `docs/getting-started.md` install block uses the real clone URL — the `<repo-url>` placeholder failed a
  verbatim copy-paste (`fatal: repository '<repo-url>' does not exist`).
- Replaced the internal-KB term "operator" with "you"/"the user" in published docs/templates
  (`FRAMEWORK.md`, `docs/going-public.md`, `commands/wrap.md`, `templates/CLAUDE.md`).
- `install.sh` no longer aborts with `HOME: unbound variable` under `set -u` when `$HOME` is unset but
  the target is given explicitly (`--home` / `KEEL_HOME`) and hooks are skipped. The `$HOME` default is
  resolved only as a fallback after arg parsing, and `keel_hooks` is resolved only when hooks are wired
  (a clear message, not a bare unbound error, if `$HOME` is missing while wiring). `install-secret-guard.sh
  --global` likewise gives a clear message instead of crashing. Core-file copies are now atomic
  (`cp` to a temp name + `mv`), so an interrupted install can't leave a half-written file under the final name.
- `secret-scan.sh` now blocks modern OpenAI `sk-proj-` / `sk-svcacct-` keys — the hyphen after `proj`
  broke the generic `sk-` rule, so the most-scraped current OpenAI shape evaded a scanner the README
  advertises as covering `sk-…`.
- `secret-scan.sh --range` no longer spawns a `git cat-file` per blob (O(blobs) — minutes on a large
  first push). It now fast-paths a clean push through a single batched `git cat-file --batch` + one grep,
  re-scanning per blob only when something matches. Same semantics (transient add-then-removed blobs
  still caught), regression tests unchanged.
- `secret-scan.sh FILE` on a missing path now exits 2 (was a false `clean`, exit 0), matching the
  exit-2-on-bad-target contract of `doctor` and `public-audit`.
- **secret-guard pre-push now scans the blobs a push introduces, not the net endpoint diff.** It used
  `git diff A..B`, which only sees the two endpoint trees — a secret added in one pushed commit and
  removed in a later one was absent from both, so the scan said "clean" while the blob still shipped to
  the remote (the most common remediation flow: commit a key, `git rm` it, push). `secret-scan --range`
  now enumerates `git rev-list --objects` for the range and scans each introduced blob; pre-push passes
  rev-list args so the first push (root commit included) needs no special-casing. (Regression test:
  add-then-remove within the range is now blocked.)
- `public-audit.sh` warns on a **shallow clone** — `git log --all` only sees the fetched depth there, so
  a clean result was silently untrustworthy. It now prints a visible WARN advising `git fetch --unshallow`.
- `public-audit.sh` reaps its `refs/keel-pr-audit/*` temp refs via an EXIT/INT/TERM trap, so a Ctrl-C
  mid-fetch — or a run against a repo with no GitHub remote — no longer orphans them.
- `doctor.sh --registry` skips table-shaped rows inside fenced code blocks, so a documentation example
  in an `INSTANCE.md` is no longer parsed as a real project.
- **secret-guard pre-push no longer waves through a new repo's first push.** On the first push the
  oldest unpushed commit is the *root* commit, so the old `${base}^..` range referenced a nonexistent
  parent, `git diff` errored silently, and the scan saw nothing — every commit in the most common push
  there is bypassed the hook. It now diffs from the empty tree when there's no parent, scanning the
  whole initial history. (Regression test added.)
- `public-audit.sh` now probes **every** remote, not just `git remote | head -1`. A non-GitHub mirror
  that sorted alphabetically ahead of the GitHub remote silently skipped the `refs/pull/*` scan; the
  tool now scans each remote that exposes PR refs and only notes "out of scope" if none do.
- `secret-scan.sh` tolerates a **CRLF-saved** `.secret-scan-allow` — a trailing CR used to become part
  of the ERE and break suppression, wrongly blocking a legit fixture. Also: dropped a misleading line
  number from diff-mode records (it numbered the added-lines stream, not the file), and `-I`-skips
  binary files in explicit-file mode (was emitting a malformed "Binary file … matches" record).
- `install.sh` no longer reports `OK secret-guard` when a **foreign** global `core.hooksPath` is set.
  It already refused to clobber a foreign hooksPath, but the verify step then printed OK for whatever
  `pre-commit` happened to live there — falsely claiming Keel's hook was wired. Verify now confirms the
  hooksPath is Keel's *and* the hook carries the Keel marker, else WARNs and points to per-repo vendoring.
- `doctor.sh`, `init-project.sh`, and `install-secret-guard.sh` detected a git repo via `[ -d .git ]`,
  which is false in a **git worktree or submodule** (there `.git` is a file) — `doctor` false-GAP'd a
  legitimate repo with "not a git repo". They now detect via `git rev-parse`, and `install-secret-guard`
  vendors into the real hooks dir (`git rev-parse --git-path hooks`), not an assumed `.git/hooks`.
- `docs/getting-started.md`: corrected a stale note — `doctor .` on the Keel repo **WARNs** (advisory,
  exit 0), it does not GAP, since the project `CLAUDE.md` is gitignored.

### Added
- `/go` command (`commands/go.md`) — start a backlog task autonomously with minimal context — and
  four promoted `FRAMEWORK.md` sections, both lifted from the private knowledge base.

### Fixed
- Corrected the `FRAMEWORK.md` token figure in `docs/loading-and-cost.md` and the README "how it
  loads" diagram (`~3,300`/`~3.4K` → `~4,200`/`~4.2K`); the file had grown past its quoted size by
  the doc's own ~4-chars/token ruler. Added `tests/test_doc_figures.sh` to fail if a quoted figure
  drifts more than 10% from the real file, so this class of drift can't slip through again.
- Made the token-figure guard exhaustive. `tests/test_doc_figures.sh` now checks **every** quoted
  per-file figure in `docs/loading-and-cost.md` (it previously covered only `FRAMEWORK.md` and
  `PRINCIPLES.md`, so drift in any other row shipped unguarded), and the combined
  `ADAPTING.md / CHANGELOG.md` row was split into one row per file so each figure is unambiguously
  checkable. Corrected the stale `CHANGELOG.md` figure surfaced by the wider check.
- `public-audit.sh` now applies its full heuristic set — home paths, Cyrillic, and agent/session
  metadata — to host PR-ref content, matching what it already runs over local history; previously the
  PR-ref scan ran only identity/token/email, so a home path or session trailer living only in a closed
  PR would have passed clean. Covered by a new `tests/test_public_audit.sh` case.
- The CI shellcheck gate now lints every tracked file with a shell shebang, not just `*.sh` plus two
  hardcoded hook paths, so a new extensionless script can't escape it.
- Widened the `commands/*.md` size range in `docs/loading-and-cost.md` to bracket the real min/max
  and added a `test_doc_figures.sh` guard for it; removed redundant duplicate `.gitignore` entries.
- `public-audit.sh` now also scans GitHub's synthetic merge refs (`refs/pull/*/merge`), not just the
  PR tips (`refs/pull/*/head`), so a leak reachable only from a merge ref is caught too; a new
  `tests/test_public_audit.sh` case covers it.
- README: noted that `secret-guard` is a prefix-based backstop for known key shapes, not full DLP, so
  readers don't over-trust it for arbitrary secrets (an AWS secret key, a JWT, a password).

## [0.1.0] — 2026-06-27

First release: the durable foundation plus a one-command, self-verifying, demonstrable mechanized
layer. Built and tested on Claude Code; the principles, framework, and tools are harness-independent
(see `ADAPTING.md`).

### Foundation (durable)
- `PRINCIPLES.md` — P0–P4, calibrated to a *rate* (not an absolute), with falsifiers and a founding
  worked example.
- `FRAMEWORK.md` — the reusable methodology engine: tiering, registry-as-index, startup-footprint
  discipline, git/code conventions.
- `README.md` with the honest "mechanized vs needs-you" boundary; `ADAPTING.md` for porting to
  another model or harness; `LICENSE` (MIT).

### Templates
- `templates/CLAUDE.md`, `templates/INSTANCE.md`, `templates/project-CLAUDE.md`,
  `templates/LEARNINGS.md` — the thin always-loaded core, the private personal layer, per-project
  context, and the workflow-insight staging tier.

### Tools (plain Bash + git, harness-agnostic)
- `tools/secret-guard/` — a git-hook scanner that blocks key-shaped secrets on commit/push, with a
  path and inline allowlist; install globally (`install-secret-guard.sh --global`) or vendor per repo.
- `tools/doctor.sh` — structural baseline self-audit (a GAP fails, a WARN is advisory); `--registry`
  sweeps the projects listed in an `INSTANCE.md` table.
- `tools/init-project.sh` — idempotent project scaffold.

### Bootstrap & CI
- `install.sh` — one-command bootstrap: copies the durable core into the harness home, wires
  secret-guard globally, seeds a private `INSTANCE.md`, and verifies. Idempotent; never clobbers an
  existing file or a foreign global hooksPath.
- `tests/` + `.github/workflows/ci.yml` — a zero-dependency bash self-test suite (secret-guard,
  doctor, init-project, install) on Linux and macOS, plus a `shellcheck` gate. The methodology
  project verifies itself.

### Demo
- `examples/` — a runnable, sandboxed 5-minute tour: `init-project` → `doctor` → `secret-guard`
  blocking a key, end to end.

### Commands (prompt procedures)
- `commands/init-project.md`, `commands/wrap.md`, `commands/global-review.md`, `commands/backlog.md`.
