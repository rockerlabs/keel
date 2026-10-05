# shellcheck shell=bash
# tools/lib/core-ownership.sh — keel/CORE.md's ownership predicate (dir #363, split from dir #278).
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
#
# dir #650 adds the block-currency comparator (keel_core_block_*): how an EMBEDDED KEEL-CORE block (copy
# mode's CLAUDE.md, --codex's AGENTS.md) relates to the shipped CORE.md — shared by install.sh's
# refresh ladder and doctor's W-CORE-DRIFT so there is one definition of "current".
#
# A Keel-owned keel/CORE.md takes one of two shapes: an ordinary linked install (CORE.md is a symlink
# into the checkout) or a --no-git trim (CORE.md is a generated regular file, code/git rails stripped,
# carrying the KEEL-NOGIT marker so a later run can recognize and heal it). install.sh's three call
# sites, uninstall.sh's one, and tools/doctor.sh's four each asked one or both of these two questions
# with their own hand-copied test before this file existed — two functions here, one definition each.
#
# REQUIRED, not optional, for uninstall.sh and tools/doctor.sh — GUARDED (`[ -s ] && bash -n`
# pre-check, one actionable message, exit 1), matching tools/lib/manifest.sh's own contract for those
# same two scripts, NOT a bare source like tools/lib/ledger.sh's own pre-existing, unaudited precedent
# (an earlier draft of this header claimed bare sourcing; found stale by this ticket's own
# /code-review max pass — the actual call sites in both scripts have always been guarded). Neither
# script has an established "must survive a tools/-less checkout" contract to preserve here, so
# refusing outright on a missing/corrupted copy is the right failure mode, not a silent degrade.
#
# OPTIONAL for install.sh, with a byte-identical inline fallback in its own sourcing block — unlike
# tools/lib/artifact-cksum.sh, install.sh's three call sites are pure filesystem checks with zero
# tools/ dependency today (the first runs before install.sh sources anything from tools/lib/ at all),
# used only for this run's own LINK/NOGIT control flow and a printed message — never written into a
# manifest record another script later trusts for a destructive decision, so there is no analogous
# cross-script poisoning risk to guard against by refusing outright. See install.sh's own sourcing
# block (hoisted before its first call site, same reasoning as its self-link guard) for the guarded,
# degrade-with-fallback pattern and the fallback copy, which must stay byte-identical to this file.

# keel_core_is_link FILE — true iff FILE is a symlink: an ordinary linked install. A dangling link
# still counts (-L, not -f/-e) — a moved/reaped checkout is still a linked install, one a re-run heals.
keel_core_is_link() {
  [ -L "$1" ]
}

# keel_core_is_nogit_trim FILE — true iff FILE is a regular file (not a symlink) carrying the
# KEEL-NOGIT marker: a generated --no-git trim, install.sh's stand-in for the symlink once the
# code/git rails are stripped.
keel_core_is_nogit_trim() {
  [ -f "$1" ] && [ ! -L "$1" ] && grep -q 'KEEL-NOGIT' "$1" 2>/dev/null
}

# keel_core_block_text FILE — the lines strictly between FILE's KEEL-CORE markers (the markers
# themselves excluded: their comment text legitimately differs). The ONE definition of "the embedded
# rails block" for install.sh's block-currency ladder and tools/doctor.sh's drift check (dir #650); it
# absorbs install.sh's former core_block(), itself a mirror of block_of() in
# tests/test_core_wrapper_sync.sh — that test's own copy is the byte-identity pin and stays.
keel_core_block_text() {
  sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$1" | sed '1d;$d'
}

# keel_core_block_is_trimmed FILE — true iff FILE's embedded block carries NEITHER droppable heading:
# "## Git — mandatory rails" and "## Before writing code — reconcile first", the two sections
# /keel-setup's no-git trim removes (tests/test_doc_figures.sh pins both names). One heading kept =
# not a trim (a partial hand edit), so it is compared byte-exact and reads as drift.
keel_core_block_is_trimmed() {
  local block
  block="$(keel_core_block_text "$1")"
  case "$block" in
    *'## Git — mandatory rails'*|*'## Before writing code — reconcile first'*) return 1 ;;
  esac
  return 0
}

# keel_core_block_norm — stdin → stdout, with every KEEL-GIT/KEEL-NOGIT marker line dropped and runs
# of blank lines squeezed to one: a hand trim leaves neither the markers nor the original spacing.
keel_core_block_norm() {
  awk '/KEEL-(NO)?GIT-(BEGIN|END)/ { next } NF { blank = 0; print; next } !blank { print; blank = 1 }'
}

# keel_core_block_state FILE CORE — how FILE's embedded KEEL-CORE block relates to the shipped CORE.md:
#   current          a full block, byte-identical to CORE.md's
#   current-trimmed  a git-rails-trimmed block (keel_core_block_is_trimmed) equal to CORE.md's block
#                    minus its KEEL-GIT regions — compared with the NOGIT breadcrumb and all marker
#                    lines dropped and blank runs squeezed (keel_core_block_norm)
#   drift            anything else (older, newer, or edited)
# The trim-aware half exists so a /keel-setup no-git trim, a deliberate edit, is never reported as
# drift forever (and never silently undone by the refresh the ladder offers).
keel_core_block_state() {
  local inst ref
  inst="$(keel_core_block_text "$1")"
  ref="$(keel_core_block_text "$2")"
  if ! keel_core_block_is_trimmed "$1"; then
    if [ "$inst" = "$ref" ]; then echo current; else echo drift; fi
    return 0
  fi
  inst="$(printf '%s\n' "$inst" | sed '/KEEL-NOGIT-BEGIN/,/KEEL-NOGIT-END/d' | keel_core_block_norm)"
  ref="$(printf '%s\n' "$ref" | awk '/KEEL-GIT-BEGIN/ { skip = 1; next } /KEEL-GIT-END/ { skip = 0; next } !skip' | keel_core_block_norm)"
  if [ "$inst" = "$ref" ]; then echo current-trimmed; else echo drift; fi
}
