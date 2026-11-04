- `docs/release-management.md` R9 now requires a pass against live data when a release changes the meaning of
  already-stored data, or a plain record that no such pass happened and why (dir #469). The five-part worker
  brief's "Leads" item gains defect-class leads beside its file-shaped ones, so an audit can hunt for what is
  absent (a missing backfill) and not only for what is wrong. Pinned in `tests/test_release_management_doc.sh`.
