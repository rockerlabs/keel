#!/usr/bin/env bash
# test_release_management_doc.sh — dir #367: docs/release-management.md is the procedure for running a
# release with one manager session and gated worker sessions, sitting in the gap between
# docs/delegation.md (read-only subagent fan-out) and docs/parallel-sessions.md (N-session safety
# mechanics); commands/manage-release.md is its thin, /go-sized entrypoint. Same idiom as
# test_drydock_doc.sh and test_delta_audit_doc.sh (fixed-string pins on BOTH legs of a naming
# coupling, so a rename on either side strands the citation loudly instead of silently) — the family
# shape the ticket's own binding test names: the command names the doc, the doc names the command
# back, and the doc carries anchors for R4, R6 and R7 (the three requirements most likely to be
# silently dropped in a rewrite).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="$REPO_ROOT/docs/release-management.md"
cmd="$REPO_ROOT/commands/manage-release.md"
delegation="$REPO_ROOT/docs/delegation.md"
go_cmd="$REPO_ROOT/commands/go.md"
checklist="$REPO_ROOT/docs/publishing-checklist.md"

check_file "docs/release-management.md exists" "$doc"
check_file "commands/manage-release.md exists" "$cmd"

# --- the mutual-reference pair: command names the doc, doc names the command back ------------------
pin "commands/manage-release.md names docs/release-management.md" \
  "$cmd" '](../docs/release-management.md)' \
  "expected the entrypoint to point at the doc it is a thin wrapper over"
pin "docs/release-management.md names commands/manage-release.md back" \
  "$doc" '](../commands/manage-release.md)' \
  "expected the doc to name its own entrypoint, per the drydock/delta-audit mutual-reference precedent"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ----------------
pin "docs/reference.md Docs index links docs/release-management.md" \
  "$REPO_ROOT/docs/reference.md" '[`docs/release-management.md`](release-management.md)' \
  "expected docs/reference.md's Docs index to list the new doc the way it lists drydock.md/delta-audit.md"

# --- the family cross-links: sits in the gap, cited on all three legs ------------------------------
pin "release-management.md links delegation.md" "$doc" '](delegation.md)' \
  "expected the doc to name the read-only fan-out sibling it is NOT an instance of"
pin "release-management.md links parallel-sessions.md" "$doc" '](parallel-sessions.md)' \
  "expected the doc to name the N-session safety-mechanics sibling"
pin "delegation.md links release-management.md back" "$delegation" '](release-management.md)' \
  "expected delegation.md's See-also to point at the doc that sits in its own stated gap"

# --- the binding test's own three required anchors: R4, R6, R7 -------------------------------------
pin "R4 anchor: two-way critique, verbatim from the record" \
  "$doc" '## R4 — two-way critique, verbatim from the record' \
  "expected a named R4 section — the requirement most likely to be silently dropped in a rewrite"
pin "R4 states the canonical set -e approval warning" \
  "$doc" 'was in the APPROVAL, not the information, and a' \
  "expected the dir #349 case to survive compression as the canonical warning"
pin "R6 anchor: transport is a requirement set, never a tool" \
  "$doc" '## R6 — transport is a requirement set, never a tool' \
  "expected a named R6 section"
pin "R6 never names a specific transport tool" \
  "$doc" '**never by naming a specific product**' \
  "expected R6 to keep the never-name-a-tool rule explicit, not just implied by omission"
pin "R7 anchor: the cost line" \
  "$doc" '## R7 — the cost line' \
  "expected a named R7 section"
pin "R7 states cost is unmeasured/a real trade, not a free win" \
  "$doc" 'not a free win' \
  "expected R7 to preserve the overridden gate's own unmeasured-cost caveat, not just the requirement to record one"

# --- R6's own felt addition: queued is not processed, countered by a per-amendment ACK requirement
# (a live crossed-message incident from this very release's own build) -----------------------------
pin "R6 states queued is not processed" "$doc" \
  'Queued is not processed, and this needs its own' \
  "expected R6 to name this as its own countermeasure, distinct from the turn-discipline style rule"
pin "R6 requires a per-amendment ACK" "$doc" \
  'explicit **per-amendment ACK**' \
  "expected R6 to state the concrete countermeasure, not just describe the failure mode"
pin "R6's ACK requirement treats an un-acked amendment as undelivered" "$doc" \
  'treat any brief amendment without an acknowledgment from its recipient as undelivered' \
  "expected the operative rule, not just the incident description"

