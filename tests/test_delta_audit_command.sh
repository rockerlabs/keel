#!/usr/bin/env bash
# test_delta_audit_command.sh — dir #385: commands/delta-audit.md is a thin entrypoint over
# docs/delta-audit.md, wired into the release manager's close checklist (dir #367 R9) so the RC audit
# is a structural step, not a memory. Same shape as test_drydock_doc.sh: the skill file exists, the
# doc and command name each other back (a mutual-reference pair, so neither can drift silently alone),
# and the skill carries anchors for the four checklist items most likely to be silently dropped in a
# rewrite — A3 (budget flow), A4 (diversity leg), A6 (run record + harvest), A7 (operator tags).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

skill="$REPO_ROOT/commands/delta-audit.md"
doc="$REPO_ROOT/docs/delta-audit.md"
delegation="$REPO_ROOT/docs/delegation.md"

check_file "commands/delta-audit.md exists" "$skill"
check_file "docs/delta-audit.md exists" "$doc"

# --- the mutual-reference pair: doc and command must point at each other ---------------------------
pin "commands/delta-audit.md names docs/delta-audit.md" "$skill" '(../docs/delta-audit.md)' \
  "expected the skill to point at the doc it is a thin checklist over"
pin "docs/delta-audit.md §1 names the command back" "$doc" '(../commands/delta-audit.md)' \
  "expected §1 to name commands/delta-audit.md as the entrypoint, so neither file can drift alone"
pin "docs/delta-audit.md §1 cites dir #385" "$doc" '`dir #385`' \
  "expected the entrypoint line to cite the ticket that closed the manual-citation gap"

# --- A3: budget flow before any wave, and the delegation.md named-override cross-edit --------------
pin "skill carries A3 (budget flow before any wave)" "$skill" 'A3 — budget flow BEFORE any wave' \
  "expected the checklist to keep the budget-flow item, not drop it in a rewrite"
pin "skill's A3 points at delegation.md's session-limit flow" "$skill" \
  "delegation.md)'s session-limit flow" \
  "expected A3 to cite the flow by reference, not restate it"
pin "delegation.md's step 1 carries dir #385's named-override cross-edit" "$delegation" \
  "Named override (\`dir #385\`" \
  "expected the session-limit flow's ask-the-operator step to name the delta-audit amendment that reads spend data first, per the amendment's own never-a-silent-contradiction rule"

# --- A4: the diversity leg is non-waivable by the orchestrator -------------------------------------
pin "skill carries A4 (diversity leg is non-waivable)" "$skill" \
  'A4 — the diversity leg is non-waivable by you' \
  "expected the checklist to keep the diversity-leg rail, not drop it in a rewrite"
pin "skill's A4 states the operator-only skip" "$skill" \
  'Skippable only by an explicit, recorded operator decision' \
  "expected the skip condition to survive compression"

# --- A6: the run record is part of the run, harvest included ---------------------------------------
pin "skill carries A6 (run record)" "$skill" 'A6 — the run record is part of the run' \
  "expected the checklist to keep the run-record item, not drop it in a rewrite"
pin "skill's A6 states the harvest step" "$skill" 'every `no-action(<reason>)` disposition' \
  "expected A6 to keep the harvest-onto-the-standing-list step, the amendment's own point"
pin "skill's A6 names the standing list" "$skill" '`## Standing list` section of `BACKLOG.md`' \
  "expected A6 to name dir #386 G4's actual standing-list location, not a generic placeholder"

# --- A7: the operator tags, sharpened per the second amendment -------------------------------------
pin "skill carries A7 (operator tags)" "$skill" \
  'A7 — you hand the operator the tag commands; you never run them' \
  "expected the checklist to keep the operator-tags rail, not drop it in a rewrite"
pin "skill's A7 requires a copy-paste-ready command block, not a pointer" "$skill" \
  'never recited from memory and never replaced by a pointer to the checklist' \
  "expected the sharpened A7 (GO arrives WITH the commands) to survive compression"
pin "skill's A7 requires the notes file to be already composed" "$skill" \
  'a notes file YOU compose' \
  "expected A7 to keep the manager/orchestrator-composes-notes requirement, not hand the operator an extract-by-hand step"

# --- portability: no keel-only absolute paths, per dir #367 R12 ------------------------------------
pin "skill states version resolves against the target project's own tags" "$skill" \
  "never keel's own release-plan table" \
  "expected the skill to state the portable resolution rule, not a keel-only shortcut"

summary
