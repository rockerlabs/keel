#!/usr/bin/env bash
# test_run_sh_canary_scope.sh — dir #768: the dir #318 canary in tests/run.sh is scoped to what a run could have
# written. A full suite used to fail closed on ordinary concurrent work in the shared checkout — a peer's branch
# moving while no worktree had it checked out, a branch-cleanup sweep, a `git push -u` on a dotted branch name,
# the run's own $TMPDIR sitting inside the checkout — and each trip cost a release wave a full re-run (~1 h).
# Each fixture runs a COPY of run.sh against a throwaway real git repo whose one test file plays the peer (the
# canary sees only effects, so a test file doing the peer's write is the same experiment). GREEN rows: the
# canary stays quiet. RED rows: what it exists for still trips. tests/test_run_sh.sh has the older rows.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

runner="$REPO_ROOT/tests/run.sh"
# A failing fixture preserves its logdir (dir #480); keep it inside the sandbox.
export TMPDIR="$SANDBOX"

# mkcanary — a real repo with two commits, a copy of run.sh, a stub lib.sh and the ref-guard helpers, everything
# committed so the tree starts clean. Prints its path.
mkcanary() {
  local d; d="$(new_repo)"
  git -C "$d" commit -q --allow-empty -m base
  mkdir -p "$d/tests" "$d/tools/lib" "$d/keep"
  cp "$runner" "$d/tests/run.sh"
  cp "$REPO_ROOT/tools/lib/ref-guard.sh" "$d/tools/lib/ref-guard.sh"
  : > "$d/tests/lib.sh"
  : > "$d/keep/tracked"
  git -C "$d" add -A
  git -C "$d" commit -q -m second
  printf '%s' "$d"
}

# peer_act REPO BODY — the one test file of REPO: BODY runs with $R set to the repo root.
peer_act() {
  printf '#!/usr/bin/env bash\nR="$(dirname "$0")/.."\n%s\nexit 0\n' "$2" > "$1/tests/test_peer.sh"
}

TRIP="TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #318)"

# --- GREEN 1: a peer worktree commits on its own branch -------------------------------------------------------
d="$(mkcanary)"
peerwt="$SANDBOX/peerwt.$$"
git -C "$d" worktree add -q -b peer "$peerwt"
peer_act "$d" "git -C '$peerwt' commit -q --allow-empty -m peer-work"
run bash "$d/tests/run.sh"
check_status "a peer worktree's commit on its own branch -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 2: a branch-cleanup sweep deletes merged branches (their tips stay reachable from main) ---------------
d="$(mkcanary)"
git -C "$d" branch merged-a
git -C "$d" branch merged-b
peer_act "$d" 'git -C "$R" branch -D merged-a merged-b >/dev/null'
run bash "$d/tests/run.sh"
check_status "a sweep deleting merged branches -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 3: an unowned branch moves forward (a peer's commit while its branch is checked out nowhere) --------
d="$(mkcanary)"
git -C "$d" branch lagging HEAD~1
peer_act "$d" 'git -C "$R" branch -f lagging HEAD'
run bash "$d/tests/run.sh"
check_status "an unowned branch fast-forwarding -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 4: tracking config for a DOTTED branch name (`git push -u` on rel/1.2) -------------------------------
d="$(mkcanary)"
peer_act "$d" 'git -C "$R" config --local branch.rel/1.2.merge refs/heads/rel/1.2
git -C "$R" config --local branch.release-0.17.0-train1.remote origin'
run bash "$d/tests/run.sh"
check_status "per-branch tracking keys of a dotted branch name -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 5: $TMPDIR inside the watched checkout (the run's own logdir is untracked there) --------------------
d="$(mkcanary)"
peer_act "$d" ':'
run env TMPDIR="$d/keep" bash "$d/tests/run.sh"
check_status "TMPDIR inside the checkout -> the run's own logdir does not trip the canary" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"
check_contains "... and the suite itself ran" "$OUT" "ALL TEST FILES PASSED"

# --- GREEN 6: the same, with a brand-new untracked directory as $TMPDIR (git collapses it into one `?? dir/`) --
d="$(mkcanary)"
peer_act "$d" ':'
mkdir "$d/fresh-tmp"
run env TMPDIR="$d/fresh-tmp" bash "$d/tests/run.sh"
check_status "an untracked TMPDIR directory inside the checkout -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 7: $TMPDIR spelled through a symlink (macOS /var -> /private/var shape) that resolves into the checkout -
d="$(mkcanary)"
peer_act "$d" ':'
mkdir "$d/linked-tmp"
tmplink="$SANDBOX/tmplink.$$"
ln -s "$d/linked-tmp" "$tmplink"
run env TMPDIR="$tmplink" bash "$d/tests/run.sh"
check_status "a symlinked TMPDIR that resolves into the checkout -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 8: git told to list untracked files one per line (status.showUntrackedFiles=all) --------------------
d="$(mkcanary)"
peer_act "$d" ':'
mkdir "$d/fresh-tmp-all"
git -C "$d" config --local status.showUntrackedFiles all
git -C "$d" add -A; git -C "$d" commit -q -m cfg 2>/dev/null || true
run env TMPDIR="$d/fresh-tmp-all" bash "$d/tests/run.sh"
check_status "showUntrackedFiles=all: the run's own log files do not trip the canary" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 9: an ancestor of the logdir with a space in its name (git quotes the path) -------------------------------
d="$(mkcanary)"
peer_act "$d" ':'
mkdir "$d/my tmp dir"
run env TMPDIR="$d/my tmp dir" bash "$d/tests/run.sh"
check_status "a TMPDIR with a space in its path -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- GREEN 10: the watched root is a SUBDIRECTORY of a bigger repo (git's status paths carry the prefix) ---------
d="$(new_repo)"
git -C "$d" commit -q --allow-empty -m base
mkdir -p "$d/proj/tests" "$d/proj/tools/lib" "$d/proj/keep"
cp "$runner" "$d/proj/tests/run.sh"
cp "$REPO_ROOT/tools/lib/ref-guard.sh" "$d/proj/tools/lib/ref-guard.sh"
: > "$d/proj/tests/lib.sh"; : > "$d/proj/keep/tracked"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/proj/tests/test_peer.sh"
git -C "$d" add -A; git -C "$d" commit -q -m proj
mkdir "$d/proj/fresh-tmp-sub"
run env TMPDIR="$d/proj/fresh-tmp-sub" bash "$d/proj/tests/run.sh"
check_status "a watched root that is a subdirectory of the repo -> the canary stays green" 0 "$STATUS"
check_absent "... no trip block" "$OUT" "$TRIP"

