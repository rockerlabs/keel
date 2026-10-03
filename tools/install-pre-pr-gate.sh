#!/usr/bin/env bash
# install-pre-pr-gate — wire the /polish pre-PR gate into a project's Claude Code hooks (opt-in, per repo).
#
#   install-pre-pr-gate.sh <repo-path>       wire 6 hooks into <repo-path>/.claude/settings.json (project
#                                            scope — the default; only sessions IN this repo are gated)
#   install-pre-pr-gate.sh --global          wire into ~/.claude/settings.json instead — EVERY repo you
#                                            open on this machine gets the gate, not just this one
#   install-pre-pr-gate.sh --home DIR        --global, but into DIR/settings.json — the flag that lets
#                                            this follow an  install.sh --home DIR  install (dir #98)
#   install-pre-pr-gate.sh --force …         replace a STALE copy of this same hook (same script, another
#                                            path — a moved checkout); backs up settings.json first
#                                            (default: refuse that one case; a different hook on the same
#                                            event+matcher needs no --force — it is appended beside)
#   install-pre-pr-gate.sh --uninstall …     the reverse: remove exactly the 6 hooks this installer
#                                            wired (byte-identical match only — a hook you or something
#                                            else has since changed is left in place, named as kept)
#
# --home exists because `install.sh --home DIR` retargets the whole install WITHOUT exporting KEEL_HOME:
# without it, the commands lived in DIR while this installer's --global wrote hooks to ~/.claude — two
# installers internally consistent but describing different machines, with nothing said at either
# install. They now take the same flag, and install.sh's own summary names it. The caveat --home can't
# engineer away is stated at the point of install: which global settings.json the HARNESS reads is the
# harness's decision (Claude Code reads $HOME/.claude), so a retargeted home is only really global if
# your harness is pointed there too.
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
# tell an answered dialog from a silently-skipped one on an `agent:*`-shaped review outcome. The same
# hook also traces step 4's mandatory skip dialog (its own `KEEL-DEPTH-DIALOG` skip marker,
# dir #116), which a `skip` unlock is checked against. See
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
# Never clobbers your data silently: an existing hook already wired to the SAME event+matcher running a
# DIFFERENT command is left exactly as it is and ours is APPENDED beside it, in a sibling entry with
# that matcher (dir #468). The one refusal left is a STALE copy of this very hook — same script,
# another path, e.g. a moved checkout — because appending would fire it twice; --force backs up
# settings.json (a timestamped sibling) first, then swaps just that one command for ours, leaving
# every other command in its entry. Everything else already in settings.json
# (other hooks, other keys) is left exactly as it was. A hook that's already exactly ours is left alone
# (idempotent — safe to re-run after every `git pull`).
#
# --uninstall (dir #136) mirrors that same discipline in reverse: on each event+matcher it removes only
# OUR hook — the {type, command} pair byte-identical to what this installer would wire right now —
# wherever it sits (a sibling entry, or inside an entry that also holds someone else's command); a hook
# you later pointed somewhere else, and every other command, is left in place — a slot holding commands
# but none of ours is reported kept — never silently taken out along with the rest. Backs up
# settings.json first, same as --force does. This is what uninstall.sh's own closing summary now points
# adopters at when it finds leftover gate hooks — a whole-home uninstall never removes them itself (it
# doesn't know whether other repos still need tools/pre-pr-gate.sh to exist).
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
gate="$repo_root/tools/pre-pr-gate.sh"

# A temp bootstrap clone (bootstrap.sh's `${TMPDIR:-/tmp}/keel.XXXXXX/keel`, reaped on exit) is not a
# checkout to point hooks at — they'd dangle within moments. This script is never invoked BY bootstrap
# (it's a separate, deliberate, opt-in step), so there's no env signal to read the way install.sh reads
# KEEL_EPHEMERAL — the path shape is what's left to go on. Strip a trailing slash from TMPDIR first
# (macOS sets it WITH one, e.g. "/var/folders/.../T/") — pwd never emits a double slash, so an
# unstripped pattern would silently never match on that platform. Checked BEFORE sourcing tools/lib/
# below: a bootstrap clone's own copy of this script is a bare, minimal fixture (found live by this
# ticket's own regression test) — it never carries tools/lib/ at all, so a source attempted first would
# fail on a missing file and mask this check's own, more useful "temp clone" rejection behind a raw
# "no such file" exit.
tmpdir_base="${TMPDIR:-/tmp}"; tmpdir_base="${tmpdir_base%/}"
case "$repo_root" in
  "$tmpdir_base"/keel.*/keel)
    echo "install-pre-pr-gate: this looks like a temporary bootstrap clone (about to be deleted), not a" >&2
    echo "  kept checkout — the hooks would point at a path that stops existing. Clone Keel somewhere" >&2
    echo "  permanent (e.g. ~/keel) and re-run tools/install-pre-pr-gate.sh from there." >&2
    exit 2
    ;;
