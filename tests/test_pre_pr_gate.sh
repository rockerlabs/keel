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
# dir #80: the receipt's REAL key mixes the MAIN checkout's repo component with the WORKTREE's own
# branch component (each worktree has an independently checked-out branch) — real_sentinel_for(MREPO,
# WT), not sentinel_for(MREPO) (which would use MREPO's OWN branch, a different file that nothing wrote).
check_file "receipt lands under the MAIN checkout's sentinel, not the worktree's" "$(real_sentinel_for "$MREPO" "$WT")"
check_nofile "no stray sentinel under the worktree's own basename" "$(sentinel_for "$WT")"
gate "gh pr create --head dir61-feature --fill" "$MREPO"
check_status "worktree receipt + --head, hook cwd = main checkout → exit 0" 0 "$STATUS"
check_absent "worktree receipt + --head → allowed (no deny payload)" "$OUT" "deny"
check_nofile "the sentinel is consumed" "$(real_sentinel_for "$MREPO" "$WT")"

# 13. Same setup, but the command carries NO --head — dir #80: the sentinel is now keyed by (repo,
# branch), so the hook (falling back to the MAIN checkout's OWN, different branch) doesn't even share
# a sentinel FILE with the worktree-written receipt — denied as "no receipt", not a SHA mismatch (the
# old repo-only keying's behavior, where both sides shared one file and only the SHA disagreed). Still
# a deny either way — the ambiguity is now caught one step earlier, by key rather than by content.
mkworktree dir61-wt-nohead dir61-feature2
write_full_receipt "$WT"
gate "gh pr create --fill" "$MREPO"
check_contains "worktree receipt, no --head, hook cwd = main checkout → denied (ambiguous branch)" "$OUT" '"permissionDecision":"deny"'
check_contains "denied as no-receipt (repo+branch key doesn't match the worktree's), not a false allow" "$OUT" "run /polish first"

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
# directly) — the path that bypasses PostToolUse entirely per Claude Code's hooks reference. Fixture
# carries the full documented field set (expansion_type/command_name/command_args/command_source/prompt),
# matching the literal JSON example at code.claude.com/docs/en/hooks.md#userpromptexpansion — see the
# skill-trace case's own TO-VERIFY-resolved comment in tools/pre-pr-gate.sh for the citation.
# `command_source`/`prompt` aren't read by the parser (it only extracts `command_name`/`command_args`) —
# they're here so the fixture proves a real event's extra fields don't upset the extraction, not just
# that the two consumed ones parse in isolation.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
sha="$(git -C "$d" rev-parse HEAD)"
json="$(jq -n --arg cwd "$d" '{hook_event_name:"UserPromptExpansion", cwd:$cwd, expansion_type:"slash_command", command_name:"code-review", command_args:"ultra", command_source:"user", prompt:"/code-review ultra"}')"
printf '%s' "$json" | bash "$gate" skill-trace >/dev/null 2>&1
check_file "skill-trace(UserPromptExpansion code-review) writes a trace file" "$tf"
check_contains "operator-typed trace line carries the SHA and level" "$(cat "$tf" 2>/dev/null)" "$sha	ultra"
rm -f "$tf"

# --- dir #63: hand-off note (its own file, nonce-independent, same-SHA-only) ---------------------
# dir #80: hand-off is now keyed by (repo, branch) too — see lib.sh's sentinel_for/real_key_for for
# the naive-vs-real distinction the dir #61 worktree tests (below) need.
handoff_for() { printf '/tmp/pre-pr-gate-handoff-%s-%s' "$(repo_key_for "$1")" "$(branch_key_for "$1")"; }
# dir #80: the real hand-off path for a (repo dir, branch-source dir) pair — same wrapping as
# lib.sh's real_sentinel_for, for the same dir #61 worktree tests.
real_handoff_for() { printf '/tmp/pre-pr-gate-handoff-%s' "$(real_key_for "$1" "$2")"; }

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
# dir #80: same real-vs-naive-key distinction as the sentinel (test 12 above) — the hand-off note is
# now (repo, branch)-keyed too.
check_file "hand-off written from a worktree lands under the MAIN checkout's hand-off file" "$(real_handoff_for "$MREPO" "$WT")"
check_nofile "no stray hand-off file under the worktree's own basename" "$(handoff_for "$WT")"
rm -f "$(real_handoff_for "$MREPO" "$WT")" "$(real_sentinel_for "$MREPO" "$WT")" "$(sentinel_for "$MREPO")" "$(sentinel_for "$WT")"