# --- operator-decided requirement: R3's post-launch model/effort verify step, folded in after the
# original build (an operator-decided requirement is exactly the class this binding test exists to
# keep from being silently dropped in a later rewrite) ----------------------------------------------
pin "R3 states the post-launch model/effort verify step is required, not advisory" "$doc" \
  'This is required, not advisory' \
  "expected R3 to state the operator-decided post-launch verify step as a hard requirement"
pin "R3's verify step folds into the existing one-health-line-per-launch report" "$doc" \
  'fold `actual vs. rec` into the same one health-line' \
  "expected the verify step to cost zero extra messages, per the operator's own rationale"
pin "R3 states the delta-audit inheritance-by-pointer clause" "$doc" \
  'with no separate edit needed on that surface' \
  "expected R3 to say a sibling procedure citing this R3 by pointer inherits the verify step, so nobody later duplicates the rule into it"

# --- the other numbered requirements, so a wholesale drop of one doesn't pass silently --------------
for r in \
  "## R1 — intake is bodies plus re-verification, not headings" \
  "## R2 — wave plan by file overlap, merges serialized" \
  "## R3 — worker launches, soft form" \
  "## R5 — verify against pushed commits, never a worker's working tree" \
  "## R8 — single writer to \`BACKLOG.md\` during the release" \
  "## R9 — close checklist" \
  "## R10 — the seams duty, active not passive" \
  "## R11 — bounded loops everywhere" \
  "## R12 — portability" \
  "## R13 — the wrap is centralized"
do
  pin "requirement heading present: ${r#\#\# }" "$doc" "$r" \
    "expected every numbered requirement (R1-R13) to survive compression as its own heading"
done

# --- R10 is the manager's one irreducible job — the doc must say so, not just number it -------------
pin "R10 states it is the manager's one irreducible job" "$doc" \
  "This is the manager's one irreducible job" \
  "expected the seams duty to be marked as load-bearing, not just listed as one requirement among many"

# --- R3's soft-form cross-edit into delegation.md, named not silent --------------------------------
pin "delegation.md's Mutator row carries the R3 soft-form override" "$delegation" \
  "Named override (\`dir #367\`'s R3 soft form)" \
  "expected a named override, never a silent contradiction between the two docs"

# --- R8's cross-edit into commands/go.md's claim step, named not silent ----------------------------
pin "go.md's claim step carries the R8 managed-release override" "$go_cmd" \
  "inside a managed release (\`dir #367\` R8)" \
  "expected go.md's claim step to name the managed-release exception explicitly"
pin "go.md still states the standalone claim step is its own default" "$go_cmd" \
  "This step as written is the standalone" \
  "expected go.md to disambiguate which of the two rules applies when"

# --- R9's cross-edit into publishing-checklist.md §4, named not silent -----------------------------
check_absent "publishing-checklist.md no longer claims curation is human by nature" \
  "$(cat "$checklist")" 'the curation is still human by nature'
pin "publishing-checklist.md §4 carries the R9 agent-composed wording" "$checklist" \
  'composing the notes is agent-composed at this step,' \
  "expected the exact reversal wording dir #367 specifies"
pin "publishing-checklist.md §4 cites dir #367 for the reversal" "$checklist" \
  '(`dir #367` — reversing this line' \
  "expected a named override, not a silent rewording of the earlier claim"
pin "publishing-checklist.md §4 still marks the felt incidents as unchanged" "$checklist" \
  "v0.6.1's blank release" \
  "expected the felt-incident WHY of the timing rule to survive the wording fix"

# --- the worker-brief shape (Handed-to-you item 4's fold-in) is a named, findable section ------------
pin "the worker-brief section exists and is named" "$doc" \
  '## The worker brief — one shape, whether launched or handed over' \
  "expected the five-part brief shape (state/slate/leads/rules/handed-to-you) to be a section, not buried prose"
for field in "State — re-derive" "Leads, not findings" "Handed to you"; do
  pin "worker-brief shape names '$field'" "$doc" "$field" \
    "expected the brief shape's own fields to be individually findable"
done

# --- naming-collision acknowledgment: plain text, no backticked slash-command form (dir #385's own
# felt incident — a backtick-wrapped /keel-* citation trips doctor.sh's dir #129 dead-reference check)
# Read each file once (not once per check below) — both are re-checked three times in this span.
doc_body="$(cat "$doc")"
cmd_body="$(cat "$cmd")"
check_contains "docs/release-management.md acknowledges the collision alias" "$doc_body" "keel-manage-release"
check_contains "commands/manage-release.md acknowledges the collision alias" "$cmd_body" "keel-manage-release"
check_absent "docs/release-management.md never backtick-wraps the collision alias as a slash command" \
  "$doc_body" '`/keel-manage-release`'
