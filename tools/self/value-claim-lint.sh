#!/usr/bin/env bash
# tools/self/value-claim-lint.sh — keel-self-maintenance (dir #672): a groom plan's value claim
# with no derived subject set was G6's top finding five grooms running (0.12.0 through 0.16.0),
# and the prose rule in docs/grooming.md G5 did not prevent a repeat. This lints the plan before
# G6 so the reviewer's budget goes to what a lint cannot see. It reads RELEASES.md (gitignored,
# main-checkout-only, so never shipped — install.sh does not carry this file) and flags every
# value-claim cell that lacks a `Subject set:` clause or an explicit `no subject set — <why>` line.
#
# What it reads — a plan section is a `## v<X.Y.Z> — ...` heading up to the next `## ` heading:
#   - a table row whose first cell starts `value claim` (any suffix: "(release)", "(falsifiable)",
#     "(subject set derived, then diffed)"); the whole row is the cell; and
#   - a prose list introduced by a `**Value claims ...**` line (the 0.16.0 plan's shape): each
#     top-level `- ` bullet, with its indented continuation lines, is one cell.
# Not covered: a claim written as free prose or a numbered list with no such lead-in (the 0.13.0
# plan's "Value claim — stated to be checkable" block). A section with no covered cell prints a
# notice instead of a silent pass, so the gap is visible.
#
# A cell passes if it carries ANY of docs/grooming.md G5's own forms (case-insensitive):
#   - `Subject set:` followed by text — the label;
#   - the three-part vocabulary G5 prescribes ("the source that defines Y ... the diff of that set
#     against the slate's live ticket list ... and the residue stated on the row by number"): a
#     `Residue:` clause is the part every compliant plan states (a row with an empty residue says
#     so), so `residue` followed by `:`, `=` or `—` passes — a plan written "source = ... diff ...
#     Residue: ..." is compliant and must not be flagged on wording alone. The source and the diff
#     are NOT checked on their own: a cell naming them but no residue is flagged;
#   - the words `no claim` ("carried-over theme, no claim beyond the release-level drain") — a row that
#     makes no claim has no set to bind; or
#   - `no subject set —` followed by a reason.
# A bare mention of "subject set" with none of these does not count. This vocabulary tracks G5; if
# G5's wording changes, change the `ok()` patterns below and the fixture per form in the test.
#
# Usage:
#   tools/self/value-claim-lint.sh [RELEASES_PATH] [VERSION]
#   tools/self/value-claim-lint.sh -h | --help
# VERSION (e.g. 0.14.0, a leading `v` allowed) limits the check to that release's plan section(s);
# without it every `## v<X.Y.Z>` section is checked. RELEASES_PATH defaults to the MAIN checkout's
# RELEASES.md (the same resolution pool-report.sh uses for BACKLOG.md).
#
# Always exits 0 (advisory — run at G5 before G6); a missing/unreadable RELEASES.md is a skip,
# not an error, like every keel-self-maintenance check that reads a gitignored file.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$self_dir/../.." && pwd)"

# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"
# shellcheck source=tools/lib/backlog-blocks.sh
. "$self_dir/../lib/backlog-blocks.sh"

releases_arg=""
version=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Usage: value-claim-lint.sh [RELEASES_PATH] [VERSION]

Flags every value-claim cell in a RELEASES.md plan section that carries none of G5's forms: a
`Subject set:` clause, a `Residue:` clause (the source/diff/residue vocabulary), `no claim ...`,
or `no subject set — <why>` (dir #672). Covers `| value claim ... |` table rows and
the bullets under a `**Value claims ...**` lead-in. VERSION (e.g. 0.14.0) limits the check to
that release's section. Advisory: always exits 0.
EOF
      exit 0 ;;
    -*)
      echo "value-claim-lint: unknown flag: $1" >&2
      exit 2 ;;
    *)
      if [ -z "$releases_arg" ]; then releases_arg="$1"
      elif [ -z "$version" ]; then version="${1#v}"
      else echo "value-claim-lint: too many arguments" >&2; exit 2
      fi
      shift ;;
  esac
done

if [ -n "$releases_arg" ]; then
  releases_file="$releases_arg"
else
  releases_file="$(backlog_root_for "$repo_root")/RELEASES.md"
fi

if [ ! -f "$releases_file" ] || [ ! -r "$releases_file" ]; then
  echo "value-claim-lint: no readable RELEASES.md at $releases_file — skipped, not a failure"
  exit 0
fi

# Fenced code is blanked in place (line numbers survive), so an example row inside a fence is not
# a claim.
blank_fenced_blocks "$releases_file" | awk -v want="$version" '
  function ok(t,   l) {
    sub(/[ \t]*\|[ \t]*$/, "", t)   # a table row ends in its closing pipe, which is not a reason
    sub(/^\|[^|]*\|/, "", t)         # a table row: judge the claim cell, not its label cell
    sub(/^- \*\*[^*]*\*\*/, "", t)    # a bullet: likewise, not its bold label ("**Row A:**")
    l = tolower(t)
    return (l ~ /subject set: *[^ ]/ || l ~ /no subject set — *[^ ]/ || l ~ /(^|[^a-z])residue *(:|=|—)/ || l ~ /(^|[^a-z])no claim([^a-z]|$)/)
  }
  function judge(t, at) {
    cells++
    if (!ok(t)) {
      flagged++
      printf "  FLAG  %s line %d: %s\n", ver, at, substr(t, 1, 90)
    }
  }
  function flush() { if (bullet != "") judge(bullet, bullet_at); bullet = "" }
  /^## / {
    flush(); in_list = 0
    in_sec = 0
    if ($0 ~ /^## v[0-9]/) {
      ver = $2
      if (want == "" || ver == "v" want) { in_sec = 1; sections++ }
    }
    next
  }
  !in_sec { next }
  in_list {
    if ($0 ~ /^- /) { flush(); bullet = $0; bullet_at = NR; next }
    if ($0 ~ /^  / && bullet != "") { bullet = bullet " " $0; next }
    if ($0 ~ /^[ \t]*$/) next   # a blank line neither ends the list nor the pending bullet
    flush(); in_list = 0               # an unindented paragraph does
  }
  /^\*\*[Vv]alue claims/ { in_list = 1; next }
  tolower($0) ~ /^\| *\**value claim/ { judge($0, NR) }
  END {
    flush()
    printf "value-claim-lint: %d plan section(s), %d value-claim cell(s), %d lacking a subject set\n", sections, cells, flagged
    if (sections == 0) print "  (no plan section matched" (want != "" ? " v" want : "") ")"
    else if (cells == 0) print "  (no covered value-claim cell found — table rows and **Value claims** bullets only; check the section by eye)"
  }
'
