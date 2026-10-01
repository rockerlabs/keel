#!/usr/bin/env bash
# state-root-migrate — move keel's durable stores out of the harness home into $HOME/.keel (dir #637).
#
# Before dir #637 the impact store and the read-trace store lived under
# ${KEEL_HOME:-$HOME/.claude}/.keel/<name>/, inside the harness home — so `rm -r ~/.claude` or a harness
# migration took them along. They now live at $HOME/.keel/<name>/ (tools/lib/state-root.sh). This tool
# moves what is still at the old address, losslessly and reversibly:
#
#   state-root-migrate.sh [--from HARNESS_HOME] [--dry-run]
#
#   --from HARNESS_HOME   the harness home to move out of (default: ${KEEL_HOME:-$HOME/.claude})
#   --dry-run             print what would happen; change nothing
#
# For each store NAME in {impact, read-trace} and each direct child directory E of
# <HARNESS_HOME>/.keel/NAME (dot-names included; files and symlinks are skipped):
#   * the target $HOME/.keel/NAME/<E> already exists → E is KEPT, untouched, and reported with a hint
#     (never merged automatically: read-trace has no merge helper, and never-clobber is the rule);
#   * otherwise E is moved there and a symlink is left at the old address, so a downgraded keel, or a
#     stale vendored secret-scan.sh copy, still finds the data. The link dies alone with the harness home.
# `mv` and `ln` both return 0 on the collisions this guards against (an entry that appeared mid-move),
# so the post-conditions are checked explicitly and reported — they are the only detection.
#
# Per-store overrides (KEEL_IMPACT_STORE, KEEL_READ_TRACE_STORE) are ignored here: the target is always
# $HOME/.keel/NAME; one notice line says so. Never deletes anything, never writes into a project.
# All output goes to stdout: one line per action, then one summary.
#
# Exit: 0 when everything moved (or there was nothing to move); 1 when something was kept or could not
# be completed; 2 on a usage error. $HOME unset → "nothing migrated", exit 0.
#
# To go back: delete the symlinks and move the directories back.

srm_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/state-root.sh
. "$srm_dir/lib/state-root.sh"

srm_usage() {
  cat <<'EOF'
Usage: state-root-migrate.sh [--from HARNESS_HOME] [--dry-run]

Move keel's impact and read-trace stores from the harness home into $HOME/.keel,
leaving one compat symlink per moved entry. Conflicts are kept and reported.
EOF
}

# srm_link_back T E — leave the compat symlink E → T after E's contents moved to T. Returns non-zero (and
# says why) when E has reappeared, or when the link could not be verified. The checks are the detection:
# `ln -s T E` returns 0 even when E is an existing directory (it nests the link INSIDE E).
srm_link_back() {
  local t="$1" e="$2"
  if [ -e "$e" ] || [ -L "$e" ]; then
    printf 'reappeared %s — something recreated it during the move; its contents are now at %s (merge by hand, then replace it with a link to %s)\n' "$e" "$t" "$t"
    return 1
  fi
  ln -s "$t" "$e" 2>/dev/null
  if [ ! -L "$e" ]; then
    printf 'could not link %s -> %s (contents are at %s)\n' "$e" "$t" "$t"
    return 1
  fi
}

# srm_keep_hint NAME E — what to do about a kept entry. `restore` targets the cwd's project, so the
# hint for an impact entry cd's into the project the entry records in `origin`.
srm_keep_hint() {
  local name="$1" e="$2" origin=""
  if [ "$name" = impact ] && [ -f "$e/origin" ]; then
    IFS= read -r origin < "$e/origin" || true
  fi
  if [ -n "$origin" ]; then
    printf '  to merge: (cd "%s" && %s/keel-impact.sh restore "%s"), then remove %s once merged\n' "$origin" "$srm_dir" "$e" "$e"
  else
    printf '  merge by hand, then remove %s\n' "$e"
  fi
}

srm_main() {
  set -u
  local from="" dry=0 root name src tgt_root e base t from_home
  local moved=0 kept=0 problems=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) [ $# -ge 2 ] && [ -n "$2" ] || { echo "state-root-migrate: --from needs a HARNESS_HOME" >&2; srm_usage >&2; return 2; }
              from="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      -h|--help) srm_usage; return 0 ;;
      *) echo "state-root-migrate: unknown argument: $1" >&2; srm_usage >&2; return 2 ;;
    esac
  done

  root="$(keel_state_root)" || { echo "state-root-migrate: HOME unset — nothing migrated"; return 0; }
  from_home="${from:-${KEEL_HOME:-$HOME/.claude}}"
  if [ -n "${KEEL_IMPACT_STORE:-}" ] || [ -n "${KEEL_READ_TRACE_STORE:-}" ]; then
    echo "state-root-migrate: note: KEEL_IMPACT_STORE / KEEL_READ_TRACE_STORE is set and ignored — migrating to $root/<name>"
  fi

  for name in impact read-trace; do
    src="$(keel_legacy_store_root "$name" "$from")" || continue
    [ -d "$src" ] || continue
    tgt_root="$root/$name"
    # The legacy root IS the target root (a compat link to it, or the same directory): nothing to move.
    if [ -d "$tgt_root" ] && [ "$(cd "$src" && pwd -P)" = "$(cd "$tgt_root" && pwd -P)" ]; then continue; fi
    for e in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -d "$e" ] && [ ! -L "$e" ] || continue
      base="$(basename "$e")"
      t="$tgt_root/$base"
      if [ -e "$t" ] || [ -L "$t" ]; then
        printf 'kept %s — %s already exists\n' "$e" "$t"
        srm_keep_hint "$name" "$e"
        kept=$((kept + 1))
        continue
      fi
      if [ "$dry" = 1 ]; then
        printf 'would move %s -> %s (and leave a link)\n' "$e" "$t"
        moved=$((moved + 1))
        continue
      fi
      mkdir -p "$tgt_root"
      mv "$e" "$t"
      if [ ! -d "$t" ] || [ -e "$t/$base" ]; then
        printf 'nested %s — the move did not land cleanly at %s; inspect both, nothing was deleted\n' "$e" "$t"
        problems=$((problems + 1))
        continue
      fi
      if srm_link_back "$t" "$e"; then
        printf 'moved %s -> %s (link left)\n' "$e" "$t"
        moved=$((moved + 1))
      else
        problems=$((problems + 1))
      fi
    done
  done

  if [ "$moved" -eq 0 ] && [ "$kept" -eq 0 ] && [ "$problems" -eq 0 ]; then
    echo "nothing to migrate from $from_home"
    return 0
  fi
  if [ "$dry" = 1 ]; then
    printf 'dry run: would move %d, kept %d\n' "$moved" "$kept"
  else
    printf 'moved %d, kept %d%s\n' "$moved" "$kept" "$([ "$problems" -gt 0 ] && printf ', %d problem(s)' "$problems")"
  fi
  [ "$kept" -eq 0 ] && [ "$problems" -eq 0 ]
}

# Run only when executed; a test sources this file to call srm_link_back directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  srm_main "$@"
  exit $?
fi
