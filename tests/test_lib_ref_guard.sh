#!/usr/bin/env bash
# test_lib_ref_guard.sh (dir #318) — direct coverage for tests/lib.sh's ref_guard_arm(): the
# git-level guard that refuses every ref write (branch, tag, commit, fetch, update-ref, worktree add)
# a test process makes against the repository it is armed for, so a fixture bug can no longer leak
# into the real checkout the way the 14 fixture branches this ticket was filed from did.
#
# T1 drives the full integration (a child process sourcing a COPY of lib.sh, exactly as a real test
# file would) so it exercises both G1 (the guard) and G2 (summary() failing the file) end to end. T2
# onward call ref_guard_arm() directly against throwaway fixture repos in THIS process — the same
# idiom test_ref_guard.sh already uses for tools/lib/ref-guard.sh's own functions — since this file
# has already sourced the real tests/lib.sh (so REPO_ROOT, the real checkout, is itself armed the
# whole time this file runs; nothing here writes to it).
#
# One consequence of arming several DIFFERENT fixture repos in this same process: $SANDBOX/ref-
# guard/refused is one shared, ACCUMULATING log per $SANDBOX (G1/G2's own design, sized for the normal
# case of one arm call per real test file — a later arm call no longer truncates an earlier arm's
# entries, dir #318's own live-found fix), so this file's own deliberate refusals (T2 onward) land in
# the exact file G2's summary() reads, and its content alone cannot say which armed repo a given line
# came from (every fixture below points its guard.cfg at the same $SANDBOX/ref-guard/hooks). What
# actually proves this file leaked nothing into the real checkout is NOT log inspection — it's
# REPO_ROOT's own refs/heads branches, snapshotted below (ownership-scoped, S-fix-1) and compared
# again at the end. Only once that direct ref-state proof holds is the log cleared, right before
# summary(), so this file's own intentional coverage of the guard doesn't fail itself via the exact
# mechanism it's testing.
#
# S-fix-1 (delta-audit 0.11.0-0.12.0 fix round F4): the ORIGINAL self-check compared REPO_ROOT's
# WHOLE `git for-each-ref` before/after, which trips on any ordinary concurrent activity in a SIBLING
# worktree of this same checkout — a branch create, a commit, a fetch moving refs/remotes — a false
# leak alarm with nothing actually leaked (live-reproduced twice; felt once in a full suite run,
# 2026-09-25). Now scoped to refs/heads only, ownership-filtered via tools/lib/ref-guard.sh's
# guard_owned_branches/guard_filter_unowned — the SAME shape tests/run.sh's own dir #333 canary
# already uses for exactly this reason (T14 below pins this file's own use of that shape via a
# fixture repo, never REPO_ROOT itself). Two namespaces the old whole-namespace compare also watched
# are dropped here, not silently: refs/remotes moves on every `git fetch` (CLAUDE.md instructs a
# `git fetch --prune` before every commit, in every worktree — the single noisiest concurrent channel
# of all); refs/tags can also move on a plain `git fetch` (tag-following is git's default) even
# without an explicit tag push. Any other namespace some other tool on this machine happens to write
# into the shared common dir (e.g. a `refs/codex/*` checkpoint ref, observed live on this checkout) is
# dropped for the same reason — it is not this file's own fixtures writing there, and ref_guard_arm
# (armed on REPO_ROOT for this whole process, below) already refuses every git-level ref write this
# file's own fixtures could make against REPO_ROOT regardless of which namespace it targets. This
# self-check is redundant proof-of-no-leak for the branch channel specifically (dir #320's own
# incident shape), not the only thing standing between a fixture bug here and the real checkout.
#
# NAMED RESIDUAL (found by this ticket's own /code-review high pass): "owned" per
# guard_owned_branches includes REPO_ROOT's OWN currently-checked-out branch — REPO_ROOT is itself
# one of the worktrees `git worktree list --porcelain` enumerates — so a hypothetical write that
# moved REPO_ROOT's own branch tip (rather than creating a new, unowned stray branch — dir #320's
# actual incident shape) would now be excluded from this compare too, same as a sibling's ordinary
# churn. Accepted, not silently: run as part of the real `./tests/run.sh` suite (this file's only
# real invocation context — it is not part of the claude-kb adopter's two-file symlink set), that
# exact scenario is still caught independently, by tests/run.sh's OWN separate before/after
# `branch --show-current`/`rev-parse HEAD` compare (dir #318), which this file's self-check never
# duplicated even before S-fix-1. The gap is real only for this one file run standalone
# (`bash tests/test_lib_ref_guard.sh`, outside `./tests/run.sh`) — a real development workflow, so
# named here rather than dismissed.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib_src="$TESTS_DIR/lib.sh"
check_file "tests/lib.sh exists" "$lib_src"

