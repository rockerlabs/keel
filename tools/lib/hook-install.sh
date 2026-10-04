# shellcheck shell=bash
# tools/lib/hook-install.sh — the one settings-merge core every hook installer shares (dir #437 build
# PR1, MW8; absorbs dir #390's extraction half).
#
# Sourced, not executed: no shebang, no set -e (inherits the caller's).
#
# Extracted from tools/install-read-trace.sh and tools/install-pre-pr-gate.sh, which carried byte-
# identical copies of the backup/atomic-write helpers, the shape check and the merge/remove jq programs
# (dir #387 copied the gate's installer; the next installer (the machine-global watcher's, dir #437 PR2) would have
# been the third copy). One definition, parameterised by the hook-specs JSON and a message prefix.
# What stays in each installer: its argument parsing, its usage text, its no-jq paste-in snippet, and
# any extras of its own (the gate's manifest and ledger).
#
# The hook-specs JSON is an array of {event, matcher, command}. Every function below takes it as an
# argument and never reads a global. The one global it WRITES is $HOOK_INSTALL_BACKUP (set by
# hook_install_backup, read by the caller right after the call), so two installers sourced into one
# shell cannot cross-talk on inputs.
#
# REQUIRED, not optional, by every caller — the same contract as tools/lib/artifact-cksum.sh, for the
# same reason: a degrade-and-continue stub here would make an installer write a settings.json merge it
# did not compute. Each installer sources this file behind a `[ -s ] && bash -n` pre-check and refuses
# outright (one actionable message, exit 1) rather than sourcing unguarded; see their call sites.
#
# Names are all `hook_install_`-prefixed: a bare `_backup_settings` here would silently redefine a
# same-named function in any caller that sources this after its own (tools/lib/manifest.sh's header
# documents the lib-sourcing shadowing hazard).

# hook_install_backup SETTINGS — a timestamped copy before any destructive edit; sets
# $HOOK_INSTALL_BACKUP to the new file's path. Shared by the merge path's --force overwrite and the
# --uninstall removal path. The name is `<file>.<UTC %Y%m%dT%H%M%SZ>.bak`; when that is taken (a
# --force and an --uninstall in the same second used to share it, and the second cp overwrote the
# first backup — dir #660), `<file>.<ts>.2.bak`, `.3.bak`, … The name is CLAIMED, not just checked:
# a noclobber `>` is an exclusive create, so two runs racing on one second still get two names. The
# claim is made under umask 077 and cp keeps an existing destination's mode, so a backup is 0600 —
# never looser than a 0600 settings.json it copies (a settings file can carry `env` secrets).
# Returns 1 (nothing claimed is left behind, one line on stderr) if no name can be claimed or the copy
# fails; a claim that fails on a name nobody holds is an unwritable directory, not a collision.
hook_install_backup() {
  local base n=1
  base="$1.$(date -u +%Y%m%dT%H%M%SZ)"
  HOOK_INSTALL_BACKUP="$base.bak"
  until (set -C; umask 077; : > "$HOOK_INSTALL_BACKUP") 2>/dev/null; do
    if [ ! -e "$HOOK_INSTALL_BACKUP" ] && [ ! -L "$HOOK_INSTALL_BACKUP" ]; then
      echo "hook-install: cannot create a backup beside $1 (is its directory writable?) — nothing was written." >&2
      return 1
    fi
    n=$((n + 1))
    [ "$n" -le 99 ] || return 1
    HOOK_INSTALL_BACKUP="$base.$n.bak"
  done
  cp "$1" "$HOOK_INSTALL_BACKUP" || { rm -f "$HOOK_INSTALL_BACKUP"; return 1; }
}

# hook_install_resolve PATH — prints PATH with every symlink hop followed (one `readlink` per hop,
# the portable form: no `-f`, which BSD readlink lacks before macOS 12.3). Returns 1 on a loop.
hook_install_resolve() {
  local p="$1" l n=0
  while [ -L "$p" ]; do
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
    l="$(readlink "$p")" || return 1
    case "$l" in
      /*) p="$l" ;;
      *) case "$p" in */*) p="${p%/*}/$l" ;; *) p="$l" ;; esac ;;
    esac
  done
  printf '%s\n' "$p"
}

