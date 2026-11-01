- `docs/keel-ab/seed.sh`'s `--with-keel PATH` now accepts a relative path. It was validated against the invocation
  directory but copied after the script had changed into the target, so a relative path passed the check, then the
  copy failed and left a half-built fixture with no `CLAUDE.md` and a nonzero exit. The path is now made absolute
  right after validation (dir #515).
