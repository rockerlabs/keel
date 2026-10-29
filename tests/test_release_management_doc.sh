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
  'wait in ONE backgrounded command and let its completion notify you' \
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

# --- dir #844: the sentence says what the verification block is checked for, not a re-derivation it never had ---
if grep -qF 'the verification block is not,' "$doc" || grep -qF 'the split-off ticket, dir #844' "$doc"; then
  fail "release-management.md does not promise a verification-block re-derivation that no tool performs (dir #844)" \
    "the 'is not, yet' / 'split-off ticket' promise is back in the doc"
else
  pass "release-management.md does not promise a verification-block re-derivation that no tool performs (dir #844)"
fi
pin "release-management.md states the verification block is hand-written, no tool re-derives its figures (dir #844)" "$doc" \
  'The verification block is hand-written and no tool re-derives its figures:' \
  "expected the Roles brief's figure paragraph to say what is actually checked of the block"

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

# --- dir #826 #827 #828 #832 #823: the release-management riders --------------------------------------------------
check_absent "the CI-wait rule no longer says 'with a timeout' (it invites GNU timeout on macOS; dir #826, dir #828)" "$doc_body" 'ONE backgrounded command with a timeout'
pin "the CI-wait rule names the missing macOS timeout binary" "$doc" \
  'never wrap it in `timeout`' \
  "expected the brief's CI-wait line to say background the watch itself (dir #826 item 6, dir #828 (a))"
pin "R1 reads a ticket as its whole block" "$doc" \
  '**A body is the whole block, not the heading line.**' \
  "expected R1 to name the block read (dir #827 item 3)"
pin "R3 names the launch gate as who opened the turn" "$doc" \
  '**The gate keys on who opened the turn' \
  "expected R3 to say a peer-opened turn is refused even with the operator's decision inside it, and to queue a proposal card (dir #826 item 1)"
pin "R3 gives the verify's read: the log by branch, quote second, metadata last" "$doc" \
  "**The verify's read, at the hello and before GO,**" \
  "expected R3 to carry the single model-verify order (dir #826 item 4, dir #827 item 2, dir #823 items 1-2)"
pin "the brief carries the same-turn rule beside the CI-wait rule" "$doc" \
  '**Include the same-turn rule beside them** (dir #832)' \
  "expected the worker brief to carry the checkpoint-in-the-opening-turn rule (dir #832)"
pin "the pre-flight checklist is read from the CI workflow at brief time" "$doc" \
  '**The checklist is read from the CI workflow at brief time' \
  "expected the fix-round pre-flight to derive from the workflow file (dir #826 item 5)"
pin "R6's ACK gates a merge" "$doc" \
  '**The ACK gates a merge too (dir #823):**' \
  "expected R6 to compare the spec's mtime with the worker's start before a merge is released (dir #823 item 7)"
pin "R6's manager change re-verifies tooling claims" "$doc" \
  '**The incoming manager also re-verifies the' \
  "expected R6 to require a probe of the hand-off's tooling and environment claims (dir #828 (c))"
pin "R9 points an audit-heavy worker at R11's stop route" "$doc" \
  '**An audit-heavy worker reaches' \
  "expected R9 to name the compaction stop at the fix loop and R11's route (dir #828 (b))"
pin "R9 names the version-identity bump's owner" "$doc" \
  '**The version-identity bump has a named owner' \
  "expected R9 to say who carries the bump (dir #823 item 4)"
pin "R11's observed-state clause names the turn-end-without-deliverable trigger" "$doc" \
  '**A turn-end note without its deliverable is a probe trigger (dir #832).**' \
  "expected R11 to make a turn-end note without its deliverable a probe trigger (dir #832)"
pin "R14's fallback gives every reported PR one of two shapes" "$doc" \
  '**In the fallback, every PR the manager reports carries exactly one of two shapes' \
  "expected R14's fallback to carry the ready-block-or-do-not-merge rule (dir #826 item 3, dir #827 item 1)"
deleg_flat="$(tr '\n' ' ' < "$delegation" | tr -s ' ')"
check_contains "delegation.md's verify order names the log as the arbiter of a disagreement (dir #826 item 4)" "$deleg_flat" \
  'a disagreement between them is an observation with two alternatives, settled by the log (find it by branch'
