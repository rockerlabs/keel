---
description: Show a project's backlog as a table — current project by default, or pass a name
---
Display a backlog as a compact table. **Read-only, with one exception** (step 2b) — never edit the backlog
or reconcile against git beyond that. Chat narration in the user's language; backlog items stay in their
original language — quote their gist as-is.

**1. Resolve the target project:**
- **No argument** → the CURRENT project: read the `project-id:` marker from the current dir's `CLAUDE.md`
  (it identifies the project across worktrees / monorepo subdirs). If there's no marker, or it isn't a row
  in the Projects table of `INSTANCE.md`, fall back to the git root
  (`git -C "$PWD" rev-parse --show-toplevel`). If that yields nothing → say "no project found" and stop.
- **`/backlog <name>`** → match `<name>` against the Projects table in `INSTANCE.md`.

**2. Find the backlog source (first that exists):**
Resolve the project's path (id → path in the Projects table), then take the first of: `<path>/BACKLOG.md` →
the separate on-demand backlog the `CLAUDE.md` map points to → the **inline open-work section** of
`<path>/CLAUDE.md`. That heading varies by project and language (`## Backlog`, `## Roadmap`, `## Next`,
`## TODO`, …) — find it by meaning, not a fixed string (small projects keep the backlog inline until
~8–10K tokens). If open work is split across sections, show the primary one and note the others exist. None
found → say "no backlog found" and stop.

**2b. Fold leftover drafts:** if `<path>/BACKLOG.drafts/*.md` exists alongside a `BACKLOG.md` source,
each file is a design/planning session's unnumbered draft ticket meant to be folded in at its own session's
wrap (see `FRAMEWORK.md`'s backlog/persist section for the convention) — but a draft can also be one
that just hasn't reached its own session's wrap yet, not necessarily a dead session's leftover. Do the
whole pass off ONE read of `BACKLOG.md`, not one read per check: read it once, then for each draft check
against that same read whether a ticket for its slug already exists (its heading carries the same
slug/title) — if so, skip it (someone folded it already, just hasn't deleted their local draft yet) and
mark it for deletion without appending. Assign each remaining draft a consecutive next-free number in
file order, append all their bodies, update the queue line if the backlog tracks one, then write once
and delete every drafted-or-skipped file. If the write hits a modified-since-read collision, re-read and
retry the whole batch once (existence checks included, against the fresh read); on a second failure
leave the remaining drafts in place rather than forcing it (they render as draft rows per step 5
instead). Report what was folded (and what was skipped as already-folded) before rendering the table.

**3. Infer status for each item** from inline markers — first match wins:

| Marker in source | Status |
|---|---|
| `Active` / `Next up` / `OPEN = one step` | **Active** |
| `DONE` / `✅` (in the open section, not the recently-closed buffer) | skip |
| `⏳ IN FLIGHT` (a session already claimed it — don't offer it as pickable) | **In flight** |
| `Gate:` / `gated` (condition not yet met) | **Parked** |
| `parked` / `deferred` / `low priority` | **Parked** |
| `blocked` / `waiting on <external>` | **Blocked** |
| no marker | **Next-up** |

Order rows **Active → In flight → Next-up → Parked → Blocked** within each section. For a `Gate:` item,
append the gate to the gist; for an **In flight** item, append the claiming branch the marker names —
the point of showing it is that the next `/go` doesn't pick it twice.

**3b. Read the target-release label, if any.** A heading's status tail can carry a `→ 0.6.1`
(or `→ next`) tag — appended at triage time (see
[`docs/release-audit.md`](../docs/release-audit.md) phase 2), orthogonal to the status markers above: it
says *which release this item is slated for*, not what state it's in. An item with no such tag simply
has no target yet — that's not itself a finding, and every status in the table above can carry one.
**Do not require the tag to be LAST on the line.** It is appended at triage time, so a closure marker
written later routinely lands after it — `— R2 — → 0.6.1 — ✅ CLOSED (…, PR #199 merged)` is the
ordinary shape once a tail ticket closes, and most of a closed tail looks like that. Read the tag
wherever it appears in the status tail; matching only a line-final one would hide most of the release
tail from step 6's grouping, which is the one thing that grouping exists to show.

**4. Multi-section backlogs:** when the source uses `##` section headers, add a **Section** column and group
rows under their section; order sections by actionability (most Active/Next-up first), items within a
section by the order above. For a flat backlog, omit the Section column.

**5. Render the table** — columns adapt to the backlog:

| ID | Item | Status |
|----|------|--------|
| <id> | one-line gist | Active |

- **ID** — only if items carry ids; omit the column otherwise.
- **Item** — one-line gist; the file is the detail, do NOT dump full prose. Lead with the actionable state.
- **Status** — per step 3.
- **Any `BACKLOG.drafts/*.md` that step 2b could not fold** (persistent race) appends as its own row: ID
  `draft` (no number assigned), Item = the draft's own gist, Status **Draft**. Order draft rows last.
- Below the table, one line `Recently closed: <ids or count>` if the source carries a cooldown buffer (don't
  dump the buffer). Name the source (project + file) so it's clear what was shown.

**6. Group by target release, if any item carries the label from step 3b.** Render one additional table
per distinct target value, titled `Release tail — <target>` (e.g. `Release tail — 0.6.1`), same ID/Item/
Status columns as step 5, ordered by the target's own natural order (a version string ascending, `next`
last) then by the step-3 status order within each group. This is what answers "what's slated for `X`?" in
one glance instead of a re-read of every heading — the reason the label exists at all (see
[`docs/release-audit.md`](../docs/release-audit.md) phase 2). Skip this step entirely when nothing in the
source carries the label; don't render an empty grouped section.

**Personal-fork note (not a Keel mechanic, recorded here because a Keel change to this file doesn't reach
it automatically):** an adopter running a personal, KB-forked copy of this command (diverged from Keel's
shipped `commands/backlog.md` on purpose, e.g. to add workflow-specific columns) does not get step 3b/6 for
free from a Keel upgrade — a forked file is edited independently by design, so porting a Keel-side change
like this one into the fork is a manual, deliberate step, not something a `git pull` of the Keel checkout
performs.
