- `tools/self/pool-report.sh` now reports the oldest pool entry's age from midnight UTC on macOS too (BSD
  `date -j -f` filled the time of day from the clock, so the age read one day short); its test freezes "now"
  and asserts the exact age (dir #804).
