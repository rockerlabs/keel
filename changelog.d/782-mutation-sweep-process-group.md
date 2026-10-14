- **The mutation sweep bounds a whole test run, not just its first process.** `tools/self/mutation-sweep.sh`
  gave each test run a perl alarm, which killed the test file's bash and left the child that bash was
  waiting on (a `$(…)` running the gate's awk) spinning: one mutant hung a sweep for over three hours
  (dir #782). Each run is now its own process group, signalled as a whole at `KEEL_SWEEP_TIMEOUT` (TERM,
  then KILL five seconds later), so a spinning mutant is recorded TIMEOUT and leaves no process behind. The
  sweep no longer needs perl, so its test file runs on Alpine too instead of skipping itself there.
