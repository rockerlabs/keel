#!/usr/bin/env bash
# tools/self/changelog-claims.sh — keel-self-maintenance (dir #810): the numeric-claim lint over changelog
# text. There is no consumer-facing counterpart and install.sh never ships this file. A number in changelog
# text (a `changelog.d/` fragment, `CHANGELOG.md`'s `## [Unreleased]`, or the section being cut) was checked
# only by reviewers, and a wrong count survived four cut-correction rounds in 0.16.0. This tool finds the
# numeric claims in that text and re-derives each one an author BOUND to a source with a marker; it lists
# every number nobody sourced, and at the cut (`--strict`) an unsourced number fails.
#
# Usage:
#   tools/self/changelog-claims.sh [--repo DIR] [--section X.Y.Z | --fragment changelog.d/NAME.md ...] [--strict]
#   tools/self/changelog-claims.sh -h | --help
#
# Text read: by default every fragment (the reader `changelog-fragments.sh --list` names them, in its order),
# then the body of `CHANGELOG.md`'s `## [Unreleased]`. --section X.Y.Z reads only the body of `## [X.Y.Z]`.
# --fragment (repeatable, each must be in the reader's list, exclusive with --section) reads only the named
# fragments: how a PR or a pre-cut correction lints its own text under --strict. Fenced blocks and inline
# code spans are never read. A line with an odd number of backticks is not code-blanked (its code numbers
# list as claims).
#
# A claim is a number in the prepared text (ticket and PR ids, versions, dates, identifiers, "step 5"-style
# structure words, exit statuses and list ordinals are not). A marker on the same line binds the nearest
# claim to its LEFT that no marker has bound yet:
#   <!-- claim: words PATH -->            the awk field count of PATH (not `wc -w`, which differs per platform)
#   <!-- claim: lines PATH -->            `wc -l` of PATH
#   <!-- claim: matches ERE PATH... -->  the sum of `grep -cE ERE` over the PATHs (ERE: 'single quoted', or
#                                        one run with no spaces)
#   <!-- claim: hand TEXT -->            says where the number comes from, with an as-of (a date YYYY-MM-DD,
#                                        a commit sha or a version vX.Y.Z); never re-derived
# A hand as-of that is a commit sha needs a digit in it ("defaced" is a word). A marker holding an odd number
# of backticks is a BADMARK: it cannot be told from a code span.
# A PATH is repo-relative: no leading /, no .. segment, a regular file that is not a symlink, physically
# under DIR. words/lines/matches take an INTEGER claim only (no ~, decimal, range or suffix: use hand). Marker
# text is data: it reaches awk, wc and grep as argv and never eval, sh -c or $(...).
#
# Output, one line per finding, in file, line, then left-to-right order:
#   VERDICT <file>:<line>: <claim as written> — <detail>
#   OK        bound, and the derived value equals the claim (detail: KIND ARGS = N)
#   MISMATCH  bound, and the derived value differs (KIND ARGS gives N)
#   HAND      bound with `hand` (detail: its TEXT)
#   UNBOUND   no marker (detail: about six words of context)
#   WORD      a spelled-out number (two..twenty, thirty..ninety, hundred, thousand): listed, never bound,
#             never failing
#   BADMARK   an invalid marker (detail: the reason; a marker with no claim prints `-`)
# then one summary line `changelog-claims: <n> claim(s): <ok> ok, <mm> mismatched, <h> hand, <u> unbound,
# <w> word, <b> bad marker(s)`.
#
# Exit codes: 0 ok · 1 any MISMATCH or BADMARK, or, with --strict, any UNBOUND · 2 bad arguments, an
# unreadable repo, an odd number of fence markers or a `## [Unreleased]` count other than 1 in CHANGELOG.md
# (the cut's own refusals), no such section, or the fragment reader failing.
#
# Read-only: writes nothing, reads no stdin, makes no network call and no git-history call.
# bash 3.2-compatible (macOS /bin/bash): no mapfile, no associative arrays. awk is a byte-wise awk under
# LC_ALL=C (busybox awk, mawk and macOS awk all agree on `–` being 3 bytes).
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

# Byte semantics for every awk and grep below, as both sibling tools do.
export LC_ALL=C
exec </dev/null

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

