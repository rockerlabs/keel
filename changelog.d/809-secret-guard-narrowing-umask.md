- `tools/install-secret-guard.sh` now honours a NARROWING umask when it places the guard's hooks and scanner,
  and still ignores a widening one (dir #809). The placed mode is the fixed one (755 executable, 644 otherwise)
  masked by the caller's umask: under umask 077 the hooks and the scanner are 700 and a non-executable
  `range-lib.sh` is 600 (0.18.0 gave 755/644 there), under 027 they are 750/640, and under 022, 002 and 000
  they stay 755/644, so the 0.16.0 fix against group- or world-writable copies still holds. Pinned by the
  A27 rows in `tests/test_secret_guard_writes.sh`. The installer's comment and that test no longer claim
  v0.15.0's `cp` gave 755/644 "under any umask" (it gave 700/600 under 077).
