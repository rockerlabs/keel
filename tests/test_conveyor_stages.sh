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
  # match(), not a direct `printf | grep -q` pipe (dir #280 — see tests/lib.sh's match() for why).
  if match "$window" -qi 'done-criterion'; then
    pass "FRAMEWORK.md: tests-before-or-alongside line gains a done-criterion cross-link"
  else
    fail "FRAMEWORK.md: tests-before-or-alongside line gains a done-criterion cross-link" \
      "expected a nearby sentence mentioning a written done-criterion"
  fi
  if match "$window" -qE '/go\.md|/polish\.md|dir #[0-9]'; then
    fail "FRAMEWORK.md: cross-link sentence stays generic" \
      "found a keel-internal reference (dir #N or a command path) in an adopter-usable doc"
  else
    pass "FRAMEWORK.md: cross-link sentence stays generic (no keel-internal references)"
  fi
fi

# (D) dir #183: step 5's add-on paragraph states the SINGLE-add-on rule, its operator-run
# tie-break, and that nothing warns you any more. This block replaces dir #161's own pin, which
# asserted the opposite (that the paragraph documents an add-on-drop warning as a MANDATORY read) —
# dir #183 deleted that warning along with the
# comma-set parser, so the old pin was holding a now-false claim in place. Windowed on the paragraph
# itself (same idiom as block (C)) rather than a bare file-wide grep: `dir #161` alone is still present
# in the new paragraph, which explains what was removed and why, so a bare grep for it proves nothing.
# The window also asserts the old "prints a warning naming it" wording is actually GONE, not merely
# supplemented — the same GONE-not-supplemented discipline dir #161's own pin used, pointed the other
# way.
# **Anchored on the single-add-on rule, not on the SHIPPED-COMMIT sentence, and widened to +30**
# (both corrected during this ticket's own /simplify pass): the earlier anchor sat BELOW the rule it
# claimed to pin, so the window covered the "nothing warns you" half only and the header's "states the
# SINGLE-add-on rule" was an overclaim — a pin whose comment promises more than its window reaches is
# worse than no pin, since it reads as coverage.
addon_line="$(grep -n 'receipt carries AT MOST ONE add-on' "$polish" | head -1 | cut -d: -f1)"
if [ -z "$addon_line" ]; then
  fail "polish.md: add-on paragraph present" "anchor sentence not found"
else
  # +45, not +30: the furthest needle sat 3 lines from a +30 edge, so any clarification added to
  # this paragraph — or a re-wrap, one of which this ticket itself made — would red a pin whose prose
  # is entirely correct. The window is a locality check, not a line budget; err wide.
  addon_window="$(sed -n "${addon_line},$((addon_line + 45))p" "$polish")"
  # match(), not a direct `printf | grep -q` pipe (dir #280 — see tests/lib.sh's match() for why).
  if match "$addon_window" -qi 'nothing warns you' && match "$addon_window" -qi 'dir #183'; then
    pass "polish.md: step 5 states that a dropped add-on no longer warns (dir #183)"
  else
    fail "polish.md: step 5 states that a dropped add-on no longer warns (dir #183)" \
      "expected a 'nothing warns you ... (dir #183)' clause in the add-on paragraph"
  fi
  if match "$addon_window" -qi 'prints a warning naming it'; then
    fail "polish.md: the old, now-false 'prints a warning' sentence is gone" \
      "found dir #161's warn description still present, but dir #183 deleted that warning"
  else
    pass "polish.md: the old, now-false 'prints a warning' sentence is gone"
  fi
  # The single-add-on rule and its tie-break — the half the old anchor never reached. This is where
  # dir #183 moved dir #81's honesty guarantee OUT of the mechanically-validated receipt, so it is the
  # sentence with the least other protection in the tree.
  if match "$addon_window" -qi 'operator-run` wins the receipt slot'; then
    pass "polish.md: step 5 states the operator-run-wins tie-break for the single add-on slot"
  else
    fail "polish.md: step 5 states the operator-run-wins tie-break for the single add-on slot" \
      "expected the rule naming which add-on takes the receipt slot when both applied"
  fi
  # The warning is gone, so what replaces it must be named, not merely omitted: the session's own read
  # of the live sentinel AND the step-10 disclosure. Otherwise the deletion reads as "one fewer thing to
  # do" rather than "the same obligation, now yours" — the silent-degradation shape dir #161's own
  # MANDATORY-read pin guarded against from the other direction. **Two separate assertions, not one
  # `||`** (corrected in this ticket's own /simplify pass): an OR is satisfied by either phrase, so
  # deleting the concrete live-sentinel instruction would have left this green on the leftover mention
  # of the other — neither replacement individually pinned, which is the whole point of the pin.
  if match "$addon_window" -qi 'live sentinel'; then
    pass "polish.md: step 5 names the live-sentinel read that replaces the deleted warning"
  else
    fail "polish.md: step 5 names the live-sentinel read that replaces the deleted warning" \
      "expected the concrete instruction to read this run's earlier polish.5-review line"
  fi
  if match "$addon_window" -qi 'step-10 disclosure'; then
    pass "polish.md: step 5 names the step-10 disclosure as the record that now carries every mechanism"
  else
    fail "polish.md: step 5 names the step-10 disclosure as the record that now carries every mechanism" \
      "expected the paragraph to point at the step-10 disclosure, not only the sentinel read"
  fi
