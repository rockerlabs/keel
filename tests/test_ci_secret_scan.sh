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

# --- the SAME orphaned-before fallback, combined with a genuinely PRE-EXISTING allowlist entry
# (dir #518 residual, disclosed — found by three independent max-review reviewer angles, confirmed
# live): resolve_range_ci's fallback shape scans the FULL history from "after" with NO exclusion at
# all, so secret-scan.sh's own --range allowlist-baseline resolution (git rev-list --boundary) finds
# ZERO boundary commits (nothing is excluded from the walk) and correctly, but conservatively, fails
# CLOSED — even a legitimately old, several-commits-back allowlist entry reads as new-this-push, and
# the otherwise-exempted key still BLOCKS. This is the SAME fail-closed fallback the ticket names for
# "no shared history at all" (dir #518's own lead 1), reached here via a different trigger (an
# orphaned before-sha, not a brand-new branch's first push) — there is no principled single baseline
# to fall back to here either (the true pre-force-push remote state is exactly what's unreachable),
# so this is accepted, not a bug: safe (over-blocking, never a silent pass), pinned by this test
# rather than left an untested gap. dir #572 keeps this exact outcome for the no-remote/no-hatch
# case below, and adds the two principled ways OUT of it (fetch the orphan; the operator hatch).
repo="$(new_repo)"
printf '%s\n' "$(key 'AKIA' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
printf 'unrelated\n' > "$repo/mid.txt"; git -C "$repo" add mid.txt; git -C "$repo" commit -qm "unrelated commit"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/root.txt"
git -C "$repo" add root.txt; git -C "$repo" commit -qm "add the exempted key"
after="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$after" "$ci"
check_status "push: orphaned before + a genuinely pre-existing allowlist entry -> still BLOCKS (disclosed fail-closed residual, dir #518)" 1 "$STATUS"
check_contains "the fail-closed message names the escape hatch (dir #572 lead 3: a hatch nobody can find is a silent pass one step removed)" \
  "$OUT" "SECRET_SCAN_CI_FORCE_PUSH_BASELINE"

# --- dir #572 (a): the orphaned "before" is still SERVABLE by sha from the remote, so ci-scan fetches
# it and the scan proceeds as an ordinary before..after — the pre-existing allowlist entry resolves at
# the boundary and exempts the key it was written for. This is the whole point of the ticket: the
# fail-closed fallback above was the ONLY behaviour, and it fired even when a principled baseline was
# one `git fetch` away. Needs a REAL force-push topology over file:// transport: a hardlinked local
# clone would already hold the orphan and prove nothing (confirmed live — `git clone <path>` copies
# unreachable objects too, `git clone file://<path>` does not) ---------------------------------------
fbare="$(mktemp -d "$SANDBOX/fbare.XXXXXX")"; git init -q --bare "$fbare"
fwork="$(mktemp -d "$SANDBOX/fwork.XXXXXX")"; git -C "$fwork" init -q
printf '%s\n' "$(key 'AKIA' 'A')" > "$fwork/.secret-scan-allow"
git -C "$fwork" add .secret-scan-allow; git -C "$fwork" commit -qm "add allowlist"
fbase="$(git -C "$fwork" rev-parse HEAD)"
printf 'unrelated\n' > "$fwork/mid.txt"; git -C "$fwork" add mid.txt; git -C "$fwork" commit -qm "the commit a force-push will orphan"
fbefore="$(git -C "$fwork" rev-parse HEAD)"
git -C "$fwork" push -q "$fbare" HEAD:refs/heads/main
git -C "$fwork" reset -q --hard "$fbase"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$fwork/key.txt"
git -C "$fwork" add key.txt; git -C "$fwork" commit -qm "add the exempted key"
fafter="$(git -C "$fwork" rev-parse HEAD)"
git -C "$fwork" push -qf "$fbare" HEAD:refs/heads/main
fclone="$(mktemp -d "$SANDBOX/fclone.XXXXXX")"; rmdir "$fclone"
git clone -q "file://$fbare" "$fclone"
# The premise this whole case rests on: the clone genuinely does NOT have the orphaned before-sha.
# Asserted as a string, not via check_status — `git cat-file -e` on a missing object only promises a
# NON-ZERO exit, and the actual code varies (128 on git 2.52 here), so pinning one would be a
# version-fragile assertion about git rather than about this fixture.
run_in "$fclone" bash -c 'git cat-file -e "$1^{commit}" 2>/dev/null && echo PRESENT || echo ABSENT' _ "$fbefore"
check_contains "dir #572 premise: the orphaned before-sha really is absent from the CI clone" "$OUT" "ABSENT"
run_in "$fclone" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$fbefore" GITHUB_EVENT_AFTER="$fafter" "$ci"
check_status "push: orphaned but FETCHABLE before -> baseline resolves, pre-existing entry exempts, exit 0" 0 "$STATUS"
check_contains "says it recovered the real before-sha rather than degrading" "$OUT" "fetched it from origin"

