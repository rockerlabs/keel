- `install-secret-guard.sh --global` (and `--where --global`) no longer reads a global git config that
  exists but cannot be read — a directory at `~/.gitconfig`, or a mode-000 file — as "unset": `--where`
  prints `read-error=1` and `--global` / `--force` / `--uninstall` refuse with exit 3, writing nothing
  (dir #802).