# --- dir #64 tier 2a: provenance line on the gate's ALLOW decision -------------------------------
# 26. A trusted "skip" outcome → the provenance line reads "review: skip", no trace involved.
d="$(mkrepo)"
write_full_receipt_review "$d" "skip"
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

# 35b. dir #64/operator-run /code-review high fix: the model-less session above must NOT have erased
# the last-known-good baseline — the state file should still read the LAST REAL model (opus), not "".
check_contains "a model-less session preserves the last-known model in the state file" "$(cat "$rstate" 2>/dev/null)" "model	claude-opus-5"

# 35c. Proof the baseline really survived: the NEXT session with a genuinely different model still
# fires a drift banner comparing against the PRESERVED value, not against an erased "".
rc_gate "claude-sonnet-5" "$d" "$cb2"
check_contains "a real change after a model-less session still fires (baseline wasn't erased)" "$OUT" "systemMessage"
check_contains "banner compares against the preserved prior model, not an erased blank" "$OUT" "model (claude-opus-5 -> claude-sonnet-5)"
rm -f "$rstate"

# --- dir #64 tier 2b: sweep — warn on K consecutive self-reported-only passes --------------------
d="$(mkrepo)"; mkdir -p "$d/.keel"
ilog="$d/.keel/impact-events.log"; rm -f "$ilog"

# 36. No impact log yet → nothing to check, exits clean.
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "sweep with no impact log → exit 0 (nothing to check)" 0 "$STATUS"

# 37. Fewer than K consecutive self-reported passes (default K=3) → OK, exit 0. Rows carry a 5th
# tab field ($5 = the stable machine tag `sweep` actually reads) alongside the human-display $4.
{
  printf '2026-07-27T00:00:00Z\treceipt-pass\tpre-pr-gate\treview: medium, trace-confirmed in-session\ttrace-confirmed\n'
  printf '2026-07-27T00:01:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\tself-reported\n'
  printf '2026-07-27T00:02:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\tself-reported\n'
} > "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "2 consecutive self-reported passes (K=3 default) → exit 0" 0 "$STATUS"

# 38. K consecutive passes with NO trace-confirmed among them → warns, non-zero exit (advisory only —
# the sweep never blocks anything itself, it's a /wrap-time read, not a gate).
{
  printf '2026-07-27T00:03:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\tself-reported\n'
} >> "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "3 consecutive self-reported passes → non-zero (advisory warn)" 1 "$STATUS"
check_contains "warns naming the threshold" "$OUT" "3+ consecutive"

# 39. The sweep is read-only — the impact log is untouched (unlike `add`'s ingest-and-truncate).
check_contains "sweep does not truncate the impact log" "$(cat "$ilog" 2>/dev/null)" "receipt-pass"

# 40. A trace-confirmed pass anywhere in the last K breaks the streak → OK again.
{
  printf '2026-07-27T00:04:00Z\treceipt-pass\tpre-pr-gate\treview: high, trace-confirmed in-session\ttrace-confirmed\n'
} >> "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "a trace-confirmed pass within the window → exit 0 again" 0 "$STATUS"

# 40b. dir #64/operator-run /code-review high fix: a repo with FEWER than K total receipt-pass rows,
# every one of them non-trace-confirmed, must still warn — the pre-fix version fell through to "OK"
# just because it hadn't yet accumulated K runs, exactly the blind spot sweep exists to catch.
d2="$(mkrepo)"; mkdir -p "$d2/.keel"
ilog2="$d2/.keel/impact-events.log"
{
  printf '2026-07-27T00:00:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\tself-reported\n'
} > "$ilog2"
run_in "$d2" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "1 self-reported pass, fewer than K total → still warns (all history is bad)" 1 "$STATUS"

