- `docs/release-management.md` (R14) and `commands/manage-release.md` (M7a) now say to launch a release
  manager without `--agent` (dir #862). A main session started with `--agent` carries `agent_type` with no
  `agent_id`, so the merge rule reads it as a subagent and refuses its merge. The gate is unchanged; the
  documentation route was taken over keying the subagent test on `agent_id` alone.
