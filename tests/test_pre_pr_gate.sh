#!/usr/bin/env bash
# test_pre_pr_gate.sh — the pre-PR gate's allow/deny decision and its bypass-prevention logic.
#
# tools/pre-pr-gate.sh is a Claude Code PreToolUse(Bash) hook: it reads a JSON event on stdin and emits
# a JSON allow/deny decision (always exit 0; an empty stdout = allow, a "permissionDecision":"deny"
# payload = block). It is meant to be unbypassable by a bare `touch` — the sentinel is a per-run receipt
# (a nonce header + one line per expected step id) and the deny paths are security-adjacent, so both the
# hook-mode gate and the `init`/`receipt`/`log` CLI subcommands (dir #49) are covered here.
#
# The gate parses its input with jq, so these tests need jq. The busybox/Alpine CI job installs only
# bash+git; there, skip cleanly. Without jq the gate now exits early by an EXPLICIT, documented choice
# (`command -v jq || exit 0`) — it can't tell `gh pr create` from any other Bash call, so it allows rather
# than block everything; it's a workflow reminder, not the secret boundary (that's secret-guard, no jq).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

gate="$REPO_ROOT/tools/pre-pr-gate.sh"
check_file "pre-pr-gate.sh exists" "$gate"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — pre-pr-gate tests skipped (gate requires jq to parse its event)"
  summary; exit $?
fi

# A git repo with one commit; prints its path.
mkrepo() {
  local d; d="$(new_repo)"
  git -C "$d" commit --allow-empty -qm init
  printf '%s' "$d"
}

# Drive the gate: $1 = command string, $2 = cwd. Captures OUT (stdout+stderr) and STATUS.
# (ALL_STEPS/repo_key_for/sentinel_for/write_full_receipt[_review] live in lib.sh, dir #64 — shared
# with test_pipeline_canary.sh, which drives the same gate CLI subcommands against a sandbox repo.)
gate() {
  local json
  json="$(jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, cwd:$d}')"
  OUT="$(printf '%s' "$json" | bash "$gate" 2>&1)"
  STATUS=$?
}

# 1. A command that is NOT `gh pr create` is none of the gate's business → allow (empty out, exit 0).
d="$(mkrepo)"
gate "ls -la" "$d"
check_status "non-target command → exit 0" 0 "$STATUS"
check_absent "non-target command is allowed (no deny payload)" "$OUT" "deny"
rm -f "$(sentinel_for "$d")"

# 2. `gh pr create` with NO sentinel → deny, telling the user to run /polish.
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")"          # ensure no stale sentinel from a prior run
gate "gh pr create --fill" "$d"
check_status "no sentinel → exit 0 (hook always exits 0)" 0 "$STATUS"
check_contains "no sentinel → deny decision" "$OUT" '"permissionDecision":"deny"'
check_contains "no sentinel → tells the user to run /polish" "$OUT" "run /polish first"

# 2b. S6 (backlog dir #4): `gh pr create` reached via a chain/prefix — not a bare leading-prefix
# match — must still be caught, no sentinel required to prove it: a bare prefix match would have
# let this straight through as a non-target command (test 1's shape) instead of denying it.
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")"
gate "cd /tmp && gh pr create --fill" "$d"
check_contains "chained command still caught → deny decision" "$OUT" '"permissionDecision":"deny"'
gate "GH_TOKEN=x gh pr create --fill" "$d"
check_contains "env-prefixed command still caught → deny decision" "$OUT" '"permissionDecision":"deny"'
gate "foo; gh pr create" "$d"
check_contains "semicolon-chained command still caught → deny decision" "$OUT" '"permissionDecision":"deny"'
gate "env GH_PAGER= gh pr create" "$d"
check_contains "env-wrapped command still caught → deny decision" "$OUT" '"permissionDecision":"deny"'
gate "$(printf 'git push\ngh pr create --fill')" "$d"
check_contains "multiline command still caught → deny decision" "$OUT" '"permissionDecision":"deny"'
# backlog dir #58: the lexical (awk lexer) fast-exit closes the `gh <global-flag> pr create` bypass
# that the substring match (S6/dir #4) documented as a known residual gap — flip that doc note here.
gate "gh --repo owner/name pr create" "$d"
check_contains "global-flag-before-subcommand bypass now caught → deny decision" "$OUT" '"permissionDecision":"deny"'
# inline /polish review catch: a real command chained AFTER a heredoc marker on the SAME line
# (`cmd <<EOF && gh pr create`) is not heredoc body — only the "<<[-]DELIM" token itself is heredoc
# syntax; the trailing `&& gh pr create` executes once the heredoc's own command finishes and must
# stay in scope. An earlier draft of the lexer dropped everything after "<<" on the line, missing this.
gate "cat <<EOF && gh pr create --fill" "$d"
check_contains "command chained after a same-line heredoc marker still caught → deny decision" "$OUT" '"permissionDecision":"deny"'
# dir #63 sibling fix: `gh api` opens a PR without the `pr create` subcommand, so the token scan
# never saw it — and it is exactly what gets reached for once `gh pr create` is denied. Caught only
# when it is a genuine WRITE to a pulls collection (see 2c-bis for the reads that must stay allowed).
gate "gh api repos/owner/name/pulls -f head=branch -f base=main" "$d"
check_contains "gh api pulls with fields caught → deny decision" "$OUT" '"permissionDecision":"deny"'
gate "gh api --method POST repos/owner/name/pulls" "$d"
check_contains "gh api pulls with explicit POST caught → deny decision" "$OUT" '"permissionDecision":"deny"'
gate "gh api -X POST repos/owner/name/pulls --input body.json" "$d"
check_contains "gh api pulls with -X POST caught → deny decision" "$OUT" '"permissionDecision":"deny"'

