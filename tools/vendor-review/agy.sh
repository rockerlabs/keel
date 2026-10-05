#!/usr/bin/env bash
# tools/vendor-review/agy.sh — thin client for tools/vendor-review.sh: wraps Google's Antigravity
# CLI (`agy`) as a cross-vendor reader. Satisfies vendor-review.sh's --client contract (see that
# file's own header): reads the user message from stdin, an optional system prompt from --system
# FILE, prints the reply to stdout, and (with --raw-out FILE) saves the raw API response as JSON —
# on a failed call it saves whatever raw response it has too, best-effort, for debugging, so
# --raw-out's mere existence is never proof of success; this script's own exit code is.
#
# Requires the `agy` CLI installed and authenticated (https://antigravity.google/cli) — this script
# holds no credentials of its own; auth is the CLI's own config, outside this repo and outside git.
# The model has NO tool access here (headless `agy -p` denies every tool call needing approval): the
# bundle you pass IS the whole universe, a reviewer over text, never over the tree.
#
#   AGY_BIN             (optional) default $HOME/.local/bin/agy
#   AGY_MODEL           (optional) default gemini-3.1-pro-high — any NON-Claude model this CLI hosts.
#                       Never point this at a Claude model: the whole point of a vendor leg is an
#                       independent reader, and a Claude model here forfeits that independence.
#   AGY_PRINT_TIMEOUT   (optional) default 15m
#
# Usage:
#   agy.sh [--system FILE] --raw-out FILE < user_message
#
# Hard stop at 185 KB combined (system + user): `agy -p`'s inline prompt path has been measured to
# silently TRUNCATE a longer prompt instead of erroring — a caller trusting a truncated read would
# act on a partial view without ever being told. Chunk the bundle into multiple rounds instead of
# raising this number.
set -euo pipefail

usage() { sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

AGY_BIN="${AGY_BIN:-$HOME/.local/bin/agy}"
MODEL="${AGY_MODEL:-gemini-3.1-pro-high}"
TIMEOUT="${AGY_PRINT_TIMEOUT:-15m}"
max_bytes=$((185 * 1024))

sys_file=""
raw_out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --system)  sys_file="${2:?--system needs a file}"; shift 2 ;;
    --raw-out) raw_out="${2:?--raw-out needs a file}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "agy.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -x "$AGY_BIN" ] || {
  echo "agy.sh: $AGY_BIN not found or not executable — install with:" >&2
  echo "  curl -fsSL https://antigravity.google/cli/install.sh | bash" >&2
  exit 1
}

user_msg="$(cat)"
sys_msg=""
[ -n "$sys_file" ] && sys_msg="$(cat "$sys_file")"

# The no-tools sentence is load-bearing: a model that tries a tool instead of reading the inline
# bundle can return an EMPTY response with status SUCCESS rather than an error.
combined="$(
  [ -n "$sys_msg" ] && printf '%s\n' "$sys_msg"
  printf '\n---\n\nIMPORTANT: do NOT call any tool; you have no tool access. Answer strictly from the\ntext in this message.\n\n'
  printf '%s' "$user_msg"
)"

combined_bytes="$(printf '%s' "$combined" | wc -c | tr -d ' ')"
if [ "$combined_bytes" -gt "$max_bytes" ]; then
  echo "agy.sh: HARD STOP — combined prompt is $combined_bytes bytes, over the ${max_bytes}-byte cap." >&2
  echo "  agy's inline truncation past ~192,000 bytes is SILENT — this is a hard stop, not a warning." >&2
  echo "  Chunk the bundle and run one round per chunk." >&2
  exit 2
fi

resp_json="$(mktemp)"
err_file="$(mktemp)"
# dir #692 — a COMPLETION MARKER, not a bare quoted-command trap: on bash 3.2 a top-level FATAL shell error
# (a `set -u` unbound variable) leaves `$?` at 0 by the time an EXIT trap runs, so a bare trap reported
# success with an empty verdict — and this script's own header says its exit code is the proof of success.
# `ok` is set only on the last line (the one legitimate exit-0 path); a status-0 exit without it is a
# crash and becomes 1. An explicit non-zero `exit N` keeps its own. The dir #264 idiom, as in
# tools/drydock/inventory.sh.
ok=""
on_exit() {
  st=$?
  [ -n "$ok" ] || [ "$st" -ne 0 ] || st=1
  rm -f "$resp_json" "$err_file"
  exit "$st"
}
trap on_exit EXIT

agy_status=0
"$AGY_BIN" -p "$combined" --model "$MODEL" --output-format json --print-timeout "$TIMEOUT" \
  > "$resp_json" 2> "$err_file" || agy_status=$?
if [ "$agy_status" != 0 ]; then
  echo "agy.sh: agy CLI call failed (exit $agy_status). stderr:" >&2
  cat "$err_file" >&2
  [ -n "$raw_out" ] && cat "$resp_json" > "$raw_out" 2>/dev/null
  exit 1
fi

status="$(jq -r '.status // empty' "$resp_json" 2>/dev/null || true)"
content="$(jq -r '.response // empty' "$resp_json" 2>/dev/null || true)"
[ -n "$raw_out" ] && cat "$resp_json" > "$raw_out"

if [ "$status" != "SUCCESS" ]; then
  echo "agy.sh: non-SUCCESS status '$status' — failing loudly rather than falling through to an" >&2
  echo "  empty verdict. stderr:" >&2
  cat "$err_file" >&2
  exit 1
fi

if [ -z "$(printf '%s' "$content" | tr -d '[:space:]')" ]; then
  # A blank or whitespace-only .response with status SUCCESS is the same failure as a truly empty
  # one — most often a tool-permission denial on stderr (the model tried a tool it doesn't have) —
  # never a valid answer worth printing as if it were.
  echo "agy.sh: blank .response with status SUCCESS — likely a denied tool attempt. stderr:" >&2
  cat "$err_file" >&2
  exit 1
fi

printf '%s' "$content"
ok=1   # genuine completion — the EXIT trap above reads it (dir #692)
