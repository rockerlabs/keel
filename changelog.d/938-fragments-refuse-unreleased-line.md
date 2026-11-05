- `tools/self/changelog-fragments.sh --check` now refuses a line a PR adds under `CHANGELOG.md`'s
  `## [Unreleased]` (dir #938). A ticket filed before dir #744 that says "CHANGELOG entry" had been read
  literally and passed this check and CI; the refusal names the file and line and points at `changelog.d/`.
  The release cut empties that section, so it is not refused. The diff base is `--base REV`, else CI's
  `GITHUB_BASE_SHA`, else `origin/HEAD` or `origin/main`; with no base to be had (a shallow clone, no remote, or
  main itself) the rule passes quietly. The CI self-check job now runs the check with the PR's base.
