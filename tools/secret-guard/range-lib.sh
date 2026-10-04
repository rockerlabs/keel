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

# secret_guard_commit_known SHA — true if SHA names a commit object in the repo the caller is in. False
# for a sha git has never heard of AND for one that peels to no commit (a blob/tree sha), so the answer
# is "can `SHA..X` be walked here", not merely "does the object exist".
secret_guard_commit_known() {
  git cat-file -e "$1^{commit}" 2>/dev/null
}

# resolve_range_local BEFORE AFTER — for the LOCAL pre-push hook. When the hook runs, git has not
# updated the remote-tracking refs for THIS push yet, so they still reflect pre-push reality. BEFORE =
# the zero sha means a brand-new ref (including a repo's very first push, which has no parent to diff
# against): scan everything reachable from AFTER that isn't already known on some remote.
#
# BEFORE = a non-zero sha that is NOT a commit in this repo is the same case in all but spelling
# (dir #546): the remote's old tip is unknown here — a force-push from a fresh `git filter-repo` clone
# (which drops `origin` and the old objects by design), or a push from a clone that never fetched that
# tip. `BEFORE..AFTER` is unresolvable then, and handing it to secret-scan.sh used to refuse the push
# with no way through but `--no-verify` — failing CLOSED on exactly the push a history scrub exists to
# make. "Everything not already on a remote" is still a full scan of whatever is not known to be public,
# so it widens the range rather than dropping it. Only the allow-list baseline gets no help from this
# shape: with no remote-tracking ref the boundary set is empty, so an allow-list entry that exempts a
# match in the pushed history is untrusted (secret-scan.sh's same-change rule) — a fetch of the remote
# first restores the baseline.
resolve_range_local() {
  local before="$1" after="$2"
  if secret_guard_is_zero_sha "$before" || ! secret_guard_commit_known "$before"; then
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
