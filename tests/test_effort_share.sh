#!/usr/bin/env bash
# tests/test_effort_share.sh — dir #635 PR2: tools/effort-share.sh counts unique --all --no-merges commits
# per repository for a caller-named meta set and product set, since a date or a ref, and prints the meta
# share (the grooming thermostat's instrument, docs/grooming.md G7/G0). Every fixture repo is built here
# with fixed committer dates; nothing clones the repo under test.
#
# EFFORT_SHARE_TOOL overrides the tool path: the mutation check (a copy of the tool with one behaviour
# broken must turn the matching assertion red) runs this same file against the mutated copy.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="${EFFORT_SHARE_TOOL:-$REPO_ROOT/tools/effort-share.sh}"
check_file "tools/effort-share.sh exists" "$tool"

commit() { # commit REPO ISO-DATE MESSAGE
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t.invalid \
    commit -q --allow-empty -m "$3"
}
mkrepo() { local r; r="$(new_repo)"; git -C "$r" symbolic-ref HEAD refs/heads/main; printf '%s' "$r"; }

# Meta repo M: c1 (before the cutoff), c2 exactly AT the cutoff instant (tagged v1), then three parallel
# lines off c2 — side s1, unmerged wip w1, main c3 — and a --no-ff merge m1 of side into main.
M="$(mkrepo)"
commit "$M" 2026-02-01T00:00:00Z c1
commit "$M" 2026-03-01T00:00:00Z c2
git -C "$M" tag v1
git -C "$M" checkout -q -b side
commit "$M" 2026-03-15T00:00:00Z s1
git -C "$M" checkout -q main
git -C "$M" checkout -q -b wip
commit "$M" 2026-03-12T00:00:00Z w1
git -C "$M" checkout -q main
commit "$M" 2026-03-20T00:00:00Z c3
GIT_AUTHOR_DATE=2026-03-25T00:00:00Z GIT_COMMITTER_DATE=2026-03-25T00:00:00Z \
  git -C "$M" -c user.name=t -c user.email=t@t.invalid merge -q --no-ff side -m m1

# Product repo P: p1 one second BEFORE the cutoff, p2 (tagged v1) and p3..p6 after it.
P="$(mkrepo)"
commit "$P" 2026-02-28T23:59:59Z p1
commit "$P" 2026-03-05T00:00:00Z p2
git -C "$P" tag v1
for d in 06 07 08 09; do commit "$P" "2026-03-${d}T00:00:00Z" "p-$d"; done

# Commits that are not work: a stash entry (refs/stash) and a notes commit (refs/notes/commits) sit outside
# every branch and tag, yet --all reaches them. The counts below must not move because of them.
STASHC="$(GIT_AUTHOR_DATE=2026-03-22T00:00:00Z GIT_COMMITTER_DATE=2026-03-22T00:00:00Z \
  git -C "$M" -c user.name=t -c user.email=t@t.invalid commit-tree "$(git -C "$M" rev-parse 'HEAD^{tree}')" -p "$(git -C "$M" rev-parse HEAD)" -m 'index on main')"
git -C "$M" update-ref refs/stash "$STASHC"
GIT_AUTHOR_DATE=2026-03-23T00:00:00Z GIT_COMMITTER_DATE=2026-03-23T00:00:00Z \
  git -C "$M" -c user.name=t -c user.email=t@t.invalid notes add -m note "$(git -C "$M" rev-parse HEAD)"
check_eq "fixture: the stash ref and the notes ref exist" 2 \
  "$(git -C "$M" for-each-ref refs/stash refs/notes | wc -l | tr -d ' ')"

check_eq "fixture: M holds exactly one merge commit" 1 "$(git -C "$M" rev-list --merges --all | wc -l | tr -d ' ')"

# --- usage ---------------------------------------------------------------------------------------
run bash "$tool" --help
check_status "--help exits 0" 0 "$STATUS"
check_contains "--help states the counting definition" "$OUT" "git rev-list --all"
check_contains "--help states merges are excluded" "$OUT" "--no-merges"
check_contains "--help states the honest limit" "$OUT" "commits are a proxy for effort"
check_contains "--help states commit granularity differs" "$OUT" "commit granularity differs across projects"
run bash "$tool"
check_status "no arguments exits 2" 2 "$STATUS"
run bash "$tool" --meta "$M" --since 2026-03-01
check_status "a missing --product exits 2" 2 "$STATUS"
run bash "$tool" --meta "$M" --product "$P"
check_status "a missing --since exits 2" 2 "$STATUS"
run bash "$tool" --meta "$M" --product "$P" --since 2026-03-01 --bogus
check_status "an unknown flag exits 2" 2 "$STATUS"

