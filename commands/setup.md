# /setup

Finish a Keel install — fill the content that `install.sh` (mechanical) can't, by inspecting **this
machine** and the **current project**. You **draft**; the human reviews. Hard rules: never clobber a
file, never `git commit`/push, and never invent a fact that isn't in the repo or the machine — flag
anything that is the user's *judgment* as a question, don't guess it.

## Preconditions

`install.sh` has run — the harness home (default `~/.claude`) has `CLAUDE.md`, `INSTANCE.md`, and
`commands/`. If it hasn't, tell the user to run `./install.sh` first and stop.

## Do, in order — confirm with the user as you go

### 1. `INSTANCE.md` → Environment (facts: auto-detect)
Open `~/.claude/INSTANCE.md`. In its **Environment** section, replace the `<placeholders>` with detected
facts (run the commands; don't assume):
- **Hardware:** `uname -m`; RAM via `sysctl -n hw.memsize` (macOS) or `/proc/meminfo` (Linux).
- **OS / shell:** `sw_vers` or `uname -sr`; the login shell from `$SHELL`.

Leave **Model access** and **Other tools** for the user — ask once, don't guess. Do **not** touch the
Projects registry (it auto-fills via `init-project` / `register-project`).

### 2. This project → draft its `CLAUDE.md` (facts: from the repo)
If the current directory isn't yet a Keel project, run `tools/init-project.sh .` (scaffolds + registers).
Then read the repo and fill the **draft** project `CLAUDE.md`:
- **Overview** — 2–3 lines of what this project is, inferred from its README / entry points.
- **Stack & conventions** — language, framework, build + test + lint commands, read from the **real**
  files (`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `Makefile`, CI config). State only
  what you can see; don't invent versions or rules.
- **Roadmap / backlog** — leave the stub unless the user tells you the open work.

Show the draft and ask the user to correct it. You're saving them the typing, not the judgment.

### 3. `~/.claude/CLAUDE.md` → the always-loaded rails
- If it's Keel's **template** (still has `<placeholders>` like chat language), fill them — ask the user
  the few choices, don't assume.
- If it's the user's **pre-existing** file (install left it untouched), do **not** overwrite. Show what
  Keel's rails would add (`diff` it against `templates/CLAUDE.md`) and offer to merge the parts they want.

### 4. Report
List what you filled (with the detected values) and what still needs the user: model access, the roadmap,
and any convention you marked uncertain. Remind them nothing was committed.

## Guardrails
- **Draft, don't decide:** facts auto-fill; judgment is the user's to confirm.
- **Never clobber** an existing file; **never commit/push**.
- If you can't detect something, leave the placeholder and say so — a blank beats a wrong guess.
