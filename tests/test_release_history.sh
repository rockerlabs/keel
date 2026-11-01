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
# Tag collection uses lib.sh's own `all_release_tag_versions()` (dir #318) — local `release_tag_versions()`
# (promoted there, dir #232's own /code-review medium pass, once a THIRD copy of doctor.sh's own
# strict-semver tag-filter regex turned up here on top of test_changelog_section.sh's) UNIONED with a
# read-only `git ls-remote`, since local tags alone go empty on a shallow/tagless CI checkout — this
# file used to be rescued only by test_changelog_section.sh's own (now-removed) fetch populating real
# tags for every test in the same run. doctor.sh keeps its own private copy (bare version, `v`
# stripped) since it isn't a consumer of this file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }
# shellcheck source=tools/lib/fence-blank.sh
. "$REPO_ROOT/tools/lib/fence-blank.sh"
# shellcheck source=tools/lib/nonneg-int.sh
. "$REPO_ROOT/tools/lib/nonneg-int.sh"
# shellcheck source=tools/lib/regex-escape.sh
. "$REPO_ROOT/tools/lib/regex-escape.sh"
# shellcheck source=tools/lib/heading-intro.sh
. "$REPO_ROOT/tools/lib/heading-intro.sh"
#
# Known residual (/code-review medium, dir #232; the dir #866 check below is outside it — it carries its own
# fixture rows): the three `fail` branches below (missing heading,
# missing tag, duplicate heading) have no permanent regression fixture — unlike doctor.sh's own check 6,
# which tests/test_self_doctor.sh exercises with synthetic scratch-repo fixtures, this file's fail paths
# are only ever exercised against this repo's own real, always-passing state in CI. All three were
# manually red-green verified live during dir #232's own session (a moved file, an injected duplicate
# heading, a renamed tag) but that verification isn't captured as a standing fixture. Left unfixed here
# as disproportionate to this ticket's scope (a scratch-git-repo fixture harness the size of
# test_self_doctor.sh's own, for a single-page digest check) rather than silently accepted.

history="$REPO_ROOT/docs/release-history.md"
changelog="$REPO_ROOT/CHANGELOG.md"

check_file "docs/release-history.md exists" "$history"

if [ ! -f "$history" ]; then
  summary
  exit $?
fi

# --- discoverability: an adopter-usable doc not linked from the Docs index is as good as
# unshipped (same class test_release_audit_doc.sh already guards for release-audit.md). -------------
pin "docs/reference.md Docs index links docs/release-history.md" \
  "$REPO_ROOT/docs/reference.md" '[`docs/release-history.md`](release-history.md)' \
  "expected docs/reference.md's Docs index to list release-history.md the way it lists release-audit.md"

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
# counted as a real entry) is exactly the class dir #139 exists to catch. Blanked ONCE into a
# $SANDBOX-scoped scratch file (tests/lib.sh's own convention; cleaned up by its EXIT trap) rather than
# per use — the per-release verification-block section below (dir #268) reads the same blanked content
# again and reuses this file instead of re-running blank_fenced_blocks a second time. Likewise the
# heading-line scan itself runs once, into $heading_lines: the verification-block section reuses it too
# instead of a second `grep -E '^## v...'` pass over $blanked_tmp that could silently drift from this one.
# The one deliberate exception is _history_entry_tokens below (dir #866): its fixtures must reach the
# extraction, so it is a second copy of this scan, and a row beside it asserts the two agree.
blanked_tmp="$(mktemp "$SANDBOX/release-history-blanked.XXXXXX")"
blank_fenced_blocks "$history" > "$blanked_tmp"
heading_lines="$(grep -E '^## v[0-9]+\.[0-9]+\.[0-9]+' "$blanked_tmp")"
headings="$(sed 's/^## //' <<< "$heading_lines" | grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+')"
# dir #318: local `git tag -l` alone (release_tag_versions()) goes empty on a shallow, tagless CI
# checkout — this file used to be rescued only by test_changelog_section.sh's own (now-removed) fetch
# against $REPO_ROOT populating local tags for every other test in the same run, an undocumented
# cross-test dependency dir #318's own design didn't account for (found live: this file went red on a
# tagless clone once that fetch was gone). all_release_tag_versions() unions in a read-only
# `git ls-remote` so this file's own tag/heading reconciliation no longer depends on a sibling test's
# side effect.
tags="$(all_release_tag_versions "$REPO_ROOT")"

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

