#!/usr/bin/env bash
# Tests for tools/keel-impact.sh — the deterministic half of the impact score. The model's judgment (which
# events happened) is out of scope; we pin the machinery: the score is DERIVED from event counts by the
# fixed formula (never asserted), the confidence tier, header/row bookkeeping, the rolling trend, the honest
# cumulative signals, input validation, and table-safety escaping.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/keel-impact.sh"
LEDGER="$SANDBOX/ledger.md"
EVIDENCE="$SANDBOX/evidence.md"
export KEEL_IMPACT_LEDGER="$LEDGER"
export KEEL_IMPACT_EVIDENCE="$EVIDENCE"
# Isolate the event log from the very top: an absent path means the early add cases ingest nothing,
# so an ambient $KEEL_IMPACT_LOG in the runner's environment can't perturb the derived scores. The
# auto-ingest section below points this at a real log on purpose.
export KEEL_IMPACT_LOG="$SANDBOX/no-such-log"

# --- empty state --------------------------------------------------------------------------------
run bash "$TOOL" rollup
check_status "rollup on missing ledger succeeds" 0 "$STATUS"
check_contains "rollup reports empty ledger" "$OUT" "no scored sessions yet"
check_file "rollup creates the ledger header" "$LEDGER"
check_contains "header carries the column row" "$(cat "$LEDGER")" "| date | score | conf |"
check_contains "header documents the formula" "$(cat "$LEDGER")" "round(100"

# --- score is DERIVED from the number of citations, never a bare count --------------------------
# a lone guardrail fire (one cited event): HELP=3, COST=0 → 100
run bash "$TOOL" add --guard "secret-guard | blocked a key" --gap "none"
check_status "add derives from a cited guard event" 0 "$STATUS"
check_contains "guard-only derives score 100" "$OUT" "derived score 100/100"
check_contains "single event is low confidence" "$OUT" "conf low"
# row cols: score|conf|guard|hold|fire|hit|miss|fric|silent → guard=1, all others 0
check_contains "row records the derived score+conf" "$(cat "$LEDGER")" "| 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 |"
# the count is the number of citations, and each one is archived to the evidence trail
check_contains "guard citation is archived" "$(cat "$EVIDENCE")" "- guard: secret-guard | blocked a key"
check_contains "evidence block is dated + scored" "$(cat "$EVIDENCE")" "score 100/100 (conf low)"

# hold is guard's higher-value sibling (weight 4): 1 hold + 1 miss → HELP=4, COST=2 → 67
run bash "$TOOL" add --hold "keel blocked my attempt to weaken secret-scan" --miss "hunted config" --gap "none"
check_contains "hold weighted at 4 derives 67" "$OUT" "derived score 67/100"
check_contains "HELP reflects the hold weight" "$OUT" "HELP=4"
# row: guard=0 hold=1 fire=0 hit=0 miss=1
check_contains "hold lands in its own column" "$(cat "$LEDGER")" "| 67 | low | 0 | 1 | 0 | 0 | 1 |"
check_contains "hold citation is archived" "$(cat "$EVIDENCE")" "- hold: keel blocked my attempt to weaken secret-scan"

# hold outranks guard for the row's strongest-citation evidence cell
run bash "$TOOL" add --hold "the hold cite" --guard "the guard cite" --gap "none"
check_contains "hold outranks guard in the evidence cell" "$(cat "$LEDGER")" "| the hold cite |"

# 2 fire + 1 miss (three cited events): HELP=4, COST=2 → round(66.6)=67, 3 events → med
run bash "$TOOL" add --fire "branched off main" --fire "changelog entry" --miss "hunted lint cmd" \
  --silent 3 --gap "demote: lint silent"
