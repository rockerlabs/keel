- `tools/read-trace.sh wrap-done` no longer prints "wrap completion recorded" when the marker could not be
  written (for example an unwritable temp directory): it now reports the failure on stderr and exits 1.
  `docs-line --wrap` made no completion claim, but silently dropped the failed stamp; it now says so on
  stderr and keeps printing its report line with exit 0 (dir #620).
