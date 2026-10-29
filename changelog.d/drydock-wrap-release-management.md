- [`commands/wrap.md`](/commands/wrap.md), [`docs/grooming.md`](/docs/grooming.md) and
  [`docs/release-management.md`](/docs/release-management.md): claims a drydock prose audit found are
  corrected. The wrap's read-trace step no longer calls a missing log a silent no-op: the call still
  prints `docs read: none` and still writes the wrap-completion stamp; only an absent tool skips the step.
  G0's degrade-cleanly lead names the read-trace aggregate as its subject, with its test pin moved.
  `docs/release-management.md` no longer says `docs/drydock.md` has a command entrypoint; it names
  `docs/delta-audit.md` as the sibling with that shape.
