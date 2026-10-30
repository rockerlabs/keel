#!/usr/bin/env bash
# test_backlog_blocks_end.sh — dir #915: the end line of the LAST ticket block in tools/lib/backlog-blocks.sh.
# backlog_ticket_blocks counted it over fence-blanked text whose trailing blank lines a command substitution
# dropped, so a last ticket ending in a fenced block was cut short for every caller. Pins: the full end for such a
# ticket (closed fence, unclosed fence, no final newline), that trailing blank lines still stay out of it, the
# `set -u` walk over the heading's continuation lines, the lookup mode (one ticket's row, no `closed` work), and
# bb_last_block_fence_end (the unclosed-fence cut tools/cloud-brief.sh used to keep locally).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/backlog-blocks.sh"
# shellcheck source=tools/lib/fence-blank.sh
. "$REPO_ROOT/tools/lib/fence-blank.sh"
# shellcheck source=/dev/null
. "$lib"

d="$(new_repo)"

# row FILE HEADING_PREFIX FIELD — field N (1 start, 2 end, 3 closed) of the row whose heading starts with the prefix.
row() { backlog_ticket_blocks "$1" | awk -F'\t' -v p="$2" -v n="$3" 'index($4, p) == 1 { print $n }'; }

# --- a last ticket ending in a closed fence: its end is the closing marker, not the last visible line -------------
f="$d/closed.md"
printf '### dir #1 — a first ticket — R3 — → pool\n\nbody\n\n### dir #2 — a last ticket — R3 — → pool\n\nbody\n\n```\nfenced tail\n```\n' > "$f"
check_eq "a last ticket ending in a closed fence: start" "5" "$(row "$f" '### dir #2' 1)"
check_eq "a last ticket ending in a closed fence: its end is the closing marker (line 11)" "11" "$(row "$f" '### dir #2' 2)"
check_eq "the ticket before it still ends at the line before the next heading" "4" "$(row "$f" '### dir #1' 2)"

# --- an unclosed fence runs to the file's last line -----------------------------------------------------------------
f="$d/unclosed.md"
printf '### dir #2 — a last ticket — R3 — → pool\n\nbody\n\n```\nunclosed body\nits last line\n' > "$f"
check_eq "a last ticket ending in an unclosed fence: its end is the file's last line (7)" "7" "$(row "$f" '### dir #2' 2)"

# --- no final newline ----------------------------------------------------------------------------------------------
f="$d/nonl.md"
printf '### dir #2 — a last ticket — R3 — → pool\n\nbody\n\n```\nfenced tail\n```' > "$f"
check_eq "a closing marker with no final newline still ends the ticket (7)" "7" "$(row "$f" '### dir #2' 2)"

# --- trailing blank lines stay out of the end, as before -----------------------------------------------------------
f="$d/blank-tail.md"
printf '### dir #2 — a last ticket — R3 — → pool\n\nbody\n\n\n\n' > "$f"
check_eq "trailing blank lines are not part of the last ticket (end 3)" "3" "$(row "$f" '### dir #2' 2)"
f="$d/blank-tail-fence.md"
printf '### dir #2 — a last ticket — R3 — → pool\n\n```\nfenced\n```\n\n\n' > "$f"
check_eq "trailing blank lines after a closing fence stay out too (end 5)" "5" "$(row "$f" '### dir #2' 2)"

# --- a section break still ends a ticket before a fence that follows it ---------------------------------------------
f="$d/section.md"
printf '### dir #2 — a ticket — R3 — → pool\n\nbody\n\n## Archive\n\n```\nfenced\n```\n' > "$f"
check_eq "a ticket ends before the section break, whatever fence follows (end 4)" "4" "$(row "$f" '### dir #2' 2)"

# --- the heading's continuation walk reaches a fence: no unbound index under set -u (bash 3.2: a[5]: unbound variable)
# A title with no tail yet keeps taking lines; the fenced lines after it are blank in the scan, and the walk must stop on
# them rather than index past the array. The end counts the fence, which the array used to lack.
f="$d/walk.md"
printf '### dir #2 — a title without its tail\nwrapped line\n```\nfenced\n```\n' > "$f"
run bash -c 'set -u; . "'"$REPO_ROOT"'/tools/lib/fence-blank.sh"; . "'"$lib"'"; backlog_ticket_blocks "'"$f"'"'
check_status "the continuation walk into a fence survives set -u" 0 "$STATUS"
check_absent "… with no unbound-variable error" "$OUT" "unbound variable"
check_contains "… and the row's end counts the fence (line 5)" "$OUT" "$(printf '1\t5\t0\t')"

