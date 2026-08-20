#!/usr/bin/env bash
# changelog-section — adopter-usable (dir #68): operates on any repo's own CHANGELOG.md, resolved
# relative to this script's own location, with nothing keel-specific hardcoded. Prints the
# `## [x.y.z]` section body for a given released version, so the
# manual "go find and copy the section out of CHANGELOG.md" step in docs/publishing-checklist.md §4
# has a deterministic replacement. This is an INPUT to writing release notes, not the note itself:
# release notes are a curated digest (v0.6.0's body was ~3.7KB) while a full section can run to
# ~31KB (v0.6.1) — see dir #162's "Scope correction". `--edit` (dir #189) folds the former by-hand
# compose recipe — redirect to a scratch file, launch $EDITOR, copy on success — into tested code:
# every real bug found across dir #162's own review rounds lived in that untested shell prose, never
# in the tested extraction code, so the mechanism moved here rather than staying hand-typed in
# docs/publishing-checklist.md.
#
# Usage:
#   tools/changelog-section.sh <version> [--digest]
#   tools/changelog-section.sh --edit <version> <notes-file>
#   tools/changelog-section.sh -h | --help
#
#   <version>   bare semver, e.g. 0.6.1 (no leading `v` — matches the `## [x.y.z]` bracket text)
#   --digest    print only the section's opening prose (everything before its first `### ` heading)
#               plus the `### ` heading lines themselves, not the full body
#   --edit      extract the section to a scratch file, open it in $EDITOR, and copy the result to
#               <notes-file> only if the editor exits 0 — <notes-file> is never touched otherwise
set -euo pipefail

usage() {
  cat <<'EOF'
usage: changelog-section.sh <version> [--digest]
       changelog-section.sh --edit <version> <notes-file>
       changelog-section.sh -h | --help

Print the `## [x.y.z]` section body of CHANGELOG.md for a released version — an input to writing
release notes, not the note itself (release notes are a curated digest, not a raw copy).

  <version>   bare semver, e.g. 0.6.1 (no leading v)
  --digest    print only the section's opening prose plus its `### ` heading lines
  --edit      compose <notes-file> interactively: extract the section to a scratch file, launch
              $EDITOR on it, and copy the result to <notes-file> only if the editor exits 0
  -h, --help  this message
EOF
}

die_usage() { echo "changelog-section: $1" >&2; exit 2; }

mode=""
notes_file=""
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --edit)
    [ "$#" -eq 3 ] || die_usage "--edit needs <version> <notes-file> (see --help)"
    version="$2"
    notes_file="$3"
    mode="--edit"
    ;;
  *)
    [ "$#" -ge 1 ] || die_usage "missing <version> (see --help)"
    version="$1"
    mode="${2:-}"
    [ "$#" -le 2 ] || die_usage "unexpected extra argument(s): ${*:3}"
    case "$mode" in
      ""|--digest) : ;;
      *) die_usage "unknown option: $mode" ;;
    esac
    ;;
esac

# Anchored ERE, not a bash glob (`[0-9]*.[0-9]*.[0-9]*` would also accept "0.6.1abc" or
# "1.2.3+(x)" — `*` matches any characters, not just digits, and a permissive match here would let
# unescaped regex metacharacters reach the `grep -E` heading search below). Same strictness as
# tools/self/doctor.sh's own tag filter.
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die_usage "version must be bare semver (e.g. 0.6.1, no leading v): $version"
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
changelog_file="$repo_root/CHANGELOG.md"
[ -f "$changelog_file" ] || { echo "changelog-section: $changelog_file not found" >&2; exit 1; }

# Same fence-blanking convention as tools/self/doctor.sh's `blank_fenced_blocks` (checks 5 and 6):
# blank, don't delete, so line numbers stay aligned, and a `## [x.y.z]`-shaped line living inside a
# fenced example (this file documents its own release-note conventions) isn't mistaken for a real
# section heading. Duplicated rather than shared per dir #26's standing, deliberate "capture only, do
# not pre-build a shared lib" call — this is now a further site on that list. Deliberately NOT the
# tools/lib/fence-blank.sh shared copy dir #169 introduced for doctor.sh/prose-drift.sh: THIS script
# is meant to be copy-portable on its own (tests/test_changelog_section.sh's own fixture copies only
# this one file into a sandbox to prove exactly that), and sourcing a sibling lib would break it —
# tests/test_fence_blank_lib.sh's duplicate-scan knows to allowlist this file for that reason.
blanked="$(awk '/^[[:space:]]*(```|~~~)/ { infence = !infence; print ""; next } infence { print ""; next } { print }' "$changelog_file")"

