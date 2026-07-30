# shellcheck shell=bash
# tools/secret-guard/range-lib.sh — shared by the pre-push hook and the CI entry point: resolves a
# before/after commit pair into the range secret-scan.sh --range expects.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

# secret_guard_is_zero_sha SHA — true if SHA is git's all-zero "no commit" sentinel. Pattern-matched
# (all zero digits) rather than compared against a fixed-length literal, because git's zero sha is as
# long as the repo's object-hash format: 40 chars under SHA-1 (the fleet default), 64 under SHA-256
# (`git init --object-format=sha256`). An exact-length compare would miss a SHA-256 repo's all-zero
# sentinel, fall through to the "existing ref" branch, and hand secret-scan.sh an unresolvable range.
secret_guard_is_zero_sha() {
  case "$1" in
    '') return 1 ;;
    *[!0]*) return 1 ;;
    *) return 0 ;;
  esac
}

# resolve_range_local BEFORE AFTER — for the LOCAL pre-push hook. When the hook runs, git has not
# updated the remote-tracking refs for THIS push yet, so they still reflect pre-push reality. BEFORE =
# the zero sha means a brand-new ref (including a repo's very first push, which has no parent to diff
# against): scan everything reachable from AFTER that isn't already known on some remote.
resolve_range_local() {
  local before="$1" after="$2"
  if secret_guard_is_zero_sha "$before"; then
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
  if secret_guard_is_zero_sha "$before"; then
    printf '%s' "$after"
  else
    printf '%s..%s' "$before" "$after"
  fi
}
