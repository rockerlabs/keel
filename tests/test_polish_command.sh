#!/usr/bin/env bash
# tests/test_polish_command.sh — dir #670: pins on commands/polish.md, the core, and its hidden guide
# commands/polish-guide.md. Slice 2 (K2): step 5's review run by a fresh-context subagent first, for
# `low|medium|high`. Slice 3 (K1): the split — a core of at most POLISH_MD_WORD_BUDGET words that a
# normal run reads alone, plus a guide holding every rare branch, loaded on a named trigger.
# Needles are matched against the file with its line breaks and runs of spaces collapsed (pinf/ping
# below), so re-wrapping prose never turns a pin red — only a change of the words does. The spawn needle
# is dir #413's one exemption (its A7 lets exactly one `general-purpose` spawn line stand, by the phrase
# below on that line or the line before), so it is pinned by line position, not by presence alone.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

polish="$REPO_ROOT/commands/polish.md"
guide="$REPO_ROOT/commands/polish-guide.md"
check_file "commands/polish.md exists" "$polish"
check_file "commands/polish-guide.md exists" "$guide"

# pinf LABEL NEEDLE — NEEDLE as a fixed string in the CORE read as ONE line (newlines -> spaces, space runs
# collapsed). ping is the same against the GUIDE.
flat="$(tr '\n' ' ' < "$polish" | tr -s ' ')"
gflat="$(tr '\n' ' ' < "$guide" | tr -s ' ')"
pinf() { check_contains "$1" "$flat" "$2"; }
pinfg() { check_contains "$1" "$gflat" "$2"; }
pinfgn() { check_absent "$1" "$gflat" "$2"; }

# --- K1 (slice 3): size — the core stays at most POLISH_MD_WORD_BUDGET words ---------------------------------
# A normal run loads only the core, and a skill's body re-enters every later turn's context, so its size is
# the cost this split exists to cut. The guide has no budget: it holds rare text verbatim.
POLISH_MD_WORD_BUDGET=3000
# budget_status FILE — "ok", or "over by N" words (the one predicate both checks below run).
budget_status() {
  local w; w="$(wc -w < "$1" | tr -d ' ')"
  if [ "$w" -le "$POLISH_MD_WORD_BUDGET" ]; then echo ok; else echo "over by $((w - POLISH_MD_WORD_BUDGET))"; fi
}
core_words="$(wc -w < "$polish" | tr -d ' ')"
check_eq "polish.md is within POLISH_MD_WORD_BUDGET ($core_words words, budget $POLISH_MD_WORD_BUDGET)" "ok" "$(budget_status "$polish")"
# The predicate must be able to fail: a copy one word over the budget reads red.
over="$SANDBOX/polish-over.md"
# Built from scratch, not from the core: a count derived from $core_words goes negative once the core passes the
# budget, and `head -n -N` never ends on GNU/busybox.
yes extra | head -n $((POLISH_MD_WORD_BUDGET + 1)) | tr '\n' ' ' > "$over"
check_eq "the budget predicate is red against a copy exactly one word over" "over by 1" "$(budget_status "$over")"

# --- K1: the guide's own header (B8d) ------------------------------------------------------------------
check_eq "polish-guide.md opens a leading --- block" "---" "$(sed -n 1p "$guide")"
guide_head="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$guide")"
check_contains "polish-guide.md is hidden from invocation (user-invocable: false)" "$guide_head" "user-invocable: false"
check_contains "polish-guide.md carries a description: line in its leading block" "$guide_head" "description: "
pinfg "polish-guide.md says the core wins a disagreement" 'Where this guide and `polish.md` (the core) disagree, the core wins.'
pinf "polish.md says the core wins a disagreement" 'Where the guide and this file disagree, this file wins.'

