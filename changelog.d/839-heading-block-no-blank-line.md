- **A ticket whose first body line sits directly under its heading no longer reads closed from that line (dir #839).**
  `tools/lib/backlog-blocks.sh` ended a heading block at the first blank line, so a body line written with
  no blank line before it joined the heading, and a `✅ DONE` in it closed an open ticket for
  `tools/self/backlog-census.sh`, `tools/self/pool-report.sh` and `tools/self/archive-sweep-check.sh` (the
  0.17.0 groom lost dir #813 from every count this way). A heading that already shows its tail (an R grade, a
  release or pool arrow, or a status glyph) now takes no further line unless that line opens with the tag's own
  em-dash, and a `Log:`, `Draft slug:` or `**` opener always ends the block; a title that wraps before its tail
  still reads as before. Residual, named in the function's header: a prose body line directly under a heading
  with no grade, arrow or glyph at all.
