# Cloud route — running a backlog ticket in a Claude Code cloud session

A ticket that needs nothing from your machine can run in a Claude Code cloud session instead of a local
one: a VM clones your repository, implements the ticket, opens a **draft** pull request, and you land it
after a model-free local check. Keel ships the pieces — [`tools/cloud-brief.sh`](../tools/cloud-brief.sh)
builds and dispatches the brief, [`tools/cloud-land.sh`](../tools/cloud-land.sh) is the landing check,
[`templates/cloud-protocol.md`](../templates/cloud-protocol.md) is what the VM is told — and this doc is
their rulebook. `/go`, `/groom` and `/manage-release` point here rather than restate it.

**Claude Code only.** The route runs on `claude --cloud` and GitHub; [`ADAPTING.md`](../ADAPTING.md) says
what that means on another tool. **It spends credit and pushes a branch from a VM**, so it is opt-in per
project, and starting a session and merging stay your decisions.

## The route at a glance

1. **Opt in** — one line in the project's `CLAUDE.md` (below).
2. **Grade** — whoever grades a ticket R3, R4 or `📐 SPEC-READY` also writes its `**Cloud:**` verdict.
3. **Check** — `cloud-brief.sh <repo> "<ticket>" --check` runs every mechanical row and writes nothing.
4. **Dispatch** — on your yes, `--dispatch` builds the brief and starts the session; the ticket's claim names
   the branch `claude/cloud-<slug>`.
5. **Land** — when the session's draft PR exists, `cloud-land.sh` scans and reads CI; exit 0 is the gate.
6. **Merge** — you do, pinned to the exact head the check passed.

## The opt-in line (B1)

A project is cloud-capable when its main checkout's `CLAUDE.md` has a line **of its own** matching

```text
^KEEL-CLOUD( unprotected-ok)?[[:space:]]*$
```

The main checkout is the first entry of `git worktree list`, as `/go` step 1 resolves `<root>`. Any other
line that names `KEEL-CLOUD` — in a paragraph, with extra words — is not the opt-in, and the tool prints it.
The line is read wherever it stands in the file, a fenced example included, so never show it in an
example block. `unprotected-ok` lets row G1b pass a repository whose default branch a direct push can reach
(the push guard below still applies). Prose around the line is the project's rails: the whole file travels in
the brief, and its test command is the VM's test command.

The repository is `origin`'s `github.com` `owner/name`. Its default branch comes from
`gh api repos/<o>/<r> --jq .default_branch`. **Protected** means the server refuses an unchecked direct push:
`gh api repos/<o>/<r>/branches/<default> --jq .protection.required_status_checks.enforcement_level` prints
`everyone`. The bare `protected` flag is not used — it is true for weaker rules too.

## The verdict line (B2)

At most one line per ticket body, starting `**Cloud:** `, placed beside `**Model rec:**`:

```text
**Cloud:** yes (YYYY-MM-DD, <who>)
**Cloud:** no — <row>: <reason> (YYYY-MM-DD, <who>)
```

`<row>` is one of G3, G3b, G4, G5, G8; `<reason>` is one line; `<who>` names the writer (`filing`,
`grade pass`, `groom`, `design session`, `operator`, or a session name). Both the count and the value are
read from the ticket block with fenced blocks blanked, so a fenced example never counts. No line means not
judged; anything else after `**Cloud:** `, or two such lines, is malformed and refused. The mechanical rows
(G1, G1b, G1c, G2, G2b, G6, G7, G9) are never recorded — they are re-run at every build. A flip from one value
to the other adds a dated `Log:` line to the body; the verdict line is replaced in place.