# 2c. backlog dir #58: the lexer fast-exit must NOT false-fire on a command that merely CONTAINS the
# phrase outside real command position (prose, a quoted/heredoc string) — the felt cost of the old
# substring match (S6/dir #4), which denied unrelated KB writes because their TEXT mentioned the
# phrase and swallowed the rest of their `&&` chain. No sentinel required: these must allow outright.
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")"
gate "echo gh pr create" "$d"
check_absent "prose after echo → allowed (no deny payload)" "$OUT" "deny"
gate 'echo "gh pr create"' "$d"
check_absent "quoted prose after echo → allowed (no deny payload)" "$OUT" "deny"
gate 'git commit -m "wire gh pr create gate"' "$d"
check_absent "phrase inside a commit message string → allowed" "$OUT" "deny"
gate "grep -c 'gh pr create' f" "$d"
check_absent "phrase inside a single-quoted grep pattern → allowed" "$OUT" "deny"
# 2c-bis (dir #63 sibling fix): the `gh api` catch above must not swallow READS. This gate blocks
# opening a PR, not looking at one — a denied `gh api .../pulls/123` would break status checks and
# teach the next session that the gate is noise.
gate "gh api repos/owner/name/pulls" "$d"
check_absent "gh api pulls list (no write flags) → allowed" "$OUT" "deny"
gate "gh api repos/owner/name/pulls/123" "$d"
check_absent "gh api single-PR read → allowed" "$OUT" "deny"
gate "gh api repos/owner/name/pulls/123/comments -f body=hi" "$d"
check_absent "gh api comment on an existing PR → allowed" "$OUT" "deny"
# An explicit method beats the fields-imply-POST inference: for a GET, `-f` sets query parameters,
# so this is a listing, not a create. Inferring "write" from the flag alone denied exactly the read
# the catch above promises to leave alone.
gate "gh api -X GET repos/owner/name/pulls -f state=open -f per_page=50" "$d"
check_absent "gh api -X GET pulls with fields → allowed" "$OUT" "deny"
gate "gh api --method GET repos/owner/name/pulls -f state=open" "$d"
check_absent "gh api --method GET pulls with fields → allowed" "$OUT" "deny"
gate "$(printf "cat >> notes.md <<'EOF'\nsome text mentioning gh pr create here\nEOF\n")" "$d"
check_absent "phrase mid-prose inside a heredoc body → allowed" "$OUT" "deny"
gate "$(printf "cat >> notes.md <<'EOF'\ngh pr create is a doc-snippet line\nEOF\n")" "$d"
check_absent "phrase starting a heredoc body line → allowed (proves the heredoc strip, not just command position)" "$OUT" "deny"

# 3. THE bypass case: a bare `touch` (empty sentinel, current behaviour) must NOT unlock the gate.
d="$(mkrepo)"
: > "$(sentinel_for "$d")"            # the `touch` bypass attempt
gate "gh pr create --fill" "$d"
check_contains "empty sentinel (bare touch) → still denied" "$OUT" '"permissionDecision":"deny"'
check_contains "empty/malformed sentinel → reported as malformed" "$OUT" "malformed"
check_nofile "a rejected sentinel is removed" "$(sentinel_for "$d")"

# 4. A complete receipt (all step ids, nonce-matching) but polish.8-unlock's SHA is STALE (HEAD moved on).
d="$(mkrepo)"
write_full_receipt "$d"
git -C "$d" commit --allow-empty -qm second      # HEAD advances past the recorded SHA
gate "gh pr create --fill" "$d"
check_contains "stale-SHA receipt → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "stale-SHA receipt → reported as stale" "$OUT" "stale"
check_nofile "stale sentinel is removed" "$(sentinel_for "$d")"

# 5. A complete receipt with the CURRENT HEAD SHA (what /polish's step 8 writes) → allow, one-shot consume.
d="$(mkrepo)"
write_full_receipt "$d"
gate "gh pr create --fill" "$d"
check_status "matching receipt → exit 0" 0 "$STATUS"
check_absent "matching receipt → allowed (no deny payload)" "$OUT" "deny"
check_nofile "the sentinel is consumed (one-shot, removed after a pass)" "$(sentinel_for "$d")"

