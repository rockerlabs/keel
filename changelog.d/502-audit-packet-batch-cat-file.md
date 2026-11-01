- `tools/audit-packet/export.sh` no longer forks `git cat-file` three times per listed file (`-e`, `-s`, `-p`):
  one `--batch-check` pass reads existence, type and size for the whole list and one `--batch` pass per chunk
  streams the contents, so a whole-tree packet costs `1 + <chunks>` git processes instead of `3 x <files>`
  (1344 -> 30 on the 448-file keel tree). Chunks and `MANIFEST.txt` are byte-identical to before (diff-tested);
  the chunk header and first-fit packing are unchanged (dir #502).