# 40c. Same short-history shape, but the only row IS trace-confirmed → OK (nothing bad to warn about).
{
  printf '2026-07-27T00:00:00Z\treceipt-pass\tpre-pr-gate\treview: medium, trace-confirmed in-session\ttrace-confirmed\n'
} > "$ilog2"
run_in "$d2" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "1 trace-confirmed pass, fewer than K total → exit 0" 0 "$STATUS"

# 40d. An impact log with events but NO receipt-pass rows at all (e.g. only guard/deny events) → OK,
# not a false warning — there is nothing to judge yet, not "everything so far is bad".
d3="$(mkrepo)"; mkdir -p "$d3/.keel"
printf '2026-07-27T00:00:00Z\tguard\tpre-pr-gate\tblocked\n' > "$d3/.keel/impact-events.log"
run_in "$d3" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "no receipt-pass rows at all → exit 0 (nothing to judge yet)" 0 "$STATUS"

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

# --- dir #70: the independent-agent-review leg (SubagentStop trace + agent:<level> outcome) -------
# Feeds a synthetic SubagentStop event to skill-trace. $1 = repo dir, $2 = agent_type, $3 = the
# last_assistant_message text (may be multi-line — real review write-ups are).
subagentstop_trace() {
  local d="$1" agent_type="$2" msg="$3" json
  json="$(jq -n --arg cwd "$d" --arg at "$agent_type" --arg msg "$msg" \
    '{hook_event_name:"SubagentStop", cwd:$cwd, agent_type:$at, agent_id:"test-agent-id", last_assistant_message:$msg}')"
  OUT="$(printf '%s' "$json" | bash "$gate" skill-trace 2>&1)"
  STATUS=$?
}

# 41. A SubagentStop(general-purpose) event whose final text carries the marker line (on its own
# line, amid other prose — a real review write-up isn't just the marker) writes an `agent:<level>`
# trace line keyed by the hook's OWN observed HEAD sha, never a self-reported one.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
sha="$(git -C "$d" rev-parse HEAD)"
subagentstop_trace "$d" "general-purpose" "$(printf 'Reviewed the diff, no issues found.\nKEEL-AGENT-REVIEW: level=high\n')"
check_status "SubagentStop(general-purpose) with marker → exit 0" 0 "$STATUS"
check_file "SubagentStop(general-purpose) with marker writes a trace file" "$tf"
check_contains "trace line carries the sha and the agent:<level> tag" "$(cat "$tf" 2>/dev/null)" "$sha	agent:high"
rm -f "$tf"

# 42. Regression guard for the newline-truncation bug found while building this leg: bash `read`
# stops at the first embedded newline regardless of what IFS is set to, so a naive single-`read`
# extraction of `last_assistant_message` alongside the other (single-line) fields would silently see
# only the message's FIRST line — above the marker — and never find it. The marker line above is
# NOT the first line, so this only passes if the multi-line message is read in full.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
subagentstop_trace "$d" "general-purpose" "$(printf 'Line one.\nLine two.\nLine three.\nKEEL-AGENT-REVIEW: level=medium\n')"
check_file "marker found even several lines into the message (no newline truncation)" "$tf"
rm -f "$tf"

# 43. A non-`general-purpose` agent_type is ignored (no trace) — the hook's own defense-in-depth
# check, redundant with the install-time matcher but exercised directly here.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
subagentstop_trace "$d" "Explore" "$(printf 'Reviewed.\nKEEL-AGENT-REVIEW: level=high\n')"
check_nofile "SubagentStop for a non-general-purpose agent_type is ignored" "$tf"