# --- dir #572 (c): the orphan is unrecoverable (no origin at all) but the operator sets the hatch to a
# trusted pre-force-push rev -> the scan runs against THAT baseline and the entry exempts again -------
repo="$(new_repo)"
printf '%s\n' "$(key 'AKIA' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
hbase="$(git -C "$repo" rev-parse HEAD)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/key.txt"
git -C "$repo" add key.txt; git -C "$repo" commit -qm "add the exempted key"
after="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$after" \
  SECRET_SCAN_CI_FORCE_PUSH_BASELINE="$hbase" "$ci"
check_status "push: unfetchable orphan + operator hatch -> scans hatch..after, entry exempts, exit 0" 0 "$STATUS"
check_contains "logs the hatch loudly rather than using it silently" "$OUT" "operator-supplied SECRET_SCAN_CI_FORCE_PUSH_BASELINE"

# a hatch that resolves to nothing is a CONFIG error (exit 2), never a silent degrade to the
# full-history fallback: the operator believes the hatch is in force, and 1 would read as "a secret
# was found". Same for the degenerate paste of the pushed head itself, whose range scans nothing.
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$after" \
  SECRET_SCAN_CI_FORCE_PUSH_BASELINE="no-such-rev-here" "$ci"
check_status "push: hatch that does not resolve to a commit -> exit 2 (config error), not 0 or 1" 2 "$STATUS"
check_contains "names the unresolvable value" "$OUT" "does not resolve to a commit"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$after" \
  SECRET_SCAN_CI_FORCE_PUSH_BASELINE="$after" "$ci"
check_status "push: hatch set to the pushed head itself -> exit 2, not an empty range scanning nothing" 2 "$STATUS"
check_contains "says why the degenerate baseline is refused" "$OUT" "would scan nothing"

# The real before-sha WINS over a set hatch, and says so — an operator must never be left believing a
# stale hatch shaped the scan. Needs a SECOND, pristine clone: the fetch above is a side effect on the
# object db, so re-running in $fclone would find the orphan already present and skip this arm entirely
# (caught by this assertion failing on the first run against the reused clone).
fclone2="$(mktemp -d "$SANDBOX/fclone2.XXXXXX")"; rmdir "$fclone2"
git clone -q "file://$fbare" "$fclone2"
run_in "$fclone2" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$fbefore" GITHUB_EVENT_AFTER="$fafter" \
  SECRET_SCAN_CI_FORCE_PUSH_BASELINE="$fbase" "$ci"
check_status "push: fetchable orphan wins over a set hatch -> exit 0" 0 "$STATUS"
check_contains "announces the hatch as not needed" "$OUT" "was not needed"

# --- max-review finding, reproduced live: the degenerate-range guard must catch a DESCENDANT of
# "after", not only an exact-equality paste. `git rev-list X..Y` is empty whenever Y is reachable
# from X — true for X == Y (already covered above) AND for any X that is a proper descendant of Y.
# The equality-only guard this replaced would have let this through silently (exit 0, no scan). ------
repo="$(new_repo)"
git -C "$repo" commit -q --allow-empty -m base
descbase="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" commit -q --allow-empty -m child
descchild="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$descbase" \
  SECRET_SCAN_CI_FORCE_PUSH_BASELINE="$descchild" "$ci"
