#!/usr/bin/env bash
# Tests for tools/branch-cleanup.sh — the confidence classifier for post-merge branch cleanup (backlog #25).
# We pin the machinery, not judgment: which tier each branch lands in (AUTO/ASK/FLAG/skip) given its
# merge-state, worktree-state, age, and name; that --prune-safe deletes ONLY the AUTO tier; and that the
# non-destructive report mode touches nothing. All offline — no remote is needed for the core cases; one
# section builds a real origin to exercise the origin/<default> base path.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/branch-cleanup.sh"
OLD="2020-01-01T12:00:00"   # a committer date safely older than any --days threshold

# tier of the OUT line mentioning $1 (empty if absent) — robust to column padding
line_for() { printf '%s\n' "$OUT" | grep -F -- "$1" || true; }

# --- a repo with one branch per tier -----------------------------------------------------------
repo="$(new_repo)"
git -C "$repo" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$repo" commit -q --allow-empty -m c1
c1="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" commit -q --allow-empty -m c2          # recent; main tip
git -C "$repo" branch claude/old-merged   "$c1"       # merged, ephemeral, old      -> AUTO
git -C "$repo" branch feature/fresh-merged HEAD       # merged, ephemeral, recent   -> ASK (recent)
git -C "$repo" branch staging             "$c1"       # merged, off-pattern, old     -> ASK (off-pattern)
git -C "$repo" branch claude/wip          HEAD        # will get an unmerged commit  -> skip
git -C "$repo" checkout -q claude/wip
git -C "$repo" commit -q --allow-empty -m wip
git -C "$repo" checkout -q main
git -C "$repo" branch claude/wt "$c1"                 # merged, ephemeral, old, but in a worktree -> FLAG
git -C "$repo" worktree add -q "$repo.wt" claude/wt >/dev/null

# report, default --days 7: fresh branch is recent, old ones cross the age gate
run_in "$repo" bash "$TOOL" --days 7
check_status  "report exits 0" 0 "$STATUS"
OUT_KEEP="$OUT"
check_contains "old ephemeral merged -> AUTO"     "$(line_for claude/old-merged)"   "AUTO"
check_contains "fresh merged -> ASK"              "$(line_for feature/fresh-merged)" "ASK"
check_contains "fresh merged reason is recent"    "$(line_for feature/fresh-merged)" "recent"
check_contains "old off-pattern -> ASK"           "$(line_for staging)"             "ASK"
check_contains "off-pattern reason"               "$(line_for staging)"             "off-pattern"
check_contains "worktree branch -> FLAG"          "$(line_for claude/wt)"           "FLAG"
check_contains "FLAG gives the manual command"    "$(line_for claude/wt)"           "git worktree remove"
check_absent   "unmerged branch is left alone"    "$OUT_KEEP" "claude/wip"
# counts prove the default branch + the unmerged branch are excluded (AUTO=1, ASK=2, FLAG=1)
check_contains "summary counts exclude default and unmerged" "$OUT_KEEP" \
  "1 auto-safe, 2 to confirm (ASK), 1 worktrees to review"

# report mode deletes nothing
run git -C "$repo" rev-parse --verify -q refs/heads/claude/old-merged
check_status "report mode is non-destructive" 0 "$STATUS"

# --days 0 drops the age gate: the fresh ephemeral branch joins AUTO, off-pattern staging stays ASK
run_in "$repo" bash "$TOOL" --days 0
check_contains "days 0: fresh ephemeral merged -> AUTO" "$(line_for feature/fresh-merged)" "AUTO"
check_contains "days 0: old ephemeral still AUTO"       "$(line_for claude/old-merged)"    "AUTO"
check_contains "days 0: off-pattern name stays ASK"     "$(line_for staging)"              "ASK"
check_contains "days 0 summary" "$OUT" "2 auto-safe, 1 to confirm (ASK), 1 worktrees to review"

# --prune-safe (default --days 7) deletes ONLY the AUTO tier
run_in "$repo" bash "$TOOL" --prune-safe --days 7
check_status   "prune-safe run exits 0" 0 "$STATUS"
check_contains "prune-safe deletes the AUTO branch"  "$(line_for claude/old-merged)" "deleted"
check_contains "prune-safe summary counts one deleted" "$OUT" "1 deleted"
check_contains "prune-safe still reports ASK"        "$(line_for staging)"           "ASK"
check_contains "prune-safe still reports FLAG"       "$(line_for claude/wt)"         "FLAG"
# survival checks (these `run` calls overwrite OUT/STATUS, so they come after the content asserts above)
run git -C "$repo" rev-parse --verify -q refs/heads/claude/old-merged
check_status "AUTO branch is really gone"            1 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/feature/fresh-merged
check_status "recent ASK branch survives prune"      0 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/staging
check_status "off-pattern ASK branch survives prune" 0 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/claude/wip
check_status "unmerged branch survives prune"        0 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/claude/wt
check_status "worktree branch survives prune"        0 "$STATUS"

# --- current branch is never a candidate, even if otherwise AUTO-eligible ----------------------
repo2="$(new_repo)"
git -C "$repo2" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$repo2" commit -q --allow-empty -m c1
git -C "$repo2" branch claude/cur HEAD
git -C "$repo2" checkout -q claude/cur                # now the current branch, merged+ephemeral+old
run_in "$repo2" bash "$TOOL" --days 0
check_absent "current branch is never listed" "$OUT" "claude/cur"
check_contains "nothing to do -> zero counts" "$OUT" "0 auto-safe, 0 to confirm (ASK), 0 worktrees to review"

