#!/usr/bin/env bash
# tools/self/value-claim-lint.sh (dir #672): flags a groom plan's value-claim cell that has no
# `Subject set:` clause and no `no subject set — <why>` line. Fixtures are synthetic: the 0.14.0 plan's
# row A as first written (before its G6-1 finding) is reconstructed from the ledger's wording, never
# read from the real gitignored RELEASES.md.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

vc="$REPO_ROOT/tools/self/value-claim-lint.sh"

mk_releases() {
  local d
  d="$(mktemp -d "$SANDBOX/rel.XXXXXX")"
  printf '%s' "$1" > "$d/RELEASES.md"
  printf '%s' "$d/RELEASES.md"
}

# --- --help / bad args / missing file ------------------------------------------------------------
run "$vc" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$vc" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$vc" "$SANDBOX/no-such-releases.md"
check_status "missing RELEASES.md -> exit 0 (skip, not an error)" 0 "$STATUS"
check_contains "prints a skip line" "$OUT" "no readable RELEASES.md"

# --- the done-when: the 0.14.0 plan as first written is flagged, as fixed it passes -------------------
first_written="## v0.14.0 — cut readiness (groomed 2026-10-04)

### Row A — the cost of a /go session

| acceptance | the cost test is green |
| value claim | After 0.14.0, the median \`/go\` session costs under 2.55M tokens, down from the 0.13.0 median. |
| design economics | 0 owed |
"
f="$(mk_releases "$first_written")"
run "$vc" "$f" 0.14.0
check_status "as first written -> exit 0 (advisory)" 0 "$STATUS"
check_contains "row A as first written is flagged" "$OUT" "FLAG  v0.14.0 line 6"
check_contains "summary counts one cell, one lacking" "$OUT" "1 value-claim cell(s), 1 lacking a subject set"

as_fixed="${first_written/under 2.55M tokens, down from the 0.13.0 median./under 2.55M tokens. Subject set: every 0.14.0 slate /go session that starts after the cost slices are merged and deployed; diffed against the slate, residue none.}"
f="$(mk_releases "$as_fixed")"
run "$vc" "$f" 0.14.0
check_absent "row A as fixed is not flagged" "$OUT" "FLAG"
check_contains "summary: 0 lacking" "$OUT" "1 value-claim cell(s), 0 lacking a subject set"

# --- the two accepted clauses, and what does NOT count -------------------------------------------
f="$(mk_releases "## v1.0.0 — cut readiness

| value claim (release) | The drain. Subject set: the 12 tickets slated at this groom. |
| **value claim, plainly enough to be wrong in public** | no subject set — a behaviour, not a set of tickets. |
| VALUE CLAIM | uppercase label, subject set: named in lower case here. |
| value claim | mentions the phrase subject set without a clause. |
| value claim | no subject set |
| value claim | no subject set — |
")"
run "$vc" "$f"
check_contains "three cells pass, three are flagged" "$OUT" "6 value-claim cell(s), 3 lacking a subject set"
check_contains "bare phrase mention is flagged" "$OUT" "mentions the phrase subject set without a clause"
check_contains "'no subject set' with no reason is flagged" "$OUT" "FLAG  v1.0.0 line 7: | value claim | no subject set |"
check_contains "'no subject set —' with an empty reason is flagged" "$OUT" "FLAG  v1.0.0 line 8"
check_absent "the (release) suffix cell passes" "$OUT" "The drain"
check_absent "the bold-label no-subject-set cell passes" "$OUT" "plainly enough"

# --- G5's own vocabulary is accepted, one fixture per form; a claim with none of them is still flagged ---------
f="$(mk_releases "## v1.5.0 — cut readiness

| value claim | source = the known-issues paragraph's three tokens; diff against the slate = two in; Residue: #9 (not public). |
| value claim | Closed, by ticket kind. Residue: empty. |
| value claim | Carried-over theme, no claim beyond the release-level drain. |
| value claim | the median session costs under 2.55M tokens. |

**Value claims (G5):**
- **Row A:** source = row A's 17; Residue: none.
- **Row B:** carried-over theme, no claim beyond the release-level drain.
- **Row C:** closes the six known issues. Source: the paragraph.
")"
run "$vc" "$f"
check_contains "source+diff+Residue, Residue alone and 'no claim' pass; two bare claims are flagged" "$OUT" "7 value-claim cell(s), 2 lacking a subject set"
check_contains "a claim with no G5 form is flagged (0.14.0 row A's shape)" "$OUT" "FLAG  v1.5.0 line 6: | value claim | the median session"
check_contains "a source named but no residue or diff is still flagged" "$OUT" "FLAG  v1.5.0 line 11: - **Row C:**"
check_absent "the source/diff/Residue row passes" "$OUT" "line 3:"
check_absent "the Residue-alone row passes" "$OUT" "line 4:"
check_absent "the 'no claim' table row passes" "$OUT" "line 5:"

# --- prose bullets under a **Value claims** lead-in: continuation lines belong to their bullet -------
f="$(mk_releases "## v2.0.0 — cut readiness

**Value claims (G5; subject sets derived, then diffed against the slate):**
- **Release:** every ticket is credited. Subject set: the census list at this groom
  (57). Wrong in public if more than 5 are returned.
- **Row A:** the first row is closed; the clause sits only
  on a continuation line — Subject set: rows A's own tickets.
- **Row B:** claimed over a source and a residue, but never labelled as a set.
- **Row D:** carried-over theme, no claim beyond the release-level drain.

A later paragraph that says value claims in passing is not a cell.
")"
run "$vc" "$f"
check_contains "four bullets read, one lacks every form (Row D says no claim)" "$OUT" "4 value-claim cell(s), 1 lacking a subject set"
check_contains "bullet without a clause is flagged" "$OUT" "FLAG  v2.0.0 line 8"
check_absent "a bullet saying no claim passes" "$OUT" "line 9:"
check_absent "a clause on a continuation line counts for its bullet" "$OUT" "line 6:"

# --- review findings (fresh-context round 1) -----------------------------------------------------------------
f="$(mk_releases "## v6.0.0 — cut readiness

**Value claims (G5):**

- **Row A:** closed, Subject set: the census list.

- **Row B:** a bare claim with nothing bound.
  wrapped on an indented line.

An unindented paragraph ends the list.
- **Not a cell:** this bullet follows a paragraph and is not under the lead-in.
| value claim | there is no claimant lag and no claims were reopened. |
| value claim (residue: see below) | the median session costs under 2.55M tokens. |
| value claim | Closed. Residue — none. |
")"
run "$vc" "$f"
check_contains "blank lines around bullets keep list mode: both bullets read" "$OUT" "FLAG  v6.0.0 line 7: - **Row B:**"
check_contains "'no claimant' / 'no claims' is not the phrase 'no claim'" "$OUT" "FLAG  v6.0.0 line 12"
check_contains "a G5 form in the LABEL cell does not rescue the claim cell" "$OUT" "FLAG  v6.0.0 line 13"
check_contains "a bullet after an unindented paragraph is not a cell; 5 cells, 3 lacking" "$OUT" "5 value-claim cell(s), 3 lacking a subject set"
check_absent "Residue followed by an em dash passes" "$OUT" "line 14:"
OUT="$(export LC_ALL=C; "$vc" "$f" 2>&1)"
check_contains "same verdicts under LC_ALL=C (a multibyte dash is not a byte class)" "$OUT" "5 value-claim cell(s), 3 lacking a subject set"

f="$(mk_releases "## v6.1.0 — cut readiness

**Value claims (G5):**
- **Residue:** #12 deferred; the claim is that every other ticket closes.

- **Row B:** closed.

  Subject set: row B's own tickets, on an indented paragraph after a blank line.
- **Subject set:** the six known-issues items, diffed against the slate.
- **Row C:** bare.
")"
run "$vc" "$f"
check_contains "a bullet whose bold lead IS a G5 form passes; only the bare bullet is flagged" "$OUT" "4 value-claim cell(s), 1 lacking a subject set"
check_contains "the bare bullet is the one flagged" "$OUT" "FLAG  v6.1.0 line 10: - **Row C:**"
check_absent "Row B passes through its blank-separated continuation" "$OUT" "line 6:"

# --- an EMPTY clause is not a clause: bold markup and bare labels carry no content -------------------------------
f="$(mk_releases "## v6.2.0 — cut readiness

**Value claims (G5):**
- **Subject set:**
- **Residue:**
- **No subject set —**
- **Row A:** closes everything. **Subject set:** the real list.
- **Row B:** closes everything. Residue: none.
")"
run "$vc" "$f"
check_contains "empty bold G5 clauses are flagged; a bold clause with content, and Residue: none, pass" "$OUT" "5 value-claim cell(s), 3 lacking a subject set"
check_contains "an empty Subject set label is flagged" "$OUT" "FLAG  v6.2.0 line 4: - **Subject set:**"
check_contains "an empty Residue label is flagged" "$OUT" "FLAG  v6.2.0 line 5: - **Residue:**"
check_contains "an empty no-subject-set label is flagged" "$OUT" "FLAG  v6.2.0 line 6: - **No subject set"
check_absent "a bold Subject set clause with content passes" "$OUT" "line 7:"
check_absent "Residue: none passes" "$OUT" "line 8:"

# --- sections: VERSION filters, no VERSION reads all, a duplicate heading is read twice --------------
f="$(mk_releases "## v3.0.0 — cut readiness

| value claim | bad cell in 3.0.0 |

## Release plan 0.8.2 → 0.13.0 (old shape, not a v-section)

| value claim | bad cell outside any v-section |

## v3.1.0 — cut readiness

| value claim | Subject set: fine. |

## v3.0.0 — cut readiness (re-groomed)

| value claim | another bad cell in 3.0.0 |
")"
run "$vc" "$f" 3.1.0
check_contains "VERSION filter: only that section, clean" "$OUT" "1 plan section(s), 1 value-claim cell(s), 0 lacking"
run "$vc" "$f" v3.0.0
check_contains "a leading v is accepted; a duplicate heading is read twice" "$OUT" "2 plan section(s), 2 value-claim cell(s), 2 lacking"
run "$vc" "$f"
check_contains "no VERSION reads every v-section" "$OUT" "3 plan section(s), 3 value-claim cell(s), 2 lacking"
check_absent "a non-v section is never read" "$OUT" "outside any v-section"
run "$vc" "$f" 9.9.9
check_contains "no matching section says so" "$OUT" "no plan section matched v9.9.9"

# --- nothing covered is a notice, never a silent pass ----------------------------------------------------
f="$(mk_releases "## v4.0.0 — cut readiness

**Value claim — stated to be checkable.** After 4.0.0 nothing is wrong. (A shape this check does not read.)
")"
run "$vc" "$f"
check_contains "an uncovered shape is reported as a gap" "$OUT" "no covered value-claim cell found"

# --- an example row inside a fenced block is not a claim -------------------------------------------------
f="$(mk_releases "## v5.0.0 — cut readiness

\`\`\`
| value claim | an illustrative row in a fence |
\`\`\`
")"
run "$vc" "$f"
check_contains "a fenced example row is not counted" "$OUT" "0 value-claim cell(s)"

summary
