- `tu_session_totals()` in `tools/lib/transcript-usage.sh` now tests its `jq` capture with `|| status=$?`
  instead of a bare assignment followed by `status=$?`, so its temp-file cleanup runs however a caller
  invokes it under `set -e` (dir #438). No current call site in the tree reaches the leak; this is hardening.
