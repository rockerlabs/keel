- **README slimmed from 344 to about 170 lines; the detail moved rather than went.** The landing page
  now carries the pitch, the four properties, one install command, the standalone git hook and a short
  pre-PR gate section. Where the rest went:
  - The full docs index is now the Docs section of [`docs/reference.md`](/docs/reference.md); the README
    lists the five docs to start with.
  - The what-loads-when diagram and the before/after picture are in
    [`docs/loading-and-cost.md`](/docs/loading-and-cost.md).
  - The gate's `SubagentStart` rails hook, its git floor and their off switches are in
    [`docs/getting-started.md`](/docs/getting-started.md) §6, beside the rest of the gate's wiring; the
    linked install's full note that the secret-guard hook is a copy is in its Linked install section
    (the README keeps a short form).
  - The machine-watch watcher's one-time macOS Script Editor step is on `docs/reference.md`'s
    `tools/machine-watch.sh` row, beside its notification switches.
  - The `keel` CLI's verb list is pinned on `docs/reference.md`'s keel row alone; the README points at
    `keel help`.
  - The tests that pinned this prose in the README now pin it where it lives.
  - One row is gone: the install table's deferred `.dmg` option, which does not exist yet.
