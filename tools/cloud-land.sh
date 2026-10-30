#!/usr/bin/env bash
# cloud-land.sh — adopter-usable: the model-free local landing check for a pull request a cloud session opened
# from a ticket tools/cloud-brief.sh dispatched (dir #900). For such a PR it stands in for the pre-PR gate,
# beside the session's own review, the VM's pre-push scans and CI; the rule is docs/cloud.md's landing section.
#
#   cloud-land.sh <repo> <PR#> [--ticket <id>]
#
# <repo> is any path inside the project; its `origin` names the GitHub repository, which must equal the ledger
# row's repo cell. The row is found by the PR's head branch, or by --ticket when the session pushed another
# branch (an exit 0 then corrects the row's branch cell). The scans are decided BEFORE CI is read, each with the
# scanner's inline allow marker off (SECRET_SCAN_NO_INLINE_ALLOW=1):
#   1. in a fresh full clone without tags (never the project's checkout), the fetched branch tip must equal the
#      PR's head SHA, and keel's scanner `--range refs/remotes/origin/<default>..refs/remotes/origin/<branch>`
#      must exit 0 (keys, personal literals, session trailers in commit messages) — it reads each blob the range
#      introduces whole, so a file the range changes refuses on a line already on <default> that only an inline
#      marker exempts (the default branch's .secret-scan-allow still applies);
#   2. the PR title + body must pass the scanner's file mode (from an empty directory) and a grep for a session
#      URL or a `-Session:` line, which file mode does not look for;
#   3. no line any commit in the range adds (its patch, read as text, uncolored, no textconv, the root commit's
#      included) and no line of any commit message in the range may carry the scanner's inline allow marker, read
#      in the scanner's decoded views (as is, NUL-stripped, each with its invalid UTF-8 dropped, and each blob decoded
#      as UTF-16/32 through textconv) — a grep that fails is a scan error.
# Then CI: every check in the rollup completed as a success, neutral or skipped (a commit status: a success), and
# at least one succeeded — so an empty or all-skipped rollup is not green.
#
# Exit: 0 scans clean and CI green · 1 a scan hit or a scan error · 2 usage, a gh failure, no ledger row, a
# repository mismatch, a PR whose base is not the default branch · 3 CI not green, or the branch moved after the
# PR was read. A run that found its row records its landing exit, head SHA and PR; only exit 0 also corrects the
# branch and sets the status to `landed` and the landed date — "the check passed at that head", not "merged". No
# merge without an exit 0 for the exact head SHA merged: the printed merge command pins it.
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

ENGINE="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
for lib in state-root repo-top safe-write leak-gate cloud; do
  [ -s "$ENGINE/tools/lib/$lib.sh" ] && bash -n "$ENGINE/tools/lib/$lib.sh" 2>/dev/null \
    || die 2 "$ENGINE/tools/lib/$lib.sh is missing or corrupted — re-clone or re-download Keel"
  # shellcheck source=/dev/null
  . "$ENGINE/tools/lib/$lib.sh"
done
cloud_absolutize_env || die 2 "cannot make the path variables absolute"

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
cloud_personal_file || die 2 "$CLOUD_ERR"

# --- the repository: <repo>'s origin ------------------------------------------------------------------------------
cloud_resolve_main "$REPO_ARG" || die 2 "$CLOUD_ERR"
ORIGIN_URL="$(git -C "$MAIN" config --get remote.origin.url 2>/dev/null || true)"
OR="$(cloud_github_slug "$ORIGIN_URL")" || die 2 "origin (${ORIGIN_URL:-none}) is not a github.com repository"
OWNER="${OR%%/*}"
DEFAULT="$(cloud_gh_api "repos/$OR" --jq .default_branch)" && [ -n "$DEFAULT" ] \
  || die 2 "gh api cannot read the default branch of $OR"

# --- the PR ---------------------------------------------------------------------------------------------------------
# Plain JSON whatever the caller's environment asks of gh: a forced TTY or forced color would colorize it.
PR_JSON="$(env -u GH_FORCE_TTY CLICOLOR_FORCE=0 NO_COLOR=1 \
  gh pr view "$PR" --repo "$OR" --json title,headRefName,baseRefName,body,statusCheckRollup,headRefOid)" \
  || die 2 "gh pr view $PR --repo $OR failed"
