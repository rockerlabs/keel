- **The backlog scanner recognises an adopter's uniform closure form `✅ **Done 2026-09-20**` (dir #609).**
  `BB_CLOSURE_TAG_PATTERN` in `tools/lib/backlog-blocks.sh` now accepts each closure word in UPPER or Title case (`DONE`, `Done`) and allows up to two
  `*` or `_` of markdown emphasis between the glyph and the word (all-lowercase stays prose; a title that puts a closure word right after a glyph reads as closed, a new case for Title case, as it always was for UPPER), so `bb_closure_word_ok` no longer refuses the form
  a peer project kept for weeks and the census, the pool report and the archive-sweep check read it as closed.
  `bb_closure_word_ok` also gains the scanner's own trailing boundary, so `✅ FIXEDX` is refused instead of read as
  `✅ FIXED`, and the archive-sweep check dates a closure from a bare date after the word. The body-prose regex in
  `tools/self/doctor.sh` stays case-sensitive on purpose; its comment says why.