guard_lib="$REPO_ROOT/tools/lib/ref-guard.sh"
check_file "tools/lib/ref-guard.sh exists" "$guard_lib"
# shellcheck source=tools/lib/ref-guard.sh
. "$guard_lib" || { echo "tools/lib/ref-guard.sh failed to source — refusing (S-fix-1's self-check needs its ownership-scoping helpers, and a silent 'command not found' here would make the self-check vacuously pass)" >&2; exit 1; }

# repo_root_self_check_unowned OWNED_BEFORE OWNED_AFTER REFS_SNAPSHOT — the ownership-scoped filter
# this file's own self-check (at the bottom) and T14's fixture-driven proof (below) both apply, via
# the SAME seam: swapping this body from guard_union+guard_filter_unowned back to a bare passthrough
# (`printf '%s\n' "$3"` — the pre-S-fix-1 whole-namespace-equivalent shape for the refs/heads channel)
# is exactly the mutation T14(a)'s sibling-activity assertion exists to catch red. A named local
# wrapper, not a direct guard_union/guard_filter_unowned call at each site, so that one mutation
# catches every caller without also affecting tools/lib/ref-guard.sh's own coverage in
# test_ref_guard.sh. Takes OWNED_BEFORE/OWNED_AFTER rather than a pre-unioned single argument, so a
# caller needs no separate union variable of its own — the union (a sibling worktree's branch may
# start or stop being owned mid-window either way) is computed here, once per call, from whichever
# REFS_SNAPSHOT (before or after) that call is filtering.
repo_root_self_check_unowned() {
  guard_filter_unowned "$(guard_union "$1" "$2")" "$3"
}

repo_root_owned_before_self="$(guard_owned_branches "$REPO_ROOT")"
repo_root_refs_before_self="$(guard_refs_snapshot "$REPO_ROOT")"

# assert_refused LABEL CMD... — CMD is expected to exit non-zero (the guard refused a ref write).
# Refusal shapes differ by operation and git version (128 for most, 255 for a refused `worktree add`
# on some versions — E3), so this checks "not zero", not one fixed code.
assert_refused() {
  local label="$1"; shift
  run "$@"
  if [ "$STATUS" -ne 0 ]; then pass "$label"; else fail "$label" "expected a refused (non-zero) exit, got 0: $OUT"; fi
}
# assert_allowed LABEL CMD... — CMD is expected to exit zero (unaffected by the guard).
assert_allowed() {
  local label="$1"; shift
  run "$@"
  if [ "$STATUS" -eq 0 ]; then pass "$label"; else fail "$label" "expected exit 0, got $STATUS: $OUT"; fi
}

