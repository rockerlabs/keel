# shellcheck shell=bash
# tools/secret-guard/range-lib.sh — shared by the pre-push hook and the CI entry point: resolves a
# before/after commit pair into the range secret-scan.sh --range expects.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

SECRET_GUARD_ZERO_SHA="0000000000000000000000000000000000000000"

# resolve_range_local BEFORE AFTER — for the LOCAL pre-push hook. When the hook runs, git has not
# updated the remote-tracking refs for THIS push yet, so they still reflect pre-push reality. BEFORE =
# the zero sha means a brand-new ref (including a repo's very first push, which has no parent to diff
# against): scan everything reachable from AFTER that isn't already known on some remote.
resolve_range_local() {
  local before="$1" after="$2"
  if [ "$before" = "$SECRET_GUARD_ZERO_SHA" ]; then
    printf '%s --not --remotes' "$after"
  else
    printf '%s..%s' "$before" "$after"
  fi
}

# resolve_range_ci BEFORE AFTER — for a CI checkout. Do NOT reuse resolve_range_local's "--not
# --remotes" trick here: a CI job checks out AFTER the push already landed, so its remote-tracking refs
# reflect POST-push state — "$after --not --remotes" would exclude the very commits it should scan,
# silently reporting a brand-new ref's first push as clean. BEFORE = the zero sha instead scans the
# FULL history reachable from AFTER (no exclusion): correctness over cheapness on this rare edge.
resolve_range_ci() {
  local before="$1" after="$2"
  if [ "$before" = "$SECRET_GUARD_ZERO_SHA" ]; then
    printf '%s' "$after"
  else
    printf '%s..%s' "$before" "$after"
  fi
}