check_absent "commands/manage-release.md never backtick-wraps the collision alias as a slash command" \
  "$cmd_body" '`/keel-manage-release`'

# --- portability: no keel-only absolute paths, the shipped → <version> convention named --------------
check_absent "release-management.md carries no absolute keel-checkout path" "$doc_body" '/Users/'
check_absent "manage-release.md carries no absolute keel-checkout path" "$cmd_body" '/Users/'
pin "release-management.md names the → <version> heading-tag convention" "$doc" \
  '`→ <version>` tag' \
  "expected R12 to name the portable release-slate convention, not keel's own release-plan table"
pin "manage-release.md resolves the release the portable way" "$cmd" \
  '`→ <version>` tag' \
  "expected M1 to resolve the version against the shipped convention, not a keel-only table"

# --- the entrypoint stays thin: a pointer-and-checklist, not a second copy of the procedure ----------
pin "manage-release.md states it is a pointer, never a restatement" "$cmd" \
  'never a restatement' \
  "expected the same never-a-restatement framing commands/delta-audit.md uses for its own doc"

# --- R6's second felt addition (v0.8.3 fixer launch): identity at first contact ----------------------
pin "R6 carries the identity-at-first-contact rule" "$doc" \
  'Identity at first contact' \
  "expected R6 to say how a worker verifies the session claiming to be its manager"
pin "R6 points at delegation.md for the generic identity rule" "$doc" \
  'next to the post-launch model-verify rule it mirrors' \
  "expected R6 to instantiate the generic rule the way R3 does, not carry a second copy"
pin "delegation.md carries the generic identity-at-first-contact rule" "$delegation" \
  'identity at first contact' \
  "expected the launch-time requirement to live where the model-verify rule lives"
pin "delegation.md's identity rule requires addresses copied verbatim, never retyped" "$delegation" \
  'copied verbatim from the tool' \
  "expected the rule to bind the address source, since a retyped address is what the incident was"
pin "delegation.md states a worker's refusal on unverifiable identity is correct" "$delegation" \
  'refusal to proceed on an unverifiable identity' \
  "expected the rule to protect the worker's stop condition rather than train it away"

# --- dir #455 / dir #596: the un-set default's direction and the install step ------------------------
pin "delegation.md states which way the un-set worker tier falls" "$delegation" \
  'the silent direction is the expensive one' \
  "expected the launch-time rule to name the default's direction (dir #455)"
pin "delegation.md orders the verify sources, running tier before metadata" "$delegation" \
  'session metadata last (it reports what is configured)' \
  "expected the verify-source order to put metadata last (dir #455)"
pin "delegation.md states the hello-then-hold launch" "$delegation" \
  'the launch holds' \
  "expected the hello-then-wait-for-go hold (dir #455)"
pin "R3 points at the default direction and the hold" "$doc" \
  'which way the un-set default falls' \
  "expected R3 to inherit the dir #455 clause by pointer"
pin "R9 owes an install block where the build has a daily-use location" "$doc" \
  'installs the build from' \
  "expected R9 to carry the dir #596 install step"
pin "M8 lists install next to tag, publish" "$cmd" \
  'tag, publish, and install' \
  "expected M8's hand-over sentence to name install (dir #596)"

# --- dir #616: the CI-wait rule rides in the worker brief beside the keep-alive contract ---------------------
pin "R-brief item 4 carries the bounded one-backgrounded-command CI-wait rule" "$doc" \
  'wait in ONE backgrounded command with a timeout' \
  "expected the worker-brief section to carry the CI-wait rule (dir #616)"
pin "the CI-wait rule names the Claude Code tools it forbids" "$doc" \
  '`ScheduleWakeup` (for loop mode only) and `Monitor`' \
  "expected the harness-scoped tool names"
pin "docs/token-economy.md owns the cost reason for waiting" "$REPO_ROOT/docs/token-economy.md" \
  'Waiting on external state is the same edge.' \
  "expected token-economy to own the cost reason for the CI-wait rule (dir #616)"

