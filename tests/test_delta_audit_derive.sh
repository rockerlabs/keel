#!/usr/bin/env bash
# Tests for tools/delta-audit/derive.sh — dir #207's mechanical delta-audit universe deriver.
#
# The two load-bearing claims this file pins, beyond ordinary output correctness:
#   1. Ledger row ORDER is read-order (seams+invariant, then remaining code/test, then
#      prose+historical) and NOT git diff --name-only's alphabetical order — every fixture below
#      is built so alphabetical order and read order actively disagree, so a regression to a plain
#      `sort` would be caught, not hidden by a fixture where both orders happen to coincide.
#   2. The closure check (the union of every per-PR file list vs the range diff) actually FIRES on
#      a squash-merged commit, which is the one structural blind spot this derivation cannot avoid:
#      a squash/rebase merge leaves no "Merge pull request #N" commit to attribute files to.
# Byte-identical reproduction against the two real prototype datasets
# (private/audit/delta-0.7.0-0.7.1/ and private/audit/delta-0.6.1-0.7.0/, both gitignored and
# main-checkout-only) is dir #207's own done-criteria 1-2, verified by hand at implementation time
# and recorded in the PR body — this suite tests the general mechanism against fixtures it owns.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/delta-audit/derive.sh"
check_file "derive.sh exists" "$TOOL"

TAB="$(printf '\t')"

# A repo with one empty init commit — the fixture base every case below branches from. Plain
# new_repo(), no bare origin: derive.sh never touches a remote, unlike tools/drydock/inventory.sh's
# origin/main default.
mk_repo() {
  local d
  d="$(new_repo)"
  git -C "$d" commit -q --allow-empty -m init
  printf '%s' "$d"
}

# Merge branch $3 of repo $1 into its current branch as PR #$2 — the exact commit-subject shape
# derive.sh's sed pattern parses ('Merge pull request #N from ...').
merge_pr() {
  git -C "$1" merge -q --no-ff -m "Merge pull request #$2 from someorg/$3" "$3"
}

# --- the main fixture: seams, every class, and alphabetical order actively disagreeing with the
# pinned read order (bucket1 files sort LAST alphabetically; bucket3 files sort FIRST) -------------
r="$(mk_repo)"
base="$(git -C "$r" rev-parse HEAD)"

git -C "$r" checkout -qb pr1
mkdir -p "$r/tests"
printf 'x\n'  > "$r/shared.sh"                    # touched by 2 PRs -> a seam
printf 'y\n'  > "$r/aa-prose.md"                  # plain prose, alphabetically FIRST
printf 'z\n'  > "$r/mm-code.sh"                   # plain code, one PR, not a seam
printf 't\n'  > "$r/tests/test_thing.sh"
git -C "$r" add -A
git -C "$r" commit -qm "pr1 content"
git -C "$r" checkout -q main
merge_pr "$r" 101 pr1

git -C "$r" checkout -qb pr2
printf 'x2\n' >> "$r/shared.sh"                   # shared.sh's 2nd PR -> seam confirmed
printf 'w\n'  > "$r/zz-secret-guard-thing.sh"     # matches DELTA_INVARIANT_PATHS by substring,
                                                   # alphabetically LAST
printf 'c\n'  > "$r/CHANGELOG.md"                 # always prose-historical, regardless of being a
                                                   # seam itself (5-PR CHANGELOG.md is the real-world
                                                   # case this rule exists for)
git -C "$r" add -A
git -C "$r" commit -qm "pr2 content"
git -C "$r" checkout -q main
merge_pr "$r" 102 pr2
head="$(git -C "$r" rev-parse HEAD)"

out1="$SANDBOX/out1"
mkdir -p "$out1"
run_in "$r" "$TOOL" --out "$out1" "$base" "$head"
check_status "the main fixture -> exit 0 (closure closes)" 0 "$STATUS"

check_file "delta-files.txt written" "$out1/delta-files.txt"
check_file "file-pr-map.tsv written" "$out1/file-pr-map.tsv"
check_file "ledger.md written" "$out1/ledger.md"
check_file "run-record.md written" "$out1/run-record.md"

