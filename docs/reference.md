# Reference: what's in the box

Every file, tool, and command — grouped, one line each. Legend: ⚙️ runs by itself (no context cost) ·
📖 advice, applies when read · 📝 template you fill in once.

## Core files

| | File | What it is |
|---|---|---|
| 📖 | [`PRINCIPLES.md`](../PRINCIPLES.md) | The lasting foundation. Read it for big, hard-to-undo decisions. |
| 📖 | [`FRAMEWORK.md`](../FRAMEWORK.md) | The reusable how-to: load-a-little-always, project list, git and code conventions. |
| 📖 | [`CORE.md`](../CORE.md) | The always-on rails alone — placeholder-free. On Claude Code, import it live (`git pull` refreshes it); elsewhere the template embeds it verbatim. |

## Templates

| | File | What it is |
|---|---|---|
| 📝 | [`templates/CLAUDE.md`](../templates/CLAUDE.md) | The small always-on file: `CORE.md` + your personal sections (file map, preferences). |
| 📝 | [`templates/INSTANCE.md`](../templates/INSTANCE.md) | Your private layer: hardware, available models, project list. |
| 📝 | [`templates/project-CLAUDE.md`](../templates/project-CLAUDE.md) | Per-project notes. |
| 📝 | [`templates/LEARNINGS.md`](../templates/LEARNINGS.md) | Holding place for tips not yet worth a full rule. |

## Tools

| | Tool | What it does |
|---|---|---|
| ⚙️ | [`install.sh`](../install.sh) | One-command setup: copies (or, with `--link`, symlinks) the always-on files and turns on secret-guard. Safe to re-run; never touches your own files. |
| ⚙️ | [`tools/secret-guard/`](../tools/secret-guard/) | Git hook: blocks key-shaped secrets (`ghp_`, `AKIA…`, `sk-…`, `glpat-`, …) on commit/push — and, opt-in, your listed personal data, even inside UTF-16 binaries. Also blocks agent session-metadata trailers on push and scans annotated-tag messages. |
| ⚙️ | [`tools/public-audit.sh`](../tools/public-audit.sh) | Pre-go-public scan of files **and git history**: committer identities and declared tokens are a hard stop; names/emails/home paths are flagged for review. |
| ⚙️ | [`tools/doctor.sh`](../tools/doctor.sh) | Checks a setup for missing pieces (`--install` audits the linked install). |
| ⚙️ | [`tools/init-project.sh`](../tools/init-project.sh) | Scaffolds a new project and registers it in `INSTANCE.md`. |
| ⚙️ | [`tools/register-project.sh`](../tools/register-project.sh) | Adds existing project folder(s) to the `INSTANCE.md` list; safe to re-run. |
| ⚙️ | [`tools/keel-impact.sh`](../tools/keel-impact.sh) | Optional per-project tracker behind `/keel-score`: an auditable ledger of cited events. Off by default. |

*secret-guard is a safety net for known key shapes plus your listed literals — not a catch-all. It won't
catch an arbitrary AWS secret key, a JWT, or a password.*

## Commands (`commands/`)

| Command | What it does |
|---|---|
| `/keel-setup` | Lets the assistant finish setup: fills machine details, drafts a project's `CLAUDE.md` from its code. |
| `/init-project` | Sets up a new project. |
| `/context-dump` | Onboards an existing, undocumented codebase by actually reading it. |
| `/go` | Starts a backlog task on its own. |
| `/wrap` | Closes out a session: notes, changelog, backlog. |
| `/global-review` | Reviews across all projects. |
| `/backlog` | Shows the backlog. |
| `/keel-score` | Scores how much Keel shaped a session — derived from cited events, not asserted. |

## Docs & extras

| | What it is |
|---|---|
| [`examples/`](../examples/) | A runnable, safe 5-minute tour: `init-project` → `doctor` → secret-guard blocking a key. |
| [`docs/loading-and-cost.md`](loading-and-cost.md) | What loads when and the per-session token cost, with a with/without comparison. |
| [`docs/getting-started.md`](getting-started.md) | The longer setup walk-through. |
| [`docs/going-public.md`](going-public.md) | Making a private repo public, step by step. |

## Not on Claude Code?

`./install.sh --home DIR` targets another AI tool's config folder; `--no-hooks` skips the git check. By
hand: copy `templates/CLAUDE.md`, `templates/INSTANCE.md`, `FRAMEWORK.md`, and `PRINCIPLES.md` into your
tool's config folder, then run `tools/install-secret-guard.sh --global`. See [`ADAPTING.md`](../ADAPTING.md).
