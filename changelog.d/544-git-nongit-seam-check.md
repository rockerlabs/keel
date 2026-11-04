- The delta audit and the release-management pattern now name the git × gitignored-file seam as a procedural check
  (dir #544). A merged PR whose premise lives in a gitignored, manager-owned file (a project's `CLAUDE.md`,
  `BACKLOG.md`) can be invalidated after the merge by that file's own edit, and the audit's git-derived universe
  never shows it. The starting brief now carries a `Non-git inputs:` line, the orchestrator snapshots each listed
  file's post-cut state at the anchor, one named leg diffs the merged prose against it, and the verifier checks that
  leg ran (in [`docs/delta-audit.md`](/docs/delta-audit.md): the anchor procedure, the Protocol's seam-duty rule and the leg prompts). In
  [`docs/release-management.md`](/docs/release-management.md), R9 carries the brief line and the release-row risk
  list duty, R10 names the seam, and R11's sweep before each merge re-reads the listed files.
