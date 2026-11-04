- `docs/release-management.md` now says outright that a build worker's chip is `/go <N>` plus a coordination-only
  overlay (dir #648). The manager's verified facts and scope corrections go into the ticket as dated `Log:` lines;
  the overlay carries identity, reporting, deferred `/go` steps, siblings, bounds and the worker-brief rails in their
  own wording, plus the live-experiment rail (a scratch clone under a sandboxed tmpdir, never the real checkout).
  The merge hand-off adds `do not merge #N yet` the moment a correction is in flight on an open PR.
  `commands/manage-release.md` points at it.
