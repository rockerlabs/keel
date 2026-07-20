# MCP and Keel — analysis and decision

**Status:** decided — no MCP integration; re-open triggers named below. **Date:** 2026-07-19.

MCP (the Model Context Protocol) is the emerging open standard for wiring AI assistants to external
tools, resources, and prompts through servers the harness connects to. It is exactly the kind of
shiny, seemingly-foundational concept `PRINCIPLES.md` says must be absorbed *cheaply* — a parked
note and a changelog row, not a restructuring. This file is that absorption, and the record of why.

Three possible roles for MCP in Keel were examined:

- **A. Keel as an MCP server** — expose `PRINCIPLES.md` / `FRAMEWORK.md` / `INSTANCE.md` and the
  project registry as MCP resources, `doctor` / `public-audit` as MCP tools, `commands/*` as MCP
  prompts, so any MCP client could consume Keel without files.
- **B. Keel managing the user's MCP configuration** — conventions or tooling for which servers to
  run and how to configure them per harness.
- **C. Documentation-level acknowledgement** — treat MCP servers as a fact of a user's environment,
  recorded per instance.

## A. Keel as an MCP server — rejected

1. **No felt friction (P4).** File-based loading works on every substrate Keel has actually run on
   (Claude Code, Codex, Cursor — see `ADAPTING.md`), and no adopter has asked for an MCP surface.
   P4's prophylactic carve-out doesn't apply: nothing here is irreversible or high-severity. Building
   it now would be structure from completeness, not from a problem.

2. **The always-on layer cannot ride MCP — by design of both sides.** Keel's core promise is a thin
   layer *injected* into every session. MCP resources and tools are *agent-requestable*: the model
   must decide to fetch them. Keel has already measured what agent-requestable delivery does to the
   rails — on Cursor, the documented `.cursor/rules` "Always" format loaded as requestable rather
   than injected, and the rails silently did not fire (the agent committed straight to `master`;
   see the warning in `ADAPTING.md`). An MCP-served core reproduces that failure mode as its normal
   operation. MCP's server `instructions` field is the one inject-ish primitive, and client support
   for it is uneven — not a floor to stand on.

3. **It breaks the zero-dependency boundary (P0 — mechanism stays thin).** `tools/` is plain Bash +
   git precisely so the mechanized layer runs under any tool, any model, or none. An MCP server
   means a runtime (Node or Python), a long-running process, per-harness registration, and a spec
   that is still churning revision to revision. That is pure *mechanism* in P0's sense — the layer
   that depreciates by design — bolted onto the project's most durable parts.

4. **The token economics invert (P2/P3).** Keel's tools cost **zero** context tokens; only their
   short output ever reaches the model. MCP tool and resource schemas load into the context of every
   session that connects the server — a new fixed cost where today there is none. Worse, wrapping
   `secret-guard` as an MCP tool would *weaken* it: from a git-level hook that fires whether or not
   the model remembers it, to a callable the model must choose to invoke. That reverses the one hard
   guarantee Keel makes ("deterministic gates enforce; loaded prose only nudges").

5. **The on-demand tier already has a delivery mechanism.** The map in the always-on core points at
   files; every tested harness can read a file. An MCP resource layer over the same files duplicates
   an existing capability at added operational complexity and adds none.

## B. Keel managing the user's MCP configuration — rejected

MCP configuration is harness-specific (`.mcp.json` and friends, formats differing per tool),
machine-specific, and fast-churning — all three of the properties that place a fact in
`INSTANCE.md`, not in the reusable layer. `templates/INSTANCE.md` already carries the slot
(**Other tools:** MCP servers, search providers, …). Keel taking ownership of MCP config would
violate the reusability boundary and the tool-independence stance in one move.

## C. Documentation-level acknowledgement — accepted

Which MCP servers an instance runs is an environment fact, recorded in that instance's
`INSTANCE.md` line. This document records the reasoning. Nothing else changes.

## Re-open triggers

Revisiting on a calendar would violate P4; each trigger below is a felt-friction event that would
genuinely change the analysis:

1. **A real adopter on a harness where files cannot be injected or read** and MCP is the only
   extension surface — a transfer-failure signal in P0's terms, and the first case where an MCP
   adapter would add a capability instead of duplicating one.
2. **MCP (or a successor) ships a widely-honored always-inject primitive** for instructions. Then
   the always-on core could ride it as a *delivery channel*, content unchanged — the platform
   absorbing a mechanism, which P0 counts as an upgrade, not a loss.
3. **A real second consumer asks for Keel-as-MCP-server** with a concrete task that file loading
   demonstrably cannot do.

## What ports if this reopens

The asymmetry that makes waiting cheap: everything durable ports untouched. `PRINCIPLES.md`,
`FRAMEWORK.md`, and the templates are plain text — serving them as MCP resources is a thin,
disposable adapter; `doctor` and `public-audit` wrap trivially as tools around their existing exit
codes and output. Nothing decided away today is expensive to build tomorrow — but carrying a
server, a runtime dependency, and a churning spec *now* is a cost paid every day against a benefit
no one has felt. Cheap later, costly-to-carry now: wait.