# 44. A general-purpose SubagentStop with NO marker line at all is ignored — this fires on every
# ordinary general-purpose subagent call in a session, not just polish's review, so silence here is
# the common case, not an error.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
subagentstop_trace "$d" "general-purpose" "Just some unrelated subagent output, no marker here."
check_nofile "SubagentStop with no marker line is ignored" "$tf"

# 45. A marker naming a level outside the accepted set (skip/ultra never reach this leg — skip does
# no review at all, ultra always hands off to the human) is ignored, not trusted verbatim.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
subagentstop_trace "$d" "general-purpose" "$(printf 'Reviewed.\nKEEL-AGENT-REVIEW: level=ultra\n')"
check_nofile "SubagentStop marker with an out-of-set level (ultra) is ignored" "$tf"

# 46. Gate PASS: an `agent:<level>` receipt backed by a matching SubagentStop trace at the SAME
# commit and level unlocks the gate, with a provenance line naming the independent agent review
# (never presented as if the built-in /code-review itself ran).
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
sha="$(git -C "$d" rev-parse HEAD)"
subagentstop_trace "$d" "general-purpose" "$(printf 'Reviewed. No issues.\nKEEL-AGENT-REVIEW: level=high\n')"
write_full_receipt_review "$d" "agent:high"
gate "gh pr create --fill" "$d"
check_status "agent:<level> receipt + matching trace → exit 0" 0 "$STATUS"
check_absent "agent:<level> receipt + matching trace → allowed" "$OUT" "deny"
check_contains "provenance names the independent agent review, not a built-in /code-review run" "$OUT" "review: high, independent agent review (Skill(code-review) not model-invokable in-session)"
rm -f "$tf"

# 47. Gate DENY: an `agent:<level>` receipt with NO matching trace at all — same bar as a bare-level
# claim with no `/code-review` trace (test 16 above); an agent-review claim is just as fabricable by
# self-report, so it earns no more trust.
d="$(mkrepo)"
rm -f "$(trace_for "$d")"
write_full_receipt_review "$d" "agent:high"
gate "gh pr create --fill" "$d"
check_contains "agent:<level> receipt, no trace → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "agent:<level> receipt, no trace → names the trace as missing" "$OUT" "no trace matching"

# 48. Gate DENY: a trace exists, but for a DIFFERENT level than the receipt claims — a real `agent:low`
# review must not vouch for a receipt claiming `agent:max`.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
printf '%s\tagent:low\n' "$(git -C "$d" rev-parse HEAD)" > "$tf"
write_full_receipt_review "$d" "agent:max"
gate "gh pr create --fill" "$d"
check_contains "agent:<level> receipt, trace at a different level → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the trace, not some other reason" "$OUT" "no trace matching"
rm -f "$tf"

# 49. Gate DENY: `agent:<level>` outcome cross-checked against polish.4-depth's OWN recorded level —
# an agent review claiming `high` must not unlock a diff step 4 actually sized `medium` (same
# depth-consistency cross-check dir #63 built for the bare-level case, extended to this leg).
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests
run_in "$d" bash "$gate" receipt polish.4-depth "medium:+412-96,10f,code"
run_in "$d" bash "$gate" receipt polish.5-review "agent:high"
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.7-selfcheck "skipped:no-doctor"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_contains "'agent:high' against a sized-medium depth → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the depth mismatch, not some other reason" "$OUT" "doesn't match the depth"

# 50. sweep: an "agent-confirmed" pass breaks a self-reported-only streak the same way a
# "trace-confirmed" one does (dir #70: an independent agent review is just as independently
# verifiable as a real in-session /code-review pass — not the self-reported blind spot sweep exists
# to catch).
d="$(mkrepo)"; mkdir -p "$d/.keel"
ilog="$d/.keel/impact-events.log"
{
  printf '2026-07-29T00:00:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\tself-reported\n'
  printf '2026-07-29T00:01:00Z\treceipt-pass\tpre-pr-gate\treview: medium, operator-run (self-reported)\tself-reported\n'
  printf '2026-07-29T00:02:00Z\treceipt-pass\tpre-pr-gate\treview: high, independent agent review (Skill(code-review) not model-invokable in-session)\tagent-confirmed\n'
} > "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "an agent-confirmed pass within the window → exit 0 (breaks the self-reported streak)" 0 "$STATUS"

