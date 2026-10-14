#!/usr/bin/env bash
# tools/self/accumulate.sh (dir #838 slice 1a): the generic finding accumulator — a class registry, an append-only
# sighting log, a counter with ageing and a threshold check. Every case here runs the tool on fixture data dirs at a
# fixed --as-of date; nothing reads the real clock except the lock's own age. The cases are the spec's A13 list (the
# window boundary, dedupe and distinct-source counting, threshold / per-class window / `counts felt`, felt danger,
# retire, promoted / fixed recurrence, `closed` on three heading forms, owner filtering, `status`, the lock and its
# stale break, lint's six failures) plus the verdict, init and usage surfaces. tests/mutants/accumulate.tsv lists the
# single-clause edits of the tool this file must turn red (tools/self/mutation-sweep.sh).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

ACC="${KEEL_ACCUMULATE_SH:-$REPO_ROOT/tools/self/accumulate.sh}"
T=2026-10-13
TAB="$(printf '\t')"

check_file "tools/self/accumulate.sh exists" "$ACC"

# A DIR ARGS… → OUT, STATUS: the tool on data dir DIR at --as-of $ASOF (default $T).
A() { local d="$1"; shift; run bash "$ACC" --dir "$d" --as-of "${ASOF:-$T}" "$@"; }
# mk → a fresh initialised data dir
mk() { local d; d="$(mktemp -d "$SANDBOX/acc.XXXXXX")"; bash "$ACC" --dir "$d" init >/dev/null 2>&1; printf '%s' "$d"; }
# cls DIR ID [OWNER [THRESHOLD [WINDOW [COUNTS]]]] — register a class (title and fix are fixed text)
cls() {
  local d="$1" id="$2" owner="${3:-commands}" thr="${4:-}" win="${5:-}" cnt="${6:-}"
  bash "$ACC" --dir "$d" --as-of "$T" new-class "$id" "title of $id" "commands/polish.md rule for $id" "$owner" "$thr" "$win" "$cnt" >/dev/null 2>&1
}
# sight DIR DATE CLASS CONSUMER SOURCE FELT DANGER — one sighting (model and evidence fixed)
sight() {
  local d="$1"
  bash "$ACC" --dir "$d" --as-of "${ASOF:-$T}" add "$2" "$3" "$4" "$5" "$6" "$7" unknown "f.md:1" >/dev/null 2>&1
}
status_of() { awk -F'\t' -v c="$2" '$1 == c { print $6 }' "$1/classes.tsv"; }
nlines() { wc -l < "$1" | tr -d ' '; }

# --- usage surface -------------------------------------------------------------------------------------------------------
run bash "$ACC" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run bash "$ACC" lint
check_status "no --dir -> exit 2" 2 "$STATUS"
d="$(mktemp -d "$SANDBOX/acc.XXXXXX")"
A "$d" bogus
check_status "unknown subcommand -> exit 2" 2 "$STATUS"
run bash "$ACC" bogus
check_contains "unknown subcommand is named even with no --dir" "$OUT" "unknown subcommand: bogus"
run bash "$ACC" init extra --as-of garbage
check_contains "a stray argument is reported ahead of --dir / --as-of problems" "$OUT" "unexpected argument: extra"
A "$d" lint
check_status "a data dir without the TSVs -> exit 2 (I/O), not a lint finding" 2 "$STATUS"
A "$d" count x
check_status "count on a dir without the TSVs -> exit 2" 2 "$STATUS"

d0="$(mktemp -d "$SANDBOX/acc.XXXXXX")"
A "$d0" init --help
check_status "init --help (a stray argument after the subcommand) -> exit 2" 2 "$STATUS"
check_nofile "... and init wrote nothing" "$d0/classes.tsv"
A "$d0" init extra
check_status "init with an extra positional -> exit 2" 2 "$STATUS"
# --- init: the headers byte for byte (A2) --------------------------------------------------------------------------------
d="$(mk)"
printf 'class\ttitle\tfix\towner\tcreated\tstatus\tthreshold\twindow\tcounts\n' > "$SANDBOX/want-classes"
printf 'date\tclass\tconsumer\tsource\tfelt\tdanger\tmodel\tevidence\tnote\n' > "$SANDBOX/want-sightings"
cmp -s "$SANDBOX/want-classes" "$d/classes.tsv"; check_status "init: classes.tsv holds exactly the header" 0 "$?"
cmp -s "$SANDBOX/want-sightings" "$d/sightings.tsv"; check_status "init: sightings.tsv holds exactly the header" 0 "$?"
A "$d" lint
check_status "lint: two header-only files are clean" 0 "$STATUS"
A "$d" init
check_status "init over existing files -> exit 2 (never clobbers)" 2 "$STATUS"
cmp -s "$SANDBOX/want-classes" "$d/classes.tsv"; check_status "init refusal leaves the files untouched" 0 "$?"

