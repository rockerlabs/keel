- **A copy-mode block refresh that keeps a `/keel-setup` git-rails trim no longer writes linked-mode advice.**
  The always-on breadcrumb it leaves in `CLAUDE.md` (or `--codex`'s `AGENTS.md`) used to tell the assistant to
  run `install.sh --link --with-git`, which exits 2 in a copy home (and `--link` alone would migrate it). It
  now says to re-add the two trimmed sections from Keel's `CORE.md`, the copy path's own restore; a linked
  `--no-git` home keeps its `--with-git` advice (dir #689).
