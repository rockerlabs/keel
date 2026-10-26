# Keel

[![CI](https://github.com/rockerlabs/keel/actions/workflows/ci.yml/badge.svg)](https://github.com/rockerlabs/keel/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> ### Context isn't free — and most of yours is clutter.
> Bloated `CLAUDE.md` files and a junk-drawer `.claude/` load as ballast every session — burning
> tokens and burying the signal your assistant actually needs. **Keel keeps the always-on layer thin,
> and loads the rest only when a task needs it.**

Keel is a small *"how I work"* layer your AI coding assistant reads at the start of every session — the
ground rules, plus a map of where everything else lives — so it stops re-learning your project and
stops drowning in a context dump. Alongside it are a few zero-dependency Bash tools: a git hook that
blocks secrets and personal data, a setup checker, and a go-public audit. It's **tool-independent** —
works with any assistant, not just Claude Code — and takes about 10 minutes to set up.

https://github.com/user-attachments/assets/653ede31-639b-4d2b-9ad5-b1b619f221c5

**Built for the case where the clutter compounds:** you run an assistant across several projects on a
months-long horizon, and/or you're taking a private repo public. If that's you, read on.

## What Keel brings

Four properties, independent of which model or tool you run:

1. **Economy.** A thin, stable core (~2.5K tokens) instead of a context dump — the re-explanation
   tax ("we branch off main… there's already a client in `net/`…") stops being paid every session.
   `keel tokens` reads your own sessions' actual spend, so you can check this on your machine
   ([`docs/token-economy.md`](docs/token-economy.md)).
2. **Stability.** The same rails load every session, so behavior stops drifting between sessions —
   and the unchanged prefix is prime prompt-cache material.
3. **Constraint.** The secret-guard git hook blocks a key-shaped leak no matter what the model decides.
   A hard guarantee, not a nudge ([what it covers](SECURITY.md#threat-model--the-lethal-trifecta)).
4. **Accumulation.** The reason for the other three ([`PRINCIPLES.md`](PRINCIPLES.md), P0): decisions
   and project knowledge earned in a session outlive the session — and the model, and the tool itself.

They hold with different force — see
[What runs by itself, what only nudges](#what-runs-by-itself-what-only-nudges) below.

## Install

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel && ./install.sh --link
```

Then **restart Claude Code and run `/keel-setup`** — the assistant finishes setup, no editing by hand.
Run it again inside each project you want Keel on (not the `keel` clone itself): there it writes a first
draft of that project's `CLAUDE.md` from its own code, for you to review.

The installer also turns on the secret-guard git hook where it safely can (`tools/doctor.sh` reports
whether it is on), and it **never overwrites a file you own**: linked mode's one edit to an existing file
is a single announced import line in `~/.claude/CLAUDE.md`, and a re-run only *offers* to refresh a rails
block Keel itself wrote, backing it up first. `--link` wires Keel by reference, so a `git pull` refreshes
the linked files; the secret-guard hook is a copy, though, so re-run `./install.sh --link` after a pull
to refresh it and to wire any file a release adds. Plain `./install.sh` makes a one-time copy instead
(for tools other than Claude Code; Codex has `./install.sh --codex`). *Want to see it work first?*
`./examples/tour.sh` runs a safe demo in a throwaway sandbox.

### Other ways to install

- **Let your assistant do it.** Paste into Claude Code: *"Install Keel from
  https://github.com/rockerlabs/keel — read its README install section and set it up for me (linked mode
  if I have git), then tell me how to finish with `/keel-setup`."*
- **One line, no manual clone:**

  ```bash
  curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh -s -- --link
  ```

Every flag, the no-git fallback, version pinning and what each path installs →
[docs/getting-started.md](docs/getting-started.md).

## How it works

Keel rests on three plain ideas:

1. **Load a little always, the rest on demand** — a small stable core every session; everything else
   pulled in only when a task needs it.
2. **Some things last, some don't** — tools go out of date in a year; your judgment and project
   decisions don't. Invest in the lasting part, keep the machinery thin.
3. **Add a rule only when something hurts** — every rule must fix a real problem you actually ran into.
   That's what keeps a `CLAUDE.md` from rotting into a junk drawer.

What loads when, and what it costs in tokens → [`docs/loading-and-cost.md`](docs/loading-and-cost.md).
The foundation is [`PRINCIPLES.md`](PRINCIPLES.md); the reusable how-to is [`FRAMEWORK.md`](FRAMEWORK.md).

## What runs by itself, what only nudges

This is the honest part. A file full of good advice does **not**, on its own, change how your assistant
behaves — loaded text nudges it, but nothing forces it to follow.

- **Runs by itself:** the tools — the **secret-guard** git hook, the **public-audit** go-public scan,
  **install / doctor / init-project**, and, once you opt in, the **`/polish` gate** (Claude Code).
- **Up to you:** `PRINCIPLES.md`, `FRAMEWORK.md`, and the `CLAUDE.md` ground rules shape decisions
  *when read* — a lens you choose to look through, not an autopilot.

The always-on layer keeps context lean; the tools do the enforcing.

## Just want the git hook?

The two safety tools work standalone — plain Bash + git, no Keel core, no config files, and they never
enter your assistant's context:

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel
tools/install-secret-guard.sh --global   # every repo on this machine, from now on
```

- **secret-guard** blocks key-shaped secrets (`ghp_`, `AKIA…`, `sk-…`, `glpat-`, …) on every commit and
  push — and, opt-in, **your own personal data** (real name, emails, serials) listed in a local
  never-committed file, caught even inside UTF-16 binary fixtures. It exists because such a leak shipped
  in practice: test fixtures from a real device carried their owner's name.
- **public-audit** (`tools/public-audit.sh <repo>`) scans a repo's files **and its git history** for
  personal and secret leaks before you flip it public.

![Real sandboxed run: secret-guard blocks an API key on commit, then the owner's own name hidden inside a UTF-16 binary fixture](docs/demo.gif)

*One of the tools, ~40 seconds, nothing mocked: install the hook → an API key is blocked on commit →
your own name is blocked even inside a UTF-16 binary fixture. Reproduce it yourself:
[`docs/demo/record-demo.sh`](docs/demo/record-demo.sh) (sandboxed, touches nothing).*

## The pre-PR gate — the agent can't lie about review

On Claude Code, once wired, the agent's own `gh pr create` is **hard-denied** until `/polish` — simplify,
tests, a review depth matched to the diff — has run cleanly on the current commit. A hook writes a
mechanical trace the moment a real `/code-review` pass runs, and the gate checks it before unlocking, so
"review: medium" in a PR means a review actually ran.
`/polish` has a fresh-context subagent run the real, built-in `/code-review` pass first, and the PR is
labeled honestly whatever path the review took. The same gate also denies the agent's own `gh pr merge`
(a release manager's pinned `--merge` is the one exception, and only where the project opted in with `KEEL-MANAGER-MERGES`): the merge stays yours.

```bash
tools/install-pre-pr-gate.sh <repo>   # project scope (default) — --global covers every repo instead
```

Opt-in and separate from `install.sh`; it gates the agent, never you typing in your own terminal. What it
wires, its off switches and its limits →
[docs/getting-started.md](docs/getting-started.md#6-the-polish-pre-pr-gate-claude-code-opt-in). Its opt-in
companion, `tools/machine-watch.sh`, flags a change to a machine-global file (git config, hooks, ssh, shell
rc) on the tool call that made it → [docs/reference.md](docs/reference.md).

## Good to know

> **"Isn't this just a well-written `CLAUDE.md`?"** Mostly, yes — and that's the point: one that's
> already written, installed in one command, tested on CI across three platforms, and disciplined enough
> to stay thin. Plus the guard rails a text file can't give you — the git hook and the go-public audit.

> **Not using Claude Code?** Keel doesn't depend on it. The ideas, the `tools/`, and the always-on file
> work with any AI coding tool (Cursor, Aider, Codex, a plain API agent, …); the one Claude-Code-specific
> bit is the slash commands. See [`ADAPTING.md`](ADAPTING.md).

> **Already have your own conventions?** Keel isn't all-or-nothing: lift single ideas into your own
> `CLAUDE.md`, run the [standalone tools](#just-want-the-git-hook) next to what you have, or grab one
> `commands/*.md` and ignore the rest.

> **One command for the rest.** The install adds a `keel` CLI; `keel help` lists its verbs.

> **Status: early experiment.** A cleaned-up copy of one person's working setup, public to find out
> whether it helps anyone besides its author. Feedback welcome; expect rough edges.

## Docs

- [`docs/reference.md`](docs/reference.md) — **what's in the box**: every file, tool and command, and
  [the index of every doc](docs/reference.md#docs).
- [`docs/getting-started.md`](docs/getting-started.md) — the longer setup walk-through.
- [`docs/loading-and-cost.md`](docs/loading-and-cost.md) — what loads when and the per-session token cost.
- [`docs/going-public.md`](docs/going-public.md) — a safe step-by-step for making a private repo public.
- [`ADAPTING.md`](ADAPTING.md) — running Keel on tools other than Claude Code.

## Tests, scope, license

A small Bash test suite (no extra dependencies) and a `shellcheck` pass run on every change across Linux,
macOS and Alpine/busybox — the same rule Keel asks of you, applied to Keel itself. Keel is a reference and
method, not a packaged product. References like `dir #N` in code comments and the changelog point at a
private backlog; the surrounding prose always carries the full context. Licensed under MIT (see
[`LICENSE`](LICENSE)); releases are tracked in [`CHANGELOG.md`](CHANGELOG.md).
