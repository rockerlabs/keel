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
# guard/refused is one shared log per $SANDBOX (G1/G2's own design, sized for the normal case of one
# arm call per real test file), so this file's own deliberate refusals (T2 onward) land in the exact
# file G2's summary() reads. Verified explicitly instead of assumed: REPO_ROOT's own refs are
# snapshotted below and compared again at the end, and the shared log is inspected line-by-line
# against the fixture repos this file itself created before being cleared ahead of the final
# summary() — never blindly, so a genuine leak into REPO_ROOT still fails this file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib_src="$TESTS_DIR/lib.sh"
check_file "tests/lib.sh exists" "$lib_src"
repo_root_refs_before_self="$(git -C "$REPO_ROOT" for-each-ref)"

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

# The authoritative check this whole file rests on: REPO_ROOT's own refs, proven unchanged by direct
# comparison — not by trusting the shared refused-log's contents, since that log cannot say which
# armed repo each refusal came from (every fixture above points its guard.cfg at the same
# $SANDBOX/ref-guard/hooks). This is what actually rules out a leak into the real checkout.
repo_root_refs_after_self="$(git -C "$REPO_ROOT" for-each-ref)"
if [ "$repo_root_refs_before_self" = "$repo_root_refs_after_self" ]; then
  pass "self-check: REPO_ROOT's own refs are unchanged after every fixture above"
else
  fail "self-check: REPO_ROOT's own refs are unchanged after every fixture above" \
    "REPO_ROOT's refs changed — this is a real leak, not an expected fixture refusal"
fi

# Having proven that directly, the shared refused-log's entries can only be this file's own
# deliberate T2/T3/T4/T6/T12 fixture refusals (dir #318, G2's own log path is one-per-$SANDBOX, sized
# for the normal one-arm-per-process case) — clear it before summary() so this file's own intentional
# coverage of the guard doesn't fail itself via the exact mechanism it's testing.
: > "$SANDBOX/ref-guard/refused"

summary
