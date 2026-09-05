#!/usr/bin/env bash
# install-read-trace — wire dir #387's read-trace fuses into a project's (or the machine-global)
# Claude Code hooks (opt-in, per repo). Same discipline as tools/install-pre-pr-gate.sh, trimmed to
# this mechanism's own 3 hooks:
#
#   install-read-trace.sh <repo-path>       wire into <repo-path>/.claude/settings.json (project
#                                            scope — the default; only sessions IN this repo are traced)
#   install-read-trace.sh --global          wire into ~/.claude/settings.json instead — EVERY repo you
#                                            open on this machine gets the trace, not just this one
#   install-read-trace.sh --home DIR        --global, but into DIR/settings.json (follows an
#                                            install.sh --home DIR install, same flag as
#                                            install-pre-pr-gate.sh's own --home)
#   install-read-trace.sh --force …         overwrite a pre-existing, DIFFERENT hook on the same
#                                            event+matcher (backs up settings.json first; default: refuse)
#   install-read-trace.sh --uninstall …     remove exactly the 3 hooks this installer wired
#                                            (byte-identical match only)
#
# Wires 3 hooks, all pointing at THIS checkout's tools/read-trace.sh by absolute path (no copy — a
# stale copy silently going out of sync is the same felt-incident class tools/pre-pr-gate.sh's own
# header names for itself):
#   PostToolUse  / Edit|Write|NotebookEdit|Read  -> read-trace.sh log-tool     (silent)
#   SessionStart / startup                       -> read-trace.sh startup     (silent unless a
#                                                    wrap-fuse flag is pending)
#   SessionEnd   / (all reasons)                 -> read-trace.sh session-end (silent)
#
# Never clobbers your data silently (same discipline as install-secret-guard.sh/
# install-pre-pr-gate.sh): an existing hook already wired to the SAME event+matcher running a
# DIFFERENT command is refused and named; --force backs up settings.json (a timestamped sibling)
# first. Everything else already in settings.json is left exactly as it was. A hook that's already
# exactly ours is left alone (idempotent — safe to re-run after every `git pull`).
#
# Needs jq to edit settings.json safely. Without it: prints the exact hooks JSON to paste in by hand
# instead of writing anything.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
rt="$repo_root/tools/read-trace.sh"

tmpdir_base="${TMPDIR:-/tmp}"; tmpdir_base="${tmpdir_base%/}"
case "$repo_root" in
  "$tmpdir_base"/keel.*/keel)
    echo "install-read-trace: this looks like a temporary bootstrap clone (about to be deleted), not a" >&2
    echo "  kept checkout — the hooks would point at a path that stops existing. Clone Keel somewhere" >&2
    echo "  permanent (e.g. ~/keel) and re-run tools/install-read-trace.sh from there." >&2
    exit 2
    ;;
esac

usage() {
  cat <<'EOF'
install-read-trace — wire dir #387's read-trace fuses' 3 hooks into Claude Code settings.json.

Usage:
  install-read-trace.sh <repo-path>     wire into <repo-path>/.claude/settings.json (project scope)
  install-read-trace.sh --global        wire into ~/.claude/settings.json (every repo on this machine)
  install-read-trace.sh --home DIR      --global, but into DIR/settings.json (follows install.sh --home)
  install-read-trace.sh --force …       replace a pre-existing, different hook on the same event+matcher
  install-read-trace.sh --uninstall …   remove exactly the hooks this installer wired (same target flags)
  install-read-trace.sh -h | --help
EOF
}

force=0
uninstall=0
home_dir=""
scope_flag=""
rest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
    --global) [ -n "$home_dir" ] || scope_flag="--global" ;;
    --home)
      shift
      case "${1:-}" in
        "")  echo "install-read-trace.sh: --home needs a DIR (got nothing)" >&2; exit 2 ;;
        -*)  echo "install-read-trace.sh: --home needs a DIR, got the flag '$1'" >&2; exit 2 ;;
      esac
      home_dir="$1"; scope_flag="--home" ;;
    -h|--help) usage; exit 0 ;;
    *) if [ -n "$rest" ]; then
         echo "install-read-trace.sh: unexpected extra argument '$1' — one repo path (or --global/--home DIR) per run" >&2
         exit 2
       fi
       rest="$1" ;;
  esac
  shift
done
set -- ${rest:+"$rest"}

