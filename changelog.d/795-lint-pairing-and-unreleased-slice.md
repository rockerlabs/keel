- `changelog-fragments.sh --check` no longer flags a `dir #N` that sits between two code spans on one line,
  and `citation-resolvability.sh` takes the `[Unreleased]` slice from the fence-blanked changelog and skips a
  tracked-but-deleted fragment quietly (dir #795).
