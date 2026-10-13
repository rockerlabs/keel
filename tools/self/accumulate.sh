#!/usr/bin/env bash
# tools/self/accumulate.sh — keel-self-maintenance (dir #838; dir #68: never installed by install.sh): the generic
# finding accumulator. A recurring defect class is noticed today only when a person connects two tickets, and the
# hand-kept `[n×]` counters that were meant to do it rarely move. This tool is the counter: a CLASS REGISTRY
# (classes.tsv), an append-only SIGHTING LOG (sightings.tsv), and the arithmetic over them — ageing, distinct-source
# counting, the threshold check — done here in tested awk, never in a model's prose. It lists what is due and never
# files: the consumer that owns a class (the command observer, dir #842's guard register, a later /triage observer)
# does the filing. It reads a backlog only in `closed` and `verdict`; it never edits a ticket, and sources
# tools/lib/backlog-blocks.sh for the closure vocabulary instead of keeping a copy of it.
#
# Model (spec dir #838 B2, B3, B7, B12, B13):
#   class      stable id `[a-z0-9:-]+` (kebab-case, or a consumer's own key such as `<guard>:<shape-slug>`), a title,
#              the `fix` (one sentence naming where the change lives), an `owner` (the consumer group that files), a
#              `created` date, a `status`, an optional `threshold` (blank -> 2), `window` in days (blank -> 60) and
#              `counts` (blank -> every distinct source counts; `felt` -> only `felt yes` sightings count).
#   status     `open` | `promoted:<ref>:<date>` | `fixed:<ref>:<date>` | `retired:<date>` (a `<ref>` may itself carry
#              colons, `draft:<file name>`; the date is always the last `:`-field).
#   sighting   date, class, consumer, source, felt, danger, model, evidence, note. Stored unique by
#              (class, source, consumer) and COUNTED by distinct `source` — a source is one independent event (an audit
#              run, a real session), however many legs or consumers recorded it.
#   counting   a sighting counts at D (--as-of) iff date <= D and D - date < window days (a 59-day-old sighting counts at
#              window 60, a 60-day-old one does not), it passes the class's `counts` filter, and — for a `fixed`
#              class — it is dated strictly AFTER the fixed date (recurrence counts from the fix's closure).
#   due        a class of the owner that is `open` or `fixed` and has count >= threshold, or has a counting sighting
#              with `felt yes` and `danger yes` (due at once). A `promoted` class is never due.
#   danger     this tool only reads the `felt` and `danger` columns; what is dangerous is each consumer's own rule.
# All day arithmetic is awk integer arithmetic on the ISO date (a days-from-civil formula), never `date`; the one `date`
# call is the default for --as-of and the lock's start time.
#
# Usage: accumulate.sh --dir DIR [--as-of D] <subcommand> [args]     (options may sit anywhere on the line)
#   init                                                         create the two TSVs with their headers (refuses if present)
#   lock | unlock                                                the run-level lock (a dir inside DIR); lock exits 2 on a
#                                                                live one and breaks one older than 2 hours, saying so
#   new-class CLASS TITLE FIX OWNER [THRESHOLD] [WINDOW] [COUNTS]
#   add DATE CLASS CONSUMER SOURCE FELT DANGER MODEL EVIDENCE [NOTE]
#                                                                a duplicate (class, source, consumer) prints `dup`, exit 0;
#                                                                a sighting of a `retired` class reopens it
#   count CLASS                                                  the distinct counting sources at the as-of day
#   due --owner O [--verbose]                                    class ids due, one per line (--verbose: id, count, reason)
#   status --owner O                                             open=N at-threshold-1=N retired-at-D=N promoted-seen-again=N
#   promote CLASS REF                                            open|fixed -> promoted:REF:<as-of>
#   fixed CLASS REF [--date D]                                   promoted -> fixed:REF:D (D defaults to the as-of day)
#   retire                                                       every `open` class with count 0 -> retired:<as-of>; never
#                                                                a promoted or fixed one
#   closed CLASS --backlog PATH… --drafts DIR…                   open | closed <✅|❌> <date or —> | draft | orphaned
#   verdict --consumer C --backlog PATH… --drafts DIR…           NEEDS-REWORK <classes> | CLEAR
#   lint                                                         header, tabs, field shapes, dates, unknown classes,
#                                                                duplicates, statuses
#   --selftest | --help
# `closed` finds the `Observer-class: CLASS` line (anchored, outside code fences), takes the nearest `### ` heading above
# it (any id form: `dir #N`, `KB.N`, `B.N`, `H.N`), and tests that heading block — the heading line plus its wrapped
# continuation lines up to the first blank — against BB_CLOSURE_TAG_PATTERN. Several tags for one class (an old closed
# ticket and a recurrence): any open ticket -> `open`, else a draft -> `draft`, else the latest closed one, else `orphaned`.
# Every write runs under the lock: one the caller already holds (a `lock` earlier in the run), else one taken and released
# for that single write. The lock is cooperative and guards a RUN, not a single write: a write that finds ANY lock
# proceeds (the run that took it was a separate process and the tool cannot tell its own caller from another run), so two
# bare writes with no `lock` held are not serialised, and a stale lock is only reported and broken by `lock` itself. The
# exclusion between runs is `lock` (exit 2); every run takes it first. A value that starts with a dash goes after `--`. Exit: 0 ok, 1 a `lint` finding, 2 a usage, lock or I/O error.
set -u
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

