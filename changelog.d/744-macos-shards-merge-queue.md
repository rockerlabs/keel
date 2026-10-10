- **CI's macOS leg runs as two shards, and every required check runs on the merge queue's event (dir #744
  slice 3).** `tests/run.sh` gains `KEEL_TEST_SHARD=K/N`: it runs shard K's share of the test files, assigned
  size-greedy by byte size so the shards come out near-even and every file runs exactly once, prints
  `shard K/N: <m> of <total> test files`, refuses a malformed value before any file runs, and removes the
  variable so a nested runner sees all of its own fixtures. `ci.yml` runs macOS as `tests (macos-14, shard 1/2)`
  and `… 2/2`; an aggregator job on ubuntu reports the one required name, `tests (macos-14)`, green only when both
  shards succeed, so branch protection needs no change. `on:` gains `merge_group:`, and
  `tools/secret-guard/ci-scan.sh` scans a merge group's base..head exactly like a pull request — the
  prerequisite for turning on GitHub's merge queue.
