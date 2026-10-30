#!/usr/bin/env bash
# tools/self/procsub-leak.sh — keel-self-maintenance (dir #68 exemption, per tools/self/prose-drift.sh's
# header): flags a process substitution that bash 3.2 keeps open once per loop pass. There is no
# consumer-facing counterpart and install.sh never ships this file.
#
# THE LEAK (dir #904, dir #905). Apple's /bin/bash is 3.2, and it closes a process substitution's fd only
# when the top-level command that opened it finishes. Inside a function that is the whole function call,
# so a `while …; done < <(cmd)` run once per item of a loop holds one fd per item. Near 250 items the fd
# that reaches 256 hits 3.2's `add_fifo_list` off-by-one, a one-byte heap overwrite: a crash at random
# (SIGABRT, exit 134), which is how macos-14 CI went red in tools/self/prose-drift.sh. bash 4+ does not
# leak, so a Linux run or a Homebrew bash never shows it.
#
# WHAT LEAKS, measured on 3.2.57 with `lsof` (40 passes of a loop inside a function, 9 fds at rest):
#   leaks, +1 fd per pass   `done < <(…)`, `} < <(…)`, `fi < <(…)`, `esac < <(…)`, `read x < <(…)`,
#                           `myfunc < <(…)`, `echo x > >(…)`, `source <(…)` — a command the shell runs
#                           in itself; also a call to `f() { …; } < <(…)`, whose redirect is per call
#   holds at 9              `cat < <(…)`, `grep x <(…)`, `( … ) < <(…)`, `x=$(… < <(…))` — a child
#                           process owns the fd and takes it with it when it exits
#   holds at 9              any of the above in a loop at the top level of a script
# A function that opens ONE such fd per call leaks the same way when another function calls it in a loop
# (the call returns, the fd stays): tools/lib/transcript-usage.sh's tu_session_totals() did, under
# tools/self/session-cost.sh's _sc_ticket_cost(). So the check follows calls, across files too, since a
# lib's functions run in the shell that sources it.
# One thing hides the leak: an external command the function runs itself (not inside `$(…)`) makes 3.2
# close every fd held so far, so a loop body that runs `jq` never piles them up. The check does not credit
# that. It is a side effect, and moving the `jq` into a `$(…)` brings the leak back.
#
# HOW IT READS A SCRIPT. Bash parses it, not a regex: each file is wrapped in a function and printed back
# with `declare -f` (parsing alone runs nothing). That output has comments stripped and one command per
# line, with `do`/`done` and a function's braces on lines of their own, which a small awk reader can
# follow. Lines inside a multi-line `$(…)`, `<(…)` or `( … )` run in a subshell and are skipped. The
# wrapper's body is the script's top level, and is never a function. A `while`/`until` condition counts as
# inside its loop: it runs every pass.
#
# AXIS, named: a call is seen only when the function's name is the command word of a line segment
# outside a pipeline, a `( … )` and a `$(…)`; a call through a variable, `eval` or a pipeline is not
# followed. Sourcing is not traced either: a call counts as leaking when any tracked file defines a
# function of that name that leaks, which can over-report, never under-report.
# The input is keel's own tracked scripts, which the suite runs anyway; the wrap would let a crafted file
# close its brace early and run code, so this is no checker for untrusted trees.
#
# The fix the finding asks for (dir #904's): capture the output, then read it from a herestring —
#   out="$(cmd)" || true                 # `|| true` where the old loop ignored cmd's status
#   [ -z "$out" ] || while …; done <<< "$out"   # the guard: `<<< ""` would feed one empty line
#
# Usage:
#   tools/self/procsub-leak.sh [REPO_DIR] [--quiet]
#   tools/self/procsub-leak.sh -h | --help
#
# REPO_DIR defaults to the current directory. Exit 0 unless a leak is found; 2 on a usage error, when the
# scan cannot run (REPO_DIR is no directory or no git checkout, it tracks no shell script, bash lists no
# builtins), or for a script bash cannot parse (named UNPARSED, never passed as clean).
# KNOWN LIMIT (dir #906): the awk reader can still lose its place partway through a script bash parsed
# (quoting it mis-reads, a `case` pattern's `)` inside a multi-line `$(…)`, a `<<word` inside a string).
# From there on it can miss a leak or report one that is not there, and nothing says the place was lost:
# neither exit 0 nor a LEAK line is proof on its own until that ticket lands.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUIET=0
usage() {
  cat <<'EOF'
tools/self/procsub-leak.sh — a process substitution bash 3.2 keeps open once per loop pass
inside a function (one fd per item; fd 256 crashes bash 3.2 at random).

Usage:
  tools/self/procsub-leak.sh [REPO_DIR]   scan REPO_DIR's tracked shell scripts (default: .)
  tools/self/procsub-leak.sh --quiet      print only LEAK lines
  tools/self/procsub-leak.sh -h | --help

Exit 0 unless a leak is found; 2 on a usage error, when the scan cannot run, or for an
unparseable script. Known limit: the reader can lose its place partway through a script,
then miss a leak or report a false one, without saying so (dir #906).
EOF
}

REPO_ARG=.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "procsub-leak.sh: unknown flag '$1' (try --help)" >&2; exit 2 ;;
    *) REPO_ARG="$1" ;;
  esac
  shift