# 6. Edge: a matching-looking request whose cwd is not a git repo → HEAD SHA is empty → deny (fail safe).
d="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
printf 'whatever' > "$(sentinel_for "$d")"
gate "gh pr create --fill" "$d"
check_contains "non-git cwd → denied, never silently allowed" "$OUT" '"permissionDecision":"deny"'
rm -f "$(sentinel_for "$d")"

# --- receipt completeness (dir #49) --------------------------------------------------------------
# 7. Missing one step id (the rest complete, current nonce, matching SHA) → deny naming that id.
d="$(mkrepo)"
write_full_receipt "$d" "polish.3-tests"
gate "gh pr create --fill" "$d"
check_contains "missing-step receipt → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "missing-step receipt → names the missing id" "$OUT" "polish.3-tests"
check_nofile "incomplete sentinel is removed" "$(sentinel_for "$d")"

# 8. Stale-nonce replay: the missing id's only line carries a DIFFERENT (earlier-run) nonce, not the
# current header's — a leftover line from a previous run must not count toward completeness.
d="$(mkrepo)"
write_full_receipt "$d" "" "polish.5-review"
gate "gh pr create --fill" "$d"
check_contains "stale-nonce replay → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "stale-nonce replay → names the affected id" "$OUT" "polish.5-review"
check_contains "stale-nonce replay → reported as a replay, not a plain miss" "$OUT" "stale nonce"
check_nofile "replayed sentinel is removed" "$(sentinel_for "$d")"

# 9. Conditional steps skipped-with-outcome still count as present (set-completeness, no order check).
# polish.5-review uses a trusted (-operator-run) outcome here — this test is about the OTHER
# skipped-with-outcome steps, not the dir #63 trace check, which gets its own tests below.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests "skipped:--no-test"
run_in "$d" bash "$gate" receipt polish.4-depth low
run_in "$d" bash "$gate" receipt polish.5-review low-operator-run
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.7-selfcheck "skipped:no-doctor"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_status "skipped-with-outcome steps still pass → exit 0" 0 "$STATUS"
check_absent "skipped-with-outcome steps still pass → allowed" "$OUT" "deny"

# --- CLI subcommands: init / receipt -------------------------------------------------------------
# 10. `receipt` before `init` refuses (no active receipt to append to).
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")"
run_in "$d" bash "$gate" receipt polish.1-diff
check_status "receipt before init → non-zero exit" 1 "$STATUS"
check_contains "receipt before init → tells the user to run init" "$OUT" "init"
rm -f "$(sentinel_for "$d")"

# 11. `init` mints a fresh nonce and discards a previous run's leftover lines.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
old_nonce="$(awk -F'\t' 'NR==1{print $2}' "$(sentinel_for "$d")")"
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" init
new_nonce="$(awk -F'\t' 'NR==1{print $2}' "$(sentinel_for "$d")")"
lines="$(wc -l < "$(sentinel_for "$d")" | tr -d ' ')"
if [ "$old_nonce" != "$new_nonce" ] && [ "$lines" = "1" ]; then
  pass "re-running init mints a new nonce and clears prior step lines"
else
  fail "re-running init mints a new nonce and clears prior step lines" "nonces: $old_nonce / $new_nonce, lines: $lines"
fi
rm -f "$(sentinel_for "$d")"

# --- impact instrumentation: guardrail-fire event on deny ---------------------------------------
# A deny (here: no sentinel → run /polish first) records ONE metadata-only guard event when tracking is on
# (via $KEEL_IMPACT_LOG or the target repo's .keel/ marker), on the log file only — never on stdout, so the
# hook's JSON decision stays intact.
d="$(mkrepo)"; rm -f "$(sentinel_for "$d")"
imp_log="$SANDBOX/pprg-events.log"; rm -f "$imp_log"
json="$(jq -n --arg c "gh pr create --fill" --arg d "$d" '{tool_input:{command:$c}, cwd:$d}')"

# (a) explicit override
out="$(printf '%s' "$json" | KEEL_IMPACT_LOG="$imp_log" bash "$gate" 2>/dev/null)"
check_contains "deny still emits the deny payload on stdout" "$out" '"permissionDecision":"deny"'
check_absent "stdout is not polluted by the event line" "$out" "pre-pr-gate	blocked"
check_file "deny records an impact event when opted in" "$imp_log"
check_contains "event is a guard/pre-pr-gate line" "$(cat "$imp_log" 2>/dev/null)" "	guard	pre-pr-gate	blocked"
check_contains "a receipt-deny event is also recorded (no-run)" "$(cat "$imp_log" 2>/dev/null)" "	receipt-deny	pre-pr-gate	no-run"

# (b) per-repo .keel/ marker, NO env — resolved from the hook's cwd ($d)
mkdir -p "$d/.keel"; rm -f "$(sentinel_for "$d")"
printf '%s' "$json" | env -u KEEL_IMPACT_LOG bash "$gate" >/dev/null 2>&1
check_file "marker alone records the deny event (no env)" "$d/.keel/impact-events.log"
check_contains "marker event is a guard/pre-pr-gate line" "$(cat "$d/.keel/impact-events.log" 2>/dev/null)" "	guard	pre-pr-gate	blocked"

