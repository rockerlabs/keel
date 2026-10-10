#!/usr/bin/env bash
# tools/self/changelog-cut.sh — keel-self-maintenance (dir #68): the release cut's CHANGELOG transform,
# as one deterministic command instead of prose. There is no consumer-facing counterpart and install.sh
# never ships this file. dir #744 slice 1 (B17): since a PR's changelog entry is a fragment under
# `changelog.d/` (tools/self/changelog-fragments.sh is its one reader), the cut has to carry the fragments
# into CHANGELOG.md; "rename the heading by hand" no longer covers that, and a prose recipe is exactly
# what dir #722 found failing.
#
# Usage:
#   tools/self/changelog-cut.sh [--repo DIR] VERSION DATE
#   tools/self/changelog-cut.sh -h | --help
#
# VERSION is `x.y.z`, DATE is `YYYY-MM-DD`. On success, in order:
#   1. appends changelog-fragments.sh's output after the last non-blank line of `## [Unreleased]`'s body
#      (one blank line between that body and the fragments, and between two fragments);
#   2. renames that heading to `## [VERSION] — DATE`;
#   3. inserts a fresh, empty `## [Unreleased]` above it;
#   4. deletes the fragment files (README.md stays).
# The new text is built in a temp file and written OVER CHANGELOG.md with `cat tmp > CHANGELOG.md` — never
# `mv`/`cp` of a fresh mktemp file onto it, which would give the changelog the temp file's 0600 (busybox
# `cp` onto an existing file also takes the SOURCE's mode; CLAUDE.md Linux trap 6). The script never runs
# git — the result is an ordinary working-tree edit for the cut PR to commit. Each step is printed.
#
# Exit 0 done. Exit 2 REFUSED, changing nothing: a bad VERSION or DATE, no CHANGELOG.md, not exactly one
# `## [Unreleased]` heading (fenced examples do not count), a `## [VERSION]` heading already present, or
# `changelog-fragments.sh --check` failing. A `## [VERSION]` already present while fragment files are
# still on disk: the refusal labels each fragment `assembled` (every one of its top-level bullet lines
# already appears verbatim in that section — a cut that stopped before deleting it; delete the file) or `late` (it does
# not — merged after the cut ran; append it to that section by hand, then delete it). Running the cut
# twice therefore refuses the second time.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

export LC_ALL=C

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

refuse() { echo "changelog-cut.sh: refused — $1" >&2; echo "changelog-cut.sh: nothing was changed" >&2; exit 2; }
die_args() { echo "changelog-cut.sh: $1" >&2; echo "usage: changelog-cut.sh [--repo DIR] VERSION DATE" >&2; exit 2; }

repo_dir="$(cd "$self_dir/../.." && pwd)"
pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    --repo)
      [ $# -ge 2 ] || die_args "--repo needs a directory"
      repo_dir="$2"; shift 2 ;;
    -*) die_args "unknown flag '$1'" ;;
    *) pos+=("$1"); shift ;;
  esac
done
[ "${#pos[@]}" -eq 2 ] || die_args "expected VERSION and DATE, got ${#pos[@]} argument(s)"
version="${pos[0]}"
date_str="${pos[1]}"
[ -d "$repo_dir" ] || die_args "no such directory: $repo_dir"

grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$version" || refuse "VERSION '$version' is not x.y.z"
grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' <<< "$date_str" \
  || refuse "DATE '$date_str' is not YYYY-MM-DD"

changelog="$repo_dir/CHANGELOG.md"
[ -f "$changelog" ] || refuse "no CHANGELOG.md in $repo_dir"
reader="$self_dir/changelog-fragments.sh"

# Headings are located on a fence-blanked copy (line-aligned with the file): a `## [Unreleased]` inside a
# fenced example is not a section.
blanked="$(blank_fenced_blocks "$changelog")"
# An odd number of fence markers would leave that blanking stuck "in fence" to the end of the file, hiding
# every later heading: refuse rather than guess where [Unreleased] ends.
fence_marks="$(grep -cE '^[[:space:]]*(```|~~~)' "$changelog" || true)"
[ $((fence_marks % 2)) -eq 0 ] || refuse "CHANGELOG.md has an odd number of fence markers ($fence_marks) — an unclosed fenced block hides every later heading; close it first"
unreleased_count="$(grep -c '^## \[Unreleased\]' <<< "$blanked" || true)"
[ "$unreleased_count" = 1 ] || refuse "CHANGELOG.md has $unreleased_count '## [Unreleased]' headings, expected exactly 1"

