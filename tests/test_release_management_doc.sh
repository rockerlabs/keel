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
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/release-management.md"
cmd="$REPO_ROOT/commands/manage-release.md"
delegation="$REPO_ROOT/docs/delegation.md"
go_cmd="$REPO_ROOT/commands/go.md"
checklist="$REPO_ROOT/docs/publishing-checklist.md"
readme="$REPO_ROOT/README.md"

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
pin "README Docs section links docs/release-management.md" \
  "$readme" '[`docs/release-management.md`](docs/release-management.md)' \
  "expected the Docs section to list the new doc the way it lists drydock.md/delta-audit.md"

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
for f in "$doc" "$cmd"; do
  check_contains "$(basename "$f") acknowledges the collision alias" "$(cat "$f")" "keel-manage-release"
done
check_absent "docs/release-management.md never backtick-wraps the collision alias as a slash command" \
  "$(cat "$doc")" '`/keel-manage-release`'
check_absent "commands/manage-release.md never backtick-wraps the collision alias as a slash command" \
  "$(cat "$cmd")" '`/keel-manage-release`'

# --- portability: no keel-only absolute paths, the shipped → <version> convention named --------------
check_absent "release-management.md carries no absolute keel-checkout path" \
  "$(cat "$doc")" '/Users/'
check_absent "manage-release.md carries no absolute keel-checkout path" \
  "$(cat "$cmd")" '/Users/'
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

summary
