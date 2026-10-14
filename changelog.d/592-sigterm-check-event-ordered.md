- **The runner's SIGTERM and interrupt checks no longer fail when a loaded machine is slow.** The check in
  `tests/test_run_sh.sh` that a SIGTERM'd run exits and kills its fixtures timed kill-to-exit against a
  10 s wall-clock bound, and flaked under the parallel release waves' load for four workers in a row
  (dir #592). It is now an event: the run exits within the suite's own hang bound
  (`KEEL_TEST_HANG_BOUND`) and the fixtures' sleeps, now 300 s long, are gone. A new case runs the same
  scenario against a runner whose exit is made 12 s slow on purpose, so the stretch that used to flake it
  is reproduced rather than waited for. The 15 s bound on the interrupt-with-a-TERM-ignoring-file case
  went the same way.
