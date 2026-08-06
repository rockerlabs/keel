# Changelog

All notable changes to Keel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). It is an experimental
probe, so pre-1.0 minor releases may still carry breaking changes.

## [Unreleased]

### Added
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

### Fixed
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
