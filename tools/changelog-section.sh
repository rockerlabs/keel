#!/usr/bin/env bash
# changelog-section — adopter-usable (dir #68): operates on any repo's own CHANGELOG.md, resolved
# relative to this script's own location, with nothing keel-specific hardcoded. Prints the
# `## [x.y.z]` section body for a given released version, so the
# manual "go find and copy the section out of CHANGELOG.md" step in docs/publishing-checklist.md §4
# has a deterministic replacement. This is an INPUT to writing release notes, not the note itself:
# release notes are a curated digest (v0.6.0's body was ~3.7KB) while a full section can run to
# ~31KB (v0.6.1) — see dir #162's "Scope correction". Intended usage:
#   tools/changelog-section.sh <version> > /tmp/notes-draft.md && eval "${EDITOR:?set the EDITOR environment variable first} /tmp/notes-draft.md" \
#     && cp /tmp/notes-draft.md <notes-file>
#   tools/changelog-section.sh <version> --digest    # opener + ### headings only, for skimming
#
# Usage:
#   tools/changelog-section.sh <version> [--digest]
#
#   <version>  bare semver, e.g. 0.6.1 (no leading `v` — matches the `## [x.y.z]` bracket text)
#   --digest   print only the section's opening prose (everything before its first `### ` heading)
#              plus the `### ` heading lines themselves, not the full body
set -euo pipefail

version="${1:?usage: changelog-section.sh <version> [--digest]}"
mode="${2:-}"
[ "$#" -le 2 ] || { echo "changelog-section: unexpected extra argument(s): ${*:3}" >&2; exit 1; }

# Anchored ERE, not a bash glob (`[0-9]*.[0-9]*.[0-9]*` would also accept "0.6.1abc" or
# "1.2.3+(x)" — `*` matches any characters, not just digits, and a permissive match here would let
# unescaped regex metacharacters reach the `grep -E` heading search below). Same strictness as
# tools/self/doctor.sh's own tag filter.
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "changelog-section: version must be bare semver (e.g. 0.6.1, no leading v): $version" >&2
  exit 1
fi
case "$mode" in
  ""|--digest) : ;;
  *) echo "changelog-section: unknown option: $mode" >&2; exit 1 ;;
esac

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
