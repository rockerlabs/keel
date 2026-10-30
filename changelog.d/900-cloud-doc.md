- The cloud route gets its rulebook and its command text (dir #900, slice 2; the tools shipped in slice 1).
  [`docs/cloud.md`](/docs/cloud.md) describes the opt-in `KEEL-CLOUD` line, the `**Cloud:**` verdict line, the
  eligibility rows G1 to G9, what `tools/cloud-brief.sh` and `tools/cloud-land.sh` do as shipped (the CLI runs
  under a pseudo-terminal, steering is the web view or `claude --cloud <session id>`, the landing check
  refuses a PR whose base is not the default branch and needs at least one successful check), who may
  dispatch, the release manager's route column, the ledger and `--sweep`, and abandoning a dispatch.
  `/go` offers the cloud on a `**Cloud:** yes` ticket in a project that opted in, and says nothing of it inside
  a managed release; its word budget rises to
  1305 <!-- claim: hand 2026-10-30 -- GO_MD_WORD_BUDGET in tests/test_go_command.sh --> (the operator's decision,
  GO11). `/backlog`'s legend and headline discipline name the verdict line and who writes it; `/groom` fills missing verdicts;
  [`docs/release-management.md`](/docs/release-management.md) R1 to R3 and `/manage-release` M2 to M4 gain
  the intake, route-column and launch duties, and [`docs/delegation.md`](/docs/delegation.md) names the cloud
  worker's own gate. `tests/test_cloud_doc.sh` pins the doc and its pointers.
