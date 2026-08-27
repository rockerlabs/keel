#!/usr/bin/env bash
# tools/self/citation-resolvability.sh — keel-self-maintenance (dir #68 exemption, per
# tools/self/prose-drift.sh's header): checks that every `dir #N` cited in KEEL'S OWN tracked docs
# resolves to exactly one ticket. There is no consumer-facing counterpart and install.sh never ships
# this file.
#
# Filed dir #266, 2026-08-27, after a day in which three separate tickets were filed for citations
# that looked resolvable and were not (dir #64's two-tickets-one-number collision, fixed as dir #259).
# This subsumes dir #259: a duplicate `### dir #N` heading is exactly what makes citations of that
# number ambiguous, so the cause (duplicate heading) and the consequence (ambiguous citation) are one
# check, not two.
#
# WHERE the ticket sources live, and why this can be neither a CI check nor a tools/self/doctor.sh
# leg: `BACKLOG.md` is gitignored and exists ONLY at the main checkout (never a worktree — dir #34).
# The second source, the closed-ticket archive index, lives entirely outside the repo, at
# ~/.claude/projects/<slugified-repo-path>/CLAUDE-archive.md (Claude Code's own memory convention —
# BACKLOG.md:1255 names this exact path). A worktree run, or a CI run, has neither file on disk. Both
# absences degrade SILENTLY (a skip line, exit 0) rather than failing — the same shape as its sibling
# tools/self/shellcheck-targets.sh, which this script's REPO_DIR default also borrows for test-sandbox
# use.
#
# The trap this exists to avoid: a version that reads ONLY BACKLOG.md false-positives on every ticket
# a cooldown sweep has moved to the archive. dir #202 is the worked example — zero headings in
# BACKLOG.md, one line in the archive, and NOT dead. A citation is resolvable if it resolves in
# EITHER source; only BACKLOG.md's own live `### dir #N` headings count toward ambiguity (two or more
# means dir #259's collision has recurred), since the archive accumulates repeated closure-sweep
# blocks by design and a citation appearing there more than once is not a fresh ambiguity.
#
# Usage:
#   tools/self/citation-resolvability.sh [REPO_DIR] [--quiet]
#   tools/self/citation-resolvability.sh -h | --help
#
# REPO_DIR defaults to the current directory and must be the MAIN CHECKOUT (the one with BACKLOG.md
# at its root) to do anything useful; run from a worktree it degrades to the skip line below.
#
# Env overrides (test isolation, same shape as KEEL_IMPACT_LOG et al. in tests/lib.sh):
#   KEEL_CITATION_ARCHIVE_FILE   full path to the archive index; overrides the derived
#                                ~/.claude/projects/<slug>/CLAUDE-archive.md default
#
# Exit 0 unless a dead (zero-source) or ambiguous (2+ live BACKLOG.md headings) citation is found.
set -euo pipefail

QUIET=0
usage() {
  cat <<'EOF'
tools/self/citation-resolvability.sh — every `dir #N` cited in tracked docs must resolve to exactly
one ticket, across BACKLOG.md's live headings and the closed-ticket archive index.

Usage:
  tools/self/citation-resolvability.sh [REPO_DIR]   scan REPO_DIR (default: current directory)
  tools/self/citation-resolvability.sh --quiet      print only DEAD/AMBIGUOUS lines
  tools/self/citation-resolvability.sh -h | --help

Exit 0 unless a dead or ambiguous citation is found, or BACKLOG.md is absent (degrades to a skip).
EOF
}

REPO_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "citation-resolvability.sh: unknown flag '$1' (try --help)" >&2; exit 2 ;;
    *) REPO_ARG="$1" ;;
  esac
  shift
done
repo_dir="${REPO_ARG:-.}"
[ -d "$repo_dir" ] || { echo "citation-resolvability.sh: not a directory: $repo_dir" >&2; exit 2; }
repo_dir="$(cd "$repo_dir" && pwd)"

say() { [ "$QUIET" = 1 ] || echo "$@"; }

say "● citation resolvability ($repo_dir)"

backlog_file="$repo_dir/BACKLOG.md"
if [ ! -f "$backlog_file" ]; then
  say "  SKIP no BACKLOG.md at $repo_dir (worktree, or not the main checkout) — nothing to check"
  exit 0
fi

# Derived per BACKLOG.md:1255's own naming convention: the project dir under ~/.claude/projects/ is
# the repo's absolute path with every '/' replaced by '-'. Overridable for test isolation, since the
# real archive is personal state outside the repo and outside git entirely.
if [ -n "${KEEL_CITATION_ARCHIVE_FILE:-}" ]; then
  archive_file="$KEEL_CITATION_ARCHIVE_FILE"
else
  slug="$(printf '%s' "$repo_dir" | tr '/' '-')"
  archive_file="${HOME:-}/.claude/projects/$slug/CLAUDE-archive.md"
fi
if [ -f "$archive_file" ]; then
  say "  archive: $archive_file"
else
  say "  archive: absent ($archive_file) — a moved-to-archive ticket will read as dead"
  archive_file=""
fi

# Tracked doc set: docs/*.md only — matching dir #266's own proof run (26 unique numbers, 41
# mentions, 1 unresolvable). CHANGELOG.md and commands/*.md/templates/*.md are deliberately excluded,
# same reasoning as tools/self/doctor.sh's dead-reference check exempting CHANGELOG.md: those are
# history text, not live documentation, and legitimately keep citing a ticket number long after that
# ticket has aged out of both BACKLOG.md and the archive — six real CHANGELOG.md citations of exactly
# that shape (dir #12, #23, #27, #28, #49, #77) surfaced as false positives the first time this script
# scanned CHANGELOG.md, which is the cry-wolf failure this ticket itself warns against.
scan_files=()
while IFS= read -r f; do scan_files+=("$f"); done < <(
  git -C "$repo_dir" ls-files -- 'docs/*.md'
)

exit_code=0
dead=0
ambiguous=0

# Every unique ticket number cited anywhere in the tracked doc set.
cited_numbers=()
if [ "${#scan_files[@]}" -gt 0 ]; then
  while IFS= read -r n; do
    [ -n "$n" ] && cited_numbers+=("$n")
  done < <(
    grep -hoE 'dir #[0-9]+' "${scan_files[@]/#/$repo_dir/}" 2>/dev/null \
      | sed -E 's/^dir #//' | sort -un
  )
fi

for n in "${cited_numbers[@]}"; do
  live_count="$(grep -cE "^### dir #${n}([^0-9]|\$)" "$backlog_file" || true)"
  archive_hit=0
  if [ -n "$archive_file" ] && grep -qE "dir #${n}([^0-9]|\$)" "$archive_file" 2>/dev/null; then
    archive_hit=1
  fi

  if [ "$live_count" -ge 2 ]; then
    echo "  AMBIGUOUS dir #$n — $live_count live ### headings in BACKLOG.md"
    ambiguous=$((ambiguous + 1))
    exit_code=1
  elif [ "$live_count" -eq 0 ] && [ "$archive_hit" -eq 0 ]; then
    # Cite the first tracked file mentioning it, for a starting point.
    first_hit="$(grep -lE "dir #${n}([^0-9]|\$)" "${scan_files[@]/#/$repo_dir/}" 2>/dev/null | head -1 || true)"
    echo "  DEAD dir #$n — no live BACKLOG.md heading, not in the archive (first cited: ${first_hit#"$repo_dir"/})"
    dead=$((dead + 1))
    exit_code=1
  fi
done

say "  ${#cited_numbers[@]} unique ticket number(s) cited, $dead dead, $ambiguous ambiguous"
exit "$exit_code"
