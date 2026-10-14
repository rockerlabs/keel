- **`tools/self/doctor.sh` no longer prints an OK over a read it could not complete (dir #766).** The
  self-check had about forty sites where a failed producer read as a clean answer: a git that would not run
  (`log`, `tag -l`, `rev-parse --is-shallow-repository`, `grep`) made the CHANGELOG staleness, release-tag and
  commit-ticket checks print OK or a silent "skipping"; an unreadable tracked file either aborted the whole
  run with no GAP or read as empty; and the `changelog-fragments.sh` calls ended in `|| true`. Each of those is
  now a GAP naming what could not be read and the check it leaves incomplete (no OK line), and later checks
  still run. The sites that stay unchecked on purpose (a `grep` with no match, a filter over text already in
  memory, a best-effort `gh` call) are listed with their reason in
  `tests/test_doctor_status_register.sh`, which fails on any new unregistered `|| true`, `|| echo`, `< <(` or
  `2>/dev/null)` site. An unreadable `CHANGELOG.md` is now a GAP rather than a silent skip.
