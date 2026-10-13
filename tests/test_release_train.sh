#!/usr/bin/env bash
# tools/self/release-train.sh (dir #811 slice S3, B9): the release train's build / body / check tool.
# One fixture repo (base `main`; b1 and b2 disjoint except the shared file `f` and CHANGELOG.md, which both
# edit on disjoint lines; b3 conflicts with b2 on `f`; b4 is disjoint from all; b2b descends from b2; after
# the branches are cut `main` advances by one commit, so a two-dot seam or an unexcluded CHANGELOG.md would
# show in the seam list). Covers: the clean build, the pairwise conflict exit with nothing created, the
# --allow-conflicts in-progress merge and the hand resolution, build --continue (order kept, not sorted),
# body (table, hand-resolved merges, integration commits between and after train merges, update-branch,
# placeholders, non-train refusal), check (a moved head, a missing N, the LAST line of a twice-merged N), and
# every refusal leaving the branch list, the worktree list and the caller's checkout exactly as they were.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="$REPO_ROOT/tools/self/release-train.sh"

# --- the fixture ---------------------------------------------------------------------------------
d="$(new_repo)"
gd() { git -C "$d" "$@"; }
printf '%s\n' l1 l2 l3 l4 l5 l6 l7 l8 l9 l10 > "$d/f"
printf '%s\n' '# Changelog' '' '- c1' '' '- c2' '' '- c3' '' '- c4' '' '- c5' '' '- c6' > "$d/CHANGELOG.md"
printf 'x\n' > "$d/README"
gd add -A
gd commit -q -m base

cut_branch() { gd checkout -q -b "$1" main; }
cut_branch b1
sed 's/^l2$/b1-l2/' "$d/f" > "$d/f.new"; cat "$d/f.new" > "$d/f"; rm "$d/f.new"
sed 's/^- c1$/- c1 by b1/' "$d/CHANGELOG.md" > "$d/c.new"; cat "$d/c.new" > "$d/CHANGELOG.md"; rm "$d/c.new"
printf 'one\n' > "$d/one.txt"
gd add -A; gd commit -q -m "b1: f, changelog, one"
cut_branch b2
sed 's/^l8$/b2-l8/' "$d/f" > "$d/f.new"; cat "$d/f.new" > "$d/f"; rm "$d/f.new"
sed 's/^- c6$/- c6 by b2/' "$d/CHANGELOG.md" > "$d/c.new"; cat "$d/c.new" > "$d/CHANGELOG.md"; rm "$d/c.new"
printf 'two\n' > "$d/two.txt"
gd add -A; gd commit -q -m "b2: f, changelog, two"
cut_branch b3
sed 's/^l8$/b3-l8/' "$d/f" > "$d/f.new"; cat "$d/f.new" > "$d/f"; rm "$d/f.new"
printf 'three\n' > "$d/three.txt"
gd add -A; gd commit -q -m "b3: f (conflicts with b2), three"
cut_branch b4
printf 'four\n' > "$d/four.txt"
gd add -A; gd commit -q -m "b4: four"
gd checkout -q b2
gd checkout -q -b b2b
printf 'two more\n' > "$d/two-more.txt"
gd add -A; gd commit -q -m "b2b: on top of b2"
gd checkout -q main
printf 'later\n' > "$d/later.txt"
gd add -A; gd commit -q -m "main moves on"

s1="$(gd rev-parse b1)"; s2="$(gd rev-parse b2)"; s3="$(gd rev-parse b3)"; s4="$(gd rev-parse b4)"; s2b="$(gd rev-parse b2b)"

# rt ARGS… → OUT/STATUS, run from the caller's checkout (the manager's cwd is the main checkout on `main`).
rt() { OUT="$(cd "$d" && bash "$tool" "$@" 2>&1 </dev/null)"; STATUS=$?; }
# fp WT BASE → the first-parent subjects past BASE, oldest first.
fp() { git -C "$1" log --first-parent --reverse --format=%s "$2..HEAD"; }
# caller_state — everything a build must not touch in the caller's checkout.
caller_state() { printf '%s|%s|%s|%s\n' "$(gd symbolic-ref HEAD)" "$(gd rev-parse HEAD)" "$(gd write-tree)" "$(gd status --porcelain --untracked-files=no)"; }
snap() { printf '%s\n--\n%s\n' "$(gd branch --list)" "$(gd worktree list)"; }
caller0="$(caller_state)"