# --- new-class ------------------------------------------------------------------------------------------------------------
d="$(mk)"
A "$d" new-class polish-gap "A polish gap" "commands/polish.md step 3" commands
check_status "new-class: ok" 0 "$STATUS"
want="$(printf 'polish-gap\tA polish gap\tcommands/polish.md step 3\tcommands\t%s\topen\t\t\t' "$T")"
check_eq "new-class: the row is id, title, fix, owner, created, open, then blank threshold/window/counts" "$want" "$(sed -n 2p "$d/classes.tsv")"
A "$d" new-class polish-gap t f commands
check_status "new-class: a duplicate id -> exit 2" 2 "$STATUS"
A "$d" new-class "Bad_Id" t f commands
check_status "new-class: an id outside [a-z0-9:-] -> exit 2" 2 "$STATUS"
A "$d" new-class "guards:slug-1" t f guards 2 90 felt
check_status "new-class: a consumer's own key with a colon, threshold, window and counts felt -> ok" 0 "$STATUS"
want="$(printf 'guards:slug-1\tt\tf\tguards\t%s\topen\t2\t90\tfelt' "$T")"
check_eq "new-class: the optional columns land in order" "$want" "$(sed -n 3p "$d/classes.tsv")"
A "$d" new-class c1 t f ""
check_status "new-class: an empty owner -> exit 2" 2 "$STATUS"
A "$d" new-class c2 t f commands x
check_status "new-class: a non-numeric threshold -> exit 2" 2 "$STATUS"
A "$d" new-class c3 t f commands 2 0
check_status "new-class: a zero window -> exit 2" 2 "$STATUS"
A "$d" new-class c4 t f commands 2 60 bogus
check_status "new-class: counts other than blank/felt -> exit 2" 2 "$STATUS"
A "$d" new-class c5 "a${TAB}b" f commands
check_status "new-class: a TAB inside a field -> exit 2" 2 "$STATUS"
check_eq "none of the refusals wrote a row" 3 "$(nlines "$d/classes.tsv")"
A "$d" lint
check_status "lint: the written registry is clean" 0 "$STATUS"

# --- add: refusals, dedupe, distinct sources ----------------------------------------------------------------------------------
d="$(mk)"; cls "$d" x
A "$d" add 2026-10-01 nope /polish audit:keel@a yes no m ev
check_status "add: an unknown class -> exit 2" 2 "$STATUS"
A "$d" add 2026-10-01 x /polish audit:keel@a maybe no m ev
check_status "add: felt other than yes/no -> exit 2" 2 "$STATUS"
A "$d" add 2026-10-01 x /polish audit:keel@a yes perhaps m ev
check_status "add: danger other than yes/no -> exit 2" 2 "$STATUS"
A "$d" add 2026-13-01 x /polish audit:keel@a yes no m ev
check_status "add: an impossible date (month 13) -> exit 2" 2 "$STATUS"
A "$d" add 2026-02-30 x /polish audit:keel@a yes no m ev
check_status "add: an impossible date (Feb 30) -> exit 2" 2 "$STATUS"
A "$d" add 2026-10-14 x /polish audit:keel@a yes no m ev
check_status "add: a date after --as-of -> exit 2" 2 "$STATUS"
A "$d" add 2026-10-01 x /polish audit:keel@a yes no "" ev
check_status "add: an empty model -> exit 2" 2 "$STATUS"
A "$d" add 2026-10-01 x /polish audit:keel@a yes no m "e${TAB}v"
check_status "add: a TAB inside a field -> exit 2" 2 "$STATUS"
check_eq "add: no refusal wrote a sighting" 1 "$(nlines "$d/sightings.tsv")"
A "$d" add "$T" x /polish audit:keel@a yes no m ev
check_status "add: a sighting dated --as-of itself is accepted" 0 "$STATUS"
A "$d" count x
check_eq "count: the as-of day itself counts" 1 "$OUT"
A "$d" add "$T" x /polish audit:keel@a yes no m ev2 "another finding, same audit"
check_status "add: the same (class, source, consumer) again -> exit 0" 0 "$STATUS"
check_eq "add: ... and prints dup" "dup" "$OUT"
check_eq "add: ... and writes nothing" 2 "$(nlines "$d/sightings.tsv")"
A "$d" add "$T" x /go audit:keel@a yes no m ev
check_status "add: /go on the same source is a second row" 0 "$STATUS"
check_eq "add: two rows now" 3 "$(nlines "$d/sightings.tsv")"
A "$d" count x
check_eq "count: /go and /polish on one source count once" 1 "$OUT"
A "$d" add "$T" x /polish audit:keel@b yes no m ev
A "$d" count x
check_eq "count: a second distinct source -> 2" 2 "$OUT"
A "$d" add "$T" x /polish audit:keel@dash yes no m ev -- --starts-with-dashes
check_status "add: a note beginning with -- after a -- terminator is recorded" 0 "$STATUS"
check_contains "... verbatim" "$(tail -1 "$d/sightings.tsv")" "--starts-with-dashes"
A "$d" add "$T" x /polish audit:keel@help yes no m ev -- -h
check_status "add: -h after a -- terminator is a value, not --help" 0 "$STATUS"
check_eq "... and the row was written" "added" "$OUT"
check_contains "... with -h as the note" "$(tail -1 "$d/sightings.tsv")" "${TAB}-h"
A "$d" add "$T" x /polish audit:keel@extra yes no m ev note -h
check_status "add: one argument too many is an error, never a silent help" 2 "$STATUS"
A "$d" add "$T" x /polish audit:keel@typo yes no m --help
check_status "add: --help in a value slot (no --) is an error, never recorded as data" 2 "$STATUS"
check_eq "... and nothing was written" 0 "$(grep -c 'audit:keel@typo' "$d/sightings.tsv")"
A "$d" count nope
check_status "count: an unknown class -> exit 2" 2 "$STATUS"
want="$(printf '%s\tx\t/polish\taudit:keel@a\tyes\tno\tm\tev\t' "$T")"
check_eq "add: the row is date, class, consumer, source, felt, danger, model, evidence, note" "$want" "$(sed -n 2p "$d/sightings.tsv")"

# three legs of one audit are one source: the same row added three times is one row, one count
d="$(mk)"; cls "$d" x
for leg in S1 S2 S3; do A "$d" add 2026-10-01 x /polish audit:keel@v1..v2 yes no m "report-$leg.md:3"; done
check_eq "three legs of one audit -> one stored row" 2 "$(nlines "$d/sightings.tsv")"
A "$d" count x; check_eq "three legs of one audit -> count 1" 1 "$OUT"