# --- K1: the pointer (B8c) — every step's own trigger list, and the exact instruction ----------------------
# step_text N — the text of numbered step N, from "N. **" to the next step's line.
step_text() {
  awk -v n="$1" -v nx="$(($1 + 1))" '
    $0 ~ "^"n"\\. \\*\\*" { f = 1; print; next }
    f && $0 ~ "^"nx"\\. \\*\\*" { exit }
    f { print }' "$polish" | tr '\n' ' ' | tr -s ' '
}
instr='load the `polish-guide` skill (`keel-polish-guide` if aliased), else `polish-guide.md` beside this file'
# ends_with_rare N — step N's text from its LAST "*Rare —" marker on, i.e. the pointer line the step ends with.
ends_with_rare() { step_text "$1" | sed 's/.*\*Rare — /*Rare — /'; }
# dir #739 (build A): the load instruction is stated ONCE, in **The guide.**; steps 1, 4 and 5 (and step 2)
# end with the short form "the guide, § Step N." and carry neither the instruction nor "unreachable".
# Steps 8 and 9 still carry the long form until slice 3 dedupes them, so each count below is 3.
for n in 1 4 5 8 9; do
  t="$(ends_with_rare "$n")"
  check_contains "step $n ends with a rare-trigger marker" "$t" "*Rare — "
  check_contains "step $n's closing pointer names its guide section" "$t" "§ Step $n"
done
for n in 1 4 5; do
  t="$(ends_with_rare "$n")"
  check_contains "step $n's closing pointer is the short form ending the step" "$t" "the guide, § Step $n."
  check_absent "step $n's pointer does not repeat the guide-loading instruction" "$t" "$instr"
  check_absent "step $n's pointer does not repeat the unreachable-guide clause" "$t" "unreachable"
done
for n in 8 9; do
  t="$(ends_with_rare "$n")"
  check_contains "step $n ends with the exact guide-loading instruction" "$t" "$instr"
  check_contains "step $n's closing pointer says an unreachable guide stops the run" "$t" "guide unreachable → stop and report"
done
# **The guide.** paragraph: from its bold lead to the sentence that follows it.
gpara="${flat#*'**The guide.**'}"
gpara="${gpara%%'Where the guide and this file disagree'*}"
check_contains "**The guide.** states the guide-loading instruction" "$gpara" "$instr"
check_contains "**The guide.** says an unreachable guide stops the run" "$gpara" "guide unreachable → stop and report"
check_contains "**The guide.** forbids improvising a branch" "$gpara" "Never improvise a branch."
check_eq "the guide-loading instruction appears 3 times in the core (The guide., steps 8, 9)" "3" "$(grep -oF "$instr" <<< "$flat" | wc -l | tr -d ' ')"
check_eq "'unreachable' appears 3 times in the core (The guide., steps 8, 9)" "3" "$(grep -oF "unreachable" <<< "$flat" | wc -l | tr -d ' ')"
check_contains "step 9's closing pointer also reaches step 10's add-on summary forms" "$(ends_with_rare 9)" "§ Step 10 for the add-on summary forms"
check_contains "step 1's trigger list names a convergence round and --recover" "$(step_text 1)" 'a convergence round'
check_contains "step 1's trigger list names --recover" "$(step_text 1)" '`--recover`'
check_contains "step 4's trigger list names a handoff-check match" "$(step_text 4)" 'a `handoff-check` match'
check_contains "step 4's trigger list names the max/ultra/skip/borderline dialogs" "$(step_text 4)" 'max/ultra/skip/borderline dialogs'
check_contains "step 5's trigger list names a refused attempt or an unavailable Agent tool" "$(step_text 5)" 'the direct attempt refused or the Agent tool unavailable'
check_contains "step 5's trigger list names a void review" "$(step_text 5)" 'a void review'
check_contains "step 5's trigger list names an add-on review" "$(step_text 5)" 'an add-on review'
check_contains "step 5's trigger list names a second delta round still finding" "$(step_text 5)" 'a second delta round still finding'
check_contains "step 8's trigger list names a deny" "$(step_text 8)" 'any deny'
check_contains "step 9's trigger list names an already-open PR" "$(step_text 9)" 'the PR is already open'
check_contains "step 9's trigger list names an add-on disclosure" "$(step_text 9)" "an add-on review's disclosure"
for n in 1 2 3 4 5 6 7 8 9 10; do
  check_ne "step $n exists in the core" "" "$(step_text "$n")"
