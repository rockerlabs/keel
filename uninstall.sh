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
# Mirrors install.sh's mode flags too: --codex reverses `install.sh --codex` (default home ~/.codex, the
# always-loaded file is AGENTS.md instead of CLAUDE.md). Any one run touches ONE home, so it NAMES an
# install of the other mode it finds rather than leaving it silently behind — and REFUSES outright when
# the home it was pointed at holds the other mode, since most of what it removes is shared between the
# two and it would otherwise half-dismantle that install (dir #109).
#
# Usage:
#   uninstall.sh                 remove from ${KEEL_HOME:-$HOME/.claude} (prompts on a terminal)
#   uninstall.sh --home DIR      remove from DIR
#   uninstall.sh --codex         reverse an  install.sh --codex  (default home ~/.codex, AGENTS.md)
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
  uninstall.sh --codex         reverse an  install.sh --codex  (default home ~/.codex, AGENTS.md)
  uninstall.sh --yes           don't prompt (required when not run from a terminal)
  uninstall.sh --dry-run       show what WOULD be removed, change nothing
  uninstall.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"
ASSUME_YES=0
DRY_RUN=0
CODEX=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --home) shift; HOME_DIR="${1:?--home needs a DIR}" ;;
    --codex) CODEX=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done
# Home + context-file resolution mirrors install.sh's, flag for flag: a --codex install lands in
# $HOME/.codex and writes AGENTS.md, so its reversal has to look in the same place for the same file.
# The pairs are named because the mode checks below need the OTHER mode's pair — the one this run is
# not operating on.
CODEX_LEAF=".codex";  CODEX_CONTEXT="AGENTS.md"
CLAUDE_LEAF=".claude"; CLAUDE_CONTEXT="CLAUDE.md"
if [ "$CODEX" = 1 ]; then
  leaf="$CODEX_LEAF";  CONTEXT_FILE="$CODEX_CONTEXT";  other_leaf="$CLAUDE_LEAF"; other_context="$CLAUDE_CONTEXT"; other_cmd="uninstall.sh"
else
  leaf="$CLAUDE_LEAF"; CONTEXT_FILE="$CLAUDE_CONTEXT"; other_leaf="$CODEX_LEAF";  other_context="$CODEX_CONTEXT";  other_cmd="uninstall.sh --codex"
fi
# Exactly install.sh's precedence: an explicit target (--home, else $KEEL_HOME) outranks the mode's
# default leaf, so an install placed with `KEEL_HOME=X install.sh --codex` is reversed by
# `KEEL_HOME=X uninstall.sh --codex`. The mode/home mismatch that precedence makes possible is caught
# below rather than papered over here — see the refusal.
: "${HOME_DIR:=${HOME:?uninstall: set HOME, or pass --home DIR}/$leaf}"

# core_import_re — THE definition of "this line IS the core @import", byte-identical to install.sh's
# has_core_import (which tools/doctor.sh --install mirrors too); tools/self/doctor.sh's check 1b holds
# the three to it. The boundaries are load-bearing, not decoration: matching by bare substring, as this
# used to, also hits a line that merely MENTIONS the path in prose — a backtick-quoted
# `@~/.claude/keel/CORE.md` in someone's own notes — and silently deletes it, contradicting the promise
# printed with the strip below, that the rest of your file is untouched (dir #108).
core_import_re='(^|[[:space:]])@[^[:space:]]*keel/CORE\.md([[:space:]]|$)'

# has_keel_rails FILE — the file carries Keel's always-on rails, embedded or imported.
has_keel_rails() {
  [ -f "$1" ] || return 1
  grep -q 'KEEL-CORE-BEGIN' "$1" 2>/dev/null || grep -qE "$core_import_re" "$1" 2>/dev/null
}