# (c) no override AND no marker → nothing written
d2="$(mkrepo)"; rm -f "$(sentinel_for "$d2")"
json2="$(jq -n --arg c "gh pr create --fill" --arg d "$d2" '{tool_input:{command:$c}, cwd:$d}')"
printf '%s' "$json2" | env -u KEEL_IMPACT_LOG bash "$gate" >/dev/null 2>&1
check_nofile "no event written without override or marker" "$d2/.keel/impact-events.log"

# (d) a clean pass records a receipt-pass event too.
d="$(mkrepo)"
write_full_receipt "$d"
imp_log2="$SANDBOX/pprg-events-pass.log"; rm -f "$imp_log2"
out="$(KEEL_IMPACT_LOG="$imp_log2" bash "$gate" <<<"$(jq -n --arg c "gh pr create --fill" --arg d "$d" '{tool_input:{command:$c}, cwd:$d}')" 2>&1)"
check_absent "a clean pass emits no deny payload" "$out" "deny"
check_contains "a clean pass records a receipt-pass event" "$(cat "$imp_log2" 2>/dev/null)" "	receipt-pass	pre-pr-gate	"
check_contains "the receipt-pass event's detail carries the provenance classification (dir #64)" "$(cat "$imp_log2" 2>/dev/null)" "	receipt-pass	pre-pr-gate	review: medium, operator-run (self-reported)"

# (e) `pre-pr-gate.sh log` appends an arbitrary verdict/friction line for the current run.
d="$(mkrepo)"
mkdir -p "$d/.keel"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" log receipt-verdict "true-catch polish.3-tests"
check_contains "log subcommand appends the given type/detail" "$(cat "$d/.keel/impact-events.log" 2>/dev/null)" "	receipt-verdict	pre-pr-gate	true-catch polish.3-tests"

# --- dir #61: worktree/event-cwd resolution ------------------------------------------------------
# Felt bug: /polish writes receipts from inside a linked worktree, but the `gh pr create` hook event's
# cwd can report a DIFFERENT checkout of the same repo (the harness's tracked session-root cwd does
# not track an in-command `cd`) — e.g. the main checkout. Before the fix, the sentinel path (keyed by
# raw basename) and the SHA check (bare `rev-parse HEAD` of that wrong cwd) both missed.

# A main repo + a linked worktree on a fresh branch, with one commit in the worktree (so the
# worktree's HEAD differs from the main checkout's). Sets MREPO/WT. $1 = worktree dir name (under
# $SANDBOX), $2 = branch name.
mkworktree() {
  MREPO="$(mkrepo)"
  WT="$SANDBOX/$1"
  git -C "$MREPO" worktree add -q -b "$2" "$WT" >/dev/null 2>&1
  git -C "$WT" commit --allow-empty -qm "feature work"
}

# 12. Receipt written from a worktree is found via a hook event whose cwd is the MAIN checkout, and an
# explicit --head names the branch actually being PR'd, so the SHA check compares against ITS tip —
# not the main checkout's own (different) HEAD.
mkworktree dir61-wt dir61-feature
check_dir "dir #61 worktree fixture exists" "$WT"
write_full_receipt "$WT"
check_file "receipt lands under the MAIN checkout's sentinel, not the worktree's" "$(sentinel_for "$MREPO")"
check_nofile "no stray sentinel under the worktree's own basename" "$(sentinel_for "$WT")"
gate "gh pr create --head dir61-feature --fill" "$MREPO"
check_status "worktree receipt + --head, hook cwd = main checkout → exit 0" 0 "$STATUS"
check_absent "worktree receipt + --head → allowed (no deny payload)" "$OUT" "deny"
check_nofile "the sentinel is consumed" "$(sentinel_for "$MREPO")"

# 13. Same setup, but the command carries NO --head — the gate has no way to know which branch is
# meant, so it falls back to bare HEAD of the reported cwd (the main checkout's OWN branch): a genuine
# mismatch against the worktree-recorded SHA, correctly denied (not a false allow).
mkworktree dir61-wt-nohead dir61-feature2
write_full_receipt "$WT"
gate "gh pr create --fill" "$MREPO"
check_contains "worktree receipt, no --head, hook cwd = main checkout → denied (ambiguous branch)" "$OUT" '"permissionDecision":"deny"'
check_contains "denied as a SHA mismatch, not a missing receipt" "$OUT" "stale"

# 14. -H (gh's short flag) and --head=BRANCH (the = form) are both recognized.
mkworktree dir61-wt-short dir61-feature3
write_full_receipt "$WT"
gate "gh pr create -H dir61-feature3 --fill" "$MREPO"
check_status "-H short flag resolves the branch → exit 0" 0 "$STATUS"
check_absent "-H short flag → allowed" "$OUT" "deny"

