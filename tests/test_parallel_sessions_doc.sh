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
# these four already live in CORE.md/FRAMEWORK.md and must be linked, not restated). -------------
pin "parallel-sessions.md cites CORE.md's 'Git — mandatory rails' heading" \
  "$doc" 'Git — mandatory rails' \
  "the doc's rails table should name this CORE.md heading; if renamed here the citation is stale"
pin "CORE.md still carries the 'Git — mandatory rails' heading" \
  "$core" '## Git — mandatory rails' \
  "renamed in CORE.md? update docs/parallel-sessions.md's rails table too"

pin "parallel-sessions.md cites CORE.md's 'Before writing code — reconcile first' heading" \
  "$doc" 'Before writing code — reconcile first' \
  "the doc's rails table should name this CORE.md heading; if renamed here the citation is stale"
pin "CORE.md still carries the 'Before writing code — reconcile first' heading" \
  "$core" '## Before writing code — reconcile first' \
  "renamed in CORE.md? update docs/parallel-sessions.md's rails table too"

pin "parallel-sessions.md cites FRAMEWORK.md's 'Worktree discipline' paragraph" \
  "$doc" 'Worktree discipline' \
  "the doc's rails table should name this FRAMEWORK.md paragraph; if renamed here the citation is stale"
pin "FRAMEWORK.md still carries the 'Worktree discipline' paragraph" \
  "$framework" '**Worktree discipline.**' \
  "renamed in FRAMEWORK.md? update docs/parallel-sessions.md's rails table too"

# --- the three rails this doc originates (decision 5: verified absent from the tracked tree at
# design time) must actually be present as full prose, not just named. -----------------------------
pin "parallel-sessions.md states the push-verify rail in full" \
  "$doc" '**Push-verify.**' \
  "expected the originated push-verify rail to be stated as this doc's own prose"
pin "parallel-sessions.md states the spent-branch/stale-resume rail in full" \
  "$doc" 'A merged branch is spent' \
  "expected the originated spent-branch/stale-resume rail to be stated as this doc's own prose"
pin "parallel-sessions.md states the stale-file-refusal/conflict-detection rail in full" \
  "$doc" 'stale-file refusal' \
  "expected the originated conflict-detection rail to be stated as this doc's own prose"

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
