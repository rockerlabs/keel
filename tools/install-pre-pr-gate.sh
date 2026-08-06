#!/usr/bin/env bash
# install-pre-pr-gate — wire the /polish pre-PR gate into a project's Claude Code hooks (opt-in, per repo).
#
#   install-pre-pr-gate.sh <repo-path>       wire 6 hooks into <repo-path>/.claude/settings.json (project
#                                            scope — the default; only sessions IN this repo are gated)
#   install-pre-pr-gate.sh --global          wire into ~/.claude/settings.json instead — EVERY repo you
#                                            open on this machine gets the gate, not just this one
#   install-pre-pr-gate.sh --force …         overwrite a pre-existing, DIFFERENT hook on the same
#                                            event+matcher (backs up settings.json first; default: refuse)
#
# Ships `/polish` (commands/polish.md) + its enforcement (tools/pre-pr-gate.sh) to adopters, not just the
# maintainer (dir #68). `install.sh` now drops `polish.md` from its skip list unconditionally, but wires
# NOTHING into settings.json by itself — a hook changes what your sessions can do without asking each
# time, so wiring it is this separate, explicit, opt-in step. Nothing about your workflow changes until
# you run this. Once wired: the agent's own `gh pr create` is hard-denied until `/polish` (simplify +
# tests + a depth-matched review) has run cleanly on the current commit — your own terminal is never
# gated, only the agent's tool calls (a PreToolUse hook fires on THOSE, not on you typing `gh` yourself).
#
# The 5th hook (`SubagentStop`/`general-purpose`, dir #70) traces the independent-agent-review leg
# `/polish` step 5 falls back to when `/code-review` itself refuses model invocation — see
# tools/pre-pr-gate.sh's own dir #70 header section for the full mechanism.
#
# The 6th hook (`PostToolUse`/`AskUserQuestion`, dir #88) traces step 5(a)'s MANDATORY review-reminder
# dialog — the "agent review already ran, additionally run /code-review too?" question — so the gate can
# tell an answered dialog from a silently-skipped one on an `agent:*`-shaped review outcome. See
# tools/pre-pr-gate.sh's own dir #88 header section for the full mechanism, including the arming rule
# (the gate-side check stays inert until this hook is actually wired, avoiding a false-deny window
# between a `git pull` picking up the check and this installer re-wiring the trace leg).
#
# Requires a KEPT checkout: the hooks point at THIS checkout's tools/pre-pr-gate.sh by absolute path — no
# copy (a stale copy silently going out of sync was a felt incident; see that file's own header). A
# temporary bootstrap clone (about to be deleted) can't be the source; re-run from a checkout you keep.
#
# Needs jq to edit settings.json safely. Without it: prints the exact hooks JSON to paste in by hand
# instead of writing anything — degrade to instructions, never a partial/broken write.
#
# Never clobbers your data silently (same discipline as install-secret-guard.sh): an existing hook
# already wired to the SAME event+matcher running a DIFFERENT command is refused and named; --force
# backs up settings.json (a timestamped sibling) first, then replaces just that matcher's hooks.
# Everything else already in settings.json (other hooks, other keys) is left exactly as it was. A hook
# that's already exactly ours is left alone (idempotent — safe to re-run after every `git pull`).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
gate="$repo_root/tools/pre-pr-gate.sh"

# A temp bootstrap clone (bootstrap.sh's `${TMPDIR:-/tmp}/keel.XXXXXX/keel`, reaped on exit) is not a
# checkout to point hooks at — they'd dangle within moments. This script is never invoked BY bootstrap
# (it's a separate, deliberate, opt-in step), so there's no env signal to read the way install.sh reads
# KEEL_EPHEMERAL — the path shape is what's left to go on. Strip a trailing slash from TMPDIR first
# (macOS sets it WITH one, e.g. "/var/folders/.../T/") — pwd never emits a double slash, so an
# unstripped pattern would silently never match on that platform.
tmpdir_base="${TMPDIR:-/tmp}"; tmpdir_base="${tmpdir_base%/}"
case "$repo_root" in
  "$tmpdir_base"/keel.*/keel)
    echo "install-pre-pr-gate: this looks like a temporary bootstrap clone (about to be deleted), not a" >&2
    echo "  kept checkout — the hooks would point at a path that stops existing. Clone Keel somewhere" >&2
    echo "  permanent (e.g. ~/keel) and re-run tools/install-pre-pr-gate.sh from there." >&2
    exit 2
    ;;