# 50a. dir #81: Gate PASS for the combined `agent:<level>+operator-run` outcome — the operator
# additionally ran `/code-review` on top of an already-standing, trace-confirmed agent review. The
# trace only ever records the bare `agent:<level>` shape (it predates the operator's pass and knows
# nothing of it), so the gate must strip `+operator-run` before matching, not require the trace to
# carry the suffix too. The provenance line must name BOTH mechanisms, never collapse into one.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
subagentstop_trace "$d" "general-purpose" "$(printf 'Reviewed. No issues.\nKEEL-AGENT-REVIEW: level=high\n')"
write_full_receipt_review "$d" "agent:high+operator-run"
gate "gh pr create --fill" "$d"
check_status "combined agent:<level>+operator-run receipt + matching agent trace → exit 0" 0 "$STATUS"
check_absent "combined receipt + matching trace → allowed" "$OUT" "deny"
check_contains "provenance names BOTH the agent review and the operator-run /code-review" "$OUT" "review: high, independent agent review (trace-confirmed) + operator-run /code-review (self-reported)"
rm -f "$tf"

# 50b. dir #81: Gate DENY for the combined outcome when NO trace exists at all — the agent half is
# still mechanically checked, the operator-run half riding along doesn't exempt it.
d="$(mkrepo)"
rm -f "$(trace_for "$d")"
write_full_receipt_review "$d" "agent:high+operator-run"
gate "gh pr create --fill" "$d"
check_contains "combined receipt, no trace → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "combined receipt, no trace → names the trace as missing" "$OUT" "no trace matching"

# 50c. dir #81: Gate DENY for the combined outcome when a trace exists but at a DIFFERENT level — a
# real `agent:low` review must not vouch for a receipt claiming `agent:max+operator-run`.
d="$(mkrepo)"
tf="$(trace_for "$d")"; rm -f "$tf"
printf '%s\tagent:low\n' "$(git -C "$d" rev-parse HEAD)" > "$tf"
write_full_receipt_review "$d" "agent:max+operator-run"
gate "gh pr create --fill" "$d"
check_contains "combined receipt, trace at a different level → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "combined-receipt denial names the trace, not some other reason" "$OUT" "no trace matching"
rm -f "$tf"

# 50d. dir #81: Gate DENY when the combined outcome's level doesn't match polish.4-depth's OWN
# recorded level — same depth-consistency cross-check dir #63 built for the bare-level case and dir
# #70 extended to the plain agent:<level> case, extended again to the combined shape.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests
run_in "$d" bash "$gate" receipt polish.4-depth "medium:+412-96,10f,code"
run_in "$d" bash "$gate" receipt polish.5-review "agent:high+operator-run"
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.7-selfcheck "skipped:no-doctor"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_contains "'agent:high+operator-run' against a sized-medium depth → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the depth mismatch, not some other reason" "$OUT" "doesn't match the depth"

# 51. Regression guard: a `receipt-pass` row with NO 5th field at all (the shape any repo that
# adopted the gate between dir #49 and dir #64 has in its real history, predating prov_tag) must NOT
# be misread as "verified" just because it isn't literally "self-reported" — an early draft of the
# `!= "self-reported"` streak check (found in this same review pass) treated a blank field as
# verified, silently breaking sweep for exactly the legacy-log case it's supposed to keep catching.
d="$(mkrepo)"; mkdir -p "$d/.keel"
ilog="$d/.keel/impact-events.log"
{
  printf '2026-07-29T00:00:00Z\treceipt-pass\tpre-pr-gate\treview: medium\n'
  printf '2026-07-29T00:01:00Z\treceipt-pass\tpre-pr-gate\treview: medium\n'
  printf '2026-07-29T00:02:00Z\treceipt-pass\tpre-pr-gate\treview: medium\n'
} > "$ilog"
run_in "$d" env -u KEEL_IMPACT_LOG bash "$gate" sweep
check_status "3 consecutive pre-dir-64 rows (no 5th field) → still warns, not misread as verified" 1 "$STATUS"

