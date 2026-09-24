#!/usr/bin/env bash
# test_ref_guard.sh (dir #333) — direct coverage for tools/lib/ref-guard.sh, the ownership-scoping
# helpers tests/run.sh's corruption canary (dir #318) uses for its new refs/heads before/after
# compare. The canary itself can't be exercised end-to-end without corrupting the real checkout it
# watches (the very thing it exists to catch), so this drives the extracted helpers directly against
# a throwaway sandbox repo instead — same idiom as test_nonneg_int_lib.sh / test_range_lib.sh for the
# repo's other shared tools/lib/*.sh files.
#
# Three scenarios, matching the brief this ticket shipped from: RED on a fixture that creates and
# deletes a ref in the watched repo (a leftover stray branch survives, unowned); GREEN on an untouched
# repo; and a third the brief's own lead 2 called out — a worktree's own legitimate branch commit
# must NOT trip the guard, since refs/heads is the git COMMON dir, shared by every worktree of a
# checkout.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/ref-guard.sh"
check_file "tools/lib/ref-guard.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

# --- guard_filter_unowned: pure string-matching edge cases, no git involved -------------------------

out="$(guard_filter_unowned "main" "$(printf 'main abc123\nside def456\n')")"
check_absent "guard_filter_unowned drops an owned branch" "$out" "main abc123"
check_contains "guard_filter_unowned keeps an unowned branch" "$out" "side def456"

out="$(guard_filter_unowned "" "$(printf 'side def456\n')")"
check_contains "guard_filter_unowned: an empty owned list excludes nothing" "$out" "side def456"

out="$(guard_filter_unowned "$(printf 'a\nb\n')" "$(printf 'a 1\nb 2\nc 3\n')")"
check_absent "guard_filter_unowned: multiple owned entries all drop" "$out" "a 1"
check_contains "guard_filter_unowned: multiple owned entries — unowned survives" "$out" "c 3"

# dir #333, review-caught: an empty REFS_SNAPSHOT must report zero unowned refs, not a synthetic blank
# line manufactured by `printf '%s\n' ""` always emitting one line.
out="$(guard_filter_unowned "main" "")"
if [ -z "$out" ]; then pass "guard_filter_unowned: an empty refs snapshot -> truly empty output, not a blank line"
else fail "guard_filter_unowned: an empty refs snapshot -> truly empty output, not a blank line" "got [$out]"; fi

# --- guard_owned_branches / guard_filter_unowned against a real sandbox repo ------------------------

repo="$(new_repo)"
git -C "$repo" commit -q --allow-empty -m init

# GREEN: an untouched repo between two snapshots — nothing to report.
owned_before="$(guard_owned_branches "$repo")"
refs_before="$(guard_refs_snapshot "$repo")"
owned_after="$(guard_owned_branches "$repo")"
refs_after="$(guard_refs_snapshot "$repo")"
owned_union="$(guard_union "$owned_before" "$owned_after")"
before_unowned="$(guard_filter_unowned "$owned_union" "$refs_before")"
after_unowned="$(guard_filter_unowned "$owned_union" "$refs_after")"
if [ "$before_unowned" = "$after_unowned" ]; then pass "GREEN: untouched repo — unowned-ref snapshots match"
else fail "GREEN: untouched repo — unowned-ref snapshots match" "before=[$before_unowned] after=[$after_unowned]"; fi

# RED: a fixture creates AND deletes a ref, plus leaves one stray behind — the exact shape dir #320's
# incident took (branches left in the real repo that nobody's worktree explains).
owned_before="$(guard_owned_branches "$repo")"
refs_before="$(guard_refs_snapshot "$repo")"
git -C "$repo" branch leaked-fixture-branch
git -C "$repo" branch -D leaked-fixture-branch >/dev/null
git -C "$repo" branch stray-leftover-branch
owned_after="$(guard_owned_branches "$repo")"
refs_after="$(guard_refs_snapshot "$repo")"
owned_union="$(guard_union "$owned_before" "$owned_after")"
before_unowned="$(guard_filter_unowned "$owned_union" "$refs_before")"
after_unowned="$(guard_filter_unowned "$owned_union" "$refs_after")"
check_ne "RED: a leaked-and-deleted ref plus a stray leftover trips the unowned-ref compare" \
  "$before_unowned" "$after_unowned"
check_contains "RED: the stray leftover branch is the reported difference" "$after_unowned" "stray-leftover-branch"

git -C "$repo" branch -D stray-leftover-branch >/dev/null