# --- NOTE: the watched checkout's own ref-guard.sh predates guard_refs_unexplained: skipped with a NOTE, not silent --
d="$(mkcanary)"
peer_act "$d" 'git -C "$R" branch stray'
# An "older" lib: the working-tree one cut before the dir #768 functions (everything from guard_tip_survives on).
awk '/^# guard_tip_survives REPO SHA/ { exit } { print }' "$REPO_ROOT/tools/lib/ref-guard.sh" > "$d/tools/lib/ref-guard.sh"
check_eq "the stale-lib fixture really lacks the new function" "0" "$(grep -c '^guard_refs_unexplained()' "$d/tools/lib/ref-guard.sh")"
run bash "$d/tests/run.sh"
check_contains "an older ref-guard.sh -> a NOTE names the missing function" "$OUT" "predates guard_refs_unexplained"
check_absent "... and no 'command not found' leaks into the run" "$OUT" "command not found"
# The skip is of the refs half only: the branch/HEAD/status compare of dir #318 still runs and trips.
d="$(mkcanary)"
peer_act "$d" 'git -C "$R" commit -q --allow-empty -m own-commit'
awk '/^# guard_tip_survives REPO SHA/ { exit } { print }' "$REPO_ROOT/tools/lib/ref-guard.sh" > "$d/tools/lib/ref-guard.sh"
run bash "$d/tests/run.sh"
check_status "an older ref-guard.sh -> the HEAD compare still trips on the run's own commit" 1 "$STATUS"

# --- RED 1: a stray new branch (dir #320's shape) --------------------------------------------------------------
d="$(mkcanary)"
peer_act "$d" 'git -C "$R" branch stray'
run bash "$d/tests/run.sh"
check_status "a stray new branch -> the canary trips" 1 "$STATUS"
check_contains "... the trip block" "$OUT" "$TRIP"
check_contains "... naming the branch as appeared (+)" "$OUT" "+ stray"

# --- RED 2: an unowned branch with its own commit is deleted: commits lost --------------------------------------
d="$(mkcanary)"
git -C "$d" checkout -q -b unique-work
git -C "$d" commit -q --allow-empty -m only-here
git -C "$d" checkout -q -
peer_act "$d" 'git -C "$R" branch -D unique-work >/dev/null'
run bash "$d/tests/run.sh"
check_status "deleting an unowned branch whose commits no ref reaches -> the canary trips" 1 "$STATUS"
check_contains "... naming it as lost (-)" "$OUT" "- unique-work"

# --- RED 3: an unowned branch is rewritten away from its old tip -------------------------------------------------
d="$(mkcanary)"
git -C "$d" checkout -q -b rewritten
git -C "$d" commit -q --allow-empty -m old-tip
git -C "$d" checkout -q -
peer_act "$d" 'git -C "$R" branch -f rewritten HEAD'
run bash "$d/tests/run.sh"
check_status "resetting an unowned branch so its old tip is unreachable -> the canary trips" 1 "$STATUS"
check_contains "... naming it as rewritten (~)" "$OUT" "~ rewritten"

# --- RED 4: the run's own branch moves, and the local config (outside the per-branch keys) changes -----------------
d="$(mkcanary)"
peer_act "$d" 'git -C "$R" commit -q --allow-empty -m own-commit'
run bash "$d/tests/run.sh"
check_status "the run's own branch moving -> the canary trips" 1 "$STATUS"

d="$(mkcanary)"
peer_act "$d" 'git -C "$R" config --local core.somethingNew value'
run bash "$d/tests/run.sh"
check_status "a non-branch key written to the local config -> the canary trips" 1 "$STATUS"
check_contains "... naming the key" "$OUT" "core.somethingnew"

d="$(mkcanary)"
peer_act "$d" 'git -C "$R" config --local branch.autoSetupMerge always'
run bash "$d/tests/run.sh"
check_status "a bare top-level branch.* setting still trips" 1 "$STATUS"

# --- RED 5: a stray file written next to (not inside) the run's own scratch directory ----------------------------
d="$(mkcanary)"
peer_act "$d" 'printf x > "$R/leaked-file"'
run env TMPDIR="$d/keep" bash "$d/tests/run.sh"
check_status "TMPDIR inside the checkout does not hide a stray file elsewhere" 1 "$STATUS"
check_contains "... naming it" "$OUT" "leaked-file"

# --- RED 6: a stray file INSIDE the TMPDIR directory itself (tracked dir) is still named ----------------------------
d="$(mkcanary)"
peer_act "$d" 'printf x > "$R/keep/leaked-in-tmp"'
run env TMPDIR="$d/keep" bash "$d/tests/run.sh"
check_status "a stray file inside the TMPDIR directory -> the canary trips" 1 "$STATUS"
check_contains "... naming it" "$OUT" "keep/leaked-in-tmp"

summary