# Locate the target heading and the next `## ` heading after it (any shape — [Unreleased] or another
# version — marks the end of this section), same heading grammar doctor.sh's check 6 already parses.
escaped_version="$(printf '%s' "$version" | sed 's/[.[\*^$/]/\\&/g')"
heading_re="^## \\[${escaped_version}\\]"

start_line="$(grep -nE "$heading_re" <<< "$blanked" | head -1 | cut -d: -f1 || true)"
[ -n "$start_line" ] || { echo "changelog-section: no \`## [$version]\` section found in $changelog_file" >&2; exit 1; }

next_line="$(tail -n "+$((start_line + 1))" <<< "$blanked" | grep -nE '^## ' | head -1 | cut -d: -f1 || true)"
if [ -n "$next_line" ]; then
  end_line=$((start_line + next_line - 1))
else
  end_line='$'
fi
section="$(sed -n "${start_line},${end_line}p" "$changelog_file")"

if [ "$mode" = "--edit" ]; then
  # The compose recipe itself, formerly hand-typed shell prose in docs/publishing-checklist.md §4
  # (dir #189): extract to a mktemp scratch file, guard $EDITOR being unset with a message that
  # spells the variable name out in plain words (no `$` sigil) — no single backslash-escaping of a
  # `$VAR`-shaped word renders correctly in both bash and zsh, dir #162's own fix for the standalone
  # recipe — launch it via `eval` so a flag-carrying $EDITOR (e.g. "code --wait") re-splits correctly
  # in both shells, then copy the draft to <notes-file> only if the editor exits 0.
  : "${EDITOR:?set the EDITOR environment variable first, no shell metacharacters}"
  scratch_file="$(mktemp)"
  trap 'rm -f "$scratch_file"' EXIT
  printf '%s\n' "$section" > "$scratch_file"
  # A nonzero editor exit doesn't necessarily mean nothing was typed — a --wait wrapper's own
  # housekeeping failing, a window-close race, or a Ctrl-C can all leave real, curated content
  # sitting in $scratch_file. Cancel the cleanup trap on this path too (same reasoning as the
  # cp-failure branch below), so an editor failure never silently destroys work the user already did.
  if ! eval "$EDITOR \"\$scratch_file\""; then
    trap - EXIT
    echo "changelog-section: \$EDITOR exited with an error — your draft, if any, is preserved at $scratch_file" >&2
    exit 1
  fi
  # `--` guards against a flag-shaped <notes-file> (e.g. `--digest`) being read as a `cp` option —
  # BSD and GNU `cp` disagree on unknown long options, so an unguarded `cp` would silently create a
  # file literally named `--digest` on one platform and abort on the other. On a `cp` failure, cancel
  # the cleanup trap so the user's edited draft survives at $scratch_file instead of being discarded
  # along with their work.
  if ! cp -- "$scratch_file" "$notes_file"; then
    trap - EXIT
    echo "changelog-section: could not write $notes_file — your edited draft is preserved at $scratch_file" >&2
    exit 1
  fi
  exit 0
fi

if [ "$mode" = "--digest" ]; then
  # Opener = everything before the section's first REAL `### ` heading; then the `### ` heading
  # lines themselves. Heading detection runs against the same fence-blanked slice used for the `##`
  # boundary above (not against `$section`, which is sliced from the raw file) — a `### `-shaped
  # line inside a fenced example within this section must not be mistaken for a real subheading
  # either, same reasoning as the `##` boundary check just above it.
  section_blanked="$(sed -n "${start_line},${end_line}p" <<< "$blanked")"
  sub_lines="$(grep -nE '^### ' <<< "$section_blanked" | cut -d: -f1 || true)"
  first_sub_line="$(head -1 <<< "$sub_lines")"
  if [ -n "$first_sub_line" ]; then
    sed -n "1,$((first_sub_line - 1))p" <<< "$section"
    while IFS= read -r n; do
      [ -n "$n" ] && sed -n "${n}p" <<< "$section"
    done <<< "$sub_lines"
  else
    printf '%s\n' "$section"
  fi
else
  printf '%s\n' "$section"
fi
