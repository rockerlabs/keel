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

# --- dir #177: the IN-RUN convergence path (resolve, --amend, continue the same run) needs its own
# paragraph beside step 5's "converge, don't restart" block, and step 1's --recover warning needs the
# mirror-image case added: a "nothing to recover" answer is by-design on this path too, not proof of a
# fresh run. -----------------------------------------------------------------------------------------
pin "polish.md: step 5 names the in-run converge-and-continue path explicitly" \
  "$polish" 'The IN-RUN path is the cheaper alternative when steps 6/7/8 are still ahead' \
  "expected step 5 to name the in-run --amend-and-continue path beside 'converge, don't restart'"
pin "polish.md: step 5's in-run paragraph names polish.3-tests as the pre-existing sha-bound receipt" \
  "$polish" '**`polish.3-tests`**, the one PRE-EXISTING receipt' \
  "expected the in-run paragraph to name polish.3-tests by id"
pin "polish.md: step 5's in-run paragraph names polish.6-retest as the receipt that re-establishes binding" \
  "$polish" '`polish.6-retest` receipt against the new HEAD satisfies it on its own' \
  "expected the in-run paragraph to name polish.6-retest by id"
pin "polish.md: step 1's --recover warning names the in-run mirror-image trap" \
  "$polish" 'answer has a mirror-image trap too (dir #177)' \
  "expected step 1's 'do NOT use --recover's own output' warning to cover the nothing-to-recover case too"
pin "polish.md: step 5's in-run paragraph does not misattribute the later-staleness trigger to steps 6/7" \
  "$polish" 'but not via step 6 or step 7' \
  "expected the polish.5-review staleness clause to name an add-on review as the trigger, not step 6/7 (which mandate re-invoking /polish, never an in-run amend)"
pin "polish.md: step 5's in-run paragraph names the review dialog as per-commit too" \
  "$polish" 'The MANDATORY review dialog (dir #88), on that same later-amend trigger' \
  "expected the polish.5-review staleness clause to also cover the dir #88 review dialog going stale"

summary
