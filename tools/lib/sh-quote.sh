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
