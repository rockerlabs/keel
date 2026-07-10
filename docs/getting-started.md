# Getting started — set up Keel and fit it into how you work

The [Quickstart](../README.md#quickstart) is the short version. This is the longer walk: what gets set up,
how it actually changes your sessions, and how to tell it's working.

## What you actually do — two steps

**1. Install** (§1) — copies the always-on files into `~/.claude`, turns on `secret-guard`, and adds the
commands. One command:

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel && ./install.sh
```

**2. Run `/keel-setup`** (§2–§3) — restart Claude Code first (new commands show up only when a session
starts). The machine half runs from **anywhere** — even with no projects yet: the assistant fills in your
machine details and the always-on ground rules. Then run it again **inside each project you want Keel on**
(**not** the `keel` clone): that part **drafts the project's `CLAUDE.md` from its code** — you **check** the
draft and add the parts only you know (which models you use, your roadmap).

```
/keel-setup
```

After step 1, secret-guard already protects every commit; after step 2 the ground rules and project notes
are filled in. That's the loop — run `/keel-setup` again in each new project you add.

> **`/keel-setup` not showing up in Claude Code?** New commands appear only when a session **starts** —
> open a **new Claude Code session** after installing, then type `/` and check that `keel-setup` is listed.
>
> The `keel-` prefix keeps it from clashing with a `/setup` you might already have — it installs as
> `/keel-setup`, a name nothing else uses. If for some reason it isn't wired, just follow
> [`commands/keel-setup.md`](../commands/keel-setup.md) by hand — it's a short prompt.

> **Rather do it by hand — or want to know exactly what `/keel-setup` fills in?** `/keel-setup` is just the
> files below, drafted by the assistant from your repo and machine instead of typed by you. The sections
> below break each one down (and the `tools/` you'd run yourself): the always-on ground rules (§2), the
> per-project `CLAUDE.md` (§3), and how to check it works (§5).

## 1. Install

**You need:** `bash` (3.2+) and `git`. The tools and git checks start with a `bash` line, so a bare image
without it (Alpine, distroless) needs `bash` first — e.g. `apk add bash git` on Alpine. Without `bash` the
checks fail *safe* (a commit/push is blocked, not let through), but nothing else runs.

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel
./install.sh
```

> **Express (core only):** `curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh`
> installs the always-on core + the secret-guard check + the commands into `~/.claude` in one command (pass
> install flags after `--`, e.g. `… | sh -s -- --no-hooks`). It leaves **no local copy of the repo**,
> though — the `tools/` (`doctor`, `public-audit`, `init-project`) and `examples/tour.sh` need the clone
> above. That includes the `/keel-setup` and `/init-project` commands: they call `tools/init-project.sh`,
> so they need the full clone too — bootstrap installs the commands, not the tool they drive.

> **What you'll be asked during install:** the secret-guard step changes one global git setting
> (`core.hooksPath`) so the check runs in every repo on the machine. If an AI tool is driving the
> install (Claude Code, the Claude desktop app, …), it will likely show a **permission dialog** for
> that change. It looks technical, but it isn't a bug — it's the one change that turns the protection
> on; allowing it is expected. (Skip the step entirely with `--no-hooks`.)

**Keep the clone when you're done.** The commands and checks need it (the note above lists which) — don't
delete it; park it anywhere out of the way (e.g. `~/keel`). It's Keel itself, not one of your projects:
don't register it or point `/keel-setup` at it. To update later, run `git pull && ./install.sh` in the clone.

`install.sh` is safe to re-run. It **never touches the files you own** (`CLAUDE.md`, `INSTANCE.md`,
`LEARNINGS.md`); for Keel's own core (`FRAMEWORK`, `PRINCIPLES`, the commands) a re-run offers to update a
copy that has **drifted** from the shipped version — asking first (default *no*) when run from a terminal,
or printing the `cp` to run otherwise. It:

- copies the always-on files into your config folder (`~/.claude` by default),
- adds the commands into `<config>/commands/` (so `/wrap`, `/go`, `/init-project`, … are commands on Claude
  Code — no manual copy),
- turns on the `secret-guard` git check machine-wide,
- creates a private `INSTANCE.md`,
- checks the result and prints a `Done. Next:` summary so you know it worked.

> **Already use Claude Code?** If you already have a `~/.claude/CLAUDE.md`, install **won't overwrite it** —
> it copies everything else but leaves your file alone, so Keel's always-on ground rules aren't merged in.
> It says so in `Verify` and points you at a `diff` so you can merge the parts you want by hand.

Flags: `--home DIR` sets up the always-on slot for an AI tool other than Claude Code; `--no-hooks` skips the
git check.

## 2. What just got set up

| In your config folder | What it is | What to do |
|---|---|---|
| `CLAUDE.md` | the small **always-on file** — ground rules + a map of where the rest lives | **fill in its placeholders** (chat language, etc.) |
| `FRAMEWORK.md`, `PRINCIPLES.md`, `LEARNINGS.md` | files loaded only when needed | leave as-is; they're pulled in when a task needs them |
| `INSTANCE.md` | your **private** layer — machine details + a list of your projects | fill in the **machine details**; the project list fills itself as you `init-project`/`register-project`. Keep it private (git-ignored). |
| a global git check | `secret-guard` | nothing — it runs on its own |

(What loads when → the README's [*How it loads*](../README.md#the-idea) diagram and
[`loading-and-cost.md`](loading-and-cost.md).)

## 3. Per project (each repo you work in)

`/keel-setup` (above) does this for you — it sets the project up, then **drafts the project `CLAUDE.md` from
the repo's code** for you to check. The by-hand version:

```bash
tools/init-project.sh <path>   # set up: git, a .gitignore that hides private notes, a project CLAUDE.md
tools/doctor.sh       <path>   # check the setup (GAP = something's missing, WARN = a suggestion)
```

`doctor` checks the essentials: the private AI context is git-ignored, `CLAUDE.md` exists and stays inside
the startup-token budget, `secret-guard` is wired (and not silently bypassed by a repo-local `core.hooksPath`),
dependencies are pinned (no `:latest` / `@vN`), each detected stack has its native linter gate
(Checkstyle / Ruff / SwiftLint), and a live worktree carries its `CLAUDE.md` bridge. It can also sweep every
project in your `INSTANCE.md` registry at once: `tools/doctor.sh --registry ~/.claude/INSTANCE.md`.

Fill in the project `CLAUDE.md` (your stack, conventions, roadmap). It loads **automatically** when you work
in that repo. `init-project` also **adds the project to your `INSTANCE.md` list** (so a review across all
projects can find it) — `--no-register` skips that. To add projects you already have, all at once:

```bash
tools/register-project.sh ~/code/projA ~/code/projB   # one line each, safe to re-run
```

**Onboarding an existing, undocumented codebase?** `/keel-setup`'s draft is a shallow README/manifest
read — fine for a small or well-documented repo. For a real legacy repo, run `/context-dump` instead: it
reads the actual source tree (not just the front door) to draft the stack, architecture, and a
`legacy`-tagged backlog of what it found outdated or risky, citing the file each claim came from.

## 4. How it fits into your day — what changes

- **The always-on file.** Every session your assistant reads the small core — your git flow, check-before-
  you-start, verify, secrets, how to handle a choice with no obvious answer. You do nothing; it's loaded.
  The assistant leans toward your way of working, so you **stop re-explaining it** every session.
- **Per-project notes.** `cd` into a project and its `CLAUDE.md` loads — the assistant knows the stack and
  conventions without being told.
- **The git check runs on its own.** A key-shaped secret is blocked on commit/push whether or not anyone
  remembered to look. Opt-in, it also blocks your *personal data* (real name, drive labels, emails,
  serials — even inside UTF-16 binary files): copy `tools/secret-guard/secret-scan-personal.example`
  to `~/.claude/secret-scan-personal` and fill in your literals; the file stays local, never committed.
- **Load-only-when-needed files.** The assistant pulls in `FRAMEWORK`/`PRINCIPLES` only when a task needs
  them — you don't carry them in every session's memory.
- **Commands.** `/wrap`, `/go`, `/init-project`, `/context-dump`, `/global-review`, `/backlog` are
  ready-made prompts.
  `install.sh` copies them into `<config>/commands/`, so on Claude Code they're commands out of the box; on
  another AI tool, point its custom-command feature at that folder, or paste the body.
- **Checks when you want them.** `doctor` (what's missing) and `public-audit` (before going public) — run
  them when you like; they cost zero memory.

## 5. Did it work? — an honest check

The **tool** parts are checkable. Run them and watch:

```bash
examples/tour.sh                 # safe sandbox: init-project → doctor → secret-guard blocks a fake key
tools/doctor.sh <your-project>   # a real check of your project
```

> Note: running `doctor .` on the Keel repo itself gives a **WARN** (just a suggestion; it passes,
> "structural baseline OK") — not a failure. Keel's own project `CLAUDE.md` is git-ignored (private tool
> notes), so a fresh clone has none. Point `doctor` at *your* project, not at Keel, to see a full check.

The **advice** part (the always-on file) nudges the assistant *when read* — there's no automatic "test" for
that, because loaded text only nudges, it doesn't run (see the README's *what runs by itself vs what's up to
you*). You feel it instead: the assistant weighs options instead of charging at the default, searches before
rewriting a helper that already exists, won't hardcode a secret. If it doesn't, the file is loaded but the
assistant didn't act on it — you're still the trigger.

## 6. Another model or AI tool?

Most of Keel works with any AI tool. To run it under Cursor / Aider / Codex / Continue / a plain API agent,
see [`../ADAPTING.md`](../ADAPTING.md) — what works as-is, what needs a small tweak, and where it stops.
