- **A release train and the manager's merge are now a procedure, `docs/release-management.md` R14.** In a
  managed release the manager lands the slate as trains it builds, seam-reviews and merges itself, where the
  project's own `CLAUDE.md` carries a `KEEL-MANAGER-MERGES` line (dir #811, the procedure slice: the text only; the
  gate that enforces it, the operator's settings edits and the build tool follow in later slices). R14
  carries the preconditions for every merge (CI green on the exact head, the worker's literal `no more
  pushes; ok`, no correction in flight, a merge commit with `--match-head-commit`), the build of a train
  with plain git (`git merge-tree` over every pair, `--no-ff` merges of each frozen head as is, an ancestor
  check), a seam review sized from the seam rather than the diff, the rebuild bound, and the fallback in
  which the operator still merges. The Operator row of the Roles table now holds decisions only, R2, R9 and
  R10 point at R14, `commands/manage-release.md` gains M7a, `docs/delegation.md` calls the operator's scarce
  resource decision bandwidth, `SECURITY.md` scopes "never merge autonomously" to outside a release manager's
  gated merge, and `/polish`'s guide (§ Step 4) points at R14's rule that a train always opens the depth dialog.
  Standalone sessions never merge, unchanged.