usage_line="usage: changelog-claims.sh [--repo DIR] [--section X.Y.Z | --fragment changelog.d/NAME.md ...] [--strict]"
die_args() { echo "changelog-claims.sh: $1" >&2; echo "$usage_line" >&2; exit 2; }
die() { echo "changelog-claims.sh: $1" >&2; exit 2; }

repo_dir="$(cd "$self_dir/../.." && pwd)"
section=""
have_section=0
strict=0
frag_args=""
nfrag=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    --repo)
      [ $# -ge 2 ] || die_args "--repo needs a directory"
      repo_dir="$2"; shift 2 ;;
    --section)
      [ $# -ge 2 ] || die_args "--section needs a version"
      section="$2"; have_section=1; shift 2 ;;
    --fragment)
      [ $# -ge 2 ] || die_args "--fragment needs a changelog.d/NAME.md path"
      frag_args="$frag_args$2"$'\n'; nfrag=$((nfrag + 1)); shift 2 ;;
    --strict) strict=1; shift ;;
    *) die_args "unknown argument '$1'" ;;
  esac
done
[ -d "$repo_dir" ] || die_args "no such directory: $repo_dir"
repo_dir="$(cd "$repo_dir" && pwd)"
repo_real="$(cd "$repo_dir" && pwd -P)"
if [ "$have_section" = 1 ]; then
  [ "$nfrag" -eq 0 ] || die_args "--section and --fragment are exclusive"
  grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$section" || die_args "--section '$section' is not x.y.z"
fi

reader="$self_dir/changelog-fragments.sh"
changelog="$repo_dir/CHANGELOG.md"

