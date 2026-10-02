#!/usr/bin/env bash
# tools/machine-watch.sh — a detector for the sandbox rail (dir #437): fingerprint a defined set of
# machine-global paths, and report what changed. Adopter-usable: any harness can run the CLI by hand;
# the opt-in installer (tools/install-machine-watch.sh) wires it into Claude Code as a hook.
#
# The problem: docs/delegation.md's rail says a live check never touches the real $HOME, but nothing
# enforces that for a real session's OWN commands. In the felt incident a denied command was retyped
# shorter, lost its HOME= prefix, and rewrote the machine's real git identity. A rule that a denial can
# silently delete is not a rail — so this watches the machine itself, and tells the session that acted
# while it still knows what it ran. It DETECTS; it never prevents, never blocks, never fails a tool call.
#
# Usage:
#   machine-watch.sh hook                  Claude Code hook mode: one JSON payload on stdin. SessionStart
#                                           records (or, on a resume, checks) this session's baseline;
#                                           PostToolUse / PostToolUseFailure check it; SessionEnd removes
#                                           it. Always exits 0.
#   machine-watch.sh paths                 print the resolved watched set, one `<tier> <kind> <path>` a line
#   machine-watch.sh snapshot NAME         record a baseline under NAME
#   machine-watch.sh check NAME            print what changed since the baseline (plain text) and replace
#                                           it. Exit 0 = unchanged, 1 = changed, 2 = error or no baseline
#   machine-watch.sh forget NAME           delete NAME's baseline
# Without hooks (any other harness): `snapshot x` before a live check, `check x` after it.
#
# The watched set (MW1), resolved in the CALLER's environment — for the hook that is the harness's, on
# purpose: a command's own sandbox variables must not hide the real machine from its watcher. `<H>` is
# the harness home, ${KEEL_HOME:-$HOME/.claude}.
#   ALERT (a change raises an operator banner AND tells the model)
#     the git global config files (git var GIT_CONFIG_GLOBAL), the git system config, every file directly
#     inside the effective machine-wide core.hooksPath dir, ~/.ssh/config, the shell rc files
#   QUIET (a change tells only the model, and names the expected writer)
#     <H>/settings.json, <H>/CLAUDE.md, ~/.ssh/known_hosts, the XDG config tree (~/.config)
#   deletion of ANY watched path, and of <H> or <H>/.keel, is ALWAYS alert
#   plus your own paths, one `alert|quiet <absolute path>` per line, in $HOME/.keel/machine-watch.paths
# Excluded on purpose: the shared /tmp (dir #398), the real repo's refs (dir #333), the contents of
# <H>/.keel, other directories under <H> (the harness writes there constantly).
#
# Fingerprints (MW2): a file is `absent` or `file <octal mode> <cksum>`; a tree is one ctime scan
# (find -cnewer), never per-file hashes; file CONTENT is never stored and never printed. The baseline
# store is $HOME/.keel/machine-watch (dir #637's state root), or $KEEL_MACHINE_WATCH_STORE.
#
# What it cannot do: it cannot tell WHO made a change (another session, the operator, a background
# process) — every report says so, and tells the model not to "restore" anything it cannot prove it did.
# A coarse-timestamp find (busybox: whole seconds) can miss a tree change made in the very second the
# baseline was written; a mode-only change inside a tree is seen only where find supports -cnewer.
set -o pipefail
# dir #647: drop an inherited repo selector before any git call — the watched set is MACHINE-wide, and an inherited
# GIT_DIR would make `git -C <scratch> config core.hooksPath` read that repo's local scope instead.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The fixed paragraph, verbatim (MW4) — on ONE line so a pin can match it.
MW_FIXED='This watcher cannot tell who made the change — another session, the operator, or a background process may have. Tell the operator what changed. Do not restore or revert it yourself unless you can show that your own last command made this exact change.'

# Required libs, each behind a `[ -s ] && bash -n` pre-check (tools/lib/artifact-cksum.sh's pattern): a
# degrade-and-continue stub here would fingerprint everything as the unreadable sentinel and report
# nothing ever, silently. A missing lib is reported, not sourced.
MW_LIBS_ERR=""
for _mw_lib in state-root git-global-paths stat-portable artifact-cksum; do
  if [ -s "$here/lib/$_mw_lib.sh" ] && bash -n "$here/lib/$_mw_lib.sh" 2>/dev/null; then
    # shellcheck source=/dev/null
    . "$here/lib/$_mw_lib.sh"
  else
    MW_LIBS_ERR="tools/lib/$_mw_lib.sh is missing or corrupted — this checkout is incomplete"
    break
  fi
