- `keel-impact.sh add --dry-run` previews the auto-ingest before any row exists: it runs the same ingestion
  function as `add`, prints the same `ingested:` / `stale-skipped:` / `foreign-kept:` lines and writes nothing
  (no ledger row, no evidence block, the event log neither consumed nor rotated). The valence ritual in
  `commands/keel-score.md` now runs the preview first and only then a single `add`, with `--no-ingest` and
  the corrected flags when a line is a false fire, so a correction no longer costs a second row (dir #271).
