#!/usr/bin/env bash
# Tests for tools/branch-cleanup.sh — the confidence classifier for post-merge cleanup (backlog #25).
# We pin the machinery, not judgment: which tier each branch lands in (AUTO/ASK/FLAG/skip) given its
# merge-state, worktree LIVENESS, age, and name; that --prune-safe deletes ONLY the AUTO tier (free
# branches AND provably-dead worktrees); that a dead worktree's removal loses nothing while a live or
# valued one is never auto-touched; and that report mode touches nothing. All offline — no remote is
# needed for the core cases; one section builds a real origin to exercise the origin/<default> base path.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/branch-cleanup.sh"
OLD="2020-01-01T12:00:00"   # a committer date safely older than any --days threshold

# tier of the OUT line mentioning $1 (empty if absent) — robust to column padding
line_for() { printf '%s\n' "$OUT" | grep -F -- "$1" || true; }

# --- a repo with one branch per tier, including all four worktree-liveness states ----------------
repo="$(new_repo)"
git -C "$repo" symbolic-ref HEAD refs/heads/main
printf 'private/\n.DS_Store\n' > "$repo/.gitignore"   # so a worktree can hold VALUED vs disposable ignored
git -C "$repo" add .gitignore
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$repo" commit -q -m c1
c1="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" commit -q --allow-empty -m c2          # recent; main tip

# free branches (no worktree)
git -C "$repo" branch claude/old-merged   "$c1"       # merged, ephemeral, old      -> AUTO
git -C "$repo" branch feature/fresh-merged HEAD       # merged, ephemeral, recent   -> ASK (recent)
git -C "$repo" branch staging             "$c1"       # merged, off-pattern, old     -> ASK (off-pattern)
git -C "$repo" branch claude/wip          HEAD        # will get an unmerged commit  -> skip
git -C "$repo" checkout -q claude/wip
git -C "$repo" commit -q --allow-empty -m wip
git -C "$repo" checkout -q main

# worktree branches — one per liveness state (all merged, ephemeral, old)
git -C "$repo" branch claude/wt-clean "$c1"           # clean worktree               -> AUTO (dead, removable)
git -C "$repo" branch claude/wt-dirty "$c1"           # untracked work in worktree   -> FLAG (alive)
git -C "$repo" branch claude/wt-keep  "$c1"           # valued gitignored content    -> ASK (keep-ignored)
git -C "$repo" worktree add -q "$repo.wt-clean" claude/wt-clean >/dev/null
git -C "$repo" worktree add -q "$repo.wt-dirty" claude/wt-dirty >/dev/null
git -C "$repo" worktree add -q "$repo.wt-keep"  claude/wt-keep  >/dev/null
: > "$repo.wt-clean/.DS_Store"                         # disposable ignored -> still "clean"
: > "$repo.wt-dirty/wip.txt"                           # untracked, NOT ignored -> "dirty" (remove would refuse)
mkdir -p "$repo.wt-keep/private"; : > "$repo.wt-keep/private/draft.txt"   # ignored + non-disposable -> keep

# report, default --days 7: fresh branch is recent, old ones cross the age gate. --live-hours 0 disables the
# liveness probe for these pre-existing assertions -- the worktree fixtures above were just created, so their
# file mtimes are "now" and would otherwise all read as live; liveness itself gets its own scenario below.
run_in "$repo" bash "$TOOL" --days 7 --live-hours 0
check_status  "report exits 0" 0 "$STATUS"
OUT_KEEP="$OUT"
check_contains "old ephemeral merged -> AUTO"       "$(line_for claude/old-merged)"    "AUTO"
check_contains "fresh merged -> ASK"                "$(line_for feature/fresh-merged)" "ASK"
check_contains "fresh merged reason is recent"      "$(line_for feature/fresh-merged)" "recent"
check_contains "old off-pattern -> ASK"             "$(line_for staging)"              "ASK"
check_contains "off-pattern reason"                 "$(line_for staging)"              "off-pattern"
# the four worktree states
check_contains "clean old worktree -> AUTO"         "$(line_for claude/wt-clean)"      "AUTO"
check_contains "worktree AUTO carries remove cmd"   "$(line_for claude/wt-clean)"      "git worktree remove"
check_contains "dirty worktree -> FLAG"             "$(line_for claude/wt-dirty)"      "FLAG"
check_contains "FLAG reason names live work"        "$(line_for claude/wt-dirty)"      "uncommitted/untracked work"
check_absent   "FLAG gives NO destructive command"  "$(line_for claude/wt-dirty)"      "git worktree remove"
check_contains "keep-ignored worktree -> ASK"       "$(line_for claude/wt-keep)"       "ASK"
check_contains "keep-ignored reason"                "$(line_for claude/wt-keep)"       "keep-ignored"
check_absent   "unmerged branch is left alone"      "$OUT_KEEP" "claude/wip"
# AUTO=2 (old-merged, wt-clean), ASK=3 (fresh, staging, wt-keep), FLAG=1 (wt-dirty)
check_contains "summary counts exclude default and unmerged" "$OUT_KEEP" \
  "2 auto-safe, 3 to confirm (ASK), 1 with live work (FLAG)"