check_status "push: hatch is a DESCENDANT of after (not equal) -> exit 2, not a silent empty-range pass (dir #572 max-review finding)" 2 "$STATUS"
check_contains "names it as scanning nothing, the same message as the equality case" "$OUT" "would scan nothing"

# --- max-review finding: the hatch must ALSO be tried via fetch, not only checked locally — the exact
# same "servable by sha until gc'd" property the auto-recovery above relies on applies to whatever rev
# the operator names too. Without this, a hatch naming a genuinely dangling-but-still-fetchable commit
# spuriously failed as "does not resolve to a commit in this clone". -------------------------------
# Content is deliberately clean on both sides here — this test's only job is proving the hatch value
# itself gets fetched and resolved, not exercising the allowlist-boundary walk (already covered by
# other cases above): htrusted and hafter are sibling commits off a common root, so the boundary walk
# for "htrusted..hafter" would need its own separate reasoning about a non-ancestor exclusion seed,
# which is orthogonal to what this test checks.
hbare="$(mktemp -d "$SANDBOX/hbare.XXXXXX")"; git init -q --bare "$hbare"
hwork="$(mktemp -d "$SANDBOX/hwork.XXXXXX")"; git -C "$hwork" init -q
git -C "$hwork" commit -q --allow-empty -m root
hroot="$(git -C "$hwork" rev-parse HEAD)"
git -C "$hwork" commit -q --allow-empty -m "the commit a force-push will orphan"
htrusted="$(git -C "$hwork" rev-parse HEAD)"
git -C "$hwork" push -q "$hbare" HEAD:refs/heads/main
git -C "$hwork" reset -q --hard "$hroot"
printf 'clean\n' > "$hwork/clean.txt"
git -C "$hwork" add clean.txt; git -C "$hwork" commit -qm "a clean sibling history"
hafter="$(git -C "$hwork" rev-parse HEAD)"
git -C "$hwork" push -qf "$hbare" HEAD:refs/heads/main
hclone="$(mktemp -d "$SANDBOX/hclone.XXXXXX")"; rmdir "$hclone"
git clone -q "file://$hbare" "$hclone"
run_in "$hclone" bash -c 'git cat-file -e "$1^{commit}" 2>/dev/null && echo PRESENT || echo ABSENT' _ "$htrusted"
check_contains "premise: the hatch target is genuinely absent from this clone too" "$OUT" "ABSENT"
run_in "$hclone" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$orphan" GITHUB_EVENT_AFTER="$hafter" \
  SECRET_SCAN_CI_FORCE_PUSH_BASELINE="$htrusted" "$ci"
check_status "push: hatch names a dangling-but-fetchable commit -> fetched and used, exit 0 (dir #572 max-review finding)" 0 "$STATUS"

