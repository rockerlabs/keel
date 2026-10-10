#!/usr/bin/env bash
# tools/self/mutation-sweep.sh — keel-self-maintenance (dir #745, dir #68: never installed by install.sh).
#
# A re-runnable mutation sweep: for each row of a checked-in mutant list, break the named file in ONE way,
# run a test file against the broken copy, and report whether the test file noticed. A mutant the tests do
# not notice (SURVIVED) is a clause nothing guards — the class dir #745's S7-2 filed (16 of 40 push-rule
# clauses unguarded). A one-off proof in a PR body rots; this tool plus a list that
# tests/test_mutation_lists.sh keeps current does not.
#
# Usage: tools/self/mutation-sweep.sh <list> [<test-file>]
#        tools/self/mutation-sweep.sh --check <list>
#   <list>       a TSV, one mutant per line: id<TAB>file<TAB>needle<TAB>replacement<TAB>note. Read with awk -F'\t'
#                (never a bash `IFS` read, which collapses an empty field). `#` lines and blank lines are
#                ignored. In the needle and the replacement `\t`, `\n` and `\\` are decoded; the replacement
#                may be empty (a deletion mutant). `file` is relative to the checkout's top level.
#   <test-file>  the suite to run per mutant, relative to the top level; default tests/test_pre_pr_gate_lexer.sh.
#   --check      validate the list against the WORKING TREE, run nothing: five fields, an id unique in the list,
#                a needle occurring exactly once in its file, a replacement that differs from the needle, a file path
#                that is relative, without `..`, and neither a symlink nor under one. One problem per line on
#                stdout; exit 0 when the list is sound, 1 otherwise. tests/test_mutation_lists.sh is its caller —
#                one parser and one path rule, so the sweep (which tests committed HEAD, and refuses a dirty named
#                file) and the staleness check agree on a row whenever the named files are clean.
#   KEEL_SWEEP_TIMEOUT   seconds per test run (default 600), via `perl -e 'alarm shift; exec @ARGV'`.
#
# Run from inside a keel checkout; the repo is that checkout's top level. The sweep tests COMMITTED HEAD: it
# refuses (exit 2) when a file the list names, or the test file, has a tracked change, staged or not (an
# untracked file is ignored), then `git clone --no-hardlinks`s the top level into a `mktemp -d` under
# ${TMPDIR:-/tmp} and detaches at the checkout's HEAD sha. It never writes outside that clone, which is removed
# at exit (its path is printed if removal fails). It first runs the test file unmutated, under the same
# timeout; unless that run has a summary with failed = 0 it aborts (exit 2) — a broken baseline would make
# every mutant look killed.
#
# A run's summary is the last line of the test file's output matching `: N passed, M failed`; its failed count
# is M. Per mutant the needle must occur exactly once in the file, counted as substring occurrences,
# overlapping ones included (else BADNEEDLE; so is a row naming a tracked symlink, or a file under one); it is replaced literally; the file
# must change (else NOCHANGE). Outcome: TIMEOUT (exit status 142), else CRASHED (no summary), else KILLED (failed >= 1)
# or SURVIVED (failed = 0). The file is restored from git after each mutant. Known limits: the timeout kills the test
# file's bash, not its children — a mutant that makes a child (the gate's awk) spin leaves that child running after
# TIMEOUT; and a mutant file that lacks a final newline gains one (awk reads lines).
#
# Output: one line per mutant, `<id><TAB><outcome><TAB><summary, or ->`, then
# `N killed, S survived, T timeout, C crashed, B bad` (B counts BADNEEDLE and NOCHANGE). Exit 0 when S = 0 and
# B = 0; 1 otherwise; 2 for a refusal or an abort. TIMEOUT and CRASHED are not survivors (the suite did not
# pass) but are printed so a reader can check each is a real kill.
set -euo pipefail
# drop an inherited repo selector before any git call (the dir #647 convention shared by tools/).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

