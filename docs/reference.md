# Reference: what's in the box

Every file, tool, and command — grouped, one line each.

## 📖 Core files — advice, applies when read

| File | What it is |
|---|---|
| [`PRINCIPLES.md`](../PRINCIPLES.md) | The lasting foundation. Read it for big, hard-to-undo decisions. |
| [`FRAMEWORK.md`](../FRAMEWORK.md) | The reusable how-to: load-a-little-always, registry-as-index design, git and code conventions. |
| [`CORE.md`](../CORE.md) | The always-on rails alone — placeholder-free. On Claude Code, import it live (`git pull` refreshes it); elsewhere the template embeds it verbatim. |

## 📝 Templates — you fill them in once

| File | What it is |
|---|---|
| [`templates/CLAUDE.md`](../templates/CLAUDE.md) | The small always-on file: `CORE.md` + your personal sections (file map, preferences). |
| [`templates/INSTANCE.md`](../templates/INSTANCE.md) | Your private layer: hardware, available models, project list. |
| [`templates/project-CLAUDE.md`](../templates/project-CLAUDE.md) | Per-project notes. |
| [`templates/LEARNINGS.md`](../templates/LEARNINGS.md) | Holding place for tips not yet worth a full rule. |
| [`templates/IDEAS.md`](../templates/IDEAS.md) | Free-form scratchpad for raw ideas — the lowest-commitment staging tier, one step before `LEARNINGS.md`. |

## ⚙️ Tools — run by themselves, zero context cost

