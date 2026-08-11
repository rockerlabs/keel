# Using Keel with another AI tool (not Claude Code)

Keel is built and tested on Claude Code, but most of it doesn't depend on Claude at all — that's on purpose
(keep the machinery thin and easy to swap). This is the honest map: what works as-is, what needs a small
tweak, and how. So "works with any AI tool" is something you can actually *do*, not just a claim.

> **Heads-up — honesty first.** Keel has now been run live on three substrates: **Claude Code**, **Codex**
> (the one bundled in the ChatGPT desktop app), and **Cursor** — the rails fired on all three (with one
> Cursor caveat below). Everything else in the table is still a general recipe, not a tested click-by-click.
> If you get it working on Aider, Continue, Windsurf, or anything else, please
> [share how](#help-map-your-tool) — that's the fastest way this section gets real.

## Non-Claude quickstart (3 steps)

Every AI coding tool has a spot where it reads instructions at the start of a session (an "always-on" file
or a config folder) and, usually, a way to save reusable prompts. Keel just plugs into those.

**1. Put the always-on file where your tool reads it.** Copy the contents of
[`templates/CLAUDE.md`](templates/CLAUDE.md) into your tool's auto-loaded instructions, and edit the map at
the bottom to point at wherever you keep `FRAMEWORK.md`, `INSTANCE.md`, and `PRINCIPLES.md`. Common spots:

| Tool | Where the always-on instructions live | Tested? |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` (what `install.sh` uses) | ✅ |
| Codex (in the ChatGPT desktop app) | `~/.codex/AGENTS.md` (`./install.sh --codex` generates it) | ✅ |
| Cursor | project-root **`AGENTS.md`** — **not** `.cursor/rules/*.mdc` (see the warning below) | ✅ |
| Codex CLI (the standalone OpenAI tool) | an `AGENTS.md` file / the `~/.codex` config | — |
| Windsurf | project "rules" file | — |
| Aider | a "conventions" file you pass in | — |
| Continue | a rule entry | — |
| A plain API / local-model agent | the system-prompt preamble | ⚠️ (see [the boundary](#the-honest-boundary)) |

> **`AGENTS.md` is becoming the cross-tool standard.** The *same* project-root `AGENTS.md` file worked as
> the always-on core on both Codex and Cursor — when in doubt, that's the surface to try first.

> **Cursor warning — use `AGENTS.md`, not `.cursor/rules`.** In testing, a `.cursor/rules/*.mdc` file with
> `alwaysApply: true` (Cursor's own documented "Always" format) was loaded as *agent-requestable on demand*,
> **not** injected as full text — so the rails silently did not fire (the agent committed straight to
> `master`). The identical core placed in a project-root `AGENTS.md` injected as always-on and the rails
> fired. Global **User Rules** (Settings) is the other always-on option, but it lives in-app — you can't
> `git pull` to refresh it.

These are starting points — check your tool's docs for the exact file, and tell us what worked (see below).

> **Already have rules on your tool** (`.cursorrules`, `AGENTS.md`, a conventions file you've tuned)?
> Don't replace them. Keep *your* file as the always-on core and lift into it only what you want from
> [`templates/CLAUDE.md`](templates/CLAUDE.md) — usually the map (pointing at wherever you park
> `FRAMEWORK.md` / `PRINCIPLES.md`) plus whichever rails you don't already have. The `tools/` work the
> same no matter whose rules file you keep.

**2. Use the tools directly — nothing to change.** `tools/` is plain Bash + git. They never call a model,
so they run under any tool, any model, or none:

```bash
tools/install-secret-guard.sh --global   # turn on the commit/push secret check
tools/doctor.sh       <your-project>      # check a project's setup
tools/init-project.sh <your-project>      # set up a new project
```

(`./install.sh --home DIR` will also copy the always-on files into any folder you point it at, if your
tool's config lives somewhere other than `~/.claude`. For Codex specifically, `./install.sh --codex`
generates `~/.codex/AGENTS.md` directly — no manual copy-and-edit needed.)

**3. Wire up the commands.** The files in `commands/` (`/wrap`, `/init-project`, …) are just prompts in
plain English. If your tool has a custom-command or snippet feature, point it at that folder. If it doesn't,
keep them around and paste the one you need when you need it.

> **Skills systems convert 1:1.** Both Codex (`~/.codex/skills/<name>/SKILL.md`) and Cursor
> (`.cursor/skills/<name>/SKILL.md`) use the same shape as Claude Code skills — a `description:` front-matter
> that the agent matches on demand. A Keel command ports across almost unchanged (add a `name:`, drop
> Claude-only fields like `$ARGUMENTS`) and then **autoloads and triggers** — tested on both with
> `/backlog`. So on those tools the command layer is autopilot, not paste-by-hand.

> **Command naming:** unprefixed names (`/wrap`, `/go`, `/init-project`) are lifecycle verbs — once
> installed they're *yours* to edit. The `keel-` prefix marks commands about Keel itself (`/keel-setup`,
> `/keel-score`) — and doubles as the collision fallback: if you already own a command under one of the
> unprefixed names, `install.sh` offers Keel's version alongside as `keel-<name>` instead of overwriting.

## What works as-is (no change)

- **`PRINCIPLES.md`, `FRAMEWORK.md`** — pure method; any model can read them.
- **`tools/`** — `doctor.sh`, `secret-guard/`, `init-project.sh`, `keel-check.sh` are plain Bash. They don't
  depend on any model — e.g. `keel-check.sh "npm test"` fires its stop-the-spiral banner (after the same
  check fails twice) on any tool that runs a shell.
- **The ideas** — load-a-little-always, the project list, keeping the always-on part small — are concepts,
  not code.

## The honest boundary

- The part that **runs by itself** — the `secret-guard` check blocking a key on commit/push — is git-level
  and **works everywhere**, any tool or none.
- The **commands** only auto-run if your tool has a command feature. Without one, they're prompts you paste
  by hand, not autopilot.
- The **stop-the-spiral shim** (`keel-check.sh`) works everywhere — its banner fires off your check's exit
  code on any tool with a shell. Its **hard** form — `keel-check-gate.sh` *blocking* a commit while the
  check is red — is a Claude Code `PreToolUse` hook, so like the commands it's autopilot only where your
  tool has that hook feature; elsewhere the banner is the nudge you get.
- **The `/polish` pre-PR gate** — the command (simplify, tests, a depth-matched review) is plain prose
  and ports like any other command (see above). Its *enforcement* — `tools/pre-pr-gate.sh` hard-denying
  `gh pr create` until `/polish` has run, with a mechanical trace closing the "claimed a review ran"
  bypass — is built entirely on Claude Code `PreToolUse`/`PostToolUse`/`SessionStart`/`UserPromptExpansion`
  hooks (`tools/install-pre-pr-gate.sh` wires them). It **does not port**: on another tool, `/polish`'s
  steps are still worth running by hand or as a prompt, but nothing will block a PR if you skip them.
- **Linked consumption of `CORE.md`** — on Claude Code the always-on file can *import* the rails live
  (an `@path` line pointing at the checkout's `CORE.md`), so `git pull` refreshes them without re-copying.
  `install.sh --link` mechanizes exactly this (plus command symlinks; `doctor.sh --install` audits the
  result). That import mechanism is Claude Code-specific — and the symlinks assume a Unix-y filesystem
  (on Windows, symlink creation is often restricted). On another tool, copying `templates/CLAUDE.md`
  stays the way in — unless your tool has its own include mechanism, in which case the same split
  (rails imported, personal sections yours) works there too.
- The **Memory section** in `templates/CLAUDE.md` assumes your tool has a persistent auto-memory keyed to
  the session or working directory (that's how Claude Code's auto-memory works). Drop that section when you
  copy the file over if your tool has no such feature — there's nothing for it to attach to — **or** if it
  has its *own* native memory that works differently (Codex, for instance, keeps its own memory store, so
  the cwd-keyed-file model doesn't apply). Let the tool handle memory its own way.
- The **Git rails and reconcile-first sections** of `templates/CLAUDE.md` assume you work with code in git
  repositories. If you don't (documents, research, writing), drop both — on a copy install just delete
  the two sections when you copy the file over (`/keel-setup` offers this trim on Claude Code); on a
  linked install run `install.sh --link --no-git`, which generates a trimmed `keel/CORE.md` in place of
  the symlink, keeps the import line, and stays sticky across re-runs (`--with-git` restores the full
  rails). Keep the **Secrets & personal data** section either way: it applies with or without git.
- The **advice** (principles, framework, ground rules) nudges any model *when it's loaded*, but — as always
  — doesn't enforce itself. You're the trigger.
- **The nudge scales with the model.** On a strong model behind real injection (Claude Code, Codex) the
  rails fired reliably. On a **small local model** (tested via ollama) the same loaded prose was a *weak
  nudge, not a reliable gate* — it steered toward the rail sometimes and missed it other times. The one part
  that holds regardless of model strength is the **mechanized `secret-guard` hook**: it's git-level, so it
  blocks a leak whether the model "understood" the rules or not. If you run Keel on a small or local model,
  lean on the git-level guard as your floor and treat the prose rails as guidance, not a gate.

So: the lasting layer and the git-level check work everywhere; the command convenience is as good as your
tool's command support, and the prose rails are as strong as your model. That's exactly what "works with any
AI tool" means here — and exactly where it stops.

## Running several tools on one project in parallel

Keel's rails are tool-independent, so nothing stops you from pointing **different** AI tools at the
**same** repository at the same time — one ticket each. We ran this live: three small independent
tickets on one Java/Spring project, worked concurrently by Claude Code, Codex (the ChatGPT-app one),
and Cursor, with Keel as the only coordination layer — no orchestrator, no daemon, just the rails,
git, and a shared backlog file. All three delivered green PRs; the merged result passed the full test
suite with **zero cross-task interference**. Here is what made it work, and what bit us.

**What carried the run:**

- **Pre-assign tickets and file ownership.** The operator fixed ticket→tool up front (no self-pick),
  and each ticket's spec named the exact files it owns — "if your change needs a file another ticket
  owns, STOP and report." The three PRs ended up with zero overlapping files and merged without a
  single conflict. This is the cheapest concurrency control there is: partition, don't lock.
- **One isolated working copy per tool** (worktree or clone — see the gotcha below), each branch cut
  from fresh `main` before launch.
- **Claim markers in the shared backlog.** Each session stamps an `⏳ IN FLIGHT` marker onto its ticket
  at session start — date and branch at the time of this run, plus the test-first decision `/go`'s rail
  has asked for since. Advisory, not a lock — but combined with the branch scan it's enough.
- **The rails themselves.** Branch-first held on all three tools. Best moment of the run: a session
  hit a git state it didn't expect (the coordinator had renamed branches mid-flight — our mistake,
  see below), re-checked git, and **stopped and asked instead of guessing** — "a blank beats a wrong
  guess" firing exactly as written, zero damage.

**What bit us (learn from our run):**

- **Per-folder-sandboxed tools can't use linked worktrees.** A linked worktree's `.git` is a pointer
  into the main checkout's `.git/worktrees/…` — *outside* the folder the tool's sandbox granted. The
  ChatGPT-app Codex finished its ticket, then couldn't run a single git write. For such tools use a
  **full clone** (self-contained `.git`); keep worktrees for tools whose file access spans the main
  checkout.
- **A ticket number is not a unique key.** On a machine with several Keel projects, "ticket 14"
  resolved against the *wrong project's* backlog and produced a coherent, confidently wrong
  "already done" story. Have the session echo back *which project and ticket title* it resolved
  before it starts working — a cheap catch point for you.
- **Vendor quota dies mid-ticket.** One tool hit its plan limit after authoring the code but before
  commit/PR. Keep every lane finishable without that tool's model: the remaining git mechanics are
  LLM-free, and honest authorship labeling in the PR keeps the record straight.
- **Land your `.gitignore` changes before cutting the working copies** (they inherit ignore rules
  from the commit they're created at), and mind that a *dir-only* pattern like `.cursor/` does not
  match a symlink standing in for that directory.
- **Don't touch branches under live sessions.** A cosmetic branch rename by the coordinator
  mid-flight stalled a session into (correctly) refusing to proceed. Rename before launch or after
  the PRs — or not at all.
- **Merge stays human, one PR at a time.** The tools deliver; the acceptance gate is yours.

The honest summary: the coordination Keel provides here is **passive** — conventions plus git. It was
enough for disjoint tickets, and the failure modes we hit were environmental (sandboxes, quotas,
ignore rules), not collisions between the agents themselves. Overlapping tickets would need more than
this; start disjoint.

## Help map your tool

Claude Code, Codex (ChatGPT app), and Cursor have been run live; everything else in the table is still a
best guess. **If you got Keel running on another tool, please share the recipe** — it's the single most
useful thing you can contribute right now.

Open a short PR or issue with:

- **which tool** (and version), and **which file** it auto-loads instructions from;
- **where you put** the always-on core and the load-only-when-needed docs;
- **how you wired the commands** (or that you paste them by hand);
- **what worked and what didn't** — especially anything in the table above that was wrong.

Even a two-line "on <tool> the always-on file is `X`, the rest worked" is worth a lot. No need for a polished
write-up — a rough note we can fold in is perfect.