BRANCH="$(jq -r '.headRefName // ""' <<< "$PR_JSON")"
HEAD_OID="$(jq -r '.headRefOid // ""' <<< "$PR_JSON")"
BASE="$(jq -r '.baseRefName // ""' <<< "$PR_JSON")"
[ -n "$BRANCH" ] && [ -n "$HEAD_OID" ] || die 2 "PR $PR has no head branch or head SHA in gh's answer"
[ "$BASE" = "$DEFAULT" ] || die 2 "PR $PR targets '$BASE', not $OR's default branch $DEFAULT — the scans read the range against $DEFAULT"
cloud_cell_ok "$BRANCH" || die 2 "head branch '$BRANCH' cannot be a ledger cell"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die 2 "head branch '$BRANCH' is not a valid branch name"

# --- the ledger row: by --ticket, else by head branch; this repository's row first ----------------------------------
# Every key compare is a string compare (`x ""`): awk compares two numeric-looking strings as numbers, so ticket
# `2.1` would match a row `2.10`.
find_row() { # COLUMN VALUE → "<repo>\t<ticket>" of the matching row, this repository's first
  CL_C="$1" CL_V="$2" CL_R="$OR" awk -F'\t' '
    BEGIN { c = ENVIRON["CL_C"] + 0; v = ENVIRON["CL_V"] ""; r = ENVIRON["CL_R"] "" }
    NR > 1 && ($c "") == v { if (($2 "") == r) { print $2 "\t" $3; found = 1; exit } if (!other) other = $2 "\t" $3 }
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

finish() { # EXIT — record this run on the row, then exit; the branch, status and landed date only on exit 0 (B14)
  local cells=("12=$1" "13=$HEAD_OID" "14=$PR")
  [ "$1" -ne 0 ] || cells+=("4=$BRANCH" "8=landed" "11=$(date +%F)")
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
RANGE="refs/remotes/origin/$DEFAULT..refs/remotes/origin/$BRANCH"
# No tags (a tag named `origin/<branch>` would shadow the remote-tracking ref) and the remote pinned to `origin`
# (clone.defaultRemoteName); every ref below is spelled in full.
if ! git clone -q --no-tags -o origin "$CLONE_URL" "$CLONE" 2> "$WORK/clone.err" \
   || ! git -C "$CLONE" fetch -q --no-tags origin "+refs/heads/$DEFAULT:refs/remotes/origin/$DEFAULT" \
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

# report_scan LABEL RC OUTPUT — one scan's line; any non-zero exit fails the landing.
report_scan() {
  if [ "$2" -eq 0 ]; then echo "  $1: clean"; else echo "  $1: exit $2"; sed 's/^/    /' <<< "$3"; SCAN_FAIL=1; fi
}
rc=0
out="$(CDPATH='' cd -- "$CLONE" && SECRET_SCAN_NO_INLINE_ALLOW=1 bash "$SCANNER" --range "$RANGE" 2>&1)" || rc=$?
report_scan "range scan" "$rc" "$out"
# --range reads each blob the range introduces whole, so a line already on the default branch that only an inline
# marker exempts counts as soon as the range changes its file; the allowlist file is the exemption that holds here.
# Named only when a hit carries the marker: for a bare key or a trailer, an allowlist entry is never the remedy.
[ "$rc" -ne 1 ] || ! grep -qF 'secret-scan:allow' <<< "$out" \
  || echo "    (a hit above carries an inline allow marker, which exempts nothing here: if it is a fixture already on $DEFAULT, list it in $DEFAULT's .secret-scan-allow)"

jq -r '.title, "", (.body // "")' <<< "$PR_JSON" > "$WORK/pr-text.md"
rc=0
out="$(cloud_scan_file "$SCANNER" "$WORK/pr-text.md" "$WORK")" || rc=$?
report_scan "PR-text scan" "$rc" "$out"
if hits="$(grep -nE 'claude\.ai/code/session|-Session:' "$WORK/pr-text.md")"; then
  echo "  PR-text session grep: hit"; sed 's/^/    /' <<< "$hits"; SCAN_FAIL=1
else
  echo "  PR-text session grep: clean"
fi

# The scans above read with the marker off, but a marker that lands would exempt its line from every
# later local scan, so a PR that adds one never lands (the protocol forbids writing it). This reads
# every commit's patch (not the net diff: a line added then deleted still ships), as text,
# uncolored, with no diff driver or textconv, the root commit's included whatever the caller's log.showRoot, and
# every commit message. Every `+` line counts, the `+++` file headers included: a path carrying the marker refuses
# too (--no-renames: a renamed path shows as one). A merge commit's own changes are its dense combined diff (--cc),
# where a line new against every parent reads `++`; a line taken unchanged from one parent is not the merge's own
# and does not count. git's output goes to files and is grepped as bytes (LC_ALL=C -a): under a UTF-8 locale a
# byte that is not valid UTF-8 would stop `.*` short of the marker.
# range_log OUT ERR ARG… — `git log ARG… $RANGE` in the clone with the shared flags; stdout to OUT, stderr to ERR.
# With $VIEW_CMD set the patches are those of each blob converted by that command (git's textconv), not of its bytes.
range_log() {
  local out="$1" err="$2" tc=(--no-textconv) conf=(); shift 2
  if [ -n "${VIEW_CMD:-}" ]; then tc=(--textconv); conf=(-c "diff.keelview.textconv=$VIEW_CMD"); fi
  git -C "$CLONE" "${conf[@]}" -c log.showRoot=true log --root --no-color --no-ext-diff "${tc[@]}" --no-renames --text "$@" "$RANGE" \
    > "$out" 2> "$err"
}
# The scanner matches the inline marker in decoded views (NUL-stripped; `iconv -c` in the caller's locale, so a marker
# split by an invalid byte reads whole; UTF-16/32 decoded), and every later scan without the switch (pre-commit,
# pre-push, CI) honours what it finds. So the grep reads the same ones: the spool as it is, NUL-stripped (the marker
# is ASCII, so it survives that in any UTF-16/32 byte order), and each of those with its invalid UTF-8 dropped.
# utf8_clean IN OUT — IN with its invalid UTF-8 removed by `iconv -c`, padded with newlines first (a file ending in
# an incomplete sequence still converts whole). Where iconv is missing, fails, or stops at the first invalid unit
# (musl's does, and ignores -c), every byte >= 0x80 is dropped instead — a superset of iconv -c for an ASCII needle,
# so it can only refuse more.
iconv_resumes=""
command -v iconv >/dev/null 2>&1 && [ "$(printf 'a\377b\n' | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)" = ab ] && iconv_resumes=1
utf8_clean() {
  if [ -n "$iconv_resumes" ] && { cat "$1"; printf '\n\n\n\n'; } | iconv -c -f UTF-8 -t UTF-8 > "$2" 2>/dev/null; then
    return 0
  fi
  LC_ALL=C tr -d '\200-\377' < "$1" > "$2"
}
# marker_grep FILE ERE — the lines of FILE's views matching ERE, numbered and led by the view's name, on stdout;
# grep's status (≥ 2: it, or building a view, failed). FILE is grepped as bytes (LC_ALL=C -a).
marker_grep() {
  local f="$1" re="$2" rc=0 hits="" v out name
  LC_ALL=C tr -d '\000' < "$f" > "$f.nul" || return 2
  utf8_clean "$f" "$f.u8" || return 2
  utf8_clean "$f.nul" "$f.nul.u8" || return 2
  for v in "$f" "$f.nul" "$f.u8" "$f.nul.u8"; do
    name="${v#"$f"}"; name="${name#.}"
    out="$(LC_ALL=C grep -anE -e "$re" "$v")" || { rc=$?; [ "$rc" -le 1 ] || return "$rc"; rc=0; continue; }
    hits="${hits:+$hits$'\n'}$(sed "s/^/${name:-raw}: /" <<< "$out")"
  done
  [ -n "$hits" ] || return 1
  printf '%s\n' "$hits"
}
# The scanner also decodes a blob as UTF-16/UTF-32 (`iconv -c`, both byte orders; UTF-16 again from the blob's second
# byte), dropping an invalid unit whose bytes are not NUL, so a NUL-strip of the patch cannot rejoin a marker split by
# one. A patch is not one aligned stream, so git decodes each blob itself: textconv through an info/attributes entry
# (it beats the repository's own .gitattributes), once per decode, the patches of the converted blobs grepped.
# Where there is no iconv the scanner has no such decode either. conv_grep KIND ERE — the hits of every view of the
# KIND (patch|merge) spool; grep's status (≥ 2: something failed).
VIEWS=""
if command -v iconv >/dev/null 2>&1; then
  if mkdir -p "$CLONE/.git/info" && printf '* diff=keelview\n' > "$CLONE/.git/info/attributes"; then
    VIEWS="UTF-16LE:1 UTF-16BE:1 UTF-32LE:1 UTF-32BE:1 UTF-16LE:2 UTF-16BE:2"
  else
    echo "  scan error: cannot set up the decoded patch views"; SCAN_FAIL=1
  fi
fi
conv_grep() {
  local kind="$1" re="$2" spec enc skip sh out hits="" rc
  for spec in $VIEWS; do
    enc="${spec%:*}" skip="${spec#*:}" sh="$WORK/view-$enc-$skip.sh"
    printf '#!/bin/sh\ntail -c +%s "$1" | iconv -c -f %s -t UTF-8 2>/dev/null || true\n' "$skip" "$enc" > "$sh" || return 2
    case "$kind" in
      patch) VIEW_CMD="sh $sh" range_log "$WORK/$kind.$enc.$skip.out" "$WORK/$kind.err" -p --no-merges --format= || return 2 ;;
      *) VIEW_CMD="sh $sh" range_log "$WORK/$kind.$enc.$skip.out" "$WORK/$kind.err" -p --merges --cc --format= || return 2 ;;
    esac
    out="$(LC_ALL=C grep -anE -e "$re" "$WORK/$kind.$enc.$skip.out")" || { rc=$?; [ "$rc" -le 1 ] || return "$rc"; continue; }
    hits="${hits:+$hits$'\n'}$(sed "s/^/$enc+$skip: /" <<< "$out")"
  done
  [ -n "$hits" ] || return 1
  printf '%s\n' "$hits"
}
p_rc=0 m_rc=0 c_rc=0
if ! range_log "$WORK/patch.out" "$WORK/patch.err" -p --no-merges --format= \
   || ! range_log "$WORK/merge.out" "$WORK/merge.err" -p --merges --cc --format=; then
  echo "  scan error: cannot read the range's patches"; cat "$WORK/patch.err" "$WORK/merge.err" 2>/dev/null | sed 's/^/    /'
  SCAN_FAIL=1
