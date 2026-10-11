- **The secret-guard installer's files no longer depend on your umask, and the changelog cut refuses instead of dropping fragments.**
  Found by the 0.16.0 delta audit (S7-1, S11-4). `tools/install-secret-guard.sh` now places the hooks and the
  scanner with mode 755 (the library `range-lib.sh` 644) under any umask; since the rename-based write landed they
  came out group-writable under umask 002 and world-writable under umask 000, where 0.15.0 gave 755/644.
  `tools/self/changelog-fragments.sh` now exits 2 (`could not list changelog.d/`) when `git ls-files` fails, rather
  than reading it as "no fragments" — the cut used to write the release section without them and exit 0.
