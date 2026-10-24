- Five checked-in mutant lists now cover guard suites beyond the pre-PR gate (dir #764):
  `tests/mutants/secret-scan.tsv` (the scanner's fail-closed rules), `tests/mutants/safe-write.tsv` (the
  never-clobber rules of the shared write library), `tests/mutants/manifest.tsv` (the link-record
  predicates uninstall and install ask), and `tests/mutants/install-never-clobber.tsv` and
  `tests/mutants/install-product-dirs.tsv` (the installers' refusals to write into, or move a file out of,
  the Keel checkout). Each is swept with `tools/self/mutation-sweep.sh <list> <test file>` and kept current
  by `tests/test_mutation_lists.sh`. The sweep found clauses no test guarded; `tests/test_secret_guard.sh`,
  `tests/test_safe_write.sh` and `tests/test_manifest_lib.sh` now pin them.
