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
#   AUTO   merged into origin/<default> AND last commit >= --days old AND the name matches an ephemeral
#          glob (claude/*, feat/*, ...). A FREE branch is deleted (its tip is provably an ancestor of the
#          default branch, so every commit survives there; the ref is a redundant pointer). A branch in a
#          WORKTREE also qualifies IF the worktree is provably safe to drop — clean of tracked/untracked
#          work AND holding no gitignored content of value (see worktree_state); it is removed via
#          `git worktree remove` (no --force) and its branch deleted. Either way, removal loses nothing.
#   ASK    merged but not provably safe unattended: a free branch that's recent (< --days) or off-pattern
#          (maybe long-lived like staging / release-*), OR a clean worktree that's recent/off-pattern/holds
#          non-disposable gitignored content. Surfaced with the manual command -- never auto-removed.
#   FLAG   merged worktree with LIVE work — either uncommitted/untracked-non-ignored files (so `git worktree
#          remove` would refuse without --force), OR clean but with a file (or the .git link file) touched
#          within --live-hours: a worktree merged TODAY can be a parallel session still mid-wrap (ledger/
#          backlog writes land AFTER the merge), not a stale leftover -- see backlog #51. Reported WITHOUT a
#          destructive command (forcing it would discard that work, or race a live session); the human
#          reviews first. This is the genuinely-alive case, not mere presence.
#   (skip) not merged (unmerged work OR a squash-merge, which is indistinguishable from active work without
#          gh -- left alone by design: zero-dep buys no false positives at the cost of not cleaning
#          squash-merged branches), the default branch itself, and the current branch / worktree.
#
# "merged" = the branch tip is reachable from origin/<default> (git for-each-ref --merged). This assumes
# a recent `git fetch --prune`; commands/wrap.md runs one in step 0 before calling this. The script itself
# does NO network and NO deletion in report mode, so it is safe to run and unit-test offline.
#
# Usage:
#   branch-cleanup.sh [--days N] [--live-hours N]  report AUTO/ASK/FLAG tiers; delete nothing (default)
#   branch-cleanup.sh --prune-safe [--days N]      delete the AUTO tier, then report ASK/FLAG
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

  branch-cleanup.sh [--days N] [--live-hours N]  report AUTO/ASK/FLAG tiers; delete nothing (default)
  branch-cleanup.sh --prune-safe [--days N]      delete/remove the AUTO tier, then report ASK/FLAG
  branch-cleanup.sh -h | --help

AUTO = merged + >= N days old (default 7) + ephemeral name. A free branch is deleted; a worktree that is
       also clean + holds no gitignored content of value is removed (git worktree remove, no --force) + its
       branch deleted. Nothing of value is lost.
ASK  = merged but not provably safe: recent/off-pattern free branch, or a clean worktree that's
       recent/off-pattern/holds non-disposable ignored content -> confirm before removing.
FLAG = merged worktree with live work -> reported for review, no destructive command. Either uncommitted/
       untracked files, or (clean) a file touched within --live-hours (default 6) -- possibly a parallel
       session still mid-wrap, not a stale leftover.
Env: KEEL_CLEANUP_GLOBS  overrides the ephemeral-name allowlist (space-separated globs).
     KEEL_KEEP_WORKTREE  path of the worktree to never touch (default: this run's own worktree).
EOF
}

# -f (noglob): $GLOBS is word-split into case patterns below. Without it a pattern like `docs/*` would be
# pathname-expanded against the CWD (the keel checkout HAS a docs/ dir) — destroying the literal pattern so
# `docs/foo` never matches and misclassifies as ASK. Nothing here relies on filename globbing, so disabling
# it script-wide is safe (case-statement pattern matching is unaffected by -f).
set -f
DAYS=7
LIVE_HOURS=6
PRUNE=0
GLOBS="${KEEL_CLEANUP_GLOBS:-claude/* feat/* feature/* fix/* bugfix/* hotfix/* docs/* chore/* refactor/* test/*}"

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:-}"; shift 2 || shift ;;   # `|| shift` so a trailing `--days` doesn't abort under set -e
    --days=*) DAYS="${1#*=}"; shift ;;
    --live-hours) LIVE_HOURS="${2:-}"; shift 2 || shift ;;
    --live-hours=*) LIVE_HOURS="${1#*=}"; shift ;;
    --prune-safe) PRUNE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'branch-cleanup: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