usage() { printf 'usage: mutation-sweep.sh <list> [<test-file>]\n       mutation-sweep.sh --check <list>\n' >&2; exit 2; }
refuse() { printf 'mutation-sweep: %s\n' "$*" >&2; exit 2; }
# path_shape_bad REL — 0 when REL is not a path relative to the top level without `..` (empty, absolute, or climbing).
path_shape_bad() {
  case "$1" in ''|/*|..|../*|*/..|*/../*) return 0 ;; esac
  return 1
}
# via_symlink ROOT REL — 0 when REL, or any directory on its way, is a symlink under ROOT: a write there leaves the
# clone.
via_symlink() {
  local p="$1" rest="$2" part
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    p="$p/$part"
    [ -L "$p" ] && return 0
  done
  return 1
}
# path_problem ROOT REL — prints why REL cannot be a mutant target under ROOT (nothing when it can); the ONE path
# rule, applied by --check (to the working tree) and by the sweep (to its clone).
path_problem() {
  if path_shape_bad "$2"; then echo "must be a path relative to the top level without '..'"
  elif via_symlink "$1" "$2"; then echo "is, or lies under, a symlink"
  fi
  return 0
}
# shellcheck source=tools/lib/nonneg-int.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/nonneg-int.sh"

# One awk program, three modes (-v mode=): `list` prints `<row>\t<id>\t<file>` per mutant row; `check` prints one
# problem per bad row; `mutate` (-v want=<row>) writes row <want>'s mutated file to -v out= and prints OK,
# BADNEEDLE\t<why> or NOCHANGE. No single quote appears below: the program lives in a shell single-quoted string.
AWK_PROG='
function decode(s,   o, i, c, d) {
  o = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < length(s)) {
      d = substr(s, i + 1, 1)
      if (d == "t") { o = o "\t"; i++; continue }
      if (d == "n") { o = o "\n"; i++; continue }
      if (d == "\\") { o = o "\\"; i++; continue }
    }
    o = o c
  }
  return o
}
function slurp(path,   line, rc, got) {
  got = ""
  rc = (getline line < path)
  if (rc < 0) { slurp_ok = 0; return "" }
  slurp_ok = 1
  while (rc > 0) { got = got line "\n"; rc = (getline line < path) }
  close(path)
  return got
}
function count(hay, n,   c, p) {
  c = 0
  if (n == "") return 0
  while ((p = index(hay, n)) > 0) { c++; hay = substr(hay, p + 1) }
  return c
}
function load(file) {
  if (!(file in have)) { body[file] = slurp(root "/" file); have[file] = slurp_ok }
}
# The ONE validity rule a row must meet (check and mutate both use it): "" when sound, else the problem.
function problem(nf, file, needle,   n) {
  if (nf != 5) return nf " fields, want 5"
  load(file)
  if (!have[file]) return "file " file " not found"
  n = count(body[file], needle)
  if (n != 1) return "needle occurs " n " times in " file ", want 1"
  return ""
}
/^#/ || /^[ \t]*$/ { next }
{
  row++
  if (mode == "list") { printf "%d\t%s\t%s\n", row, ($1 == "" ? "-" : $1), $2; next }
  if (mode == "mutate" && row != want) next
  id = $1; file = $2
  needle = decode($3); repl = decode($4)
  why = problem(NF, file, needle)
  if (mode == "check") {
    if (id in seen) print id ": id repeated"
    seen[id] = 1
    if (why != "") print id ": " why
    if (NF == 5 && needle == repl) print id ": replacement equals needle"
    next
  }
  if (why != "") { print "BADNEEDLE\t" why; next }
  if (needle == repl) { print "NOCHANGE"; next }
  p = index(body[file], needle)
  printf "%s", substr(body[file], 1, p - 1) repl substr(body[file], p + length(needle)) > out
  close(out)
  print "OK"
}
'

mode=sweep
if [ "${1:-}" = "--check" ]; then
  mode=check; shift
fi
case "${1:-}" in -h|--help) usage ;; esac
if [ "$mode" = check ]; then
  [ "$#" -eq 1 ] || usage
else
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
fi
list="$1"; tfile="${2:-tests/test_pre_pr_gate_lexer.sh}"
[ -f "$list" ] || refuse "no such list: $list"

top="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git checkout"

if [ "$mode" = check ]; then
  nl=$'\n'
  problems="$(awk -F'\t' -v mode=check -v root="$top" "$AWK_PROG" "$list")"
  while IFS=$'\t' read -r _row _id file; do
    why="$(path_problem "$top" "$file")"
    [ -z "$why" ] || problems="$problems${problems:+$nl}$_id: $file $why"
  done <<EOF
$(awk -F'\t' -v mode=list "$AWK_PROG" "$list")
EOF
  if [ -n "$problems" ]; then printf '%s\n' "$problems"; exit 1; fi
  exit 0
fi

command -v perl >/dev/null 2>&1 || refuse "perl is required: the per-run timeout is a perl alarm"
timeout="${KEEL_SWEEP_TIMEOUT:-600}"
{ _nonneg_int_valid "$timeout" && [ "$timeout" -gt 0 ]; } || refuse "KEEL_SWEEP_TIMEOUT must be a positive integer (got '$timeout')"

rows="$(awk -F'\t' -v mode=list "$AWK_PROG" "$list")"
[ -n "$rows" ] || refuse "the list has no mutant rows: $list"

# files the sweep touches: every file the list names, plus the test file — each must be a clean path inside the
# checkout (relative, no `..`) and carry no tracked change (git status takes a repeated path in stride).
set --
while IFS=$'\t' read -r _row _id file; do
  ! path_shape_bad "$file" || refuse "row $_id: file must be a path relative to the top level without '..' (got '$file')"
  set -- "$@" "$file"
done <<EOF
$rows
EOF
! path_shape_bad "$tfile" || refuse "test file must be a path relative to the top level without '..' (got '$tfile')"
[ -f "$top/$tfile" ] || refuse "no such test file: $tfile"
set -- "$@" "$tfile"
dirty="$(git -C "$top" status --porcelain --untracked-files=no -- "$@")"
if [ -n "$dirty" ]; then
  printf 'mutation-sweep: refusing — a file the sweep uses has a tracked change (it sweeps committed HEAD):\n%s\n' "$dirty" >&2
  exit 2
fi

sha="$(git -C "$top" rev-parse HEAD)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/keel-mutation-sweep.XXXXXX")"
cleanup() {
  rm -rf "$tmp" 2>/dev/null || true
  [ -d "$tmp" ] && printf 'mutation-sweep: could not remove %s\n' "$tmp" >&2
  return 0
}
trap cleanup EXIT
work="$tmp/clone"
git clone -q --no-hardlinks "$top" "$work" >/dev/null 2>&1 || refuse "could not clone $top"
if ! git -C "$work" checkout -q --detach "$sha" 2>/dev/null; then
  # HEAD reachable from no branch of the source (a detached checkout): fetch it by name
  git -C "$work" fetch -q "$top" HEAD >/dev/null 2>&1 && git -C "$work" checkout -q --detach "$sha" 2>/dev/null \
    || refuse "could not check out $sha in the clone"
fi
[ -f "$work/$tfile" ] || refuse "the test file is not in HEAD: $tfile"

# run_test → sets rc, summary ('' when none), nfailed (its failed count) and out_file (this run's output).
run_test() {
  rc=0; runs=$((runs + 1))
  # a fresh output file per run: a child orphaned by an earlier TIMEOUT may still hold the previous one open
  out_file="$tmp/out.$runs"
  ( cd "$work" && perl -e 'alarm shift; exec @ARGV' "$timeout" bash "$tfile" ) </dev/null >"$out_file" 2>&1 || rc=$?
  summary="$(grep -E ': [0-9]+ passed, [0-9]+ failed$' "$out_file" | tail -n 1 || true)"
  nfailed="${summary% failed}"; nfailed="${nfailed##* }"
}

runs=0
run_test
baseline_fail() { tail -n 8 "$out_file" >&2; refuse "$@"; }
if [ "$rc" -eq 142 ]; then baseline_fail "the unmutated test file timed out after ${timeout}s: $tfile"; fi
[ -n "$summary" ] || baseline_fail "the unmutated test file printed no summary line (exit $rc): $tfile"
[ "$nfailed" = 0 ] || baseline_fail "the unmutated test file has failures — a broken baseline makes every mutant look killed: $summary"

killed=0; survived=0; timed=0; crashed=0; bad=0
while IFS=$'\t' read -r row id file; do
  why="$(path_problem "$work" "$file")"
  if [ -n "$why" ]; then   # e.g. a tracked symlink: a write through it would leave the clone
    printf '%s\tBADNEEDLE\t-\n' "$id"; printf 'mutation-sweep: %s: %s %s\n' "$id" "$file" "$why" >&2
    bad=$((bad + 1)); continue
  fi
  res="$(awk -F'\t' -v mode=mutate -v root="$work" -v want="$row" -v out="$tmp/mutant" "$AWK_PROG" "$list")"
  case "$res" in
    BADNEEDLE*|NOCHANGE)
      printf '%s\t%s\t-\n' "$id" "${res%%$'\t'*}"
      [ "$res" = NOCHANGE ] || printf 'mutation-sweep: %s: %s\n' "$id" "${res#*$'\t'}" >&2
      bad=$((bad + 1)); continue ;;
  esac
  cat "$tmp/mutant" >"$work/$file"
  run_test
  rm -f "$out_file"   # an orphan still writing to it writes to an unlinked file; the BASELINE's file is kept for a refusal
  git -C "$work" checkout -q -- "$file"
  if [ "$rc" -eq 142 ]; then outcome=TIMEOUT; timed=$((timed + 1))
  elif [ -z "$summary" ]; then outcome=CRASHED; crashed=$((crashed + 1))
  elif [ "$nfailed" -ge 1 ]; then outcome=KILLED; killed=$((killed + 1))
  else outcome=SURVIVED; survived=$((survived + 1)); fi
  printf '%s\t%s\t%s\n' "$id" "$outcome" "${summary:--}"
done <<EOF
$rows
EOF

printf '%d killed, %d survived, %d timeout, %d crashed, %d bad\n' "$killed" "$survived" "$timed" "$crashed" "$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