# --- dir #732: R3 names BOTH launch paths and what each verifies; the command agrees with R13 -------------------
pin "R3 names the direct launch that presets model and effort" "$doc" \
  'A direct launch (`start_session`) takes a `model` and an `effort`' \
  "expected R3 to say a direct launch presets the worker's tier (dir #732)"
pin "R3 names the hand-off path where the operator sets the tier" "$doc" \
  'task chip or any hand-off the operator starts' \
  "expected R3 to name the manual-gesture path beside the direct one (dir #732)"
pin "R3 says each path is verified against what is RUNNING" "$doc" \
  'verifies what is actually running' \
  "expected R3 to require the running-tier check on both paths (dir #732)"
check_absent "R3 no longer says the manager cannot preset the tier" "$doc_body" 'it cannot preset it'
check_absent "delegation.md no longer says a launcher cannot preset the tier" "$(cat "$delegation")" 'not something a launcher can preset'
pin "delegation.md's launch-time rule names both paths" "$delegation" \
  'A direct launch (`start_session`) can preset' \
  "expected the delegation.md cross-reference to agree with R3 (dir #732)"

pin "manage-release.md says workers carry the R13 marker" "$cmd" \
  'carries the `WRAP CENTRALIZED (R13)` marker' \
  "expected the closing paragraph to agree with R13 (dir #732)"
check_absent "manage-release.md no longer says workers carry the DELEGATION RUN line" "$cmd_body" 'DOES carry that line'
check_absent "manage-release.md M9 no longer asks for a 'structured event-count block'" "$cmd_body" 'structured event-count block'
pin "manage-release.md M9 asks for cited events in the scoring tool's shape" "$cmd" \
  'tools/keel-impact.sh shape' \
  "expected M9 to point at the shape verb (dir #732)"

pin "R13 names the shipped one-event shape verb" "$doc" \
  '`tools/keel-impact.sh shape`' \
  "expected R13's one-cited-event paragraph to name the shipped verb (dir #732)"
pin "R13 names the session attribution flag" "$doc" \
  'add --session <worker id>' \
  "expected R13 to say each worker's score is attributed to its session (dir #732)"
check_absent "R13 no longer names dir #732 as a pending remover" "$doc_body" 'its remover is `dir #732`'

# --- dir #744 A6 / B8: the wave-plan prose qualifies "every PR collides in CHANGELOG.md" ------------------
pin "R2 qualifies the CHANGELOG collision assumption with changelog fragments" "$doc" \
  'unless the project keeps changelog fragments' \
  "expected R2 to say the collision assumption holds unless the project keeps changelog fragments (dir #744)"
pin "R2 still says merges serialize, and why (strict up-to-date)" "$doc" 'serialize as a consequence (strict up-to-date still forces it)' \
  "expected R2 to keep the serialization consequence"
pin "manage-release M3 qualifies the CHANGELOG collision assumption with changelog fragments" "$cmd" \
  'unless the project keeps changelog fragments' \
  "expected M3 to carry the same qualifier as R2 (dir #744)"
pin "manage-release M3 still says merges serialize, and why (strict up-to-date)" "$cmd" 'merges serialize as a consequence (strict up-to-date still forces it)' \
  "expected M3 to keep the serialization consequence"

# --- dir #760: practice corrections from the 0.15.0 run and the 0.16.0 ledger, each at its requirement ------
pin "R2 prices sequential merges under strict up-to-date" "$doc" \
  '**Strict up-to-date makes every sequential merge cost' \
  "expected R2 to say a strict up-to-date base makes N merges cost N Update-branch plus CI cycles (dir #760)"
pin "R2 names the integration PR and the train" "$doc" \
  '**An integration PR or a train lands several clean PRs' \
  "expected R2 to say how a multi-PR landing is built, who starts its session, and R5 on every head (dir #760)"
pin "R2 applies R5 to every constituent head" "$doc" \
  '**R5 holds for every constituent**' \
  "expected R2 to apply the pushed-head rule to each PR merged into a train (dir #760)"
pin "R2 names the Update-branch versus worker-rebase race" "$doc" \
  "**The operator's Update branch and a worker's rebase race" \
  "expected R2 to say a REBASE starts with a fetch and a head compare (dir #760)"
pin "R3 requires a launch on an operator-started turn" "$doc" \
  '**A launch needs a turn the operator started' \
  "expected R3 to say the harness refuses a launch on a worker-started turn, and the shapes that work (dir #760)"
