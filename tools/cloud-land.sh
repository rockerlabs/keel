#!/usr/bin/env bash
# cloud-land.sh — adopter-usable: the model-free local landing check for a pull request a cloud session opened
# from a ticket tools/cloud-brief.sh dispatched (dir #900). For such a PR it stands in for the pre-PR gate,
# beside the session's own review, the VM's pre-push scans and CI; the rule is docs/cloud.md's landing section.
#
#   cloud-land.sh <repo> <PR#> [--ticket <id>]
#
# <repo> is any path inside the project; its `origin` names the GitHub repository, which must equal the ledger
# row's repo cell. The row is found by the PR's head branch, or by --ticket when the session pushed another
# branch (the row's branch cell is then corrected). The scans are decided BEFORE CI is read:
#   1. in a fresh full clone (never the project's checkout), the fetched branch tip must equal the PR's head SHA,
#      and keel's scanner `--range origin/<default>..origin/<branch>` must exit 0 (keys, personal literals,
#      session trailers in commit messages);
#   2. the PR title + body must pass the scanner's file mode (marker defanged, from an empty directory) and a
#      grep for a session URL or a `-Session:` line, which file mode does not look for;
#   3. no added line in the range may carry the scanner's inline allow marker.
# Then CI: a non-empty check rollup, every check completed and successful.
#
# Exit: 0 scans clean and CI green · 1 a scan hit or a scan error · 2 usage, a gh failure, no ledger row, a
# repository mismatch · 3 CI not green, or the branch moved after the PR was read. A run that found its row
# records its landing exit, head SHA and PR; only exit 0 sets the status to `landed` — "the check passed at
# that head", not "merged". No merge without an exit 0 for the exact head SHA merged: the printed merge
# command pins it.
#
# Env (relative values are made absolute against the start directory): CLOUD_LEDGER
# ($(keel_store_root cloud)/ledger.tsv) · CLOUD_ORIGIN (unset: https://github.com/<repo cell>.git; tests point it
# at a bare repo) · SECRET_SCAN_PERSONAL_FILE (the scanner's default; fail-closed as in cloud-brief.sh).
set -uo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

START_DIR="$PWD"
abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$START_DIR" "$1" ;; esac; }
die() { local code="$1"; shift; printf 'cloud-land: %s\n' "$*" >&2; exit "$code"; }

ENGINE="$(cd "$(dirname "$0")/.." && pwd -P)"
for lib in backlog-blocks state-root cloud; do
  [ -f "$ENGINE/tools/lib/$lib.sh" ] || die 2 "no $ENGINE/tools/lib/$lib.sh"
  # shellcheck source=/dev/null
  . "$ENGINE/tools/lib/$lib.sh"
done

usage() { die 2 "usage: cloud-land.sh <repo> <PR#> [--ticket <id>]"; }
REPO_ARG="" PR="" TICKET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ticket) [ $# -ge 2 ] || usage; TICKET="$2"; shift ;;
    -*) usage ;;
    *) if [ -z "$REPO_ARG" ]; then REPO_ARG="$1"; elif [ -z "$PR" ]; then PR="$1"; else usage; fi ;;
  esac
  shift
done
[ -n "$REPO_ARG" ] || usage
case "$PR" in ''|*[!0-9]*) usage ;; esac
cloud_cell_ok "$TICKET" || usage

if [ -z "${CLOUD_LEDGER:-}" ]; then
  CLOUD_LEDGER="$(keel_store_root cloud)/ledger.tsv" || die 2 "no state root: HOME is unset"
fi
CLOUD_LEDGER="$(abs "$CLOUD_LEDGER")"
SCANNER="$ENGINE/tools/secret-guard/secret-scan.sh"
[ -f "$CLOUD_LEDGER" ] || die 2 "no ledger at $CLOUD_LEDGER"
[ -f "$SCANNER" ] || die 2 "no scanner at $SCANNER"
cloud_personal_file || die 2 "no personal-literals list at $SECRET_SCAN_PERSONAL_FILE — the scan fails closed; set SECRET_SCAN_PERSONAL_FILE to your list (or to /dev/null to opt out)"

# --- the repository: <repo>'s origin ------------------------------------------------------------------------------
[ -d "$REPO_ARG" ] || die 2 "no directory $REPO_ARG"
REPO_DIR="$(cd "$REPO_ARG" && pwd -P)" || die 2 "cannot enter $REPO_ARG"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || die 2 "$REPO_DIR is not inside a git repository"
MAIN="$(backlog_root_for "$REPO_DIR")"
ORIGIN_URL="$(git -C "$MAIN" config --get remote.origin.url 2>/dev/null || true)"
OR="$(cloud_github_slug "$ORIGIN_URL")" || die 2 "origin (${ORIGIN_URL:-none}) is not a github.com repository"
OWNER="${OR%%/*}"
DEFAULT="$(cloud_gh_api "repos/$OR" --jq .default_branch)" && [ -n "$DEFAULT" ] \
  || die 2 "gh api cannot read the default branch of $OR"

