#!/usr/bin/env bash
# tests/test_polish_command.sh — dir #670: pins on commands/polish.md's step 5 as K2 (slice 2) writes it —
# the review run by a fresh-context subagent first, for `low|medium|high`. Each pin is a needle matched
# against the file with its line breaks and runs of spaces collapsed (pinf below), so re-wrapping prose never
# turns one red; only a change of the words does — the rule's text is what these hold. The spawn needle is dir #413's one exemption (its A7
# lets exactly one `general-purpose` spawn line stand, by the phrase below on that line or the line
# before), so it is pinned by line position, not by presence alone.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

polish="$REPO_ROOT/commands/polish.md"
check_file "commands/polish.md exists" "$polish"

# pinf LABEL NEEDLE HINT — NEEDLE as a fixed string in polish.md read as ONE line (newlines -> spaces, space
# runs collapsed), so a needle may span a wrap point and prose can be re-wrapped freely.
flat="$(tr '\n' ' ' < "$polish" | tr -s ' ')"
pinf() { check_contains "$1" "$flat" "$2" ; }

# --- the spawn line and dir #413's needle -------------------------------------------------------------
# Of the lines carrying `subagent_type: "general-purpose"`, at least one has the needle on it or on the
# line before. (polish.md has other general-purpose lines — the (a) fallback, the second opinion — which
# are dir #413's to retire; this one is K2's.)
needle="step 5's review subagent"
spawn_ok="$(awk -v n="$needle" '
  index($0, "subagent_type: \"general-purpose\"") { if (index($0, n) || index(prev, n)) ok = 1 }
  { prev = $0 }
  END { print ok ? "yes" : "no" }' "$polish")"
check_eq "K2's spawn line carries the needle on it or the line before (dir #413 A7's exemption)" "yes" "$spawn_ok"

# --- B1: when ---------------------------------------------------------------------------------------
pinf "step 5: K2 is the first attempt for low|medium|high" \
  'the FIRST attempt is a review run by a fresh-context subagent (dir #670);'
pinf "step 5: max, ultra and skip keep their paths" \
  '`max`, `ultra` and `skip` keep their paths below, unchanged.'
pinf "step 5: the direct attempt is for max, and for low|medium|high after K2's fallbacks" \
  '`max` — and for `low|medium|high` once K2'"'"'s fallbacks send you here — ATTEMPT `Skill(code-review) <level>`'

# --- B2: the spawn ----------------------------------------------------------------------------------
pinf "step 5: spawn precondition — no tracked change pending" \
  '`git status --porcelain --untracked-files=no` must print nothing'
pinf "step 5: a pending tracked change is committed, as its own commit" \
  'commit exactly that work now, as its own commit'
pinf "step 5: a step-5 commit makes step 6's retest REQUIRED" \
  "step 6's retest is then REQUIRED"
pinf "step 5: a tree that cannot be committed stops the run" \
  'cannot be committed → stop and report'
pinf "step 5: HEAD and status are recorded right before the spawn" \
  'Record `git rev-parse HEAD` and `git status --porcelain` right before the spawn'
pinf "step 5: the model is not pinned" \
  'no `model` pin, so it runs this session'"'"'s own model'
pinf "step 5: a restricted reviewer type needs Skill and the read-only git verbs" \
  'includes `Skill` and the read-only git verbs `diff`, `log`, `show` and `blame`.'
# the cost tool finds the review subagent by this exact line, so polish.md's text is pinned to the tool's constant
fixed_line="$(sed -n 's/^SC_REVIEW_FIRST_LINE="\(.*\)"$/\1/p' "$REPO_ROOT/tools/self/session-cost.sh")"
check_ne "session-cost.sh defines SC_REVIEW_FIRST_LINE" "" "$fixed_line"
pinf "step 5: the prompt's first line is exactly session-cost.sh's SC_REVIEW_FIRST_LINE" \
  "The FIRST line is exactly \`$fixed_line\`"
pinf "step 5: the prompt carries the diff scope" \
  'the diff scope `git diff origin/<default>...HEAD`'
pinf "step 5: the prompt states a missing ticket explicitly" \
  'step 5(a)'"'"'s two-way conformance mandate — or the explicit statement that none exists'
pinf "step 5: the args are level first, then the diff target" \
  'the level first (the gate reads the args'"'"' first word as the level), then the diff target'
pinf "step 5: the args are the only channel to the review" \
  '**The args are the only channel to the review itself:**'
