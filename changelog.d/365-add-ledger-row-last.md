- `keel-impact add` now writes its evidence blocks before the ledger row, so the ledger row is the last write
  and a refused or failing evidence write (for example, a non-regular `evidence.md`) aborts before any row
  exists. Before, the row landed first and the store was left half-updated with no message (dir #365).
