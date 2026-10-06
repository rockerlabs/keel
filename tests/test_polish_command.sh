#!/usr/bin/env bash
# tests/test_polish_command.sh — dir #670: pins on commands/polish.md's step 5 as K2 (slice 2) writes it —
# the review run by a fresh-context subagent first, for `low|medium|high`. Each pin is a single-line
# needle (pin() is line-mode grep -F), so a reword that wraps a needle across two lines turns a pin red
# on purpose: the rule's text is what these hold. The spawn needle is dir #413's one exemption (its A7
# lets exactly one `general-purpose` spawn line stand, by the phrase below on that line or the line
# before), so it is pinned by line position, not by presence alone.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

polish="$REPO_ROOT/commands/polish.md"
check_file "commands/polish.md exists" "$polish"

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
pin "step 5: K2 is the first attempt for low|medium|high" "$polish" \
  'the FIRST attempt is a review run by a fresh-context subagent (dir #670);' \
  "expected K2's lead sentence naming low|medium|high and the first attempt"
pin "step 5: max, ultra and skip keep their paths" "$polish" \
  '`max`, `ultra` and `skip` keep their paths below, unchanged.' \
  "expected K2 to say max/ultra/skip are unchanged"
pin "step 5: the direct attempt is for max, and for low|medium|high after K2's fallbacks" "$polish" \
  '`max` — and for `low|medium|high` once K2'"'"'s fallbacks send you here — ATTEMPT `Skill(code-review) <level>`' \
  "expected the direct in-session attempt to be second for low|medium|high"

# --- B2: the spawn ----------------------------------------------------------------------------------
pin "step 5: spawn precondition — no tracked change pending" "$polish" \
  '`git status --porcelain --untracked-files=no` must print nothing' \
  "expected the clean-tracked-tree precondition"
pin "step 5: a pending tracked change is committed, as its own commit" "$polish" \
  'commit exactly that work now, as its own commit' \
  "expected the dirty-tree commit rule"
pin "step 5: a step-5 commit makes step 6's retest REQUIRED" "$polish" \
  "so step 6's retest is then REQUIRED even if the review" \
  "expected the required-retest consequence of the commit"
pin "step 5: a tree that cannot be committed stops the run" "$polish" \
  'cannot be committed → stop and report' \
  "expected the commit-fails stop"
pin "step 5: HEAD and status are recorded right before the spawn" "$polish" \
  'Record `git rev-parse HEAD` and `git status --porcelain` right' \
  "expected the spawn-time record"
pin "step 5: the model is not pinned" "$polish" \
  'no `model` pin, so it runs this session'"'"'s own model' \
  "expected the unpinned model"
pin "step 5: a restricted reviewer type needs Skill and the read-only git verbs" "$polish" \
  'includes `Skill` and the read-only git verbs `diff`, `log`, `show` and `blame`.' \
  "expected dir #413's type condition"
pin "step 5: the prompt's fixed first line" "$polish" \
  'You are /polish step 5'"'"'s review subagent.' \
  "expected the fixed first line session-cost.sh tail finds the subagent by"
pin "step 5: the prompt carries the diff scope" "$polish" \
  'Then: the diff scope `git diff' \
  "expected the diff scope in the prompt"
pin "step 5: the prompt states a missing ticket explicitly" "$polish" \
  'step 5(a)'"'"'s two-way conformance mandate — or the explicit statement that none exists' \
  "expected the two-way mandate or the explicit absence"
pin "step 5: the args are level first, then the diff target" "$polish" \
  'origin/<default>...HEAD` — the level first (the gate reads the args'"'"' first word as the level), then the' \
  "expected the two-word args, level first"
pin "step 5: the args are the only channel to the review" "$polish" \
  '**The args are the only channel to the review itself:**' \
  "expected the args-channel statement"
pin "step 5: the skill's fork is not a subagent of its own" "$polish" \
  'The skill'"'"'s own fork is not "a subagent of your own" under the rails'"'"' no-spawn' \
  "expected the no-spawn-line reading"
pin "step 5: the subagent edits nothing and commits nothing" "$polish" \
  'line. Then: edit nothing, commit nothing; wait for the skill to finish, including any background agents' \
  "expected edit-nothing and the wait for background work"
pin "step 5: findings are restated in the final message" "$polish" \
  'it starts; restate every finding in your final message as `file:line — quoted text — failure scenario`,' \
  "expected the findings restatement"
pin "step 5: a ReportFindings-only reply still restates" "$polish" \
  'even after a `ReportFindings` call, and write `0 findings` explicitly when there are none; print no' \
  "expected the ReportFindings override and the explicit 0 findings"

