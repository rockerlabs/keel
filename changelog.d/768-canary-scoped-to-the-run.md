- **The test-suite canary no longer fails a run for a peer's ordinary work in the shared checkout.** `tests/run.sh`
  compares the checkout's refs, config and status before and after a run, and a full suite re-run cost a release
  wave about an hour each time it tripped on something the run never wrote (dir #768). It is now scoped to what the
  run could have written. Among branches no worktree has checked out, it reports a new one, or one whose old tip no
  ref reaches any more; a branch-cleanup sweep of merged branches or a peer's branch moving forward no longer
  trips it. A tracking key of a dotted branch name (`release-0.17.0-train1`) is per-branch tracking like any other,
  where before only a branch name without a dot was. A `TMPDIR` inside the watched checkout no longer trips the
  run on its own log directory (the old "TMPDIR inside the checkout self-trips" pin is reversed). An own-branch move,
  a changed `.git/config` key and a stray file elsewhere still trip it.
