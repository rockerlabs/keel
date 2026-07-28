#!/usr/bin/env bash
# uninstall — reverse install.sh. The mirror image of what install wires, and nothing more: it
# removes ONLY Keel-owned content (the linked keel/ consumption dir, the one @import line / embedded
# rails block in the global CLAUDE.md, the command symlinks + collision aliases, the keel PATH
# symlink, and any copy-mode FRAMEWORK/PRINCIPLES it placed). It NEVER touches your own files
# (INSTANCE.md, LEARNINGS.md, IDEAS.md, or a command you authored) and NEVER silently drops the
# machine-global secret-guard (a shared safety net — removing it is a separate, announced opt-in).
#
# Backs up before it removes: everything it takes out is MOVED into a timestamped backup dir under the
# home (CLAUDE.md is copied there before its in-place edit), so an uninstall is reversible — nothing is
# hard-deleted. Refuse-to-clobber in reverse: a file that differs from what Keel shipped is treated as
# yours and left in place.
#
# Usage:
#   uninstall.sh                 remove from ${KEEL_HOME:-$HOME/.claude} (prompts on a terminal)
#   uninstall.sh --home DIR      remove from DIR
#   uninstall.sh --yes           don't prompt (required when not run from a terminal)
#   uninstall.sh --dry-run       show what WOULD be removed, change nothing
#   uninstall.sh -h | --help
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"   # the Keel checkout (this script lives at the top level)

usage() {
  cat <<'EOF'
uninstall — reverse install.sh: remove Keel-owned content from your harness home, backing up
everything it takes out. Leaves your own files and the machine-global secret-guard untouched.

Usage:
  uninstall.sh                 remove from ${KEEL_HOME:-$HOME/.claude} (prompts on a terminal)
  uninstall.sh --home DIR      remove from DIR
  uninstall.sh --yes           don't prompt (required when not run from a terminal)
  uninstall.sh --dry-run       show what WOULD be removed, change nothing
  uninstall.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"
ASSUME_YES=0
DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --home) shift; HOME_DIR="${1:?--home needs a DIR}" ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done
: "${HOME_DIR:=${HOME:?uninstall: set HOME, or pass --home DIR}/.claude}"

if [ ! -d "$HOME_DIR" ]; then
  echo "uninstall: nothing to do — no Keel home at $HOME_DIR"
  exit 0
fi

echo "Keel uninstall ← $HOME_DIR"
echo "        checkout $root"
if [ "$DRY_RUN" = 1 ]; then
  echo "        (dry run — nothing will be changed)"
elif [ "$ASSUME_YES" = 0 ]; then
  if [ -t 0 ]; then
    printf "Remove Keel-owned content from %s? Your own files are kept and everything is backed up. [y/N] " "$HOME_DIR"
    read -r reply || reply=""
    case "$reply" in [yY]|[yY][eE][sS]) : ;; *) echo "uninstall: aborted."; exit 0 ;; esac
  else
    echo "uninstall: not a terminal — pass --yes to confirm (or --dry-run to preview)." >&2
    exit 2
  fi
fi

# Backup dir, created lazily on the first real removal so a dry run (or a no-op uninstall) leaves no
# trace. Timestamped UTC so repeated runs never collide.
backup=""
removed=0
_ensure_backup() {
  [ -n "$backup" ] && return 0
  backup="$HOME_DIR/.keel-uninstall-$(date -u +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  echo "  backup → $backup"
}