# ============================================================================================
# T1 — full integration: a fixture repo F, a child test file that sources a COPY of lib.sh and
# swallows its own ref write's failure (`|| true`, E1's own shape), still fails via G2.
# ============================================================================================
f1="$(mktemp -d "$SANDBOX/T1.XXXXXX")"
require_sandbox_path "$f1" test_lib_ref_guard_T1
git -C "$f1" init -q
git -C "$f1" commit -q --allow-empty -m init
mkdir -p "$f1/tests"
cp "$lib_src" "$f1/tests/lib.sh"
cat > "$f1/tests/test_leak.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
git -C "$REPO_ROOT" branch leak || true
summary
EOF
before_refs_t1="$(git -C "$f1" for-each-ref)"
run bash "$f1/tests/test_leak.sh"
check_status "T1: a child file whose own ref write is swallowed (|| true) still exits non-zero" 1 "$STATUS"
check_contains "T1: the G2 failure label names dir #318" "$OUT" "no test wrote the real repository's refs (dir #318)"
after_refs_t1="$(git -C "$f1" for-each-ref)"
if [ "$before_refs_t1" = "$after_refs_t1" ]; then
  pass "T1: F's for-each-ref output is unchanged"
else
  fail "T1: F's for-each-ref output is unchanged" "before=[$before_refs_t1] after=[$after_refs_t1]"
fi

# ============================================================================================
# T2 — arm a fresh fixture repo directly; branch/tag/update-ref/commit/fetch/worktree-add are all
# refused; a refused worktree add leaves no admin dir and no branch (E6).
# ============================================================================================
r2="$(new_repo)"
git -C "$r2" commit -q --allow-empty -m init
bare2="$(new_bare_origin "$r2")"
git -C "$r2" push -q origin "$(branch_raw_for "$r2")"
# So a subsequent fetch has something new to write (E1's own shape: a fetch that would be a no-op
# never reaches the hook's "prepared" state at all — E7 found exactly this).
git -C "$bare2" branch extra-on-bare "$(git -C "$bare2" rev-parse HEAD)"
ref_guard_arm "$r2"

assert_refused "T2: branch is refused"      git -C "$r2" branch t2-branch
assert_refused "T2: tag is refused"         git -C "$r2" tag t2-tag
assert_refused "T2: update-ref is refused"  git -C "$r2" update-ref refs/heads/t2-upd "$(git -C "$r2" rev-parse HEAD)"
assert_refused "T2: commit is refused"      git -C "$r2" commit -q --allow-empty -m t2-second
assert_refused "T2: fetch from a local bare is refused" git -C "$r2" fetch -q origin

wt2="$SANDBOX/T2-wt"
assert_refused "T2: worktree add -b is refused" git -C "$r2" worktree add -q -b t2-wt-branch "$wt2"
check_nodir "T2: a refused worktree add leaves no checkout dir (E6)" "$wt2"
check_nodir "T2: a refused worktree add leaves no admin dir under .git/worktrees (E6)" "$r2/.git/worktrees"
run git -C "$r2" show-ref --verify --quiet refs/heads/t2-wt-branch
check_status "T2: a refused worktree add creates no branch (E6)" 1 "$STATUS"

# ============================================================================================
# T3 — from an EXISTING linked worktree of the guarded fixture, branch is refused, and so is a
# cwd-resolved branch run from inside it (E5: the `<cd>/**` pattern covers linked worktrees too).
# ============================================================================================
r3="$(new_repo)"
git -C "$r3" commit -q --allow-empty -m init
wt3="$SANDBOX/T3-wt"
git -C "$r3" worktree add -q -b t3-peer "$wt3"
ref_guard_arm "$r3"
assert_refused "T3: branch from an existing linked worktree is refused" git -C "$wt3" branch t3-inner
assert_refused "T3: a cwd-resolved branch inside that worktree is refused" \
  bash -c 'cd "$0" && git branch t3-inner-cwd' "$wt3"

# ============================================================================================
# T4 — repo-local AND worktree-scope core.hooksPath set on the fixture: command scope still wins
# (E4). This project's own worktrees carry a worktree-scope core.hooksPath, which is exactly why
# command scope (not a config file) is load-bearing.
# ============================================================================================
# Only the core.hooksPath VALUES matter for this precedence check (branch never invokes pre-commit
# at all), so the two hooksPath targets below need not exist as real, executable hooks.
r4="$(new_repo)"
git -C "$r4" commit -q --allow-empty -m init
git -C "$r4" config core.hooksPath "$SANDBOX/T4-localhooks"
git -C "$r4" config extensions.worktreeConfig true
wt4="$SANDBOX/T4-wt"
git -C "$r4" worktree add -q -b t4-peer "$wt4"
git -C "$wt4" config --worktree core.hooksPath "$SANDBOX/T4-wthooks"
ref_guard_arm "$r4"
assert_refused "T4: branch refused even with repo-local AND worktree-scope core.hooksPath set (E4)" \
  git -C "$r4" branch t4-branch

