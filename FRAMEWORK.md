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
- **A fallback model falls back, it doesn't route.** A configured fallback model is for provider
  overload/unavailability, not for task difficulty — don't conflate the two.

Tie to P3: economy lives *above* the P1 gate — never downgrade below what a correct result needs, but don't
pay for headroom a task won't use. When unsure whether a task is "hard," name the uncertainty and let the
user pick the tier.

---

## Interview loops — eliciting a multi-question decision

CORE's "Decisions & forks" rail covers a single fork; this is the operational elaboration for a genuine
multi-question **interview** — a decision tree, not one isolated choice (`/design`'s process step 2 runs
one informally today).

- **Fact-vs-decision split first.** Before putting anything to the user, check whether the answer is
  discoverable by reading code, docs, or the environment (`INSTANCE.md` included) — ask only what needs
  the user's own judgment.
- **Sequential when questions branch, batched when independent.** An earlier answer that changes which
  later question even applies (the decision-tree case) forces sequential; independent questions cost less
  round-trip batched — a tool like `AskUserQuestion` supports multi-question batches by design. Don't carry
  a blanket "one at a time" rule forward — that's a chat-interview convention, not a universal.
- **Always attach a recommended answer** to each question, so the user's fastest path is confirming a
  default instead of composing one from scratch.
- **Doesn't lower CORE's bar for opening a fork.** "Don't ask to confirm a default you'd pick anyway"
  still governs whether to open the interview at all — this section only covers mechanics once a genuine
  multi-question fork is already in motion.
- **Thin-orchestrator / reusable-interview-skill split — named, not built.** When a second Keel command
  needs this same interview logic, extract it into a shared skill invoked by thin per-command wrappers.
  Every `commands/*.md` today is monolithic with no felt duplication yet — build the split only once a
  second real command needs it, not speculatively.

---

## Project context-file structure (the knowledge base)

How to organize `CLAUDE.md` + memory so session startup is cheap on tokens, facts are traceable, and the
whole thing stays maintainable. Applies to all projects.

**Default assumption:** a project = a software repo under git. A different kind of project (notes / content
/ infra without a repo) — adapt the layout, don't silently force the software structure.

**Monorepo:** one repo ≠ one project — nested `CLAUDE.md` files in subfolders are allowed, each loaded when
you work inside its subtree.

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

## Loop model — the four operational loops

The knowledge base runs on four nested loops, each with its own input, work, carry-forward, and
termination. Naming them gives future improvements (a cadence backstop, a convergence check) a stable
target instead of ad-hoc reasoning about "the review process."

- **L1 — Session.** *Input:* the backlog + memory + the operator's request. *Work:* whatever the session
  does. *Carry-forward:* memory + backlog + changelog updates. *Termination:* session wrap. *Frequency:*
  every session. *Observability:* none built in — carry-forward correctness is currently an agent's
  judgment call at wrap time, not a measured or verified step.
- **L2 — Wrap.** *Input:* the session's git log + a chat summary. *Work:* reconcile state, update
  backlog/memory/changelog. *Carry-forward:* a commit to the knowledge-base repo. *Termination:* the
  commit is pushed. *Frequency:* end of most sessions. *Observability:* none — nothing automatically
  verifies the reconciliation actually captured everything worth persisting.
- **L3 — Global review.** *Input:* the structure-audit tool (`doctor`) + the backlog + `PRINCIPLES.md`.
  *Work:* sweep the KB for drift, stale items, and structural issues; reconcile. *Carry-forward:* an
  updated KB, pushed. *Termination:* the audit passes clean ("structural-green") and any remaining gaps
  are deliberately deferred to the backlog. *Frequency:* felt-friction-triggered — no fixed cadence by
  default. *Observability:* a pass/fail signal from `doctor`, plus the qualitative signals in the
  "Convergence check" subsection below.
- **L4 — Dev (a backlog ticket).** *Input:* one backlog ticket. *Work:* implement, test, review.
  *Carry-forward:* a merged PR + the ticket closed in the backlog. *Termination:* PR merged and the
  session wraps. *Frequency:* per ticket. *Observability:* none for a ticket that runs long — no
  mid-task checkpoint if the session is interrupted before merge.