files="$(cat "$out1/delta-files.txt")"
check_contains "the file list equals the range diff (6 files)" "$(wc -l < "$out1/delta-files.txt" | tr -d ' ')" "6"
for f in shared.sh aa-prose.md mm-code.sh tests/test_thing.sh zz-secret-guard-thing.sh CHANGELOG.md; do
  check_contains "delta-files.txt lists $f" "$files" "$f"
done

map="$(cat "$out1/file-pr-map.tsv")"
check_contains "shared.sh is a seam: 2 PRs, both named" "$map" "$(printf 'shared.sh%s2%s#101 #102' "$TAB" "$TAB")"
check_contains "mm-code.sh: 1 PR" "$map" "$(printf 'mm-code.sh%s1%s#101' "$TAB" "$TAB")"
check_contains "CHANGELOG.md: 1 PR (this fixture; a seam in real runs)" "$map" \
  "$(printf 'CHANGELOG.md%s1%s#102' "$TAB" "$TAB")"

ledger="$(cat "$out1/ledger.md")"
check_contains "shared.sh classed code, seam -> read-order bucket 1" "$ledger" \
  "| shared.sh | code | 2 | #101 #102 |"
check_contains "zz-secret-guard-thing.sh classed code-invariant (default DELTA_INVARIANT_PATHS)" \
  "$ledger" "| zz-secret-guard-thing.sh | code-invariant | 1 | #102 |"
check_contains "mm-code.sh classed code, not a seam -> bucket 2" "$ledger" \
  "| mm-code.sh | code | 1 | #101 |"
check_contains "tests/test_thing.sh classed test" "$ledger" "| tests/test_thing.sh | test | 1 | #101 |"
check_contains "CHANGELOG.md always prose-historical" "$ledger" \
  "| CHANGELOG.md | prose-historical | 1 | #102 |"
check_contains "aa-prose.md classed plain prose" "$ledger" "| aa-prose.md | prose | 1 | #101 |"

# The regression pin: read order, not alphabetical. Alphabetical (delta-files.txt / a naive `sort`)
# would put CHANGELOG.md and aa-prose.md FIRST and zz-secret-guard-thing.sh LAST — the opposite of
# what docs/delta-audit.md's read-order rule requires. A mutation back to alphabetical emission would
# violate every inequality below.
line_of() { grep -n -F -- "$2" "$1" | head -1 | cut -d: -f1; }
l_shared="$(line_of "$out1/ledger.md" '| shared.sh |')"
l_secret="$(line_of "$out1/ledger.md" '| zz-secret-guard-thing.sh |')"
l_test="$(line_of "$out1/ledger.md" '| tests/test_thing.sh |')"
l_code="$(line_of "$out1/ledger.md" '| mm-code.sh |')"
l_changelog="$(line_of "$out1/ledger.md" '| CHANGELOG.md |')"
l_prose="$(line_of "$out1/ledger.md" '| aa-prose.md |')"
if [ -n "$l_shared" ] && [ -n "$l_secret" ] && [ -n "$l_test" ] && [ -n "$l_code" ] \
   && [ -n "$l_changelog" ] && [ -n "$l_prose" ] \
   && [ "$l_shared" -lt "$l_code" ] && [ "$l_secret" -lt "$l_code" ] \
   && [ "$l_code" -lt "$l_changelog" ] && [ "$l_test" -lt "$l_changelog" ]; then
  pass "ledger read order: seams+invariant, then code/test, then prose+historical (not alphabetical)"
else
  fail "ledger read order: seams+invariant, then code/test, then prose+historical (not alphabetical)" \
    "lines: shared=$l_shared secret-guard=$l_secret test=$l_test code=$l_code changelog=$l_changelog prose=$l_prose"
fi
check_absent "S1 is never assigned per-row (it is the mechanical baseline, covers every row)" \
  "$ledger" "| S1 |"

# --- the packing knob: DELTA_SESSION_FILES caps how many read-ordered rows share a session --------
run_in "$r" env "DELTA_SESSION_FILES=2" "$TOOL" --out "$SANDBOX/out-cap" "$base" "$head"
check_status "a lowered session cap -> exit 0" 0 "$STATUS"
cap_ledger="$(cat "$SANDBOX/out-cap/ledger.md")"
check_contains "row 0 (shared.sh) in the first session" "$cap_ledger" "| shared.sh | code | 2 | #101 #102 | S2 |"
check_contains "row 1 (zz-secret-guard-thing.sh) still in the first session (cap 2)" "$cap_ledger" \
  "| zz-secret-guard-thing.sh | code-invariant | 1 | #102 | S2 |"
