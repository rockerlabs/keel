#!/usr/bin/env bash
# tools/branch-cleanup.sh — classify local branches for post-merge cleanup (zero-dependency, network-free).
#
# The problem (backlog #25): after a PR merges, nothing prunes the local branch or its worktree, so they
# pile up (this repo hit 12 live worktrees, several sitting on already-merged branches). CORE.md's git rails
# promise "...merge -> delete the branch", but no command closed the loop.
#
# The design is a CONFIDENCE classifier (same shape as /polish step 4's review-depth gate): it reads only
# git facts and sorts each local branch into one tier, so the destructive decision is graded by how safe it
# provably is -- never a blanket delete.
#
#   AUTO   merged into origin/<default> AND not checked out in any worktree AND last commit >= --days old
#          AND the name matches an ephemeral glob (claude/*, feat/*, ...). Safe to delete unattended --
#          the tip is provably an ancestor of the default branch, so every commit survives there; the
#          local ref is a redundant pointer, recreatable from origin/<default>. Deletion loses nothing.
#   ASK    merged + free, but recent (< --days) OR an off-pattern name (could be long-lived like
#          staging / release-*). Surface for the human to confirm -- never auto-deleted.
#   FLAG   merged but checked out in a NON-current worktree. Never auto-removed (a worktree can hold
#          uncommitted or gitignored work -- e.g. a private/ draft); only reported with the manual command.
#   (skip) not merged (unmerged work OR a squash-merge, which is indistinguishable from active work without
#          gh -- left alone by design: zero-dep buys no false positives at the cost of not cleaning
#          squash-merged branches), the default branch itself, and the current branch / worktree.
#
# "merged" = the branch tip is reachable from origin/<default> (git for-each-ref --merged). This assumes
# a recent `git fetch --prune`; commands/wrap.md runs one in step 0 before calling this. The script itself
# does NO network and NO deletion in report mode, so it is safe to run and unit-test offline.
#
# Usage:
#   branch-cleanup.sh [--days N]               report AUTO/ASK/FLAG tiers; delete nothing (default)
#   branch-cleanup.sh --prune-safe [--days N]  delete the AUTO tier, then report ASK/FLAG
#   branch-cleanup.sh -h | --help
#
# Env: KEEL_CLEANUP_GLOBS overrides the ephemeral-name allowlist (space-separated globs).
#      KEEL_KEEP_WORKTREE=<path> names the worktree to never FLAG for removal (defaults to this run's own
#      worktree); a caller that reconciles from another dir exports it to protect the session's worktree.
#
# No bash arrays: macOS ships bash 3.2, where `${arr[@]}` under `set -u` on an empty array is an error;
# newline/TAB-delimited string accumulation is portable and just as clear at this size.
set -euo pipefail

usage() {
  cat <<'EOF'
branch-cleanup.sh — classify local branches for post-merge cleanup (zero-dep, network-free).

  branch-cleanup.sh [--days N]               report AUTO/ASK/FLAG tiers; delete nothing (default)
  branch-cleanup.sh --prune-safe [--days N]  delete the AUTO tier, then report ASK/FLAG
  branch-cleanup.sh -h | --help

AUTO = merged into origin/<default>, no worktree, >= N days old (default 7), ephemeral name -> safe to delete.
ASK  = merged + free but recent or off-pattern (maybe long-lived) -> confirm before deleting.
FLAG = merged but checked out in a worktree -> remove the worktree by hand.
Env: KEEL_CLEANUP_GLOBS  overrides the ephemeral-name allowlist (space-separated globs).
     KEEL_KEEP_WORKTREE  path of the worktree to never FLAG (default: this run's own worktree).
EOF
}

# -f (noglob): $GLOBS is word-split into case patterns below. Without it a pattern like `docs/*` would be
# pathname-expanded against the CWD (the keel checkout HAS a docs/ dir) — destroying the literal pattern so
# `docs/foo` never matches and misclassifies as ASK. Nothing here relies on filename globbing, so disabling
# it script-wide is safe (case-statement pattern matching is unaffected by -f).
set -f
DAYS=7
PRUNE=0
GLOBS="${KEEL_CLEANUP_GLOBS:-claude/* feat/* feature/* fix/* bugfix/* hotfix/* docs/* chore/* refactor/* test/*}"

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:-}"; shift 2 || shift ;;   # `|| shift` so a trailing `--days` doesn't abort under set -e
    --days=*) DAYS="${1#*=}"; shift ;;
    --prune-safe) PRUNE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'branch-cleanup: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
case "$DAYS" in ''|*[!0-9]*) printf 'branch-cleanup: --days must be a non-negative integer\n' >&2; exit 2 ;; esac

git rev-parse --git-dir >/dev/null 2>&1 || { printf 'branch-cleanup: not a git repository\n' >&2; exit 2; }