done
unset _mw_lib

MW_TAB=$'\t'
MW_ERR=""
# Per-run temp files live in the store (same filesystem, so the final mv is atomic) and are removed on exit.
MW_TMP=""
trap '[ -z "$MW_TMP" ] || rm -f "$MW_TMP".* 2>/dev/null' EXIT

# --- naming and the store ---------------------------------------------------------------------------

# mw_sanitize NAME — NAME if it is only [A-Za-z0-9._-] and non-empty; otherwise prints nothing, rc 1.
mw_sanitize() {
  case "$1" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s' "$1"
}

# mw_store — resolve the store directory ONCE per run into $MW_STORE; sets MW_ERR and returns 1 when none can
# be named. (A global, not a printed value: a `$(…)` capture would redo the resolution in a subshell per call.)
MW_STORE=""
mw_store() {
  [ -z "$MW_STORE" ] || return 0
  MW_STORE="$(keel_machine_watch_store)" || { MW_STORE=""; MW_ERR="no \$HOME, so no baseline store can be named"; return 1; }
}

# mw_harness_home — <H>; prints nothing and returns 1 without a HOME or KEEL_HOME.
mw_harness_home() {
  if [ -n "${KEEL_HOME:-}" ]; then printf '%s' "$KEEL_HOME"; return 0; fi
  [ -n "${HOME:-}" ] || return 1
  printf '%s/.claude' "$HOME"
}

# --- the watched set (MW1) ---------------------------------------------------------------------------

