#!/usr/bin/env bash
# test_release_history.sh — dir #232: docs/release-history.md's own drift guard.
#
# This page is condensed-derived prose (dir #128 rule 3, the dir #206 class): a human-written digest
# that restates a fact git already knows (which versions are actually tagged). Nothing else re-derives
# it, so a cut release whose digest paragraph was forgotten reads as identical to one that never
# happened — exactly the failure `tools/self/doctor.sh`'s CHANGELOG<->tag reconciliation (dir #139)
# already guards CHANGELOG.md against. Mirrors that check's two invariants for this file: every
# release tag has a matching `## v<tag>` heading, and every heading has a matching tag, PLUS (dir #299)
# its commit-distance-bounded pending-release allowance — without it the two invariants above are
# structurally impossible to keep green across a release. Still deliberately NOT the one piece of
# doctor.sh machinery that has nothing to earn its keep against here: section-count arithmetic, since
# this file has no `[Unreleased]`-equivalent for a count invariant to reconcile against.
#
# Tag collection uses lib.sh's own `release_tag_versions()` — promoted there (dir #232's own
# /code-review medium pass) once a THIRD copy of doctor.sh's `_release_tag_versions()` regex turned up
# here, on top of the one already living in test_changelog_section.sh; both test files source lib.sh
# already, so nothing stopped them sharing one copy. doctor.sh keeps its own private copy (bare
# version, `v` stripped) since it isn't a consumer of this file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source=tools/lib/fence-blank.sh
. "$REPO_ROOT/tools/lib/fence-blank.sh"
# shellcheck source=tools/lib/nonneg-int.sh
. "$REPO_ROOT/tools/lib/nonneg-int.sh"
#
# Known residual (/code-review medium, dir #232): the three `fail` branches below (missing heading,
# missing tag, duplicate heading) have no permanent regression fixture — unlike doctor.sh's own check 6,
# which tests/test_self_doctor.sh exercises with synthetic scratch-repo fixtures, this file's fail paths
# are only ever exercised against this repo's own real, always-passing state in CI. All three were
# manually red-green verified live during dir #232's own session (a moved file, an injected duplicate
# heading, a renamed tag) but that verification isn't captured as a standing fixture. Left unfixed here
# as disproportionate to this ticket's scope (a scratch-git-repo fixture harness the size of
# test_self_doctor.sh's own, for a single-page digest check) rather than silently accepted.

history="$REPO_ROOT/docs/release-history.md"
readme="$REPO_ROOT/README.md"
changelog="$REPO_ROOT/CHANGELOG.md"

check_file "docs/release-history.md exists" "$history"

if [ ! -f "$history" ]; then
  summary
  exit $?
fi

# --- README discoverability: an adopter-usable doc not linked from the Docs index is as good as
# unshipped (same class test_release_audit_doc.sh already guards for release-audit.md). -------------
pin "README Docs section links docs/release-history.md" \
  "$readme" '[`docs/release-history.md`](docs/release-history.md)' \
  "expected the Docs section to list release-history.md the way it lists release-audit.md"

pin "CHANGELOG.md header links docs/release-history.md" \
  "$changelog" '[`docs/release-history.md`](docs/release-history.md)' \
  "expected the CHANGELOG.md header to point readers at the condensed digest, per dir #232's scope"

# --- heading <-> tag reconciliation (dir #139's own rationale, applied to this file) ----------------
# Headings: `## v<x.y.z> — <date>`. Tags: `v<x.y.z>`, the same shape doctor.sh's own tag scan expects.
# `grep -qxF` per item, not a comm/sort/process-substitution pipeline — same idiom doctor.sh's own
# check 6 uses for this identical class of membership check (found by /simplify's own simplification
# pass on this ticket's first draft, which had reached for comm instead). Fenced-block-blanked before
# the heading scan (the same guard doctor.sh's own identical CHANGELOG.md heading scan uses, via the
# shared tools/lib/fence-blank.sh) — this page is unlikely to ever carry a fenced `## v<x.y.z>`
# example, but the guard is one sourced line and the failure mode it prevents (a doc example silently
# counted as a real entry) is exactly the class dir #139 exists to catch.
headings="$(blank_fenced_blocks "$history" | grep -oE '^## v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^## //')"
tags="$(release_tag_versions "$REPO_ROOT")"