done
for h in 'Preamble' 'Step 1' 'Step 2' 'Step 3' 'Step 4' 'Step 5' 'Step 6' 'Step 7' 'Step 8' 'Step 9' 'Step 10'; do
  pinfg "polish-guide.md has a section for $h" "## $h "
done

# --- K1: what a normal run needs stays in the CORE (B8b) -----------------------------------------------------
# dir #678: step 3 backgrounds the suite with an explicit timeout and never reports a cut-short run as green.
pinf "core: step 3 backgrounds the suite with an explicit timeout" 'backgrounded with an explicit timeout past the suite'
pinf "core: step 3 says a cut-short run is not green" 'A cut-short run is not green: re-run the remainder.'
pinf "core: step 9 requires --head" '`gh pr create --head <branch>` — `--head` is mandatory'
pinf "core: step 9 writes every receipt in its own Bash call" 'Write every receipt in its own Bash call and invoke `gh pr create` alone in the next'
pinf "core: step 8 pushes before it unlocks" 'Push the branch first'
pinf "core: step 8's unlock receipt binds HEAD" '`tools/pre-pr-gate.sh receipt polish.8-unlock "$(git rev-parse HEAD)"`'
pinf "core: step 6's retest receipt binds HEAD" '`tools/pre-pr-gate.sh receipt polish.6-retest "$(git rev-parse HEAD)"`'
pinf "core: step 3's tests receipt binds HEAD" '`tools/pre-pr-gate.sh receipt polish.3-tests "$(git rev-parse HEAD)"`'
check_contains "core: step 1 mints the run's nonce with init" "$(step_text 1)" '`tools/pre-pr-gate.sh init`'
pinf "core: step 4's receipt carries the sizing evidence" '`tools/pre-pr-gate.sh receipt polish.4-depth <level>:<what it was sized from>`'
pinf "core: the delta-round budget" 'the full review runs once, then at most TWO delta rounds'
pinf "core: dir #244's commit-message re-read after an --amend" 'on `--amend`, re-read the commit message against the final diff (dir #244)'
pinf "core: step 6 never commits while a background suite run is alive" '**Never commit, amend or edit while a background suite run is alive**'
pinf "core: a finding's fix is folded into one commit where practical" "Fold a finding's fix into one commit where practical"
check_contains "core: step 6 skips the re-run when nothing changed" "$(step_text 6)" "Nothing changed → skip the re-run (\`skipped:no-file-changes\`)"
pinf "core: ordering rule 1 is named, K2 cites it" '**Ordering rule 1 — have the implementation committed by step 3**'
pinf "core: dir #488's review-null exception is defined where K2 cites it" "decided by the gate's own diff check, never your say-so: a later fix commit that is wholly comment/blank-line changes to already-reviewed \`.sh\` files keeps the earlier trace at that level; anything else needs a fresh one"
check_contains "core: step 6 skips the retest under --no-test" "$(step_text 6)" "and tests weren't \`--no-test\`-skipped, re-run the test command once"
check_contains "core: step 7 sends a fix commit to a convergence round" "$(step_text 7)" "A fix commit for what it flagged → re-invoke \`/polish\`: a convergence round (step 1's pointer)"
pinf "core: the receipt contract" 'The gate denies `gh pr create` unless every step id is present for the current run'
pinf "core: step 4's bucket table" 'pure docs/wording, no cross-references → **skip**'
pinf "core: step 4's auto rule" '`low`/`medium`/`high` clearly inside one bucket → run it automatically'
pinf "core: step 4's dialog marker" 'ended by the literal line `KEEL-DEPTH-DIALOG`'
# dir #721 S3-2 (the audit's #528 finding): the honesty / dialog / step-9 rails a NORMAL run reads ONLY in the
# core. tests/test_rails_honesty.sh pins the guide's copy of the same paragraphs — a copy a normal run never
# loads — so each clause below is held on the core itself, in the step that owns it (step_text N), and each
# was shown red by deleting exactly that clause from polish.md.
check_contains "core S3-2: step 2's refused-or-unavailable pointer" "$(step_text 2)" 'Refused or unavailable → § Step 2.'
check_contains "core S3-2: step 4's dialog is ALWAYS raised for skip, max and ultra" "$(step_text 4)" 'ALWAYS for `skip`, `max` and `ultra`'
check_contains "core S3-2: step 5 says ultra stops for real, with its guide pointer" "$(step_text 5)" '`ultra` cannot be launched from here → guide § Step 5 (b).'
check_contains "core S3-2: step 9's body names every review mechanism that ACTUALLY RAN" "$(step_text 9)" 'The body names every review mechanism that ACTUALLY RAN, not only the receipt'
check_contains "core S3-2: step 9 — invoking /polish IS the authorization; the merge stays the operator's" "$(step_text 9)" 'Invoking `/polish` IS the authorization to push and open the PR; the merge stays the operator'
check_contains "core S3-2: step 10 reports the review depth with its exact mechanism" "$(step_text 10)" 'the review depth with its exact mechanism, never the depth alone'
pinfg "guide S3-2: step 5's (b) label — the target of the core's ultra pointer" '**(b) Stop for real** — `ultra`'