# mw_resolve — print the watched set, one `<id><TAB><tier><TAB><kind><TAB><path>` a line, deduplicated by
# path (first wins). Ids a-k are MW1's table rows; they select the expected-writer text of a quiet line.
mw_resolve() {
  local h line d f xdg tier rest p
  h="$(mw_harness_home)" || return 0
  xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  {
    while IFS= read -r line; do [ -n "$line" ] && printf 'a\talert\tfile\t%s\n' "$line"; done < <(git_global_config_files)
    while IFS= read -r line; do [ -n "$line" ] && printf 'b\talert\tfile\t%s\n' "$line"; done < <(git_global_system_config_file)
    d="$(git_global_hooks_dir)"
    if [ -n "$d" ] && [ -d "$d" ]; then
      for f in "$d"/* "$d"/.[!.]* "$d"/..?*; do
        [ -f "$f" ] && printf 'c\talert\tfile\t%s\n' "$f"
      done
    fi
    printf 'd\talert\tfile\t%s\n' "$HOME/.ssh/config"
    for f in .zshrc .zshenv .zprofile .bashrc .bash_profile .profile; do
      printf 'e\talert\tfile\t%s\n' "$HOME/$f"
    done
    printf 'f\tquiet\tfile\t%s\n' "$h/settings.json"
    printf 'g\tquiet\tfile\t%s\n' "$h/CLAUDE.md"
    printf 'h\tquiet\tfile\t%s\n' "$HOME/.ssh/known_hosts"
    printf 'i\tquiet\ttree\t%s\n' "$xdg"
    printf 'j\talert\texist\t%s\n' "$h"
    printf 'j\talert\texist\t%s\n' "$h/.keel"
    p="$(keel_state_root)/machine-watch.paths"
    if [ -f "$p" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ""|"#"*) continue ;; esac
        tier="${line%% *}"; rest="${line#* }"
        case "$tier" in alert|quiet) ;; *) continue ;; esac
        rest="$(git_global_expand_tilde "$rest")"
        case "$rest" in /*) ;; *) continue ;; esac
        if [ -d "$rest" ]; then printf 'k\t%s\ttree\t%s\n' "$tier" "$rest"; else printf 'k\t%s\tfile\t%s\n' "$tier" "$rest"; fi
      done < "$p"
    fi
  } | awk -F'\t' '!seen[$4]++'
}

# mw_writer ID — the expected writer a quiet line names.
mw_writer() {
  case "$1" in
    f) printf '%s' 'Claude Code (a permission grant, `/config`) or a hook installer' ;;
    g) printf '%s' "your own tooling that regenerates the always-on file (e.g. keel's \`install.sh\`)" ;;
    h) printf '%s' 'ssh, on a first connection to a new host' ;;
    i) printf '%s' 'applications store their settings here' ;;
    k) printf '%s' 'listed by you in machine-watch.paths' ;;
    *) printf '%s' 'an unknown writer' ;;
  esac
}

# --- fingerprints (MW2) ------------------------------------------------------------------------------

# mw_state KIND PATH — one state string: file: `absent` | `file <mode> <cksum>` | `other`;
# exist: `absent` | `dir`; tree: `absent` | `tree`. Content is hashed, never kept.
mw_state() {
  local kind="$1" p="$2"
  case "$kind" in
    file)
      if [ -f "$p" ]; then
        printf 'file %s %s' "$(stat_portable_mode "$p")" "$(artifact_cksum "$p")"
      elif [ -e "$p" ] || [ -L "$p" ]; then printf 'other'
      else printf 'absent'; fi ;;
    exist|tree)
      if [ -d "$p" ]; then
        if [ "$kind" = tree ]; then printf 'tree'; else printf 'dir'; fi
      else printf 'absent'; fi ;;
  esac
}

# mw_fingerprint — read `<id><TAB><tier><TAB><kind><TAB><path>` lines on stdin, print each with its state
# appended as a fifth field.
mw_fingerprint() {
  local id tier kind p
  _stat_portable_ensure_flavor   # once here: inside each `$(…)` it would re-probe, and the cache would be lost
  while IFS="$MW_TAB" read -r id tier kind p; do
    [ -n "$p" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$tier" "$kind" "$p" "$(mw_state "$kind" "$p")"
  done
}

# mw_find_newer_flag — `-cnewer` where find has it, else `-newer` (mtime: a mode-only change inside a tree
# is then missed — busybox's find has no -cnewer). Probed once per run.
MW_NEWER=""
mw_find_newer_flag() {
  [ -n "$MW_NEWER" ] && return 0
  MW_NEWER=-cnewer
  find "$here" -maxdepth 0 -cnewer "$here" >/dev/null 2>&1 || MW_NEWER=-newer
}

# --- the check (MW2-MW4) -----------------------------------------------------------------------------

ALERT_L=""   # newline-separated report lines, alert tier
QUIET_L=""   # …quiet tier
mw_add() {   # TIER LINE
  if [ "$1" = alert ]; then ALERT_L="${ALERT_L}${ALERT_L:+
}$2"; else QUIET_L="${QUIET_L}${QUIET_L:+
}$2"; fi
}
# mw_line TIER ID PATH WORD — one report line; a quiet line names its expected writer.
mw_line() {
  if [ "$1" = alert ]; then mw_add alert "$3: $4"
  else mw_add quiet "$3: $4 (quiet — expected writer: $(mw_writer "$2"))"; fi
}

# mw_diff_file TIER ID PATH OLD NEW — classify one file's change.
mw_diff_file() {
  local tier="$1" id="$2" p="$3" old="$4" new="$5" _o om oc nm nc
  # Only called for a path whose state DIFFERS from its baseline (the diff pass above filters).
  case "$old/$new" in
    absent/*) mw_line "$tier" "$id" "$p" created; return 0 ;;
    */absent) mw_line alert "$id" "$p" deleted; return 0 ;;
    other/*|*/other) mw_line "$tier" "$id" "$p" changed; return 0 ;;
  esac
  read -r _o om oc <<<"$old"
  read -r _o nm nc <<<"$new"
  # Braces, not `$om→$nm`: under a single-byte (Latin-1) locale bash reads the arrow's bytes as part of the
  # variable name and both expansions come out empty (CI's macos-14 leg).
  if [ "$om" != "$nm" ]; then mw_line "$tier" "$id" "$p" "mode ${om}→${nm}"; fi
  if [ "$oc" != "$nc" ]; then mw_line "$tier" "$id" "$p" "content changed"; fi
}

