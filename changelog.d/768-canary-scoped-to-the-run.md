- **The test-suite canary no longer fails a run for a peer's ordinary work in the shared checkout.**
  `tests/run.sh` compares the checkout's refs, config and status before and after a run. A full suite re-run
  cost a release wave about an hour each time it tripped on something the run never wrote (dir #768). The
  canary is now scoped to what the run could have written:
  - **Branches** no worktree has checked out are reported only when a new one appears, or when one is deleted
    or rewritten so that no ref reaches its old tip any more. A sweep of branches that were merged for real,
    or a peer's branch moving forward, no longer trips it. A squash-merged branch deleted by hand still does.
  - **Config:** the tracking keys of a branch whose name has a dot (`release-0.17.0-train1`) are
    per-branch tracking like any other. Only a branch name without a dot was treated that way before.
  - **`TMPDIR` inside the watched checkout** no longer trips the run on its own log directory. The old
    "TMPDIR inside the checkout self-trips" pin is reversed.
  - An own-branch move, a changed `.git/config` key and a stray file elsewhere still trip it.