# --- K2 (slice 2): the spawn line and dir #413's needle ------------------------------------------------------
# Of the lines carrying `subagent_type: "general-purpose"`, at least one has the needle on it or on the
# line before. (The guide's (a) fallback and second opinion carry others — dir #413's to retire; this one is K2's.)
needle="step 5's review subagent"
spawn_ok="$(awk -v n="$needle" '
  index($0, "subagent_type: \"general-purpose\"") { if (index($0, n) || index(prev, n)) ok = 1 }
  { prev = $0 }
  END { print ok ? "yes" : "no" }' "$polish")"
check_eq "K2's spawn line carries the needle on it or the line before (dir #413 A7's exemption)" "yes" "$spawn_ok"

# B1: when ---------------------------------------------------------------------------------------
pinf "step 5: K2 is the first attempt for low|medium|high" \
  'the FIRST attempt is a review run by a fresh-context subagent (dir #670);'
pinf "step 5: max, ultra and skip keep their paths" \
  '`max`, `ultra` and `skip` keep their paths below, unchanged.'
pinf "step 5: the direct attempt is for max, and for low|medium|high after K2's fallbacks" \
  "for \`max\`, and when K2's fallbacks send you here, ATTEMPT \`Skill(code-review) <level>\` directly"

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
pinf "step 5: the two-way conformance mandate is defined in the core, not only in the guide" \
  "The two-way conformance mandate (step 5(a)'s): the diff must realize the ticket's done-criterion, and nothing in it may silently exceed or contradict it."
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
  'neither a findings list nor an explicit `0 findings` and its quoted line'
pinf "step 5: the void reply goes to the in-session attempt; an empty or error quote is void, (none) is clean only at low" \
  'go to the in-session attempt below. An empty or error quote is void, and so is `(none)` except at `low` with `0 findings`. Otherwise verify every finding live against the file'
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
  'refused there too → the guide'"'"'s (a) and (b)'
pinf "step 6: the receipt names both skip receipts (no-file-changes, --no-test)" \
  '`skipped:no-file-changes`/`skipped:--no-test`) — the outcome IS the sha'

# B7/B7a: disclosure and clause fates
pinf "step 5: the disclosure wording" \
  'name this mechanism as "`/code-review <level>` run by a fresh-context subagent"'
pinf "step 5: a bare level means a genuine pass run here or by K2's subagent" \
  "the bare \`polish.5-review <level>\` (a genuine \`/code-review\` pass, run here or by K2's subagent)"
pinf "step 6: a step-5 commit of pending work requires the retest" \
  'or committed pending work, and tests weren'"'"'t `--no-test`-skipped, re-run the test command once'
pinf "step 10: the summary names the subagent-run mechanism" \
  '`/code-review <level>` run by a fresh-context subagent, a genuine in-session'
