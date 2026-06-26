# Keel

A thin, model-agnostic layer for **what to load into an AI agent's context, when, and how much** — and for
keeping the judgment and project knowledge you accumulate from devaluing every time the tools change.

> **Status: experimental probe.** This is an early, depersonalized extract of a working personal knowledge
> base. It is published to find out whether it's useful to anyone beyond its author — not as a finished
> product. Feedback welcome; expect rough edges.

## The idea

Every AI session starts cold — the agent re-learns your project, conventions, and past decisions from
scratch. Dumping everything into context is the opposite failure: the agent drowns in noise and grabs the
wrong fact. Keel is the discipline in between, on three ideas:

1. **Tiering** — a small, stable core is always loaded; everything else is pulled on demand. This is what
   makes it work even on small context windows.
2. **Durable vs disposable** — tools devalue in a year; your judgment and domain decisions don't. Invest in
   the durable layer; keep mechanism thin and replaceable.
3. **Build from friction** — every rule earns its place by solving a real, felt problem, never by wanting
   to be "complete." This is what keeps it from rotting into bureaucracy.

The foundation is in [`PRINCIPLES.md`](PRINCIPLES.md) (P0–P4); the reusable engine is in
[`FRAMEWORK.md`](FRAMEWORK.md).

## What's in the box

| | |
|---|---|
| `PRINCIPLES.md` | The durable foundation (P0–P4) — consult on foundational decisions. |
| `FRAMEWORK.md` | The reusable methodology: tiering, the registry-as-index, startup-footprint discipline, git/code conventions. Zero personal data. |
| `templates/CLAUDE.md` | The thin always-loaded core — copy into your harness (e.g. `~/.claude/`) and edit. |
| `templates/INSTANCE.md` | Your private personal layer (hardware, model access, project registry). |
| `templates/project-CLAUDE.md` | Per-project context template. |
| `tools/doctor.sh` | Structural self-audit of a project's knowledge base baseline. |
| `tools/secret-guard/` | A git-hook scanner that blocks key-shaped secrets on commit/push. |
| `tools/init-project.sh` | Scaffold a new project to the baseline (born-compliant). |
| `commands/init-project.md` | The `/init-project` command. |

## What's mechanized vs what needs you

This is the honest part. A pure-prose principles file does **not** change an agent's behavior on its own —
loaded text nudges a model but neither enforces nor reliably activates; **the human is the trigger.**
Out-of-the-box behavior change comes only from the mechanized layer. So:

**Mechanized — works without you remembering to apply it:**
- `secret-guard` — blocks a key-shaped secret on commit/push (a git hook; fires by itself).
- `doctor` — reports baseline drift on demand (run it; it answers).
- `init-project` — scaffolds a compliant project (run it; it sets up).

**Needs you — prose that biases, but the human must apply:**
- `PRINCIPLES.md`, `FRAMEWORK.md`, the `CLAUDE.md` rails — these shape decisions *when read*, but nothing
  forces them. Treat them as a lens you invoke, not an autopilot.

Knowing which is which is the point: don't expect the principles to enforce themselves.

## Quickstart

```bash
# 1. Put the thin core where your harness auto-loads it, then edit the placeholders:
cp templates/CLAUDE.md   ~/.claude/CLAUDE.md
cp templates/INSTANCE.md ~/.claude/INSTANCE.md      # keep private — your env + project list
cp FRAMEWORK.md PRINCIPLES.md ~/.claude/

# 2. Turn on the secret guard machine-wide (covers every repo without a local hooks override):
tools/install-secret-guard.sh --global

# 3. Scaffold or audit a project:
tools/init-project.sh ~/path/to/project
tools/doctor.sh       ~/path/to/project
```

## License & scope

A reference / methodology repository, not a packaged product or a subscription. Not tied to any one model
or provider. See [`notes/positioning.md`](notes/positioning.md) for the longer framing.
