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
# The bundle you pass is meant to be the whole universe — a reviewer over text, never over the tree — and
# two rules enforce that rather than assume it (dir #662):
#   - agy runs from a fresh EMPTY directory (removed on exit), never the caller's cwd: agy loads
#     AGENTS.md / GEMINI.md from its cwd into the prompt, unscanned text from the caller's tree reaching
#     the vendor. An empty cwd holds none.
#   - agy is invoked ONLY when its settings (`$HOME/.gemini/antigravity-cli/settings.json`) carry no
#     `permissions.allow` rule: a rule reaches this headless call (measured, dir #662) and hands the
#     model file reads. Any rule — or a settings file this script cannot read — refuses (exit 1).
#     The guarantee is exactly that: those allow-rules are the one grant source checked; agy's MCP
#     servers and plugins are NOT, so "no tool access" is never claimed unqualified. The prompt's own
#     "do NOT call any tool" sentence stays as a second layer. This script never passes `--add-dir`
#     or `--dangerously-skip-permissions`.
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
# Hard stop on the combined prompt (system + user), exit 2 before agy runs: 185 KiB, or 131071 bytes on
# Linux (`uname -s`). `agy -p`'s inline prompt path has been measured to silently TRUNCATE a prompt past
# ~192,000 bytes instead of erroring — a caller trusting a truncated read would act on a partial view
# without ever being told — and the prompt travels as ONE argument, which Linux caps at 131071 bytes
# (131072 fails with E2BIG, "Argument list too long"). Chunk the bundle into multiple rounds instead of
# raising either number. An agy exec that fails with exit 126 and that message anyway (a platform with
# a smaller limit) is also exit 2, naming the OS's per-argument limit.
#
# Exit codes: 0 reply on stdout · 1 agy failed / non-SUCCESS / blank reply / a denied tool call / settings
# forbid it · 2 refused before agy ran (oversize, empty input, E2BIG, bad args). Other stderr agy wrote on
# a successful call is forwarded to this script's stderr.
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

# B9 — no tool access is enforced, not assumed: refuse while agy's settings grant anything. A rule in
# `permissions.allow` reaches this headless call (dir #662 probe) and lets the model read files outside the
# bundle. Fail closed: a settings file this script cannot read or parse is not a clean one. The message
# names the file and the COUNT, never the rules (they carry paths), and says the rules may belong to
# other sessions or tools — editing them is a human's decision, not an agent's workaround.
settings="$HOME/.gemini/antigravity-cli/settings.json"
if [ -e "$settings" ]; then
  # jq absent (127), unparseable (2) and a non-object root (5) all land on "bad": fail closed.
  n_rules="$(jq -r '.permissions as $p
    | if $p == null then 0
      elif ($p | type) != "object" then "bad"
      elif $p.allow == null then 0
      elif ($p.allow | type) != "array" then "bad"
      else ($p.allow | length) end' "$settings" 2>/dev/null)" || n_rules="bad"
  case "$n_rules" in
    0) ;;
    ''|*[!0-9]*)
      echo "agy.sh: refusing to run — agy's settings file $settings could not be read or its permissions" >&2
      echo "  parsed (needs jq and a JSON object). An unreadable policy is not a clean one: a vendor reader" >&2
      echo "  must have no tool access, and this cannot be confirmed." >&2
      exit 1 ;;
    *)
      echo "agy.sh: refusing to run — agy's settings file $settings carries $n_rules permissions.allow rule(s)." >&2
      echo "  A vendor reader must have no tool access, and such a rule hands the model file reads (measured," >&2
      echo "  dir #662). The rules may belong to other sessions or tools, so changing them is a human's" >&2
      echo "  decision, not an agent's workaround." >&2
      exit 1 ;;
  esac
fi

user_msg="$(cat)"
sys_msg=""
[ -n "$sys_file" ] && sys_msg="$(cat "$sys_file")"

# B5(b) — no round on empty input. `grep -c` rather than `-q`: -q exits at the first match and the writer
# upstream could take SIGPIPE under pipefail (the test needs only "is there any non-space byte").
if [ "$(printf '%s' "$user_msg" | LC_ALL=C grep -c '[^[:space:]]')" = 0 ]; then
  echo "agy.sh: refusing an empty or whitespace-only user message (nothing to review) — no round was run." >&2
  exit 2
fi

# The no-tools sentence is load-bearing: a model that tries a tool instead of reading the inline
# bundle can return an EMPTY response with status SUCCESS rather than an error.
combined="$(
  [ -n "$sys_msg" ] && printf '%s\n' "$sys_msg"
  printf '\n---\n\nIMPORTANT: do NOT call any tool; you have no tool access. Answer strictly from the\ntext in this message.\n\n'
  printf '%s' "$user_msg"
)"

