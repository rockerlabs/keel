- **Keel's own maintenance: `tools/self/accumulate.sh closed` reads a ticket's heading the way the census does.** The
  accumulator cut a heading block at the first blank line, so an open ticket whose first body line was written with no
  blank line under a finished heading, and carried a `✅ DONE`, read as closed. `closed` now takes the lines
  `bb_heading_continues` accepts (dir #839's rule), so that ticket reads open and a title still wrapping onto the next
  line keeps its continuation. A false close would have silenced a recurring class for dir #838's observers and dir #842's
  guard register. Ticket: dir #847.