esac

# shellcheck source=tools/lib/sh-quote.sh
. "$here/lib/sh-quote.sh"
# shellcheck source=tools/lib/gate-paths.sh
. "$here/lib/gate-paths.sh"
# shellcheck source=tools/lib/repo-arg-guard.sh
. "$here/lib/repo-arg-guard.sh"
# gate_sh — $gate quoted (dir #514), already wrapped in single quotes AND JSON-escaped, for the ONE
# place $gate is spliced into a shell command string INSIDE a hand-written JSON heredoc, by hand,
# rather than through jq's `@sh` (print_snippet below, the no-jq fallback — a heredoc can't call a jq
# filter, so it needs sh_quote_json's second JSON-escaping pass too, not just sh_quote's shell one).
# Same escaping jq's `@sh` performs (JSON-aware, so it needs no separate JSON-escaping step of its
# own), shared with install-read-trace.sh's identical need via tools/lib/sh-quote.sh rather than a
# second hand-copy.
gate_sh="$(sh_quote_json "$gate")"
# hook-install (dir #437 MW8) — REQUIRED, not optional, unlike the libs above: it computes the
# settings.json merge/removal itself, so a degrade-and-continue stub here would write a merge this
# script did not compute. Refuse outright on a missing or unparseable copy; see
# tools/lib/artifact-cksum.sh's header for the pattern.
if [ -s "$here/lib/hook-install.sh" ] && bash -n "$here/lib/hook-install.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/hook-install.sh
  . "$here/lib/hook-install.sh"
else
  echo "install-pre-pr-gate: tools/lib/hook-install (the settings-merge lib) is missing or corrupted — this checkout is incomplete and cannot safely edit settings.json; re-clone or re-download Keel" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
install-pre-pr-gate — wire the /polish pre-PR gate's 6 hooks into Claude Code settings.json.

Usage:
  install-pre-pr-gate.sh <repo-path>     wire into <repo-path>/.claude/settings.json (project scope)
  install-pre-pr-gate.sh --global        wire into ~/.claude/settings.json (every repo on this machine)
  install-pre-pr-gate.sh --home DIR      --global, but into DIR/settings.json (follows install.sh --home)
  install-pre-pr-gate.sh --force …       replace a stale copy of this hook (same script, another path), with a backup
  install-pre-pr-gate.sh --uninstall …   remove exactly the hooks this installer wired (same target flags)
  install-pre-pr-gate.sh -h | --help
EOF
}

force=0
uninstall=0
home_dir=""
scope_flag=""   # empty = project scope (a repo path); set = machine-global, and names the flag that asked
rest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
    # --home is --global with an explicit target, so it stays the flag every message names when both
    # are passed — it's the one that actually decides where the hooks land.
    --global) [ -n "$home_dir" ] || scope_flag="--global" ;;
    --home)
      shift
      # An EMPTY DIR is rejected as loudly as a missing one: `--home "$KEEL_HOME"` in a shell where
      # KEEL_HOME was never exported is exactly the situation dir #98 describes (install.sh --home
      # does not export it), and falling through to $HOME/.claude there would silently re-create the
      # split install this flag exists to close — including skipping the NOTE below, since the
      # resolved dir would then equal the default. A leading dash is a swallowed flag, not a path.
      case "${1:-}" in
        "")  echo "install-pre-pr-gate.sh: --home needs a DIR (got nothing)" >&2; exit 2 ;;
        -*)  echo "install-pre-pr-gate.sh: --home needs a DIR, got the flag '$1'" >&2; exit 2 ;;
      esac
      home_dir="$1"; scope_flag="--home" ;;
    -h|--help) usage; exit 0 ;;
    *) if [ -n "$rest" ]; then
         echo "install-pre-pr-gate.sh: unexpected extra argument '$1' — one repo path (or --global/--home DIR) per run" >&2
         exit 2
       fi
       rest="$1" ;;
  esac
  shift
done
set -- ${rest:+"$rest"}

