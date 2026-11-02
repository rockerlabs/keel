- Prose: reflowed every over-long verification block in `docs/release-history.md` to about 100 columns, with no
  wording changed (the blocks for v0.10.2 and v0.11.0 were single lines of 3.5 and 5.9 KB). `tests/test_release_history.sh`
  now bounds each verification-block line at 100 characters and pins the check with fixtures (dir #632).
