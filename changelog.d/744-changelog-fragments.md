- **A PR's changelog entry is now a file of its own under `changelog.d/`, not a bullet at the top of
  `[Unreleased]` (dir #744 slice 1).** Two PRs that each added a bullet at that one anchor conflicted, and a
  PR that fell behind turned DIRTY with no CI run; two PRs that each add their own file do not.
  `changelog.d/README.md` states the rules; `tools/self/changelog-fragments.sh` reads and lints the directory
  (`--check`); `tools/self/changelog-cut.sh VERSION DATE` is the release cut as one deterministic command,
  and [`docs/release-audit.md`](/docs/release-audit.md) Phase 7 now names it. This entry is itself the first
  fragment. Bullets already under `[Unreleased]` stay valid beside fragments.
- **The checks that read the changelog read the fragments too (dir #744 slice 1).** `tools/self/doctor.sh`
  matches a commit's `dir #N` against `[Unreleased]` and the fragments, and takes the newest commit touching
  either as the changelog's age; the five tests that pin a changelog cite read `CHANGELOG.md` plus the
  fragment reader's output; the delta-audit, audit-packet, drydock and line-citation tools class a fragment as
  history, like `CHANGELOG.md`; the pre-PR gate keeps `changelog.d/` in the tests-receipt hash; and `/go`'s
  seam step scans fragments for numeric claims. The wave-plan prose in
  [`docs/release-management.md`](/docs/release-management.md) R2 and `commands/manage-release.md` M3 no longer
  assumes every PR collides in `CHANGELOG.md`.
