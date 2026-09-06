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
| `~/.claude/CLAUDE.md` (from `templates/CLAUDE.md`) | **every session** | The thin always-loaded core: git/secret rails, reconcile-first, verify discipline, how to handle forks, memory, a trigger-condition index of shipped `docs/` procedures, and a **map** of where everything else lives. Shapes **every** decision the agent makes. | **~2,490** |
| `CORE.md` | **every session** in a linked setup (imported live); never as its own file in a copy setup — the template above embeds it verbatim | The rails alone, placeholder-free. A Claude Code linked install imports this instead of copying the template, so `git pull` in the checkout refreshes the rails; your own map/preferences ride in your own file. (On a machine with no git projects, `install.sh --link --no-git` trims the code/git rails out of the imported core — a couple hundred tokens lighter, and the trim leaves an always-on breadcrumb so the rails come back before git ever enters the workflow.) | ~1,920 |
| `<project>/CLAUDE.md` (from `templates/project-CLAUDE.md`) | when you work **in that project** | Project context: stack, architecture, conventions, roadmap. Shapes decisions inside the project. | ~330 *(as filled)* |
| `FRAMEWORK.md` | on demand — tasks about KB structure / conventions | The reusable methodology engine. Read when grooming a knowledge base, not every session. | ~12,300 |
| `PRINCIPLES.md` | on demand — foundational / expensive-to-reverse forks | P0–P4. Opened rarely, for a specific decision. | ~5,950 |
| `INSTANCE.md` (from `templates/INSTANCE.md`) | on demand — need the project registry / environment | The private personal layer (hardware, model access, project list). | ~380 |
| `LEARNINGS.md` (from `templates/LEARNINGS.md`) | on demand — staging a workflow insight | The on-ramp between "promote to a rule" and "drop". | ~360 |
| `IDEAS.md` (from `templates/IDEAS.md`) | on demand — staging a raw, not-yet-actionable idea | The earliest staging tier, one step before `LEARNINGS.md`/`BACKLOG.md`. | ~290 |
| `ADAPTING.md` | on demand — run Keel under another AI tool | Reference. | ~3,750 |
| `CHANGELOG.md` | on demand — release history | Reference. | ~115,000+ |
| `commands/*.md` (excl. `polish.md`) | **only when you invoke** that command | Lifecycle procedures (`/wrap`, `/init-project`, …). Only the invoked command's body loads. | ~250–2,100+ each |
| `commands/polish.md` | **only when you invoke** `/polish` | The outlier: simplify + tests + a depth-matched review + the gate + the PR, in one command — several times the next-largest command. | ~14,000+ |
| `install.sh`, `tools/*.sh`, `secret-guard/*` | **never loaded** — executed in the shell | The mechanized layer: blocks secrets, runs audits. Only their few lines of **output** reach the context. | **0** |

## The actual per-session cost

The only thing you pay **every** session is the always-loaded core:

- **Globally, any session:** ~2,490 tokens (~1,920 if you import `CORE.md` and keep the
  map/preferences in your own file).
- **Working inside a project:** + ~330 → **~2,820 tokens** at session start.

Everything else is opt-in. A typical session reads **none** of `FRAMEWORK` / `PRINCIPLES` / the commands —
they open pointwise, under a specific task. The tools cost **zero** context.

Put in perspective:

- A ~200K-token context window means the core is **~1.2%** of it. Practically noise.
- The core is **identical from session to session** → a prime candidate for **prompt caching**, where a
  cache hit costs ~10% of the normal input price. The effective cost is lower still.
- Over a month at ~50 sessions, the always-loaded core is ~125K input tokens total — cents, less with caching.
- Even if you do open `FRAMEWORK` + `PRINCIPLES` together (rare), that's a one-off ~18.3K for one decision.

A guard against bloat ships with the whole session's set: `doctor` raises a **HINT** (`H-FOOTPRINT`)
when a project's own `CLAUDE.md` PLUS the resolved global `CLAUDE.md` (its `@…/keel/CORE.md` import
followed, when one is wired) together pass **10,000 tokens** (`KEEL_STARTUP_WARN_TOKENS`), naming both
figures separately. For scale, the typical project file above is ~330 and the global core ~2,490 —
together roughly 28% of the budget — so the hint fires only once one side has grown into a roadmap,
which is exactly what it then tells you to move to the on-demand tier.

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

**With Keel — the rails and project context are already loaded (~2,820 tokens, cached):**

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

Cost: ~2,820 fixed, cacheable tokens — and you **stop paying the re-explanation tax**. Outcomes are
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
- The **mechanized layer** is a hard guarantee: `secret-guard` is a git hook that *fires by itself*
  and blocks a key-shaped secret regardless of what the model decides; `doctor` / `public-audit` answer on
  demand. These cost **zero** context tokens.

## Retiring a shipped capability

Everything above prices *adding* to this tiered structure. The same tiering discipline has a reverse
direction: retiring something that no longer earns its keep. Without a designed path for that, "add" is
the only move the process supports, and a knowledge base only ever grows. This is that path. (Doctrine
origin: `dir #358`.)

