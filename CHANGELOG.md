# Changelog

All notable changes to Keel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). It is an experimental
probe, so pre-1.0 minor releases may still carry breaking changes.

## [Unreleased]

### Changed
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
