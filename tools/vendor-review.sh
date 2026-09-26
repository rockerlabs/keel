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
#   - accept --raw-out FILE and, on success, write the full raw API response there as JSON;
#   - exit non-zero on any failure (auth error, vendor error, denied tool call, oversize prompt)
#     rather than printing a plausible-looking empty answer.
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
#   --label NAME    a short slug for the round dir, e.g. a ticket id or PR number.
#   --out DIR       where round dirs are written (default: out).
#
# Writes <out>/round-<UTC timestamp>-<label>/{raw.json,reply.md} and prints that path.
#
# The leak gate is mandatory and has no bypass — no --force, no --skip-scan. It scans --system and
# --bundle with tools/secret-guard/secret-scan.sh before anything is sent, and refuses on any hit,
# printing only the offending path, never the matched content (the same discipline as
# tools/audit-packet/export.sh's own leak gate).
set -euo pipefail

usage() { sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; }
die()      { local code="$1"; shift; echo "vendor-review.sh: $*" >&2; exit "$code"; }
die_args() { die 2 "$@"; }
refuse()   { die 3 "$@"; }

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

script_dir="$(cd "$(dirname "$0")" && pwd)"
scan_script="$script_dir/secret-guard/secret-scan.sh"
[ -x "$scan_script" ] || refuse "tools/secret-guard/secret-scan.sh is missing or not executable next
  to this script ($scan_script) — refusing to run without a working leak gate. There is no --force
  and no --skip-scan."

gate_err="$(mktemp)"
trap 'rm -f "$gate_err"' EXIT

gate_status=0
"$scan_script" -- "$system" "$bundle" >/dev/null 2>"$gate_err" || gate_status=$?

if [ "$gate_status" = 1 ]; then
  # BLOCKED — extract ONLY the leading path off each "  path:line:content" detail line
  # (secret-scan.sh's own format), never the matched content that follows it (dir #495's own leak
  # gate discipline, see tools/audit-packet/export.sh's run_leak_gate for the precedent).
  hit_paths="$(sed -n 's/^  //p' "$gate_err" | cut -d: -f1 | LC_ALL=C sort -u)"
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
$(sed 's/^/  /' "$gate_err")"
fi

# One round dir per launch, never reused — two launches sharing a dir can overwrite each other's
# reply mid-flight.
round="$out_dir/round-$(date -u +%Y%m%dT%H%M%SZ)-$label"
mkdir -p "$round"

client_status=0
"$client" --system "$system" --raw-out "$round/raw.json" < "$bundle" > "$round/reply.md" \
  || client_status=$?
if [ "$client_status" != 0 ]; then
  echo "vendor-review.sh: client '$client' failed (exit $client_status) — see $round/reply.md and
  $round/raw.json for whatever it left behind." >&2
  exit "$client_status"
fi

bundle_bytes="$(wc -c < "$bundle")"
bundle_bytes="${bundle_bytes// /}"
printf 'vendor-review: round written to %s (leak gate clean, bundle %s bytes)\n' "$round" "$bundle_bytes"