# ============================================================================================
# T5 — an unrelated repo, and a clone of the guarded fixture, accept branch and commit.
# ============================================================================================
r5="$(new_repo)"
git -C "$r5" commit -q --allow-empty -m init
ref_guard_arm "$r5"

unrelated5="$(new_repo)"
git -C "$unrelated5" commit -q --allow-empty -m init
assert_allowed "T5: an unrelated repo accepts branch" git -C "$unrelated5" branch t5-unrelated-branch
assert_allowed "T5: an unrelated repo accepts commit" git -C "$unrelated5" commit -q --allow-empty -m t5-second

clone5="$SANDBOX/T5-clone"
run git clone -q "$r5" "$clone5"
check_status "T5: cloning the guarded repo succeeds (reading is fine)" 0 "$STATUS"
assert_allowed "T5: a clone of the guarded repo accepts branch" git -C "$clone5" branch t5-clone-branch
assert_allowed "T5: a clone of the guarded repo accepts commit" git -C "$clone5" commit -q --allow-empty -m t5-second

# ============================================================================================
# T6 — miscellaneous guard-mechanics checks.
# ============================================================================================

# ref_guard_arm on a non-git dir is a silent no-op, exit 0, no NOTE.
nongit6="$(mktemp -d "$SANDBOX/T6-nongit.XXXXXX")"
nongit6_err="$SANDBOX/T6-nongit.stderr"
if ref_guard_arm "$nongit6" 2>"$nongit6_err"; then
  pass "T6: ref_guard_arm on a non-git dir returns 0"
else
  fail "T6: ref_guard_arm on a non-git dir returns 0" "returned $?"
fi
check_absent "T6: ref_guard_arm on a non-git dir prints no NOTE (silent no-op)" "$(cat "$nongit6_err")" "NOTE"

# Arming twice (nested) keeps the earlier GIT_CONFIG_KEY_* entries intact and appends.
r6b="$(new_repo)"; git -C "$r6b" commit -q --allow-empty -m init
r6c="$(new_repo)"; git -C "$r6c" commit -q --allow-empty -m init
count_before_t6="${GIT_CONFIG_COUNT:-0}"
key_at_before_index_var="GIT_CONFIG_KEY_${count_before_t6}"
ref_guard_arm "$r6b"
key_at_before_index="${!key_at_before_index_var:-}"
ref_guard_arm "$r6c"
key_at_before_index_after="${!key_at_before_index_var:-}"
check_ne "T6: nested arming increases GIT_CONFIG_COUNT" "$count_before_t6" "$GIT_CONFIG_COUNT"
if [ -n "$key_at_before_index" ] && [ "$key_at_before_index" = "$key_at_before_index_after" ]; then
  pass "T6: nested arming keeps the earlier GIT_CONFIG_KEY_* entry intact"
else
  fail "T6: nested arming keeps the earlier GIT_CONFIG_KEY_* entry intact" \
    "before=[$key_at_before_index] after=[$key_at_before_index_after]"
fi
assert_refused "T6: after nested arming, the FIRST fixture (r6b) is still guarded" git -C "$r6b" branch t6b-branch
assert_refused "T6: after nested arming, the SECOND fixture (r6c) is also guarded" git -C "$r6c" branch t6c-branch

