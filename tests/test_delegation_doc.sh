#!/usr/bin/env bash
# test_delegation_doc.sh — dir #171: docs/delegation.md generalizes the drydock orchestration pattern
# into a keel-shipped capability. Pins the cross-links (drydock.md <-> delegation.md, README index),
# the centralized-wrap marker line verbatim (the countermeasure to a real run-1 Stop-hook nudge — see
# docs/drydock.md), the non-delegable rail, and the FRAMEWORK.md pointer staying a pointer, not the
# pattern body. Same idiom as test_drydock_doc.sh: fixed-string pins on both legs of a naming coupling,
# so a rename on either side strands the citation silently instead of failing loudly here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/delegation.md"
drydock="$REPO_ROOT/docs/drydock.md"
readme="$REPO_ROOT/README.md"
framework="$REPO_ROOT/FRAMEWORK.md"

check_file "docs/delegation.md exists" "$doc"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ---------------
pin "README Docs section links docs/delegation.md" \
  "$readme" '[`docs/delegation.md`](docs/delegation.md)' \
  "expected the Docs section to list delegation.md the way it lists drydock.md"

# --- cross-links, pinned on both legs (drydock.md is the doc's own worked instantiation) -----------
pin "drydock.md links delegation.md back" "$drydock" '](delegation.md)' \
  "expected docs/drydock.md to cross-ref delegation.md as the generalized pattern it instantiates"
pin "delegation.md links drydock.md" "$doc" '](drydock.md)' \
  "expected delegation.md to point at drydock.md as the worked instantiation"

# --- the non-delegable set is stated as a rail, not advice -----------------------------------------
pin "delegation.md names the non-delegable set" "$doc" 'The non-delegable set' \
  "expected an explicit rail section naming what never gets delegated"
for item in 'commits and PRs' 'merges' 'releases' 'deletions' 'backlog ticket-number assignment' \
  'memory / knowledge-base writes'; do
  pin "non-delegable set includes: $item" "$doc" "$item" \
    "expected the non-delegable rail to list: $item"
done

# --- the centralized-wrap marker line, verbatim, in the rails block AND the mutator template -------
# dir #171 SPEC requires this EXACT line (run-1: the Stop hook nudged all 7 fixer sessions toward a
# spurious /wrap). A paraphrase would silently fail to fire the same way a literal-string match does.
marker='DELEGATION RUN: wrap duties are centralized — this session does NOT run /wrap or write any log/backlog/memory; the orchestrator owns all bookkeeping.'
marker_hits="$(grep -cF -- "$marker" "$doc")"
if [ "$marker_hits" -ge 2 ]; then
  pass "centralized-wrap marker appears verbatim at least twice (rails block + mutator template)"
else
  fail "centralized-wrap marker appears verbatim at least twice (rails block + mutator template)" \
    "found $marker_hits occurrence(s); expected >= 2"
fi

# --- prompt templates: worker / verifier / mutator skeletons, parameter slots marked <...> ---------
pin "delegation.md ships a worker template" "$doc" 'You are a delegation WORKER' \
  "expected an inline worker prompt skeleton"
pin "delegation.md ships a verifier template" "$doc" 'You are a delegation VERIFIER' \
  "expected an inline verifier prompt skeleton"
pin "delegation.md ships a mutator template" "$doc" 'You are a delegation MUTATOR' \
  "expected an inline mutator prompt skeleton"

# --- the three-valued verdict --------------------------------------------------------------------
for verdict in 'accepted' 'rejected:' 'known —'; do
  pin "delegation.md's verdict contract carries: $verdict" "$doc" "$verdict" \
    "expected the three-valued verdict to include: $verdict"
done

# --- application sketches: audit is the field-tested one, the other three are explicitly not -------
# Pinned per-sketch, not by a line-count threshold: a threshold check can't tell "a real label moved"
# from "a real label vanished" when an unrelated wording change shifts the count by coincidence.
pin "delegation.md points the audit sketch at drydock.md" "$doc" 'Whole-tree audit.' \
  "expected an audit application sketch"
for sketch in 'Grooming wave' 'Pre-implementation recon dossier' 'Post-merge read-only sweep'; do
  pin "sketch labeled not-yet-field-tested: $sketch" "$doc" "**$sketch** *(not yet field-tested).*" \
    "expected the '$sketch' sketch to carry its own not-yet-field-tested label"
done

# --- FRAMEWORK.md gains a pointer, not the pattern body (dir #171 done-check: <= 4 lines) -----------
pin "FRAMEWORK.md points at docs/delegation.md" "$framework" 'docs/delegation.md' \
  "expected a short pointer to the delegation pattern"
pointer_lines="$(awk '
  /bulk read-only analysis over many independent units/ { p = 1 }
  p { print }
  p && /docs\/delegation\.md/ { exit }
' "$framework" | wc -l | tr -d ' ')"
if [ -n "$pointer_lines" ] && [ "$pointer_lines" -ge 1 ] && [ "$pointer_lines" -le 4 ]; then
  pass "FRAMEWORK.md's delegation pointer is <= 4 lines ($pointer_lines)"
else
  fail "FRAMEWORK.md's delegation pointer is <= 4 lines" \
    "measured $pointer_lines lines — pointer must stay a pointer, not the pattern body"
fi

summary
