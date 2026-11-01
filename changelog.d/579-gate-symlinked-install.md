- `tools/pre-pr-gate.sh` now follows symlinks when it locates its own directory, so an install that links
  `~/.claude/pre-pr-gate.sh` to the checkout's script sources `lib/` without the «No such file or directory»
  errors; `tools/doctor.sh --install` warns (W-GATE-LIBS) when such a link's target has no `lib/` beside it (dir #579).
