- `read-trace aggregate` no longer prints "nothing in this repository is in the trace's scope" for a repo
  whose `docs/` or `commands/` is a symlink, or holds only symlinked files: the scope scan follows
  symlinks (dir #803).
