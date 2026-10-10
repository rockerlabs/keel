- **`tools/self/cut-sim.sh` runs the suite on the cut shape of the changelog, and CI runs it as a non-required
  `cut-simulation` job (dir #722, dir #744 slice 4).** The 0.14.0 delta audit found three tests that pinned
  `## [Unreleased]` shipping to the release candidate, because nothing ran the suite after the cut moved that text
  under a dated heading. `cut-sim.sh [--repo DIR]` clones DIR's `HEAD` into `${TMPDIR:-/tmp}/keel-cut-sim.XXXXXX`,
  runs the clone's `tools/self/changelog-cut.sh` as `9999.0.0` with today's UTC date, commits that under a fixed
  identity and runs the clone's `tests/run.sh`, printing `PASS` or `FAIL` (exit 0, 1). It never writes to DIR,
  removes the clone on every exit path including a signal, and refuses with exit 2, naming `fetch-depth: 0`, when
  DIR has no `v*` tag. The `cut-simulation` job (`ubuntu-24.04`, `fetch-depth: 0`, 20-minute timeout) is not a
  required check; requiring it is the operator's branch-protection call. `docs/release-audit.md` Phase 7's cut
  paragraph names the check to run before the cut PR is opened.
