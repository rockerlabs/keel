- `tools/lib/backlog-blocks.sh` (dir #448): two latent false-`closed=1` shapes fixed in the shared closure
  helpers. `bb_strip_foreign_citations` now walks each verb form to a true fixed point (a self-citation
  ahead of a foreign one no longer halts the strip), and `BB_CLOSURE_TAG_PATTERN`'s internal gaps are
  same-line whitespace, so a glyph at the end of one line and `DONE` at the start of the next is no longer
  one closure tag. Neither had a live instance; fixtures in `tests/test_backlog_blocks_lib.sh` pin both.
