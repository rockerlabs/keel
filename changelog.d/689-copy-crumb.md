- **A copy-mode block refresh that keeps a `/keel-setup` git-rails trim no longer writes linked-mode advice.**
  The always-on note it leaves in `CLAUDE.md` (or `--codex`'s `AGENTS.md`) used to tell the assistant to run
  `install.sh --with-git` (which exits 2 in a copy home) or `--link --with-git` (which would migrate it). It now
  says to replace the embedded rails block with the one in Keel's `CORE.md`, which brings back both trimmed
  sections and drops the note; `/keel-setup` gives the same copy-path advice. A copy home whose earlier
  refresh left the linked note no longer reads as up to date: `install.sh` offers the trim-keeping refresh,
  and `doctor.sh` warns. A linked `--no-git` home keeps its `--with-git` advice (dir #689).