done
repo_dir="$REPO_ARG"
[ -d "$repo_dir" ] || { echo "procsub-leak.sh: not a directory: $repo_dir" >&2; exit 2; }
repo_dir="$(cd "$repo_dir" && pwd)"

say() { [ "$QUIET" = 1 ] || echo "$@"; }
say "● process substitutions held open per loop pass ($repo_dir)"

files="$(bash "$self_dir/shellcheck-targets.sh" "$repo_dir")" ||
  { echo "procsub-leak.sh: could not list the tracked shell scripts under $repo_dir (not a git checkout?)" >&2; exit 2; }
[ -n "$files" ] || { echo "procsub-leak.sh: no tracked shell scripts under $repo_dir" >&2; exit 2; }

normalized="$(mktemp)"
# The completion marker (dir #264's idiom, see tools/self/line-citations.sh): on bash 3.2 a `set -u` abort
# reaches an EXIT trap with `$?` already 0, and a crash must never read as a clean tree.
ok=""
cleanup() {
  leak_rc=$?
  [ -n "$ok" ] || [ "$leak_rc" -ne 0 ] || leak_rc=1
  rm -f "$normalized"
  exit "$leak_rc"
}
trap cleanup EXIT

# One `\001FILE <path>` marker, then that file's normalized text. extglob is on before the parse: a
# script that turns it on itself uses `@(…)` patterns that do not parse without it.
unparsed=0
nfiles=0
while IFS= read -r f; do
  nfiles=$((nfiles + 1))
  if body="$(bash -c 'shopt -s extglob; eval "__keel_wrap() {
$(<"$1")
}" && declare -f __keel_wrap' _ "$repo_dir/$f" 2>/dev/null)"; then
    printf '\001FILE %s\n%s\n' "$f" "$body" >> "$normalized"
  else
    echo "  UNPARSED  $f — bash could not parse it; its loops were not checked" >&2
    unparsed=$((unparsed + 1))
  fi
done <<< "$files"

# What the shell runs in itself: bash's own builtins, asked of bash rather than kept by hand (a hand-kept
# list missed `getopts`, `let`, `trap`, …). A command word that is neither one nor a defined function runs
# as a child process, which takes its fd with it.
builtins="$(compgen -b | tr '\n' ' ')"
case " $builtins " in *" read "*) ;; *) echo "procsub-leak.sh: could not list bash's builtins" >&2; exit 2 ;; esac

