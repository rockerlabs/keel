# Getting started — install Keel and fold it into your agent flow

The [Quickstart](../README.md#quickstart) is the one-command version. This is the fuller walk: what gets
set up, how it actually changes your sessions, and how to tell it's working.

## What you actually do — the whole checklist

Keel is **mechanized setup + content only you can write.** The scripts can't write the content for you —
that's the point (your judgment and project knowledge, not a generated guess). The full list:

| | Step | Type |
|---|---|---|
| 1 | **Install** — `git clone … && cd keel && ./install.sh` (§1) | one command |
| 2 | **Make the rails yours** — fill the placeholders in `~/.claude/CLAUDE.md`. **If you already had a `~/.claude/CLAUDE.md`, install won't overwrite it — merge Keel's rails in by hand** (§1–§2). | ✍️ content |
| 3 | **Fill your private layer** — `~/.claude/INSTANCE.md` **environment** (hardware, model access). The project *registry* fills itself in step 5, so this is just the environment (§2). | ✍️ content |
| 4 | **Check it works** — `examples/tour.sh`, then `doctor` on a real project (§5). | one command |
| 5 | **Per project (repeat for each repo)** — `tools/init-project.sh <path>` *(scaffolds the repo **and auto-registers it** in `INSTANCE.md`)*, **then fill the project `CLAUDE.md` it creates** (stack, conventions, roadmap) (§3). | command + ✍️ content |

The ✍️ content steps (2, 3, the fill in 5) are where Keel becomes useful — an unfilled template loads
nothing worth loading, and `secret-guard` is the only piece that works with zero input from you. Details
of each step below.

## 1. Install

**Requirements:** `bash` (3.2+) and `git`. The tools and git hooks have a `bash` shebang, so a minimal
image without it (Alpine, distroless) needs `bash` first — e.g. `apk add bash git` on Alpine. Without
`bash` the hooks fail *closed* (a commit/push is blocked, not let through), but nothing will run.

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel
./install.sh
```

> **Express (core only):** `curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh`
> installs the always-loaded core + the secret-guard hook + the slash commands into `~/.claude` in one
> command (pass install flags after `--`, e.g. `… | sh -s -- --no-hooks`). It leaves **no local checkout**,
> though — the `tools/` (`doctor`, `public-audit`) and `examples/tour.sh` need the clone above.

`install.sh` is idempotent and **never clobbers a file you already have**. It:

- copies the durable core into your harness home (`~/.claude` by default),
- installs the lifecycle commands into `<home>/commands/` (so `/wrap`, `/go`, `/init-project`, … are
  slash commands on Claude Code — no manual copy),
- wires the `secret-guard` git hook machine-wide,
- seeds a private `INSTANCE.md`,
- verifies the result and prints a `Done. Next:` summary (your install-moment confirmation).

> **Already use Claude Code?** If you already have a `~/.claude/CLAUDE.md`, install **won't overwrite it**
> — it copies everything else but leaves your file untouched, so Keel's always-loaded rails aren't merged
> in. It says so in `Verify` and points you at a `diff` to merge the rails you want by hand.

Flags: `--home DIR` targets a non-Claude-Code harness's always-loaded slot; `--no-hooks` skips the global
git hook.

## 2. What just got set up

| In your harness home | What it is | You should |
|---|---|---|
| `CLAUDE.md` | the thin **always-loaded core** — rails + a map | **edit its placeholders** (chat language, etc.) |
| `FRAMEWORK.md`, `PRINCIPLES.md`, `LEARNINGS.md` | on-demand docs | leave as-is; they're pulled when needed |
| `INSTANCE.md` | your **private** layer — environment + a project registry | fill in the **environment**; the registry auto-fills as you `init-project`/`register-project`. Keep it private (gitignored). |
| a global git hook | `secret-guard` | nothing — it fires by itself |

(What loads when → the README's [*How it loads*](../README.md#the-idea) diagram and
[`loading-and-cost.md`](loading-and-cost.md).)

## 3. Per project (each repo you work in)

```bash
tools/init-project.sh <path>   # scaffold: git, a .gitignore that hides private context, a project CLAUDE.md
tools/doctor.sh       <path>   # audit the baseline (GAP fails, WARN advises)
```

Fill the project `CLAUDE.md` (stack, conventions, roadmap). It loads **automatically** when you work in
that repo. `init-project` also **auto-adds the project to your `INSTANCE.md` registry** (so a
cross-project sweep can find it) — `--no-register` skips that. To register projects you already have, in
one go:

```bash
tools/register-project.sh ~/code/projA ~/code/projB   # one row each, idempotent
```

## 4. How it folds into your flow — what changes day to day

- **Always-loaded rails.** Every session your agent reads the thin core — git flow, reconcile-first, verify,
  secrets, how to handle forks. You do nothing; it's loaded. The agent is biased toward your way of working,
  so you **stop re-explaining it** each session.
- **Per-project context.** `cd` into a project and its `CLAUDE.md` loads — the agent knows the stack and
  conventions without being told.
- **The git hook fires by itself.** A key-shaped secret is blocked on commit/push whether or not anyone
  remembered to check.
- **On-demand docs.** The agent pulls `FRAMEWORK`/`PRINCIPLES` only when a task needs them — you don't carry
  them in every session's footprint.
- **Commands.** `/wrap`, `/go`, `/init-project`, `/global-review`, `/backlog` are prompt procedures.
  `install.sh` copies them into `<home>/commands/`, so on Claude Code they're slash commands out of the
  box; on another harness, point its custom-command feature at that dir, or paste the body.
- **Audits on demand.** `doctor` (baseline drift) and `public-audit` (before going public) — run them when
  you want; they cost zero context tokens.

## 5. Did it work? — an honest check

The **mechanized** parts are checkable. Run them and watch:

```bash
examples/tour.sh                 # sandboxed: init-project → doctor → secret-guard blocks a fake key
tools/doctor.sh <your-project>   # a real baseline audit
```

> Note: running `doctor .` on the Keel repo itself **WARNs** (advisory; exit 0, "structural baseline
> OK") — it does not GAP. Keel's own project `CLAUDE.md` is gitignored (private tool context, per P0), so
> a clone has none. Point `doctor` at *your* project, not at Keel, to see a populated baseline audit.

The **prose rails** (the loaded core) bias the agent *when read* — there is no deterministic "test" for
that, because loaded text nudges a model, it doesn't execute (see the README's *mechanized vs needs-you*).
You feel it instead: the agent branches rather than committing to the default, greps before rewriting a
helper, won't hardcode a secret. If it doesn't, the rails are loaded but the agent didn't apply them — the
human is still the trigger.

## 6. Another model or harness?

Most of Keel is harness-independent. To run it under Cursor / Aider / Continue / a plain API agent, see
[`../ADAPTING.md`](../ADAPTING.md) — what ports as-is, what needs a small adapter, and where it stops.
