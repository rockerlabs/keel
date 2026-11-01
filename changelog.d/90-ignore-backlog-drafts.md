- The tracked `.gitignore` now ignores `/BACKLOG.drafts/` next to `/BACKLOG.md`. Before, a `/design` draft ticket
  sitting in the main checkout was untracked but not ignored, one `git add -A` away from a commit in a
  publication-first repo (dir #90).
