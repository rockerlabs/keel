#!/usr/bin/env bash
# Pre-PR gate — the enforcement half of the /polish → PR flow.
#
# Ships to adopters (dir #68) — pairs with commands/polish.md, which install.sh installs unconditionally.
# This script itself is never auto-wired, though: it's a Claude-Code-specific hook, and a hook changes
# what a session can do without asking each time, so wiring it is a separate, explicit, opt-in step —
# tools/install-pre-pr-gate.sh <repo> (project scope, the default) or --global (every repo). Until that
# runs, /polish's steps still work; only the gh pr create block (below) is inert.
#
# Wired as a Claude Code PreToolUse(Bash) hook (tools/install-pre-pr-gate.sh does this for you): it
# intercepts `gh pr create` and requires /polish (simplify + independent review + tests) to have run on the
# current HEAD. The bypass path is closed by
# content, not just presence: each polish step appends a receipt line (see below), and the gate denies
# unless every expected step id is present AND the final step's recorded SHA matches live HEAD — so a
# bare `touch` (empty file), a partial run, or a sentinel from an earlier commit all fail.
# Unlock: run /polish — it writes the receipt automatically as it completes each step.
#
# --- receipt format (dir #49) ---------------------------------------------------------------------
# The sentinel is no longer a bare SHA — it's a small per-run receipt at the same path/keying:
#   nonce\t<run-id>                     (line 1, written by `init`)
#   <run-id>\t<step-id>\t<outcome>      (one per step, written by `receipt`, in any order)
# Only lines carrying the CURRENT run's nonce count — a leftover line from an earlier run (a different
# nonce) is invisible to the completeness check, so a stale receipt can't be replayed just because it
# happens to still list the right step ids. THREE outcomes are HEAD SHAs, not free text: `polish.3-tests`
# (dir #96), `polish.6-retest` (dir #72) and `polish.8-unlock` (dir #49). Step 8's presence doubles as
# both the last step id and the SHA effect-check — no separate finalize step needed — while steps 3 and 6
# are what actually tie a TEST RUN to the commit being shipped; see the dir #96 block further down.
#
# CLI subcommands (used by commands/polish.md, so a step never needs a raw `echo >>`):
#   pre-pr-gate.sh init                    mint a fresh nonce, start a new receipt (run from repo root)
#   pre-pr-gate.sh receipt <step-id> [outcome]   append a receipt line for the current run (outcome default: done)
#   pre-pr-gate.sh receipt --recover       re-stamp the immediately-prior (retired) run's step receipts
#                                           onto the current nonce — dir #72, the review-fix-commit
#                                           convergence shortcut (see commands/polish.md step 1's
#                                           convergence branch, and step 5's convergence rule)
#   pre-pr-gate.sh log <type> [detail]     append a line to the impact log (same resolution as the guard event)
#   pre-pr-gate.sh handoff <level> <sha>   record step 5(b)'s stop so a re-invocation doesn't re-ask (dir #63)
#   pre-pr-gate.sh handoff-check           print+exit 0 if a handoff matches current HEAD, else exit 1 (dir #63)
#   pre-pr-gate.sh skill-trace             hook subcommand (see dir #63 section below) — not run by hand
#   pre-pr-gate.sh rollout-check           SessionStart hook subcommand (dir #64 tier 1) — not run by hand
#   pre-pr-gate.sh sweep [K]               /wrap-time floor (dir #64 tier 2b): warn when the last K
#                                           polish runs closed without a verified (non-self-reported) review (default K=3)
#
# With no subcommand, it runs as the PreToolUse(Bash) hook: reads the tool-call JSON event on stdin,
# decides allow/deny for `gh pr create`.
#
# --- dir #63: making step 5's review outcome verifiable -------------------------------------------
# Hole A (a fabricated in-session review claim is unfalsifiable): `polish.5-review`'s receipt is a
# free-form string the model writes about itself, so a real in-session `/code-review <level>` pass and
# a session that only claims one are byte-identical. Fix: two ADDITIONAL hooks (same settings.json as
# the PreToolUse gate above — tools/install-pre-pr-gate.sh wires all six together) write a mechanical
# trace line to a HOOK-OWNED side channel the model isn't expected to touch — a materially higher bar
# than getting one self-report right, though not literally unfakeable (the model still has Bash; see the
# residual limit below):
#   "PostToolUse":         [{ "matcher": "Skill",       "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh skill-trace" }] }]
#   "UserPromptExpansion": [{ "matcher": "code-review", "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh skill-trace" }] }]
# The PostToolUse leg fires when Claude itself calls Skill(code-review) — PostToolUse only fires after
# a tool call SUCCEEDS (a refused/unavailable call never reaches it, so an unavailable-skill run leaves
# no trace by construction — see the residual limit below). The UserPromptExpansion leg fires when the
# OPERATOR types `/code-review <level>` directly, which bypasses PostToolUse entirely (confirmed against
# Claude Code's hooks reference: "a PreToolUse hook matching the Skill tool fires only when Claude calls
# the tool, but typing /skillname directly bypasses PreToolUse" — PostToolUse matches the same tool-name
# set). Both write the same trace line via `skill-trace`, keyed like the sentinel (main_top_for), to
# /tmp/pre-pr-gate-trace-<repo>: "<HEAD-sha>\t<level-if-known>".
# **TO VERIFY, resolved 2026-07-28** (dir #68 flagged skill-trace's field-name assumptions as
# unverified, unlike rollout-check's own TO-VERIFY block below — checked against the same source,
# code.claude.com/docs/en/hooks.md):
# (1) `UserPromptExpansion` IS a real, documented hook event ("runs when a user-typed command expands
#     into a prompt before reaching Claude" — exactly the operator-typed-`/code-review` path this leg
#     exists to catch), and its input carries `hook_event_name`, `expansion_type`, `command_name`,
#     `command_args`, `command_source`, and `prompt` — CONFIRMED against the doc's own literal example:
#     `{"hook_event_name":"UserPromptExpansion","expansion_type":"slash_command",
#     "command_name":"example-skill","command_args":"arg1 arg2","command_source":"plugin",
#     "prompt":"/example-skill arg1 arg2"}`. `command_name` is the BARE skill name (no leading `/`),
#     matching the `st_skill` case pattern below (`code-review|*:code-review|/code-review` covers it).
# (2) `.tool_input.skill` / `.tool_input.args` for a PostToolUse(Skill) event has no dedicated worked
#     example in the docs (unlike Bash/Write/Edit/Agent/etc., which each get one) — the docs only give
#     the general rule that `tool_input` is "the arguments sent to the tool" and "the exact schema...
#     depends on the tool." PLAUSIBLE at high confidence, not literally doc-confirmed: every documented
#     tool's `tool_input` mirrors its own call-parameter names 1:1 (Agent -> `prompt`/`subagent_type`/
#     `model`; Write -> `file_path`/`content`), and the Skill tool's own declared parameters are named
#     exactly `skill` and `args` — so the same convention should apply. A live sandboxed
#     PostToolUse(Skill) capture would close this the rest of the way but was not run this pass (the
#     operator declined the throwaway-sandbox probe that would have produced one).
# The gate's PASS branch (hook mode, below) cross-checks this trace whenever `polish.5-review`'s
# outcome is a BARE level (no `-operator-run`/`-waived` suffix, not `skip`) — that shape claims a real
# in-session run, so it must have left a trace for the SAME sha AND the SAME level, or the gate denies
# (an honest `/code-review low` pass must not be able to vouch for a receipt claiming `max`). Separately,
# EVERY outcome shape — including the trusted `skip`/`-operator-run`/`-waived` ones, which need no trace
# — is cross-checked against `polish.4-depth`'s own recorded level: without this, a session could size
# the diff `medium` and then simply write `polish.5-review skip`, since `skip` was trusted unconditionally.
# **Residual limits** (write these into any doc referencing the mechanism):
# (1) the unavailable→inline-pass hand-off (commands/polish.md step 5(a)/(b)/(c)) leaves no trace by
#     construction — its outcome (`-operator-run`/`-waived`) stays self-reported; the trace only makes
#     ONE dishonesty channel checkable — "claims the skill ran when it didn't" — not the inline pass's
#     own thoroughness.
# (2) the trace records `git -C <event-cwd> rev-parse HEAD` at invocation time — if the session's
#     harness-tracked cwd for the Skill/slash-command event is a DIFFERENT checkout than the one the
#     eventual `gh pr create --head <branch>` targets (the split main-checkout/worktree pattern dir #61
#     hardened for the sentinel and gate-side SHA check), the trace can be keyed to the wrong commit —
#     a genuine review then false-denies rather than false-passing. Not fixable at trace-write time (the
#     eventual `--head` isn't known yet); same accepted trade-off as (3).
# (3) the hand-off file is repo-scoped like the sentinel, so two worktrees of the SAME repo mid-`/polish`
#     at the same time share one hand-off (and, if they land on the identical commit before either has
#     diverged, could overwrite each other's note) — an existing limitation of the sentinel's own
#     per-repo (not per-worktree) keying, not a new one this ticket introduces.
#
# Hole B (the hand-off's only exit depended on session memory): step 5(c) used to exit only when "the
# session already shows they ran it" — gone after a compaction or a fresh session on the same branch, so
# a re-invocation would defer forever (`init` mints a fresh nonce by design, wiping the receipt sentinel,
# dir #49's replay fix). Fix: `handoff` writes `polish.5\t<level>\t<HEAD-sha>` to its OWN file
# (`handoff_path()`, keyed like the sentinel) at step 5(b) stop time — a separate file, not a line folded
# into the sentinel, so `init`'s nonce reset never has to know it exists: it survives by construction,
# not by a special case. `receipt polish.5-review <outcome>` removes it once the real receipt lands.
# `handoff-check` on a re-invocation tells step 5(c) whether the question was already asked for this
# EXACT diff (same HEAD SHA) — a match means collect the answer without re-deferring; any new commit
# invalidates the match (same-SHA-only replay window, not open-ended).
#
# --- dir #64: a model/harness rollout must not break the pipeline silently ------------------------
# Generalizes dir #63's root cause: the Opus 5 rollout silently removed /code-review's model-invokability
# and nothing warned — the only way to learn it was reading a transcript. Three tiers, each independent:
#
# Tier 1 — rollout-check (this file, SessionStart hook, below). Wire as:
#   "SessionStart": [{ "matcher": "startup", "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh rollout-check" }] }]
# Records the session's `.model` (from the SessionStart hook JSON) + `claude --version` into a per-repo
# state file; on either changing since the last recorded session, appends a `pipeline-drift` impact-log
# event and emits a `systemMessage` banner. First-ever run for a repo just records a baseline (nothing to
# compare against yet) — never a false warning.
# **TO VERIFY, resolved 2026-07-27:** (1) the SessionStart hook JSON DOES carry a `model` field (per
# code.claude.com/docs/en/hooks.md) — may be omitted after `/clear`/recovery, handled as "nothing to
# compare" rather than "changed". (2) plain stdout from a SessionStart hook is NOT shown to the human
# operator — the docs are explicit that for SessionStart (like UserPromptSubmit/UserPromptExpansion),
# stdout is "added as context that Claude can see and act on", i.e. model-visible only. The
# human-visible channel is the separate `systemMessage` JSON field, which is what `rollout-check` uses.
#
# Tier 2 — provenance surfacing (this file, PASS branch + `sweep` subcommand, below).
#   (a) the gate's ALLOW decision now carries a `systemMessage`/`permissionDecisionReason` naming how
#       step 5's review was actually established — "review: skip", "review: <level>, trace-confirmed
#       in-session" (dir #63's mechanical trace matched), or "review: <level>, operator-run
#       (self-reported)" / "review: <level>, waived (self-reported)" for the hand-off outcomes dir #63
#       never traces. Visible at PR-creation time instead of only via transcript archaeology.
#   (b) `sweep [K]` reads the impact log's `receipt-pass` rows (now carrying that same classification as
#       their detail field) and warns when the last K (default 3) consecutive passes never carried any
#       tag other than the self-reported one — any independently verified tag counts (currently
#       "trace-confirmed" and dir #70's "agent-confirmed"; a future third one is covered automatically,
#       since the check is negative, not an enumeration) — a run of self-reported-only reviews, the
#       exact pre-#63 blind spot. Read-only, never blocks; wiring it into a `/wrap` step is a manual
#       follow-up (same precedent as dir #63's hook wiring into settings.json — see that section above).
#
# Tier 3 — tools/pipeline-canary.sh (separate file). A sandboxed operator ritual that builds a toy repo +
# isolated HOME + stubbed `gh` + this file's hooks wired in, then either drives a real `/polish` run
# (operator-triggered) or seeds a fabricated step-5 claim and asserts the gate still denies it (fully
# scripted, no model needed — the canary's own proof that it CAN fail). Full design + the TO VERIFY
# outcome on headless hook-firing → that file's own header.
#
# --- dir #70: an independent SUBAGENT review when Skill(code-review) itself refuses --------------
# Root cause at the time this was built: `/code-review` shipped `disable-model-invocation: true`, so a
# session could never call it on its own — every unavailable-case /polish run used to fall back to a
# same-context inline pass (the author reviewing itself) standing in for a real review. **Superseded by
# dir #254 — see commands/polish.md step 5's own intro for the why/when.** Everything below in this
# section is reached only as the FALLBACK when a direct `Skill(code-review)` attempt is refused for a
# given run, not as the standing default. commands/polish.md step 5(a) spawns ONE
# independent Agent-tool subagent (type `general-purpose`, fresh context — no memory of the code-writing
# session) to do the review instead; this file's job is making THAT claim verifiable too, the same way
# dir #63 made a real in-session `/code-review` call verifiable.
#
# **TO VERIFY, resolved at impl start (corrects the ticket's own original assumption):** the ticket
# guessed a `PostToolUse` hook matched on a "Task"/"Agent" tool name, mirroring the Skill leg above.
# Checked against code.claude.com/docs/en/hooks.md: no such tool-call hook exists for subagent spawning.
# `TaskCreate`/`TaskCreated`/`TaskCompleted` are a DIFFERENT feature (the background-task queue, unrelated
# to subagent review). The real, documented mechanism is a pair of DEDICATED lifecycle events,
# `SubagentStart`/`SubagentStop`, matched on `agent_type` (not `tool_name`) — `general-purpose` is one of
# the built-in values. `SubagentStop` additionally carries `last_assistant_message`: "the final assistant
# text from the subagent's conversation." That is the ONLY place this hook can read the review's outcome
# — unlike PostToolUse(Skill), a subagent event has no `tool_input`/`prompt` field to read a call argument
# from — so the marker commands/polish.md's step 5(a) prompt requires (`KEEL-AGENT-REVIEW: level=<level>`,
# alone on a line) must appear in the subagent's own returned text, not in its invocation.
#
# The sha is this hook's OWN `git … rev-parse HEAD` at fire time (never a self-reported field) — same
# trust boundary as every other leg's own sha resolution below (all three now share `_append_trace_line`,
# dir #88's own extraction); a self-reported sha would let a stale review vouch for a later commit. Trace
# line: `<sha>\tagent:<level>` (same file, same tab format as
# the Skill/UserPromptExpansion legs, distinguished only by the `agent:` prefix on the level field) — the
# gate's PASS branch (below) matches `$review_outcome` against it VERBATIM, so `polish.5-review`'s outcome
# must be written as the same literal string (`agent:<level>`), not just the bare level.
#
# **Residual limits (write these into any doc referencing the mechanism, same discipline as dir #63):**
# (1) the marker lives in the subagent's OWN model-authored response — a materially higher bar than a
# bare self-report (it requires a real, separate-context `SubagentStop` event to fire for the claimed
# agent_type), but not literally unfakeable: a trivial, no-op subagent call that merely echoes the marker
# line would still satisfy this leg. The depth-consistency check (dir #63's cross-check against
# `polish.4-depth`'s own recorded level, unchanged and reused as-is below) is the compensating control —
# it doesn't inspect the review's substance, but a fabricated marker still can't claim a DIFFERENT level
# than what step 4 sized, narrowing the fabrication to "ran a real subagent and lied about doing the work,
# at the correct level" rather than "claimed anything at all."
# (2) the match itself is looser than the Skill/UserPromptExpansion legs': those require a SPECIFIC
# structured field (`tool_input.skill == "code-review"`), so only an actual code-review invocation can
# leave a trace. This leg matches on `agent_type == "general-purpose"` — the platform's default/catch-all
# subagent type, used for arbitrary unrelated work in the SAME gated session, not only /polish's own
# spawn — plus a free-text regex over that subagent's prose. ANY general-purpose subagent whose final
# message happens to contain a line matching the marker exactly (an unrelated subagent asked to quote or
# explain this very mechanism, say) writes a trace line for the CURRENT commit, even though it reviewed
# nothing. Found in the operator-run /code-review high pass on this ticket. Not a new SECURITY hole (a
# dishonest model already has Bash and could write the trace file directly, the same residual (1)
# describes) — but it IS a real ACCIDENTAL-collision surface an honest session could hit by coincidence.
# No structural fix exists today (no more-restricted, adopter-available subagent type ties an event back
# to /polish's own spawn specifically) — named here so it isn't silently assumed away.
# (3) dir #85 (rails audit M2-6): commands/polish.md step 5(a) mandates that the subagent prompt carry
# the ticket/spec the diff implements, with a two-way conformance mandate (dir #78). NOTHING here can
# check that. A `SubagentStop` event carries no prompt/call-argument field (same absence residual (1)
# is built around), so the spec hand-off is verifiable only by the subagent's own prose — i.e. it is
# not verified at all. The prose sits one line away from claims that ARE trace-backed, so it reads as
# gated when it is not; recorded here rather than reworded, because the mandate is worth keeping even
# unenforced. Mechanization candidate, not a defect in this file.
#
# `sweep` (dir #64 tier 2b, below) counts an `agent:`-confirmed pass the same as a `trace-confirmed` one —
# both are independently-verifiable reviews, the pre-#63 blind spot `sweep` exists to catch is
# self-reported-only runs, and this leg is not one of those. Its streak check tests `!= "self-reported"`
# rather than enumerating each verified tag by name, so this leg didn't need to touch that logic at all.
#
# --- dir #72: the review gate has no convergence rule for a review-fix commit -----------------------
# Felt three times in one run (dir #69/PR #145): a real step-5 finding gets fixed and committed, which
# moves HEAD — but dir #70's SubagentStop trace and dir #63's SHA check are both keyed to HEAD at fire
# time, so the run that was just receipted no longer satisfies the gate, and `init` (run again at step 1
# of the next /polish invocation) mints a fresh nonce that discards ALL eight step receipts, not just the
# one (step 5) that actually needs redoing. Two ADDITIONAL fixes, both small and additive — nothing above
# this section changes:
#   (a) commands/polish.md step 5 now states the convergence rule in prose: fold a review fix into the
#       same commit where practical, then re-review the DELTA only and stop once a pass needs no further
#       changes — a fix-commit moving HEAD is expected, not a "loop back to step 4" violation. Step 1
#       gained its own convergence branch that calls `receipt --recover` (below) right after `init` and
#       explicitly skips steps 2/4/7 for the rest of that run — recovering at step 5 instead (the first
#       draft's placement) would let stale values silently overwrite this round's genuinely fresh ones,
#       found by an independent review during this same ticket's own /polish pass.
#   (b) `receipt --recover` (this file) makes re-receipting the UNCHANGED steps (1, 2, 4, 7) after that
#       commit cost one command instead of eight manual `receipt <step-id> <outcome>` calls. dir #96
#       moved step 3 OUT of that set: its outcome is now the sha the tests ran at, so after a fix commit
#       the recovered value is stale by construction and either the tests re-run or step 6 binds the new
#       HEAD (see the dir #123 update below for how step 3 recovery works today). It reads
#       from a single-slot backup (`_prev_sentinel_path_for_key()`) that `retire_sentinel()` now writes at every
#       point that used to just `rm -f`/overwrite the live sentinel (every gate-deny branch, the PASS
#       branch's own post-unlock cleanup, and `init`'s overwrite) — so whichever run was just retired,
#       for whatever reason, is the one `--recover` restores. Only one slot: this is a convenience for the
#       common one-fix-commit case, not a receipt history. dir #96 made the filtering EXPLICIT rather
#       than relying on a later write to supersede a recovered line: at the time dir #96 shipped,
#       `polish.3-tests` and `polish.5-review` were both never restored (their trusted arms — a sha that
#       still matches, a `skip`/`-operator-run`/`-waived` outcome — would otherwise vouch for a commit
#       they never saw). dir #123 later lifted the step-3 exclusion (see the `receipt --recover`
#       implementation below): it now recovers like any other step, since its stamped tree-relevant hash
#       lets the read-time check mechanically tell a stale recovery from a still-good one. Recovery never
#       overwrites a step id THIS run already receipted, so the order of `--recover` against your own
#       receipt calls does not matter. The steps a convergence round must ALWAYS write itself are 5, 6
#       and 8 (3 usually recovers now too). The gate's
#       completeness/sha/trace checks are entirely unchanged: a recovered-but-stale step-8 sha still
#       denies exactly as before — `--recover` only removes the busywork of re-typing what didn't
#       change.
#
# --- dir #80: the sentinel is a single /tmp file shared by ALL worktrees of a repo -------------------
# dir #61 deliberately keyed the sentinel off the repo's MAIN checkout (main_top_for -> basename), not
# the raw event cwd, so a receipt written from worktree A and a `gh pr create` hook event reporting
# worktree B still agree on one file. Correct for THAT problem, but with heavy concurrent activity on
# the SAME repo (many worktrees active at once), the one shared sentinel becomes a single race point: a
# different session's own `init` (or a denied `gh pr create`'s retire_sentinel()) can wipe the file
# between one session's receipt-writes and its own `gh pr create` call. Fix: key the sentinel,
# prev-sentinel, and hand-off note by (repo, branch) instead of repo alone — `_require_receipt_key`
# (below) resolves the invoking cwd's own current branch and hands it, with `_repo_key`, to
# `_receipt_key_for`, which owns the key FORMAT for every writer site. Two worktrees of the same repo
# on DIFFERENT branches now get separate slots;
# two sessions on the SAME branch of the same repo still share one (arguably correct-to-deny — accepted
# and documented in commands/polish.md's receipt-deny paragraph as a manual-fallback last resort, not
# fixed here). NOT re-keyed: `trace_path_for` (append-only, matched by sha+level scan — concurrent
# branches already interleave harmlessly) and `rollout_state_path` (genuinely per-repo, not per-run).
# `_require_receipt_key` hard-errors on a detached HEAD (empty branch slug) — /polish never legitimately
# runs detached (core rails), so err loud rather than key onto an empty string. Hook-side resolution
# (hook mode, below) additionally tries an explicit `--head`/`-f head=` before falling back to the event
# cwd's own branch, and DENIES (rather than crashing) when neither resolves — a workflow gate must
# always emit a JSON decision, never die mid-hook.
#
# Related, not a duplicate: dir #82 (the keel-impact.sh event log's own concurrent-write race). Same
# root-cause CLASS (shared, unlocked /tmp or .keel/ state, raced by concurrent worktree sessions on one
# repo) hitting a different file with different semantics — this ticket's sentinel is a single-slot
# completeness receipt (fixed by keying); dir #82's log is an append-only queue (fixed by a subtractive
# rewrite). No shared mechanism; each keeps its own fix.
# --- dir #88: gate-checking step 5(a)'s MANDATORY review-reminder dialog ---------------------------
# Root cause: the MANDATORY `AskUserQuestion` reminder in commands/polish.md step 5(a) ("agent review
# already ran — additionally run the stronger built-in /code-review <level>?") was silently skipped 3x
# (felt on dir #62/PR #147) — prose alone doesn't stop a session from writing the `agent:<level>`
# receipt and moving straight to step 6. Same fix class as dir #63/#70: a THIRD trace leg, not a
# hand-off check (the hand-off note is CLEARED before the gate ever runs — see step 5's own `receipt`
# case above — so "hand-off present at gate time" would deny the honest flow, and "absent" is
# indistinguishable from "dialog never opened").
#   "PostToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "bash <checkout>/tools/pre-pr-gate.sh skill-trace" }] }]
# PostToolUse fires only after the tool call SUCCEEDS — for AskUserQuestion that means the operator
# ANSWERED it (any answer, including "Other", and per Claude Code's own docs on the tool's auto-continue
# timeout, an unattended timeout also SUBMITS whatever was selected and counts as a completed call, not
# a failure). That resolves the same fork dir #63/#70 already resolved for their own legs: the traced
# event is "dialog opened AND answered", so it can never wedge an in-flight session (an unanswered
# dialog means the flow is still sitting at it and hasn't reached `gh pr create` yet), and a session that
# abandons the dialog and pushes on leaves no trace and denies right here — exactly the skip this ticket
# closes.
# **TO VERIFY, resolved at impl start** (same drill as dir #63/#70, checked against
# code.claude.com/docs/en/hooks.md and .../tools-reference.md): (1) `AskUserQuestion` is confirmed as the
# tool's exact `tool_name` string (tools-reference.md's own tool table lists it verbatim). (2) Neither
# doc page gives a worked PostToolUse(AskUserQuestion) JSON example, so the exact field the question text
# lands in (`tool_input` vs `tool_response`) is PLAUSIBLE, not doc-confirmed — same unresolved-schema
# shape as dir #63's own point (2). Mitigated the same way design pt 3 below does it: `skill-trace` greps
# the RAW event JSON for the marker rather than reading a named field, so the exact field name is not
# load-bearing. (3) No documented cancel/interrupt path exists for `AskUserQuestion` separate from
# "answered" or "timed out" (which itself submits) — nothing here currently distinguishes a hypothetical
# future interrupt path from an ordinary miss, and none is assumed.
#
# **Marker** — the dialog's question text must carry, verbatim, the literal line
# `KEEL-REVIEW-DIALOG: level=<level>` (same literal-match discipline as `KEEL-AGENT-REVIEW` above, same
# reason: this hook greps for it, not the human-facing wording, which must stay free to change — dir #64's
# tag-vs-prose lesson). Below, `skill-trace`'s new branch greps `$st_input` (the RAW event JSON, not a
# parsed field — see TO VERIFY (2) above) for `KEEL-REVIEW-DIALOG: level=<word>`, takes the LAST match,
# then validates the captured word against `$ACCEPTED_REVIEW_LEVELS` exactly (not embedded in the regex
# itself — found in the operator-run /code-review high pass: an in-regex alternation lets grep's
# leftmost-longest match truncate a malformed `level=highest` down to a false-accepted `high`), and
# appends `<sha>\tdialog:<level>` to the same trace file the Skill/UserPromptExpansion/
# SubagentStop legs already write (`trace_path_for`) — sha is this hook's OWN `git … rev-parse HEAD` at
# fire time, never a self-reported field, same trust boundary as every other leg. No marker / no sha →
# silent exit 0, same as the other legs.
#
# **Gate check** — in the PASS branch, immediately after the existing review-trace check: whenever
# `$review_outcome` matches `agent:*` (bare `agent:<level>`, or with any add-on set —
# `agent:<level>+<addon>[,<addon>…]`, dir #158's single arm; the dialog reminder fires identically for
# every one of them), additionally
# require a `dialog:<outcome_level>` line for `$current_sha` in the trace file; else deny naming the
# dialog as missing. Per-SHA by construction (dir #72's convergence-round fork): a fix-commit moves HEAD,
# so an earlier round's dialog line doesn't cover a later commit — a fresh answered dialog is required
# per round, matching the MANDATORY paragraph's own "each such round moves HEAD" prose. Applies to
# `agent:*`-shaped outcomes and — since dir #116 — to `skip`, whose required dialog is a DIFFERENT one
# (step 4's mandatory skip dialog, its own `KEEL-DEPTH-DIALOG` skip marker — a distinct token, so
# a sizing dialog can never pre-satisfy this reminder check — and its own deny message):
# skip bypasses step 5 outright, so the sizing dialog that chose it is the only dialog there is.
# Unaffected: bare `<level>` (a genuine in-session /code-review run — step 5(a)'s reminder doesn't
# exist on that path), `<level>-operator-run`/`<level>-waived` (the (b)/(c) hand-off outcomes, already
# self-reported and covered by the depth-consistency check above), and `ultra` (never reaches (a) at
# all).
#
# **Arming rule (part of the spec, not optional):** the check above only fires when the AskUserQuestion
# leg is actually WIRED — `_dialog_leg_armed` (below) greps the resolvable settings.json candidates
# (project `.claude/settings.json`/`.claude/settings.local.json`, main-checkout-resolved per dir #61,
# `~/.claude/settings.json`, and `${KEEL_HOME:-~/.claude}/settings.json` — four static paths, dir #137 —
# PLUS one dynamic candidate per home the checkout-side install ledger has verified still carries a gate
# manifest, dir #125/B2, see `_gate_ledger_candidates` below) for a `PostToolUse` entry whose matcher is
# `AskUserQuestion` and whose hook command names this script. Two
# rejected alternatives, same reasoning as dir #63/#70's own residual-limit
# sections: (i) fail closed unconditionally — the gate CHECK ships in this file and goes live the instant
# an adopter `git pull`s, but the TRACE leg needs a SEPARATE, explicit `tools/install-pre-pr-gate.sh`
# re-run (dir #68's opt-in-wiring discipline) — an unconditional check would false-deny every `agent:*`
# unlock in that window, open-ended for anyone who never re-runs the installer. (ii) arm once the trace
# file contains any `dialog:` line — a flow that always skips the dialog would then never arm the check
# at all, making it a permanent no-op, the exact failure mode this ticket exists to close.
#
# **Residual limits** (same discipline as dir #63/#70's own sections): (1) marker fabrication — any
# `AskUserQuestion` whose text contains the marker traces, even an unrelated one, but uniquely among the
# trace legs the faked artifact is ITSELF operator-visible (every dialog renders to the human), so the
# silent-skip failure mode this ticket closes stays structurally closed even under fabrication; a
# dishonest model with Bash could anyway write the trace file directly (the standing residual every leg
# shares). (2) sha keyed to the event cwd, not the eventual `--head` — same split-checkout false-deny
# trade-off as dir #63 limit (2). (3) per-repo trace file shared across worktrees — same as dir #63 limit
# (3). (4) the arming grep is a structural presence check, not a liveness check — a matcher wired to a
# STALE copy of this script (the felt incident that keeps `install-pre-pr-gate.sh` pointing at a kept
# checkout by absolute path, never a copy) would still read as armed. Since dir #125/B2 this ALSO covers
# the ledger-derived candidates, in a STRICTLY WIDER way than the four static ones: a home the
# checkout-side ledger (`<checkout>/.keel/installed-homes`) lists is trusted once its gate manifest is
# present and version-1, never re-verified against the harness's actual loaded hooks — AND, unlike the
# four static candidates (each scoped to THIS invocation's own `$top`/`$HOME`/`$KEEL_HOME`), a ledger
# candidate is never scoped to the current session's environment at all: any `--home DIR` install ever
# recorded anywhere on the machine arms every later `gh pr create` in every repo, whether or not that
# session's own harness has anything to do with the recorded home (flagged by this ticket's own
# operator-run/independent review passes). Deliberately not narrowed to intersect the ledger against
# `$HOME`/`$KEEL_HOME`: the same "erring toward deny" reasoning the KEEL_HOME residual above already
# accepts applies with equal force here — a false ARM degrades to the documented manual-terminal escape,
# while narrowing scope risks recreating exactly the false-UNARMED silent skip this ticket exists to
# close, for a `--home DIR` whose relationship to the current session isn't reliably determinable from
# env vars alone (that's the whole reason B2 needed the ledger instead of another env-var guess). (5)
# dir #63/#70's OWN trace-required
# checks (the `trusted==0` block above, unchanged by this ticket) have no equivalent arming guard — an
# adopter who `git pull`s past dir #63/#70 without re-running `tools/install-pre-pr-gate.sh` hits the same
# false-deny window this ticket's arming rule exists to close, just unguarded. Found auditing this ticket
# (altitude review) but deliberately NOT retrofitted here — those checks and their own test coverage
# predate this ticket and are out of its scope; named so it isn't silently assumed away, a candidate for
# its own follow-up ticket if ever felt in practice.