# A fixture repo under a dir whose name contains '[' is either guarded or NOTE-skipped (V1, G1 step 5).
br6="$SANDBOX/T6-br[ack]et"
mkdir -p "$br6"
git -C "$br6" init -q
git -C "$br6" commit -q --allow-empty -m init
ref_guard_arm "$br6"
br6_hooks="$(git -C "$br6" config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$br6_hooks" ]; then
  assert_refused "T6 (V1): a dir with a literal '[' in its name is guarded (escaped) and refuses writes" \
    git -C "$br6" branch t6-inbracket
else
  pass "T6 (V1): a dir with a literal '[' in its name was NOT armed — NOTE-skipped per G1 step 5's fallback"
fi

# With an "old git" (simulated: GIT_CONFIG_COUNT/KEY/VALUE dropped before delegating, as a pre-2.31
# git would never look at them at all) on PATH for the arm call only, the step 6 self-check prints
# its NOTE — the guard never fails open silently.
oldgit_dir="$(mktemp -d "$SANDBOX/T6-oldgit.XXXXXX")"
real_git_bin="$(command -v git)"
oldgit_body='#!/bin/sh
unset GIT_CONFIG_COUNT
i=0
while [ "$i" -le 10 ]; do
  eval "unset GIT_CONFIG_KEY_$i GIT_CONFIG_VALUE_$i"
  i=$((i + 1))
done
exec __REALGIT__ "$@"
'
oldgit_body="${oldgit_body//__REALGIT__/$real_git_bin}"
printf '%s' "$oldgit_body" > "$oldgit_dir/git"
chmod +x "$oldgit_dir/git"
r6d="$(new_repo)"; git -C "$r6d" commit -q --allow-empty -m init
oldgit_note="$(PATH="$oldgit_dir:$PATH" ref_guard_arm "$r6d" 2>&1 1>/dev/null)"
check_contains "T6: an inert (pre-2.31-shaped) git makes the self-check print its NOTE" \
  "$oldgit_note" "NOTE: dir #318 ref guard did not arm"

# Under the armed env, `git config --list` exits 0, run from a cwd that is neither the sandbox nor
# REPO_ROOT — pins E20's two fatal shapes (a relative include value, a non-integer count): either one
# would make EVERY git call in this process die with "fatal: unable to parse command-line config".
run_in "$(dirname "$SANDBOX")" git config --list
check_status "T6: git config --list exits 0 under the armed env from a neutral cwd (E20)" 0 "$STATUS"

# G1 item 7's rule is pinned in tests/lib.sh's own header.
pin "T6: tests/lib.sh's header states the ref-namespace rule" "$lib_src" \
  'git clone "$REPO_ROOT" into $SANDBOX and write in the clone' \
  "expected G1 item 7's rule in tests/lib.sh's header"

# ...and the hook's own stderr line names dir #318 and the remedy.
r6e="$(new_repo)"; git -C "$r6e" commit -q --allow-empty -m init
ref_guard_arm "$r6e"
run git -C "$r6e" branch t6e-branch
check_contains "T6: the hook's stderr line names dir #318" "$OUT" "dir #318"
check_contains "T6: the hook's stderr line names the remedy (new_repo/clone)" "$OUT" "new_repo()"

# ============================================================================================
# T12 — seams raised by the release manager (E19), probed live.
# ============================================================================================

# (a) An inherited GIT_DIR pointing at the guarded fixture's gitdir binds even via `-C <other>`.
r12="$(new_repo)"
git -C "$r12" commit -q --allow-empty -m init
ref_guard_arm "$r12"
other12="$(new_repo)"
git -C "$other12" commit -q --allow-empty -m init
assert_refused "T12: an inherited GIT_DIR pointing at the guarded fixture is refused even via -C <other> (E19a)" \
  env GIT_DIR="$r12/.git" git -C "$other12" branch t12-inherited-gitdir