esac

usage() {
  cat <<'EOF'
install-pre-pr-gate — wire the /polish pre-PR gate's 6 hooks into Claude Code settings.json.

Usage:
  install-pre-pr-gate.sh <repo-path>     wire into <repo-path>/.claude/settings.json (project scope)
  install-pre-pr-gate.sh --global        wire into ~/.claude/settings.json (every repo on this machine)
  install-pre-pr-gate.sh --force …       replace a pre-existing, different hook on the same event+matcher
  install-pre-pr-gate.sh -h | --help
EOF
}

force=0
global=0
rest=""
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    --global) global=1 ;;
    -h|--help) usage; exit 0 ;;
    *) if [ -n "$rest" ]; then
         echo "install-pre-pr-gate.sh: unexpected extra argument '$a' — one repo path (or --global) per run" >&2
         exit 2
       fi
       rest="$a" ;;
  esac
done
set -- ${rest:+"$rest"}

if [ "$global" = 1 ]; then
  [ -z "${1:-}" ] || { echo "install-pre-pr-gate.sh: --global doesn't take a repo path" >&2; exit 2; }
  settings_dir="${KEEL_HOME:-${HOME:?install-pre-pr-gate: --global needs HOME set}/.claude}"
  echo "install-pre-pr-gate: --global wires EVERY repo on this machine — the agent's gh pr create is" >&2
  echo "  hard-denied without a matching /polish receipt in every project you open here, not just this one." >&2
elif [ -n "${1:-}" ]; then
  repo="$1"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
  settings_dir="$repo/.claude"
else
  usage >&2
  exit 2
fi
settings="$settings_dir/settings.json"

# print_snippet — the raw hooks JSON, ready to paste into settings.json's "hooks" key by hand. Must work
# WITHOUT jq (it's the fallback for exactly that case), so it's a plain heredoc, not jq -n.
print_snippet() {
  cat <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash '$gate'" }] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "bash '$gate' rollout-check" }] }
    ],
    "PostToolUse": [
      { "matcher": "Skill", "hooks": [{ "type": "command", "command": "bash '$gate' skill-trace" }] },
      { "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "bash '$gate' skill-trace" }] }
    ],
    "UserPromptExpansion": [
      { "matcher": "code-review", "hooks": [{ "type": "command", "command": "bash '$gate' skill-trace" }] }
    ],
    "SubagentStop": [
      { "matcher": "general-purpose", "hooks": [{ "type": "command", "command": "bash '$gate' skill-trace" }] }
    ]
  }
}
EOF
}

if ! command -v jq >/dev/null 2>&1; then
  echo "install-pre-pr-gate: jq is required to safely edit settings.json (not found on PATH)." >&2
  echo "Nothing was changed. Merge this into the \"hooks\" key of $settings by hand:" >&2
  print_snippet
  exit 1
fi

mkdir -p "$settings_dir"
current="{}"
if [ -f "$settings" ]; then
  if ! current="$(jq -c '.' "$settings" 2>/dev/null)"; then
    echo "install-pre-pr-gate: $settings is not valid JSON — fix or remove it by hand. Nothing was changed." >&2
    exit 2
  fi
fi

# The 6 hooks — shapes documented in tools/pre-pr-gate.sh's own header (reconcile there on drift).
# $gate is single-quoted WITHIN the command string itself (not just JSON-escaped, which jq already does
# for the string as a whole) — a checkout path containing a space would otherwise split into two argv
# tokens when Claude Code's hook runner passes this string to a shell, silently no-op'ing every hook.
hook_specs="$(jq -n --arg gate "$gate" '[
  {event: "PreToolUse",         matcher: "Bash",           command: ("bash '\''" + $gate + "'\''")},
  {event: "SessionStart",       matcher: "startup",        command: ("bash '\''" + $gate + "'\'' rollout-check")},
  {event: "PostToolUse",        matcher: "Skill",          command: ("bash '\''" + $gate + "'\'' skill-trace")},
  {event: "UserPromptExpansion", matcher: "code-review",   command: ("bash '\''" + $gate + "'\'' skill-trace")},
  {event: "SubagentStop",       matcher: "general-purpose", command: ("bash '\''" + $gate + "'\'' skill-trace")},
  {event: "PostToolUse",        matcher: "AskUserQuestion", command: ("bash '\''" + $gate + "'\'' skill-trace")}
]')"

