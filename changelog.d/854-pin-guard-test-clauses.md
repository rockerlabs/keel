- Test-only: three previously unpinned clauses of two guards are now pinned. `tests/test_secret_guard_binary_cost.sh`
  requires the secret scanner's personal-list grep to still read the unfiltered-run file when the `iconv`
  sanitizer fails (a stub `iconv` makes that case deterministic), and `tests/test_bypass_scan.sh` requires
  `bypass-scan.sh` to refuse `--out` inside a second git work tree, inside a checkout that is not a work tree, and a
  `TMPDIR` inside a work tree. The old "inside ANY git work tree" row never created its second repository and passed
  only because the file could not be written (dir #854).