mkworktree dir61-wt-eq dir61-feature4
write_full_receipt "$WT"
gate "gh pr create --head=dir61-feature4 --fill" "$MREPO"
check_status "--head=BRANCH form resolves the branch → exit 0" 0 "$STATUS"
check_absent "--head=BRANCH form → allowed" "$OUT" "deny"

# The `gh api` create path carries its branch as a field, not a --head flag. It needs the same dir #61
# resolution, or a fully-polished worktree PR opened that way is denied as an ambiguous branch.
mkworktree dir61-wt-api dir61-feature5
write_full_receipt "$WT"
gate "gh api repos/owner/name/pulls -f head=dir61-feature5 -f base=main" "$MREPO"
check_status "gh api -f head= resolves the branch → exit 0" 0 "$STATUS"
check_absent "gh api -f head= → allowed" "$OUT" "deny"

# Cross-fork head fields carry an `owner:` prefix that is not part of the ref name.
mkworktree dir61-wt-apifork dir61-feature6
write_full_receipt "$WT"
gate "gh api repos/owner/name/pulls -f head=someone:dir61-feature6 -f base=main" "$MREPO"
check_status "gh api cross-fork head= strips the owner prefix → exit 0" 0 "$STATUS"
check_absent "gh api cross-fork head= → allowed" "$OUT" "deny"

# 15. A receipt written AND read from the SAME worktree cwd (the ordinary, non-split case) still works
# unchanged — main_top_for resolves the same main checkout consistently regardless of which member of
# the worktree set is used throughout, so this is not a regression against the pre-fix common case.
mkworktree dir61-wt-same dir61-feature5
write_full_receipt "$WT"
gate "gh pr create --fill" "$WT"
check_status "receipt + hook both from the worktree → exit 0" 0 "$STATUS"
check_absent "receipt + hook both from the worktree → allowed" "$OUT" "deny"

# --- dir #63: skill-invocation trace + nonce-surviving hand-off ----------------------------------
trace_for() { printf '/tmp/pre-pr-gate-trace-%s' "$(repo_key_for "$1")"; }

# 16. A BARE review outcome (a real in-session level, no -operator-run/-waived suffix) with NO
# matching trace at all → denied, naming the trace as the reason (not a generic completeness miss).
d="$(mkrepo)"
rm -f "$(trace_for "$d")"
write_full_receipt_review "$d" "medium"
gate "gh pr create --fill" "$d"
check_contains "bare review outcome, no trace → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "bare review outcome, no trace → names the trace as missing" "$OUT" "no trace matching"
check_nofile "denied-for-trace sentinel is removed" "$(sentinel_for "$d")"

# 17. Same, but a trace file exists for a DIFFERENT (older) commit — still denied; a trace from a
# past run must not vouch for a later, unreviewed commit. Asserts the SPECIFIC trace-missing reason,
# not just "denied for some reason" — the fixture is otherwise a complete, matching receipt, so a
# vaguer check here could pass even if the trace check silently stopped firing.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
printf '%s\tmedium\n' "0000000000000000000000000000000000000000" > "$tf"
write_full_receipt_review "$d" "medium"
gate "gh pr create --fill" "$d"
check_contains "stale-commit trace → still denied" "$OUT" '"permissionDecision":"deny"'
check_contains "stale-commit trace → denied for the trace, not some other reason" "$OUT" "no trace matching"
rm -f "$tf"

# 17b. A trace line for the RIGHT commit but the WRONG level — a cheap `low` review must not vouch
# for a receipt claiming `max` (the exact-level-match half of the trace check).
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
printf '%s\tlow\n' "$(git -C "$d" rev-parse HEAD)" > "$tf"
write_full_receipt_review "$d" "max"
gate "gh pr create --fill" "$d"
check_contains "right commit, wrong trace level → still denied" "$OUT" '"permissionDecision":"deny"'
check_contains "right commit, wrong trace level → denied for the trace, not some other reason" "$OUT" "no trace matching"
rm -f "$tf"

# 18. A trace line matching the CURRENT HEAD SHA → the bare outcome is now trusted, gate passes.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
printf '%s\tmedium\n' "$(git -C "$d" rev-parse HEAD)" > "$tf"
write_full_receipt_review "$d" "medium"
gate "gh pr create --fill" "$d"
check_status "matching-commit trace → exit 0" 0 "$STATUS"
check_absent "matching-commit trace → allowed" "$OUT" "deny"
rm -f "$tf"

# --- dir #63: polish.5-review's outcome must match polish.4-depth's OWN recorded level -----------
# 18b. The `skip` bypass: a session sizes the diff `medium` (polish.4-depth), then simply claims
# `polish.5-review skip` — `skip` needs no trace, so without this cross-check it unlocks the gate on
# one lied-about word regardless of what was actually sized.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests
run_in "$d" bash "$gate" receipt polish.4-depth "medium:+412-96,10f,code"
run_in "$d" bash "$gate" receipt polish.5-review skip
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.7-selfcheck "skipped:no-doctor"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_contains "review 'skip' against a sized-medium depth → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the depth mismatch, not some other reason" "$OUT" "doesn't match the depth"

