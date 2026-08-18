#!/usr/bin/env bash
# test_drydock_doc.sh — dir #170: docs/drydock.md cites three sibling docs by section name, ships a
# tool by path, and hands its role prompts to agents as separate files. Same idiom as
# test_release_audit_doc.sh (fixed-string pins on BOTH legs of a naming coupling): a rename on either
# side would otherwise strand the citation silently — which is `broken-xref`, a finding class
# drydock.md itself defines. A doc that defines a defect class and then ships an instance of it is the
# one prose defect this repo should never merge twice.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/drydock.md"
audit="$REPO_ROOT/docs/release-audit.md"
rollout="$REPO_ROOT/docs/rollout-audit.md"
checklist="$REPO_ROOT/docs/publishing-checklist.md"
readme="$REPO_ROOT/README.md"
auditor="$REPO_ROOT/docs/drydock/auditor.md"
verifier="$REPO_ROOT/docs/drydock/verifier.md"
fixer="$REPO_ROOT/docs/drydock/fixer.md"

check_file "docs/drydock.md exists" "$doc"
check_file "docs/drydock/auditor.md exists" "$auditor"
check_file "docs/drydock/verifier.md exists" "$verifier"
check_file "docs/drydock/fixer.md exists" "$fixer"
check_file "tools/drydock/inventory.sh exists" "$REPO_ROOT/tools/drydock/inventory.sh"

# --- discoverability: an adopter-usable doc nobody links to is as good as unshipped ---------------
pin "README Docs section links docs/drydock.md" \
  "$readme" '[`docs/drydock.md`](docs/drydock.md)' \
  "expected the Docs section to list drydock.md the way it lists release-audit.md"

# --- the family cross-links, pinned on BOTH legs (the changelog claims they are two-way) ----------
pin "drydock.md links release-audit.md" "$doc" '](release-audit.md)' \
  "expected drydock.md to cite its release-readiness sibling"
pin "drydock.md links rollout-audit.md" "$doc" '](rollout-audit.md)' \
  "expected drydock.md to cite its rollout sibling"
pin "drydock.md links publishing-checklist.md" "$doc" '](publishing-checklist.md)' \
  "expected drydock.md to cite its publishing sibling"
pin "release-audit.md links drydock.md back" "$audit" '](drydock.md)' \
  "expected release-audit.md's family paragraph to name drydock as the fourth leg"
pin "rollout-audit.md links drydock.md back" "$rollout" '](drydock.md)' \
  "expected rollout-audit.md to point at the whole-tree prose pass its own insight implies"
pin "publishing-checklist.md links drydock.md back" "$checklist" '](drydock.md)' \
  "expected publishing-checklist.md's sibling paragraph to name drydock"

# --- the cited section of release-audit.md must keep its name ------------------------------------
# drydock.md rests its tier-1/tier-2 split on this heading twice; renaming it silently breaks both.
pin "release-audit.md still has the phase 0 heading drydock.md cites" \
  "$audit" '## Phase 0 — the state definition the whole flow rests on' \
  "drydock.md cites release-audit.md's phase 0 by name for the green-contracts state definition"

# --- the tool path the doc tells adopters to run -------------------------------------------------
pin "drydock.md names the inventory tool by its real path" \
  "$doc" 'tools/drydock/inventory.sh' \
  "expected the phase 0 command block to name the shipped script"
pin "docs/reference.md lists the inventory tool" \
  "$REPO_ROOT/docs/reference.md" '[`tools/drydock/inventory.sh`](../tools/drydock/inventory.sh)' \
  "expected the reference Tools table to carry the new shipped tool"

# --- the role prompts are reachable from the procedure -------------------------------------------
pin "drydock.md links the auditor prompt" "$doc" '](drydock/auditor.md)' \
  "expected the role-prompt section to link the auditor template"
pin "drydock.md links the verifier prompt" "$doc" '](drydock/verifier.md)' \
  "expected the role-prompt section to link the verifier template"
pin "drydock.md links the fixer prompt" "$doc" '](drydock/fixer.md)' \
  "expected the role-prompt section to link the fixer template"

# --- the audit-file contract is stated in two places on purpose; pin the shared shape ------------
# drydock.md documents it for the operator, auditor.md hands it to the agent. Both must carry the
# same field names, or the orchestrator's completeness check and the agent's output disagree.
for field in '# drydock audit — <repo-relative path> @ <baseline-sha>' '## claims' 'verdict:'; do
  pin "drydock.md's contract carries: $field" "$doc" "$field" \
    "the file contract in drydock.md must match docs/drydock/auditor.md field for field"
  pin "auditor.md's contract carries: $field" "$auditor" "$field" \
    "the file contract in docs/drydock/auditor.md must match drydock.md field for field"
done

# The verifier's footer line is part of the contract drydock.md documents, so both must name it.
pin "drydock.md documents the verifier footer" "$doc" 'verifier: <model + effort>' \
  "expected the file-contract section to name the footer phase 2 appends"
pin "verifier.md writes the footer drydock.md documents" "$verifier" 'verifier: <your model + effort>' \
  "expected the verifier template to specify the footer line it appends"

summary
