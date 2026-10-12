- **Grooming and release management: the release record is checked by path, filed tickets carry a tag, and
  leftover ticket drafts get folded.** Three rules from the 0.17.0 groom's retro. Keel's releases record and its
  audit record share one file name, and a release closed with only the audit row written. So
  [`docs/release-management.md`](/docs/release-management.md) R7 now names the releases record by its full
  path, and a release is not closed while its row still holds the groom's placeholder. G0 in
  [`docs/grooming.md`](/docs/grooming.md) checks that row as well as the audit's. Under R8, every ticket the
  manager files carries a release tag on its heading, `→ pool` when nothing else fits. An untagged one sits
  outside every pool reading. G4 now folds every leftover draft in the project's drafts folder, `→ pool`.
  That groom found 23 such drafts, one of them a spec-ready design.