# --- --help / bad arguments ----------------------------------------------------------------------
rt --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
rt
check_status "no arguments -> exit 2" 2 "$STATUS"
rt bogus
check_status "unknown command -> exit 2" 2 "$STATUS"
rt build --bogus --branch x "1=$s1" "2=$s2"
check_status "unknown flag -> exit 2" 2 "$STATUS"
rt body
check_status "body without --branch -> exit 2" 2 "$STATUS"
rt check --branch b1
check_status "check without constituents -> exit 2" 2 "$STATUS"

# --- refusals: exit 2, and nothing written (the E30 case among them) --------------------------------
mkdir -p "$SANDBOX/wt-busy"; printf 'x\n' > "$SANDBOX/wt-busy/file"
refused() {   # refused LABEL ARGS… — exit 2 with the branch list, the worktree list and the caller untouched
  local label="$1" before after; shift
  before="$(snap)"
  rt "$@"
  check_status "$label -> exit 2" 2 "$STATUS"
  after="$(snap)"
  check_eq "$label: branch list and worktree list identical" "$before" "$after"
  check_eq "$label: the caller's checkout untouched" "$caller0" "$(caller_state)"
}
refused "one constituent" build --branch t-one --base main "1=$s1"
refused "no constituent" build --branch t-none --base main
refused "an unknown sha" build --branch t-unk --base main "1=$s1" "2=0123456789abcdef0123456789abcdef01234567"
refused "a malformed constituent" build --branch t-bad --base main "1=$s1" "two"
refused "a duplicate N" build --branch t-dup --base main "1=$s1" "1=$s2"
refused "an existing branch" build --branch b4 --base main "1=$s1" "4=$s4"
refused "an existing non-empty worktree path" build --branch t-busy --base main --worktree "$SANDBOX/wt-busy" "1=$s1" "4=$s4"
refused "an unknown base" build --branch t-nobase --base no-such-ref "1=$s1" "4=$s4"
refused "a constituent already on the base" build --branch t-onbase --base main "1=$(gd rev-parse main)" "4=$s4"
refused "build without --branch" build --base main "1=$s1" "4=$s4"
check_absent "the busy path's branch was not left behind" "$(gd branch --list)" "t-busy"

# --- a conflicting pair: exit 1 naming the pair and the file, nothing created ---------------------------
before="$(snap)"
rt build --branch t-conf --base main "2=$s2" "3=$s3"
check_status "build of a conflicting pair -> exit 1" 1 "$STATUS"
check_contains "...names the pair" "$OUT" "#2 x #3"
check_contains "...and the file" "$OUT" " f"
check_eq "...no branch and no worktree created" "$before" "$(snap)"
check_eq "...the caller's checkout untouched" "$caller0" "$(caller_state)"

# --- the clean build (default worktree path) ------------------------------------------------------------
rt build --branch t1 --base main "1=$s1" "2=$s2"
check_status_out "build b1 b2 -> exit 0" 0
case "$OUT" in "worktree: "*) pass "the worktree path is the first line" ;; *) fail "the worktree path is the first line" "got: $(head -1 <<<"$OUT")" ;; esac
wt1="$(sed -n '1s/^worktree: //p' <<<"$OUT")"
case "$wt1" in */.claude/worktrees/t1) pass "the default worktree path is under .claude/worktrees/" ;; *) fail "the default worktree path is under .claude/worktrees/" "got $wt1" ;; esac
check_dir "...and the worktree exists" "$wt1"
check_eq "two first-parent merges named train: #N (sha)" "train: #1 ($s1)
train: #2 ($s2)" "$(fp "$wt1" main)"
gd merge-base --is-ancestor "$s1" t1 && gd merge-base --is-ancestor "$s2" t1 && pass "both heads are ancestors" || fail "both heads are ancestors" "lost"
check_eq "the seam list is exactly the shared file (no CHANGELOG.md, no main-only file)" "seam file: f" "$(match "$OUT" '^seam file: ')"
check_contains "integration count printed (0 at build)" "$OUT" "integration commits: 0"
check_eq "the new branch does not track origin/main (no upstream)" "" "$(gd config --get branch.t1.merge || true)"
check_eq "the caller's checkout untouched after a build" "$caller0" "$(caller_state)"
refused "build again on the existing branch" build --branch t1 --base main "1=$s1" "2=$s2"