# --- max-review finding, the most severe of the three: the FETCH-SUCCESS path (the recovered
# "before" itself) had NO degenerate-range guard at all before this fix, unlike the hatch path's
# (then-incomplete) one. A rollback-style force-push — the ref is force-pushed BACKWARD to an older
# commit — reports GITHUB_EVENT_BEFORE as the newer, now-orphaned tip and GITHUB_EVENT_AFTER as the
# older commit it rolled back to; if that orphaned "before" is still fetchable by sha (as it usually
# is, same mechanism as any other orphan), it would have been accepted with NO check that "after" is
# already reachable from it (git rev-list "before..after" is then empty by construction) --------------
rbare="$(mktemp -d "$SANDBOX/rbare.XXXXXX")"; git init -q --bare "$rbare"
rwork="$(mktemp -d "$SANDBOX/rwork.XXXXXX")"; git -C "$rwork" init -q
git -C "$rwork" commit -q --allow-empty -m root
rroot="$(git -C "$rwork" rev-parse HEAD)"
git -C "$rwork" push -q "$rbare" HEAD:refs/heads/main
git -C "$rwork" commit -q --allow-empty -m "a commit a rollback force-push will orphan"
rnewer="$(git -C "$rwork" rev-parse HEAD)"
git -C "$rwork" push -q "$rbare" HEAD:refs/heads/main
git -C "$rwork" reset -q --hard "$rroot"
git -C "$rwork" push -qf "$rbare" HEAD:refs/heads/main
rclone="$(mktemp -d "$SANDBOX/rclone.XXXXXX")"; rmdir "$rclone"
git clone -q "file://$rbare" "$rclone"
run_in "$rclone" bash -c 'git cat-file -e "$1^{commit}" 2>/dev/null && echo PRESENT || echo ABSENT' _ "$rnewer"
check_contains "premise: the rolled-back-from tip is genuinely absent from this clone" "$OUT" "ABSENT"
run_in "$rclone" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$rnewer" GITHUB_EVENT_AFTER="$rroot" "$ci"
check_status "push: rollback force-push, recovered before is a DESCENDANT of after -> exit 2, not a silent empty-range pass (dir #572 max-review finding, most severe: no guard existed on this path at all)" 2 "$STATUS"
check_contains "names it as scanning nothing, same as the hatch-side guard" "$OUT" "would scan nothing"

# --- push: an ORDINARY (non-force-push) before..after range, in a REAL CI clone topology, with a
# genuinely pre-existing allowlist entry -> the entry must still suppress (max-review CI-safety
# finding, second round): SECRET_SCAN_LOCAL_PUSH is what makes dir #518's --not---remotes baseline
# fix safe to apply at all, and ci-scan.sh must NEVER set it (secret-scan.sh's own header names why).
# A real bare+clone topology (like the zero-before case above) has BOTH before AND after already
# reachable from the clone's own origin/* by the time ci-scan.sh runs -- proving the ordinary,
# non-force-push CI path is unaffected by dir #518's fix, not just the already-covered force-push one.
bare2="$(mktemp -d "$SANDBOX/bare2.XXXXXX")"; git init -q --bare "$bare2"
work2="$(mktemp -d "$SANDBOX/work2.XXXXXX")"; git -C "$work2" init -q
printf '%s\n' "$(key 'AKIA' 'A')" > "$work2/.secret-scan-allow"
git -C "$work2" add .secret-scan-allow; git -C "$work2" commit -qm "add allowlist"
before2="$(git -C "$work2" rev-parse HEAD)"
git -C "$work2" push -q "$bare2" HEAD:refs/heads/main
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$work2/key.txt"
git -C "$work2" add key.txt; git -C "$work2" commit -qm "add the exempted key"
after2="$(git -C "$work2" rev-parse HEAD)"
git -C "$work2" push -q "$bare2" HEAD:refs/heads/main
clone2="$(mktemp -d "$SANDBOX/clone2.XXXXXX")"; rmdir "$clone2"
git clone -q "$bare2" "$clone2"
run_in "$clone2" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$before2" GITHUB_EVENT_AFTER="$after2" "$ci"
check_status "push: ordinary range in a real CI clone, pre-existing entry -> still suppresses, exit 0 (dir #518 fix does not regress CI)" 0 "$STATUS"

# --- the scanner missing next to ci-scan.sh is a config error, not a raw exec failure --------------
missing="$(mktemp -d "$SANDBOX/missing.XXXXXX")"
cp "$ci" "$missing/ci-scan.sh"
run_in "$repo" env GITHUB_EVENT_NAME=push GITHUB_EVENT_BEFORE="$sha" GITHUB_EVENT_AFTER="$sha" \
  "$missing/ci-scan.sh"
check_status "scanner not found next to ci-scan.sh -> exit 2" 2 "$STATUS"
check_contains "names the problem" "$OUT" "scanner not found"

summary
