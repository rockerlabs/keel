# /init-project

Scaffold a new project to the Keel baseline so it is born-compliant (no backfilling later).

## What it does

Runs `tools/init-project.sh` in the target directory, which idempotently ensures:
1. **git** initialized.
2. **`.gitignore`** ignores the private AI context (`CLAUDE.md`, `.claude/`) + IDE/OS noise.
3. **project `CLAUDE.md`** created from `templates/project-CLAUDE.md` (never overwrites an existing one).

Then it prints the manual follow-ups: fill in `CLAUDE.md`, wire `secret-guard`, register the project in
`INSTANCE.md`, and verify with `doctor`.

## Usage

```
tools/init-project.sh [PROJECT_DIR]      # default: current directory
```

## Notes

- **Idempotent** — safe to re-run; it fills gaps, never clobbers.
- For an existing project that predates the baseline, run it to backfill the missing pieces, then run
  `tools/doctor.sh .` — the audit is the gate, not the scaffold.
- Keep `CLAUDE.md` thin (≤ ~8–10K tokens). Move detail to the on-demand tier as it grows
  (see `FRAMEWORK.md` → "Project context-file structure").