# The reader. Stack entries: T (the wrapper, i.e. top level), F (a function), L (a loop), each with the
# indent of the line that opened it. Each line is split into its list segments (`&&`, `||`, `;`) after
# every complete `( … )` on it is folded into one placeholder: \003 for a `<(…)` or `>(…)`, \002 for a
# `$(…)`, an arithmetic `$((…))` or a subshell. A site is a segment that holds a \003 and whose command
# runs in this shell; a call is a function name in command position. END widens "opens an fd per call"
# to every function that calls one such (by name, across files), and reports a site or a call that sits
# in a loop inside a function.
# LC_ALL=C: the reader is byte-wise ASCII, and a tracked script may hold bytes that are no valid UTF-8 —
# under a UTF-8 locale macOS awk aborts on them ("towc: multibyte conversion failure") and gawk warns.
hits="$(LC_ALL=C awk -v blist="$builtins" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# dequote S — S with the quotes around a here-document delimiter (`<<\047X\047`, `<<"X"`) dropped, so that
# unquote then keeps the delimiter and removes only real strings, a `<<\047X\047` inside one included.
function dequote(s,   m) {
  while (match(s, /<<-?[ ]*[\047"][A-Za-z_][A-Za-z0-9_]*[\047"]/)) {
    m = substr(s, RSTART, RLENGTH); gsub(/[\047"]/, "", m); sub(/<</, "\004", m)
    s = substr(s, 1, RSTART - 1) m substr(s, RSTART + RLENGTH)
  }
  gsub(/\004/, "<<", s)
  return s
}
function unquote(s) { gsub(/\\./, "", s); gsub(/\047[^\047]*\047/, "", s); gsub(/"[^"]*"/, "", s); return s }
# parens S — the count of `(` minus the count of `)` in S.
function parens(s,   t) { t = s; return gsub(/[(]/, "", t) - gsub(/[)]/, "", s) }
# fold S CUT — S with each complete `( … )`, innermost first, and each backtick pair folded into a
# placeholder. With CUT, the text from a `(` the line leaves open onward is cut too, since it runs in a
# subshell (a `<(`/`>(` cut so still leaves its \003).
function fold(s, cut,   c) {
  while (match(s, /[(][^()]*[)]/)) {
    c = (RSTART > 1) ? substr(s, RSTART - 1, 1) : ""
    s = substr(s, 1, RSTART - 1) ((c == "<" || c == ">") ? "\003" : "\002") substr(s, RSTART + RLENGTH)
  }
  gsub(/`[^`]*`/, "\002", s)
  if (cut && match(s, /[$<>]?[(]|`/)) { c = substr(s, RSTART, 1); s = substr(s, 1, RSTART - 1) ((c == "<" || c == ">") ? "\003" : "") }
  return s
}
# pscan S STOP — walk S, adding 1 to cs at a `(` and taking 1 at a `)`, outside single quotes. csq and csd,
# an open single or double quote, carry across lines (an awk program in `\047…\047` spans several); a `(`
# opens a fresh context, so it clears csd. With STOP, return the index just past the `)` that brings cs
# to 0; else, or when none does, length(S) + 1.
function pscan(s, stop,   i, c) {
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (csq) { if (c == "\047") csq = 0; continue }
    if (c == "\\") i++
    else if (c == "\047" && !csd) csq = 1
    else if (c == "\"") csd = !csd
    else if (c == "(") { cs++; csd = 0 }
    else if (c == ")") { cs--; if (stop && cs == 0) return i + 1 }
  }
  return i
}
function owner(   k) { for (k = sp; k >= 1; k--) if (st[k] == "F") return k; return 0 }
function looped(fk,   k) { for (k = sp; k > fk; k--) if (st[k] == "L") return 1; return 0 }
# cmdword SEG — the command word of one list segment: leading keywords, `!`, and VAR=value words dropped.
function cmdword(seg,   w) {
  seg = trim(seg)
  while (seg != "") {
    w = seg; sub(/[ \t].*/, "", w)
    if (w ~ /^(if|then|else|elif|do|while|until|time|builtin|command|!|[{])$/ || w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?=/) {
      seg = substr(seg, length(w) + 1); seg = trim(seg); continue
    }
    return w
  }
  return ""
}
# opensub — this line leaves a `(` open: count its parens again, quotes honoured, and if one is still open,
# skip the lines up to the `)` that closes it.
function opensub() { cs = 0; csq = 0; csd = 0; pscan(raw, 0); if (cs < 0) cs = 0 }
function site(fn, inloop, w, text) {
  site_n++; s_file[site_n] = file; s_fn[site_n] = fn; s_loop[site_n] = inloop; s_cmd[site_n] = w
  s_text[site_n] = trim(text)
}
BEGIN { n = split(blist, b, " "); for (i = 1; i <= n; i++) isb[b[i]] = 1 }
/^\001FILE / { file = substr($0, 7); sp = 0; hd = ""; cs = 0; csq = 0; csd = 0; pend = ""; next }
{
  line = $0
  if (hd != "") { t = line; if (hdtab) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
  raw = dequote(line); u = unquote(raw)
  # A here-document starting on this line: its body follows, verbatim, until the terminator. Only the
  # check above reads hd, so setting it here skips the lines after this one, whatever this line is. It is
  # read from the folded text, so a `$((1<<n))` shift is no opener.
  h = fold(u, 0)
  if (match(h, /(^|[^<])<<-?[ ]*[A-Za-z_][A-Za-z0-9_]*/)) {
    h = substr(h, RSTART, RLENGTH); hdtab = (h ~ /<<-/); sub(/^[^<]*<<-?[ ]*/, "", h); hd = h
  }
  # Inside a multi-line substitution: skip to the `)` that closes it, and read what follows it (less a
  # leading `"` that ends a string the substitution sat in).
  if (cs > 0) {
    i = pscan(raw, 1)
    if (cs > 0) next
    raw = substr(raw, i); sub(/^"/, "", raw); u = unquote(raw)
  }
  d = parens(u)
  match(line, /^ */); ind = RLENGTH
  if (pend != "") {
    if (line ~ /^ *[{] *$/) {
      sp++; st[sp] = (pend == "__keel_wrap") ? "T" : "F"; si[sp] = pind; sn[sp] = pend
      if (st[sp] == "F") isfn[pend] = 1
      pend = ""; next
    }
    pend = ""
  }
  if (line ~ /^ *(function +)?[^ ;&|<>(){}$`]+ +[(][)] *$/) {
    pend = trim(line); sub(/^function +/, "", pend); sub(/ +[(][)].*/, "", pend); pind = ind; next
  }
  if (sp > 0 && (st[sp] == "F" || st[sp] == "T") && ind == si[sp] && line ~ /^ *[}]/) {
    # `f() { …; } < <(…)`: a redirect on the whole function, one fd per call.
    if (st[sp] == "F" && fold(u, 1) ~ /\003/) site(sn[sp], 0, "", line)
    if (d > 0) opensub()
    sp--; next
  }
  fk = owner()
  if (line ~ /^ *done([ ;]|$)/ && sp > 0 && st[sp] == "L") sp--
  # A line that leaves a substitution open ends inside it: a `do` there belongs to a loop in that subshell.
  # A `while`/`until` condition runs every pass, so its loop opens before the line is read.
  opens = (d <= 0 && line ~ /(^|[ ;])do *$/)
  if (opens && line ~ /^ *(while|until) /) { sp++; st[sp] = "L"; si[sp] = ind; opens = 0 }
  if (fk > 0) {
    nseg = split(fold(u, 1), segs, /&&|[|][|]|;/)
    for (i = 1; i <= nseg; i++) {
      # A pipeline runs in subshells. A `( … )` folds to \002, which no builtin or function name matches.
      if (segs[i] ~ /(^|[^|])[|]([^|]|$)/) continue
      w = cmdword(segs[i])
      if (segs[i] ~ /\003/) site(sn[fk], looped(fk), (w ~ /^(done|fi|esac|[}])$/) ? "" : w, line)
      if (w == "" || w ~ /^(done|fi|esac|[}]|for|case|select|local|return|break|continue)$/) continue
      call_n++; c_file[call_n] = file; c_fn[call_n] = sn[fk]; c_loop[call_n] = looped(fk); c_to[call_n] = w
    }
  }
  if (opens) { sp++; st[sp] = "L"; si[sp] = ind }
  if (d > 0) opensub()
}
# mark K — K (file SUBSEP name) opens an fd per call; 1 if that is news.
function mark(k,   kp) { if (k in leaky) return 0; leaky[k] = 1; split(k, kp, SUBSEP); lname[kp[2]] = 1; return 1 }
# calls I — call I may run a function that opens an fd per call: one of that name does, in any file
# (sourcing is not traced, so any definition of the name counts: an over-report, never an under-one).
function calls(i) { return c_to[i] in lname }
END {
  for (i = 1; i <= site_n; i++) {
    if (s_cmd[i] == "" || (s_cmd[i] in isb) || (s_cmd[i] in isfn)) {
      mark(s_file[i] SUBSEP s_fn[i])
      if (s_loop[i]) printf "%s\t%s()\t%s\n", s_file[i], s_fn[i], s_text[i]
    }
  }
  changed = 1
  while (changed) {
    changed = 0
    for (i = 1; i <= call_n; i++) if (calls(i) && mark(c_file[i] SUBSEP c_fn[i])) changed = 1
  }
  for (i = 1; i <= call_n; i++)
    if (c_loop[i] && calls(i))
      printf "%s\t%s()\tcalls %s() in a loop, and each call leaves an fd open\n", c_file[i], c_fn[i], c_to[i]
}
' "$normalized" | LC_ALL=C sort -u)" ||
  { echo "procsub-leak.sh: the reader failed (awk exit above); nothing was checked" >&2; exit 2; }

nhits=0
[ -z "$hits" ] || while IFS=$'\t' read -r hf hfn htext; do
  echo "  LEAK  $hf $hfn: $htext"
  nhits=$((nhits + 1))
done <<< "$hits"
if [ "$nhits" -gt 0 ]; then
  say "  $nhits leak(s) in $nfiles script(s) — capture the output and read it with \`<<<\` (see this script's header)"
  exit 1
fi
[ "$unparsed" -eq 0 ] || exit 2
ok=1
say "  OK — no process substitution held open per loop pass ($nfiles scripts)"