# --- counting: dates, the instant boundary, merges, --all, uniqueness ----------------------------
run bash "$tool" --meta "$M" --product "$P" --since 2026-03-01 --json
check_status_out "a date run exits 0" 0
check_contains "M counts c2 (at the cutoff), s1, w1, c3 and NOT the merge or c1 (a merge commit is not counted)" "$OUT" "\"meta_commits\":4"
check_contains "P counts p2..p6 and not p1 (one second before the cutoff)" "$OUT" "\"product_commits\":5"
check_contains "stash and notes commits are not counted (M stays at 4)" "$OUT" "\"meta_commits\":4"
check_contains "the share is meta over the total, one decimal" "$OUT" "\"meta_share_percent\":44.4"
check_contains "the JSON names each repo with its count" "$OUT" "{\"repo\":\"$M\",\"commits\":4}"

run bash "$tool" --meta "$M" --product "$P" --since 2026-03-01
check_status_out "the table run exits 0" 0
check_contains "the table prints the share" "$OUT" "meta share 44.4%"

run bash "$tool" --meta "$M" --product "$P" --since 1969-12-31
check_status "a date before 1970 refuses" 2 "$STATUS"
run bash "$tool" --meta "$M" --product "$P" --since 2040-01-01 --json
check_contains "a far-future date is an empty period, not a clamped one (n/a)" "$OUT" "\"meta_share_percent\":null"
run bash "$tool" --meta "$M" --product "$P" --since -q
check_status "a --since starting with a dash refuses" 2 "$STATUS"
check_contains "... as neither a date nor a ref" "$OUT" "neither a valid date"

# --- refs: resolved per repo ----------------------------------------------------------------------
run bash "$tool" --meta "$M" --product "$P" --since v1 --json
check_status_out "a ref run exits 0" 0
check_contains "a ref counts the commits not reachable from it, per repo (M: s1, w1, c3)" "$OUT" "\"meta_commits\":3"
check_contains "a ref is resolved in each repo (P: p3..p6)" "$OUT" "\"product_commits\":4"
check_contains "the ref share" "$OUT" "\"meta_share_percent\":42.9"

git -C "$M" tag only-in-meta
run bash "$tool" --meta "$M" --product "$P" --since only-in-meta
check_status "a ref missing from one repo refuses with exit 2" 2 "$STATUS"
check_contains "... naming the repo that lacks it" "$OUT" "$P"
check_absent "... and prints no count for the other repo" "$OUT" "meta share"
git -C "$P" tag only-in-product
run bash "$tool" --meta "$M" --product "$P" --since only-in-product
check_status "a ref missing from the meta repo refuses too" 2 "$STATUS"
check_contains "... naming the meta repo" "$OUT" "$M"

# --- an unparseable --since: git reads it as "now" and answers an empty period; the tool refuses ---
check_eq "premise: git log --since=garbage silently yields zero commits" 0 \
  "$(git -C "$M" log --all --since=garbage --format=%h | wc -l | tr -d ' ')"
run bash "$tool" --meta "$M" --product "$P" --since garbage
check_status "an unparseable --since refuses (never a silent zero share)" 2 "$STATUS"
check_contains "... saying what it accepts" "$OUT" "neither a valid date"
run bash "$tool" --meta "$M" --product "$P" --since yesterday
check_status "a relative date word refuses" 2 "$STATUS"
run bash "$tool" --meta "$M" --product "$P" --since 2026-02-30
check_status "an impossible calendar date refuses" 2 "$STATUS"
check_contains "... as an invalid date" "$OUT" "not a valid date"
run bash "$tool" --meta "$M" --product "$P" --since 2026-13-01
check_status "a month 13 refuses" 2 "$STATUS"