**Who writes it, and when (B3).** In a cloud-capable project, any edit that sets a ticket's grade to R3 or R4,
or its status to `📐 SPEC-READY`, writes or refreshes its `**Cloud:**` line in the same edit. A later edit that
changes what the ticket writes, reads or checks re-judges it. `/go` judges and writes a missing line on its
first look; `/groom` writes the line for every slate ticket that lacks one. `cloud-brief.sh <repo> --sweep`
lists every open R3/R4/`📐` ticket with its verdict or `—`. The tool never writes the backlog: on `--eligible`
it prints the `yes` line for the session to write with an edit tool.

## Eligibility — the rows

All must hold. Mechanical rows the tool decides; judged rows are the grader's, recorded once in the verdict.

| id | row | decided |
|---|---|---|
| G1 | The project is cloud-capable (the opt-in line above) and `origin` resolves to a github.com repository `gh api` can read. A default-branch name outside `[A-Za-z0-9._/+-]` is refused here too — the protocol pastes it unquoted into the VM's shell. | mech |
| G1b | The default branch is protected (`enforcement_level` is `everyone`), or the `KEEL-CLOUD` line carries `unprotected-ok`. | mech |
| G1c | The repository has CI the landing check can read: `gh api repos/<o>/<r>/actions/workflows --jq .total_count` is above 0. No CI is refused before any credit is spent: the landing check needs a non-empty, green check rollup. | mech |
| G2 | The ticket is open and R3, R4 or `📐 SPEC-READY` (the LAST `— R<d>` token of the heading decides; `📐` with no grade passes; `📐` beside R0–R2 is refused — a contradiction), with none of ✅ · ❌ · `SUPERSEDED` · `RETRACTED` · `⏳ IN FLIGHT` · `⛔ BLOCKED` on the heading. Markers count on the heading only. | mech |
| G2b | The ticket's verdict is not `no`; `yes` confirms the judged rows; no verdict needs `--eligible`. A malformed verdict is refused. | mech |
| G3 | Every file the work writes is tracked in the project — never a gitignored or untracked file, the backlog, the rails file when it is gitignored, anything outside the repository. | judged |
| G3b | Every file the work must read is tracked, or travels in the brief (the ticket, its spec, the rails). | judged |
| G4 | Every check that decides the work runs on an Ubuntu VM with no key, device or live account; a final live check alone is done locally at landing. | judged |
| G5 | The ticket is not itself a managed-release role (manager, train worker, auditor). A slate ticket may run as a cloud worker. | judged |
| G6 | The rewritten brief is at most `CLOUD_BRIEF_MAX_BYTES` (default 130000: the dispatch passes it as ONE argument, and Linux caps one argument at 131071 bytes). | mech |
| G7 | A `Spec:` line's first token names a file in the main checkout. No `Spec:` line passes. Never an absolute path, a symlink, a directory symlinked out of the checkout, or a path through `.git` — the repository's git config, auth headers included, would ship to the VM. | mech |
| G8 | The ticket does not ask for a design pass first. | mech for two phrases, each alone sufficient — "Question for a /design pass" in the body, "for the design" (case-insensitive) on the `**Model rec:**` line · judged otherwise |
| G9 | `--dispatch` only: the main checkout is on the default branch, and `origin` has no `claude/cloud-<slug>` branch. | mech |

## `cloud-brief.sh`

```text
cloud-brief.sh <repo> <ticket-id> [--check | --eligible | --dispatch] [--credit-before <amount>] [--redispatch] [--out FILE]
cloud-brief.sh <repo> --sweep
```

Call it as `<keel-checkout>/tools/cloud-brief.sh`. `<repo>` is any path inside the project (a worktree too);
the tool works on its main checkout. `<ticket-id>` is spelled as the heading spells it (`dir #801`, `KB.34`) —
quote it. The backlog is resolved the `/backlog` way: `<root>/BACKLOG.md`, else the inline ticket section of
`CLAUDE.md`; a project with neither is spec-mode and its tickets are not dispatched.

