#!/usr/bin/env bash
# install-machine-watch — wire dir #437's machine-global watcher (tools/machine-watch.sh) into a project's
# (or the machine-global) Claude Code hooks. Opt-in, per repo; adopter-usable, Claude-Code-only (hooks are
# a Claude Code mechanism — the watcher's CLI `snapshot`/`check` runs by hand on any harness). Same
# discipline as tools/install-read-trace.sh, on the shared settings-merge core (tools/lib/hook-install.sh).
#
#   install-machine-watch.sh <repo-path>    wire into <repo-path>/.claude/settings.json (project scope —
#                                            the DEFAULT: survives deletion of ~/.claude, but covers only
#                                            sessions started in that repo)
#   install-machine-watch.sh --global       wire into ~/.claude/settings.json instead — covers EVERY
#                                            session and subagent on this machine, but lives in the
#                                            harness home, so a deletion of ~/.claude removes it too
#   install-machine-watch.sh --home DIR     --global, but into DIR/settings.json (follows an
#                                            install.sh --home DIR install)
#   install-machine-watch.sh --print …      print the hooks JSON to merge by hand; write nothing
#   install-machine-watch.sh --force …      replace a STALE copy of this same hook (same script, another
#                                            path — a moved checkout); backs up settings.json first
#   install-machine-watch.sh --uninstall …  remove exactly the 4 hooks this installer wired
#
# The two scopes do not conflict: wire both and the additive merge keeps them separate.
#
# Wires 4 hooks, all `bash <this checkout>/tools/machine-watch.sh hook` by absolute path (no copy):
#   SessionStart       / (any source)                  record this session's baseline (or, on a resume, check)
#   PostToolUse        / Bash|Write|Edit|NotebookEdit   check after every write-capable tool call
#   PostToolUseFailure / Bash|Write|Edit|NotebookEdit   …and after one that failed (it may still have written)
#   SessionEnd         / (any reason)                  drop the baseline
# Hooks from settings files also run inside subagents, so one wiring covers a vendor fan-out too.
#
# Creates the baseline store directory ($HOME/.keel/machine-watch, or $KEEL_MACHINE_WATCH_STORE) at install
# time, so the watcher can read its later absence as a removal rather than a fresh install.
#
# NEVER writes a deny rule: prevention is a documented recipe only (docs/delegation.md), with its measured
# cost beside it. Nothing here touches `permissions`.
#
# Never clobbers your data silently (same discipline as install-read-trace.sh): a different hook on the same
# event+matcher is left exactly as it is and ours is APPENDED beside it, in a sibling entry. The one refusal
# is a STALE copy of this very hook (same script, another path), where appending would fire it twice —
# --force backs up settings.json first, then swaps just that command. A hook already exactly ours is left
# alone (idempotent — safe to re-run after every `git pull`).
#
# Needs jq to edit settings.json safely. Without it: prints the exact hooks JSON to paste in by hand.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
mw="$repo_root/tools/machine-watch.sh"

# Checked BEFORE sourcing tools/lib/ below: a bootstrap clone's own copy of this script is a bare,
# minimal fixture (found live by install-pre-pr-gate.sh's own regression test, same shape here) — it
# never carries tools/lib/ at all, so a source attempted first would fail on a missing file and mask
# this check's own, more useful "temp clone" rejection behind a raw "no such file" exit.
tmpdir_base="${TMPDIR:-/tmp}"; tmpdir_base="${tmpdir_base%/}"
case "$repo_root" in
  "$tmpdir_base"/keel.*/keel)
    echo "install-machine-watch: this looks like a temporary bootstrap clone (about to be deleted), not a" >&2
    echo "  kept checkout — the hooks would point at a path that stops existing. Clone Keel somewhere" >&2
    echo "  permanent (e.g. ~/keel) and re-run tools/install-machine-watch.sh from there." >&2
    exit 2
    ;;
esac

# shellcheck source=tools/lib/sh-quote.sh
. "$here/lib/sh-quote.sh"
# shellcheck source=tools/lib/repo-arg-guard.sh
. "$here/lib/repo-arg-guard.sh"
# mw_sh — $mw quoted (dir #514), already wrapped in single quotes AND JSON-escaped, for the ONE place
# $mw is spliced into a shell command string INSIDE a hand-written JSON heredoc, by hand, rather than
# through jq's `@sh` (print_snippet below, the no-jq fallback — a heredoc can't call a jq filter, so
# it needs sh_quote_json's second JSON-escaping pass too, not just sh_quote's shell one). Same
# escaping jq's `@sh` performs (JSON-aware, so it needs no separate JSON-escaping step of its own),
# shared with install-pre-pr-gate.sh's identical need via tools/lib/sh-quote.sh rather than a second
# hand-copy.
mw_sh="$(sh_quote_json "$mw")"
# state-root (dir #637) — where the baseline store lives. Optional here: without it the store dir is simply
# not pre-created, and the watcher's own SessionStart creates it.
if [ -s "$here/lib/state-root.sh" ] && bash -n "$here/lib/state-root.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/state-root.sh
  . "$here/lib/state-root.sh"
