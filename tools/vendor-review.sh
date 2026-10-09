#!/usr/bin/env bash
# tools/vendor-review.sh — leak-gated orchestrator for a scriptable cross-vendor reading leg.
#
# It never calls a vendor's API itself: it leak-gates a bundle, then hands it to a swappable
# --client script that does. A new vendor is a new client, never a rewrite of this file — the
# orchestration (the leak gate, one round dir per launch) is the part worth sharing across vendors.
# Full recipe, the two bundle shapes, and the non-negotiable rails: docs/vendor-review.md.
#
# A --client script must:
#   - read the user message on stdin;
#   - accept an optional system prompt via --system FILE;
#   - print the model's reply to stdout;
#   - accept --raw-out FILE and, on success, write the full raw API response there as JSON — it MAY
#     also write it on a failed call, best-effort, for debugging: --raw-out's mere existence is not
#     proof of success, only the client's own exit code is;
#   - exit non-zero on any failure (auth error, vendor error, denied tool call, oversize prompt,
#     empty or whitespace-only reply) rather than printing a plausible-looking empty answer.
# tools/vendor-review/agy.sh (Google's Antigravity CLI, `agy`) ships as the worked example.
#
# Usage:
#   tools/vendor-review.sh --client PATH --system FILE --bundle FILE --label NAME [--out DIR]
#   tools/vendor-review.sh -h | --help
#
#   --client PATH   executable satisfying the contract above.
#   --system FILE   the role/system prompt.
#   --bundle FILE   the assembled review bundle (the user message) — a file, not stdin, so this
#                   script can leak-scan it before anything is sent.
#   --label NAME    a short slug for the round dir, e.g. a ticket id or PR number — letters, digits,
#                   '_' and '-' only (no '/', so it can never escape --out).
#   --out DIR       where round dirs are written (default: <keel state root>/vendor-review, i.e.
#                   $HOME/.keel/vendor-review — outside every repo, so a default run leaves nothing in the
#                   caller's tree; an explicit --out is relative to the caller's cwd and never needs HOME).
#
# Writes <out>/round-<UTC timestamp>-<label>/{raw.json,reply.md} and prints that path — exactly one line on
# stdout, nothing else (the status sentence goes to stderr; on any failure stdout is empty), so
# `round="$(tools/vendor-review.sh ...)"` captures a usable path. Refuses if that exact round dir already
# exists (same label within the same second) rather than silently overwriting a concurrent launch's output.
#
# The leak gate is mandatory and has no bypass — no --force, no --skip-scan, and no working-directory
# bypass: --system and --bundle are resolved to absolute paths and the scanner runs from a fresh EMPTY
# directory (tools/lib/leak-gate.sh's LEAK_GATE_CWD), so no `.secret-scan-allow` in the caller's cwd or repo
# applies; leak_gate_run also resolves the scanner's path-valued environment (a relative
# SECRET_SCAN_PERSONAL_FILE) against the caller's cwd first. It scans them with
# tools/secret-guard/secret-scan.sh before anything is sent, and refuses on any hit, printing only the offending
# path, never the matched content — the scan-then-parse-then-refuse shape
# is tools/lib/leak-gate.sh's leak_gate_run, shared with tools/audit-packet/export.sh's own leak gate
# rather than a second hand-copy of it. An empty or whitespace-only --bundle is refused (exit 2) before the
# gate and the client; a client that exits 0 with an empty reply is a failure (exit 1, round dir kept).
# Exit codes: 0 round written · 1 empty reply · 2 bad arguments / empty bundle · 3 refused (gate hit, gate
# failed to run, collision, no usable temp or out dir) · otherwise the failing client's own status.
set -euo pipefail

usage() { sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; }
err()      { printf 'vendor-review.sh: %s\n' "$1" >&2; exit "$2"; }
die_args() { err "$1" 2; }
refuse()   { err "$1" 3; }

