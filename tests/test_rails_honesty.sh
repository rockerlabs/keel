#!/usr/bin/env bash
# test_rails_honesty.sh — pins the wording fixes of dir #99/#111/#112/#119: places where a shipped
# rail described a guarantee it does not give. Grep-based, same idiom as test_conveyor_stages.sh — the
# failure mode these guard against is a later edit quietly restoring the overclaim, which nothing else
# would notice.
#
# dir #110's class-level "no unshipped slash-command reference" guard used to live here too, but it
# ran only in Keel's own suite — no adopter install inherited it. Moved to tools/self/doctor.sh's
# check 2b (dir #129), which every adopter's tools/doctor.sh run already orchestrates; the coverage
# on Keel's own tree is preserved by tests/test_self_doctor.sh's smoke test (self/doctor.sh against
# the real checkout), and mutation-tested against a synthetic sandbox the same way check 2's dead
# internal references already are — coverage this file's own live-tree scan never had.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

checklist="$REPO_ROOT/docs/publishing-checklist.md"
going="$REPO_ROOT/docs/going-public.md"
go="$REPO_ROOT/commands/go.md"
wrap="$REPO_ROOT/commands/wrap.md"
polish="$REPO_ROOT/commands/polish.md"

check_file "docs/publishing-checklist.md exists" "$checklist"
check_file "docs/going-public.md exists" "$going"
check_file "commands/go.md exists" "$go"
check_file "commands/wrap.md exists" "$wrap"
check_file "commands/polish.md exists" "$polish"

# --- dir #99: neither go-public doc may read as "green exit = no personal data" ------------------
# public-audit's personal-data heuristics are all WARN-tier and leave the exit code at 0, so both
# documents have to say what exit 0 does and does not prove, and hand the WARN read to the human.
pin "publishing-checklist: §0's [auto] tag is scoped to the exit code, not the whole item" \
  "$checklist" '**[auto]** for the exit code' \
  "expected the item to split [auto] (the exit code) from [you] (the WARNs)"
pin "publishing-checklist: §0 states a green exit is not proof of a clean tree" \
  "$checklist" 'A clean exit is not a clean tree' \
  "expected an explicit 'a clean exit is not a clean tree' disclaimer next to the WARN tier"
# One pin per SITE, keyed on a literal unique to that site. A single shared phrase would let any one
# site satisfy the guard for all three — and the site most worth holding is the scrub gate, the last
# check before a `--force` push.
pin "going-public: the flip step requires a WARN read, not just exit 0" \
  "$going" 'have read its WARNs' \
  "step 4 must name the WARN read alongside the exit code — exit 0 clears the GAP tier only"
pin "going-public: the §0 detect block hands the WARN list to the human" \
  "$going" 'then read the WARNs yourself' \
  "§0 must say the WARNs are yours to read, not something the exit code covered"
pin "going-public: the scrub gate before the force-push names the WARN read" \
  "$going" 'exit 0 AND its WARNs read' \
  "the third scrub gate must not read as satisfied by a green exit alone — a WARN-tier leak would ship"

# --- dir #111: /wrap must actually carry the fold FRAMEWORK.md calls its serialization point -----
pin "wrap.md: step 2 names the BACKLOG.drafts fold" \
  "$wrap" 'BACKLOG.drafts' \
  "FRAMEWORK.md calls the session's own wrap the single serialization point; wrap.md must carry the step"
pin "wrap.md: claims the serialization point FRAMEWORK.md assigns it" \
  "$wrap" 'serialization point' \
  "expected wrap.md to name itself the drafts' serialization point"
pin "FRAMEWORK.md: points the serialization point at the command that implements it" \
  "$REPO_ROOT/FRAMEWORK.md" '`/wrap` step 2' \
  "expected the drafts convention to name '/wrap step 2'"
pin "FRAMEWORK.md: says Keel ships the fold side of the convention, not the producer" \
  "$REPO_ROOT/FRAMEWORK.md" 'Keel ships the fold side' \
  "the drafts are written by your own design/planning flow; no shipped command creates them — say so"

# --- dir #112: /go's test-first rail must disclose that nothing enforces it ----------------------
pin "go.md: says the test-first rail is self-reported, with no receipt or gate behind it" \
  "$go" 'no receipt, no gate' \
  "expected an explicit 'self-reported' + 'no receipt, no gate' disclosure, not a bare /polish analogy"
pin "go.md: gives the decision a home that outlives the ticket (the PR's test plan)" \
  "$go" 'tests: infeasible' \
  "expected the test decision written into the PR test plan and the IN FLIGHT marker, not only the chat"

# --- dir #119: a step-7 finding triggers the same convergence round as a step-5 one --------------
pin "polish.md: step 1's convergence branch names a step-7 self-check trigger" \
  "$polish" "step 7's self-check" \
  "expected the convergence-round question to cover step 7, not only step 5's review"
pin "polish.md: step 7 itself names the convergence round its finding triggers" \
  "$polish" 'you are in a convergence round' \
  "expected step 7 to state that a fix commit puts the run into step 1's convergence branch"

summary