# _pending_release_intro_commit VERSION — SHA of the commit that most recently introduced the heading
# line "## VERSION ..." into docs/release-history.md's tracked history, outside any fenced block. The walk
# is tools/lib/heading-intro.sh's `heading_intro_commit`, shared with tools/self/doctor.sh (dir #428 — this
# was a mirrored copy kept in step by a comment alone; dir #299's anchoring landed here first and doctor.sh
# only caught up when the v0.9.0 cut false-GAPed). What stays here:
#
# 1. ANCHORED match (dir #299). This file's bracket-less `## vX.Y.Z` has no closing `]` to stop a shorter
#    version matching as a prefix of a longer one (`## v0.7.1` is a substring of `## v0.7.10`), so
#    `$heading_re` requires the character after the version to be a non-digit (or end of line).
# 2. SHALLOW-CLONE guard (dir #299). A shallow clone's boundary commit is indistinguishable from a genuine
#    first commit (its parent object is absent, so `before` is empty), which would fabricate distance 0 for
#    a years-old heading. doctor.sh skips its whole reconciliation on a shallow clone; this test's CI job
#    does not fetch full history (dir #300), so it bails here and the caller fails OPEN.
# 3. A git failure inside the walk (the lib returns 2) also fails OPEN here — a test helper, not a
#    self-check verdict; doctor.sh GAPs on the same status.
#
# Prints nothing if no candidate resolves; the caller below fails OPEN (keeps the allowance, no distance).
_pending_release_intro_commit() {
  local heading_re
  [ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo true)" = "false" ] || return 0
  heading_re="^## $(escape_bre_literal "$1")([^0-9]|\$)"
  heading_intro_commit "$REPO_ROOT" "${history#"$REPO_ROOT"/}" "$heading_re" || true
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

# --- every released CHANGELOG.md section has its docs/release-history.md entry (dir #866) -------------
# A cut PR can land with a released `## [x.y.z]` section and no `## vx.y.z` entry, and nothing caught it
# before the tag (0.17.0: PR #664 cut, `v0.17.0` was tagged, `main` and every open PR stayed red until the
# entry was added). The tag<->heading rows above only fire AFTER the tag, so this one reads the two FILES
# and no git state: it runs unchanged on the shallow, tagless checkout CI uses, and it does not use the
# pending-release allowance (the cut PR's section is exactly the untagged newest one that allowance
# exempts).
#
# cut_sim_version is the one version exempt from the check: tools/self/cut-sim.sh cuts a CLONE as
# 9999.0.0 and runs this suite on it, and a real cut would carry a curated entry that a simulation cannot.
# The exemption is the EXACT string (9999.0.1 and 9999.1.0 are not exempt), and the pin right below it
# binds it to cut-sim's own invocation, so changing either side without the other fails HERE, in the
# required legs, not only in the non-required cut-simulation job.
cut_sim_version="9999.0.0"
pin "cut-sim.sh cuts the version this check exempts" \
  "$REPO_ROOT/tools/self/cut-sim.sh" '--repo "$clone" '"$cut_sim_version" \
  "expected tools/self/cut-sim.sh to invoke changelog-cut.sh as '--repo \"\$clone\" $cut_sim_version' — change cut_sim_version and cut-sim.sh together"

# _history_entry_tokens HISTORY_FILE — the `vX.Y.Z` token of every `## vX.Y.Z` heading outside a fenced block,
# in file order. The SAME shape as the top-level scan that fills $headings further up (the row after the check
# below asserts the two agree on the real file), kept as its own function because the fixtures below must
# reach the fence-blanking of each file.
_history_entry_tokens() {
  blank_fenced_blocks "$1" | grep -oE '^## v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^## //' || true
}

# _changelog_sections_without_entry CHANGELOG_FILE HISTORY_FILE — print, `v`-prefixed and `, `-separated in
# CHANGELOG file order, every released `## [x.y.z]` section of CHANGELOG_FILE (outside fenced blocks;
# `## [Unreleased]` never matches) whose whole `vX.Y.Z` token is not a heading of HISTORY_FILE. The one
# exempt version is $cut_sim_version. Exit 0 = none missing, 1 = some missing, 2 (nothing printed) = a file is
# unreadable OR CHANGELOG_FILE has no released section at all (counted BEFORE the exemption, so a CHANGELOG
# whose only section is the exempt one is exit 0): a reader that matched nothing must FAIL, never pass
# vacuously. Reads no tag and no git state, and compares whole tokens with match() (never a substring, so
# 0.9.1 is not found in v0.9.10), so it is the same on a shallow, tagless checkout.
_changelog_sections_without_entry() {
  local cl="$1" hist="$2" sections tokens v out=""
  [ -r "$cl" ] && [ -r "$hist" ] || return 2
  sections="$(blank_fenced_blocks "$cl" | grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' | sed 's/^## \[//; s/\]$//' || true)"
  [ -n "$sections" ] || return 2
  tokens="$(_history_entry_tokens "$hist")"
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    [ "$v" = "$cut_sim_version" ] && continue
    match "$tokens" -qxF "v$v" || out="$out${out:+, }v$v"
  done <<< "$sections"
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"
  return 1
}

# fx_case ID EXPECTED_OUTPUT EXPECTED_RC CHANGELOG_TEXT HISTORY_TEXT — one synthetic CHANGELOG/history pair
# under $SANDBOX run through _changelog_sections_without_entry, asserted on stdout AND exit code. Passing the
# string ABSENT as CHANGELOG_TEXT or HISTORY_TEXT leaves that file out of the directory.
fx_case() {
  local id="$1" want_out="$2" want_rc="$3" cl="$4" hist="$5" dir out rc
  dir="$(mktemp -d "$SANDBOX/fx-entry.XXXXXX")"
  [ "$cl" = ABSENT ] || printf '%s\n' "$cl" > "$dir/CHANGELOG.md"
  [ "$hist" = ABSENT ] || printf '%s\n' "$hist" > "$dir/history.md"
  out="$(_changelog_sections_without_entry "$dir/CHANGELOG.md" "$dir/history.md")"; rc=$?
  check_eq "fixture $id stdout" "$want_out" "$out"
  check_status "fixture $id exit code" "$want_rc" "$rc"
}

fx_case C1 "" 0 $'## [Unreleased]\n\n## [0.2.0] - 2026-01-02\n\n## [0.1.0] - 2026-01-01' \
  $'## v0.2.0 — 2026-01-02\n\n## v0.1.0 — 2026-01-01'
fx_case C2 "v0.17.0" 1 $'## [0.17.0] - 2026-10-14\n\n## [0.16.0] - 2026-10-01' \
  $'## v0.16.0 — 2026-10-01'
fx_case C3 "v0.2.0" 1 $'## [0.3.0] - 2026-01-03\n\n## [0.2.0] - 2026-01-02\n\n## [0.1.0] - 2026-01-01' \
  $'## v0.3.0 — 2026-01-03\n\n## v0.1.0 — 2026-01-01'
fx_case C4 "" 0 $'## [Unreleased]\n\n## [0.2.0] - 2026-01-02' \
  $'## v0.2.0 — 2026-01-02'
fx_case C5a "v0.9.1" 1 $'## [0.9.1] - 2026-01-02' \
  $'## v0.9.10 — 2026-01-02'
fx_case C5b "v0.9.10" 1 $'## [0.9.10] - 2026-01-02' \
  $'## v0.9.1 — 2026-01-02'
fx_case C6a "" 0 $'## [0.2.0] - 2026-01-02\n\n```\n## [1.2.3] - 2026-01-01\n```' \
  $'## v0.2.0 — 2026-01-02'
fx_case C6b "v1.2.3" 1 $'## [1.2.3] - 2026-01-02' \
  $'## v0.1.0 — 2026-01-01\n\n```\n## v1.2.3 — 2026-01-02\n```'
fx_case C7 "" 0 $'## [Unreleased]\n\n## [9999.0.0] - 2026-10-15' \
  $'## v0.1.0 — 2026-01-01'
fx_case C8a "v9999.0.1" 1 $'## [9999.0.1] - 2026-10-15' \
  $'## v0.1.0 — 2026-01-01'
fx_case C8b "v9999.1.0" 1 $'## [9999.1.0] - 2026-10-15' \
  $'## v0.1.0 — 2026-01-01'
# Three sections, file order 0.18.0, 0.9.0, 0.10.0: neither a lexical nor a version-order `sort` reproduces it.
fx_case C9 "v0.18.0, v0.9.0, v0.10.0" 1 $'## [0.18.0] - 2026-03-01\n\n## [0.9.0] - 2026-02-01\n\n## [0.10.0] - 2026-01-01' \
  $'## v0.1.0 — 2026-01-01'
fx_case C10a "" 2 ABSENT $'## v0.1.0 — 2026-01-01'
fx_case C10b "" 2 $'## [Unreleased]\n\nNo release yet.' $'## v0.1.0 — 2026-01-01'
fx_case C10c "" 2 $'## [0.1.0] - 2026-01-01' ABSENT

# The real row dispatches on the exit CODE, never on whether the output is empty: an empty output is also
# what a reader that matched nothing prints (exit 2). tests/lib.sh runs without -e, so rc is captured at once.
missing_entry="$(_changelog_sections_without_entry "$changelog" "$history")"; entry_rc=$?
case "$entry_rc" in
  0) pass "every released CHANGELOG.md section has a docs/release-history.md entry" ;;
  1) fail "every released CHANGELOG.md section has a docs/release-history.md entry" \
       "release(s) cut in CHANGELOG.md with no '## v<x.y.z>' entry in docs/release-history.md: $missing_entry — add the entry in the cut-and-land PR (docs/release-audit.md, Phase 7)" ;;
  *) fail "every released CHANGELOG.md section has a docs/release-history.md entry" \
       "CHANGELOG.md or docs/release-history.md unreadable, or CHANGELOG.md has no released '## [x.y.z]' section — the reader matched nothing" ;;
