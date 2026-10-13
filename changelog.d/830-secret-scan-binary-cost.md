- **`secret-scan.sh --tracked` no longer stalls on a large tracked binary** (dir #830). Decoding a binary writes
  several text views; one of them, the raw printable runs, put a newline after every non-printable byte, so a
  20 MiB incompressible blob became about 12.6 million tiny lines and the class-1 grep paid a fixed ~12 µs on
  each of them: ~190 s of CPU for the blob, and on a machine under load a `kb-doctor.sh` run that never seemed
  to finish. The view is now squeezed to maximal printable runs and drops every run shorter than the shortest
  string any pattern can match (the floor is derived from the class-1 patterns and the personal literals, and
  is 1, nothing dropped, for an ERE it cannot read), so the verdict is unchanged. The blob now scans in ~47 s
  of CPU (class 1 only), linear in its size, and a test pins that with a generated 20 MiB blob and a CPU-time
  ceiling. `tools/public-audit.sh`'s decode carries the same squeeze; its own regexes cost 60 times less per
  line, so it never shared the stall.
