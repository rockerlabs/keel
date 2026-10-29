- New [`tools/self/procsub-leak.sh`](/tools/self/procsub-leak.sh) (dir #905) flags the open-file leak behind
  dir #904's macos-14 crash wherever it occurs. The leak is a process substitution that macOS's bash 3.2 holds
  open once per loop pass inside a function. That covers `done < <(…)` and the other compound or built-in
  forms (`source <(…)` and a function whose whole body is redirected among them), plus a call, in a loop,
  to a function that opens one per call; the check follows such calls across files. It lets bash parse each
  script (via `declare -f`), so comments never trip it, and it skips here-documents and subshells. It has no
  allow-list, and `tests/test_self_procsub_leak.sh` runs it over keel's own tree. On a host whose `/bin/bash`
  is that old bash, the test also re-measures which shapes leak. Known limit: some nested quoting still
  makes the reader lose its place before a file ends, and such a file is not yet reported (dir #906).
- Every site the new check flagged is fixed the dir #904 way: the output is captured, then read from a
  here-string. They are in `tools/doctor.sh` (`memory_checks`, `alwayson_chain`),
  `tools/self/session-cost.sh` (`table`, `tail`), `tools/token-report.sh`, `tools/lib/transcript-usage.sh`
  (`tu_session_totals`), `tools/machine-watch.sh`, `tools/state-root-migrate.sh` and four test files. Two
  leaked in practice: `doctor.sh --memory-age` held one descriptor per memory note (a peak of
  107 <!-- claim: hand lsof peak over this repo's own 101-note memory dir, 2026-10-29 --> on a real memory dir), and
  `session-cost.sh table` held one per manifest line. Both now stay flat, and each has a test that runs it
  under `ulimit -n 64` on `/bin/bash`. In the other sites an external command in the loop body happened to
  close the descriptors, which bash 3.2 does as a side effect, so their leak stayed hidden.