require_nonneg_int() {
  case "$2" in ''|*[!0-9]*) printf 'branch-cleanup: %s must be a non-negative integer\n' "$1" >&2; exit 2 ;; esac
}
require_nonneg_int --days "$DAYS"
require_nonneg_int --live-hours "$LIVE_HOURS"

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

# Classify a worktree by how provably safe removing it is (no network, no deletion). `git worktree remove`
# without --force is the built-in safety net for TRACKED work: it refuses on any uncommitted change or
# untracked non-ignored file. The one gap it leaves is GITIGNORED content, which it deletes silently — so
# that is the only thing we gate here. Prints exactly one word:
#   dirty        — porcelain non-empty (uncommitted or untracked non-ignored): remove would refuse. Alive.
#   keep-ignored — clean of tracked/untracked, but holds gitignored content that isn't provably disposable
#                  (e.g. private/, .env, a local config): auto-removing would delete it -> a human decides.
#   clean        — clean, and every gitignored entry is provably disposable (a CLAUDE.md symlink into the
#                  main checkout, the worktree's own .claude/ tool state, .DS_Store, or a regenerable build
#                  dir): nothing of value is lost by removal.
worktree_state() {
  local wtp="$1" out ignored line path
  # One `status` call: --ignored is a superset of plain porcelain, so it answers both questions.
  out="$(git -C "$wtp" status --porcelain --ignored 2>/dev/null || true)"
  # Any porcelain line that ISN'T an ignored (`!! `) entry is tracked/untracked work -> remove would refuse.
  [ -n "$(printf '%s\n' "$out" | grep -v '^!! ' | grep . || true)" ] && { printf 'dirty\n'; return 0; }
  ignored="$(printf '%s\n' "$out" | grep '^!! ' || true)"
  [ -n "$ignored" ] || { printf 'clean\n'; return 0; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line#!! }"
    case "$path" in
      CLAUDE.md) [ -L "$wtp/CLAUDE.md" ] || { printf 'keep-ignored\n'; return 0; } ;;  # symlink into main = safe; a real file may hold work
      .claude/|.DS_Store|.git|.git/) : ;;                                              # tool / OS state
      node_modules/|target/|dist/|build/|.venv/|venv/|.next/|.gradle/|Pods/|DerivedData/|.build/|vendor/|.idea/) : ;;  # regenerable build dirs
      *) printf 'keep-ignored\n'; return 0 ;;                                          # anything else -> a human decides
    esac
  done <<EOF
$ignored
EOF
  printf 'clean\n'
}

# Portable file mtime, epoch seconds: GNU/busybox stat use -c '%Y'; BSD stat (macOS) uses -f '%m'. Detected
# ONCE below (STAT_FMT) rather than trying both forms per file -- see the ticket note on stat -f/-c divergence.
epoch_mtime() {
  case "$STAT_FMT" in
    c) stat -c '%Y' "$1" 2>/dev/null ;;
    f) stat -f '%m' "$1" 2>/dev/null ;;
  esac
}
STAT_FMT=c
stat -c '%Y' "$0" >/dev/null 2>&1 || STAT_FMT=f

