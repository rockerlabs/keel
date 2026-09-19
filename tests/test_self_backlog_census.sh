#!/usr/bin/env bash
# tools/self/backlog-census.sh: --help/bad-args, the no-BACKLOG.md skip, the last-arrow tag
# extraction (pool/next/on-demand/N.N[.N] vocabulary only — a prose arrow, a closure note's own
# trailing arrow, a wrapped heading, a RE-SCOPED-but-open heading, a legacy heading, and a grade
# re-tag arrow are docs/grooming.md G3's own four extraction rules plus the re-grade shape this
# tool's own header names as excluded by construction), `untagged`, and `--list TAG` file order.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

bc="$REPO_ROOT/tools/self/backlog-census.sh"

# --- --help / bad args -----------------------------------------------------------------------
run "$bc" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$bc" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$bc" --list
check_status "--list with no tag -> exit 2" 2 "$STATUS"

# --- no BACKLOG.md -> silent skip, exit 0 -----------------------------------------------------
run "$bc" "$SANDBOX/no-such-backlog.md"
check_status "missing BACKLOG.md -> exit 0 (skip, not an error)" 0 "$STATUS"
check_contains "prints a skip line" "$OUT" "no readable BACKLOG.md"
run "$bc" "/no/such/dir/BACKLOG.md"
check_status "nonexistent BACKLOG_PATH directory -> exit 0 (advisory skip, not a crash)" 0 "$STATUS"
check_absent "no raw 'No such file or directory' stderr leaks through" "$OUT" "No such file or directory"

# --- fixture builder ----------------------------------------------------------------------------
mk_backlog() {
  local d f
  d="$(mktemp -d "$SANDBOX/bl.XXXXXX")"
  f="$d/BACKLOG.md"
  printf '%s' "$1" > "$f"
  printf '%s' "$f"
}

# --- the six shapes docs/grooming.md's G3 names, one census run --------------------------------
# dir #1: a plain, current tag.
# dir #2: a prose arrow inside the body ("→ ask") that must NOT be read as a tag — the real tag
#   is the wrapped heading's own continuation-line arrow (dir #255's wrapped-heading shape).
# dir #3: a closure note ending in its OWN arrow ("→ 10,884 lines") — must not count at all, the
#   ticket is closed.
# dir #4: RE-SCOPED but still open — a status word, not a closure marker; must still count.
# ### 5. a legacy heading (no `dir #N`) with a real tag — must count under its own bare number.
# dir #6: a grade re-tag arrow ("R2 → R3") textually AFTER the real release tag, same shape as
#   the live dir #461 heading this tool's own header cites — the LAST QUALIFYING arrow is still
#   the release tag, not "R3" (which never matches the pool/next/on-demand/N.N[.N] vocabulary).
backlog="### dir #1 — a plain pool ticket (found 2026-01-01) — R1 — → pool

body

### dir #2 — a wrapped heading whose own tag sits on the continuation line, and whose BODY
contains a prose arrow that must not be read as a tag — R2 — → 0.9.0

this ticket also says → ask the operator before doing X, which must not be read as a tag

### dir #3 — closed, own trailing arrow must not be read as a tag — R1 — ✅ DONE (2026-01-01) — → 10,884 lines

body

### dir #4 — RE-SCOPED but still open, must still count — R2 — → pool

body

### 5. a legacy heading with a real tag — → 0.8

body

### dir #6 — re-graded, the grade arrow sits AFTER the real tag — R3 — → 0.11.0 (0.11.0 groom: R2 → R3, drain-shaped)

body
"

f="$(mk_backlog "$backlog")"
run "$bc" "$f"
check_status "basic run -> exit 0" 0 "$STATUS"
check_contains "pool: dir #1 and the RE-SCOPED dir #4 (2)" "$OUT" $'2\tpool'
check_contains "0.9.0: the wrapped-heading tag (1), prose arrow excluded" "$OUT" $'1\t0.9.0'
check_contains "0.8: the legacy heading's own tag (1)" "$OUT" $'1\t0.8'
check_contains "0.11.0: the re-graded ticket's real tag, not the grade arrow (1)" "$OUT" $'1\t0.11.0'
check_absent "the closed ticket's own trailing arrow is never counted as a tag" "$OUT" "10,884"
check_absent "no phantom 'R3' tag from the grade re-tag arrow" "$OUT" $'\tR3'