# other_mode_hint — this run only ever touches ONE home, and the two install modes live in different
# ones. Without this an adopter who ran both is told "done"/"nothing to do" with a full set of Keel
# rails still loading into every session of the other harness. Symmetric on purpose: a --codex run
# names a leftover Claude install exactly as a plain run names a leftover Codex one (an asymmetric
# version of this guard was what let the mis-target refused below print a clean "done").
# Called explicitly at each of the three reporting exits rather than from an EXIT trap: the trap would
# also fire on the refusal paths (no --yes on a non-terminal, an unknown flag, the mismatch below),
# where a leftover-install hint is noise attached to a run that did nothing. The exit that matters most
# is the earliest — "no Keel home at ~/.claude" is exactly the run a Codex-only adopter makes first
# (dir #109).
other_mode_hint() {
  [ -n "${HOME:-}" ] || return 0
  local other="$HOME/$other_leaf"
  [ "$other" != "$HOME_DIR" ] || return 0
  has_keel_rails "$other/$other_context" || return 0
  echo "  • A Keel install is still in place at $other/$other_context — this run did not touch it."
  echo "    Remove it too:  $other_cmd"
}

if [ ! -d "$HOME_DIR" ]; then
  echo "uninstall: nothing to do — no Keel home at $HOME_DIR"
  other_mode_hint
  exit 0
fi

# is_keel_owned PATH SHIPPED — the removal steps' own rule for "this slot is Keel's, not yours": a
# symlink we wired, or a regular file byte-identical to what this checkout ships. A drifted copy is
# yours. Factored out here because home_has_keel_content asks the same question the steps do.
is_keel_owned() {
  [ -L "$1" ] && return 0
  [ -f "$1" ] && [ -n "${2:-}" ] && cmp -s "$1" "$2" && return 0
  return 1
}

