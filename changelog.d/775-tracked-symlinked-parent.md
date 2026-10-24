- `tools/secret-guard/secret-scan.sh --tracked` no longer reads a committed key as clean when the file's
  parent directory has been replaced by a symlink (dir #775). The working file read through the link is the
  target's, so the committed blob was never scanned; a tracked path whose parent chain crosses a symlink now
  has its target content and its index copy both scanned, with a WARN naming each such path. A blob git cannot
  read still exits 2.
