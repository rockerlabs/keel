- **The secret scanner's selftest no longer prints `Broken pipe` on its own (dir #849).** Its fail-closed
  probe fed `grep` through a pipe from `printf`; `grep` exits on the deliberately malformed pattern before it
  reads, so `printf` was sometimes signalled and wrote `write error: Broken pipe` to stderr, which made
  `tests/test_tour_transcript.sh` fail in roughly one run in ten. The probe now reads a file, so no producer
  can be signalled. `tests/test_secret_guard.sh` pins the probe line and that `--selftest` stays quiet on
  stderr. See [`tools/secret-guard/secret-scan.sh`](/tools/secret-guard/secret-scan.sh).