fi

# (E) dir #254: `Skill(code-review)`'s model-invocation block has lifted, so step 5 now attempts the
# real skill directly for `low|medium|high|max` FIRST, and the independent-subagent path (dir #70) is
# the fallback for a refused attempt, not the standing default. Two windows, same idiom as block (D):
# assert the new prose is present AND the old, now-false prose it replaces is gone, so a revert or a
# partial edit both fail loudly instead of going unnoticed.
ask_line="$(grep -n 'Then decide \*\*auto vs ask\*\*' "$polish" | head -1 | cut -d: -f1)"
if [ -z "$ask_line" ]; then
  fail "polish.md: step 4's auto-vs-ask decision still present" "anchor sentence not found"
else
  ask_window="$(sed -n "${ask_line},$((ask_line + 10))p" "$polish")"
  # No backslash before the backtick: inside single quotes it's already a shell-literal backtick, and
  # `\`` is a GNU grep extension meaning "start of buffer" (paired with `\'`) — escaping it here matched
  # BSD grep/busybox (backtick taken literally either way) but silently failed on GNU grep/Linux CI,
  # since the pattern then required three buffer-starts in one line and could never match mid-string
  # (found live via Docker ubuntu:24.04 + GNU grep 3.11, cross-checked against BSD grep 2.6.0-FreeBSD).
  if match "$ask_window" -qE '`max`.*`ultra`.*always open'; then
    pass "polish.md: step 4's mandatory-ask threshold is max/ultra (dir #254, raised from high)"
  else
    fail "polish.md: step 4's mandatory-ask threshold is max/ultra (dir #254, raised from high)" \
      "expected a '\`max\` or \`ultra\` -> always open' clause"
  fi
  if match "$ask_window" -qE '`high` or above → always open'; then
    fail "polish.md: the old, now-false 'high or above -> always ask' sentence is gone" \
      "found the pre-dir-#254 high-and-above threshold still present alongside the new wording"
  else
    pass "polish.md: the old, now-false 'high or above -> always ask' sentence is gone"
  fi
fi

review_line="$(grep -n 'one terminal pass, no loop-back' "$polish" | head -1 | cut -d: -f1)"
if [ -z "$review_line" ]; then
  fail "polish.md: step 5's review intro still present" "anchor sentence not found"
else
  review_window="$(sed -n "${review_line},$((review_line + 15))p" "$polish")"
  if match "$review_window" -qi 'ATTEMPT `Skill(code-review)'; then
    pass "polish.md: step 5 attempts the real Skill(code-review) call FIRST (dir #254)"
  else
    fail "polish.md: step 5 attempts the real Skill(code-review) call FIRST (dir #254)" \
      "expected an 'ATTEMPT \`Skill(code-review)\`' clause ahead of the subagent fallback"
  fi
  if match "$review_window" -qi 'do NOT attempt `Skill(code-review)`'; then
    fail "polish.md: the old, now-false 'do NOT attempt the skill' sentence is gone" \
      "found the pre-dir-#254 blanket-unavailable sentence still present alongside the new wording"
  else
    pass "polish.md: the old, now-false 'do NOT attempt the skill' sentence is gone"
  fi
fi

if grep -qi '(a) Fallback for .*reached when the direct attempt above was refused' "$polish"; then
  pass "polish.md: branch (a)'s subagent is framed as the refusal fallback, not the standing default"
else
  fail "polish.md: branch (a)'s subagent is framed as the refusal fallback, not the standing default" \
    "expected (a)'s intro to name itself as reached on a refused direct attempt"
fi

# (F) dir #206: step 9 gains an already-open-PR branch (a review finding corrected the source after the
# PR opened, and nothing re-derived the body) — named triggers with a concrete check each, not a general
# re-read; step 1 points at it from the convergence-round sequence sentence.
if grep -qi 'Already-open-PR branch' "$polish"; then
  pass "polish.md: step 9 gains an already-open-PR branch"
else
  fail "polish.md: step 9 gains an already-open-PR branch" \
    "expected an 'Already-open-PR branch' heading in step 9"
fi
pin "polish.md step 9's already-open-PR branch carries the test/CI-outcome trigger row" \
  "$polish" '| a test or CI outcome ("suite green", "tests pass") | re-derive it from the run bound to **current HEAD**, not from the round that first wrote the sentence |' \
  "expected the trigger table's test/CI-outcome row naming a re-derive-from-current-HEAD check"
if grep -qi 'every recorded catch of this class came from a cross-session reviewer' "$polish"; then
  pass "polish.md: step 9 states the known cross-session-only weakness of the already-open-PR branch"
else
  fail "polish.md: step 9 states the known cross-session-only weakness of the already-open-PR branch" \
    "expected a clause naming that every recorded catch came from a cross-session reviewer"
fi
if grep -qi "step 9's already-open-PR" "$polish"; then
  pass "polish.md: step 1's convergence-round sequence sentence points at step 9's already-open-PR branch"
else
  fail "polish.md: step 1's convergence-round sequence sentence points at step 9's already-open-PR branch" \
    "expected step 1's sequence sentence to point at step 9 for an already-open PR"
fi

summary
