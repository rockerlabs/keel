# shellcheck shell=bash
# tools/lib/personal-literals.sh — the ONE parser for the personal-literals file (the local,
# gitignored `secret-scan-personal`: one ERE per line, `#` comments). public-audit.sh sources it; the
# vendored tools/secret-guard/secret-scan.sh cannot (a vendored file may only source what ships beside
# it) and carries an inline IN-SYNC twin, `_personal_literals_parse_inline`, whose body is identical to
# the function below. tests/test_secret_guard.sh (the `dir #148` section) runs both on shared fixtures,
# compares them with a literal expected output, and asserts the two bodies are byte-identical — edit
# BOTH copies or that test goes red.
#
# Sourced, not executed — no shebang, no `set` (inherits the caller's).
#
# personal_literals_parse FILE — print the file's literals, one per line, in file order, duplicates kept.
# Each printed line is non-empty, has no leading/trailing whitespace and no leading `#`; a leading UTF-8
# BOM (first line only), a CR before the newline and an inline ` # comment` are stripped. A FILE that is
# not a regular file (absent, a directory, /dev/null) prints nothing and returns 0. Status:
#   0  every line parsed
#   2  FILE exists but is unreadable (dir #680) — nothing printed, nothing on stderr: the caller says so
#   3  a line ends in an ODD run of backslashes (dir #680) — that line is NOT printed (joined with the
#      next line it would become `prev\|next`, a valid ERE matching neither literal), every other line is
#   other non-zero: a read failure on an existing, readable file (the failed redirect's status)
# Callers capture the output by `x="$(…)" || rc=$?` — a PLAIN assignment, never `local x=$(…)`, never a
# process substitution (those hide the status) — and treat ANY non-zero status as "do not trust the
# literals": secret-scan.sh exits 2, public-audit.sh raises a GAP (it still uses the lines printed on 3).
#
# BRE `sed` on purpose (busybox-portable); the `[ -f ]` test is exact — a `[ -e ]` reads a directory with
# an error and blocks forever on a FIFO.
personal_literals_parse() {
  [ -f "$1" ] || return 0
  [ -r "$1" ] || return 2
  local _pl_t="" _pl_first=1 _pl_rc=0 _pl_run=""
  while IFS= read -r _pl_t || [ -n "$_pl_t" ]; do
    if [ "$_pl_first" = 1 ]; then
      _pl_t="${_pl_t#$'\357\273\277'}"
      _pl_first=0
    fi
    _pl_t="${_pl_t%$'\r'}"
    _pl_t="$(printf '%s' "$_pl_t" | sed 's/[[:space:]][[:space:]]*#.*$//; s/^[[:space:]][[:space:]]*//; s/[[:space:]][[:space:]]*$//')"
    case "$_pl_t" in
      ''|\#*) ;;
      *)
        _pl_run="${_pl_t##*[!\\]}"
        if [ $(( ${#_pl_run} % 2 )) -eq 1 ]; then
          _pl_rc=3
        else
          printf '%s\n' "$_pl_t"
        fi ;;
    esac
  done < "$1" || return $?
  return "$_pl_rc"
}