# report mode deletes/removes nothing
run git -C "$repo" rev-parse --verify -q refs/heads/claude/old-merged
check_status "report mode is non-destructive (branch)" 0 "$STATUS"
check_contains "report mode is non-destructive (worktree)" "$([ -d "$repo.wt-clean" ] && echo y)" "y"

# --days 0 drops the age gate: fresh ephemeral + clean worktree join AUTO; keep-ignored/off-pattern stay ASK
run_in "$repo" bash "$TOOL" --days 0 --live-hours 0
check_contains "days 0: fresh ephemeral merged -> AUTO"   "$(line_for feature/fresh-merged)" "AUTO"
check_contains "days 0: clean worktree still AUTO"        "$(line_for claude/wt-clean)"      "AUTO"
check_contains "days 0: keep-ignored still ASK (age-independent)" "$(line_for claude/wt-keep)" "keep-ignored"
check_contains "days 0: dirty worktree still FLAG"        "$(line_for claude/wt-dirty)"      "FLAG"
check_contains "days 0: off-pattern name stays ASK"       "$(line_for staging)"              "ASK"
# AUTO=3 (old-merged, fresh, wt-clean), ASK=2 (staging, wt-keep), FLAG=1 (wt-dirty)
check_contains "days 0 summary" "$OUT" "3 auto-safe, 2 to confirm (ASK), 1 with live work (FLAG)"

# --prune-safe (default --days 7) deletes ONLY the AUTO tier: the free branch AND the dead worktree
run_in "$repo" bash "$TOOL" --prune-safe --days 7 --live-hours 0
check_status   "prune-safe run exits 0" 0 "$STATUS"
check_contains "prune-safe deletes the AUTO free branch" "$(line_for claude/old-merged)" "deleted"
check_contains "prune-safe removes the dead worktree"    "$(line_for claude/wt-clean)"   "removed"
check_contains "prune-safe summary counts two removed"   "$OUT" "2 removed"
check_contains "prune-safe still reports ASK"            "$(line_for staging)"           "ASK"
check_contains "prune-safe still reports FLAG"           "$(line_for claude/wt-dirty)"   "FLAG"
# survival checks (these `run` calls overwrite OUT/STATUS, so they come after the content asserts above)
run git -C "$repo" rev-parse --verify -q refs/heads/claude/old-merged
check_status "AUTO free branch is really gone"       1 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/claude/wt-clean
check_status "AUTO worktree branch is really gone"   1 "$STATUS"
check_absent "AUTO worktree dir is really gone" "$([ -d "$repo.wt-clean" ] && echo y)" "y"
run git -C "$repo" rev-parse --verify -q refs/heads/feature/fresh-merged
check_status "recent ASK branch survives prune"      0 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/staging
check_status "off-pattern ASK branch survives prune" 0 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/claude/wip
check_status "unmerged branch survives prune"        0 "$STATUS"
run git -C "$repo" rev-parse --verify -q refs/heads/claude/wt-dirty
check_status "FLAG (live) worktree branch survives prune" 0 "$STATUS"
# the whole point of keep-ignored: its valued gitignored content is NEVER auto-deleted
check_contains "keep-ignored worktree dir survives prune"  "$([ -d "$repo.wt-keep" ] && echo y)" "y"
check_contains "keep-ignored private/ content survives"    "$([ -f "$repo.wt-keep/private/draft.txt" ] && echo y)" "y"
check_contains "dirty worktree dir survives prune"         "$([ -d "$repo.wt-dirty" ] && echo y)" "y"

# --- liveness probe (backlog #51): a merged, git-clean worktree with recently-touched files is a possibly-
# live parallel session, not a stale ASK candidate -- even though `git worktree remove` would happily take it.
# `touch -t` backdates portably (BSD/GNU/busybox all accept the same [[CC]YY]MMDDhhmm[.SS] form), letting the
# "old" half of the scenario be deterministic instead of racing the clock.
liverepo="$(new_repo)"
git -C "$liverepo" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$liverepo" commit -q --allow-empty -m c1
git -C "$liverepo" commit -q --allow-empty -m c2               # recent; main tip
git -C "$liverepo" branch claude/wt-fresh HEAD                 # merged, ephemeral, recent (0d) -> would be ASK
git -C "$liverepo" branch claude/wt-quiet HEAD                 # same shape, but its files get backdated
git -C "$liverepo" worktree add -q "$liverepo.wt-fresh" claude/wt-fresh >/dev/null
git -C "$liverepo" worktree add -q "$liverepo.wt-quiet" claude/wt-quiet >/dev/null
find "$liverepo.wt-quiet" -exec touch -t 202001011200.00 {} + 2>/dev/null

