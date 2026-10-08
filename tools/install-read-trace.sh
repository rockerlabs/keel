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
#   install-read-trace.sh --force …         replace a STALE copy of this same hook (same script, another
#                                            path — a moved checkout); backs up settings.json first
#                                            (default: refuse that one case; a different hook on the same
#                                            event+matcher needs no --force — it is appended beside)
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
# Never clobbers your data silently: an existing hook already wired to the SAME event+matcher running a
# DIFFERENT command is left exactly as it is and ours is APPENDED beside it, in a sibling entry with
# that matcher (dir #468 — the slot is shared: install-pre-pr-gate.sh holds SessionStart/startup too).
# The one refusal left is a STALE copy of this very hook (same script, another path — a moved checkout):
# appending would fire it twice, so --force backs up settings.json (a timestamped sibling) first, then
# swaps just that command for ours. Everything else already in settings.json is left exactly as it was.
# A hook that's already exactly ours is left alone (idempotent — safe to re-run after every `git pull`).
#
# Needs jq to edit settings.json safely. Without it: prints the exact hooks JSON to paste in by hand
# instead of writing anything.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
rt="$repo_root/tools/read-trace.sh"

# Checked BEFORE sourcing tools/lib/ below: a bootstrap clone's own copy of this script is a bare,
# minimal fixture (found live by install-pre-pr-gate.sh's own regression test, same shape here) — it
# never carries tools/lib/ at all, so a source attempted first would fail on a missing file and mask
# this check's own, more useful "temp clone" rejection behind a raw "no such file" exit.
tmpdir_base="${TMPDIR:-/tmp}"; tmpdir_base="${tmpdir_base%/}"
case "$repo_root" in
  "$tmpdir_base"/keel.*/keel)
    echo "install-read-trace: this looks like a temporary bootstrap clone (about to be deleted), not a" >&2
    echo "  kept checkout — the hooks would point at a path that stops existing. Clone Keel somewhere" >&2
    echo "  permanent (e.g. ~/keel) and re-run tools/install-read-trace.sh from there." >&2
    exit 2
    ;;
esac

# shellcheck source=tools/lib/sh-quote.sh
. "$here/lib/sh-quote.sh"
# shellcheck source=tools/lib/repo-arg-guard.sh
. "$here/lib/repo-arg-guard.sh"
# rt_sh — $rt quoted (dir #514), already wrapped in single quotes AND JSON-escaped, for the ONE place
# $rt is spliced into a shell command string INSIDE a hand-written JSON heredoc, by hand, rather than
# through jq's `@sh` (print_snippet below, the no-jq fallback — a heredoc can't call a jq filter, so
# it needs sh_quote_json's second JSON-escaping pass too, not just sh_quote's shell one). Same
# escaping jq's `@sh` performs (JSON-aware, so it needs no separate JSON-escaping step of its own),
# shared with install-pre-pr-gate.sh's identical need via tools/lib/sh-quote.sh rather than a second
# hand-copy.
rt_sh="$(sh_quote_json "$rt")"
# hook-install (dir #437 MW8) — REQUIRED, not optional, unlike the two libs above: it computes the
# settings.json merge/removal itself, so a degrade-and-continue stub here would write a merge this
# script did not compute. Refuse outright on a missing or unparseable copy; see
# tools/lib/artifact-cksum.sh's header for the pattern.
if [ -s "$here/lib/hook-install.sh" ] && bash -n "$here/lib/hook-install.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/hook-install.sh
  . "$here/lib/hook-install.sh"
else
  echo "install-read-trace: tools/lib/hook-install (the settings-merge lib) is missing or corrupted — this checkout is incomplete and cannot safely edit settings.json; re-clone or re-download Keel" >&2
  exit 1
fi
# safe-write (dir #679) — REQUIRED: the settings.json write and its backup go through it (the
# hook-install wrappers above), so a symlinked settings.json is written through and a hard-linked one
# refused. Loaded right after hook-install, so a checkout missing both still names hook-install first.
if [ -s "$here/lib/safe-write.sh" ] && bash -n "$here/lib/safe-write.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/safe-write.sh
  . "$here/lib/safe-write.sh"
else
  echo "install-read-trace: tools/lib/safe-write.sh (the safe-write lib) is missing or corrupted — re-clone or re-download Keel and re-run" >&2
  exit 1
fi
KEEL_SAFE_WRITE_CHECKOUT="$repo_root"

