- Test-only: two status gates are now pinned. `tests/test_public_audit.sh` requires `--no-history --token '['`
  and `'('` to exit 1 with the `GAP  could not search the tracked tree for` prefix (a `pa_match` that always
  returned 0 used to leave the suite green), and `tests/test_secret_guard.sh` requires the scanner's
  personal-list grep to run under `LC_ALL=C` (dir #797).