# home_has_keel_content — did an install ever run against THIS home? Deliberately independent of the
# rails: an install over a pre-existing, foreign CLAUDE.md leaves that file untouched (install.sh's
# foreign_core path) while still wiring commands, bin/keel and the FRAMEWORK/PRINCIPLES copies, so
# "carries Keel's rails" is not the same question and answering it here read a real Keel home as empty.
home_has_keel_content() {
  [ -d "$HOME_DIR/keel" ] && return 0
  [ -L "$HOME_DIR/bin/keel" ] && return 0
  local f slot
  for f in FRAMEWORK.md PRINCIPLES.md; do
    is_keel_owned "$HOME_DIR/$f" "$root/$f" && return 0
  done
  if [ -d "$root/commands" ] && [ -d "$HOME_DIR/commands" ]; then
    for f in "$root"/commands/*.md; do
      [ -f "$f" ] || continue
      slot="$HOME_DIR/commands/$(basename "$f")"
      is_keel_owned "$slot" "$f" && return 0
    done
  fi
  return 1
}

# Mode/home mismatch — refuse rather than half-dismantle. Steps 1-4 below (the linked keel/ dir, the
# CLI symlink, the commands, the FRAMEWORK/PRINCIPLES copies) are mode-AGNOSTIC and would fire happily
# on any Keel home, while only step 5 is mode-specific. So a --codex run aimed at a Claude home strips
# the shared half and leaves CLAUDE.md loading its rails forever — a half-dismantled install reported
# as a clean success. Reachable because an explicit target outranks the mode leaf (above):
# `KEEL_HOME=<claude-home> uninstall.sh --codex` is the felt case, and the reverse is just as possible.
#
# The three conditions are each load-bearing:
#   - this mode's context file ABSENT — its presence is what says an install of THIS mode ran here
#     (install always leaves one, whether it wrote the file or kept yours);
#   - the other mode's context file PRESENT — plain existence, NOT "carries Keel's rails". Requiring
#     rails was the first version of this guard and it let the whole foreign-core case through: an
#     install over someone's own pre-Keel CLAUDE.md never writes rails into it, so a --codex run aimed
#     there sailed past the guard and removed the commands, the CLI and both product copies of an
#     install nobody asked it to touch (found by the operator's second /code-review pass);
#   - the home holding Keel content — without it, a bare dir containing only the user's own AGENTS.md
#     would be refused with advice to re-run under --codex, which would then find nothing to do. With
#     it, that case falls through to the honest "no Keel-owned content" no-op below.
# A home with NEITHER context file is an ordinary empty/foreign dir, and one the user emptied of their
# own context file still uninstalls normally — neither is a mismatch.
if [ ! -f "$HOME_DIR/$CONTEXT_FILE" ] && [ -f "$HOME_DIR/$other_context" ] && home_has_keel_content; then
  echo "uninstall: $HOME_DIR has no $CONTEXT_FILE, but it does hold a Keel install and an $other_context." >&2
  echo "  That's the other install mode — removing it from here would take the shared half (commands," >&2
  echo "  the CLI symlink, FRAMEWORK/PRINCIPLES) and leave $other_context in place as its own install." >&2
  echo "  Nothing was changed. Reverse it with:  $other_cmd --home \"$HOME_DIR\"" >&2
  exit 2
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
    if is_keel_owned "$slot" "$cmd"; then
      take "$slot"
    elif [ -e "$slot" ]; then
      echo "  =    commands/$name differs from Keel's — kept (yours)"
    fi
    case "$name" in
      keel-*) ;;   # keel-* commands never get an alias
      *)
        if [ ! -f "$root/commands/keel-$name" ]; then
          alias_slot="$HOME_DIR/commands/keel-$name"
          if is_keel_owned "$alias_slot" "$cmd"; then
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
  if is_keel_owned "$slot" "$root/$f"; then
    take "$slot"
  elif [ -e "$slot" ]; then
    echo "  =    $f differs from Keel's — kept (yours)"
  fi
done

# 5. The global always-loaded file (CLAUDE.md; AGENTS.md under --codex) — never deleted (it may hold
# your edits): only the Keel-delivered rails come out, i.e. the @import line and/or the embedded
# KEEL-CORE block. Backed up before the edit.
# (core_import_re / has_keel_rails — and why the boundaries matter — are defined near the top.)
gclaude="$HOME_DIR/$CONTEXT_FILE"
if has_keel_rails "$gclaude"; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "  would strip the Keel rails (import line / KEEL-CORE block) from $CONTEXT_FILE"
    removed=$((removed + 1))
  else
    _ensure_backup
    mkdir -p "$backup"
    cp "$gclaude" "$backup/$CONTEXT_FILE"
    # Drop the embedded block (markers inclusive) and any line carrying the core import. The regex
    # arrives through ENVIRON, not -v: awk applies escape processing to a -v assignment, which would
    # eat the `\.` and quietly widen the pattern — the exact class of drift this shared definition exists
    # to prevent.
    KEEL_IMPORT_RE="$core_import_re" awk '
      BEGIN             { re = ENVIRON["KEEL_IMPORT_RE"] }
      /KEEL-CORE-BEGIN/ { skip=1; next }
      /KEEL-CORE-END/   { skip=0; next }
      skip              { next }
      $0 ~ re           { next }
      { print }
    ' "$gclaude" > "$gclaude.keeltmp.$$" && mv -f "$gclaude.keeltmp.$$" "$gclaude"
    echo "  stripped the Keel rails from $CONTEXT_FILE (backup: $backup/$CONTEXT_FILE; the rest of your file is untouched)"
    removed=$((removed + 1))
  fi
fi

# --- summary ------------------------------------------------------------------------------------
echo
if [ "$removed" = 0 ]; then
  echo "uninstall: found no Keel-owned content at $HOME_DIR — nothing removed."
  other_mode_hint
  exit 0
fi
if [ "$DRY_RUN" = 1 ]; then
  echo "uninstall: dry run — $removed item(s) would be removed. Re-run without --dry-run to apply."
  other_mode_hint
  exit 0
fi
echo "uninstall: done — $removed item(s) removed (backed up in $backup)."
echo "  • Your INSTANCE.md / LEARNINGS.md / IDEAS.md and any command you authored were left in place."
other_mode_hint

# The machine-global secret-guard is deliberately NOT removed: it's a shared safety net that may guard
# repos beyond Keel, and dropping it silently would weaken protection. Report it as an opt-in manual step.
hp="$(git config --global core.hooksPath 2>/dev/null || true)"
case "$hp" in
  *keel-hooks)
    echo "  • The machine-global secret-guard is still wired (core.hooksPath=$hp) — kept on purpose."
    echo "    To remove it too:  git config --global --unset core.hooksPath && rm -rf \"$hp\""
    ;;
esac