self_path="${BASH_SOURCE[0]}"
self_dir="$(cd "$(dirname "$self_path")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"
# shellcheck source=tools/lib/backlog-blocks.sh
. "$self_dir/../lib/backlog-blocks.sh"

TAB="$(printf '\t')"
NL=$'\n'
US=$'\037'
HDR_CLASSES="class${TAB}title${TAB}fix${TAB}owner${TAB}created${TAB}status${TAB}threshold${TAB}window${TAB}counts"
HDR_SIGHTINGS="date${TAB}class${TAB}consumer${TAB}source${TAB}felt${TAB}danger${TAB}model${TAB}evidence${TAB}note"
LOCK_STALE_SECONDS=7200

die() { printf 'accumulate: %s\n' "$*" >&2; exit 2; }
lock_release() { rm -f "$DIR/.lock/info"; rmdir "$DIR/.lock" 2>/dev/null; }

usage() {
  cat <<'EOF'
Usage: accumulate.sh --dir DIR [--as-of D] <subcommand> [args]
  init | lock | unlock | lint | retire | --selftest
  new-class CLASS TITLE FIX OWNER [THRESHOLD] [WINDOW] [COUNTS]
  add DATE CLASS CONSUMER SOURCE FELT DANGER MODEL EVIDENCE [NOTE]
  count CLASS | due --owner O [--verbose] | status --owner O
  promote CLASS REF | fixed CLASS REF [--date D]
  closed CLASS --backlog PATH... --drafts DIR...
  verdict --consumer C --backlog PATH... --drafts DIR...
Counts distinct independent sources per class inside a window, flags the classes past their threshold, and lists them;
it never files a ticket. Exit 0 ok, 1 a lint finding, 2 a usage, lock or I/O error. See the header of this file.
EOF
}

# --- awk: the date arithmetic and the one place the facts are computed ----------------------------------------------------
AWKLIB='
function isdate(s,   y, m, d, dim) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m < 1 || m > 12 || d < 1) return 0
  dim = substr("312831303130313130313031", (m - 1) * 2 + 1, 2) + 0
  if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) dim = 29
  return d <= dim
}
function dn(s,   y, m, d, era, yoe, doy, doe) {
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m <= 2) y -= 1
  era = int(y / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe
}
function statusok(st,   p, d, ref) {
  if (st == "open") return 1
  if (st ~ /^retired:/) return isdate(substr(st, 9))
  if (st !~ /^(promoted|fixed):/) return 0
  if (length(st) < 14) return 0
  d = substr(st, length(st) - 9)
  if (substr(st, length(st) - 10, 1) != ":" || !isdate(d)) return 0
  p = index(st, ":")
  ref = substr(st, p + 1, length(st) - p - 11)
  return ref != ""
}
'
AWK() { LC_ALL=C awk "$@"; }

valid_date() { ACC_V="$1" AWK "${AWKLIB}"'BEGIN { exit !isdate(ENVIRON["ACC_V"]) }'; }
no_ctl() { case "$1" in *"$TAB"*|*"$NL"*) return 1 ;; esac; return 0; }
is_id() { [[ "$1" =~ ^[a-z0-9:-]+$ ]]; }
valid_ref() { no_ctl "$1" && [ -n "$1" ]; }
date_gt() { [ "${1//-/}" -gt "${2//-/}" ]; }   # ISO dates compared as integers: no locale collation involved
is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

