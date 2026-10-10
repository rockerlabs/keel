#!/usr/bin/env bash
# doctor H-FOOTPRINT (dir #686, dir #687): the figure sums the harness's MEMORY.md index next to the
# project and global CLAUDE.md (it loads every session), the default budget is 16000 tokens (the old 10000
# plus ~6000 for the index, keel's own measuring 5.8k), and a live `## Footprint exceptions` row
# in the project's CLAUDE.md silences the hint until its expiry while an EXPIRED row is flagged. Own file,
# not an extension of test_doctor.sh: that file's tail is where every other doctor PR appends.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doctor="$REPO_ROOT/tools/doctor.sh"
ghome="$SANDBOX/fp-ghome"; mkdir -p "$ghome"          # an empty global home: global ~0
today="$(date +%Y-%m-%d)"

# fproj BYTES — a clean project whose CLAUDE.md is BYTES long (4 bytes = 1 token); prints its path
fproj() {
  local d; d="$(new_repo)"
  head -c "$1" /dev/zero | tr '\0' 'P' > "$d/CLAUDE.md"; printf '\n' >> "$d/CLAUDE.md"
  printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
  printf '%s' "$d"
}
# fmem BYTES — a memory dir whose MEMORY.md is BYTES long; prints its path
fmem() {
  local m; m="$(mktemp -d "$SANDBOX/fpmem.XXXXXX")"
  head -c "$1" /dev/zero | tr '\0' 'M' > "$m/MEMORY.md"
  printf '%s' "$m"
}
frun() { local m="$1" p="$2"; shift 2; run env "KEEL_MEMORY_DIR=$m" "KEEL_HOME=$ghome" "$@" "$doctor" "$p"; }

# --- dir #686: MEMORY.md is summed and named -------------------------------------------------------
d="$(fproj 400)"; m="$(fmem 800)"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "the memory figure is named in the footprint hint" "$OUT" "memory ~200"
check_contains "the total includes the index (100 project + 0 global + 200 memory)" "$OUT" "~300 tokens"

# the index is what tips an otherwise-under-budget project over
d="$(fproj 400)"; m="$(fmem 4000)"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=500
check_contains "project alone under budget, the index tips it over" "$OUT" "[H-FOOTPRINT]"
frun "$(fmem 40)" "$d" KEEL_STARTUP_WARN_TOKENS=500
check_absent "a small index leaves the same project under budget" "$OUT" "[H-FOOTPRINT]"

# no memory dir at all → memory ~0, never a crash
d="$(fproj 400)"
run env "KEEL_MEMORY_DIR=$SANDBOX/no-such-mem" "KEEL_HOME=$ghome" KEEL_STARTUP_WARN_TOKENS=1 "$doctor" "$d"
check_contains "an absent memory dir contributes 0" "$OUT" "memory ~0"

# the default budget: 16000 tokens (64000 bytes) fires above, not below
d="$(fproj 60000)"; m="$(fmem 3000)"          # 15000 + 750 = 15750 ≤ 16000
frun "$m" "$d"
check_absent "15750 tokens is under the 16000 default" "$OUT" "[H-FOOTPRINT]"
d="$(fproj 60000)"; m="$(fmem 6000)"          # 15000 + 1500 = 16500 > 16000
frun "$m" "$d"
check_contains "16500 tokens is over the 16000 default" "$OUT" "[H-FOOTPRINT]"
check_contains "the hint states the 16000 budget" "$OUT" "budget 16000"

# --- dir #687: the Footprint exceptions row -------------------------------------------------------
exc() { # exc PROJECT DATE NOTE — append a one-row exceptions section to the project's CLAUDE.md
  printf '\n## Footprint exceptions\n\n| Expires (YYYY-MM-DD) | Ticket/note |\n|---|---|\n| %s | %s |\n' "$2" "$3" >> "$1/CLAUDE.md"
}
d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "2099-12-31" "dir #999 trim planned"  # a fixed far-future date: always live, and no date arithmetic (busybox date has neither -v nor -d '+30 days')
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_absent "a live exception row silences the hint" "$OUT" "[H-FOOTPRINT]"
check_contains "a live exception is still said, with its note" "$OUT" "acknowledged until"
check_contains "the note rides along" "$OUT" "dir #999 trim planned"
check_status "a live exception exits 0" 0 "$STATUS"

d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "$today" "expires today"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_absent "a row dated today is still live (inclusive)" "$OUT" "[H-FOOTPRINT]"

d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "2020-01-01" "old decision"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "an expired row still hints" "$OUT" "HINT [H-FOOTPRINT]"
check_contains "an expired row is flagged EXPIRED" "$OUT" "EXPIRED 2020-01-01"
check_status "an expired exception still exits 0" 0 "$STATUS"

d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "never" "bad date"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "a malformed date never counts as live" "$OUT" "HINT [H-FOOTPRINT]"

# the LAST row wins (a renewal supersedes an old row without deleting it)
d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "2020-01-01" "old"
printf '| 2099-12-31 | renewed |\n' >> "$d/CLAUDE.md"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_absent "the last row wins: a later live row supersedes an expired one" "$OUT" "[H-FOOTPRINT]"

# the section closes on the next heading: a later table is not a row
d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "2020-01-01" "old"
printf '\n## Other\n\n| 2099-12-31 | not an exception |\n' >> "$d/CLAUDE.md"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "a table under another heading is not an exception row" "$OUT" "EXPIRED 2020-01-01"

# an exception on a project under budget says nothing
d="$(fproj 400)"; m="$(fmem 40)"; exc "$d" "2020-01-01" "stale but moot"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=100000
check_absent "an expired row under budget is moot, not flagged" "$OUT" "EXPIRED"

# a malformed date is named as such (not silently the same hint as no row)
d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "never" "bad date"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "a malformed-date row is named, not ignored silently" "$OUT" "no valid YYYY-MM-DD date"
# a calendar-invalid date never counts as live
d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "9999-99-99" "impossible"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "9999-99-99 is not a live date" "$OUT" "no valid YYYY-MM-DD date"
# CRLF line endings leave no \r on the note; the heading must match exactly
d="$(fproj 400)"; m="$(fmem 800)"
printf '\r\n## Footprint exceptions\r\n\r\n| Expires | Note |\r\n|---|---|\r\n| 2020-01-01 | crlf note |\r\n' >> "$d/CLAUDE.md"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "a CRLF CLAUDE.md row still parses" "$OUT" "EXPIRED 2020-01-01 (crlf note)"
d="$(fproj 400)"; m="$(fmem 800)"
printf '\n## Footprint exceptions-old\n\n| 2099-12-31 | not this heading |\n' >> "$d/CLAUDE.md"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "a longer heading does not open the section" "$OUT" "HINT [H-FOOTPRINT]"

# regex boundaries: each impossible month/day is rejected; a suffixed heading still opens the section
for bad in 2026-13-01 2026-00-10 2026-01-32 2026-01-00; do
  d="$(fproj 400)"; m="$(fmem 800)"; exc "$d" "$bad" "boundary"
  frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
  check_contains "$bad is not a valid date" "$OUT" "no valid YYYY-MM-DD date"
done
d="$(fproj 400)"; m="$(fmem 800)"
printf '\n## Footprint exceptions (until the split)\n\n| 2020-01-01 | suffixed |\n' >> "$d/CLAUDE.md"
frun "$m" "$d" KEEL_STARTUP_WARN_TOKENS=1
check_contains "a suffixed heading still opens the section" "$OUT" "EXPIRED 2020-01-01"

summary