# --force's whole meaning (swap a stale copy of this hook) doesn't exist on the removal path — --uninstall
# already never touches a hook that differs from ours, unconditionally. Reject the combination instead
# of silently ignoring one flag.
if [ "$uninstall" = 1 ] && [ "$force" = 1 ]; then
  echo "install-pre-pr-gate.sh: --uninstall and --force don't combine (--uninstall never touches a" >&2
  echo "  hook that differs from ours, with or without --force)" >&2
  exit 2
fi

if [ -n "$scope_flag" ]; then
  [ -z "${1:-}" ] || { echo "install-pre-pr-gate.sh: $scope_flag doesn't take a repo path" >&2; exit 2; }
  # Precedence, in one expression: --home DIR > $KEEL_HOME > $HOME/.claude. The ${HOME:?} is evaluated
  # only if both earlier candidates are empty, so --home still works with HOME unset.
  settings_dir="${home_dir:-${KEEL_HOME:-${HOME:?install-pre-pr-gate: --global needs HOME set, or pass --home DIR}/.claude}}"
  # An explicitly-typed --home DIR must EXIST. The flag's whole purpose is to follow an
  # `install.sh --home DIR` install, so the dir is there by construction — while `mkdir -p` below would
  # happily accept a typo, write a complete settings.json into a brand-new directory nothing reads,
  # print "wired into …" and exit 0. The adopter then believes the gate is on and it is nowhere
  # (`--home ~/.keel-hom` reproduced exactly that). The project-scope arm below validates its target
  # with `git rev-parse` for the same reason. Deliberately NOT applied to the $KEEL_HOME/$HOME fallback:
  # that path is a documented default this ticket didn't open, and creating it is its existing contract.
  if [ -n "$home_dir" ] && [ ! -d "$home_dir" ]; then
    echo "install-pre-pr-gate.sh: --home $home_dir does not exist (or is not a directory)." >&2
    echo "  --home names a home an install already created; it is not a place to create one. Nothing" >&2
    echo "  was changed. Check the path, or run install.sh --home \"$home_dir\" first." >&2
    exit 2
  fi
  if [ "$uninstall" = 1 ]; then
    echo "install-pre-pr-gate: $scope_flag reaches EVERY repo on this machine — removing here lifts the" >&2
    echo "  gate everywhere it was machine-global, not just one project." >&2
  else
    echo "install-pre-pr-gate: $scope_flag wires EVERY repo on this machine — the agent's gh pr create is" >&2
    echo "  hard-denied without a matching /polish receipt in every project you open here, not just this one." >&2
  fi
  # dir #98's residual, which no flag can close: where the harness looks for its global settings is the
  # harness's decision, not this installer's. Stated, not engineered away.
  if [ "$settings_dir" != "${HOME:-}/.claude" ]; then
    echo "  NOTE Claude Code reads ${HOME:-\$HOME}/.claude/settings.json as its global scope; this run targets" >&2
    echo "  $settings_dir (matching an install.sh --home / KEEL_HOME install). If your harness isn't" >&2
    echo "  pointed at that home, wire per repo instead:  install-pre-pr-gate.sh <repo>" >&2
  fi
  settings="$settings_dir/settings.json"
elif [ -n "${1:-}" ]; then
  repo="$1"
  keel_repo_arg_guard "$repo"
  # dir #182: the project-scope write target is now the same shared `gate_project_settings_path`
  # (tools/lib/gate-paths.sh) that the armer's `_dialog_leg_armed` and doctor.sh's `proj_settings`
  # also derive from — $settings_dir (used below for mkdir -p / cd) is its containing directory, not
  # an independent literal.
  settings="$(gate_project_settings_path "$repo")"
  settings_dir="${settings%/*}"
else
  usage >&2
  exit 2
fi

# Nothing was ever wired here — say so and stop before creating anything. Checked before the jq
# requirement below too: an adopter uninstalling on a machine with no jq and no gate ever wired
# shouldn't be told jq is required for a removal that has nothing to do.
if [ "$uninstall" = 1 ] && [ ! -f "$settings" ]; then
  echo "install-pre-pr-gate: nothing to remove — no $settings"
  exit 0
fi

# print_snippet — the raw hooks JSON, ready to paste into settings.json's "hooks" key by hand. Must work
# WITHOUT jq (it's the fallback for exactly that case), so it's a plain heredoc, not jq -n.
print_snippet() {
  cat <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash $gate_sh" }] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "bash $gate_sh rollout-check" }] }
    ],
    "PostToolUse": [
      { "matcher": "Skill", "hooks": [{ "type": "command", "command": "bash $gate_sh skill-trace" }] },
      { "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "bash $gate_sh skill-trace" }] }
    ],
    "UserPromptExpansion": [
      { "matcher": "code-review", "hooks": [{ "type": "command", "command": "bash $gate_sh skill-trace" }] }
    ],
    "SubagentStop": [
      { "matcher": "general-purpose", "hooks": [{ "type": "command", "command": "bash $gate_sh skill-trace" }] }
    ]
  }
}
EOF
}

