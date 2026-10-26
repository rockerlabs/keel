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

# Reads files named on argv; prints `path<TAB>line number<TAB>trimmed line` per offending line. A replacement is the
# text after the second unescaped, unbracketed, unquoted `/` of a `${name/pat/rep}` / `${name//pat/rep}` /
# `${name/#pat/rep}` / `${name/%pat/rep}`; backslash escapes, '...', "..." and $'...' segments are dropped from it
# first, and any `$` left over is an unquoted interpolation. Comment-only lines are skipped.
scan_unquoted_replacements() {
  perl -e '
    my $b; $b = qr/(\$\{(?:[^{}]++|(?-1))*+\})/;
    for my $f (@ARGV) {
      open(my $h, "<", $f) or die "cannot read $f: $!";
      my $n = 0;
      while (my $l = <$h>) {
        $n++; chomp $l;
        next if $l =~ /^\s*#/;
        my $hit = 0;
        while ($l =~ /\$\{((?:[^{}]++|\{(?:[^{}]++|(?-1))*+\})*+)\}/g) {
          my $body = $1;
          next unless $body =~ m{^(?:[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[@*])(?:\[[^\]]*\])?(//?[#%]?)(.*)$}s;
          my $rest = $2; my ($pat, $rep) = ("", undef);
          my ($i, $len, $br) = (0, length $rest, 0);
          while ($i < $len) {
            my $c = substr($rest, $i, 1);
            if ($c eq "\\") { $i += 2; next }
            if ($c eq "\x27") { my $j = index($rest, "\x27", $i + 1); $i = $j < 0 ? $len : $j + 1; next }
            if ($c eq "\"") { $i++; while ($i < $len && substr($rest, $i, 1) ne "\"") { $i += substr($rest, $i, 1) eq "\\" ? 2 : 1 } $i++; next }
            if ($c eq "[") { my $j = index($rest, "]", $i + 2); $i = $j < 0 ? $len : $j + 1; next }
            if ($c eq "/") { $rep = substr($rest, $i + 1); last }
            $i++;
          }
          next unless defined $rep;
          $rep =~ s/\\.//gs; $rep =~ s/\$\x27[^\x27]*\x27//g; $rep =~ s/\x27[^\x27]*\x27//g; $rep =~ s/"[^"]*"//g;
          $hit = 1 if $rep =~ /\$/;
        }
        if ($hit) { (my $t = $l) =~ s/^\s+|\s+$//g; print "$f\t$n\t$t\n" }
      }
    }' -- "$@"
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
real="$(violations $(git ls-files 'tools/*.sh' tests/lib.sh))"
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
