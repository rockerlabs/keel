- New `tools/effort-share.sh` (dir #635): counts the commits of a caller-named meta set and product set of
  repositories since a date or a ref, and prints each repository's count and the meta share. One counting
  definition, stated in `--help` together with its honest limit: the unique commits reachable from any ref,
  merge commits excluded; commits are a proxy for effort and commit granularity differs across projects.
  A ref is resolved in every repository and refuses, naming the repository, where one lacks it; a `--since`
  that is neither a valid date nor a ref refuses instead of reading as an empty period; a path that is not
  a git repository refuses; no commits at all prints `n/a`, never `0%`. `--json` needs no `jq`. Nothing
  about any project is hard-coded: the caller passes both lists. Tests in `tests/test_effort_share.sh`.
- The grooming procedure's cross-run record in [`docs/grooming.md`](/docs/grooming.md) gains one field for a
  project that is infrastructure for other projects, and only for such a project: the meta share since the
  previous groom with its ledger colour. The retro phase reads the previous row's value. The threshold is
  project-set; two consecutive readings above it restrict the next release to rows that meet one of the
  first four conditions of the filing bar in the verification-economics doc, so a row that is only a
  requested capability waits. Pinned in `tests/test_grooming_doc.sh`.