# --- B3/B4: the trace and the return --------------------------------------------------------------------
pin "step 5: no marker, SubagentStop trace or dialog on this path" "$polish" \
  'level — so there is no marker line, no `SubagentStop` trace and no dialog on this path, and the receipt' \
  "expected the K2 path's trace statement"
pin "step 5: HEAD and status are compared after every return" "$polish" \
  'First compare `git rev-parse HEAD` and `git status --porcelain` with the values' \
  "expected the post-return compare"
pin "step 5: a changed tree voids the review and stops, never restored" "$polish" \
  'never restore the tree with `git checkout`/`reset`/`clean`/`stash` (dir #375),' \
  "expected the no-restore stop"
pin "step 5: a changed tree never falls through to the in-session attempt" "$polish" \
  'and never fall through to the in-session attempt on a tree the subagent changed.' \
  "expected the no-fallthrough rule"
pin "step 5: a reply with no findings list or '0 findings' is void" "$polish" \
  'neither a findings list nor an explicit `0 findings`' \
  "expected the void rule"
pin "step 5: the void reply goes to the in-session attempt" "$polish" \
  'skill launched: go to the in-session attempt below. Otherwise verify every finding live against the' \
  "expected the void-to-fallback route"
pin "step 5: a refuted finding is named in step 10" "$polish" \
  'finding that fails live verification is named as refuted, with why, in step 10'"'"'s summary.' \
  "expected the refuted-finding disclosure"

# --- B5: delta rounds -------------------------------------------------------------------------------
pin "step 5: a delta round goes to the SAME subagent" "$polish" \
  'the SAME subagent (its agent id — dir #127'"'"'s "same reviewer"), repeating the prompt'"'"'s instructions' \
  "expected the same-reviewer delta round"
pin "step 5: the delta round's args" "$polish" \
  'the Skill args are `<level> <the HEAD the last review saw>..HEAD`, so the fork' \
  "expected the delta args"
pin "step 5: HEAD and status are recorded again before each follow-up" "$polish" \
  'and status again before each follow-up message; the compare above applies to every return.' \
  "expected the per-message record"
pin "step 5: a full re-review is not dir #127's terminal signal" "$polish" \
  'which is not dir #127'"'"'s terminal signal.' \
  "expected the full-pass accounting"
pin "step 5: a gone subagent is replaced by a fresh spawn on the delta" "$polish" \
  '"No transcript found") → spawn a fresh one with' \
  "expected the gone-subagent path"

# --- B6/B6a: fallbacks --------------------------------------------------------------------------------
pin "step 5: a missing-trace deny after a moved HEAD is a delta round" "$polish" \
  'HEAD moved since the HEAD the last review saw (the' \
  "expected B6a's moved-HEAD routing"
pin "step 5: a missing-trace deny with HEAD unchanged goes in-session" "$polish" \
  'HEAD unchanged (the trace is genuinely missing) → the in-session attempt below.' \
  "expected B6a's unchanged-HEAD routing"
pin "step 5: the in-session fallback keeps the two-word args" "$polish" \
  'with the SAME two-word args `<level> origin/<default>...HEAD` (after step 8'"'"'s push the skill'"'"'s own' \
  "expected the fallback's args"
pin "step 5: the fallback order ends in (a) then (b)" "$polish" \
  'there too → (a) below; then (b). Each existing' \
  "expected the fallback order"

# --- B7/B7a: disclosure and clause fates -------------------------------------------------------------------
pin "step 5: the disclosure wording" "$polish" \
  'name this mechanism as "`/code-review <level>` run' \
  "expected the K2 disclosure wording"
pin "step 5: a bare level now means a genuine pass run here or by K2's subagent" "$polish" \
  '(bare — a genuine `/code-review` pass, run here in-session or by K2'"'"'s' \
  "expected B7a's bare-level reading"
check_absent "step 5: the retired 'bare — this IS the genuine in-session pass' wording is gone" \
  "$(cat "$polish")" 'bare — this IS the genuine in-session pass'
check_absent "step 5: the retired 'ordinary automated outcome' wording is gone" \
  "$(cat "$polish")" 'the ordinary automated outcome'
pin "step 5: the receipt catalogue names the subagent-run pass" "$polish" \
  'run by K2'"'"'s review subagent, or operator-typed or' \
  "expected the catalogue entry"
pin "step 6: a step-5 commit of pending work requires the retest" "$polish" \
  'step-5 commit of pending work (K2'"'"'s spawn precondition), which moves HEAD past step 3'"'"'s receipt and so' \
  "expected step 6's retest exception"
pin "step 10: the summary names the subagent-run mechanism" "$polish" \
  '`/code-review <level>` run by a fresh-context subagent (K2); an independent agent review' \
  "expected step 10's mechanism list"

summary
