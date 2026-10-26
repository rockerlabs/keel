#!/usr/bin/env bash
# test_patsub_quoting.sh (dir #859) — static pin for the bash >= 5.2 patsub_replacement class.
#
# bash >= 5.2 turns `patsub_replacement` on by default, so an unquoted `&` in the REPLACEMENT of
# `${v/pat/rep}` / `${v//pat/rep}` stands for the matched text. A replacement that interpolates a variable
# (`$HOME`, `$SANDBOX/...`) therefore corrupts the result whenever the value holds a `&` (a path can). The
# fix is to quote the replacement and leave the assignment itself unquoted: `x=${x//pat/"$rep"}` is the one
# form that yields a literal `&` on bash 3.2 and 5.2 alike (an outer double quote keeps the inner quotes
# literally on 3.2).
#
# This file scans every tracked `tools/**/*.sh` and `tests/lib.sh` for a replacement carrying an unquoted
# `$` and fails on any that is not in ALLOW below (each entry: `path<TAB>line content`, with its reason). It
# reads text, so it runs on every leg, bash 3.2 included. Fixtures prove the scanner goes red on an unquoted
# replacement and on one real site (tools/doctor.sh's `~` expansion) with its quotes removed.
#
# Keel-self-maintenance: it scans keel's own tools/ tree and tests/lib.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# replacement_has_unquoted_dollar TEXT — TEXT is the part of a `${name/pat/rep}` body after the op. Walks it to the first
# unescaped `/` outside '...', "...", and a [...] bracket expression (that ends the pattern), then walks the replacement
# skipping backslash escapes, '...', $'...' and "..." segments; true when a `$` is left, i.e. an unquoted interpolation.
replacement_has_unquoted_dollar() {
  local t="$1" i=0 n c j
  n=${#t}
  while [ "$i" -lt "$n" ]; do
    c="${t:i:1}"
    case "$c" in
      '\') i=$((i + 2)) ;;
      "'") i=$((i + 1)); while [ "$i" -lt "$n" ] && [ "${t:i:1}" != "'" ]; do i=$((i + 1)); done; i=$((i + 1)) ;;
      '"') i=$((i + 1)); while [ "$i" -lt "$n" ] && [ "${t:i:1}" != '"' ]; do
             if [ "${t:i:1}" = '\' ]; then i=$((i + 2)); else i=$((i + 1)); fi
           done; i=$((i + 1)) ;;
      '[') j=$((i + 2)); while [ "$j" -lt "$n" ] && [ "${t:j:1}" != ']' ]; do j=$((j + 1)); done; i=$((j + 1)) ;;
      /) i=$((i + 1)); break ;;
      *) i=$((i + 1)) ;;
    esac
  done
  [ "$i" -le "$n" ] || return 1
  # no second `/` found (a plain `${v/pat}` deletion) leaves i at n: nothing to inspect
  while [ "$i" -lt "$n" ]; do
    c="${t:i:1}"
    case "$c" in
      '\') i=$((i + 2)) ;;
      "'") i=$((i + 1)); while [ "$i" -lt "$n" ] && [ "${t:i:1}" != "'" ]; do i=$((i + 1)); done; i=$((i + 1)) ;;
      '"') i=$((i + 1)); while [ "$i" -lt "$n" ] && [ "${t:i:1}" != '"' ]; do
             if [ "${t:i:1}" = '\' ]; then i=$((i + 2)); else i=$((i + 1)); fi
           done; i=$((i + 1)) ;;
      '$')
        if [ "${t:i+1:1}" = "'" ]; then
          i=$((i + 2)); while [ "$i" -lt "$n" ] && [ "${t:i:1}" != "'" ]; do i=$((i + 1)); done; i=$((i + 1))
        else
          return 0
        fi ;;
      *) i=$((i + 1)) ;;
    esac
  done
  return 1
}

# line_has_unquoted_replacement LINE — true when any `${name/pat/rep}`-shaped expansion on LINE carries an unquoted `$` in rep.
line_has_unquoted_replacement() {
  local rest="$1" body depth i n c
  local re='^[!]?([A-Za-z_][A-Za-z_0-9]*|[0-9]+|[@*])(\[[^]]*\])?//?[#%]?'
  while case "$rest" in *'${'*) true ;; *) false ;; esac; do
    rest="${rest#*'${'}"
    depth=1; i=0; n=${#rest}
    while [ "$i" -lt "$n" ]; do
      c="${rest:i:1}"
      case "$c" in '{') depth=$((depth + 1)) ;; '}') depth=$((depth - 1)); [ "$depth" -gt 0 ] || break ;; esac
      i=$((i + 1))
    done
    body="${rest:0:i}"
    if [[ "$body" =~ $re ]]; then
      replacement_has_unquoted_dollar "${body:${#BASH_REMATCH[0]}}" && return 0
    fi
  done
  return 1
}

