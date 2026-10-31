- The 0.18.0 audit's six known-bypass entries now sit in their registers (dir #885): A02 (a one-string
  `check-run.sh` command whose pipe or `;` masks its red, or an `update-index --assume-unchanged|--skip-worktree`
  edit) and A03 (a receipt bound by a run on uncommitted edits) in `tools/pre-pr-gate.sh`, A09 (a byte-order mark
  before the generated marker) and C02 (two unpinned clauses of `keel_context_is_generated`) in
  `tools/lib/safe-write.sh`, C06 (`cksum_of` on a missing file) and C04 (`para_of`'s `awk -v` needle) in
  `tests/lib.sh`. Only A02 carries a `[bypass:]` key, `gate-pr:check-run-masked-exit`, with a shape row in
  `tools/self/known-bypass-shapes.tsv`; A03 is a tree state and carries none. Comments and registers only: no
  behaviour changes. A02 stays disclosed as known issue K2 until its fix lands.
