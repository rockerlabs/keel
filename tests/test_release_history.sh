#!/usr/bin/env bash
# test_release_history.sh — dir #232: docs/release-history.md's own drift guard.
#
# This page is condensed-derived prose (dir #128 rule 3, the dir #206 class): a human-written digest
# that restates a fact git already knows (which versions are actually tagged). Nothing else re-derives
# it, so a cut release whose digest paragraph was forgotten reads as identical to one that never
# happened — exactly the failure `tools/self/doctor.sh`'s CHANGELOG<->tag reconciliation (dir #139)
# already guards CHANGELOG.md against. Mirrors that check's two invariants for this file: every
# release tag has a matching `## v<tag>` heading, and every heading has a matching tag. Deliberately
# NOT the full doctor.sh machinery (semver-max, pending-release allowance, section-count arithmetic)
# — this file has no "in preparation" section and no [Unreleased]-equivalent, so that complexity has
# nothing to earn its keep against here.
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

# match(), not a direct `printf | grep -qxF` pipe (dir #280 — see tests/lib.sh's match() for why;
# reproduced live: `test_release_history.sh: line 69: printf: write error: Broken pipe` turned a
# genuine v0.3.0 heading into a false "no entry" failure — the incident that named this ticket).
missing_heading=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  match "$headings" -qxF "$t" || missing_heading="$missing_heading${missing_heading:+, }$t"
done <<< "$tags"

missing_tag=""
while IFS= read -r h; do
  [ -n "$h" ] || continue
  match "$tags" -qxF "$h" || missing_tag="$missing_tag${missing_tag:+, }$h"
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