# Valid JSON is not the same as the expected SHAPE — a hand-edited settings.json could have ".hooks" as
# an array, or ".hooks.PreToolUse" as a string, and the merge below would otherwise crash with a raw jq
# type error instead of the clean refusal every other bad-input path here gives.
shape_ok="$(jq -r --argjson specs "$hook_specs" '
  (.hooks // {}) as $h |
  (($h | type) == "object") as $hooks_ok |
  ($specs | map(.event) | unique | all(. as $e | (($h[$e] // []) | type) == "array")) as $events_ok |
  ($hooks_ok and $events_ok)
' <<<"$current")"
if [ "$shape_ok" != "true" ]; then
  echo "install-pre-pr-gate: $settings's \"hooks\" section has an unexpected shape (not the usual" >&2
  echo "  Claude Code hooks object) — fix it by hand. Nothing was changed." >&2
  exit 2
fi

# One pass computes BOTH the merged settings AND each hook's classification — MISSING (not wired), SAME
# (already exactly ours — idempotent), or CONFLICT (that event+matcher already runs a different command,
# someone else's) — from the same walk, so there's exactly one place that decides what "already wired"
# means. Computing the merged (as-if-forced) result even on a CONFLICT is harmless: it's simply never
# written unless the refuse/--force gate below clears it.
merge_prog='
{obj: (.hooks //= {}), report: []} |
reduce $specs[] as $s (.;
  .obj.hooks[$s.event] //= [] |
  (.obj.hooks[$s.event] | map(.matcher == $s.matcher) | index(true)) as $idx |
  if $idx == null then
    .obj.hooks[$s.event] += [{matcher: $s.matcher, hooks: [{type: "command", command: $s.command}]}]
    | .report += [["MISSING", $s.event, $s.matcher]]
  elif (.obj.hooks[$s.event][$idx].hooks // [] | map(.command) | index($s.command)) != null then
    .report += [["SAME", $s.event, $s.matcher]]
  else
    .obj.hooks[$s.event][$idx].hooks = [{type: "command", command: $s.command}]
    | .report += [["CONFLICT", $s.event, $s.matcher]]
  end
) |
{new: .obj, report: (.report | map(@tsv) | join("\n"))}
'
merged="$(jq --argjson specs "$hook_specs" "$merge_prog" <<<"$current")"
statuses="$(jq -r '.report' <<<"$merged")"

conflicts=""
n_conflict=0
while IFS=$'\t' read -r status event matcher; do
  [ -n "$status" ] || continue
  if [ "$status" = "CONFLICT" ]; then
    n_conflict=$((n_conflict + 1))
    conflicts="${conflicts}${conflicts:+, }$event/$matcher"
  fi
done <<<"$statuses"

if [ "$n_conflict" -gt 0 ] && [ "$force" != 1 ]; then
  echo "install-pre-pr-gate: $settings already has a different hook wired for: $conflicts" >&2
  echo "  Refusing to overwrite your data — re-run with --force to back it up and replace, or edit" >&2
  echo "  $settings by hand. Nothing was changed." >&2
  exit 3
fi

if [ "$n_conflict" -gt 0 ] && [ -f "$settings" ]; then
  backup="$settings.$(date -u +%Y%m%dT%H%M%SZ).bak"
  cp "$settings" "$backup"
  echo "install-pre-pr-gate: backed up your existing settings.json → $(basename "$backup") (--force)"
fi

new_settings="$(jq '.new' <<<"$merged")"
printf '%s\n' "$new_settings" > "$settings.keeltmp.$$" && mv -f "$settings.keeltmp.$$" "$settings"

while IFS=$'\t' read -r status event matcher; do
  [ -n "$status" ] || continue
  case "$status" in
    MISSING)  echo "  +    $event/$matcher wired" ;;
    SAME)     echo "  =    $event/$matcher already wired (up to date)" ;;
    CONFLICT) echo "  ^    $event/$matcher replaced (--force)" ;;
  esac
done <<<"$statuses"

echo "install-pre-pr-gate: wired into $settings"
echo "Restart Claude Code (hooks load only at session start) — then /polish unlocks gh pr create for real."
echo "Health check any time: tools/doctor.sh --install"