**Coupling:** L4 nests inside L1 (a dev session is still a session — it starts and ends the same way).
L1 triggers L2 (every session ends in a wrap). L3 reads the accumulated state of every L1/L2 iteration
since the last review — it is the only loop that looks backward across many sessions rather than forward
within one. **Shared state:** all four loops read and write the same knowledge-base repo; there is no
separate state store per loop, so a loop's "carry-forward" is really just "what it committed."

### Convergence check

The structural audit answers "not broken"; it does not answer "improving." A global review (L3) that
terminates on structural-green alone has a necessary but insufficient convergence signal — the review
can keep passing while the knowledge base quietly stops getting better. Before closing a review, read
four qualitative signals:

1. **Advisory-warning trend.** Compare this review's advisory-warning count (the warn-not-gap class the
   structural-audit tool reports) against the last recorded count. Flat across two or more reviews — or
   rising — is a convergence miss worth naming.
2. **Stuck backlog items.** A backlog item open and unchanged across two or more consecutive reviews is
   not moving; surface it explicitly instead of letting it age silently.
3. **Prune-tier health.** The staging tier for not-yet-rules (promote on recurrence, prune when stale)
   only works if entries move. An entry that hit its promotion count but was not promoted — or nothing
   promoted in roughly five sessions — means the tier is filling instead of draining.
4. **Review-over-review improvement.** Are fewer gaps and warnings surfacing per review as conventions
   mature, or does each review find a similarly sized pile? The latter means the conventions are not
   sticking — only the review is.

None of these is a hard gate; each is a question the review answers in a line. What matters is that the
answers are recorded, so the next review has something to diff against — an unrecorded signal cannot
trend.

**Known gaps** (candidates for future backlog tickets, not a design flaw to fix here):
- L1/L2 carry-forward correctness is asserted, not verified — nothing checks that a wrap actually
  captured everything worth persisting.
- L3 has no cadence backstop — a felt-friction trigger with no maximum interval can go dormant
  indefinitely.
- L4 has no mid-task checkpoint, so a long-running ticket interrupted mid-session loses its plan state.

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

**Decision capture — record the fork when it resolves.** The moment a significant fork settles
in-session (a library pick, an approach, a convention agreed in chat), draft the record THEN: one
line — what was chosen plus the dated why, naming the losing option when it clarifies the reason —
and the human ratifies or rejects the wording before it lands. The ratify step is what keeps the
record "what was ruled", not "what the agent found notable". Route it via the list above (a
`CLAUDE.md` conventions line, a backlog ticket, a changelog entry) — no new file kind, no format
mandate. The recorded why is what stops a later session from re-litigating a settled choice; a bare
"X was chosen" reopens the debate. Capture at the moment is primary; the wrap red-flag sweep is the
net for forks that resolved without a record. This is a process — capture, ratify, sweep — not a
record format; external decision-record formats compose with it.

**Customizing a plugin-shipped skill or command — fork it, don't edit in place.** A skill or command
installed from a plugin lives under the harness's own plugin directory, which is third-party and not tracked
by your knowledge base — so an in-place edit is lost on the next plugin update and absent on a fresh machine
(plugins reinstall clean). Copy it into your own tracked skills/commands directory and edit the copy: a
same-name user-level entry overrides the plugin's, and the fork is versioned and travels with your KB.

**Memory:** one file = one topic. An index file carries one hook line per file, not a copy of the content.
Before writing, check there isn't already a file on the topic. Delete what became wrong. Name files
predictably — snake_case with a category prefix (`feedback_` / `project_` / `reference_`), the in-file
slug and `[[links]]` as the same name in kebab-case — so recall and linking never depend on remembering
an ad-hoc name.

