- **`tools/self/doctor.sh` refuses instead of reporting OK when it cannot list the files it checks.** A failing
  `shellcheck-targets.sh` used to read "OK   shellcheck: no tracked shell scripts to check" (a process substitution
  hid its exit status), and a corrupt index printed OK beside `fatal:` for the dead-reference, slash-command and
  PIPESTATUS checks. Each of the five `git ls-files` enumerations and the selector now checks its status: a failure is
  a GAP, `could not list <what> (exit <N>) — <check> is INCOMPLETE`, that check prints no OK line, and the run exits 1.
  The tool-wiring loop is skipped when its reference files could not be listed, so no tool is falsely named
  unreferenced. Its `git grep`, `git log` and `git tag` reads still print OK when git fails (dir #766). A stale "line 56" cite in a comment is now "near the top" (dir #738).
