#!/usr/bin/env bash
# tools/self/release-train.sh — keel-self-maintenance (dir #68): the release train's build, body and check as
# one deterministic tool instead of hand-typed git and a hand-typed SHA table (dir #811 slice S3, spec B9). A
# train is one branch that merges N ready PRs' frozen heads `--no-ff`, so a single merge commit on `main`
# puts every constituent head on `main` and closes each PR as merged. This file is for keel's own release
# managers; install.sh never ships it. Git only: no `gh`, never a push (the manager's `gh` reads feed `check`).
#
# Usage:
#   tools/self/release-train.sh build --branch NAME [--base origin/main] [--worktree PATH] [--allow-conflicts] N=SHA N=SHA …
#   tools/self/release-train.sh build --continue --worktree PATH [--base origin/main] [--allow-conflicts] N=SHA …
#   tools/self/release-train.sh body  --branch NAME [--base origin/main]
#   tools/self/release-train.sh check --branch NAME [--base origin/main] N=SHA …
#   tools/self/release-train.sh -h | --help
# Every command also takes `--repo DIR` (default: the current directory) — a git directory of the repository
# whose branches and objects the train lives in; `build --continue` works inside the given worktree instead.
#
# build   Creates its own worktree (`git worktree add --no-track -b NAME PATH BASE`; PATH defaults to
#         `<main checkout>/.claude/worktrees/NAME`, with `/` in NAME written as `-`) and runs every git command
#         there with `-C`, so the caller's checkout, branch and index are never touched. The refusals below run
#         BEFORE any git write — `git worktree add -b` on an existing path creates the branch and then fails.
#         Then: a pairwise `git merge-tree --write-tree --name-only` over every pair of constituent heads (a
#         conflicting pair → exit 1 naming the pair and the files, nothing created, unless --allow-conflicts);
#         each head merged `--no-ff` in the GIVEN order (never sorted) with the message `train: #N (SHA)` (the
#         full 40-hex sha); an ancestor check of every constituent; the seam list (files in ≥ 2 constituents'
#         `git diff --name-only BASE...SHA` sets — the three-dot form, CHANGELOG.md excluded); and the integration
#         commit count. With --allow-conflicts (or a conflict only the sequence exposes) the FIRST conflicting
#         merge is left IN PROGRESS (MERGE_HEAD, the UU paths printed) and the tool exits 1: no second merge is
#         possible until the resolver commits it. Git completes it under the tool's own `train: #N (SHA)`
#         subject, so a hand-resolved merge IS an integration commit by definition.
# build --continue   Merges the remaining constituents onto the existing train in the worktree, in the given
#         order. A constituent already in the train may be given again with a new head that descends from
#         the old one (a push on top: the LAST `train: #N` line decides). Refuses a worktree with unresolved
#         paths or a merge still in progress, and one with no `train: #N` first-parent merge past BASE.
# body    Prints the train PR body from the first-parent walk `git merge-base BASE BRANCH`..BRANCH: the title,
#         the constituent table (from the `train: #N (SHA)` subjects, never retyped; a PR merged twice takes
#         its LAST line), the pairwise result, the seam list, every integration commit wherever it sits
#         (a train merge whose two parents `merge-tree` to a conflict is "resolved by hand"; a merge whose
#         second parent is an ancestor of BASE — `gh pr update-branch` — is "update-branch (not reviewed)" and
#         is not counted), and `<fill>` placeholders for what only the train worker can state.
# check   Exit 1 naming each constituent whose LAST merged sha differs from the given live sha, or that is not
#         in the train (B8g's input is the manager's `gh pr view --json headRefOid` read). Without --base the
#         whole first-parent history is read when `origin/main` does not exist.
#
# Every run prints each step. Exit codes: 0 done · 1 a conflict, a lost ancestor, a moved head · 2 refused,
# changing nothing (a bad argument, an existing branch, a non-empty worktree path, a sha not present locally —
# `git fetch --prune origin` first —, fewer than 2 constituents, a branch that is not a train).
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

export LC_ALL=C
export GIT_MERGE_AUTOEDIT=no

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/repo-top.sh
. "$self_dir/../lib/repo-top.sh"