# --- lookup mode: one ticket's row, the closed field not computed -----------------------------------------------------
f="$d/lookup.md"
printf '### dir #1 — an open ticket — R3 — → pool\n\nbody\n\n### dir #2 — a closed ticket — R3 — ✅ DONE (2026-08-01, done)\n\nbody\n\n### dir #3 — the last ticket — R3 — → pool\n\n```\nfenced\n```\n' > "$f"
all="$(backlog_ticket_blocks "$f")"
one="$(backlog_ticket_blocks "$f" '' 'dir #3')"
check_eq "lookup: exactly one row" "1" "$(printf '%s\n' "$one" | grep -c .)"
check_eq "lookup: start and end are the full scan's" "$(printf '%s' "$all" | awk -F'\t' '$1 == 9 { print $1 "\t" $2 }')" "$(printf '%s' "$one" | cut -f1-2)"
check_eq "lookup: the heading is the full scan's" "$(printf '%s' "$all" | awk -F'\t' '$1 == 9 { print $4 }')" "$(printf '%s' "$one" | cut -f4)"
check_eq "lookup: the closed field is a placeholder, not a value" "-" "$(printf '%s' "$one" | cut -f3)"
check_eq "lookup: a closed ticket is found too" "5" "$(backlog_ticket_blocks "$f" '' 'dir #2' | cut -f1)"
check_eq "lookup: an unknown id gives nothing" "" "$(backlog_ticket_blocks "$f" '' 'dir #4')"
check_eq "lookup: a prefix of an id is not the id (dir #3 vs dir #30)" "" "$(backlog_ticket_blocks "$f" '' 'dir #')"
# The point of the mode: no per-heading closure work. A stub that records its calls shows none are made.
calls="$d/calls"
: > "$calls"
bb_strip_foreign_citations() { echo strip >> "$calls"; }
bb_own_ticket_num() { echo own >> "$calls"; }
backlog_ticket_blocks "$f" '' 'dir #3' > /dev/null
check_eq "lookup: bb_strip_foreign_citations and bb_own_ticket_num are never called" "0" "$(grep -c . "$calls")"
backlog_ticket_blocks "$f" > /dev/null
check_ne "control: the full scan does call them" "0" "$(grep -c . "$calls")"
# shellcheck source=/dev/null
. "$lib"

# --- bb_last_block_fence_end FILE START END [ERE]: the cut for a last block that leaves a fence open ------------------
# Prints the end line to use and returns 0, or returns 1 printing the line N of the heading-shaped line the unclosed
# fence hides inside the ticket's text (the toggle cannot say which fence is the open one).
fe() { # FILE START — the helper over the lib's own end for that start
  local e
  e="$(backlog_ticket_blocks "$1" '' "$3" | cut -f2)"
  bb_last_block_fence_end "$1" "$2" "$e"
}
f="$d/fe-even.md"
printf '### dir #7 — all closed — R3 — → pool\n\n```\n## an example section\n```\n\ntail text\n' > "$f"
run fe "$f" 1 'dir #7'
check_status "every fence closed: no cut, no refusal" 0 "$STATUS"
check_eq "… the end is the file's last line (7)" "7" "$OUT"

f="$d/fe-unclosed.md"
printf '### dir #7 — an open fence — R3 — → pool\n\nbody\n\n```\nopen body\n\n### dir #8 — hidden — R3 — → pool\n\nBody 8.\n' > "$f"
run fe "$f" 1 'dir #7'
check_status "an unclosed fence, nothing visible after the hidden heading: cut" 0 "$STATUS"
check_eq "… at the line before that heading (7)" "7" "$OUT"

f="$d/fe-after-end.md"
printf '### dir #7 — closed fence holding a section, then an open one — R3 — → pool\n\nbody\n\n```\n## an example section\nmore\n```\n\n```\nopen tail\n' > "$f"
run fe "$f" 1 'dir #7'
check_status "a closed fence holding a section line, then an unclosed fence: cut" 0 "$STATUS"
check_eq "… no heading after the unclosed opener, so the file's last line (11)" "11" "$OUT"

f="$d/fe-visible.md"
printf '### dir #7 — an open fence before a fenced archive — R3 — → pool\n\n```\nopen body\n\n## Archive\n\n```sh\narchived code\n```\n\ntail\n' > "$f"
run fe "$f" 1 'dir #7'
check_status "visible text after a hidden section line: refused" 1 "$STATUS"
check_eq "… naming the hidden section line (6)" "6" "$OUT"

f="$d/fe-not-last.md"
printf '### dir #7 — not last — R3 — → pool\n\nbody\n\n### dir #8 — last — R3 — → pool\n\n```\nopen\n' > "$f"
run bb_last_block_fence_end "$f" 1 3
check_status "a block that is not the last one is left alone" 0 "$STATUS"
check_eq "… its end comes back unchanged" "3" "$OUT"

summary
