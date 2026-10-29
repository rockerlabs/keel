- [`tools/self/prose-drift.sh`](/tools/self/prose-drift.sh): the line-length signal no longer holds one open
  file descriptor per scanned file on macOS's bash 3.2, which keeps a process substitution's descriptor open
  until the enclosing function returns (dir #904). With the repo's current count of tracked shell scripts one
  descriptor reached bash 3.2's `dev_fd_list` off-by-one, a one-byte heap overwrite that crashed the script at
  random on the macos-14 runners (SIGABRT, exit 134 from `tests/test_self_prose_drift.sh`, and an
  `Abort trap: 6` inside `tools/self/doctor.sh`). Each file's hits are now captured before they are read, and
  a new test runs the signal over a fixture under a low open-file limit, where a leaking loop leaves files
  unscanned.
