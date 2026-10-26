- Replacements of `${var/pat/rep}` that interpolate a path are now quoted at every site (`tests/lib.sh`'s ref-guard
  hook, `tools/doctor.sh`, `tools/keel-impact.sh`, `tools/self/citation-resolvability.sh` and three test
  fixtures), so a `&` in `$HOME`, `$TMPDIR` or a repo path no longer turns into the matched text on bash >= 5.2
  (`patsub_replacement`, on by default). Before, `TMPDIR='/tmp/a&b'` wrote the ref guard's refusal record to a
  wrong path, and `HOME='/tmp/h&x'` made `tools/doctor.sh` report a false `G-DIR-MISSING`. A new
  `tests/test_patsub_quoting.sh` fails on any unquoted variable-bearing replacement in `tools/**/*.sh` and
  `tests/lib.sh`, and a `tests/test_lib_ref_guard.sh` row runs the guard under a `&` TMPDIR on bash >= 5.2 (dir #859).
