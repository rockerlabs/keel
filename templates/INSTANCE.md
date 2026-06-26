# Instance (this user / this machine) — TEMPLATE

> The **personal layer** — everything host-, user- and project-specific that the reusable `FRAMEWORK.md`
> deliberately excludes. Fill this in; change nothing in `FRAMEWORK.md`. **Keep this file private**
> (gitignored or in a private repo) — it holds your environment and project list.
>
> On demand — NOT auto-loaded (the always-loaded `CLAUDE.md` points here). Read it when you need the
> Projects registry, the hardware/model context, or the backup-remote specifics.

---

## Environment

- **Hardware:** <machine, RAM, arch — matters for platform decisions>
- **OS / shell:** <OS; which shell the agent's Bash tool actually runs>
- **Model access:** <which models/providers you use, local vs hosted, any API-key availability>
- **Other tools:** <MCP servers, search providers, etc.>

## Backup remote

- <where this knowledge base backs itself up, and the restore runbook pointer>

---

## Projects — a thin index

One row = name → path → its `CLAUDE.md` → a short stack **tag** (a retrieval hint, not the spec — versions
and feature lists drift, so they stay out). Query the detail, don't dump it: a project's real context lives
in its own `CLAUDE.md`. For a sweep across many projects, recurse into a script/subagent that returns only
the answer — don't read every row's project into the session.

| Project | Path | CLAUDE.md | Tag |
|---------|------|-----------|-----|
| <name>  | <abs path> | <link> | <language / role> |
