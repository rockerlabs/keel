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
# shellcheck source=tools/lib/dir-tickets.sh
. "$self_dir/../lib/dir-tickets.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$self_dir/../lib/impact-store.sh"

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
# BACKLOG.md lives ONLY there, never in a linked worktree. `_impact_main_top`/`impact_project_id`
# (tools/lib/impact-store.sh, dir #251) already implement this exact projection — sourced rather than
# hand-rolled a second time, since dir #251's own store resolution needs the identical main-checkout
# and `~/.claude/projects/`-style slug this script also needs for the archive path below.
backlog_root="$(_impact_main_top "$repo_dir")"
backlog_root="${backlog_root:-$repo_dir}"
backlog_file="$backlog_root/BACKLOG.md"
# `-r`, not just `-f`: an unreadable file (a stray chmod, found live by dir #266's own review) must
# degrade the same silent way an absent one does, not fall through and report every citation as DEAD —
# tools/self/doctor.sh's own check 5 makes the identical distinction for the identical file.
if [ ! -r "$backlog_file" ]; then
  say "  SKIP no readable BACKLOG.md at $backlog_root — nothing to check"
  exit 0
fi

# Derived per BACKLOG.md:1255's own naming convention: the project dir under ~/.claude/projects/ is
# the repo's absolute path with every '/' replaced by '-' — exactly `impact_project_id`'s own D2
# slug (tools/lib/impact-store.sh), reused rather than hand-rolled. Overridable for test isolation,
# since the real archive is personal state outside the repo and outside git entirely.
if [ -n "${KEEL_CITATION_ARCHIVE_FILE:-}" ]; then
  archive_file="$KEEL_CITATION_ARCHIVE_FILE"
else
  archive_file="${HOME:-}/.claude/projects/$(impact_project_id "$backlog_root")/CLAUDE-archive.md"
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
# fenced code example must not read as a real citation — tools/lib/fence-blank.sh, dir #169) and run
# it through `extract_dir_tickets` (tools/lib/dir-tickets.sh, dir #274, promoted from
# tools/self/doctor.sh for this second consumer) rather than a bare `grep -oE 'dir #[0-9]+'` — that
# naive form silently drops every bare `#N` in a shorthand/slash/range list like "dir #201/#214"
# (docs/delegation.md:221, a real shipped instance, not hypothetical — found live by dir #266's own
# review reproducing the exact bug class `extract_dir_tickets` was hardened against). Backtick-quoted
# inline spans are stripped by `extract_dir_tickets` itself, so an illustrative `` `dir #999` `` in
# prose is not double-guarded here.
#
# Builds two maps as it goes: which file first cites a given number (for reporting) and, once, the
# deduped set of every number cited anywhere. Plain `+=` array appends, not a string round-trip: this
# repo's tools target bash 3.2 (macOS's shipped /bin/bash), where `"${arr[@]}"` on a still-empty
# array throws unbound-variable under `set -u` even when declared — but `arr+=("x")` on that same
# still-empty array is safe (only EXPANDING an empty array is the trap, not appending to one), so the
# final `for` loop below just needs its own length guard, nothing upstream does.
cited_numbers=()
if [ "${#abs_files[@]}" -gt 0 ]; then
  for f in "${abs_files[@]}"; do
    while IFS= read -r n; do
      # extract_dir_tickets can emit a non-numeric marker line for an absurdly wide range
      # ("dir #1-99999 (range too large to expand, dir #274)") rather than silently dropping it —
      # correct for its own WARN-surfacing caller in doctor.sh, but not a valid ticket number here, so
      # it's filtered out rather than fed into a variable name or an integer comparison below.
      [[ "$n" =~ ^dir\ \#([0-9]+)$ ]] || continue
      n="${BASH_REMATCH[1]}"
      var="cite_first_$n"
      if [ -z "${!var:-}" ]; then
        printf -v "$var" '%s' "${f#"$repo_dir"/}"
        cited_numbers+=("$n")
      fi
    done < <(blank_fenced_blocks "$f" | extract_dir_tickets)
  done
fi
# Numeric order for stable, predictable output (the accumulation above is first-cited-file order).
if [ "${#cited_numbers[@]}" -gt 0 ]; then
  sorted_numbers=()
  while IFS= read -r n; do sorted_numbers+=("$n"); done < <(printf '%s\n' "${cited_numbers[@]}" | sort -un)
  cited_numbers=("${sorted_numbers[@]}")
fi

# The two resolution-source scans below only ever matter if something was actually cited — skip both
# when nothing was, rather than paying a full fence-blanked pass over BACKLOG.md (1.3MB+ in this repo)
# and the archive for a result nothing will consult.
if [ "${#cited_numbers[@]}" -gt 0 ]; then
  # One pass over BACKLOG.md (fence-blanked, same reasoning as the doc files above — an illustrative
  # `### dir #N` heading inside a fenced example must not count as a live one): a number -> live-
  # heading-count map, built once, rather than a `grep -cE` re-scan of the whole file per cited
  # number. Plain dynamic variable names (`live_$n`), not `declare -A` — this repo's tools target
  # bash 3.2 (macOS's shipped /bin/bash), which has no associative arrays; `printf -v`/`${!var}`
  # indirection is the established bash-3.2-safe substitute (tests/run.sh's own header names the
  # same constraint). This is a HEADING scan (`^### dir #N`), a different job from `extract_dir_tickets`
  # above (every citation anywhere in running prose) — deliberately not reused for this anchor-match.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    var="live_$n"
    printf -v "$var" '%s' "$(( ${!var:-0} + 1 ))"
  done < <(blank_fenced_blocks "$backlog_file" | grep -oE '^### dir #[0-9]+' | grep -oE '[0-9]+')

  # One pass over the archive (when present), fence-blanked the same way as the two sources above (an
  # illustrative `dir #N` inside a pasted fenced transcript must not count as a real archival
  # resolution either) and run through the same hardened `extract_dir_tickets`. The set of numbers it
  # mentions at all, built once rather than a re-grep per cited number. Presence only, not a count —
  # the archive accumulates repeated closure-sweep blocks by design (see header), so more than one
  # mention there is not an ambiguity.
  if [ -n "$archive_file" ]; then
    while IFS= read -r n; do
      [[ "$n" =~ ^dir\ \#([0-9]+)$ ]] || continue
      printf -v "arch_${BASH_REMATCH[1]}" 1
    done < <(blank_fenced_blocks "$archive_file" | extract_dir_tickets)
  fi
fi

exit_code=0
dead=0
ambiguous=0

# `"${cited_numbers[@]}"` on a still-empty array throws unbound-variable under `set -u` on this
# repo's target bash 3.2 even though the array WAS declared — guard the length before iterating,
# every time.
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