pin "R6 budgets cross-session sends" "$doc" \
  '**Budget the cross-session sends' \
  "expected R6 to carry the per-operator-turn send cap and the batching rule (dir #760)"
pin "R6 treats a manager change as a re-identification" "$doc" \
  '**A manager change is a re-identification' \
  "expected R6 to carry the handover rule: the shared brief's manager id, one line per live worker (dir #760)"
pin "R7 points at the shipped weights override" "$doc" \
  '`KEEL_TOKENS_WEIGHTS`' \
  "expected R7 to name the tool and the override that sum the actual at the estimate's weights (dir #760)"
pin "R8 requires a checked writer for filings, not only markers" "$doc" \
  '**The single writer needs a checked writer' \
  "expected R8 to carry the truncation incident and the read-temp-refuse-to-shrink-rename rule (dir #760)"
check_absent "R8 no longer limits the routing rule to marker writes" "$doc_body" 'marker writes route through the manager instead'
pin "manage-release.md M4 routes every backlog write through the manager" "$cmd" \
  'backlog writes of any kind' \
  "expected M4 to agree with go.md's step 6 override, which covers any backlog entry (dir #760)"
pin "R9 states the stacked cut PR and its restated GO conditions" "$doc" \
  '**The cut PR can ride on the last fix PR' \
  "expected R9 to carry the stacked-cut shape and what it changes for the GO conditions (dir #760)"
pin "R10 requires a seam plan to name both merge orders" "$doc" \
  '**A seam plan names its resolution in BOTH merge orders' \
  "expected R10 to say the operator may merge out of the proposed order (dir #760)"
pin "R10 names a repo-wide check landing mid-wave as a seam" "$doc" \
  '**A repo-wide check landing mid-wave' \
  "expected R10 to say a new lint reddens in-flight PRs at Update-branch and must be announced (dir #760)"
pin "R10 says which seam shapes the per-PR Seams step leaves manual" "$doc" \
  "**The worker's Seams step covers less than the manager's duty does" \
  "expected R10 to name the two shapes dir #668's step leaves manual (dir #760)"
pin "R11 says the sweep is load-bearing" "$doc" \
  '**The sweep is load-bearing' \
  "expected R11 to carry the wedge record and the late-timer rule (dir #760)"
pin "R11 says a worker's own stop needs a named blocker" "$doc" \
  "**A worker's own stop needs a named blocker" \
  "expected R11 to say a long review loop is not a reason to stop (dir #760)"
pin "R11 treats suite concurrency as a budget" "$doc" \
  '**Suite concurrency is a budget too' \
  "expected R11 to carry the per-worker concurrency cap (dir #760)"
pin "R11 keeps branch cleanup out of a running wave" "$doc" \
  '**No branch cleanup while a wave runs' \
  "expected R11 to carry the ref-canary false-trip rule (dir #760)"
pin "R11 settles a stop that waits for the operator at wave-plan time" "$doc" \
  '**A stop that waits for the operator is settled at wave-plan time' \
  "expected R11 to carry the compaction-stop rule (dir #760)"

# --- dir #810: the cut's re-derivation is no longer "an observation no ticket owns yet" --------------------------
if grep -qF 'an observation no ticket' "$doc"; then
  fail "release-management.md no longer calls the cut re-derivation an observation no ticket owns (dir #810)" \
    "the phrase 'an observation no ticket' is still in the doc"
else
  pass "release-management.md no longer calls the cut re-derivation an observation no ticket owns (dir #810)"
fi
pin "release-management.md names tools/self/changelog-claims.sh at the cut (dir #810)" "$doc" \
  'changelog-claims.sh' \
  "expected the Roles brief's figure paragraph to name the claim lint"

# --- dir #811 S1 (A1, A2): R14 — the release train, and the merge; the manager merges where the policy allows --------
# A section is cut by awk into a variable, then matched with a here-string (no producer piped into a `grep -q`: the
# dir #280 SIGPIPE race). A needle must sit on ONE line of the doc (`pin` is a line-mode `grep -F`).
r14="$(awk '/^## R14 /{f=1} /^## What this pattern deliberately is not/{f=0} f' "$doc")"
r2="$(awk '/^## R2 /{f=1} /^## R3 /{f=0} f' "$doc")"
r9="$(awk '/^## R9 /{f=1} /^## R10 /{f=0} f' "$doc")"
operator_row="$(grep -F '| **Operator** |' "$doc" || true)"
m8="$(awk '/^\*\*M8 /{f=1} /^\*\*M9 /{f=0} f' "$cmd")"
m7a="$(awk '/^\*\*M7a /{f=1} /^\*\*M8 /{f=0} f' "$cmd")"

