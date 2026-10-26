- `keel tokens --session <uuid>` now finds the transcript when the projects root is a symlink (`find` was
  given the root without a trailing slash and did not descend), and no longer pipes `find` into `head`.
  `keel tokens --help` / `-h` now prints the usage without jq (dir #769).