# --- the worktree the run sits IN is never FLAGged to remove itself (path-based, not branch-name) --------
# Regression: the exclusion used to compare the INVOKING cwd's branch NAME, so running from a different dir
# than the session's worktree (e.g. wrap reconciling from the main checkout) flagged the session's own
# worktree. Now it's compared by PATH. Two merged worktrees; running FROM one must shield only that one.
wtrepo="$(new_repo)"
git -C "$wtrepo" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$wtrepo" commit -q --allow-empty -m c1
c1w="$(git -C "$wtrepo" rev-parse HEAD)"
git -C "$wtrepo" commit -q --allow-empty -m c2                 # main tip; c1 is merged into it
git -C "$wtrepo" branch claude/session "$c1w"                  # merged, ephemeral, old
git -C "$wtrepo" worktree add -q "$wtrepo.session" claude/session >/dev/null
git -C "$wtrepo" branch claude/other "$c1w"                    # a second merged worktree
git -C "$wtrepo" worktree add -q "$wtrepo.other" claude/other >/dev/null
run_in "$wtrepo.session" bash "$TOOL" --days 0
check_absent   "own worktree is never flagged to remove itself" "$OUT" "claude/session"
check_contains "a different merged worktree still FLAGs"        "$(line_for claude/other)" "FLAG"

# KEEL_KEEP_WORKTREE shields a named worktree even when the tool runs from ELSEWHERE (wrap from main-top):
# run from the main checkout but protect the session worktree by path.
export KEEL_KEEP_WORKTREE="$wtrepo.session"
run_in "$wtrepo" bash "$TOOL" --days 0
unset KEEL_KEEP_WORKTREE
check_absent   "KEEL_KEEP_WORKTREE shields the named worktree from a run elsewhere" "$OUT" "claude/session"
check_contains "other worktree still FLAGs under KEEL_KEEP_WORKTREE" "$(line_for claude/other)" "FLAG"

# --- origin/<default> is preferred over the local default as the merge base --------------------
# The proof needs local main and origin/main to DIVERGE: a branch merged into origin/main but NOT into
# local main must still be AUTO. If the tool wrongly used the local base, it would be skipped instead.
work="$(new_repo)"
origin="$(mktemp -d "$SANDBOX/origin.XXXXXX")"
git -C "$origin" init -q --bare
git -C "$work" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$work" commit -q --allow-empty -m c1
c1w="$(git -C "$work" rev-parse HEAD)"
git -C "$work" remote add origin "$origin"
git -C "$work" commit -q --allow-empty -m c2          # advance main to c2 ...
git -C "$work" push -q -u origin main                 # ... push it, so origin/main = c2
git -C "$work" remote set-head origin main            # refs/remotes/origin/HEAD -> origin/main
git -C "$work" branch claude/on-origin HEAD           # at c2 = origin/main tip
git -C "$work" update-ref refs/heads/main "$c1w"      # roll LOCAL main back to c1 -> diverges from origin/main
run_in "$work" bash "$TOOL" --days 0
# claude/on-origin (c2) is reachable from origin/main (c2) but NOT from local main (c1): AUTO proves
# the tool compared against the origin base.
check_contains "origin base preferred over local default" "$(line_for claude/on-origin)" "AUTO"

# --- glob patterns must NOT be pathname-expanded against the CWD (regression: set -f) -----------
# A default glob like `docs/*` run from a dir that HAS a docs/ tree would expand to real filenames and
# stop matching branch names — silently misclassifying `docs/foo` as ASK. `set -f` prevents that.
globrepo="$(new_repo)"
git -C "$globrepo" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$globrepo" commit -q --allow-empty -m c1
git -C "$globrepo" branch docs/old-note HEAD          # matches the default glob `docs/*`
git -C "$globrepo" branch experiment/thing HEAD       # not in the default glob set
mkdir -p "$globrepo/docs"; : > "$globrepo/docs/real-file"   # a real docs/* target, so an unguarded glob expands
run_in "$globrepo" bash "$TOOL" --days 0
check_contains "glob is not filesystem-expanded (docs/* still matches)" "$(line_for docs/old-note)" "AUTO"
check_contains "off-glob name is ASK by default" "$(line_for experiment/thing)" "ASK"

# --- KEEL_CLEANUP_GLOBS overrides the ephemeral-name allowlist ----------------------------------
export KEEL_CLEANUP_GLOBS='experiment/*'
run_in "$globrepo" bash "$TOOL" --days 0
unset KEEL_CLEANUP_GLOBS
check_contains "KEEL_CLEANUP_GLOBS makes the custom name AUTO" "$(line_for experiment/thing)" "AUTO"

# --- usage / arg handling / guards -------------------------------------------------------------
run bash "$TOOL" -h
check_status   "help exits 0" 0 "$STATUS"
check_contains "help explains the tool" "$OUT" "classify local branches"

run bash "$TOOL" --bogus
check_status "unknown argument exits 2" 2 "$STATUS"

run bash "$TOOL" --days abc
check_status "non-numeric --days exits 2" 2 "$STATUS"

notrepo="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
run_in "$notrepo" bash "$TOOL"
check_status   "outside a git repo exits 2" 2 "$STATUS"
check_contains "not-a-repo message" "$OUT" "not a git repository"

empty="$(new_repo)"                                    # inited, no commit -> no default branch
run_in "$empty" bash "$TOOL"
check_status   "no base branch exits 0 (nothing to do)" 0 "$STATUS"
check_contains "no-base message hints at fetch" "$OUT" "to compare against"

summary