check_contains "row 2 rolls into a new session" "$cap_ledger" "S3"
check_contains "the highest-index rows reach a later session still" "$cap_ledger" "S4"

# --- DELTA_SESSION_FILES=0 (or any non-positive override) falls back to the default rather than
# dividing by zero. `idx / session_cap` on session_cap=0 is a fatal arithmetic error inside the
# printf loop; under set -e that used to abort only that ONE iteration silently, so the run exited 0
# with every ledger data row missing — a silent-success data-loss bug, not a documented refusal.
run_in "$r" env "DELTA_SESSION_FILES=0" "$TOOL" --out "$SANDBOX/out-cap0" "$base" "$head"
check_status "DELTA_SESSION_FILES=0 -> exit 0, not a crash" 0 "$STATUS"
zero_ledger="$(cat "$SANDBOX/out-cap0/ledger.md")"
check_contains "every data row still lands in the ledger, not silently dropped" \
  "$zero_ledger" "| shared.sh | code | 2 | #101 #102 |"
check_contains "...all six of them" "$zero_ledger" "| aa-prose.md | prose | 1 | #101 |"
row_count="$(printf '%s\n' "$zero_ledger" | grep -c ' | S[0-9]\{1,\} | |$')"
if [ "$row_count" -eq 6 ]; then
  pass "exactly 6 data rows survive (no silent truncation)"
else
  fail "exactly 6 data rows survive (no silent truncation)" "got $row_count rows"
fi

# --- the historical-class knob: DELTA_HISTORICAL ---------------------------------------------------
run_in "$r" env "DELTA_HISTORICAL=NOTHING.md" "$TOOL" --out "$SANDBOX/out-hist" "$base" "$head"
hist_ledger="$(cat "$SANDBOX/out-hist/ledger.md")"
check_contains "overriding DELTA_HISTORICAL: CHANGELOG.md is no longer prose-historical" \
  "$hist_ledger" "| CHANGELOG.md | prose |"
check_absent "and it is no longer forced into the last bucket ahead of a non-special prose file" \
  "$hist_ledger" "| CHANGELOG.md | prose-historical |"

# --- the invariant-paths knob: DELTA_INVARIANT_PATHS, and its precedence over both tests/ and seams -
run_in "$r" env "DELTA_INVARIANT_PATHS=mm-code" "$TOOL" --out "$SANDBOX/out-inv" "$base" "$head"
inv_ledger="$(cat "$SANDBOX/out-inv/ledger.md")"
check_contains "a custom invariant pattern reclassifies its match" "$inv_ledger" "| mm-code.sh | code-invariant |"
check_contains "the default pattern no longer applies once overridden" "$inv_ledger" \
  "| zz-secret-guard-thing.sh | code | 1 | #102 |"

# invariant beats tests/: first-match-wins order names invariant BEFORE the tests/ prefix rule.
r2="$(mk_repo)"
base2="$(git -C "$r2" rev-parse HEAD)"
mkdir -p "$r2/tests"
printf 'x\n' > "$r2/tests/pre-pr-gate-thing.sh"
git -C "$r2" add -A; git -C "$r2" commit -qm "a test-dir file matching the default invariant list"
head2="$(git -C "$r2" rev-parse HEAD)"
run_in "$r2" "$TOOL" --out "$SANDBOX/out-prec" "$base2" "$head2"
prec_ledger="$(cat "$SANDBOX/out-prec/ledger.md")"
check_contains "a tests/ path matching DELTA_INVARIANT_PATHS classes code-invariant, not test" \
  "$prec_ledger" "| tests/pre-pr-gate-thing.sh | code-invariant |"

# --- an executable, extensionless file (mirrors the real ./keel CLI) classes code -----------------
r3="$(mk_repo)"
base3="$(git -C "$r3" rev-parse HEAD)"
printf '#!/bin/sh\necho hi\n' > "$r3/cli-tool"
chmod +x "$r3/cli-tool"
git -C "$r3" add -A; git -C "$r3" commit -qm "an extensionless executable"
head3="$(git -C "$r3" rev-parse HEAD)"
run_in "$r3" "$TOOL" --out "$SANDBOX/out-exec" "$base3" "$head3"
exec_ledger="$(cat "$SANDBOX/out-exec/ledger.md")"
check_contains "an executable extensionless file classes code" "$exec_ledger" "| cli-tool | code |"

