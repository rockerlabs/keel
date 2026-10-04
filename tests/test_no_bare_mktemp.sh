#!/usr/bin/env bash
# test_no_bare_mktemp.sh — a static census of one leak shape in the test files (dir #437, caught by the 0.13.0
# delta audit; rebuilt by dir #663). A `mktemp` call in a test file whose template is not under $SANDBOX
# lands in the REAL temp dir, and on macOS a bare `mktemp` ignores $TMPDIR, so no redirect can catch it:
# install tests left PATH farms (one symlink per command on PATH) and a scratch checkout there on every run.
# tests/lib.sh removes $SANDBOX when a test file exits, so a path minted under it goes with it.
#
# This is the STATIC half. The DYNAMIC half is tests/run.sh's residue gate (dir #663 (b)): it traces what
# `mktemp` really minted during a full run and fails on any survivor — including the shapes no census of
# text can see (a cleared EXIT trap, a scratch file a tool keeps on purpose). The census stays because it
# names the line, and runs without a full suite.
#
# What it reads (dir #663 fold, 0.13.0 delta audit R2-6 and the DeepSeek round-3 CV-1): a small shell
# lexer, not a grep. It follows quotes (single, double, $'…'), `$( )` and backtick substitutions, comments
# and here-document bodies across lines, so it flags a `mktemp` in COMMAND position — however spelled
# (`$(mktemp`, `$( mktemp`, a backtick, `command mktemp`, `/usr/bin/mktemp`, `VAR=x mktemp`, a bare line, after
# a pipe) — and not the word inside a string, a fixture's own text, or a heredoc. A call is fine when its
# first template word is rooted at $SANDBOX in any quoting (`"$SANDBOX/x"`, `"$SANDBOX"/x`, `${SANDBOX}/x`,
# `-p "$SANDBOX"`). Everything else needs an allow-list entry.
#
# The allow-list is keyed by file, exact line text AND the number of lines allowed: a second copy of an
# allowed line is flagged, and an entry that matches fewer lines than it claims is reported stale, so the
# list cannot silently outlive the code it excuses. The census also refuses to pass on zero files, and
# reports a file whose quoting it could not balance (it would have read the rest of that file as text).
#
# Axis, named: this reads the literal text. A template held in a variable (`mktemp -d "$tpl"`) is flagged
# (unprovable), an `eval`ed or generated call is not seen, and a leak by another route (`mkdir /tmp/x`) is the
# residue gate's to catch only when it goes through `mktemp` on PATH.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "no unsandboxed mktemp in test files (dir #437, dir #663)"

# The allow-list — `file|count|exact (indent-trimmed) line`, each with its reason. Real tree only.
ALLOW_REAL='
test_install_pre_pr_gate.sh|1|btmp="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
test_self_citation_resolvability.sh|2|archive_dir="$(mktemp -d)"
'
# why: the first asserts the installer refuses a bootstrap-shaped temp clone, so the clone must sit in the real
# temp dir (the case removes it with `rm -rf "$btmp"`); the second is removed by its case's own `rm -rf
# "$archive_dir"` (out of the dir #437 fix's scope; it leaves nothing).

