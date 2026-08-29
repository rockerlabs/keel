# Getting started — set up Keel and fit it into how you work

The README's [Install](../README.md#install) is the short version. This is the longer walk: what gets set up,
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

After step 1, secret-guard protects every commit — the install summary confirms it (and says so plainly
instead if you skipped it with `--no-hooks` or wiring was refused/failed); after step 2 the ground rules and project notes
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

> **Don't have git yet (macOS)?** Run `xcode-select --install` — a small, quick prompt that installs git on
> its own. You don't need Homebrew first just to get git; that's a longer route to the same tool.

```bash
git clone https://github.com/rockerlabs/keel.git && cd keel
./install.sh
```

> **Express (core only):** `curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh`
> installs the always-on core + the secret-guard check + the commands into `~/.claude` in one command (pass
> install flags after `--`, e.g. `… | sh -s -- --no-hooks`). In copy mode it leaves **no local copy of the
> repo**, though — the `tools/` (`doctor`, `public-audit`, `init-project`) and `examples/tour.sh` need the
> clone above. That includes the `/keel-setup` and `/init-project` commands: they call
> `tools/init-project.sh`, so they need the full clone too — bootstrap installs the commands, not the tool
> they drive. (Passing `--link` is the exception: it *keeps* a clone — see [Linked install](#linked-install--recommended-on-claude-code).)

> **No git?** The same one-liner still works — it downloads a source tarball instead of cloning and
> installs the **prose rails + commands only** (secret-guard is a git hook, so it's skipped and `--no-hooks`
> is forced). Install git first for the full setup incl. the guard (macOS tip above). Already have a
> `.tar.gz`? Point `KEEL_TARBALL` at it (URL or local file) to install offline.

> **Latest vs a pinned version:** no flag installs the latest `main`; pin a release with `KEEL_REF=<tag>`
> — it works on every path: `… | KEEL_REF=v0.4.0 sh`, `… | KEEL_REF=v0.4.0 sh -s -- --link`, or
> `git clone --branch v0.4.0 …`. (Linked: re-run with a new `KEEL_REF` to move a pinned checkout to
> another tag; a bare re-run just fast-forwards whatever it's tracking.)

> **Or default to the last release instead of naming a tag:** each GitHub release attaches its own
> `bootstrap.sh`, stamped to install ITS OWN tag by default (main-tracking `KEEL_REF` still overrides
> it) — `curl -fsSL https://github.com/rockerlabs/keel/releases/latest/download/bootstrap.sh | sh`.
> GitHub's `releases/latest` redirect moves itself on every release, so this always resolves to the
> most recent tagged (audited) cut with no manual pointer to maintain — the tradeoff for "audited, one
> version behind main" instead of "freshest, CI-gated but unaudited." `-s -- --link` and `KEEL_TARBALL`
> work the same as above.

> **What you'll be asked during install:** the secret-guard step changes one global git setting
> (`core.hooksPath`) so the check runs in every repo on the machine. If an AI tool is driving the
> install (Claude Code, the Claude desktop app, …), it will likely show a **permission dialog** for
> that change. It looks technical, but it isn't a bug — it's the one change that turns the protection
> on; allowing it is expected. (Skip the step entirely with `--no-hooks`.)

**Keep the clone when you're done.** The commands and checks need it (the note above lists which) — don't
delete it; park it anywhere out of the way (e.g. `~/keel`). It's Keel itself, not one of your projects:
don't register it or point `/keel-setup` at it. To update later, run `git pull && ./install.sh` in the clone.

`install.sh` is safe to re-run. It **never touches the files you own** (`CLAUDE.md`, `INSTANCE.md`,
`LEARNINGS.md`, `IDEAS.md`); for Keel's own core (`FRAMEWORK`, `PRINCIPLES`, the commands) a re-run offers to update a
copy that has **drifted** from the shipped version — asking first (default *no*) when run from a terminal,
or printing the `cp` to run otherwise. It:

- copies the always-on files into your config folder (`~/.claude` by default),
- adds the commands into `<config>/commands/` (so `/wrap`, `/go`, `/init-project`, … are commands on Claude
  Code — no manual copy),
- turns on the `secret-guard` git check machine-wide,
- creates a private `INSTANCE.md`,
- checks the result and prints a closing `Done. … Next:` summary so you know it worked.

> **Already use Claude Code?** If you already have a `~/.claude/CLAUDE.md`, install **won't overwrite it** —
> it copies everything else but leaves your file alone, so Keel's always-on ground rules aren't merged in.
> It says so in `Verify` and points you at a `diff` so you can merge the parts you want by hand.
> (Linked mode below closes this gap differently — with one appended line.)

### Linked install — recommended on Claude Code

`./install.sh --link` wires Keel **by reference** instead of copying: a `~/.claude/keel/` folder of
symlinks into the clone, ONE `@…/keel/CORE.md` import line in your global `CLAUDE.md` (Claude Code
expands `@path` lines at session start), and the commands as symlinks. What that buys — and costs:

**One line, no manual clone:** `curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh -s -- --link`
does the clone for you — into `~/keel` (set `KEEL_DIR` to change) — then links it. Re-run the same line
anytime to update the checkout in place (`git pull`) and re-wire; it refuses if `KEEL_DIR` already holds
something that isn't a Keel checkout. (Plain `curl … | sh` without `--link` stays copy mode and keeps no
clone — the linked path needs a checkout that survives, so this variant keeps one.)

- **Update = `git pull` in the clone.** The next session runs the fresh rails, commands, and docs.
  Then re-run `./install.sh --link` once: a pull refreshes *content*, not *composition* — a file a new
  release ADDS doesn't wire itself. `tools/doctor.sh --install` checks nothing is missing or dangling.
- **Have your own `~/.claude/CLAUDE.md`?** Linked mode appends the single import line to it
  (announced; delete that line to unlink) — your rules stay yours, the rails ride in under them.
- **Migrating from a copy install:** re-run with `--link` — it swaps the embedded rails block for the
  import line and upgrades unmodified command copies to symlinks; anything you edited is left alone
  and flagged instead.
- **A pull changes your next session's rails without review.** `main` is PR- and CI-protected, but
  pull deliberately — don't automate it; a conservative setup pins a release tag (`git checkout vX.Y.Z`).
- **The clone becomes the installation.** Park it somewhere permanent *before* linking; moving it later
  dangles every link (re-run `--link` from the new spot to repair). Removal is fully enumerable:
  delete `~/.claude/keel/`, the one import line, and the command symlinks.
- `@import` and symlinks are **Claude Code / Unix mechanisms** — on other tools, and on Windows setups
  without symlink support, stay on the copy path above (see [ADAPTING.md](../ADAPTING.md)).

Flags: `--link` wires by reference as above (Claude Code); `--home DIR` sets up the always-on slot for
an AI tool other than Claude Code; `--no-hooks` skips the git check; `--link --no-git` trims the
code/git rails from the always-on core on a machine with **no** git projects (sticky across re-runs;
`--with-git` restores them — do that *before* git ever enters the workflow).

## 2. What just got set up

| In your config folder | What it is | What to do |
|---|---|---|
| `CLAUDE.md` | the small **always-on file** — ground rules + a map of where the rest lives | **fill in its placeholders** (chat language, etc.) |
| `FRAMEWORK.md`, `PRINCIPLES.md`, `LEARNINGS.md`, `IDEAS.md` | files loaded only when needed | leave as-is; they're pulled in when a task needs them. (On a **linked** install FRAMEWORK/PRINCIPLES live in `keel/` as symlinks, not at the top level.) |
| `INSTANCE.md` | your **private** layer — machine details + a list of your projects | fill in the **machine details**; the project list fills itself as you `init-project`/`register-project`. Keep it private (git-ignored). |
| a global git check | `secret-guard` | nothing — it runs on its own |

(What loads when → the README's [*How it works*](../README.md#how-it-works) diagram and
[`loading-and-cost.md`](loading-and-cost.md).)

## 3. Per project (each repo you work in)

`/keel-setup` (above) does this for you — it sets the project up, then **drafts the project `CLAUDE.md` from
the repo's code** for you to check. The by-hand version:

```bash
tools/init-project.sh <path>   # set up: git, a .gitignore that hides private notes, a project CLAUDE.md
tools/doctor.sh       <path>   # check the setup (GAP = missing, WARN = a suggestion, HINT = a nudge)
```

`doctor` checks the essentials: the private AI context is git-ignored, `CLAUDE.md` exists and stays inside
the startup-token budget, `secret-guard` is wired (and not silently bypassed by a repo-local `core.hooksPath`),
dependencies are pinned (no `:latest` / `@vN`), each detected stack has its native linter gate
(Checkstyle / Ruff / SwiftLint / shellcheck), and a live worktree carries its `CLAUDE.md` bridge. It can also sweep every
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
- **Stop the spiral when a fix keeps failing.** Run your task's check through `tools/keel-check.sh "npm
  test"` (any command): after the same check fails twice it prints a STOP-and-diagnose banner instead of
  letting the assistant keep trying new variants on hope. Zero-dependency, works on any tool with a shell.
  On Claude Code you can go further — `KEEL_CHECK_VETO=1` plus registering `tools/keel-check-gate.sh` as a
  PreToolUse hook *blocks* a commit while your declared check is still red.

> **Working without git or code** (documents, research, chat-style sessions)? Be clear about what's left:
> the advice layer still applies — persist decisions, verify before claiming done, handle forks openly —
> and the git/code sections can come out of your always-on file: on a linked install run
> `install.sh --link --no-git` (`/keel-setup` will offer it; `--with-git` brings the rails back if git
> ever enters the picture), on a copy install `/keel-setup` trims your copy in place. But the mechanized
> layer (`secret-guard`, `doctor`, `public-audit`) is git-based and won't fire without repositories:
> for you, Keel is advice that nudges, not guarantees that run by themselves.

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

## 6. The `/polish` pre-PR gate (Claude Code, opt-in)

`/polish` — simplify, run tests, a review depth matched to the diff, then open the PR — ships with every
install. Its enforcement (`tools/pre-pr-gate.sh`, a Claude Code hook) does **not**: wiring a hook changes
what a session can do without asking each time, so it's a separate step you opt into per project:

```bash
tools/install-pre-pr-gate.sh <repo>     # project scope — only sessions IN this repo are gated
tools/install-pre-pr-gate.sh --global   # every repo you open on this machine, instead
```

If you installed into a non-default home (`install.sh --home DIR`), pass the same home here —
`tools/install-pre-pr-gate.sh --home DIR` — or the machine-global hooks land in `~/.claude` while the
rest of the install lives in `DIR`. Per-repo wiring is unaffected.

**What changes in your workflow, once wired:**

- **The agent's `gh pr create` is hard-denied** until `/polish` has run cleanly on the current commit —
  a bare `touch` of the receipt, a partial run, or a receipt from an earlier commit all still fail.
  **Your own terminal is never gated** — the hook fires on the assistant's tool calls, not on you typing
  `gh` yourself.
- **The claim is checked, not just trusted.** A separate hook writes a mechanical trace the instant a
  real `/code-review <level>` pass runs (whether the agent invoked it or you typed it directly); the gate
  cross-checks that trace against the receipt before unlocking, so a session can't write "review: medium"
  without one actually having happened.
- **`/code-review` now runs for real, on its own (dir #254).** The harness's earlier
  `disable-model-invocation` block on `/code-review` has lifted — a session can invoke it directly, so
  `/polish`'s step 5 attempts the real, built-in multi-agent `/code-review <level>` pass itself, with no
  operator hand-off, for `low|medium|high|max`. Only if that direct attempt is refused (the block could
  return) does step 5 fall back to spawning a second, independent Agent-tool subagent (fresh context, no
  memory of the code it's reviewing) to do the review instead, traced the same mechanical way. The PR body
  and the closing summary are always labeled honestly — "independent agent review" is never presented as
  if `/code-review` itself ran on the fallback path. **You're asked before the fact only at the two ends of
  the scale** — `max`/`ultra` (expensive) and `skip` (no review at all); `low`/`medium`/`high` run with no
  question, a deliberate change from the earlier `high`-and-above threshold now that the model can run the
  review itself. The one channel this can't close: if you're asked to run — or waive — a review yourself
  instead (reached only via `ultra`, or the fallback subagent itself being unavailable), that outcome stays
  self-reported (visible in the receipt as `-operator-run` / `-waived`, not a bare level or `agent:<level>`).
  If you choose to run `/code-review` ON TOP of a review that already ran, the receipt records both — the
  mechanically-traced half stays trace-confirmed, only the operator half is self-reported
  (`agent:<level>+operator-run`). **The receipt carries at most one add-on**, and when both an
  operator-run pass and an in-session cross-model second opinion applied, `operator-run` takes the slot
  — it names a human pass, the rarer event and the one you're least able to infer. **The one that loses
  the slot is not lost from the record: the closing summary and the PR body name every mechanism that
  reviewed the commit**, so the receipt is the short form and the prose is the complete one. (A
  comma-separated set used to record all of them; the parser behind it carried several rare-path
  defects and was removed in favour of the prose rule.)
- **A one-line banner at session start** (the `SessionStart` hook, `rollout-check`) if the model or
  Claude Code version changed since your last session here — a silent rollout is exactly how a pipeline
  step like `/code-review` can quietly stop being callable without anyone noticing.
- **`tools/pre-pr-gate.sh sweep`** is a manual, read-only check (run it yourself, e.g. as part of your
  own `/wrap` habit) that warns when the last few `/polish` runs all closed on a self-reported review
  rather than a trace-confirmed one — the blind spot the trace mechanism exists to close.
- **Costs:** `jq` on PATH (required — without it the installer prints the hooks JSON to paste in by hand
  instead of writing anything), a few small `/tmp` state files per repo, and a few extra minutes per PR
  for the review pass itself.

Never clobbers a hook you already have on the same slot — same refuse/`--force`-backs-up discipline as
`install-secret-guard.sh`. Health check any time: `tools/doctor.sh --install` (flags `/polish` shipped
but no machine-global gate wired — expected if you used project scope instead, which is the default).
This is a Claude Code hooks mechanism specifically — see [`ADAPTING.md`](../ADAPTING.md) for the honest
boundary on other tools.

## 7. Another model or AI tool?

Most of Keel works with any AI tool. To run it under Cursor / Aider / Codex / Continue / a plain API agent,
see [`../ADAPTING.md`](../ADAPTING.md) — what works as-is, what needs a small tweak, and where it stops.