check_contains "mixed help/cost derives 67" "$OUT" "derived score 67/100"
check_contains "three events is medium confidence" "$OUT" "conf med"
# row cols: guard|hold|fire|hit|miss|fric|silent → guard=0 hold=0 fire=2 hit=0 miss=1 fric=0 silent=3
check_contains "counts equal the citation tally; silent recorded, not scored" "$(cat "$LEDGER")" "| 0 | 0 | 2 | 0 | 1 | 0 | 3 |"
# strongest-citation rule: fire outranks miss, so the row's evidence cell is the first fire
check_contains "evidence cell is the strongest citation" "$(cat "$LEDGER")" "| branched off main |"
check_contains "every cited event is in the trail" "$(cat "$EVIDENCE")" "- miss: hunted lint cmd"

# only a miss: HELP=0, COST=2 → 0 (Keel was net-negative — the honest floor, not a skip)
run bash "$TOOL" add --miss "hunted the test cmd" --gap "promote: test cmd"
check_contains "cost-only derives score 0" "$OUT" "derived score 0/100"

# no cited events → "—" (nothing to measure), never a fake 0; silent alone does not earn a block
run bash "$TOOL" add --silent 4 --gap "demote: 4 rules idle"
check_contains "no events derives an em-dash score" "$OUT" "derived score —/100"
check_contains "no events is 'none' confidence" "$OUT" "conf none"

# high confidence at 6+ events (1 guard + 2 fire + 3 hit citations)
run bash "$TOOL" add --guard "g1" --fire "f1" --fire "f2" --hit "h1" --hit "h2" --hit "h3" --gap "none"
check_contains "six events is high confidence" "$OUT" "conf high"

# --- rollup: mean skips the em-dash, cumulative signals are summed from events ------------------
# Rows so far: 100, 67(hold+miss), 100(hold+guard), 67, 0, "—", 100 → 7 sessions, 6 scored.
run bash "$TOOL" rollup
check_contains "rollup counts every session" "$OUT" "7 session(s)"
check_contains "mean is over numeric scores only" "$OUT" "over 6 scored"
check_contains "trend shows numeric scores oldest-first" "$OUT" "67 → 0 → 100"
check_contains "cumulative guardrail fires summed" "$OUT" "3 guardrail fire(s)"
check_contains "cumulative agent-holds summed" "$OUT" "2 agent-hold(s)"
check_contains "cumulative retrieval misses summed" "$OUT" "3 retrieval miss(es)"

# --- free-text safety --------------------------------------------------------------------------
# A pipe in a citation is the natural "rule | diff" separator: kept literal in the trail, escaped only in
# the ledger table cell (where a bare pipe would break the column).
run bash "$TOOL" add --fire "value | with pipe" --gap "none"
check_status "row with a pipe in a citation succeeds" 0 "$STATUS"
check_contains "pipe in the ledger cell is escaped" "$(cat "$LEDGER")" 'value \| with pipe'
check_contains "trail keeps the citation literally" "$(cat "$EVIDENCE")" '- fire: value | with pipe'

# friction is cost (weight 2), same as miss: 1 fire + 1 friction → HELP=2, COST=2 → 50
run bash "$TOOL" add --fire "applied a rule" --friction "stale lint rule misled me" --gap "demote: stale lint"
check_contains "friction contributes to COST" "$OUT" "derived score 50/100"
# row cols guard|hold|fire|hit|miss|fric|silent → fire=1 fric=1, rest 0
check_contains "friction lands in its own column" "$(cat "$LEDGER")" "| 0 | 0 | 1 | 0 | 0 | 1 |"
check_contains "friction citation is archived" "$(cat "$EVIDENCE")" "- friction: stale lint rule misled me"

# --- validation --------------------------------------------------------------------------------
# only --silent is a bare count now; a citation flag takes any string, so "-1" is a valid citation there
run bash "$TOOL" add --silent -1 --gap x
check_status "negative silent count is rejected" 2 "$STATUS"
check_contains "negative count explains itself" "$OUT" "non-negative integer"