**Staleness check — note-age vs code-age.** "Delete what became wrong" needs a way to notice a note
went wrong. The pull-side check: when a note actually gets read, compare its last-touched date with
the last real change of the code it describes — `git log -1 --format=%cs -- <note-file>` vs
`git log -1 --format=%cs -- <code-path>` (committer dates; squash-merges rewrite them to when the
change actually landed). A note older than the code's last change is suspect: re-verify before
trusting it, then refresh the note or delete it. Honest limits, by design: the check is lazy (drift
sits undetected between reads) and per-file — the one-file-one-topic rule above is what makes it
land on something small enough to point at the suspect claim. No push triggers or dependency graphs.

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
(absolute paths leak into the main checkout otherwise). **The shell cwd drifts silently** after any `cd`
or `git -C <other-checkout>` op — a later `git checkout -b` then creates the branch in the wrong working
tree — so run repo ops with an explicit `git -C <worktree-path>` and verify
`git -C <path> rev-parse --abbrev-ref HEAD` per working copy before committing; never take the cwd alone
as proof of which tree you're in. On a leak, move the changes over with `git stash` (the checkouts share
one `.git`) or a patch. After merge, tear the worktree down too — worktrees pile up faster than branches
(`git worktree remove <path>`; `git worktree prune` for ones whose dir is already gone) — and if your
harness keeps a per-worktree session-memory dir, sweep that orphan as well. A private-fork project
gitignores `CLAUDE.md`, so a fresh worktree starts blind — symlink the main checkout's `CLAUDE.md` into
the worktree so the session keeps the project's context.

**The squash/rebase "merged" caveat.** A squash/rebase-merge looks *unmerged* by SHA even when its content
is fully in — judge "merged?" by PR state, not SHA-reachability, before deleting a branch. Full rule (the
two false verdicts, branch classification, delete-on-merge) → the *Git branch lifecycle* section below.

---

## Code conventions

**Per-stack lint gate.** Every project enforces a code-style standard through the linter/formatter native to
its stack, run in CI. The *gate* is the durable convention; the specific tool is just that stack's instance
of it (e.g. a `.editorconfig`/formatter config present and wired into CI). A stack with no first-party code
has no gate. `doctor` checks the gate's presence; add a check when a new stack enters the fleet.

**Dependency versioning — never float.** Pin explicit versions everywhere; never `:latest`, `*`, or
unversioned refs. Full rule (what to pin, examples, the *why*, what `doctor` flags) → the *Dependency
versioning* section below.

**Configuration & secrets.** Never hardcode credentials, URLs, ports, timeouts, or magic numbers — use
environment variables. Personal / machine-specific identifiers (signing IDs, local paths, per-machine
endpoints) → a gitignored local override from the start, never "commit now, clean up later" (it lingers in
history). Commit a tracked config that *optionally* includes a gitignored local one, so a fresh checkout
still builds.

**Design principles.** SOLID; model the domain explicitly (entities, value objects, repositories, services
named after domain concepts); write tests before or alongside implementation — no feature ships without
tests.

**Build identity — make it self-reporting, early.** Any app should surface its own build identity — a human
version *plus* a per-build stamp (commit SHA + build date) — in its own UI/output (a menu line, an
`--version` flag, a startup log), wired in from near the first ticket that produces a runnable artifact. The
recurring failure it prevents: not being able to tell *which* build is actually running — a stale binary
still serving old code, a cached artifact, an un-relaunched process — which turns a trivial "is this even the
new code?" into a real debugging detour. A static marketing version alone is not enough: it can't
distinguish two rebuilds, so the per-build stamp is the point. Cheap to add at the start, disproportionately
painful to retrofit mid-incident.

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

## Service managers run with an empty environment — `set -u` turns a bare `$HOME` into a fatal crash

A script that runs fine when tested by hand can crash the moment a service manager runs it, because
**systemd (and most service managers) start services with a near-empty environment — `$HOME` is unset**
(also `$USER`, `$LOGNAME`, and only a minimal `PATH`). If the script has `set -u` (nounset) and references
a bare `$HOME` (e.g. `export PATH="…:$HOME/bin:$PATH"`, or `~/…`), expanding the unset var aborts the
whole script before it does anything.

**Why it's a nasty one:** running the script manually — even `sudo ./script.sh` — *does* set `$HOME` (sudo
preserves/sets it), so the manual smoke test passes and the bug only shows up under the timer/service —
e.g. a health-check unit and its `ExecStopPost` handler both dying on `HOME: unbound variable` on the
first real timer fire, after every manual run had been green.

**How to apply:**
- Don't reference a bare `$HOME` in a service script under `set -u`. Use the nounset-safe forms
  `${HOME:+:$HOME/bin}` (append only if set) / `${HOME:-/root}` (explicit default), and `${PATH:-}` for
  `PATH` itself.
