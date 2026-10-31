#!/usr/bin/env bash
# test_redirect_order.sh — dir #887: redirections apply left to right, so `cmd < file 2>/dev/null` prints the
# shell's own "Permission denied" for an unreadable file before stderr is silenced. Put the stderr redirect
# first (`cmd 2>/dev/null < file`). This lint refuses the pattern in every tracked non-test .sh file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

export LC_ALL=C
AWK_PROG='
/^[[:space:]]*#/ { next }
{
  s = $0
  while (match(s, /<[[:space:]]*[^[:space:]<(&|;]+/)) {
    pre = substr(s, RSTART - 1, 1); tgt = substr(s, RSTART, RLENGTH); rest = substr(s, RSTART + RLENGTH)
    sub(/^<[[:space:]]*/, "", tgt)
    if (pre != "<" && pre !~ /[0-9]/ && tgt != "/dev/null" && tgt !~ /^[<(]/) {
      seg = rest; sub(/[|;&].*/, "", seg)
      if (seg ~ /2>/) { print FILENAME ":" FNR ": " $0; break }
    }
    s = rest
  }
}'

# Lint over the tracked tree (tests/ excluded: they plant bad forms on purpose).
# A scan that could not run must fail, never pass as "no hits".
files="$(cd "$REPO_ROOT" && git ls-files -z -- '*.sh' ':!tests/' | tr '\0' '\n')" || files=""
if [ -z "$files" ]; then
  fail "lint scans the tracked tools" "git ls-files listed no .sh files"
else
  hits="$(cd "$REPO_ROOT" && printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 awk "$AWK_PROG")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "lint scans the tracked tools" "awk/xargs failed (rc=$rc)"
  elif [ -z "$hits" ]; then
    pass "no 'cmd < file 2>…' input-before-stderr redirect in tracked tools"
  else
    fail "no 'cmd < file 2>…' input-before-stderr redirect in tracked tools" "$hits"
  fi
fi

# Self-rows on a scratch file: the lint reports the bad form and stays quiet on the fixed forms.
scratch="$SANDBOX/redirect-order-probe.sh"
printf '%s\n' 'bad < "$x" 2>/dev/null' > "$scratch"
out="$(awk "$AWK_PROG" "$scratch")"
check_contains "self-row: planted bad form is reported" "$out" 'bad < "$x" 2>/dev/null'
cat > "$scratch" <<'FIXED'
wc -c 2>/dev/null < "$1" | tr -d ' '
cat 2>"$e" > "$o" < "$f"
grep -q x >/dev/null 2>&1 < "$p"
FIXED
out="$(awk "$AWK_PROG" "$scratch")"
check_eq "self-row: fixed forms are not reported" "" "$out"

summary
