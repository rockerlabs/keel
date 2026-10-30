#!/usr/bin/env bash
# test_cloud_doc.sh — dir #900 slice 2 (A7): pins docs/cloud.md, the rulebook of the cloud route, and the
# places that point at it — commands/backlog.md's headline-discipline block, docs/release-management.md R1/R2/R3,
# commands/manage-release.md M2/M3/M4, docs/delegation.md's named override, docs/grooming.md's gap-fill, and the
# discoverability rows (docs/reference.md, README.md, ADAPTING.md). The doc is read through a flattened copy
# (line breaks and runs of blanks become one space), so a pin survives re-wrapping but not a changed word.
# Reads ${KEEL_CLOUD_DOC:-docs/cloud.md} and ${KEEL_BACKLOG_MD:-commands/backlog.md}, so a mutation is shown red
# by re-invoking THIS file against a scratch copy — no tracked file is edited to prove a case.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="${KEEL_CLOUD_DOC:-$REPO_ROOT/docs/cloud.md}"
backlog_md="${KEEL_BACKLOG_MD:-$REPO_ROOT/commands/backlog.md}"
rm_doc="$REPO_ROOT/docs/release-management.md"
mr_cmd="$REPO_ROOT/commands/manage-release.md"
deleg_doc="$REPO_ROOT/docs/delegation.md"
groom_doc="$REPO_ROOT/docs/grooming.md"

SCRATCH_COPY_PREFIX="cloud-doc-copy"
MUTATION_SCRIPT="$REPO_ROOT/tests/test_cloud_doc.sh"
MUTATION_SKIP_VAR="KEEL_CLOUD_DOC_TEST_SKIP_MUTATIONS"

check_file "docs/cloud.md exists" "$doc"
check_file "commands/backlog.md exists" "$backlog_md"

# flat FILE — the file as one line, runs of whitespace collapsed to one space.
flat() { tr '\n' ' ' < "$1" | sed -E 's/[[:space:]]+/ /g'; }
# section FILE START_ERE END_ERE — the lines from the first match of START up to (not including) the next
# match of END, flattened.
section() { awk -v s="$2" -v e="$3" '$0 ~ s && !on { on = 1; print; next } on && $0 ~ e { exit } on' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g'; }
# has LABEL HAYSTACK NEEDLE — a fixed-string containment check on already-flattened text.
has() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected: $3" ;;
  esac
}

doc_flat="$(flat "$doc")"

# --- the B4 table: each row exactly once as a table row, its decisive clause inside THAT row ----------------
row_text() { awk -v id="$1" 'index($0, "| " id " |") == 1' "$doc"; }
check_row() { # ID CLAUSE
  local id="$1" clause="$2" n text
  n="$(row_text "$id" | grep -c '')"
  if [ "$n" -ne 1 ]; then
    fail "(A7) eligibility row $id appears exactly once as a table row" "found $n rows"
    return
  fi
  pass "(A7) eligibility row $id appears exactly once as a table row"
  text="$(row_text "$id")"
  has "(A7) row $id carries its decisive clause" "$text" "$clause"
}
check_row G1  'default-branch name outside `[A-Za-z0-9._/+-]` is refused here too'
check_row G1b '`enforcement_level`'
check_row G1c 'No CI is refused before any credit is spent'
check_row G2  '`📐` beside R0–R2 is refused'
check_row G2b 'no verdict needs `--eligible`'
check_row G3  'the rails file when it is gitignored'
check_row G3b 'or travels in the brief'
check_row G4  'runs on an Ubuntu VM with no key, device or live account'
check_row G5  'A slate ticket may run as a cloud worker'
check_row G6  'Linux caps one argument at 131071 bytes'
check_row G7  'a symlink'
check_row G8  '"Question for a /design pass" in the body, "for the design" (case-insensitive) on the `**Model rec:**` line'
check_row G9  '`--dispatch` only'

# --- the verdict, the opt-in and who dispatches -------------------------------------------------------------
has "(A7) B2: the yes line form" "$doc_flat" '**Cloud:** yes (YYYY-MM-DD, <who>)'
has "(A7) B2: the no line form" "$doc_flat" '**Cloud:** no — <row>: <reason> (YYYY-MM-DD, <who>)'
has "(A7) B1: the opt-in line shape" "$doc_flat" '^KEEL-CLOUD( unprotected-ok)?[[:space:]]*$'
has "(A7) B1: unprotected-ok is named" "$doc_flat" '`unprotected-ok` lets row G1b pass'
has "(A7) B10: who may dispatch, and when" "$doc_flat" \
  "A session runs \`--dispatch\` only in a turn the operator started, and only after the operator's yes in that session to a question that named the ticket — or to a wave plan that lists it as cloud."
has "(A7) B10: a yes covers one dispatch" "$doc_flat" 'A yes covers one dispatch'
has "(A7) B11: /go goes on locally on a refusal, with no offer" "$doc_flat" \
  'a refusal is named and `/go` goes on locally, with no offer'
