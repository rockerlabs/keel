#!/usr/bin/env bash
# test_grooming_doc.sh — dir #386: docs/grooming.md is the procedure for assembling a release from
# the backlog on a fixed cadence, closing the manager family's loop (/design -> /go ->
# /manage-release -> /delta-audit -> /groom -> feeds /design again); commands/groom.md is its thin,
# /go-sized entrypoint. Same idiom as test_release_management_doc.sh and test_delta_audit_doc.sh
# (fixed-string pins on BOTH legs of a naming coupling, so a rename on either side strands the
# citation loudly instead of silently) — the family shape the ticket's own binding test names: the
# command names the doc, the doc names the command back, and the doc carries anchors for G0, G3 and
# G6 (the three requirements most likely to be silently dropped in a rewrite).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/grooming.md"
cmd="$REPO_ROOT/commands/groom.md"
readme="$REPO_ROOT/README.md"

check_file "docs/grooming.md exists" "$doc"
check_file "commands/groom.md exists" "$cmd"

# --- the mutual-reference pair: command names the doc, doc names the command back ------------------
pin "commands/groom.md names docs/grooming.md" \
  "$cmd" '](../docs/grooming.md)' \
  "expected the entrypoint to point at the doc it is a thin wrapper over"
pin "docs/grooming.md names commands/groom.md back" \
  "$doc" '](../commands/groom.md)' \
  "expected the doc to name its own entrypoint, per the drydock/delta-audit/release-management mutual-reference precedent"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ----------------
pin "README Docs section links docs/grooming.md" \
  "$readme" '[`docs/grooming.md`](docs/grooming.md)' \
  "expected the Docs section to list the new doc the way it lists drydock.md/delta-audit.md/release-management.md"

# --- the family cross-links: the manager-family loop this doc closes -------------------------------
pin "grooming.md links release-management.md" "$doc" '](release-management.md)' \
  "expected the doc to name the release-manager sibling its plan feeds work into"
pin "grooming.md links delta-audit.md" "$doc" '](delta-audit.md)' \
  "expected the doc to name the release-candidate-audit sibling"

# --- the binding test's own three required anchors: G0, G3, G6 -------------------------------------
pin "G0 anchor: retro first" \
  "$doc" '## G0 — retro first' \
  "expected a named G0 section — the requirement most likely to be compressed into one line in a rewrite"
pin "G0 requires amendments to be APPLIED, not reported" \
  "$doc" 'applied, not reported' \
  "expected G0 to keep the apply-not-report distinction explicit"
pin "G3 anchor: derive, don't assert" \
  "$doc" "## G3 — derive, don't assert" \
  "expected a named G3 section"
pin "G3 states a ticket's release tag is never asserted in prose" \
  "$doc" 'Never assert a specific release tag in prose' \
  "expected G3 to carry the tag-citation rule, not just the count-regeneration rule"
pin "G6 anchor: fresh-reviewer adjudication is mandatory" \
  "$doc" '## G6 — a fresh-reviewer adjudication round is mandatory' \
  "expected a named G6 section"
pin "G6 states the round is not optional polish" \
  "$doc" 'not optional polish' \
  "expected G6 to state plainly that this round is required, not a nice-to-have on top of G0-G5"

# --- the other numbered requirements, so a wholesale drop of one doesn't pass silently --------------
for g in \
  "## G1 — pains are the input, and only the operator supplies them" \
  "## G2 — read ticket bodies, not headings" \
  "## G4 — the hygiene sweep" \
  "## G5 — every release row, five fields" \
  "## G7 — the releases cross-run record" \
  "## G8 — cadence-bound, never a daemon" \
  "## G9 — portability"
do
  pin "requirement heading present: ${g#\#\# }" "$doc" "$g" \
    "expected every numbered requirement (G0-G9) to survive compression as its own heading"
done

# --- G0's read-trace input degrades cleanly when the mechanism doesn't exist -------------------------
pin "G0 states the tier-2 aggregate is read generically, by pointer" \
  "$doc" 'by pointing at' \
  "expected G0 to consume the read-trace aggregate by pointing at its tool, never by hardcoding a path or format"
pin "G0 states the tier-2 input degrades cleanly when absent" \
  "$doc" 'Degrade cleanly when it does not exist yet' \
  "expected G0 to say explicitly what happens when the aggregate mechanism isn't installed"

# --- G4(a): the standing list is named, and its own filing-bar source is cited ----------------------
pin "G4(a) names the Standing list section" "$doc" '## Standing list' \
  "expected G4(a) to name keel's own instance of the standing list by its literal section heading"
pin "G4(a) cites the filing bar it satisfies" "$doc" 'verification-economics.md' \
  "expected G4(a) to cite the doc whose filing bar makes the standing list necessary"

# --- G7: the cross-run record names its per-project location and its audit-record sibling -----------
pin "G7 names keel's own releases cross-run record path" "$doc" 'private/releases/RUNS.md' \
  "expected G7 to name keel's own instance of the record, same as R7/A6 name private/audit/RUNS.md"
pin "G7 states cost may be recorded unmeasured, never fabricated" "$doc" 'never a fabricated zero' \
  "expected G7 to preserve the unmeasured-not-fabricated convention shared with the audit record"

# --- naming-collision acknowledgment (plain text, no backticked slash-command form — dir #385's own
# felt incident, a backtick-wrapped /keel-* citation trips doctor.sh's dir #129 dead-reference check)
# and portability (no keel-only absolute paths), looped over both files ------------------------------
for f in "$doc" "$cmd"; do
  label="${f#"$REPO_ROOT"/}"
  body="$(cat "$f")"
  check_contains "$label acknowledges the collision alias" "$body" "keel-groom"
  check_absent "$label never backtick-wraps the collision alias as a slash command" "$body" '`/keel-groom`'
  check_absent "$label carries no absolute keel-checkout path" "$body" '/Users/'
done

pin "grooming.md names both -> <version> and -> pool heading-tag conventions" "$doc" \
  '`→ <version>` and `→ pool`' \
  "expected G9 to name the portable release-slate/pool-lane convention, not keel's own release-plan table"

# --- the entrypoint stays thin: a pointer-and-checklist, not a second copy of the procedure ----------
pin "groom.md states it is a pointer, never a restatement" "$cmd" \
  'never a restatement' \
  "expected the same never-a-restatement framing the sibling entrypoints use for their own docs"

# --- self-revision: grooming.md is subject to its own G0, same as release-audit/delta-audit/drydock --
pin "grooming.md carries a self-revision clause" "$doc" '## Self-revision clause' \
  "expected the doc to state it revises itself via its own G0, same discipline it asks of its siblings"

summary
