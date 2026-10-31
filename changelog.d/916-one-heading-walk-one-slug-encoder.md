- Internal consolidation (dir #916): the wrapped-heading walk of BACKLOG.md tickets is one `bb_heading_end` in
  `tools/lib/backlog-blocks.sh` (used by the lib, the keel doctor check, the observer-class closure lookup and
  `tools/cloud-brief.sh`), and Claude Code's project-directory name is encoded by one `keel_project_slug`
  (`tools/lib/project-slug.sh`) for `cloud-brief.sh`, `keel tokens` and the memory checks of `keel doctor`.
  The encoder now writes every byte outside `[A-Za-z0-9]` as `-` (a space or `_` in a project path used to be kept
  by `keel tokens` and `keel doctor`, so their lookup missed the real directory).
