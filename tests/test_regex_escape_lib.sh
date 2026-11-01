#!/usr/bin/env bash
# test_regex_escape_lib.sh — dir #428: tools/lib/regex-escape.sh is the ONE literal-regex escape builder.
# Pins its output, the escaped text actually matching only itself under grep (BRE and ERE) and sed, and the
# deliberately-inlined copy in tools/changelog-section.sh staying in step with it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/regex-escape.sh"
check_file "tools/lib/regex-escape.sh exists" "$lib"
# shellcheck source=tools/lib/regex-escape.sh
. "$lib"

check_eq "plain version: dots escaped" '0\.9\.0' "$(escape_bre_literal '0.9.0')"
check_eq "heading: both brackets escaped (the closing ] is the class the old copies missed)" \
  '## \[0\.9\.0\]' "$(escape_bre_literal '## [0.9.0]')"
check_eq "backslash, star, caret, dollar escaped" 'a\\b\*\^\$' "$(escape_bre_literal 'a\b*^$')"
check_eq "'#' and '/' pass through unless named as extra" 'a#b/c' "$(escape_bre_literal 'a#b/c')"
check_eq "extra delimiter chars are escaped" 'a\#b\/c' "$(escape_bre_literal 'a#b/c' '#/')"
check_eq "+ ? | ( ) { } stay literal (a backslash would turn on GNU BRE operators)" 'a+b?c|(d){e}' \
  "$(escape_bre_literal 'a+b?c|(d){e}')"
check_eq "empty string -> empty" '' "$(escape_bre_literal '')"

# The escaped text must match ONLY the literal, in BRE, ERE and as a sed pattern.
for lit in '## [1.2.3]' 'a.b' 'x]y' '[x' 'a*b' '^c$' 'back\slash'; do
  esc="$(escape_bre_literal "$lit")"
  if printf '%s\n' "$lit" | grep -q "^$esc\$" && printf '%s\n' "$lit" | grep -qE "^$esc\$"; then
    pass "literal '$lit' matches itself (grep BRE + ERE)"
  else fail "literal '$lit' matches itself (grep BRE + ERE)" "escaped as: $esc"; fi
  if printf '%s\n' "$lit" | sed "s/^$esc\$/HIT/" | grep -qx HIT; then
    pass "literal '$lit' matches itself (sed)"
  else fail "literal '$lit' matches itself (sed)" "escaped as: $esc"; fi
done
esc="$(escape_bre_literal 'a.b')"
if printf 'axb\n' | grep -q "^$esc\$"; then fail "an escaped '.' does not match another character" "matched axb"
else pass "an escaped '.' does not match another character"; fi

# '#' as the sed delimiter (the use that tests/test_tour_transcript.sh makes of the extra argument).
esc="$(escape_bre_literal '/a#b.c/' '#')"
check_eq "extra '#': a path holding the delimiter substitutes cleanly" 'X' \
  "$(printf '/a#b.c/\n' | sed "s#^$esc\$#X#")"

# tools/changelog-section.sh keeps an inline copy ON PURPOSE (copy-portable alone): its sed must produce the
# same output as the lib for every version-shaped input.
copy_cmd="$(grep -E '^escaped_version=' "$REPO_ROOT/tools/changelog-section.sh" | grep -o "sed '[^']*'" || true)"
check_ne "tools/changelog-section.sh still has its inline escape" '' "$copy_cmd"
for v in '0.9.0' '1.2.3-rc.1' '[x]' 'a\b'; do
  got="$(printf '%s' "$v" | eval "$copy_cmd")"
  check_eq "changelog-section's inline copy agrees with the lib on '$v'" "$(escape_bre_literal "$v")" "$got"
done

# No other inline copy of the same class may creep back into the tree (the drift this lib closed).
hits="$(grep -rnF -e "s/[][\\.*^\$" -e "sed_escape()" "$REPO_ROOT/tools" "$REPO_ROOT/tests" 2>/dev/null \
  | grep -vF -e "$lib" -e "tools/changelog-section.sh" -e "tests/test_regex_escape_lib.sh" || true)"
check_eq "no other inline copy of the literal-escape sed exists" '' "$hits"

summary
