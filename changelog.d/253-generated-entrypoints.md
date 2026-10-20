- No Keel installer rewrites an entrypoint another tool generates (dir #253, slice 1). A context file whose line 1
  begins `<!-- KEEL-GENERATED` is generator-owned: `install.sh` (every mode, `--codex` too) leaves it byte-identical
  with no prompt and no manifest edit record, `uninstall.sh` leaves its rails in place, and `doctor.sh --install` names
  it and gives the generator's remedy (regenerate) instead of an `install.sh` run. This closes the `install.sh --link`
  hazard that swapped a generated file's embedded rails for an import line. `ADAPTING.md` gains "Generating your
  entrypoints yourself" (the marker and the `KEEL-*` names Keel reads).
- `install.sh --link` now auto-swaps (or auto-removes) an embedded KEEL-CORE block only when the prior manifest
  recorded it as Keel's own copy-install block (dir #253). A block Keel did not record (a hand copy, another tool's
  file, an install older than its manifest) is offered on a terminal and left untouched otherwise, except when the
  file already holds the import line beside a block identical to Keel's: that case is never offered, only reported;
  a drifted block keeps its existing path. After a plain `install.sh`, `--link` migrates a copy home as before.