# 18c. Same shape for a trusted -operator-run outcome: claiming "low-operator-run" against a depth
# actually sized "high" must not unlock the gate either — write_full_receipt_review always matches
# polish.4-depth to the given outcome, so this one is built by hand to deliberately mismatch them.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests
run_in "$d" bash "$gate" receipt polish.4-depth "high:+900-50,15f,code"
run_in "$d" bash "$gate" receipt polish.5-review low-operator-run
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.7-selfcheck "skipped:no-doctor"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_contains "'low-operator-run' against a sized-high depth → denied" "$OUT" '"permissionDecision":"deny"'

# 19. skill-trace subcommand: a PostToolUse(Skill) event for the code-review skill appends a trace
# line keyed by the event's own HEAD SHA.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
sha="$(git -C "$d" rev-parse HEAD)"
json="$(jq -n --arg cwd "$d" '{hook_event_name:"PostToolUse", cwd:$cwd, tool_name:"Skill", tool_input:{skill:"code-review", args:"high"}}')"
printf '%s' "$json" | bash "$gate" skill-trace >/dev/null 2>&1
check_file "skill-trace(PostToolUse code-review) writes a trace file" "$tf"
check_contains "trace line carries the SHA and level" "$(cat "$tf" 2>/dev/null)" "$sha	high"
rm -f "$tf"

# 20. skill-trace ignores a PostToolUse(Skill) event for any OTHER skill (no trace written).
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
json="$(jq -n --arg cwd "$d" '{hook_event_name:"PostToolUse", cwd:$cwd, tool_name:"Skill", tool_input:{skill:"backlog"}}')"
printf '%s' "$json" | bash "$gate" skill-trace >/dev/null 2>&1
check_nofile "skill-trace ignores a non-code-review skill call" "$tf"

# 21. skill-trace also fires on UserPromptExpansion (the operator typing `/code-review <level>`
# directly) — the path that bypasses PostToolUse entirely per Claude Code's hooks reference.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
sha="$(git -C "$d" rev-parse HEAD)"
json="$(jq -n --arg cwd "$d" '{hook_event_name:"UserPromptExpansion", cwd:$cwd, expansion_type:"slash_command", command_name:"code-review", command_args:"ultra"}')"
printf '%s' "$json" | bash "$gate" skill-trace >/dev/null 2>&1
check_file "skill-trace(UserPromptExpansion code-review) writes a trace file" "$tf"
check_contains "operator-typed trace line carries the SHA and level" "$(cat "$tf" 2>/dev/null)" "$sha	ultra"
rm -f "$tf"

# --- dir #63: hand-off note (its own file, nonce-independent, same-SHA-only) ---------------------
handoff_for() { printf '/tmp/pre-pr-gate-handoff-%s' "$(repo_key_for "$1")"; }

# 22. The hand-off note lives in its OWN file — not a line inside the sentinel — so `init`'s nonce
# reset (which discards everything in the sentinel, the dir #49 replay fix) never touches it at all.
d="$(mkrepo)"
sha="$(git -C "$d" rev-parse HEAD)"
hf="$(handoff_for "$d")"; rm -f "$hf"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" handoff medium "$sha"
run_in "$d" bash "$gate" init
check_file "hand-off file survives a re-run of init" "$hf"
check_contains "hand-off file carries the level and SHA" "$(cat "$hf" 2>/dev/null)" "polish.5	medium	$sha"
rm -f "$hf"

# 23. `handoff-check`: a hand-off recorded for the CURRENT HEAD prints it and exits 0; one recorded
# for a different (older) SHA is invisible — any new commit invalidates the replay window.
d="$(mkrepo)"
sha="$(git -C "$d" rev-parse HEAD)"
hf="$(handoff_for "$d")"; rm -f "$hf"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" handoff high "$sha"
run_in "$d" bash "$gate" handoff-check
check_status "handoff-check matches current HEAD → exit 0" 0 "$STATUS"
check_contains "handoff-check prints the matching line" "$OUT" "polish.5	high	$sha"
git -C "$d" commit --allow-empty -qm "moved on"
run_in "$d" bash "$gate" handoff-check
check_status "handoff-check on a NEW commit → exit 1 (replay window is same-SHA only)" 1 "$STATUS"
rm -f "$hf"

# 24. Writing the real `polish.5-review` receipt removes the hand-off file — its job (recording that
# step 5(b) already asked) is done once the question is actually answered.
d="$(mkrepo)"
sha="$(git -C "$d" rev-parse HEAD)"
hf="$(handoff_for "$d")"; rm -f "$hf"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" handoff medium "$sha"
run_in "$d" bash "$gate" receipt polish.5-review "medium-operator-run"
check_nofile "hand-off file removed once the real polish.5-review receipt lands" "$hf"