# (b) A sandbox repo with its own core.hooksPath still runs its own hook, unaffected by guards armed
# elsewhere in this same process.
sbx12="$(new_repo)"
mkdir -p "$SANDBOX/T12-ownhooks"
marker12="$SANDBOX/T12-ownhooks-marker"
own_hook_body='#!/bin/sh
touch "__MARKER__"
exit 0
'
own_hook_body="${own_hook_body//__MARKER__/$marker12}"
printf '%s' "$own_hook_body" > "$SANDBOX/T12-ownhooks/pre-commit"
chmod +x "$SANDBOX/T12-ownhooks/pre-commit"
git -C "$sbx12" config core.hooksPath "$SANDBOX/T12-ownhooks"
git -C "$sbx12" commit -q --allow-empty -m t12-own-hook
check_file "T12: a sandbox repo's own pre-commit still ran despite guards armed elsewhere (E19e)" "$marker12"

# (c) ref_guard_arm on a path whose common dir resolves EMPTY (a `cd` into a bogus relative path
# fails, so nothing is printed) arms nothing and prints the NOTE — never a pattern that could match
# every repository (G1 step 1).
badcd_dir="$(mktemp -d "$SANDBOX/T12-badcd.XXXXXX")"
badcd_body='#!/bin/sh
args="$*"
case "$args" in
  *"rev-parse --git-common-dir")
    printf "no-such-subdir-T12\n"
    exit 0
    ;;
esac
exec __REALGIT__ "$@"
'
badcd_body="${badcd_body//__REALGIT__/$real_git_bin}"
printf '%s' "$badcd_body" > "$badcd_dir/git"
chmod +x "$badcd_dir/git"
r12c="$(new_repo)"; git -C "$r12c" commit -q --allow-empty -m init
badcd_note="$(PATH="$badcd_dir:$PATH" ref_guard_arm "$r12c" 2>&1 1>/dev/null)"
check_contains "T12: an empty resolved common dir arms nothing and prints the NOTE (G1 step 1)" \
  "$badcd_note" "could not resolve a usable git common dir"
r12c_hooks="$(git -C "$r12c" config --get core.hooksPath 2>/dev/null || true)"
if [ -z "$r12c_hooks" ]; then
  pass "T12: an empty resolved common dir arms nothing — core.hooksPath stays unset"
else
  fail "T12: an empty resolved common dir arms nothing — core.hooksPath stays unset" "got [$r12c_hooks]"
fi