usage() {
  cat <<'EOF'
Usage:
  release-train.sh build --branch NAME [--base origin/main] [--worktree PATH] [--allow-conflicts] N=SHA N=SHA ...
  release-train.sh build --continue --worktree PATH [--base origin/main] [--allow-conflicts] N=SHA ...
  release-train.sh body  --branch NAME [--base origin/main]
  release-train.sh check --branch NAME [--base origin/main] N=SHA ...
  release-train.sh -h | --help
Every command also takes --repo DIR (default: the current directory).
Exit codes: 0 done · 1 a conflict, a lost ancestor, a moved head · 2 refused (nothing written).
EOF
}

say() { printf '%s\n' "$*"; }
refuse() { printf 'release-train: refused: %s\n' "$*" >&2; exit 2; }

# --- arguments -----------------------------------------------------------------------------------------------
cmd="${1:-}"
[ -n "$cmd" ] || { usage >&2; exit 2; }
shift
case "$cmd" in
  -h|--help) usage; exit 0 ;;
  build|body|check) ;;
  *) usage >&2; refuse "unknown command '$cmd'" ;;
esac

repo="."; branch=""; base=""; wt=""; allow=0; cont=0
ARGS=()
set_opt() {
  case "$1" in
    --repo) repo="$2" ;;
    --branch) branch="$2" ;;
    --base) base="$2" ;;
    --worktree) wt="$2" ;;
  esac
}
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --repo|--branch|--base|--worktree)
      [ $# -ge 2 ] || refuse "$1 needs a value"
      set_opt "$1" "$2"; shift 2 ;;
    --repo=*|--branch=*|--base=*|--worktree=*) set_opt "${1%%=*}" "${1#*=}"; shift ;;
    --allow-conflicts) allow=1; shift ;;
    --continue) cont=1; shift ;;
    -*) refuse "unknown flag '$1'" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
if [ "$cont" -eq 1 ] && [ "$cmd" != build ]; then refuse "--continue belongs to build"; fi
if [ "$allow" -eq 1 ] && [ "$cmd" != build ]; then refuse "--allow-conflicts belongs to build"; fi
if [ -n "$wt" ] && [ "$cmd" != build ]; then refuse "--worktree belongs to build"; fi

abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
# canon_path P — P absolute with symlinks resolved through its nearest existing ancestor (git lists worktrees by
# their real path, so a /var vs /private/var spelling must not hide a registered one).
canon_path() {
  local p tail=""
  p="$(abs_path "$1")"
  p="${p%/}"
  while [ -n "$p" ] && [ ! -d "$p" ]; do tail="/${p##*/}$tail"; p="${p%/*}"; done
  p="$(cd -P "${p:-/}" && pwd -P)"
  printf '%s%s' "${p%/}" "$tail"
}

# For `build --continue` the repository IS the worktree (its branch, its objects).
if [ "$cont" -eq 1 ]; then
  [ -n "$wt" ] || refuse "build --continue needs --worktree PATH"
  wt="$(abs_path "$wt")"
  [ -d "$wt" ] || refuse "worktree $wt is not a directory"
  repo="$wt"
fi
[ -d "$repo" ] || refuse "--repo $repo is not a directory"
repo="$(cd "$repo" && pwd)"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || refuse "$repo is not a git repository"

