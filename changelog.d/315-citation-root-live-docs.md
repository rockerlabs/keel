- `tools/self/citation-resolvability.sh` now also scans the root-level live docs `FRAMEWORK.md` and
  `PRINCIPLES.md` (dir #315). Both sat outside the `docs/*.md` glob without ever being considered;
  `FRAMEWORK.md` is the methodology `install.sh` syncs into every install, so the history-text argument
  that excludes `CHANGELOG.md` does not apply. The other root docs stay unscanned by stated decision, and
  the script's comment now names the caveat that a scoped negative proves less than it looks like, on
  whichever axis (files, vocabulary) was scoped.