# hook_install_atomic_write FILE CONTENT — write CONTENT to FILE via a same-dir temp file + rename, so
# a reader never observes a partially-written file. Two properties of the file it replaces survive
# (dir #660):
#   a symlink — the write goes THROUGH it, to the file it resolves to, and the link stays a link. The
#     installers already READ settings through the link (`jq . "$settings"` follows it), so the merge
#     was computed from the target's content; writing a fresh regular file at the link's path instead
#     detached it from a dotfiles-managed target the adopter chose.
#   the mode — the temp file starts as a `cp -p` of the target, and a `>` onto an existing file keeps
#     its mode, so a 0600 settings.json stays 0600 (a bare `>` + `mv` took the umask's 0644).
# A FILE that does not exist yet is created with the umask's mode, as before. Refused, with one line on
# stderr and nothing written: a symlink loop; a target that exists but is not a regular file (a `mv`
# onto a directory would nest the temp file inside it and report success); a write that fails — a
# read-only target (its mode now carries to the temp file, where the old rename replaced it anyway), or
# a dangling link into a directory that does not exist.
hook_install_atomic_write() {
  local target="$1" tmp
  if [ -L "$1" ] && ! target="$(hook_install_resolve "$1")"; then
    echo "hook-install: $1 is a symlink loop — nothing was written." >&2
    return 1
  fi
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    echo "hook-install: $target is not a regular file — nothing was written." >&2
    return 1
  fi
  tmp="$target.keeltmp.$$"
  if ! { { [ ! -f "$target" ] || cp -p "$target" "$tmp"; } &&
         printf '%s\n' "$2" > "$tmp" && mv -f "$tmp" "$target"; } 2>/dev/null; then
    rm -f "$tmp"
    echo "hook-install: could not write $target (read-only, or its directory is missing or not writable) — nothing was written." >&2
    return 1
  fi
}