# Is any file under the worktree (including its .git link file) touched within --live-hours? A merged,
# git-clean worktree with fresh file activity is plausibly a parallel session still mid-wrap, not a dead
# leftover (backlog #51). `find -newermt`/`-mmin` aren't reliably available on busybox, so this compares
# mtimes directly instead of relying on find's own time predicates -- only -name/-prune/-type/-print, which
# are portable across GNU, BSD, and busybox find. Heavy regenerable dirs are pruned to bound the walk; a
# build having just run in one doesn't itself prove a live session, and scanning e.g. node_modules is slow.
worktree_live() {
  [ "$LIVE_HOURS" -eq 0 ] && return 1   # probe disabled -- skip the walk entirely
  local wtp="$1" threshold f m
  threshold=$(( now - LIVE_HOURS * 3600 ))
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    m="$(epoch_mtime "$f")"
    case "$m" in ''|*[!0-9]*) continue ;; esac
    [ "$m" -gt "$threshold" ] && return 0
  done < <(find "$wtp" \( -name node_modules -o -name target -o -name dist -o -name build -o -name .venv \
    -o -name venv -o -name .next -o -name .gradle -o -name Pods -o -name DerivedData -o -name .build \
    -o -name vendor -o -name .idea \) -prune -o -type f -print 2>/dev/null)
  return 1
}

now="$(date +%s)"
auto="";   n_auto=0          # free branches safe to delete (also carries worktree autos, see autowt)
autowt=""                   # worktrees safe to auto-remove: name<TAB>age<TAB>path
ask="";    n_ask=0           # free branches to confirm
askwt=""                    # worktrees to confirm: name<TAB>age<TAB>path<TAB>reason
flag="";   n_flag=0          # worktrees with live work (dirty OR recently-touched-but-clean) — never auto-touched

# --merged="$base" does the "merged" gate in git itself (tip reachable from base — an unmerged or
# squash-merged branch is simply not listed), replacing a per-branch `git merge-base` fork. The committer
# date rides along free from the same call (a ref name can't contain a space, so `read b cd` splits
# cleanly) — no per-branch `git log` fork either. (`--merged` needs git >= 2.7, 2015; macOS/Alpine clear it.)
while read -r b cd; do
  [ "$b" = "$default" ] && continue                         # base is trivially merged into itself
  age=$(( (now - ${cd:-$now}) / 86400 ))
  match=0
  # shellcheck disable=SC2254  # $g is INTENTIONALLY a glob here (claude/*, feat/*): we match the name against it
  for g in $GLOBS; do case "$b" in $g) match=1; break ;; esac; done
  wtp="$(wt_path_for "$b")"
  if [ -n "$wtp" ]; then                                    # checked out in a worktree
    [ "$wtp" -ef "$current_wt" ] && continue                # the worktree we're standing in -> never touch
    state="$(worktree_state "$wtp")"
    if [ "$state" = dirty ]; then                          # live work -> remove would need --force. Never auto.
      flag="${flag}${b}"$'\t'"${wtp}"$'\t'"dirty"$'\n'; n_flag=$((n_flag + 1))
    elif worktree_live "$wtp"; then                        # clean but recently touched -> possibly a live
      flag="${flag}${b}"$'\t'"${wtp}"$'\t'"live"$'\n'; n_flag=$((n_flag + 1))   # parallel session, not dead
    elif [ "$state" = clean ] && [ "$age" -ge "$DAYS" ] && [ "$match" -eq 1 ]; then
      # provably safe: idle, ephemeral name, nothing of value on disk -> auto-remove like a confident branch
      autowt="${autowt}${b}"$'\t'"${age}"$'\t'"${wtp}"$'\n'; n_auto=$((n_auto + 1))
    else                                                    # clean but recent / off-pattern / keep-ignored -> confirm
      if [ "$state" = keep-ignored ]; then wr=keep-ignored
      elif [ "$age" -lt "$DAYS" ]; then wr=recent
      else wr=off-pattern; fi
      askwt="${askwt}${b}"$'\t'"${age}"$'\t'"${wtp}"$'\t'"${wr}"$'\n'; n_ask=$((n_ask + 1))
    fi
    continue
  fi
  if [ "$age" -ge "$DAYS" ] && [ "$match" -eq 1 ]; then
    auto="${auto}${b}"$'\t'"${age}"$'\n'; n_auto=$((n_auto + 1))
  else
    reason=recent; [ "$age" -ge "$DAYS" ] && reason=off-pattern
    ask="${ask}${b}"$'\t'"${age}"$'\t'"${reason}"$'\n'; n_ask=$((n_ask + 1))
  fi