# ============================================================================================
# T13 — dir #644 residual N8, closed. Reproduced live (git 2.52.0, this host — E19(c) itself was
# probed on Homebrew 2.52.0): an inherited GIT_DIR (whether or not paired with a foreign
# GIT_COMMON_DIR) is NOT bound by ref_guard_arm's includeIf.gitdir pattern unless it names the
# guarded repo's OWN gitdir (E19a/b) — so a GIT_DIR naming any OTHER real repo makes `git -C
# <target>` silently operate on THAT other repo instead of the one named on the command line: the
# write escapes -C entirely, unrefused, and lands in the ambient repo. tests/lib.sh now unsets
# GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE before its own first git call, closing this for
# every process that sources it — once unset, -C is the only thing left that can select a repo.
#
# `other13` and `foreign13` are BOTH created in THIS (unpoisoned) process, before the child ever
# runs — load-bearing: `new_repo()` is itself a `git init`, and `git init` under an ambient GIT_DIR
# does not create a `.git` in its own `-C` target at all, it silently no-ops against GIT_DIR's repo
# instead (verified live) — a fixture created INSIDE the poisoned child would never become a real repo
# to begin with, and any later `-C other` read-back inside that same child is reading through the
# exact mechanism under test, which is no proof of anything. Reading `other13`/`foreign13` back from
# THIS unpoisoned process after the child exits is what makes the result trustworthy. Reproduced via a
# CHILD process (T1's own idiom) only for `g13` (the fixture that must itself source a COPY of
# tests/lib.sh — the thing dir #644 actually changed): fixture g13 stands in for "the real repo" being
# protected; `foreign13` stands in for whatever repo an inherited GIT_DIR happens to name;
# `other13` is the repo -C names, i.e. the one the write is SUPPOSED to land in.
#
# Escape from the spec (docs/specs/318-test-ref-isolation.md E19(c)): its own wording — "the branch
# landed in the real repo [GIT_COMMON_DIR's target]" — did not reproduce live on this host/git
# version; the write reproducibly lands in GIT_DIR's target (foreign13) instead, GIT_COMMON_DIR
# playing no observable role either way. The underlying claim this ticket exists to close — an
# ambient var makes `-C` lose control of which repo is written to, unrefused — reproduces exactly as
# described; only the WHICH-repo detail differs. Recorded in the PR body (dir #644 escapes).
# ============================================================================================
g13="$(new_repo)"
git -C "$g13" commit -q --allow-empty -m init
mkdir -p "$g13/tests"
cp "$lib_src" "$g13/tests/lib.sh"
g13_common_dir="$(git -C "$g13" rev-parse --git-common-dir)"
case "$g13_common_dir" in /*) ;; *) g13_common_dir="$g13/$g13_common_dir" ;; esac
foreign13="$(new_repo)"; git -C "$foreign13" commit -q --allow-empty -m init
other13="$(new_repo)"; git -C "$other13" commit -q --allow-empty -m init
cat > "$g13/tests/test_leak_n8.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
. "\$(dirname "\$0")/lib.sh"
run git -C '$other13' branch t13-n8
printf 'STATUS=%s\n' "\$STATUS"
summary
EOF
g13_refs_before="$(git -C "$g13" for-each-ref)"
foreign13_refs_before="$(git -C "$foreign13" for-each-ref)"
child13_out="$(env GIT_DIR="$foreign13/.git" GIT_COMMON_DIR="$g13_common_dir" bash "$g13/tests/test_leak_n8.sh" 2>&1)"
g13_refs_after="$(git -C "$g13" for-each-ref)"
foreign13_refs_after="$(git -C "$foreign13" for-each-ref)"
other13_branches_after="$(git -C "$other13" branch --format='%(refname:short)' | tr '\n' ',')"

check_contains "T13: the write against -C other13 under an ambient GIT_DIR=foreign13 exits 0 (unrefused)" \
  "$child13_out" "STATUS=0"
check_contains "T13: the branch landed in other13, the repo actually named via -C (N8 closed)" \
  "$other13_branches_after" "t13-n8,"
check_block_equal "T13: g13's own refs are unchanged" "$g13_refs_before" "$g13_refs_after"
check_block_equal "T13: foreign13's own refs are unchanged — the ambient GIT_DIR named it but did not divert the write into it" \
  "$foreign13_refs_before" "$foreign13_refs_after"

# ============================================================================================
# T14 — S-fix-1: the self-check's own ownership-scoped compare, fixture-driven (never against the
# real REPO_ROOT, which this file cannot safely leak-simulate against). tools/lib/ref-guard.sh's own
# test_ref_guard.sh already covers guard_owned_branches/guard_refs_snapshot/guard_filter_unowned/
# guard_union in isolation; this scenario instead pins repo_root_self_check_unowned() above — the
# exact seam this file's own self-check (below) calls — via a fixture repo standing in for REPO_ROOT.
# ============================================================================================
r14="$(new_repo)"
git -C "$r14" commit -q --allow-empty -m init

# (a) sibling-worktree activity during the window: a linked worktree branching and committing on ITS
# OWN branch is ordinary concurrent work (this repo's own fleet of worktrees), not a leak — the
# scoped compare must stay green.
wt14="$SANDBOX/T14-sibling-wt"
run git -C "$r14" worktree add -q -b t14-sibling "$wt14"
check_status "T14: sibling worktree add for the fixture succeeds" 0 "$STATUS"
owned_before_t14a="$(guard_owned_branches "$r14")"
refs_before_t14a="$(guard_refs_snapshot "$r14")"
git -C "$wt14" commit -q --allow-empty -m "t14 sibling commit"
owned_after_t14a="$(guard_owned_branches "$r14")"
refs_after_t14a="$(guard_refs_snapshot "$r14")"
unowned_before_t14a="$(repo_root_self_check_unowned "$owned_before_t14a" "$owned_after_t14a" "$refs_before_t14a")"
unowned_after_t14a="$(repo_root_self_check_unowned "$owned_before_t14a" "$owned_after_t14a" "$refs_after_t14a")"
if [ "$unowned_before_t14a" = "$unowned_after_t14a" ]; then
  pass "T14(a): sibling-worktree commit activity during the window stays green (scoped compare)"
else
  fail "T14(a): sibling-worktree commit activity during the window stays green (scoped compare)" \
    "before=[$unowned_before_t14a] after=[$unowned_after_t14a]"
fi

# (b) an unowned branch created directly in the fixture's main repo (nobody's worktree) during the
# window — the exact shape dir #320's own incident took — must still trip red.
owned_before_t14b="$(guard_owned_branches "$r14")"
refs_before_t14b="$(guard_refs_snapshot "$r14")"
git -C "$r14" branch t14-unowned-leak
owned_after_t14b="$(guard_owned_branches "$r14")"
refs_after_t14b="$(guard_refs_snapshot "$r14")"
unowned_before_t14b="$(repo_root_self_check_unowned "$owned_before_t14b" "$owned_after_t14b" "$refs_before_t14b")"
unowned_after_t14b="$(repo_root_self_check_unowned "$owned_before_t14b" "$owned_after_t14b" "$refs_after_t14b")"
check_ne "T14(b): an unowned branch appearing during the window trips the scoped compare (red path pinned)" \
  "$unowned_before_t14b" "$unowned_after_t14b"
check_contains "T14(b): the unowned leak branch is the reported difference" "$unowned_after_t14b" "t14-unowned-leak"
git -C "$r14" branch -D t14-unowned-leak >/dev/null

# The authoritative check this whole file rests on: REPO_ROOT's own UNOWNED refs/heads branches
# (S-fix-1: scoped, not the whole namespace — see the header comment), proven unchanged by direct
# comparison — not by trusting the shared refused-log's contents, since that log cannot say which
# armed repo each refusal came from (every fixture above points its guard.cfg at the same
# $SANDBOX/ref-guard/hooks). This is what actually rules out a leak into the real checkout, without
# false-tripping on a sibling worktree's own ordinary branch churn.
repo_root_owned_after_self="$(guard_owned_branches "$REPO_ROOT")"
repo_root_refs_after_self="$(guard_refs_snapshot "$REPO_ROOT")"
repo_root_refs_before_self_unowned="$(repo_root_self_check_unowned "$repo_root_owned_before_self" "$repo_root_owned_after_self" "$repo_root_refs_before_self")"
repo_root_refs_after_self_unowned="$(repo_root_self_check_unowned "$repo_root_owned_before_self" "$repo_root_owned_after_self" "$repo_root_refs_after_self")"
if [ "$repo_root_refs_before_self_unowned" = "$repo_root_refs_after_self_unowned" ]; then
  pass "self-check: REPO_ROOT's own unowned refs/heads branches are unchanged after every fixture above"
else
  fail "self-check: REPO_ROOT's own unowned refs/heads branches are unchanged after every fixture above" \
    "an unowned branch appeared, moved, or disappeared in REPO_ROOT — this is a real leak, not an
expected fixture refusal, and not explained by any sibling worktree's own branch churn. diff:
$(diff <(printf '%s\n' "$repo_root_refs_before_self_unowned") <(printf '%s\n' "$repo_root_refs_after_self_unowned"))"
fi

# Having proven that directly, the shared refused-log's entries can only be this file's own
# deliberate T2/T3/T4/T6/T12 fixture refusals (dir #318, G2's own log path is one-per-$SANDBOX, sized
# for the normal one-arm-per-process case) — clear it before summary() so this file's own intentional
# coverage of the guard doesn't fail itself via the exact mechanism it's testing. This is a clear, not
# a per-line inspection: the log's own content has no way to name which armed repo a line came from
# (see the header comment), so the ref-state proof above is what does the real work here.
: > "$SANDBOX/ref-guard/refused"

summary