# --- the window boundary (A13): 59 days counts, 60 does not --------------------------------------------------------------------
d="$(mk)"; cls "$d" x; cls "$d" y
sight "$d" 2026-08-15 x /polish audit:keel@a yes no       # 59 days before 2026-10-13
sight "$d" 2026-08-14 y /polish audit:keel@a yes no       # 60 days before
A "$d" count x; check_eq "window 60: a 59-day-old sighting counts" 1 "$OUT"
A "$d" count y; check_eq "window 60: a 60-day-old sighting does not" 0 "$OUT"
ASOF=2026-10-12 A "$d" count x; check_eq "--as-of moves the window: 58 days counts" 1 "$OUT"
ASOF=2026-10-14 A "$d" count x; check_eq "--as-of moves the window: 60 days does not" 0 "$OUT"
ASOF=2026-08-14 A "$d" count x; check_eq "--as-of before a sighting's date: the sighting is not counted" 0 "$OUT"
ASOF=2026-08-15 A "$d" count x; check_eq "--as-of equal to the sighting's date: counts" 1 "$OUT"
ASOF=2026-08-14 A "$d" add 2026-08-15 x /go audit:keel@z yes no m ev
check_status "add: a date after an earlier --as-of -> exit 2" 2 "$STATUS"

# the per-class window column is honoured (A13): window 90 keeps a 70-day-old sighting
d="$(mk)"; cls "$d" w90 commands "" 90; cls "$d" w60 commands
sight "$d" 2026-08-04 w90 /polish audit:keel@a yes no     # 70 days
sight "$d" 2026-08-04 w60 /polish audit:keel@a yes no
sight "$d" 2026-07-16 w90 /polish audit:keel@b yes no     # 89 days
sight "$d" 2026-07-15 w90 /polish audit:keel@c yes no     # 90 days: out
A "$d" count w90; check_eq "window 90: 70 and 89 days count, 90 does not" 2 "$OUT"
A "$d" count w60; check_eq "window blank -> 60: a 70-day-old sighting does not" 0 "$OUT"

# leap-year arithmetic: the day count spans 2028-02-29
d="$(mk)"; cls "$d" x
ASOF=2028-02-29 sight "$d" 2028-01-01 x /polish audit:keel@a yes no
ASOF=2028-02-29 A "$d" count x; check_eq "leap day: 59 days after 2028-01-01 counts" 1 "$OUT"
ASOF=2028-03-01 A "$d" count x; check_eq "leap day: 60 days after 2028-01-01 does not" 0 "$OUT"
ASOF=2028-03-01 sight "$d" 2028-01-02 x /go audit:keel@jan2 yes no
ASOF=2028-03-01 A "$d" count x; check_eq "leap year: 59 days from 2028-01-02 across Feb 29 counts (2028-01-01 is 60, out)" 1 "$OUT"
ASOF=2027-03-01 sight "$d" 2027-01-02 x /go audit:keel@jan2b yes no
ASOF=2027-03-01 A "$d" count x; check_eq "common year: 58 days from 2027-01-02 to 2027-03-01 counts" 1 "$OUT"
A "$d" new-class lp t f commands
ASOF=2028-02-29 A "$d" add 2028-02-29 lp /go audit:keel@l yes no m ev
check_status "add: 2028-02-29 is a real date" 0 "$STATUS"
ASOF=2027-03-01 A "$d" add 2027-02-29 lp /go audit:keel@m yes no m ev
check_status "add: 2027-02-29 is not" 2 "$STATUS"

# --- due: threshold, per-class threshold, owner filter ------------------------------------------------------------------------
d="$(mk)"; cls "$d" two; cls "$d" three commands 3; cls "$d" other guards
sight "$d" 2026-10-01 two /polish audit:keel@a yes no
sight "$d" 2026-10-01 three /polish audit:keel@a yes no
sight "$d" 2026-10-01 other guards session:u1 yes no
sight "$d" 2026-10-02 other guards session:u2 yes no
A "$d" due --owner commands
check_status "due: ok" 0 "$STATUS"
check_eq "due: one sighting is not due (default threshold 2)" "" "$OUT"
sight "$d" 2026-10-02 two /wrap session:u3 yes no
sight "$d" 2026-10-02 three /wrap session:u3 yes no
A "$d" due --owner commands
check_eq "due: two distinct sources are due at the default threshold; threshold 3 with 2 is not" "two" "$OUT"
A "$d" due --owner guards
check_eq "due --owner filters: another owner's due class is listed only for that owner" "other" "$OUT"
sight "$d" 2026-10-03 three /go audit:keel@d yes no
A "$d" due --owner commands
check_eq "due: per-class threshold 3 reached with three sources" "$(printf 'two\nthree')" "$OUT"
A "$d" due
check_status "due without --owner -> exit 2" 2 "$STATUS"
A "$d" due --owner commands --verbose
check_contains "due --verbose names the class, the count and the reason" "$OUT" "two${TAB}2${TAB}threshold"
# the same source twice (two findings of one audit) never reaches the threshold
d="$(mk)"; cls "$d" x
A "$d" add 2026-10-01 x /polish audit:keel@a yes no m ev1
A "$d" add 2026-10-01 x /polish audit:keel@a yes no m ev2
A "$d" due --owner commands
check_eq "due: two findings of one audit are one sighting, not due" "" "$OUT"
# the window is part of due: a sighting that aged out no longer helps
d="$(mk)"; cls "$d" x
sight "$d" 2026-08-14 x /polish audit:keel@a yes no
sight "$d" 2026-10-01 x /polish audit:keel@b yes no
A "$d" due --owner commands; check_eq "due: a 60-day-old sighting plus one fresh is not due" "" "$OUT"
sight "$d" 2026-08-15 x /polish audit:keel@c yes no
A "$d" due --owner commands; check_eq "due: a 59-day-old sighting plus one fresh is due" "x" "$OUT"