# take PATH — back up (preserving its path under the home) then remove. Symlinks are moved as-is
# (mv doesn't follow them), so the backup records exactly what was wired.
take() {
  local p="$1" rel dest
  [ -e "$p" ] || [ -L "$p" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then echo "  would remove  ${p#"$HOME_DIR"/}"; removed=$((removed + 1)); return 0; fi
  _ensure_backup
  case "$p" in "$HOME_DIR"/*) rel="${p#"$HOME_DIR"/}" ;; *) rel="$(basename "$p")" ;; esac
  dest="$backup/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$p" "$dest"
  echo "  removed  $rel"
  removed=$((removed + 1))
}

# 1. The linked consumption dir — entirely Keel's (symlinks into the checkout + a generated README).
take "$HOME_DIR/keel"

# 2. The keel CLI symlink on PATH, and the bin/ dir if it's now empty (install created both).
if [ -L "$HOME_DIR/bin/keel" ]; then
  take "$HOME_DIR/bin/keel"
elif [ -e "$HOME_DIR/bin/keel" ]; then
  echo "  =    bin/keel is not a symlink — left in place (not something install wired)"
fi
[ -d "$HOME_DIR/bin" ] && [ "$DRY_RUN" = 0 ] && rmdir "$HOME_DIR/bin" 2>/dev/null || true

# 3. Lifecycle commands. A slot is Keel's if it's a symlink OR a regular file byte-identical to what
# this checkout ships; a file that DIFFERS is yours (you authored or edited it) — left untouched. The
# keel-<name> collision alias is removed the same way, but only where keel-<name> isn't itself shipped
# (mirror of install.sh's alias rule).
if [ -d "$root/commands" ]; then
  for cmd in "$root"/commands/*.md; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"
    slot="$HOME_DIR/commands/$name"
    if [ -L "$slot" ] || { [ -f "$slot" ] && cmp -s "$slot" "$cmd"; }; then
      take "$slot"
    elif [ -e "$slot" ]; then
      echo "  =    commands/$name differs from Keel's — kept (yours)"
    fi
    case "$name" in
      keel-*) ;;   # keel-* commands never get an alias
      *)
        if [ ! -f "$root/commands/keel-$name" ]; then
          alias_slot="$HOME_DIR/commands/keel-$name"
          if [ -L "$alias_slot" ] || { [ -f "$alias_slot" ] && cmp -s "$alias_slot" "$cmd"; }; then
            take "$alias_slot"
          fi
        fi ;;
    esac
  done
  [ -d "$HOME_DIR/commands" ] && [ "$DRY_RUN" = 0 ] && rmdir "$HOME_DIR/commands" 2>/dev/null || true
fi

# 4. Copy-mode on-demand tier: a root FRAMEWORK/PRINCIPLES that install placed (a symlink, or a copy
# byte-identical to the shipped file). A drifted copy is treated as yours and left.
for f in FRAMEWORK.md PRINCIPLES.md; do
  slot="$HOME_DIR/$f"
  if [ -L "$slot" ] || { [ -f "$slot" ] && cmp -s "$slot" "$root/$f"; }; then
    take "$slot"
  elif [ -e "$slot" ]; then
    echo "  =    $f differs from Keel's — kept (yours)"
  fi
done

# 5. The global CLAUDE.md — never deleted (it may hold your edits): only the Keel-delivered rails come
# out, i.e. the @import line and/or the embedded KEEL-CORE block. Backed up before the edit.
gclaude="$HOME_DIR/CLAUDE.md"
if [ -f "$gclaude" ] \
   && { grep -q 'KEEL-CORE-BEGIN' "$gclaude" \
        || grep -qE '@[^[:space:]]*keel/CORE\.md' "$gclaude"; }; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "  would strip the Keel rails (import line / KEEL-CORE block) from CLAUDE.md"
    removed=$((removed + 1))
  else
    _ensure_backup
    mkdir -p "$backup"
    cp "$gclaude" "$backup/CLAUDE.md"
    # Drop the embedded block (markers inclusive) and any line carrying the keel/CORE.md import token.
    awk '
      /KEEL-CORE-BEGIN/ { skip=1; next }
      /KEEL-CORE-END/   { skip=0; next }
      skip              { next }
      /@[^[:space:]]*keel\/CORE\.md/ { next }
      { print }
    ' "$gclaude" > "$gclaude.keeltmp.$$" && mv -f "$gclaude.keeltmp.$$" "$gclaude"
    echo "  stripped the Keel rails from CLAUDE.md (backup: $backup/CLAUDE.md; the rest of your file is untouched)"
    removed=$((removed + 1))
  fi
fi

# --- summary ------------------------------------------------------------------------------------
echo
if [ "$removed" = 0 ]; then
  echo "uninstall: found no Keel-owned content at $HOME_DIR — nothing removed."
  exit 0
fi
if [ "$DRY_RUN" = 1 ]; then
  echo "uninstall: dry run — $removed item(s) would be removed. Re-run without --dry-run to apply."
  exit 0
fi
echo "uninstall: done — $removed item(s) removed (backed up in $backup)."
echo "  • Your INSTANCE.md / LEARNINGS.md / IDEAS.md and any command you authored were left in place."

# The machine-global secret-guard is deliberately NOT removed: it's a shared safety net that may guard
# repos beyond Keel, and dropping it silently would weaken protection. Report it as an opt-in manual step.
hp="$(git config --global core.hooksPath 2>/dev/null || true)"
case "$hp" in
  *keel-hooks)
    echo "  • The machine-global secret-guard is still wired (core.hooksPath=$hp) — kept on purpose."
    echo "    To remove it too:  git config --global --unset core.hooksPath && rm -rf \"$hp\""
    ;;
esac
