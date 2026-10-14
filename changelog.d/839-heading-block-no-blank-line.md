- **A ticket whose first body line sits directly under its heading no longer reads closed from that line (dir #839).**
  `tools/lib/backlog-blocks.sh` ended a heading block at the first blank line, so a body line written with
  no blank line before it joined the heading, and a `✅ DONE` in it closed an open ticket for
  `tools/self/backlog-census.sh`, `tools/self/pool-report.sh` and `tools/self/archive-sweep-check.sh` (the
  0.17.0 groom lost dir #813 from every count this way). A heading that already shows its tail (an R grade, a
  release, pool or lane arrow, or a status glyph) now takes no further line, and a `Log:`, `Draft slug:` or `**`
  opener always ends the block. A title that wraps before its tail still reads as before. What
  leaves the block is whatever is wrapped onto the line after a finished first line: dir #207's parenthetical note,
  a lane arrow (no longer read by the pool report) and a closure tag (a wrapped `— ✅ CLOSED` now reads open); no
  known heading has the last two, and no `closed` verdict on the maintainers' backlog changes. The other residual,
  named in the function's header, is a prose body line directly under a heading with no tail at all.
