- Four test-binding gaps found by live mutation are closed (dir #292). The "consumer sources the shared library"
  pins for the leak-pattern, safe-email, ticket-extraction and non-negative-integer libraries now use a new
  `check_sources` helper in `tests/lib.sh` that needs an executable `.` or `source` line, so the
  `# shellcheck source=` pragma no longer satisfies them and deleting the real sourcing line turns them red. The
  doctor test's two absence checks on a retired message are replaced by the invariant they guarded: no
  worktree-local `.keel/` directory is created. The pipe-race guard's `|| true` exemption no longer depends on an
  exact end of line, so trailing blanks and a carriage return keep it. The `keel sync` verb, which no test ran,
  now has a behavioural test against a local upstream with no network: pull first, then install with the caller's
  arguments and exit code, and a non-fast-forward checkout still re-wires with a warning. Test-only; no tool
  changed.
