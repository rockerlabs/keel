# shellcheck shell=bash
# tools/lib/personal-literals.sh — the ONE parser for the personal-literals file (the local,
# gitignored `secret-scan-personal`: one ERE per line, `#` comments). public-audit.sh sources it; the
# vendored tools/secret-guard/secret-scan.sh cannot (a vendored file may only source what ships beside
# it) and carries an inline IN-SYNC twin, `_personal_literals_parse_inline`, whose body is identical to
# the function below. tests/test_secret_guard.sh (the `dir #148` section) runs both on shared fixtures,
# compares them with a literal expected output, and asserts the two bodies are byte-identical — edit
# BOTH copies or that test goes red. dir #148: these were two hand-copied loops behind no pointer at all.
#
# Sourced, not executed — no shebang, no `set` (inherits the caller's).
#
# personal_literals_parse FILE — print the file's literals, one per line, in file order, duplicates kept.
# Each printed line is non-empty, has no leading/trailing whitespace and no leading `#`; a CR before the
# newline and an inline ` # comment` are stripped. A FILE that is not a regular file (absent, a
# directory, /dev/null) prints nothing and returns 0. A read failure on an existing file is NOT handled
# here: the function returns the failed redirect's non-zero status, and the caller must capture the
# output by a plain assignment (never `local x=$(…)`, never inside `if`/`||`/`&&`, never a process
# substitution — those hide the status).
#
# BRE `sed` on purpose (busybox-portable); the `[ -f ]` test is exact — a `[ -e ]` reads a directory with
# an error and blocks forever on a FIFO.
personal_literals_parse() {
  [ -f "$1" ] || return 0
  local _pl_t=""
  while IFS= read -r _pl_t || [ -n "$_pl_t" ]; do
    _pl_t="${_pl_t%$'\r'}"
    _pl_t="$(printf '%s' "$_pl_t" | sed 's/[[:space:]][[:space:]]*#.*$//; s/^[[:space:]][[:space:]]*//; s/[[:space:]][[:space:]]*$//')"
    case "$_pl_t" in
      ''|\#*) ;;
      *)      printf '%s\n' "$_pl_t" ;;
    esac
  done < "$1"
}
