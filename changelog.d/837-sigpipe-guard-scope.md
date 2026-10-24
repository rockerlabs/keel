- The SIGPIPE-race guard (`tests/test_no_pipe_sigpipe_race.sh`) now also scans `install.sh`, `uninstall.sh`,
  `bootstrap.sh`, `keel` and the `tools/secret-guard/pre-commit` and `pre-push` hooks, and matches the
  consumer spellings `/usr/bin/grep -q`, `command grep -q`, `ggrep -q`, `rg -q` and `grep -e pat -q`
  (dir #837). No live miss was found in the newly scanned files.
