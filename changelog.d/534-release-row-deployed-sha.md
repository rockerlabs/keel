- A release row now closes with the deployment state, read from the target (dir #534). A tag is not a deployment: one project's
  release stood "shipped" while its target still ran the previous release. [`docs/release-management.md`](/docs/release-management.md)
  R9 has the manager write `deployed <sha> <date>` from the target's own head command, or `NOT deployed — operator step pending`,
  or `no deploy target`, and [`docs/grooming.md`](/docs/grooming.md) G0 re-checks it against the live target before the previous
  cycle is read as shipped.