check_contains "delegation.md's hold step checks the tier by rule (1)'s order" "$deleg_flat" "the launcher checks the tier by rule (1)'s order"
pin "delta-audit.md's Fixer brief rows carry an executable acceptance check" "$REPO_ROOT/docs/delta-audit.md" \
  '**A Fixer'"'"'s brief is rows of finding plus an executable acceptance check' \
  "expected delta-audit.md to carry the fix-batch brief shape (dir #826 item 2)"

# the rules' bodies, not only their headings (a heading pin stays green when the paragraph is rewritten)
pin "R3's gate paragraph queues a refused launch as a proposal card" "$doc" \
  'can make on its own is one made on a turn the operator opened' \
  "expected R3 to say which launches the manager makes itself (dir #826 item 1)"
pin "R3's verify follows delegation.md's order: running tier, trailer, metadata last" "$doc" \
  "follows \`docs/delegation.md\`'s order: running-tier evidence" \
  "expected R3's verify read to point at delegation.md's order, not a third one (dir #826 item 4)"
pin "R3's verify settles a disagreement by the log, never against the worker" "$doc" \
  'recorded with both and settled by the log, never a finding against the worker' \
  "expected R3 to treat a quote/metadata disagreement as an observation (dir #823 item 1)"
pin "R6's merge ACK is named by R14's precondition (c)" "$doc" \
  'and so does a spec amendment the worker has not ACKed (R6)' \
  "expected R14 (c) to carry the amendment-ACK hold (dir #823 item 7)"
pin "R6's ACK paragraph names R14's precondition (c)" "$doc" \
  "(R14's precondition (c) names this check)" \
  "expected R6's ACK clause to point back at R14 (c) (dir #823 item 7)"
pin "R14's fallback reports a bare status line as neither shape" "$doc" \
  'neither shape and is not sent' \
  "expected the fallback to refuse a bare status report (dir #827 item 1)"
pin "the CI-wait rule says to background the watch itself" "$doc" \
  'so background the watch itself and never wrap it in' \
  "expected the CI-wait line to give the portable instruction (dir #828 (a))"

# --- dir #866 A6: R9 and M8 carry the release-record entry rule (the cut PR carries the entry; the suite gates it) ----
r9="$(awk '/^## R9 — close checklist/{f=1;next} /^## /{f=0} f' "$doc")"
check_contains "R9 names the suite check that gates the release-record entry in the cut PR (dir #866)" "$r9" "test_release_history.sh"
m8="$(awk '/^\*\*M8 — close checklist \(R9\)\.\*\*/{p=1} p&&/^$/{exit} p' "$cmd")"
check_contains "M8 names the release-record entry the cut PR carries (dir #866)" "$m8" "release-history"

# --- dir #860: a context budget for a release (B1 workers' threshold, B2 clear per ticket, B3 manager hand-over, B4 the close) ----
# Each check_contains / check_absent runs over the section or paragraph FLATTENED (newlines -> spaces, runs squeezed; lib.sh's
# para_of), so a phrase that wraps a line is found, and a dropped clause is not passed vacuously by a raw-line check (A2).
r3flat="$(section_body '## R3 — worker launches, soft form' "$doc" | tr '\n' ' ' | tr -s ' ')"
r6flat="$(section_body '## R6 — transport is a requirement set, never a tool' "$doc" | tr '\n' ' ' | tr -s ' ')"
r7flat="$(section_body '## R7 — the cost line' "$doc" | tr '\n' ' ' | tr -s ' ')"
b1_needle='**The release runs at the default compaction threshold'
b2_needle='**Clear an idle finished worker before its next ticket'
pin "R11 states the release runs at the default compaction threshold (dir #860 A1)" "$doc" "$b1_needle" \
  "expected R11 to carry the workers' threshold rule: the default, and only the operator names another"