# --- the PR ---------------------------------------------------------------------------------------------------------
PR_JSON="$(gh pr view "$PR" --repo "$OR" --json number,title,headRefName,isDraft,body,statusCheckRollup,headRefOid)" \
  || die 2 "gh pr view $PR --repo $OR failed"
BRANCH="$(jq -r '.headRefName // ""' <<< "$PR_JSON")"
HEAD_OID="$(jq -r '.headRefOid // ""' <<< "$PR_JSON")"
[ -n "$BRANCH" ] && [ -n "$HEAD_OID" ] || die 2 "PR $PR has no head branch or head SHA in gh's answer"
cloud_cell_ok "$BRANCH" || die 2 "head branch '$BRANCH' cannot be a ledger cell"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die 2 "head branch '$BRANCH' is not a valid branch name"

# --- the ledger row: by --ticket, else by head branch; this repository's row first ----------------------------------
find_row() { # COLUMN VALUE → "<repo>\t<ticket>" of the matching row, this repository's first
  CL_C="$1" CL_V="$2" CL_R="$OR" awk -F'\t' '
    BEGIN { c = ENVIRON["CL_C"] + 0; v = ENVIRON["CL_V"]; r = ENVIRON["CL_R"] }
    NR > 1 && $c == v { if ($2 == r) { print $2 "\t" $3; found = 1; exit } if (!other) other = $2 "\t" $3 }
    END { if (!found && other) print other }' "$CLOUD_LEDGER"
}
if [ -n "$TICKET" ]; then
  KEY="$(find_row 3 "$TICKET")"
  [ -n "$KEY" ] || die 2 "no ledger row for ticket $TICKET in $CLOUD_LEDGER"
else
  KEY="$(find_row 4 "$BRANCH")"
  [ -n "$KEY" ] || die 2 "no ledger row for branch $BRANCH in $CLOUD_LEDGER — pass --ticket <id> if the session pushed another branch"
fi
ROW_REPO="${KEY%%$'\t'*}" ROW_TICKET="${KEY#*$'\t'}"
[ "$ROW_REPO" = "$OR" ] || die 2 "the ledger row for ${TICKET:-$BRANCH} is for $ROW_REPO, but $MAIN's origin is $OR"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cloud-land.XXXXXX")" || die 2 "mktemp failed"
trap 'rm -rf "$WORK"' EXIT

finish() { # EXIT — record this run on the row, then exit
  local cells=("4=$BRANCH" "11=$(date +%F)" "12=$1" "13=$HEAD_OID" "14=$PR")
  [ "$1" -ne 0 ] || cells+=("8=landed")
  if cloud_ledger_lock "$CLOUD_LEDGER"; then
    cloud_ledger_set "$CLOUD_LEDGER" "$OR" "$ROW_TICKET" "${cells[@]}" || echo "cloud-land: cannot update the ledger row" >&2
    cloud_ledger_unlock "$CLOUD_LEDGER"
  else
    echo "cloud-land: the ledger row was not updated" >&2
  fi
  exit "$1"
}

# --- scans, decided before CI -------------------------------------------------------------------------------------
echo "== scans ($OR PR #$PR, $BRANCH @ $HEAD_OID)"
CLONE_URL="${CLOUD_ORIGIN:-https://github.com/$OR.git}"
case "$CLONE_URL" in *://*|*@*:*) ;; *) CLONE_URL="$(abs "$CLONE_URL")" ;; esac
SCAN_FAIL=""
CLONE="$WORK/clone"
if ! git clone -q "$CLONE_URL" "$CLONE" 2> "$WORK/clone.err" \
   || ! git -C "$CLONE" fetch -q origin "+refs/heads/$DEFAULT:refs/remotes/origin/$DEFAULT" \
        "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>> "$WORK/clone.err"; then
  sed 's/^/  /' "$WORK/clone.err"
  echo "  scan error: cannot clone $CLONE_URL or fetch $DEFAULT and $BRANCH"
  finish 1
fi
TIP="$(git -C "$CLONE" rev-parse "refs/remotes/origin/$BRANCH")"
if [ "$TIP" != "$HEAD_OID" ]; then
  echo "  the branch moved: fetched tip $TIP, PR head $HEAD_OID — re-run once the PR settles"
  finish 3