set -u

_ppg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/nonneg-int.sh
. "$_ppg_dir/lib/nonneg-int.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$_ppg_dir/lib/impact-store.sh"
unset _ppg_dir

EXPECTED_STEPS="polish.1-diff polish.2-simplify polish.3-tests polish.4-depth polish.5-review polish.6-retest polish.7-selfcheck polish.8-unlock"
# dir #149: the single membership test every raw write into the sentinel routes through — both
# `receipt`'s own append and `receipt --recover`'s replay of a retired sentinel's lines (search their
# call sites below). A literal `for`-loop + `=` compare, same idiom as $ACCEPTED_REVIEW_LEVELS's own
# membership checks just below — NOT a `case " $EXPECTED_STEPS " in *" $step_id "*)` glob-substring
# test, which an earlier draft of this used and which a fresh review caught as unsound in isolation: two
# space-adjacent EXPECTED_STEPS entries joined into one string (`"polish.1-diff polish.2-simplify"`)
# match that pattern as a substring, even though no single legal step id contains a space. Literal `=`
# comparison has no such spanning failure mode — a whitespace-bearing candidate simply never equals any
# single-word entry — so this one helper structurally closes the membership check even for a
# whitespace-carrying candidate; both call sites keep dir #144's own whitespace-specific guard ahead of
# this call anyway, purely for that guard's own friendlier, more specific error message.
_expected_step() {
  local want="$1" s
  for s in $EXPECTED_STEPS; do
    [ "$s" = "$want" ] && return 0
  done
  return 1
}

# dir #88 (found in the operator-run /code-review high pass on this ticket): the accepted review-depth
# levels used to be hardcoded independently in the SubagentStop and AskUserQuestion marker-parsing
# branches below — one shared source avoids a future tier addition/rename updating one and silently
# leaving the other rejecting it. Space-separated (a case PATTERN LIST needs its `|` separators literal
# in the script SOURCE — an unquoted `|`-joined variable expansion is matched as one literal string, not
# split into alternatives at runtime; confirmed the hard way before shipping this). The regex use below
# derives its own `|`-joined form from this via `${ACCEPTED_REVIEW_LEVELS// /|}`; the case-match use below
# loops over the space-separated words instead. `ultra` deliberately excluded: it never reaches either
# marker path (see commands/polish.md step 5).
ACCEPTED_REVIEW_LEVELS='low medium high max'
# dir #158: the review ADD-ONS a step-5 outcome may name on top of a standing agent review, as a set:
# `agent:<level>+<addon>[,<addon>…]`. Was two hardcoded literals (`+operator-run`, dir #81;
# `+second-opinion`, dir #141), one per `case` arm, with step 5 holding one value — so a commit that
# genuinely got BOTH (felt on dir #155: the operator ran `/code-review high`, then a cross-model second
# opinion in a later round) had to drop one from the record whichever literal was written. Adding a
# literal per combination grows the arm list combinatorially; one set parse handles every future add-on
# with no new arm.
#
# **This function IS the allowlist — deliberately not a separate `ACCEPTED_REVIEW_ADDONS` list.** A
# first draft had both, and shellcheck caught the list as unused: validation ran through this `case`
# while the list only documented it, i.e. two sources of truth for one fact, kept in step by nothing —
# the exact sync-comment smell `FRAMEWORK.md`'s contract-first section (dir #128) names, and the same
# class as the still-open dir #147/#148. So an add-on is accepted **iff** it is describable here: a new
# one cannot be silently allowed without also being given prose, and its unknown-token deny path
# (below) needs no second list to stay consistent with.
#
# Every add-on is "(self-reported)": the SubagentStop trace proves SOME general-purpose subagent wrote
# the marker for this commit+level, but can neither count runs nor identify a model tier. Only the
# STANDING agent review is trace-confirmed; see the `agent:*+*` arm below.
_addon_label() {
  case "$1" in
    operator-run)    printf 'operator-run /code-review (self-reported)' ;;
    # Longer parenthetical than operator-run's on purpose, and pinned by tests/test_pre_pr_gate.sh: for
    # a human pass "self-reported" is self-explanatory, but here a reader can reasonably assume the
    # trace covers it, since a subagent genuinely did run. Naming the limit is what stops the label
    # reading as a confirmation it isn't (found by an operator-run /code-review pass on dir #141).
    second-opinion)  printf 'in-session cross-model second opinion (self-reported — the trace can'"'"'t distinguish one subagent run from two)' ;;
    *)               return 1 ;;
  esac
}

# dir #161 /code-review high: the "no word-split, no glob" comma-walk shared by BOTH consumers of a
# `<something>+<addon>[,<addon>...]` suffix — the gate's own unlock-time `agent:*+*` validation arm
# (below) and `_normalize_addon_set` (below). $1 = the raw text after the `+`. Prints one element per
# line, EMPTY ELEMENTS INCLUDED (as empty lines) — do not add a `[ -n "$a" ]` filter here. The unlock
# arm depends on seeing an empty element (`agent:<level>+,` or a trailing `,`) so it can feed it to
# `_addon_label`, which denies on empty — that is the mechanism dir #158's own tests (50m) pin as
# proving "at least one mechanism was actually named"; dropping empties in this shared splitter would
# silently reopen that hole. `_normalize_addon_set` filters empties itself, on the caller side, since it
# has no such validation to protect. An entirely empty suffix ($1="") emits nothing at all — the
# `[ -n "$rest" ]` loop guard runs zero iterations there — matching the unlock arm's own prior special
# case for a bare `agent:<level>+` (its own now-inherited `$addon_prose`-empty check still catches that).
_split_comma_set() {
  local rest="$1" a
  while [ -n "$rest" ]; do
    a="${rest%%,*}"
    if [ "$rest" = "$a" ]; then rest=""; else rest="${rest#*,}"; fi
    printf '%s\n' "$a"
  done
}

# dir #161: the add-on SET a `polish.5-review` outcome carries, as one token per line (never printed —
# consumed by `_warn_dropped_addons` below). Branches on the `agent:` prefix first, then the dash forms,
# per the ticket's normalization table: only `agent:<level>+<a>[,<b>...]` carries a non-empty set — every
# other recognized shape (bare `agent:<level>`, `*-waived`, `skip`) is a review with no separately-named
# mechanism, and `*-operator-run` names exactly one (`operator-run`). An unrecognized shape falls through
# to the empty set: this function must never manufacture a warn by guessing at a shape it doesn't know.
# Deliberately NOT validated against `_addon_label` here — that happens once, in `_warn_dropped_addons`,
# against the PRIOR set only (see its own comment for why: this function's job is only to read what was
# written, not to judge it).
_normalize_addon_set() {
  local outcome="$1" rest a
  case "$outcome" in
    agent:*+*)
      # `_split_comma_set` (above) yields empty elements too — this caller drops them itself, since it
      # has no validation to protect (unlike the unlock arm, which needs to SEE an empty element to
      # deny it via `_addon_label`).
      rest="${outcome#agent:}"
      rest="${rest#*+}"
      while IFS= read -r a; do
        [ -n "$a" ] && printf '%s\n' "$a"
      done < <(_split_comma_set "$rest")
      ;;
    *-operator-run)   printf '%s\n' operator-run ;;
    # Every other recognized shape (bare `agent:<level>`, `*-waived`, `skip`), and any unrecognized
    # shape, falls through with no output — bash's own `case` already no-ops on no match, so there is
    # no need for an explicit catch-all arm here (verified: a `case` with zero matching patterns exits
    # 0 with nothing printed; simplify pass, dir #161's own /code-review high).
  esac
}

