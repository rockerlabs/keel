- `tools/secret-guard/secret-scan.sh --range` no longer reads a UTF-16 binary as clean when the host's `grep -i`
  folds a letter of a personal literal to a non-ASCII one (dir #897): on GNU grep in a UTF-8 locale `s` matches
  U+017F and `i` matches U+0131, so the literal `risk` matched `riſk` in the decoded view of a UTF-16 blob, which
  `--tracked` blocked and the `--range` fast path counted as 0. The fast path now keys on the stream, not on the
  literal: a range whose blobs hold no NUL byte keeps it whatever the literals look like (a dotted literal such as
  `micha.ek` over 300 text blobs costs the fast path's two `iconv` calls again, where the dir #761 skip made it run
  the detailed scan), and a range holding a NUL byte with a personal literal set takes the detailed scan. Cost: a
  push that carries a binary now pays the detailed scan for every blob in the range, a plain literal included.