# --- arguments ---------------------------------------------------------------------------------------------------------------------
DIR=""; ASOF=""; OWNER=""; CONSUMER=""; FDATE=""; VERBOSE=0; SELFTEST=0
pos=(); BACKLOGS=(); DRAFTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) if [ "${#pos[@]}" -eq 0 ]; then usage; exit 0; fi; die "unexpected $1 after the subcommand (a value starting with a dash goes after --)" ;;
    --) shift; while [ $# -gt 0 ]; do pos+=("$1"); shift; done ;;
    --selftest) SELFTEST=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --dir|--as-of|--owner|--consumer|--date)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --dir) DIR="$2" ;; --as-of) ASOF="$2" ;; --owner) OWNER="$2" ;;
        --consumer) CONSUMER="$2" ;; --date) FDATE="$2" ;;
      esac
      shift 2 ;;
    --backlog|--drafts)
      opt="$1"; shift
      while [ $# -gt 0 ]; do
        case "$1" in --*) break ;; esac
        if [ "$opt" = --backlog ]; then BACKLOGS+=("$1"); else DRAFTS+=("$1"); fi
        shift
      done ;;
    --*) die "unknown option: $1" ;;
    *) pos+=("$1"); shift ;;
  esac
done

TOOK_LOCK=0; TMPF=""
cleanup() {
  [ -n "$TMPF" ] && rm -f "$TMPF"
  if [ "$TOOK_LOCK" = 1 ]; then lock_release; fi
  return 0
}
trap cleanup EXIT

# --- the lock: a dir inside DIR holding `pid<TAB>epoch` -------------------------------------------------------------------------------
lock_take() {   # lock_take → 0 taken, 2 held by a live run; prints the report line for a stale break
  local l="$DIR/.lock" now ts pid age
  now="$(date +%s)"
  if [ -d "$l" ]; then
    ts=""; pid=""
    if [ -f "$l/info" ]; then
      pid="$(AWK -F'\t' 'NR == 1 { print $1 }' "$l/info")"
      ts="$(AWK -F'\t' 'NR == 1 && $2 ~ /^[0-9]+$/ { print $2 }' "$l/info")"
    fi
    if [ -z "$ts" ]; then
      printf 'accumulate: lock held (no readable start time in %s/info); remove %s if no run is active\n' "$l" "$l" >&2
      return 2
    fi
    age=$((now - ts))
    if [ "$age" -gt "$LOCK_STALE_SECONDS" ]; then
      printf 'accumulate: stale lock broken (held by pid %s since epoch %s, %s s old)\n' "$pid" "$ts" "$age"
      lock_release; [ ! -d "$l" ] || die "could not remove the stale lock $l"
    else
      printf 'accumulate: lock held by pid %s since epoch %s (%s s old)\n' "$pid" "$ts" "$age" >&2
      return 2
    fi
  fi
  mkdir "$l" 2>/dev/null || { printf 'accumulate: lock held (taken just now by another run)\n' >&2; return 2; }
  printf '%s\t%s\n' "$$" "$now" > "$l/info"
  return 0
}

write_lock() {   # a write holds the lock: the caller's, else its own for this one process
  [ -d "$DIR/.lock" ] && return 0
  lock_take >/dev/null || die "could not take the lock"
  TOOK_LOCK=1
}

