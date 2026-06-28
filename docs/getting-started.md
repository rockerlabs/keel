# Getting started — install Keel and fold it into your agent flow

The [Quickstart](../README.md#quickstart) is the one-command version. This is the fuller walk: what gets
set up, how it actually changes your sessions, and how to tell it's working.

## 1. Install

```bash
git clone <repo-url> keel && cd keel
./install.sh
```

`install.sh` is idempotent and **never clobbers a file you already have**. It:

- copies the durable core into your harness home (`~/.claude` by default),
- wires the `secret-guard` git hook machine-wide,
- seeds a private `INSTANCE.md`,
- verifies the result and prints a `Done. Next:` summary (your install-moment confirmation).

Flags: `--home DIR` targets a non-Claude-Code harness's always-loaded slot; `--no-hooks` skips the global
git hook.

## 2. What just got set up

| In your harness home | What it is | You should |
|---|---|---|
| `CLAUDE.md` | the thin **always-loaded core** — rails + a map | **edit its placeholders** (chat language, etc.) |
| `FRAMEWORK.md`, `PRINCIPLES.md`, `LEARNINGS.md` | on-demand docs | leave as-is; they're pulled when needed |
| `INSTANCE.md` | your **private** layer — environment + project registry | fill it; keep it private (gitignored) |
| a global git hook | `secret-guard` | nothing — it fires by itself |

(What loads when → the README's [*How it loads*](../README.md#the-idea) diagram and
[`loading-and-cost.md`](loading-and-cost.md).)

## 3. Per project (each repo you work in)

```bash
tools/init-project.sh <path>   # scaffold: git, a .gitignore that hides private context, a project CLAUDE.md
tools/doctor.sh       <path>   # audit the baseline (GAP fails, WARN advises)
```

Fill the project `CLAUDE.md` (stack, conventions, roadmap). It loads **automatically** when you work in
that repo. Add the project to your `INSTANCE.md` registry so a cross-project sweep can find it.

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
- **Commands.** `/wrap`, `/init-project`, `/global-review`, `/backlog` are prompt procedures. On Claude Code
  they're slash commands; on another harness, wire them to its custom-command feature, or paste the body.
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
