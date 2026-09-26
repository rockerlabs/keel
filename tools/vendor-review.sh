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
#   --out DIR       where round dirs are written (default: out).
#
# Writes <out>/round-<UTC timestamp>-<label>/{raw.json,reply.md} and prints that path. Refuses if
# that exact round dir already exists (same label within the same second) rather than silently
# overwriting a concurrent launch's output.
#
# The leak gate is mandatory and has no bypass — no --force, no --skip-scan. It scans --system and
# --bundle with tools/secret-guard/secret-scan.sh before anything is sent, and refuses on any hit,
# printing only the offending path, never the matched content (the same discipline as
# tools/audit-packet/export.sh's own leak gate).
set -euo pipefail

usage() { sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; }
err()      { printf 'vendor-review.sh: %s\n' "$1" >&2; exit "$2"; }
die_args() { err "$1" 2; }
refuse()   { err "$1" 3; }

client="" system="" bundle="" label="" out_dir="out"
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

script_dir="$(cd "$(dirname "$0")" && pwd)"
scan_script="$script_dir/secret-guard/secret-scan.sh"
[ -x "$scan_script" ] || refuse "tools/secret-guard/secret-scan.sh is missing or not executable next
  to this script ($scan_script) — refusing to run without a working leak gate. There is no --force
  and no --skip-scan."

gate_status=0
gate_err="$("$scan_script" -- "$system" "$bundle" 2>&1 >/dev/null)" || gate_status=$?

if [ "$gate_status" = 1 ]; then
  # BLOCKED — extract ONLY the leading path off each "  path:line:content" detail line
  # (secret-scan.sh's own format), never the matched content that follows it (dir #495's own leak
  # gate discipline, see tools/audit-packet/export.sh's run_leak_gate for the precedent).
  hit_paths="$(printf '%s\n' "$gate_err" | sed -n 's/^  //p' | cut -d: -f1 | LC_ALL=C sort -u)"
  [ -n "$hit_paths" ] || hit_paths="(the gate reported a hit but its path could not be parsed — re-run
  tools/secret-guard/secret-scan.sh -- \"$system\" \"$bundle\" directly)"
  refuse "leak gate BLOCKED — secret-shaped string(s) or personal data found in:
$(printf '%s\n' "$hit_paths" | sed 's/^/  /')
Nothing was sent. Remove the finding (or, for a genuine test fixture, an operator-approved
.secret-scan-allow entry — a human, out-of-band decision, never an agent's own workaround) and
re-run. There is no --force and no --skip-scan."
elif [ "$gate_status" != 0 ]; then
  refuse "leak gate failed to run (tools/secret-guard/secret-scan.sh exited $gate_status) — refusing
  to run without a clean gate. Its stderr:
$(printf '%s\n' "$gate_err" | sed 's/^/  /')"
fi

# One round dir per launch, never reused: mkdir (no -p on the leaf) fails loudly if the exact same
# label collides within the same UTC second, instead of two concurrent launches silently sharing a
# dir and one's reply.md overwriting the other's mid-flight (found live in review).
mkdir -p "$out_dir"
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

bundle_bytes="$(wc -c < "$bundle" | tr -d ' ')"
printf 'vendor-review: round written to %s (leak gate clean, bundle %s bytes)\n' "$round" "$bundle_bytes"