# dir #161: advisory-only check, called from the ordinary `receipt polish.5-review <outcome>` write path
# AFTER the line has already been appended — this never affects the write itself (same appended line,
# same exit 0). Warns on stderr when the immediately-prior round (the single-slot prev-sentinel backup)
# named a review add-on this round's outcome does not carry, so a re-typed-from-memory receipt (the dir
# #155 incident) is noticed at the exact moment the omission is made rather than never. See the ticket
# (dir #161) for why this fires here and not in `--recover` or the gate's PASS branch, and why it fails
# SILENT (opposite direction from `--recover`'s fail-closed) on every unverifiable condition: this grants
# no trust, so an unverifiable prior must never manufacture a warn.
# **Best-effort, not a guarantee (cross-model second-opinion review, dir #161):** the single-slot prev
# backup only ever holds the MOST RECENT retirement. If an intermediate round is retired without ever
# writing a `polish.5-review` receipt (a gate deny at an earlier step, or two `init`s in a row with no
# review write between them), that round's own prior add-on memory is silently gone from the chain —
# correctly fail-silent per the rule above, but it means a real drop from two-or-more rounds back can
# go unnoticed. A nudge for the common case, not a substitute for reading the receipt.
# **Third case, same family (found 2026-08-20 by dir #192's RC cross-PR-seam pass, dir #201):** on the
# IN-RUN convergence path (`commands/polish.md` step 5 — resolve, `--amend`, continue without
# re-`init`-ing, dir #177) nothing is retired, so this run's own earlier `polish.5-review` line stays
# in the LIVE sentinel, which this function never reads. Note the shape precisely, because it is NOT
# "silent on the in-run path": the comparison still runs, against whatever the last RETIRED round
# held. So an in-run drop is judged against the wrong baseline in both directions — silent when that
# round carried no add-on (an add-on gained and dropped inside one run, the dir #155 shape), and
# a warning about that OLDER round when it did, which only looks like a catch. Those two were verified
# live; so, separately, was the third direction below.
# **A further direction within that third case (dir #214), beyond the two just named:** whether EITHER
# of them happens depends on the lineage guard. `retire_sentinel` stamps the then-HEAD into the backup
# as `base-sha`, and `_validated_prev_sentinel` requires that sha to still be REACHABLE from current
# HEAD. A plain `--amend` of the very commit retirement saw ORPHANS it (a rewrite, not an extension),
# the guard returns 3, and this check goes SILENT there too, whatever the retired round held. Two
# details the obvious reading gets wrong, both load-bearing for any test written against this:
# (1) the condition is REACHABILITY, not "a fresh commit landed since `init`" — a commit is its own
# ancestor, so a round where HEAD never moved passes the guard and still compares; (2) the stamp is NOT
# necessarily the current round's `init`. `retire_sentinel` runs on every deny path and on the PASS
# branch as well (see its call sites and `init`'s own note, "the same retire_sentinel every deny/pass
# path uses below"), and it stamps only when a live sentinel exists — so after a deny or a shipped
# round, `init` finds nothing to retire and the backup keeps the EARLIER retirement's sha.
# Disclosed in that step's own prose rather than fixed here, because dir #186 removes this whole
# check; keep it in sync with BOTH other copies — `commands/polish.md` step 5 and the `[0.7.0]`
# CHANGELOG Known-issues block, which now carries the mechanism too, not just an announcement.
_warn_dropped_addons() {
  local receipt_key="$1" new_outcome="$2" cwd="${3:-$PWD}"
  local raw_prev prev prev_outcome prior_set new_set a label missing=""
  # dir #161 /code-review high: cheap pre-check, no fork of `git`/`awk` beyond the grep below — most
  # rounds have no prev backup at all, and there is nothing to compare regardless of lineage. Skipping
  # straight to the expensive lineage check inside `_validated_prev_sentinel` (a `git merge-base` fork)
  # before knowing whether the prev file even MENTIONS `polish.5-review` was wasted work on the common
  # no-op path. `-F` (fixed-string): the step id has no regex metacharacters worth treating specially.
  raw_prev="$(_prev_sentinel_path_for_key "$receipt_key")"
  [ -f "$raw_prev" ] || return 0
  # ANSI-C quoting, not `$(printf ...)` (dir #161 /code-review high): the whole point of this
  # pre-check is avoiding forks on the common no-op path — building its own search pattern via a
  # command-substitution fork would have undercut that.
  grep -qF -- $'\tpolish.5-review\t' "$raw_prev" || return 0
  # Existence/header/lineage validation is shared with `--recover` via `_validated_prev_sentinel`
  # (defined above, near `retire_sentinel`) — every failure reason (no backup, malformed header,
  # foreign lineage) is silent here, the opposite of `--recover`'s loud refusal, per this function's
  # own header.
  prev="$(_validated_prev_sentinel "$receipt_key" "$cwd")" || return 0
  # Same header-nonce + last-write-wins idiom `--recover` uses (shared via `_prev_sentinel_outcomes`,
  # above), filtered to just the one step id this check cares about.
  prev_outcome="$(_prev_sentinel_outcomes "$prev" polish.5-review)"
  [ -n "$prev_outcome" ] || return 0
  prior_set="$(_normalize_addon_set "$prev_outcome")"
  # Bail before computing `new_set` (a subshell fork) when `prior_set` is empty — the majority case per
  # the normalization table above (bare `agent:<level>`, `*-waived`, and `skip` all normalize to `{}`)
  # — the loop below would do nothing with `new_set` in that case anyway.
  [ -n "$prior_set" ] || return 0
  new_set="$(_normalize_addon_set "$new_outcome")"
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    # Filter the PRIOR set through `_addon_label` — the add-on allowlist, deliberately not duplicated
    # here (see its own header) — so this can never advise re-adding a token the gate would then deny.
    # The NEW set is compared as opaque tokens: the gate already rejects an invented add-on at unlock
    # time, duplicating that check here buys nothing.
    label="$(_addon_label "$a")" || continue
    # Pure-bash exact-line membership test — no `printf | grep` fork per token. `$a` is already
    # allowlist-filtered by `_addon_label` above (only ever `operator-run`/`second-opinion`, both
    # glob-metacharacter-free), so it is safe to use as a `case` PATTERN here; `$new_set` is only ever
    # the VALUE being matched, never itself a pattern, so its content needs no such guarantee.
    case $'\n'"$new_set"$'\n' in
      *$'\n'"$a"$'\n'*) : ;;
      *)
        # Name the raw TOKEN, not just its human label (found by the cross-model second-opinion review,
        # dir #161): the label alone (e.g. "in-session cross-model second opinion (self-reported...)")
        # gives the operator nothing to copy-paste back into the receipt — the token is what actually
        # goes after the `+` in `agent:<level>+<addon>`.
        missing="${missing:+$missing, }$a ($label)"
        ;;
    esac
  done <<< "$prior_set"
  [ -n "$missing" ] || return 0
  # Advisory only — stderr, and the caller's exit 0 is unaffected either way. Deliberately does not
  # mention either trace marker literal (KEEL-REVIEW-DIALOG/KEEL-DEPTH-DIALOG followed by ": level=") —
  # same discipline the skip-dialog deny message follows elsewhere in this file, so a session recapping
  # this warning inside an AskUserQuestion can never hand a hook the exact line it greps for.
  printf 'pre-pr-gate: this step-5 receipt drops add-on(s) the prior round recorded: %s. The add-on set applies to the SHIPPED COMMIT, not the round — if that reviewed work is still in HEAD, re-run with the full set (e.g. receipt polish.5-review "agent:<level>+<addon>[,<addon>...]"). If the fix commit removed the reviewed work, dropping it is fine and no action is needed.\n' "$missing" >&2
  # dir #161 /code-review high (altitude finding): the stderr print is the fastest signal in the
  # common case, but it relies entirely on being read — nothing forces that. Also persist the fact to
  # the durable impact log (the same `log_event` primitive `receipt-deny`/`receipt-pass`/etc. already
  # use throughout this file), so a session that misses the stderr line still leaves a mechanically
  # recoverable trail rather than none at all. Does not upgrade this into a gate — still advisory,
  # still `exit 0` either way; a later step is free to grep the log for this event type, but nothing
  # here requires it to.
  log_event review-addon-dropped "$missing" "$cwd"
}

# The hook's OWN observation of HEAD at fire time — never a self-reported field — shared by both
# skill-trace legs (the SubagentStop leg and the Skill/UserPromptExpansion legs below) so the same
# trust-boundary comment and the same one-liner aren't typed out twice in one case block.
_head_sha() { git -C "${1:-.}" rev-parse HEAD 2>/dev/null; }

# dir #123: a deterministic digest of the test-relevant part of a commit's tree, used to let
# `polish.3-tests` rebind to a LATER commit without re-running the suite when nothing that could affect
# a test outcome changed underneath it.
#
# **Not a blanket `*.md` exclusion — found unsound by this ticket's own operator-run /code-review high
# pass, reproduced live against this repo.** A `.md` file is only a CANDIDATE for exclusion; it is
# actually dropped from the hash ONLY when no file under `tests/` mentions its basename at all. Grepping
# every tracked `.md` basename against this repo's own suite found the vast majority genuinely
# test-relevant: `test_core_wrapper_sync.sh`/`test_conveyor_stages.sh`/`test_rails_honesty.sh`/
# `test_release_audit_doc.sh` byte-compare or content-check `CORE.md`, `templates/CLAUDE.md`,
# `commands/*.md`, `FRAMEWORK.md`, `docs/*.md`, `README.md` against the real repo tree; even
# `CHANGELOG.md` — the ticket's own headline "safe" example — is read by `test_doc_figures.sh`'s
# figure/floor check. A blanket exclusion would have let a commit that breaks one of those byte-equality
# checks sail through as "nothing test-relevant changed," precisely the false-negative the ticket's own
# acceptance criterion forbids. This dynamic check is self-maintaining (a newly-added test that starts
# reading some `.md` file makes that file test-relevant again automatically, no list to keep in sync) and
# fails closed (a `.md` file this check can't prove untested stays IN the hash, never silently dropped).
# Still no per-project pathspec — the "is it referenced" check is generic, not project-configured.
#
# `git ls-tree -r --full-tree <sha>` prints `<mode> <blob-sha> <path>` for the WHOLE tree regardless of
# `$cwd` — plain `-r` alone (an earlier version of this function used it) is silently scoped to `$cwd`'s
# OWN subtree when `-C` points below the repo root, so a change to a file elsewhere in the tree would
# never move the hash at all; reproduced live (a file outside the invocation's cwd, edited, and the hash
# didn't budge) by the same review pass. `%(objectmode)` is included too — content alone
# (`%(objectname)`) is unchanged by a `chmod +x`, so a mode-only change (also reproduced live: identical
# hash before/after) would otherwise be invisible to a mechanism whose whole job is detecting what
# changed. A content OR mode OR path change all move what gets printed; hashing the filtered listing with
# `git hash-object --stdin` folds that into one digest per (sha, filter) pair.
#
# **Failure contract, found by this ticket's own high review:** `git hash-object --stdin` hashes
# whatever bytes it receives, including zero of them — it emits the well-known empty-blob constant
# (`e69de2...`) for BOTH a genuinely empty/all-excluded tree AND a failed `ls-tree` (bad sha, corrupt
# odb) piped through as nothing. String emptiness can't tell those apart, so this returns via EXIT
# STATUS instead: non-zero (and no output) means `ls-tree` itself failed — callers must check that, not
# `-n` on the string, which is silently never false.
_test_relevant_tree_hash() {
  local cwd="$1" sha="$2" listing line rest path base
  local testsdir="$cwd/tests"
  listing="$(git -C "$cwd" ls-tree -r --full-tree --format='%(objectmode) %(objectname) %(path)' "$sha" 2>/dev/null)" || return 1
  {
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      # Fixed-width mode + objectname, so splitting on the first two spaces is safe even when the
      # PATH itself contains a space — `--format` (unlike default `ls-tree` output) does NOT C-quote
      # unusual path bytes, confirmed live: a filename with an embedded space came out raw, so
      # whitespace-based field-splitting across the whole line would have silently mis-parsed it.
      rest="${line#* }"
      path="${rest#* }"
      case "$path" in
        *.md)
          base="${path##*/}"
          [ -d "$testsdir" ] && grep -rq -F -- "$base" "$testsdir" 2>/dev/null && printf '%s\n' "$line"
          ;;
        *) printf '%s\n' "$line" ;;
      esac
    done <<< "$listing"
  } | git -C "$cwd" hash-object --stdin 2>/dev/null
}

# dir #123: enrich a `polish.3-tests` outcome with its tree-relevant hash — kept as its own function
# (not inlined into the `receipt` CLI's step-id dispatch below) because it's a trust-boundary
# computation with its own rationale, not a one-line side effect like the CLI's other per-step
# specializations. Any suffix the CALLER already appended (a hand-crafted "sha:fakehash", or a recovered
# value re-receipted by hand) is stripped and recomputed here, never taken as-is — trusting it would let
# a self-reported tree hash forge a match at read time, exactly the "trust the model" shape this ticket
# exists to avoid. The two skip literals (and anything else that isn't a resolvable commit) pass through
# unchanged; their read-time check is a plain string match and needs no suffix.
_stamp_tests_outcome() {
  local cwd="$1" outcome="$2" candidate_sha treehash
  case "$outcome" in
    skipped:*) printf '%s' "$outcome"; return ;;
  esac
  candidate_sha="${outcome%%:*}"
  if git -C "$cwd" rev-parse --verify --quiet "${candidate_sha}^{commit}" >/dev/null 2>&1; then
    # Exit status, not string emptiness (see _test_relevant_tree_hash's own comment) — a failed
    # computation must leave the outcome as the bare sha, not silently stamp nothing onto it.
    if treehash="$(_test_relevant_tree_hash "$cwd" "$candidate_sha")"; then
      outcome="${candidate_sha}:${treehash}"
    else
      outcome="$candidate_sha"
    fi
  fi
  printf '%s' "$outcome"
}

# dir #236: stamp a skip-level `polish.4-depth` outcome with the commit it was decided against — the
# same trust-boundary move dir #123 made for step 3 above (`_stamp_tests_outcome`): always computed
# fresh here, server-side, never taken from the caller. `receipt --recover` (below) reads only the LAST
# colon-separated field as the stamped sha, so any field a caller already embedded (a hand-crafted
# trailing sha, or a recovered value re-receipted by hand) is inert — this fresh append is always what
# gets read. Non-skip levels are untouched: they don't bypass step 5, so dir #116's hole never applied
# to them and there is nothing here for a digest to protect.
_stamp_depth_outcome() {
  local cwd="$1" outcome="$2" sha
  [ "${outcome%%:*}" = "skip" ] || { printf '%s' "$outcome"; return; }
  sha="$(_head_sha "$cwd")"
  [ -n "$sha" ] && outcome="${outcome}:${sha}"
  printf '%s' "$outcome"
}

# The `git worktree list --porcelain` main-entry projection, factored out so main_top_for() and
# resolve_impact_log() below (one file, two pre-dir-#61 and dir-#61 call sites) share the fragment
# instead of each inlining it — the awk is identical; only the surrounding fallback order differs, so
# only the fragment is extracted, not the two functions merged (dir #26 logs the wider idiom as
# duplicated across 5 TOOLS by design, no shared lib yet — that's a cross-tool constraint, unrelated to
# sharing one fragment within a single file).
_worktree_main_entry() {
  git -C "${1:-.}" worktree list --porcelain 2>/dev/null |
    awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true
}

# Resolve the main checkout's top for cwd $1 (dir #10/PR #67 discipline). Falls back to $1's own
# canonicalized toplevel when the main worktree entry is bare (no working tree) — this does NOT unify
# across a bare main's several worktrees (each still resolves to its own toplevel there); that's an
# accepted limitation shared with the established `_keel_main_top` idiom elsewhere, and keel's own
# worktrees are always cut from a non-bare checkout, so the dir #61 scenario below is unaffected. Falls
# back to $1 itself when it isn't a repo at all.
# dir #61: both the receipt writer (_require_receipt_key, below) and the hook reader key off THIS instead of
# a raw dirname/basename, so a receipt written from inside a (non-bare-main) worktree and a `gh pr
# create` hook event reporting a different checkout of the SAME repo (e.g. the harness's tracked
# session-root cwd) agree on one sentinel file — they always resolve to the same main-checkout path.
main_top_for() {
  local cwd="${1:-.}" main top
  main="$(_worktree_main_entry "$cwd")"
  if [ -n "$main" ]; then printf '%s' "$main"; return; fi
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then printf '%s' "$top"; return; fi
  printf '%s' "$cwd"
}

# dir #88: whether the AskUserQuestion -> skill-trace leg is actually wired into this session's Claude
# Code hooks — the PASS branch's dialog check (below) only fires when this returns true. See that dir
# #88 header section above for why an unconditional check would false-deny every `agent:*` unlock in
# the window between `git pull` and the operator re-running the installer. Checks the same candidate
# settings.json paths install-pre-pr-gate.sh itself writes to (project scope, and machine-global) — a
# repo/hook mismatch here means the installer's own write-target resolution changed and this needs a
# matching update, not a silent drift. Takes the main checkout's TOP PATH directly (already resolved via
# main_top_for per dir #61 by the PASS branch's own $wt derivation, above) rather than a cwd, so this
# doesn't re-fork `git worktree list --porcelain` a second time for the same answer.
#
# dir #85 (code audit, finding 4 + rails audit M2-7): the invariant that comment declares had ALREADY
# drifted. `install-pre-pr-gate.sh --global` writes to `${KEEL_HOME:-$HOME/.claude}/settings.json`,
# while this probed a hardcoded `$HOME/.claude/settings.json` — so an adopter with a non-default
# KEEL_HOME got a genuinely wired reminder hook that this read as UNARMED, and the dir #88
# mandatory-dialog deny then silently no-op'd: exactly the silent skip dir #88 exists to close.
#
# The KEEL_HOME-resolved path is ADDED to the candidate list, never substituted for `$HOME/.claude`
# (found by this ticket's own independent review, which caught the first fix doing exactly that).
# The two are not interchangeable: `$HOME/.claude/settings.json` is the file Claude Code loads by
# default, so a `KEEL_HOME` merely exported in the gate's environment must not stop this from probing
# it — that would re-open the same silent no-op from a different precondition. `settings.local.json` is
# in the list on the same basis (a hand-wired or harness-managed local override arms the leg just as
# well, even though the installer never writes it).
#
# **Residual limit** (raised by the operator-run /code-review high pass on this ticket, kept rather
# than engineered away): ARMED wins, so an extra candidate can only ever turn a false UNARMED into a
# correct ARMED — but if it matches a settings.json the HARNESS never loads, the wired-there hook never
# fires, no `dialog:` trace can ever be written, and the deny below becomes unsatisfiable. The escape
# is the same one commands/polish.md step 8 documents — an operator running `gh pr create` in their own
# terminal bypasses this PreToolUse hook entirely, since it fires on the AGENT's tool calls, not on a
# human typing. Note step 8 scopes that instruction to the dir #80 sentinel race, not to this deny;
# the mechanism is general, the written procedure for reaching for it is not. Why this is accepted: a
# KEEL_HOME-based install puts Keel's COMMANDS in the same directory this reads, so if `/polish` is
# running at all, the harness is loading it — the inert-file case and the "`/polish` is executing"
# precondition largely exclude each other. Erring toward deny in what is left is the deliberate choice:
# this leg guards a MANDATORY review step, and its failure mode is a loud block with a documented
# manual escape, versus a silent skip with none.
#
# That argument covers KEEL_HOME, NOT `install.sh --home DIR`/`install-pre-pr-gate.sh --home DIR`
# (dir #98 added `--home` to BOTH installers after this paragraph was first written — a prior version of
# it claimed the gate installer "has no --home of its own", which stopped being true and became this
# section's own stale comment, the exact class of bug B2 is named after). `install-pre-pr-gate.sh --home
# DIR` wires the 6 hooks at `DIR/settings.json`, a path none of the four static candidates above ever
# probe — a genuinely wired AskUserQuestion leg there reads as UNARMED and the dir #88 mandatory-dialog
# deny silently no-ops, the same class PR #165 closed for `KEEL_HOME` and PR #173's `--home` flag
# reopened (dir #125's own B2 finding).
#
# **Fix (dir #125):** rather than adding a fifth static guess, `_dialog_leg_armed` now also walks the
# checkout-side install ledger (`<checkout>/.keel/installed-homes`, `tools/lib/ledger.sh`'s discovery
# index, written by both installers) via `_gate_ledger_candidates` below. For every home the ledger
# lists, it verifies that home STILL carries a well-formed (version-1) gate manifest
# (`<home>/.keel/install-manifest.gate`) before trusting its recorded `settings=` path as a candidate —
# a stale ledger line whose manifest was since removed contributes nothing. This closes the `--home`
# gap without special-casing the flag: whatever directory the gate installer actually wired into is
# exactly the directory its own manifest records, ledger-verified.
_dialog_leg_armed() {
  local top="${1:?_dialog_leg_armed: main-checkout top path required}" f
  command -v jq >/dev/null 2>&1 || return 1
  # dir #150 audit (kept, not removed): these four static candidates were in scope for the general
  # no-manifest-fallback removal sweep, but they are NOT a transitional pre-manifest fallback the way the
  # other consumers' were — install-pre-pr-gate.sh's PROJECT scope (no --global/--home, the documented
  # default: tools/doctor.sh's own pairing-check comment names it that) writes NO manifest and NO ledger
  # entry, ever, by design (see that installer's own "project scope writes none" comment). The ledger
  # walk below can only ever see global/home-scope installs. Removing the static probes would leave
  # `_dialog_leg_armed` permanently UNARMED for every ordinary project-scope gate — not just pre-0.7
  # installs — silently disabling the dir #88 mandatory-review-dialog check for the common case forever.
  # That is exactly the "silent behavior change" this whole removal ticket forbids, so this block stays.
  for f in "$top/.claude/settings.json" "$top/.claude/settings.local.json" \
           "${HOME:-}/.claude/settings.json" \
           "${KEEL_HOME:-${HOME:-}/.claude}/settings.json"; do
    [ -f "$f" ] || continue
    if _gate_settings_has_dialog_hook "$f"; then
      return 0
    fi
  done
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if _gate_settings_has_dialog_hook "$f"; then
      return 0
    fi
  done < <(_gate_ledger_candidates)
  return 1
}

