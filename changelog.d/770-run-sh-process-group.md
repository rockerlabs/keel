- **`tests/run.sh` signals a test file's whole process group, so a killed or interrupted file leaves nothing
  running.** The per-file watchdog and the interrupt handler signalled only the file's own bash, so a
  `sleep` or holder it had started kept running after a timeout or Ctrl-C (dir #770). Each file now
  starts as the leader of its own process group, and the watchdog, the reap and `on_interrupt` signal
  that group: TERM, then KILL for a file or child that ignores it. `on_interrupt` gains the KILL step the
  watchdog already had (a 5 s grace, then KILL, then exit 130). The mechanism is pure bash, so it works on
  stock macOS and Alpine alike, and it is the same one `tools/self/mutation-sweep.sh` uses. A test
  file's stdin is now `/dev/null` rather than the runner's.
