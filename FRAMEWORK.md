# Keel — Framework (reusable methodology)

The **universal, reusable layer**: how to run a knowledge base and engineer across projects, with **zero
personal data and zero host paths**. A fresh adopter takes this file verbatim and supplies only their own
`INSTANCE.md` (projects, hardware, language, model access). The thin always-loaded `CLAUDE.md` keeps the
unconditional safety rails + a map, and points here on demand.

- **On demand — NOT auto-loaded.** The always-loaded `CLAUDE.md` map says when to read this: knowledge-base structure /
  engineering conventions / changelog format / git mechanics.
- **Reusability boundary:** this file must never contain an absolute host path, a username, hardware, a
  specific model provider, or a project name — those live in `INSTANCE.md`. `doctor` hard-fails if a
  host/user identifier leaks in here.
- Foundation under everything here: `PRINCIPLES.md` (P0–P4).

---

## Model & reasoning-effort selection

No harness today auto-routes the model by task difficulty, so this is a **manual discipline**: pick the
cheapest setting that clears the correctness gate (P1), and *raise effort before swapping the model* —
effort is the finer, cheaper dial.

- **Default: a mid-tier model + medium effort** for the bulk of work (edits, wiring, straightforward fixes,
  docs). Most tasks never need more.
- **Raise reasoning effort first (high)** for: subtle correctness, tricky debugging, ambiguous design with
  competing constraints, multi-file refactors with invariants to preserve. A high-effort pass on a mid-tier
  model often beats a low-effort pass on the top model — and costs less.
- **Reach for the top-tier model** only for *genuinely hard reasoning*: architecture/foundational forks,
  deep root-cause hunts, anything where a confidently-wrong answer is expensive. Not for volume.
- **Context size is NOT a model-selection signal.** Hitting the window calls for compaction / a fresh
  session / better retrieval (P2), not a bigger model.

Tie to P3: economy lives *above* the P1 gate — never downgrade below what a correct result needs, but don't
pay for headroom a task won't use. When unsure whether a task is "hard," name the uncertainty and let the
user pick the tier.

---

## Project context-file structure (the knowledge base)

How to organize `CLAUDE.md` + memory so session startup is cheap on tokens, facts are traceable, and the
whole thing stays maintainable. Applies to all projects.

**Default assumption:** a project = a software repo under git. A different kind of project (notes / content
/ infra without a repo) — adapt the layout, don't silently force the software structure.

**Three tiers — by *when* content loads** *(everything at startup is paid in EVERY session):*
1. **Startup (always loaded):** the project `CLAUDE.md` (how the project works + a roadmap index). Only what
   must always be visible; target `CLAUDE.md` ≤ ~8–10K tokens.
2. **On demand (a pointer from `CLAUDE.md`, not loaded itself):** full changelog, the index of closed work,
   detailed plans for open tasks.
3. **On recall (pointwise):** memory files — reusable invariants.

**Single source of truth:** a fact lives in one place; everywhere else is a pointer, not a copy. **Mutable
state** (test counts, current version, "next task") lives ONLY in `CLAUDE.md`/git — never duplicated into
memory (it will drift).

**Split by threshold, not upfront:** a small project is fine with a single `CLAUDE.md` — don't spawn files
just for structure (that's over-engineering, P4). Move the "on demand" tier into separate files only once
`CLAUDE.md` outgrows ~8–10K tokens.

**Map at the top:** the start of `CLAUDE.md` carries a short "where things live" block (3 tiers + pointers)
so a cold session grasps the layout immediately.

**Project baseline (the minimum every project carries):** git initialized; a `.gitignore` that ignores the
private AI context (`.claude/` / `CLAUDE.md`) plus IDE/OS/build artifacts; a project `CLAUDE.md`. Anything
beyond that is threshold-triggered, not upfront.

**Audit it:** `doctor` reports baseline drift per project — a missing `CLAUDE.md`, an unignored AI context,
a missing secret-guard, a startup footprint over budget. Run it during a periodic review; `init-project`
keeps new projects born-compliant.

### Registry as a thin index — flat cost as project count grows

The cross-project registry (the Projects table in `INSTANCE.md`) is the working-set principle one level up:
it is an **index, not a detail store**. One row = a project's name, path, a pointer to its own `CLAUDE.md`,
and a short stack **tag** (a retrieval hint — language + role, not versions or feature lists). The
per-project detail is single-sourced in that project's `CLAUDE.md`; the registry never copies it (a copy
bloats the registry linearly with project count and drifts from its source).

**Query, don't dump.** When a task needs more than the index:
- *one project* → follow its row's pointer and read that one `CLAUDE.md` (O(1));
- *a sweep over many projects* → recurse into an external context that returns only the conclusion (a script
  iterating the registry, or a subagent for a sweep needing judgment), never into the parent session. The
  parent pays O(1); the sub-context pays O(k) for the k projects it inspects and hands back only the answer.

Adding the Nth project adds one short index row and never inflates a session that is not about it.

### Startup footprint — measured, not assumed