| mode | what it does |
|---|---|
| (none) | builds the brief and writes a `built` ledger row |
| `--check` | every row above except G9, plus the model mapping, the ledger refusal, and G6 and the secret scan on a brief assembled in a temporary directory; **writes nothing**. Its last stdout line is `cloud-check: <exit> <ticket> <head sha of the main checkout>` — the receipt a wave plan quotes |
| `--eligible` | builds a ticket that has no verdict yet, the judged rows taken as confirmed, and prints the `yes` line to write |
| `--dispatch` | builds, checks G9, writes the row as `dispatched`, runs `claude --cloud` and prints the claim to write |
| `--sweep` | read-only: the open tickets with their verdicts, and this repository's `dispatched` and `landed` rows with their PRs |

**Exit codes.** 0 done · 1 the secret scan refused the brief · 2 usage, not found, a `gh` or git failure, the
ledger lock · 3 a mechanical row, the model mapping or the ledger refused · 4 judged rows unconfirmed (no
verdict yet — the judged rows and both line templates are printed) · 5 the dispatch itself failed. A `gh`
answer of 404 or 403 is a G1/G1b/G1c refusal (exit 3); a rate limit is a 403 too, so a refusal that names
"cannot read" is worth one re-run before it is believed.

**The model** comes from the ticket's `**Model rec:**` line: top tier → opus, mid tier → sonnet, light tier →
haiku, with the effort word on the same line (no effort word: medium). No line: sonnet and medium. A line
naming no mapped tier is refused.

**The brief** is one plain file: `=== protocol ===` (the template, its placeholders filled), `=== ticket ===`,
`=== spec ===` when G7 named one, `=== rails ===` (the main checkout's `CLAUDE.md`), and the last line
`=== end of brief ===`. Before anything is written:

- the home path is rewritten — `$HOME` and the passwd home, each logical and physical, become `~`; Claude
  Code's project-directory encoding of each becomes `-Users-x`; the session scratch roots become `<tmp>/`.
  A path is replaced wherever it occurs, so with HOME=/root a path beginning /rootfs also becomes ~fs;
- the whole brief goes through `tools/secret-guard/secret-scan.sh`, the allow marker defanged, from an empty
  directory. The personal check is **fail-closed**: the tool exports `SECRET_SCAN_PERSONAL_FILE` — its value
  when set, else the scanner's default `~/.claude/secret-scan-personal` — and refuses (exit 2, nothing
  written) when that path is not a regular file, unless it is `/dev/null`, the scanner's deliberate opt-out.
  The list is per machine, not per project.

**Where things go.** The brief is written to `CLOUD_BRIEF_DIR` (or `--out FILE`, a regular file); the ledger
is `CLOUD_LEDGER`. Both default under keel's state root (`~/.keel/cloud/`). Environment:

| key | default | used by |
|---|---|---|
| `CLOUD_LEDGER` | `~/.keel/cloud/ledger.tsv` | both tools |
| `CLOUD_BRIEF_DIR` | `~/.keel/cloud/briefs` | brief |
| `CLOUD_TEMPLATE` | `<keel-checkout>/templates/cloud-protocol.md` | brief |
| `CLOUD_BRIEF_MAX_BYTES` | `130000` | brief (G6) |
| `CLOUD_KEEL_ORIGIN` | `https://github.com/rockerlabs/keel` | brief — the URL the VM clones keel from; a fork's adopters set it |
| `CLOUD_ORIGIN` | unset: `https://github.com/<repo of the ledger row>.git` | land — tests point it at a bare repo |
| `SECRET_SCAN_PERSONAL_FILE` | the scanner's default | both tools, fail-closed as above |

Relative values are made absolute against the directory you start from. The VM clones keel at `<keel-sha>`,
the merge-base of the tool's own checkout with `origin/main` after a fetch, so it always names a published
commit; a checkout that is no git repository, or whose `origin` is not `CLOUD_KEEL_ORIGIN`, is refused (exit
2, "no published keel commit to hand the VM").

