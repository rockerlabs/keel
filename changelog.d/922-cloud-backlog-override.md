- The cloud route reaches a project whose tickets live outside `BACKLOG.md` and whose tests the VM cannot run
  (dir #922). `CLOUD_BACKLOG` names the backlog file directly for the brief, `--check`, `--sweep` and
  `--dispatch` (unset: today's resolution; set but not a readable regular file: exit 2).
  The protocol's step (e) now falls back to the draft PR's CI when the VM lacks what the test command needs:
  the session reads the pushed head's `check-runs` through REST in a bounded loop (every 2 minutes, at most
  60 minutes per push) and names in the PR's Checks which checks only CI ran.
  [`docs/cloud.md`](/docs/cloud.md) gains the `CLOUD_BACKLOG` row and G4's CI clause.