pinf "step 5: the skill's fork is not a subagent of its own" \
  'is not "a subagent of your own" under the rails'"'"' no-spawn line'
pinf "step 5: the subagent edits nothing and commits nothing" \
  'edit nothing, commit nothing; wait for the skill to finish, including any background agents'
pinf "step 5: findings are restated in the final message" \
  'restate every finding in your final message as `file:line — quoted text — failure scenario`'
pinf "step 5: a ReportFindings-only reply still restates" \
  'even after a `ReportFindings` call, and write `0 findings` explicitly'

# --- B3/B4: the trace and the return --------------------------------------------------------------------
pinf "step 5: the trace is minted when the Skill call returns, as the fork launches" \
  'when the Skill call returns (for the forked review, as it launches)'
pinf "step 5: no marker, SubagentStop trace or dialog on this path" \
  'no marker line, no `SubagentStop` trace and no dialog on this path'
pinf "step 5: HEAD and status are compared after every return" \
  'compare `git rev-parse HEAD` and `git status --porcelain` with the values recorded at the spawn'
pinf "step 5: a changed tree voids the review and stops, never restored" \
  'never restore the tree with `git checkout`/`reset`/`clean`/`stash` (dir #375),'
pinf "step 5: a changed tree never falls through to the in-session attempt" \
  'and never fall through to the in-session attempt on a tree the subagent changed.'
pinf "step 5: a reply with no findings list or '0 findings' is void" \
  'neither a findings list nor an explicit `0 findings`'
pinf "step 5: the void reply goes to the in-session attempt" \
  'go to the in-session attempt below. Otherwise verify every finding live against the file'
pinf "step 5: a refuted finding is named in step 10" \
  'finding that fails live verification is named as refuted, with why, in step 10'"'"'s summary.'

# --- B5: delta rounds -------------------------------------------------------------------------------
pinf "step 5: a delta round goes to the SAME subagent" \
  'the SAME subagent (its agent id'
pinf "step 5: the delta round's args" \
  'the Skill args are `<level> <the HEAD the last review saw>..HEAD`'
pinf "step 5: HEAD and status are recorded again before each follow-up" \
  'and status again before each follow-up message'
pinf "step 5: a full re-review is not dir #127's terminal signal" \
  'which is not dir #127'"'"'s terminal signal.'
pinf "step 5: a gone subagent is replaced by a fresh spawn on the delta" \
  'spawn a fresh one with the same prompt, the delta as the args'"'"' target'

# --- B6/B6a: fallbacks --------------------------------------------------------------------------------
pinf "step 5: a missing-trace deny after a moved HEAD is a delta round" \
  'HEAD moved since the HEAD the last review saw'
pinf "step 5: a missing-trace deny after an in-session review re-reviews in-session" \
  'unless that review itself ran in-session (a fallback below), when no K2 subagent exists'
pinf "step 5: a missing-trace deny with HEAD unchanged goes in-session" \
  'HEAD unchanged (the trace is genuinely missing) → the in-session attempt below.'
pinf "step 5: the in-session fallback keeps the two-word args" \
  'with the SAME two-word args `<level> origin/<default>...HEAD`'
pinf "step 5: the fallback order ends in (a) then (b)" \
  'refused there too → (a) below; then (b)'

# --- B7/B7a: disclosure and clause fates -------------------------------------------------------------------
pinf "step 5: the disclosure wording" \
  'name this mechanism as "`/code-review <level>` run by a fresh-context subagent"'
pinf "step 5: a bare level now means a genuine pass run here or by K2's subagent" \
  '(bare — a genuine `/code-review` pass, run here in-session or by K2'"'"'s subagent)'
check_absent "step 5: the retired 'bare — this IS the genuine in-session pass' wording is gone" \
  "$(cat "$polish")" 'bare — this IS the genuine in-session pass'
check_absent "step 5: the retired 'ordinary automated outcome' wording is gone" \
  "$(cat "$polish")" 'the ordinary automated outcome'
pinf "step 5: the receipt catalogue names the subagent-run pass" \
  'run by K2'"'"'s review subagent, or operator-typed or revisit-triggered in-session'
pinf "step 6: a step-5 commit of pending work requires the retest" \
  'step-5 commit of pending work (K2'"'"'s spawn precondition)'
pinf "step 10: the summary names the subagent-run mechanism" \
  '`/code-review <level>` run by a fresh-context subagent (K2); an independent agent review'

summary
