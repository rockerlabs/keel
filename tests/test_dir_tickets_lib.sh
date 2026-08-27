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
# doctor.sh keeps its old private name as a one-line wrapper (no call-site/test churn) — pin that it
# stays a WRAPPER (calls the shared function) rather than silently reverting to its own full copy.
check_contains "doctor.sh's _extract_dir_tickets is a thin wrapper, not a re-duplicated copy" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" '_extract_dir_tickets() { extract_dir_tickets; }'

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

out="$(printf 'an illustrative example: `dir #999` is not real\n' | extract_dir_tickets)"
check_absent "a backtick-quoted citation is stripped, not extracted" "$out" "999"

out="$(printf 'dir #107-104\n' | extract_dir_tickets)"
check_contains "a reversed range surfaces its low endpoint (not silently dropped)" "$out" "dir #104"
check_contains "a reversed range surfaces its high endpoint (not silently dropped)" "$out" "dir #107"

summary