# --- the awk scanner: one source (fence-blanked text on stdin) -> one record per finding ----------------------------
# Record fields, separated by US (0x1f): type (C claim · W word · M a marker with no claim) · line · text ·
# integer value or "-" · context · marker state (N none · B bad · K parsed) · kind · ERE · paths (joined by
# RS 0x1e) · args as written / the bad reason · "." (a sentinel: no field is ever last-and-empty).
read -r -d '' awk_prog <<'AWK' || true
function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); return x }
function bad(i, why) { mst[i] = "B"; mbad[i] = why }
function is_sha(w, needdigit) { return length(w) >= 7 && length(w) <= 40 && w ~ /^[0-9a-f]+$/ && w ~ /[a-f]/ && (!needdigit || w ~ /[0-9]/) }
function has_asof(t,    n, a, k, w) {
  if (t ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 1
  if (t ~ /v[0-9]+\.[0-9]+\.[0-9]+/) return 1
  n = split(t, a, /[^0-9A-Za-z]+/)
  for (k = 1; k <= n; k++) if (is_sha(a[k], 1)) return 1   # a digit too: "defaced" is a word, not a commit
  return 0
}
function parse_marker(i, inner, closed,    t, k, kind, rest, np, a, r, q, ere, after, j) {
  mst[i] = "K"; mkind[i] = ""; mere[i] = ""; mpaths[i] = ""; margs[i] = ""; mbad[i] = ""
  if (!closed) { bad(i, "marker has no closing -->"); return }
  if (gsub(/`/, "&", inner) % 2 == 1) { bad(i, "a marker with an odd number of backticks cannot be told from a code span"); return }
  if (substr(inner, 1, 1) != ":") { bad(i, "malformed marker: expected 'claim:' after '<!--'"); return }
  t = trim(substr(inner, 2))
  if (t == "") { bad(i, "missing argument: no kind"); return }
  k = index(t, " ")
  if (k == 0) { kind = t; rest = "" } else { kind = substr(t, 1, k - 1); rest = trim(substr(t, k + 1)) }
  mkind[i] = kind; margs[i] = rest
  if (kind == "hand") {
    if (rest == "") bad(i, "empty hand: say where the number comes from, with an as-of")
    else if (!has_asof(rest)) bad(i, "hand without an as-of: add a date YYYY-MM-DD, a commit sha or a version vX.Y.Z")
    return
  }
  if (kind == "words" || kind == "lines") {
    np = split(rest, a, " ")
    if (rest == "") bad(i, "missing argument: " kind " needs a PATH")
    else if (np > 1) bad(i, "extra argument: " kind " takes exactly one PATH")
    else mpaths[i] = a[1]
    return
  }
  if (kind == "matches") {
    if (rest == "") { bad(i, "missing argument: matches needs an ERE and a PATH"); return }
    if (substr(rest, 1, 1) == "'") {
      r = substr(rest, 2); q = index(r, "'")
      if (q == 0) { bad(i, "unclosed quote in the ERE"); return }
      ere = substr(r, 1, q - 1)
      if (substr(r, q + 1, 1) != "" && substr(r, q + 1, 1) != " ") { bad(i, "malformed ERE argument: text glued to the closing quote"); return }
      after = trim(substr(r, q + 1))
    } else {
      k = index(rest, " ")
      if (k == 0) { ere = rest; after = "" } else { ere = substr(rest, 1, k - 1); after = trim(substr(rest, k + 1)) }
    }
    if (ere == "" || after == "") { bad(i, "missing argument: matches needs an ERE and at least one PATH"); return }
    np = split(after, a, " ")
    r = a[1]
    for (j = 2; j <= np; j++) r = r RSEP a[j]
    mere[i] = ere; mpaths[i] = r
    return
  }
  bad(i, "unknown kind '" kind "'")
}
function blank_range(st, ln,    sp) {
  sp = sprintf("%" ln "s", "")
  s = substr(s, 1, st - 1) sp substr(s, st + ln)
}
# blank(re, ci, lb): overwrite every match of re with spaces of the same length (positions never shift).
# ci matches on the lowercase copy (same byte positions under LC_ALL=C); lb requires a non-alphanumeric
# byte to the match's left.
function blank(re, ci, lb,    t, from, st, ln) {
  from = 1
  while (from <= length(s)) {
    t = substr(ci ? tolower(s) : s, from)
    if (!match(t, re)) return
    st = from + RSTART - 1; ln = RLENGTH
    if (ln <= 0) { from = st + 1; continue }
    if (lb && st > 1 && substr(s, st - 1, 1) ~ /[A-Za-z0-9]/) { from = st + 1; continue }
    blank_range(st, ln)
    from = st + ln
  }
}
function blank_shas(    from, st, ln, w) {
  from = 1
  while (from <= length(s)) {
    if (!match(substr(s, from), /[A-Za-z0-9]+/)) return
    st = from + RSTART - 1; ln = RLENGTH; w = substr(s, st, ln)
    if (is_sha(w)) blank_range(st, ln)
    from = st + ln
  }
}
function context(pos,    left, right, na, nb, a, b, out, i, k) {
  left = substr(c, 1, pos - 1); right = substr(c, pos)
  gsub(PH, "", left); gsub(PH, "", right)
  na = split(left, a, " "); nb = split(right, b, " ")
  out = ""
  for (i = (na > 2 ? na - 1 : 1); i <= na; i++) out = out (out == "" ? "" : " ") a[i]
  # the claim's own word keeps any text glued to its left ("a.sh:12", "5/6")
  glue = (out != "" && substr(left, length(left), 1) != " ")
  for (k = 1; k <= 4 && k <= nb; k++) out = out (out == "" || (k == 1 && glue) ? "" : " ") b[k]
  return out
}
function emit(type, ln, text, val, ctx, k) {
  printf "%s%s%s%s%s%s%s%s%s%s", type, FS_, ln, FS_, text, FS_, val, FS_, ctx, FS_
  if (k > 0) printf "%s%s%s%s%s%s%s%s%s%s%s%s", mst[k], FS_, mkind[k], FS_, mere[k], FS_, mpaths[k], FS_, margs[k], FS_, mbad[k], FS_
  else printf "N%s%s%s%s%s%s", FS_, FS_, FS_, FS_, FS_, FS_
  printf ".\n"
}
BEGIN {
  FS_ = "\037"; RSEP = "\036"; PH = "\001"
  en = "\342\200\223"; sect = "\302\247"
  sanit = "[\001\036\037\t\r]"
  split("two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety hundred thousand", wl, " ")
  for (i in wl) wset[wl[i]] = 1
  num = "[0-9]+(,[0-9][0-9][0-9])*"
  dec = num "(\\.[0-9]+)?"
  sep = "(, and |, | and | or | to |-|" en ")"
  list = num "(" sep num ")*"
  re_x6 = "(steps?|slices?|phase|rounds?|spec|lines?|turn|fd|items?|legs?|pass(es)?|part) " list
  re_x6s = sect " ?" list
  re_x7 = "(exit(s|ing|ed)?|exit code|return(s)?|status) " list
  on = (h == "")
}
{
  if (h != "") {
    if (!on) { if (index($0, h) == 1) on = 1; next }
    if (index($0, "## ") == 1) exit
  }
  s = $0
  gsub(sanit, " ", s)
  # 1. inline code spans, blanked length-preserving (not on a line with an odd backtick count: a span
  # wrapped across lines). s0 keeps the line as written: a marker's text is read from it, so a backtick
  # pair inside a marker's ERE or hand text is data, never a span.
  s0 = s
  nb = gsub(/`/, "&", s)
  if (nb > 0 && nb % 2 == 0) {
    from = 1
    while (match(substr(s, from), /`[^`]*`/)) { blank_range(from + RSTART - 1, RLENGTH); from += RSTART - 1 + RLENGTH }
  }
  # 2. markers, found and read on s0 (so a backtick inside a marker never hides its end); one whose start
  # the span blanking reached is inside a code span and is not a marker. Left to right; each marker's
  # text becomes one placeholder byte so claims keep a side.
  nm = 0; out = ""; rest = s; rest0 = s0
  while ((p = index(rest0, "<!-- claim")) > 0) {
    pre = substr(rest, 1, p - 1)
    if (substr(rest, p, 10) != "<!-- claim") { out = out pre substr(rest, p, 10); rest = substr(rest, p + 10); rest0 = substr(rest0, p + 10); continue }
    body0 = substr(rest0, p + 10)
    q = index(body0, "-->")
    nm++
    if (q == 0) { parse_marker(nm, body0, 0); rest = ""; rest0 = "" }
    else { parse_marker(nm, substr(body0, 1, q - 1), 1); rest = substr(rest, p + 10 + q + 2); rest0 = substr(body0, q + 3) }
    out = out pre PH
  }
  s = out rest
  # 3. every other single-line comment, then every link target
  out = ""; rest = s
  while ((p = index(rest, "<!--")) > 0) {
    q = index(substr(rest, p + 4), "-->")
    if (q == 0) break
    mid = substr(rest, p + 4, q - 1)
    if (index(mid, PH) > 0) { out = out substr(rest, 1, p + 3); rest = substr(rest, p + 4); continue }
    out = out substr(rest, 1, p - 1) " "
    rest = substr(rest, p + q + 6)
  }
  s = out rest
  out = ""; rest = s
  while ((p = index(rest, "](")) > 0) {
    q = index(substr(rest, p + 2), ")")
    if (q == 0) break
    mid = substr(rest, p + 2, q - 1)
    if (index(mid, PH) > 0) { out = out substr(rest, 1, p + 1); rest = substr(rest, p + 2); continue }
    out = out substr(rest, 1, p - 1) " "
    rest = substr(rest, p + q + 2)
  }
  s = out rest
  c = s
  # 4. exclusions X1-X8 (an excluded number is not a claim). ORDER MATTERS: a rule that runs earlier hides
  # its text from the later ones. X1's "of M" tail goes with its PR id (else "of 3" stays a claim), SHAs
  # and versions go before the identifier shape (else "3b8b41c" is cut at "b8"), the structure words
  # (X6/X7) go after it, and "(N)" ordinals last.
  blank("PR-[0-9]+( of [0-9]+)?", 0, 0)
  blank("#[0-9]+", 0, 0)
  blank("KB\\.[0-9]+", 0, 1)
  blank("H\\.[0-9]+", 0, 1)
  blank("https?://[^ ]*", 0, 0)
  blank("v?[0-9]+\\.[0-9]+\\.[0-9]+", 0, 0)
  blank("(bash|git|zsh|awk|perl|python) [0-9]+(\\.[0-9]+)?( and [0-9]+(\\.[0-9]+)?)?", 1, 1)
  blank("[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9](T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z?)?", 0, 0)
  blank("[0-9]?[0-9]:[0-9][0-9]Z?", 0, 0)
  blank("[0-9]+(st|nd|rd|th)", 0, 0)
  blank_shas()
  blank("[A-Za-z]+-?[0-9]+(-[0-9]+)?[A-Za-z]*", 0, 1)
  blank(re_x6, 1, 1)
  blank(re_x6s, 0, 0)
  blank(re_x7, 1, 1)
  blank("\\([0-9]+\\)", 0, 0)
  if (match(s, "^(- )?[0-9]+\\. ")) blank_range(RSTART, RLENGTH)
  blank("(mode|umask) [0-9]+", 1, 1)
  blank("[0-7][0-7][0-7]/[0-7][0-7][0-7]", 0, 0)
  # 5a. claims
  nc = 0; i = 1
  while (i <= length(s)) {
    if (!match(substr(s, i), /[0-9]/)) break
    st = i + RSTART - 1
    if (st > 1 && substr(s, st - 1, 1) ~ /[A-Za-z0-9]/) {
      match(substr(s, st), /^[0-9]+(,[0-9][0-9][0-9])*(\.[0-9]+)?[A-Za-z0-9]*/)
      i = st + RLENGTH; continue
    }
    match(substr(s, st), /^[0-9]+(,[0-9][0-9][0-9])*/)
    e = st + RLENGTH
    digits = substr(s, st, RLENGTH)
    nonint = 0; ds = st
    if (substr(s, e, 1) == "." && substr(s, e + 1, 1) ~ /[0-9]/) { match(substr(s, e), /^\.[0-9]+/); e += RLENGTH; nonint = 1 }
    if (st > 1 && substr(s, st - 1, 1) == "~") { ds = st - 1; nonint = 1 }
    if (st > 1 && substr(s, st - 1, 1) == "." && (st == 2 || substr(c, st - 2, 1) !~ /[A-Za-z0-9.]/)) { ds = st - 1; nonint = 1 }
    nword = 0
    sw = (substr(s, e, 1) == "-") ? 1 : ((substr(s, e, 3) == en) ? 3 : 0)
    if (sw && substr(s, e + sw, 1) ~ /[0-9]/) {
      match(substr(s, e + sw), "^" dec); e += sw + RLENGTH; nonint = 1
    } else if (substr(s, e, 1) == "-" && substr(s, e + 1, 1) ~ /[A-Za-z]/) {
      match(substr(s, e + 1), /^[A-Za-z]+/); e += 1 + RLENGTH; nword = 1
    }
    if (!nword && match(substr(s, e), /^[A-Za-z%][A-Za-z0-9%]*/)) { e += RLENGTH; nonint = 1 }
    nc++
    cpos[nc] = st; ctext[nc] = substr(s, ds, e - ds)
    v = digits; gsub(/,/, "", v); cval[nc] = nonint ? "-" : v
    cb[nc] = 0
    i = e
  }
  # 5b. spelled numbers (outside code spans, comments and markers: the prepared line)
  nw = 0; i = 1
  lc = tolower(s)
  while (i <= length(lc)) {
    if (!match(substr(lc, i), /[a-z]+/)) break
    st = i + RSTART - 1; ln = RLENGTH; w = substr(lc, st, ln); i = st + ln
    if (w in wset) { nw++; wpos[nw] = st; wtext[nw] = substr(s, st, ln) }
  }
  # 6. bind: each marker takes the nearest unbound claim to its left
  ni = 0; from = 1
  for (k = 1; k <= nm; k++) {
    p = index(substr(s, from), PH)
    if (p == 0) mpos = length(s) + 1; else { mpos = from + p - 1; from = mpos + 1 }
    best = 0
    for (j = 1; j <= nc; j++) if (!cb[j] && cpos[j] < mpos) best = j
    if (best) cb[best] = k
    else { ni++; ipos[ni] = mpos; itype[ni] = "M"; iidx[ni] = k }
  }
  for (j = 1; j <= nc; j++) { ni++; ipos[ni] = cpos[j]; itype[ni] = "C"; iidx[ni] = j }
  for (j = 1; j <= nw; j++) { ni++; ipos[ni] = wpos[j]; itype[ni] = "W"; iidx[ni] = j }
  for (a = 1; a < ni; a++) for (b = a + 1; b <= ni; b++) if (ipos[b] < ipos[a]) {
    t1 = ipos[a]; ipos[a] = ipos[b]; ipos[b] = t1
    t1 = itype[a]; itype[a] = itype[b]; itype[b] = t1
    t1 = iidx[a]; iidx[a] = iidx[b]; iidx[b] = t1
  }
  for (a = 1; a <= ni; a++) {
    j = iidx[a]
    if (itype[a] == "C") emit("C", NR, ctext[j], cval[j], context(cpos[j]), cb[j])
    else if (itype[a] == "W") emit("W", NR, wtext[j], "-", context(wpos[j]), 0)
    else emit("M", NR, "-", "-", context(ipos[a]), j)
  }
}
AWK

# --- counters and the verdict printer --------------------------------------------------------------------------------
n_claims=0; n_ok=0; n_mm=0; n_hand=0; n_unb=0; n_word=0; n_bad=0

# path_problem PATH — prints why PATH is not an acceptable marker path (nothing when it is).
path_problem() {
  local p="$1" dp d
  case "$p" in /*) echo "path '$p' is absolute (repo-relative only)"; return ;; esac
  case "/$p/" in */../*) echo "path '$p' has a '..' segment"; return ;; esac
  if [ ! -f "$repo_dir/$p" ]; then echo "path '$p' is not a file in the repository"; return; fi
  if [ -L "$repo_dir/$p" ]; then echo "path '$p' is a symlink"; return; fi
  dp="$(dirname -- "$p")"
  d="$(cd "$repo_dir/$dp" 2>/dev/null && pwd -P)" || { echo "path '$p' is not readable"; return; }
  case "$d/" in "$repo_real"/*) ;; *) echo "path '$p' is not under the repository"; return ;; esac
}

# strip_zeros N — N with leading zeros dropped (007 equals 7).
strip_zeros() {
  local v="$1"
  v="${v#"${v%%[!0]*}"}"
  printf '%s' "${v:-0}"
}

# derive KIND ERE PATHS — prints the derived integer; returns 2 (no output) when grep rejects the ERE.
derive() {
  local kind="$1" ere="$2" paths="$3" p n total rc c
  local -a parr
  case "$kind" in
    words)
      n="$(awk '{ n += NF } END { print n + 0 }' "$repo_dir/$paths")"
      printf '%s' "$n" ;;
    lines)
      n="$(wc -l < "$repo_dir/$paths")"
      printf '%s' "$((n + 0))" ;;
    matches)
      IFS=$'\036' read -r -a parr <<< "$paths"
      total=0
      for p in "${parr[@]}"; do
        rc=0
        c="$(grep -cE -- "$ere" "$repo_dir/$p" 2>/dev/null)" || rc=$?
        [ "$rc" -le 1 ] || return 2
        total=$((total + c))
      done
      printf '%s' "$total" ;;
  esac
}

# marker_problem KIND ERE PATHS — the reason a parsed non-hand marker is unusable (path, then ERE); nothing if fine.
marker_problem() {
  local kind="$1" ere="$2" paths="$3" p why rc
  local -a parr
  [ "$kind" != hand ] || return 0
  IFS=$'\036' read -r -a parr <<< "$paths"
  for p in "${parr[@]}"; do
    why="$(path_problem "$p")"
    if [ -n "$why" ]; then printf '%s' "$why"; return 0; fi
  done
  if [ "$kind" = matches ]; then
    rc=0
    grep -cE -- "$ere" /dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -gt 1 ]; then printf 'invalid ERE: grep rejects it'; return 0; fi
  fi
}

# scan LABEL HEADING — read one fence-blanked text on stdin; print a finding per record.
scan() {
  local label="$1" heading="$2" recs typ ln txt val ctx mst mkind mere mpaths margs mbad _end
  local why got
  recs="$(awk -v h="$heading" "$awk_prog")"
  while IFS=$'\037' read -r typ ln txt val ctx mst mkind mere mpaths margs mbad _end; do
    [ -n "$typ" ] || continue
    if [ "$typ" = W ]; then
      n_word=$((n_word + 1))
      printf 'WORD %s:%s: %s — %s\n' "$label" "$ln" "$txt" "$ctx"
      continue
    fi
    [ "$typ" != C ] || n_claims=$((n_claims + 1))
    case "$mst" in
      N)
        n_unb=$((n_unb + 1))
        printf 'UNBOUND %s:%s: %s — %s\n' "$label" "$ln" "$txt" "$ctx"
        continue ;;
      B) why="$mbad" ;;
      *)
        why="$(marker_problem "$mkind" "$mere" "$mpaths")"
        if [ -z "$why" ] && [ "$typ" = M ]; then why="marker with no unbound claim to its left"; fi
        if [ -z "$why" ] && [ "$mkind" != hand ] && [ "$val" = "-" ]; then
          why="$mkind on a non-integer claim (a range, ~, decimal or suffix cannot be re-derived: use hand)"
        fi ;;
    esac
    if [ -n "$why" ]; then
      n_bad=$((n_bad + 1))
      printf 'BADMARK %s:%s: %s — %s\n' "$label" "$ln" "$txt" "$why"
      continue
    fi
    if [ "$mkind" = hand ]; then
      n_hand=$((n_hand + 1))
      printf 'HAND %s:%s: %s — %s\n' "$label" "$ln" "$txt" "$margs"
      continue
    fi
    got="$(derive "$mkind" "$mere" "$mpaths")" || true
    if [ -z "$got" ]; then
      n_bad=$((n_bad + 1))
      printf 'BADMARK %s:%s: %s — %s\n' "$label" "$ln" "$txt" "grep failed on the marker's file"
    elif [ "$got" = "$(strip_zeros "$val")" ]; then
      n_ok=$((n_ok + 1))
      printf 'OK %s:%s: %s — %s %s = %s\n' "$label" "$ln" "$txt" "$mkind" "$margs" "$got"
    else
      n_mm=$((n_mm + 1))
      printf 'MISMATCH %s:%s: %s — %s %s gives %s\n' "$label" "$ln" "$txt" "$mkind" "$margs" "$got"
    fi
  done <<< "$recs"
}

# fence_parity FILE LABEL — refuse (exit 2) a file with an odd number of fence markers: the blanking would
# stay "in fence" to the end and --strict would pass numbers it never saw.
fence_parity() {
  local marks
  marks="$(grep -cE '^[[:space:]]*(```|~~~)' "$1" || true)"
  [ $((marks % 2)) -eq 0 ] || die "$2 has an odd number of fence markers ($marks) — an unclosed fenced block hides every later line; close it first"
}

# --- the fragments and CHANGELOG.md --------------------------------------------------------------------------------------
if [ -n "$section" ] || [ "$nfrag" -eq 0 ]; then read_changelog=1; else read_changelog=0; fi
if [ -n "$section" ]; then read_frags=0; else read_frags=1; fi

blanked=""
if [ "$read_changelog" = 1 ]; then
  if [ -f "$changelog" ]; then
    fence_parity "$changelog" CHANGELOG.md
    blanked="$(blank_fenced_blocks "$changelog")"
    unreleased_count="$(grep -c '^## \[Unreleased\]' <<< "$blanked" || true)"
    [ "$unreleased_count" = 1 ] || die "CHANGELOG.md has $unreleased_count '## [Unreleased]' headings, expected exactly 1"
    if [ -n "$section" ]; then
      sec_count="$(grep -c "^## \[${section//./\\.}\]" <<< "$blanked" || true)"
      [ "$sec_count" -ge 1 ] || die "no section '## [$section]' in CHANGELOG.md"
    fi
  elif [ -n "$section" ]; then
    die "--section needs a CHANGELOG.md in $repo_dir"
  fi
fi

if [ "$read_frags" = 1 ]; then
  listing="$("$reader" --repo "$repo_dir" --list)" || die "the fragment reader failed (changelog-fragments.sh --list)"
  if [ "$nfrag" -gt 0 ]; then
    chosen=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -qxF -- "$f" <<< "$listing" || die_args "--fragment '$f' is not a fragment the reader lists (changelog-fragments.sh --list)"
      chosen="$chosen$f"$'\n'
    done <<< "$frag_args"
    listing="$chosen"
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fence_parity "$repo_dir/$f" "$f"
    text="$(blank_fenced_blocks "$repo_dir/$f")"
    scan "$f" "" <<< "$text"
  done <<< "$listing"
fi

if [ "$read_changelog" = 1 ] && [ -f "$changelog" ]; then
  scan CHANGELOG.md "## [${section:-Unreleased}]" <<< "$blanked"
fi

printf 'changelog-claims: %d claim(s): %d ok, %d mismatched, %d hand, %d unbound, %d word, %d bad marker(s)\n' \
  "$n_claims" "$n_ok" "$n_mm" "$n_hand" "$n_unb" "$n_word" "$n_bad"
if [ "$n_mm" -gt 0 ] || [ "$n_bad" -gt 0 ]; then exit 1; fi
if [ "$strict" = 1 ] && [ "$n_unb" -gt 0 ]; then exit 1; fi
exit 0
