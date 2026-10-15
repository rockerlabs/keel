- **The runner's SIGTERM and interrupt checks no longer fail when a loaded machine is slow.** The check in
  `tests/test_run_sh.sh` that a SIGTERM'd run exits and kills its fixtures timed kill-to-exit against a
  10 s <!-- claim: hand the check's old bound in tests/test_run_sh.sh, v0.16.0 --> wall-clock bound, and flaked under the parallel release waves' load for four workers in a row
  (dir #592). It is now an event: the run exits within the suite's own hang bound
  (`KEEL_TEST_HANG_BOUND`) and the fixtures' sleeps, now 300 s <!-- claim: hand the fixtures' sleep length in tests/test_run_sh.sh, 2026-10-15 --> long, are gone. A new case runs the same
  scenario against a runner whose exit is made 12 s <!-- claim: hand the stretched exit in tests/test_run_sh.sh, 2026-10-15 --> slow on purpose, so the stretch that used to flake it
  is reproduced rather than waited for. The interrupt-with-a-TERM-ignoring-file case is event-ordered
  the same way.
