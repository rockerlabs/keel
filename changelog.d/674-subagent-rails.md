- **Every subagent now starts with the worker rails.** dir #674: `tools/install-pre-pr-gate.sh` wires a seventh
  hook, `SubagentStart`, that puts the Worker rails block of
  [`docs/delegation.md`](/docs/delegation.md) (read-only, no spawns of its own) into the starting context of
  every `general-purpose`, `Explore`, `Plan`, `claude` and `claude-code-guide` subagent — including the ones a
  built-in skill composes itself, and `Explore` and `Plan`, which start with no `CLAUDE.md` at all. The text is
  read live from the checkout, so there is no second copy to drift; every other agent type gets nothing. It is a
  nudge, not a floor. `KEEL_SUBAGENT_RAILS=off` in the session environment switches it off. **To upgrade:**
  re-run `tools/install-pre-pr-gate.sh` with your scope flag (the six existing hooks read as already wired) and
  restart your sessions; until you do, `tools/doctor.sh` reports `W-GATE-SUBAGENT-RAILS`.
