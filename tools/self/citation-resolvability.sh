#!/usr/bin/env bash
# tools/self/citation-resolvability.sh — keel-self-maintenance (dir #68 exemption, per
# tools/self/prose-drift.sh's header): checks that every `dir #N` cited in KEEL'S OWN docs/*.md
# resolves to exactly one ticket. There is no consumer-facing counterpart and install.sh never ships
# this file.
#
# Filed dir #266, 2026-08-27, after a day in which three separate tickets were filed for citations
# that looked resolvable and were not (dir #64's two-tickets-one-number collision, fixed as dir #259).
# This subsumes dir #259: a duplicate `### dir #N` heading is exactly what makes citations of that
# number ambiguous, so the cause (duplicate heading) and the consequence (ambiguous citation) are one
# check, not two.
#
# WHERE the ticket sources live, and why this is a standalone script rather than a
# tools/self/doctor.sh leg (per this ticket's own filed scope, reaffirmed by the filing session): the
# second source, the closed-ticket archive index, lives entirely OUTSIDE the repo, at
# ~/.claude/projects/<slugified-repo-path>/CLAUDE-archive.md (Claude Code's own memory convention —
# BACKLOG.md:1255 names this exact path). A CI run has neither `BACKLOG.md` nor that archive on disk
# regardless of how this check is packaged. Both absences degrade SILENTLY (a skip line, exit 0)
# rather than failing — the same shape as its sibling tools/self/shellcheck-targets.sh, which this
# script's REPO_DIR default also borrows for test-sandbox use. `BACKLOG.md` itself is resolved to the
# MAIN checkout the same way tools/self/doctor.sh's own check 5 does (dir #135) — so, unlike a naive
# version, this DOES run for real from the common case, a worktree session.
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
# REPO_DIR defaults to the current directory and may be a worktree of the target repo — BACKLOG.md is
# looked up at the main checkout regardless of which one REPO_DIR names, docs/*.md at REPO_DIR itself
# (a worktree's tracked files are real, git-synced copies, unlike BACKLOG.md).
#
# Env overrides (test isolation, same shape as KEEL_IMPACT_LOG et al. in tests/lib.sh):
#   KEEL_CITATION_ARCHIVE_FILE   full path to the archive index; overrides the derived
#                                ~/.claude/projects/<slug>/CLAUDE-archive.md default
#
# Exit 0 unless a dead (zero-source) or ambiguous (2+ live BACKLOG.md headings) citation is found.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

