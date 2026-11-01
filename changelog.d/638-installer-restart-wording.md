- `tools/install-read-trace.sh` and `tools/install-pre-pr-gate.sh` no longer tell adopters that hooks "load only at
  session start". They now say hooks are usually live at once and to restart Claude Code only if a hook does not
  fire, matching the current Claude Code hooks docs. Both installer tests pin the new wording (dir #638).
