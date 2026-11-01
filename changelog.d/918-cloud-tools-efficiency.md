- The cloud tools are leaner and the landing refusal is truer (dir #918). `cloud-brief.sh` fills the protocol
  template with its own byte-wise `rewrite` (pairs passed through awk's ARGV, no numbered environment
  variables), `--sweep` forks no `grep` per heading, and `cloud-land.sh` reads each ref once, by the clone.
  The VM push guard drops its redundant `(delete)` arm (the all-zero-sha arm refuses a deletion). A refusal for
  an added allow marker now says that fixing forward cannot clear it (only a rewritten or fresh branch can), in
  `docs/cloud.md` too, and the cloud tools and tests spell the marker split. Test helpers: `path_farm` links per
  directory, and the two cloud test files share one `cell`/`set_cell`.
