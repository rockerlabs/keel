# Changelog

All notable changes to Keel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). It is an experimental
probe, so pre-1.0 minor releases may still carry breaking changes.

## [Unreleased]

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
