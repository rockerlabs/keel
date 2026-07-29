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

![As sessions progress from 1 to 10 to 30, the on-demand files — FRAMEWORK.md, BACKLOG.md, LEARNINGS.md — grow taller, with BACKLOG.md briefly shrinking when tickets close. The always-on core files stay the same thin height throughout, and a gauge showing tokens loaded at session start stays flat at about 2K across all three moments — the per-session cost never grows even as total knowledge does.](tier-growth.svg)

This is the tiering discipline shown over time rather than at one instant: the *dynamic* companion to
the table above.

## File by file

| File | When it loads | Why / what it influences | ~Tokens |
|---|---|---|---|
| `~/.claude/CLAUDE.md` (from `templates/CLAUDE.md`) | **every session** | The thin always-loaded core: git/secret rails, reconcile-first, verify discipline, how to handle forks, memory, and a **map** of where everything else lives. Shapes **every** decision the agent makes. | **~2,210** |
| `CORE.md` | **every session** in a linked setup (imported live); never as its own file in a copy setup — the template above embeds it verbatim | The rails alone, placeholder-free. A Claude Code linked install imports this instead of copying the template, so `git pull` in the checkout refreshes the rails; your own map/preferences ride in your own file. (On a machine with no git projects, `install.sh --link --no-git` trims the code/git rails out of the imported core — a couple hundred tokens lighter, and the trim leaves an always-on breadcrumb so the rails come back before git ever enters the workflow.) | ~1,720 |
| `<project>/CLAUDE.md` (from `templates/project-CLAUDE.md`) | when you work **in that project** | Project context: stack, architecture, conventions, roadmap. Shapes decisions inside the project. | ~270 *(as filled)* |
| `FRAMEWORK.md` | on demand — tasks about KB structure / conventions | The reusable methodology engine. Read when grooming a knowledge base, not every session. | ~8,000 |
| `PRINCIPLES.md` | on demand — foundational / expensive-to-reverse forks | P0–P4. Opened rarely, for a specific decision. | ~5,100 |
| `INSTANCE.md` (from `templates/INSTANCE.md`) | on demand — need the project registry / environment | The private personal layer (hardware, model access, project list). | ~380 |
| `LEARNINGS.md` (from `templates/LEARNINGS.md`) | on demand — staging a workflow insight | The on-ramp between "promote to a rule" and "drop". | ~360 |
| `ADAPTING.md` | on demand — run Keel under another AI tool | Reference. | ~3,400 |
| `CHANGELOG.md` | on demand — release history | Reference. | ~25,000+ |
| `commands/*.md` | **only when you invoke** that command | Lifecycle procedures (`/wrap`, `/init-project`, …). Only the invoked command's body loads. | ~250–1,450+ each |
| `install.sh`, `tools/*.sh`, `secret-guard/*` | **never loaded** — executed in the shell | The mechanized layer: blocks secrets, runs audits. Only their few lines of **output** reach the context. | **0** |

## The actual per-session cost

The only thing you pay **every** session is the always-loaded core:

- **Globally, any session:** ~2,210 tokens (~1,720 if you import `CORE.md` and keep the
  map/preferences in your own file).
- **Working inside a project:** + ~270 → **~2,480 tokens** at session start.

Everything else is opt-in. A typical session reads **none** of `FRAMEWORK` / `PRINCIPLES` / the commands —
they open pointwise, under a specific task. The tools cost **zero** context.

Put in perspective:

- A ~200K-token context window means the core is **~1.1%** of it. Practically noise.
- The core is **identical from session to session** → a prime candidate for **prompt caching**, where a
  cache hit costs ~10% of the normal input price. The effective cost is lower still.
- Over a month at ~50 sessions, the always-loaded core is ~100K input tokens total — cents, less with caching.
- Even if you do open `FRAMEWORK` + `PRINCIPLES` together (rare), that's a one-off ~12K for one decision.

A guard against bloat ships with it: `doctor` raises a **WARN** if the always-loaded core exceeds **10,000
tokens** (`KEEL_STARTUP_WARN_TOKENS`). The template core is ~2,210 — about 22% of that budget, with room.

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

**With Keel — the rails and project context are already loaded (~2,480 tokens, cached):**

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

Cost: ~2,480 fixed, cacheable tokens — and you **stop paying the re-explanation tax**. Outcomes are
consistent across sessions.

## The full loop — actor by actor (Claude Code, gate wired)

The moment above is one exchange. Zoomed out to a whole session, here's who does each step —
**agent** or **operator** — once you've wired the `/polish` gate
(`tools/install-pre-pr-gate.sh <repo>`; see the [README](../README.md#the-pre-pr-gate--the-agent-cant-lie-about-review)):

| Step | Actor | What happens |
|---|---|---|
| Session start | agent (mechanized) | the always-on rails load; `rollout-check` warns if the model/harness changed since last time |
| Reconcile | agent | reads project context, greps for what already exists, checks in-flight branches |
| Branch | agent | cuts a feature branch — never commits to the default branch |
| Implementation | agent | does the work |
| `/polish` | agent | simplify, tests, a review depth matched to the diff |
| *(optional)* raise the bar | **operator** | `/code-review high` or the human-only `/code-review ultra` |
| Gate-unlocked PR | agent (mechanized) | `gh pr create` stays denied until `/polish`'s receipt matches HEAD |
| Review + merge | **operator** | the merge is never the agent's call (core rail) |
| `/wrap` | agent | notes, changelog, backlog updated |

**The operator's whole loop is 3 real touches, +1 optional:** (1) start it — `/go <n>` or a prompt;
*(optional)* raise the review bar yourself; (2) review and merge the PR; (3) `/wrap`. Everything between
is the agent's, and the gate is what makes that middle stretch trustworthy without a fourth touch — the
agent can't skip straight to a PR, and can't fake having reviewed it either (the mechanical trace behind
step 5 of `/polish` — see [`docs/getting-started.md`](getting-started.md#6-the-polish-pre-pr-gate-claude-code-opt-in)).

**Without Keel, the same loop has no rails and no gate:**

| Step | Actor | What happens |
|---|---|---|
| Session start | — | cold; nothing loaded |
| Everything | operator | re-explain conventions, remember to branch, remember to test, remember to review, remember to write it down — every time |
| PR | agent | opens whenever it decides to, reviewed or not — nothing checks |

Both entry points here (`/go`, `/wrap`) already ship to every adopter, so the 3-touch claim holds for
you, not just the maintainer — the gate is the one piece that's opt-in (see the README section linked
above for why: a hook changes session behavior, so it's never wired without a yes).

## The honest boundary

Keel is not magic, and this page won't pretend otherwise (see the README's *What runs by itself, what only nudges*):

- The **prose rails bias** the agent — loaded text makes the good path *much more likely*, but it does not
  *enforce*. "With Keel" means consistent biasing, not a guarantee.
- The **one hard guarantee** is the mechanized layer: `secret-guard` is a git hook that *fires by itself*
  and blocks a key-shaped secret regardless of what the model decides; `doctor` / `public-audit` answer on
  demand. These cost **zero** context tokens.

## Bottom line

You pay a **small, stable, cacheable** fixed cost — ~2,210 tokens globally, ~2,480 inside a project — for
two things: the agent stops re-deriving your project from scratch each session, and a mechanical layer
guards your commits for free. The heavy material (`PRINCIPLES`, `FRAMEWORK`) stays behind an on-demand
door, off the startup footprint. That is the whole point of tiering — keep the *always* tier tiny, and let
everything expensive be *pulled*, not *carried*.