# B3 — the prompt is ONE argv element: Linux refuses a single argument over 131071 bytes (E2BIG), below
# the 185 KiB truncation cap, so the cap follows the platform.
platform="$(uname -s 2>/dev/null || true)"
case "$platform" in
  Linux) max_bytes=131071 ;;
  *)     max_bytes=$((185 * 1024)) ;;
esac
combined_bytes="$(printf '%s' "$combined" | wc -c | tr -d ' ')"
if [ "$combined_bytes" -gt "$max_bytes" ]; then
  echo "agy.sh: HARD STOP — combined prompt is $combined_bytes bytes, over the ${max_bytes}-byte cap for ${platform:-this platform}." >&2
  echo "  agy's inline truncation past ~192,000 bytes is SILENT, and Linux fails a single argument over 131071 bytes" >&2
  echo "  (E2BIG) — this is a hard stop, not a warning. Chunk the bundle and run one round per chunk." >&2
  exit 2
fi

# Paths resolved BEFORE the cd below: a relative AGY_BIN / --raw-out must keep meaning "relative to the caller".
case "$AGY_BIN" in /*) ;; *) AGY_BIN="$PWD/$AGY_BIN" ;; esac
case "$raw_out" in ''|/*) ;; *) raw_out="$PWD/$raw_out" ;; esac

# dir #692 — a COMPLETION MARKER, not a bare quoted-command trap: on bash 3.2 a top-level FATAL shell error
# (a `set -u` unbound variable) leaves `$?` at 0 by the time an EXIT trap runs, so a bare trap reported
# success with an empty verdict — and this script's own header says its exit code is the proof of success.
# `ok` is set only on the last line (the one legitimate exit-0 path); a status-0 exit without it is a
# crash and becomes 1. An explicit non-zero `exit N` keeps its own. The dir #264 idiom, as in
# tools/drydock/inventory.sh. dir #662 adds the neutral cwd to what the handler removes; the files are
# armed (set empty) BEFORE they are created so a kill in between leaks nothing.
resp_json="" err_file="" agy_cwd=""
ok=""
on_exit() {
  st=$?
  [ -n "$ok" ] || [ "$st" -ne 0 ] || st=1
  rm -f "$resp_json" "$err_file"
  [ -z "$agy_cwd" ] || rm -rf "$agy_cwd"
  exit "$st"
}
trap on_exit EXIT   # no explicit INT/TERM traps: an untrapped signal runs this handler at once; a TERM trap would defer it until agy returns

resp_json="$(mktemp)"
err_file="$(mktemp)"
# B8 — agy runs from a fresh empty directory: it loads AGENTS.md / GEMINI.md from its cwd into the prompt,
# and the caller's tree holds unscanned text. An explicit `${TMPDIR:-/tmp}/…XXXXXX` template — a bare
# `mktemp -d` ignores TMPDIR on macOS.
agy_cwd="$(mktemp -d "${TMPDIR:-/tmp}/agy.XXXXXX")" || {
  echo "agy.sh: could not create a neutral working directory under ${TMPDIR:-/tmp} — agy was not run." >&2
  exit 1
}

agy_status=0
( cd "$agy_cwd" && exec "$AGY_BIN" -p "$combined" --model "$MODEL" --output-format json --print-timeout "$TIMEOUT" ) \
  > "$resp_json" 2> "$err_file" || agy_status=$?
if [ "$agy_status" != 0 ]; then
  if [ "$agy_status" = 126 ] && grep -q 'Argument list too long' "$err_file"; then
    echo "agy.sh: the prompt ($combined_bytes bytes) exceeds this OS's per-argument size limit (E2BIG) — agy was" >&2
    echo "  not run. Chunk the bundle and run one round per chunk." >&2
    exit 2
  fi
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

# B4 — a denied tool call is a failure even when a reply came back: the reply then rests on a partial view.
# The measured notice: `a tool required the "<tool>" permission`. Any OTHER stderr on a successful call is
# forwarded (it used to be dropped) — an unrecognised denial format stays visible rather than silent.
if grep -Eq 'required the "[^"]+" permission' "$err_file"; then
  echo "agy.sh: a tool call was denied during this round — the reply rests on a partial view and is withheld." >&2
  echo "  agy's stderr:" >&2
  cat "$err_file" >&2
  exit 1
fi
[ ! -s "$err_file" ] || cat "$err_file" >&2

printf '%s' "$content"
ok=1   # genuine completion — the EXIT trap above reads it (dir #692)
