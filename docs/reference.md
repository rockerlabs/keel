# Reference: what's in the box

Every file, tool, and command — grouped, one line each.

## 📖 Core files — advice, applies when read

| File | What it is |
|---|---|
| [`PRINCIPLES.md`](../PRINCIPLES.md) | The lasting foundation. Read it for big, hard-to-undo decisions. |
| [`FRAMEWORK.md`](../FRAMEWORK.md) | The reusable how-to: load-a-little-always, project list, git and code conventions. |
| [`CORE.md`](../CORE.md) | The always-on rails alone — placeholder-free. On Claude Code, import it live (`git pull` refreshes it); elsewhere the template embeds it verbatim. |

## 📝 Templates — you fill them in once

| File | What it is |
|---|---|
| [`templates/CLAUDE.md`](../templates/CLAUDE.md) | The small always-on file: `CORE.md` + your personal sections (file map, preferences). |
| [`templates/INSTANCE.md`](../templates/INSTANCE.md) | Your private layer: hardware, available models, project list. |
| [`templates/project-CLAUDE.md`](../templates/project-CLAUDE.md) | Per-project notes. |
| [`templates/LEARNINGS.md`](../templates/LEARNINGS.md) | Holding place for tips not yet worth a full rule. |
| [`templates/IDEAS.md`](../templates/IDEAS.md) | Free-form scratchpad for raw ideas — the lowest-commitment staging tier, one step before `LEARNINGS.md`. |

## ⚙️ Tools — run by themselves, zero context cost