# `contains(...)`, not a regex `test(...)` — a plain substring check for this fixed literal, matching
# tools/doctor.sh's own `gate_hook_wired()` idiom for the identical "is this hook wired" shape (found
# in the operator-run /code-review high pass on this ticket — the two had drifted to different jq
# idioms with no behavioral difference; kept consistent so a future arming check copied from this one
# doesn't carry forward an unnecessary regex-escaping habit). Factored out of `_dialog_leg_armed` so
# both the static-candidate loop and the ledger-candidate loop (dir #125) share one jq query.
_gate_settings_has_dialog_hook() {
  jq -e '
      (.hooks.PostToolUse // []) | any(
        .matcher == "AskUserQuestion" and
        ((.hooks // []) | any(.command // "" | contains("pre-pr-gate.sh")))
      )
    ' "$1" >/dev/null 2>&1
}

# dir #125 (B2 fix): the checkout root THIS SCRIPT itself resides in — not `$top` (the project the gate
# is running against, resolved via `main_top_for` above), but the Keel checkout that ships this file and
# that `install-pre-pr-gate.sh` recorded a ledger entry into. Self-resolved from the running script's own
# path (mirrors `install-pre-pr-gate.sh`'s own `here=`/`repo_root=` derivation) so a symlinked or
# directly-invoked copy still finds its own siblings rather than the caller's cwd.
_gate_checkout_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || return 1
  (cd "$here/.." && pwd) 2>/dev/null
}

# dir #125 (B2 fix): for each home the checkout-side ledger (`installed-homes`) records, print that
# home's gate-manifest `settings=` path — but only when the manifest is still actually there and at a
# `keel_manifest_version` this reads (an unversioned/corrupt/removed manifest is silently skipped, never
# a crash: same versioning contract as every other dir #125 consumer, via `manifest_usable`/
# `manifest_field` — tools/lib/manifest.sh, sourced below; this used to be a THIRD hand-copy of the
# `key=value` reader tools/doctor.sh and uninstall.sh each already carry (found by an independent
# /simplify pass — all four review angles converged on the same duplication). A first draft shared it
# via tools/lib/ledger.sh instead, which uninstall.sh/install.sh/install-pre-pr-gate.sh ALSO source (for
# ledger_append/ledger_remove) and which each ALSO defines its own local manifest_field/manifest_usable
# for — that draft would have silently redefined those files' own functions mid-run the moment their
# existing ledger.sh source line executed (found by an operator-run /code-review high pass, reproduced
# at uninstall.sh's own conditional source inside its `manifests_left = 0` branch). A separate,
# single-consumer lib file avoids the collision instead of documenting around it. `KEEL_LEDGER_FILE` is
# the same test-isolation override `install.sh`/`install-pre-pr-gate.sh` respect. ARMED still wins
# (residual limit above), so a candidate this prints that turns out not to match is harmless — it just
# never matches.
_gate_ledger_candidates() {
  local checkout_root ledger home manifest settings
  checkout_root="$(_gate_checkout_root)" || return 0
  # shellcheck source=tools/lib/manifest.sh
  . "$checkout_root/tools/lib/manifest.sh" 2>/dev/null || return 0
  ledger="${KEEL_LEDGER_FILE:-$checkout_root/.keel/installed-homes}"
  [ -f "$ledger" ] || return 0
  while IFS= read -r home; do
    [ -n "$home" ] || continue
    manifest="$home/.keel/install-manifest.gate"
    manifest_usable "$manifest" || continue
    settings="$(manifest_field "$manifest" settings)"
    [ -n "$settings" ] && printf '%s\n' "$settings"
  done < "$ledger"
}

# The basename-of-main-checkout key every per-repo /tmp file below shares, factored out once dir #63
# added a second and third call site (skill-trace's own cwd, the hand-off note) beside the pre-existing
# hook-mode one — same rationale as _worktree_main_entry's own extraction, above.
_repo_key() { basename "$(main_top_for "${1:-$PWD}")"; }

# dir #80: sanitize a branch name into a flat-filename-safe slug — every char outside
# [A-Za-z0-9._-] (branch names routinely contain '/') becomes '-'. LC_ALL=C keeps this a plain ASCII
# whitelist regardless of the invoking locale's character classes. Takes the branch NAME as a string
# (not a cwd) — hook mode already has one resolved (an explicit --head, or a fork it already paid for)
# and must not re-derive it via a second git call just to sanitize it. LOSSY by design (many branch
# names can sanitize to the same slug, e.g. "feature/foo" and "feature-foo" both become
# "feature-foo") — never used alone to key uniqueness on; see _receipt_key_hash below, which hashes
# the RAW branch instead.
_sanitize_branch() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-'; }

# The CURRENT branch of cwd $1, RAW (unsanitized) — empty on a detached HEAD (no current branch; a
# fresh `git init` with no commits still reports its unborn default branch, so this is empty only on
# a true detached checkout).
_branch_raw_for() { git -C "${1:-.}" branch --show-current 2>/dev/null; }

# dir #80 (found by this ticket's own /code-review high pass): an unambiguous fingerprint of the
# (repo-key, RAW branch) pair $1/$2 — NOT a naive "$1-$2" string join, which is ambiguous: repo-key
# "foo-bar" + branch "baz" and repo-key "foo" + branch "bar-baz" both join to the identical string
# "foo-bar-baz" (both components routinely contain '-'). Hashing the RAW branch, not the sanitized
# slug, also sidesteps _sanitize_branch's own collapse (see its comment) — two branches that sanitize
# identically still hash differently as long as their raw names differ. \x1f (Unit Separator) joins
# the two inputs before hashing: neither a directory basename nor a git branch name can contain a
# control character, so this join is unambiguous even before the hash reduces it further. `cksum |
# tr -cd '0-9'` is the SAME house pattern keel-check.sh/keel-check-gate.sh already use to turn an
# arbitrary string into a filename-safe key — same 32-bit-CRC collision-risk tolerance this codebase
# already accepts elsewhere for the identical purpose.
_receipt_key_hash() { printf '%s\x1f%s' "$1" "$2" | cksum | tr -cd '0-9'; }

# dir #85 (code audit, findings 1+2): the ONE place the receipt-key FORMAT is assembled. dir #80
# factored out the primitives (_repo_key, _receipt_key_hash, _sanitize_branch) but left the three-part
# join itself hand-copied into three call sites — _require_receipt_key, retire_sentinel's key fallback,
# and hook mode's own inline build — so a format change (say a version prefix) meant three synchronized
# edits, one of them (the retire fallback) with no test of its own. Takes the repo key $1 and the RAW
# branch $2, exactly the two inputs every site already had on hand.
_receipt_key_for() { printf '%s-%s-%s' "$1" "$(_receipt_key_hash "$1" "$2")" "$(_sanitize_branch "$2")"; }

# dir #80: repo + branch, combined into the key every writer-side per-run file (sentinel,
# prev-sentinel, hand-off) is now keyed by, so two worktrees of the same repo on DIFFERENT branches no
# longer share one slot. Sets $RECEIPT_KEY in the CALLER's shell — same "call this inline, never via
# $(...)" discipline as require_active_receipt below: a detached-HEAD exit here must kill the whole
# script, not just a capturing subshell (which would silently leave $RECEIPT_KEY empty and let the
# caller carry on keying onto "-"). NOT used for trace_path_for/rollout_state_path — those stay
# per-repo, see their own definitions just below. Also sets $RECEIPT_REPO_KEY (the repo-only half it
# already computed along the way) so a caller needing BOTH — the `keys` subcommand below — doesn't
# pay for a second `_repo_key` fork just to get the piece this call already resolved. $RECEIPT_KEY
# itself is `<repo-key>-<hash>-<branch-slug>`: only the hash is load-bearing for uniqueness (see
# _receipt_key_hash above) — the surrounding repo-key/slug are cosmetic, kept so a human glancing at
# /tmp can still tell which repo/branch a sentinel belongs to.
_require_receipt_key() {
  local cwd="${1:-$PWD}" raw
  raw="$(_branch_raw_for "$cwd")"
  if [ -z "$raw" ]; then
    printf 'pre-pr-gate: cannot key the receipt — detached HEAD; check out the PR branch first\n' >&2
    exit 1
  fi
  RECEIPT_REPO_KEY="$(_repo_key "$cwd")"
  RECEIPT_KEY="$(_receipt_key_for "$RECEIPT_REPO_KEY" "$raw")"
}

# dir #72 finding #7: plain string-building, no `_repo_key` fork of their own — callers that already
# have a resolved key (hook mode's `$wt`/`$receipt_key`, `init`/`require_active_receipt` below) build
# paths through these instead of the `_repo_key`-calling wrappers, so a repo key already paid for once
# is never re-derived (each `_repo_key` call forks `git worktree list --porcelain`). The wrappers below
# still exist and still call `_repo_key` themselves — for callers that do NOT already have the key on
# hand, nothing changes.
_sentinel_path_for_key()      { printf '/tmp/pre-pr-gate-%s' "$1"; }
_prev_sentinel_path_for_key() { printf '/tmp/pre-pr-gate-prev-%s' "$1"; }

# dir #63: the review-invocation trace (skill-trace writes it, the gate's PASS branch reads it) and the
# step-5(b) hand-off note (handoff/handoff-check) each get their OWN file, keyed the same way as the
# sentinel — not lines folded into the sentinel itself. Keeping them separate means `init`'s nonce reset
# (the sentinel's job: wipe the PREVIOUS run's receipts, dir #49) never has to know the hand-off note
# exists at all: it lives elsewhere, so it survives by construction, not by a special case in `init`.
# dir #80: trace_path_for stays per-repo (NOT $RECEIPT_KEY) — see the dir #80 header section above for
# why (append-only, matched by sha+level, concurrent branches already interleave harmlessly).
trace_path_for() { printf '/tmp/pre-pr-gate-trace-%s' "$(_repo_key "${1:-$PWD}")"; }
# dir #80: reads the already-resolved $RECEIPT_KEY (set by _require_receipt_key, called inline by
# every CLI subcommand that uses this below) rather than re-deriving it itself — deriving it here
# would mean calling the detached-HEAD-checking _require_receipt_key from inside a function that's
# itself invoked via `$(...)` everywhere below, where its `exit 1` would only kill the capturing
# subshell instead of the whole script.
handoff_path()   { printf '/tmp/pre-pr-gate-handoff-%s' "$RECEIPT_KEY"; }
# dir #88 (found in the operator-run /code-review high pass on this ticket): all three `skill-trace`
# legs below (SubagentStop, PostToolUse/AskUserQuestion, Skill/UserPromptExpansion) share this exact
# tail — resolve THIS hook's own observed sha, guard a missing one, append `<sha>\t<tag_level>` to the
# trace file — factored out once dir #88's new leg turned a 2x duplicate into a 3x one (matches
# `_trace_has_line`'s own read-side extraction above, same rule-of-three trigger). `exit 0` on a missing
# sha exits the whole script, not just this function — safe and intended: every call site is a direct
# call, never inside a subshell/pipeline, so this preserves each leg's own prior silent-no-op behavior.
_append_trace_line() {
  local cwd="$1" tag_level="$2" sha
  sha="$(_head_sha "$cwd")"
  [ -n "$sha" ] || exit 0
  printf '%s\t%s\n' "$sha" "$tag_level" >> "$(trace_path_for "$cwd")"
}
# dir #88 simplify pass: the PASS branch's dir #63 trace check and its new dir #88 dialog check both
# ask "does the trace file carry a line <sha>\t<level> for this repo key" — factored out once there
# were two, so a future trace-file format change only needs one edit. Takes the repo KEY directly
# (not a cwd) since both PASS-branch call sites already have `$wt` resolved (dir #72 finding #7's own
# reasoning: don't re-fork `_repo_key` for a key already on hand).
_trace_has_line() {
  local wt_key="$1" sha="$2" lvl="$3" tp
  tp="/tmp/pre-pr-gate-trace-$wt_key"
  [ -f "$tp" ] && awk -F'\t' -v sha="$sha" -v lvl="$lvl" '$1==sha && $2==lvl{f=1} END{exit !f}' "$tp"
}
# dir #72: a single-slot backup of whatever receipt was just invalidated — by `init` minting a fresh
# nonce, or by the gate denying and discarding the sentinel. `retire_sentinel` (below) is the ONE place
# that both writes this and clears the live sentinel, so every invalidation path (there are several —
# MALFORMED/MISSING/REPLAY/sha-mismatch/review-depth-mismatch/review-trace-missing denies, the PASS
# branch's own post-unlock cleanup, and `init`'s overwrite) leaves the same recoverable trail. Only the
# MOST RECENT retirement is kept (a plain overwrite, not a history) — matches the felt shape (dir #69/PR
# #145): one review-fix commit invalidates the run that was just denied or just completed, and that is
# exactly what `receipt --recover` needs to restore.
# $2 (cwd) matters in hook mode: the live sentinel there is keyed off the JSON event's `.cwd`, not this
# script's own $PWD (dir #61 discipline) — defaulting to $PWD only serves the CLI subcommands, where
# $PWD IS the repo by construction. A same-filesystem rename (both paths are /tmp) does the backup-then-
# clear in one process instead of a copy plus a separate unlink. $3 (key) lets a caller that already
# resolved the (dir #80: repo+branch) key (hook mode's `$receipt_key`, `init` below) pass it straight
# through instead of paying for a second fork of the same git commands (dir #72 finding #7) — every
# real call site below passes it; the fallback (key derived fresh from `$cwd` when $3 is omitted) is a
# defensive last resort, not a path any current caller exercises.
retire_sentinel() {
  local sentinel="$1" cwd="${2:-$PWD}" key="${3:-}" prev sha rk raw
  if [ -z "$key" ]; then
    rk="$(_repo_key "$cwd")"
    raw="$(_branch_raw_for "$cwd")"
    key="$(_receipt_key_for "$rk" "$raw")"
  fi
  if [ -f "$sentinel" ]; then
    prev="$(_prev_sentinel_path_for_key "$key")"
    if mv -f "$sentinel" "$prev" 2>/dev/null; then
      # dir #72 finding #3 (verified review, high-effort code-review pass): stamp the backup with
      # $cwd's HEAD sha AT RETIREMENT TIME, so `receipt --recover` can refuse to trust a backup that
      # is not on the SAME lineage as the diff it is about to be recovered onto — an unrelated
      # worktree/branch's retirement (the shared per-repo key is deliberate, dir #61), or a rebase/
      # amend since retirement. 2 tab-separated fields, safely ignored by every existing 3+-field
      # step parser over this file (both `receipt --recover`'s own step extraction below and, if ever
      # pointed at this file, the completeness parser's `NF>=3` guard).
      sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null)"
      [ -n "$sha" ] && printf 'base-sha\t%s\n' "$sha" >> "$prev"
    else
      # dir #72 finding #4: a failed mv used to be entirely silent (stderr discarded, exit status
      # never checked) — the live sentinel still gets cleared below (correct either way: it is
      # invalid once retirement was attempted), but the loss is now at least recorded instead of
      # masquerading as "nothing was ever retired" the next time `receipt --recover` runs.
      log_event retire-sentinel-mv-failed "$cwd"
    fi
  fi
  rm -f "$sentinel"
}
# dir #161: shared by `receipt --recover` and `_warn_dropped_addons` (below) — both need "does key $1's
# retired backup exist, is its header well-formed, and is it on the SAME lineage as $2 (cwd)'s current
# HEAD" before trusting anything it says. On success, prints the prev sentinel's path on stdout and
# returns 0. On failure, returns one of three distinct codes and prints nothing — the two callers need
# opposite FAIL DIRECTIONS (`--recover` is about to grant trust, so it reports each reason loudly and
# stops; `_warn_dropped_addons` grants no trust, so an unverifiable prior must never manufacture a warn,
# and stays silent on all three — see its own header), so the messaging stays with each caller rather
# than living here:
#   1 = no backup at all (a first-ever round, or nothing retired since the last `init`)
#   2 = malformed header (no leading `nonce\t…` line)
#   3 = lineage guard failed (missing/foreign base-sha — not a verified ancestor of current HEAD)
# Before this (dir #161), `--recover` carried this exact three-check sequence inline and
# `_warn_dropped_addons` would have been a second, independent copy of it (flagged live in this ticket's
# own /simplify pass — reuse, simplification and altitude angles all converged on the same finding).
# **This function itself carries no trust semantics (found by the cross-model /code-review high pass,
# dir #161) — the "grants trust" / "grants no trust" language above describes its two CURRENT CALLERS,
# not this function.** It only checks facts and returns a path + a numeric code; a future third caller
# must consciously choose its own fail direction (loud vs. silent) for its own use case rather than
# pattern-matching one of the two existing callers off the language in this comment.
_validated_prev_sentinel() {
  local key="$1" cwd="${2:-$PWD}" prev prev_header base_sha
  prev="$(_prev_sentinel_path_for_key "$key")"
  [ -f "$prev" ] || return 1
  prev_header="$(awk -F'\t' 'NR==1{print; exit}' "$prev")"
  case "$prev_header" in
    nonce$'\t'*) : ;;
    *) return 2 ;;
  esac
  base_sha="$(awk -F'\t' '$1=="base-sha"{print $2; exit}' "$prev")"
  if [ -z "$base_sha" ] || ! git -C "$cwd" merge-base --is-ancestor "$base_sha" HEAD 2>/dev/null; then
    return 3
  fi
  printf '%s\n' "$prev"
}
# dir #161 /code-review high: shared by `receipt --recover`'s own replay (which reads ALL steps) and
# `_warn_dropped_addons` (which reads only ONE) — both read the RETIRED prev sentinel and need no
# foreign-nonce/MISSING/REPLAY bookkeeping. Contrast the completeness parser elsewhere in this file
# (search `EXPECTED_STEPS`), which reads the LIVE sentinel and does need that extra state for its
# PASS/MISSING/REPLAY verdict — dir #72 finding #6 already argued, and this still holds, for why THAT
# one stays a separate implementation rather than sharing with either of these two. $1 = the prev
# sentinel file (assumed already header-validated by the caller, e.g. via `_validated_prev_sentinel`).
# $2 = an optional step id filter: given, prints only that step's outcome (nothing if it was never
# written under the matching nonce); omitted, prints "step<TAB>outcome" for every step, in first-seen
# order — the shape `--recover` needs to replay them all. If the receipt line FORMAT itself ever
# changes (delimiter, field count), this is now the ONE place that needs the matching edit for both
# consumers.
_prev_sentinel_outcomes() {
  awk -F'\t' -v want="${2:-}" '
    NR==1 { if ($1=="nonce" && $2!="") pnonce=$2; next }
    NF>=3 && pnonce!="" && $1==pnonce {
      # Filtered call (dir #161 /code-review high): track a plain scalar, not the order[]/val[]
      # array pair — that bookkeeping is only needed to replay ALL steps in first-seen order for
      # `--recover`, which this branch never does. Building it anyway on every matching line, only
      # to have `END` never read it, was wasted work. The nonce guard above still applies either
      # way — only lines under the CURRENT nonce ever reach here.
      if (want!="") { if ($2==want) scalar=$3; next }
      if (!($2 in val)) order[++n]=$2
      val[$2]=$3
    }
    END {
      if (want!="") { print scalar; exit }
      for (i=1;i<=n;i++) print order[i] "\t" val[order[i]]
    }
  ' "$1"
}
# dir #72: shared by `receipt --recover` and the ordinary `receipt <step-id>` path (both need "is there
# an active receipt, and what's its nonce" before doing anything else) — sets $sentinel/$nonce in the
# CALLER's shell (this runs inline, not in a `$(...)` subshell, so `exit 1` here ends the whole script
# exactly like the two call sites' own inline checks used to). Also sets $receipt_key (dir #72 finding
# #7) so `receipt --recover` can build its own prev-sentinel path from it directly instead of paying
# for a second fork of the same key-derivation commands. dir #80: calls `_require_receipt_key` inline
# (same discipline — a detached-HEAD exit here must end the whole script too) so $receipt_key is now
# the combined (repo, branch) key, and also sets $RECEIPT_KEY for handoff_path()'s benefit.
require_active_receipt() {
  _require_receipt_key
  receipt_key="$RECEIPT_KEY"
  sentinel="$(_sentinel_path_for_key "$receipt_key")"
  if [ ! -f "$sentinel" ]; then
    printf 'pre-pr-gate: no active receipt — run "pre-pr-gate.sh init" first\n' >&2
    exit 1
  fi
  nonce="$(awk -F'\t' 'NR==1 && $1=="nonce"{print $2}' "$sentinel")"
  if [ -z "$nonce" ]; then
    printf 'pre-pr-gate: receipt file has no nonce header — run "pre-pr-gate.sh init" first\n' >&2
    exit 1
  fi
}
# dir #64 tier 1: the last-seen model/harness version per repo, keyed the same way — a fresh file, so
# `init`'s nonce reset (the sentinel's job) never touches it, same rationale as the trace/hand-off files.
rollout_state_path() { printf '/tmp/pre-pr-gate-rollout-%s' "$(_repo_key "${1:-$PWD}")"; }

# Resolve the impact log path for a given cwd ($1): $KEEL_IMPACT_LOG, else this project's external
# store entry (dir #251), else a legacy in-tree .keel/impact-events.log left over from before the
# store existed. One resolution used everywhere a guard/receipt/log event is recorded (dir #49 folded
# three copies into this one; dir #251 moved its body into tools/lib/impact-store.sh, shared by every
# consumer that CAN source it — this file, public-audit.sh, keel-impact.sh itself).
resolve_impact_log() {
  impact_log_path "$1"
}