# the guide keeps the pre-split step-5 text, with B7a's clause fates applied
pinfg "guide: a bare level now means a genuine pass run here in-session or by K2's subagent" \
  "(bare — a genuine \`/code-review\` pass, run here in-session or by K2's subagent)"
pinfg "guide: the receipt catalogue names the subagent-run pass" \
  "run by K2's review subagent, or operator-typed or revisit-triggered in-session"
pinfg "guide: agent:medium is the fallback outcome, not the ordinary one" \
  'the fallback outcome (K2'"'"'s fallbacks, then the direct attempt refused'
pinfg "guide: (d)'s mechanism list names the subagent-run pass" \
  'a `/code-review <level>` run by a fresh-context subagent (K2)'
pinfgn "guide: the retired 'bare — this IS the genuine in-session pass' wording is gone" \
  'bare — this IS the genuine in-session pass'
pinfgn "guide: the retired 'ordinary automated outcome' wording is gone" \
  'the ordinary automated outcome'

# --- dir #612: step 2 sizes by content class — a prose-only diff gets ONE inline pass, receipted by name ----
# guide_step N — the guide's `## Step N` section, line breaks and space runs collapsed (stops at the next `## `).
guide_step() { awk -v h="## Step $1 " 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$guide" | tr '\n' ' ' | tr -s ' '; }
c2="$(step_text 2)"
g2="$(guide_step 2)"
check_contains "core: step 2's trigger is an md-only diff with no command, skill or runbook, and loads the guide's § Step 2" \
  "$c2" 'Every changed file `*.md`, none a command, skill or runbook → the guide, § Step 2.'
check_contains "core: step 2 ends with the short refused-or-unavailable pointer" "$c2" 'Refused or unavailable → § Step 2.'
check_absent "core: step 2 does not repeat the guide-loading instruction" "$c2" "$instr"
check_absent "core: step 2 does not repeat the unreachable-guide clause" "$c2" 'nreachable'
check_contains "core: step 2 keeps the plain /simplify receipt" "$c2" '`tools/pre-pr-gate.sh receipt polish.2-simplify`'
check_absent "core: the no-simplify-skill receipt moved to the guide" "$c2" 'inline:no-simplify-skill'
check_contains "guide: § Step 2 names the prose-only class by its receipt" "$g2" '`tools/pre-pr-gate.sh receipt polish.2-simplify inline:prose-only`'
check_contains "guide: § Step 2's prose-only class needs no changed code file" "$g2" '(a) no changed file is code'
check_contains "guide: § Step 2's prose-only class needs no fenced block touched" "$g2" '(b) no fenced block is added, removed or edited'
check_contains "guide: § Step 2's prose-only class keeps procedure docs out" "$g2" '(c) no changed file is a procedure doc'
check_contains "guide: § Step 2 sends anything else, or any doubt, to the full /simplify" "$g2" 'Anything else, or any doubt, runs the full `/simplify`'
check_contains "guide: § Step 2 states the inline pass is one reuse/duplication pass" "$g2" 'ONE inline reuse/duplication pass'
check_contains "guide: § Step 2 keeps the unavailable-skill receipt" "$g2" 'inline:no-simplify-skill'

# --- dir #616: wait on CI in ONE backgrounded, bounded command — never a wakeup, a sleep chain or a short Monitor ----
check_contains "core: step 9 names the one backgrounded command and what never to use" "$(step_text 9)" \
  'Waiting on CI: ONE backgrounded `gh pr checks <n> --watch` with a timeout; never wakeups, sleeps or short Monitors.'
pinfg "guide: § Step 9 owns the CI-wait rule, bounded (dir #616)" '**Waiting on CI (dir #616).** If you wait on CI after the PR opens, wait in ONE backgrounded Bash command with a timeout or iteration cap'
pinfg "guide: § Step 9 forbids ScheduleWakeup for a background wait" 'Never ScheduleWakeup'
pinfg "guide: § Step 9 gives a harness with no completion notice a bounded foreground wait" 'A harness with no background-completion notice: one bounded foreground wait'

# --- dir #583: guide § Step 8 says a missing-receipt deny can be a sandbox visibility problem ----------------
pinfg "guide: § Step 8 names the sandbox visibility cause (dir #583)" '"No receipt is on file" can be a visibility problem, not a missing one (dir #583)'
pinfg "guide: § Step 8 states both key shapes side by side" 'the sentinel by repo AND branch, the review trace by repo only'
pinfg "guide: § Step 8 says every write is redone, not just the last command" 'not just the final `gh pr create`'

# --- dir #612 seam (found by dir #661's review): the unavailable-/simplify fallback is its OWN inline pass ----
# "the same ONE inline pass" read as the prose-only reuse pass, but the fallback runs on a diff that has code:
# it must cover the cleanup angles /simplify would, and say it is not the prose-only pass.
check_contains "guide: § Step 2's unavailable-skill fallback covers /simplify's own cleanup angles" "$g2" \
  'over the angles `/simplify` covers (duplication, dead code, over-complication, naming)'
check_contains "guide: § Step 2 says the fallback is not the prose-only pass" "$g2" 'not the prose-only pass above'

# dir #714: the fallback-within-a-fallback precondition names B4's agent-type-not-found case too.
pinfg "guide: 'Fallback within a fallback' precondition names the agent-type-not-found case" \
  'unavailable/refuses, or the Agent call answers that the type `keel-polish-reviewer` was not found'

# --- dir #736 (build A): the K2 subagent quotes the skill's first line after `Result:` -----------------------
# Each needle sits where it must live, so a clause moved elsewhere in the core cannot satisfy it.
kprompt="${flat#*'**Its prompt.**'}"
kprompt="${kprompt%%'```'*}"
check_contains "K2 prompt: the subagent writes 0 findings and quotes the skill's first line after Result:" "$kprompt" \
  "and write \`0 findings\` explicitly when there are none, quoting the skill's first line after \`Result:\`;"
kfall="${flat#*'**Fallbacks, in order.**'}"
kfall="${kfall%% - \*\**}"
check_contains "K2 fallbacks: a void quote takes the same route as a missing findings list" "$kfall" \
  "voided for a missing findings list or quote"

# --- dir #745 lines (build A): the intro names the push-bypass deny; the header comment is accurate ----------
pinf "core intro: the gate also denies a bypassed git push" 'and always `git push --no-verify`'
pinf "core header comment: unwired, only the gate's blocks are inert" 'only its blocks are inert'
check_absent "core header comment: the retired 'only the gh pr create block' wording is gone" "$flat" 'only the gh pr create block is inert'

# --- dir #711 (build A): the guide's preamble no longer claims "unchanged" or "the whole text of its step" ------
pinfgn "guide preamble: no 'whole text of its step' claim" 'whole text of its step'
gpre="$(sed -n 1,12p "$guide")"
check_absent "guide preamble: no 'unchanged' claim in its first lines" "$gpre" 'unchanged'
pinfg "guide preamble: amended in place since the split" 'carried over from the pre-split `polish.md` and amended in place since'
pinfg "guide preamble: the core can hold text the guide lacks" 'The core can also hold text this guide lacks'

# --- dir #711 (build A): docs and test headers carry no "unchanged" claim about the pre-split text --------------
check_count "docs/loading-and-cost.md no longer calls the pre-split polish.md 'unchanged'" \
  "$REPO_ROOT/docs/loading-and-cost.md" 'polish.md`, unchanged' 0
# The needle is split so this file's own line does not match it.
hdr_hits="$(grep -l 'unchanged, in commands/''polish-guide.md' "$REPO_ROOT"/tests/*.sh 2>/dev/null || true)"
check_eq "no test header says its pre-split text lives 'unchanged' in the guide" "" "$hdr_hits"
check_count "docs/release-audit.md names the guide as the growing open-FLOOR file" \
  "$REPO_ROOT/docs/release-audit.md" 'the guide is the one that grows' 1

summary