# --- constituents --------------------------------------------------------------------------------------------
NS=(); SHAS=()
# add_constituent N=SHA RESOLVE — RESOLVE=1: the sha must be a commit present locally (full name stored).
add_constituent() {
  local arg="$1" resolve="$2" n s i full
  case "$arg" in
    [0-9]*=[0-9a-fA-F]*) ;;
    *) refuse "constituent '$arg' is not N=SHA" ;;
  esac
  n="${arg%%=*}"; s="${arg#*=}"
  case "$n" in *[!0-9]*) refuse "constituent '$arg': N is not a number" ;; esac
  case "$s" in *[!0-9a-fA-F]*) refuse "constituent '$arg': SHA is not hex" ;; esac
  [ "${#n}" -le 9 ] || refuse "constituent '$arg': N is too long"
  [ "${#s}" -ge 7 ] && [ "${#s}" -le 40 ] || refuse "constituent '$arg': SHA must be 7 to 40 hex digits"
  n=$((10#$n))
  s="$(printf '%s' "$s" | tr 'A-F' 'a-f')"
  if [ "$resolve" -eq 1 ]; then
    full="$(git -C "$repo" rev-parse --verify --quiet "${s}^{commit}" 2>/dev/null)" ||
      refuse "#$n: sha $s is not present locally (run 'git fetch --prune origin' first)"
    s="$full"
  else
    full="$(git -C "$repo" rev-parse --verify --quiet "${s}^{commit}" 2>/dev/null)" || full=""
    [ -z "$full" ] || s="$full"
  fi
  i=0
  while [ "$i" -lt "${#NS[@]}" ]; do
    if [ "${NS[$i]}" = "$n" ]; then
      refuse "#$n is given twice (a PR joins a train once; a moved head is appended later with build --continue)"
    fi
    i=$((i + 1))
  done
  NS+=("$n"); SHAS+=("$s")
}

# --- git helpers ---------------------------------------------------------------------------------------------
# mt_names A B — prints the conflicting paths of merging A and B; rc 0 clean, 1 conflict, 2 merge-tree failed.
mt_names() {
  local out rc=0
  out="$(git -C "$repo" merge-tree --write-tree --name-only "$1" "$2" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) awk 'NR == 1 { next } $0 == "" { exit } { print }' <<<"$out"; return 1 ;;
    *) return 2 ;;
  esac
}

# pairwise — over NS/SHAS: sets PW_PAIRS and PW_CONFLICTS (one "#a x #b: files" line per conflicting pair).
PW_PAIRS=0; PW_CONFLICTS=""
pairwise() {
  local i j rc names
  PW_PAIRS=0; PW_CONFLICTS=""
  i=0
  while [ "$i" -lt "${#SHAS[@]}" ]; do
    j=$((i + 1))
    while [ "$j" -lt "${#SHAS[@]}" ]; do
      PW_PAIRS=$((PW_PAIRS + 1))
      rc=0
      names="$(mt_names "${SHAS[$i]}" "${SHAS[$j]}")" || rc=$?
      if [ "$rc" -eq 1 ]; then
        PW_CONFLICTS="${PW_CONFLICTS}conflict: #${NS[$i]} x #${NS[$j]}: $(tr '\n' ' ' <<<"$names" | sed 's/ *$//')"$'\n'
      elif [ "$rc" -ne 0 ]; then
        PW_CONFLICTS="${PW_CONFLICTS}conflict: #${NS[$i]} x #${NS[$j]}: (git merge-tree --write-tree failed: git >= 2.38 is needed, or the histories are unrelated)"$'\n'
      fi
      j=$((j + 1))
    done
    i=$((i + 1))
  done
}

# seam_files BASE SHA… — paths in at least two constituents' `BASE...SHA` name sets, CHANGELOG.md excluded.
seam_files() {
  local b="$1" s; shift
  for s in "$@"; do
    git -C "$repo" -c core.quotePath=false diff --name-only "$b...$s"
  done | awk '$0 != "CHANGELOG.md"' | sort | uniq -c | awk '$1 >= 2 { sub(/^ *[0-9]+ /, ""); print }'
}

# unmerged_paths DIR — `git status --porcelain` lines of unresolved paths (UU, AA, DD, AU, UA, DU, UD).
unmerged_paths() {
  git -C "$1" status --porcelain | awk '$1 ~ /^(UU|AA|DD|AU|UA|DU|UD)$/'
}
merge_in_progress() { git -C "$1" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; }