# 52. `receipt --recover`: no active receipt at all → error, exit 1, points back at `init`.
d="$(mkrepo)"
rm -f "$(sentinel_for "$d")" "$(prev_sentinel_for "$d")"
run_in "$d" bash "$gate" receipt --recover
check_status "recover with no active receipt → exit 1" 1 "$STATUS"
check_contains "recover with no active receipt → tells the user to init first" "$OUT" "no active receipt"

# 53. `receipt --recover`: an active receipt exists, but nothing was ever retired since → error, exit 1
# (a fresh repo's very first /polish run has nothing to recover from — this is not itself a failure).
d="$(mkrepo)"
rm -f "$(prev_sentinel_for "$d")"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt --recover
check_status "recover with nothing retired yet → exit 1" 1 "$STATUS"
check_contains "recover with nothing retired yet → says so" "$OUT" "nothing to recover"

# 54. `receipt --recover`: the felt dir #72 shape end-to-end — a completed run passes the gate (which
# retires its receipt to the single-slot backup), a review-fix commit moves HEAD, and `receipt --recover`
# restores the UNCHANGED steps (1-4, 7) in one call; only the steps that actually changed (5, 6, 8) need a
# fresh `receipt` call, which supersedes the recovered line for that step id (last write wins).
d="$(mkrepo)"
rm -f "$(prev_sentinel_for "$d")"
write_full_receipt "$d"
gate "gh pr create --fill" "$d"
check_status "setup: initial run → exit 0" 0 "$STATUS"
check_absent "setup: initial run → allowed" "$OUT" "deny"
check_file "a successful pass still leaves a recoverable backup (single-slot, not just on deny)" "$(prev_sentinel_for "$d")"
git -C "$d" commit --allow-empty -qm "review fix"    # HEAD moves — the review-fix commit
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt --recover
check_status "recover after the fix-commit's own init → exit 0" 0 "$STATUS"
check_contains "recover reports how many steps it restored" "$OUT" "recovered 8 step receipt(s)"
run_in "$d" bash "$gate" receipt polish.5-review "medium-operator-run"
run_in "$d" bash "$gate" receipt polish.6-retest "skipped:no-file-changes"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_status "recover + only-the-changed-steps rewritten → exit 0" 0 "$STATUS"
check_absent "recover + only-the-changed-steps rewritten → allowed" "$OUT" "deny"
rm -f "$(prev_sentinel_for "$d")"

# 55. `receipt --recover` alone is NOT enough to unlock the gate — a recovered-but-unrefreshed
# `polish.8-unlock` still names the OLD commit's sha, so the gate's own sha check (unchanged by this
# ticket) still denies it. Recover removes the busywork of re-typing what didn't change; it does not
# weaken what the gate actually verifies.
d="$(mkrepo)"
rm -f "$(prev_sentinel_for "$d")"
write_full_receipt "$d"
gate "gh pr create --fill" "$d"
check_status "setup: initial run → exit 0" 0 "$STATUS"
git -C "$d" commit --allow-empty -qm "review fix"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt --recover
gate "gh pr create --fill" "$d"
check_contains "recovered-but-unrefreshed receipt (stale sha) → still denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the stale sha, not silently accepted" "$OUT" "sentinel is stale"
rm -f "$(prev_sentinel_for "$d")"

# 56. Gate DENY: dir #72 finding #1's fix — polish.6-retest is no longer a trust-me completion marker.
# A bare "done" (the pre-fix default outcome, not a sha, not skipped:*) must now be denied.
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests
run_in "$d" bash "$gate" receipt polish.4-depth "medium:test-fixture"
run_in "$d" bash "$gate" receipt polish.5-review "medium-operator-run"
run_in "$d" bash "$gate" receipt polish.6-retest
run_in "$d" bash "$gate" receipt polish.7-selfcheck
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
gate "gh pr create --fill" "$d"
check_contains "polish.6-retest bare 'done' → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the retest receipt, not some other reason" "$OUT" "retest receipt"

