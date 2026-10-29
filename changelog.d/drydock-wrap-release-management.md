- [`commands/wrap.md`](/commands/wrap.md), [`docs/grooming.md`](/docs/grooming.md) and
  [`docs/release-management.md`](/docs/release-management.md): claims a drydock prose audit found are
  corrected. The wrap's read-trace step no longer calls a missing log a silent no-op: it says the call
  still prints `docs read: none` and still writes the wrap-completion stamp, and only an absent tool skips
  the step. G0's degrade-cleanly lead now names the read-trace aggregate as its subject, with its test
  pin moved. `docs/release-management.md` no longer says `docs/drydock.md` has a command entrypoint: the
  thin-entrypoint split names `docs/grooming.md` instead, and the See also keeps
  `docs/delta-audit.md` as the entrypoint sibling and `docs/drydock.md` for its file-contract and
  role-prompt mechanics.
