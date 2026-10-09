#!/usr/bin/env bash
# tools/self/changelog-fragments.sh — keel-self-maintenance (dir #68): the ONE reader of
# `changelog.d/` for keel's own repo. There is no consumer-facing counterpart and install.sh never ships
# this file. dir #744 slice 1 (B4a): a PR's changelog entry is a new file `changelog.d/<ticket>-<slug>.md`
# instead of a bullet under `CHANGELOG.md`'s `## [Unreleased]`, so two PRs stop colliding at that one
# anchor. Every reader of fragments goes through this script — doctor.sh (check 7), changelog-cut.sh (the
# cut), the tests that pin a changelog cite, and `changelog.d/README.md`'s examples — so no second
# listing of the directory exists to drift from this one.
#
# Usage:
#   tools/self/changelog-fragments.sh [--repo DIR] [--check]
#   tools/self/changelog-fragments.sh -h | --help
#
# Default: print every fragment's text — each `changelog.d/*.md` except README.md, in `LC_ALL=C` filename
# order (never mtime order), one blank line between fragments. No `changelog.d/`, or no fragments:
# empty output, exit 0 — a project without fragments is unaffected.
#
# --check: print nothing and exit 0 when every entry of `changelog.d/` passes; otherwise one line per
# failure, `changelog.d/<file>:<line>: <reason>`, exit 1. The rules (docs: changelog.d/README.md):
#   - anything besides README.md must be a regular, non-empty `*.md` file named
#     `<ticket>-<slug>.md` (ticket = digits) or `<slug>.md`, the slug lowercase kebab-case;
#   - the first non-blank line starts `- `; a non-blank line that does not start `- ` is a continuation
#     line and must be indented; no line starts with `#` (a heading would split the cut's section);
#   - a markdown link target is root-anchored (`/docs/x.md`) or an absolute http(s)/mailto URL —
#     tools/self/prose-drift.sh resolves a bare relative target beside the linking file, so
#     `docs/x.md` is dead from inside `changelog.d/` while the cut moves the text into CHANGELOG.md
#     verbatim (a link inside an inline `code span` or a fenced block is an example, not a link).
#
# Exit codes: 0 ok · 1 --check found a failure · 2 bad arguments or an unreadable repo.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

# Filename order is the contract (B4): a locale-dependent collation would make the assembled changelog
# depend on the operator's machine.
export LC_ALL=C

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

die_args() { echo "changelog-fragments.sh: $1" >&2; echo "usage: changelog-fragments.sh [--repo DIR] [--check]" >&2; exit 2; }

repo_dir="$(cd "$self_dir/../.." && pwd)"
check=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    --repo)
      [ $# -ge 2 ] || die_args "--repo needs a directory"
      repo_dir="$2"; shift 2 ;;
    --check) check=1; shift ;;
    *) die_args "unknown argument '$1'" ;;
  esac
done
[ -d "$repo_dir" ] || die_args "no such directory: $repo_dir"

frag_dir="$repo_dir/changelog.d"
# No changelog.d/ at all is the adopter / pre-slice-1 case: nothing to read, nothing to lint.
[ -d "$frag_dir" ] || exit 0

# Every entry of the directory, one per line, sorted — dotfiles included (`ls -A`), so a stray `.keep` or
# editor swap file is named by --check instead of hiding. A newline inside a name is not supported (it is
# not kebab-case either, so --check would name its pieces).
entries="$(ls -A "$frag_dir" | sort)"

# is_fragment NAME — a name the reader prints: `*.md` that is not README.md, and a regular file.
is_fragment() {
  case "$1" in README.md) return 1 ;; *.md) [ -f "$frag_dir/$1" ] ;; *) return 1 ;; esac
}

if [ "$check" = 0 ]; then
  first=1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    is_fragment "$name" || continue
    [ "$first" = 1 ] || printf '\n'
    first=0
    # Text with trailing blank lines dropped, so exactly one blank line separates two fragments
    # whatever the file ends with. awk, not sed `$d` tricks: portable to BSD/busybox.
    awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }' \
      "$frag_dir/$name"
  done <<< "$entries"
  exit 0
fi

bad=0
fail() { printf 'changelog.d/%s:%s: %s\n' "$1" "$2" "$3"; bad=1; }

while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ "$name" = README.md ] && continue
  path="$frag_dir/$name"
  # B1 name: `<ticket>-<slug>.md` or `<slug>.md`; digits for the ticket, lowercase kebab-case slug. A
  # digits-only stem (`744.md`) reads as a slug, which is fine — it is still a unique, kebab-valid name.
  if [ ! -f "$path" ]; then
    fail "$name" 1 "not a regular file — changelog.d/ holds only README.md and fragment files"
    continue
  fi
  case "$name" in
    *.md) ;;
    *) fail "$name" 1 "not a .md file — changelog.d/ holds only README.md and *.md fragments"; continue ;;
  esac
  stem="${name%.md}"
  if ! grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' <<< "$stem"; then
    fail "$name" 1 "name is not kebab-case — use <ticket>-<slug>.md (lowercase, digits and hyphens only)"
  fi
  if ! grep -q '[^[:space:]]' "$path"; then
    fail "$name" 1 "empty file — a fragment holds at least one bullet"
    continue
  fi
  # Fence- and inline-code-blanked copy, line-aligned with the file: links are judged on this, the rest
  # on the raw lines.
  blanked="$(blank_fenced_blocks "$path" | blank_inline_code_spans)"
  seen_first=0
  ln=0
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln + 1))
    case "$line" in
      *[![:space:]]*) ;;
      *) continue ;;
    esac
    if [ "$seen_first" = 0 ]; then
      seen_first=1
      case "$line" in
        '- '*) ;;
        *) fail "$name" "$ln" "first non-blank line must start with '- ' (a bullet), exactly as it would sit under ## [Unreleased]"; continue ;;
      esac
    fi
    case "$line" in
      '#'*) fail "$name" "$ln" "line starts with '#' — a fragment holds bullets only, no headings" ;;
      '- '*|[[:space:]]*) ;;
      *) fail "$name" "$ln" "continuation line must be indented" ;;
    esac
  done < "$path"
  # Link targets, on the blanked copy. `](` followed by anything up to the closing paren; a target that is
  # neither root-anchored nor an absolute http(s)/mailto URL would resolve beside the fragment.
  ln=0
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln + 1))
    rest="$line"
    while :; do
      case "$rest" in
        *']('*) ;;
        *) break ;;
      esac
      rest="${rest#*](}"
      target="${rest%%)*}"
      case "$target" in
        /*|http://*|https://*|mailto:*) ;;
        *) fail "$name" "$ln" "link target '$target' is file-relative — write it root-anchored (/docs/x.md): prose-drift resolves a bare target beside changelog.d/" ;;
      esac
    done
  done <<< "$blanked"
done <<< "$entries"

exit "$bad"