if [ "$uninstall" = 1 ] && [ "$force" = 1 ]; then
  echo "install-read-trace.sh: --uninstall and --force don't combine (--uninstall never touches a" >&2
  echo "  hook that differs from ours, with or without --force)" >&2
  exit 2
fi

if [ -n "$scope_flag" ]; then
  [ -z "${1:-}" ] || { echo "install-read-trace.sh: $scope_flag doesn't take a repo path" >&2; exit 2; }
  settings_dir="${home_dir:-${KEEL_HOME:-${HOME:?install-read-trace: --global needs HOME set, or pass --home DIR}/.claude}}"
  if [ -n "$home_dir" ] && [ ! -d "$home_dir" ]; then
    echo "install-read-trace.sh: --home $home_dir does not exist (or is not a directory)." >&2
    echo "  --home names a home an install already created; it is not a place to create one. Nothing" >&2
    echo "  was changed. Check the path, or run install.sh --home \"$home_dir\" first." >&2
    exit 2
  fi
  if [ "$uninstall" = 1 ]; then
    echo "install-read-trace: $scope_flag reaches EVERY repo on this machine — removing here lifts the" >&2
    echo "  trace everywhere it was machine-global, not just one project." >&2
  else
    echo "install-read-trace: $scope_flag wires EVERY repo on this machine — every session opened here" >&2
    echo "  gets its Read/Edit/Write/NotebookEdit calls logged (see tools/read-trace.sh's own header)." >&2
  fi
  if [ "$settings_dir" != "${HOME:-}/.claude" ]; then
    echo "  NOTE Claude Code reads ${HOME:-\$HOME}/.claude/settings.json as its global scope; this run targets" >&2
    echo "  $settings_dir (matching an install.sh --home / KEEL_HOME install). If your harness isn't" >&2
    echo "  pointed at that home, wire per repo instead:  install-read-trace.sh <repo>" >&2
  fi
elif [ -n "${1:-}" ]; then
  repo="$1"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
  settings_dir="$repo/.claude"
else
  usage >&2
  exit 2
fi
settings="$settings_dir/settings.json"

if [ "$uninstall" = 1 ] && [ ! -f "$settings" ]; then
  echo "install-read-trace: nothing to remove — no $settings"
  exit 0
fi

print_snippet() {
  cat <<EOF
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write|NotebookEdit|Read", "hooks": [{ "type": "command", "command": "bash '$rt' log-tool" }] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "bash '$rt' startup" }] }
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "bash '$rt' session-end" }] }
    ]
  }
}
EOF
}

if ! command -v jq >/dev/null 2>&1; then
  echo "install-read-trace: jq is required to safely edit settings.json (not found on PATH)." >&2
  if [ "$uninstall" = 1 ]; then
    echo "Nothing was changed. Remove the read-trace hook entries from $settings by hand — look for the" >&2
    echo "  \"command\" values containing '$rt' under hooks.PostToolUse/SessionStart/SessionEnd and" >&2
    echo "  delete just those matcher entries." >&2
  else
    echo "Nothing was changed. Merge this into the \"hooks\" key of $settings by hand:" >&2
    print_snippet
  fi
  exit 1
fi

mkdir -p "$settings_dir"
current="{}"
if [ -f "$settings" ]; then
  if ! current="$(jq -c '.' "$settings" 2>/dev/null)"; then
    echo "install-read-trace: $settings is not valid JSON — fix or remove it by hand. Nothing was changed." >&2
    exit 2
  fi
fi

hook_specs="$(jq -n --arg rt "$rt" '[
  {event: "PostToolUse",  matcher: "Edit|Write|NotebookEdit|Read", command: ("bash '\''" + $rt + "'\'' log-tool")},
  {event: "SessionStart", matcher: "startup",                      command: ("bash '\''" + $rt + "'\'' startup")},
  {event: "SessionEnd",   matcher: "",                             command: ("bash '\''" + $rt + "'\'' session-end")}
]')"

_backup_settings() { backup="$1.$(date -u +%Y%m%dT%H%M%SZ).bak"; cp "$1" "$backup"; }
_atomic_write() { printf '%s\n' "$2" > "$1.keeltmp.$$" && mv -f "$1.keeltmp.$$" "$1"; }