| Tool | What it does |
|---|---|
| [`keel`](../keel) | One CLI over the rest, installed to `~/.claude/bin` (the install summary prints a one-line PATH hint if that dir isn't on your PATH): `keel install \| sync \| doctor \| audit \| init \| check \| uninstall \| version \| help`. A thin dispatcher, so it works from any directory. |
| [`bootstrap.sh`](../bootstrap.sh) | The `curl … \| sh` entry point: fetches the repo (git clone, or a tarball on a git-less machine) and runs `install.sh`. |
| [`install.sh`](../install.sh) | One-command setup: copies (or, with `--link`, symlinks) the always-on files and turns on secret-guard. Safe to re-run; never overwrites your own files. On a machine with no git projects, `--link --no-git` trims the code/git rails from the always-on core (sticky across re-runs; `--with-git` restores). |
| [`uninstall.sh`](../uninstall.sh) | Reverses `install.sh` (`keel uninstall`): removes only Keel-owned content, backs up what it removes, leaves your own files and the machine-global secret-guard alone. Mirrors install's mode flags — `--home DIR`, and `--codex` for an `install.sh --codex` install (`~/.codex`, `AGENTS.md`); a plain run names a Codex install it finds rather than leaving it behind. |
| [`tools/secret-guard/`](../tools/secret-guard/) | Git hook: blocks key-shaped secrets (`ghp_`, `AKIA…`, `sk-…`, `glpat-`, …) on commit/push — and, opt-in, your listed personal data, even inside UTF-16 binaries. Also blocks agent session-metadata trailers on push and scans annotated-tag messages. |
| [`tools/public-audit.sh`](../tools/public-audit.sh) | Pre-go-public scan of files **and git history**: commit/tag identities and declared tokens are a hard stop; emails/home paths/Cyrillic and agent-session metadata are flagged for review (a bare personal name has no built-in pattern — to catch one, pass `--token` or put a `token:` in a **gitignored** `.public-audit`, never a committed one). |
| [`tools/doctor.sh`](../tools/doctor.sh) | Checks a setup for missing pieces (`--install` audits the linked install). |
| [`tools/init-project.sh`](../tools/init-project.sh) | Scaffolds a new project and registers it in `INSTANCE.md`. |
| [`tools/register-project.sh`](../tools/register-project.sh) | Adds existing project folder(s) to the `INSTANCE.md` list; safe to re-run. |
| [`tools/keel-impact.sh`](../tools/keel-impact.sh) | Optional per-project tracker behind `/keel-score`: an auditable ledger of cited events. Projects scaffolded by `init-project` are tracked by default (`--no-impact` opts out); an existing repo is off until `keel-impact.sh enable <dir>`. |
| [`tools/install-secret-guard.sh`](../tools/install-secret-guard.sh) | Wires the secret-guard hooks: `--global` sets a machine-wide `core.hooksPath`; `<repo-path>` vendors a self-contained copy into one repo. Never clobbers a non-Keel hook without `--force` (which backs it up). |
| [`tools/keel-check.sh`](../tools/keel-check.sh) | The stop-mode floor: run a task's verification command through it and repeated failure of the same check prints a STOP-and-diagnose banner instead of letting an agent spiral. `tools/keel-check-gate.sh` is the opt-in hard-veto half — register it as a Claude Code `PreToolUse` hook (plus `KEEL_CHECK_VETO=1`) to *block* a commit while your declared check is still red, instead of only nudging. |
| [`tools/branch-cleanup.sh`](../tools/branch-cleanup.sh) | Classifies local branches after merges into AUTO/ASK/FLAG confidence tiers so post-merge cleanup never blanket-deletes live work. |
| [`tools/pre-pr-gate.sh`](../tools/pre-pr-gate.sh) | The `/polish` pre-PR gate: a Claude Code hook that blocks the agent's own `gh pr create` until `/polish` (simplify + tests + a depth-matched review) has run cleanly on the current commit. Ships with `commands/polish.md`, but is never auto-wired — see `install-pre-pr-gate.sh` below. |
| [`tools/install-pre-pr-gate.sh`](../tools/install-pre-pr-gate.sh) | Wires the `/polish` gate's 6 hooks into a project's `.claude/settings.json` (project scope, the default) or `--global` (every repo; `--home DIR` targets the same home an `install.sh --home DIR` install used). Opt-in and separate from `install.sh` on purpose: a hook changes what a session can do without asking each time. Same never-clobber discipline as `install-secret-guard.sh`. |
| [`tools/pipeline-canary.sh`](../tools/pipeline-canary.sh) | A sandboxed operator ritual for auditing your own `/polish` → gate pipeline: drives a real dry run (or a scripted, no-model `demo-bypass`) in an isolated toy repo + `HOME`, so you can check the gate still denies a fabricated review claim. |

*secret-guard is a safety net for known key shapes plus your listed literals — not a catch-all. It won't
catch an arbitrary AWS secret key, a JWT, or a password.*

*Maintainer-only, not shipped by `install.sh`: `tools/self/` (this repo's own structural self-checks —
dead references, ship-skip-list sync, doc staleness).*

## Commands (`commands/`)

| Command | What it does |
|---|---|
| `/keel-setup` | Lets the assistant finish setup: fills machine details, drafts a project's `CLAUDE.md` from its code. |
| `/init-project` | Sets up a new project. |
| `/context-dump` | Onboards an existing, undocumented codebase by actually reading it. |
| `/go` | Starts a backlog task on its own. |
| `/polish` | Pre-PR pass — simplify, tests, a depth-matched review, then open the PR. Gated by `tools/pre-pr-gate.sh` once you've run `install-pre-pr-gate.sh` for the repo (optional; every step still runs without it). |
| `/wrap` | Closes out a session: notes, changelog, backlog. |
| `/global-review` | Reviews across all projects. |
| `/backlog` | Shows the backlog. |
| `/keel-score` | Scores how much Keel shaped a session — derived from cited events, not asserted. |

## Extras

[`examples/`](../examples/) is a runnable, safe 5-minute tour: `init-project` → `doctor` → secret-guard
blocking a key. The docs themselves are indexed in the [README's Docs section](../README.md#docs).

Setting Keel up for a tool other than Claude Code (installer flags, the by-hand copy) →
[`docs/getting-started.md`](getting-started.md) and [`ADAPTING.md`](../ADAPTING.md).
