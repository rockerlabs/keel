- One bad line no longer aborts the session-cost reader for the whole file (dir #852).
  `weighted`, `table`, `session`, `selfcheck` and `tail --json` read a transcript line by line, so a truncated last
  line, a line that is not an object, a CRLF line, or a tool call whose `cwd` or `file_path` is not a string skips only
  itself and the file is priced at the same number as its clean twin. `selfcheck` reports the skipped-line count; `keel tokens` shares the reader
  (`tools/lib/transcript-usage.sh`) and skips a bad line the same way, without reporting it. A
  manifest line that names no session file is priced as zero with a note instead of aborting on bash 3.2.