# scan_unquoted_replacements FILE... — one `path<TAB>line number<TAB>trimmed line` per offending line; comment-only lines are
# skipped. grep prefilters the candidates so the character walk runs on a handful of lines, not on every line of tools/.
scan_unquoted_replacements() {
  local f num line t
  for f in "$@"; do
    while IFS= read -r line; do
      num="${line%%:*}"; line="${line#*:}"
      t="${line#"${line%%[![:space:]]*}"}"
      case "$t" in '#'*) continue ;; esac
      if line_has_unquoted_replacement "$line"; then printf '%s\t%s\t%s\n' "$f" "$num" "${t%"${t##*[![:space:]]}"}"; fi
    done < <(grep -n -E '\$\{[!]?[A-Za-z_0-9@*]+(\[[^]]*\])?//?' "$f" || true)
  done
}

# Replacements proven free of a `&`: `path<TAB>needle<TAB>reason`, matched when the offending line contains the needle.
# An edit to the needle re-opens the question; a line move does not.
ALLOW='tools/self/accumulate.sh	${rec//$US/$NL}	$NL is a newline, set once in this file
tests/lib.sh	${s// /${ch}}	$ch is the two bytes of one Cyrillic letter'

# violations FILE... — scanner hits that ALLOW does not cover, as `path:line: content`.
violations() {
  local path num content nf nn nr ok
  while IFS=$'\t' read -r path num content; do
    [ -n "$path" ] || continue
    ok=0
    while IFS=$'\t' read -r nf nn nr; do
      [ -n "$nf" ] || continue
      if [ "$nf" = "$path" ] && [ -n "$nr" ]; then case "$content" in *"$nn"*) ok=1 ;; esac; fi
    done <<<"$ALLOW"
    [ "$ok" = 1 ] || printf '%s:%s: %s\n' "$path" "$num" "$content"
  done < <(scan_unquoted_replacements "$@")
}

cd "$REPO_ROOT" || exit 1

# --- the real tree ---------------------------------------------------------------------------------
# shellcheck disable=SC2046  # tracked names in tools/ hold no whitespace (git ls-files, one per line)
real="$(violations $(git ls-files 'tools/*.sh' tools/secret-guard/pre-commit tools/secret-guard/pre-push tests/lib.sh))"
if [ -z "$real" ]; then
  pass "no tools/**/*.sh or tests/lib.sh replacement carries an unquoted \$ outside the allow-list"
else
  fail "no tools/**/*.sh or tests/lib.sh replacement carries an unquoted \$ outside the allow-list" \
    "quote it as x=\${x//pat/\"\$rep\"} (assignment unquoted), or allow-list it with its reason:
$real"
fi

# --- fixtures: the scanner must go red, or the green above proves nothing --------------------------
fx="$SANDBOX/patsub-fx"; mkdir -p "$fx"
printf '%s\n' 'x=${x//a/$b}' 'y="${p/#\~/$HOME}"' 'w=${w//a/${HOME:-}/z}' 'v=${1//a/$b}' > "$fx/bad.sh"
check_eq "fixture: four unquoted variable-bearing replacements are all reported" 4 "$(violations "$fx/bad.sh" | wc -l | tr -d ' ')"
printf '%s\n' 'x=${x//a/"$b"}' 'y=${p/#\~/"$HOME"}' 'z=${z//$pat/x}' 'n=${n//$'"'"'\n'"'"'/ }' 'q=${q//a/\$b}' \
  '# c=${c//a/$b}' 'e=${e//[\/.]/-}' > "$fx/good.sh"
check_eq "fixture: quoted, pattern-only, \$'..', escaped and commented forms are not reported" "" "$(violations "$fx/good.sh")"

# One real site with its quotes removed: tools/doctor.sh's `~` expansion.
site='path=${path/#\~/"$HOME"}'
if grep -q -F -- "$site" tools/doctor.sh; then
  sed 's|path=${path/#\\~/"$HOME"}|path=${path/#\\~/$HOME}|' tools/doctor.sh > "$fx/doctor-reverted.sh"
  if [ -n "$(violations "$fx/doctor-reverted.sh")" ]; then
    pass "fixture: tools/doctor.sh with one \`~\` expansion left unquoted turns the scanner red"
  else
    fail "fixture: tools/doctor.sh with one \`~\` expansion left unquoted turns the scanner red" "no violation reported"
  fi
else
  fail "fixture: tools/doctor.sh still holds the quoted \`~\` expansion this fixture reverts" "missing: $site"
fi

summary
