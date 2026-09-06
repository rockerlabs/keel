#!/usr/bin/env bash
# tools/self/archive-sweep-check.sh — keel-self-maintenance (dir #359): the closed-ticket
# archive sweep was a one-off catch-up (dir #353, 21,780 -> 10,884 lines), not a standing step —
# nothing scheduled it and nothing schedules the next one except a human noticing the file has
# grown large again. This is the mechanical trigger: it reports BACKLOG.md's closed-ticket line
# share and WARNs once that share crosses a threshold. There is no consumer-facing counterpart
# and install.sh never ships this file (BACKLOG.md itself is keel-self-maintenance content).
#
# This script is READ-ONLY. It does not move, summarize, or delete anything — dir #353's own
# manual run (identify eligible tickets, condense each into one archive line, gate on
# tools/self/citation-resolvability.sh before/after) is still the executed procedure for
# actually performing a sweep; this only mechanizes the "is one due" signal so it stops
# depending on a human happening to notice.
#
# Both traps dir #359 records, carried here rather than restated at the call site
# (docs/release-audit.md phase 7):
#   1. Cooldown and datability — nothing closed in the current, uncut release may be swept, and
#      nothing whose closure date can't be read may be swept. This script reports the
#      datability half (an undated closure) as an informational count; cooldown needs the
#      current release's cut boundary, which this script does not know, so that half stays a
#      manual check before any actual sweep.
#   2. Wrapped headings — a heading's own closure tag can sit on a continuation line, not just
#      the `### dir #N`/`### <n>.` line itself (dir #255/#352). tools/lib/backlog-blocks.sh's
#      block detection mirrors tools/self/doctor.sh's check 5 exactly, for the same reason.
#
# Usage:
#   tools/self/archive-sweep-check.sh [--threshold N] [BACKLOG_PATH]
#   tools/self/archive-sweep-check.sh -h | --help
#
# BACKLOG_PATH defaults to the MAIN checkout's BACKLOG.md, resolved the same way
# tools/self/doctor.sh's check 5 does (dir #135) — this repo's own convention: BACKLOG.md lives
# only at the main checkout root, never in a linked worktree.
#
# Env override: KEEL_ARCHIVE_SWEEP_THRESHOLD — closed-line-share percentage (default 40) at or
# above which this script WARNs. Always exits 0 (advisory only, per dir #359's own "warns" — not
# "fails" — shape); a missing/unreadable BACKLOG.md is a silent skip, not an error, the same as
# every other keel-self-maintenance check that reads this gitignored, optional file.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$self_dir/../.." && pwd)"

# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"
# shellcheck source=tools/lib/backlog-blocks.sh
. "$self_dir/../lib/backlog-blocks.sh"

threshold="${KEEL_ARCHIVE_SWEEP_THRESHOLD:-40}"
backlog_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold)
      [ $# -ge 2 ] || { echo "archive-sweep-check: --threshold needs a value" >&2; exit 2; }
      threshold="$2"; shift 2 ;;
    --threshold=*) threshold="${1#*=}"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: archive-sweep-check.sh [--threshold N] [BACKLOG_PATH]

Reports BACKLOG.md's closed-ticket line share; WARNs (to stderr, exit stays 0) once that
share is at or above N percent (default 40, or $KEEL_ARCHIVE_SWEEP_THRESHOLD). Read-only —
never modifies BACKLOG.md. BACKLOG_PATH defaults to the main checkout's BACKLOG.md.
EOF
      exit 0 ;;
    -*)
      echo "archive-sweep-check: unknown flag: $1" >&2
      exit 2 ;;
    *)
      backlog_arg="$1"; shift ;;
  esac
done

if [ -n "$backlog_arg" ]; then
  backlog_file="$backlog_arg"
else
  backlog_file="$(backlog_root_for "$repo_root")/BACKLOG.md"
fi

if [ ! -f "$backlog_file" ] || [ ! -r "$backlog_file" ]; then
  echo "archive-sweep-check: no readable BACKLOG.md at $backlog_file — skipped, not a failure"
  exit 0
fi

# NR, not `wc -l`: a file with no trailing newline still has its last line counted, matching
# the line numbers backlog_ticket_blocks reports (the same guard doctor.sh check 5 documents).
total_lines="$(awk 'END{print NR}' "$backlog_file")"

closed_count=0
closed_lines=0
undated_closed=0

while IFS=$'\t' read -r start end closed heading_block; do
  [ "$closed" = "1" ] || continue
  closed_count=$((closed_count + 1))
  closed_lines=$((closed_lines + end - start + 1))
  if ! grep -qE '✅ (DONE|CLOSED) \([0-9]{4}-[0-9]{2}-[0-9]{2}' <<< "$heading_block"; then
    undated_closed=$((undated_closed + 1))
  fi
done < <(backlog_ticket_blocks "$backlog_file")

pct=0
[ "$total_lines" -gt 0 ] && pct=$(( closed_lines * 100 / total_lines ))

echo "archive-sweep-check: $backlog_file"
echo "  total lines:       $total_lines"
echo "  closed tickets:    $closed_count ($closed_lines lines, ${pct}%)"
echo "  undated closures:  $undated_closed (trap 1's datability half — would block an actual sweep on those; verify by hand)"
echo "  threshold:         ${threshold}%"

if [ "$pct" -ge "$threshold" ]; then
  echo "WARN: closed-ticket line share (${pct}%) is at or above the ${threshold}% threshold — an archive re-sweep is due (dir #359). Carry both recorded traps: cooldown/datability, and wrapped-heading terminal-marker recovery (dir #255)." >&2
fi

exit 0