usage() {
  cat <<'EOF'
install-read-trace — wire dir #387's read-trace fuses' 3 hooks into Claude Code settings.json.

Usage:
  install-read-trace.sh <repo-path>     wire into <repo-path>/.claude/settings.json (project scope)
  install-read-trace.sh --global        wire into ~/.claude/settings.json (every repo on this machine)
  install-read-trace.sh --home DIR      --global, but into DIR/settings.json (follows install.sh --home)
  install-read-trace.sh --force …       replace a stale copy of this hook (same script, another path), with a backup
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
  keel_repo_arg_guard "$repo"
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
      { "matcher": "Edit|Write|NotebookEdit|Read", "hooks": [{ "type": "command", "command": "bash $rt_sh log-tool" }] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "bash $rt_sh startup" }] }
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "bash $rt_sh session-end" }] }
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

# Quoted via jq's own `@sh` (dir #514) — NOT a hand-rolled `"'\''" + $rt + "'\''"` splice: that form
# wraps $rt in single quotes but never escapes one IF $rt itself contains one, so a checkout path with
# an apostrophe produced a command with an unterminated quote ("unexpected EOF while looking for
# matching quote") and every wired hook silently broke. `@sh` produces a shell-safe single-quoted
# token, escaping any embedded `'` as `'\''`.
hook_specs="$(jq -n --arg rt "$rt" '[
  {event: "PostToolUse",  matcher: "Edit|Write|NotebookEdit|Read", command: ("bash " + ($rt|@sh) + " log-tool")},
  {event: "SessionStart", matcher: "startup",                      command: ("bash " + ($rt|@sh) + " startup")},
  {event: "SessionEnd",   matcher: "",                             command: ("bash " + ($rt|@sh) + " session-end")}
]')"

hook_install_check_shape "install-read-trace" "$settings" "$hook_specs" "$current" || exit 2

if [ "$uninstall" = 1 ]; then
  removal="$(hook_install_remove "$hook_specs" "$current")"
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

  hook_install_backup "$settings"
  new_settings="$(jq '.new' <<<"$removal")"
  hook_install_atomic_write "$settings" "$new_settings"
  echo "install-read-trace: backed up settings.json → $(basename "$HOOK_INSTALL_BACKUP")"

  while IFS=$'\t' read -r status event matcher; do
    [ -n "$status" ] || continue
    print_removal_status "$status" "$event" "$matcher"
  done <<<"$statuses"

  echo "install-read-trace: $n_removed of 3 hook(s) removed from $settings"
  exit 0
fi

merged="$(hook_install_merge "$hook_specs" "$current")"
statuses="$(jq -r '.report' <<<"$merged")"

stale=""
n_stale=0
while IFS=$'\t' read -r status event matcher; do
  [ -n "$status" ] || continue
  if [ "$status" = "STALE" ]; then
    n_stale=$((n_stale + 1))
    stale="${stale}${stale:+, }$event/$matcher"
  fi
done <<<"$statuses"

if [ "$n_stale" -gt 0 ] && [ "$force" != 1 ]; then
  echo "install-read-trace: $settings already wires this hook at a different path for: $stale" >&2
  echo "  (a moved or re-cloned checkout — appending would fire it twice). Re-run with --force to back" >&2
  echo "  up settings.json and point it at this checkout; your other hooks stay. Nothing was changed." >&2
  exit 3
fi

if [ "$n_stale" -gt 0 ] && [ -f "$settings" ]; then
  hook_install_backup "$settings"
  echo "install-read-trace: backed up your existing settings.json → $(basename "$HOOK_INSTALL_BACKUP") (--force)"
fi

new_settings="$(jq '.new' <<<"$merged")"
hook_install_atomic_write "$settings" "$new_settings"

while IFS=$'\t' read -r status event matcher; do
  [ -n "$status" ] || continue
  case "$status" in
    MISSING)  echo "  +    $event/$matcher wired" ;;
    SAME)     echo "  =    $event/$matcher already wired (up to date)" ;;
    APPENDED) echo "  +    $event/$matcher APPENDED beside your existing hook (yours is untouched)" ;;
    STALE)    echo "  ^    $event/$matcher stale path replaced (--force); your other hooks untouched" ;;
  esac
done <<<"$statuses"

echo "install-read-trace: wired into $settings"
echo "Restart Claude Code (hooks load only at session start) — read-trace is now recording."
