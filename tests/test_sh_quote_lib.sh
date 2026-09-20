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

# --- sh_quote_json: sh_quote's own output, JSON-escaped for embedding in a JSON string literal
# (dir #514 gap 2, found live by an independent /code-review medium pass) — a plain path needs no
# extra escaping over sh_quote's own output ------------------------------------------------------
check_status "sh_quote_json: plain path == sh_quote's own output (no backslash to double)" \
  "$(sh_quote "/Users/x/keel/tools/pre-pr-gate.sh")" \
  "$(sh_quote_json "/Users/x/keel/tools/pre-pr-gate.sh")"

# --- an apostrophe path's sh_quote output contains a literal backslash (from the '\'' doubling) —
# sh_quote_json must double THAT backslash too, or the result is not valid JSON when spliced into a
# "..." string literal.
apjson="$(sh_quote_json "$apostrophe_path")"
check_status "sh_quote_json: doubles the backslash sh_quote's own escaping introduces" \
  "'/Users/x/Alex'\\\\''s checkout/keel/tools/pre-pr-gate.sh'" "$apjson"

# --- a literal double-quote in the path (dir #566): sh_quote itself does not escape `"` (only single
# quotes are special to its own quoting), so sh_quote_json must escape it for JSON — the
# backslash-doubling pass must run FIRST, or the `\` this introduces would itself get doubled -------
dquote_path='/Users/x/Say "hi" checkout/keel/tools/pre-pr-gate.sh'
dqjson="$(sh_quote_json "$dquote_path")"
check_status "sh_quote_json: escapes a literal double-quote" \
  "'/Users/x/Say \\\"hi\\\" checkout/keel/tools/pre-pr-gate.sh'" "$dqjson"

# --- the real proof: splice sh_quote_json's output into an actual JSON string literal and confirm
# jq accepts it AND reads back the exact command a real shell would still parse correctly — the two
# escaping layers (shell, then JSON) must compose, not just each look right in isolation.
printf '{ "command": "bash %s" }\n' "$apjson" > "$SANDBOX/sh-quote-json-snippet.json"
run bash -c "jq . '$SANDBOX/sh-quote-json-snippet.json'"
check_status "sh_quote_json: spliced into JSON, the result is valid JSON (jq accepts it)" 0 "$STATUS"
decoded_cmd="$(jq -r '.command' "$SANDBOX/sh-quote-json-snippet.json")"
eval "set -- $decoded_cmd"
check_status "sh_quote_json: the JSON-decoded command still resolves to the real path" \
  "$apostrophe_path" "$2"

# --- the same round-trip proof, for the double-quote path this ticket adds (dir #566) ---------------
printf '{ "command": "bash %s" }\n' "$dqjson" > "$SANDBOX/sh-quote-json-dquote-snippet.json"
run bash -c "jq . '$SANDBOX/sh-quote-json-dquote-snippet.json'"
check_status "sh_quote_json: double-quote path spliced into JSON is valid JSON (jq accepts it)" 0 "$STATUS"
decoded_dquote_cmd="$(jq -r '.command' "$SANDBOX/sh-quote-json-dquote-snippet.json")"
eval "set -- $decoded_dquote_cmd"
check_status "sh_quote_json: the JSON-decoded command still resolves to the real double-quote path" \
  "$dquote_path" "$2"

summary
