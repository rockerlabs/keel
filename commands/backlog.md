---
description: Show a project's backlog as a table — current project by default, or pass a name
---
Display a backlog as a compact table. **Read-only** — never edit the backlog or reconcile against git unless
asked. Chat narration in the user's language; backlog items stay in their original language — quote their
gist as-is.

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

**3. Infer status for each item** from inline markers — first match wins:

| Marker in source | Status |
|---|---|
| `Active` / `Next up` / `OPEN = one step` | **Active** |
| `DONE` / `✅` (in the open section, not the recently-closed buffer) | skip |
| `Gate:` / `gated` (condition not yet met) | **Parked** |
| `parked` / `deferred` / `low priority` | **Parked** |
| `blocked` / `waiting on <external>` | **Blocked** |
| no marker | **Next-up** |

Order rows **Active → Next-up → Parked → Blocked** within each section. For a `Gate:` item, append the gate
to the gist.

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
- Below the table, one line `Recently closed: <ids or count>` if the source carries a cooldown buffer (don't
  dump the buffer). Name the source (project + file) so it's clear what was shown.
