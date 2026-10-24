- Four checked-in mutant lists now cover guard suites beyond the pre-PR gate (dir #764):
  `tests/mutants/safe-write.tsv` (the never-clobber rules of the shared write library),
  `tests/mutants/manifest.tsv` (the link-record predicates uninstall and install ask),
  `tests/mutants/install-never-clobber.tsv` and `tests/mutants/install-product-dirs.tsv` (the installers'
  refusals to write into, or move a file out of, the Keel checkout). Each is swept with
  `tools/self/mutation-sweep.sh <list> <test file>` and kept current by `tests/test_mutation_lists.sh`.
  The sweep found clauses no test guarded; `tests/test_safe_write.sh` and `tests/test_manifest_lib.sh`
  now pin them (a hop-count bound, an exclusive backup name, UTC backup names, the checkout predicate's
  `..` and link handling, and the link-record predicate's clauses).
