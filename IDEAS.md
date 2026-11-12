# Ideas — raw-idea staging tier

Keel's own instance of the tier `templates/IDEAS.md` describes: raw ideas about Keel itself, parked so
they aren't lost to a chat transcript, and kept out of the always-loaded surfaces and the backlog until
one earns a next step. Format: `- [date] idea — context (where it came from)`. Reviewed at `/wrap`'s
red-flag sweep (in its mechanized outcome set since PR #213) and periodically — promote to the
backlog once actionable, or drop explicitly. (Ideas != Backlog: a next step may never materialize,
and that's fine.)

## Ideas

- [2026-07-20] **Contributor-docs line: agent commit trailers vs the SEC4 commit-message scan** — felt
  on PR #106: a coding harness's session-URL commit trailer matched the key-shape patterns and the CI
  scan blocked the push; resolved by stripping the trailer (no allowlist, per the gate's own rule). One
  line in contributor-facing docs would save the next agent session the rediscovery.
  **Dropped 2026-09-06 (first `/groom` G4(b) pass) — mooted:** `SECURITY.md` now states that the
  guard blocks agent session-metadata trailers, and `docs/reference.md`'s secret-guard row says the
  same; there is no `CONTRIBUTING.md` to carry a third copy, and a third copy is the sync-drift class
  dir #166 names. Nothing left to write.
- [2026-07-20] **The ladder from the `--no-git` trim to real always-on modules** — from the PR #106
  design discussion: the strip-generation approach was chosen over two-module composition (CORE +
  `CORE-GIT.md`, one `@import` line each) to keep the majority path unchanged; if a *third* optional
  always-on module ever materializes, switch to composition — the `KEEL-GIT` markers already fix the
  module boundary, so the migration stays mechanical. Next module candidate: the Memory section
  (`ADAPTING.md` already tells tools without cwd-keyed auto-memory to drop it). Not actionable until a
  second real module shows demand. **Reviewed 2026-09-06 (first `/groom` G4(b) pass): trigger not
  fired — no second always-on module has been asked for; kept, with this stamp so the next pass can
  see it was judged rather than skipped.** **Re-reviewed 2026-09-11 (0.10.1 groom, G4(b)): still not
  fired; kept.** **Re-reviewed 2026-09-16 (0.10.2 groom, G4(b)): still not fired — `ADAPTING.md` names
  no second always-on module and no adopter has asked for one; kept.** **Re-reviewed 2026-09-20
  (0.11.0 groom, G4(b)): still not fired — `ADAPTING.md` unchanged on this point, no adopter request
  in the 0.10.2 cycle; kept.** **Re-reviewed 2026-09-23 (0.12.0 groom, G4(b)): still not fired in the
  0.11.0 cycle; kept.** **Re-reviewed 2026-10-09 (0.16.0 groom, G4(b)): still not fired through the
  0.12.0–0.15.0 cycles — `ADAPTING.md` names no second always-on module; kept.**
  **Re-reviewed 2026-10-12 (0.17.0 groom, G4(b)): still not fired in the 0.16.0 cycle — no second
  always-on module asked for; kept.** **Re-reviewed 2026-10-20 (0.18.0 groom, G4(b)): still not
  fired in the 0.17.0 cycle; kept. Where it would fire first: dir #253's §1 layer model, if that
  ticket runs.**
- [2026-07-23] **openwiki (langchain-ai/openwiki) — auto-generated CLAUDE.md/AGENTS.md, opposite bet from
  Keel's manual curation** — surfaced while triaging six repos from an Instagram post; the only one that
  overlapped with Keel's domain (the other five dropped without action). OpenWiki synthesizes
  `CLAUDE.md`/`AGENTS.md` + a full wiki from the codebase and external sources (Notion, Gmail, X, HN) via
  an LLM agent, with CI-scheduled upkeep and Mermaid diagrams —
  vs. Keel's bet on deliberate human authorship (`PRINCIPLES.md` P0, accumulation). Possible next step:
  read `PRINCIPLES.md` / `ADAPTING.md` and decide whether (a) auto-draft-then-manually-refine is worth a
  `tools/` script (seed a first-pass CLAUDE.md from openwiki, hand off to Keel's normal flow), (b)
  CI-scheduled-upkeep or the Mermaid-diagram-map are worth borrowing standalone, or (c) the manual-only
  stance is deliberate and this gets dropped with that reasoning recorded.
  **Decided 2026-07-23 — (c): nothing ported; the manual-curation stance is deliberate. Entry closed.**
  Checked against `PRINCIPLES.md` and `ADAPTING.md`; four independent reasons, any one sufficient:
  (1) an auto-draft script would be the first model-calling tool in `tools/`, whose documented contract
  is "plain Bash + git — they never call a model" (`ADAPTING.md`); breaking that breaks the layer's
  substrate-independence, which is its whole point. (2) The auto-draft-then-refine value already exists
  in Keel's own shape: `/init-project` scaffolds the skeleton and the session agent drafts from the live
  codebase with the human judging in the loop — same outcome, P1-compliant, no new tool; and no adopter
  has asked for a batch variant, so building one fails P4's felt-friction gate. (3) CI-scheduled
  regeneration makes the always-loaded context volatile and removes the human verifier — directly
  against P3 ("stability of the loaded set") and P1 ("the system that can hallucinate cannot be the
  sole judge"). (4) OpenWiki's product is a codebase *description* — derivable-from-code content Keel
  deliberately keeps OUT of curated context (a Keel `CLAUDE.md` banks decisions, constraints, and felt
  incidents — exactly what code cannot show); the Mermaid map falls under the same rule, derivable on
  demand by any session that needs it. Reopen trigger: a real second consumer (P0) asking for cold-start
  bootstrap of a large existing codebase — that is felt friction; revisit option (a) then.
- [2026-07-23] **Positioning: the derivable-context layer is commoditizing — sharpen the pitch around
  the non-derivable layer** — follow-up to the openwiki entry above. Auto-generation tools (openwiki
  and its kin) compete for the same `CLAUDE.md`/`AGENTS.md` slot and may teach the market that
  "context" means scheduled auto-generation. Not a functional threat — they fill the slot with the
  derivable layer while Keel banks the non-derivable one (reason (4) above), and the two even compose —
  but a positioning one: the adopter who believes the generated wiki *is* their context never hears the
  difference. By P0's own frame the trend is favorable — commoditizing the derivable layer raises the
  relative value of captured non-derivable capital — but only if the pitch says so out loud. Possible
  next step: make "Keel keeps what cannot be derived from the code" a load-bearing line in the README /
  pitch surfaces. Promote to `BACKLOG.md` once a concrete pitch-surface edit is picked.
  **Promoted 2026-09-06 (first `/groom` G4(b) pass) to dir #400** — the concrete edit is picked
  there (one load-bearing README line), and it sits in the value-pitch lane the v0.9.0 sprint is about.
- [2026-08-12] **Session-handoff artifact — a candidate fix for the named L4 mid-task-checkpoint gap** —
  from triaging a practitioner's agent-pipeline video (transcript supplied in chat; the pipeline builds
  on a public skills repo — grill/wayfinder/handoff — links live in the author's channel, repo not
  independently verified). Their `handoff` skill writes a small MD artifact on interruption or
  session/model switch: what was achieved, where work stopped, which artifacts carry forward — the
  explicit principle being *"between sessions, only artifacts pass"* (code + MD files), never raw
  context. This is precisely `FRAMEWORK.md`'s known gap "L4 has no mid-task checkpoint, so a
  long-running ticket interrupted mid-session loses its plan state" — and Keel already has a narrower
  cousin (`/polish`'s same-SHA hand-off note via `tools/pre-pr-gate.sh handoff`), so the shape is
  proven in-house. Possible next step: a ticket-level checkpoint convention (where the note lives, what
  three fields it carries, when `/go` writes and consumes it) — P2-native, no new tool required.
  **Promoted 2026-09-06 (first `/groom` G4(b) pass) to dir #401.** **Shipped 2026-10-06 (dir #401,
  `tools/go-handoff.sh`); the gap quoted above is closed where a kept checkout exists, and
  `FRAMEWORK.md` now names only the copy-mode remainder, which dir #691 has since decided to keep (copy mode needs a kept checkout)** (the 0.15.0 groom).
- [2026-08-12] **Interview-loop refinements: frontier rounds, a closing shared-understanding gate, and
  prototype-resolved forks** — same video triage. Three mechanics their "grilling" skill adds over
  `FRAMEWORK.md`'s Interview loops section: (1) *frontier questions* — each round batches exactly the
  questions for which enough context has accumulated, then rebuilds the decision tree from the answers
  before computing the next round (a crisper operational rule than "sequential when branching, batched
  when independent" — it unifies the two); (2) the loop ends with an explicit *shared-understanding
  confirmation* — the agent restates the agreed behavior and the human confirms or reopens, so passive
  skim-and-agree on a generated plan is structurally prevented; (3) a fork that can't be resolved in
  text (UI layout, state-machine logic) is resolved by a *disposable prototype artifact answering one
  question* — 3–5 radically different variants, not one variant in three colors. All three are
  section-sized edits to the existing Interview loops rail, not new machinery.
  **Promoted 2026-09-06 (first `/groom` G4(b) pass) to dir #402, bundled with the two entries below
  from the same triage — one `FRAMEWORK.md` touch, three section-sized edits.**
- [2026-08-12] **Ticket decomposition rails: fits-one-fresh-session sizing, behavior-named vertical
  slices, and ticketed design stages** — same video triage. Their pipeline sizes every ticket to fit
  one fresh-context session *including tests, review, and report* (context budget as the splitting
  criterion — even asking the agent "will this ticket fit one context?" at grooming time); names
  tickets by the observable behavior they add, never by layer ("DB schema", "the API") — so every
  ticket lands as a verifiable vertical slice with blocking dependencies named; and when the *design
  itself* exceeds one session ("wayfinder"), the design questions are themselves ticketed and each gets
  its own interview session, converging into one spec with an explicit out-of-scope-with-reasons
  section. Keel's `/go` already assumes a groomed ticket with a done-criterion; these are the missing
  grooming-side rules that make that assumption hold. Candidate home: a short decomposition subsection
  near the Loop model (L4) in `FRAMEWORK.md`. **Promoted 2026-09-06 to dir #402 (bundled).**
- [2026-08-12] **Phase-based effort routing as a complement to task-difficulty routing** — same video
  triage. `FRAMEWORK.md`'s model-selection rail routes by task difficulty; their pipeline routes by
  *pipeline phase*: design/spec sessions run at high effort, ticket implementation at low effort —
  because a well-groomed ticket has all decisions pre-made, so implementation is execution, not
  reasoning — and independent review back at high effort / a strong model. The underlying claim is
  P3-flavored and worth stating even without adopting their pipeline: *decomposition quality is what
  buys the right to cheap implementation passes* — the better the grooming, the lower the effort tier a
  ticket needs. One added sentence in the model-selection section would carry it. **Promoted
  2026-09-06 to dir #402 (bundled).**
- [2026-08-17] **Capability-split delegation pipeline: read-only analysis fans out to cheap spawned
  subagents, gated mutation stays in serialized operator sessions** — surfaced designing drydock
  (dir #165) and field-tested by its run 1 the same day. **Promoted the same day to dir #171** —
  the run's empirics fired this entry's own promotion trigger; the pattern, the measured field test,
  the "wrap duties are centralized" worker-marker lesson, and the design mandate all live in that
  ticket now.
- [2026-09-20] **A "System One" leg for keel's triage layer — TypeSafe AI's Jev** — surfaced while
  reading the Jev launch (a non-autoregressive model: state + typed questions in, typed answers with
  calibrated probabilities out, ~70–500 ms, output tokens free; early access opened 2026-09-20). Keel's
  decision surface has three layers, and Jev fits exactly one: NOT the deterministic gates
  (`pre-pr-gate`, `doctor`, `secret-guard` must stay bash-only, offline, reproducible — a probabilistic
  network call there is a regression), NOT the deep review legs (find-rate tracks reviewer novelty and
  depth per `docs/verification-economics.md` §2, and Jev's output is itself a claim, never a
  verification), but the TRIAGE middle that today is either a noisy heuristic or a full LLM round.
  Candidates, best first: (A) finding triage in delta-audit/drydock — `{new|known class, class_id,
  severity, duplicate-of}` with a confidence, escalating below-threshold items to a human; past
  adjudications in `private/audit/` are labeled data, so the experiment is checkable; (B) escalation
  in the audit harness — a cheap "does this hunk plausibly carry a defect of class X?" pass to decide
  which files earn a `deepseek-reasoner` round (it exhausts its completion budget on reasoning), as
  prioritization, never a stopping rule; (C) a second-stage filter over `tools/self/prose-drift.sh`'s
  WARN signal, which self-describes as unable to tell a truncated edit from a long sentence.
  Weaker: `/wrap`'s red-flag classification (volume too low to matter), backlog duplicate detection
  (context size). NOT a candidate: `keel-impact` — the "model judges with citations, script counts"
  split is what makes the number honest; a cheaper judge loses the citations. Constraints: keel is
  publication-first and tool-independent, so any Jev use is an opt-in leg (like the Gemini G6 leg and
  the DeepSeek harness — `private/` or a flagged tool degrading to "as before" without a key), never
  in the always-on path or `install.sh`; key via env. Next step, per dir #344's lesson (measure a
  proposed checker's noise before building it): one evening's experiment on candidate (A) — run
  already-adjudicated findings through Jev, score agreement with the human verdict AND calibration
  (is p>0.9 right ~90 % of the time). Calibrated → (B) and (C) become near-free; not → close with a
  number, not an opinion. **Promoted 2026-09-21 to dir #613** (spec-ready, a design pass): the
  experiment as designed there, with the API verified live against an early-access key — `jev-latest`
  → `jev-1.13.0`, ~1 s per request, a 72 KB state accepted, a $5 monthly credit that covers the whole
  run ~500×.
  **Outcome (2026-09-21, dir #613 phase 1):** NOT calibrated — closed with the number, no phase-2
  ticket. 43 already-adjudicated findings from 4 delta runs, both state conditions (finding-only /
  finding+hunk): REFUTED-recall 0.636/0.545, REFUTED-precision 0.280/0.261, ECE 0.291/0.313 — below
  bar (≥0.70 / ≥0.60 / ≤0.10) on every axis, both conditions. `holds`'s class-conditional means are
  statistically indistinguishable (0.421 vs 0.448) — no signal, not a threshold problem. `severity`:
  0% exact agreement across 32 scored rows despite ≈95% stated confidence — confidently wrong rather
  than usefully uncertain. Candidates (B) and (C) inherit this result per this entry's own framing
  and are not separately tested. Full report:
  `private/audit-harness/jev/runs/20260921T122220Z/REPORT.md`; narrative:
  `private/audit/RUNS.md`'s Jev section.
- [2026-11-10] **A quiet mode for the test runner: no `ok` lines, keep `FAIL` and each file's summary**
  — from evaluating reslop (github.com/tshemsedinov/reslop), whose `reslop t -- <cmd>` prints only
  failures plus a short summary and names the raw log for an agent to read when a detail is missing.
  Keel's suite is the opposite: `tests/lib.sh` `pass()` prints one `  ok` line per assertion and
  `tests/run.sh` echoes every file's whole log; the test files hold ~723 `pass` and ~1171
  assertion-helper call sites (`assert_*`, `pin`, …) across 181 files, so a full run prints on the
  order of 2k `ok` lines (call sites, not a run count — loops add more). Next step before any
  ticket: measure whether agent sessions actually take that output in whole (transcript corpus: the
  size of Bash results from `tests/run.sh` runs, and how often they are already cut by `tail`) — the
  suite usually runs in the background and is read by its tail, so the saving may be small. If built:
  `run.sh`'s own scans of each log (the `command not found` backstop, `guard_summary_owed`) must still
  see what they read. reslop's reducer itself is no fit: a Node dependency, and it parses only
  eslint, tsc, prettier, jest, TAP and `node --test` output.
- [2026-11-10] **A read-only worktree overview across every registered project** — from the same
  evaluation: `reslop <folder>` shows the repositories in a folder as tiles, each with its git
  worktrees. Keel has the per-repo half: `tools/branch-cleanup.sh` grades one repo's branches and
  worktrees (AUTO / ASK / FLAG). The idea: one view over every project in `INSTANCE.md`'s Projects
  table — per project its worktrees, their branch, merged or not, dirty, live — so stale worktrees
  across the fleet are visible at once. Next step: check whether looping `branch-cleanup.sh`'s
  report over the registry already gives it, before any new tool.
- [2026-11-12] **A value bar for writing tests: four questions before a test is added** — from
  evaluating bb (getbb.app, github.com/get-bb/bb), an agentic IDE whose repo carries a `test-audit`
  skill (`.bb/skills/test-audit/SKILL.md`). Before adding a test the agent answers: which behavior or
  contract it protects; which believable regression makes it fail; why existing coverage misses that
  regression; and whether it needs a production seam no real caller uses (if so, test at the real
  boundary instead). The skill also lists junk patterns — an expected value produced by the code under
  test, a mock that implements the asserted behavior, a negative control that passes for an unrelated
  reason, a test name that promises more than its input exercises — and allows deleting a test only
  after a mutation shows a kept test still catches the bug it caught. Keel has the other half:
  `FRAMEWORK.md` "Code conventions" says no feature ships without tests, and "Contract-first"
  mutation-tests a guard's negative path; nothing guards against a test that adds run time and no
  protection. Caveat: keel's `pin()` tests are exact-string greps, a shape bb counts as junk unless it
  guards a user-facing contract — so a keel version must keep pins on load-bearing prose. **Where it
  would live (2026-11-12):** bb's three modes map onto three keel homes, never one command. The
  authoring gate → `commands/go-guide.md` I2, where `/go` writes its tests and which already holds
  question 2 ("a test that passes before your change tests nothing"); add questions 1, 3 and 4 there,
  plus the generic sentence in `FRAMEWORK.md` "Code conventions" for sessions outside `/go`. The
  deletion rule (mutation proof before a test goes) → a one-off audit ticket over keel's own suite,
  not a command. Not `/polish`: its review receives only the `/code-review` args, so a junk-pattern
  mandate cannot reach it, and a new step there taxes every PR. Next step: put the four questions to
  one recent PR's added tests and count the failures; a few → the I2 lines and the sentence; many →
  the audit ticket too, starting from the slowest test files.
- [2026-11-12] **A bash gate in front of a scheduled agent: wake the model only when there is work**
  — same evaluation (bb's "Run an agent on a schedule" guide). A scheduled job there can be a plain
  script that starts an agent only when it finds work (CI went red, a new review comment) and prints
  nothing otherwise; a silent exit is recorded as `skipped`, an error as `failed`, and three failures
  in a row pause the job. The shape fits keel's split — `tools/` is plain Bash that calls no model
  (`ADAPTING.md`; the opt-in vendor review is the one exception), and model time is spent only past
  the gate. Keel counts consecutive failures for one check (`tools/keel-check.sh`), but no doc
  describes the scheduled-run shape. **First consumer (operator, 2026-11-12): the release manager's
  night.** `docs/release-management.md` R11 has the manager sweep on a wall clock because a session
  killed by a 429 or wedged on a wait sends no event; in practice (the 0.18.0 close's lesson) that
  wake is a backgrounded `until` loop (~60 min), after which the manager re-reads its whole context
  and sweeps every row, found something or not. The gate would replace that loop: one background
  bash watch that exits only on the first event the manager cannot otherwise hear — a watched PR's
  CI concluded, a live worker's newest transcript line carries `rate_limit` or another
  API error, an open row's transcript silent past N minutes — or on a long heartbeat cap, and prints
  that event as its one line. Scope: the gate only decides WHEN the manager wakes; the merge stays
  the manager's under R14 (freeze line, ACK, head pin, seam review, the pre-PR gate's merge rule),
  and night launches stay refused (R3), so a wake can merge, sweep and message idle workers, never
  start a session. Next step: from the last overnight release's manager transcript, count the night
  wakes that found nothing and what each cost; mostly empty → design the watch as a dir ticket.
- [2026-11-12] **A per-project "verify it live" recipe, a draft until it has been run once** — same
  evaluation (`.bb/skills/create-verification-skill`). bb generates, per repo, a recipe for driving the
  real app: launch it in isolation, a read-only check that the right instance is up, how to drive each
  feature, where evidence goes, cleanup — with each feature marked live-verified, source-only or
  blocked, and the recipe counted as a draft until a session has followed it end to end. Keel's
  `templates/project-CLAUDE.md` asks only for build/test commands, and CORE's Verify discipline says
  not to pass a smoke off as full verification — but a session in a project with a UI or a server
  re-learns each time how to see a change working. Candidate: an optional "Verify live" section in
  the project template (launch, ready signal, one drive step, cleanup), written by `/keel-setup` or by
  the first `/go` that had to work it out, and `/go`'s I8 report saying which of the three states its
  check reached. Next step: look for adopter projects that already keep such notes in their
  `CLAUDE.md` — felt demand (P4) before a template section.
- [2026-11-12] **A committed list of the gitignored files a new worktree needs** — same evaluation
  (bb's `docs/worktrees.md`). bb reads a `.worktreeinclude` file at the repo root (gitignore syntax)
  and copies the matching untracked files into each new worktree, then runs optional committed setup
  and teardown scripts. `docs/parallel-sessions.md` names both failure modes — a file symlinked into
  every worktree is shared by every session, and a gitignored file never linked is missing or lost —
  but gives no way to declare which files a worktree needs; keel bridges only `CLAUDE.md`, by symlink.
  A list makes the choice explicit per file: copy (isolated, but edits strand when the worktree goes)
  or symlink (live, but concurrent sessions collide). TO VERIFY first: whether Claude Code already
  honors `.worktreeinclude` for the worktrees it creates — if it does, this is one paragraph in
  `docs/parallel-sessions.md` pointing at it, not a tool.
