- `tools/secret-guard/secret-scan.sh` and `tools/public-audit.sh` no longer read a UTF-16 binary as clean when
  an ASCII personal literal (or, in the audit, a `--token`) uses an ERE dot, bracket expression or class
  escape that stands for a non-ASCII letter (dir #761). The literal `micha.ek` against UTF-16LE `Michałek`
  left `MichaB\x01ek` in the NUL-stripped view, so `--range`'s fast path counted 0 and skipped the detailed
  scan; on a host whose iconv cannot resume (musl) the built-in decoder, gated on a non-ASCII literal, never
  ran. Both tools now share one classifier, `needle_wide`, that turns the decoder on and skips the fast path,
  and a pin in `tests/test_secret_guard.sh` keeps the two copies equal. Cost: a push with such a literal
  runs the detailed scan of every blob, which takes seconds where the fast path took a fraction of one.