# the lexer: one awk program over every file given; prints `file<TAB>line<TAB>text` per flagged call
CENSUS_AWK='
function push(c) { stack = stack c }
function pop() { stack = substr(stack, 1, length(stack) - 1) }
function top() { return substr(stack, length(stack), 1) }
function incode(t) { return (t == "B" || t == "c" || t == "p" || t == "b") }
function words(s,   i, n, ch, q, w, inw) {
  NW = 0; w = ""; inw = 0; q = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    ch = substr(s, i, 1)
    if (q != "") { if (ch == q) q = ""; else w = w ch; continue }
    if (ch == "\"" || ch == Q) { q = ch; inw = 1; continue }
    if (ch == "\\") { w = w substr(s, i + 1, 1); i++; inw = 1; continue }
    if (ch ~ "[;&|)<>]") break
    if (ch == "#" && !inw) break
    if (ch == " " || ch == "\t") { if (inw) { W[++NW] = w; w = ""; inw = 0 } continue }
    w = w ch; inw = 1
  }
  if (inw) W[++NW] = w
}
function rooted(w) { return (w ~ "^\\$SANDBOX(/|$)" || w ~ "^\\$\\{SANDBOX\\}(/|$)") }
function sandboxed(   k) {
  for (k = 1; k <= NW; k++) {
    if (W[k] == "-p" || W[k] == "--tmpdir") { if (k < NW && rooted(W[k + 1])) return 1; k++; continue }
    if (W[k] ~ "^--tmpdir=") { if (rooted(substr(W[k], 10))) return 1; continue }
    if (W[k] ~ "^-") continue
    return rooted(W[k])
  }
  return 0
}
function command_pos(pre,   last, tok) {
  if (pre ~ "=$") return 0
  while (1) {
    sub(/[ \t]+$/, "", pre)
    if (pre == "") return 1
    last = substr(pre, length(pre), 1)
    if (last ~ "[;&|({`!)]") return 1
    tok = pre; sub(/^.*[ \t;&|(){`]/, "", tok)
    if (tok ~ "^(command|exec|builtin|env|nohup|time|then|do|else|elif|if|while|until)$") return 1
    if (tok ~ "^[A-Za-z_][A-Za-z0-9_]*=") { pre = substr(pre, 1, length(pre) - length(tok)); continue }
    return 0
  }
}
function finish() {
  if (curfile != "" && top() != "B" && length(stack) > 0 && stack != "B")
    printf "%s\t%d\t%s\n", curfile, 0, "(the lexer ended inside an open quote or substitution: the rest of this file was read as text)"
}
BEGIN { Q = "\047" }
FNR == 1 { finish(); curfile = FILENAME; sub(/^.*\//, "", curfile); stack = "B"; hd = "" }
{
  line = $0
  if (hd != "") { t = line; if (hdtab) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
  pend = ""; n = length(line)
  for (i = 1; i <= n; i++) {
    ch = substr(line, i, 1); t = top(); nx = substr(line, i + 1, 1)
    if (t == "s") { if (ch == Q) pop(); continue }
    if (t == "a") { if (ch == "\\") i++; else if (ch == Q) pop(); continue }
    if (ch == "\\") { i++; continue }
    if (t == "d") {
      if (ch == "\"") pop()
      else if (ch == "$" && nx == "(") { push("c"); i++ }
      else if (ch == "`") push("b")
      continue
    }
    if (ch == Q) { push("s"); continue }
    if (ch == "$" && nx == Q) { push("a"); i++; continue }
    if (ch == "\"") { push("d"); continue }
    if (ch == "#" && (i == 1 || substr(line, i - 1, 1) ~ "[ \t;&|(]")) break
    if (ch == "$" && nx == "(") { push("c"); i++; continue }
    if (ch == "(") { push("p"); continue }
    if (ch == ")") { if (t == "c" || t == "p") pop(); continue }
    if (ch == "`") { if (t == "b") pop(); else push("b"); continue }
    if (ch == "<" && nx == "<") {
      if (substr(line, i + 2, 1) == "<") { i += 2; continue }
      j = i + 2; tab = 0
      if (substr(line, j, 1) == "-") { tab = 1; j++ }
      while (substr(line, j, 1) == " " || substr(line, j, 1) == "\t") j++
      qc = substr(line, j, 1)
      if (qc == Q || qc == "\"") { j++; e = index(substr(line, j), qc); if (e > 0) { pend = substr(line, j, e - 1); pendtab = tab } }
      else if (qc ~ "[A-Za-z_]") { e = j; while (substr(line, e, 1) ~ "[A-Za-z0-9_]") e++; pend = substr(line, j, e - j); pendtab = tab }
      i++; continue
    }
    if (substr(line, i, 6) == "mktemp" && substr(line, i + 6, 1) !~ "[A-Za-z0-9_.-]") {
      j = i - 1
      while (j >= 1 && substr(line, j, 1) ~ "[A-Za-z0-9_./-]") j--
      pw = substr(line, j + 1, i - 1 - j)
      if (pw != "" && substr(pw, length(pw), 1) != "/") continue
      if (!command_pos(substr(line, 1, j))) continue
      words(substr(line, i + 6))
      if (!sandboxed()) { txt = line; sub(/^[ \t]+/, "", txt); printf "%s\t%d\t%s\n", curfile, FNR, txt }
    }
  }
  if (pend != "") { hd = pend; hdtab = pendtab }
}
END { finish() }
'

# census DIR ALLOWTABLE — flagged calls in DIR/test_*.sh, as `file:line: text`, then any stale allow-list
# entry. Excludes this file (its own fixture text and allow-list are the shapes it hunts).
census() {
  local dir="$1" table="$2" f file ln text flagged i hit n=0 efile ecount etext
  local -a files=() keys=() left=()
  for f in "$dir"/test_*.sh; do
    [ -f "$f" ] || continue
    [ "${f##*/}" = test_no_bare_mktemp.sh ] && continue
    files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || { printf 'VACUOUS: no test_*.sh files under %s\n' "$dir"; return 0; }
  flagged="$(awk "$CENSUS_AWK" "${files[@]}")"
  while IFS='|' read -r efile ecount etext; do
    [ -n "$efile" ] || continue
    keys[n]="$efile|$etext"; left[n]="$ecount"; n=$((n + 1))
  done <<< "$table"
  while IFS=$'\t' read -r file ln text; do
    [ -n "$file" ] || continue
    hit=0
    for ((i = 0; i < n; i++)); do
      if [ "${keys[i]}" = "$file|$text" ] && [ "${left[i]}" -gt 0 ]; then
        left[i]=$((left[i] - 1)); hit=1; break
      fi
    done
    [ "$hit" = 1 ] && continue
    printf '%s:%s: %s\n' "$file" "$ln" "$text"
  done <<< "$flagged"
  for ((i = 0; i < n; i++)); do
    [ "${left[i]}" -eq 0 ] || printf 'STALE allow-list entry (matched fewer lines than it claims, %s short): %s\n' "${left[i]}" "${keys[i]}"
  done
  return 0
}
# census_files DIR — how many files the census reads (the vacuity guard compares it with an independent count)
census_files() {
  local n=0 f
  for f in "$1"/test_*.sh; do
    [ -f "$f" ] || continue
    [ "${f##*/}" = test_no_bare_mktemp.sh ] && continue
    n=$((n + 1))
  done
  printf '%s' "$n"
}

# --- non-vacuity: the lexer flags what it should, and only that, on a planted tree ---------------------------------
plant="$(mktemp -d "$SANDBOX/plant.XXXXXX")"
cat > "$plant/test_planted.sh" <<'PLANT'
a="$(mktemp -d)"
b="$(mktemp)"
c="$(mktemp -d "$TMPDIR/c.XXXXXX")"
d="$(mktemp -d "$SANDBOX/d.XXXXXX")"
e="$(mktemp "${SANDBOX}/e.XXXXXX")"
  # a comment naming "$(mktemp -d)"
archive_dir="$(mktemp -d)"
f="$(mktemp -d "$SANDBOX/f.XXXXXX")" g="$(mktemp -d)"
h=`mktemp -d`
i="$( mktemp -d )"
j="$(command mktemp -d)"
k="$(/usr/bin/mktemp -d)"
TMPDIR="$SANDBOX" mktemp -d >/dev/null
mktemp -d >/dev/null
printf 'x\n' | mktemp
l="$(mktemp -d "$SANDBOX"/l.XXXXXX)"
m="$(mktemp -d -p "$SANDBOX" m.XXXXXX)"
n="$(mktemp -d -p "$HOME" n.XXXXXX)"
o="$(mktemp -d "$tpl")"
echo "mktemp -d failed"
cat > "$x/mktemp" <<EOF
body="$(mktemp -d)"
EOF
real_mktemp="$(command -v mktemp)"
path_farm "$farm" mktemp
fixture 'p="$(mktemp -d)"
q="$(mktemp)"
r=$(mktemp -d)'
s="$(mktemp -d "$SANDBOX/s.XXXXXX")"; t="$(mktemp -d)"
u=mktemp
v="$(true && mktemp -d)"
w="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
w="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
PLANT
planted_table='
test_planted.sh|1|archive_dir="$(mktemp -d)"
test_planted.sh|1|w="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
test_planted.sh|1|this line matches nothing
'
out="$(census "$plant" "$planted_table")"
ln_of() { grep -nF -- "$1" "$plant/test_planted.sh" | head -1 | cut -d: -f1; }
flagged() { check_contains "$1" "$out" "test_planted.sh:$(ln_of "$2"):"; }
unflagged() { check_absent "$1" "$out" "test_planted.sh:$(ln_of "$2"):"; }
flagged   "a bare \`mktemp -d\` is flagged" 'a="$(mktemp -d)"'
flagged   "a bare \`mktemp\` is flagged" 'b="$(mktemp)"'
flagged   "a template outside \$SANDBOX is flagged" 'c="$(mktemp -d "$TMPDIR/c.XXXXXX")"'
unflagged "a \$SANDBOX template is not flagged" 'd="$(mktemp -d "$SANDBOX/d.XXXXXX")"'
unflagged "a \${SANDBOX} template is not flagged" 'e="$(mktemp "${SANDBOX}/e.XXXXXX")"'
unflagged "a comment line is not flagged" '# a comment naming'
check_contains "a bare call sharing a line with a sandboxed one is flagged" "$out" "test_planted.sh:$(ln_of 'f="$(mktemp -d "$SANDBOX/f.XXXXXX")" g=')"
flagged   "a backtick call is flagged" 'h=`mktemp -d`'
flagged   "a spaced \$( mktemp ) call is flagged" 'i="$( mktemp -d )"'
flagged   "\`command mktemp\` is flagged" 'j="$(command mktemp -d)"'
flagged   "an absolute-path call is flagged" 'k="$(/usr/bin/mktemp -d)"'
flagged   "TMPDIR=\$SANDBOX in front is flagged (macOS ignores TMPDIR)" 'TMPDIR="$SANDBOX" mktemp -d'
flagged   "a call that is its own command (no substitution) is flagged" 'mktemp -d >/dev/null'
flagged   "a call after a pipe is flagged" "printf 'x\\n' | mktemp"
unflagged "\"\$SANDBOX\"/name (the quote closes before the slash) is not flagged" 'l="$(mktemp -d "$SANDBOX"/l.XXXXXX)"'
unflagged "-p \"\$SANDBOX\" is not flagged" 'm="$(mktemp -d -p "$SANDBOX" m.XXXXXX)"'
flagged   "-p with a directory outside the sandbox is flagged" 'n="$(mktemp -d -p "$HOME" n.XXXXXX)"'
flagged   "a template held in a variable is flagged (unprovable)" 'o="$(mktemp -d "$tpl")"'
unflagged "the word inside a double-quoted message is not flagged" 'echo "mktemp -d failed"'
unflagged "a path to a shim named mktemp, inside quotes, is not flagged" 'cat > "$x/mktemp" <<EOF'
unflagged "a heredoc body is not flagged" 'body="$(mktemp -d)"'
unflagged "command -v mktemp is not a call" 'real_mktemp="$(command -v mktemp)"'
unflagged "mktemp as an argument is not a call" 'path_farm "$farm" mktemp'
check_absent "a multi-line single-quoted fixture's text is not flagged (first line)" "$out" "test_planted.sh:$(ln_of "fixture 'p=")"
check_absent "... (second line)" "$out" "test_planted.sh:$(ln_of 'q="$(mktemp)"'):"
check_absent "... (third line)" "$out" "test_planted.sh:$(ln_of 'r=$(mktemp -d)'"'"):"
check_contains "a bare call after a sandboxed one with ; on a line is flagged" "$out" "test_planted.sh:$(ln_of 's="$(mktemp -d "$SANDBOX/s.XXXXXX")"; t=')"
unflagged "a value that merely spells mktemp (u=mktemp) is not a call" 'u=mktemp'
flagged   "a call after && inside a substitution is flagged" 'v="$(true && mktemp -d)"'
# allow-list: exact text AND count
check_absent "an allow-listed line is not flagged" "$out" "test_planted.sh:$(ln_of 'archive_dir="$(mktemp -d)"'):"
check_eq "an allow-list entry with count 1 excuses ONE of two identical lines; the second is flagged" 1 \
  "$(printf '%s\n' "$out" | grep -cF 'w="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"')"
check_contains "an entry that matches nothing is reported stale" "$out" "STALE allow-list entry"
check_contains "... naming it" "$out" "this line matches nothing"
# every offending line, exactly (the count binds the whole detector at once)
check_eq "exactly these lines are reported (offenders + the one flagged duplicate + the stale entry)" 17 "$(printf '%s\n' "$out" | grep -c .)"
# a per-file allow-list: an allow-listed line in ANOTHER file is still flagged
printf '%s\n' 'archive_dir="$(mktemp -d)"' > "$plant/test_other.sh"
out2="$(census "$plant" "$planted_table")"
check_contains "an allow-listed line in ANOTHER file is still flagged (the allow-list is per file)" "$out2" "test_other.sh:1:"
# a file whose quotes never close
mkdir -p "$SANDBOX/unbalanced"
printf '%s\n' "x='never closed" 'y="$(mktemp -d)"' > "$SANDBOX/unbalanced/test_open.sh"
out3="$(census "$SANDBOX/unbalanced" '')"
check_contains "a file the lexer cannot balance is reported, not silently read as text" "$out3" "the lexer ended inside an open quote"
# zero files
mkdir -p "$SANDBOX/empty-tests"
out4="$(census "$SANDBOX/empty-tests" '')"
check_contains "zero files is reported, never a pass" "$out4" "VACUOUS"

# --- the real census ------------------------------------------------------------------------------------------------
out="$(census "$TESTS_DIR" "$ALLOW_REAL")"
nfiles="$(census_files "$TESTS_DIR")"
indep="$(find "$TESTS_DIR" -maxdepth 1 -name 'test_*.sh' ! -name test_no_bare_mktemp.sh | wc -l | tr -d ' ')"
check_ne "the census reads at least one test file" "$nfiles" 0
check_eq "the census reads exactly the files an independent count finds" "$indep" "$nfiles"
if [ -z "$out" ]; then
  pass "no tests/test_*.sh mints scratch outside \$SANDBOX beyond the allow-list"
else
  fail "no tests/test_*.sh mints scratch outside \$SANDBOX beyond the allow-list" \
    "mint it under the sandbox instead (mktemp -d \"\$SANDBOX/name.XXXXXX\"), or fix the allow-list:
$out"
fi

summary