run bash "$TOOL" add --silent abc --gap x
check_status "non-integer silent count is rejected" 2 "$STATUS"

run bash "$TOOL" add --guard g --bogus x
check_status "unknown flag is rejected" 2 "$STATUS"

# an empty/missing citation is rejected cleanly (exit 2 + message), not bash's cryptic ${2:?} abort
run bash "$TOOL" add --fire "" --gap none
check_status "empty citation is rejected cleanly" 2 "$STATUS"
check_contains "empty citation explains itself" "$OUT" "non-empty citation"
run bash "$TOOL" add --hold
check_status "a citation flag with no value is rejected" 2 "$STATUS"

# an add with no cited events is legal — it derives "—" (an honestly inert session)
run bash "$TOOL" add --gap "none"
check_status "eventless add is legal" 0 "$STATUS"
check_contains "eventless add derives em-dash" "$OUT" "derived score —/100"

# an inert session (silent only, no citations) archives NO block — nothing to cite, nothing to record
ev_inert="$SANDBOX/evidence-inert.md"
run env KEEL_IMPACT_LEDGER="$SANDBOX/ledger-inert.md" KEEL_IMPACT_EVIDENCE="$ev_inert" \
  KEEL_IMPACT_LOG="$SANDBOX/no-such-log" bash "$TOOL" add --silent 2 --gap none
check_status "inert add succeeds" 0 "$STATUS"
check_nofile "an inert session creates no evidence file" "$ev_inert"

# --- deterministic event log: producer API + auto-ingest ---------------------------------------
# A fresh, isolated ledger+log+evidence for the ingest cases (the cases above left rows in $LEDGER).
LEDGER="$SANDBOX/ledger2.md"; LOG="$SANDBOX/events.log"; EVIDENCE="$SANDBOX/evidence2.md"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG" KEEL_IMPACT_EVIDENCE="$EVIDENCE"

run bash "$TOOL" event guard secret-guard blocked
check_status "event records a guard line" 0 "$STATUS"
check_contains "event confirms the write" "$OUT" "recorded guard event"
check_contains "log line is well-formed TSV" "$(cat "$LOG")" "guard	secret-guard	blocked"

run bash "$TOOL" event bogus
check_status "unknown event type is rejected" 2 "$STATUS"

# a second guard event, then a score: the model passes NO --guard; both logged guards are auto-ingested.
run bash "$TOOL" event guard secret-guard blocked
run bash "$TOOL" add --fire "flow" --gap "none"
check_status "add with pending log events succeeds" 0 "$STATUS"
check_contains "add reports the auto-ingest" "$OUT" "2 auto-ingested"
# HELP = 3*2(guard, from log) + 2*1(fire) = 8, COST=0 → score 100; guard col shows the ingested 2, hold=0
check_contains "logged guards reach the derived score" "$(cat "$LEDGER")" "| 100 | med | 2 | 0 | 1 |"
check_contains "log is truncated after ingest" "$(wc -l < "$LOG" | tr -d ' ')" "0"
# ingested guards are cited too: their source|detail becomes the archived citation
check_contains "ingested guard is archived with a citation" "$(cat "$EVIDENCE")" "- guard: secret-guard | blocked"

# a subsequent score does NOT re-count the consumed events (no double counting)
run bash "$TOOL" add --hit "later" --gap "none"
check_contains "consumed events are not re-ingested" "$OUT" "from 1 event(s)"

# --no-ingest leaves the log untouched and scores only the model's cited events
run bash "$TOOL" event guard secret-guard blocked
run bash "$TOOL" add --fire "manual only" --no-ingest --gap "none"
check_contains "--no-ingest ignores the log" "$OUT" "from 1 event(s)"
check_contains "--no-ingest preserves the log" "$(wc -l < "$LOG" | tr -d ' ')" "1"

