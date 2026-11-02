- `docs/release-management.md` R9 (with a pointer from R8's closing write) now requires a closure record that closes an
  audit finding to quote the finding's own definition from the audit's cross-run record and list each named part
  with its status; the manager diffs those two texts at approval, and a part the closure drops stays open. The class
  is a closure record that narrows the finding it closes (dir #537). `tests/test_release_management_doc.sh` pins the rule.
