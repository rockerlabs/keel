- **The secret scanner's fail-closed regex probes no longer print `Broken pipe` on their own (dir #849).** Both
  the selftest's probe and the production check that refuses a malformed personal pattern fed `grep` through a
  pipe from `printf`; `grep` exits on a bad pattern before it reads, so `printf` was sometimes signalled and
  wrote `write error: Broken pipe` to stderr — which made `tests/test_tour_transcript.sh` fail in roughly one
  run in ten, and could land ahead of the scanner's own reason line. Both probes now read a file, so no
  producer can be signalled. `tests/test_secret_guard.sh` pins that no `printf` pipe feeds a `grep` in the
  scanner and that `--selftest` stays quiet on stderr. See
  [`tools/secret-guard/secret-scan.sh`](/tools/secret-guard/secret-scan.sh).