The three tiers keep on-demand and on-recall content out of startup; this keeps the **startup tier itself**
honest. Two signals drive placement, not intuition:

- **Footprint drift = the demote signal.** `doctor` reports the per-session always-loaded set (global
  `CLAUDE.md` + the project's `CLAUDE.md`) as a tracked baseline and warns any project over budget. A WARN
  means: trim — move roadmap/changelog detail to the on-demand tier.
- **Retrieval miss = the promote signal.** A footprint too *small* fails silently — a needed fact wasn't
  loaded and the session ran on a guess. There's no automated hook for this, so capture it by a light
  ritual at session wrap: did the session have to hunt for a fact that should have been in startup? A logged
  miss means: lift that fact into the right tier.

**Prefer a stable cached core over a minimal one.** Size is not the only cost of the always-loaded set:
prompt caching is the dominant lever (P3). A small but *volatile* file in the startup set is worse than a
slightly larger *stable* one, because every edit busts the cached prefix. Keep churning content (mutable
state, "next task") behind an on-demand pointer so the cached startup prefix stays stable across sessions.

### Logical project identity — memory keyed by id, not path

Harnesses commonly key memory off the physical cwd path, so the *same logical project* opened from a
worktree, a monorepo subdir, a moved checkout, or another machine lands in a *different* silo and its memory
doesn't resolve. The durable fix is dependency inversion: bind memory to a stable **logical project id**
(declared in the project's own `CLAUDE.md`, default = its registry name), not to the path. The id travels
with the repo and carries no host path. *(This probe ships the convention, not a resolver tool — when the
harness ships native id-keyed memory, the convention ports straight onto it; the platform absorbing the
mechanism is an upgrade, not a loss — P0.)*

---

## Knowledge & context upkeep

So context files don't bloat and stay useful.

**Where things land — don't duplicate across places:**
- Closed task → git commit/PR (detail) + one line in the archive/index. Keep the last ≤2 closed tasks in a
  `## Recently closed` buffer for a milestone or two before sweeping (a just-closed task often spawns a
  follow-up). Do NOT append an implementation chronicle into memory.
- Open task / design fork → backlog in the project `CLAUDE.md` (detail → the on-demand file once it grows).
- Reusable lesson/invariant NOT present in the code → a memory file, briefly.
- **Anything surfaced but not yet handled** — an idea, a finding, a loose-end, a decision still owed →
  persist it immediately as a backlog ticket (or record the drop + reason). Never leave it chat-only: the
  next session starts cold and won't recall it. This is the *checked* arm of P0's capture engine — every
  session wrap ends with a **red-flag sweep** that tickets / stages / drops everything still floating.
- **A useful workflow insight not yet worth a committed rule → `LEARNINGS.md`** (the staging tier between
  "promote" and "drop"). Each entry carries a recurrence counter; on the 2nd occurrence promote it into the
  right surface and delete the entry — recurrence is the felt-friction promotion signal. Prune candidates
  that neither promoted nor recurred in ~5 sessions; an unpruned list is noise (P2/P3).

**Memory:** one file = one topic. An index file carries one hook line per file, not a copy of the content.
Before writing, check there isn't already a file on the topic. Delete what became wrong.

**The cwd-silo trap:** memory keyed by the session's cwd will NOT load when you later work from a different
path for the same project. So: **cross-project facts** (user/environment, cross-cutting feedback, tool
gotchas) → a global knowledge-base file (cwd-independent); **project-specific facts** → that project's own memory, written
while working FROM the project dir — never from a throwaway cwd. A cross-project fact stranded in a project
silo is effectively invisible.

---

## Git conventions

**Never commit or push directly to the default branch.** Every project, any change size:
1. Create a feature branch off the default.
2. Commit to the feature branch.
3. Push the feature branch.
4. Open a PR into the default branch.
5. After merge, delete the branch (local + remote) and prune stale refs.

*(A solo single-author knowledge-base repo with no reviewer and no CI is the one reasonable carve-out — committing to
the default directly there is ceremony-free; discipline still holds via clear commit messages. Decide this
deliberately, per repo, not by silent default.)*

**Force-push targets a named branch.** Before any `--force`: reconcile the local branch with its upstream
first (never force-push a stale local default), and push the *specific* ref — `git push origin --force
<branch>` — never `git push origin --force --all`, which overwrites every remote ref, including from a
stale local default, and can silently roll the default branch back over merged work.

**Before writing code — reconcile first.** Never start an implementation without analyzing what already
exists. Read the project `CLAUDE.md`; grep shared modules (the function you're about to write probably
exists — extend it, don't duplicate); `git fetch --prune` FIRST so you reconcile against fresh
remote-tracking refs, not a stale picture.

**Worktree discipline.** When working from a git worktree: use the worktree path for every `file_path`/`cd`
(absolute paths leak into the main checkout otherwise); verify `git branch --show-current` before
committing; after merge, tear the worktree down too. A private-fork project gitignores `CLAUDE.md`, so a
fresh worktree starts blind — symlink the main checkout's `CLAUDE.md` into the worktree so the session keeps
the project's context.

**The squash/rebase "merged" caveat.** Git judges "merged?" by commit-SHA reachability, so a squash- or
rebase-merge looks *unmerged* even when its content is fully in. Judge "merged?" by PR state, never by
SHA-reachability alone, before deleting a branch.

---

## Code conventions

**Per-stack lint gate.** Every project enforces a code-style standard through the linter/formatter native to
its stack, run in CI. The *gate* is the durable convention; the specific tool is just that stack's instance
of it (e.g. a `.editorconfig`/formatter config present and wired into CI). A stack with no first-party code
has no gate. `doctor` checks the gate's presence; add a check when a new stack enters the fleet.

**Dependency versioning — never float.** Pin explicit versions everywhere; never `:latest`, `*`, or
unversioned refs (container images, CI runners, language versions, packages). Floating versions break builds
silently when upstream releases; pinned versions make builds reproducible and failures explicit.

**Configuration & secrets.** Never hardcode credentials, URLs, ports, timeouts, or magic numbers — use
environment variables. Personal / machine-specific identifiers (signing IDs, local paths, per-machine
endpoints) → a gitignored local override from the start, never "commit now, clean up later" (it lingers in
history). Commit a tracked config that *optionally* includes a gitignored local one, so a fresh checkout
still builds.

**Design principles.** SOLID; model the domain explicitly (entities, value objects, repositories, services
named after domain concepts); write tests before or alongside implementation — no feature ships without
tests.

---

## PR review

Review the diff before merge — for correctness bugs and for reuse/simplification/efficiency cleanups.

- **Manual review is the mandatory baseline:** a deliberate read of the branch's diff (by you, or a
  heavyweight review pass your harness offers) before the PR merges.
- **An automated PR-review bot is optional (opt-in), not a baseline.** A bot that comments on every PR is
  useful, but it usually needs its own API budget/token (a cost beyond a normal subscription) and may have
  auth/expiry constraints unfit for CI. Wire one only where an API key is deliberately available; otherwise
  rely on the manual pass.

---

## Git branch lifecycle — the squash/rebase "merged" caveat

Git decides "is this branch merged?" by **commit-SHA reachability**. A **squash- or rebase-merge** rewrites
the commits, so the branch keeps SHAs that are *not* ancestors of the default branch even though its content
is fully merged. Two false "unmerged" verdicts follow:

- `git branch -d <local>` **refuses** (thinks work would be lost) → after confirming, use `git branch -D`.
- `git branch -r --no-merged origin/<default>` **flags the branch** → do NOT treat that as stranded work.

**How to apply:** judge "merged?" by **PR state** (`gh pr list --head <branch> --state all`), not by
SHA-reachability alone. Classify each branch `--no-merged` flags: **MERGED** (content is in the default,
branch just not deleted — a cleanup target) · **CLOSED** (deliberately abandoned) · **open** (in-flight,
never flag) · **no PR + real unmerged commits** (genuinely stranded — the only class to surface for human
triage). Enable `gh repo edit <repo> --delete-branch-on-merge` once per repo so merged branches never
accumulate in the first place.

---

## Dependency versioning — NEVER use `latest`

**In every config across every project — pin explicit versions. Never `:latest`, `*`, or unversioned
references.** Applies to:

- Docker images: `postgres:16.3`, not `postgres:latest`
- GitHub Actions: `actions/checkout@v4.1.1`, not `actions/checkout@v4`
- CI runner OS: `ubuntu-24.04`, not `ubuntu-latest`
- Language versions in CI: `python-version: '3.11.9'`, not `'3.11'` / `'3.x'`
- Package manifests: pin in the lockfile / a versions block, never floating inline

**Why:** floating versions break builds silently when upstream releases a new version; pinned versions make
builds reproducible and failures explicit. (`doctor` flags floating image `:latest` tags and major-only
Action `@vN` tags — a managed `*-latest` CI runner label is *not* flagged, it's a recommended alias.)

---

## Shell — an agent's Bash tool often runs the login shell (commonly zsh, not bash)

Many agent "Bash" tools execute via the user's **login shell**, not bash — on macOS that is **zsh** by
default (`$0` = `/bin/zsh`, `BASH_VERSION` unset), despite the tool's name.

**Trap (zsh):** zsh does NOT word-split unquoted parameter expansions (bash does). An unquoted `$var`
holding newline/space-separated items stays a **single argument** — e.g. `git push origin --delete $var`
built from a multi-line substitution passes ONE multi-line refspec and fails (`invalid refspec`), deleting
nothing.

**How to apply:** for multi-item args, don't rely on unquoted `$var` splitting — pipe the list to `xargs`,
loop explicitly, or use a real array; quote single values as `"$var"`. (Which shell your instance runs is an
`INSTANCE.md` fact.)

---

## Changelog

When a project reaches a milestone (end of a session with big changes, infra upgrade, new version), add an
entry to a `## Changelog` section of the project `CLAUDE.md`. Format: `| YYYY-MM-DD | what changed — one line |`.
No need for an entry per commit — only for significant milestones (the git log carries the rest).