# analyze BASE BRANCH — read the train's first-parent walk into globals:
#   T_N / T_SHA   one entry per PR, in order of first appearance, carrying its LAST merged sha
#   I_LINES       the integration commits, in walk order (hand-resolved merges included); I_COUNT their number
#   U_LINES       update-branch merges (listed, never counted)
#   HEAD_SHA      the branch tip
# Refuses (exit 2) a branch that is not a train: its first first-parent commit past the base must be a
# `train: #N (SHA)` merge whose second parent is that sha.
T_N=(); T_SHA=(); I_LINES=(); U_LINES=(); I_COUNT=0; HEAD_SHA=""
analyze() {
  local b="$1" br="$2" mb walk h parents subj p1 p2 p3 n s i idx first=1 rc names re valid
  T_N=(); T_SHA=(); I_LINES=(); U_LINES=(); I_COUNT=0
  re='^train: #([0-9]+) \(([0-9a-f]{40})\)$'
  git -C "$repo" rev-parse --verify --quiet "${br}^{commit}" >/dev/null 2>&1 || refuse "branch $br does not exist"
  git -C "$repo" rev-parse --verify --quiet "${b}^{commit}" >/dev/null 2>&1 || refuse "base $b does not exist"
  mb="$(git -C "$repo" merge-base "$b" "$br" 2>/dev/null)" || refuse "no merge base between $b and $br"
  HEAD_SHA="$(git -C "$repo" rev-parse "${br}^{commit}")"
  walk="$(git -C "$repo" log --first-parent --reverse --format='%H%x1f%P%x1f%s' "$mb..$br")"
  [ -n "$walk" ] || refuse "$br is not a train: no commits past $b"
  while IFS=$'\x1f' read -r h parents subj; do
    p1=""; p2=""; p3=""
    read -r p1 p2 p3 <<<"$parents" || true
    valid=0
    if [[ $subj =~ $re ]] && [ -n "$p2" ] && [ -z "$p3" ] && [ "${BASH_REMATCH[2]}" = "$p2" ]; then
      valid=1
      n=$((10#${BASH_REMATCH[1]})); s="${BASH_REMATCH[2]}"
    fi
    if [ "$first" -eq 1 ] && [ "$valid" -eq 0 ]; then
      refuse "$br is not a train: its first first-parent commit past $b is '${subj}', not a 'train: #N (sha)' merge"
    fi
    first=0
    if [ "$valid" -eq 1 ]; then
      idx=-1; i=0
      while [ "$i" -lt "${#T_N[@]}" ]; do
        if [ "${T_N[$i]}" = "$n" ]; then idx=$i; fi
        i=$((i + 1))
      done
      if [ "$idx" -ge 0 ]; then T_SHA[$idx]="$s"; else T_N+=("$n"); T_SHA+=("$s"); fi
      rc=0
      names="$(mt_names "$p1" "$p2")" || rc=$?
      if [ "$rc" -eq 1 ]; then
        I_LINES+=("resolved by hand: #$n ($s) — conflicted files: $(tr '\n' ' ' <<<"$names" | sed 's/ *$//')")
        I_COUNT=$((I_COUNT + 1))
      elif [ "$rc" -ne 0 ]; then
        I_LINES+=("train merge #$n ($s): git merge-tree failed on its parents — treated as an integration commit")
        I_COUNT=$((I_COUNT + 1))
      fi
    elif [ -n "$p2" ] && [ -z "$p3" ] && git -C "$repo" merge-base --is-ancestor "$p2" "$b" 2>/dev/null; then
      U_LINES+=("update-branch (not reviewed): ${h:0:12} $subj")
    else
      I_LINES+=("${h:0:12} $subj")
      I_COUNT=$((I_COUNT + 1))
    fi
  done <<<"$walk"
}

# verify_ancestors BRANCH — every constituent of the analyzed train must be an ancestor of the branch tip;
# prints one line per step and returns the number of lost heads.
verify_ancestors() {
  local br="$1" i=0 lost=0
  while [ "$i" -lt "${#T_N[@]}" ]; do
    if git -C "$repo" merge-base --is-ancestor "${T_SHA[$i]}" "$br"; then
      say "ancestor ok: #${T_N[$i]} (${T_SHA[$i]})"
    else
      say "LOST ancestor: #${T_N[$i]} (${T_SHA[$i]}) is not an ancestor of $br"
      lost=$((lost + 1))
    fi
    i=$((i + 1))
  done
  return "$lost"
}

print_seam() {   # BASE
  local f count=0 out
  out="$(seam_files "$1" "${T_SHA[@]}")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    say "seam file: $f"
    count=$((count + 1))
  done <<<"$out"
  say "seam files: $count (touched by >= 2 constituents; CHANGELOG.md excluded)"
}

# --- build ---------------------------------------------------------------------------------------------------
# merge_all WT — merge NS/SHAS into the worktree in order; on a conflict leave it in progress and exit 1.
merge_all() {
  local w="$1" i=0 msg out rest
  while [ "$i" -lt "${#SHAS[@]}" ]; do
    msg="train: #${NS[$i]} (${SHAS[$i]})"
    say "merge: #${NS[$i]} (${SHAS[$i]})"
    if out="$(git -C "$w" merge --no-ff -m "$msg" "${SHAS[$i]}" 2>&1)"; then
      [ "$(git -C "$w" log -1 --format=%s)" = "$msg" ] || {
        say "release-train: merging #${NS[$i]} made no merge commit (already contained?): $out"; exit 1; }
    else
      if merge_in_progress "$w"; then
        say "CONFLICT merging #${NS[$i]} (${SHAS[$i]}) — left IN PROGRESS in $w:"
        unmerged_paths "$w" | while IFS= read -r line; do say "  $line"; done
        rest=""
        i=$((i + 1))
        while [ "$i" -lt "${#SHAS[@]}" ]; do rest="$rest #${NS[$i]}=${SHAS[$i]}"; i=$((i + 1)); done
        say "resolve and commit it there (git completes it under the subject 'train: #N (sha)'), then:"
        say "  release-train.sh build --continue --worktree $w${rest:+ }${rest# }"
        exit 1
      fi
      say "release-train: git merge of #${NS[$i]} failed without a conflict: $out"
      exit 1
    fi
    i=$((i + 1))
  done
}

cmd_build() {
  local b="${base:-origin/main}" i a main_co name wtabs registered cur tip lost names rc out
  if [ "$cont" -eq 1 ]; then
    cur="$(git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null)" || refuse "worktree $wt is on a detached HEAD"
    [ -z "$branch" ] || [ "$branch" = "$cur" ] || refuse "--branch $branch is not the branch checked out in $wt ($cur)"
    branch="$cur"
    for a in ${ARGS[@]+"${ARGS[@]}"}; do add_constituent "$a" 1; done
    [ "${#NS[@]}" -ge 1 ] || refuse "build --continue needs at least one N=SHA to merge"
    git -C "$repo" rev-parse --verify --quiet "${b}^{commit}" >/dev/null 2>&1 || refuse "base $b does not exist"
    merge_in_progress "$wt" && refuse "a merge is still in progress in $wt — resolve and commit it first"
    [ -z "$(unmerged_paths "$wt")" ] || refuse "unresolved paths in $wt: $(unmerged_paths "$wt" | tr '\n' ';')"
    analyze "$b" "$branch"   # refuses a branch with no train merge
    i=0
    while [ "$i" -lt "${#SHAS[@]}" ]; do
      git -C "$repo" merge-base --is-ancestor "${SHAS[$i]}" HEAD 2>/dev/null &&
        refuse "#${NS[$i]} (${SHAS[$i]}) is already an ancestor of the train head"
      i=$((i + 1))
    done
    say "continue: $branch in $wt (${#NS[@]} to merge, base $b)"
    pairwise
    if [ -n "$PW_CONFLICTS" ] && [ "$allow" -eq 0 ]; then
      printf '%s' "$PW_CONFLICTS"
      say "release-train: conflicting pair(s) among the new constituents — nothing merged (--allow-conflicts to go on)"
      exit 1
    fi
    [ -z "$PW_CONFLICTS" ] || printf '%s' "$PW_CONFLICTS"
    i=0
    while [ "$i" -lt "${#SHAS[@]}" ]; do
      names=""; rc=0
      names="$(mt_names HEAD "${SHAS[$i]}")" || rc=$?
      if [ "$rc" -eq 1 ] && [ "$allow" -eq 0 ]; then
        say "conflict: train head x #${NS[$i]}: $(tr '\n' ' ' <<<"$names" | sed 's/ *$//')"
        say "release-train: #${NS[$i]} conflicts with the train head — nothing merged (--allow-conflicts to go on)"
        exit 1
      fi
      i=$((i + 1))
    done
    merge_all "$wt"
  else
    [ -n "$branch" ] || refuse "build needs --branch NAME"
    git -C "$repo" check-ref-format --branch "$branch" >/dev/null 2>&1 || refuse "'$branch' is not a valid branch name"
    for a in ${ARGS[@]+"${ARGS[@]}"}; do add_constituent "$a" 1; done
    [ "${#NS[@]}" -ge 2 ] || refuse "a train needs at least 2 constituents (one ready PR merges alone)"
    git -C "$repo" rev-parse --verify --quiet "${b}^{commit}" >/dev/null 2>&1 || refuse "base $b does not exist"
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then refuse "branch $branch already exists"; fi
    if [ -z "$wt" ]; then
      main_co="$(keel_repo_top "$repo")"
      [ -n "$main_co" ] || refuse "cannot find the main checkout of $repo"
      name="${branch//\//-}"
      wt="$main_co/.claude/worktrees/$name"
    fi
    wtabs="$(canon_path "$wt")"
    registered="$(git -C "$repo" worktree list --porcelain | awk '$1 == "worktree" { sub(/^worktree /, ""); print }')"
    if grep -qxF -- "$wtabs" <<<"$registered"; then refuse "worktree path $wtabs is already a registered worktree"; fi
    if [ -e "$wtabs" ]; then
      [ -d "$wtabs" ] || refuse "worktree path $wtabs exists and is not a directory"
      [ -z "$(ls -A "$wtabs")" ] || refuse "worktree path $wtabs exists and is not empty"
    fi
    i=0
    while [ "$i" -lt "${#SHAS[@]}" ]; do
      git -C "$repo" merge-base --is-ancestor "${SHAS[$i]}" "$b" 2>/dev/null &&
        refuse "#${NS[$i]} (${SHAS[$i]}) is already an ancestor of $b — it needs no train"
      i=$((i + 1))
    done
    say "worktree: $wtabs"
    say "train: $branch off $b with ${#NS[@]} constituents"
    pairwise
    if [ -n "$PW_CONFLICTS" ]; then
      printf '%s' "$PW_CONFLICTS"
      if [ "$allow" -eq 0 ]; then
        say "release-train: conflicting pair(s) — no branch and no worktree created (the later PR's worker rebases, or --allow-conflicts)"
        exit 1
      fi
      say "conflicts allowed (--allow-conflicts): going on, the first conflicting merge will be left in progress"
    else
      say "pairwise: $PW_PAIRS pair(s), none conflicting"
    fi
    if ! out="$(git -C "$repo" worktree add --no-track -b "$branch" "$wtabs" "$b" 2>&1)"; then
      say "release-train: git worktree add failed for $wtabs: $out"
      exit 1
    fi
    say "created: branch $branch at $(git -C "$wtabs" rev-parse --short HEAD) in $wtabs"
    wt="$wtabs"
    merge_all "$wt"
  fi
  say "merges done: ${#NS[@]}"
  repo="$wt"
  analyze "$b" "$branch"
  lost=0
  verify_ancestors "$branch" || lost=$?
  if [ "$lost" -gt 0 ]; then
    say "release-train: $lost constituent head(s) lost from the train"
    exit 1
  fi
  tip="$(git -C "$wt" rev-parse HEAD)"
  say "train head: $tip"
  print_seam "$b"
  say "integration commits: $I_COUNT"
}

# --- body ----------------------------------------------------------------------------------------------------
cmd_body() {
  local b="${base:-origin/main}" i lost=0 l rng_lo rng_hi
  [ -n "$branch" ] || refuse "body needs --branch NAME"
  [ "${#ARGS[@]}" -eq 0 ] || refuse "body takes no constituents (they are read from the branch)"
  analyze "$b" "$branch"
  NS=("${T_N[@]}"); SHAS=("${T_SHA[@]}")
  pairwise
  rng_lo="${T_N[0]}"; rng_hi="${T_N[0]}"
  for l in "${T_N[@]}"; do
    [ "$l" -lt "$rng_lo" ] && rng_lo="$l"
    [ "$l" -gt "$rng_hi" ] && rng_hi="$l"
  done
  say "Suggested title: <fill version> train <fill k>: land #${rng_lo}–#${rng_hi} as one merge"
  say ""
  say "## Constituents"
  say ""
  say "| PR | Ticket | Frozen head |"
  say "|---|---|---|"
  i=0
  while [ "$i" -lt "${#T_N[@]}" ]; do
    say "| #${T_N[$i]} | <fill> | ${T_SHA[$i]} |"
    i=$((i + 1))
  done
  say ""
  say "## Pairwise merge check"
  say ""
  if [ -z "$PW_CONFLICTS" ]; then
    say "pairwise: $PW_PAIRS pair(s) of constituent heads merge clean (git merge-tree --write-tree)"
  else
    say "pairwise: $PW_PAIRS pair(s); conflicting:"
    printf '%s' "$PW_CONFLICTS"
  fi
  say ""
  say "## Seam"
  say ""
  print_seam "$b"
  say ""
  say "## Integration commits"
  say ""
  say "integration commits: $I_COUNT"
  if [ "$I_COUNT" -eq 0 ]; then say "none"; fi
  for l in ${I_LINES[@]+"${I_LINES[@]}"}; do say "- $l"; done
  for l in ${U_LINES[@]+"${U_LINES[@]}"}; do say "- $l"; done
  say ""
  say "## Verification at $HEAD_SHA"
  say ""
  say "- full suite: <fill>"
  say "- shellcheck -x --severity=warning over every changed .sh: <fill>"
  say "- Alpine leg: <fill>"
  verify_ancestors "$branch" >/dev/null || lost=$?
  if [ "$lost" -eq 0 ]; then
    say "- ancestor check: all ${#T_N[@]} constituent heads are ancestors of $HEAD_SHA"
  else
    say "- ancestor check: LOST $lost constituent head(s) — rebuild"
  fi
  say ""
  say "## Review disclosure"
  say ""
  say "- level: <fill>"
  say "- read: <fill>"
  say "- not read: <fill>"
  say ""
  say "Merge: create a merge commit — only a merge commit puts the constituent heads on \`main\` and closes each PR as merged"
  [ "$lost" -eq 0 ] || exit 1
}

# --- check ---------------------------------------------------------------------------------------------------
cmd_check() {
  local b="${base:-origin/main}" range walk h parents subj re n s i j a seen bad=0 want have
  [ -n "$branch" ] || refuse "check needs --branch NAME"
  for a in ${ARGS[@]+"${ARGS[@]}"}; do add_constituent "$a" 0; done
  [ "${#NS[@]}" -ge 1 ] || refuse "check needs at least one N=SHA"
  git -C "$repo" rev-parse --verify --quiet "${branch}^{commit}" >/dev/null 2>&1 || refuse "branch $branch does not exist"
  range="$branch"
  if git -C "$repo" rev-parse --verify --quiet "${b}^{commit}" >/dev/null 2>&1; then
    range="$(git -C "$repo" merge-base "$b" "$branch")..$branch"
  elif [ -n "$base" ]; then
    refuse "base $b does not exist"
  fi
  re='^train: #([0-9]+) \(([0-9a-f]{40})\)$'
  walk="$(git -C "$repo" log --first-parent --format='%H%x1f%P%x1f%s' "$range")"
  T_N=(); T_SHA=()
  # newest first: the first line seen for an N is its LAST merge
  while IFS=$'\x1f' read -r h parents subj; do
    [[ $subj =~ $re ]] || continue
    n=$((10#${BASH_REMATCH[1]})); s="${BASH_REMATCH[2]}"
    seen=0; j=0
    while [ "$j" -lt "${#T_N[@]}" ]; do
      if [ "${T_N[$j]}" = "$n" ]; then seen=1; fi
      j=$((j + 1))
    done
    if [ "$seen" -eq 0 ]; then T_N+=("$n"); T_SHA+=("$s"); fi
  done <<<"$walk"
  i=0
  while [ "$i" -lt "${#NS[@]}" ]; do
    want="${SHAS[$i]}"; have=""; j=0
    while [ "$j" -lt "${#T_N[@]}" ]; do
      if [ "${T_N[$j]}" = "${NS[$i]}" ]; then have="${T_SHA[$j]}"; fi
      j=$((j + 1))
    done
    if [ -z "$have" ]; then
      say "missing: #${NS[$i]} is not in the train $branch"
      bad=$((bad + 1))
    elif [ "$have" != "$want" ]; then
      say "moved: #${NS[$i]} — the train merged $have, the live head is $want"
      bad=$((bad + 1))
    else
      say "ok: #${NS[$i]} ($want)"
    fi
    i=$((i + 1))
  done
  if [ "$bad" -gt 0 ]; then
    say "release-train: $bad constituent(s) moved or missing"
    exit 1
  fi
}

case "$cmd" in
  build) cmd_build ;;
  body) cmd_body ;;
  check) cmd_check ;;
esac
