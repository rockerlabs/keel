- **`secret-scan.sh --tracked` no longer stalls on a large tracked binary** (dir #830). Decoding a binary writes
  several text views and also reads its printable runs; the old recipe put a newline after every non-printable
  byte, so a 20 MiB incompressible blob became about 12.6 million tiny lines and the class-1 grep paid a fixed
  ~12 µs on each of them: ~180 s of CPU for the blob (~250 s with the operator's personal literals), and on a
  machine under load a `kb-doctor.sh` run that never seemed to finish. Class 1 now reads no run view (its
  patterns are unanchored printable ASCII, so every match already sits in the NUL-stripped view; a test pins
  that); the personal-literal passes read the runs squeezed to one line per run, in a file of their own. The
  verdict is unchanged. The same blob now scans in ~45 s of CPU (~60 s with personal literals), linear in its
  size, and a test pins that with a generated 20 MiB blob and a CPU-time ceiling (CPU, not wall-clock:
  wall-clock measures the machine's load, which is what made the stall look endless).
  `tools/public-audit.sh`'s decode carries the same squeeze; its own regexes cost 60 times less per line, so it
  never shared the stall.