# both branches are 0d old (< default --days 7) and ephemeral -- absent the liveness probe both would be a
# plain ASK-recent. The probe's job is to pull ONLY the fresh-mtime one out into FLAG.
run_in "$liverepo" bash "$TOOL" --live-hours 6
check_contains "fresh-mtime clean worktree -> FLAG (possibly live)" \
  "$(line_for claude/wt-fresh)" "FLAG"
check_contains "live FLAG names it a possible parallel session" \
  "$(line_for claude/wt-fresh)" "possibly a live parallel session"
check_absent   "live FLAG gives NO destructive command" \
  "$(line_for claude/wt-fresh)" "git worktree remove"
check_contains "old-mtime clean worktree stays ASK" \
  "$(line_for claude/wt-quiet)" "ASK"
check_absent   "old-mtime worktree is NOT flagged live" \
  "$(line_for claude/wt-quiet)" "FLAG"

# --live-hours 0 turns the probe off: the fresh-mtime worktree falls back to its ordinary ASK-recent grade.
run_in "$liverepo" bash "$TOOL" --live-hours 0
check_contains "live-hours 0 disables the probe: fresh-mtime worktree is ASK again" \
  "$(line_for claude/wt-fresh)" "ASK"
check_absent   "live-hours 0: fresh-mtime worktree no longer FLAGged" \
  "$(line_for claude/wt-fresh)" "FLAG"

run bash "$TOOL" --live-hours abc
check_status "non-numeric --live-hours exits 2" 2 "$STATUS"

# --- current branch is never a candidate, even if otherwise AUTO-eligible ----------------------
repo2="$(new_repo)"
git -C "$repo2" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$repo2" commit -q --allow-empty -m c1
git -C "$repo2" branch claude/cur HEAD
git -C "$repo2" checkout -q claude/cur                # now the current branch, merged+ephemeral+old
run_in "$repo2" bash "$TOOL" --days 0
check_absent "current branch is never listed" "$OUT" "claude/cur"
check_contains "nothing to do -> zero counts" "$OUT" "0 auto-safe, 0 to confirm (ASK), 0 with live work (FLAG)"

# --- the worktree the run sits IN is never a candidate to remove itself (path-based, not branch-name) ----
# Regression: the exclusion used to compare the INVOKING cwd's branch NAME, so running from a different dir
# than the session's worktree (e.g. wrap reconciling from the main checkout) targeted the session's own
# worktree. Now it's compared by PATH. Two clean merged worktrees; running FROM one must shield only that
# one — the OTHER is now provably dead (clean/old/ephemeral) so it surfaces as AUTO, not FLAG.
wtrepo="$(new_repo)"
git -C "$wtrepo" symbolic-ref HEAD refs/heads/main
GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git -C "$wtrepo" commit -q --allow-empty -m c1
c1w="$(git -C "$wtrepo" rev-parse HEAD)"
git -C "$wtrepo" commit -q --allow-empty -m c2                 # main tip; c1 is merged into it
git -C "$wtrepo" branch claude/session "$c1w"                  # merged, ephemeral, old
git -C "$wtrepo" worktree add -q "$wtrepo.session" claude/session >/dev/null
git -C "$wtrepo" branch claude/other "$c1w"                    # a second merged worktree (clean)
git -C "$wtrepo" worktree add -q "$wtrepo.other" claude/other >/dev/null
run_in "$wtrepo.session" bash "$TOOL" --days 0 --live-hours 0
check_absent   "own worktree is never listed to remove itself" "$OUT" "claude/session"
check_contains "a different clean merged worktree is AUTO"     "$(line_for claude/other)" "AUTO"

# KEEL_KEEP_WORKTREE shields a named worktree even when the tool runs from ELSEWHERE (wrap from main-top):
# run from the main checkout but protect the session worktree by path.
export KEEL_KEEP_WORKTREE="$wtrepo.session"
run_in "$wtrepo" bash "$TOOL" --days 0 --live-hours 0
unset KEEL_KEEP_WORKTREE
check_absent   "KEEL_KEEP_WORKTREE shields the named worktree from a run elsewhere" "$OUT" "claude/session"
check_contains "other worktree still surfaces (AUTO) under KEEL_KEEP_WORKTREE" "$(line_for claude/other)" "AUTO"

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
