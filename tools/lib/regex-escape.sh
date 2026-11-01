# shellcheck shell=bash
# tools/lib/regex-escape.sh — keel-self-maintenance (dir #68): escape_bre_literal builds the text of a
# regex that matches a string LITERALLY. One shared builder (dir #428) replaces three inline copies whose
# character classes had drifted apart (one missed `]`, one missed `]` and `/`).
#
# Sourced, not executed — no shebang, no `set -e` (inherits the caller's).
#
# escape_bre_literal STRING [EXTRA] — print STRING with a backslash put before each of `] [ \ . * ^ $`,
# plus before every character of EXTRA (the delimiter of the `sed s` the result is interpolated into, e.g.
# `/` or `#`). The result is a literal in POSIX BRE, and in ERE too for any STRING free of `+ ? | ( ) { }`
# (versions and `## [x.y.z]` headings are). It deliberately does NOT
# escape `+ ? | ( ) { }`: they are ordinary characters in a POSIX BRE, and a backslash before them turns
# on GNU's non-portable BRE operators (`\+`, `\?`, `\|`), so escaping a literal `+` would make it a
# quantifier. A caller that feeds the result to `grep -E` or the git pickaxe must therefore not pass a string holding those.
# EXTRA must not hold a character with a meaning inside a bracket expression (`]`, `\`, `^`, `-`).
#
# tools/changelog-section.sh keeps its own copy ON PURPOSE (it must stay copy-portable alone — see its
# header); tests/test_regex_escape_lib.sh pins that copy to this one.
escape_bre_literal() {
  printf '%s' "$1" | sed "s/[][\\.*^\$${2:-}]/\\\\&/g"
}
