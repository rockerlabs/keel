#!/usr/bin/env bash
# test_cloud_land.sh (dir #900) — tools/cloud-land.sh, the landing check for a cloud session's PR: the scans
# decided before CI, the head-SHA pin, the ledger row's update, the repository taken from <repo>'s origin and
# matched to the row, the default branch resolved through gh (spec docs/specs/900-cloud-ticket-routing.md, A4).
# Fixtures only: projects with bare origins (CLOUD_ORIGIN points the clone at them), a stub `gh`, a fixture
# ledger and personal list.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "cloud-land.sh (dir #900)"

LAND="$REPO_ROOT/tools/cloud-land.sh"
TOKEN="$(key ghp_ "$(rep A 36)")"
ALLOW_MARK="secret-scan:""allow"

gh_fixture_stub "$SANDBOX/bin"
export PATH="$SANDBOX/bin:$PATH"

LEDGER_HEADER="$(printf 'built\trepo\tticket\tbranch\tmodel/effort\tbrief bytes\tcredit before\tstatus\tcredit after\toverlap\tlanded\tlanding exit\thead SHA\tPR')"

# proj NAME OWNER/REPO DEFAULT — a project with a bare origin and a pushed cloud branch carrying one clean commit.
# Sets $P (its checkout), $O (its bare origin), $HEAD (the branch tip).
proj() {
  P="$F/$1" O="$F/$1-origin.git"
  mkdir -p "$P"
  git init -q -b "$3" "$P"
  printf 'readme\n' > "$P/README.md"
  git -C "$P" add README.md
  git -C "$P" commit -qm init
  git init -q --bare "$O"
  git -C "$P" remote add origin "https://github.com/$2.git"
  git -C "$P" push -q "$O" "HEAD:refs/heads/$3"
  git -C "$P" checkout -q -b claude/cloud-dir-801
  printf 'work\n' > "$P/work.txt"
  git -C "$P" add work.txt
  git -C "$P" commit -qm "cloud work"
  git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
  HEAD="$(git -C "$P" rev-parse HEAD)"
  git -C "$P" checkout -q "$3"
  local key; key="$(printf '%s' "repos/$2" | tr '/' '_')"
  mkdir -p "$GH_FX/api" "$GH_FX/pr"
  printf '{"default_branch":"%s"}\n' "$3" > "$GH_FX/api/$key.json"
}

# pr_json OWNER/REPO NUMBER BRANCH HEAD CI-JSON [BODY] [TITLE] [BASE] — the stub's `gh pr view` answer, the
# fields the tool requests (an empty BODY or TITLE takes the default; BASE defaults to main).
pr_json() {
  jq -n --arg b "$3" --arg h "$4" --argjson ci "$5" --arg body "${6:-Summary.

## Landing notes
- PR #$2 from $3
}" --arg t "${7:-Cloud work}" --arg base "${8:-main}" \
    '{title: $t, headRefName: $b, baseRefName: $base, body: $body, statusCheckRollup: $ci, headRefOid: $h}' \
    > "$GH_FX/pr/$(printf '%s' "$1" | tr '/' '_')-$2.json"
}
GREEN='[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]'
RED='[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]'
PENDING='[{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":null}]'
SKIPPED='[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SKIPPED"},{"__typename":"CheckRun","name":"b","status":"COMPLETED","conclusion":"SKIPPED"}]'
TRAILER="Claude-""Session"

# row REPO TICKET BRANCH STATUS — append a ledger row.
row() { printf '2026-10-27\t%s\t%s\t%s\tsonnet/high\t1000\t?\t%s\t\t\t\t\t\t\n' "$1" "$2" "$3" "$4" >> "$CLOUD_LEDGER"; }
# cell REPO TICKET N — print cell N of the row; set_cell REPO TICKET N VALUE — set it. String compares: a ticket
# `2.1` is not `2.10`.
cell() { awk -F'\t' -v r="$1" -v t="$2" -v n="$3" 'NR > 1 && ($2 "") == (r "") && ($3 "") == (t "") { print $n }' "$CLOUD_LEDGER"; }
set_cell() {
  awk -F'\t' -v OFS='\t' -v r="$1" -v t="$2" -v n="$3" -v val="$4" \
    'NR > 1 && ($2 "") == (r "") && ($3 "") == (t "") { $n = val } { print }' "$CLOUD_LEDGER" > "$CLOUD_LEDGER.new" \
    && mv "$CLOUD_LEDGER.new" "$CLOUD_LEDGER"
}