# 25. dir #61 discipline extended to the trace/hand-off paths: both key off the MAIN checkout, not the
# raw event/PWD cwd — a trace written for a Skill event whose cwd is a worktree, and a hand-off written
# from inside that same worktree, must both land under the MAIN checkout's files, exactly like the
# sentinel already does (tests 12-15). (The trace's SHA/level CONTENT can still be wrong under a split
# session-root/worktree cwd — documented as an accepted residual limit in the gate's own header — this
# test only proves the FILE ITSELF is the one the gate will actually look at.)
mkworktree dir63-wt dir63-feature
sha="$(git -C "$WT" rev-parse HEAD)"
json="$(jq -n --arg cwd "$WT" '{hook_event_name:"PostToolUse", cwd:$cwd, tool_name:"Skill", tool_input:{skill:"code-review", args:"high"}}')"
printf '%s' "$json" | bash "$gate" skill-trace >/dev/null 2>&1
check_file "trace from a worktree event-cwd lands under the MAIN checkout's trace file" "$(trace_for "$MREPO")"
check_nofile "no stray trace file under the worktree's own basename" "$(trace_for "$WT")"
check_contains "the worktree-sourced trace carries the worktree's own SHA" "$(cat "$(trace_for "$MREPO")" 2>/dev/null)" "$sha"
rm -f "$(trace_for "$MREPO")"

run_in "$WT" bash "$gate" init
run_in "$WT" bash "$gate" handoff high "$sha"
check_file "hand-off written from a worktree lands under the MAIN checkout's hand-off file" "$(handoff_for "$MREPO")"
check_nofile "no stray hand-off file under the worktree's own basename" "$(handoff_for "$WT")"
rm -f "$(handoff_for "$MREPO")" "$(sentinel_for "$MREPO")" "$(sentinel_for "$WT")"

# --- dir #64 tier 2a: provenance line on the gate's ALLOW decision -------------------------------
# 26. A trusted "skip" outcome → the provenance line reads "review: skip", no trace involved.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests
run_in "$d" bash "$gate" receipt polish.4-depth "skip:no-code-changes"
run_in "$d" bash "$gate" receipt polish.5-review skip
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.7-selfcheck "skipped:no-doctor"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_status "skip outcome → exit 0" 0 "$STATUS"
check_contains "skip outcome → provenance reads 'review: skip'" "$OUT" "review: skip"

# 27. A trusted -operator-run outcome → provenance names it explicitly self-reported.
d="$(mkrepo)"
write_full_receipt_review "$d" "medium-operator-run"
gate "gh pr create --fill" "$d"
check_contains "operator-run outcome → provenance names it self-reported" "$OUT" "review: medium, operator-run (self-reported)"

# 28. A trusted -waived outcome → provenance names it explicitly self-reported/waived.
d="$(mkrepo)"
write_full_receipt_review "$d" "high-waived"
gate "gh pr create --fill" "$d"
check_contains "waived outcome → provenance names it self-reported/waived" "$OUT" "review: high, waived (self-reported)"

# 29. A bare outcome backed by a matching mechanical trace → provenance says so explicitly, the
# whole point of dir #63's trace being visible at PR-creation time, not just transcript archaeology.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
printf '%s\tmedium\n' "$(git -C "$d" rev-parse HEAD)" > "$tf"
write_full_receipt_review "$d" "medium"
gate "gh pr create --fill" "$d"
check_contains "trace-confirmed outcome → provenance names the mechanical trace" "$OUT" "review: medium, trace-confirmed in-session"
rm -f "$tf"

# --- dir #64 tier 1: rollout-check (SessionStart hook) --------------------------------------------
rollout_state_for() { printf '/tmp/pre-pr-gate-rollout-%s' "$(repo_key_for "$1")"; }

# A fake `claude` binary on PATH so version-drift assertions don't depend on whatever real Claude
# Code build happens to be installed on the machine running these tests. $1 = version text to print.
fake_claude_bin() {
  local dir; dir="$(mktemp -d "$SANDBOX/fakeclaude.XXXXXX")"
  printf '#!/bin/sh\nprintf "%s (Claude Code)\\n"\n' "$1" > "$dir/claude"
  chmod +x "$dir/claude"
  printf '%s' "$dir"
}

# Drive rollout-check: $1 = model (empty string = field omitted, simulating a model-less event),
# $2 = cwd, $3 = a PATH-prepend dir holding the fake `claude` binary. Pins KEEL_IMPACT_LOG to $rimp
# (set by the caller below) so the pipeline-drift assertions read a known file, not lib.sh's ambient
# sandbox-wide default.
rc_gate() {
  local model="$1" cwd="$2" claudebin="$3" json
  json="$(jq -n --arg m "$model" --arg d "$cwd" '{cwd:$d} + (if $m == "" then {} else {model:$m} end)')"
  OUT="$(printf '%s' "$json" | PATH="$claudebin:$PATH" KEEL_IMPACT_LOG="$rimp" bash "$gate" rollout-check 2>&1)"
  STATUS=$?
}

d="$(mkrepo)"
rstate="$(rollout_state_for "$d")"; rm -f "$rstate"
cb1="$(fake_claude_bin "1.0.0")"
rimp="$SANDBOX/rollout-events.log"; rm -f "$rimp"

