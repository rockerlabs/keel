# shellcheck shell=bash
# tools/lib/core-ownership.sh — keel/CORE.md's ownership predicate (dir #363, split from dir #278).
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
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
