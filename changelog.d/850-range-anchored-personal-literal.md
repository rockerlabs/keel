- `tools/secret-guard/secret-scan.sh --range` (the pre-push scan) now catches a personal literal that matches only
  in a binary's printable runs: an ERE with an unescaped `^` or `$`, or a `\<` `\>` word boundary (or GNU `\'`), used to read
  clean over a pushed range while `--staged` and `--tracked` blocked the same blob (dir #850). The NUL-stripped
  fast path is now skipped for such a literal, as it already is for a non-ASCII or `.`/bracket one. Cost: an
  adopter with such a literal pays the detailed scan over every blob in the pushed range.