# hook_install_check_shape PREFIX SETTINGS_PATH SPECS CURRENT — valid JSON is not the same as the
# expected SHAPE: a hand-edited settings.json could have ".hooks" as an array, or ".hooks.<Event>" as a
# string, and the merge would otherwise crash with a raw jq type error instead of the clean refusal every
# other bad-input path gives. The check goes as deep as the merge and remove programs read, on the
# events the SPECS own (dir #660 — it used to stop at the event array, so `["str"]` or an entry whose
# "hooks" was a string still died in raw jq, exit 5): the document is an object, each of our event
# arrays holds objects, each entry's "hooks" is absent or an array, and that array holds objects.
# Returns 0 when fine; on a bad shape prints the refusal (stderr) under PREFIX and returns 2 — the
# caller exits.
hook_install_check_shape() {
  local prefix="$1" settings="$2" specs="$3" current="$4" shape_ok
  shape_ok="$(jq -r --argjson specs "$specs" '
    (type == "object") and (
      (.hooks // {}) as $h |
      (($h | type) == "object") and
      ($specs | map(.event) | unique | all(. as $e | ($h[$e] // []) |
        type == "array" and all(.[];
          type == "object" and ((.hooks // []) |
            type == "array" and all(.[]; type == "object")))))
    )
  ' <<<"$current" 2>/dev/null)"
  if [ "$shape_ok" != "true" ]; then
    echo "$prefix: $settings's \"hooks\" section has an unexpected shape (not the usual" >&2
    echo "  Claude Code hooks object) — fix it by hand. Nothing was changed." >&2
    return 2
  fi
}

# hook_install_jq_defs — the jq definitions BOTH programs below share, prepended to each.
# `covers($m)` (dir #92) — which existing entries can hold the spec's hook: the same matcher, OR a
# match-all one (no "matcher" key, null, "" or "*"; Claude Code fires those on every value). Our command
# inside a matcher-less entry already fires on our matcher's events, so reading it as MISSING added a
# second entry and the hook ran twice (felt: a --force re-wire duplicated the gate's rollout-check beside
# a hand-merged matcher-less SessionStart entry). A specific matcher never covers another, so a matcher
# migration (old → new) still reads MISSING and leaves the old entry for the operator. Defined once so
# the merge's SAME and the remove's REMOVED can never disagree about where our hook is.
hook_install_jq_defs() {
  printf '%s\n' 'def covers($m): .matcher == $m or .matcher == null or .matcher == "" or .matcher == "*";'
}

# hook_install_merge SPECS CURRENT — prints {new, report} as one JSON object. One pass computes BOTH the
# merged settings AND each hook's classification, from the same walk, so there is exactly one place that
# decides what "already wired" means. Per spec, over EVERY entry on that event that `covers` the spec's
# matcher (an adopter's settings can carry several; the first one is not special):
#   SAME      our exact command is already in one of them — idempotent, nothing written.
#   STALE     the same hook at a DIFFERENT path is there — the same script basename + the same arguments,
#             e.g. a moved keel checkout. Appending would fire it twice (old path and new), so this is the
#             one case the caller refuses without --force; forced, ONLY that command is swapped for ours,
#             in place, and every sibling command in the entry stays (dir #468).
#   APPENDED  a different hook already holds this event+matcher: ours goes in a SIBLING entry with the
#             same matcher. The incumbent entry is never touched, so no adopter hook is lost to wire
#             ours (dir #468).
#   MISSING   no entry holds this event+matcher: a fresh one is added.
# APPENDED vs MISSING, and where a new entry goes, key on the EXACT matcher, not on `covers`.
# "Same hook" (STALE) is judged by `ident` below: the script basename plus the arguments of a
# `bash '<path>/<script>.sh' args` command, i.e. the shape the installers build with tools/lib/sh-quote.sh's
# quoting — change one and the other must follow, or STALE silently degrades to APPENDED. It matches on
# basename only, so an adopter's own script with the same name and args on the same slot reads as STALE
# too; the cost is a refusal naming it (no --force, no write), never a silent overwrite.
# Computing the merged (as-if-forced) result even on a STALE is harmless: it is simply never written
# unless the caller's refuse/--force gate clears it. `report` is TSV lines: STATUS<TAB>event<TAB>matcher.
hook_install_merge() {
  local merge_prog='
def ident: if type == "string" then first(capture("(?<b>[^/\u0027 ]+\\.sh)\u0027?(?<r>( .*)?)$") | .b + .r) // null else null end;
def dedup_ours($c): reduce .[] as $h ([]; if $h.command == $c and any(.[]; .command == $c) then . else . + [$h] end);
{obj: (.hooks //= {}), report: []} |
reduce $specs[] as $s (.;
  .obj.hooks[$s.event] //= [] |
  .obj.hooks[$s.event] as $arr |
  ($s.command | ident) as $id |
  ([$arr[] | select(.matcher == $s.matcher)]) as $mine |
  ([$arr[] | select(covers($s.matcher)) | (.hooks // [])[] | .command]) as $cmds |
  if ($cmds | index($s.command)) != null then
    .report += [["SAME", $s.event, $s.matcher]]
  elif $id != null and ($cmds | map(select(ident == $id)) | length) > 0 then
    .obj.hooks[$s.event] |= map(if covers($s.matcher) then .hooks = ((.hooks // []) | map(if (.command | ident) == $id then .command = $s.command else . end) | dedup_ours($s.command)) else . end)
    | .report += [["STALE", $s.event, $s.matcher]]
  else
    .obj.hooks[$s.event] += [{matcher: $s.matcher, hooks: [{type: "command", command: $s.command}]}]
    | .report += [[(if ($mine | length) > 0 then "APPENDED" else "MISSING" end), $s.event, $s.matcher]]
  end
) |
{new: .obj, report: (.report | map(@tsv) | join("\n"))}
'
  jq --argjson specs "$1" "$(hook_install_jq_defs)$merge_prog" <<<"$2"
}

# hook_install_remove SPECS CURRENT — the mirror image of the merge, same one-pass-tagged-report shape
# (REMOVED/KEPT instead of the merge's statuses). Across EVERY entry that `covers` the spec's matcher
# (an APPENDED sibling can sit after the incumbent, and a forced STALE swap leaves ours inside an entry
# that also holds someone else's command), only our exact {type, command} hook comes out; an entry it leaves empty goes with it, and
# every other command — the incumbent's, or a hook you later pointed somewhere else — stays. KEPT when
# that exact event+matcher has entries but none holds ours; otherwise a slot that holds no ours gets no
# report line. An event array goes only when THIS run's removal empties it, pruned at that moment
# (dir #600): an array that was already empty — another tool's, or a hand edit's, even under one of
# our own event names — is not ours to delete.
hook_install_remove() {
  local remove_prog='
{obj: (.hooks //= {}), report: []} |
reduce $specs[] as $s (.;
  (.obj.hooks[$s.event] // []) as $arr |
  ({type: "command", command: $s.command}) as $ours |
  ([$arr[] | select(.matcher == $s.matcher)]) as $mine |
  def holds_ours: covers($s.matcher) and ((.hooks // []) | any(. == $ours));
  if ($arr | any(holds_ours)) then
    .obj.hooks[$s.event] = [$arr[] | if holds_ours then (.hooks |= map(select(. != $ours))) | select(.hooks != []) else . end]
    | if .obj.hooks[$s.event] == [] then del(.obj.hooks[$s.event]) else . end
    | .report += [["REMOVED", $s.event, $s.matcher]]
  elif ($mine | length) > 0 then
    .report += [["KEPT", $s.event, $s.matcher]]
  else
    .
  end
) |
{new: .obj, report: (.report | map(@tsv) | join("\n"))}
'
  jq --argjson specs "$1" "$(hook_install_jq_defs)$remove_prog" <<<"$2"
}