esac

# The function's own history scan is a DELIBERATE second copy of the top-level scan above (the fixtures must
# reach the extraction); this row binds the two copies to each other on the real file.
check_eq "the entry check's history scan agrees with the top-level heading scan" \
  "$headings" "$(_history_entry_tokens "$history")"

# --- no heading is duplicated (dir #139's own precedent: a dedup-based membership check alone can't
# see a duplicate — self/doctor.sh's own check 6 has a dedicated check for exactly this on
# CHANGELOG.md's `[Unreleased]` heading, for the same reason). ---------------------------------------
if [ -z "$dup_heading" ]; then
  pass "no docs/release-history.md heading is duplicated"
else
  fail "no docs/release-history.md heading is duplicated" \
    "heading(s) appearing more than once: $dup_heading"
fi

# --- per-release verification block (dir #268) ---------------------------------------------------------
# Two checks, both walking the same per-heading block text (everything between a `## vX.Y.Z — <date>`
# heading and the next one, or EOF) via tests/lib.sh's own section_body() — the same "second use =
# promote" slicer test_core_capability_index.sh already reuses for this identical "slice one heading's
# body" idiom, so no new bespoke extractor is written here. section_body() matches by exact heading-LINE
# equality, not a version substring, so it sidesteps dir #299's `## v0.9.1` vs `## v0.9.10` collision on
# its own: two releases sharing a numeric prefix still have different heading lines (the date differs
# too). section_body() reads a real FILE, not text, so it reads $blanked_tmp — the same fence-blanked
# scratch file the heading scan above already wrote, not a second blanking pass over the same doc.
#
# 1. Presence, floored at v0.9.0 (dir #268 §3.2 — "history starts at v0.9.0", no back-fill). This fires
#    only once a heading at or above the floor exists; none does yet on this release, so today it is
#    vacuously green by construction, the same shape dir #299's own pending-release allowance uses
#    elsewhere in this file — no synthetic fixture needed, the check earns its keep the moment the first
#    v0.9.0 heading lands.
# 2. The no-private-provenance rule (dir #268 §4.3), scoped to the block region ONLY. The surrounding
#    digest paragraphs are dir #N-rich by design (dir #269's separate, larger sweep) and an unscoped
#    assertion here would fail on day one against this file's own existing prose — the exact trap the
#    reconciliation memo named. A block is identified by its own `**Verification.**` opening marker;
#    only the text from that marker onward is checked, never the digest paragraph above it.
verification_floor="v0.9.0"
missing_block=""
provenance_leak=""
while IFS= read -r hline; do
  [ -n "$hline" ] || continue
  h="$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' <<< "$hline" | head -1)"
  block="$(section_body "$hline" "$blanked_tmp")"

  # Scoped to the text from the `**Verification.**` marker onward — same region the provenance check
  # below uses, and for the same reason: without this, a digest paragraph that merely happens to use
  # bold text (`**Scope:**` in ordinary prose, say) can satisfy a label the block itself never carries
  # (found live, /code-review medium on this ticket's own first draft).
  verification_part="$(awk '/\*\*Verification\.\*\*/{f=1} f{print}' <<< "$block")"

  if [ "$h" = "$verification_floor" ] || _semver_gt "$h" "$verification_floor"; then
    for label in '\*\*Verification\.\*\*' '\*\*Scope:\*\*' '\*\*Method:\*\*' '\*\*Coverage:\*\*' \
                 '\*\*Findings:\*\*' '\*\*Behavioural defects:\*\*' '\*\*Which layer found what:\*\*' \
                 '\*\*What was NOT checked:\*\*' '\*\*Induced-defect rate:\*\*'; do
      match "$verification_part" -qE -- "$label" \
        || missing_block="$missing_block${missing_block:+, }$h: missing $label"
    done
  fi

  if [ -n "$verification_part" ]; then
    match "$verification_part" -qE 'private/' \
      && provenance_leak="$provenance_leak${provenance_leak:+, }$h: cites a private/ path"
    match "$verification_part" -qE 'dir #[0-9]+' \
      && provenance_leak="$provenance_leak${provenance_leak:+, }$h: cites a dir #N ticket"
  fi
done <<< "$heading_lines"

if [ -z "$missing_block" ]; then
  pass "every docs/release-history.md heading at/above the v0.9.0 verification floor carries a verification block"
else
  fail "every docs/release-history.md heading at/above the v0.9.0 verification floor carries a verification block" \
    "$missing_block"
fi

if [ -z "$provenance_leak" ]; then
  pass "no docs/release-history.md verification block cites a private/ path or a dir #N ticket"
else
  fail "no docs/release-history.md verification block cites a private/ path or a dir #N ticket" \
    "$provenance_leak"
fi

summary
