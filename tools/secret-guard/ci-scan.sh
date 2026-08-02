#!/usr/bin/env bash
# tools/secret-guard/ci-scan.sh — server-side secret-scan CI entry point (backlog dir #37 / SEC4).
#
# Resolves the git range a CI event actually introduces and hands it to secret-scan.sh --range — the
# CI-side counterpart to tools/secret-guard/pre-push (same --range contract, different trigger: a push
# event's before/after instead of a hook's stdin ref lines, and a different first-push range — see
# range-lib.sh's resolve_range_ci for why the two callers can't share one implementation there). No new
# detection logic lives here; this only computes WHAT to scan, kept in its own file (not inlined in
# ci.yml) so the range-resolution is unit-testable without a GitHub Actions runner — mirrors
# tools/self/shellcheck-targets.sh's canonical-source shape.
#
# Reads GitHub Actions' own event fields, passed in by ci.yml as plain env vars (never interpolated
# into this script's text, so a branch name or PR title can't inject shell):
#   GITHUB_EVENT_NAME                    "pull_request" or "push"
#   GITHUB_BASE_SHA / GITHUB_HEAD_SHA    pull_request: base/head commit shas
#   GITHUB_EVENT_BEFORE / GITHUB_EVENT_AFTER
#                                        push: before/after commit shas ("before" is the all-zero sha
#                                        on a new ref's first push; "after" is the all-zero sha on a
#                                        ref deletion — nothing to scan)
#
# Exit 0 = clean (or nothing to scan); 1 = a secret-shaped string or personal data found; 2 = usage/
# config error (matches secret-scan.sh's own contract — a missing/unrecognized env var must not read
# as "1: a secret was found").
#
# Usage: tools/secret-guard/ci-scan.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scan="$here/secret-scan.sh"
if [ ! -x "$scan" ]; then
  echo "ci-scan: scanner not found next to this script ($scan)" >&2
  exit 2
fi
# shellcheck source=range-lib.sh
. "$here/range-lib.sh"

case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    base="${GITHUB_BASE_SHA:-}"
    head="${GITHUB_HEAD_SHA:-}"
    if [ -z "$base" ] || [ -z "$head" ]; then
      echo "ci-scan: GITHUB_BASE_SHA and GITHUB_HEAD_SHA required for a pull_request event" >&2
      exit 2
    fi
    range="$(resolve_range_ci "$base" "$head")"
    ;;
  push)
    before="${GITHUB_EVENT_BEFORE:-}"
    after="${GITHUB_EVENT_AFTER:-}"
    if [ -z "$before" ] || [ -z "$after" ]; then
      echo "ci-scan: GITHUB_EVENT_BEFORE and GITHUB_EVENT_AFTER required for a push event" >&2
      exit 2
    fi
    if secret_guard_is_zero_sha "$after"; then
      echo "ci-scan: ref deleted (after is the zero sha) — nothing to scan"
      exit 0
    fi
    # A force-push orphans "before", so the CI clone may not have that object at all. before..after
    # would then be a config error (secret-scan --range fails closed, exit 2) — but this is an
    # expected topology, not a misconfiguration: fall back to the zero-sha shape and scan the FULL
    # history reachable from "after" instead. Correctness over cheapness; never silently "clean".
    if ! secret_guard_is_zero_sha "$before" && ! git cat-file -e "$before^{commit}" 2>/dev/null; then
      echo "ci-scan: before-sha $before not in this clone (force-push?) — scanning full history from after"
      before="0"
    fi
    range="$(resolve_range_ci "$before" "$after")"
    ;;
  *)
    echo "ci-scan: unsupported GITHUB_EVENT_NAME '${GITHUB_EVENT_NAME:-}' (want pull_request or push)" >&2
    exit 2
    ;;
esac

exec "$scan" --range "$range"