# --- counts felt (dir #842's choice) -----------------------------------------------------------------------------------------
d="$(mk)"; cls "$d" g:slug guards 2 90 felt; cls "$d" plain guards 2 90
sight "$d" 2026-10-01 g:slug guards session:u1 yes no
sight "$d" 2026-10-02 g:slug guards audit:keel@a no no      # an audit: not felt
sight "$d" 2026-10-01 plain guards session:u1 yes no
sight "$d" 2026-10-02 plain guards audit:keel@a no no
A "$d" count g:slug; check_eq "counts felt: an unfelt sighting is not counted" 1 "$OUT"
A "$d" count plain;  check_eq "counts blank: every distinct source counts" 2 "$OUT"
A "$d" due --owner guards; check_eq "counts felt: not due on one felt + one unfelt; the unfiltered class is" "plain" "$OUT"
sight "$d" 2026-10-03 g:slug guards session:u2 yes no
A "$d" due --owner guards; check_eq "counts felt: a second felt source makes it due" "$(printf 'g:slug\nplain')" "$OUT"

# --- danger: due at once, only with felt yes ---------------------------------------------------------------------------------------
d="$(mk)"; cls "$d" felt-danger; cls "$d" sandbox-danger; cls "$d" quiet
sight "$d" 2026-10-01 felt-danger /wrap session:u1 yes yes
sight "$d" 2026-10-01 sandbox-danger /polish audit:keel@a no yes
sight "$d" 2026-10-01 quiet /wrap session:u1 yes no
A "$d" due --owner commands
check_eq "danger: felt + danger is due on the first sighting; unfelt danger and a plain felt one are not" "felt-danger" "$OUT"
A "$d" due --owner commands --verbose
check_contains "danger: --verbose names the reason" "$OUT" "felt-danger${TAB}1${TAB}danger"
# a felt danger that aged out is no longer due
d="$(mk)"; cls "$d" x
sight "$d" 2026-08-14 x /wrap session:u1 yes yes
A "$d" due --owner commands; check_eq "danger: a 60-day-old felt danger is not due" "" "$OUT"

# --- retire: only a quiet open class -----------------------------------------------------------------------------------------------
d="$(mk)"; cls "$d" quiet; cls "$d" live; cls "$d" prom; cls "$d" fix
sight "$d" 2026-10-01 live /polish audit:keel@a yes no
sight "$d" 2026-08-01 prom /polish audit:keel@a yes no
sight "$d" 2026-08-01 prom /polish audit:keel@b yes no
A "$d" promote prom draft:observer-prom.md
sight "$d" 2026-08-01 fix /polish audit:keel@a yes no
sight "$d" 2026-08-01 fix /polish audit:keel@b yes no
A "$d" promote fix 123
A "$d" fixed fix 123 --date 2026-08-20
A "$d" retire
check_status "retire: ok" 0 "$STATUS"
check_eq "retire: prints the retired class ids" "quiet" "$OUT"
check_eq "retire: a quiet open class -> retired:<as-of>" "retired:$T" "$(status_of "$d" quiet)"
check_eq "retire: an open class with a counting sighting stays open" "open" "$(status_of "$d" live)"
case "$(status_of "$d" prom)" in promoted:*) pass "retire: never touches a promoted class (count 0)" ;; *) fail "retire: never touches a promoted class (count 0)" "status is $(status_of "$d" prom)" ;; esac
case "$(status_of "$d" fix)" in fixed:*) pass "retire: never touches a fixed class (count 0)" ;; *) fail "retire: never touches a fixed class (count 0)" "status is $(status_of "$d" fix)" ;; esac
A "$d" due --owner commands; check_eq "a retired class is never due" "" "$OUT"
A "$d" add "$T" quiet /go session:u9 yes no m ev
check_eq "add: a new sighting reopens a retired class" "open" "$(status_of "$d" quiet)"
A "$d" retire; check_eq "retire: the reopened class has a counting sighting, stays open" "" "$OUT"
A "$d" lint; check_status "lint: statuses written by promote / fixed / retire are valid" 0 "$STATUS"

# --- promote: never due again, "seen again while open" -----------------------------------------------------------------------------
d="$(mk)"; cls "$d" x
sight "$d" 2026-10-01 x /polish audit:keel@a yes no
sight "$d" 2026-10-02 x /polish audit:keel@b yes no
A "$d" due --owner commands; check_eq "before promote: due" "x" "$OUT"
A "$d" promote x draft:observer-x-2026-10-13.md
check_status "promote: ok" 0 "$STATUS"
check_eq "promote: status is promoted:<ref>:<as-of>" "promoted:draft:observer-x-2026-10-13.md:$T" "$(status_of "$d" x)"
A "$d" due --owner commands; check_eq "a promoted class is never due" "" "$OUT"
A "$d" promote x 99; check_status "promote: a class already promoted -> exit 2" 2 "$STATUS"
A "$d" promote nope 99; check_status "promote: an unknown class -> exit 2" 2 "$STATUS"
A "$d" status --owner commands
check_contains "status: nothing seen again yet" "$OUT" "promoted-seen-again=0"
A "$d" add "$T" x /go audit:keel@same-day yes no m ev
A "$d" status --owner commands
check_contains "status: a sighting dated the promotion day is not 'after' it" "$OUT" "promoted-seen-again=0"
ASOF=2026-10-14 A "$d" add 2026-10-14 x /go audit:keel@c yes no m ev
ASOF=2026-10-14 A "$d" due --owner commands
check_eq "a promoted class with a new sighting is still not due" "" "$OUT"
ASOF=2026-10-14 A "$d" status --owner commands
check_contains "status: a new sighting after the promotion -> seen again" "$OUT" "promoted-seen-again=1"
ASOF=2026-10-14 A "$d" retire
check_eq "retire: a promoted class is not retired even at count > 0" "" "$OUT"