# --- TSV helpers ------------------------------------------------------------------------------------------------------------------------
CF=""; SF=""
need_dir() {
  [ -n "$DIR" ] || die "--dir is required"
  [ -d "$DIR" ] || die "data dir $DIR does not exist"
}
need_files() {
  need_dir
  CF="$DIR/classes.tsv"; SF="$DIR/sightings.tsv"
  [ -f "$CF" ] && [ -r "$CF" ] || die "no readable $CF (run init)"
  [ -f "$SF" ] && [ -r "$SF" ] || die "no readable $SF (run init)"
}
ensure_newline() { if [ -n "$(tail -c1 "$1")" ]; then printf '\n' >> "$1"; fi; }
class_exists() { ACC_C="$1" AWK -F'\t' 'NR > 1 && $1 == ENVIRON["ACC_C"] { found = 1 } END { exit !found }' "$CF"; }
class_status() { ACC_C="$1" AWK -F'\t' 'NR > 1 && $1 == ENVIRON["ACC_C"] { print $6 }' "$CF"; }
class_word() { local s; s="$(class_status "$1")"; printf '%s' "${s%%:*}"; }
set_status() {   # set_status CLASS NEWSTATUS — rewrites only the status cell of one row
  local tmp
  tmp="$(mktemp "$DIR/.acc.XXXXXX")" || die "mktemp failed in $DIR"
  TMPF="$tmp"
  ACC_C="$1" ACC_S="$2" AWK -F'\t' -v OFS='\t' 'NR > 1 && $1 == ENVIRON["ACC_C"] { $6 = ENVIRON["ACC_S"] } { print }' "$CF" > "$tmp" \
    || die "could not rewrite $CF"
  cat "$tmp" > "$CF" || die "could not write $CF"
  rm -f "$tmp"; TMPF=""
}

# facts → one TSV line per class, in registry order:
#   class owner statusword threshold count danger(0|1) seen-again(0|1) consumers(csv, `-` if none) status-date(`-` if none)
facts() {
  ACC_D="$ASOF" AWK "${AWKLIB}"'
  BEGIN { FS = "\t"; OFS = "\t"; D = ENVIRON["ACC_D"]; Dn = dn(D) }
  FILENAME == ARGV[1] {
    if (FNR == 1) next
    id = $1; ord[++nc] = id; owner[id] = $4; st = $6
    thr[id] = ($7 == "" ? 2 : $7 + 0); win[id] = ($8 == "" ? 60 : $8 + 0); cnt[id] = $9
    p = index(st, ":")
    if (p == 0) { sw[id] = st; sd[id] = "" } else { sw[id] = substr(st, 1, p - 1); sd[id] = substr(st, length(st) - 9) }
    next
  }
  {
    if (FNR == 1) next
    id = $2
    if (!(id in owner)) next
    if (!isdate($1)) next
    if (cnt[id] == "felt" && $5 != "yes") next
    if ($1 > D) next
    if (Dn - dn($1) >= win[id]) next
    if (sw[id] == "fixed" && $1 <= sd[id]) next
    k = id SUBSEP $4
    if (!(k in seen)) { seen[k] = 1; count[id]++ }
    if ($5 == "yes" && $6 == "yes") danger[id] = 1
    ck = id SUBSEP $3
    if (!(ck in cs)) { cs[ck] = 1; cl[id] = (cl[id] == "" ? "" : cl[id] ",") $3 }
    if (sw[id] == "promoted" && $1 > sd[id]) again[id] = 1
  }
  END {
    for (i = 1; i <= nc; i++) {
      id = ord[i]
      print id, owner[id], sw[id], thr[id], count[id] + 0, danger[id] + 0, again[id] + 0, (cl[id] == "" ? "-" : cl[id]), (sd[id] == "" ? "-" : sd[id])
    }
  }' "$CF" "$SF"
}

