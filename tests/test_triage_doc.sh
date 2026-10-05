#!/usr/bin/env bash
# test_triage_doc.sh — dir #517: docs/triage.md is the procedure for turning the accumulator tiers
# (LEARNINGS.md / IDEAS.md / the standing list) into a rule, a ticket, or a recorded drop;
# commands/triage.md is its thin entrypoint. Same idiom as test_grooming_doc.sh: fixed-string pins on
# BOTH legs of each naming coupling (a rename on either side strands the citation loudly), plus the
# callers' pins — groom, global-review and wrap must each NAME /triage, or the owner sentence the
# ticket exists to add silently regresses. pin() needles are single-line (lib.sh is line-mode grep -F).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="$REPO_ROOT/docs/triage.md"
cmd="$REPO_ROOT/commands/triage.md"
readme="$REPO_ROOT/README.md"

check_file "docs/triage.md exists" "$doc"
check_file "commands/triage.md exists" "$cmd"

# --- the mutual-reference pair ----------------------------------------------------------------------
pin "commands/triage.md names docs/triage.md" "$cmd" '](../docs/triage.md)' \
  "expected the entrypoint to point at the doc it is a thin wrapper over"
pin "docs/triage.md names commands/triage.md back" "$doc" '](../commands/triage.md)' \
  "expected the doc to name its own entrypoint"
pin "README Docs section links docs/triage.md" "$readme" '[`docs/triage.md`](docs/triage.md)' \
  "expected the Docs section to list the new doc next to docs/grooming.md"
pin "docs/reference.md Commands table has a /triage row" "$REPO_ROOT/docs/reference.md" '| `/triage` |' \
  "expected the Commands table to list the new command"

# --- the doc's family cross-links ----------------------------------------------------------------------
pin "triage.md links grooming.md" "$doc" '](grooming.md)' "expected a link back to G4, its caller"
pin "triage.md links FRAMEWORK.md" "$doc" '](../FRAMEWORK.md)' \
  "expected a link to FRAMEWORK.md (review signal 3, the LEARNINGS rule)"

# --- the procedure's load-bearing facts: T0-T6, the four verdicts, T3 ------------------------------
for t in T0 T1 T2 T3 T4 T5 T6; do
  pin "triage.md carries the $t heading" "$doc" "**$t — " "expected every numbered step to survive as its own bold lead"
done
for v in PROMOTE-RULE PROMOTE-TICKET KEEP DROP; do
  pin "triage.md pins the $v verdict" "$doc" "| \`$v\` |" "expected the verdict table to name all four verdicts"
done
pin "T3: an entry never survives a promotion" "$doc" 'An entry never survives a promotion.' \
  "expected T3's sentence — the failure the ticket exists to remove"
pin "T2 names the 60-day horizon" "$doc" '60 days at `[1×]`' \
  "expected the staleness horizon operationalized, not left as '~5 sessions'"
pin "T1 names the per-pass bound" "$doc" 'default 40' "expected the per-pass bound"

# --- the callers name /triage by reference ------------------------------------------------------------
pin "commands/groom.md names /triage" "$REPO_ROOT/commands/groom.md" '/triage' "G4 must call, not restate"
pin "docs/grooming.md G4 names /triage" "$REPO_ROOT/docs/grooming.md" '/triage' "G4 must call, not restate"
pin "commands/global-review.md names /triage" "$REPO_ROOT/commands/global-review.md" '/triage' \
  "global-review must run the KB tiers through /triage, not only 'prune'"
pin "commands/wrap.md names /triage" "$REPO_ROOT/commands/wrap.md" '/triage' \
  "wrap keeps the bump, /triage owns the promote-due set"
pin "FRAMEWORK.md names /triage" "$REPO_ROOT/FRAMEWORK.md" '/triage' "signal 3 and the LEARNINGS rule name the owner"
pin "templates/CLAUDE.md map names /triage" "$REPO_ROOT/templates/CLAUDE.md" '/triage' "the map's tier lines name the owner"
pin "templates/LEARNINGS.md names /triage" "$REPO_ROOT/templates/LEARNINGS.md" '/triage' "header names the reviewer"
pin "templates/IDEAS.md names /triage" "$REPO_ROOT/templates/IDEAS.md" '/triage' "header names the reviewer"

# --- naming-collision acknowledgment (plain text, never a backtick-wrapped slash command) and
# portability, looped over both files ---------------------------------------------------------------
for f in "$doc" "$cmd"; do
  label="${f#"$REPO_ROOT"/}"
  body="$(cat "$f")"
  check_contains "$label acknowledges the collision alias" "$body" "keel-triage"
  check_absent "$label never backtick-wraps the collision alias as a slash command" "$body" '`/keel-triage`'
  check_absent "$label carries no absolute keel-checkout path" "$body" '/Users/'
done

summary
