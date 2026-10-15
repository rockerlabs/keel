- **`tools/self/doctor.sh` check 5 <!-- claim: hand the check number in tools/self/doctor.sh, 2026-10-15 --> reads a ticket's heading the way the census does (dir #766).** The staleness
  check kept its own copy of the old "heading block runs to the first blank line" loop, so a body line written
  directly under a finished, untagged heading was absorbed into the heading, and a `— ✅ CLOSED` at its start read
  as the heading's own tag: the check went quiet on a ticket whose body already recorded the close. It now sources
  `tools/lib/backlog-blocks.sh` and asks `bb_heading_continues` (dir #839) which following lines belong to the
  heading, so doctor, the census, the pool report and the archive-sweep check share one rule. A title that wraps
  before its tail still takes its continuation lines, as before.