# mw_scan_tree TIER ID ROOT STAMP — the ctime scan of one tree: find -cnewer STAMP, never per-file hashes.
# A non-directory hit is `changed`; a directory hit is `entries changed` (covers a deletion inside) — except
# a directory whose only news is a .DS_Store created in it (creating ANY entry bumps the parent's ctime, so
# without this the excluded file would still be reported through its parent). A hit that is itself a watched
# FILE (SETFILE: the resolved set) is filtered out of find's output in ONE awk pass (a fork per hit would cost
# thousands on a bulk change) — its own row already reports it, under its own tier. Capped at 20 lines.
mw_scan_tree() {
  local tier="$1" id="$2" root="$3" stamp="$4" setfile="$5" hit n=0 more=0
  [ -f "$stamp" ] || return 0
  mw_find_newer_flag
  while IFS= read -r hit; do
    if [ -d "$hit" ] && [ ! -L "$hit" ]; then
      if [ -n "$(find "$hit/.DS_Store" -maxdepth 0 "$MW_NEWER" "$stamp" 2>/dev/null)" ]; then continue; fi
      if [ "$n" -lt 20 ]; then n=$((n + 1)); mw_line "$tier" "$id" "$hit" "entries changed"; else more=$((more + 1)); fi
    else
      if [ "$n" -lt 20 ]; then n=$((n + 1)); mw_line "$tier" "$id" "$hit" "changed"; else more=$((more + 1)); fi
    fi
  done < <(find "$root" "$MW_NEWER" "$stamp" ! -name .DS_Store 2>/dev/null | awk -v sf="$setfile" '
    BEGIN { FS = "\t"; while ((getline l < sf) > 0) { split(l, a, "\t"); if (a[3] == "file") skip[a[4]] = 1 } }
    !($0 in skip)')
  if [ "$more" -gt 0 ]; then mw_line "$tier" "$id" "$root" "…and $more more entries changed"; fi
}

# mw_snap_write NAME — write the baseline and stamp. Stamp first: a change made while the fingerprint is
# being taken is then re-reported next time, never missed.
mw_snap_write() {
  local name="$1" store snap stamp
  mw_store || return 1
  store="$MW_STORE"
  mkdir -p "$store" 2>/dev/null || { MW_ERR="cannot create $store"; return 1; }
  snap="$store/$name.snap"; stamp="$store/$name.stamp"
  MW_TMP="$store/.tmp.$$"
  touch "$MW_TMP.stamp" 2>/dev/null || { MW_ERR="cannot write to $store"; return 1; }
  mw_resolve | mw_fingerprint > "$MW_TMP.snap" 2>/dev/null || { MW_ERR="cannot write to $store"; return 1; }
  mv -f "$MW_TMP.stamp" "$stamp" && mv -f "$MW_TMP.snap" "$snap" || { MW_ERR="cannot write to $store"; return 1; }
}

# mw_check NAME — compare against NAME's baseline into ALERT_L/QUIET_L and replace the baseline and stamp
# (each change is reported once per session). rc 0 = unchanged, 1 = changed, 2 = error / no baseline.
mw_check() {
  local name="$1" store snap stamp diff id tier kind p old new
  mw_store || return 2
  store="$MW_STORE"
  snap="$store/$name.snap"; stamp="$store/$name.stamp"
  [ -f "$snap" ] || { MW_ERR="no baseline named $name"; return 2; }
  ALERT_L=""; QUIET_L=""
  MW_TMP="$store/.tmp.$$"
  touch "$MW_TMP.stamp" 2>/dev/null || { MW_ERR="cannot write to $store"; return 2; }
  # Fresh set, plus every path the baseline knew that the fresh set no longer names (a deleted hooks-dir
  # file, a repointed config): those are fingerprinted directly, so a vanished file reads `deleted`, not
  # as silence.
  mw_resolve > "$MW_TMP.res"
  cp "$MW_TMP.res" "$MW_TMP.set"
  awk -F'\t' -v rf="$MW_TMP.res" 'FILENAME==rf {seen[$4]=1; next} !($4 in seen) {print $1 "\t" $2 "\t" $3 "\t" $4}' \
    "$MW_TMP.res" "$snap" >> "$MW_TMP.set"
  mw_fingerprint < "$MW_TMP.set" > "$MW_TMP.cur"
  # One diff pass: every path whose state differs from its baseline state (absent when never tracked).
  diff="$(awk -F'\t' -v of="$snap" '
    FILENAME==of { os[$4]=$5; next }
    { o = ($4 in os) ? os[$4] : "absent"; if (o != $5) print $1 "\t" $2 "\t" $3 "\t" $4 "\t" o "\t" $5 }
  ' "$snap" "$MW_TMP.cur")"
  while IFS="$MW_TAB" read -r id tier kind p old new; do
    [ -n "$p" ] || continue
    case "$kind" in
      file) mw_diff_file "$tier" "$id" "$p" "$old" "$new" ;;
      exist) [ "$new" = absent ] && mw_line alert "$id" "$p" deleted ;;
      tree)
        if [ "$new" = absent ]; then mw_line alert "$id" "$p" deleted
        else mw_line "$tier" "$id" "$p" created; fi ;;
    esac
  done <<<"$diff"
  # The tree scan, for every tree present both then and now.
  while IFS="$MW_TAB" read -r id tier kind p old; do
    [ "$kind" = tree ] && [ "$old" = tree ] || continue
    [ -d "$p" ] && mw_scan_tree "$tier" "$id" "$p" "$stamp" "$MW_TMP.set"
  done < "$snap"
  # Replace the baseline with the fresh fingerprint — minus a vanished path the fresh set no longer names
  # (it was reported once as deleted; it is not tracked forever).
  awk -F'\t' -v rf="$MW_TMP.res" 'FILENAME==rf {keep[$4]=1; next} $5 != "absent" || ($4 in keep) {print}' \
    "$MW_TMP.res" "$MW_TMP.cur" > "$MW_TMP.snap"
  mv -f "$MW_TMP.stamp" "$stamp" && mv -f "$MW_TMP.snap" "$snap" || { MW_ERR="cannot write to $store"; return 2; }
  [ -z "$ALERT_L$QUIET_L" ] && return 0
  return 1
}

