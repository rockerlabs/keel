#!/usr/bin/env bash
# test_fence_blank_lib.sh — dir #169: blank_fenced_blocks() used to be a private copy inside
# tools/self/doctor.sh (already found duplicated once between two of doctor.sh's OWN checks by an
# earlier /code-review medium pass, per that function's own comment) until tools/self/prose-drift.sh
# needed the identical toggle and this was extracted to tools/lib/fence-blank.sh instead of becoming
# a second hand-maintained copy. Pin this at the SOURCE level (grep both consumers for the sourcing
# line, and grep the whole tree for a re-duplicated inline copy of the toggle), not the output level —
# an output-level check would only prove today's two callers happen to agree, not that a third copy
# can't reappear.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/fence-blank.sh"
check_file "tools/lib/fence-blank.sh exists" "$lib"

# --- both known consumers source the shared lib, not a private copy -----------------------------
check_contains "doctor.sh sources tools/lib/fence-blank.sh" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" 'lib/fence-blank.sh'
check_contains "prose-drift.sh sources tools/lib/fence-blank.sh" \
  "$(cat "$REPO_ROOT/tools/self/prose-drift.sh")" 'lib/fence-blank.sh'

# --- no re-duplicated copy of THIS FUNCTION anywhere else under tools/ --------------------------
# The bare ```/~~~ fence-marker regex is NOT itself the marker — it's a legitimate, independent
# building block several pre-existing tools already use for a DIFFERENT purpose (tools/doctor.sh x3,
# tools/keel-impact.sh x1 — all `{f=!f;next} !f`, which DROPS fenced lines outright rather than
# blanking them to preserve line alignment; verified these predate this file and serve config/registry
# parsing, not this ticket's line-number-preserving need). The marker below is the variable name this
# function's toggle uses, unique to its own body — a re-duplication of blank_fenced_blocks() ITSELF
# would carry it; the unrelated filter-style copies above do not.
marker='infence = !infence'
# `grep -rl` already IS the "which files contain it" scan a hand-rolled find+while loop would
# rebuild line by line; only the lib's own match needs excluding from the result.
hits="$(grep -rlF "$marker" "$REPO_ROOT/tools" 2>/dev/null | grep -vF "$lib" || true)"
if [ -z "$hits" ]; then
  pass "no duplicated fence-toggle pattern outside tools/lib/fence-blank.sh"
else
  fail "no duplicated fence-toggle pattern outside tools/lib/fence-blank.sh" "found in: $hits"
fi

# --- the lib itself blanks fenced content while preserving line count/alignment -----------------
# shellcheck source=/dev/null
. "$lib"
d="$(new_repo)"
printf 'before\n```\nfenced long line %s\n```\nafter\n' "$(rep x 200)" > "$d/f.md"
out="$(blank_fenced_blocks "$d/f.md")"
line_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [ "$line_count" = 5 ]; then
  pass "blank_fenced_blocks preserves line count (5)"
else
  fail "blank_fenced_blocks preserves line count (5)" "got $line_count"
fi
check_contains "the line before the fence survives" "$out" "before"
check_contains "the line after the fence survives" "$out" "after"
check_absent "the fenced long line is blanked out" "$out" "fenced long line"
check_absent "the fence markers themselves are blanked too" "$out" '```'

summary