# dir #74: the log's 5th TSV field — the claim key an event is stamped with, so a shared multi-worktree
# log can tell "my event" from "someone else's" at ingest time. This is the site's OWN worktree top,
# taken BEFORE resolve_impact_log's main-checkout fallback — the fallback is only about where the log
# FILE lives, not who fired the event. Empty outside a repo (matches resolve_impact_log's own git call).
#
# CAVEAT: "field 5 = claim key" only holds for a `detail` with no embedded tab. The receipt-pass call
# below intentionally packs two values into `detail` via a literal tab (dir #63/#64's `sweep` provenance
# trick), so its actual on-disk line has 6 tab fields, not 5, and $5 there is `prov_tag`, not the claim
# key — currently harmless only because `keel-impact.sh` doesn't score receipt-pass (EVENT_TYPES excludes
# it), so nothing ever reads that misplaced field. `keel-impact.sh cmd_add`'s ingest loop round-trips such
# a line VERBATIM (the original 6-field text, not a 5-field reconstruction) whenever a rewrite happens to
# preserve it, so the extra field survives on disk even though nothing reads it yet — but don't extend
# EVENT_TYPES to cover a type whose detail can carry an embedded tab without also sanitizing it here the
# way `keel-impact.sh cmd_event`'s `_flatten` does for its own writes.
# Append one event line, resolving the log path for cwd $3 (default $PWD). Writes to the log file only —
# never stdout, so a hook's JSON decision stays intact; with no log path resolved, this is a silent no-op.
log_event() {
  local ty="$1" detail="${2:-}" cwd="${3:-$PWD}" log key
  log="$(resolve_impact_log "$cwd")"
  [ -n "$log" ] || return 0
  # dir #251 review: this used to be a local _claim_key(), byte-for-byte identical to the shared lib's
  # own impact_claim_key() (already sourced above for resolve_impact_log) — one fewer copy of dir #74's
  # concurrency-invariant logic to keep in sync.
  key="$(impact_claim_key "$cwd")"
  # dir #251 review: the resolver's legacy-marker fallback can name a path whose parent .keel/ doesn't
  # physically exist yet (a fresh clone carrying the committed gitignore line but never recreating the
  # untracked dir) — without this, the append's own failed redirect leaks a raw error and silently
  # drops the event.
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ty" pre-pr-gate "$detail" "$key" >> "$log" 2>/dev/null || true
}

case "${1:-}" in
  repo-key)
    # Exposes _repo_key() (the worktree-aware basename(main_top_for(...)) dir #61 resolution the
    # trace/rollout-state paths are keyed by) to other tools — dir #64's own pipeline-canary.sh uses
    # this instead of hand-copying the algorithm, which would silently drop the worktree resolution
    # if it ever changes here. dir #80: the sentinel/prev-sentinel/hand-off paths moved to the
    # (repo, branch) key below — use `receipt-key`, not this, for those.
    printf '%s\n' "$(_repo_key "${2:-$PWD}")"
    exit 0
    ;;
  receipt-key)
    # dir #80: exposes _require_receipt_key()'s (repo, branch) key — the sentinel/prev-sentinel/
    # hand-off keying — to other tools/tests, same rationale as `repo-key` above: a sanitization-
    # algorithm change here never needs a matching hand-copied edit in tests/lib.sh or
    # pipeline-canary.sh. Detached HEAD still hard-errors (same as every other writer-side use)
    # rather than silently emitting a wrong/empty key.
    _require_receipt_key "${2:-$PWD}"
    printf '%s\n' "$RECEIPT_KEY"
    exit 0
    ;;
  keys)
    # dir #80: repo-key and receipt-key together, tab-separated, from ONE `_require_receipt_key` call
    # — a caller needing both (pipeline-canary.sh's cmd_check: repo-key for the trace path,
    # receipt-key for the sentinel/hand-off paths) would otherwise fork this whole script twice, each
    # independently re-running `git worktree list --porcelain`/`git branch --show-current` to arrive
    # at values one call already produces.
    _require_receipt_key "${2:-$PWD}"
    printf '%s\t%s\n' "$RECEIPT_REPO_KEY" "$RECEIPT_KEY"
    exit 0
    ;;
  init)
    _require_receipt_key
    sentinel="$(_sentinel_path_for_key "$RECEIPT_KEY")"
    # dir #72: back up whatever this overwrite is about to discard (via the same retire_sentinel every
    # deny/pass path uses below), before minting the fresh nonce — so a re-`init` after a review-fix
    # commit still leaves the PRIOR run's completed steps reachable via `receipt --recover`. Passing
    # $RECEIPT_KEY through (dir #72 finding #7) skips a second fork for the same key.
    retire_sentinel "$sentinel" "$PWD" "$RECEIPT_KEY"
    nonce="$(date -u +%Y%m%dT%H%M%S)-$$-$RANDOM"
    printf 'nonce\t%s\n' "$nonce" > "$sentinel"
    printf 'pre-pr-gate: receipt started (nonce %s)\n' "$nonce"
    exit 0
    ;;
  receipt)
    if [ "${2:-}" = "--recover" ]; then
      # dir #72: re-stamp the immediately-prior (now-retired) run's receipts onto the CURRENT nonce, in
      # one call — the convergence-round shortcut commands/polish.md step 1's own convergence branch
      # calls right after `init`. dir #96 narrowed it once, so this is no longer "whatever the prior run
      # had, superseded later by a fresh write": `polish.5-review` is never restored (see the filter
      # below), and a step id THIS run already wrote is left alone rather than overwritten — so the
      # order of `--recover` against your own receipt calls no longer matters. `polish.3-tests` WAS also
      # excluded here by dir #96, but dir #123 lifted that: it now recovers like any other step, because
      # its stamped tree-relevant hash (see `_test_relevant_tree_hash` above) lets the read-time check
      # below mechanically tell a genuinely-stale recovery from one that's still good — recovering it
      # unconditionally used to be exactly the silent-skip dir #96 existed to close, so lifting the
      # exclusion had to come with that read-time proof, not on its own. The steps a round must ALWAYS
      # write for itself are 5, 6 and 8 (3 usually recovers now; see the dir #123 note near the
      # test-binding check below for when it still can't). The gate's own completeness/sha/trace checks
      # are untouched either way, so a recovered-but-now-stale value can never itself unlock it.
      require_active_receipt
      # `prev`'s path is recomputed here even though `_validated_prev_sentinel` (below) derives the
      # identical value internally — reviewed live (cross-model /code-review high, dir #161) and kept
      # deliberately: this block's own message #2 needs `$prev`'s VALUE for its text, and the shared
      # function's bare 1/2/3 return-code signature has no channel to hand it back without widening that
      # signature for a caller-specific need. Same reasoning covers the `base_sha` re-derivation on the
      # `rc=3` branch below — real, minor duplication, judged not worth complicating a shared,
      # security-adjacent validator's signature to remove.
      prev="$(_prev_sentinel_path_for_key "$receipt_key")"
      # dir #161: the exists/header/lineage checks below now live once, in `_validated_prev_sentinel`
      # (shared with `_warn_dropped_addons`) — this block keeps its own three distinct, loud messages
      # (dir #72 findings #3/#5), since `--recover` is about to GRANT trust and must say exactly why it
      # refuses to; only the shared VALIDATION moved, not the reporting.
      _validated_prev_sentinel "$receipt_key" "$PWD" >/dev/null
      rc=$?
      if [ "$rc" -ne 0 ]; then
        case "$rc" in
          1)
            printf 'pre-pr-gate: nothing to recover — no receipt was retired since the last init\n' >&2
            ;;
          2)
            printf 'pre-pr-gate: prior receipt (%s) is malformed (bad or missing nonce header) — not recovering. Investigate the file, or proceed as a fresh (non-convergence) run.\n' "$prev" >&2
            ;;
          *)
            base_sha="$(awk -F'\t' '$1=="base-sha"{print $2; exit}' "$prev")"
            printf 'pre-pr-gate: refusing to recover — the retired backup base commit (%s) is not a verified ancestor of current HEAD. Looks like an unrelated run (a different worktree/branch), or a rebase/amend since retirement. Proceed as a fresh (non-convergence) run instead.\n' "${base_sha:-<none>}" >&2
            ;;
        esac
        exit 1
      fi
      # dir #72 finding #6 / dir #161: reads the RETIRED sentinel via `_prev_sentinel_outcomes` (shared
      # with `_warn_dropped_addons`, above) — see that function's own header for why it does NOT also
      # share with the completeness parser below (`EXPECTED_STEPS`), which reads the LIVE sentinel and
      # needs extra MISSING/REPLAY bookkeeping this one doesn't.
      recovered="$(_prev_sentinel_outcomes "$prev")"
      if [ -z "$recovered" ]; then
        printf 'pre-pr-gate: prior receipt had no completed steps to recover\n' >&2
        exit 1
      fi
      # dir #96: NEVER clobber a receipt this run already wrote. Recovery appends, and the completeness
      # parser takes the last write per step id — so before this guard, a session that re-ran its tests
      # and receipted `polish.3-tests <new sha>` BEFORE calling `--recover` had that fresh, correct
      # value silently superseded by the stale recovered one, and then got denied for an unbound test
      # run it had actually done. Harmless while step 3's outcome was inert; load-bearing the moment it
      # became a sha. Rather than leaning on step 1's prose ("call --recover right after init"), make
      # the order stop mattering: recovery fills gaps, it does not overwrite this run's own work.
      already="$(awk -F'\t' -v n="$nonce" 'NF>=3 && $1==n {print $2}' "$sentinel" | sort -u)"
      # Shared by the polish.5-review/polish.3-tests/polish.4-depth withheld-from-recovery arms below —
      # note a step as unrecovered (and why) UNLESS this run already wrote it itself, in which case a
      # fresh write already exists and the note would send the round to redo work it just did.
      _note_unrecovered() {
        local step="$1" reason="$2"
        # A `<<<` here-string, not `printf | grep -q`: this file has no `pipefail` today, so the
        # SIGPIPE race dir #280 fixes elsewhere can't flip this yet — but the fix is free, and most of
        # this repo's tools/*.sh files do set pipefail, so leaving the pipe form here is one stray
        # `set -o pipefail` away from reintroducing it.
        if ! grep -qxF -- "$step" <<< "$already"; then
          unrecovered="${unrecovered:+$unrecovered / }$step"
          todo="${todo:+$todo, }$reason"
        fi
      }
      # dir #236: the digest the narrowed skip-recovery arm below checks a stamped `polish.4-depth`
      # outcome against — computed once here rather than per-line, since it can't change mid-loop.
      current_head="$(_head_sha "$PWD")"
      count=0; skipped_existing=0; unrecovered=""; todo=""
      while IFS=$'\t' read -r r_step r_outcome; do
        [ -n "$r_step" ] || continue
        # dir #144 (operator-run /code-review medium finding) + dir #149: the direct `receipt <step-id>`
        # write path rejects both a whitespace-carrying step_id and one not in $EXPECTED_STEPS, but this
        # recovery path reads r_step from a RETIRED sentinel that could predate either guard (or was
        # hand-edited) — without this check, recovering it would silently reintroduce the exact
        # malformed-line bug those guards exist to close, just through a second entry point. Skip (not
        # abort) so one bad historical line doesn't block recovering the rest of an otherwise-good
        # backup. Whitespace gets its own, more specific reason text ahead of the general membership
        # check (the same `_expected_step` helper `receipt` itself now calls) purely for a friendlier
        # message — a whitespace-carrying candidate would fail the membership check too.
        r_malformed_reason=""
        case "$r_step" in
          *[[:space:]]*) r_malformed_reason="carries whitespace" ;;
        esac
        if [ -z "$r_malformed_reason" ] && ! _expected_step "$r_step"; then
          r_malformed_reason="not one of the expected steps"
        fi
        if [ -n "$r_malformed_reason" ]; then
          unrecovered="${unrecovered:+$unrecovered / }$r_step (malformed — $r_malformed_reason)"
          todo="${todo:+$todo, }a prior receipt for this step was malformed and could not be recovered; re-run it fresh"
          continue
        fi
        case "$r_step" in
          polish.5-review)
            # dir #96: never recovered. It binds a claim to a SPECIFIC commit and has an arm that does
            # not self-correct when the commit moves — a bare level or `agent:*` is caught by the trace
            # check (keyed to current HEAD), but the TRUSTED arms — `skip`, `*-operator-run`,
            # `*-waived` — skip that check entirely, so a recovered one claims this fix commit was
            # reviewed when it was not. Reproduced end-to-end by this ticket's own high review.
            # commands/polish.md already tells the round to redo it ("step 5 for the delta re-review"),
            # so this makes the code say what the prose already said.
            _note_unrecovered "$r_step" "step 5 a fresh delta re-review"
            continue
            ;;
          polish.3-tests)
            # dir #123: recovered ONLY when the retired outcome carries a stamped tree-relevant hash
            # (`<sha>:<treehash>`, written server-side by `receipt` itself — see there) — the read-time
            # test-binding check below independently re-verifies that hash against current HEAD, so a
            # recovered value that turns out stale still denies on its own; recovering it is safe. A
            # SKIP LITERAL (`skipped:--no-test`, `skipped:no-test-command`) or a legacy bare sha carries
            # no such re-validation, so it is NEVER recovered, unchanged from dir #96's original rule:
            # blindly carrying a skip literal forward would silently re-assert a waiver into a round that
            # never asked for one — the exact hole a second dir #96 review pass found and closed by
            # excluding step 3 outright, before this hash existed to re-check it safely. The glob
            # requires a HEX first character before the colon so neither shape can slip through it: a
            # skip literal starts with `s`, a bare sha has no colon at all.
            case "$r_outcome" in
              [0-9a-f]*:*) : ;;
              *)
                _note_unrecovered "$r_step" 'step 3 bound to $(git rev-parse HEAD) (step 6 rebinds it too, but only if a later commit still changes files)'
                continue
                ;;
            esac
            ;;
          polish.4-depth)
            # dir #116: a SKIP-level depth is never recovered — the other depth with an arm that stays
            # silently true across a commit. `skip` is the one level that bypasses step 5 outright, and
            # commands/polish.md step 4 tells a convergence round to reuse the recovered level AS-IS
            # ("do not re-size") — so recovering it hands the new commit a review bypass the operator
            # chose for a DIFFERENT diff. Reproduced end-to-end by dir #96's own review: trivial diff →
            # skip → substantial fix commit → recovered skip + fresh `polish.5-review skip` matched the
            # depth cross-check and the gate answered allow with no review ever seeing the commit.
            # Non-skip levels keep recovering (dir #72's convenience): they bypass nothing — step 5
            # still has to produce a fresh outcome for them, HEAD-keyed by trace or named-source arms.
            #
            # dir #236: narrowed, not lifted. Felt case: a session skip-sizes a trivial diff, misses
            # step 5's own receipt-only write (no review to run for `skip`), and `gh pr create` denies for
            # the missing step 5 receipt — retiring this sentinel even though nothing shipped since the
            # skip decision. Refusing recovery unconditionally forces a full re-ask of BOTH step 4 dialogs
            # for a diff the operator already approved skipping. `_stamp_depth_outcome` (write path, above)
            # now stamps every skip outcome with the commit it was decided against, so this can tell dir
            # #116's dangerous case (a fix commit landed since) from the safe one (nothing did) by a
            # digest instead of assuming the worst every time: recover only when that stamped sha still
            # equals current HEAD. A legacy/unstamped bare `skip` (written before this fix, or if sha
            # resolution ever failed at write time) has no digest to check and stays withheld, same as
            # today — the safe default whenever the evidence is missing, not just when it's contradicted.
            # One arm, not two: a bare `skip` (no stamp) and a stamped `skip:<measurement>:<sha>` that
            # mismatches current HEAD both fail the identical "is there a digest, and does it match"
            # test. `##*:` takes the LAST colon-separated field, which is the sha whenever one was
            # stamped (the free-text measurement in between may itself contain no colon, but nothing
            # requires that — greedy-from-the-end is what makes this robust either way); on a bare
            # `skip` with no colon at all, `##*:` is a no-op, so comparing the result back to the whole
            # string is how "no stamp existed" is told apart from "a stamp existed and it was empty".
            case "$r_outcome" in
              skip|skip:*)
                r_depth_sha="${r_outcome##*:}"
                [ "$r_depth_sha" = "$r_outcome" ] && r_depth_sha=""
                if [ -z "$r_depth_sha" ] || [ "$r_depth_sha" != "$current_head" ]; then
                  _note_unrecovered "$r_step" "step 4 re-sized fresh (no proof the recorded skip was decided for current HEAD — an unstamped/legacy skip, or one decided at a different commit; re-confirm skip, or size fresh, for this diff)"
                  continue
                fi
                ;;
            esac
            ;;
        esac
        # A `<<<` here-string, not `printf | grep -q` (dir #280 — see _note_unrecovered above for why).
        if grep -qxF -- "$r_step" <<< "$already"; then
          skipped_existing=$((skipped_existing + 1)); continue
        fi
        printf '%s\t%s\t%s\n' "$nonce" "$r_step" "$r_outcome" >> "$sentinel"
        count=$((count + 1))
      done <<< "$recovered"
      [ "$skipped_existing" -eq 0 ] || printf 'pre-pr-gate: kept %s receipt(s) this run had already written (not overwritten by recovery)\n' "$skipped_existing"
      # No ticket number in this shared note: it now reports two exclusions with different origins
      # (steps 3/5 — dir #96; a skip-level step 4 — dir #116), and a single hardcoded reference sent
      # readers to the wrong ticket for the other one. The per-arm comments above carry the attribution.
      [ -z "$unrecovered" ] || printf 'pre-pr-gate: %s NOT recovered by design — this round must write: %s\n' "$unrecovered" "$todo"
      printf 'pre-pr-gate: recovered %s step receipt(s) from the prior run onto nonce %s\n' "$count" "$nonce"
      exit 0
    fi
    step_id="${2:?pre-pr-gate: receipt <step-id> [outcome] — step id required}"
    # dir #144 (stranded fix/pre-pr-gate-malformed-receipt-guard, re-derived onto current main): step-id
    # and outcome are separate shell args — `receipt "polish.4-depth high:+261-27,..."` (one combined
    # quoted string) used to write a malformed line whose step-id field was the whole string, so the
    # completeness check's literal match on e.g. "polish.4-depth" silently failed later, denying
    # `gh pr create` with a message indistinguishable from a real concurrent-write sentinel collision —
    # see [[pre-pr-gate-receipt-needs-two-args]]. No real step id ever contains whitespace, so failing
    # loudly HERE turns a deferred, misleading "missing receipt" denial into an immediate, legible one.
    case "$step_id" in
      *[[:space:]]*)
        printf 'pre-pr-gate: step-id %q contains whitespace — step-id and outcome must be SEPARATE arguments (e.g. receipt polish.4-depth "high:+261-27,..."), not one combined quoted string. Re-run with the two split apart.\n' "$step_id" >&2
        exit 1
        ;;
    esac
    # dir #149: the whitespace guard above catches the felt "combined quoted string" incident, but a
    # typo'd, space-free step-id (e.g. "polish.4-depht") still passed it and wrote silently — the same
    # deferred, misleading "missing receipt" denial at `gh pr create` time, just via a different
    # malformation shape. `_expected_step` (defined by EXPECTED_STEPS above) closes it.
    if ! _expected_step "$step_id"; then
      printf 'pre-pr-gate: step-id %q is not one of the expected steps (%s)\n' "$step_id" "$EXPECTED_STEPS" >&2
      exit 1
    fi
    outcome="${3:-done}"
    # A real outcome routinely contains SPACES (e.g. "medium:+412-96,10f,code"), so it can't reuse
    # step_id's own [[:space:]] guard — only a TAB or newline actually corrupts the TSV sentinel (an
    # extra field, the same malformed-line failure mode this dir #144 fix exists to close for step_id).
    case "$outcome" in
      *[$'\t\n']*)
        printf 'pre-pr-gate: outcome %q contains a tab or newline — that would corrupt the sentinel'\''s tab-separated format. Re-run with a plain-text outcome (spaces are fine).\n' "$outcome" >&2
        exit 1
        ;;
    esac
    # dir #123: stamp polish.3-tests with its tree-relevant hash — see `_stamp_tests_outcome` above for
    # the trust-boundary rationale (never trusts a caller-supplied suffix).
    [ "$step_id" = "polish.3-tests" ] && outcome="$(_stamp_tests_outcome "$PWD" "$outcome")"
    # dir #236: stamp a skip-level polish.4-depth with the commit it was decided against — see
    # `_stamp_depth_outcome` above for the trust-boundary rationale.
    [ "$step_id" = "polish.4-depth" ] && outcome="$(_stamp_depth_outcome "$PWD" "$outcome")"
    require_active_receipt
    printf '%s\t%s\t%s\n' "$nonce" "$step_id" "$outcome" >> "$sentinel"
    # dir #63/Hole B: the real receipt landing IS the answer step 5(b) was waiting on — clear the
    # hand-off note rather than let it linger past the question it recorded.
    if [ "$step_id" = "polish.5-review" ]; then
      rm -f "$(handoff_path)"
      # dir #161: advisory-only, never affects this exit 0.
      _warn_dropped_addons "$receipt_key" "$outcome" "$PWD"
    fi
    exit 0
    ;;
  log)
    ty="${2:?pre-pr-gate: log <type> [detail] — type required}"
    detail="${3:-}"
    log_event "$ty" "$detail" "$PWD"
    exit 0
    ;;
  handoff)
    level="${2:?pre-pr-gate: handoff <level> <sha> — level required}"
    sha="${3:?pre-pr-gate: handoff <level> <sha> — sha required}"
    _require_receipt_key
    printf 'polish.5\t%s\t%s\n' "$level" "$sha" > "$(handoff_path)"
    exit 0
    ;;
  handoff-check)
    _require_receipt_key
    hp="$(handoff_path)"
    if [ -f "$hp" ]; then
      sha="$(git rev-parse HEAD 2>/dev/null)"
      line="$(awk -F'\t' -v sha="$sha" '$3==sha{print}' "$hp")"
      if [ -n "$line" ]; then printf '%s\n' "$line"; exit 0; fi
    fi
    exit 1
    ;;
  skill-trace)
    # PostToolUse(Skill), UserPromptExpansion(code-review) — dir #63 — SubagentStop(general-purpose)
    # — dir #70, the independent-agent-review leg — or PostToolUse(AskUserQuestion) — dir #88, the
    # step-5(a) review-reminder-dialog leg — hook. Never blocks or alters anything: silently no-ops
    # (exit 0) on anything it can't parse or that isn't a code-review invocation/review/dialog, since a
    # missed trace is a residual limit, not a false deny. One jq call for every field any of the four
    # legs needs — it fires on every Skill/slash-command/subagent-stop/AskUserQuestion event in every
    # session using this hook, so it's worth sparing the extra forks a call-per-leg would cost.
    # Joined with \x1f (NOT tab): bash `read` collapses an EMPTY field sitting between two tab
    # delimiters regardless of IFS (the same class of bug the keel-impact log parser hit) — real here,
    # since a UserPromptExpansion event has no `tool_name` field at all, and a SubagentStop event has
    # neither `tool_name` nor `command_name` — both empty fields sitting between populated ones.
    # `last_assistant_message` (SubagentStop only) is deliberately NOT one of these joined fields: `read`
    # stops at the first embedded newline regardless of what IFS is set to (IFS governs splitting WITHIN
    # a line, not the line terminator itself) — a real review write-up is virtually guaranteed to be
    # multi-line, so folding it into this join would silently truncate it to its first line, above the
    # marker line this hook actually needs to see. Fetched separately, below, only on that branch.
    command -v jq >/dev/null 2>&1 || exit 0
    st_input=$(cat 2>/dev/null)
    # `str` coerces every field to a plain string first — an unexpected shape (args as an object/array,
    # say) would otherwise make `join` throw and lose the WHOLE row, including the hook_event_name/skill
    # fields that were perfectly fine, turning one malformed field into total silence from this hook.
    IFS=$'\x1f' read -r st_event st_cwd st_tool st_skill st_level st_agent <<<"$(printf '%s' "$st_input" | jq -r '
      def str: if . == null then "" elif type == "string" then . else tostring end;
      [.hook_event_name, (.cwd|str), (.tool_name|str),
       (if .hook_event_name == "PostToolUse" then .tool_input.skill else .command_name end|str),
       (if .hook_event_name == "PostToolUse" then .tool_input.args else .command_args end|str),
       (.agent_type|str)
      ] | join("\u001f")' 2>/dev/null)"
    [ -n "$st_cwd" ] || st_cwd="$PWD"

    if [ "$st_event" = "SubagentStop" ]; then
      # dir #70: matcher "general-purpose" (install-pre-pr-gate.sh) already restricts which
      # SubagentStop events reach this hook at all — checked again here in case a broader matcher is
      # ever wired by hand (same double-check style as the PostToolUse/Skill leg below).
      [ "$st_agent" = "general-purpose" ] || exit 0
      st_msg="$(printf '%s' "$st_input" | jq -r '.last_assistant_message // ""' 2>/dev/null)"
      sa_level="$(printf '%s' "$st_msg" | grep -Eo "^KEEL-AGENT-REVIEW: level=(${ACCEPTED_REVIEW_LEVELS// /|})\$" | tail -n1)"
      sa_level="${sa_level#KEEL-AGENT-REVIEW: level=}"
      [ -n "$sa_level" ] || exit 0
      _append_trace_line "$st_cwd" "agent:$sa_level"
      exit 0
    fi

    if [ "$st_event" = "PostToolUse" ] && [ "$st_tool" = "AskUserQuestion" ]; then
      # dir #88: unlike the Skill/SubagentStop legs, the marker is searched for in the RAW event JSON
      # ($st_input), not a parsed field — the questions-array schema for a hook event is the one
      # unverified detail (see the dir #88 header section's TO VERIFY), so grepping the raw text makes
      # the exact field name non-load-bearing, the same defensive move dir #63's own TO-VERIFY-resolved
      # block already documents for a different field. No `^...$` line anchor: the marker sits embedded
      # inside a JSON string, not alone on its own line the way a subagent's plain-text final message is.
      # Correctness fix (found in the operator-run /code-review high pass on this ticket): capture the
      # FULL trailing word (greedy `[a-zA-Z0-9_-]+` — digits, underscore AND hyphen in the class:
      # dir #116's own reviews found `level=high2` truncating to a false-accepted `high` under a
      # letters-only class, `level=skip_x` under a letters-digits one, and `level=skip-waived` under a
      # hyphen-less one — hyphen being the one separator this file's own outcome vocabulary uses, so
      # exactly the string the receipt path rejects would have minted a trace), then
      # validate it against the exact accepted set with a
      # loop over $ACCEPTED_REVIEW_LEVELS — matching `(low|medium|high|max)` directly here would let
      # `grep -Eo`'s leftmost-longest match truncate a malformed `level=highest`/`level=maximum` down to
      # a false-accepted `high`/`max`, the same right-side-anchor gap the SubagentStop marker avoids with
      # its own `^...$` anchoring. A loop, not a `case` pattern list, deliberately: an unquoted `|`-joined
      # variable in a case pattern is matched as ONE literal glob string, not split into alternatives at
      # runtime — confirmed the hard way while building this fix, see $ACCEPTED_REVIEW_LEVELS's own comment.
      # dir #116: step 4's mandatory skip dialog carries its OWN `KEEL-DEPTH-DIALOG` skip marker
      # — never the review marker below. A distinct token keeps the namespaces mechanically separate:
      # a sizing dialog cannot pre-satisfy step 5(a)'s dir #88 check (its token never yields a
      # `dialog:<review-level>` line), and the review marker cannot vouch for a skip (skip stays out of
      # $ACCEPTED_REVIEW_LEVELS — the SubagentStop leg shares that set, and an agent review "at skip"
      # would vouch for no review at all). Only `skip` is accepted on this token, parsed by the SAME
      # extract-then-exact-compare idiom as the review token (one discipline, one word class); both
      # tokens converge on the same `dialog:<level>` trace shape, so the PASS-branch check reads them
      # uniformly. The two parses are INDEPENDENT, not exclusive — an event carrying both tokens writes
      # both lines. Exclusivity was the first cut and produced a real false-deny: a step 5(a) reminder
      # dialog merely QUOTING the depth token lost its own `dialog:<level>` line and denied a genuine
      # agent unlock. The residual this direction accepts instead — one deliberately dual-marked dialog
      # satisfying both checks — needs the model to compose both literals into one question against
      # commands/polish.md's explicit one-marker-per-dialog instructions: fabrication-class, not the
      # momentum-class miss these dialog checks exist to stop, and every dialog renders to the human.
      # Common case first: most AskUserQuestion events (step 4's own sizing dialog, ordinary clarifying
      # questions) carry NO marker — one builtin glob check keeps that dominant path fork-free.
      case "$st_input" in
        *KEEL-*-DIALOG:*) : ;;
        *) exit 0 ;;
      esac
      dpt_word="$(printf '%s' "$st_input" | grep -Eo 'KEEL-DEPTH-DIALOG: level=[a-zA-Z0-9_-]+' | tail -n1)"
      if [ "${dpt_word#KEEL-DEPTH-DIALOG: level=}" = "skip" ]; then
        _append_trace_line "$st_cwd" "dialog:skip"
      fi
      dlg_word="$(printf '%s' "$st_input" | grep -Eo 'KEEL-REVIEW-DIALOG: level=[a-zA-Z0-9_-]+' | tail -n1)"
      dlg_word="${dlg_word#KEEL-REVIEW-DIALOG: level=}"
      dlg_level=""
      for lvl in $ACCEPTED_REVIEW_LEVELS; do
        [ "$dlg_word" = "$lvl" ] && dlg_level="$lvl" && break
      done
      [ -n "$dlg_level" ] && _append_trace_line "$st_cwd" "dialog:$dlg_level"
      exit 0
    fi

    case "$st_event" in
      PostToolUse) [ "$st_tool" = "Skill" ] || exit 0 ;;
      UserPromptExpansion) ;;
      *) exit 0 ;;
    esac
    case "$st_skill" in
      code-review|*:code-review|/code-review) ;;
      *) exit 0 ;;
    esac
    _append_trace_line "$st_cwd" "$st_level"
    exit 0
    ;;
  rollout-check)
    # SessionStart hook (dir #64 tier 1) — see the dir #64 header section above. Never blocks; any
    # parse failure or missing jq is a silent no-op rather than a false warning.
    command -v jq >/dev/null 2>&1 || exit 0
    rc_input=$(cat 2>/dev/null)
    # One jq call for both fields (same rationale as skill-trace's own field-parsing above — this fires
    # on every session start, worth sparing the extra fork). \x1f: same bash-`read`-collapses-an-empty-
    # tab-delimited-field pitfall skill-trace already documents, so a missing `.model` can't shift `.cwd`
    # into the wrong variable.
    IFS=$'\x1f' read -r rc_model rc_cwd <<<"$(printf '%s' "$rc_input" | jq -r '[(.model // ""), (.cwd // "")] | join("\u001f")' 2>/dev/null)"
    [ -n "$rc_cwd" ] || rc_cwd="$PWD"
    rc_version="$(claude --version 2>/dev/null | head -n1)"
    rc_state="$(rollout_state_path "$rc_cwd")"
    rc_prev_model=""; rc_prev_version=""
    if [ -f "$rc_state" ]; then
      IFS=$'\x1f' read -r rc_prev_model rc_prev_version <<<"$(awk -F'\t' -v SEP=$'\x1f' '
        $1=="model"{m=$2} $1=="version"{v=$2} END{print m SEP v}
      ' "$rc_state" 2>/dev/null)"
    fi
    # Only compare a field when BOTH sides are known — an empty reading (jq/claude unavailable this
    # run, or a `model`-less SessionStart event) means "can't tell", not "changed".
    rc_changed=""
    if [ -n "$rc_model" ] && [ -n "$rc_prev_model" ] && [ "$rc_model" != "$rc_prev_model" ]; then
      rc_changed="model ($rc_prev_model -> $rc_model)"
    fi
    if [ -n "$rc_version" ] && [ -n "$rc_prev_version" ] && [ "$rc_version" != "$rc_prev_version" ]; then
      [ -n "$rc_changed" ] && rc_changed="$rc_changed, "
      rc_changed="${rc_changed}harness ($rc_prev_version -> $rc_version)"
    fi
    # Persist a field only when this run actually read it — an empty reading (e.g. a `model`-less
    # SessionStart event) must NOT clobber the last-known-good baseline with "", or the NEXT session's
    # genuine change would compare against an erased value and silently pass the "can't tell" guard
    # above (found in the operator-run /code-review high pass on this ticket).
    {
      printf 'model\t%s\n' "${rc_model:-$rc_prev_model}"
      printf 'version\t%s\n' "${rc_version:-$rc_prev_version}"
    } > "$rc_state"
    if [ -n "$rc_changed" ]; then
      log_event pipeline-drift "$rc_changed" "$rc_cwd"
      rc_msg="model/harness changed since last session ($rc_changed) - pipeline commands may have silently degraded; watch /polish step 5, consider tools/pipeline-canary.sh"
      # dir #96: jq-built like every other hook payload here — $rc_msg embeds `.model` from the event.
      # No permissionDecision, so the worst case was a dropped banner rather than a flipped decision;
      # but one interpolated payload left the rule "this file never printfs JSON" false, and a rule with
      # an exception is one a future edit copies the wrong half of.
      jq -cn --arg m "$rc_msg" '{systemMessage:$m}'
    fi
    exit 0
    ;;
  sweep)
    # dir #64 tier 2b — read-only /wrap-time floor, never blocks. Warns when the last K consecutive
    # receipt-pass rows in the impact log never carried any tag other than the self-reported one (any
    # independently verified tag counts, currently "trace-confirmed" and dir #70's "agent-confirmed") —
    # the pre-#63 blind spot: every recent /polish run closed on a self-reported review only — OR when
    # there are FEWER than K rows total and every one of them is unverified (a new/low-volume repo
    # shouldn't read as "fine" just because it hasn't accumulated K runs yet — found in the operator-run
    # /code-review high pass on this ticket). Not wired into any hook by design (a sweep needs to run
    # once per /wrap, not per gate decision) — invoking it is a manual follow-up.
    # Sanitized (dir #196 — see tools/lib/nonneg-int.sh): a non-numeric OR overflowing override falls
    # back to 3 rather than crashing a later comparison against this value.
    sw_k="$(sanitize_nonneg_int "${2:-3}" 3)"
    sw_log="$(resolve_impact_log "$PWD")"
    if [ -z "$sw_log" ] || [ ! -f "$sw_log" ]; then
      printf 'pre-pr-gate: sweep - no impact log found, nothing to check\n'
      exit 0
    fi
    # $5, not a regex over $4: the receipt-pass detail field ($4, `prov_label`) is HUMAN-DISPLAY prose;
    # $5 is the separate machine tag ("trace-confirmed"/"self-reported") the PASS branch now logs
    # alongside it, so a future rewording of the display text can't silently break this classification
    # (found in the same review pass — the tag/prose coupling was itself a finding).
    sw_result="$(awk -F'\t' -v k="$sw_k" '
      $2 == "receipt-pass" { rows[++n] = $5 }
      END {
        streak = 0
        for (i = n; i >= 1; i--) {
          # Any NON-EMPTY tag other than "self-reported" breaks the streak — testing the real
          # distinction (independently verifiable vs self-reported) rather than enumerating each
          # verified tag by name, so a future third verified tag (dir #70 added "agent-confirmed"
          # alongside "trace-confirmed" without needing to touch this line) is covered automatically
          # instead of silently reading as an unbroken self-reported-only streak until someone
          # remembers to list it here too. The empty-string exclusion matters on its own: $5 (prov_tag)
          # is a dir #64 addition — a `receipt-pass` row logged by a pre-dir-64 gate (real for any repo
          # that adopted the gate between dir #49 and dir #64) has no 5th field at all, and treating a
          # blank as "verified" would misclassify exactly the self-reported-only history this sweep
          # exists to catch (found in the operator-run /code-review high pass on this ticket).
          if (rows[i] != "" && rows[i] != "self-reported") break
          streak++
        }
        if (streak >= k) { print "WARN"; exit }
        if (n > 0 && streak == n) { print "WARN"; exit }
        print "OK"
      }
    ' "$sw_log")"
    if [ "$sw_result" = "WARN" ]; then
      printf 'pre-pr-gate: sweep - %s+ consecutive /polish runs closed without a verified code-review (self-reported only). Consider tools/pipeline-canary.sh or an operator-run /code-review.\n' "$sw_k"
      exit 1
    fi
    printf 'pre-pr-gate: sweep - recent runs look fine (a verified review within the last %s)\n' "$sw_k"
    exit 0
    ;;
