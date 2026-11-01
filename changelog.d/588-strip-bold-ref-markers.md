- `doctor`'s `(ref)` exclusion now sees through bold markup (dir #588). `_strip_ref_citations` matched only a plain
  `dir #N (ref)`, so a bold-wrapped `**dir #N** (ref)` marker still counted as a live citation once
  `extract_dir_tickets` learned to read through `**…**` (dir #578); it now strips the same `**`/`__` markers
  first, in the same sed pass, so both agree on the same text.