fi
# Check out the default branch, so the working tree's allowlist is its trusted copy (the scanner reads it there).
git -C "$CLONE" checkout -q --detach "refs/remotes/origin/$DEFAULT" 2>/dev/null \
  || { echo "  scan error: cannot check out origin/$DEFAULT"; finish 1; }

rc=0
out="$(cd "$CLONE" && bash "$SCANNER" --range "origin/$DEFAULT..origin/$BRANCH" 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then echo "  range scan: clean"; else echo "  range scan: exit $rc"; sed 's/^/    /' <<< "$out"; SCAN_FAIL=1; fi

jq -r '.title, "", (.body // "")' <<< "$PR_JSON" > "$WORK/pr-text.md"
mkdir "$WORK/empty"
sed 's/secret-scan:allow/secret-scan-allow-stripped/g' "$WORK/pr-text.md" > "$WORK/pr-text.scan.md"
rc=0
out="$(cd "$WORK/empty" && bash "$SCANNER" -- "$WORK/pr-text.scan.md" 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then echo "  PR-text scan: clean"; else echo "  PR-text scan: exit $rc"; sed 's/^/    /' <<< "$out"; SCAN_FAIL=1; fi
if hits="$(grep -nE 'claude\.ai/code/session|-Session:' "$WORK/pr-text.md")"; then
  echo "  PR-text session grep: hit"; sed 's/^/    /' <<< "$hits"; SCAN_FAIL=1
else
  echo "  PR-text session grep: clean"
fi

# A marker added in the range would hide its own line from the range scan. Every `+` line counts, the `+++` file
# headers included: a path carrying the marker refuses too.
if ! diff_out="$(git -C "$CLONE" diff "refs/remotes/origin/$DEFAULT...refs/remotes/origin/$BRANCH" 2>&1)"; then
  echo "  scan error: cannot diff the range"; sed 's/^/    /' <<< "$diff_out"; SCAN_FAIL=1
elif hits="$(grep -nE '^\+.*secret-scan:allow' <<< "$diff_out")"; then
  echo "  added allow marker: hit"; sed 's/^/    /' <<< "$hits"; SCAN_FAIL=1
else
  echo "  added allow marker: none"
fi

# --- CI ---------------------------------------------------------------------------------------------------------------
echo "== CI rollup"
jq -r '.statusCheckRollup[]? | "  \(.name // .context // "?"): \(.status // "-") \(.conclusion // .state // "-")"' <<< "$PR_JSON"
CI_GREEN=""
jq -e '(.statusCheckRollup // []) as $r | ($r | length) > 0 and ($r | all(
         if .__typename == "StatusContext" or (has("state") and (has("status") | not))
         then .state == "SUCCESS"
         else .status == "COMPLETED" and ((.conclusion // "") | IN("SUCCESS", "NEUTRAL", "SKIPPED"))
         end))' <<< "$PR_JSON" >/dev/null && CI_GREEN=1
if [ -n "$CI_GREEN" ]; then echo "  green"; else echo "  NOT green (a failing, pending or missing check)"; fi

echo "== Landing notes"
notes="$(jq -r '.body // ""' <<< "$PR_JSON" | awk '/^## Landing notes[[:space:]]*$/ {f = 1; print; next} f && /^## / {exit} f')"
if [ -n "$notes" ]; then printf '%s\n' "$notes"; else echo "  (none — the PR body has no '## Landing notes' section; the cloud protocol asks for one)"; fi

echo "== Override"
echo "  A cloud PR's pre-PR gate is this check plus the session's review, the VM's scans and CI — not the local"
echo "  pre-PR flow (docs/cloud.md, the landing section). The operator merges."

if [ -n "$SCAN_FAIL" ]; then
  echo "== REFUSED: a scan hit or a scan error. Do not merge; nothing pushed can be unpublished — fix forward on the branch."
  finish 1
fi
if [ -z "$CI_GREEN" ]; then
  echo "== CI not green. Steer the cloud session (its web view, or \`claude --cloud <session id>\` from a terminal), then re-run this check."
  finish 3
fi
cat <<NEXT
== Next ($OWNER's default branch: $DEFAULT)
  1. write the claim's closure from the Landing notes, persist the learnings, and do any step marked unverified
     there, locally;
  2. gh pr ready $PR --repo $OR
  3. gh pr merge $PR --repo $OR --merge --match-head-commit $HEAD_OID
     (refused if anything was pushed after this run, an "Update branch" click included — then re-run this check)
NEXT
finish 0
