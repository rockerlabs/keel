- `docs/release-history.md`'s entry for the 0.7.2 release now matches that release's own Known issues section in
  the changelog (dir #339): it said "two failure windows in the auto-migration path" shipped plus "two further
  known issues", which read as four. The release disclosed two: a wrong sentence printed by `keel-impact.sh
  enable` (the migration itself is correct) and a weak changelog-citation check in `doctor`. Docs-only.