# --- fixed: recurrence counts from the closure date ---------------------------------------------------------------------------------
d="$(mk)"; cls "$d" x
sight "$d" 2026-09-20 x /polish audit:keel@a yes no
sight "$d" 2026-09-25 x /polish audit:keel@b yes no
A "$d" fixed x 123 --date 2026-10-01
check_status "fixed: on an open class -> exit 2" 2 "$STATUS"
A "$d" promote x 123
A "$d" fixed x 123 --date 2026-10-14
check_status "fixed: a date after --as-of -> exit 2" 2 "$STATUS"
A "$d" fixed x 123 --date 2026-10-01
check_status "fixed --date: ok" 0 "$STATUS"
check_eq "fixed: status is fixed:<ref>:<closure date>" "fixed:123:2026-10-01" "$(status_of "$d" x)"
A "$d" count x; check_eq "fixed: the two sightings before the closure no longer count" 0 "$OUT"
A "$d" due --owner commands; check_eq "fixed: not due on the old sightings" "" "$OUT"
sight "$d" 2026-10-01 x /polish audit:keel@c yes no        # dated ON the closure date
A "$d" count x; check_eq "fixed: a sighting dated on the closure day is not after it" 0 "$OUT"
sight "$d" 2026-10-05 x /polish audit:keel@d yes no
A "$d" due --owner commands; check_eq "fixed: one sighting after the closure is not due" "" "$OUT"
sight "$d" 2026-10-08 x /go audit:keel@e yes no
A "$d" due --owner commands; check_eq "fixed: two sightings after the closure -> due again" "x" "$OUT"
A "$d" count x; check_eq "fixed: the count is the post-closure distinct sources" 2 "$OUT"
A "$d" promote x 456
check_eq "a recurring class can be promoted again" "promoted:456:$T" "$(status_of "$d" x)"
A "$d" fixed x 456
check_eq "fixed with no --date takes the as-of day" "fixed:456:$T" "$(status_of "$d" x)"
A "$d" lint; check_status "lint: a ticket-id ref and a draft: ref both lint clean" 0 "$STATUS"

# --- status: the report's numbers ------------------------------------------------------------------------------------------------------
d="$(mk)"; cls "$d" a; cls "$d" b commands 3; cls "$d" c; cls "$d" g guards
sight "$d" 2026-10-01 a /polish audit:keel@a yes no        # count 1 at threshold 2: at threshold-1
sight "$d" 2026-10-01 b /polish audit:keel@a yes no
sight "$d" 2026-10-02 b /polish audit:keel@b yes no        # count 2 at threshold 3: at threshold-1
cls "$d" retiring
A "$d" retire
A "$d" status --owner commands
check_status "status: ok" 0 "$STATUS"
check_eq "status: open watched classes, classes at threshold-1, retired at the as-of day, promoted seen again" \
  "open=2 at-threshold-1=2 retired-at-D=2 promoted-seen-again=0" "$OUT"
A "$d" status
check_status "status without --owner -> exit 2" 2 "$STATUS"

# --- closed: three heading forms, a draft, an orphan -------------------------------------------------------------------------------------------
d="$(mk)"
for c in glued-body unfinished-wrap span-only-line log-opener two-parens tie tie-rev wrapped-date pr-number later-date bad-date dash-wrap glyph-date paren-next-line by-construction glued-paren open-one kb-closed b-superseded wrapped foreign-citation body-closed-word recurred drafted nowhere fenced-only midline-only parked-one odd-word two-closed two-closed-rev glued; do cls "$d" "$c"; done
bl="$SANDBOX/bl.md"
cat > "$bl" <<'EOF'
# Backlog

### dir #5 — an open keel ticket — R2

Observer-class: open-one

### KB.7 — a KB ticket closed with a dated tag — ✅ CLOSED (2026-10-01)

Observer-class: kb-closed

### B.3 — a B ticket that was dropped — ❌ SUPERSEDED

Observer-class: b-superseded

### dir #8 — a wrapped heading whose closure
sits on the continuation line — ✅ DONE (2026-09-30)

Observer-class: wrapped

### dir #9 — an open ticket quoting a sibling — R2 — see also Supersedes dir #3 — ✅ CLOSED

Observer-class: foreign-citation

### H.2 — a heading with only the word closed in prose — R2

closed ✅ CLOSED later, in the body. Observer-class: mid-line is not a tag line.

Observer-class: body-closed-word

### dir #60 — first of two closed tickets, no date — ❌ SUPERSEDED

Observer-class: two-closed

### dir #61 — second of two closed tickets, dated — ✅ CLOSED (2026-10-01)

Observer-class: two-closed

### dir #62 — dated first — ✅ CLOSED (2026-10-02)

Observer-class: two-closed-rev

### dir #63 — undated second — ❌ SUPERSEDED

Observer-class: two-closed-rev

### dir #64 — a date glued to the closure word — ✅ FIXED2026-10-05

Observer-class: glued

### dir #65 — same date, superseded — ❌ SUPERSEDED (2026-10-01)

Observer-class: tie

### dir #66 — same date, a real closure — ✅ CLOSED (2026-10-01)

Observer-class: tie

### dir #68 — same date, a real closure first — ✅ CLOSED (2026-10-01)

Observer-class: tie-rev

### dir #69 — same date, superseded second — ❌ SUPERSEDED (2026-10-01)