# --- reporting (MW4) ---------------------------------------------------------------------------------

# mw_emit EVENT HEADER — the hook's JSON on stdout: additionalContext always (every line + the fixed
# paragraph); systemMessage only when an alert line exists (alert lines + the fixed paragraph).
mw_emit() {
  local ev="$1" header="$2" ctx sys=""
  ctx="$header
${ALERT_L}${ALERT_L:+${QUIET_L:+
}}${QUIET_L}
$MW_FIXED"
  if [ -n "$ALERT_L" ]; then
    sys="$header
$ALERT_L
$MW_FIXED"
  fi
  jq -n --arg ev "$ev" --arg ctx "$ctx" --arg sys "$sys" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}
     + (if $sys == "" then {} else {systemMessage: $sys} end)'
}

# mw_notice TEXT — a lone systemMessage.
mw_notice() { jq -n --arg s "$1" '{systemMessage: $s}'; }

# --- hook mode (MW3) ---------------------------------------------------------------------------------

# mw_hook_snap SID — record the baseline, or tell the session the watcher could not.
mw_hook_snap() {
  mw_snap_write "$1" || { mw_notice "machine-watch: check failed: $MW_ERR"; return 1; }
}
# mw_hook_check SID EVENT HEADER — check, then emit the report (changed) or a failure notice (error).
mw_hook_check() {
  local rc
  mw_check "$1"; rc=$?
  if [ "$rc" = 2 ]; then mw_notice "machine-watch: check failed: $MW_ERR"
  elif [ "$rc" = 1 ]; then mw_emit "$2" "$3"; fi
}

