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

ALL_STEPS="polish.1-diff polish.2-simplify polish.3-tests polish.4-depth polish.5-review polish.6-retest polish.7-selfcheck polish.8-unlock"

# A git repo with one commit; prints its path.
mkrepo() {
  local d; d="$(new_repo)"
  git -C "$d" commit --allow-empty -qm init
  printf '%s' "$d"
}

sentinel_for() { printf '/tmp/pre-pr-gate-%s' "$(basename "$1")"; }

# Drive the gate: $1 = command string, $2 = cwd. Captures OUT (stdout+stderr) and STATUS.
gate() {
  local json
  json="$(jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, cwd:$d}')"
  OUT="$(printf '%s' "$json" | bash "$gate" 2>&1)"
  STATUS=$?
}

# Build a complete, matching receipt at $1 (repo dir) via the CLI subcommands (run_in so $PWD == $1, since
# both `init` and `receipt` key the sentinel off basename "$PWD"). $2 = optional step to omit (for the
# incomplete-receipt tests); $3 = optional step whose line should be re-tagged with a foreign nonce instead
# of being written at all (for the replay tests).
write_full_receipt() {
  local d="$1" omit="${2:-}" replay_step="${3:-}" s
  run_in "$d" bash "$gate" init
  for s in $ALL_STEPS; do
    [ "$s" = "$omit" ] && continue
    if [ "$s" = "$replay_step" ]; then
      printf 'stale-nonce-from-a-previous-run\t%s\tdone\n' "$s" >> "$(sentinel_for "$d")"
      continue
    fi
    if [ "$s" = "polish.8-unlock" ]; then
      run_in "$d" bash "$gate" receipt "$s" "$(git -C "$d" rev-parse HEAD)"
    else
      run_in "$d" bash "$gate" receipt "$s"
    fi
  done
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
d="$(mkrepo)"
run_in "$d" bash "$gate" init
run_in "$d" bash "$gate" receipt polish.1-diff
run_in "$d" bash "$gate" receipt polish.2-simplify
run_in "$d" bash "$gate" receipt polish.3-tests "skipped:--no-test"
run_in "$d" bash "$gate" receipt polish.4-depth low
run_in "$d" bash "$gate" receipt polish.5-review low
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

# 15. A receipt written AND read from the SAME worktree cwd (the ordinary, non-split case) still works
# unchanged — main_top_for resolves the same main checkout consistently regardless of which member of
# the worktree set is used throughout, so this is not a regression against the pre-fix common case.
mkworktree dir61-wt-same dir61-feature5
write_full_receipt "$WT"
gate "gh pr create --fill" "$WT"
check_status "receipt + hook both from the worktree → exit 0" 0 "$STATUS"
check_absent "receipt + hook both from the worktree → allowed" "$OUT" "deny"

summary
