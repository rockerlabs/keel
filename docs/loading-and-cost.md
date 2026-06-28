# What loads, when, and what it costs

Keel's central discipline is **tiering**: a small, stable core is loaded into the agent's context every
session, and everything heavier is pulled in only when a task actually needs it. This page is the concrete
answer to "what will Keel cost me in tokens, and what do I get for it."

Token figures below are measured from the shipped templates and estimated at ~4 characters per token (the
same estimate `doctor.sh` uses). Your real numbers depend on how much you fill the templates in.

## Three tiers

| Tier | Loaded… | Goes into the model's context? |
|---|---|---|
| **Always-loaded core** | every session, any directory | yes — the fixed cost you pay each session |
| **On-demand** | only when the task pulls it (the core's map points there) | yes, but only when read |
| **Mechanisms** | never — they run in the shell | no — only their short output appears |

## File by file

| File | When it loads | Why / what it influences | ~Tokens |
|---|---|---|---|
| `~/.claude/CLAUDE.md` (from `templates/CLAUDE.md`) | **every session** | The thin always-loaded core: git/secret rails, reconcile-first, verify discipline, how to handle forks, memory, and a **map** of where everything else lives. Shapes **every** decision the agent makes. | **~1,380** |
| `<project>/CLAUDE.md` (from `templates/project-CLAUDE.md`) | when you work **in that project** | Project context: stack, architecture, conventions, roadmap. Shapes decisions inside the project. | ~270 *(as filled)* |
| `FRAMEWORK.md` | on demand — tasks about KB structure / conventions | The reusable methodology engine. Read when grooming a knowledge base, not every session. | ~4,200 |
| `PRINCIPLES.md` | on demand — foundational / expensive-to-reverse forks | P0–P4. Opened rarely, for a specific decision. | ~5,100 |
| `INSTANCE.md` (from `templates/INSTANCE.md`) | on demand — need the project registry / environment | The private personal layer (hardware, model access, project list). | ~380 |
| `LEARNINGS.md` (from `templates/LEARNINGS.md`) | on demand — staging a workflow insight | The on-ramp between "promote to a rule" and "drop". | ~360 |
| `ADAPTING.md` | on demand — port to another model or harness | Reference. | ~730 |
| `CHANGELOG.md` | on demand — release history | Reference. | ~1,080 |
| `commands/*.md` | **only when you invoke** that command | Lifecycle procedures (`/wrap`, `/init-project`, …). Only the invoked command's body loads. | ~250–1,010 each |
| `install.sh`, `tools/*.sh`, `secret-guard/*` | **never loaded** — executed in the shell | The mechanized layer: blocks secrets, runs audits. Only their few lines of **output** reach the context. | **0** |

## The actual per-session cost

The only thing you pay **every** session is the always-loaded core:

- **Globally, any session:** ~1,380 tokens.
- **Working inside a project:** + ~270 → **~1,650 tokens** at session start.

Everything else is opt-in. A typical session reads **none** of `FRAMEWORK` / `PRINCIPLES` / the commands —
they open pointwise, under a specific task. The tools cost **zero** context.

Put in perspective:

- A ~200K-token context window means the core is **~0.6–0.75%** of it. Practically noise.
- The core is **identical from session to session** → a prime candidate for **prompt caching**, where a
  cache hit costs ~10% of the normal input price. The effective cost is lower still.
- Over a month at ~50 sessions, the always-loaded core is ~60K input tokens total — cents, less with caching.
- Even if you do open `FRAMEWORK` + `PRINCIPLES` together (rare), that's a one-off ~8K for one decision.

A guard against bloat ships with it: `doctor` raises a **WARN** if the always-loaded core exceeds **10,000
tokens** (`KEEL_STARTUP_WARN_TOKENS`). The template core is ~1,380 — about 14% of that budget, with room.

## With Keel vs without — a concrete moment

Same task, a fresh session three weeks into a project: *"add a retry wrapper around our HTTP client and
commit it."*

**Without Keel — the agent starts cold, every time:**

```
you ▸ add a retry wrapper around our HTTP client and commit it
agent ▸ writes a new retry wrapper from scratch (one already exists in net/)
        commits straight to main
        hardcodes the timeout as a literal
you ▸ "we branch off main… there's already a client in net/… don't hardcode the timeout"
      — the same context you typed last week, and will type again next week
```

Cost: a variable re-explanation tax **every session** (hundreds–thousands of tokens of back-and-forth) +
your time + a wrong-fact commit to undo. Outcomes drift between sessions.

**With Keel — the rails and project context are already loaded (~1,650 tokens, cached):**

```
~/.claude/CLAUDE.md (always loaded) already encodes:
  • feature branch → PR, never commit to main
  • reconcile first; grep shared modules before writing — the thing probably already exists
  • never hardcode constants
<project>/CLAUDE.md already encodes: the stack, and that the HTTP layer lives in net/

you ▸ add a retry wrapper around our HTTP client and commit it
agent ▸ greps net/ → finds the existing client, extends it
        opens feature/http-retry, commits there, opens a PR
        (and if it ever stages a key, secret-guard blocks the commit — mechanically)
```

Cost: ~1,650 fixed, cacheable tokens — and you **stop paying the re-explanation tax**. Outcomes are
consistent across sessions.

## The honest boundary

Keel is not magic, and this page won't pretend otherwise (see the README's *mechanized vs needs-you*):

- The **prose rails bias** the agent — loaded text makes the good path *much more likely*, but it does not
  *enforce*. "With Keel" means consistent biasing, not a guarantee.
- The **one hard guarantee** is the mechanized layer: `secret-guard` is a git hook that *fires by itself*
  and blocks a key-shaped secret regardless of what the model decides; `doctor` / `public-audit` answer on
  demand. These cost **zero** context tokens.

## Bottom line

You pay a **small, stable, cacheable** fixed cost — ~1,380 tokens globally, ~1,650 inside a project — for
two things: the agent stops re-deriving your project from scratch each session, and a mechanical layer
guards your commits for free. The heavy material (`PRINCIPLES`, `FRAMEWORK`) stays behind an on-demand
door, off the startup footprint. That is the whole point of tiering — keep the *always* tier tiny, and let
everything expensive be *pulled*, not *carried*.
