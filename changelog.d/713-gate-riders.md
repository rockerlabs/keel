- **The pre-PR gate's riders from dir #583's last review round (dir #713, spec 745 PR-3).**
  `pre-pr-gate.sh -h` now names the gate by the path it was invoked as, and inside a work tree where key resolution
  fails (a detached HEAD) it prints why instead of the generic "no checkout" note. A first argument that is none of
  the gate's subcommands (`--halp`, `foo`) prints a usage line and exits 2 at once, instead of falling into hook mode
  and waiting on stdin; the hook is always wired with no argument, so nothing that runs it changes. The
  missing-review-trace deny for an `agent:*` outcome now names the remedy an agent can perform (re-run the
  `keel-polish-reviewer` subagent, whose `SubagentStop` writes the trace), and the `polish.5-review` hint no longer
  says an agent review satisfies nothing: the reviewer's own `agent:<level>` receipt is accepted, a bare Agent spawn
  of any other type is not. Three guards gained tests proved by mutated copies of the gate (the header-boundary
  extraction, no sandbox note in a checkout, the note as exactly one line). Not changed, with the reason: `keys`
  stays under the `$HOME` guard, and the released changelog bullet for dir #583 is history, so it is not rewritten.