# 57. Gate DENY: after `receipt --recover`, if step 8 gets a fresh sha but step 6 is left recovered
# (stale, pre-fix-commit) rather than re-written, the gate now catches THAT too — dir #72 finding #1.
d="$(mkrepo)"
rm -f "$(prev_sentinel_for "$d")"
write_full_receipt "$d"
gate "gh pr create --fill" "$d"
check_status "setup: initial run → exit 0" 0 "$STATUS"
git -C "$d" commit --allow-empty -qm "review fix"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt --recover
run_in "$d" bash "$gate" receipt polish.5-review "medium-operator-run"
run_in "$d" bash "$gate" receipt polish.8-unlock "$(git -C "$d" rev-parse HEAD)"
# deliberately NOT re-writing polish.6-retest — it still carries the prior commit's sha via recovery
gate "gh pr create --fill" "$d"
check_contains "recovered-but-unrefreshed polish.6-retest sha → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied for the retest receipt specifically" "$OUT" "retest receipt"
rm -f "$(prev_sentinel_for "$d")"

# 58. `receipt --recover` refuses a backup whose base-sha is NOT an ancestor of current HEAD — dir #72
# finding #3: an unrelated retirement (simulated here via an orphan branch, standing in for a different
# worktree/branch or a rebase since retirement) must not be silently trusted.
d="$(mkrepo)"
orig_branch="$(git -C "$d" branch --show-current)"
rm -f "$(prev_sentinel_for "$d")"
write_full_receipt "$d"
gate "gh pr create --fill" "$d"
check_status "setup: initial run → exit 0" 0 "$STATUS"
git -C "$d" checkout -q --orphan unrelated
git -C "$d" commit --allow-empty -qm "totally unrelated history"
# dir #80: rename back onto the ORIGINAL branch name — the receipt key now includes the branch, so
# staying on a differently-NAMED branch would miss the prev-sentinel entirely (a "nothing to recover"
# exit 1, not the ancestor-mismatch exit 1 this test wants) rather than reaching the lineage check.
git -C "$d" branch -M "$orig_branch"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt --recover
check_status "recover refuses a non-ancestor backup → exit 1" 1 "$STATUS"
check_contains "refusal names the lineage mismatch" "$OUT" "not a verified ancestor"
rm -f "$(prev_sentinel_for "$d")"

# 59. `receipt --recover` distinguishes a MALFORMED prior receipt (bad/missing nonce header) from a
# genuinely-empty one — dir #72 finding #5.
d="$(mkrepo)"
rm -f "$(prev_sentinel_for "$d")"
write_full_receipt "$d"
gate "gh pr create --fill" "$d"
check_status "setup: initial run → exit 0" 0 "$STATUS"
git -C "$d" commit --allow-empty -qm "review fix"
printf 'not-a-nonce-header\tgarbage\n' > "$(prev_sentinel_for "$d")"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt --recover
check_status "recover on a malformed prior receipt → exit 1" 1 "$STATUS"
check_contains "malformed prior receipt → distinct message" "$OUT" "malformed"
rm -f "$(prev_sentinel_for "$d")"

# --- dir #80: (repo, branch) receipt keying --------------------------------------------------------
# 60. `receipt-key` subcommand exposes the combined key other tools/tests reuse (pipeline-canary.sh's
# own `_receipt_key_of`) instead of hand-copying the branch-sanitization algorithm.
d="$(mkrepo)"
run "$gate" receipt-key "$d"
check_status "receipt-key → exit 0" 0 "$STATUS"
check_contains "receipt-key combines repo basename and branch" "$OUT" "$(basename "$d")-$(git -C "$d" branch --show-current)"