# a final log line with NO trailing newline (a producer appending directly, or a partial write) must still
# be ingested — otherwise it is dropped and then lost when the log is truncated.
LEDGER="$SANDBOX/ledger-nonl.md"; LOG="$SANDBOX/events-nonl.log"; EVIDENCE="$SANDBOX/evidence-nonl.md"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG" KEEL_IMPACT_EVIDENCE="$EVIDENCE"
printf '%s\tguard\tsecret-guard\tblocked\n' "2026-01-01T00:00:00Z" > "$LOG"
printf '%s\tguard\tsecret-guard\tblocked'   "2026-01-01T00:00:01Z" >> "$LOG"   # no trailing newline
run bash "$TOOL" add --gap "none"
check_contains "unterminated final log line is still ingested" "$OUT" "2 auto-ingested"
check_contains "both guards reach the score (none dropped)" "$(cat "$LEDGER")" "| 100 | low | 2 | 0 |"

# --- hold event type: producer API + auto-ingest at weight 4 ------------------------------------
LEDGER="$SANDBOX/ledger3.md"; LOG="$SANDBOX/events3.log"; EVIDENCE="$SANDBOX/evidence3.md"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG" KEEL_IMPACT_EVIDENCE="$EVIDENCE"
run bash "$TOOL" event hold classifier "rejected the fix twice"
check_status "event accepts the hold type" 0 "$STATUS"
check_contains "hold log line is well-formed TSV" "$(cat "$LOG")" "hold	classifier	rejected the fix twice"
run bash "$TOOL" add --gap "none"
# a lone hold: HELP = 4*1 = 4, COST=0 → 100
check_contains "a logged hold auto-ingests at weight 4" "$OUT" "HELP=4"
check_contains "hold-only derives 100" "$OUT" "derived score 100/100"
check_contains "ingested hold is archived with its citation" "$(cat "$EVIDENCE")" "- hold: classifier | rejected the fix twice"

# --- retro (thread C): a quarantined retrospective score --------------------------------------
LEDGER="$SANDBOX/ledger4.md"; EVIDENCE="$SANDBOX/evidence4.md"; LOG="$SANDBOX/events4.log"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_EVIDENCE="$EVIDENCE" KEEL_IMPACT_LOG="$LOG"
run bash "$TOOL" add --retro --asof 2026-05-01 --fire "past rule applied" --hit "past fact used" --gap "none"
check_status "retro add succeeds" 0 "$STATUS"
# HELP = 2*1(fire) + 1(hit) = 3 → 100; conf med→low then tagged retro (drop one tier: 3 events would be med)
check_contains "retro drops one conf tier and tags it" "$OUT" "conf low-retro"
check_contains "retro row is backdated by --asof" "$(cat "$LEDGER")" "| 2026-05-01 | 100 | low-retro |"
# a live score into the same ledger
run bash "$TOOL" add --fire "live rule" --gap "none"
check_contains "live score is not tagged retro" "$OUT" "conf low"
# the live rollup quarantines the retro row: only the 1 live session counts
run bash "$TOOL" rollup
check_contains "live rollup excludes the retro row" "$OUT" "impact ledger: 1 session(s)"
# rollup --retro shows only the quarantined rows
run bash "$TOOL" rollup --retro
check_contains "retro rollup labels itself" "$OUT" "retro impact ledger: 1 session(s)"
check_contains "retro rollup means only retro scores" "$OUT" "mean score 100.0/100"

# --asof rejects a non-date
run bash "$TOOL" add --retro --asof notadate --fire x
check_status "bad --asof is rejected" 2 "$STATUS"
check_contains "bad --asof explains itself" "$OUT" "YYYY-MM-DD"

# retro forces no-ingest: a pending log event is neither consumed nor counted
run bash "$TOOL" event guard secret-guard blocked
run bash "$TOOL" add --retro --fire "only the fire" --gap "none"
check_contains "retro ignores the live log" "$OUT" "from 1 event(s)"
check_contains "retro preserves the live log" "$(wc -l < "$LOG" | tr -d ' ')" "1"