b1="$(para_of "$doc" "$b1_needle")"
check_contains "R11 B1 names the keel default 250000 (A1)" "$b1" '250000'
check_contains "R11 B1: the manager does not ask for or set an override (A1)" "$b1" 'does not ask for or set'
check_contains "R11 B1: a named value is recorded as a positive integer (A1)" "$b1" 'positive integer'
check_contains "R11 B1: a named value reaches live workers as a one-line pointer (A1)" "$b1" 'one-line pointer'
check_contains "R11 B1: a worker with no send left waits for the operator's next turn (A1)" "$b1" "waits for the operator's next turn"
pin "R11 keeps the threshold the operator's decision, never the manager's (dir #860 A7)" "$doc" \
  "The threshold and any override are the operator's decision" \
  "expected R11 to keep the sentence F1's pick rests on: only the operator names another value"
pin "R3 says to clear an idle finished worker before its next ticket (dir #860 A2)" "$doc" "$b2_needle" \
  "expected R3 to carry the cleared-context-per-ticket rule"
b2="$(para_of "$doc" "$b2_needle")"
check_contains "R3 B2 defines finished as frozen (A2)" "$b2" 'frozen'
check_contains "R3 B2 handles a PR unfrozen after its author's clear by a new freeze (A2)" "$b2" 'new freeze'
check_contains "R3 B2 keeps the refusal fallback for a pinned or open session (A2)" "$b2" 'pinned or open on screen'
check_contains "R3 B2 clears the session first, before any hand-out (A2)" "$b2" 'clears that session first'
check_contains "R3 B2 never hands the ticket to the warm session (A2)" "$b2" 'never to the warm session'
check_contains "R3 B2: with no send left the clear and the message go together (A2)" "$b2" 'the clear and the message go together'
check_contains "R3 B2: past the hand-over threshold a queued launch is out (A2)" "$b2" 'a queued launch is out'
check_absent "R3 no longer says a follow-up message keeps the worker's context (dir #860 A2)" "$r3flat" 'keeps its context'
pin "R6 says the manager hands over at 600k tokens of context (dir #860 A3)" "$doc" \
  '**The manager hands over at 600k tokens of context' \
  "expected R6 to carry the manager's hand-over threshold"
check_contains "R6 B3 reads the manager's own context with the workers' reader at 600000 (A3)" "$r6flat" 'KEEL_POLISH_COMPACT_TOKENS=600000 tools/token-report.sh --context'
check_contains "R6 B3: on verdict compact the manager launches nothing new (A3)" "$r6flat" 'launches nothing new'
check_contains "R6 B3: an unknown reading is named once and the full window stays the trigger (A3)" "$r6flat" 'context: unknown'
pin "R7 records the context budget the run held (dir #860 A4)" "$doc" \
  '**Beside the figure, record the context budget the run held' \
  "expected R7 to record the thresholds and how often each fired, so a moved cost line can be split from a moved budget"
check_contains "R7 B4 counts the compaction stops (A4)" "$r7flat" 'compaction stops'
pin "manage-release.md M4 clears an idle finished worker before its next ticket (dir #860 A6)" "$cmd" \
  'clear an idle finished worker' \
  "expected M4 to carry B2: the manager acts from the M-items"
pin "manage-release.md M7 reads the manager's own context against the hand-over threshold (dir #860 A6)" "$cmd" \
  'hand-over threshold (R6)' \
  "expected M7 to carry B3: the manager acts from the M-items"

# --- dir #871: R11's review-round cap, the counting rules, the stop line and the brief's item 4 -----------------------
# Needles are checked on the flattened doc (`flatten_ws`), because `pin` is a line-mode `grep -F`
# and these clauses wrap; the rule needles are scoped to their own paragraph, so a rule that moved or was dropped
# from it is not passed by the same words elsewhere.
docflat="$(flatten_ws < "$doc")"
# count_of TEXT NEEDLE — occurrences of NEEDLE in TEXT. awk `index()` loop: busybox `grep -oF` reports only the first
# match on a one-line text, so the flattened doc cannot be counted with it, and a bash `${t//n/}` is quadratic on it.
count_of() { printf '%s' "$1" | NEEDLE="$2" awk '{ s = $0; n = ENVIRON["NEEDLE"]; while ((i = index(s, n)) > 0) { c++; s = substr(s, i + length(n)) } } END { print c + 0 }'; }
cap_head='**A review loop has a cap, and reaching it is the operator'"'"'s call (dir #871).**'
count_head='**What counts as a round toward the cap (dir #871).**'
rounds_line='ROUNDS <token> <PR or branch> — <that round'"'"'s trend line>'
check_eq "R11 carries the review-round cap paragraph once (dir #871 A1)" 1 "$(count_of "$docflat" "$cap_head")"
check_eq "R11 carries the what-counts-as-a-round paragraph once (dir #871 A1)" 1 "$(count_of "$docflat" "$count_head")"
check_eq "the ROUNDS stop line appears twice, in R11 and in the brief's item 4 (dir #871 A2)" \
  2 "$(count_of "$docflat" "$rounds_line")"