# The fragments, by the reader's own listing (no second listing of changelog.d/ here): the text to carry
# and the names to delete, space-separated (kebab-case names have no spaces).
if frag_text="$("$reader" --repo "$repo_dir")"; then :; else refuse "could not read changelog.d/"; fi
if frag_list="$("$reader" --repo "$repo_dir" --list)"; then :; else refuse "could not list changelog.d/"; fi
frag_files=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  frag_files="$frag_files${frag_files:+ }${f#changelog.d/}"
done <<< "$frag_list"

# The lint first: a malformed fragment (empty, headings, unbalanced fence) can be neither carried nor honestly
# labelled assembled/late below.
if check_out="$("$reader" --repo "$repo_dir" --check)"; then :; else
  refuse "changelog-fragments.sh --check fails:
$check_out"
fi

if grep -qE "^## \[${version//./\\.}\]" <<< "$blanked"; then
  if [ -n "$frag_files" ]; then
    # The body of the existing ## [VERSION], to tell a fragment already carried into it from one that
    # arrived after the cut ran.
    section="$(awk -v h="## [$version]" 'index($0, h) == 1 { on = 1; next } on && /^## / { exit } on { print }' <<< "$blanked")"
    labelled=""
    for f in $frag_files; do
      # assembled = EVERY top-level bullet line of the fragment is already in the section; one missing and
      # deleting the file would lose content, so it reads as late.
      assembled=1
      while IFS= read -r bullet; do
        grep -qxF -- "$bullet" <<< "$section" || { assembled=0; break; }
      done < <(grep '^- ' "$repo_dir/changelog.d/$f" || true)
      if [ "$assembled" = 1 ]; then
        labelled="$labelled
  changelog.d/$f — assembled (every bullet is already in [$version]: a cut stopped before deleting it; delete the file)"
      else
        labelled="$labelled
  changelog.d/$f — late (not in [$version]: merged after the cut ran; append it to that section by hand, then delete the file)"
      fi
    done
    refuse "## [$version] is already in CHANGELOG.md and fragment files remain:$labelled"
  fi
  refuse "## [$version] is already in CHANGELOG.md"
fi

# --- build the new file --------------------------------------------------------------------------
tmp="$changelog.cut.$$"
trap 'rm -f "$tmp"' EXIT

# Line numbers: the Unreleased heading and the next `## ` heading after it (or end of file) are found on the
# fence-blanked copy (same numbering as the file); the last non-blank line of the body between them is found
# on the RAW file, so a body that ends in a fenced block keeps its fence.
u_line="$(grep -n '^## \[Unreleased\]' <<< "$blanked" | head -n 1 | cut -d: -f1)"
# awk's NR counts an unterminated last line too (wc -l would undercount it).
total="$(awk 'END { print NR }' "$changelog")"
next_line="$(awk -v u="$u_line" 'NR > u && /^## / { print NR; exit }' <<< "$blanked")"
[ -n "$next_line" ] || next_line=$((total + 1))
last_body="$(awk -v u="$u_line" -v e="$next_line" 'BEGIN { last = u } NR > u && NR < e && /[^[:space:]]/ { last = NR } END { print last }' "$changelog")"

{
  # Everything above the heading, then the fresh empty section.
  [ "$u_line" -gt 1 ] && sed -n "1,$((u_line - 1))p" "$changelog"
  printf '## [Unreleased]\n\n'
  printf '## [%s] — %s\n' "$version" "$date_str"
  # The old body through its last non-blank line (the heading's own blank line comes along with it).
  if [ "$last_body" -gt "$u_line" ]; then
    sed -n "$((u_line + 1)),${last_body}p" "$changelog"
  elif [ -n "$frag_text" ]; then
    printf '\n'
  fi
  if [ -n "$frag_text" ]; then
    [ "$last_body" -gt "$u_line" ] && printf '\n'
    printf '%s\n' "$frag_text"
  fi
  # A blank line, then whatever followed the section (the next release heading onward).
  if [ "$next_line" -le "$total" ]; then
    printf '\n'
    sed -n "${next_line},\$p" "$changelog"
  fi
} > "$tmp"

# Written over the existing file, so its mode survives (see the header).
cat "$tmp" > "$changelog"
echo "changelog-cut.sh: CHANGELOG.md: appended ${frag_files:+fragments ($frag_files) and }renamed [Unreleased] to [$version] — $date_str, opened a fresh empty [Unreleased]"

for f in $frag_files; do
  rm -f "$repo_dir/changelog.d/$f"
  echo "changelog-cut.sh: deleted changelog.d/$f"
done
[ -n "$frag_files" ] || echo "changelog-cut.sh: no fragments to carry"
echo "changelog-cut.sh: done — curate the new section by hand, then commit (this script never runs git)"