else
  keel_machine_watch_store() { return 1; }
fi
# hook-install (dir #437 MW8) — REQUIRED, not optional, unlike the two libs above: it computes the
# settings.json merge/removal itself, so a degrade-and-continue stub here would write a merge this
# script did not compute. Refuse outright on a missing or unparseable copy; see
# tools/lib/artifact-cksum.sh's header for the pattern.
if [ -s "$here/lib/hook-install.sh" ] && bash -n "$here/lib/hook-install.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/hook-install.sh
  . "$here/lib/hook-install.sh"
else
  echo "install-machine-watch: tools/lib/hook-install (the settings-merge lib) is missing or corrupted — this checkout is incomplete and cannot safely edit settings.json; re-clone or re-download Keel" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
install-machine-watch — wire the machine-global watcher's 4 hooks into Claude Code settings.json (Claude Code only).

Usage:
  install-machine-watch.sh <repo-path>   wire into <repo-path>/.claude/settings.json — project scope (the default):
                                         survives deletion of ~/.claude, but covers only sessions started in that repo
  install-machine-watch.sh --global      wire into ~/.claude/settings.json: covers every session and subagent, but
                                         dies with ~/.claude (a deletion of the harness home removes it too)
  install-machine-watch.sh --home DIR    --global, but into DIR/settings.json (follows install.sh --home)
  install-machine-watch.sh --print …     print the hooks JSON to merge by hand; write nothing
  install-machine-watch.sh --force …     replace a stale copy of this hook (same script, another path), with a backup
  install-machine-watch.sh --uninstall … remove exactly the hooks this installer wired (same target flags)
  install-machine-watch.sh -h | --help
The two scopes do not conflict — wire both if you like. Nothing here writes a deny rule.
EOF
}

force=0
uninstall=0
print_only=0
home_dir=""
scope_flag=""
rest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
    --print) print_only=1 ;;
    --global) [ -n "$home_dir" ] || scope_flag="--global" ;;
    --home)
      shift
      case "${1:-}" in
        "")  echo "install-machine-watch.sh: --home needs a DIR (got nothing)" >&2; exit 2 ;;
        -*)  echo "install-machine-watch.sh: --home needs a DIR, got the flag '$1'" >&2; exit 2 ;;
      esac
      home_dir="$1"; scope_flag="--home" ;;
    -h|--help) usage; exit 0 ;;
    *) if [ -n "$rest" ]; then
         echo "install-machine-watch.sh: unexpected extra argument '$1' — one repo path (or --global/--home DIR) per run" >&2
         exit 2
       fi
       rest="$1" ;;
  esac
  shift
done
set -- ${rest:+"$rest"}

if [ "$uninstall" = 1 ] && [ "$force" = 1 ]; then
  echo "install-machine-watch.sh: --uninstall and --force don't combine (--uninstall never touches a" >&2
  echo "  hook that differs from ours, with or without --force)" >&2
  exit 2
fi

if [ -n "$scope_flag" ]; then
  [ -z "${1:-}" ] || { echo "install-machine-watch.sh: $scope_flag doesn't take a repo path" >&2; exit 2; }
  settings_dir="${home_dir:-${KEEL_HOME:-${HOME:?install-machine-watch: --global needs HOME set, or pass --home DIR}/.claude}}"
  if [ -n "$home_dir" ] && [ ! -d "$home_dir" ]; then
    echo "install-machine-watch.sh: --home $home_dir does not exist (or is not a directory)." >&2
    echo "  --home names a home an install already created; it is not a place to create one. Nothing" >&2
    echo "  was changed. Check the path, or run install.sh --home \"$home_dir\" first." >&2
    exit 2
  fi
  if [ "$print_only" != 1 ]; then
    if [ "$uninstall" = 1 ]; then
      echo "install-machine-watch: $scope_flag reaches EVERY repo on this machine — removing here lifts the" >&2
      echo "  watcher everywhere it was machine-global, not just one project." >&2
    else
      echo "install-machine-watch: $scope_flag wires EVERY repo on this machine — every session and subagent" >&2
      echo "  gets a machine-global fingerprint check after each write-capable tool call (tools/machine-watch.sh's header)." >&2
    fi
  fi
  if [ "$settings_dir" != "${HOME:-}/.claude" ]; then
    echo "  NOTE Claude Code reads ${HOME:-\$HOME}/.claude/settings.json as its global scope; this run targets" >&2
    echo "  $settings_dir (matching an install.sh --home / KEEL_HOME install). If your harness isn't" >&2
    echo "  pointed at that home, wire per repo instead:  install-machine-watch.sh <repo>" >&2
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
  echo "install-machine-watch: nothing to remove — no $settings"
  exit 0