else
  p_hits="$(marker_grep "$WORK/patch.out" '^\+.*secret-scan:allow')" || p_rc=$?
  m_hits="$(marker_grep "$WORK/merge.out" '^\+\+.*secret-scan:allow')" || m_rc=$?
  if [ "$p_rc" -le 1 ] && [ "$m_rc" -le 1 ]; then
    c_rc=0 cp_hits="" cm_hits=""
    cp_hits="$(conv_grep patch '^\+.*secret-scan:allow')" || c_rc=$?
    [ "$c_rc" -gt 1 ] || cm_hits="$(conv_grep merge '^\+\+.*secret-scan:allow')" || c_rc=$?
    [ "$c_rc" -le 1 ] || p_rc=$c_rc
    p_hits="$p_hits$cp_hits" m_hits="$m_hits$cm_hits"
  fi
  if [ "$p_rc" -gt 1 ] || [ "$m_rc" -gt 1 ]; then
    echo "  scan error: a marker grep failed over the range's patches (exit $p_rc, $m_rc)"; SCAN_FAIL=1
  elif [ -n "$p_hits$m_hits" ]; then
    echo "  added allow marker: hit"; printf '%s\n' "$p_hits" "$m_hits" | sed -e '/^$/d' -e 's/^/    /'; SCAN_FAIL=1
  else
    echo "  added allow marker: none"
  fi