Observer-class: tie-rev

### dir #70 — an undated closure with a later date on its wrapped line — ✅ CLOSED (see PR)
Opened 2025-03-04 elsewhere

Observer-class: wrapped-date

### dir #71 — words between the tag and the date — ✅ FIXED in PR #345 (2026-10-01)

Observer-class: pr-number

### dir #72 — a later unrelated date on the line — ✅ SUPERSEDED by dir #12, opened 2025-01-01

Observer-class: later-date

### dir #73 — an impossible date — ✅ CLOSED (2026-13-45)

Observer-class: bad-date

### dir #75 — the supersede tag has no date, a later wrapped tag does — ❌ SUPERSEDED by dir #9
✅ DONE (2026-10-04)

Observer-class: glyph-date

### dir #80 — a finished open heading with a body line glued under it — R3 — → pool
✅ DONE for the first half of the work (a body line, written with no blank line before it)

Observer-class: glued-body

### dir #81 — a title still unfinished when it wraps
sits on the next line and closes there — ✅ DONE (2026-10-02)

Observer-class: unfinished-wrap

### dir #82 — an unfinished title, then a line that is only a code span
`dir #5`
sits here and closes — ✅ DONE (2026-10-03)

Observer-class: span-only-line

### dir #83 — an unfinished title, then a Log opener
Log: 2026-10-01 — ✅ DONE is only a note in the body

Observer-class: log-opener

### dir #79 — a first parenthesis that is not a date — ✅ CLOSED (see dir #9) (2026-10-07)

Observer-class: two-parens

### dir #76 — the tag ends one line, the parenthesis starts the next — ✅ FIXED
(2026-10-04) see below

Observer-class: paren-next-line

### dir #77 — a longer closure phrase — ✅ CLOSED BY CONSTRUCTION (2026-09-30, see the PR)

Observer-class: by-construction

### dir #78 — no space before the parenthesis — ✅ FIXED(2026-10-06)

Observer-class: glued-paren

### dir #74 — a heading that wraps right after the dash —
✅ FIXED (2026-10-04)

Observer-class: dash-wrap

### dir #14 — an unrelated closed ticket — ✅ CLOSED (2026-01-01)

See Observer-class: midline-only for context; the tag must start its own line.

### dir #11 — a recurred class: the old ticket is closed, the new one open — ✅ FIXED (2026-08-01)

Observer-class: recurred

### dir #12 — the recurrence ticket — R2

Observer-class: recurred

Example in a fence is not a tag:

```
### dir #13 — ✅ CLOSED
Observer-class: fenced-only
```
EOF
dr="$SANDBOX/drafts"; mkdir -p "$dr"
printf 'target: new\n### observer: a title — 2 sightings in 60 days (2026-10-13)\n\nObserver-class: drafted\nThe fix line.\n' > "$dr/observer-drafted-2026-10-13.md"
A "$d" closed open-one --backlog "$bl" --drafts "$dr";       check_eq "closed: a ### dir #N heading, open" "open" "$OUT"
A "$d" closed kb-closed --backlog "$bl" --drafts "$dr";      check_eq "closed: ### KB.N, ✅ CLOSED (date) -> the date is parsed" "closed ✅ 2026-10-01" "$OUT"
A "$d" closed b-superseded --backlog "$bl" --drafts "$dr";   check_eq "closed: ### B.N, ❌ SUPERSEDED -> closed, no date" "closed ❌ —" "$OUT"
A "$d" closed wrapped --backlog "$bl" --drafts "$dr";        check_eq "closed: a wrapped heading's tag on the continuation line" "closed ✅ 2026-09-30" "$OUT"
A "$d" closed foreign-citation --backlog "$bl" --drafts "$dr"; check_eq "closed: a foreign ticket's citation in the heading is not this ticket's closure" "open" "$OUT"
A "$d" closed body-closed-word --backlog "$bl" --drafts "$dr"; check_eq "closed: a closure word in the body is not the heading's" "open" "$OUT"
A "$d" closed recurred --backlog "$bl" --drafts "$dr";       check_eq "closed: the old closed ticket and a new open one -> open" "open" "$OUT"
A "$d" closed drafted --backlog "$bl" --drafts "$dr";        check_eq "closed: a draft-only promotion -> draft" "draft" "$OUT"
A "$d" closed midline-only --backlog "$bl" --drafts "$dr";   check_eq "closed: a tag mentioned mid-line is not a tag line" "orphaned" "$OUT"
A "$d" closed two-closed --backlog "$bl" --drafts "$dr";     check_eq "closed: several closed tickets -> the dated one wins over an undated one" "closed ✅ 2026-10-01" "$OUT"
A "$d" closed two-closed-rev --backlog "$bl" --drafts "$dr";  check_eq "closed: ... in either file order" "closed ✅ 2026-10-02" "$OUT"
A "$d" closed tie --backlog "$bl" --drafts "$dr";             check_eq "closed: equal dates -> a real closure beats a supersede, whichever file order" "closed ✅ 2026-10-01" "$OUT"
A "$d" closed tie-rev --backlog "$bl" --drafts "$dr";         check_eq "closed: ... and with the real closure first" "closed ✅ 2026-10-01" "$OUT"
A "$d" closed wrapped-date --backlog "$bl" --drafts "$dr";    check_eq "closed: a date on a wrapped continuation line is not the closure date" "closed ✅ —" "$OUT"
A "$d" closed pr-number --backlog "$bl" --drafts "$dr";       check_eq "closed: words between the tag and the parenthesised date are fine" "closed ✅ 2026-10-01" "$OUT"
A "$d" closed by-construction --backlog "$bl" --drafts "$dr"; check_eq "closed: ✅ CLOSED BY CONSTRUCTION (date …) reads its date" "closed ✅ 2026-09-30" "$OUT"
A "$d" closed glued-paren --backlog "$bl" --drafts "$dr";     check_eq "closed: a parenthesis glued to the tag still opens the date" "closed ✅ 2026-10-06" "$OUT"
A "$d" closed glyph-date --backlog "$bl" --drafts "$dr";      check_eq "closed: the glyph and the date come from the same tag (a later tag's date is not borrowed)" "closed ❌ —" "$OUT"
A "$d" closed glued-body --backlog "$bl" --drafts "$dr";      check_eq "closed: a glued body line with a closure tag under a FINISHED open heading stays OPEN (dir #847)" "open" "$OUT"
A "$d" closed unfinished-wrap --backlog "$bl" --drafts "$dr"; check_eq "closed: an unfinished title still takes its wrapped continuation (dir #255 shape)" "closed ✅ 2026-10-02" "$OUT"
A "$d" closed span-only-line --backlog "$bl" --drafts "$dr";  check_eq "closed: a line that is only a code span ends the block, as in the census" "open" "$OUT"
A "$d" closed log-opener --backlog "$bl" --drafts "$dr";      check_eq "closed: a Log: line is never part of the heading block" "open" "$OUT"
A "$d" closed two-parens --backlog "$bl" --drafts "$dr";      check_eq "closed: a first parenthesis that does not open a date -> undated" "closed ✅ —" "$OUT"
A "$d" closed paren-next-line --backlog "$bl" --drafts "$dr"; check_eq "closed: a parenthesis on the next line is not the tag's date" "closed ✅ —" "$OUT"
A "$d" closed later-date --backlog "$bl" --drafts "$dr";      check_eq "closed: a later unrelated date on the line is not the closure date" "closed ✅ —" "$OUT"
A "$d" closed bad-date --backlog "$bl" --drafts "$dr";        check_eq "closed: an impossible date is undated" "closed ✅ —" "$OUT"
A "$d" closed dash-wrap --backlog "$bl" --drafts "$dr";       check_eq "closed: a heading wrapped right after the dash keeps its date" "closed ✅ 2026-10-04" "$OUT"
A "$d" closed glued --backlog "$bl" --drafts "$dr";           check_eq "closed: a date glued to the closure word, with no parenthesis, is undated" "closed ✅ —" "$OUT"
A "$d" closed not-in-the-registry --backlog "$bl" --drafts "$dr"; check_status "closed: a class that is not in the registry -> exit 2, not 'orphaned'" 2 "$STATUS"
A "$d" closed nowhere --backlog "$bl" --drafts "$dr";        check_eq "closed: a tag in no backlog and no draft -> orphaned" "orphaned" "$OUT"
A "$d" closed fenced-only --backlog "$bl" --drafts "$dr";    check_eq "closed: a tag line inside a code fence does not count" "orphaned" "$OUT"
parked="$SANDBOX/parked.md"
printf '### dir #40 — a parked open ticket\n\nObserver-class: parked-one\n' > "$parked"
A "$d" closed parked-one --backlog "$bl" "$parked" --drafts "$dr"
check_eq "closed: several --backlog files are all searched" "open" "$OUT"
A "$d" closed open-one --backlog "$SANDBOX/no-such-backlog.md" --drafts "$dr"
check_status "closed: a missing backlog file -> exit 2" 2 "$STATUS"
A "$d" closed open-one --backlog "$bl" --drafts "$SANDBOX/no-such-drafts"
check_status "closed: a missing drafts dir is empty, not an error" 0 "$STATUS"
A "$d" closed open-one
check_status "closed without --backlog -> exit 2" 2 "$STATUS"
# the closure vocabulary is the shared one: a word outside it is not a closure
printf '### dir #50 — shipped but with an unlisted word — ✅ SHIPPEDX\n\nObserver-class: odd-word\n' > "$SANDBOX/odd.md"
A "$d" closed odd-word --backlog "$SANDBOX/odd.md"
check_eq "closed: a closure word outside BB_CLOSURE_TAG_PATTERN stays open" "open" "$OUT"

# --- verdict ----------------------------------------------------------------------------------------------------------------------------------
d="$(mk)"; cls "$d" p-due; cls "$d" p-prom; cls "$d" p-closed; cls "$d" w-due; cls "$d" p-quiet
bl="$SANDBOX/vbl.md"
printf '### dir #1 — open promoted ticket\n\nObserver-class: p-prom\n\n### dir #2 — closed promoted ticket — ✅ CLOSED (2026-10-10)\n\nObserver-class: p-closed\n' > "$bl"
dr="$SANDBOX/vdrafts"; mkdir -p "$dr"
sight "$d" 2026-10-01 p-due /polish audit:keel@a yes no
sight "$d" 2026-10-02 p-due /polish audit:keel@b yes no
sight "$d" 2026-10-01 p-prom /polish audit:keel@a yes no
sight "$d" 2026-10-01 p-closed /polish audit:keel@a yes no
sight "$d" 2026-10-01 w-due /wrap session:u1 yes yes
sight "$d" 2026-10-01 p-quiet /polish audit:keel@a yes no
A "$d" promote p-prom 1; A "$d" promote p-closed 2
A "$d" verdict --consumer /polish --backlog "$bl" --drafts "$dr"
check_status "verdict: ok" 0 "$STATUS"
check_eq "verdict: due and promoted-not-closed classes of the consumer; a closed promotion and a quiet class are not listed" "NEEDS-REWORK p-due p-prom" "$OUT"
A "$d" verdict --consumer /wrap --backlog "$bl" --drafts "$dr"
check_eq "verdict: another consumer sees only its own classes" "NEEDS-REWORK w-due" "$OUT"
A "$d" verdict --consumer /go --backlog "$bl" --drafts "$dr"
check_eq "verdict: a consumer with no counting sighting -> CLEAR" "CLEAR" "$OUT"
A "$d" promote p-due draft:gone.md; A "$d" promote w-due 77
A "$d" verdict --consumer /polish --backlog "$bl" --drafts "$dr"
check_eq "verdict: a promotion found nowhere is orphaned and counts as open" "NEEDS-REWORK p-due p-prom" "$OUT"
A "$d" verdict --consumer /polish
check_status "verdict without --backlog -> exit 2" 2 "$STATUS"
A "$d" verdict --backlog "$bl"
check_status "verdict without --consumer -> exit 2" 2 "$STATUS"

