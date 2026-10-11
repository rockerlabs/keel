- **`docs/release-management.md`: practice corrections from the 0.15.0 and 0.16.0 managed releases, each written at
  its requirement (R2, R3, R6–R11).** They cover the cost of sequential merges and how an integration or train PR
  is built, a launch needing an operator-started turn, a cap on cross-session sends, a checked backlog writer, a
  stacked cut PR, seam plans for both merge orders, and the sweep, stop and concurrency rules of R11.
  `commands/manage-release.md` and `commands/groom.md` carry matching pointers, and `docs/delta-audit.md`'s
  mutation-leg `df` floor now names a value. dir #760.