if ! command -v jq >/dev/null 2>&1; then
  echo "install-pre-pr-gate: jq is required to safely edit settings.json (not found on PATH)." >&2
  if [ "$uninstall" = 1 ]; then
    echo "Nothing was changed. Remove the gate's hook entries from $settings by hand — look for the" >&2
    echo "  \"command\" values containing '$gate' under hooks.PreToolUse/SessionStart/PostToolUse/" >&2
    echo "  UserPromptExpansion/SubagentStop and delete just those matcher entries." >&2
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
    echo "install-pre-pr-gate: $settings is not valid JSON — fix or remove it by hand. Nothing was changed." >&2
    exit 2
  fi
fi

# The 6 hooks — shapes documented in tools/pre-pr-gate.sh's own header (reconcile there on drift).
# $gate is single-quoted WITHIN the command string itself (not just JSON-escaped, which jq already does
# for the string as a whole) — a checkout path containing a space would otherwise split into two argv
# tokens when Claude Code's hook runner passes this string to a shell, silently no-op'ing every hook.
# Quoted via jq's own `@sh` (dir #514) — NOT a hand-rolled `"'\''" + $gate + "'\''"` splice: that form
# wraps $gate in single quotes but never escapes one IF $gate itself contains one, so a checkout path
# with an apostrophe (an adopter's real home directory, not just a hypothetical) produced a command
# with an unterminated quote ("unexpected EOF while looking for matching quote") and every wired hook
# silently broke. `@sh` produces a shell-safe single-quoted token, escaping any embedded `'` as `'\''`.
hook_specs="$(jq -n --arg gate "$gate" '[
  {event: "PreToolUse",         matcher: "Bash",           command: ("bash " + ($gate|@sh))},
  {event: "SessionStart",       matcher: "startup",        command: ("bash " + ($gate|@sh) + " rollout-check")},
  {event: "PostToolUse",        matcher: "Skill",          command: ("bash " + ($gate|@sh) + " skill-trace")},
  {event: "UserPromptExpansion", matcher: "code-review",   command: ("bash " + ($gate|@sh) + " skill-trace")},
  {event: "SubagentStop",       matcher: "general-purpose", command: ("bash " + ($gate|@sh) + " skill-trace")},
  {event: "PostToolUse",        matcher: "AskUserQuestion", command: ("bash " + ($gate|@sh) + " skill-trace")}
]')"

# Backup/atomic-write/shape-check/merge/remove all live in tools/lib/hook-install.sh (dir #437 MW8),
# shared with install-read-trace.sh — reconcile there, not here, on drift.
# Valid JSON is not the same as the expected SHAPE (a hand-edited ".hooks" as an array): the lib's
# check refuses with a clean message instead of a raw jq type error.
hook_install_check_shape "install-pre-pr-gate" "$settings" "$hook_specs" "$current" || exit 2

# --uninstall: the mirror image of the merge below (hook_install_remove / hook_install_merge, same
# one-pass-tagged-report shape — REMOVED/KEPT instead of MISSING/SAME/APPENDED/STALE). Only OUR exact
# {type, command} hook comes out, from any entry on that event+matcher (dir #468: after an append, ours
# sits in a sibling entry; after a forced STALE swap, inside an entry that also holds someone else's
# command); an entry it leaves empty goes with it, and everything else on that slot stays.
if [ "$uninstall" = 1 ]; then
  removal="$(hook_install_remove "$hook_specs" "$current")"
  statuses="$(jq -r '.report' <<<"$removal")"

  # One definition of each status's print line, reused by both the early "nothing removed" exit (KEPT
  # only) and the normal completion path (REMOVED + KEPT) below — previously duplicated between them.
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
    echo "install-pre-pr-gate: nothing to remove — no wired hook at $settings matches what this installer would wire"
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
  echo "install-pre-pr-gate: backed up settings.json → $(basename "$HOOK_INSTALL_BACKUP")"

  while IFS=$'\t' read -r status event matcher; do
    [ -n "$status" ] || continue
    print_removal_status "$status" "$event" "$matcher"
  done <<<"$statuses"

  echo "install-pre-pr-gate: $n_removed of 6 hook(s) removed from $settings"

  # Gate manifest (dir #125) — global/home scope only (project scope writes none). Removed when
  # hooks were actually removed; the checkout-side ledger entry is pruned when no install-manifest.*
  # remains at this home (install.sh's own claude/codex manifests may still be there).
  if [ -n "$scope_flag" ]; then
    gate_home_resolved="$(cd "$settings_dir" && pwd)"
    gate_manifest_file="$gate_home_resolved/.keel/install-manifest.gate"
    if [ -f "$gate_manifest_file" ]; then
      rm -f "$gate_manifest_file"
      echo "install-pre-pr-gate: gate manifest removed ($gate_manifest_file)"
    fi
    manifests_left=0
    for m in "$gate_home_resolved"/.keel/install-manifest.*; do
      [ -e "$m" ] && manifests_left=1
    done
    if [ "$manifests_left" = 0 ]; then
      # shellcheck source=tools/lib/ledger.sh
      . "$here/lib/ledger.sh"
      ledger_remove "${KEEL_LEDGER_FILE:-$repo_root/.keel/installed-homes}" "$gate_home_resolved"
    fi
  fi

  exit 0