# --- enable: opt a repo into tracking (the .keel/ marker the hooks look for) ---------------------
erepo="$(new_repo)"
run bash "$TOOL" enable "$erepo"
check_status "enable succeeds on a git repo" 0 "$STATUS"
check_dir "enable creates the .keel/ marker" "$erepo/.keel"
check_contains "enable gitignores the event log only" "$(cat "$erepo/.gitignore" 2>/dev/null)" "/.keel/impact-events.log"
check_contains "enable confirms tracking is on" "$OUT" "impact tracking enabled"

# idempotent: a second enable doesn't duplicate the gitignore line
run bash "$TOOL" enable "$erepo"
check_status "second enable succeeds" 0 "$STATUS"
check_contains "gitignore has exactly one event-log line" "$(grep -c '^/\.keel/impact-events\.log$' "$erepo/.gitignore")" "1"

# end-to-end: an enabled repo records a guard event with NO env, and the ledger resolves to .keel/ledger.md
run_in "$erepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" event guard secret-guard blocked
check_file "event lands in the enabled repo's .keel/ log" "$erepo/.keel/impact-events.log"
run_in "$erepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --fire "e" --gap none
check_file "score writes the ledger to .keel/ledger.md (marker-resolved, no env)" "$erepo/.keel/ledger.md"
check_file "score writes the trail to .keel/evidence.md (marker-resolved, no env)" "$erepo/.keel/evidence.md"
# the split: the ephemeral log is ignored, the durable ledger + evidence trail stay trackable
git -C "$erepo" check-ignore -q .keel/impact-events.log && pass "event log is gitignored" || fail "event log is gitignored" "not ignored"
git -C "$erepo" check-ignore -q .keel/ledger.md && fail "ledger stays trackable (not ignored)" "ledger is ignored" || pass "ledger stays trackable (not ignored)"
git -C "$erepo" check-ignore -q .keel/evidence.md && fail "evidence stays trackable (not ignored)" "evidence is ignored" || pass "evidence stays trackable (not ignored)"

# --- worktree fallback: the marker is untracked, so it lives ONLY at the main checkout's top ------
# a session in a linked worktree must still resolve the MAIN .keel/ (log, ledger, evidence) — before the
# fallback, events from worktree sessions silently vanished (felt on keel's own dogfooding, dir #10)
git -C "$erepo" add -A -- ':!.keel' >/dev/null 2>&1
git -C "$erepo" commit -qm "seed" >/dev/null 2>&1
ewt="$SANDBOX/erepo-wt"
git -C "$erepo" worktree add -q -b wt-session "$ewt" >/dev/null 2>&1
check_dir "worktree fixture exists" "$ewt"
wt_log_before="$(wc -l < "$erepo/.keel/impact-events.log" | tr -d ' ')"
run_in "$ewt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" event guard secret-guard blocked
check_status "event from a worktree succeeds" 0 "$STATUS"
check_contains "worktree event appends to the MAIN checkout's log" "$(wc -l < "$erepo/.keel/impact-events.log" | tr -d ' ')" "$((wt_log_before + 1))"
[ ! -d "$ewt/.keel" ] && pass "no stray worktree-local .keel/" || fail "no stray worktree-local .keel/" "worktree grew its own marker"
# the add also auto-ingests the pending guard event above FROM the main log — proof the worktree session
# reads and writes the main .keel/ end-to-end (guard=1 ingested + fire=1 cited → 100, guard cell wins)
run_in "$ewt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --fire "wt cite" --gap none
check_contains "add from a worktree ingests the MAIN log and writes the MAIN ledger" "$(cat "$erepo/.keel/ledger.md")" "| 100 | low | 1 | 0 | 1 | 0 | 0 | 0 | 0 |"
check_contains "add from a worktree archives to the MAIN evidence trail" "$(cat "$erepo/.keel/evidence.md")" "- fire: wt cite"

