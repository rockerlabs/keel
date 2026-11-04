- Mutation-blind assertions in the test suite now fail under the mutation they were written to catch
  (dir #239). The gate suite's composed-marker leak sweep no longer folds a failed `git grep` into "no matches":
  it fails when the sweep cannot run, and two controls (a directory with no `.git`; a tracked file that spells a
  marker) make the clean result falsifiable. The self-prose-drift test gains the negative companion for a
  leading-hyphen anchor, so skipping validation for such anchors goes red. The public-audit overflow-cap test
  gains a blob larger than the documented default cap, for both the history and the working-tree pass, so a larger
  fallback goes red. A defensive absence check on a message the sweep's awk path cannot emit was dropped.
  One more item from the ticket was already fixed: the changelog-section scratch-file survival check exists
  and goes red when the cleanup trap is not cancelled. Test-only; no tool changed.