| Tool | What it does |
|---|---|
| [`keel`](../keel) | One CLI over the rest, installed to `~/.claude/bin` (the install summary prints a one-line PATH hint if that dir isn't on your PATH): `keel install \| sync \| doctor \| audit \| init \| check \| tokens \| uninstall \| version \| help`. A thin dispatcher, so it works from any directory. |
| [`bootstrap.sh`](../bootstrap.sh) | The `curl … \| sh` entry point: fetches the repo (git clone, or a tarball on a git-less machine) and runs `install.sh`. |
| [`install.sh`](../install.sh) | One-command setup: copies (or, with `--link`, symlinks) the always-on files and turns on secret-guard. Safe to re-run; never overwrites your own files — bar one consented exception: a terminal re-run offers (default no) to refresh only the rails block inside `CLAUDE.md`/`AGENTS.md`, backing the file up first. Also places Keel's own `docs/` beside `FRAMEWORK.md`. A drifted Keel-owned file (`FRAMEWORK`, `PRINCIPLES`, a command, a doc) refreshes automatically when it provably is Keel's own untouched older release, else it asks (or flags non-interactively); `--force` takes over a drifted/refused Keel-owned file anyway, backed up first — never your own files, hooks, or `settings.json`, and a symlink Keel did not make is never replaced. On a machine with no git projects, `--link --no-git` trims the code/git rails from the always-on core (sticky across re-runs; `--with-git` restores). |
| [`uninstall.sh`](../uninstall.sh) | Reverses `install.sh` (`keel uninstall`): removes only Keel-owned content, backs up what it removes, leaves your own files and the machine-global secret-guard alone. Mirrors install's mode flags — `--home DIR`, and `--codex` for an `install.sh --codex` install (`~/.codex`, `AGENTS.md`); a run names an install of the other mode it finds rather than leaving it behind, and refuses when pointed at the other mode's home (most of what it removes is shared, so it would half-dismantle that install). |
| [`tools/secret-guard/`](../tools/secret-guard/) | Git hook: blocks key-shaped secrets (`ghp_`, `AKIA…`, `sk-…`, `glpat-`, …) on commit/push — and, opt-in, your listed personal data, even inside UTF-16 binaries. Also blocks agent session-metadata trailers on push and scans annotated-tag messages. |
| [`tools/public-audit.sh`](../tools/public-audit.sh) | Pre-go-public scan of files **and git history**: commit/tag identities and declared tokens are a hard stop; emails/home paths/Cyrillic and agent-session metadata are flagged for review (a bare personal name has no built-in pattern — to catch one, pass `--token` or put a `token:` in a **gitignored** `.public-audit`, never a committed one). |
| [`tools/doctor.sh`](../tools/doctor.sh) | Checks a setup for missing pieces (`--install` audits the linked install). |
| [`tools/init-project.sh`](../tools/init-project.sh) | Scaffolds a new project and registers it in `INSTANCE.md`. |
| [`tools/register-project.sh`](../tools/register-project.sh) | Adds existing project folder(s) to the `INSTANCE.md` list; safe to re-run. |
| [`tools/keel-impact.sh`](../tools/keel-impact.sh) | Optional per-project tracker behind `/keel-score`: an auditable ledger of cited events. Projects scaffolded by `init-project` are tracked by default (`--no-impact` opts out); an existing repo is off until `keel-impact.sh enable <dir>`. Upgrading from a pre-0.7.2 install where the ledger still lives in-tree (`.keel/`)? Run `keel-impact.sh migrate [dir] [--dry-run]` to sweep it (main checkout + every linked worktree) into the external store — an untracked source is merged and removed automatically, but a **tracked** legacy file is left in place with the choice (keep / `git rm --cached` / rewrite history) printed for you to make. Each `enable` records a durable `keel.impactStore` value in the repo's own local git config (dir #630), so a store entry that later goes missing (a wiped or moved state root) is refused with a named "store entry is missing" error — never a silent restart at zero — and recovered with `keel-impact.sh restore FROM_DIR`, or started fresh on purpose with `enable --restart`. `KEEL_HOME` names the harness home keel installs into; keel's own state lives in `$HOME/.keel`. |
| [`tools/state-root-migrate.sh`](../tools/state-root-migrate.sh) | Moves keel's durable stores (impact, read-trace) out of the harness home into `$HOME/.keel` (dir #637), leaving one compat symlink per moved entry; `install.sh` runs it on every run. `--from HARNESS_HOME` picks the home to move out of, `--dry-run` prints the plan. Never clobbers: an entry already at the target is kept and reported with a merge hint. To go back, delete the symlinks and move the directories back. |
| [`tools/install-secret-guard.sh`](../tools/install-secret-guard.sh) | Wires the secret-guard hooks: `--global` sets a machine-wide `core.hooksPath`; `<repo-path>` vendors a self-contained copy into one repo. Never clobbers a non-Keel hook without `--force` (which backs it up to `<hook>.pre-keel.bak`, or the next free `.pre-keel.2.bak` if a file appears there mid-run), never writes through a symlinked hook, replaces a hard-linked one by rename so its other name keeps its bytes, and decides "Keel's hook" by an exact marker line. `--global` refuses a `core.hooksPath` that a conditional `[includeIf]` include sets elsewhere, unless `--force`. A `core.hooksPath` set at any scope, the empty value included, is yours: `--global` refuses it without `--force`, and `--global --force` records the exact value it replaces (an empty one stays empty) and refuses a `hooksPath` with no value at all; `--global --uninstall` restores it (or unsets Keel's). `--where <repo>` / `--where --global` print, read-only, which hooks dir an install writes, which one git actually reads, and (`set=`) whether any scope sets a `core.hooksPath` — the one answer `tools/doctor.sh` and `install.sh` Verify also use. |
| [`tools/keel-check.sh`](../tools/keel-check.sh) | The stop-mode floor: run a task's verification command through it and repeated failure of the same check prints a STOP-and-diagnose banner instead of letting an agent spiral. `tools/keel-check-gate.sh` is the opt-in hard-veto half — register it as a Claude Code `PreToolUse` hook (plus `KEEL_CHECK_VETO=1`) to *block* a commit while your declared check is still red, instead of only nudging. |
| [`tools/token-report.sh`](../tools/token-report.sh) | `keel tokens`: a read-only report of where your Claude Code token spend went, for a project or a single session — fan-out, cold prompt-cache resumes, and repeated file reads, named as patterns rather than only totalled; `--context` prints one line, the session's last-turn context against `/polish`'s compaction threshold. See [`docs/token-economy.md`](token-economy.md). |
| [`tools/branch-cleanup.sh`](../tools/branch-cleanup.sh) | Classifies local branches after merges into AUTO/ASK/FLAG confidence tiers so post-merge cleanup never blanket-deletes live work. |
| [`tools/pre-pr-gate.sh`](../tools/pre-pr-gate.sh) | The `/polish` pre-PR gate: a Claude Code hook that blocks the agent's own `gh pr create` until `/polish` (simplify + tests + a depth-matched review) has run cleanly on the current commit. It also denies a `git push` that disables the pre-push secret scan in a form the hook can see (`--no-verify`, `-c core.hooksPath=…`, an inline `GIT_CONFIG_GLOBAL=…`/`HOME=…` prefix); a bypass it cannot see is left to the CI scan. Ships with `commands/polish.md`, but is never auto-wired — see `install-pre-pr-gate.sh` below. |
| [`tools/install-pre-pr-gate.sh`](../tools/install-pre-pr-gate.sh) | Wires the `/polish` gate's 6 hooks into a project's `.claude/settings.json` (project scope, the default) or `--global` (every repo; `--home DIR` targets the same home an `install.sh --home DIR` install used). Opt-in and separate from `install.sh` on purpose: a hook changes what a session can do without asking each time. Never clobbers a hook already on the same slot — it appends beside a foreign one, where `install-secret-guard.sh` refuses without `--force`. |
| [`tools/machine-watch.sh`](../tools/machine-watch.sh) | The sandbox rail's detector (dir #437): fingerprints the machine-global files a live check must never touch (git global/system config, the global hooks dir, ssh config, shell rc — alert tier; harness settings, `known_hosts`, `~/.config` — quiet tier) and reports what changed. `hook` is Claude Code hook mode (never blocks, always exits 0); `snapshot NAME` / `check NAME` do the same by hand on any harness. Baselines live in `$HOME/.keel/machine-watch`; your own paths go in `$HOME/.keel/machine-watch.paths`. It cannot say who made a change, only that it happened. An alert-tier report also raises one native OS notification (macOS `osascript`, Linux `notify-send`; the hook banner is not rendered in the Claude desktop app) — off with `KEEL_MACHINE_WATCH_NOTIFY=0`, replaceable with `KEEL_MACHINE_WATCH_NOTIFIER`. |
| [`tools/install-machine-watch.sh`](../tools/install-machine-watch.sh) | Wires the watcher's 4 hooks into a project's `.claude/settings.json` (project scope, the default) or `--global` / `--home DIR`. Opt-in and separate from `install.sh`; appends beside a hook already on the same slot; `--uninstall` removes exactly its own; never writes a deny rule (the recipe in [`delegation.md`](delegation.md) is documentation only). |
| [`tools/drydock/inventory.sh`](../tools/drydock/inventory.sh) | Freezes a [drydock](drydock.md) run's scope as code: measures the tracked prose and code surface (markdown whole-file, shell comment blocks, whole shell code) at one baseline commit and derives the per-auditor batches. Refuses a dirty tree or a HEAD that isn't the baseline — with no bypass flag — because an inventory measured off the baseline scopes the whole audit against a commit nobody chose. `--prev <sha>` scopes an incremental run to what changed since the last one. `--paths` prints a bare path list instead of the report, for a caller like `export.sh` below. |
| [`tools/audit-packet/export.sh`](../tools/audit-packet/export.sh) | Builds a leak-gated packet for [drydock](drydock.md)'s external leg: a caller-supplied file list (`inventory.sh --paths`, or `delta-audit/derive.sh`'s file list), chunked with a `PROBE.md` window-measuring chunk 0 and a `PROMPT.md` role prompt, scanned by the secret-guard leak gate twice — once before anything is written, once more over the fully assembled packet dir. Refuses a dirty tree, a HEAD that isn't `--baseline`, or any leak-gate hit at either pass — no bypass. |
| [`tools/audit-packet/import.sh`](../tools/audit-packet/import.sh) | Imports an external auditor's replies (chunked, `export.sh`'s own packet; or unchunked, a tooled reader's single reply) into drydock's ordinary `<slug>-audit.md` file contract, so phase 2 verifies them exactly as it verifies a subagent's findings. Refuses a chunk that doesn't quote its own `CHUNK-END` line as truncated. |
| [`tools/changelog-section.sh`](../tools/changelog-section.sh) | Prints one released version's `## [x.y.z]` section out of your repo's own `CHANGELOG.md`, so cutting release notes is one command instead of a hand-scroll (`--digest` prints just the opener and the `### ` headings; `--edit <version> <notes-file>` composes the curated notes-file in `$EDITOR` directly). An input to the release note, which stays a curated digest of the section — see `docs/publishing-checklist.md` §4. |
| [`tools/pipeline-canary.sh`](../tools/pipeline-canary.sh) | A sandboxed operator ritual for auditing your own `/polish` → gate pipeline: drives a real dry run (or a scripted, no-model `demo-bypass`) in an isolated toy repo + `HOME`, so you can check the gate still denies a fabricated review claim. |
| [`tools/delta-audit/derive.sh`](../tools/delta-audit/derive.sh) | Mechanically derives a release delta audit's universe from git history: the range's file list, a file→PR seam map, an empty-verdict ledger skeleton (in pinned read order — seams and behaviour-with-a-rail code first, prose last), and a run-record stub. Its closure check refuses when a squash- or rebase-merged PR leaves files unattributed, so a hand-drawn universe can't silently under-count. The full procedure that adopts it is [delta-audit](delta-audit.md). |
| [`tools/vendor-review.sh`](../tools/vendor-review.sh) | A scriptable cross-vendor reading leg: leak-gates a bundle with `secret-scan.sh` (no bypass), then hands it to a swappable `--client` script per vendor CLI, one round dir per launch. [`tools/vendor-review/agy.sh`](../tools/vendor-review/agy.sh) (Google's Antigravity CLI, reaching Gemini) ships as the worked client. See [`docs/vendor-review.md`](vendor-review.md). |
| [`tools/go-handoff.sh`](../tools/go-handoff.sh) | The `/go` handoff note (dir #401): `write`/`read`/`clear` one small three-field note (`done`, `next`, `carry`) per ticket, in `$HOME/.keel/tmp/go-handoff/`, so a `/go` session that stops before `/polish` — context limit, crash, a deleted worktree — does not take its plan with it. Keyed by the ticket's canonical id, shared by every worktree of the repo; `read` ends with a `verdict:` line (`fresh`, `behind n`, `ahead n`, `unrelated`, `unknown`) saying how far HEAD has moved since. A dated hint, never a gate; never committed; notes older than `KEEL_GO_HANDOFF_PRUNE_DAYS` (30) are pruned. Needs a kept checkout, so a copy-mode install has no note. |

*secret-guard is a safety net for known key shapes plus your listed literals — not a catch-all. It won't
catch an arbitrary AWS secret key, a JWT, or a password.*

*Maintainer-only, not shipped by `install.sh`: `tools/self/` (this repo's own structural self-checks —
dead references, ship-skip-list sync, doc staleness) and `tools/stamp-release-bootstrap.sh` (stamps a
release's `bootstrap.sh` asset, run by hand per `docs/publishing-checklist.md`).*

## Commands (`commands/`)

| Command | What it does |
|---|---|
| `/keel-setup` | Lets the assistant finish setup: fills machine details, drafts a project's `CLAUDE.md` from its code. |
| `/init-project` | Sets up a new project. |
| `/context-dump` | Onboards an existing, undocumented codebase by actually reading it. |
| `/go` | Implements one backlog ticket, after checking it is ready. |
| `/polish` | Pre-PR pass — simplify, tests, a depth-matched review, then open the PR. Gated by `tools/pre-pr-gate.sh` once you've run `install-pre-pr-gate.sh` for the repo (optional; every step still runs without it). |
| `/wrap` | Closes out a session: notes, changelog, backlog. |
| `/triage` | Promote-or-drop pass over the staging tiers (`LEARNINGS.md`, `IDEAS.md`, the standing list) — one verdict per entry. |
| `/global-review` | Reviews across all projects. |
| `/backlog` | Shows the backlog. |
| `/keel-score` | Scores how much Keel shaped a session — derived from cited events, not asserted. |

`go-guide` is not a slash command: it is the implementer guide `/go` loads at its step 7. `polish-guide` is not one either: it holds `/polish`'s rare branches (a convergence round, a compaction stop, a mutation pass, the depth dialogs, a refused or void review, an add-on, a gate deny, an already-open PR), and the `/polish` core loads it only when one of them fires.

## Agents (`agents/`)

| Agent | What it does |
|---|---|
| `keel-polish-reviewer` | `/polish`'s review subagent: reads the diff its caller embeds in the prompt plus files on disk, and nothing else — its `tools:` allowlist is `Read, Grep, Glob`, so it cannot run a command, a test or git (a structural floor under the read-only rails, not a remembered instruction). |

`install.sh` wires `agents/*.md` into `<home>/agents/` (a symlink under `--link`, never under `--codex`);
`uninstall.sh` removes what it placed; `doctor.sh --install` reports a missing agent
(`W-REVIEW-AGENT-MISSING`) and an installed copy whose `tools:` grew past the shipped set
(`W-REVIEW-AGENT-FLOOR`). `/polish` spawns it for step 5's fallback review and its second opinion, and the
gate's `SubagentStop` trace trusts only that agent type: `tools/install-pre-pr-gate.sh` wires the matching
hook and retires the legacy `general-purpose` one, and `doctor.sh --install` flags wiring that was not
migrated (`W-GATE-REVIEW-MATCHER`).

## Extras

[`examples/`](../examples/) is a runnable, safe 5-minute tour: `init-project` → `doctor` → secret-guard
blocking a key. Most of the docs are indexed in the [README's Docs section](../README.md#docs) too — a
few (`keel-impact.md`, `keel-impact-evidence.md`, `mcp-decision.md`, `publishing-checklist.md`, and the
five [`docs/drydock/`](drydock/) role-prompt templates) aren't.

[`docs/memory-layers.md`](memory-layers.md) answers "does Keel do memory?": the five memory layers mapped
onto Keel's files, what Keel deliberately does not build, and the `doctor` checks that find stale or
unreachable memory files.

Setting Keel up for a tool other than Claude Code (installer flags, the by-hand copy) →
[`docs/getting-started.md`](getting-started.md) and [`ADAPTING.md`](../ADAPTING.md).
