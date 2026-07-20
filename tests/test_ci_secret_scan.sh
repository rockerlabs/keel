#!/usr/bin/env bash
# test_ci_secret_scan.sh — tools/secret-guard/ci-scan.sh (backlog dir #37 / SEC4): the CI-side range
# resolution that hands a pull_request's base..head or a push's before..after to secret-scan.sh
# --range. Exercises the script directly with the same env vars ci.yml passes it, so this is verified
# without a GitHub Actions runner. Covers tools/secret-guard/range-lib.sh's resolve_range_ci()
# indirectly through ci-scan.sh, the same way test_secret_guard.sh covers resolve_range_local()
# through the pre-push hook.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

ci="$REPO_ROOT/tools/secret-guard/ci-scan.sh"
zero="$(rep 0 40)"

# --- pull_request: a key introduced between base and head is BLOCKED ----------------------------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/b.txt"
git -C "$repo" add b.txt; git -C "$repo" commit -qm withkey
head="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=pull_request GITHUB_BASE_SHA="$base" GITHUB_HEAD_SHA="$head" "$ci"
check_status "pull_request: key introduced in the range -> BLOCKED" 1 "$STATUS"
check_contains "reports BLOCKED" "$OUT" "BLOCKED"

# --- pull_request: a clean range stays clean -----------------------------------------------------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf 'still nothing secret\n' > "$repo/b.txt"; git -C "$repo" add b.txt; git -C "$repo" commit -qm clean
head="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=pull_request GITHUB_BASE_SHA="$base" GITHUB_HEAD_SHA="$head" "$ci"
check_status "pull_request: clean range -> exit 0" 0 "$STATUS"

# --- push: before..after with an introduced key is BLOCKED ---------------------------------------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
before="$(git -C "$repo" rev-parse HEAD)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/b.txt"
git -C "$repo" add b.txt; git -C "$repo" commit -qm withkey
after="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$before" GITHUB_EVENT_AFTER="$after" "$ci"
check_status "push: key introduced in before..after -> BLOCKED" 1 "$STATUS"

# --- push: before is the all-zero sha (new branch's first push) -> scans the root commit ---------
repo="$(new_repo)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/root.txt"
git -C "$repo" add root.txt; git -C "$repo" commit -qm root
after="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$zero" GITHUB_EVENT_AFTER="$after" "$ci"
check_status "push: all-zero before (first push) still scans the root commit -> BLOCKED" 1 "$STATUS"

# --- push: all-zero before, in a REAL CI checkout topology (not just a remote-less sandbox repo) --
# pre-push's local "--not --remotes" trick only works because a local hook runs BEFORE git updates the
# remote-tracking refs for its own push. A CI checkout runs AFTER the push already landed, so
# refs/remotes/origin/* there already equals $after — resolve_range_ci must NOT reuse that trick (it
# would self-exclude everything and report a brand-new ref's first push as clean). Reproduce the real
# topology: push to a bare "remote", then clone it (a clone's origin/* mirrors what actions/checkout's
# fetch-depth:0 leaves behind) ------------------------------------------------------------------------
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
work="$(mktemp -d "$SANDBOX/work.XXXXXX")"; git -C "$work" init -q
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$work/root.txt"
git -C "$work" add root.txt; git -C "$work" commit -qm root
sha="$(git -C "$work" rev-parse HEAD)"
git -C "$work" push -q "$bare" HEAD:refs/heads/main
clone="$(mktemp -d "$SANDBOX/clone.XXXXXX")"; rmdir "$clone"
git clone -q "$bare" "$clone"
run_in "$clone" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$zero" GITHUB_EVENT_AFTER="$sha" "$ci"
check_status "push: first-push root commit survives a real CI clone's post-push remote state -> BLOCKED" 1 "$STATUS"

# --- push: after is the all-zero sha (ref deletion) -> an explicit clean skip, not an accidental one
# via a swallowed git error on an unresolvable before..0000...0 range ------------------------------
repo="$(new_repo)"
git -C "$repo" commit -q --allow-empty -m base
before="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$before" GITHUB_EVENT_AFTER="$zero" "$ci"
check_status "push: all-zero after (ref deletion) -> exit 0 (explicit skip)" 0 "$STATUS"
check_contains "names it as a deletion, not silent success" "$OUT" "deleted"

# --- a session trailer in a pushed commit message is caught the same way as the pre-push hook ------
repo="$(new_repo)"
git -C "$repo" commit -q --allow-empty -m base
before="$(git -C "$repo" rev-parse HEAD)"
trailer="$(printf 'Claude-%s: https://claude.ai/code/%s_test' Session session)"
git -C "$repo" commit -q --allow-empty -m msg -m "$trailer"
after="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$before" GITHUB_EVENT_AFTER="$after" "$ci"
check_status "push: session trailer in a commit message -> BLOCKED" 1 "$STATUS"
check_contains "labels the offending commit message" "$OUT" "message"

# --- a required env var missing is a config error (exit 2) — must NOT collide with exit 1 ("a secret
# was found"), which a bash `${VAR:?msg}` abort would have produced -------------------------------
repo="$(new_repo)"
git -C "$repo" commit -q --allow-empty -m base
sha="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$sha" "$ci"
check_status "push: missing GITHUB_EVENT_AFTER -> exit 2, not 1" 2 "$STATUS"
run_in "$repo" env GITHUB_EVENT_NAME=pull_request GITHUB_BASE_SHA="$sha" "$ci"
check_status "pull_request: missing GITHUB_HEAD_SHA -> exit 2, not 1" 2 "$STATUS"

# --- an unsupported or missing event name is also a config error, not a silent clean pass — both fall
# through the same case statement's catch-all arm, so one loop covers both inputs -------------------
for ev in workflow_dispatch ""; do
  run_in "$repo" env GITHUB_EVENT_NAME="$ev" "$ci"
  check_status "event name '$ev' -> exit 2 (config error)" 2 "$STATUS"
done

# --- push: an ORPHANED before-sha (force-push topology) falls back to full-history scan ----------
# The clone doesn't have "before" after a force-push; before..after must not read as exit-2 config
# error (nor, pre-2026-07-21, silently "clean") — ci-scan degrades to the zero-sha full scan.
repo="$(new_repo)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/root.txt"
git -C "$repo" add root.txt; git -C "$repo" commit -qm root
after="$(git -C "$repo" rev-parse HEAD)"
orphan="$(rep d 40)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$after" "$ci"
check_status "push: orphaned before (force-push) -> full scan still BLOCKS the key" 1 "$STATUS"
check_contains "announces the fallback" "$OUT" "scanning full history"

repo="$(new_repo)"
printf 'clean\n' > "$repo/root.txt"
git -C "$repo" add root.txt; git -C "$repo" commit -qm root
after="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$after" "$ci"
check_status "push: orphaned before over a clean history -> exit 0" 0 "$STATUS"

# --- the scanner missing next to ci-scan.sh is a config error, not a raw exec failure --------------
missing="$(mktemp -d "$SANDBOX/missing.XXXXXX")"
cp "$ci" "$missing/ci-scan.sh"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$sha" GITHUB_EVENT_AFTER="$sha" \
  "$missing/ci-scan.sh"
check_status "scanner not found next to ci-scan.sh -> exit 2" 2 "$STATUS"
check_contains "names the problem" "$OUT" "scanner not found"

summary