# --- repo validation -----------------------------------------------------------------------------
NR="$SANDBOX/not-a-repo"; mkdir -p "$NR"
run bash "$tool" --meta "$M" --product "$NR" --since 2026-03-01
check_status "a path that is not a git repo refuses" 2 "$STATUS"
check_contains "... naming it" "$OUT" "$NR"
run bash "$tool" --meta "$M" --product "$SANDBOX/does-not-exist" --since 2026-03-01
check_status "a missing path refuses" 2 "$STATUS"
mkdir -p "$M/subdir"
run bash "$tool" --meta "$M/subdir" --product "$P" --since 2026-03-01
check_status "a subdirectory of a repo (not its top) refuses" 2 "$STATUS"
run bash "$tool" --meta "$M" --product "$M" --since 2026-03-01
check_status "the same repo in both sets refuses (it would be counted twice)" 2 "$STATUS"
run bash "$tool" --meta "$M" "$M" --product "$P" --since 2026-03-01
check_status "the same repo twice in one set refuses" 2 "$STATUS"

git -C "$M" worktree add -q "$SANDBOX/wt-of-m" -b wtbranch
run bash "$tool" --meta "$M" --product "$SANDBOX/wt-of-m" --since 2026-03-01
check_status "a linked worktree of an already-listed repo refuses (it shares the ref set)" 2 "$STATUS"
run bash "$tool" --meta "$M" --product "$M/.git" --since 2026-03-01
check_status "the .git directory of an already-listed repo refuses" 2 "$STATUS"
TABP="$SANDBOX/tab$(printf '\t')repo"
run bash "$tool" --meta "$M" --product "$TABP" --since 2026-03-01
check_status "a repository path with a control character refuses" 2 "$STATUS"
check_contains "... saying so" "$OUT" "control character"

# --- multiple repos per set ----------------------------------------------------------------------
P2="$(mkrepo)"
commit "$P2" 2026-04-01T00:00:00Z q1
run bash "$tool" --meta "$M" --product "$P" "$P2" --since 2026-03-01 --json
check_contains "several product repos are summed" "$OUT" "\"product_commits\":6"

# --- zero commits in total: n/a, never 0% and never a division error -------------------------------
run bash "$tool" --meta "$M" --product "$P" --since 2030-01-01
check_status_out "zero commits in total exits 0" 0
check_contains "... the share is n/a" "$OUT" "meta share n/a"
check_absent "... never 0%" "$OUT" "0%"
check_absent "... no division error" "$OUT" "division"
run bash "$tool" --meta "$M" --product "$P" --since 2030-01-01 --json
check_contains "... JSON carries null" "$OUT" "\"meta_share_percent\":null"
EMPTY="$(mkrepo)"
E2="$(mkrepo)"
run bash "$tool" --meta "$EMPTY" --product "$E2" --since 2026-01-01
check_status_out "two empty repos exit 0" 0
check_contains "... share n/a" "$OUT" "meta share n/a"

# --- shape constraints of the source -------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  run bash "$tool" --meta "$M" --product "$P" --since 2026-03-01 --json
  check_eq "the JSON parses and carries the share" 44.4 "$(printf '%s' "$OUT" | jq -r .meta_share_percent)"
else
  pass "jq not available — JSON parse check skipped (the tool itself never needs jq)"
fi
check_eq "the tool does not call jq" 0 "$(grep -v '^[[:space:]]*#' "$tool" | grep -cE '(^|[^[:alnum:]_])jq([^[:alnum:]_]|$)')"
check_eq "the tool uses no bash-4 feature (mapfile, readarray, declare -A, case-modifying expansion, +=( )" 0 \
  "$(grep -cE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)|\+=\(' "$tool")"
check_eq "every awk and sort call runs under LC_ALL=C" 0 \
  "$(grep -v '^[[:space:]]*#' "$tool" | grep -E '(^|[|;( ])(awk|sort) ' | grep -vc 'LC_ALL=C \(awk\|sort\)')"
check_eq "nothing about any operator repo is hard-coded" 0 \
  "$(grep -ciE 'hermes|traverse|sidecast|social-media|\.keel|INSTANCE\.md|\$HOME|~/' "$tool")"
check_eq "the tool carries the repo-selector guard line before any git call" 1 \
  "$(grep -cxF "$(grep -m1 '^unset GIT_DIR' "$REPO_ROOT/tools/lib/repo-arg-guard.sh")" "$tool")"

summary
