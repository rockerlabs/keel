#!/usr/bin/env bash
# test_sh_quote_lib.sh — dir #514: tools/lib/sh-quote.sh's sh_quote is the shared quoting primitive
# that closed the "hand-rolled '\''-escaping duplicated identically in two installers" finding from
# this ticket's own /simplify pass — direct unit coverage so a future edit to the algorithm (or a
# regression in it) is caught here, not only via the two installers' own end-to-end fixtures
# (tests/test_install_pre_pr_gate.sh, tests/test_install_read_trace.sh).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/sh-quote.sh"
check_file "tools/lib/sh-quote.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- the basic shape: wraps in single quotes, no embedded quote to escape ---------------------------
check_status "sh_quote: plain path, no apostrophe" "'/Users/x/keel/tools/pre-pr-gate.sh'" \
  "$(sh_quote "/Users/x/keel/tools/pre-pr-gate.sh")"

# --- an embedded apostrophe is escaped, not left to break the surrounding quoting -------------------
check_status "sh_quote: one embedded apostrophe" "'/Users/x/Alex'\\''s checkout/keel/tools/pre-pr-gate.sh'" \
  "$(sh_quote "/Users/x/Alex's checkout/keel/tools/pre-pr-gate.sh")"

# --- two embedded apostrophes (not just the first) --------------------------------------------------
check_status "sh_quote: two embedded apostrophes" "'it'\\''s a test'\\''s path'" \
  "$(sh_quote "it's a test's path")"

# --- empty string: still a valid, empty-but-quoted token, never a bare nothing ----------------------
check_status "sh_quote: empty string" "''" "$(sh_quote "")"

# --- the real proof: the escaped output, run through a real shell, round-trips to the original string
# (the same round-trip the two installers' own end-to-end fixtures check, done here directly against
# the lib rather than through a full installer invocation).
apostrophe_path="/Users/x/Alex's checkout/keel/tools/pre-pr-gate.sh"
quoted="$(sh_quote "$apostrophe_path")"
roundtrip="$(eval "printf '%s' $quoted")"
check_status "sh_quote: round-trips through a real shell unchanged" "$apostrophe_path" "$roundtrip"

# --- a space, not just an apostrophe, still comes back as ONE token (the other half of dir #514's own
# comment: an unquoted path splitting into two argv tokens silently no-ops a hook) --------------------
space_path="/Users/x/My Checkout/keel/tools/pre-pr-gate.sh"
quoted_space="$(sh_quote "$space_path")"
eval "set -- $quoted_space"
check_status "sh_quote: a space stays inside one argv token" 1 "$#"
check_status "sh_quote: …and the token is the real, unescaped path" "$space_path" "$1"

summary