pin "R14 anchor: the release train, and the merge" "$doc" '## R14 — the release train, and the merge' \
  "expected a named R14 section after R13 (dir #811)"
check_contains "the Operator row exists (the negative pin below is not vacuous)" "$operator_row" '| **Operator** |'
check_contains "R14 adds the policy line last, after the floor is in place" "$r14" 'only after that floor is in place'
r14flat="$(tr '\n' ' ' <<< "$r14" | tr -s ' ')"
check_contains "R14's intake report lists the merge modes in precedence order" "$r14flat" 'the first that applies of `merges: operator (no policy line)`, `merges: operator (deny in place)` or `merges: manager (deny lifted)`'
check_contains "R14: a gate absent or not wired is a setup defect, never a fallback case" "$r14flat" 'absent or not wired'
check_contains "R14: a refusal the gate actually issues stays the fallback's case (2)" "$r14flat" "a refusal the gate actually issues stays the fallback's case (2)"
check_contains "R14: the floor's end-to-end check is stopped by the gate itself, not the harness" "$r14flat" 'is stopped by the gate itself, with the gate'\''s reason, and not by the harness'
check_contains "R14: the floor's end-to-end check uses a PR number that does not exist" "$r14flat" 'the check must use a PR number that does not exist, since a missing floor lets it merge'
check_contains "R14: only the manager's own missing --merge or head pin is fixed and retried once" "$r14flat" 'the manager'\''s own missing `--merge` or head pin is not this case: it is fixed and retried once per PR, and a second denial is this case'
check_contains "R14: the gate's denials include a missing --merge" "$r14flat" '`--merge` is missing, or the head pin is not a full sha'
check_contains "R14's fallback names the harness denial still in place" "$r14flat" 'a harness denial still in place'
check_contains "Operator row names the train's review depth" "$operator_row" 'the review depth of a train'
check_absent "Operator row no longer carries the merge, in any wording (merges, merging, merge queue)" "$operator_row" 'merg'
check_contains "Operator row states the class rule (a touchpoint is a decision)" "$operator_row" 'a different answer changes what happens next'
check_contains "R9 hands the merge to the manager under R14" "$r9" "merges are the manager's under R14"
check_absent "R9 no longer lists the merge queue as an operator hand-over" "$r9" 'a merge queue, the tag'
check_contains "R9 keeps the paste-ready merge block as R14's fallback" "$r9" "only as R14's fallback"
check_contains "R2 lands a wave's ready PRs as one train" "$r2" 'land as one train (R14)'
check_absent "R2 no longer hands the train's merge to the operator" "$r2" 'And the operator merges it with a merge commit'
for needle in 'no more pushes; ok' '--match-head-commit' 'merge-tree' '--no-ff' 'git merge-base --is-ancestor' \
  'KEEL-MANAGER-MERGES' 'HELD' 'never force-push'; do
  check_contains "R14 carries: $needle" "$r14" "$needle"
done
for needle in 'MERGED #N as' 'REFUSED #N' 'DIALOG train k' 'ALWAYS opens the dialog' 'update-branch' \
  'merges: manager (deny lifted)' 'merges: operator (no policy line)' "the operator's standing decision" \
  'first GitHub refusal' 'never routed around' 'HELD #N' 'resolved by the LATER PR'; do
  check_contains "R14 carries: $needle" "$r14" "$needle"
done
check_absent "R14 names no merge queue (dir #784 closed: keel enables none)" "$r14" 'merge queue'
for needle in 'release-train.sh build' 'release-train.sh body' 'release-train.sh check' 'build --continue'; do
  check_contains "R14 names the train tool (dir #811 S3): $needle" "$r14" "$needle"
done
check_contains "manage-release has the M7a step naming R14" "$m7a" 'R14'
check_contains "M8 hands over tag, publish and install, not the merge" "$m8" 'tag, publish, and install'
check_absent "M8 no longer lists the merge among the hand-over actions" "$m8" 'merge, tag, publish, and install'
check_contains "M8 points at R14 for the merge" "$m8" 'R14'
pin "polish-guide Step 4 points at R14's train dialog carve-out" "$REPO_ROOT/commands/polish-guide.md" \
  'A release train always asks' "expected Step 4 to carry the one pointer sentence to R14 (dir #811 B8d)"

summary