# _semver_gt A B — true iff v-prefixed semver A is strictly greater than v-prefixed semver B. Own copy,
# not a shared lib call: doctor.sh's own `_semver_gt` (mirrored, not shared, here — dir #299) operates
# on bare `x.y.z` (it strips `v` off tags itself) while this file's tags/headings keep the `v` prefix
# throughout (`release_tag_versions`'s own contract) — same three-integer-component logic, `v` stripped
# locally instead of upstream. Integers, not a string/`sort -V` compare, for the same reason doctor.sh's
# copy gives: `sort -V` isn't available on the alpine-busybox CI leg and a string compare ranks 1.10.0
# below 1.9.0.
_semver_gt() {
  local a="${1#v}" b="${2#v}" a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$a"
  IFS=. read -r b1 b2 b3 <<< "$b"
  if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
  if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
  [ "$a3" -gt "$b3" ]
}

# match(), not a direct `printf | grep -qxF` pipe (dir #280 — see tests/lib.sh's match() for why;
# reproduced live: `test_release_history.sh: line 69: printf: write error: Broken pipe` turned a
# genuine v0.3.0 heading into a false "no entry" failure — the incident that named this ticket).
#
# One pass over $tags derives BOTH $missing_heading and $highest_tag (dir #299 — the pending-release
# allowance below needs the latter) — folded together rather than run as two separate loops over the
# identical stream, the same don't-spell-the-same-scan-twice point doctor.sh's own check 6 makes beside
# its own identical fold.
missing_heading=""
highest_tag=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  match "$headings" -qxF "$t" || missing_heading="$missing_heading${missing_heading:+, }$t"
  if [ -z "$highest_tag" ] || _semver_gt "$t" "$highest_tag"; then highest_tag="$t"; fi
done <<< "$tags"

# --- release-in-preparation allowance (dir #299) -----------------------------------------------------
# Without this, the tag<->heading reconciliation above is structurally impossible to keep green across
# a release: the release-prep PR adds the `## vX.Y.Z` heading before the tag exists (heading->tag
# direction fails), and the tag doesn't exist until the operator cuts it on the merged commit (nothing
# re-runs this suite at that instant to ever see it pass). Every release cut a red window.
#
# Same shape `tools/self/doctor.sh` already ships for CHANGELOG.md (dir #156), transferred rather than
# invented fresh (operator decision 2026-08-30, dir #299): the untagged heading is exempt only if it is
# BOTH the newest heading (first in file order, per this page's own "newest first" convention) AND its
# version genuinely sorts above every existing tag (a stale/backported heading below a real tag is
# still drift, not a release in prep) AND HEAD is no more than KEEL_PENDING_RELEASE_MAX_COMMITS commits
# past the commit that introduced that heading. That third conjunct is what keeps a genuinely
# forgotten/deleted tag from reading as "still pending" forever — see doctor.sh's own comment beside
# `pending_max_commits` for the full reasoning, which applies unchanged here. The bound is STRICTLY
# NARROWING (every input that fails today still fails; some that pass today now fail instead), so it
# cannot open a new false-green path — only a false FAIL, and that names the heading and the bound.
pending_max_commits="${KEEL_PENDING_RELEASE_MAX_COMMITS:-40}"
pending_max_commits="$(sanitize_nonneg_int "$pending_max_commits" 40)"

# _pending_release_intro_commit VERSION — SHA of the commit that most recently introduced the exact
# text "## VERSION" into docs/release-history.md's tracked history, outside any fenced block. Mirrored
# from doctor.sh's own `_pending_release_intro_commit` (dir #156, not shared — dir #299): `git log -S`
# (the pickaxe) newest first, verified per-candidate against its immediate parent (fence-blanked both
# sides) so a fenced example elsewhere in the file can't be mistaken for the heading's real
# introduction. Prints nothing if no candidate resolves; the caller below fails OPEN (keeps the
# allowance) on that empty case rather than inventing a distance it couldn't measure.
_pending_release_intro_commit() {
  local heading="## $1" rel sha now before
  rel="${history#"$REPO_ROOT"/}"
  while IFS= read -r sha; do
    now="$(blank_fenced_blocks <(git -C "$REPO_ROOT" show "$sha:$rel" 2>/dev/null) 2>/dev/null)"
    before="$(blank_fenced_blocks <(git -C "$REPO_ROOT" show "$sha^:$rel" 2>/dev/null) 2>/dev/null)"
    if grep -qF "$heading" <<< "$now" && ! grep -qF "$heading" <<< "$before"; then
      printf '%s\n' "$sha"
      return 0
    fi
  done < <(git -C "$REPO_ROOT" log -S"$heading" --format=%H -- "$history" 2>/dev/null || true)
}

