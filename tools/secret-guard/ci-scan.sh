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
# One knob of this script's own (dir #572), read in exactly one situation — a push whose "before" sha
# is orphaned (force-push) AND unfetchable from origin:
#   SECRET_SCAN_CI_FORCE_PUSH_BASELINE   a rev the OPERATOR attests was a trusted pre-force-push state
#                                        of the pushed ref, used as the range's baseline in place of
#                                        the unreachable one. Deliberate, loudly logged, and a config
#                                        error (exit 2) if it does not resolve to a commit here or
#                                        resolves to the pushed head itself. Unset (the default) is
#                                        the safe case: a full-history scan that still blocks. See the
#                                        push arm below for why the three-step degrade exists at all.
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
# shellcheck source=tools/secret-guard/range-lib.sh
. "$here/range-lib.sh"

# _ci_scan_reject_degenerate_range BASELINE AFTER LABEL — dir #572. Exits 2 (the whole script, not a
# subshell: called as a plain statement below, never via command substitution — an `exit` inside a
# function invoked as `x="$(f)"` would only kill that subshell) if BASELINE..AFTER would resolve to
# an EMPTY scan range. `git rev-list X..Y` is empty exactly when Y is already reachable from X, so
# this is ONE `git merge-base --is-ancestor` check rather than a narrower equality compare — it
# catches BASELINE == AFTER (an operator hatch pasting the pushed head itself) and the broader case,
# BASELINE being any descendant of AFTER at all: a rollback-style force-push (the recovered "before"
# turns out to be downstream of "after"), or an operator hatch naming a too-recent commit. Both would
# otherwise resolve to a syntactically valid range that silently scans nothing (max-review finding,
# reproduced live: the equality-only guard this replaced missed exactly this class).
_ci_scan_reject_degenerate_range() {
  local baseline="$1" after="$2" label="$3"
  if git merge-base --is-ancestor "$after" "$baseline" 2>/dev/null; then
    echo "ci-scan: $label ($baseline) is at or after the pushed head ($after) — that range would scan nothing" >&2
    exit 2
  fi
}

