- `keel-impact add` now writes its ledger row last, after the evidence blocks. A refused evidence write
  (for example, a non-regular `evidence.md`) therefore aborts before any row exists. Before, the row landed
  first, and a refused evidence write left a row with no evidence block; the refusal message was printed, but
  the store was already half-updated (dir #365). The ledger is preflighted, so a refused ledger leaves no evidence block.