fi
g_rc=0
if ! range_log "$WORK/msg.out" "$WORK/msg.err" --format=%B; then
  echo "  scan error: cannot read the range's commit messages"; sed 's/^/    /' "$WORK/msg.err"; SCAN_FAIL=1
else
  g_hits="$(marker_grep "$WORK/msg.out" 'secret-scan:allow')" || g_rc=$?
  if [ "$g_rc" -gt 1 ]; then
    echo "  scan error: a marker grep failed over the range's commit messages (exit $g_rc)"; SCAN_FAIL=1
  elif [ -n "$g_hits" ]; then
    echo "  allow marker in a commit message: hit"; sed 's/^/    /' <<< "$g_hits"; SCAN_FAIL=1
  else
    echo "  allow marker in a commit message: none"
  fi
fi

# --- CI ---------------------------------------------------------------------------------------------------------------
echo "== CI rollup"
jq -r '.statusCheckRollup[]? | "  \(.name // .context // "?"): \(.status // "-") \(.conclusion // .state // "-")"' <<< "$PR_JSON"
CI_GREEN=""
# Every check passed (a check run may also be neutral or skipped) and at least one succeeded — which also makes
# an empty rollup not green.
jq -e 'def status_context: .__typename == "StatusContext" or (has("state") and (has("status") | not));
       (.statusCheckRollup // []) as $r
       | ($r | all(if status_context then .state == "SUCCESS"
                   else .status == "COMPLETED" and ((.conclusion // "") | IN("SUCCESS", "NEUTRAL", "SKIPPED")) end))
         and ($r | any(if status_context then .state == "SUCCESS" else .conclusion == "SUCCESS" end))' \
  <<< "$PR_JSON" >/dev/null && CI_GREEN=1
if [ -n "$CI_GREEN" ]; then echo "  green"; else echo "  NOT green (a failing, pending or missing check, or none succeeded)"; fi

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