has "(A7) B11: the offer comes before /go's own claim" "$doc_flat" \
  "the offer comes before \`/go\`'s own claim (step 6)"
has "(A7) B9: the Log line carries the session id only for a gitignored backlog" "$doc_flat" \
  'only when the backlog file is gitignored'

# --- B12: the manager's duties and the wave-peer rule ---------------------------------------------------------
has "(A7) B12: a wave peer keeps a ticket local" "$doc_flat" \
  'A ticket that shares a file with another ticket in the same wave does not go to the cloud in that wave'
has "(A7) B12: a ticket that names no file counts as sharing" "$doc_flat" 'a ticket that names none counts as sharing'
has "(A7) B12: the plan quotes the cloud-check receipt" "$doc_flat" 'the plan quotes its `cloud-check:` receipt line'

# --- B13: landing and the merge ---------------------------------------------------------------------------------
has "(A7) B13: the operator merges" "$doc_flat" '**The operator merges.**'
has "(A7) B13: a cloud PR is never a constituent of the manager's train" "$doc_flat" \
  'a cloud PR is never a constituent of a train the manager merges'
has "(A7) B13: outside a release, who lands" "$doc_flat" \
  'The operator, or a local session the operator asks, runs the landing check'
has "(A7) B13: the merge is pinned to the head" "$doc_flat" '--match-head-commit <sha>'

# --- B14: abandoning, under its own heading ---------------------------------------------------------------------
if grep -qx '## Abandoning' "$doc"; then
  pass "(A7) B14: a section headed Abandoning exists"
else
  fail "(A7) B14: a section headed Abandoning exists" "expected a '## Abandoning' heading in $doc"
fi
aband="$(section "$doc" '^## Abandoning' '^## ')"
has "(A7) B14: who carries abandoning out" "$aband" \
  'carried out by the manager inside a managed release, else by a local session the operator asks'
has "(A7) B14: abandoning clears the claim" "$aband" 'clear the claim marker'
has "(A7) B14: abandoning sets the row to abandoned" "$aband" "set the ledger row's status to \`abandoned\`"
has "(A7) B14: abandoning deletes the remote branch" "$aband" 'delete the remote `claude/cloud-<slug>` branch'

# --- the tools as shipped (slice 1's escapes), not as the spec first described them -------------------------------
has "(A7) shipped: dispatch runs the CLI under script, for the terminal it requires" "$doc_flat" \
  'the tool runs it under `script` (a pseudo-terminal)'
has "(A7) shipped: steering goes through the web view or claude --cloud from a terminal" "$doc_flat" \
  'or `claude --cloud <session id>` from a terminal'
has "(A7) shipped: landing refuses a PR whose base is not the default branch" "$doc_flat" \
  'a PR whose base is not the default branch'
has "(A7) shipped: CI is green only when at least one check succeeded" "$doc_flat" '**and at least one succeeded**'
has "(A7) shipped: --sweep marks a landed row stale on a non-zero landing exit" "$doc_flat" \
  'when its last landing check exited non-zero'
has "(A7) shipped: the marker check reads every commit" "$doc_flat" 'Every commit is read, not the net diff'
has "(A7) shipped: the home rewrite is wider than one form" "$doc_flat" \
  'each logical and physical'
has "(A7) shipped: the personal check is fail-closed" "$doc_flat" 'The personal check is **fail-closed**'

# --- the places that point at the doc ------------------------------------------------------------------------------
headline="$(section "$backlog_md" '^\*\*Headline discipline' '^\*\*Readiness & field legend')"
has "(A7) B3: backlog.md's headline-discipline block carries the cloud-verdict rule" "$headline" \
  '**The cloud verdict (docs/cloud.md).**'
has "(A7) B3: ...with both line forms" "$headline" \
  '`**Cloud:** yes (YYYY-MM-DD, <who>)` or `**Cloud:** no — <row>: <reason> (YYYY-MM-DD, <who>)`'
has "(A7) B3: ...as a body line, never a heading marker" "$headline" 'a body line, never a heading marker'

r1="$(section "$rm_doc" '^## R1 ' '^## R2 ')"
r2="$(section "$rm_doc" '^## R2 ' '^## R3 ')"
r3="$(section "$rm_doc" '^## R3 ' '^## The worker brief')"
has "(A7) B12: R1 carries the verdict duty" "$r1" "intake also settles each slate ticket's cloud verdict"
has "(A7) B12: R2 carries the route column" "$r2" 'the wave plan carries a route column'
has "(A7) B12: R2 names --check and its receipt" "$r2" '`cloud-check:` receipt line'
has "(A7) B12: R3 carries the cloud exception" "$r3" 'Named exception — a cloud worker'
has "(A7) B12: R3 keeps the operator as the merger" "$r3" 'never a constituent of a train the manager merges'

