- **`tools/self/citation-resolvability.sh` now reads the unreleased changelog text, and flags a PR number written as a ticket (dir #729).**
  Besides `docs/*.md` it scans CHANGELOG.md's `[Unreleased]` section and the `changelog.d/` fragments (released
  sections stay out: their aged-out citations are history). A cited `dir #N` that resolves to no ticket is
  DEAD as before; when that number is also a merged PR number in the repo's history the line says so, since
  four PR numbers were written as tickets in one 0.14.0 fix brief. The PR-number match is a hint on a DEAD
  line, never a finding of its own: ticket and PR numbers overlap, and with no `BACKLOG.md` (gitignored,
  maintainer-side) the check skips, as it always did.