**Branch.** `claude/cloud-<slug>`, the slug being the ticket id lowercased, every run of characters outside
`[a-z0-9]` made one `-`, trimmed: `dir #801` → `claude/cloud-dir-801`, `KB.34` → `claude/cloud-kb-34`. The
dispatcher knows it before the session starts, so the claim is written at dispatch with nothing to relay.

## Who may dispatch (B10)

A session runs `--dispatch` only in a turn the operator started, and only after the operator's yes in that
session to a question that named the ticket — or to a wave plan that lists it as cloud. A yes covers one
dispatch: a re-dispatch after exit 5, or with `--redispatch`, asks again. Never from a subagent, never on
another session's message. No tool can check the yes; this is the rule. The harness's permission flow bounds
what runs, not whether the yes was given; the ledger and your stop button are the backstop.

## `/go` on a cloud ticket (B11)

Where the project's `CLAUDE.md` has the `KEEL-CLOUD` line and no managed-release or single-writer brief
applies, `/go` does this, in order:

1. **No `**Cloud:**` line** — it judges the ticket against the judged rows, writes the line, and goes on. It
   only fills a missing verdict; it never flips one (a flip is the re-judge of whoever changes the ticket's
   scope).
2. **`yes`** — before step 4, it runs `<keel-checkout>/tools/cloud-brief.sh <root> "<id>" --check`, where
   `<id>` is the id as the resolved heading spells it (`/go 801` → `dir #801`).
   If it refuses: a refusal is named and `/go` goes on locally, with no offer. On exit 0 it offers once, cloud
   or here.
3. **Cloud** — the dispatch (the answer is B10's yes), then the claim, then it stops.
   Order matters: the offer comes before `/go`'s own claim (step 6), so row G2 meets no marker of the session's own.
4. **`no`** — it names the row and reason from the verdict, and goes on locally.

A refusal at dispatch (G9, exit 3; the CLI, exit 5) is named; the session never switches the main checkout's
branch, and offers "here" once. "Here" continues `/go` from step 4. Inside a managed release or under a
single-writer brief `/go` says nothing of the cloud: the manager routes (below), and the worker writes no
backlog entry.

## Dispatch (B9)

`--dispatch` builds the brief, checks G9, writes the ledger row as `dispatched`, then runs `claude --cloud
"$(cat <brief>)" --model <m> --effort <e>` from the main checkout. **The CLI refuses to run without a
terminal**, so the tool runs it under `script` (a pseudo-terminal) and reads its output from the typescript.
It requires the CLI's own "Created cloud session" line beside exit 0. No `script` on the host: exit 5, the row
goes back to `built`, and the command is printed for you to run in a terminal from the main checkout.

- **Success (exit 0)** prints the CLI's output (the session's title, its web URL and its id), then the claim
  `⏳ IN FLIGHT (<today>, branch claude/cloud-<slug>, cloud)`, the heading with the claim appended after its
  last line, and a dated `Log:` line. The session appends the claim to the heading and the `Log:` line to
  the body with an edit tool. The tool never writes the backlog. A `📐 SPEC-READY` stays on the heading — the
  claim appends, as `/go`'s own does. The `Log:` line carries the session id only when the backlog file is
  gitignored, since a tracked backlog is published.
- **Failure (exit 5)** prints the CLI's output (stdout and stderr arrive merged), sets the row back to
  `built`, and claims nothing.
- **Steering a running session**: its web view (the URL the CLI printed), or `claude --cloud <session id>`
  from a terminal. A non-interactive `claude -p` ignores `--cloud`.

## The protocol the VM follows (B7, B8)

The template is the brief's first part; read it for the full text. What matters to an operator:

- It checks the brief ended with `=== end of brief ===`, and stops without touching anything if not.
- **(a1)** It clones keel at `<keel-sha>` and checks the sha. A failed clone is retried once after 30 seconds;
  a sha mismatch is never retried; either ends the session with nothing pushed.