shape_ok="$(jq -r --argjson specs "$hook_specs" '
  (.hooks // {}) as $h |
  (($h | type) == "object") as $hooks_ok |
  ($specs | map(.event) | unique | all(. as $e | (($h[$e] // []) | type) == "array")) as $events_ok |
  ($hooks_ok and $events_ok)
' <<<"$current")"
if [ "$shape_ok" != "true" ]; then
  echo "install-read-trace: $settings's \"hooks\" section has an unexpected shape (not the usual" >&2
  echo "  Claude Code hooks object) — fix it by hand. Nothing was changed." >&2
  exit 2
fi

if [ "$uninstall" = 1 ]; then
  remove_prog='
{obj: (.hooks //= {}), report: []} |
reduce $specs[] as $s (.;
  (.obj.hooks[$s.event] // []) as $arr |
  ($arr | map(.matcher == $s.matcher) | index(true)) as $idx |
  if $idx == null then
    .
  elif $arr[$idx].hooks == [{type: "command", command: $s.command}] then
    .obj.hooks[$s.event] = (.obj.hooks[$s.event] | del(.[$idx]))
    | .report += [["REMOVED", $s.event, $s.matcher]]
  else
    .report += [["KEPT", $s.event, $s.matcher]]
  end
) |
($specs | map(.event) | unique) as $our_events |
.obj.hooks = (.obj.hooks | with_entries(. as $e | select(($e.value | length > 0) or ($our_events | index($e.key) | not)))) |
{new: .obj, report: (.report | map(@tsv) | join("\n"))}
'
  removal="$(jq --argjson specs "$hook_specs" "$remove_prog" <<<"$current")"
  statuses="$(jq -r '.report' <<<"$removal")"

  print_removal_status() {
    case "$1" in
      REMOVED) echo "  -    $2/$3 removed" ;;
      KEPT)    echo "  =    $2/$3 differs from ours — kept (yours)" ;;
    esac
  }

  n_removed=0; n_kept=0
  while IFS=$'\t' read -r status event matcher; do
    [ -n "$status" ] || continue
    case "$status" in
      REMOVED) n_removed=$((n_removed + 1)) ;;
      KEPT)    n_kept=$((n_kept + 1)) ;;
    esac
  done <<<"$statuses"

  if [ "$n_removed" = 0 ]; then
    echo "install-read-trace: nothing to remove — no wired hook at $settings matches what this installer would wire"
    if [ "$n_kept" -gt 0 ]; then
      echo "  ($n_kept hook(s) present on the same event+matcher, but differing from ours — left in place)"
      while IFS=$'\t' read -r status event matcher; do
        [ "$status" = "KEPT" ] || continue
        print_removal_status "$status" "$event" "$matcher"
      done <<<"$statuses"
    fi
    exit 0
  fi

  _backup_settings "$settings"
  new_settings="$(jq '.new' <<<"$removal")"
  _atomic_write "$settings" "$new_settings"
  echo "install-read-trace: backed up settings.json → $(basename "$backup")"

  while IFS=$'\t' read -r status event matcher; do
    [ -n "$status" ] || continue
    print_removal_status "$status" "$event" "$matcher"
  done <<<"$statuses"

  echo "install-read-trace: $n_removed of 3 hook(s) removed from $settings"
  exit 0
fi

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
  echo "install-read-trace: $settings already has a different hook wired for: $conflicts" >&2
  echo "  Refusing to overwrite your data — re-run with --force to back it up and replace, or edit" >&2
  echo "  $settings by hand. Nothing was changed." >&2
  exit 3
fi

if [ "$n_conflict" -gt 0 ] && [ -f "$settings" ]; then
  _backup_settings "$settings"
  echo "install-read-trace: backed up your existing settings.json → $(basename "$backup") (--force)"
fi

new_settings="$(jq '.new' <<<"$merged")"
_atomic_write "$settings" "$new_settings"

while IFS=$'\t' read -r status event matcher; do
  [ -n "$status" ] || continue
  case "$status" in
    MISSING)  echo "  +    $event/$matcher wired" ;;
    SAME)     echo "  =    $event/$matcher already wired (up to date)" ;;
    CONFLICT) echo "  ^    $event/$matcher replaced (--force)" ;;
  esac
done <<<"$statuses"

echo "install-read-trace: wired into $settings"
echo "Restart Claude Code (hooks load only at session start) — read-trace is now recording."