for n in '**Include the review-round cap beside them** (R11, dir #871)' \
  'this replaces `/polish`'"'"'s own two-round budget and residual exit' \
  'a review forced by a rebase or merge of the default branch' \
  'or a fresh reviewer for a lost one, is the same round'; do
  check_eq "the brief's item 4 carries: $n (dir #871 A3)" 1 "$(count_of "$docflat" "$n")"
done
check_contains "R11's bound list names the release's review-round cap (dir #871 A4)" "$docflat" \
  "max review/fix rounds per PR (the release's review-round cap, below)"
check_absent "R11's bound list no longer defers the round bound to the project's own convention (dir #871 A4)" \
  "$docflat" "per your project's own round-budget convention"
check_contains "the wave-plan paragraph names the review-round stop as its one exception (dir #871 A4)" "$docflat" \
  "(the review-round stop above is the one exception, asked per PR)"
cap_para="$(para_of "$doc" "$cap_head")"
count_para="$(para_of "$doc" "$count_head")"
for n in "keel's wave plans name five" "replaces the project's own round budget and its residual exit" \
  "the loop's budget precondition is \`/polish\`'s own context check at entry" \
  "whose verdict under \`FRAMEWORK.md\`'s stop rule is \`MERGE\`" "standing in for that rule's two-round ceiling" \
  "Before the cap a worker still stops only on a named blocker" "at or past the cap is the stop" \
  "fixes nothing more, commits nothing" "no background watch is needed" "logs the line in the ledger" \
  "never settled in advance at the wave plan" "more rounds (its cap rises" "fixes that round's findings first" \
  "the residual exit (\`/polish\` step 5's own" "counts as converged for R14's readiness" "the branch is kept" \
  "as one message under R6's budget, in the order the stops came" "while no send is left (R6)" \
  "the manager names the wait in its health line" "does not clear a waiting worker"; do
  check_contains "the cap paragraph carries: $n (dir #871 A5)" "$cap_para" "$n"
done
for n in "a full re-review included" "a clean full re-review never converges the loop" \
  "the worker goes on with a delta round" "or a fresh reviewer spawned because the last one was lost, is the same round" \
  "adds no round" "Four kinds of review count only when they find something serious" \
  "the review of the one commit that fixes the remaining findings" \
  "forced by a rebase or merge of the default branch" "leaves a converged loop converged" \
  "in at most one commit" "named in the PR body, not fixed" "measured on top of dir #860's context budget"; do
  check_contains "the counting paragraph carries: $n (dir #871 A5)" "$count_para" "$n"
done

# --- dir #862: a manager launched with --agent reads as a subagent to the merge rule ----------------
pin "R14 says to launch the manager without --agent (dir #862)" "$doc" \
  'launches the manager without `--agent`, because the merge rule reads a main session started with `--agent` as a subagent and refuses its merge' \
  "expected R14 to carry the launch-without---agent sentence (dir #862; the gate header tools/pre-pr-gate.sh says the same)"
pin "M7a says a --agent manager cannot merge and points at R14 (dir #862)" "$cmd" \
  'A manager launched with `--agent` cannot merge, since the merge rule reads that session as a subagent; launch it without `--agent` (R14).' \
  "expected M7a to carry the launch-without---agent sentence, pointing at R14 (dir #862)"

summary
