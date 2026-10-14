- **`/polish`'s compaction stop continues itself instead of waiting for two operator messages (dir #845).** At
  the context threshold the run still commits and writes its hand-over file, then hands on by the first route
  that applies: a turn the operator started launches a fresh-context successor with `start_session` in the same
  worktree; a managed-release worker sends its manager `COMPACT <token> <hand-over file>` and the manager clears
  the idle session and sends one continuation message; only when the harness refuses does the run end with the
  old two paste-ready lines, naming the refusal. Every route continues with the same skill call, so the
  `after a compaction stop` loop guard still holds. See
  [`commands/polish-guide.md`](/commands/polish-guide.md) § Step 1 and
  [`docs/release-management.md`](/docs/release-management.md) R11.
