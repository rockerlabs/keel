# Keel

[![CI](https://github.com/rockerlabs/keel/actions/workflows/ci.yml/badge.svg)](https://github.com/rockerlabs/keel/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **In plain words:** a short "how I work" file your AI coding assistant reads at the start of every
> session — so it stops re-learning your project, your conventions, and the decisions you already made —
> plus a few small Bash tools that block secrets and check your setup. Works with any AI tool, not just
> Claude. About 10 minutes to set up.
>
> **"Isn't this just a well-written CLAUDE.md?"** Mostly, yes — and that's the point: one that's already
> written, installed in one command, tested on CI across three platforms, plus the guard rails a text
> file can't give you — a git hook that blocks secrets and personal data, and an audit for taking a
> repo public.

**AI assistants start every session from zero.** Each new chat re-figures-out your project, your habits,
and choices you already settled — and if you paste in everything to make up for it, the assistant drowns in
detail and grabs the wrong fact. Keel is the middle path: a small, tool-independent layer that decides
**what your assistant loads, when, and how much** — so the knowledge and judgment you build up don't get
thrown away every time the tools change.

![Real sandboxed run: secret-guard blocks an API key on commit, then the owner's own name hidden inside a UTF-16 binary fixture](docs/demo.gif)

*~40 seconds, nothing mocked: install the hook → an API key is blocked on commit → your own name is
blocked even inside a UTF-16 binary fixture. Reproduce it yourself:
[`docs/demo/record-demo.sh`](docs/demo/record-demo.sh) (sandboxed, touches nothing).*

## Quickstart

**1. Install.** Copies the small always-on file into `~/.claude`, turns on the **secret-guard** check
(stops key-shaped secrets — and, opt-in, your own personal data — from being committed or pushed),
and adds the `/wrap` `/go` `/init-project`
commands — **without ever touching a file you own.** (A re-run offers to update Keel's *own* core files if
they've drifted, asking first — see [getting-started](docs/getting-started.md#1-install). Needs `bash` +
`git` — nothing else.)

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel && ./install.sh
```

**2. Run `/keel-setup` and let the assistant finish the setup — no editing by hand.** Restart Claude Code
(new commands only show up when a session starts) and run `/keel-setup` — from anywhere, even with **no
projects yet**: it fills in your machine details and sets up the ground rules. Then run it again inside
each project you want Keel on (**not** the `keel` folder you just cloned): that part **writes a first
draft of the project's `CLAUDE.md` from its own code** — you *check* the draft, you don't write it.

```
/keel-setup
```

Two steps. After step 1, secret-guard already protects your commits; `/keel-setup` does the rest, and you
just review what it drafts. (Still don't see `/keel-setup`? You're in an old session — start a fresh one.)

*Want to see it work before installing?* `./examples/tour.sh` runs a safe demo in a throwaway sandbox
(touches nothing on your machine): it sets up a sample project and watches secret-guard block a key-shaped secret.

That's the whole loop. Longer walk-through, other AI tools, and the honest "what runs by itself vs what's up
to you" → [docs/getting-started.md](docs/getting-started.md).

## Just want the git hook?

The two safety tools work standalone — plain Bash + git, no Keel core, no config files, and they never
enter your assistant's context:

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel
tools/install-secret-guard.sh --global   # every repo on this machine, from now on
```

- **secret-guard** blocks key-shaped secrets (`ghp_`, `AKIA…`, `sk-…`, `glpat-`, …) on every commit and
  push — and, opt-in, **your own personal data** (real name, emails, drive labels, serials) listed in a
  local never-committed file, caught even inside UTF-16 binary fixtures. It exists because exactly such a
  leak shipped in practice: test fixtures generated from a real device carried their owner's name, and a
  plain-text scan couldn't see it.
- **public-audit** (`tools/public-audit.sh <repo>`) scans a repo's files **and its git history** for
  personal and secret leaks before you flip it public — committer identities, tokens, names, home paths.

Everything below is optional on top of that.

> **Not using Claude Code?** Keel doesn't depend on it. The ideas, the `tools/`, and the always-on file
> work with any AI coding tool (Cursor, Aider, Codex, a plain API agent, …). The one Claude-Code-specific
> bit is the slash commands. See [`ADAPTING.md`](ADAPTING.md) for a short non-Claude setup — and, if you
> get it running on another tool, a quick way to share how.

> **Already have your own conventions?** Keel isn't all-or-nothing, and it won't fight your setup —
> `install.sh` never touches a file you own. But you probably don't want the whole thing on top of a
> system you've already tuned. Take only what's useful:
>
> - **The ideas.** Read [`PRINCIPLES.md`](PRINCIPLES.md) and [`FRAMEWORK.md`](FRAMEWORK.md) and lift what
>   fits into your *own* `CLAUDE.md`. Load-a-little-always, durable-vs-disposable, build-from-friction port
>   to any setup — you don't need Keel's files to use them.
> - **The standalone tools.** `secret-guard` and `public-audit` run next to whatever you already use —
>   no Keel "core" required; see [Just want the git hook?](#just-want-the-git-hook) above.
> - **One piece at a time.** Grab a single `commands/*.md` or a template and ignore the rest.
>
> Keel is a method and a few tools you graft onto what you have — not a framework you adopt whole.

> **Status: early experiment.** This is an early, cleaned-up copy of one person's working setup. It's
> public to find out whether it helps anyone besides its author — not as a finished product. Feedback
> welcome; expect rough edges.

## The idea

Keel rests on three plain ideas:

1. **Load a little always, the rest on demand.** A small, stable core loads every session; everything else
   is pulled in only when a task actually needs it. That's what lets it work even when the assistant's
   working memory is small.
2. **Some things last, some don't.** Tools go out of date in a year; your judgment and project decisions
   don't. Put your effort into the lasting part, and keep the machinery thin and easy to swap out.
3. **Add a rule only when something hurts.** Every rule has to fix a real problem you actually ran into —
   not just be there to look complete. That's what keeps it from turning into red tape.

The foundation is in [`PRINCIPLES.md`](PRINCIPLES.md); the reusable how-to is in
[`FRAMEWORK.md`](FRAMEWORK.md). For exactly what loads when — and what it costs in tokens, with a
with/without comparison — see [`docs/loading-and-cost.md`](docs/loading-and-cost.md).

### How it loads, at a glance

```mermaid
flowchart TD
    subgraph always["Always loaded — every session (~1.4K tokens)"]
        core["CLAUDE.md — thin core:<br/>ground rules + a map of where the rest lives"]
        proj["project CLAUDE.md<br/>(when you are in a project)"]
    end
    subgraph demand["On demand — pulled only when a task needs it"]
        fw["FRAMEWORK.md (~4.2K)"]
        prin["PRINCIPLES.md (~5.1K)"]
        inst["INSTANCE.md"]
        cmd["commands/* (when invoked)"]
    end
    subgraph never["Never in context — runs in the shell (0 tokens)"]
        tools["secret-guard, doctor,<br/>public-audit, init-project"]
    end
    core -->|the map points here| fw
    core --> prin
    core --> inst
    core -.->|when invoked| cmd
    tools -.->|only their output reaches context| core
```

The always-on part stays tiny; the bigger files (`PRINCIPLES`, `FRAMEWORK`) wait behind a door and load only
when needed; the tools never enter the assistant's memory at all. That's the whole point.

## What's in the box

| | |
|---|---|
| `PRINCIPLES.md` | The lasting foundation — the handful of ideas everything else rests on. Read it for big, hard-to-undo decisions. |
| `FRAMEWORK.md` | The reusable how-to: load-a-little-always, the project list, keeping the always-on part small, plus git and code conventions. No personal data. |
| `templates/CLAUDE.md` | The small always-on file — copy it into your AI tool's config folder (e.g. `~/.claude/`) and edit it. |
| `templates/INSTANCE.md` | Your private personal layer (hardware, which models you can use, your list of projects). |
| `templates/project-CLAUDE.md` | A template for per-project notes. |
| `templates/LEARNINGS.md` | A holding place for workflow tips that aren't yet worth a full rule (between "make it a rule" and "drop it"). |
| `install.sh` | One-command setup: copies the always-on files into your config folder and turns on the secret-guard check. Safe to re-run — never touches your own files; offers to update Keel's own core if it's drifted, asking first. |
| `tools/doctor.sh` | Checks a project's setup for missing pieces. |
| `tools/public-audit.sh` | Before you make a private repo public, scans the files **and the git history** for things that shouldn't leak. A committer identity or a declared private token is a hard stop; names, emails and home paths in file content are flagged for you to review. |
| `tools/secret-guard/` | A git check that blocks key-shaped secrets when you commit or push — and, opt-in, your personal data (name, drive labels, emails, serials) listed in a local never-committed file, caught even inside UTF-16 binary fixtures. It's a safety net for known key shapes (`ghp_`, `AKIA…`, `sk-…`, `glpat-`, …) plus your listed literals, not a catch-all — it won't catch arbitrary secrets like an AWS *secret* key, a JWT, or a password. On push it also blocks agent session-metadata trailers (a `Claude-Session`-style line) in the pushed commits' messages, and scans annotated-tag messages against all of the above. |
| `tools/init-project.sh` | Sets up a new project with the basics in place, and adds it to your `INSTANCE.md` project list. |
| `tools/register-project.sh` | Adds existing project folder(s) to the `INSTANCE.md` project list — one line each, safe to re-run: `register-project.sh <path>…`. |
| `commands/` | Commands you can run: `/keel-setup` (lets the assistant finish setup — fills your machine details and drafts a project's `CLAUDE.md` from its code), `/init-project` (set up a project), `/context-dump` (onboard an existing, undocumented codebase by actually reading it), `/go` (start a backlog task on its own), `/wrap` (close out a session — tidy up notes, changelog, backlog), `/global-review` (review across all projects), `/backlog` (show the backlog). |
| `examples/` | A runnable, safe 5-minute tour of the tools — `init-project` → `doctor` → `secret-guard` blocking a key, start to finish. |
| `docs/loading-and-cost.md` | What loads when, why, and the per-session token cost — with a with/without-Keel comparison. |
| `docs/getting-started.md` | The longer setup walk-through: what gets set up, how it fits into your day-to-day, and how to tell it's working. |
| `docs/going-public.md` | A safe step-by-step for making a private repo public: find leaks (`public-audit`) → fix names → clean history → flip. |

## What runs by itself vs what's up to you

This is the honest part. A file full of good advice does **not**, on its own, change how your assistant
behaves — loaded text nudges it, but nothing forces it to follow, and it won't always remember to.
**You are the trigger.** Real out-of-the-box behavior change comes only from the tools. So:

**Runs by itself — works without you remembering:**
- `secret-guard` — blocks a key-shaped secret, or your listed personal data, when you commit or push
  (a git check; fires on its own).
- `install` — sets up the core and the check in one command (run it; it's done).
- `doctor` — tells you what's missing when you ask (run it; it answers).
- `public-audit` — scans files and git history for personal leaks before you go public (run it; it answers).
- `init-project` — sets up a project (run it; it's done).

**Up to you — advice that nudges, but you have to apply it:**
- `PRINCIPLES.md`, `FRAMEWORK.md`, the `CLAUDE.md` ground rules — they shape decisions *when read*, but
  nothing makes the assistant obey. Think of them as a lens you choose to look through, not an autopilot.

Knowing which is which is the point: don't expect the advice to enforce itself.

`./install.sh --home DIR` sets Keel up for an AI tool other than Claude Code; `--no-hooks` skips the git
check. To set it up by hand instead, copy `templates/CLAUDE.md`, `templates/INSTANCE.md`, `FRAMEWORK.md`,
and `PRINCIPLES.md` into `~/.claude/`, then run `tools/install-secret-guard.sh --global`.

Want to see it work first, without touching anything? Run the safe
[5-minute tour](examples/README.md): `examples/tour.sh`.

New here? The longer walk-through — what gets set up, how it fits into your day-to-day, and how to tell it's
working — is in [`docs/getting-started.md`](docs/getting-started.md).

## Tests

The tools check themselves — a small Bash test suite (no extra dependencies) runs on every change across
Linux and macOS, plus a `shellcheck` pass. If any tool breaks, the tests go red.

```bash
tests/run.sh   # secret-guard block/allow/allowlist, doctor checks,
               # init-project re-run safety, install.sh setup + don't-overwrite guards
```

It's the same rule Keel asks of you, applied to Keel itself: the project is the first thing it checks.

## Scope

A reference and method, not a packaged product or a subscription. Built for Claude Code but not tied to any
one model or tool — see [`ADAPTING.md`](ADAPTING.md).

## License

Licensed under MIT (see [`LICENSE`](LICENSE)). Releases are tracked in [`CHANGELOG.md`](CHANGELOG.md).