# --- the mirror case: an extensionless executable DELETED within the range still classes code, not
# prose. is_code() only had a head-tree lookup originally, so a file absent from head's tree (any
# deletion) silently fell through every rule to the catch-all "prose" — the exact opposite of what a
# removed executable is. Falls back to the PREV tree's mode when the path is missing from head's.
r6="$(mk_repo)"
printf '#!/bin/sh\necho hi\n' > "$r6/cli-tool"
chmod +x "$r6/cli-tool"
git -C "$r6" add -A; git -C "$r6" commit -qm "cli-tool exists at the range's start"
base6="$(git -C "$r6" rev-parse HEAD)"
git -C "$r6" checkout -qb remove-cli
git -C "$r6" rm -q cli-tool
git -C "$r6" commit -qm "remove cli-tool"
git -C "$r6" checkout -q main
merge_pr "$r6" 401 remove-cli
head6="$(git -C "$r6" rev-parse HEAD)"
run_in "$r6" "$TOOL" --out "$SANDBOX/out-del-exec" "$base6" "$head6"
check_status "a deleted extensionless executable -> exit 0 (closure closes, one merge)" 0 "$STATUS"
check_contains "a deleted extensionless executable still classes code, not prose" \
  "$(cat "$SANDBOX/out-del-exec/ledger.md")" "| cli-tool | code |"

# --- run-record.md is a stub carrying the scope line, nothing else asserted (it is filled by hand) -
check_contains "run-record.md's scope line names the file and PR counts" \
  "$(cat "$out1/run-record.md")" "| scope | 6 files, 2 PRs |"

# --- the closure check fires on a squash/rebase merge: the one structural blind spot --------------
sq="$(mk_repo)"
sq_base="$(git -C "$sq" rev-parse HEAD)"
git -C "$sq" checkout -qb feature
printf 'a\n' > "$sq/only-in-feature.txt"
git -C "$sq" add -A; git -C "$sq" commit -qm "feature work"
git -C "$sq" checkout -q main
git -C "$sq" merge -q --squash feature
git -C "$sq" commit -qm "squashed, no merge commit at all"
sq_head="$(git -C "$sq" rev-parse HEAD)"
run_in "$sq" "$TOOL" --out "$SANDBOX/out-sq" "$sq_base" "$sq_head"
check_status "a squash-merged PR -> the closure check fires -> exit 3" 3 "$STATUS"
check_contains "the refusal says the universe does not close" "$OUT" "does not close"
check_contains "the refusal names the squash-merge class as the likely cause" "$OUT" "squash-merged or rebase-merged"
check_contains "the refusal names the orphaned file" "$OUT" "only-in-feature.txt"
check_file "delta-files.txt is still written on a closure failure (it is correct; the MAP is short)" \
  "$SANDBOX/out-sq/delta-files.txt"

# --- the closure check's OTHER direction: a file attributed to a PR but outside the final range
# diff — e.g. added by one PR and removed by a later PR in the same range, so it nets to no change
# between the two endpoints yet still appears in both per-merge diffs. The squash fixture above only
# exercises "in delta-files.txt but attributed to no PR" (the map too SHORT); this exercises the
# opposite (the map too LONG relative to the net range diff), the closure check's own other half.
om="$(mk_repo)"
om_base="$(git -C "$om" rev-parse HEAD)"
git -C "$om" checkout -qb add-temp
printf 'x\n' > "$om/temp.txt"
git -C "$om" add -A; git -C "$om" commit -qm "add temp.txt"
git -C "$om" checkout -q main
merge_pr "$om" 201 add-temp
git -C "$om" checkout -qb remove-temp
git -C "$om" rm -q temp.txt
git -C "$om" commit -qm "remove temp.txt again"
git -C "$om" checkout -q main
merge_pr "$om" 202 remove-temp
om_head="$(git -C "$om" rev-parse HEAD)"
run_in "$om" "$TOOL" --out "$SANDBOX/out-om" "$om_base" "$om_head"
check_status "a file added then removed within the range -> closure fires -> exit 3" 3 "$STATUS"
check_contains "the refusal says the universe does not close" "$OUT" "does not close"
check_contains "the refusal names the over-attributed file" "$OUT" "temp.txt"
check_contains "the refusal labels this direction distinctly" "$OUT" "attributed to a PR but outside the range diff"
check_absent "temp.txt nets to no change, so it is absent from delta-files.txt itself" \
  "$(cat "$SANDBOX/out-om/delta-files.txt")" "temp.txt"

