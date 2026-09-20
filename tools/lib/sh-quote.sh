# shellcheck shell=bash
# tools/lib/sh-quote.sh — sh_quote STR: echoes STR wrapped in single quotes, safe to splice into a
# shell command string, with any embedded `'` doubled into `'\''` (the standard POSIX technique: close
# the quote, emit an escaped literal quote, reopen it). Shared by install-pre-pr-gate.sh and
# install-read-trace.sh's no-jq heredoc fallback (dir #514: both hand-rolled this identically — the
# same "keep two copies in sync by hand" shape that let the ORIGINAL bug in this same file ship
# unescaped in the first place). The jq-driven write path in both installers already gets this for
# free from jq's own `@sh` filter; this is the one place bash needs its own copy of the same
# algorithm, because a heredoc can't call a jq filter.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

sh_quote() {
  local s
  # Assignment RHS, deliberately UNQUOTED (found live by this ticket's own unit test): wrapping this
  # exact `${s//pat/repl}` expansion in double quotes changes how bash parses the backslashes in the
  # REPLACEMENT text and over-escapes it (`Alex's` -> `Alex\'\\'\'s`, not the intended `Alex'\''s`) —
  # a plain assignment's RHS is never word-split or glob-expanded regardless of quoting, so leaving it
  # bare here is safe AND is what actually produces the correct replacement.
  s=${1//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

# sh_quote_json STR — sh_quote's output, additionally escaped for embedding inside a JSON
# double-quoted string literal (dir #514 gap 2, found live by an independent /code-review medium
# line-by-line pass): sh_quote's own `'\''`-doubling introduces a literal backslash, and a bare `\'`
# is not one of JSON's recognized escape sequences — splicing sh_quote's raw output into a
# hand-written JSON heredoc (both installers' own no-jq print_snippet fallback, which can't call a
# jq filter to get this for free) produced INVALID JSON whenever the checkout path held an
# apostrophe (verified live: `jq .` on the printed snippet failed with "Invalid escape at line N"),
# even though the SHELL-level escaping was already correct — the bug just moved up one layer instead
# of being fixed. A literal `"` needs escaping too (dir #566: a checkout/HOME path containing `"` —
# splicing sh_quote's raw output into the hand-written JSON heredoc produced invalid JSON there as
# well, `jq .` failing with "Invalid numeric literal") — the backslash-doubling pass MUST run first,
# or the `\` it introduces for the `"` escape gets doubled too. Backslash and `"` are the only
# JSON-escaping sh_quote's own output ever needs: it never contains a control character, only
# printable path characters, `'`, `\`, and `"`, so a full general-purpose JSON-string escaper would
# be solving a problem this call site doesn't have.
sh_quote_json() {
  local q
  q="$(sh_quote "$1")"
  q="${q//\\/\\\\}"
  printf '%s' "${q//\"/\\\"}"
}