mw_hook() {
  local payload parsed sid ev store
  if ! command -v jq >/dev/null 2>&1; then
    printf '{"systemMessage":"machine-watch: check failed: jq not found (hook mode needs it)"}\n'
    return 0
  fi
  [ -z "$MW_LIBS_ERR" ] || { mw_notice "machine-watch: check failed: $MW_LIBS_ERR"; return 0; }
  IFS= read -r -d '' payload || true
  parsed="$(jq -r '(.session_id // ""), (.hook_event_name // "")' <<<"$payload" 2>/dev/null)"
  { read -r sid; read -r ev; } <<<"$parsed"
  case "$ev" in SessionStart|PostToolUse|PostToolUseFailure|SessionEnd) ;; *) return 0 ;; esac
  sid="$(mw_sanitize "$sid")" || { mw_notice "machine-watch: check failed: unusable session_id (only A-Z a-z 0-9 . _ - are accepted)"; return 0; }
  mw_store || { mw_notice "machine-watch: check failed: $MW_ERR"; return 0; }
  store="$MW_STORE"
  case "$ev" in
    SessionEnd)
      rm -f "$store/$sid.snap" "$store/$sid.stamp" 2>/dev/null
      return 0 ;;
    SessionStart)
      if [ -f "$store/$sid.snap" ]; then
        # A resume or a compact can hide changes made while this session was not running.
        mw_hook_check "$sid" SessionStart 'machine-watch: machine-global state changed while this session was not running:'
      else
        mw_hook_snap "$sid" || return 0
      fi
      # Crashed sessions leave baselines behind.
      find "$store" -maxdepth 1 \( -name '*.snap' -o -name '*.stamp' \) -mtime "+${KEEL_MACHINE_WATCH_MAX_AGE_DAYS:-7}" \
        -exec rm -f {} + 2>/dev/null
      return 0 ;;
  esac
  # PostToolUse / PostToolUseFailure
  local header='machine-watch: machine-global state changed around this tool call:'
  if [ -f "$store/$sid.snap" ]; then
    mw_hook_check "$sid" "$ev" "$header"
  elif [ ! -d "$store" ]; then
    # No baseline for this session is itself evidence: the store was removed.
    ALERT_L="$store: deleted (this session's baseline went with it)"; QUIET_L=""
    mw_hook_snap "$sid" || return 0
    mw_emit "$ev" "$header"
  else
    mw_hook_snap "$sid" || return 0
    mw_notice "machine-watch: no baseline for this session — recorded one now (wired mid-session)"
  fi
  return 0
}

# --- CLI (MW6) ----------------------------------------------------------------------------------------

mw_usage() {
  cat <<'EOF'
machine-watch — fingerprint machine-global paths and report what changed (dir #437).

Usage:
  machine-watch.sh hook                Claude Code hook mode (JSON on stdin; always exits 0)
  machine-watch.sh paths               print the resolved watched set
  machine-watch.sh snapshot NAME       record a baseline
  machine-watch.sh check NAME          print what changed since it, replace it (exit 0 unchanged / 1 changed / 2 error)
  machine-watch.sh forget NAME         delete a baseline
  machine-watch.sh -h | --help
On a harness without hooks: `snapshot x` before a live check, `check x` after it.
EOF
}

mw_cli() {
  local cmd="${1:-}" name rc tier kind rest
  [ -z "$MW_LIBS_ERR" ] || { echo "machine-watch: $MW_LIBS_ERR" >&2; return 2; }
  case "$cmd" in
    -h|--help) mw_usage; return 0 ;;
    paths)
      mw_resolve | while IFS="$MW_TAB" read -r _ tier kind rest; do printf '%s %s %s\n' "$tier" "$kind" "$rest"; done
      return 0 ;;
    snapshot|check|forget)
      name="$(mw_sanitize "${2:-}")" || { echo "machine-watch: $cmd needs a NAME of only A-Z a-z 0-9 . _ -" >&2; return 2; }
      case "$cmd" in
        snapshot) mw_snap_write "$name" || { echo "machine-watch: $MW_ERR" >&2; return 2; } ;;
        forget) mw_store || { echo "machine-watch: $MW_ERR" >&2; return 2; }
                rm -f "$MW_STORE/$name.snap" "$MW_STORE/$name.stamp" ;;
        check)
          mw_check "$name"; rc=$?
          if [ "$rc" = 2 ]; then echo "machine-watch: $MW_ERR" >&2; return 2; fi
          [ -z "$ALERT_L" ] || printf '%s\n' "$ALERT_L"
          [ -z "$QUIET_L" ] || printf '%s\n' "$QUIET_L"
          return "$rc" ;;
      esac
      return 0 ;;
    *) mw_usage >&2; return 2 ;;
  esac
}

if [ "${1:-}" = hook ]; then
  mw_hook
  exit 0
fi
mw_cli "$@"
exit $?