**The unit of removal is the delivery slot, not "a capability" in the abstract** — the same three tiers
from the top of this page, given a cost ruler each rather than just a loading rule:

| Class | What it is | What it costs | Existing ruler |
|---|---|---|---|
| **A — always-on** | a `CORE.md`/`templates/CLAUDE.md` section or index bullet | every session, forever | the token figures on this page |
| **B — on-demand** | `docs/*.md`, `FRAMEWORK.md`, `PRINCIPLES.md`, `commands/*.md` | tokens × how often it's actually reached — frequency is the half nobody measures | tokens only, today |
| **C — mechanism** | a script, hook, or guard | zero context tokens; the cost is maintenance and friction | tickets and fixes filed against it |

**The evidence bar is a required shape, not a threshold.** A number fixed before the data exists is
arbitrary; one fixed after is fitted to the verdict you already wanted. A retirement proposal needs all
four of:

1. **Cost** — measured per the class above, never estimated where a ruler exists.
2. **Benefit** — measured against the one property the capability itself claims to serve, or explicitly
   marked absent.
3. **Reach** — measured: does it have a trigger condition (or an invocation site), and does it fire?
4. **The successor** — named: a simpler alternative, an absorbing capability, or an explicit "nothing
   replaces it; the need goes unserved." Cost without a named successor is a measurement, not a proposal.

**Verdict rule:** cost alone never licenses retirement — a cheap useless thing and an expensive vital
thing both fail a cost-only bar, in opposite and equally wrong directions. Retire only when measured cost
is non-trivial for its class **and** measured benefit is not distinguishable from zero across repeated
measurement, never a single point estimate. Zero reach licenses descending exactly one rung (to
Unsurface, below) — no further, since low reach can be a delivery defect rather than a value one. **Ties
go to keeping, except in class A**, where the always-on cost is paid by every session forever — the same
asymmetry this page already argues for *adding*, run in reverse.

**The tail-risk exemption does not bend under cost pressure:** a guard, a refusal, or a never-clobber
rail is judged on **whether the hazard it guards against still exists — not on how often it has fired.**
A quiet guard and a useless one look identical to a cost/benefit ledger, and the bar would be most
persuasive exactly when it was most wrong: deleting a safety rail during the quiet period it earned by
working (the remove-side mirror of [`PRINCIPLES.md`](../PRINCIPLES.md)'s P4 prophylactic exception, run
in reverse). The exemption excuses the *benefit* input only — cost, the record below, and the cooldown
still apply. To invoke it, name the hazard: "it might matter someday" doesn't qualify, a reproducible
failure mode does.

**Five rungs, ordered by reversibility, descended one at a time:**

| Rung | Action | Result | Available today? |
|---|---|---|---|
| **R0 — Freeze** | stop investing further | nothing changes on disk | yes |
| **R1 — Unsurface** | drop the trigger reference; it still ships and works | a cheaper always-on layer only | yes |
| **R2 — Unship** | stop placing it in new/updated installs; source stays in the repo | gone from new installs | yes for `docs/*` (no adopter footprint); a placed artifact needs a prune step this project doesn't ship yet |
| **R3 — Off by default** | ship it, wire it, default it inert | present but inactive until turned on | no — needs an off-switch mechanism this project doesn't have yet |
| **R4 — Delete** | remove it from the repo | gone | yes for `docs/*`; a placed artifact needs R2's prune first |

R1 is the rung most knowledge bases skip, and the useful one: it separates *"is this worth its always-on
cost?"* from *"is this capability any good?"*, answering only the first — cheaply, reversibly, with an
exact, re-measurable cost recovery. Unsurface when something **can't earn a place in the trigger index**
— never because the index merely feels crowded; a crowded index is a re-measurement problem, not a
licence to cut. **Cooldown:** descend one rung per release, never skipping — each rung produces the
evidence the next decision needs, and skipping ahead throws it away. One exception: something that never
shipped in a tagged release can be deleted outright — no installs to strand. Class A never reaches
R2/R3 in practice, since a `CORE.md` bullet has no "wired but inert" state to occupy — its real ladder is
R0/R1/R4.

**The record must not manufacture a dead reference.** If your changelog follows [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/): announce a retirement in `### Deprecated` one release
ahead of it (the adopter-visible form of the cooldown above), and record it in `### Removed` in the
release that performs it — naming the capability, the property it claimed, the measured cost recovered,
the rung it moved from and to, and where the reasoning went. **Tombstone what is cited, delete what is
not.** A retired capability's reasoning is the most valuable part of it — lose it and the same idea gets
re-proposed at the same cost later, but keeping full prose for every retirement forever recreates the
growth retirement exists to stop.

## Bottom line

You pay a **small, stable, cacheable** fixed cost — ~2,490 tokens globally, ~2,820 inside a project — for
two things: the agent stops re-deriving your project from scratch each session, and a mechanical layer
guards your commits for free. The heavy material (`PRINCIPLES`, `FRAMEWORK`) stays behind an on-demand
door, off the startup footprint. That is the whole point of tiering — keep the *always* tier tiny, and let
everything expensive be *pulled*, not *carried*.
