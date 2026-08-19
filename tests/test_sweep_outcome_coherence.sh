#!/usr/bin/env bash
# test_sweep_outcome_coherence.sh — the red-flag-sweep outcome set is restated in prose across four
# independent surfaces (CORE.md's Persist rail, commands/wrap.md, commands/global-review.md,
# FRAMEWORK.md), plus two files that describe their own place in that sweep (IDEAS.md,
# templates/LEARNINGS.md). Manual coherence provably does not hold: PR #213 fixed a missing IDEAS.md
# outcome on two of the four surfaces and never checked the other two against each other, leaving
# commands/global-review.md missing the rule outcome (drydock run 1 phase-6 finding P6-1,
# private/audit/phase6-recheck.md). This test makes the class mechanical: extract each surface's own
# sweep paragraph and require it to name the same canonical outcome-token set. dir #166 (drydock
# ratchet); P6-3 extends the same coherence set to the swept files' self-descriptions after PRs #212
# and #213 landed individually-correct fixes that contradicted each other within a day.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

core="$REPO_ROOT/CORE.md"
wrap="$REPO_ROOT/commands/wrap.md"
global_review="$REPO_ROOT/commands/global-review.md"
framework="$REPO_ROOT/FRAMEWORK.md"
ideas="$REPO_ROOT/IDEAS.md"
learnings_template="$REPO_ROOT/templates/LEARNINGS.md"

for f in "$core" "$wrap" "$global_review" "$framework" "$ideas" "$learnings_template"; do
  check_file "$(basename "$f") exists" "$f"
done

# Each surface's own sweep-outcome paragraph, isolated by anchoring on a unique sentence/phrase and
# reading forward to the next blank line — line numbers drift as prose is edited, anchor text does
# not. If an anchor ever stops matching (the paragraph was reworded away), the extraction comes back
# empty and every token check below on it fails loudly instead of silently passing on an empty
# haystack (the first token check, "backlog ticket", doubles as the anchor-matched signal).
extract() { awk "/$1/,/^\$/" "$2"; }

core_para="$(extract 'Any idea, finding, decision, or loose-end surfaced' "$core")"
wrap_para="$(extract 'Red-flag sweep \(P0' "$wrap")"
framework_para="$(extract 'Anything surfaced but not yet handled' "$framework")"
# FRAMEWORK.md's outcome vocabulary spans two adjacent bullet list items with no blank line between
# them, so extract() intentionally continues past the first bullet into the second — a purely
# cosmetic reformat that inserts a blank line between those two bullets would truncate this
# extraction and red the LEARNINGS.md/rule checks below with no real coherence regression. Its only
# "committed rule" mention is the negated "not yet worth a committed rule" (the LEARNINGS.md staging
# clause) — genuine content, but it means a cosmetic reword of that one clause could also flip this
# specific check without a real coherence regression; a known, accepted fragility of prose-matching.

global_review_para="$(extract 'Persist before closing \(red-flag sweep' "$global_review")"

# Canonical outcome-token set (dir #166's "likely" shape from the ticket): each of the four sweep
# surfaces must name all five. label|extended-regex (alternation via `|` inside the pattern half,
# matched with bash's own `=~` — no external grep fork needed per check).
tokens=(
  "backlog ticket|backlog"
  "committed/promoted rule|committed rule|promoted rule"
  "LEARNINGS.md staging tier|LEARNINGS\\.md"
  "IDEAS.md staging tier|IDEAS\\.md"
  "explicit drop|drop"
)

surfaces=(
  "CORE.md|$core_para"
  "commands/wrap.md|$wrap_para"
  "commands/global-review.md|$global_review_para"
  "FRAMEWORK.md|$framework_para"
)

for surface_entry in "${surfaces[@]}"; do
  surface_name="${surface_entry%%|*}"
  surface_text="${surface_entry#*|}"
  for token_entry in "${tokens[@]}"; do
    token_label="${token_entry%%|*}"
    token_patterns="${token_entry#*|}"
    if [[ "$surface_text" =~ $token_patterns ]]; then
      pass "$surface_name names the $token_label outcome"
    else
      fail "$surface_name names the $token_label outcome" \
        "none of [$token_patterns] found in its sweep paragraph"
    fi
  done
done

# --- P6-3 scope extension: the swept files' own self-descriptions must not contradict what the
# sweep surfaces above say about them. Both files independently describe whether/how they are part
# of the mechanized sweep; a header claiming exclusion ("not yet part of") while wrap.md and
# global-review.md both list them as sweep destinations is exactly the PR #212/#213 contradiction.
# Header = everything before the first `## ` heading — anchor-based like extract() above, not a
# fixed line count, so header prose can grow without pushing the relevant sentence out of the check.
header() { awk '/^## /{exit} {print}' "$1"; }

ideas_header="$(header "$ideas")"
learnings_header="$(header "$learnings_template")"

check_contains "IDEAS.md header claims sweep inclusion" "$ideas_header" "red-flag sweep"
check_absent "IDEAS.md header does not claim sweep exclusion" "$ideas_header" "not yet part of"

# templates/LEARNINGS.md's header never mentions the sweep by name — it describes its own two-outcome
# lifecycle instead ("promote to a rule/ticket" and "explicit drop"), so pin THAT positively rather
# than only asserting an absence with nothing to anchor it (a vacuous check: a header that never says
# anything about the sweep trivially "doesn't claim exclusion" no matter how it's worded).
check_contains "templates/LEARNINGS.md header states its promote outcome" "$learnings_header" "promote"
check_contains "templates/LEARNINGS.md header states its drop outcome" "$learnings_header" "drop"
check_absent "templates/LEARNINGS.md header does not claim sweep exclusion" \
  "$learnings_header" "not yet part of"

summary