# 61. The ticket's own acceptance test: two interleaved init+receipt sequences on TWO BRANCHES of ONE
# repo (same repo key, different branch — worktrees so both can be "current" at once) never corrupt
# each other. Under the old repo-only keying, branch B's `init` would wipe branch A's in-progress
# receipt (the exact felt incident, dir #62/#79's own /polish runs); here each keeps its own slot.
d="$(mkrepo)"
git -C "$d" branch dir80-featA >/dev/null 2>&1
git -C "$d" branch dir80-featB >/dev/null 2>&1
da="$SANDBOX/dir80-a"; db="$SANDBOX/dir80-b"
git -C "$d" worktree add -q "$da" dir80-featA >/dev/null 2>&1
git -C "$d" worktree add -q "$db" dir80-featB >/dev/null 2>&1
git -C "$da" commit --allow-empty -qm "feat A work"
git -C "$db" commit --allow-empty -qm "feat B work"
write_full_receipt "$da"
write_full_receipt "$db"
# dir #80: $da/$db are worktrees of $d — same real-vs-naive distinction as the dir #61 tests above
# (real_sentinel_for mixes the MAIN checkout's repo component with each worktree's OWN branch); a
# naive sentinel_for("$da") would basename the WORKTREE itself, a different (unwritten) file.
check_file "branch A's sentinel exists" "$(real_sentinel_for "$d" "$da")"
check_file "branch B's sentinel exists independently of branch A's (interleaved init didn't wipe it)" "$(real_sentinel_for "$d" "$db")"
gate "gh pr create --head dir80-featA --fill" "$d"
check_status "branch A's own complete receipt passes independently" 0 "$STATUS"
check_absent "branch A pass → allowed" "$OUT" "deny"
check_file "branch B's sentinel is untouched by branch A's consumption" "$(real_sentinel_for "$d" "$db")"
gate "gh pr create --head dir80-featB --fill" "$d"
check_status "branch B's own complete receipt (never touched by A's run) still passes" 0 "$STATUS"
check_absent "branch B pass → allowed" "$OUT" "deny"
rm -f "$(real_sentinel_for "$d" "$da")" "$(real_sentinel_for "$d" "$db")"

# 62. Hook branch resolution priority: an explicit --head wins over the event cwd's own checked-out
# branch (not just in the worktree shape tests 12-15 above — this isolates the same priority with a
# single checkout switching branches, to prove it's the FLAG being read, not incidentally a worktree
# property).
d="$(mkrepo)"
orig_branch="$(git -C "$d" branch --show-current)"
git -C "$d" branch dir80-other >/dev/null 2>&1
git -C "$d" checkout -q dir80-other
write_full_receipt "$d"
sp="$(sentinel_for "$d")"
git -C "$d" checkout -q "$orig_branch"
gate "gh pr create --head dir80-other --fill" "$d"
check_status "--head names the receipted branch even though cwd checked out a different one → exit 0" 0 "$STATUS"
check_absent "--head resolution wins over cwd's own (different) branch → allowed" "$OUT" "deny"
rm -f "$sp"

# 63. Hook branch resolution failure: a detached-HEAD cwd with no --head resolves no branch at all —
# denied naming the actual problem (dir #80's fix message), not the old generic "run /polish again",
# so the reader knows to pass --head rather than blindly re-running /polish (the felt incidents' 4-5
# blind retries).
d="$(mkrepo)"
git -C "$d" checkout -q --detach >/dev/null 2>&1
gate "gh pr create --fill" "$d"
check_contains "detached HEAD cwd, no --head → denied" "$OUT" '"permissionDecision":"deny"'
check_contains "denied with the branch-resolution message, not a generic run-/polish-again" "$OUT" "could not resolve the PR branch"

# 64. Writer-side (init) hard-errors on a detached HEAD rather than silently keying onto an empty
# branch slug.
d="$(mkrepo)"
git -C "$d" checkout -q --detach >/dev/null 2>&1
run_in "$d" bash "$gate" init
check_status "init on a detached HEAD → exit 1" 1 "$STATUS"
check_contains "init on a detached HEAD → names the cause" "$OUT" "detached HEAD"

summary
