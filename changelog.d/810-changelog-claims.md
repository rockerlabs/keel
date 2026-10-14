- **Changelog: numbers in the text are re-derived or listed (dir #810).** `tools/self/changelog-claims.sh` reads
  the changelog fragments and `CHANGELOG.md`'s `[Unreleased]` (or one section, `--section x.y.z`) and finds
  every numeric claim. A `<!-- claim: words|lines|matches … -->` marker on the same line binds a number to a
  source the tool re-derives (a stale one is a MISMATCH and fails); `claim: hand` carries a measurement or a
  history number with its as-of; a number with no marker is listed UNBOUND and fails at the cut under
  `--strict`. The four 0.16.0 claims that shipped wrong or nearly did are the tool's test fixtures.
  `changelog.d/README.md` has a new Numbers section, and the cut (`docs/release-audit.md` Phase 7), the
  correction round (`docs/delta-audit.md` §10) and `docs/release-management.md` name the tool.