m2="$(section "$mr_cmd" '^\*\*M2 ' '^\*\*M3 ')"
m3="$(section "$mr_cmd" '^\*\*M3 ' '^\*\*M4 ')"
m4="$(section "$mr_cmd" '^\*\*M4 ' '^\*\*M5 ')"
has "(A7) B12: manage-release M2 points at the cloud doc" "$m2" 'docs/cloud.md'
has "(A7) B12: manage-release M3 points at the route column" "$m3" "R2's route column"
has "(A7) B12: manage-release M4 points at the cloud exception" "$m4" "R3's cloud exception"

has "(A7) B12: delegation.md's named override has the cloud sentence" "$(flat "$deleg_doc")" \
  "A cloud worker is launched under [\`docs/cloud.md\`](cloud.md)'s own gate"
has "(A7) B3: grooming.md carries the gap-fill" "$(flat "$groom_doc")" \
  'the groom also fills the cloud-verdict gaps in its slate'

pin "(A7) docs/reference.md lists docs/cloud.md" "$REPO_ROOT/docs/reference.md" '[`docs/cloud.md`](cloud.md)' \
  "expected the Docs index to list the cloud doc"
pin "(A7) docs/reference.md lists tools/cloud-brief.sh" "$REPO_ROOT/docs/reference.md" '[`tools/cloud-brief.sh`](../tools/cloud-brief.sh)' \
  "expected the Tools table to list the brief builder"
pin "(A7) docs/reference.md lists tools/cloud-land.sh" "$REPO_ROOT/docs/reference.md" '[`tools/cloud-land.sh`](../tools/cloud-land.sh)' \
  "expected the Tools table to list the landing check"
pin "(A7) docs/reference.md lists templates/cloud-protocol.md" "$REPO_ROOT/docs/reference.md" '[`templates/cloud-protocol.md`](../templates/cloud-protocol.md)' \
  "expected the file table to list the protocol template"
pin "(A7) README.md links docs/cloud.md" "$REPO_ROOT/README.md" '[docs/cloud.md](docs/cloud.md)' \
  "expected the README to point at the cloud doc"
pin "(A7) ADAPTING.md says the cloud route does not port" "$REPO_ROOT/ADAPTING.md" '**The cloud route**' \
  "expected ADAPTING.md to name the cloud route as Claude Code only"

# =====================================================================================================
# Mutation proof (never on a tracked file): each wrong build below must turn its case red.
if [ -n "${!MUTATION_SKIP_VAR:-}" ]; then
  summary
  exit $?
fi

# Wrong build 1: G5 listed twice (the old and the new wording) fails "exactly once".
m1="$(scratch_copy "$doc" cloud.md)"
printf '%s\n' '| G5 | The ticket is not itself a managed-release role. | judged |' >> "$m1"
assert_case_turns_red "(A7) mutation: G5 listed twice" \
  "(A7) eligibility row G5 appears exactly once as a table row" "KEEL_CLOUD_DOC=$m1"

# Wrong build 2: G5 without its decisive clause.
m2c="$(scratch_copy "$doc" cloud.md)"
replace_in_line_containing "$m2c" '| G5 |' ' A slate ticket may run as a cloud worker.' ''
assert_case_turns_red "(A7) mutation: G5's slate-ticket clause removed" \
  "(A7) row G5 carries its decisive clause" "KEEL_CLOUD_DOC=$m2c"

# Wrong build 3: the Abandoning heading renamed.
m3c="$(scratch_copy "$doc" cloud.md)"
replace_in_line_containing "$m3c" '## Abandoning' 'Abandoning' 'Cleaning up'
assert_case_turns_red "(A7) mutation: Abandoning heading renamed" \
  "(A7) B14: a section headed Abandoning exists" "KEEL_CLOUD_DOC=$m3c"

# Wrong build 4: the operator no longer merges.
m4c="$(scratch_copy "$doc" cloud.md)"
replace_in_line_containing "$m4c" '**The operator merges.**' '**The operator merges.**' 'The manager merges.'
assert_case_turns_red "(A7) mutation: the merge handed to the manager" \
  "(A7) B13: the operator merges" "KEEL_CLOUD_DOC=$m4c"

# Wrong build 5: a backlog legend that names **Cloud:** in the fence only, with no write rule (leg 1 F7).
m5="$(scratch_copy "$backlog_md" backlog.md)"
awk 'index($0, "**The cloud verdict (docs/cloud.md).**") { skip = 1 } skip && /^$/ { skip = 0; next } !skip' "$m5" > "$m5.tmp" \
  && mv "$m5.tmp" "$m5"
assert_case_turns_red "(A7) mutation: the headline block loses the cloud-verdict rule" \
  "(A7) B3: backlog.md's headline-discipline block carries the cloud-verdict rule" "KEEL_BACKLOG_MD=$m5"

# Wrong build 6: B10's sentence weakened.
m6="$(scratch_copy "$doc" cloud.md)"
replace_in_line_containing "$m6" 'A session runs' 'and only after the operator'"'"'s yes in that' 'whenever it likes in that'
assert_case_turns_red "(A7) mutation: B10's yes requirement removed" \
  "(A7) B10: who may dispatch, and when" "KEEL_CLOUD_DOC=$m6"

summary