# --- dirty-tree invariance: TO VERIFY closed empirically at implementation time, pinned here as a
# regression test. derive.sh reads only history (git diff/log), never the working tree, so a dirty
# tree must leave every output byte-identical to a clean-tree run. -----------------------------------
run_in "$r" "$TOOL" --out "$SANDBOX/out-clean" "$base" "$head"
printf 'uncommitted scratch\n' >> "$r/aa-prose.md"
printf 'untracked\n' > "$r/untracked-scratch.txt"
run_in "$r" "$TOOL" --out "$SANDBOX/out-dirty" "$base" "$head"
git -C "$r" checkout -q -- aa-prose.md
rm -f "$r/untracked-scratch.txt"
if diff -q "$SANDBOX/out-clean/delta-files.txt" "$SANDBOX/out-dirty/delta-files.txt" >/dev/null \
   && diff -q "$SANDBOX/out-clean/file-pr-map.tsv" "$SANDBOX/out-dirty/file-pr-map.tsv" >/dev/null \
   && diff -q "$SANDBOX/out-clean/ledger.md" "$SANDBOX/out-dirty/ledger.md" >/dev/null; then
  pass "a dirty working tree leaves every output byte-identical to the clean-tree run"
else
  fail "a dirty working tree leaves every output byte-identical to the clean-tree run" \
    "outputs differed between the clean and dirty runs"
fi

# --- refusals (exit 3) -------------------------------------------------------------------------
notrepo="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
run_in "$notrepo" "$TOOL" HEAD HEAD
check_status "outside a git repository -> exit 3" 3 "$STATUS"
check_contains "the non-repo refusal says so" "$OUT" "git repository"

run_in "$r" "$TOOL" nonexistent-rev-aaa "$head"
check_status "an unresolvable prev-rev -> exit 3" 3 "$STATUS"
check_contains "the refusal names the prev-rev it could not resolve" "$OUT" "nonexistent-rev-aaa"
check_contains "the refusal points at <prev-rev>" "$OUT" "<prev-rev>"

run_in "$r" "$TOOL" "$base" nonexistent-rev-bbb
check_status "an unresolvable head-rev -> exit 3" 3 "$STATUS"
check_contains "the refusal names the head-rev it could not resolve" "$OUT" "nonexistent-rev-bbb"
check_contains "the refusal points at <head-rev>" "$OUT" "<head-rev>"

blocked="$SANDBOX/blocked-output"
: > "$blocked"    # a plain FILE where derive.sh needs a directory — mkdir -p fails for every user,
                  # root included, unlike a chmod 000 guard (project CLAUDE.md's Alpine root trap)
run_in "$r" "$TOOL" --out "$blocked" "$base" "$head"
check_status "an unusable --out target -> exit 3" 3 "$STATUS"
check_contains "the refusal names the output directory" "$OUT" "blocked-output"

# --- argument errors (exit 2) -------------------------------------------------------------------
run_in "$r" "$TOOL" "$base"
check_status "a missing <head-rev> -> exit 2" 2 "$STATUS"
check_contains "the missing-argument error names head-rev" "$OUT" "<head-rev>"

run_in "$r" "$TOOL"
check_status "both revisions missing -> exit 2" 2 "$STATUS"

run_in "$r" "$TOOL" "$base" "$head" one-too-many
check_status "a stray third positional -> exit 2" 2 "$STATUS"

run_in "$r" "$TOOL" --nonsense "$base" "$head"
check_status "an unknown option -> exit 2" 2 "$STATUS"

run_in "$r" "$TOOL" --out
check_status "--out with no value -> exit 2" 2 "$STATUS"

run_in "$r" "$TOOL" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "usage"
check_nofile "--help runs no accidental derivation (default --out is cwd)" "$r/delta-files.txt"
check_nofile "...and does not overwrite ledger.md either" "$r/ledger.md"

summary
