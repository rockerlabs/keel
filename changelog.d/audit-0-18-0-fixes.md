- **Corrections from the 0.18.0 release-candidate audit.** Prose only, no behaviour change (audit findings B01–B08).
  The always-on chain entry (dir #253) and `docs/loading-and-cost.md` now say that the always-on import reader in
  `doctor` is a line-based approximation of Claude Code's import grammar that can differ from the harness, name
  where, and call a clean chain line evidence rather than proof; the per-project run is not fail-closed on an
  unreadable project `CLAUDE.md`. `ADAPTING.md`'s "Generating your entrypoints yourself" no longer says that
  `doctor.sh --install` sends every remedy to the generator (the four `ALWAYSON` remedies name none) or that the
  `ALWAYSON` checks apply to a generated `AGENTS.md` (it is read as one file, so only its size is checked).
  `docs/token-economy.md` no longer calls the follow-ups to `/go` and `/wrap` (dir #857, dir #858) and the
  cheaper-tier runner (dir #856) pending: all three are closed. Entries of this release's own notes were corrected
  where a later change in the same release had replaced what they announced (the `/polish` receipt placement, the
  groom's audit-price floor) or where they over-read the code (the generated-entrypoints block offer, the
  release-history gate, which tools share the session-cost reader).
