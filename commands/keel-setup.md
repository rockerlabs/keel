# /keel-setup

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

### 2. This project → draft its `CLAUDE.md` (facts: from the repo) — only if there IS a project
First ask: **is the current directory a project the user wants Keel on?** A fresh user may have no
projects yet, and the keel clone itself doesn't count. If there's no such project here (or they're
unsure), skip this step — steps 1 and 3 are machine-wide and work from anywhere — and tell them to
re-run `/keel-setup` later inside each project they add.

Once confirmed: if the directory isn't yet a Keel project, run `tools/init-project.sh .` (scaffolds +
registers). Then read the repo and fill the **draft** project `CLAUDE.md`:
- **Overview** — 2–3 lines of what this project is, inferred from its README / entry points.
- **Stack & conventions** — language, framework, build + test + lint commands, read from the **real**
  files (`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `Makefile`, CI config). State only
  what you can see; don't invent versions or rules.
- **Roadmap / backlog** — leave the stub unless the user tells you the open work.

Show the draft and ask the user to correct it. You're saving them the typing, not the judgment.

### 3. `~/.claude/CLAUDE.md` → the always-loaded rails
- If it's Keel's **template** (still has `<placeholders>` like chat language), fill them — ask the user
  the few choices, don't assume.
- Ask one scope question, in plain words: **will AI sessions on this machine be used for coding projects
  in git, or mostly for documents and texts?** If clearly no-code/no-git, offer to remove the two
  code-specific sections from *their copy* — "Git — mandatory rails" and "Before writing code — reconcile
  first" (meaningfully lighter every session; the "read the project's `CLAUDE.md` first" rail survives in
  the map, and the "Secrets & personal data" section always stays — it applies with or without git).
  Unsure or mixed → keep both (the safe default); a later re-run can still trim.
  **Linked install:** if the file has no embedded rails but an `@…/keel/CORE.md` import line, NEVER edit
  the imported file — it's a symlink into the shared checkout (the trim would break it and be reverted
  by the next pull). To trim there: replace the import line with the core's rails minus the two
  sections (the file becomes copy-owned, losing pull-through — say so), or keep as-is.
- If it's the user's **pre-existing** file (install left it untouched), do **not** overwrite. Show what
  Keel's rails would add (`diff` it against `templates/CLAUDE.md`) and offer to merge the parts they want.

### 4. Report
List what you filled (with the detected values) and what still needs the user: model access, plus — when
step 2 ran — the roadmap and any convention you marked uncertain. Remind them nothing was committed.

## Guardrails
- **Draft, don't decide:** facts auto-fill; judgment is the user's to confirm.
- **Never clobber** an existing file; **never commit/push**.
- If you can't detect something, leave the placeholder and say so — a blank beats a wrong guess.
