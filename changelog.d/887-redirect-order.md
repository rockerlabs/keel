- Input redirects now come after the stderr redirect (`cmd 2>/dev/null < file`) at eleven sites in `tools/doctor.sh`,
  `tools/install-secret-guard.sh`, `tools/keel-check.sh`, `tools/lib/attr-binary.sh`, `tools/public-audit.sh` and
  `tools/secret-guard/secret-scan.sh`, so an unreadable file no longer leaks the shell's own "Permission denied" line
  (dir #887). `keel-check.sh` also silences the failed `> "$state"` open. `secret-scan.sh` also silences `cmp` in `is_binary_file`, and its read-capture now lands the failed
  open in the error file `_fail_closed` reads. A new lint, `tests/test_redirect_order.sh`, refuses the old order.