- **(a3) The push guard.** Before its first push it installs a pre-push hook outside the work tree
  (`core.hooksPath`), an allow-list that refuses every ref but `refs/heads/claude/cloud-<slug>` and refuses a
  deletion, and proves it with four runs in git's own field order. Before every later push it re-checks the
  config and the hook. The guard catches an accident, not an adversary: `--no-verify` skips it, and the
  protocol forbids that flag. It checks refs only — the secret scan before each push is the session's own
  step, which is why landing re-scans.
- It pushes `HEAD:refs/heads/claude/cloud-<slug>` and nothing else, scans every range before pushing, writes
  no session URL or `Claude-Session:` line anywhere, never writes the text `secret-scan:allow`, reviews its own
  diff, and opens a **draft** PR through the REST API with a `## Landing notes` section. It never merges,
  marks ready or closes.
- It asks in chat at a real fork, and also writes the question into Landing notes — chat may be unwatched. A
  session that stops before any PR ends with `no PR: <step> — <reason>` and a line pointing here.

## In a managed release (B12)

The duties sit where they fall due in [`release-management.md`](release-management.md): R1 (intake), R2 (the
wave plan) and R3 (the launch). The rules:

- At intake the manager judges and writes any missing verdict for a slate ticket in a cloud-capable project
  (it is the single backlog writer, R8).
- The plan's route column reads `cloud` or `local — <why>` (`no — <row>`, no verdict, a wave peer, a
  `--check` refusal). Each `cloud` passed `--check` before the plan is shown, and the plan quotes its
  `cloud-check:` receipt line. The operator's yes on that plan is B10's yes for the listed tickets, one
  dispatch each.
