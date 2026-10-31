- `backlog_ticket_blocks` (`tools/lib/backlog-blocks.sh`) now ends a last ticket that closes with a fenced block at the
  file's last non-empty line, where it used to stop at the last visible one, so `tools/self/archive-sweep-check.sh` counts
  such a ticket whole (dir #915). Its heading-continuation walk stays inside the scanned lines under bash 3.2's `set -u`.
  A third argument, a ticket id, is the new lookup mode: it walks that one heading and does no closure work for it (its
  `closed` field is `-`). `tools/cloud-brief.sh` uses it and no longer keeps its own fence-marker count: the unclosed-fence
  cut is `bb_last_block_fence_end`. A closed fence holding a section-shaped line before an unclosed one now travels
  whole when no visible text follows it (visible text there is still refused), and the refusal for an unpaired fence
  says to close it "inside the ticket, before line N".