# bcommit FILE CONTENT MESSAGE — commit FILE (CONTENT) on $P's cloud branch and push it; sets $TIP to the new tip.
bcommit() {
  git -C "$P" checkout -q claude/cloud-dir-801
  printf '%s\n' "$2" > "$P/$1"
  git -C "$P" add "$1"
  git -C "$P" commit -qm "$3"
  git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
  TIP="$(git -C "$P" rev-parse HEAD)"
  git -C "$P" checkout -q main
}

fx() {
  F="$(mktemp -d "$SANDBOX/fx.XXXXXX")"; require_sandbox_path "$F" fx
  export GH_FX="$F/gh" CLOUD_LEDGER="$F/ledger.tsv" SECRET_SCAN_PERSONAL_FILE="$F/personal"
  mkdir -p "$GH_FX"
  printf 'zzfixturezz\n' > "$F/personal"
  printf '%s\n' "$LEDGER_HEADER" > "$CLOUD_LEDGER"
  proj proj example/proj main
  export CLOUD_ORIGIN="$O"
}

# --- exit 0: scans clean, CI green ---------------------------------------------------------------------------------
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 clean scans and green CI → exit 0" 0 "$STATUS"
check_eq "A4 exit 0 sets the row to landed" "landed" "$(cell example/proj 'dir #801' 8)"
check_eq "A4 … with the head SHA" "$HEAD" "$(cell example/proj 'dir #801' 13)"
check_eq "A4 … the landing exit" "0" "$(cell example/proj 'dir #801' 12)"
check_eq "A4 … the PR" "5" "$(cell example/proj 'dir #801' 14)"
check_contains "A4 the merge line pins the exact head" "$OUT" "gh pr merge 5 --repo example/proj --merge --match-head-commit $HEAD"
check_contains "A4 the ready line names the repo" "$OUT" "gh pr ready 5 --repo example/proj"
check_contains "A4 the Landing notes are shown" "$OUT" "- PR #5 from claude/cloud-dir-801"
check_contains "A4 the PR was read from the row's repository" "$(cat "$GH_FX/calls")" "pr view 5 --repo example/proj"

# A landed row re-run at a later head with CI red stays landed, its exit and head updated, its landed date kept.
set_cell example/proj 'dir #801' 11 2026-01-01
git -C "$P" checkout -q claude/cloud-dir-801
git -C "$P" commit -q --allow-empty -m "later"
git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
HEAD2="$(git -C "$P" rev-parse HEAD)"
git -C "$P" checkout -q main
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD2" "$RED"
run "$LAND" "$P" 5
check_status "A4 CI red → exit 3" 3 "$STATUS"
check_eq "A4 a landed row re-run with exit 3 stays landed" "landed" "$(cell example/proj 'dir #801' 8)"
check_eq "A4 … its landing exit is 3" "3" "$(cell example/proj 'dir #801' 12)"
check_eq "A4 … its head SHA is the new head" "$HEAD2" "$(cell example/proj 'dir #801' 13)"
check_eq "A4 … its landed date is the one exit 0 wrote" "2026-01-01" "$(cell example/proj 'dir #801' 11)"

# --- CI pending, head moved: exit 3, a dispatched row stays dispatched -------------------------------------------
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$PENDING"
run "$LAND" "$P" 5
check_status "A4 CI pending → exit 3" 3 "$STATUS"
check_eq "A4 a dispatched row stays dispatched on exit 3" "dispatched" "$(cell example/proj 'dir #801' 8)"
check_eq "A4 … its landing exit is 3" "3" "$(cell example/proj 'dir #801' 12)"
check_eq "A4 … its head SHA recorded" "$HEAD" "$(cell example/proj 'dir #801' 13)"
check_eq "A4 … no landed date on a non-zero exit" "" "$(cell example/proj 'dir #801' 11)"
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$SKIPPED"
run "$LAND" "$P" 5
check_status "A4 a rollup whose every check was skipped → exit 3" 3 "$STATUS"
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" '[]'
run "$LAND" "$P" 5
check_status "A4 an empty check rollup → exit 3" 3 "$STATUS"
pr_json example/proj 5 claude/cloud-dir-801 "0000000000000000000000000000000000000001" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 the head moved after the PR was read → exit 3" 3 "$STATUS"
check_contains "A4 … named" "$OUT" "the branch moved"

