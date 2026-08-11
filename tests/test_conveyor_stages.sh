#!/usr/bin/env bash
# test_conveyor_stages.sh — dir #78: pins the two conveyor stages keel's own pipeline was missing
# (acceptance-tests-before-code in /go, and a spec-fed conformance mandate for /polish step 5(a)'s
# independent reviewer), plus the FRAMEWORK.md cross-link. Grep-based, same idiom as
# test_doc_figures.sh's droppable-heading pins — a later edit that silently drops this prose should
# fail loudly instead of just being unnoticed.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

go="$REPO_ROOT/commands/go.md"
polish="$REPO_ROOT/commands/polish.md"
framework="$REPO_ROOT/FRAMEWORK.md"

check_file "commands/go.md exists" "$go"
check_file "commands/polish.md exists" "$polish"
check_file "FRAMEWORK.md exists" "$framework"

# (A) /go derives failing acceptance tests from the ticket's done-criterion before implementing,
# with an explicit escape hatch for genuinely test-infeasible tickets.
if grep -qi 'acceptance tests' "$go" && grep -qi 'done-criterion' "$go"; then
  pass "go.md: names deriving acceptance tests from the ticket's done-criterion"
else
  fail "go.md: names deriving acceptance tests from the ticket's done-criterion" \
    "expected an 'acceptance tests' + 'done-criterion' paragraph"
fi

# The `skipped:<reason>` reference is deliberately KEPT rather than dropped (dir #112): the analogy was
# the problem only while it was unqualified, so go.md now names it *and* says it has none of /polish's
# mechanism. test_rails_honesty.sh pins that second half; this pin holds the first. Deleting the analogy
# outright fails here — qualify it instead.
if grep -qi 'infeasible' "$go" && grep -qi 'skipped:<reason>' "$go"; then
  pass "go.md: names the test-infeasible escape hatch (executed decision, not a silent skip)"
else
  fail "go.md: names the test-infeasible escape hatch" \
    "expected an 'infeasible' clause referencing /polish's skipped:<reason> receipts"
fi

# (B) /polish step 5(a)'s subagent prompt carries the ticket/spec + a two-way conformance mandate,
# with an explicit no-ticket fallback.
if grep -qi 'two-way conformance' "$polish"; then
  pass "polish.md: step 5(a) prompt carries a two-way conformance mandate"
else
  fail "polish.md: step 5(a) prompt carries a two-way conformance mandate" \
    "expected 'two-way conformance' in the subagent prompt-contents list"
fi

if grep -qi 'no ticket exists' "$polish" || grep -qi 'no-ticket fallback' "$polish"; then
  pass "polish.md: step 5(a) states the no-ticket fallback explicitly"
else
  fail "polish.md: step 5(a) states the no-ticket fallback explicitly" \
    "expected an explicit 'no ticket exists' / no-ticket-fallback clause"
fi

# (C) FRAMEWORK.md's tests-before-or-alongside line gains a generic cross-link sentence — no
# keel-internal references (dir #N, /go, /polish) leaking into the adopter-usable doc.
design_line="$(grep -n 'write tests before or alongside implementation' "$framework" | head -1 | cut -d: -f1)"
if [ -z "$design_line" ]; then
  fail "FRAMEWORK.md: tests-before-or-alongside line still present" "line not found"
else
  # the cross-link sentence should land within the next few lines of the same bullet
  window="$(sed -n "${design_line},$((design_line + 4))p" "$framework")"
  if printf '%s' "$window" | grep -qi 'done-criterion'; then
    pass "FRAMEWORK.md: tests-before-or-alongside line gains a done-criterion cross-link"
  else
    fail "FRAMEWORK.md: tests-before-or-alongside line gains a done-criterion cross-link" \
      "expected a nearby sentence mentioning a written done-criterion"
  fi
  if printf '%s' "$window" | grep -qE '/go\.md|/polish\.md|dir #[0-9]'; then
    fail "FRAMEWORK.md: cross-link sentence stays generic" \
      "found a keel-internal reference (dir #N or a command path) in an adopter-usable doc"
  else
    pass "FRAMEWORK.md: cross-link sentence stays generic (no keel-internal references)"
  fi
fi

summary
