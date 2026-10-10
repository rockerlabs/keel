- **The release docs say how a merge queue changes the merge step (dir #744 slice 5).**
  [`docs/release-management.md`](/docs/release-management.md) R2 adds that where the repository requires a merge
  queue (keel does), the operator enqueues a green PR instead of updating and merging it, and a conflict or red
  check ejects it back to its worker; `commands/manage-release.md` M3 and M8 carry the same clause. R9 now calls
  the operator's list of merges "the merge list", so it no longer reads as GitHub's queue. Without a queue the
  text and the flow are unchanged.
