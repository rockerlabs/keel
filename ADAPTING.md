# Using Keel with another model or harness

Keel is built and tested on Claude Code, but most of it is harness-independent by design (P0: keep mechanism
thin and replaceable). This is the honest map of what ports as-is, what needs a small adapter, and how — so
"model-agnostic" is a thing you can *do*, not just a claim.

## What's already harness-agnostic (no change)

- **`PRINCIPLES.md`, `FRAMEWORK.md`** — pure methodology; any model reads them.
- **`tools/`** — `doctor.sh`, `secret-guard/`, `init-project.sh` are plain Bash + git. They never call a
  model, so they work under any agent, any model, or none.
- **The ideas** — tiering, registry-as-thin-index, the startup-footprint discipline — are concepts, not code.

## What needs a per-harness adapter

| Keel piece | In Claude Code | In another harness |
|---|---|---|
| The thin always-loaded core (`templates/CLAUDE.md`) | auto-loaded `~/.claude/CLAUDE.md` | put its content wherever your harness auto-injects context — Cursor/Windsurf project rules, an Aider conventions file, a Continue rule, or a system-prompt preamble for a plain API agent |
| On-demand docs (`FRAMEWORK` / `INSTANCE` / `PRINCIPLES`) | read on demand via the map | same idea — keep them in the repo/home and have the agent read them when the task needs them |
| Commands (`commands/*.md`) | `/wrap`, `/init-project`, … slash commands | the bodies are plain prompt procedures — wire them to your harness's custom-command/snippet feature, or invoke by pasting |
| Memory | the harness memory dir (often cwd-keyed) | use your harness's memory, or a folder of notes; keep the `project-id:` convention so a fact resolves across worktrees/machines |

## Minimal port (three steps)

1. **Core:** put `templates/CLAUDE.md`'s content into your harness's always-loaded slot, and edit its map to
   point at where you keep `FRAMEWORK.md` / `INSTANCE.md` / `PRINCIPLES.md`.
2. **Tools:** use them directly — `tools/install-secret-guard.sh --global`, `tools/doctor.sh`,
   `tools/init-project.sh`. No change needed; they're git/Bash.
3. **Commands:** treat `commands/*.md` as prompt templates — bind them to your harness's command mechanism,
   or run them by hand.

## The honest boundary (P1)

- The **mechanized, fires-by-itself** behaviour — the `secret-guard` hook blocking a key on commit/push — is
  git-level and **fully portable** to any harness or none.
- The **command** automations depend on your harness having a custom-command feature. Without one, they are
  manual prompt templates, not autopilot.
- The **principles/framework** bias any model *when loaded*, but — as always — don't enforce themselves; the
  human is the trigger.

So: the durable layer and the git-level mechanism port everywhere; the command ergonomics are as good as your
harness's command support. That is exactly what "model-agnostic" means here — and exactly where it stops.