# --- scans ----------------------------------------------------------------------------------------------------------
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
git -C "$P" checkout -q claude/cloud-dir-801
printf 'key %s\n' "$TOKEN" > "$P/leak.txt"
git -C "$P" add leak.txt
git -C "$P" commit -qm leak
git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
git -C "$P" checkout -q main
pr_json example/proj 5 claude/cloud-dir-801 "$(git -C "$P" rev-parse claude/cloud-dir-801)" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 a token in the pushed range → exit 1" 1 "$STATUS"
check_eq "A4 … the row stays dispatched" "dispatched" "$(cell example/proj 'dir #801' 8)"
check_eq "A4 … its landing exit is 1" "1" "$(cell example/proj 'dir #801' 12)"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN" "Body with key $TOKEN"
run "$LAND" "$P" 5
check_status "A4 a token in the PR body → exit 1" 1 "$STATUS"
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN" "Body with key $TOKEN # $ALLOW_MARK"
run "$LAND" "$P" 5
check_status "A4 a token beside an allow marker in the PR body still refuses (defanged) → exit 1" 1 "$STATUS"
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN" "See https://claude.ai/code/session_01X for details"
run "$LAND" "$P" 5
check_status "A4 a session URL in the PR body → exit 1" 1 "$STATUS"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
git -C "$P" checkout -q claude/cloud-dir-801
printf 'harmless # %s\n' "$ALLOW_MARK" > "$P/marked.txt"
git -C "$P" add marked.txt
git -C "$P" commit -qm marked
git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
git -C "$P" checkout -q main
pr_json example/proj 5 claude/cloud-dir-801 "$(git -C "$P" rev-parse claude/cloud-dir-801)" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 an added allow marker → exit 1" 1 "$STATUS"
check_contains "A4 … named" "$OUT" "added allow marker: hit"

# The marker check reads every commit's patch and message, not the net diff.
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
bcommit hidden.txt "key $TOKEN # $ALLOW_MARK" "hide"
git -C "$P" checkout -q claude/cloud-dir-801
git -C "$P" rm -q hidden.txt
git -C "$P" commit -qm "unhide"
git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
git -C "$P" checkout -q main
pr_json example/proj 5 claude/cloud-dir-801 "$(git -C "$P" rev-parse claude/cloud-dir-801)" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 a marked token added in one commit and deleted in the next → exit 1" 1 "$STATUS"
check_contains "A4 … named" "$OUT" "added allow marker: hit"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
bcommit m.txt "plain" "Add m.txt

key $TOKEN # $ALLOW_MARK"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 a marked token on a commit-message line → exit 1" 1 "$STATUS"
check_contains "A4 … named" "$OUT" "allow marker in a commit message: hit"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
bcommit c.txt "key $TOKEN # $ALLOW_MARK" "colored"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
git config --global color.ui always
run "$LAND" "$P" 5
git config --global --unset color.ui
check_status "A4 an added marker under color.ui=always → exit 1" 1 "$STATUS"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
printf 'main moves\n' > "$P/main.txt"
git -C "$P" add main.txt
git -C "$P" commit -qm "main moves"
git -C "$P" push -q "$O" HEAD:refs/heads/main
git -C "$P" checkout -q claude/cloud-dir-801
git -C "$P" merge -q --no-ff --no-commit main
printf 'key %s # %s\n' "$TOKEN" "$ALLOW_MARK" > "$P/m.txt"
git -C "$P" add m.txt
git -C "$P" commit -qm "merge main"
git -C "$P" push -q "$O" HEAD:refs/heads/claude/cloud-dir-801
TIP="$(git -C "$P" rev-parse HEAD)"
git -C "$P" checkout -q main
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 an allow marker added only in a merge commit's resolution → exit 1" 1 "$STATUS"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
printf '*.dat -diff\n' > "$P/.gitattributes"
git -C "$P" add .gitattributes
git -C "$P" commit -qm attrs
git -C "$P" push -q "$O" HEAD:refs/heads/main
bcommit x.dat "key $TOKEN # $ALLOW_MARK" "data"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 an added marker in a file the default branch marks -diff → exit 1" 1 "$STATUS"

# A tag named like the remote-tracking branch cannot shadow the range.
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
git -C "$O" tag origin/claude/cloud-dir-801 main
bcommit leak.txt "key $TOKEN" "leak"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 a token in the range, a tag origin/<branch> at the default tip → exit 1" 1 "$STATUS"

# KB.172's T14 cases.
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
bcommit b.txt "two" "Add b.txt

$TRAILER: https://claude.ai/code/session_x"
bcommit c.txt "three" "Add c.txt"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 (T14) a session trailer in an interior commit → exit 1" 1 "$STATUS"
check_contains "A4 (T14) … the trailer line is named" "$OUT" "$TRAILER: https://claude.ai/code/session_x"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
bcommit owner.txt "owner zzfixturezz" "owner"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 (T14e) a commit adding the personal literal → exit 1" 1 "$STATUS"
pr_json example/proj 5 claude/cloud-dir-801 "$TIP" "$RED"
run "$LAND" "$P" 5
check_status "A4 (T14d) a scan hit and a failing check → exit 1 (scans first)" 1 "$STATUS"
check_eq "A4 (T14d) … the row records exit 1" "1" "$(cell example/proj 'dir #801' 12)"

fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN" "" "Fix it $TOKEN"
run "$LAND" "$P" 5
check_status "A4 (T14h) a ghp_ token in the PR title only → exit 1" 1 "$STATUS"
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN" "Summary.
$TRAILER: abc"
run "$LAND" "$P" 5
check_status "A4 (T14i) a body line '$TRAILER: abc' (no URL) → exit 1" 1 "$STATUS"

# --- the row: absent, by --ticket, the repository match -----------------------------------------------------------
fx
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 no ledger row → exit 2" 2 "$STATUS"
row example/proj "dir #801" claude/harness-named dispatched
run "$LAND" "$P" 5
check_status "A4 a row whose branch differs is not found by branch → exit 2" 2 "$STATUS"
run "$LAND" "$P" 5 --ticket "dir #801"
check_status "A4 --ticket binds a row whose branch cell differs → 0" 0 "$STATUS"
check_eq "A4 … and corrects its branch cell" "claude/cloud-dir-801" "$(cell example/proj 'dir #801' 4)"

# Ticket ids compare as strings: 2.1 is not 2.10.
fx
row example/proj 2.10 claude/other-210 dispatched
row example/proj 2.1 claude/harness-named dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN"
run "$LAND" "$P" 5 --ticket 2.1
check_status "A4 --ticket 2.1 with a 2.10 row above it → 0" 0 "$STATUS"
check_eq "A4 … binds 2.1's row" "claude/cloud-dir-801" "$(cell example/proj 2.1 4)"
check_eq "A4 … 2.10's row untouched" "claude/other-210 dispatched" "$(cell example/proj 2.10 4) $(cell example/proj 2.10 8)"

# The PR must target the default branch.
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN" "" "" release-1
run "$LAND" "$P" 5
check_status "A4 a PR whose base is not the default branch → exit 2" 2 "$STATUS"
check_contains "A4 … names the base" "$OUT" "release-1"
check_contains "A4 … and the default branch" "$OUT" "default branch main"

fx
row example/other "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN"
run "$LAND" "$P" 5
check_status "A4 a <repo> whose origin differs from the row's repo cell → exit 2" 2 "$STATUS"
check_contains "A4 … named" "$OUT" "is for example/other"

# Two rows for two repositories (the same ticket id in each) land independently.
fx
P1="$P" O1="$O" H1="$HEAD"
proj other example/other main
P2="$P" O2="$O" H2="$HEAD"
row example/proj "dir #801" claude/cloud-dir-801 dispatched
row example/other "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$H1" "$GREEN"
pr_json example/other 9 claude/cloud-dir-801 "$H2" "$GREEN"
CLOUD_ORIGIN="$O2" run "$LAND" "$P2" 9 --ticket "dir #801"
check_status "A4 the second repository's row lands" 0 "$STATUS"
check_eq "A4 … its row landed at its head" "$H2" "$(cell example/other 'dir #801' 13)"
check_eq "A4 … the first repository's row untouched" "dispatched" "$(cell example/proj 'dir #801' 8)"
check_contains "A4 … its merge line names its repository" "$OUT" "gh pr merge 9 --repo example/other --merge --match-head-commit $H2"
CLOUD_ORIGIN="$O1" run "$LAND" "$P1" 5
check_status "A4 the first repository's row lands on its own" 0 "$STATUS"
check_eq "A4 … at its own head" "$H1" "$(cell example/proj 'dir #801' 13)"

# A repository whose default branch is master.
fx
proj legacy example/legacy master
export CLOUD_ORIGIN="$O"
row example/legacy "dir #801" claude/cloud-dir-801 dispatched
pr_json example/legacy 3 claude/cloud-dir-801 "$HEAD" "$GREEN" "" "" master
run "$LAND" "$P" 3
check_status "A4 a default branch named master lands" 0 "$STATUS"
check_contains "A4 … the range is read against master" "$OUT" "range scan: clean"

# --- fail-closed personal list ---------------------------------------------------------------------------------------
fx
row example/proj "dir #801" claude/cloud-dir-801 dispatched
pr_json example/proj 5 claude/cloud-dir-801 "$HEAD" "$GREEN"
SECRET_SCAN_PERSONAL_FILE="$F/missing" run "$LAND" "$P" 5
check_status "A4 a personal list that is not a file → exit 2" 2 "$STATUS"

summary