- A ticket that shares a file with another ticket in the same wave does not go to the cloud in that wave: the
  manager cannot message a cloud worker, so R10's seams duty has no channel. "Shares a file" is read from the
  files each ticket names (its body, or its spec's impact map); a ticket that names none counts as sharing, so
  it stays local. The manager may move a ticket to a later wave to free it, and says so in the plan.
- The manager runs the dispatch and writes the claim. A cloud worker writes no backlog entry; its PR body's
  Landing notes are its checkpoint report (R13).
- At each R10/R11 sweep the manager learns a cloud PR exists by `gh api repos/<o>/<r>/pulls?head=<o>:<branch>`,
  runs the landing check, and reports its exit to the operator on the R6 channel. A dispatch refused after a
  passed `--check` (exit 1, 3 or 5) sends that ticket local this wave, reported the same way. A dispatch with
  no PR is abandoned under "Abandoning".
- A release role (manager, train worker, auditor) never runs in the cloud (G5).

## Landing (B13)

For a PR whose head branch has a ledger row, the local pre-PR gate does not apply: the VM opens the PR, and
nothing in that gate recognises one. The route's own gate is a checklist the operator runs before the merge —
the cloud session's review, the VM's pre-push scans, CI, and `cloud-land.sh` exit 0 for the exact head SHA. No
hook enforces it; the tool prints the pinned merge command only on exit 0.

```text
cloud-land.sh <repo> <PR#> [--ticket <id>]
```

The repository is `<repo>`'s `origin`, asserted equal to the ledger row's repository (a mismatch is exit 2);
the default branch is resolved from GitHub, never assumed to be `main`. The row is found by the PR's head
branch, or by `--ticket` when the session pushed another branch (an exit 0 then corrects the row's branch).
The scans are decided before CI is read, in a fresh full clone of the repository:

1. the fetched branch tip must equal the PR's head SHA, and the scanner's `--range` over the branch against
   the default branch must exit 0 (keys, personal literals, session trailers in commit messages);
2. the PR title and body pass the scanner's file mode, and carry no session URL or `Claude-Session:` line;
3. no line any commit in the range adds — its patch, merge commits' own combined diff included — and no line
   of any commit message in the range, carries the scanner's allow marker. Every commit is read, not the net
   diff, so a marker added and later deleted still refuses.

Then CI: every check in the rollup completed as success, neutral or skipped, **and at least one succeeded** —
so an empty or all-skipped rollup is not green. A draft PR whose expensive workflow skips drafts can read
green beside one cheap success: read the rollup the tool prints before you mark the PR ready.

**Exit codes.** 0 scans clean and CI green · 1 a scan hit or a scan error · 2 usage, a `gh` failure, no ledger
row, a repository mismatch, or a PR whose base is not the default branch · 3 CI not green, or the branch moved
after the PR was read. Every run that found its row records its landing exit, head SHA and PR on it; only exit
0 also sets the status to `landed` and corrects the branch.

On exit 0 the tool prints the Landing notes and two commands, `gh pr ready <PR#> --repo <o>/<r>` and `gh pr
merge <PR#> --repo <o>/<r> --merge --match-head-commit <sha>`. **The operator merges.** Inside a managed
release too: a cloud PR is never a constituent of a train the manager merges (it may sit in a train the
operator merges, R14's fallback). Pushing anything after the check — an "Update branch" click included —
makes the pinned merge refuse; re-run the check.

**Outside a managed release** the dispatching session is gone by landing. The operator, or a local session
the operator asks, runs the landing check; the dispatch's final report gives the exact landing command and
the `--sweep` command. A later `/go <id>` on the claimed ticket stops at its step 4 (a live branch not its
own); the claim's `cloud` tag is the cue to read this section. `/wrap`'s closing sweep replaces the `⏳` with
✅ on merge. Inside a release the manager runs the check and reports its exit.

## The ledger and the sweep (B14)

`CLOUD_LEDGER` is a header line, then one tab-separated row per (repository, ticket):
`built · repo · ticket · branch · model/effort · brief bytes · credit before · status · credit after ·
overlap · landed · landing exit · head SHA · PR`. Credit cells are optional (`?`).

- **Status**: `built` (brief written) → `dispatched` → `landed` (landing exit 0), or `abandoned` (by hand).
  `landed` means the check passed at that head, not that the PR merged. A non-zero landing run never changes
  the status, so a `dispatched` row stays `dispatched` and a `landed` row re-run at a later head stays `landed`.
- **Refusals**: a rebuild replaces a `built` row. A `dispatched` or `abandoned` row refuses both build and
  dispatch without `--redispatch` (a second dispatch starts a second paid session on the same branch); a
  `landed` row always refuses — set it to `abandoned` by hand if its PR closed unmerged.
- **Lock**: writers take a `mkdir` lock beside the ledger and wait up to 10 seconds; a lock older than 10
  minutes is named stale and never removed by a tool.
- **`--sweep`** lists the open R3/R4/`📐` tickets with their verdicts, then each `dispatched` row of this
  repository with its age and its PR, and each `landed` row marked `STALE` when the PR's head is no longer the
  head it landed at, or when its last landing check exited non-zero. It looks the PR up by the row's branch, so
  a "no PR" on a row you landed with `--ticket` is worth a `gh pr list` before you abandon anything.

## Abandoning

Abandoning a dispatched ticket — the session produced no PR (`--sweep` shows it), or you stopped it — is the
operator's call. It is carried out by the manager inside a managed release, else by a local session the
operator asks:

1. clear the claim marker from the ticket's heading;
2. set the ledger row's status to `abandoned`;
3. delete the remote `claude/cloud-<slug>` branch and any harness-named branch the session pushed besides;
4. `--redispatch` builds it again, on a new yes.

A stale `claude/cloud-<slug>` on `origin` is what G9 refuses on, naming the branch to delete.

## See also

[`release-management.md`](release-management.md) R1–R3 · [`delegation.md`](delegation.md) (a cloud worker's
gate) · [`grooming.md`](grooming.md) (the verdict gap-fill) · [`commands/go.md`](../commands/go.md) ·
[`ADAPTING.md`](../ADAPTING.md).