# 30. First-ever session for a repo: nothing to compare against yet → records a baseline, no banner.
rc_gate "claude-sonnet-5" "$d" "$cb1"
check_status "rollout-check always exits 0" 0 "$STATUS"
check_absent "first session for a repo → no drift banner (nothing to compare yet)" "$OUT" "systemMessage"
check_file "first session records a baseline state file" "$rstate"
check_contains "baseline records the model" "$(cat "$rstate" 2>/dev/null)" "model	claude-sonnet-5"
check_contains "baseline records the harness version" "$(cat "$rstate" 2>/dev/null)" "version	1.0.0 (Claude Code)"

# 31. Same model, same harness version next session → silent, no false positive.
rc_gate "claude-sonnet-5" "$d" "$cb1"
check_absent "unchanged model+version → no drift banner" "$OUT" "systemMessage"

# 32. Model changed since the last session → banner fires, names old and new, and logs a
# pipeline-drift event (metadata only, same log-file-not-stdout discipline as the other events).
rc_gate "claude-opus-5" "$d" "$cb1"
check_contains "model change → drift banner fires" "$OUT" "systemMessage"
check_contains "banner names the old and new model" "$OUT" "model (claude-sonnet-5 -> claude-opus-5)"
check_contains "model change logs a pipeline-drift event" "$(cat "$rimp" 2>/dev/null)" "	pipeline-drift	pre-pr-gate	model (claude-sonnet-5 -> claude-opus-5)"

# 33. Having settled on the new model, the NEXT session with that same model is silent again.
rc_gate "claude-opus-5" "$d" "$cb1"
check_absent "settled on the new model → no repeat banner" "$OUT" "systemMessage"

# 34. Harness version changed (same model) → banner fires for the version, not the model.
cb2="$(fake_claude_bin "2.0.0")"
rc_gate "claude-opus-5" "$d" "$cb2"
check_contains "harness version change → drift banner fires" "$OUT" "systemMessage"
check_contains "banner names the old and new harness version" "$OUT" "harness (1.0.0 (Claude Code) -> 2.0.0 (Claude Code))"

# 35. A model-less SessionStart event (e.g. immediately after /clear, per the hooks reference) must
# not be misread as "model changed to empty" — an unknown reading is "can't tell", not "changed".
rc_gate "" "$d" "$cb2"
check_absent "empty model field this run → no false drift (can't tell, not changed)" "$OUT" "systemMessage"
rm -f "$rstate"

# --- dir #64 tier 2b: sweep — warn on K consecutive self-reported-only passes --------------------
d="$(mkrepo)"; mkdir -p "$d/.keel"
ilog="$d/.keel/impact-events.log"; rm -f "$ilog"

# 36. No impact log yet → nothing to check, exits clean.
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "sweep with no impact log → exit 0 (nothing to check)" 0 "$STATUS"

# 37. Fewer than K consecutive self-reported passes (default K=3) → OK, exit 0.
{
  printf '2026-07-27T00:00:00Z\treceipt-pass\tpre-pr-gate\treview: medium, trace-confirmed in-session\n'
  printf '2026-07-27T00:01:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\n'
  printf '2026-07-27T00:02:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\n'
} > "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "2 consecutive self-reported passes (K=3 default) → exit 0" 0 "$STATUS"

# 38. K consecutive passes with NO trace-confirmed among them → warns, non-zero exit (advisory only —
# the sweep never blocks anything itself, it's a /wrap-time read, not a gate).
{
  printf '2026-07-27T00:03:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\n'
} >> "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "3 consecutive self-reported passes → non-zero (advisory warn)" 1 "$STATUS"
check_contains "warns naming the threshold" "$OUT" "3+ consecutive"

# 39. The sweep is read-only — the impact log is untouched (unlike `add`'s ingest-and-truncate).
check_contains "sweep does not truncate the impact log" "$(cat "$ilog" 2>/dev/null)" "receipt-pass"

# 40. A trace-confirmed pass anywhere in the last K breaks the streak → OK again.
{
  printf '2026-07-27T00:04:00Z\treceipt-pass\tpre-pr-gate\treview: high, trace-confirmed in-session\n'
} >> "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "a trace-confirmed pass within the window → exit 0 again" 0 "$STATUS"

# --- dir #64: repo-key subcommand (so other tools reuse the worktree-aware resolution instead of
# hand-copying it — pipeline-canary.sh calls this rather than re-deriving basename(toplevel) itself) ---
d="$(mkrepo)"
run "$gate" repo-key "$d"
check_status "repo-key → exit 0" 0 "$STATUS"
check_contains "repo-key of a plain repo is its own basename" "$OUT" "$(basename "$d")"

mkworktree dir64-repokey-wt dir64-repokey-feature
run "$gate" repo-key "$WT"
check_contains "repo-key of a worktree resolves to the MAIN checkout's basename (dir #61 discipline), not its own" "$OUT" "$(basename "$MREPO")"
check_absent "repo-key does not just basename the worktree itself" "$OUT" "$(basename "$WT")"

summary
