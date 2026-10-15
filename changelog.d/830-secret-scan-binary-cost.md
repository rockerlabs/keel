- **`secret-scan.sh --tracked` no longer stalls on a large tracked binary** (dir #830). Decoding a binary writes
  several text views and also reads its printable runs; the old recipe put a newline after every non-printable
  byte, so a 20 MiB <!-- claim: hand the generated blob of tests/test_secret_guard_binary_cost.sh, 2026-10-14 -->
  incompressible blob became about 12.6 million <!-- claim: hand lines in the decoded runs view, 2026-10-14 -->
  tiny lines, and the key-shape grep paid a fixed cost on each of them: about 180 s <!-- claim: hand CPU time before the fix, 2026-10-14 -->
  of CPU for the blob (no personal literal set), and on a machine under load a `kb-doctor.sh` run that never seemed to finish. The
  key-shape pass now reads no run view (its patterns are unanchored printable ASCII, so every match already
  sits in the NUL-stripped view; a test pins that); the personal-literal passes read the runs squeezed to one
  line per run, in a file of their own. The verdict is unchanged. On macOS (BSD grep) the same blob now scans in about 40 s <!-- claim: hand CPU time after the fix, macOS BSD grep, no personal literals, 2026-10-14 -->
  of CPU with no personal literal set (about 55 s <!-- claim: hand CPU time after the fix, macOS BSD grep, two literals, 2026-10-14 -->
  with two; each literal adds to it), linear in its size, and a test pins that with a CPU-time ceiling (CPU, not
  wall-clock: wall-clock measures the machine's load, which is what made the stall look endless). busybox grep (the
  Alpine leg) is markedly slower per pass, so there the test bounds a smaller blob and the large-blob ceiling binds
  on the macOS legs; the scan still finishes, only more slowly. `tools/public-audit.sh`'s decode
  carries the same squeeze; it never shared the stall.
  The same change also fixes a fail-open on Alpine/busybox that predates it: the printable-runs view was read with
  `tr` and the class `[:print:]`, which busybox `tr` takes literally, so every byte became a newline and a
  personal literal anchored with `^` or `$` inside a binary was missed there (at v0.16.0 the scan read clean). The
  runs are now read with the range `' -~'`, in `secret-scan.sh` and in `tools/public-audit.sh`'s decode alike; an
  Alpine adopter who installed the guard at 0.16.0 gets a tightened guard.