# enable run FROM a worktree targets the main checkout (an in-worktree marker would be ephemeral)
wrepo="$(new_repo)"
run_in "$wrepo" git commit -qm seed --allow-empty
wwt="$SANDBOX/wrepo-wt"
git -C "$wrepo" worktree add -q -b wt-enable "$wwt" >/dev/null 2>&1
run_in "$wwt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable .
check_status "enable from a worktree succeeds" 0 "$STATUS"
check_dir "enable from a worktree creates the marker at the MAIN top" "$wrepo/.keel"
[ ! -d "$wwt/.keel" ] && pass "enable leaves no worktree-local marker" || fail "enable leaves no worktree-local marker" "marker created in the worktree"
check_contains "enable from a worktree gitignores at the MAIN top" "$(cat "$wrepo/.gitignore" 2>/dev/null)" "/.keel/impact-events.log"

# bare-main topology: the first worktree-list entry has no working tree — enable must NOT write .keel/
# into the bare repo dir (nothing could ever commit it); it falls back to the worktree's own top
brepo="$SANDBOX/bare-main.git"
git clone -q --bare "$wrepo" "$brepo" 2>/dev/null    # reuse the seeded repo above for a HEAD to check out
bwt="$SANDBOX/bare-wt"
git -C "$brepo" worktree add -q -b wt-bare "$bwt" >/dev/null 2>&1
run_in "$bwt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable .
check_status "enable under a bare main succeeds" 0 "$STATUS"
[ ! -d "$brepo/.keel" ] && pass "bare main gets no .keel/" || fail "bare main gets no .keel/" ".keel created inside the bare repo"
check_dir "bare-main enable falls back to the worktree's own top" "$bwt/.keel"

# not-a-repo-yet: enable must fall back to the dir as-is (regression: the worktree-list probe exits 128
# outside a repo, and under set -euo pipefail an unguarded pipeline killed the whole script)
ngdir="$(mktemp -d "$SANDBOX/nogit.XXXXXX")"
run bash "$TOOL" enable "$ngdir"
check_status "enable on a not-yet-git dir still succeeds" 0 "$STATUS"
check_dir "not-yet-git enable creates the marker in the dir as-is" "$ngdir/.keel"

# --- rollup --registry: cross-project sweep over an INSTANCE.md Projects table -------------------
pa="$(new_repo)"; run_in "$pa" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable . >/dev/null 2>&1
run_in "$pa" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --guard "e" --gap none   # 100
pb="$(new_repo)"; run_in "$pb" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable . >/dev/null 2>&1
run_in "$pb" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --miss "m" --gap none    # 0
pc="$(new_repo)"                                                                                                # enrolled but unscored

reg="$SANDBOX/INSTANCE.md"
{
  printf '## Projects\n\n| Name | Path | Tag |\n|------|------|-----|\n'
  printf '| pa | `%s` | x |\n' "$pa"
  printf '| pb | `%s` | y |\n' "$pb"
  printf '| pc | `%s` | z |\n' "$pc"
} > "$reg"

run bash "$TOOL" rollup --registry "$reg"
check_status "rollup --registry succeeds" 0 "$STATUS"
check_contains "a scored project shows its mean" "$OUT" "mean 100.0/100 over 1 scored"
check_contains "a zero-score project is included" "$OUT" "mean 0.0/100"
check_contains "an unscored project is flagged, not counted" "$OUT" "tracking off or no sessions scored"
check_contains "grand total averages only scored sessions" "$OUT" "3 project(s), mean 50.0/100 over 2 scored"
check_contains "grand total sums the honest guard signal" "$OUT" "1 guard fire(s)"

run bash "$TOOL" rollup --registry "$SANDBOX/nope.md"
check_status "missing registry → exit 2" 2 "$STATUS"

summary