# OWNED-EXCLUSION: a second worktree committing on ITS OWN branch moves that branch's ref in the same
# shared refs/heads namespace — ordinary concurrent work (lead 2), not a leak from this repo's own
# suite run, so it must NOT trip once both snapshots' owned sets are unioned in.
wt="$SANDBOX/ref-guard-peer-wt"
run git -C "$repo" worktree add -q -b peer-branch "$wt"
check_status "worktree add for the peer-ownership case succeeds" 0 "$STATUS"
owned_before="$(guard_owned_branches "$repo")"
refs_before="$(guard_refs_snapshot "$repo")"
git -C "$wt" commit -q --allow-empty -m "peer commit"
owned_after="$(guard_owned_branches "$repo")"
refs_after="$(guard_refs_snapshot "$repo")"
owned_union="$(guard_union "$owned_before" "$owned_after")"
before_unowned="$(guard_filter_unowned "$owned_union" "$refs_before")"
after_unowned="$(guard_filter_unowned "$owned_union" "$refs_after")"
if [ "$before_unowned" = "$after_unowned" ]; then
  pass "OWNED-EXCLUSION: a peer worktree's own commit does not trip the unowned-ref compare"
else
  fail "OWNED-EXCLUSION: a peer worktree's own commit does not trip the unowned-ref compare" \
    "before=[$before_unowned] after=[$after_unowned]"
fi

# --- guard_reflog_count -------------------------------------------------------------------------

reflog_repo="$(new_repo)"
git -C "$reflog_repo" commit -q --allow-empty -m one
git -C "$reflog_repo" commit -q --allow-empty -m two
count="$(guard_reflog_count "$reflog_repo")"
if [ "$count" = "2" ]; then pass "guard_reflog_count: counts two commits correctly"
else fail "guard_reflog_count: counts two commits correctly" "got [$count]"; fi
git -C "$reflog_repo" commit -q --allow-empty -m three
count_after="$(guard_reflog_count "$reflog_repo")"
if [ "$count_after" = "3" ]; then pass "guard_reflog_count: grows by one per further commit"
else fail "guard_reflog_count: grows by one per further commit" "got [$count_after]"; fi

# --- NAMED RESIDUAL LIMIT (dir #333, found by an independent /code-review high pass, empirically
# reproduced): a leak shaped as `git worktree add` against the watched repo — rather than a bare
# `git branch` (the historical incident's own shape, covered by the RED scenario above) — becomes
# "owned" the instant it exists, so it is EXEMPTED, not caught. This test pins that known, accepted
# trade-off (see tools/lib/ref-guard.sh's own header) so a future change to this scoping logic has to
# consciously decide to alter this behavior rather than silently drift into fixing or worsening it. ---

# dir #318 (G5): the header now names that, for test processes, this residual is closed at write
# time by tests/lib.sh's guard — the detection-layer limit this test pins above still stands for
# anything outside the suite.
pin "residual header names dir #318's write-time closure for test processes" "$lib" \
  "refused at write time by tests/lib.sh's guard (dir #318)" \
  "expected the NAMED RESIDUAL LIMIT paragraph to gain this sentence"

leak_repo="$(new_repo)"
git -C "$leak_repo" commit -q --allow-empty -m init
owned_before="$(guard_owned_branches "$leak_repo")"
refs_before="$(guard_refs_snapshot "$leak_repo")"
leak_wt="$SANDBOX/ref-guard-leak-wt"
run git -C "$leak_repo" worktree add -q -b leaked-worktree-branch "$leak_wt"
check_status "fixture: worktree-add leak simulation succeeds" 0 "$STATUS"
owned_after="$(guard_owned_branches "$leak_repo")"
refs_after="$(guard_refs_snapshot "$leak_repo")"
owned_union="$(guard_union "$owned_before" "$owned_after")"
before_unowned="$(guard_filter_unowned "$owned_union" "$refs_before")"
after_unowned="$(guard_filter_unowned "$owned_union" "$refs_after")"
if [ "$before_unowned" = "$after_unowned" ]; then
  pass "NAMED RESIDUAL LIMIT: a worktree-add-shaped leak is exempted (known, accepted trade-off)"
else
  fail "NAMED RESIDUAL LIMIT: a worktree-add-shaped leak is exempted (known, accepted trade-off)" \
    "expected this to STILL be exempted (before=[$before_unowned] after=[$after_unowned]) — if this now fails, the scoping logic changed: update this test AND tools/lib/ref-guard.sh's header comment together, don't just silence the assertion"
fi

summary