done < <(git for-each-ref --merged="$base" --format='%(refname:short) %(committerdate:unix)' refs/heads/)

# --- act + report -------------------------------------------------------------------------------
# delete_branch NAME — -d first (belt); -D fallback only because -d compares against the current HEAD, not
# $base, so it would false-refuse a branch merged into origin/<default> but not into whatever branch we are
# on. AUTO is proven an ancestor of $base above, so every commit survives there regardless.
delete_branch() { git branch -d "$1" >/dev/null 2>&1 || git branch -D "$1" >/dev/null 2>&1; }

deleted=0
if [ "$PRUNE" -eq 1 ]; then
  # in-shell (process substitution, not a pipe) so `deleted` survives the loop
  while IFS=$'\t' read -r b _age; do
    [ -n "$b" ] || continue
    if delete_branch "$b"; then
      printf 'deleted  %-40s merged into %s\n' "$b" "$base"; deleted=$((deleted + 1))
    else
      printf 'FAILED   %-40s could not delete\n' "$b" >&2
    fi
  done < <(printf '%s' "$auto")
  # Worktree autos: `git worktree remove` WITHOUT --force (git re-verifies tracked/untracked cleanliness —
  # a last guard against a race since we last checked), then delete the now-free branch. Never --force.
  while IFS=$'\t' read -r b _age wtp; do
    [ -n "$b" ] || continue
    if git worktree remove "$wtp" >/dev/null 2>&1; then
      delete_branch "$b" || true
      printf 'removed  %-40s worktree %s + branch\n' "$b" "$wtp"; deleted=$((deleted + 1))
    else
      printf 'FAILED   %-40s worktree not clean, left as-is: %s\n' "$b" "$wtp" >&2
    fi
  done < <(printf '%s' "$autowt")
else
  while IFS=$'\t' read -r b age; do
    [ -n "$b" ] || continue
    printf 'AUTO  %-40s merged, %sd old\n' "$b" "$age"
  done < <(printf '%s' "$auto")
  while IFS=$'\t' read -r b age wtp; do
    [ -n "$b" ] || continue
    printf 'AUTO  %-40s merged, %sd old, worktree %s  ->  git worktree remove %s\n' "$b" "$age" "$wtp" "$wtp"
  done < <(printf '%s' "$autowt")
fi

while IFS=$'\t' read -r b age reason; do
  [ -n "$b" ] || continue
  printf 'ASK   %-40s merged, %sd old (%s)\n' "$b" "$age" "$reason"
done < <(printf '%s' "$ask")
while IFS=$'\t' read -r b age wtp reason; do
  [ -n "$b" ] || continue
  printf 'ASK   %-40s merged, %sd old (%s), worktree %s  ->  git worktree remove %s\n' "$b" "$age" "$reason" "$wtp" "$wtp"
done < <(printf '%s' "$askwt")

# FLAG is a worktree with LIVE work — surfaced without a destructive command on purpose: removing it could
# discard that work or race a live session, so the human reviews first. Two distinct reasons:
#   dirty — uncommitted/untracked files; `git worktree remove` would refuse without --force.
#   live  — clean, but touched within --live-hours; possibly a parallel session still mid-wrap (backlog #51).
while IFS=$'\t' read -r b path reason; do
  [ -n "$b" ] || continue
  if [ "$reason" = live ]; then
    printf 'FLAG  %-40s worktree %s merged but recently active — possibly a live parallel session; leave it, re-run cleanup later\n' "$b" "$path"
  else
    printf 'FLAG  %-40s worktree %s has uncommitted/untracked work — review before removing\n' "$b" "$path"
  fi
done < <(printf '%s' "$flag")

if [ "$PRUNE" -eq 1 ]; then
  printf -- '--- %d removed, %d to confirm (ASK), %d with live work (FLAG)\n' "$deleted" "$n_ask" "$n_flag"
else
  printf -- '--- %d auto-safe, %d to confirm (ASK), %d with live work (FLAG)\n' "$n_auto" "$n_ask" "$n_flag"
fi