- Better: don't depend on `$HOME` at all — hard-code the absolute `PATH` the service needs
  (`/usr/local/bin:/usr/bin:/bin`), or set `Environment=HOME=/root` in the unit's `[Service]` block.
- **Test the real path:** trigger via `systemctl start <unit>` (which reproduces the empty service env),
  not by running the script by hand — the manual run hides exactly this class of bug. Then read
  `journalctl -u <unit>`.

---

## Verify gates — mechanizing the done-claim

A completion claim ("tests pass", "the bug's fixed", "PR's ready") is worth exactly as much as the
evidence behind it. CORE's verify-discipline rail sets the baseline — prefer a narrow, deterministic
check over eyeballing; this section names the mechanism for enforcing that once eyeballing genuinely
isn't enough (an irreversible action, an unattended multi-step procedure).

**Claim → record, not claim → trust.** A completion claim counts only when it points to a record
written by the check itself — a command's exit code, a receipt line, a git SHA — never a record the
claimant wrote about itself. Free-text claims aren't worth parsing (practitioners building
agent-verification tooling report the same dead end after exhausting dozens of patterns); only a
fixed-format declaration checked against independent state — git history, a session log — holds up.

**The receipt mechanism.** A short-lived nonce is minted at the start of a multi-step procedure; each
step appends its own receipt line under that nonce as it completes (`<run-id>\t<step-id>\t<outcome>`),
written by the step, not narrated by the agent afterward. The gate guarding the final irreversible
action (a merge, a release, a `gh pr create`) denies unless every expected step id is present under the
CURRENT run's nonce AND the last step's recorded outcome matches live state (e.g. a SHA against HEAD) —
closing the "checks passed, then one more fix landed unchecked" window. A bare `touch` of a sentinel
file, a partial run, or a stale receipt from an earlier commit all fail by construction, not by
convention.

**Why this, not just a stop-and-ask.** A human stop-point before an irreversible step is one valid
design (recent agent-verification tooling takes this shape); a content-checked receipt is another —
mutation-tested coverage checks and fixed-format completion declarations verified against independent
state are two more. Pick whichever fits the workflow's cost of a false pass; the receipt form earns its
keep when the check has to run unattended between steps, not just once at the end.

**Reference implementation.** `tools/pre-pr-gate.sh` + `commands/polish.md` implement this pattern for
Keel's own pre-PR flow and ship to every adopter; the gate itself is a separate, explicit opt-in step
(`tools/install-pre-pr-gate.sh <repo>` — a hook changes what a session can do without asking each time,
so it's never auto-wired). Read them for the concrete receipt format, not this summary. See *Enforcement
mechanics* below for the companion rule on what a gate's error text may and may not say.

---

## Enforcement mechanics — never name the bypass in the error text

An enforcement mechanism (commit hook, gate, guard, CI check) is read by an **agent**, not just a human — so
any bypass instruction printed in its block/error message becomes a step-by-step exploit the agent follows to
get unblocked. It optimizes for "make this pass," and a message that names the escape hatch hands it the
recipe. Felt twice: `pre-pr-gate` once printed the literal `touch …` unlock command and the agent ran exactly
that; `secret-guard`'s block message named `.secret-scan-allow` and an agent (being tested on Cursor) wrote
that allowlist to commit a secret-shaped key.

**How to apply:**
- Say WHAT is wrong and WHAT to do at the task level ("this looks like a secret — remove it"), never HOW to
  defeat the check (the exact bypass token, file, or flag).
- A legitimate human escape hatch must not be agent-usable in-band: reject an allowlist entry added in the
  same change as the thing it unblocks; make sentinels content-derived (a SHA of real state), not a touchable
  file; keep any bypass command out of the agent's Bash allow list.
- Design assuming a capable agent actively routes around the guard — the guard, not its prose, is the
  enforcement. Deterministic gates enforce; loaded prose only nudges — and a gate that advertises its own
  bypass isn't one.

---

## Changelog

When a project reaches a milestone (end of a session with big changes, infra upgrade, new version), add an
entry to a `## Changelog` section of the project `CLAUDE.md`. Format: `| YYYY-MM-DD | what changed — one line |`.
No need for an entry per commit — only for significant milestones (the git log carries the rest).