fi

print_snippet() {
  cat <<EOF
{
  "hooks": {
    "SessionStart": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "bash $mw_sh hook" }] }
    ],
    "PostToolUse": [
      { "matcher": "Bash|Write|Edit|NotebookEdit", "hooks": [{ "type": "command", "command": "bash $mw_sh hook" }] }
    ],
    "PostToolUseFailure": [
      { "matcher": "Bash|Write|Edit|NotebookEdit", "hooks": [{ "type": "command", "command": "bash $mw_sh hook" }] }
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "bash $mw_sh hook" }] }
    ]
  }
}
EOF
}

if [ "$print_only" = 1 ]; then
  print_snippet
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "install-machine-watch: jq is required to safely edit settings.json (not found on PATH)." >&2
  if [ "$uninstall" = 1 ]; then
    echo "Nothing was changed. Remove the machine-watch hook entries from $settings by hand — look for the" >&2
    echo "  \"command\" values containing '$mw' under hooks.SessionStart/PostToolUse/PostToolUseFailure/SessionEnd and" >&2
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
    echo "install-machine-watch: $settings is not valid JSON — fix or remove it by hand. Nothing was changed." >&2
    exit 2
  fi
fi

# Quoted via jq's own `@sh` (dir #514) — NOT a hand-rolled `"'\''" + $mw + "'\''"` splice: that form
# wraps $mw in single quotes but never escapes one IF $mw itself contains one, so a checkout path with
# an apostrophe produced a command with an unterminated quote ("unexpected EOF while looking for
# matching quote") and every wired hook silently broke. `@sh` produces a shell-safe single-quoted
# token, escaping any embedded `'` as `'\''`.
hook_specs="$(jq -n --arg mw "$mw" '("bash " + ($mw|@sh) + " hook") as $cmd | [
  {event: "SessionStart",        matcher: "",                              command: $cmd},
  {event: "PostToolUse",         matcher: "Bash|Write|Edit|NotebookEdit",  command: $cmd},
  {event: "PostToolUseFailure",  matcher: "Bash|Write|Edit|NotebookEdit",  command: $cmd},
  {event: "SessionEnd",          matcher: "",                              command: $cmd}
]')"

hook_install_check_shape "install-machine-watch" "$settings" "$hook_specs" "$current" || exit 2

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
    echo "install-machine-watch: nothing to remove — no wired hook at $settings matches what this installer would wire"
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
  echo "install-machine-watch: backed up settings.json → $(basename "$HOOK_INSTALL_BACKUP")"

  while IFS=$'\t' read -r status event matcher; do
    [ -n "$status" ] || continue
    print_removal_status "$status" "$event" "$matcher"
  done <<<"$statuses"

  echo "install-machine-watch: $n_removed of 4 hook(s) removed from $settings"
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
  echo "install-machine-watch: $settings already wires this hook at a different path for: $stale" >&2
  echo "  (a moved or re-cloned checkout — appending would fire it twice). Re-run with --force to back" >&2
  echo "  up settings.json and point it at this checkout; your other hooks stay. Nothing was changed." >&2
  exit 3
fi

if [ "$n_stale" -gt 0 ] && [ -f "$settings" ]; then
  hook_install_backup "$settings"
  echo "install-machine-watch: backed up your existing settings.json → $(basename "$HOOK_INSTALL_BACKUP") (--force)"
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

echo "install-machine-watch: wired into $settings"

# MW7: the store dir is created at install time, so the watcher can read its later ABSENCE as a removal
# (a fresh install never produces that state). Failure to create it is a warning, not an install failure:
# the watcher's SessionStart creates it itself.
mw_store="$(keel_machine_watch_store)" || mw_store=""
if [ -n "$mw_store" ]; then
  mkdir -p "$mw_store" 2>/dev/null || echo "install-machine-watch: could not create the baseline store $mw_store (the watcher will create it at the next SessionStart)" >&2
fi
echo "Hooks in settings files are normally picked up live; restart Claude Code if the watcher does not fire."
