#!/usr/bin/env bash
# keel-check.sh — the stop-mode floor (backlog dir #33, tier T1a). Run a task's declared verification
# command THROUGH this shim so repeated failure becomes a mechanical signal, not a vibe: it counts
# consecutive failures of the same check and, on the Nth (default 2), prints a STOP-and-diagnose banner
# instead of letting the agent spiral into a third variant on hope. A pass resets the count.
#
# This is the model-independent half of the anti-hallucination rail whose always-on prose half lives in
# CORE.md ("When the same check keeps failing, stop — don't spiral"). The prose nudges; this shim holds:
# a determined circling loop can ignore a rail, but the banner fires deterministically off the check's
# own exit code, no matter the model. (The optional HARD veto — blocking a commit/PR while the check is
# red — is a separate opt-in hook, tier T1b, not this file.)
#
# Usage:  keel-check.sh <command...>
#           keel-check.sh "npm test"        # one arg  -> run as a shell string
#           keel-check.sh go test ./...     # many args -> run as an argv
# Exit:   passes through the check's own exit code (0 on green), so callers/CI see the real result.
# Env:    KEEL_CHECK_THRESHOLD  (default 2) — consecutive failures before the STOP banner fires.
#         KEEL_CHECK_STATE_DIR  (default /tmp) — where the per-task counter lives. Fixed /tmp, not
#                                 $TMPDIR, so this shim and keel-check-gate.sh (a separate process, whose
#                                 $TMPDIR may differ) always agree on the path — matches pre-pr-gate.sh.
#         KEEL_IMPACT_LOG       — if set, append one zero-token friction event when the banner fires
#                                 (metadata only; never the check's output). Mirrors pre-pr-gate.sh.
set -uo pipefail

# Sanitize the threshold: a non-numeric env value falls back to 2 rather than crashing the arithmetic.
threshold="${KEEL_CHECK_THRESHOLD:-2}"
case "$threshold" in ''|*[!0-9]*) threshold=2 ;; esac
[ "$threshold" -lt 1 ] && threshold=1

if [ "$#" -eq 0 ]; then
  printf 'keel-check: usage: keel-check.sh <command...>   (e.g. keel-check.sh "npm test")\n' >&2
  exit 2
fi

# The check command, reassembled for display + task identity.
cmd="$*"

# Per-task counter, keyed under a per-repo directory so the opt-in veto gate (keel-check-gate.sh) can
# answer "is any declared check for this repo still red?" by testing whether the repo dir is non-empty.
# The repo top (the worktree dir, in a worktree) groups checks; the command text separates streaks within
# it. cksum is POSIX, so no md5/shasum dependency (busybox-safe).
repo_top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
repo_key="$(printf '%s' "$repo_top" | cksum | tr -cd '0-9')"
cmd_key="$(printf '%s' "$cmd" | cksum | tr -cd '0-9')"
state_dir="${KEEL_CHECK_STATE_DIR:-/tmp}"
repo_dir="$state_dir/keel-check/$repo_key"
state="$repo_dir/$cmd_key"
mkdir -p "$repo_dir" 2>/dev/null || true

# Run the check with its output inherited (the agent still sees the real failure), then capture its code.
if [ "$#" -eq 1 ]; then
  sh -c "$cmd"
else
  "$@"
fi
rc=$?

if [ "$rc" -eq 0 ]; then
  rm -f "$state" 2>/dev/null || true
  rmdir "$repo_dir" 2>/dev/null || true   # empties the repo's "red set" once the last check goes green
  printf 'keel-check: PASS — %s (streak reset)\n' "$cmd" >&2
  exit 0
fi

# Failed: bump the consecutive-failure counter (read-tolerant of a corrupt/missing file).
fails=0
[ -f "$state" ] && fails="$(tr -cd '0-9' < "$state" 2>/dev/null)"
[ -z "$fails" ] && fails=0
fails=$((fails + 1))
printf '%s' "$fails" > "$state" 2>/dev/null || true

if [ "$fails" -lt "$threshold" ]; then
  printf 'keel-check: FAIL #%s — %s (one more failure of this same check trips the stop)\n' \
    "$fails" "$cmd" >&2
  exit "$rc"
fi

# Nth consecutive failure — the STOP banner (the soft interrupt). Says WHAT to do (diagnose), never HOW to
# defeat the check (FRAMEWORK.md "Enforcement mechanics — never name the bypass in the error text").
{
  printf '\n========================= keel-check: STOP =========================\n'
  printf 'The same check has now failed %s times:\n    %s\n\n' "$fails" "$cmd"
  printf 'Do NOT try another variant on hope. Repeated failure is a missing\n'
  printf 'CAUSE, not a missing attempt. Stop and state, in plain words:\n'
  printf '  1. what you expected this check to prove,\n'
  printf '  2. which assumption the failures have now ruled out,\n'
  printf '  3. what you still do NOT understand about why it fails.\n'
  printf 'Then fix the cause you named — or say you cannot yet, and why.\n'
  printf '====================================================================\n\n'
} >&2

# Optional zero-token friction event for keel-impact (opt-in via env; metadata only, never the output).
if [ -n "${KEEL_IMPACT_LOG:-}" ]; then
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" friction keel-check "stop-after-$fails" \
    >> "$KEEL_IMPACT_LOG" 2>/dev/null || true
fi

exit "$rc"
