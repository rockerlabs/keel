# Using Keel with another AI tool (not Claude Code)

Keel is built and tested on Claude Code, but most of it doesn't depend on Claude at all — that's on purpose
(keep the machinery thin and easy to swap). This is the honest map: what works as-is, what needs a small
tweak, and how. So "works with any AI tool" is something you can actually *do*, not just a claim.

> **Heads-up — honesty first.** The author has only run Keel on Claude Code. The steps below are the general
> recipe, not a tested click-by-click for each tool. If you get it working on Codex, Cursor, Aider, or
> anything else, please [share how](#help-map-your-tool) — that's the fastest way this section gets real.

## Non-Claude quickstart (3 steps)

Every AI coding tool has a spot where it reads instructions at the start of a session (an "always-on" file
or a config folder) and, usually, a way to save reusable prompts. Keel just plugs into those.

**1. Put the always-on file where your tool reads it.** Copy the contents of
[`templates/CLAUDE.md`](templates/CLAUDE.md) into your tool's auto-loaded instructions, and edit the map at
the bottom to point at wherever you keep `FRAMEWORK.md`, `INSTANCE.md`, and `PRINCIPLES.md`. Common spots:

| Tool | Where the always-on instructions live |
|---|---|
| Claude Code | `~/.claude/CLAUDE.md` (what `install.sh` uses) |
| Cursor / Windsurf | project "rules" file |
| Codex (OpenAI) | an `AGENTS.md` file / the `~/.codex` config |
| Aider | a "conventions" file you pass in |
| Continue | a rule entry |
| A plain API agent | the system-prompt preamble |

These are starting points — check your tool's docs for the exact file, and tell us what worked (see below).

**2. Use the tools directly — nothing to change.** `tools/` is plain Bash + git. They never call a model,
so they run under any tool, any model, or none:

```bash
tools/install-secret-guard.sh --global   # turn on the commit/push secret check
tools/doctor.sh       <your-project>      # check a project's setup
tools/init-project.sh <your-project>      # set up a new project
```

(`./install.sh --home DIR` will also copy the always-on files into any folder you point it at, if your
tool's config lives somewhere other than `~/.claude`.)

**3. Wire up the commands.** The files in `commands/` (`/wrap`, `/init-project`, …) are just prompts in
plain English. If your tool has a custom-command or snippet feature, point it at that folder. If it doesn't,
keep them around and paste the one you need when you need it.

## What works as-is (no change)

- **`PRINCIPLES.md`, `FRAMEWORK.md`** — pure method; any model can read them.
- **`tools/`** — `doctor.sh`, `secret-guard/`, `init-project.sh` are plain Bash + git. They don't depend on
  any model.
- **The ideas** — load-a-little-always, the project list, keeping the always-on part small — are concepts,
  not code.

## The honest boundary

- The part that **runs by itself** — the `secret-guard` check blocking a key on commit/push — is git-level
  and **works everywhere**, any tool or none.
- The **commands** only auto-run if your tool has a command feature. Without one, they're prompts you paste
  by hand, not autopilot.
- The **advice** (principles, framework, ground rules) nudges any model *when it's loaded*, but — as always
  — doesn't enforce itself. You're the trigger.

So: the lasting layer and the git-level check work everywhere; the command convenience is as good as your
tool's command support. That's exactly what "works with any AI tool" means here — and exactly where it stops.

## Help map your tool

The author only tested Claude Code, so the table above is a best guess for everything else. **If you got
Keel running on another tool, please share the recipe** — it's the single most useful thing you can
contribute right now.

Open a short PR or issue with:

- **which tool** (and version), and **which file** it auto-loads instructions from;
- **where you put** the always-on core and the load-only-when-needed docs;
- **how you wired the commands** (or that you paste them by hand);
- **what worked and what didn't** — especially anything in the table above that was wrong.

Even a two-line "on <tool> the always-on file is `X`, the rest worked" is worth a lot. No need for a polished
write-up — a rough note we can fold in is perfect.
