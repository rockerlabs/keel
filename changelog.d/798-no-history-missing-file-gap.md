- `tools/public-audit.sh --no-history` now reports a tracked file that is missing from the working tree
  (`tracked file '…' is missing from the working tree`) even with no `--token` and no personal-literal file,
  where it used to print "no publication blockers found"; with a token the line still prints exactly once
  (dir #798).