client="" system="" bundle="" label="" out_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --client)  client="${2:?--client needs a path}"; shift 2 ;;
    --system)  system="${2:?--system needs a file}"; shift 2 ;;
    --bundle)  bundle="${2:?--bundle needs a file}"; shift 2 ;;
    --label)   label="${2:?--label needs a name}"; shift 2 ;;
    --out)     out_dir="${2:?--out needs a directory}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        die_args "unknown option '$1' (see --help)" ;;
    *)         die_args "unexpected argument '$1' (see --help)" ;;
  esac
done

[ -n "$client" ] || die_args "--client is required (see --help)"
[ -n "$system" ] || die_args "--system is required (see --help)"
[ -n "$bundle" ] || die_args "--bundle is required (see --help)"
[ -n "$label" ]  || die_args "--label is required (see --help)"

[ -x "$client" ] || die_args "--client '$client' is not an executable file"
[ -f "$system" ] || die_args "--system '$system' not found"
[ -f "$bundle" ] || die_args "--bundle '$bundle' not found"

# Letters/digits/'_'/'-' only: --label is concatenated straight into the round-dir path below, and a
# '/' or '..' segment in it would let the path escape --out entirely (found live in review: a label
# of 'x/../../escaped' wrote its round one level ABOVE --out).
case "$label" in
  *[!A-Za-z0-9_-]*) die_args "--label must contain only letters, digits, '_' and '-' (got '$label')" ;;
esac

# B5(a): nothing to review is not a round. `grep -q` on the FILE (no pipe, so no SIGPIPE hazard under pipefail).
LC_ALL=C grep -q '[^[:space:]]' "$bundle" \
  || die_args "--bundle '$bundle' has no non-whitespace content — nothing to review, no round was run"

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tools/lib/leak-gate.sh
. "$script_dir/lib/leak-gate.sh"
# shellcheck source=tools/lib/state-root.sh
. "$script_dir/lib/state-root.sh"

# B6: the default --out is outside every repo. An explicit --out keeps today's meaning (relative to the
# caller's cwd) and never consults the state root, so no HOME is needed then.
if [ -z "$out_dir" ]; then
  state_root="$(keel_state_root)" \
    || die_args "no --out given and no usable HOME to default it under — pass --out DIR"
  out_dir="$state_root/vendor-review"
fi

scan_script="$script_dir/secret-guard/secret-scan.sh"
[ -x "$scan_script" ] || refuse "tools/secret-guard/secret-scan.sh is missing or not executable next
  to this script ($scan_script) — refusing to run without a working leak gate. There is no --force
  and no --skip-scan."

# B1: absolute paths for the scanner, because it runs from a different cwd (below). A relative path is
# resolved against the CALLER's cwd; no `readlink -f` (absent on macOS).
abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
abs_system="$(abs_path "$system")"
abs_bundle="$(abs_path "$bundle")"
# The BLOCKED text names each file by the path the caller PASSED, not the resolved one.
relabel_gate_path() {
  case "$1" in
    "$abs_system") printf '%s' "$system" ;;
    "$abs_bundle") printf '%s' "$bundle" ;;
    *)             printf '%s' "$1" ;;
  esac
}

# B1: the leak gate runs from a fresh EMPTY directory. The scanner's file-list mode trusts every entry of
# `./.secret-scan-allow` in ITS cwd, so a caller's cwd (or a file an agent planted there) could relax a gate
# documented as having no bypass (0.13.0 audit S7-2). An explicit `${TMPDIR:-/tmp}/…XXXXXX` template — a bare
# `mktemp -d` ignores TMPDIR on macOS. The dir is removed on EVERY exit by a NAMED handler using the dir #264
# completion-marker idiom (`ok=1` on the last line of the one legitimate exit-0 path), never a bare quoted
# `trap '…' EXIT`: on bash 3.2 a bare trap turns a `set -u` crash into exit 0 (dir #692,
# tests/test_exit_trap_marker.sh). No explicit INT/TERM traps: an untrapped fatal signal already runs the EXIT
# handler and exits 128+N at once (measured on bash 3.2), whereas `trap 'exit 143' TERM` would DEFER it until the
# foreground child — here the vendor client, up to its whole timeout — returns.
gate_dir=""
ok=""
on_exit() {
  st=$?
  [ -n "$ok" ] || [ "$st" -ne 0 ] || st=1
  [ -z "$gate_dir" ] || rm -rf "$gate_dir"
  exit "$st"
}
trap on_exit EXIT
gate_dir="$(mktemp -d "${TMPDIR:-/tmp}/vendor-review.XXXXXX")" \
  || refuse "could not create a scratch directory for the leak gate under ${TMPDIR:-/tmp} — refusing to run
  without a clean gate. Nothing was sent."