QUIET=0
usage() {
  cat <<'EOF'
tools/self/citation-resolvability.sh — every `dir #N` cited in docs/*.md must resolve to exactly one
ticket, across BACKLOG.md's live headings and the closed-ticket archive index.

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

# Resolve the MAIN checkout the same way tools/self/doctor.sh's own check 5 does (dir #135):
# BACKLOG.md lives ONLY there, never in a linked worktree, and `repo_dir` above is whatever checkout
# this script was invoked against — the worktree path itself in the common case. The first `worktree
# <path>` line of `git worktree list --porcelain` names it, unless that entry is bare (a plain
# single-checkout repo's own output has exactly one such line naming itself, a no-op here). `|| true`:
# outside a repo (or a REPO_ARG sandbox dir the test suite points at a non-repo path) git exits
# non-zero, and this check is advisory-optional, never worth aborting the run over.
main_top="$(git -C "$repo_dir" worktree list --porcelain 2>/dev/null \
  | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
backlog_root="${main_top:-$repo_dir}"
backlog_file="$backlog_root/BACKLOG.md"
if [ ! -f "$backlog_file" ]; then
  say "  SKIP no BACKLOG.md at $backlog_root — nothing to check"
  exit 0
fi

# Derived per BACKLOG.md:1255's own naming convention: the project dir under ~/.claude/projects/ is
# the repo's absolute path with every '/' replaced by '-'. Overridable for test isolation, since the
# real archive is personal state outside the repo and outside git entirely.
if [ -n "${KEEL_CITATION_ARCHIVE_FILE:-}" ]; then
  archive_file="$KEEL_CITATION_ARCHIVE_FILE"
else
  slug="$(printf '%s' "$backlog_root" | tr '/' '-')"
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
# that shape (dir #12, dir #23, dir #27, dir #28, dir #49, dir #77) surfaced as false positives the
# first time this script scanned CHANGELOG.md, which is the cry-wolf failure this ticket itself warns
# against.
scan_files=()
while IFS= read -r f; do scan_files+=("$f"); done < <(
  git -C "$repo_dir" ls-files -- 'docs/*.md'
)
abs_files=()
[ "${#scan_files[@]}" -gt 0 ] && abs_files=("${scan_files[@]/#/$repo_dir/}")

# One pass per doc file (not per cited number): fence-blank it (a `dir #N`-shaped line inside a
# fenced code example must not read as a real citation — tools/lib/fence-blank.sh, dir #169, is the
# one shared toggle for this, already used by doctor.sh's own BACKLOG.md/CHANGELOG.md scans) and
# strip backtick-quoted inline spans (an illustrative `` `dir #999` `` in prose is not a real
# citation either — doctor.sh's `_extract_dir_tickets` established this same guard, dir #274).
# Builds two maps as it goes: which files ever cite a given number (first one wins, for reporting)
# and, once, the deduped set of every number cited anywhere — avoiding both the O(N) re-grep of the
# whole doc set for "first hit" and its own separate O(N) extraction pass a naive per-number loop
# would otherwise pay.
# Accumulated as a plain newline-separated string, not an array, while building it: this repo's
# tools target bash 3.2 (macOS's shipped /bin/bash), where `"${arr[@]}"` on a still-empty array
# throws an unbound-variable error under `set -u` even though the array WAS declared — reproduced
# live here, not merely a memory of the class. A string has no such failure mode; the one array this
# ultimately feeds (`cited_numbers`, below) is built from it in a single length-guarded step.
cited_raw=""
if [ "${#abs_files[@]}" -gt 0 ]; then
  for f in "${abs_files[@]}"; do
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      var="cite_first_$n"
      if [ -z "${!var:-}" ]; then
        printf -v "$var" '%s' "${f#"$repo_dir"/}"
        cited_raw="$cited_raw$n
"
      fi
    done < <(blank_fenced_blocks "$f" | sed -E 's/`[^`]*`//g' | grep -hoE 'dir #[0-9]+' | sed -E 's/^dir #//')
  done
fi
# Numeric order for stable, predictable output (the accumulation above is first-cited-file order).
cited_numbers=()
if [ -n "$cited_raw" ]; then
  while IFS= read -r n; do
    [ -n "$n" ] && cited_numbers+=("$n")
  done < <(printf '%s' "$cited_raw" | sort -un)
fi

# One pass over BACKLOG.md (fence-blanked, same reasoning as the doc files above — an illustrative
# `### dir #N` heading inside a fenced example must not count as a live one): a number -> live-heading
# -count map, built once, rather than a `grep -cE` re-scan of the whole file per cited number. Plain
# dynamic variable names (`live_$n`), not `declare -A` — this repo's tools target bash 3.2 (macOS's
# shipped /bin/bash), which has no associative arrays; `printf -v`/`${!var}` indirection is the
# established bash-3.2-safe substitute (tests/run.sh's own header names the same constraint).
while IFS= read -r n; do
  [ -n "$n" ] || continue
  var="live_$n"
  printf -v "$var" '%s' "$(( ${!var:-0} + 1 ))"
done < <(blank_fenced_blocks "$backlog_file" | grep -oE '^### dir #[0-9]+' | grep -oE '[0-9]+')

# One pass over the archive (when present): the set of numbers it mentions at all, built once rather
# than a re-grep per cited number. Presence only, not a count — the archive accumulates repeated
# closure-sweep blocks by design (see header), so more than one mention there is not an ambiguity.
if [ -n "$archive_file" ]; then
  while IFS= read -r n; do
    [ -n "$n" ] && printf -v "arch_$n" 1
  done < <(sed -E 's/`[^`]*`//g' "$archive_file" 2>/dev/null | grep -hoE 'dir #[0-9]+' | sed -E 's/^dir #//' || true)
fi

exit_code=0
dead=0
ambiguous=0

# `"${cited_numbers[@]}"` on a still-empty array throws unbound-variable under `set -u` on this
# repo's target bash 3.2 even though the array WAS declared (see the cited_raw comment above) — guard
# the length before iterating, every time.
if [ "${#cited_numbers[@]}" -gt 0 ]; then
  for n in "${cited_numbers[@]}"; do
    live_var="live_$n"; live_count="${!live_var:-0}"
    arch_var="arch_$n"; archive_hit="${!arch_var:-0}"

    if [ "$live_count" -ge 2 ]; then
      echo "  AMBIGUOUS dir #$n — $live_count live ### headings in BACKLOG.md"
      ambiguous=$((ambiguous + 1))
      exit_code=1
    elif [ "$live_count" -eq 0 ] && [ "$archive_hit" != 1 ]; then
      var="cite_first_$n"
      echo "  DEAD dir #$n — no live BACKLOG.md heading, not in the archive (first cited: ${!var:-?})"
      dead=$((dead + 1))
      exit_code=1
    fi
  done
fi

say "  ${#cited_numbers[@]} unique ticket number(s) cited, $dead dead, $ambiguous ambiguous"
exit "$exit_code"