# $headings is already in file order (this page's own "newest first" convention, unsorted by the scan
# above), so its first line is the newest heading.
newest_heading="$(head -1 <<< "$headings")"

# Guard-clause shaped (same as doctor.sh's own check 6 loop, found reusable by /code-review high there):
# each non-candidate falls straight into $missing_tag and moves on, so the three pending outcomes
# (bound-unresolvable -> fail open, over-bound -> dedicated fail, within-bound -> pending) sit at one
# consistent depth below.
missing_tag=""
pending=""
pending_dist=""
overbound_heading=""
overbound_dist=""
while IFS= read -r h; do
  [ -n "$h" ] || continue
  match "$tags" -qxF "$h" && continue
  if ! { [ "$h" = "$newest_heading" ] && { [ -z "$highest_tag" ] || _semver_gt "$h" "$highest_tag"; }; }; then
    missing_tag="$missing_tag${missing_tag:+, }$h"
    continue
  fi
  intro_commit="$(_pending_release_intro_commit "$h")"
  if [ -z "$intro_commit" ]; then
    pending="$h"
    continue
  fi
  dist="$(git -C "$REPO_ROOT" rev-list --count "$intro_commit"..HEAD)"
  if [ "$dist" -gt "$pending_max_commits" ]; then
    overbound_heading="$h"; overbound_dist="$dist"
    continue
  fi
  pending="$h"; pending_dist="$dist"
done <<< "$headings"

# Duplicate detection is a separate, single-list pass — `sort | uniq -d`, not the `grep -qxF` idiom
# above: that idiom fits set-MEMBERSHIP checks across two different lists, but re-scanning a growing
# accumulator to find a repeat within ONE list is quadratic for no reason `uniq -d` doesn't already
# solve in one pass (found by /code-review medium on this ticket's first draft).
dup_heading="$(printf '%s\n' "$headings" | sort | uniq -d | paste -sd, - | sed 's/,/, /g')"

if [ -z "$missing_heading" ]; then
  pass "every release tag has a matching docs/release-history.md heading"
else
  fail "every release tag has a matching docs/release-history.md heading" \
    "tag(s) with no '## v<x.y.z>' entry: $missing_heading"
fi

if [ -z "$missing_tag" ]; then
  pass "every docs/release-history.md heading has a matching release tag"
else
  fail "every docs/release-history.md heading has a matching release tag" \
    "heading(s) with no matching tag: $missing_tag"
fi

# Dedicated fail, distinct from the generic one above — the remedy here ("tag the release") differs
# from that one's implication ("this heading shouldn't exist"). dir #299.
if [ -z "$overbound_heading" ]; then
  pass "no release-in-preparation heading is overdue past the pending-release allowance"
else
  fail "no release-in-preparation heading is overdue past the pending-release allowance" \
    "'## $overbound_heading' was cut $overbound_dist commit(s) ago and is still untagged (bound: $pending_max_commits) — tag the release, or the heading is drift"
fi

# Informational, not a pass/fail gate on its own — announces the exempt state (dir #299's own "never
# silent" requirement, borrowed from doctor.sh) rather than passing quietly.
if [ -n "$pending" ]; then
  pass "release heading '$pending' is pending its tag${pending_dist:+ ($pending_dist/$pending_max_commits commits since cut)}"
fi

# --- no heading is duplicated (dir #139's own precedent: a dedup-based membership check alone can't
# see a duplicate — self/doctor.sh's own check 6 has a dedicated check for exactly this on
# CHANGELOG.md's `[Unreleased]` heading, for the same reason). ---------------------------------------
if [ -z "$dup_heading" ]; then
  pass "no docs/release-history.md heading is duplicated"
else
  fail "no docs/release-history.md heading is duplicated" \
    "heading(s) appearing more than once: $dup_heading"
fi

summary