gate_status=0
# Always set here, never read from the caller's environment: an inherited value must not steer the gate.
LEAK_GATE_CWD="$gate_dir"
leak_gate_run "$scan_script" "relabel_gate_path" "$abs_system" "$abs_bundle" || gate_status=$?
LEAK_GATE_CWD=""
rm -rf "$gate_dir"; gate_dir=""

if [ "$gate_status" = 1 ]; then
  hit_paths="$LEAK_GATE_HIT_PATHS"
  [ -n "$hit_paths" ] || hit_paths="(the gate reported a hit but its path could not be parsed — re-run
  tools/secret-guard/secret-scan.sh -- \"$system\" \"$bundle\" directly)"
  refuse "leak gate BLOCKED — secret-shaped string(s) or personal data found in:
$(printf '%s\n' "$hit_paths" | sed 's/^/  /')
Nothing was sent. Remove the finding and re-run. There is no --force and no --skip-scan."
elif [ "$gate_status" != 0 ]; then
  refuse "leak gate failed to run (tools/secret-guard/secret-scan.sh exited $gate_status) — refusing
  to run without a clean gate. Its stderr:
$(printf '%s' "$LEAK_GATE_STDERR" | sed 's/^/  /')"
fi

# One round dir per launch, never reused: mkdir (no -p on the leaf) fails loudly if the exact same
# label collides within the same UTC second, instead of two concurrent launches silently sharing a
# dir and one's reply.md overwriting the other's mid-flight (found live in review).
# dir #705: replies quote gitignored bundle material — store, round dir and the client's files are
# owner-only whatever the caller's umask (a pre-existing store keeps its mode; only new dirs are made 700).
umask 077
mkdir -p "$out_dir" || refuse "could not create the output directory '$out_dir' — the client was not run."
round="$out_dir/round-$(date -u +%Y%m%dT%H%M%SZ)-$label"
if [ -e "$round" ]; then
  refuse "round dir '$round' already exists — another launch with the same --label landed in the
  same second. Re-run (the next second's timestamp will differ), or use a more specific --label."
fi
mkdir "$round" || refuse "could not create round dir '$round'."

client_status=0
"$client" --system "$system" --raw-out "$round/raw.json" < "$bundle" > "$round/reply.md" \
  || client_status=$?
if [ "$client_status" != 0 ]; then
  echo "vendor-review.sh: client '$client' failed (exit $client_status) — see $round/reply.md and
  $round/raw.json for whatever it left behind." >&2
  exit "$client_status"
fi

# B5(c): the client contract already says an empty reply is a failure; this is the orchestrator's backstop for
# a client that forgets it. The round dir is kept for post-mortem.
if ! LC_ALL=C grep -q '[^[:space:]]' "$round/reply.md"; then
  echo "vendor-review.sh: client '$client' exited 0 with an empty reply — treating it as a failure. The round
  dir is kept for post-mortem: $round" >&2
  exit 1
fi

bundle_bytes="$(wc -c < "$bundle" | tr -d ' ')"
printf 'vendor-review: round written to %s (leak gate clean, bundle %s bytes)\n' "$round" "$bundle_bytes" >&2
printf '%s\n' "$round"
ok=1   # genuine completion — the EXIT trap above reads it (dir #264 / #692 idiom)
