- The cloud route's tools close the open findings of dir #900 slice 1's last `/code-review max` round (dir #907).
  `tools/secret-guard/secret-scan.sh` takes `SECRET_SCAN_NO_INLINE_ALLOW=1`, which turns the inline
  `secret-scan:allow` marker off (the `.secret-scan-allow` file still applies; unset, nothing changes; `--selftest`
  drops it). `tools/cloud-land.sh`'s range scan and the brief and PR-text scans set it, so a marker split by an
  invalid byte (which the caller-locale personal pass reads whole after `iconv -c`, while no byte grep sees it) no
  longer hides a non-ASCII personal literal; the defanged copy is gone, and the added-marker check, kept as the
  spec's landing rule, now fails closed on a grep error. A range that changes a file whose default-branch line only
  an inline marker exempts now refuses, and the landing, when a hit carries the marker, says a fixture belongs in
  `.secret-scan-allow`. `tools/cloud-brief.sh`: the last ticket's END is decided by the fence markers after its
  heading (a heading-shaped line in a closed trailing fence no longer cuts the fence, and an unclosed fence keeps
  the ticket's own text up to the first section or ticket heading after its own, so a later section's closed fence
  no longer carries that section in, and a backlog whose fences leave such a heading inside the ticket's visible
  text refuses with exit 2 until they pair up); G7 refuses git data in any case (`Spec: .GIT/config` on macOS, a
  gitfile, a bare `mirror.git` inside the checkout) and any directory git itself reads as a git directory, a bare
  clone named `vendor/upstream` too; the home rewrite also catches a project-directory name nested after a `-` and
  the `/` and `.` → `-` form `tools/lib/transcript-usage.sh` uses; the `--check` receipt reaches stdout from inside
  the brief's assembly and after `--eligible --check`, and never prints a ticket id holding a newline, and its fd 3
  is opened only under `--check`, so no other mode's children hold the caller's stdout; `--sweep` looks a row's
  recorded PR up first; a default branch starting with `+` or `-` refuses as G1. Tests: the "tomorrow" date comes
  from local noon, the HOME=/root slug case runs with HOME=/root, and the gh stub's color follows gh's own
  precedence, with `tests/lib.sh` unsetting `NO_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE` and `GH_FORCE_TTY`.
