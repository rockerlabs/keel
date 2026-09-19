#!/usr/bin/env bash
# test_dir_tickets_lib.sh — dir #266: extract_dir_tickets() used to be a private copy inside
# tools/self/doctor.sh (`_extract_dir_tickets`, dir #273/#274) until tools/self/citation-resolvability.sh
# needed the identical hardened extraction and this was promoted to tools/lib/dir-tickets.sh instead
# of becoming a second, weaker copy — the exact bug class the second copy would have reintroduced
# (a bare `grep -oE 'dir #[0-9]+'` silently drops shorthand/slash/range citations) was reproduced live
# against docs/delegation.md's own "dir #201/#214" during dir #266's own /code-review pass. Pin this
# at the SOURCE level (both consumers source the lib, doctor.sh via a one-line wrapper of its old
# name) as well as the output level (the extraction itself, including the shapes that caused real
# regressions before).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/dir-tickets.sh"
check_file "tools/lib/dir-tickets.sh exists" "$lib"

# --- both known consumers source the shared lib ---------------------------------------------------
check_contains "doctor.sh sources tools/lib/dir-tickets.sh" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" 'lib/dir-tickets.sh'
check_contains "citation-resolvability.sh sources tools/lib/dir-tickets.sh" \
  "$(cat "$REPO_ROOT/tools/self/citation-resolvability.sh")" 'lib/dir-tickets.sh'
# doctor.sh keeps its old private name as a thin wrapper (no call-site/test churn) — pin that it
# still DELEGATES to the shared function rather than silently reverting to its own full copy. dir
# #364/#273 composed a local, doctor.sh-only pre-filter (`_strip_ref_citations`, a `dir #N (ref)`
# marker strip with nothing to do with citation extraction itself) in front of the delegation — still
# a wrapper around the shared `extract_dir_tickets`, not a re-implementation of it, so the pin moves
# to the new composed shape rather than being loosened.
check_contains "doctor.sh's _extract_dir_tickets is a thin wrapper, not a re-duplicated copy" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" \
  '_extract_dir_tickets() { _strip_ref_citations | extract_dir_tickets; }'

# --- the lib itself: fully-spelled, shorthand, slash, range, and backtick-stripped shapes ----------
# shellcheck source=/dev/null
. "$lib"

out="$(printf 'see dir #5 and dir #9\n' | extract_dir_tickets)"
check_contains "fully-spelled citations are extracted" "$out" "dir #5"
check_contains "a second fully-spelled citation is extracted too" "$out" "dir #9"

out="$(printf 'dir #201/#214\n' | extract_dir_tickets)"
check_contains "a slash-separated shorthand list extracts its first number" "$out" "dir #201"
check_contains "a slash-separated shorthand list extracts its SECOND number too" "$out" "dir #214"

out="$(printf 'dir #208, #211, #212\n' | extract_dir_tickets)"
check_contains "a comma-separated shorthand list extracts #208" "$out" "dir #208"
check_contains "a comma-separated shorthand list extracts #211" "$out" "dir #211"
check_contains "a comma-separated shorthand list extracts #212" "$out" "dir #212"

out="$(printf 'dir #104-107\n' | extract_dir_tickets)"
check_contains "a range expands its low endpoint" "$out" "dir #104"
check_contains "a range expands every ticket in the middle" "$out" "dir #105"
check_contains "a range expands its high endpoint" "$out" "dir #107"

out="$(printf 'dir #364+#273\n' | extract_dir_tickets)"
check_contains "a plus-separated shorthand list extracts its first number (dir #482)" "$out" "dir #364"
check_contains "a plus-separated shorthand list extracts its SECOND number too (dir #482)" "$out" "dir #273"

out="$(printf 'an illustrative example: `dir #999` is not real\n' | extract_dir_tickets)"
check_absent "a backtick-quoted citation is stripped, not extracted" "$out" "999"

out="$(printf 'dir #107-104\n' | extract_dir_tickets)"
check_contains "a reversed range surfaces its low endpoint (not silently dropped)" "$out" "dir #104"
check_contains "a reversed range surfaces its high endpoint (not silently dropped)" "$out" "dir #107"

# --- dir #525: the 500-ticket cap and the three documented multi-line/multi-token shapes had zero
# coverage — each fixture below is red when the corresponding code is removed (verified live against
# a scratch mutation of the lib before this test was written, not assumed from reading the source) ---

# Cap: an absurdly wide range must be refused with a single loud marker line, never expanded — assert
# the line COUNT too, not just the marker text, since a truncated-but-still-multi-line expansion would
# still contain the marker substring while also flooding the output.
out="$(printf 'dir #1-99999\n' | extract_dir_tickets)"
check_contains "an absurdly wide range emits the loud marker, not real tickets (dir #274)" "$out" \
  "dir #1-99999 (range too large to expand, dir #274)"
out_lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
check_status "an absurdly wide range emits exactly one line, not a 99,999-line flood" "1" "$out_lines"

# Cross-line trailing-comma join: a ticket list wrapped across a line break (line 1 ends in a trailing
# comma, line 2 is made of nothing but ticket tokens) must join before extraction — without the join,
# line 2 never sees its own "dir " anchor and its tickets are silently dropped.
out="$(printf 'dir #200, #201,\n#202, #203\n' | extract_dir_tickets)"
check_contains "a line-wrapped ticket list extracts the first line's tickets" "$out" "dir #200"
check_contains "a line-wrapped ticket list joins onto the continuation line" "$out" "dir #202"
check_contains "a line-wrapped ticket list extracts the continuation's last ticket too" "$out" "dir #203"

# Blank-line hard flush: a blank line must flush the buffer as-is rather than let it survive to be
# joined onto a later, unrelated ticket-shaped line — two commit bodies separated by a blank line,
# where the second body happens to open with a bare ticket list, must not stitch onto the first body's
# "dir " citation.
out="$(printf 'dir #100, #101,\n#102, #103,\n\n#104, #105\n' | extract_dir_tickets)"
check_contains "a blank-line-preceded list keeps its own tickets" "$out" "dir #100"
check_absent "a blank line stops the buffer from stitching onto the next unrelated list" "$out" "dir #104"
check_absent "the blank-line flush covers the whole unrelated continuation, not just its first ticket" \
  "$out" "dir #105"

# Bare "and #N" continuation: "dir #300 and #301" (no comma) must extract both endpoints.
out="$(printf 'see dir #300 and #301\n' | extract_dir_tickets)"
check_contains "a bare \"and #N\" continuation extracts the anchor ticket" "$out" "dir #300"
check_contains "a bare \"and #N\" continuation extracts the and-joined ticket too" "$out" "dir #301"

summary