# --- lock --------------------------------------------------------------------------------------------------------------------------------------
d="$(mk)"
A "$d" lock;  check_status "lock: first take -> exit 0" 0 "$STATUS"
A "$d" lock;  check_status "lock: a live lock -> exit 2" 2 "$STATUS"
check_contains "lock: the refusal says who holds it" "$OUT" "held"
cls "$d" x
A "$d" new-class held-write t f commands
check_status "a write while the caller holds the lock proceeds" 0 "$STATUS"
A "$d" unlock; check_status "unlock: ok" 0 "$STATUS"
A "$d" lock;  check_status "lock: free again after unlock" 0 "$STATUS"
A "$d" unlock
A "$d" unlock; check_status "unlock: with no lock is still exit 0" 0 "$STATUS"
A "$d" new-class self-locked t f commands
check_absent "a write that took its own lock released it" "$(ls -a "$d")" ".lock"
# a lock older than two hours is broken, and the break is said
now="$(date +%s)"
mkdir "$d/.lock"; printf '4242\t%s\n' "$((now - 7300))" > "$d/.lock/info"
A "$d" lock
check_status "lock: one older than 2 hours is broken -> exit 0" 0 "$STATUS"
check_contains "lock: ... and the report line says it broke a stale lock" "$OUT" "stale"
A "$d" unlock
mkdir "$d/.lock"; printf '4242\t%s\n' "$((now - 3600))" > "$d/.lock/info"
A "$d" lock
check_status "lock: one an hour old is still live -> exit 2" 2 "$STATUS"
rm -f "$d/.lock/info"; rmdir "$d/.lock" 2>/dev/null

# --- lint: header, tabs, shapes, and the six broken copies of A3 ----------------------------------------------------------------------------------
base="$(mk)"; cls "$base" x; cls "$base" y commands 3 90 felt
sight "$base" 2026-10-01 x /polish audit:keel@a yes no
sight "$base" 2026-10-02 y /go session:u1 yes yes
A "$base" lint; check_status "lint: a populated clean dir passes" 0 "$STATUS"
broken() {   # broken LABEL FILE AWK-PROGRAM-OR-SED — copy BASE, damage FILE, expect lint exit 1 naming the problem
  local label="$1" file="$2" prog="$3" want="$4" b
  b="$(mktemp -d "$SANDBOX/acc.XXXXXX")"; cp "$base/classes.tsv" "$base/sightings.tsv" "$b/"
  awk -F'\t' -v OFS='\t' "$prog" "$b/$file" > "$b/$file.new" && mv "$b/$file.new" "$b/$file"
  A "$b" lint
  check_status "lint: $label -> exit 1" 1 "$STATUS"
  check_contains "lint: $label is named" "$OUT" "$want"
}
broken "a sighting of an unknown class" sightings.tsv 'NR == 2 { $2 = "ghost" } { print }' "unknown class"
broken "a duplicate (class, source, consumer)" sightings.tsv 'NR == 2 { r = $0 } { print } END { print r }' "duplicate"
broken "felt = maybe" sightings.tsv 'NR == 2 { $5 = "maybe" } { print }' "felt"
broken "a date 2026-13-01" sightings.tsv 'NR == 2 { $1 = "2026-13-01" } { print }' "date"
broken "a status done" classes.tsv 'NR == 2 { $6 = "done" } { print }' "status"
broken "a missing owner" classes.tsv 'NR == 2 { $4 = "" } { print }' "owner"
broken "a wrong header" classes.tsv 'NR == 1 { $2 = "name" } { print }' "header"
broken "a short row" sightings.tsv 'NR == 2 { print $1, $2, $3; next } { print }' "fields"
broken "a duplicate class id" classes.tsv 'NR == 2 { r = $0 } { print } END { print r }' "duplicate"
broken "a fixed status without a date" classes.tsv 'NR == 2 { $6 = "fixed:123" } { print }' "status"
broken "a window of 0" classes.tsv 'NR == 3 { $8 = "0" } { print }' "window"
broken "counts other than felt" classes.tsv 'NR == 3 { $9 = "some" } { print }' "counts"
broken "an empty evidence" sightings.tsv 'NR == 2 { $8 = "" } { print }' "evidence"
broken "danger = perhaps" sightings.tsv 'NR == 3 { $6 = "perhaps" } { print }' "danger"
broken "an id outside the allowed characters" classes.tsv 'NR == 2 { $1 = "Bad_Id" } { print }' "class"
# a status written for a ref that contains colons (draft:<file>) must lint clean
okd="$(mk)"; cls "$okd" x; A "$okd" promote x draft:observer-x-2026-10-13.md
A "$okd" lint; check_status "lint: promoted:draft:<file>:<date> is a valid status" 0 "$STATUS"

# --- selftest -------------------------------------------------------------------------------------------------------------------------------------
run bash "$ACC" --selftest
check_status "--selftest -> exit 0" 0 "$STATUS"
check_contains "--selftest says ok" "$OUT" "selftest ok"

summary
