- CI's macOS shards now run on the `macos-15` image, since GitHub retires `macos-14` on 2026-11-02 (dir #921).
  The required check names stay `tests (macos-14)` and `tests (macos-14, shard N/2)`, so branch protection
  needs no change.
  The `/go` guide's changelog-claims `find` now uses the locale-safe class `[[:lower:][:digit:]]*.md`
  instead of the range `[a-z0-9]*.md`, which a UTF-8 locale (macos-15's) expanded to match `README.md`.