esac

# --- hook mode: PreToolUse(Bash) on `gh pr create` -------------------------------------------------

# Needs jq to parse the hook event. Without it the gate cannot tell `gh pr create` from any other Bash
# command, so it allows rather than block EVERY command — an explicit, documented choice: this is a
# WORKFLOW gate (a /polish reminder), not the secret boundary (that's secret-guard, which needs no jq).
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fast-exit: only care about `gh pr create` in real command position (backlog dir #58 — replaces the
# earlier substring match, S6/backlog dir #4, which false-fired on any command merely CONTAINING the
# phrase: a KB write whose heredoc/quoted TEXT mentioned it, a commit message, a grep for the phrase
# itself). A small lexer over $cmd: strips heredoc bodies, strips quoted spans, splits on command
# separators (`;` `&` `|` `&&` `||` `(` `)` backtick, `$(`, newline), then per segment skips leading
# `VAR=value` assignments and `env`/`command` wrappers (incl. their own flags/assignments) and matches
# iff the first remaining token is exactly `gh`, followed later by `pr`, followed later by `create` —
# any tokens in between. That also closes the `gh --repo owner/name pr create` bypass (a global flag
# before the subcommand, no longer a residual gap) that the old substring match missed.
#
# A second command shape opens a PR without that subcommand at all: `gh api repos/O/R/pulls -f head=…`
# (found 2026-07-26 auditing the dir #57 rework — the natural reach once `gh pr create` is denied). It's
# matched when it is a genuine WRITE to a pulls collection: an endpoint ending in `/pulls` PLUS either
# an explicit `POST` or — absent any named method — a field/input flag, since gh itself defaults to POST
# once fields are supplied. An explicit method always wins over that inference, so `-X GET …/pulls -f
# state=open` (fields become query parameters on a GET) stays a read. Reads stay allowed on purpose —
# `.../pulls` with no write flag (list), `.../pulls/123` (one PR), `.../pulls/123/comments -f body=…`
# (commenting on an existing PR): this gate blocks OPENING a PR, not looking at or annotating one, and a
# gate that denies status checks teaches the next session to route around it. The branch is read out of
# `-f head=…` for the same dir #61 reason the `pr create` path reads `--head`.
#
# Still lexical, not a real shell parse: within this model it errs toward catching — an unstripped
# exotic heredoc form, or prose that happens to sit at a real command position, falls through as a
# false positive (an unneeded /polish reminder, not a bypass). Known accepted residuals (this is a
# WORKFLOW gate, not the secret boundary — that's secret-guard): `sh -c 'gh pr create'` / `eval "gh pr
# create"` (quoted → stripped, invisible to the lexer — a conscious regression from the old substring
# match, which DID catch these); `gh "pr" create` (quoting the bare subcommand splits it out of the
# token stream); a `gh` alias/wrapper-script rename; `env -u VAR gh pr create` (an `env` flag that
# takes its own separate value token, e.g. `-u VAR`, is not itself a flag or a `VAR=value` assignment,
# so the skip-loop stops on the value token instead of reaching `gh` — a flag-arity table to handle
# this generically is disproportionate for a workflow gate; the plain-prefix `VAR=value gh pr create`
# and `env VAR=value gh pr create` shapes above remain caught).
IFS= read -r -d '' PPG_AWK_PROG <<'PPG_AWK_EOF' || true
function flush_tok() {
  if (buf != "") { ntok++; tok[ntok] = buf; buf = "" }
}
function is_assign(t) {
  return (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/)
}
function check_segment(   i,j,k,found_pr,found_api,ep_pulls,writes,has_field,method) {
  i = 1
  while (i <= ntok) {
    if (is_assign(tok[i])) { i++; continue }
    if (tok[i] == "env" || tok[i] == "command") {
      i++
      while (i <= ntok && (substr(tok[i], 1, 1) == "-" || is_assign(tok[i]))) i++
      continue
    }
    break
  }
  if (i <= ntok && tok[i] == "gh") {
    # dir #63 sibling fix: `gh api repos/O/R/pulls -f head=…` creates a PR without ever using the
    # `pr create` subcommand, so the token scan below never saw it — the natural thing to reach for
    # once `gh pr create` is denied. Matched only when it's genuinely a WRITE to a pulls collection:
    # an endpoint ending in `/pulls` plus an explicit POST or any field/input flag. A plain
    # `gh api repos/O/R/pulls` (list) or `.../pulls/123` (read) stays allowed — this gate blocks
    # opening a PR, not looking at one.
    found_api = 0; ep_pulls = 0; has_field = 0; method = ""
    for (j = i + 1; j <= ntok; j++) {
      if (tok[j] == "api") found_api = 1
      else if (tok[j] ~ /(^|\/)pulls$/) ep_pulls = 1
      else if (tok[j] == "-X" || tok[j] == "--method") {
        if (j + 1 <= ntok) method = toupper(tok[j + 1])
      }
      else if (tok[j] ~ /^--method=/) { method = toupper(substr(tok[j], 10)) }
      else if (tok[j] == "-f" || tok[j] == "-F" || tok[j] == "--field" ||
               tok[j] == "--raw-field" || tok[j] == "--input") has_field = 1
    }
    # A field flag implies a write ONLY when no method was named — that's just gh's own default
    # (fields present ⇒ POST). An explicit method always wins: `-X GET … -f state=open` sends the
    # fields as query parameters and is a read, so inferring "write" from the flag alone would deny
    # exactly the listing this gate promises to leave alone.
    if (method != "") writes = (method == "POST")
    else writes = has_field
    if (found_api && ep_pulls && writes) {
      # Same purpose as the --head scan in the pr-create branch below (dir #61): name the branch the
      # PR is actually FOR, so the SHA check still resolves when the hook's event cwd isn't that
      # branch's own checkout. Here the branch arrives as a field, `-f head=branch`; a cross-fork
      # `head=owner:branch` carries an owner prefix that is not part of the ref.
      for (k = i + 1; k <= ntok; k++) {
        if (tok[k] ~ /^head=/) { head_out = substr(tok[k], 6); sub(/^[^:]*:/, "", head_out) }
      }
      matched = 1
      return
    }

    found_pr = 0
    for (j = i + 1; j <= ntok; j++) {
      if (!found_pr) {
        if (tok[j] == "pr") found_pr = 1
      } else if (tok[j] == "create") {
        matched = 1
        # dir #61: an explicit --head/-H names the branch the PR is actually FOR — the hook uses this
        # (instead of a bare HEAD) so the SHA check still works when the event cwd isn't that branch's
        # own checkout (e.g. `gh pr create --head <branch>` run from the main checkout's session root).
        for (k = i + 1; k <= ntok; k++) {
          if (tok[k] == "--head" || tok[k] == "-H") { if (k + 1 <= ntok) head_out = tok[k + 1] }
          else if (tok[k] ~ /^--head=/) { head_out = substr(tok[k], 8) }
        }
        return
      }
    }
  }
}
function end_segment() {
  flush_tok()
  if (ntok > 0) check_segment()
  ntok = 0
}
{
  line = $0
  if (in_hd) {
    check = line
    if (hd_strip) { while (substr(check, 1, 1) == "\t") check = substr(check, 2) }
    if (check == hd_delim) { in_hd = 0 }
    next
  }
  p = index(line, "<<")
  kept = line
  if (p > 0 && substr(line, p, 3) != "<<<") {
    rest = substr(line, p + 2)
    idx = 1
    strip = 0
    if (substr(rest, idx, 1) == "-") { strip = 1; idx++ }
    while (substr(rest, idx, 1) == " ") idx++
    q = substr(rest, idx, 1)
    quote = ""
    if (q == "'" || q == "\"") { quote = q; idx++ }
    start = idx
    rlen = length(rest)
    while (idx <= rlen) {
      c = substr(rest, idx, 1)
      if (quote != "") { if (c == quote) break } else { if (c == " " || c == "\t") break }
      idx++
    }
    delim = substr(rest, start, idx - start)
    if (delim != "") {
      if (quote != "") idx++
      # Only the "<<[-]DELIM" token itself is heredoc syntax — trailing same-line content (e.g. a
      # chained `&& real-command`) is NOT part of the heredoc and must stay in scope for scanning.
      kept = substr(line, 1, p - 1) substr(rest, idx)
      in_hd = 1; hd_delim = delim; hd_strip = strip
    }
  }
  n = length(kept)
  pos = 1
  while (pos <= n) {
    c = substr(kept, pos, 1)
    if (c == "\\") {
      if (pos < n) { buf = buf substr(kept, pos + 1, 1); pos += 2 } else { pos++ }
      continue
    }
    if (c == "'") {
      flush_tok(); pos++
      while (pos <= n && substr(kept, pos, 1) != "'") pos++
      pos++
      continue
    }
    if (c == "\"") {
      flush_tok(); pos++
      while (pos <= n) {
        cc = substr(kept, pos, 1)
        if (cc == "\\" && pos < n) { pos += 2; continue }
        if (cc == "\"") { pos++; break }
        pos++
      }
      continue
    }
    if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "`") {
      end_segment()
      pos++
      continue
    }
    if (c == " " || c == "\t") { flush_tok(); pos++; continue }
    buf = buf c
    pos++
  }
  end_segment()
}
END { if (matched) { print head_out; exit 0 }; exit 1 }
PPG_AWK_EOF