fi

# One pass (hook_install_merge) computes BOTH the merged settings AND each hook's classification —
# MISSING (not wired), SAME (already exactly ours — idempotent), APPENDED (that event+matcher already
# runs someone else's hook: ours lands in a sibling entry, theirs untouched), or STALE (this same hook at
# another path — the one case that needs --force). The as-if-forced result is computed even on a STALE
# and is never written unless the refuse/--force gate below clears it.
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
  echo "install-pre-pr-gate: $settings already wires this hook at a different path for: $stale" >&2
  echo "  (a moved or re-cloned checkout — appending would fire it twice). Re-run with --force to back" >&2
  echo "  up settings.json and point it at this checkout; your other hooks stay. Nothing was changed." >&2
  exit 3
fi

if [ "$n_stale" -gt 0 ] && [ -f "$settings" ]; then
  hook_install_backup "$settings"
  echo "install-pre-pr-gate: backed up your existing settings.json → $(basename "$HOOK_INSTALL_BACKUP") (--force)"
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

echo "install-pre-pr-gate: wired into $settings"

# Gate manifest (dir #125) — global/home scope only; project scope writes no manifest, no ledger
# entry (a repo's own hooks are already discoverable via its .claude/settings.json). Written on
# every successful wire, including the all-SAME idempotent path (state, not action).
if [ -n "$scope_flag" ]; then
  gate_home_resolved="$(cd "$settings_dir" && pwd)"
  gate_manifest_dir="$gate_home_resolved/.keel"
  gate_manifest_file="$gate_manifest_dir/install-manifest.gate"
  mkdir -p "$gate_manifest_dir"
  wired_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gate_manifest_content="keel_manifest_version=1
kind=gate
settings=$settings
gate=$gate
wired_at=$wired_at"
  hook_install_atomic_write "$gate_manifest_file" "$gate_manifest_content"
  echo "install-pre-pr-gate: gate manifest ($gate_manifest_file)"

  # Checkout-side ledger — the same discovery index install.sh writes to (tools/lib/ledger.sh),
  # respecting the same KEEL_LEDGER_FILE test-isolation override install.sh does. Non-fatal: the hook
  # wiring above already fully succeeded, so a read-only checkout must not abort the run (found by an
  # independent /code-review high pass on install.sh's own equivalent site).
  # shellcheck source=tools/lib/ledger.sh
  . "$here/lib/ledger.sh"
  ledger_append "${KEEL_LEDGER_FILE:-$repo_root/.keel/installed-homes}" "$gate_home_resolved" \
    || echo "install-pre-pr-gate: ledger write failed (non-fatal) — $repo_root/.keel not writable?" >&2
fi

echo "Restart Claude Code (hooks load only at session start) — then /polish unlocks gh pr create for real."
# Same rule as install.sh's home_flag and doctor's ihome_flag: a bare `doctor.sh --install` audits
# ${KEEL_HOME:-$HOME/.claude}, so on a retargeted home it would report on a different install than the
# one just wired (dir #98, found to be a class rather than a site).
doctor_arg=""
if [ -n "$scope_flag" ] && [ "$settings_dir" != "${KEEL_HOME:-${HOME:-}/.claude}" ]; then
  doctor_arg=" \"$settings_dir\""
fi
echo "Health check any time: tools/doctor.sh --install$doctor_arg"
