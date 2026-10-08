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
# REQUIRED for all three consumers — install.sh, uninstall.sh and tools/doctor.sh — each GUARDED
# (`[ -s ] && bash -n` pre-check, one actionable message, exit 1), matching tools/lib/manifest.sh's own
# contract. Refusing outright on a missing or corrupted copy is the right failure mode, not a silent
# degrade: an ownership decision needs a real predicate, and there is exactly one definition of it.
#
# dir #716 (B12 of docs/specs/685-symlink-policy.md) adds the in-file marker definition below: the ONE
# anchored way to find the embedded KEEL-CORE block, for every reader, writer and presence check.
# A prose line that merely MENTIONS a marker ("never edit inside KEEL-CORE-BEGIN by hand") is not a
# marker, and used to make the uninstall strip and the refresh delete everything after it.

# The marker lines. A BEGIN line starts at column 0 with `<!-- KEEL-CORE-BEGIN` and ends with `-->`
# (trailing whitespace allowed, so a CRLF file still matches); the END line is `<!-- KEEL-CORE-END -->`
# at column 0. Both shipped forms match (CORE.md's `<!-- KEEL-CORE-BEGIN -->` and templates/CLAUDE.md's
# `<!-- KEEL-CORE-BEGIN — rails below … -->`). POSIX ERE: the same strings go to grep -E and, through
# ENVIRON (never -v, whose escape processing would mangle them), to awk — hence exported.
KEEL_CORE_BEGIN_RE='^<!-- KEEL-CORE-BEGIN.*-->[[:space:]]*$'
KEEL_CORE_END_RE='^<!-- KEEL-CORE-END -->[[:space:]]*$'
export KEEL_CORE_BEGIN_RE KEEL_CORE_END_RE

# keel_core_has_block FILE — true iff FILE holds a BEGIN marker line: the one presence check.
keel_core_has_block() {
  grep -qE "$KEEL_CORE_BEGIN_RE" "$1" 2>/dev/null
}

# keel_core_block_check FILE — 0 when FILE holds no marker line at all (no block: nothing to refuse) or
# exactly one BEGIN followed later by exactly one END; 1, with ONE line on stderr, for anything else
# (two blocks, a BEGIN without an END, an END alone, the markers out of order). A write that touches the
# block calls this first and changes nothing on a 1 — it cannot tell which lines the user meant.
keel_core_block_check() {
  local seq
  seq="$(awk '
    BEGIN { b = ENVIRON["KEEL_CORE_BEGIN_RE"]; e = ENVIRON["KEEL_CORE_END_RE"] }
    $0 ~ b { seq = seq (seq == "" ? "" : ",") "BEGIN"; next }
    $0 ~ e { seq = seq (seq == "" ? "" : ",") "END" }
    END { print seq }
  ' "$1" 2>/dev/null)" || seq="unreadable"
  case "$seq" in
    ""|"BEGIN,END") return 0 ;;
  esac
  echo "keel: $1: left untouched — its KEEL-CORE markers are not exactly one BEGIN followed by one END (found: $seq); fix or remove them by hand" >&2
  return 1
}

# keel_core_block_replace FILE [REPLACEMENT] — FILE on stdout with its KEEL-CORE block (markers
# included) swapped for REPLACEMENT (multi-line allowed; empty or absent = the block removed). A file
# with no BEGIN line passes through unchanged. Returns 1 (printing nothing) on markers that are not one
# balanced block, so a writer that forgot keel_core_block_check still cannot rewrite such a file; callers
# run the check first to get its one-line explanation. Meant as the CMD of keel_write_through's command
# form, where a failing CMD leaves the file untouched.
keel_core_block_replace() {
  keel_core_block_check "$1" 2>/dev/null || return 1
  KEEL_CORE_REPL="${2-}" awk '
    BEGIN { b = ENVIRON["KEEL_CORE_BEGIN_RE"]; e = ENVIRON["KEEL_CORE_END_RE"]; r = ENVIRON["KEEL_CORE_REPL"] }
    !skip && $0 ~ b { if (r != "") print r; skip = 1; next }
    skip && $0 ~ e  { skip = 0; next }
    !skip
  ' "$1"
}

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
  keel_core_block_full "$1" | sed '1d;$d'
}

# keel_core_block_full FILE — the block WITH its marker lines (the first BEGIN through the next END).
keel_core_block_full() {
  awk '
    BEGIN { b = ENVIRON["KEEL_CORE_BEGIN_RE"]; e = ENVIRON["KEEL_CORE_END_RE"] }
    !inb && !done && $0 ~ b { inb = 1; print; next }
    inb && $0 ~ e           { print; inb = 0; done = 1; next }
    inb
  ' "$1"
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
