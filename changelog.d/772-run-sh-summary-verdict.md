- **`tests/run.sh` fails a test file that never printed its own verdict.** A file that sourced `tests/lib.sh`
  and ended without calling `summary` was judged by its last command's exit status, so FAIL lines in its log
  still counted as a pass. The 0.16.0 alpine leg shipped three red checks green that way (dir #772). The run now
  reads each green-exiting file's log for its own `<file>: N passed, M failed` line and counts a file without
  one as failed, naming it. The check lives in the runner, so it holds on macOS and Alpine alike and whatever a
  file did with its own EXIT trap. A watchdog-killed file still reads as timed out. A file that does not source
  `lib.sh` owes no summary, and a new test pins that every file in `tests/` does source it and calls `summary`.
