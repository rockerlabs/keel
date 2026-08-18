#!/usr/bin/env bash
# test_parallel_sessions_doc.sh — dir #172: docs/parallel-sessions.md links four rails out of CORE.md
# and FRAMEWORK.md instead of restating them. Same idiom as test_release_audit_doc.sh (pin() from
# tests/lib.sh, both legs of a naming coupling pinned so a rename on either side fails loudly instead
# of drifting silently).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/parallel-sessions.md"
core="$REPO_ROOT/CORE.md"
framework="$REPO_ROOT/FRAMEWORK.md"
readme="$REPO_ROOT/README.md"

check_file "docs/parallel-sessions.md exists" "$doc"
check_file "CORE.md exists" "$core"
check_file "FRAMEWORK.md exists" "$framework"
check_file "README.md exists" "$readme"

# --- README discoverability: an adopter-usable doc not linked from the Docs index is as good as
# unshipped (same class dir #85's docs layer would have flagged). --------------------------------
pin "README Docs section links docs/parallel-sessions.md" \
  "$readme" '[`docs/parallel-sessions.md`](docs/parallel-sessions.md)' \
  "expected the Docs section to list parallel-sessions.md the way it lists rollout-audit.md/drydock.md"

# --- cross-doc rail citations: the doc's "linked" rails must name a heading that still exists on the
# other side. Pin BOTH legs for each of the four linked rails (decision 5 in dir #172's design pass:
# these four already live in CORE.md/FRAMEWORK.md and must be linked, not restated). One entry per
# linked rail: label|source-file-label|source-marker (doc-side pin always searches for the label
# itself, so only the source leg's file and exact marker vary). -----------------------------------
linked_rails=(
  'Git — mandatory rails|CORE.md|## Git — mandatory rails'
  'Before writing code — reconcile first|CORE.md|## Before writing code — reconcile first'
  'Worktree discipline|FRAMEWORK.md|**Worktree discipline.**'
)
for entry in "${linked_rails[@]}"; do
  IFS='|' read -r label file_label marker <<< "$entry"
  case "$file_label" in
    CORE.md) file="$core" ;;
    FRAMEWORK.md) file="$framework" ;;
  esac
  pin "parallel-sessions.md cites $file_label's '$label' heading" \
    "$doc" "$label" \
    "the doc's rails table should name this $file_label heading; if renamed here the citation is stale"
  pin "$file_label still carries the '$label' heading" \
    "$file" "$marker" \
    "renamed in $file_label? update docs/parallel-sessions.md's rails table too"
done

# --- the three rails this doc originates (decision 5: verified absent from the tracked tree at
# design time) must actually be present as full prose, not just named. One entry per rail:
# name|marker. -----------------------------------------------------------------------------------
originated_rails=(
  'push-verify|**Push-verify.**'
  'spent-branch/stale-resume|A merged branch is spent'
  'stale-file-refusal/conflict-detection|stale-file refusal'
)
for entry in "${originated_rails[@]}"; do
  IFS='|' read -r name marker <<< "$entry"
  pin "parallel-sessions.md states the $name rail in full" \
    "$doc" "$marker" \
    "expected the originated $name rail to be stated as this doc's own prose"
done

# --- decision 4: "what worktrees do NOT isolate" must precede the failure catalog, not follow it --
isolation_line="$(grep -n '^## What a worktree isolates' "$doc" | head -1 | cut -d: -f1)"
catalog_line="$(grep -n '^## The failure catalog' "$doc" | head -1 | cut -d: -f1)"
if [ -n "$isolation_line" ] && [ -n "$catalog_line" ] && [ "$isolation_line" -lt "$catalog_line" ]; then
  pass "parallel-sessions.md: the isolation section precedes the failure catalog"
else
  fail "parallel-sessions.md: the isolation section precedes the failure catalog" \
    "expected '## What a worktree isolates...' (line ${isolation_line:-<missing>}) before '## The failure catalog' (line ${catalog_line:-<missing>})"
fi

# --- decision 3: exactly one shared recovery-tiers section, not a per-mode walkthrough ------------
recovery_count="$(grep -c '^## Recovery tiers' "$doc")"
if [ "$recovery_count" -eq 1 ]; then
  pass "parallel-sessions.md: exactly one shared Recovery tiers section"
else
  fail "parallel-sessions.md: exactly one shared Recovery tiers section" \
    "found $recovery_count '## Recovery tiers' headings, expected exactly 1"
fi

# --- the failure catalog names all four field-report modes, anonymized (no per-incident section) --
for mode in 'F1' 'F2' 'F3' 'F4'; do
  pin "parallel-sessions.md failure catalog names $mode" "$doc" "**$mode —" \
    "expected the failure catalog to enumerate $mode"
done

summary
