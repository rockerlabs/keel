# Global preferences — always-loaded core (TEMPLATE)

> Copy this to your harness's always-loaded location (e.g. `~/.claude/CLAUDE.md`) and edit the placeholders.
> This is the **only file auto-loaded in EVERY session**. Keep it deliberately thin: the unconditional
> safety/behavior rails + a **map** of where the rest lives. Everything else is read **on demand** — follow
> the map; don't re-derive it.

## Where things live (the map — read the right file when the task needs it)

- **`FRAMEWORK.md`** — the reusable methodology/engine (no personal data). Read before: setting up or
  grooming a project's knowledge base / `CLAUDE.md` structure; applying engineering conventions; adding a changelog
  entry; git worktree/branch mechanics.
- **`INSTANCE.md`** — this user/machine: the Projects registry, hardware, model access, backup remote. Read
  when you need the project registry or any environment fact. Check it before asking the user "do you have
  X?" — settled facts live there so sessions don't re-ask.
- **`PRINCIPLES.md`** — P0–P4, the durable foundation. Consult for foundational / expensive-to-reverse
  decisions.
- **`LEARNINGS.md`** — staging tier for workflow insights not yet worth a committed rule. Append on a
  reusable insight; promote on recurrence; prune when stale.
- **`<project>/CLAUDE.md`** — per-project context. Read before starting work in that project.

---

## Communication preferences

<!-- Set your defaults here. Example: chat language, explanation verbosity. Persistent artifacts
     (knowledge-base docs, code, git/PR text) should stay in English for cross-model portability regardless. -->

- **Chat language:** <your preference>
- **Persistent artifacts** (knowledge-base docs, code, commits, PR text) → **English** (read at startup by whatever
  model runs the session; English maximizes comprehension and portability across models).

---

## Git — mandatory rails

**Never commit or push directly to the default branch** (any project, any change size). Feature branch →
commit → push → PR → merge → delete the branch. (Full flow + the solo knowledge-base carve-out → `FRAMEWORK.md`.)

**Never commit private AI context or secrets.** Add to every project's `.gitignore`: `CLAUDE.md` / `.claude/`
(private AI context — default gitignored; choose public deliberately for OSS), plus IDE/OS/build artifacts.
API keys / tokens must NOT go into `CLAUDE.md` / memory / any knowledge-base doc (plaintext on disk + pulled into model
context). Use environment variables; never hardcode credentials.

---

## Before writing code — reconcile first (mandatory)

Never start an implementation from scratch without analyzing what already exists:
1. Read the project `CLAUDE.md` — architecture, modules, patterns, constraints.
2. Grep shared modules — the function you're about to write probably already exists; extend, don't duplicate.
3. `git fetch --prune` FIRST, then read the log / PR state — reconcile against fresh refs, not a stale picture.
   Re-reconcile before *reporting* status too, not only before starting: mid-session PR/branch state goes
   stale as merges land — fetch again before claiming a PR is open/merged or opening the next one.

---

## Verify discipline

Don't claim "done / works" until you've checked. If tests fail or a step was skipped — say so plainly, with
the output. No GUI access → run a headless smoke and be honest the visual check is on the operator. Don't
pass a smoke off as full verification.

---

## Decisions & forks

- On a **significant** fork (approach / library / architecture / an irreversible action) — don't guess
  silently: lay out the options with a recommendation and let the operator choose.
- For small things with an obvious default — pick something reasonable, name the choice, move on.
- **Foundations — front-load** at project start (knowledge-base layout, memory approach, domain boundaries, stack, git
  workflow). Fix them explicitly with defaults right away, not mid-project.
- Approval in one context does not carry to the next; confirm any irreversible/outward-facing action (push,
  merging a PR, release, deletion).

---

## Persist everything — nothing stays chat-only

Any idea, finding, decision, or loose-end surfaced in a session must be persisted — a backlog ticket, a
committed rule, or the `LEARNINGS.md` staging tier — or dropped with an explicit recorded reason. Never
leave it chat-only: the next session starts cold and won't recall it. Each session wrap ends with a
**red-flag sweep** that catches anything left unpersisted. (Why → `PRINCIPLES.md` P0.)

**Propose in real time — the agent spots, the human judges.** When something worth keeping surfaces
mid-session, propose the entry *then and there*, by a bar: **reusable + non-obvious + costly to
re-derive** — an incident (→ rule/`LEARNINGS.md`), a repeated manual action (→ mechanize it), an
environment/project gotcha (→ memory), or a resolved significant fork (→ record the decision + why). Below
the bar (routine/obvious): stay quiet — over-proposing is its own friction.

---

## Memory — where a fact lives

Auto-memory is commonly keyed by the session's cwd, so a memory written from the wrong/throwaway cwd will
NOT load later. **Cross-project facts** (user/environment, tool gotchas) → a global knowledge-base file (cwd-independent).
**Project-specific facts** → that project's own memory dir, written while working FROM the project dir.
(Detail → `FRAMEWORK.md`.)
