# /init-project

Scaffold a new project to the Keel baseline so it is born-compliant (no backfilling later).

## What it does

Runs `tools/init-project.sh` in the target directory, which idempotently ensures:
1. **git** initialized.
2. **`.gitignore`** ignores the private AI context (`CLAUDE.md`, `AGENTS.md`, `.claude/`) + IDE/OS noise.
3. **project `CLAUDE.md`** created from `templates/project-CLAUDE.md` (never overwrites an existing one),
   plus an **`AGENTS.md`** vendor sibling symlinked to it (dir #75).
4. **impact tracking** opted in via an external store entry (nothing written into the project's own tree).
5. **registration** in your `INSTANCE.md` Projects registry, if `INSTANCE.md` exists.

Then it prints the remaining manual follow-ups: fill in `CLAUDE.md`, wire `secret-guard`, and verify with
`doctor`. (If registration didn't happen — no `INSTANCE.md` yet, or `--no-register` — it prints that as a
manual follow-up too.)

## Usage

```
tools/init-project.sh [PROJECT_DIR]      # default: current directory
tools/init-project.sh --no-register      # skip auto-registering in INSTANCE.md
tools/init-project.sh --no-impact        # skip opting into impact tracking
```

## Notes

- **Idempotent** — safe to re-run; it fills gaps, never clobbers.
- For an existing project that predates the baseline, run it to backfill the missing pieces, then run
  `tools/doctor.sh .` — the audit is the gate, not the scaffold.
- Keep `CLAUDE.md` thin (≤ ~8–10K tokens). Move detail to the on-demand tier as it grows
  (see `FRAMEWORK.md` → "Project context-file structure").