# --- closed: the ticket behind an `Observer-class:` line --------------------------------------------------------------------------------
# hits_in_file FILE CLASS → one record per tagged heading block, newlines inside the block turned into US
hits_in_file() {
  local fb
  grep -qF -- "Observer-class: $2" "$1" || return 0
  fb="$(blank_fenced_blocks "$1")"
  printf '%s\n' "$fb" | ACC_C="$2" AWK '
  { sub(/\r$/, ""); line[NR] = $0 }
  END {
    tag = "Observer-class: " ENVIRON["ACC_C"]
    h = 0
    for (i = 1; i <= NR; i++) {
      if (line[i] ~ /^## /) h = 0
      else if (line[i] ~ /^### /) h = i
      else if (h > 0 && !(h in done)) {
        t = line[i]; sub(/[ \t]+$/, "", t)
        if (t == tag) {
          done[h] = 1; rec = line[h]; n = 1
          for (j = h + 1; j <= NR && line[j] != "" && n < 50; j++) { rec = rec "\037" line[j]; n++ }
          print rec
        }
      }
    }
  }'
}

# closed_state CLASS → prints open | closed <glyph> <date|—> | draft | orphaned
closed_state() {
  local cls="$1" f d rec block stripped m rest glyph cdate own
  local any_open=0 any_draft=0 best_glyph="" best_date="" best_key="" ckey
  for f in ${BACKLOGS[@]+"${BACKLOGS[@]}"}; do
    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      block="$(blank_inline_code_spans <<< "${rec//$US/$NL}")"
      own="$(bb_own_ticket_num "$block")"
      stripped="$(bb_strip_foreign_citations "$block" "$own" "$BB_CLOSURE_TAG_PATTERN")"
      if [[ "$stripped" =~ (—[[:space:]]*)?${BB_CLOSURE_TAG_PATTERN}([^a-zA-Z]|$) ]]; then
        m="${BASH_REMATCH[0]}"
        case "$m" in *❌*) glyph="❌" ;; *) glyph="✅" ;; esac
        rest="$m${stripped#*"$m"}"
        cdate="—"
        # the tag word is the first capitals in $rest (BB_CLOSURE_TAG_PATTERN is uppercase-only); the date must follow it on the same line
        if [[ "$rest" =~ ^[^[:upper:]]*[[:upper:]]+[^0-9${NL}]{0,40}([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ]]; then cdate="${BASH_REMATCH[1]}"; fi
        ckey="$cdate"; [ "$cdate" = "—" ] && ckey=0000-00-00
        case "$glyph" in ✅) ckey="${ckey//-/}1" ;; *) ckey="${ckey//-/}0" ;; esac
        if [ -z "$best_key" ] || [ "$ckey" -gt "$best_key" ]; then best_glyph="$glyph"; best_date="$cdate"; best_key="$ckey"; fi
      else
        any_open=1
      fi
    done <<< "$(hits_in_file "$f" "$cls")"
  done
  for f in ${DRAFTS[@]+"${DRAFTS[@]}"}; do
    [ -d "$f" ] || continue
    for d in "$f"/*.md; do
      [ -f "$d" ] || continue
      if [ -n "$(hits_in_file "$d" "$cls")" ]; then any_draft=1; fi
    done
  done
  if [ "$any_open" = 1 ]; then printf 'open\n'
  elif [ "$any_draft" = 1 ]; then printf 'draft\n'
  elif [ -n "$best_glyph" ]; then printf 'closed %s %s\n' "$best_glyph" "$best_date"
  else printf 'orphaned\n'
  fi
}

need_paths() {   # closed / verdict: the backlog files must exist; a missing drafts dir is simply empty
  local f
  [ "${#BACKLOGS[@]}" -gt 0 ] || die "--backlog PATH is required"
  for f in "${BACKLOGS[@]}"; do [ -f "$f" ] && [ -r "$f" ] || die "no readable backlog file $f"; done
}

# --- lint ----------------------------------------------------------------------------------------------------------------------------------
do_lint() {
  ACC_HC="$HDR_CLASSES" ACC_HS="$HDR_SIGHTINGS" AWK "${AWKLIB}"'
  BEGIN { FS = "\t"; bad = 0 }
  function err(f, n, m) { printf "lint: %s:%d: %s\n", f, n, m; bad = 1 }
  FILENAME == ARGV[1] {
    f = "classes.tsv"
    if (FNR == 1) { if ($0 != ENVIRON["ACC_HC"]) err(f, FNR, "header is not the classes header"); next }
    if (NF != 9) { err(f, FNR, "fields: want 9, got " NF); next }
    id = $1
    if (id !~ /^[a-z0-9:-]+$/) err(f, FNR, "class id outside [a-z0-9:-]")
    if (id in known) err(f, FNR, "duplicate class id " id)
    known[id] = 1
    if ($2 == "") err(f, FNR, "title is empty")
    if ($3 == "") err(f, FNR, "fix is empty")
    if ($4 == "" || $4 !~ /^[a-z0-9:-]+$/) err(f, FNR, "owner is empty or outside [a-z0-9:-]")
    if (!isdate($5)) err(f, FNR, "created is not a date: " $5)
    if (!statusok($6)) err(f, FNR, "status is not open | promoted:REF:DATE | fixed:REF:DATE | retired:DATE: " $6)
    if ($7 != "" && $7 !~ /^[1-9][0-9]*$/) err(f, FNR, "threshold is not a positive integer: " $7)
    if ($8 != "" && $8 !~ /^[1-9][0-9]*$/) err(f, FNR, "window is not a positive integer: " $8)
    if ($9 != "" && $9 != "felt") err(f, FNR, "counts is neither blank nor felt: " $9)
    next
  }
  {
    f = "sightings.tsv"
    if (FNR == 1) { if ($0 != ENVIRON["ACC_HS"]) err(f, FNR, "header is not the sightings header"); next }
    if (NF != 9) { err(f, FNR, "fields: want 9, got " NF); next }
    if (!isdate($1)) err(f, FNR, "date is not a date: " $1)
    if (!($2 in known)) err(f, FNR, "unknown class " $2)
    if ($3 !~ /^\/?[a-z0-9-]+$/) err(f, FNR, "consumer outside /?[a-z0-9-]: " $3)
    if ($4 !~ /^[a-z]+:./) err(f, FNR, "source is not kind:value: " $4)
    if ($5 != "yes" && $5 != "no") err(f, FNR, "felt is neither yes nor no: " $5)
    if ($6 != "yes" && $6 != "no") err(f, FNR, "danger is neither yes nor no: " $6)
    if ($7 == "") err(f, FNR, "model is empty")
    if ($8 == "") err(f, FNR, "evidence is empty")
    k = $2 SUBSEP $4 SUBSEP $3
    if (k in seen) err(f, FNR, "duplicate (class, source, consumer): " $2 ", " $4 ", " $3)
    seen[k] = 1
  }
  END { exit bad }' "$CF" "$SF"
}

# --- selftest ---------------------------------------------------------------------------------------------------------------------------------
do_selftest() {
  local d out rc
  d="$(mktemp -d "${TMPDIR:-/tmp}/accumulate-selftest.XXXXXX")" || die "mktemp failed"
  out="$(
    set -e
    t() { bash "$self_path" --dir "$d" --as-of 2026-10-13 "$@"; }
    t init
    t new-class st-class "a title" "a rule in a file" commands
    t add 2026-10-01 st-class /polish audit:p@a yes no m ev
    t add 2026-10-02 st-class /polish audit:p@b yes no m ev
    [ "$(t count st-class)" = 2 ] || { echo "count != 2"; exit 1; }
    [ "$(t due --owner commands)" = st-class ] || { echo "due != st-class"; exit 1; }
    t lint
  )"; rc=$?
  rm -f "$d/classes.tsv" "$d/sightings.tsv"; rmdir "$d" 2>/dev/null
  [ "$rc" -eq 0 ] || { printf '%s\n' "$out" >&2; die "selftest failed"; }
  printf 'accumulate: selftest ok\n'
}

# --- dispatch -----------------------------------------------------------------------------------------------------------------------------
[ "$SELFTEST" = 1 ] && { do_selftest; exit 0; }
[ "${#pos[@]}" -gt 0 ] || { usage >&2; exit 2; }
cmd="${pos[0]}"
[ -n "$DIR" ] || die "--dir is required"
if [ -z "$ASOF" ]; then ASOF="$(date +%Y-%m-%d)"; fi
valid_date "$ASOF" || die "--as-of is not a date: $ASOF"
# a stray argument (a misplaced --help, a forgotten --) is an error, never a silent no-op or a surprise write
case "$cmd" in
  init|lock|unlock|retire|lint|due|status|verdict) max_pos=1 ;;
  count|closed) max_pos=2 ;;
  promote|fixed) max_pos=3 ;;
  new-class) max_pos=8 ;;
  add) max_pos=10 ;;
  *) die "unknown subcommand: $cmd" ;;
esac
[ "${#pos[@]}" -le "$max_pos" ] || die "unexpected argument: ${pos[$max_pos]} (a value starting with a dash goes after --)"

case "$cmd" in
  init)
    mkdir -p "$DIR" || die "cannot create $DIR"
    if [ -e "$DIR/classes.tsv" ] || [ -e "$DIR/sightings.tsv" ]; then die "$DIR already holds a TSV — init never overwrites"; fi
    printf '%s\n' "$HDR_CLASSES" > "$DIR/classes.tsv" || die "cannot write $DIR/classes.tsv"
    printf '%s\n' "$HDR_SIGHTINGS" > "$DIR/sightings.tsv" || die "cannot write $DIR/sightings.tsv"
    ;;

  lock)
    need_dir
    lock_take
    exit $?
    ;;

  unlock)
    need_dir
    lock_release
    ;;

  new-class)
    need_files
    [ "${#pos[@]}" -ge 5 ] || die "new-class CLASS TITLE FIX OWNER [THRESHOLD] [WINDOW] [COUNTS]"
    c_id="${pos[1]}"; c_title="${pos[2]}"; c_fix="${pos[3]}"; c_owner="${pos[4]}"
    c_thr="${pos[5]-}"; c_win="${pos[6]-}"; c_cnt="${pos[7]-}"
    for v in "$c_id" "$c_title" "$c_fix" "$c_owner" "$c_thr" "$c_win" "$c_cnt"; do no_ctl "$v" || die "a field holds a TAB or newline"; done
    is_id "$c_id" || die "class id must match [a-z0-9:-]+: $c_id"
    is_id "$c_owner" || die "owner must match [a-z0-9:-]+: $c_owner"
    [ -n "$c_title" ] && [ -n "$c_fix" ] || die "title and fix must be non-empty"
    [ -z "$c_thr" ] || is_posint "$c_thr" || die "threshold must be a positive integer: $c_thr"
    [ -z "$c_win" ] || is_posint "$c_win" || die "window must be a positive integer: $c_win"
    [ -z "$c_cnt" ] || [ "$c_cnt" = felt ] || die "counts must be blank or felt: $c_cnt"
    class_exists "$c_id" && die "class $c_id already exists"
    write_lock
    ensure_newline "$CF"
    printf '%s\t%s\t%s\t%s\t%s\topen\t%s\t%s\t%s\n' "$c_id" "$c_title" "$c_fix" "$c_owner" "$ASOF" "$c_thr" "$c_win" "$c_cnt" >> "$CF" \
      || die "cannot append to $CF"
    ;;

  add)
    need_files
    [ "${#pos[@]}" -ge 9 ] || die "add DATE CLASS CONSUMER SOURCE FELT DANGER MODEL EVIDENCE [NOTE]"
    s_date="${pos[1]}"; s_class="${pos[2]}"; s_cons="${pos[3]}"; s_src="${pos[4]}"
    s_felt="${pos[5]}"; s_danger="${pos[6]}"; s_model="${pos[7]}"; s_evid="${pos[8]}"; s_note="${pos[9]-}"
    for v in "$s_date" "$s_class" "$s_cons" "$s_src" "$s_felt" "$s_danger" "$s_model" "$s_evid" "$s_note"; do
      no_ctl "$v" || die "a field holds a TAB or newline"
    done
    valid_date "$s_date" || die "date is not a date: $s_date"
    date_gt "$s_date" "$ASOF" && die "date $s_date is after --as-of $ASOF"
    class_exists "$s_class" || die "unknown class: $s_class"
    [[ "$s_cons" =~ ^/?[a-z0-9-]+$ ]] || die "consumer must match /?[a-z0-9-]+: $s_cons"
    [[ "$s_src" =~ ^[a-z]+:. ]] || die "source must be kind:value (audit:… session:… spec:… entry:…): $s_src"
    case "$s_felt" in yes|no) ;; *) die "felt must be yes or no: $s_felt" ;; esac
    case "$s_danger" in yes|no) ;; *) die "danger must be yes or no: $s_danger" ;; esac
    [ -n "$s_model" ] && [ -n "$s_evid" ] || die "model and evidence must be non-empty"
    write_lock
    if ACC_C="$s_class" ACC_S="$s_src" ACC_K="$s_cons" AWK -F'\t' \
        'NR > 1 && $2 == ENVIRON["ACC_C"] && $4 == ENVIRON["ACC_S"] && $3 == ENVIRON["ACC_K"] { f = 1 } END { exit !f }' "$SF"; then
      printf 'dup\n'
      exit 0
    fi
    ensure_newline "$SF"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$s_date" "$s_class" "$s_cons" "$s_src" "$s_felt" "$s_danger" "$s_model" "$s_evid" "$s_note" >> "$SF" \
      || die "cannot append to $SF"
    if [ "$(class_word "$s_class")" = retired ]; then set_status "$s_class" open; fi
    printf 'added\n'
    ;;

  count)
    need_files
    [ "${#pos[@]}" -ge 2 ] || die "count CLASS"
    class_exists "${pos[1]}" || die "unknown class: ${pos[1]}"
    facts | ACC_C="${pos[1]}" AWK -F'\t' '$1 == ENVIRON["ACC_C"] { print $5 }'
    ;;

  due)
    need_files
    [ -n "$OWNER" ] || die "due needs --owner"
    facts | ACC_O="$OWNER" ACC_V="$VERBOSE" AWK -F'\t' -v OFS='\t' '
      $2 == ENVIRON["ACC_O"] && ($3 == "open" || $3 == "fixed") && ($5 >= $4 || $6 == 1) {
        if (ENVIRON["ACC_V"] == "1") print $1, $5, ($5 >= $4 ? "threshold" : "danger"); else print $1
      }'
    ;;

  status)
    need_files
    [ -n "$OWNER" ] || die "status needs --owner"
    facts | ACC_O="$OWNER" ACC_D="$ASOF" AWK -F'\t' '
      $2 == ENVIRON["ACC_O"] {
        if ($3 == "open" || $3 == "fixed") { open++; if ($5 >= 1 && $5 == $4 - 1) near++ }
        if ($3 == "retired" && $9 == ENVIRON["ACC_D"]) ret++
        if ($3 == "promoted" && $7 == 1) again++
      }
      END { printf "open=%d at-threshold-1=%d retired-at-D=%d promoted-seen-again=%d\n", open + 0, near + 0, ret + 0, again + 0 }'
    ;;

  promote)
    need_files
    [ "${#pos[@]}" -ge 3 ] || die "promote CLASS REF"
    p_class="${pos[1]}"; p_ref="${pos[2]}"
    valid_ref "$p_ref" || die "ref must be non-empty, without TAB or newline"
    class_exists "$p_class" || die "unknown class: $p_class"
    p_word="$(class_word "$p_class")"
    case "$p_word" in open|fixed) ;; *) die "class $p_class is $p_word; only open or fixed can be promoted" ;; esac
    write_lock
    set_status "$p_class" "promoted:$p_ref:$ASOF"
    ;;

  fixed)
    need_files
    [ "${#pos[@]}" -ge 3 ] || die "fixed CLASS REF [--date D]"
    f_class="${pos[1]}"; f_ref="${pos[2]}"; f_date="${FDATE:-$ASOF}"
    valid_ref "$f_ref" || die "ref must be non-empty, without TAB or newline"
    valid_date "$f_date" || die "--date is not a date: $f_date"
    date_gt "$f_date" "$ASOF" && die "--date $f_date is after --as-of $ASOF"
    class_exists "$f_class" || die "unknown class: $f_class"
    f_word="$(class_word "$f_class")"
    [ "$f_word" = promoted ] || die "class $f_class is $f_word; only a promoted class can be fixed"
    write_lock
    set_status "$f_class" "fixed:$f_ref:$f_date"
    ;;

  retire)
    need_files
    write_lock
    while IFS= read -r r_class; do
      [ -n "$r_class" ] || continue
      set_status "$r_class" "retired:$ASOF"
      printf '%s\n' "$r_class"
    done <<< "$(facts | AWK -F'\t' '$3 == "open" && $5 == 0 { print $1 }')"
    ;;

  closed)
    need_files
    [ "${#pos[@]}" -ge 2 ] || die "closed CLASS --backlog PATH… --drafts DIR…"
    class_exists "${pos[1]}" || die "unknown class: ${pos[1]}"
    need_paths
    closed_state "${pos[1]}"
    ;;

  verdict)
    need_files
    [ -n "$CONSUMER" ] || die "verdict needs --consumer"
    need_paths
    flagged=""
    while IFS="$TAB" read -r v_id _ v_word v_thr v_cnt v_dng _ v_cons _; do
      [ -n "$v_id" ] || continue
      case ",$v_cons," in *",$CONSUMER,"*) ;; *) continue ;; esac
      case "$v_word" in
        open|fixed) if [ "$v_cnt" -ge "$v_thr" ] || [ "$v_dng" = 1 ]; then flagged="$flagged $v_id"; fi ;;
        promoted)
          case "$(closed_state "$v_id")" in closed*) ;; *) flagged="$flagged $v_id" ;; esac ;;
      esac
    done <<< "$(facts)"
    if [ -n "$flagged" ]; then printf 'NEEDS-REWORK%s\n' "$flagged"; else printf 'CLEAR\n'; fi
    ;;

  lint)
    need_files
    do_lint
    exit $?
    ;;

esac
exit 0
