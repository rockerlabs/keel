- Two assertion-strength gaps in the test suite are closed (dir #332). The gate suite's ambiguity check for two
  marker-ending questions in one dialog event now has a mirror fixture with the skip on the last question, so an
  implementation that resolves ambiguity by taking the last match goes red (the old fixture only separated the
  rule from taking the first match). The conveyor-stages test block for the already-open-PR branch now matches
  inside the slice between the step headings of the polish guide, the same line-window idiom its neighbouring
  blocks use, instead of file-wide `grep` calls: a phrase moved into the wrong step goes red. The third part of
  the ticket, the embedded-newline check, is not changed here: a stronger fixture showed the tool's own
  newline flattening is unreachable, because the argument is cut at its first newline earlier, so that part is
  reported for a tool fix. Test-only; no tool changed.
