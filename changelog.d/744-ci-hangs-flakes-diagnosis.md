- **A hung test file no longer holds a CI job for six hours, and a slow machine no longer fails the suite
  (dir #744 slice 2).** `tests/run.sh` gains a per-file watchdog (`KEEL_TEST_FILE_TIMEOUT`, 600 s under CI,
  off locally; it prints `watchdog: <N>s` up front and `=== <file> (timed out after <N>s) ===` with the file's
  log so far) and ends every run with the five slowest files. Every CI job sets `timeout-minutes`, sized to
  its leg. `tests/test_run_sh.sh` proves its concurrency checks by a peak count and times only kill→exit,
  never runner start-up; each test that waits for a background process takes its bound from
  `KEEL_TEST_HANG_BOUND` (120 s) in whole seconds, linted by `tests/test_suite_hygiene.sh`.
- **The test sandbox explains its own failures (dir #744 slice 2).** `tests/lib.sh` turns off git's
  detached auto-maintenance for every test (appended to the `GIT_CONFIG_COUNT` triple, so an inherited entry
  survives); a sandbox teardown that fails names what survived and which processes held it, then retries
  once; and `check_status_out` prints the command's output when a status check fails, used by the
  self-doctor smoke and the token-report `--since` case.
