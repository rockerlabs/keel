- **A session transcript with one bad line no longer reads as unmatched** (dir #848). `tu_files_for_branches`
  in `tools/lib/transcript-usage.sh`, the lookup behind `session-cost.sh manifest`, now parses a transcript line
  by line, so a truncated last line (a session still being written) or a line that is valid JSON but not an
  object skips only itself. Before, either aborted the whole file and its worker's branch was reported
  unmatched, which would have dropped the live manager's own session from `manifest`'s cost line. Only `manifest`'s
  lookup is tolerant: `session-cost.sh weighted` and `table` still read a transcript whole and stop on such a line.