# --- body of a clean train ----------------------------------------------------------------------------
rt body --branch t1 --base main
check_status_out "body -> exit 0" 0
check_contains "body: the table carries #1 and its sha verbatim" "$OUT" "| #1 | <fill> | $s1 |"
check_contains "body: the table carries #2 and its sha verbatim" "$OUT" "| #2 | <fill> | $s2 |"
check_contains "body: verification placeholder" "$OUT" "<fill>"
check_contains "body: integration commits none" "$OUT" "integration commits: 0"
check_absent "body: nothing resolved by hand" "$OUT" "resolved by hand"
check_contains "body: the merge-commit line" "$OUT" "Merge: create a merge commit"
check_contains "body: the title line" "$OUT" "land #1–#2 as one merge"
check_eq "body: the seam list" "seam file: f" "$(match "$OUT" '^seam file: ')"

# --- --allow-conflicts: stop IN PROGRESS at the first conflicting merge ---------------------------------
wt2="$SANDBOX/wt-t2"
rt build --branch t2 --base main --worktree "$wt2" --allow-conflicts "2=$s2" "3=$s3" "1=$s1"
check_status "build --allow-conflicts -> exit 1 after the #3 merge" 1 "$STATUS"
check_contains "...lists UU f" "$OUT" "UU f"
git -C "$wt2" rev-parse -q --verify MERGE_HEAD >/dev/null && pass "...MERGE_HEAD present in the worktree" || fail "...MERGE_HEAD present in the worktree" "no merge in progress"
check_eq "...the branch holds only train: #2" "train: #2 ($s2)" "$(fp "$wt2" main)"
rt build --continue --worktree "$wt2" --base main "1=$s1"
check_status "build --continue with an unresolved UU path -> exit 2" 2 "$STATUS"
check_eq "...nothing merged by the refusal" "train: #2 ($s2)" "$(fp "$wt2" main)"
# hand resolution: the later PR's conflict, resolved and committed under git's own message
printf '%s\n' l1 l2 l3 l4 l5 l6 l7 resolved-l8 l9 l10 > "$wt2/f"
git -C "$wt2" add f
git -C "$wt2" commit -q --no-edit
check_eq "a hand-resolved merge keeps the tool's subject" "train: #3 ($s3)" "$(git -C "$wt2" log -1 --format=%s)"
rt build --continue --worktree "$wt2" --base main "1=$s1"
check_status_out "build --continue -> exit 0" 0
check_eq "first-parent order is #2, #3, #1 (not sorted)" "train: #2 ($s2)
train: #3 ($s3)
train: #1 ($s1)" "$(fp "$wt2" main)"
check_eq "the printed seam list is still exactly the shared file" "seam file: f" "$(match "$OUT" '^seam file: ')"
check_contains "continue: the hand-resolved merge counts as an integration commit" "$OUT" "integration commits: 1"
rt body --branch t2 --base main
check_status_out "body of a hand-resolved train -> exit 0" 0
check_contains "body lists the #3 merge as resolved by hand" "$OUT" "resolved by hand: #3"
check_contains "...with its conflicting file" "$OUT" "conflicted files: f"
check_contains "body: integration count 1" "$OUT" "integration commits: 1"
check_contains "body: the pairwise result names the conflicting pair" "$OUT" "#2 x #3"
check_eq "body: three table rows" "3" "$(grep -c '^| #[0-9]* | <fill> | ' <<<"$OUT")"

# --- build --continue refusals ---------------------------------------------------------------------------
plain="$SANDBOX/wt-plain"
gd worktree add -q --no-track -b plain "$plain" main
rt build --continue --worktree "$plain" --base main "1=$s1"
check_status "build --continue on a plain-branch worktree (no train merge) -> exit 2" 2 "$STATUS"
check_eq "...and nothing was merged" "" "$(fp "$plain" main)"
rt build --continue --worktree "$SANDBOX/no-such-wt" --base main "1=$s1"
check_status "build --continue on a missing worktree -> exit 2" 2 "$STATUS"
rt build --continue --worktree "$wt1" --base main
check_status "build --continue with nothing to merge -> exit 2" 2 "$STATUS"
rt build --continue --worktree "$wt1" --base main "1=$s1"
check_status "build --continue of a head already in the train -> exit 2" 2 "$STATUS"

