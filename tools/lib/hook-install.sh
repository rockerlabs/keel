# shellcheck shell=bash
# tools/lib/hook-install.sh — the one settings-merge core every hook installer shares (dir #437 build
# PR1, MW8; absorbs dir #390's extraction half).
#
# Sourced, not executed — no shebang as the first line's contract, no set -e (inherits the caller's).
#
# Extracted from tools/install-read-trace.sh and tools/install-pre-pr-gate.sh, which carried byte-
# identical copies of the backup/atomic-write helpers, the shape check and the merge/remove jq programs
# (dir #387 copied the gate's installer; the next installer (the machine-global watcher's, dir #437 PR2) would have
# been the third copy). One definition, parameterised by the hook-specs JSON and a message prefix.
# What stays in each installer: its argument parsing, its usage text, its no-jq paste-in snippet, and
# any extras of its own (the gate's manifest and ledger).
#
# The hook-specs JSON is an array of {event, matcher, command}. Every function below takes it as an
# argument and never reads a global, so two installers sourced into one shell cannot cross-talk.
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
# --uninstall removal path.
hook_install_backup() {
  HOOK_INSTALL_BACKUP="$1.$(date -u +%Y%m%dT%H%M%SZ).bak"
  cp "$1" "$HOOK_INSTALL_BACKUP"
}

# hook_install_atomic_write FILE CONTENT — write CONTENT to FILE via a same-dir temp file + rename, so
# a reader never observes a partially-written file.
hook_install_atomic_write() {
  printf '%s\n' "$2" > "$1.keeltmp.$$" && mv -f "$1.keeltmp.$$" "$1"
}

# hook_install_check_shape PREFIX SETTINGS_PATH SPECS CURRENT — valid JSON is not the same as the
# expected SHAPE: a hand-edited settings.json could have ".hooks" as an array, or ".hooks.<Event>" as a
# string, and the merge would otherwise crash with a raw jq type error instead of the clean refusal every
# other bad-input path gives. Returns 0 when fine; on a bad shape prints the refusal (stderr) under
# PREFIX and returns 2 — the caller exits.
hook_install_check_shape() {
  local prefix="$1" settings="$2" specs="$3" current="$4" shape_ok
  shape_ok="$(jq -r --argjson specs "$specs" '
    (.hooks // {}) as $h |
    (($h | type) == "object") as $hooks_ok |
    ($specs | map(.event) | unique | all(. as $e | (($h[$e] // []) | type) == "array")) as $events_ok |
    ($hooks_ok and $events_ok)
  ' <<<"$current")"
  if [ "$shape_ok" != "true" ]; then
    echo "$prefix: $settings's \"hooks\" section has an unexpected shape (not the usual" >&2
    echo "  Claude Code hooks object) — fix it by hand. Nothing was changed." >&2
    return 2
  fi
}

# hook_install_merge SPECS CURRENT — prints {new, report} as one JSON object. One pass computes BOTH the
# merged settings AND each hook's classification — MISSING (not wired), SAME (already exactly ours —
# idempotent), or CONFLICT (that event+matcher already runs a different command, someone else's) — from
# the same walk, so there is exactly one place that decides what "already wired" means. Computing the
# merged (as-if-forced) result even on a CONFLICT is harmless: it is simply never written unless the
# caller's refuse/--force gate clears it. `report` is TSV lines: STATUS<TAB>event<TAB>matcher.
hook_install_merge() {
  local merge_prog='
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
  jq --argjson specs "$1" "$merge_prog" <<<"$2"
}

# hook_install_remove SPECS CURRENT — the mirror image of the merge, same one-pass-tagged-report shape
# (REMOVED/KEPT instead of MISSING/SAME/CONFLICT). An event+matcher entry comes out ONLY when its hooks
# array is byte-identical to the single {type, command} entry the installer would wire right now —
# anything else on that same event+matcher (yours, or a --force run's replacement of something else
# entirely) is left in place and reported KEPT, never swept out along with the rest. The empty-array
# prune is scoped to the events the SPECS own (dir #564, dir #390): another tool's empty hook array under
# `.hooks` is not ours to delete.
hook_install_remove() {
  local remove_prog='
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
  jq --argjson specs "$1" "$remove_prog" <<<"$2"
}