# Default branch: origin/HEAD's target, else main. Compare against the REMOTE default when it resolves
# (authoritative -- the merge lands there), else the local branch (offline / no remote, e.g. the tests).
# symbolic-ref (not `rev-parse --abbrev-ref origin/HEAD`, which prints "HEAD" + exits 128 with no remote --
# a pipefail landmine under set -e); an absent origin/HEAD just leaves default empty -> main.
default=""
if _ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"; then default="${_ref#refs/remotes/origin/}"; fi
[ -n "$default" ] || default=main
if git rev-parse --verify -q "origin/$default" >/dev/null 2>&1; then base="origin/$default"; else base="$default"; fi
git rev-parse --verify -q "$base" >/dev/null 2>&1 \
  || { printf 'branch-cleanup: no %s to compare against (fetch first?)\n' "$base" >&2; exit 0; }

# The one worktree we must never suggest removing: the one this run sits in (you can't `git worktree
# remove` your own CWD, and at wrap the session usually sits on an already-merged branch). Identify it by
# PATH, not branch name -- the old name check (`abbrev-ref HEAD`) compared the branch of the INVOKING cwd,
# so when the tool ran from a different dir than the session's worktree (e.g. wrap reconciling from the
# main checkout) the session's own worktree got FLAGged to remove itself. KEEL_KEEP_WORKTREE lets a caller
# that must cd away still name the worktree to protect (wrap exports it).
current_wt="${KEEL_KEEP_WORKTREE:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

# Branches checked out in ANY worktree -> "name<TAB>path", so FLAG can print the worktree to remove.
# The awk reads to EOF (no early exit -> no SIGPIPE), the felt -c-not-q discipline.
wt_branches="$(git worktree list --porcelain 2>/dev/null | awk '
  /^worktree /{p=$0; sub(/^worktree /,"",p)}
  /^branch refs\/heads\//{b=$0; sub(/^branch refs\/heads\//,"",b); print b "\t" p}' || true)"
# a branch's worktree path, empty if it isn't checked out anywhere (empty == "not in a worktree").
# Pure bash (here-string, no pipe) — no awk fork, and no early-`exit` SIGPIPE against $wt_branches.
wt_path_for() {
  local n p
  while IFS=$'\t' read -r n p; do
    [ "$n" = "$1" ] && { printf '%s\n' "$p"; return 0; }
  done <<<"$wt_branches"
  return 0   # no match: still succeed (the loop's trailing `read` fails at EOF -> would abort under set -e)
}

now="$(date +%s)"
auto=""; n_auto=0
ask="";  n_ask=0
flag=""; n_flag=0

# --merged="$base" does the "merged" gate in git itself (tip reachable from base — an unmerged or
# squash-merged branch is simply not listed), replacing a per-branch `git merge-base` fork. The committer
# date rides along free from the same call (a ref name can't contain a space, so `read b cd` splits
# cleanly) — no per-branch `git log` fork either. (`--merged` needs git >= 2.7, 2015; macOS/Alpine clear it.)
while read -r b cd; do
  [ "$b" = "$default" ] && continue                         # base is trivially merged into itself
  age=$(( (now - ${cd:-$now}) / 86400 ))
  wtp="$(wt_path_for "$b")"
  if [ -n "$wtp" ]; then                                    # checked out in a worktree
    [ "$wtp" -ef "$current_wt" ] && continue                # the worktree we're standing in -> never touch
    flag="${flag}${b}"$'\t'"${wtp}"$'\n'; n_flag=$((n_flag + 1))
    continue
  fi
  match=0
  # shellcheck disable=SC2254  # $g is INTENTIONALLY a glob here (claude/*, feat/*): we match the name against it
  for g in $GLOBS; do case "$b" in $g) match=1; break ;; esac; done
  if [ "$age" -ge "$DAYS" ] && [ "$match" -eq 1 ]; then
    auto="${auto}${b}"$'\t'"${age}"$'\n'; n_auto=$((n_auto + 1))
  else
    reason=recent; [ "$age" -ge "$DAYS" ] && reason=off-pattern
    ask="${ask}${b}"$'\t'"${age}"$'\t'"${reason}"$'\n'; n_ask=$((n_ask + 1))
  fi
done < <(git for-each-ref --merged="$base" --format='%(refname:short) %(committerdate:unix)' refs/heads/)

# --- act + report -------------------------------------------------------------------------------
deleted=0
if [ "$PRUNE" -eq 1 ]; then
  # in-shell (process substitution, not a pipe) so `deleted` survives the loop
  while IFS=$'\t' read -r b _age; do
    [ -n "$b" ] || continue
    # AUTO is proven an ancestor of $base above, so every commit survives there. -d first (belt); -D
    # fallback only because -d compares the branch against the current HEAD, not $base -- it would
    # false-refuse a branch merged into origin/<default> but not into whatever branch we happen to be on.
    if git branch -d "$b" >/dev/null 2>&1 || git branch -D "$b" >/dev/null 2>&1; then
      printf 'deleted  %-40s merged into %s\n' "$b" "$base"; deleted=$((deleted + 1))
    else
      printf 'FAILED   %-40s could not delete\n' "$b" >&2
    fi
  done < <(printf '%s' "$auto")
else
  while IFS=$'\t' read -r b age; do
    [ -n "$b" ] || continue
    printf 'AUTO  %-40s merged, %sd old\n' "$b" "$age"
  done < <(printf '%s' "$auto")
fi

while IFS=$'\t' read -r b age reason; do
  [ -n "$b" ] || continue
  printf 'ASK   %-40s merged, %sd old (%s)\n' "$b" "$age" "$reason"
done < <(printf '%s' "$ask")

while IFS=$'\t' read -r b path; do
  [ -n "$b" ] || continue
  printf 'FLAG  %-40s merged, in worktree %s  ->  git worktree remove %s\n' "$b" "$path" "$path"
done < <(printf '%s' "$flag")

if [ "$PRUNE" -eq 1 ]; then
  printf -- '--- %d deleted, %d to confirm (ASK), %d worktrees to review (FLAG)\n' "$deleted" "$n_ask" "$n_flag"
else
  printf -- '--- %d auto-safe, %d to confirm (ASK), %d worktrees to review (FLAG)\n' "$n_auto" "$n_ask" "$n_flag"
fi