# resolve_force_push_before ORPHANED_BEFORE AFTER — dir #572. Called only when ORPHANED_BEFORE is
# missing from this CI clone (the force-push case). Sets the caller's $before to the resolved
# baseline (or "0", to degrade to the original full-history fallback) and returns normally, or exits
# the whole script with 2 on a genuine config error — called as a plain statement below, per the same
# subshell note as _ci_scan_reject_degenerate_range above. Tries, in order, most-principled first:
#   1. Fetch ORPHANED_BEFORE by sha from origin. A forge keeps a force-pushed-away commit servable by
#      explicit sha until it gc's it, so this usually recovers the TRUE pre-push tip. This mechanism
#      was verified over the real upload-pack path (file:// transport, not a hardlinked local clone)
#      on git 2.43/2.47/2.52 — necessary evidence that modern git's fetch/cat-file plumbing behaves
#      this way, but NOT sufficient evidence that a given forge's own server-side policy also serves
#      an object that is unreferenced by any ref by explicit sha (a documented, not silent,
#      assumption — see the CHANGELOG entry for dir #572). If it doesn't hold on some forge, this
#      falls through to step 2 or 3 exactly as any other fetch failure would; the fail-closed
#      guarantee is unaffected either way.
#   2. The operator's SECRET_SCAN_CI_FORCE_PUSH_BASELINE escape hatch — also fetched by sha from
#      origin if not already present locally (the identical "servable until gc'd" property applies to
#      whatever rev the operator names, not only the auto-detected before).
#   3. Neither: degrade to "0", the original full-history fallback.
# Whichever candidate is chosen in step 1 or 2 is refused as a config error via
# _ci_scan_reject_degenerate_range above before it is accepted.
resolve_force_push_before() {
  local orphaned_before="$1" after="$2" hatch
  # GIT_TERMINAL_PROMPT=0: a credential prompt in a CI job hangs the run instead of failing it. The
  # cat-file recheck is not redundant — it confirms the object actually landed rather than trusting
  # fetch's exit status for it. No remote existence pre-check: `git fetch` on a clone with no "origin"
  # already fails the same way (exit 128, verified live), so a separate `git remote get-url origin`
  # guard would just be a second way to reach the same fallback.
  if GIT_TERMINAL_PROMPT=0 git fetch --quiet --no-tags origin "$orphaned_before" >/dev/null 2>&1 \
    && git cat-file -e "$orphaned_before^{commit}" 2>/dev/null; then
    _ci_scan_reject_degenerate_range "$orphaned_before" "$after" "the recovered before-sha"
    echo "ci-scan: before-sha $orphaned_before was missing from this clone (force-push?) — fetched it from origin; scanning $orphaned_before..$after as usual"
    if [ -n "${SECRET_SCAN_CI_FORCE_PUSH_BASELINE:-}" ]; then
      echo "ci-scan: SECRET_SCAN_CI_FORCE_PUSH_BASELINE is set but was not needed — the real before-sha was recoverable and takes precedence over it"
    fi
    before="$orphaned_before"
    return
  fi
  if [ -n "${SECRET_SCAN_CI_FORCE_PUSH_BASELINE:-}" ]; then
    hatch="$(git rev-parse --verify --quiet "${SECRET_SCAN_CI_FORCE_PUSH_BASELINE}^{commit}" 2>/dev/null || true)"
    if [ -z "$hatch" ]; then
      # The identical "servable by sha until gc'd" property that makes step 1 above possible applies
      # to whatever the operator names too — try fetching it before giving up on it (max-review
      # finding: the original cut only ever checked the local object db for the hatch, so a hatch
      # naming a genuinely dangling-but-still-fetchable commit spuriously failed).
      GIT_TERMINAL_PROMPT=0 git fetch --quiet --no-tags origin "${SECRET_SCAN_CI_FORCE_PUSH_BASELINE}" >/dev/null 2>&1 || true
      hatch="$(git rev-parse --verify --quiet "${SECRET_SCAN_CI_FORCE_PUSH_BASELINE}^{commit}" 2>/dev/null || true)"
    fi
    if [ -z "$hatch" ]; then
      echo "ci-scan: SECRET_SCAN_CI_FORCE_PUSH_BASELINE='$SECRET_SCAN_CI_FORCE_PUSH_BASELINE' does not resolve to a commit in this clone or on origin" >&2
      exit 2
    fi
    _ci_scan_reject_degenerate_range "$hatch" "$after" "SECRET_SCAN_CI_FORCE_PUSH_BASELINE"
    echo "ci-scan: before-sha $orphaned_before not in this clone (force-push?) and not fetchable from origin — using the operator-supplied SECRET_SCAN_CI_FORCE_PUSH_BASELINE ($hatch) as the baseline"
    before="$hatch"
    return
  fi
  echo "ci-scan: before-sha $orphaned_before not in this clone (force-push?) — scanning full history from after; every .secret-scan-allow entry fails closed here (no baseline to compare against), so set SECRET_SCAN_CI_FORCE_PUSH_BASELINE to a trusted pre-force-push rev if a legitimate entry must keep exempting"
  before="0"
}

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
    # expected topology, not a misconfiguration, so ci-scan degrades rather than erroring.
    #
    # dir #572: degrading STRAIGHT to the zero-sha full-history shape (the only response until now)
    # always fail-closes secret-scan.sh's own allowlist-baseline resolution (dir #518) — a bare
    # "$after" has no exclusion side, so `git rev-list --boundary` finds ZERO boundary commits and
    # every genuinely pre-existing .secret-scan-allow entry reads as new-this-push, blocking a push
    # the allowlist was written to exempt. resolve_force_push_before above (fetch the orphan; else the
    # documented SECRET_SCAN_CI_FORCE_PUSH_BASELINE escape hatch; else the original full-history
    # fallback, whose message now names the hatch) resolves this. Full rationale, and why this belongs
    # in ci-scan.sh rather than range-lib.sh or secret-scan.sh itself, is in the CHANGELOG.md entry.
    if ! secret_guard_is_zero_sha "$before" && ! git cat-file -e "$before^{commit}" 2>/dev/null; then
      resolve_force_push_before "$before" "$after"
    fi
    range="$(resolve_range_ci "$before" "$after")"
    ;;
  *)
    echo "ci-scan: unsupported GITHUB_EVENT_NAME '${GITHUB_EVENT_NAME:-}' (want pull_request or push)" >&2
    exit 2
    ;;
esac

exec "$scan" --range "$range"