# --- untagged: no qualifying arrow at all -------------------------------------------------------
untagged_backlog="### dir #9 — no tag of any kind, still open — R1

body

### dir #10 — a prose-only arrow, no release/pool/next/on-demand token — R2 — → contest with dir #9

body
"
fu="$(mk_backlog "$untagged_backlog")"
run "$bc" "$fu"
check_contains "both blocks fall to untagged" "$OUT" $'2\tuntagged'

# --- next / on-demand vocabulary ------------------------------------------------------------------
lane_backlog="### dir #20 — a next-lane ticket — R1 — → next

body

### dir #21 — an on-demand ticket — R2 — → on-demand

body
"
fl="$(mk_backlog "$lane_backlog")"
run "$bc" "$fl"
check_contains "next lane counted" "$OUT" $'1\tnext'
check_contains "on-demand lane counted" "$OUT" $'1\ton-demand'

# --- descending order, tie broken by tag (ascending) --------------------------------------------
order_backlog="### dir #30 — a — R1 — → pool

body

### dir #31 — b — R1 — → pool

body

### dir #32 — c — R1 — → 0.9.0

body

### dir #33 — d — R1 — → 0.8.0

body
"
fo="$(mk_backlog "$order_backlog")"
run "$bc" "$fo"
first_line="$(head -1 <<< "$OUT")"
check_status "highest count (pool, 2) sorts first" "$(printf '2\tpool')" "$first_line"
tie_line1="$(sed -n '2p' <<< "$OUT")"
tie_line2="$(sed -n '3p' <<< "$OUT")"
check_status "single-count tie broken by tag ascending: 0.8.0 before 0.9.0 (line 2)" "$(printf '1\t0.8.0')" "$tie_line1"
check_status "single-count tie broken by tag ascending: 0.8.0 before 0.9.0 (line 3)" "$(printf '1\t0.9.0')" "$tie_line2"

# --- --list TAG: ticket numbers in file order, dir #N as bare N, legacy heading as its numeral ---
list_backlog="### dir #40 — first — R1 — → pool

body

### 41. a legacy pool ticket, second in file order — → pool

body

### dir #42 — not pool — R1 — → 0.9.0

body

### dir #43 — third pool ticket — R1 — → pool

body
"
flist="$(mk_backlog "$list_backlog")"
run "$bc" --list pool "$flist"
check_status "--list pool -> exit 0" 0 "$STATUS"
check_status "--list pool prints exactly 3 ids" 3 "$(printf '%s\n' "$OUT" | grep -c .)"
check_status "--list pool: file order, dir #N as bare N, legacy heading as its numeral" \
  "$(printf '40\n41\n43')" "$OUT"
run "$bc" --list 0.9.0 "$flist"
check_status "--list 0.9.0 prints exactly the one non-pool ticket" "42" "$OUT"
run "$bc" --list no-such-tag "$flist"
check_status "--list on an unused tag -> exit 0, empty output, not an error" 0 "$STATUS"
check_status "--list on an unused tag prints nothing" "" "$OUT"

# --- legacy headings count like any other block (matches backlog_ticket_blocks' own treatment) --
legacy_backlog="### 50. a legacy heading, no dir #N, real tag — → 0.10.2

body
"
fleg="$(mk_backlog "$legacy_backlog")"
run "$bc" "$fleg"
check_contains "legacy heading's tag counted" "$OUT" $'1\t0.10.2'

# --- smoke against today's real BACKLOG.md: must not crash, must print well-formed rows ---------
if [ -f "$REPO_ROOT/BACKLOG.md" ]; then
  run "$bc" "$REPO_ROOT/BACKLOG.md"
  check_status "real baseline -> exit 0" 0 "$STATUS"
  run "$bc" --list pool "$REPO_ROOT/BACKLOG.md"
  check_status "real baseline --list pool -> exit 0" 0 "$STATUS"
fi

summary
