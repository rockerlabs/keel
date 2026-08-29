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

# (D) dir #161: step 5's add-on-set paragraph states the new warn behavior — dropping a prior round's
# add-on from a fresh step-5 receipt now prints a warning naming it, not silence. Windowed on the
# paragraph itself (same idiom as block (C)) rather than a bare file-wide grep: `dir #161` alone was
# already present in the OLD, now-false sentence this paragraph replaces, so a bare grep for it proves
# nothing — and the window also asserts that old sentence is actually GONE, not just supplemented
# (found by the cross-model second-opinion review on this ticket's own diff).
addon_line="$(grep -n "set's unit is the SHIPPED COMMIT" "$polish" | head -1 | cut -d: -f1)"
if [ -z "$addon_line" ]; then
  fail "polish.md: add-on-set paragraph still present" "anchor sentence not found"
else
  addon_window="$(sed -n "${addon_line},$((addon_line + 20))p" "$polish")"
  # match(), not a direct `printf | grep -q` pipe (dir #280 — see tests/lib.sh's match() for why).
  if match "$addon_window" -qi 'drops an add-on' && match "$addon_window" -qi 'dir #161'; then
    pass "polish.md: step 5 states the add-on-drop warning (dir #161)"
  else
    fail "polish.md: step 5 states the add-on-drop warning (dir #161)" \
      "expected a 'drops an add-on ... (dir #161)' clause in the add-on set paragraph"
  fi
  if match "$addon_window" -qi 'nothing denies or warns if you forget'; then
    fail "polish.md: the old, now-false 'nothing warns' sentence is gone" \
      "found the pre-dir-#161 sentence still present alongside the new wording"
  else
    pass "polish.md: the old, now-false 'nothing warns' sentence is gone"
  fi
  # dir #161 /code-review high (glide-past-risk finding): the warning must be a MANDATORY read, not
  # just a documented tool behavior — otherwise the mechanism this ticket built can itself be silently
  # ignored by a session, the same shape of miss dir #155 already showed happens with a text-only cue.
  if match "$addon_window" -qi 'MANDATORY read'; then
    pass "polish.md: step 5 states the add-on-drop warning must be actively read, not skimmed past"
  else
    fail "polish.md: step 5 states the add-on-drop warning must be actively read, not skimmed past" \
      "expected a 'MANDATORY read' (or equivalent) clause instructing the session to check receipt output"
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

summary
