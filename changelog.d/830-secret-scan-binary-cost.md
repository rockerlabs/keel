- **`secret-scan.sh --tracked` no longer stalls on a large tracked binary** (dir #830). Decoding a binary writes
  several text views and also reads its printable runs; the old recipe put a newline after every non-printable
  byte, so a 20 MiB <!-- claim: hand the generated blob of tests/test_secret_guard_binary_cost.sh, 2026-10-14 -->
  incompressible blob became about 12.6 million <!-- claim: hand lines in the decoded runs view, 2026-10-14 -->
  tiny lines, and the key-shape grep paid a fixed cost on each of them: about 180 s <!-- claim: hand CPU time before the fix, 2026-10-14 -->
  of CPU for the blob, and on a machine under load a `kb-doctor.sh` run that never seemed to finish. The
  key-shape pass now reads no run view (its patterns are unanchored printable ASCII, so every match already
  sits in the NUL-stripped view; a test pins that); the personal-literal passes read the runs squeezed to one
  line per run, in a file of their own. The verdict is unchanged. The same blob now scans in about 40 s <!-- claim: hand CPU time after the fix, 2026-10-14 -->
  of CPU, linear in its size, and a test pins that with a CPU-time ceiling (CPU, not wall-clock: wall-clock
  measures the machine's load, which is what made the stall look endless). `tools/public-audit.sh`'s decode
  carries the same squeeze; it never shared the stall.
