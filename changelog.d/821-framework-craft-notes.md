- `FRAMEWORK.md` gains the shell, editing and verification craft notes promoted from the first `/triage` pass
  (dir #821): a "Shell and editing craft" section (quoted heredoc delimiters and the edit tool over generated
  rewrites, `count(anchor) == 1` before every `find()`, seam re-reads after an insert, scripts over compound
  commands, `\x1f` over tab in `IFS` reads, no cache inside `$( … )`), verify-gate rules (capture the exit code
  apart from filtered output, run the path you claim unchanged, a figure carries its predicate, a guard test
  fails one assertion instead of crashing its host), and notes on ticket-number timing, `update-ref` recovery
  of a colliding local commit, out-of-tree incident recovery and multi-round document corrections.
