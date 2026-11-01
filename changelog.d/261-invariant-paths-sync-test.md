- A new test, `tests/test_invariant_paths_sync.sh`, cross-checks `DRYDOCK_INVARIANT_PATHS` (exact paths) against
  `DELTA_INVARIANT_PATHS` (substrings) so the two default lists cannot drift apart unnoticed (dir #261). The
  exact-vs-substring match semantics are unchanged; the two legitimate one-sided entries (`keel`,
  `.github/workflows/`) are named in the test, and a stale exception fails it too.
