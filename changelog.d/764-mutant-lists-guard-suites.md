- Five checked-in mutant lists now cover guard suites beyond the pre-PR gate (dir #764):
  `tests/mutants/secret-scan.tsv` (the scanner's fail-closed rules), `tests/mutants/safe-write.tsv` (the
  never-clobber rules of the shared write library), `tests/mutants/manifest.tsv` (the link-record
  predicates uninstall and install ask), and `tests/mutants/install-never-clobber.tsv` and
  `tests/mutants/install-product-dirs.tsv` (the installers' refusals to write into, or move a file out of,
  the Keel checkout). Each is swept with `tools/self/mutation-sweep.sh <list> <test file>` and kept current
  by `tests/test_mutation_lists.sh`. The sweep found clauses no test guarded; `tests/test_secret_guard.sh`,
  `tests/test_safe_write.sh` and `tests/test_manifest_lib.sh` now pin them.
  Sweep `safe-write.tsv` as an ordinary user (two of its rows are killed only by checks the root leg skips),
  and expect `secret-scan.tsv` to take about an hour: its suite runs about a minute per mutant.
