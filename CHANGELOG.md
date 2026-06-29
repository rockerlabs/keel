# Changelog

All notable changes to Keel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). It is an experimental
probe, so pre-1.0 minor releases may still carry breaking changes.

## [Unreleased]

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

### Changed
- Onboarding clarity (novice-eyed pass): `install.sh`'s `Done. Next:` now leads with `/keel-setup` as the
  easiest path (matching the README's two-step promise) instead of opening with hand-editing — the manual
  route stays as an explicit fallback. README and getting-started now say to run `/keel-setup` inside
  **your own project, not the `keel` clone**, with the session **restart** (commands load only at session
  start) promoted from a fallback footnote into the step itself; the README Quickstart states the
  `bash` + `git` requirement up front.

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