awk_out="$(awk "$PPG_AWK_PROG" <<< "$cmd")"
awk_status=$?
if [ "$awk_status" -ne 0 ]; then
  exit 0
fi
head_branch="$awk_out"

# dir #61: resolve the sentinel by the REPO's main checkout, not the raw event cwd — a receipt written
# from inside a worktree and a hook event reporting a different checkout of the same repo (the
# harness's tracked session-root cwd, which does not track an in-command `cd`) must land on one file.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
# dir #88 simplify pass: resolve the main-checkout top ONCE and derive $wt from it — `_dialog_leg_armed`
# (below, in the PASS branch) needs the full top path, not just its basename, and calling `_repo_key`
# alone here would discard it, forcing `_dialog_leg_armed` to re-fork `main_top_for` a second time for
# data this line already computed (dir #72 finding #7's own reuse-the-resolved-key discipline).
# dir #80: $sentinel is NOT set here (unlike dir #88's original single-line version) — it depends on
# the branch-aware receipt_key resolved further down, once resolved_branch is known.
main_top=$(main_top_for "$cwd")
wt=$(basename "$main_top")

deny() {
  # Impact instrumentation (metadata only, opt-in per repo): record that this guardrail fired so keel-impact
  # can auto-ingest it — deterministic, zero-token. Writes to the log file, never stdout (the hook's JSON
  # stays intact); with no log path resolved, nothing is written and the gate's behaviour is unchanged.
  log_event guard blocked "$cwd"
  # dir #96: build the JSON with jq, never `printf '%s'` into a quoted slot. Deny reasons interpolate
  # five values that reach this file as FREE TEXT through the documented `receipt <step-id> <outcome>`
  # CLI — the outcomes of steps 3, 4, 5 and 6, plus the resolved --head branch. (Steps 3 and 6 are
  # normally shas, but the load-bearing case is exactly when they are NOT.) Reproduced before this
  # fix: `receipt polish.3-tests 'x","permissionDecision":"allow","junk":"'` made the deny path emit
  # syntactically valid JSON whose LAST permissionDecision key was "allow", and every mainstream parser
  # (jq, Go, JS, Python) takes last-wins on a duplicate key. So the one deny this ticket exists to add
  # could be flipped by the very receipt value it names — no knowledge of the sentinel format needed,
  # i.e. strictly easier than the hand-written-sentinel residual this file already concedes. jq is
  # unconditionally available on every path that can reach here (hook mode exits early without it).
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# dir #80: resolve the branch this PR is actually FOR — same priority order as the --head-aware SHA
# check further down (dir #61), resolved here too since the sentinel/prev-sentinel key now needs it.
# (a) an explicit --head/-H (or `gh api -f head=`) already named it — strip a cross-fork owner prefix,
# same as the SHA check's own target_ref does. A malformed --head that strips to EMPTY (a bare
# "owner:" with nothing after the colon) denies immediately here rather than falling through to (b)
# — an explicit-but-broken --head must not be silently reinterpreted as "no --head was given at all"
# (found by this ticket's own /code-review high pass: a single blanket `[ -n "$x" ] || fallback`
# used to conflate the two, so a malformed --head could key onto the WRONG branch — cwd's own —
# instead of failing the way a bare `git rev-parse ""` used to fail closed before dir #80). (b) no
# --head at all → the event cwd's own current branch. (c) either path finding nothing — DENY naming
# the fix, rather than silently keying onto a wrong/empty branch. The message names the actual
# problem (branch resolution), not "run /polish again" — the old generic message sent the felt dir
# #80 incidents into 4-5 blind retries that never addressed the real cause.
if [ -n "$head_branch" ]; then
  resolved_branch="${head_branch##*:}"
  if [ -z "$resolved_branch" ]; then
    log_event receipt-deny "malformed-head" "$cwd"
    deny "Pre-PR gate: --head value '$head_branch' has no branch name after stripping the owner prefix — check the gh pr create invocation."
  fi
else
  resolved_branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"
  if [ -z "$resolved_branch" ]; then
    log_event receipt-deny "no-branch-resolved" "$cwd"
    deny "Pre-PR gate: could not resolve the PR branch from the event cwd — pass --head <branch> to gh pr create."
  fi
fi
receipt_key="$(_receipt_key_for "$wt" "$resolved_branch")"
sentinel="/tmp/pre-pr-gate-$receipt_key"

if [ ! -f "$sentinel" ]; then
  log_event receipt-deny "no-run" "$cwd"
  deny "Pre-PR gate: run /polish first (simplify + independent review + tests). The gate unlocks automatically when /polish completes cleanly."
fi

# Parse the receipt: line 1 must be the nonce header; every later line is <nonce>\t<step-id>\t<outcome>.
# Only lines whose nonce matches the header count toward completeness — a leftover line from an earlier
# run (different nonce) neither counts nor is silently accepted, so it surfaces as a replay, not a pass.
# dir #72 finding #6: `receipt --recover` (search `pnonce` above) implements the same nonce-header +
# last-write-wins-per-step idiom against the RETIRED sentinel — kept separate on purpose (this parser
# additionally needs `foreign[]`/MISSING/REPLAY bookkeeping that `--recover` has no use for); a receipt
# line FORMAT change needs the matching edit in both places.
result="$(awk -F'\t' -v steps="$EXPECTED_STEPS" -v SEP=$'\x1f' '
  BEGIN { n = split(steps, want, " "); for (i = 1; i <= n; i++) need[want[i]] = 1 }
  NR == 1 {
    if ($1 == "nonce" && $2 != "") { nonce = $2; next }
    malformed = 1; next
  }
  NF >= 3 {
    if (nonce != "" && $1 == nonce) { got[$2] = 1; val[$2] = $3 }
    else { foreign[$2] = 1 }
  }
  END {
    if (malformed || nonce == "") { print "MALFORMED" SEP; exit }
    missing = ""; replay = ""
    for (s in need) {
      if (!(s in got)) {
        missing = (missing == "" ? s : missing "," s)
        if (s in foreign) replay = (replay == "" ? s : replay "," s)
      }
    }
    if (missing == "") {
      print "PASS" SEP val["polish.8-unlock"] SEP val["polish.5-review"] SEP val["polish.4-depth"] SEP val["polish.6-retest"] SEP val["polish.3-tests"]; exit
    }
    if (replay != "") { print "REPLAY" SEP missing; exit }
    print "MISSING" SEP missing
  }
' "$sentinel")"

# \x1f (NOT tab) joins these fields: bash `read` collapses an EMPTY field sitting between two tab
# delimiters regardless of what IFS is set to (the same bug fixed in skill-trace, above) — a genuinely
# reachable shape here too (e.g. a malformed polish.8-unlock outcome), so use the same safe delimiter.
IFS=$'\x1f' read -r status detail review_outcome depth_outcome retest_outcome tests_outcome <<<"$result"

case "$status" in
  MALFORMED)
    retire_sentinel "$sentinel" "$cwd" "$receipt_key"
    log_event receipt-deny "malformed" "$cwd"
    deny "Pre-PR gate: receipt is malformed or empty (no nonce). Run /polish again."
    ;;
  MISSING)
    retire_sentinel "$sentinel" "$cwd" "$receipt_key"
    log_event receipt-deny "$detail" "$cwd"
    deny "Pre-PR gate: /polish did not complete — missing receipt for step(s): $detail. Run /polish again."
    ;;
  REPLAY)
    retire_sentinel "$sentinel" "$cwd" "$receipt_key"
    log_event receipt-replay-deny "$detail" "$cwd"
    deny "Pre-PR gate: receipt for step(s) $detail carries a stale nonce (replayed from an earlier run). Run /polish again."
    ;;
  PASS)
    # dir #61: an explicit --head/-H names the branch being PR'd — compare against ITS tip (a shared
    # ref, resolvable from any checkout of the repo) rather than assuming $cwd is that branch's own
    # checkout. No --head: unchanged, bare HEAD of $cwd (the pre-dir-#61 behaviour, still correct there).
    # dir #80: $resolved_branch already computed this (the owner-prefix-stripped --head, or the cwd's
    # own branch as a fallback) for the receipt key above — reuse it instead of re-deriving
    # ${head_branch##*:} a second time; "HEAD" only when --head was never given at all (head_branch
    # empty), matching the pre-dir-#61 behaviour exactly.
    target_ref="HEAD"
    [ -n "$head_branch" ] && target_ref="$resolved_branch"
    current_sha=$(git -C "$cwd" rev-parse "$target_ref" 2>/dev/null)
    if [ -z "$current_sha" ] || [ "$detail" != "$current_sha" ]; then
      retire_sentinel "$sentinel" "$cwd" "$receipt_key"
      log_event receipt-deny "sha-mismatch" "$cwd"
      deny "Pre-PR gate: sentinel is stale (HEAD changed since /polish ran, or a manual bypass was attempted). Run /polish again."
    fi
    # dir #133: every check above is against the LOCAL repo only — nothing confirms $current_sha was
    # ever pushed. A convergence-round commit made after the branch's last `git push` passes every one of
    # those local sha-binding checks and would open a PR that silently omits it (live-hit: dir #113/#114's
    # own PR, recovered via cherry-pick as PR #177 after the operator had already merged the truncated
    # one). This closes that remote-facing gap the checks above never covered: HEAD must be reachable from
    # the branch's actual push remote.
    #
    # dir #152 (found by an operator-run /code-review high on this ticket, promoted from a named-residual
    # comment to a real fix once it was reproduced live): a hardcoded `origin/$resolved_branch` is wrong
    # on two counts a real repo can hit, not just a hypothetical adopter-portability gap. (1) `gh pr
    # create` resolves its target repo from ANY configured remote, or an explicit `--repo`/`GH_REPO`, not
    # only one named `origin` — a fork-based workflow (`origin`=upstream, pushes go through `fork`) would
    # silently skip the check on every real invocation, reopening dir #113/#114 with no dishonesty
    # involved. (2) a genuine cross-fork PR (`gh pr create --head owner:branch`, dir #61's own supported
    # shape) pushes through the CONTRIBUTOR's own remote, which is routinely not named `origin` on the
    # machine that ran the push — reproduced live: `origin/$resolved_branch` doesn't exist there at all,
    # so the check false-denies with a "push the branch" message that is actively wrong (it WAS pushed,
    # just not to something named `origin`).
    #
    # Fix: prefer the LOCAL branch's own configured upstream (`<branch>@{upstream}`, set by `git push -u`
    # or `git branch --set-upstream-to`) over a hardcoded `origin` — git already knows which remote a
    # push actually went to, so ask it instead of guessing a name. Falls back to `origin/$resolved_branch`
    # only when no upstream is configured at all (a branch that was never pushed with tracking, or a
    # `git push` with no `-u` — the same shape the pre-fix behaviour already covered, so every existing
    # `origin`-only test keeps passing unchanged). Still skipped entirely — neither remote nor upstream
    # resolvable — only when the repo has NO remote at all: a real `gh pr create` invocation cannot exist
    # without one (`gh` refuses outright), so that arm is unreachable in production and exists solely so
    # a bare/offline test fixture isn't false-denied.
    #
    # **Residual still open, narrower than before:** a true cross-fork PR run from the BASE repo's own
    # checkout (not the contributor's fork clone) has no local upstream for a branch it never pushed at
    # all — that shape was already denied earlier, at the "sentinel is stale" sha-mismatch check at the
    # top of this PASS arm (since `current_sha` itself comes up empty), so it never reaches this check
    # either way; not a new gap this fix introduces. (Anchored by name, not by line number: the original
    # note said "line ~1607" and dir #123's later insert above shifted that check to ~1713 within the
    # same release tail — the exact stale-reference class this file's own comments keep catching.)
    push_remote_ref="$(git -C "$cwd" rev-parse --abbrev-ref --symbolic-full-name "$resolved_branch@{upstream}" 2>/dev/null)"
    push_remote_name="origin"
    [ -n "$push_remote_ref" ] && push_remote_name="${push_remote_ref%%/*}"
    [ -z "$push_remote_ref" ] && push_remote_ref="origin/$resolved_branch"
    if git -C "$cwd" remote get-url "$push_remote_name" >/dev/null 2>&1 &&
       ! git -C "$cwd" merge-base --is-ancestor "$current_sha" "$push_remote_ref" 2>/dev/null; then
      retire_sentinel "$sentinel" "$cwd" "$receipt_key"
      log_event receipt-deny "head-not-pushed" "$cwd"
      deny "Pre-PR gate: current HEAD ($current_sha) is not reachable on $push_remote_ref — push the branch (git push) before opening the PR."
    fi
    # dir #72 finding #1: `polish.6-retest` used to be a bare completion marker with NO value-level
    # check — unlike step 5 (trace-matched) and step 8 (sha-matched); dir #96 later sha-bound step 3
    # too, so the value-checked set is now 3, 5, 6, 8. Back then, a `receipt --recover`-restored
    # (pre-fix-commit) retest receipt could silently satisfy completeness for a fix-commit that was
    # never actually re-tested, the exact case step 6 exists to catch. Same shape as step 8's own check:
    # a genuine retest now records the sha it ran at, not a bare "done" — `skipped:*` (step 5 changed
    # nothing, so step 6 legitimately never ran) is exempt, same as step 8 has no equivalent skip but
    # step 6 always has.
    case "$retest_outcome" in
      skipped:*) : ;;
      "$current_sha") : ;;
      *)
        retire_sentinel "$sentinel" "$cwd" "$receipt_key"
        log_event receipt-deny "retest-sha-mismatch" "$cwd"
        deny "Pre-PR gate: step 6's retest receipt ('$retest_outcome') doesn't match current HEAD ($current_sha) and isn't a skip — the diff may have changed since tests last ran. Run /polish again."
        ;;
    esac
    # dir #96: THE test-binding check — the one invariant this gate exists to hold. Some run of the
    # test suite must be bound to the commit about to become a PR: step 3's own sha, or step 6's retest
    # sha. Either satisfies it; the two named waivers below are exempt, because the gate's job
    # is to stop a SILENT skip, not to overrule a stated decision.
    #
    # Why this is needed on TOP of step 6's check above: step 6 is legitimately exempt whenever step 5
    # changed no files (`skipped:*`), and in a convergence round that is the NORMAL outcome — the delta
    # re-review comes back clean. So the sequence "tests at sha1 → review finds a bug → fix commit
    # (sha2) → re-invoke → `receipt --recover` restores step 3 → step 6 skips" left NOTHING bound to
    # sha2, and the gate allowed a `gh pr create` for a commit no test had ever run against. Reproduced
    # end-to-end while filing this ticket, and observed live twice during dir #85's own session.
    #
    # Rejected alternative (the ticket's own first candidate): have `receipt --recover` refuse when
    # `base_sha == HEAD`. It cannot work — `retire_sentinel` stamps base-sha at retirement time, and
    # retirement happens inside `init`, i.e. AFTER the fix commit. So `base_sha == HEAD` in an ordinary
    # interrupted re-init AND in a genuine convergence round; the condition discriminates nothing and
    # would refuse every recovery. Verified in a sandbox before this fix was written.
    # (dir #236's skip-recovery narrowing, elsewhere in this file, superficially resembles this rejected
    # shape but isn't it: it compares current HEAD against a sha stamped at the ORIGINAL DECISION's own
    # write time — `receipt polish.4-depth skip`, which fires before any fix commit exists — never against
    # a retirement-time base-sha. That's the same discriminator dir #123 already uses for step 3's tree
    # hash, just applied to a plain sha instead. This note exists so a future reader doesn't read that
    # narrowing as "the rejected idea, shipped anyway.")
    #
    # The deeper point: the gate does not need to know WHETHER this is a convergence round. It needs to
    # know the shipped code was tested. Binding step 3 the same way steps 6 and 8 are bound removes the
    # need for a discriminator entirely — which is why commands/polish.md no longer claims that
    # `receipt --recover`'s own output tells a session which kind of round it is in.
    #
    # The waivers are two LITERALS, never the `skipped:*` class. Receipt outcomes are free text
    # (`outcome="${3:-done}"`), so a broad `skipped:*` would accept `skipped:tests-fail-unrelated` from
    # a session staring at a red suite — the exact silent skip this check exists to stop, and the same
    # unconditional-skip shape that made step 6 exempt and opened this hole in the first place. Only
    # `skipped:--no-test` (the operator's own flag) and `skipped:no-test-command` (a project that ships
    # no test command at all) waive it — see the arm below for why the second exists; anything else must
    # bind a sha.
    #
    # **Residual limit** (named rather than assumed away, same discipline as the dir #63/#70 sections
    # above): this binds a sha, not evidence. `$(git rev-parse HEAD)` costs nothing to type without
    # running anything, and unlike step 5 there is no trace leg behind step 3. It closes STALENESS —
    # a receipt that silently outlives the commit it was written for — not fabrication. Binding step 3
    # to a hook-written trace (a `PostToolUse(Bash)` leg matching the project's test command) is the
    # same escalation dir #63/#70 made for step 5 and is filed as its own ticket, not smuggled in here.
    # Two literal waivers, not a `skipped:*` class: the operator's own `--no-test`, and a project that
    # genuinely ships no test command (`skipped:no-test-command` — the same escape step 7 has had all
    # along as `skipped:no-doctor`). Without the second, a repo with no tests yet — an `/init-project`
    # scaffold, an early adopter — could never unlock the gate at all, and the deny would name causes
    # that are all wrong for it. Both are named literals so an invented reason still denies.
    #
    # dir #123: a THIRD way to satisfy this, on top of the exact-sha match and step 6's retest — a
    # `polish.3-tests` outcome carrying a `<sha>:<treehash>` suffix (stamped server-side at write time,
    # see the `receipt` case above) whose treehash still matches `$current_sha`'s OWN freshly-computed
    # `_test_relevant_tree_hash`. This is what lets `receipt --recover` carry a stale sha forward (dir
    # #96 used to block that outright, for exactly this check's absence) without reopening the silent-skip
    # hole: the comparison is two independently-computed digests, never a self-reported claim, so a commit
    # that actually touched a non-`.md` file will simply fail to match and fall through to the deny below
    # — a genuine code change can never accidentally qualify for the shortcut. `$tests_outcome` written
    # before this change (a bare sha, no colon) still satisfies the exact-match arm as before; nothing
    # about the pre-dir-#123 behavior regresses.
    tests_bound=0
    case "$tests_outcome" in
      "skipped:--no-test"|"skipped:no-test-command"|"$current_sha")
        tests_bound=1
        ;;
      *:*)
        # Cheap path first: every FRESH polish.3-tests write now carries this suffix (see the `receipt`
        # case above), so the ordinary same-commit case — tests ran on the exact commit that is still
        # HEAD — would otherwise fall through to a `git ls-tree`/`hash-object` pipeline on EVERY `gh pr
        # create` attempt just to re-derive what the stored sha already answers directly. Sha equality
        # alone proves the tree matches (it's the SAME commit); only a genuinely differing sha needs the
        # tree-hash comparison at all.
        if [ "${tests_outcome%%:*}" = "$current_sha" ]; then
          tests_bound=1
        else
          stored_treehash="${tests_outcome#*:}"
          # Exit status, not string emptiness (see _test_relevant_tree_hash's own comment) — a failed
          # recomputation here must never quietly compare equal to a stale stored hash.
          if [ -n "$stored_treehash" ] && current_treehash="$(_test_relevant_tree_hash "$cwd" "$current_sha")"; then
            [ "$stored_treehash" = "$current_treehash" ] && tests_bound=1
          fi
        fi
        ;;
    esac
    [ "$retest_outcome" = "$current_sha" ] && tests_bound=1
    if [ "$tests_bound" -eq 0 ]; then
      retire_sentinel "$sentinel" "$cwd" "$receipt_key"
      log_event receipt-deny "tests-sha-unbound" "$cwd"
      # Prescribe the one action that WORKS from here: retire_sentinel just ran, so there is no active
      # receipt to append to — telling the operator to `receipt polish.3-tests <sha>` would hand them a
      # command that answers "no active receipt". Every sibling deny in this branch says the same thing.
      deny "Pre-PR gate: no test suite run is bound to current HEAD ($current_sha) — step 3 recorded '$tests_outcome' (its tree-relevant hash, if any, no longer matches current HEAD's) and step 6 did not re-run here. Usual cause: a commit landed after the tests ran and touched a test-relevant file — not necessarily code: a .md file some test reads (e.g. CORE.md's sync check) counts too, only a .md file NO test references is exempt. If you just pulled Keel, an older copied commands/polish.md that writes a bare 'done' for step 3 causes this too — re-run install.sh. Run /polish again."
    fi
    # dir #63/Hole A: cross-check step 5's review outcome against step 4's OWN recorded depth — without
    # this, "skip"/"-operator-run"/"-waived" (the outcomes exempt from the trace check below) were
    # trusted unconditionally, so a session could size the diff `medium`, then write `polish.5-review
    # skip` regardless. ONE case statement below is the only place that knows the trusted-suffix set —
    # it strips the suffix (to compare against step 4's level), decides whether a trace is required,
    # decides whether the dir #88 dialog check applies (`$needs_dialog`: every `agent:*`-shaped
    # outcome — bare, or carrying any add-on set (dir #158) — the outcomes step 5(a)'s
    # reminder exists on — plus `skip` since dir #116, whose dialog is step 4's
    # own skip dialog instead), AND builds the dir #64 tier 2a provenance label +
    # tag (below) from the same match — dir #141 was exactly the "future third suffix" this comment
    # already anticipated, added here and nowhere else, as promised. $prov_tag is a STABLE machine value ("trace-confirmed"/
    # "self-reported") separate from $prov_label's human prose, so `sweep` (below) can classify without
    # depending on display wording (found in the operator-run /code-review high pass on this ticket —
    # sweep used to regex-match the prose directly).
    depth_level="${depth_outcome%%:*}"
    # dir #116 (operator-run /code-review high on this ticket): the level itself is now allowlisted.
    # Receipt outcomes are free text, and before this check an INVENTED level dodged every value check:
    # `polish.4-depth none:x` + `polish.5-review none-waived` matched each other, hit the trusted
    # `*-waived` arm, and unlocked with no review, no dialog, no trace — reproduced empirically; nested
    # suffixes (`skip-waived-waived`, whose outcome_level strips to `skip-waived`) rode the same hole
    # past the single-layer suffixed-skip deny below. Validating step 4's stripped level closes the
    # whole class in one place: the `outcome_level != depth_level` equality check below transitively
    # constrains step 5's level to the same set. `ultra` is a real depth here (the (b) hand-off path)
    # even though it never reaches the marker legs; `skip` is a real depth with its own dialog check.
    depth_level_ok=0
    for lvl in $ACCEPTED_REVIEW_LEVELS ultra skip; do
      [ "$depth_level" = "$lvl" ] && depth_level_ok=1 && break
    done
    if [ "$depth_level_ok" -eq 0 ]; then
      retire_sentinel "$sentinel" "$cwd" "$receipt_key"
      log_event receipt-deny "depth-level-invalid" "$cwd"
      deny "Pre-PR gate: step 4 recorded depth level '$depth_level', which is not one of the real depths (low/medium/high/max/ultra/skip) — an invented level cannot size a review. Run /polish again."
    fi
    trusted=0
    needs_dialog=0
    trace_match_outcome="$review_outcome"
    case "$review_outcome" in
      skip)             outcome_level="skip";                       trusted=1
                         # dir #116: needs_dialog here reads step 4's mandatory skip dialog (its
                         # `KEEL-DEPTH-DIALOG` skip marker), not step 5(a)'s reminder — skip is the one
                         # depth that bypasses step 5 outright, so that ANSWERED dialog is the only
                         # mechanical evidence the skip question was put to a human for THIS commit
                         # (the trace records the question's marker, not the chosen answer — reading
                         # the answer itself is dir #118). Per-SHA like the agent
                         # arms: a fix commit moves HEAD, and an inherited/re-asserted skip must not
                         # coast on the prior diff's answer. prov_label stays "self-reported": unarmed
                         # installs still pass with no dialog line, so the label describes the floor,
                         # not the best case.
                         needs_dialog=1
                         prov_label="review: skip";  prov_tag="self-reported" ;;
      *-operator-run)   outcome_level="${review_outcome%-operator-run}"; trusted=1
                         prov_label="review: $outcome_level, operator-run (self-reported)"; prov_tag="self-reported" ;;
      *-waived)         outcome_level="${review_outcome%-waived}";       trusted=1
                         prov_label="review: $outcome_level, waived (self-reported)"; prov_tag="self-reported" ;;
      agent:*+*)        # dir #81, generalized to a set by dir #158: the operator additionally ran `/code-review` ON TOP of an
                         # already-standing agent review — an honest combined record, not the old
                         # overwrite that erased the agent half. Placed BEFORE the broader `agent:*`
                         # glob below (case is first-match-wins and this literal also matches that
                         # pattern). The `+` separator (not `-`) is itself load-bearing, not cosmetic:
                         # a hyphenated `agent:<level>-operator-run` would instead match the EARLIER
                         # `*-operator-run)` arm above, which sets trusted=1 and skips the trace check
                         # below entirely — silently downgrading a real agent review + operator pass
                         # into a fully self-reported, untraced claim. Do not rename this to a hyphen
                         # for naming "consistency" with `<level>-operator-run` — that would reopen
                         # exactly this hole. trusted stays 0 here: the agent half is just as
                         # self-report-fabricable as the plain agent:* case, so it still needs the
                         # trace match below — but matched against the level WITHOUT the
                         # `+operator-run` suffix, since the SubagentStop trace (skill-trace, above)
                         # only ever writes the bare `agent:<level>` shape and knows nothing of a
                         # later operator pass. (`trace_match_outcome="agent:$outcome_level"` rather
                         # than its own independent suffix-strip: once outcome_level is stripped down
                         # to the bare level, re-composing the `agent:` prefix always reproduces the
                         # exact string the SubagentStop trace leg writes — true for every `agent:*`
                         # arm, found while simplifying dir #141's sibling arm below.)
                         #
                         # **dir #158 generalized this into a SET, and this is now the ONLY arm for any
                         # add-on combination.** Everything above still holds — it is why the separator is
                         # `+` and why `trusted` stays 0 — but the suffix is `<addon>[,<addon>…]`,
                         # validated element-wise by `_addon_label`, whose own header carries the why.
                         #
                         # An UNKNOWN add-on still denies, via the existing level cross-check rather than
                         # a deny of its own: the unrecognized token leaves $outcome_level as the raw
                         # remainder (`high+bogus`), which cannot equal step 4's level, so the
                         # `outcome_level != depth_level` check below rejects it — the same route that
                         # caught an invented suffix when these were two literal arms. No new bypass
                         # surface, and no deny message to keep in sync.
                         #
                         # $prov_label lists add-ons in the order the RECEIPT spelled them, not a
                         # canonical one — accepted: the label is human prose, every add-on is named
                         # either way, and `sweep` classifies on $prov_tag, which this doesn't touch.
                         outcome_level="${review_outcome#agent:}"
                         addons="${outcome_level#*+}"
                         # `_split_comma_set` (shared with `_normalize_addon_set`, dir #161's own
                         # /code-review high pass) does the no-word-split, no-glob comma walk — two
                         # earlier drafts of THIS walk each shipped a bug this shape avoids, both found
                         # by review: an `IFS=','` save/restore pair (whose `break` left IFS set inside a
                         # hook whose \x1f receipt read depends on it), then a `for a in ${addons//,/ }`
                         # split which — unquoted, and this script sets only `-u`, not `-f` — also ran
                         # PATHNAME EXPANSION on the set, i.e. a glob in a trust-boundary parse. Consuming
                         # it via `while read ... done < <(...)` (not a pipe) keeps `addons_ok`/
                         # `addon_prose` in THIS shell, not a subshell — `break` still works normally.
                         # The shared splitter yields an empty element too (`+,` or `+,,`), which reaches
                         # `_addon_label` as the empty string and is DENIED by its own `*)` arm below,
                         # where a word-split version would have silently produced zero elements and
                         # accepted the receipt — see the $addon_prose guard below.
                         addons_ok=1
                         addon_prose=""
                         while IFS= read -r a; do
                           p="$(_addon_label "$a")" || { addons_ok=0; break; }
                           addon_prose="$addon_prose + $p"
                         done < <(_split_comma_set "$addons")
                         # This guard is what rejects an empty SUFFIX (`agent:<level>+`) — the walk runs
                         # zero iterations there, so nothing else would. Against the current walk it is
                         # equivalent to `-n "$addons"`, but it is the right one to WRITE: it states the
                         # invariant ("at least one mechanism was actually named") where `-n "$addons"`
                         # states a proxy ("the suffix had some text"), so it still holds if the walk is
                         # ever loosened to skip empty elements rather than deny them. The proxy is what
                         # the pre-fix version used, and it accepted `agent:<level>+,` — a receipt
                         # announcing a combined outcome while naming zero mechanisms, printing the
                         # stronger `(trace-confirmed)` label on the bare arm's own evidence, reachable
                         # from one stray comma while re-typing an add-on from session memory (which dir
                         # #161 says is exactly what has to happen today).
                         # Which of this guard and the walk above rejects which shape, and which mutation
                         # reds which test: tests/test_pre_pr_gate.sh's 50m comment — measured there,
                         # stated once.
                         if [ "$addons_ok" -eq 1 ] && [ -n "$addon_prose" ]; then
                           outcome_level="${outcome_level%%+*}"
                         fi
                         trace_match_outcome="agent:$outcome_level"
                         needs_dialog=1
                         prov_label="review: $outcome_level, independent agent review (trace-confirmed)$addon_prose"; prov_tag="agent-confirmed" ;;
      agent:*)          # dir #70, re-scoped by dir #254: an independent Agent-tool subagent reviewed
                         # because the direct `Skill(code-review)` attempt was refused THIS run (the
                         # harness's blanket `disable-model-invocation` block has lifted — this is now
                         # the fallback branch, not the standing default) — trusted stays 0, same as the
                         # bare-level case below: this outcome is just as self-report-fabricable, so it
                         # earns no more trust and still needs the SubagentStop trace match (skill-trace,
                         # above).
                         outcome_level="${review_outcome#agent:}"
                         needs_dialog=1
                         prov_label="review: $outcome_level, independent agent review (Skill(code-review) invocation refused this run)"; prov_tag="agent-confirmed" ;;
      *)                outcome_level="$review_outcome"
                         prov_label="review: $outcome_level, trace-confirmed in-session"; prov_tag="trace-confirmed" ;;
    esac
    # dir #116 (found by this change's own review): `skip` is only ever a BARE outcome. There is no
    # review to waive, operator-run, or agent-run at skip — commands/polish.md's hand-off paths exist
    # only for real review levels — so any suffixed/prefixed route to outcome_level=skip is an invented
    # shape, not a hand-off result. Deny it outright rather than let a trusted-arm suffix dodge the
    # skip-dialog check below: reproduced in a sandbox, `skip-waived` + a matching `polish.4-depth
    # skip:*` unlocked an ARMED gate with no dialog ever answered, because `*-waived` sets trusted=1
    # and leaves needs_dialog=0 — the same unconditional-trust shape dir #96 closed for step 6.
    if [ "$outcome_level" = "skip" ] && [ "$review_outcome" != "skip" ]; then
      retire_sentinel "$sentinel" "$cwd" "$receipt_key"
      log_event receipt-deny "skip-suffixed-outcome" "$cwd"
      deny "Pre-PR gate: step 5 recorded '$review_outcome' — a suffixed 'skip' is not a valid outcome (skip has no review to waive or hand off; its only honest receipt is the bare 'skip', chosen via step 4's dialog). Run /polish again."
    fi
    if [ "$outcome_level" != "$depth_level" ]; then
      retire_sentinel "$sentinel" "$cwd" "$receipt_key"
      log_event receipt-deny "review-depth-mismatch" "$cwd"
      deny "Pre-PR gate: step 5's review outcome ('$review_outcome') doesn't match the depth step 4 recorded ('$depth_level'). Run /polish again."
    fi
    # A BARE review outcome (trusted=0 above: no -operator-run/-waived suffix, not skip) claims a real
    # in-session /code-review run — cross-check the mechanically-written trace (skill-trace, above) so
    # that claim can't be satisfied by self-report alone. The trace's OWN recorded level must match too
    # — otherwise a genuine `/code-review low` pass would vouch for a receipt claiming `max`. Trusted
    # outcomes need no trace — they already name a different, non-fabricable source (the human, or a
    # deliberate no-review choice) and are covered by the depth check above instead. $trace_match_outcome
    # is $review_outcome verbatim UNLESS the combined-outcome arm above overrode it
    # (any `agent:<level>+<addon>[,…]` set, dir #158) — the only shape where what's being
    # depth-checked and what's being trace-matched legitimately differ.
    if [ "$trusted" -eq 0 ]; then
      # dir #80: $wt here is deliberately still repo-only (not $receipt_key) — the trace stays
      # per-repo, see the dir #80 header section above. retire_sentinel below still gets
      # $receipt_key, though — that's the SENTINEL's own key (branch-aware), not the trace's.
      if ! _trace_has_line "$wt" "$current_sha" "$trace_match_outcome"; then
        retire_sentinel "$sentinel" "$cwd" "$receipt_key"
        log_event receipt-deny "review-trace-missing" "$cwd"
        deny "Pre-PR gate: step 5 recorded review outcome '$review_outcome', which claims a real review ran (an in-session /code-review pass, or an independent agent review) — but no trace matching both this commit AND that level was found. If the review mechanism was genuinely unavailable, /polish's hand-off should have produced an -operator-run/-waived outcome instead. Run /polish again."
      fi
    fi
    # dir #88: an `agent:*`-shaped outcome (bare `agent:<level>`, or carrying any add-on set,
    # `agent:<level>+<addon>[,<addon>…]` — dir #158 — the reminder fires
    # identically for all of them, `$needs_dialog` set by the SAME case statement above) additionally
    # requires a mechanically-traced, ANSWERED
    # AskUserQuestion dialog for step 5(a)'s MANDATORY reminder — the review claim itself can be
    # receipted honestly while that reminder is silently skipped by momentum (felt on dir #62/PR #147).
    # Armed only when the AskUserQuestion leg is actually wired (`_dialog_leg_armed`, above) — see the
    # dir #88 header section for why an unconditional check would false-deny every `agent:*` unlock
    # between `git pull` and the operator re-running the installer.
    if [ "$needs_dialog" -eq 1 ] && _dialog_leg_armed "$main_top"; then
      if ! _trace_has_line "$wt" "$current_sha" "dialog:$outcome_level"; then
        # dir #80: $receipt_key (branch-aware), not $wt (repo-only) — this retires the SENTINEL,
        # keyed the same way every other retire_sentinel call in this branch already is.
        retire_sentinel "$sentinel" "$cwd" "$receipt_key"
        # dir #116: skip's missing dialog is a DIFFERENT one than the agent arms' — step 4's own skip
        # dialog, not step 5(a)'s reminder. Named separately in both the log reason and the message so
        # a convergence round doesn't mis-read this as the dir #88 deny and go re-answer the wrong
        # dialog. An explicit if/else (not two deny calls relying on deny()'s own exit): the same
        # duplicate-JSON hazard the dir #96 comment in deny() documents would reappear the day deny
        # ever stopped being terminal.
        if [ "$outcome_level" = "skip" ]; then
          dlg_deny_reason="skip-dialog-missing"
          # This message must NEVER contain the matchable marker string itself (the token followed by
          # ': level=' and the word skip): a session recapping this deny inside an AskUserQuestion
          # would hand the hook exactly the line it greps for, and the deny would unlock itself —
          # reproduced end-to-end by the operator's third /code-review pass (DENY → dialog quoting
          # the deny → trace line → ALLOW). Same discipline as dir #88's deny, which describes its
          # marker without spelling it. A meta-test feeds this very message through the dialog leg
          # and asserts no trace is written.
          dlg_deny_msg="Pre-PR gate: step 5 recorded 'skip', but no step-4 skip dialog was answered for this commit — the confirm dialog's KEEL-DEPTH-DIALOG skip marker (spelled in polish.md step 4; if your step 4 doesn't mention the marker, your polish.md is a stale copy — re-run install.sh to refresh it) was never traced for current HEAD. An inherited or auto-selected skip doesn't count; a fix commit needs the skip dialog re-answered for ITS diff. Re-run step 4's confirm dialog for current HEAD, or size a real review. Run /polish again."
        else
          dlg_deny_reason="review-dialog-missing"
          dlg_deny_msg="Pre-PR gate: step 5's review outcome ('$review_outcome') is an independent-agent review, but step 5(a)'s MANDATORY reminder dialog was never opened/answered for this commit — re-open/answer that AskUserQuestion dialog for current HEAD (do not fall back to a plain -operator-run outcome, which would silently drop the agent review this dialog is about). Run /polish again."
        fi
        log_event receipt-deny "$dlg_deny_reason" "$cwd"
        deny "$dlg_deny_msg"
      fi
    fi
    # dir #64 tier 2a: $prov_label/$prov_tag were already built above (the same case statement dir #63's
    # cross-check uses) — visible at PR-creation time instead of only via transcript archaeology. The
    # logged detail carries BOTH, tab-joined ($4 = prov_label prose, $5 = prov_tag) — `sweep` reads $5,
    # never $4, so it never depends on the display wording.
    retire_sentinel "$sentinel" "$cwd" "$receipt_key"
    log_event receipt-pass "$prov_label"$'\t'"$prov_tag" "$cwd"
    # Same jq-built payload as deny() above — $prov_label is derived from step 5's free-text outcome.
    jq -cn --arg r "$prov_label" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r},systemMessage:$r}'
    exit 0
    ;;
esac

# Fail-safe: any unrecognized status denies rather than silently allowing.
retire_sentinel "$sentinel" "$cwd" "$receipt_key"
deny "Pre-PR gate: could not verify the receipt. Run /polish again."