# --- integration commits: between two train merges, and trailing ----------------------------------------
wt3="$SANDBOX/wt-t3"
rt build --branch t3 --base main --worktree "$wt3" "1=$s1" "2=$s2"
check_status "t3 build -> exit 0" 0 "$STATUS"
printf 'fix\n' > "$wt3/fix.txt"; git -C "$wt3" add fix.txt; git -C "$wt3" commit -q -m "integration: fix the seam"
rt build --continue --worktree "$wt3" --base main "4=$s4"
check_status_out "continue after an integration commit -> exit 0" 0
rt body --branch t3 --base main
check_status_out "body with an integration commit between two train merges -> exit 0" 0
check_contains "...lists it" "$OUT" "integration: fix the seam"
check_contains "...counts it" "$OUT" "integration commits: 1"
printf 'tail\n' > "$wt3/tail.txt"; git -C "$wt3" add tail.txt; git -C "$wt3" commit -q -m "integration: trailing"
rt body --branch t3 --base main
check_status_out "body with a trailing non-train commit -> exit 0" 0
check_contains "...lists the trailing commit" "$OUT" "integration: trailing"
check_contains "...count 2" "$OUT" "integration commits: 2"

# --- a constituent merged twice (a B8g append): the LAST line decides ------------------------------------
rt build --continue --worktree "$wt3" --base main "2=$s2b"
check_status_out "appending a new head of #2 -> exit 0" 0
rt body --branch t3 --base main
check_contains "body: #2 carries its LAST sha" "$OUT" "| #2 | <fill> | $s2b |"
check_absent "body: #2's first sha is gone from the table" "$OUT" "| #2 | <fill> | $s2 |"
check_eq "body: one row per PR (#1, #2, #4)" "3" "$(grep -c '^| #[0-9]* | <fill> | ' <<<"$OUT")"
rt check --branch t3 "2=$s2b" "1=$s1" "4=$s4"
check_status_out "check with the live shas -> exit 0" 0
rt check --branch t3 "2=$s2"
check_status "check with a moved head (the first sha of #2) -> exit 1" 1 "$STATUS"
check_contains "...naming #2" "$OUT" "#2"
rt check --branch t3 "9=$s1"
check_status "check with an N not in the train -> exit 1" 1 "$STATUS"
check_contains "...naming #9" "$OUT" "#9"
rt check --branch no-such-branch "1=$s1"
check_status "check on an unknown branch -> exit 2" 2 "$STATUS"

# --- update-branch: a merge of `main` is listed, not counted --------------------------------------------
wt5="$SANDBOX/wt-t5"
rt build --branch t5 --base main --worktree "$wt5" "1=$s1" "4=$s4"
check_status "t5 build -> exit 0" 0 "$STATUS"
printf 'later2\n' > "$d/later2.txt"; gd add later2.txt; gd commit -q -m "main moves again"
caller0="$(caller_state)"   # the fixture itself moved main; the baseline moves with it
git -C "$wt5" merge -q --no-ff -m "Merge branch 'main' into t5" main
rt body --branch t5 --base main
check_status_out "body of a train with an update-branch merge -> exit 0" 0
check_contains "...lists it as update-branch (not reviewed)" "$OUT" "update-branch (not reviewed)"
check_contains "...and does not count it as an integration commit" "$OUT" "integration commits: 0"

# --- body of a non-train branch ----------------------------------------------------------------------------
rt body --branch b1 --base main
check_status "body on a non-train branch -> exit 2" 2 "$STATUS"
rt body --branch plain --base main
check_status "body on a branch with no commits past the base -> exit 2" 2 "$STATUS"
rt body --branch no-such-branch --base main
check_status "body on an unknown branch -> exit 2" 2 "$STATUS"

# --- an existing EMPTY directory is accepted (git does), a non-empty one was refused above -----------------
mkdir -p "$SANDBOX/wt-empty"
rt build --branch t6 --base main --worktree "$SANDBOX/wt-empty" "1=$s1" "4=$s4"
check_status_out "build into an existing empty directory -> exit 0" 0

check_eq "the caller's checkout untouched through the rest of the run (HEAD, branch, index)" "$caller0" "$(caller_state)"
summary
