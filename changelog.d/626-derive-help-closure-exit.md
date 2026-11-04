- `tools/delta-audit/derive.sh`'s header and `--help` now list the closure failure among the causes of exit code 3
  (dir #626). They named only three (not a repo, an unresolvable rev, an unusable output directory) and omitted
  the one the script's headline check refuses on. Both texts also say the refusal is one-directional: a path in
  the range diff that no PR is credited with refuses, while a path credited to a PR but absent from the range diff
  prints a "transient in range" note and does not. The `--help` text is pinned in
  `tests/test_delta_audit_derive.sh`.
