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
# be ingested — otherwise it is dropped and then lost when the log is truncated. This is guarded by the
# tool's awk pre-pass, which always terminates every record it emits, not by the `read` loop's own
# `|| [ -n "$_ty" ]` EOF fallback (that's belt-and-braces — the pre-pass means `read` never actually hits
# EOF mid-record on this path). Timestamps are stamped live (not a fixed past date) so the fixture stays
# inside the default age cap regardless of when this test runs (backlog #59 — a hardcoded past date here
# would now read as stale and break this test).
LEDGER="$SANDBOX/ledger-nonl.md"; LOG="$SANDBOX/events-nonl.log"; EVIDENCE="$SANDBOX/evidence-nonl.md"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG" KEEL_IMPACT_EVIDENCE="$EVIDENCE"
_nonl_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\tguard\tsecret-guard\tblocked\n' "$_nonl_ts" > "$LOG"
printf '%s\tguard\tsecret-guard\tblocked'   "$_nonl_ts" >> "$LOG"   # no trailing newline
run bash "$TOOL" add --gap "none"
check_contains "unterminated final log line is still ingested" "$OUT" "2 auto-ingested"
check_contains "both guards reach the score (none dropped)" "$(cat "$LEDGER")" "| 100 | low | 2 | 0 |"

# --- auto-ingest age cap (backlog #59): a session that never called `add` leaves events unconsumed in the
# log, where they'd otherwise mis-attribute to whichever session's row lands next -- anything strictly
# older than the cutoff is stale: not counted, archived with a note instead of a citation, still consumed
# (log truncated) so it never resurfaces. ------------------------------------------------------------
LEDGER="$SANDBOX/ledger-agecap.md"; LOG="$SANDBOX/events-agecap.log"; EVIDENCE="$SANDBOX/evidence-agecap.md"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG" KEEL_IMPACT_EVIDENCE="$EVIDENCE"
unset KEEL_INGEST_MAX_AGE_HOURS 2>/dev/null || true
fresh_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
old_ts="2000-01-01T00:00:00Z"   # long past any sane cutoff -- the felt "unconsumed from a prior session" case

# a lone fresh event: counted, and printed as an ingested line (visibility, spec item 3)
printf '%s\tguard\tsecret-guard\tblocked\n' "$fresh_ts" > "$LOG"
run bash "$TOOL" add --gap none
check_status "fresh event add succeeds" 0 "$STATUS"
check_contains "fresh event is counted" "$OUT" "derived score 100/100"
check_contains "fresh event prints an ingested line" "$OUT" "ingested: $fresh_ts guard secret-guard | blocked"
check_contains "log is truncated after a fresh ingest" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# a lone stale event (the felt scenario): NOT counted, printed as stale-skipped, archived with a note
# (not a citation), and the log is still consumed
printf '%s\tguard\tsecret-guard\tblocked\n' "$old_ts" > "$LOG"
run bash "$TOOL" add --gap none
check_status "stale-only add succeeds" 0 "$STATUS"
check_contains "stale event derives an em-dash (nothing counted)" "$OUT" "derived score —/100"
check_contains "stale event prints a stale-skipped line" "$OUT" "stale-skipped: $old_ts guard secret-guard | blocked"
check_contains "stale event is archived with the skip note" "$(cat "$EVIDENCE")" "stale, unattributed — skipped by the 12h ingest cap"
check_contains "stale event's original line is archived" "$(cat "$EVIDENCE")" "$(printf '%s\tguard\tsecret-guard\tblocked' "$old_ts")"
check_contains "stale note carries the re-cite hint" "$(cat "$EVIDENCE")" "re-cite explicitly via flags if genuinely this session's"
check_contains "log is truncated after a stale-only run (no resurfacing)" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# dir #85 (code audit, finding 6): the stale block is written with printf '%s', never '%b'. The event
# text is third-party (whatever the firing session wrote) and _flatten only strips literal tab/newline
# BYTES — a two-character `\c` survives it. Under '%b' that `\c` TRUNCATED the rest of the printf,
# swallowing every stale row after it and quietly breaking the "no citation → no count" record this
# block exists to keep honest. Two stale events, the first carrying `\c`: both must be archived.
: > "$EVIDENCE"
{
  printf '%s\tguard\tsecret-guard\tblocked \\c mid-detail\n' "$old_ts"
  printf '%s\tfire\tsecond-source\tsecond-detail\n' "$old_ts"
} > "$LOG"
run bash "$TOOL" add --gap none
check_status "stale run with a backslash escape in the text succeeds" 0 "$STATUS"
ev="$(cat "$EVIDENCE")"
check_contains "the escape sequence is archived literally, not interpreted" "$ev" 'blocked \c mid-detail'
check_contains "the stale row AFTER the escape still reaches the trail" "$ev" "second-source"
# (No assertion on the closing re-cite hint: it is a SEPARATE printf in the same redirect group, so
# `\c` never reached it and it survived even unfixed — it would have advertised coverage it didn't
# have. The two assertions above are the red-before-green ones.)

# mixed fresh + stale in one log: only the fresh one counts; both print; both are consumed
{
  printf '%s\tguard\tsecret-guard\tblocked\n' "$old_ts"
  printf '%s\tfire\tsession\trule applied\n' "$fresh_ts"
} > "$LOG"
run bash "$TOOL" add --gap none
check_contains "mixed log: only the fresh event is counted" "$OUT" "from 1 event(s)"
check_contains "mixed log: fresh prints ingested" "$OUT" "ingested: $fresh_ts fire session | rule applied"
check_contains "mixed log: stale prints stale-skipped" "$OUT" "stale-skipped: $old_ts guard secret-guard | blocked"
check_contains "mixed log: reports 1 auto-ingested" "$OUT" "1 auto-ingested"
check_contains "mixed log: truncated after processing both" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# malformed/empty timestamp: treated as stale regardless of age (err toward NOT counting -- false credit
# is the harm here, the mirror of pre-pr-gate's err-toward-catching)
printf 'not-a-timestamp\tguard\tsecret-guard\tblocked\n' > "$LOG"
run bash "$TOOL" add --gap none
check_contains "malformed ts derives an em-dash" "$OUT" "derived score —/100"
check_contains "malformed ts prints stale-skipped" "$OUT" "stale-skipped: not-a-timestamp guard secret-guard | blocked"

# --since overrides the cutoff explicitly, in both directions
printf '%s\tguard\tsecret-guard\tblocked\n' "$old_ts" > "$LOG"
run bash "$TOOL" add --since 1999-01-01T00:00:00Z --gap none
check_contains "--since before the event's ts counts it" "$OUT" "derived score 100/100"
check_contains "--since (older cutoff) prints ingested" "$OUT" "ingested: $old_ts guard secret-guard | blocked"

printf '%s\tguard\tsecret-guard\tblocked\n' "$fresh_ts" > "$LOG"
run bash "$TOOL" add --since "2999-01-01T00:00:00Z" --gap none
check_contains "--since after the event's ts stales it" "$OUT" "derived score —/100"
check_contains "--since (future cutoff) prints stale-skipped" "$OUT" "stale-skipped: $fresh_ts guard secret-guard | blocked"

run bash "$TOOL" add --since notadate --fire x
check_status "malformed --since is rejected" 2 "$STATUS"
check_contains "malformed --since explains itself" "$OUT" "ISO-UTC timestamp"

# KEEL_INGEST_MAX_AGE_HOURS override is actually read: a huge window swallows the felt-scenario "old"
# fixture as fresh (its cutoff falls back before the year 2000)
printf '%s\tguard\tsecret-guard\tblocked\n' "$old_ts" > "$LOG"
run env KEEL_INGEST_MAX_AGE_HOURS=999999 bash "$TOOL" add --gap none
check_contains "a huge cap window counts the old fixture as fresh" "$OUT" "ingested: $old_ts guard secret-guard | blocked"
check_contains "a huge cap window derives from it" "$OUT" "derived score 100/100"

# dir #196 (same overflow class dir #156 fixed in self/doctor.sh): a digit-SHAPED but overflowing
# override (20 nines) must fall back to the default 12h cap, not silently ingest everything uncapped.
# Unguarded, `max_age_h * 3600` overflows the shell's arithmetic, `_epoch_to_iso` can't convert the
# resulting cutoff, and the tool's own date-conversion fail-open kicks in — INGESTING the felt-scenario
# "old" fixture as if no cap existed at all, the opposite of the intended fallback (reproduced live
# against the unguarded case arm before fixing it here).
printf '%s\tguard\tsecret-guard\tblocked\n' "$old_ts" > "$LOG"
run env KEEL_INGEST_MAX_AGE_HOURS=99999999999999999999 bash "$TOOL" add --gap none
check_status "an overflowing cap override does not crash the tool" 0 "$STATUS"
check_absent "no fail-open uncapped-ingest message from the overflow" "$OUT" "could not convert the ingest age-cap cutoff"
check_contains "overflow falls back to the default 12h cap, staling the old fixture" "$OUT" \
  "stale-skipped: $old_ts guard secret-guard | blocked"

# date-conversion fail-open: if every fallback in the epoch->ISO chain fails, ingest everything uncapped
# and warn -- never crash `add`. A stub `date` errors on -r/-d/-D (the three fallback flags this tool's
# cutoff conversion uses) but passes every other invocation through to the real binary, so it forces this
# path without breaking the row's own `today` timestamp (which uses none of those flags).
real_date="$(command -v date)"
mockbin="$SANDBOX/mockbin"; mkdir -p "$mockbin"
cat > "$mockbin/date" <<MOCKEOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    -r|-d|-D) exit 1 ;;
  esac
done
exec "$real_date" "\$@"
MOCKEOF
chmod +x "$mockbin/date"
printf '%s\tguard\tsecret-guard\tblocked\n' "$old_ts" > "$LOG"
run env PATH="$mockbin:$PATH" bash "$TOOL" add --gap none
check_status "fail-open add still succeeds" 0 "$STATUS"
check_contains "fail-open warns about the cutoff conversion" "$OUT" "could not convert the ingest age-cap cutoff"
check_contains "fail-open ingests the old event anyway (uncapped)" "$OUT" "ingested: $old_ts guard secret-guard | blocked"
check_contains "fail-open derives the score from it" "$OUT" "derived score 100/100"

# --- dir #74: claim-key ingest filtering -- a shared multi-worktree log must not let one session's
# `add` swallow another's fresh events. Each event line's 5th TSV field is its producer's own worktree
# top; `add` only counts events carrying its OWN key, keeping any others in the log for their owner to
# claim later. Resolve keys through git itself (not the raw mktemp path) so a macOS /tmp -> /private/tmp
# symlink can't make an exact-string comparison fail. -------------------------------------------
own_repo="$(new_repo)"
foreign_repo="$(new_repo)"
own_key="$(git -C "$own_repo" rev-parse --show-toplevel)"
foreign_key="$(git -C "$foreign_repo" rev-parse --show-toplevel)"

LEDGER="$SANDBOX/ledger-claim.md"; LOG="$SANDBOX/events-claim.log"; EVIDENCE="$SANDBOX/evidence-claim.md"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_LOG="$LOG" KEEL_IMPACT_EVIDENCE="$EVIDENCE"
ts_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# (i) own-key fresh event -> ingested + removed
printf '%s\tguard\tsecret-guard\tblocked\t%s\n' "$ts_now" "$own_key" > "$LOG"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "own-key fresh event is ingested" "$OUT" "ingested: $ts_now guard secret-guard | blocked"
check_contains "own-key event derives a score" "$OUT" "derived score 100/100"
check_contains "own-key event is removed after ingest" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# (ii) foreign-key fresh event -> not counted, foreign-kept printed, line stays in the log; a later `add`
# run from that key's OWN repo then ingests it (the acceptance case: two concurrent sessions each score
# only their own guardrail fires)
printf '%s\tguard\tsecret-guard\tblocked\t%s\n' "$ts_now" "$foreign_key" > "$LOG"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "foreign-key fresh event is not counted" "$OUT" "derived score —/100"
check_contains "foreign-key fresh event prints foreign-kept" "$OUT" "foreign-kept: $ts_now guard secret-guard | blocked"
check_contains "foreign-key event line survives in the log" "$(cat "$LOG")" "$(printf '%s\tguard\tsecret-guard\tblocked\t%s' "$ts_now" "$foreign_key")"
run_in "$foreign_repo" bash "$TOOL" add --gap none
check_contains "the owning key's own add ingests the kept-back event" "$OUT" "ingested: $ts_now guard secret-guard | blocked"
check_contains "the owning key's own add derives a score from it" "$OUT" "derived score 100/100"
check_contains "the log is empty once its own key claims it" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# (iii) legacy 4-field line (no claim key) -> ingested as today, back-compat
printf '%s\tguard\tsecret-guard\tblocked\n' "$ts_now" > "$LOG"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "legacy 4-field line is ingested (back-compat)" "$OUT" "ingested: $ts_now guard secret-guard | blocked"

# (iv) stale foreign event -> stale-skipped + removed regardless of key: dir #59's semantics are
# unchanged by claim keys (past the age cap an event is unattributable either way)
old_ts_claim="2000-01-01T00:00:00Z"
printf '%s\tguard\tsecret-guard\tblocked\t%s\n' "$old_ts_claim" "$foreign_key" > "$LOG"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "stale foreign event is stale-skipped, not foreign-kept" "$OUT" "stale-skipped: $old_ts_claim guard secret-guard | blocked"
check_absent "stale foreign event is never foreign-kept" "$OUT" "foreign-kept"
check_contains "stale foreign event is removed from the log" "$(wc -l < "$LOG" | tr -d ' ')" "0"

# (v) a 5-field line with an EMPTY detail parses collapse-proof: a foreign claim key must land in the key
# position, never slide into detail — the promoted tab-collapse trap (LEARNINGS.md, 2nd hit dir #63).
# Foreign + empty-detail is the sharpest check: if the collapse bug were present, the key would shift into
# $_det and the (now-empty) key slot would read as "own", so the event would be WRONGLY ingested here.
printf '%s\tfire\tsession\t\t%s\n' "$ts_now" "$foreign_key" > "$LOG"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "empty-detail line's claim key is not swallowed into detail" "$OUT" "foreign-kept: $ts_now fire session"
check_absent "empty-detail line's citation does not leak the claim key as detail" "$OUT" "session | $foreign_key"
check_contains "empty-detail foreign event derives no score (correctly not ingested)" "$OUT" "derived score —/100"
run_in "$foreign_repo" bash "$TOOL" add --gap none
check_contains "the owning key still ingests the empty-detail event correctly" "$OUT" "ingested: $ts_now fire session"

# (vi) a line whose type isn't in EVENT_TYPES (pre-pr-gate.sh's own housekeeping lines — receipt-pass,
# receipt-deny, pipeline-drift) is preserved VERBATIM through a rewrite instead of being silently dropped
# OR truncated. Uses the REAL receipt-pass shape (pre-pr-gate.sh's own log_event call embeds a literal
# tab in `detail`, packing prov_label+prov_tag) — a genuine 6-tab-field line, not a 5-field stand-in — so
# this actually exercises the "preserve the raw line, don't reconstruct from 5 split fields" fix; an
# earlier version of this fix looked right but silently truncated exactly this shape down to 5 fields.
housekeeping_line="$(printf '%s\treceipt-pass\tpre-pr-gate\treview: high, trace-confirmed\ttrace-confirmed\t%s' "$ts_now" "$own_key")"
printf '%s\n%s\tguard\tsecret-guard\tblocked\t%s\n' "$housekeeping_line" "$ts_now" "$own_key" > "$LOG"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "own-key ingest still fires alongside a housekeeping line" "$OUT" "ingested: $ts_now guard secret-guard | blocked"
check_contains "housekeeping line survives an ingest-triggered rewrite" "$(cat "$LOG")" "$housekeeping_line"
check_contains "the 6-field housekeeping line keeps all 6 fields (not truncated to 5)" "$(awk -F'\t' 'NR==1{print NF}' "$LOG")" "6"

# ...and when the ONLY scored activity is a foreign-kept event, the rewrite is skipped entirely (nothing
# needed removing), so the housekeeping line survives simply because the file was never touched
printf '%s\n%s\tguard\tsecret-guard\tblocked\t%s\n' "$housekeeping_line" "$ts_now" "$foreign_key" > "$LOG"
_kept_only_before="$(cat "$LOG")"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "a kept-only run derives no score" "$OUT" "derived score —/100"
check_contains "a kept-only run leaves the log byte-for-byte untouched (rewrite skipped)" "$(cat "$LOG")" "$_kept_only_before"

# --- dir #82: the rewrite is SUBTRACTIVE, not a T0-snapshot write-back --------------------------
# The old rewrite wrote back "the survivors of what I saw when I read the log", which is blind to
# anything a concurrent producer appends between that read and the eventual `mv` — a real data-loss
# race (found by dir #74's own independent review), not just a mis-attribution like dir #74 fixes.
# KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE simulates exactly that: `cmd_add` appends its value as one
# literal log line immediately before the fresh re-read the subtractive rewrite does, standing in for
# a guardrail hook (or another session's `add`) firing in that window. Reuses own_repo/own_key/LOG
# from the dir #74 claim-key block above.

# (i) the ticket's own concrete loss scenario: one own-key event to ingest, a FOREIGN-key event
# injected mid-add → own event ingested and removed, the injected line survives byte-for-byte (the
# old snapshot write-back would have silently dropped it).
inject_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
injected_line="$(printf '%s\tguard\tsecret-guard\tblocked-concurrently\t%s' "$inject_ts" "$foreign_key")"
printf '%s\tguard\tsecret-guard\tblocked\t%s\n' "$ts_now" "$own_key" > "$LOG"
export KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE="$injected_line"
run_in "$own_repo" bash "$TOOL" add --gap none
unset KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE
check_contains "own-key event still ingested despite the concurrent injection" "$OUT" "ingested: $ts_now guard secret-guard | blocked"
check_contains "the concurrently-injected line survives the rewrite byte-for-byte" "$(cat "$LOG")" "$injected_line"
check_contains "only the injected line remains (the consumed own-key line is gone)" "$(wc -l < "$LOG" | tr -d ' ')" "1"

# (ii) an OWN-key event injected mid-add survives too (not consumed, not double-cited THIS run — it
# wasn't in the T0 read this run decided from) — a later, separate `add` then ingests it normally.
inject_ts2="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
injected_own_line="$(printf '%s\tguard\tsecret-guard\tinjected-own\t%s' "$inject_ts2" "$own_key")"
printf '%s\tguard\tsecret-guard\tblocked\t%s\n' "$ts_now" "$own_key" > "$LOG"
export KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE="$injected_own_line"
run_in "$own_repo" bash "$TOOL" add --gap none
unset KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE
check_contains "the pre-existing own-key event is ingested this run" "$OUT" "ingested: $ts_now guard secret-guard | blocked"
check_absent "the injected own-key event is NOT double-cited this run (never in this run's T0 read)" "$OUT" "injected-own"
check_contains "the injected own-key event survives this run's rewrite" "$(cat "$LOG")" "$injected_own_line"
run_in "$own_repo" bash "$TOOL" add --gap none
check_contains "a second, separate add ingests the previously-injected event normally" "$OUT" "ingested: $inject_ts2 guard secret-guard | injected-own"

# (iii) count-map correctness: two BYTE-IDENTICAL own-key lines at T0, both ingested → both removed;
# a THIRD byte-identical line injected mid-run (never in this run's T0 read) must survive — proving
# the rewrite deletes exactly as many occurrences as were consumed, not "any line matching this text".
dup_line="$(printf '%s\tguard\tsecret-guard\tduplicate-event\t%s' "$ts_now" "$own_key")"
printf '%s\n%s\n' "$dup_line" "$dup_line" > "$LOG"
export KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE="$dup_line"
run_in "$own_repo" bash "$TOOL" add --gap none
unset KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE
ingested_count="$(printf '%s' "$OUT" | grep -c '^ingested: ')"
check_contains "both byte-identical T0 duplicates are ingested" "$ingested_count" "2"
check_contains "exactly one copy remains — the mid-run-injected third, not a fourth phantom survivor" "$(grep -c -F "$dup_line" "$LOG")" "1"

# (iv) unrecognized-type lines and foreign-kept lines round-trip byte-for-byte through the SUBTRACTIVE
# rewrite too — already exercised above (dir #74 block, "housekeeping line survives an ingest-triggered
# rewrite" / "a kept-only run leaves the log byte-for-byte untouched"), which now runs against this
# rewrite's new code path; no new assertions needed here, those are this ticket's regression coverage.

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
# HELP = 2*1(fire) + 1(hit) = 3 → 100; ev_count=2 (fire+hit) is already "low" (<3), so the retro
# downgrade is a no-op here — the "-retro" suffix is just appended unconditionally
check_contains "retro tags conf, tier-drop a no-op at this ev_count" "$OUT" "conf low-retro"
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

# a retro fixture that actually reaches the tier-drop `case` (the low-retro one above never does — its
# ev_count=2 is already "low", so the downgrade is a no-op there): 6 events (3 fire + 3 hit) put the
# LIVE conf at "high" (>=6), and the retro downgrade must drop it exactly one tier to "med" before
# tagging — deleting the `case`'s `high) conf="med" ;;` arm must turn this red.
LEDGER="$SANDBOX/ledger4b.md"; EVIDENCE="$SANDBOX/evidence4b.md"; LOG="$SANDBOX/events4b.log"
export KEEL_IMPACT_LEDGER="$LEDGER" KEEL_IMPACT_EVIDENCE="$EVIDENCE" KEEL_IMPACT_LOG="$LOG"
run bash "$TOOL" add --retro --asof 2026-05-02 \
  --fire "a" --fire "b" --fire "c" --hit "d" --hit "e" --hit "f" --gap "none"
check_status "6-event retro add succeeds" 0 "$STATUS"
check_contains "retro drops high to med and tags it" "$OUT" "conf med-retro"
check_contains "retro row records the dropped tier" "$(cat "$LEDGER")" "| 2026-05-02 | 100 | med-retro |"

# --asof rejects a non-date
run bash "$TOOL" add --retro --asof notadate --fire x
check_status "bad --asof is rejected" 2 "$STATUS"
check_contains "bad --asof explains itself" "$OUT" "YYYY-MM-DD"

# retro forces no-ingest: a pending log event is neither consumed nor counted
run bash "$TOOL" event guard secret-guard blocked
run bash "$TOOL" add --retro --fire "only the fire" --gap "none"
check_contains "retro ignores the live log" "$OUT" "from 1 event(s)"
check_contains "retro preserves the live log" "$(wc -l < "$LOG" | tr -d ' ')" "1"

# --- enable: opt a repo into tracking (dir #251 — an EXTERNAL store entry, nothing in-tree) -------
store_id_for() { printf '%s' "$(cd "$1" && pwd -P)" | tr '/' '-'; }

erepo="$(new_repo)"
erepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$erepo")"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable "$erepo"
check_status "enable succeeds on a git repo" 0 "$STATUS"
check_dir "enable creates an external store entry" "$erepo_store"
check_file "the store entry carries an origin file" "$erepo_store/origin"
check_nofile "enable writes NOTHING inside the project tree" "$erepo/.keel/ledger.md"
check_nofile "enable writes no .gitignore" "$erepo/.gitignore"
check_contains "enable confirms tracking is on" "$OUT" "impact tracking enabled"

# idempotent: a second enable reports itself as a no-op, not "enabled" again
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable "$erepo"
check_status "second enable succeeds" 0 "$STATUS"
check_contains "second enable reports already-enabled, not newly-enabled" "$OUT" "impact tracking already enabled"

# end-to-end: an enabled repo records a guard event with NO env, and files land in the external store
run_in "$erepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" event guard secret-guard blocked
check_file "event lands in the store's log" "$erepo_store/impact-events.log"
run_in "$erepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --fire "e" --gap none
check_file "score writes the ledger into the store (marker-free, no env)" "$erepo_store/ledger.md"
check_file "score writes the trail into the store (marker-free, no env)" "$erepo_store/evidence.md"
check_nofile "the project tree still carries nothing after add" "$erepo/.keel/ledger.md"

# --- worktree: a linked worktree resolves to the SAME store entry as its main checkout -------------
# before the store (dir #181's bug class), events from worktree sessions could silently vanish or split
git -C "$erepo" add -A >/dev/null 2>&1
git -C "$erepo" commit -qm "seed" >/dev/null 2>&1
ewt="$SANDBOX/erepo-wt"
git -C "$erepo" worktree add -q -b wt-session "$ewt" >/dev/null 2>&1
check_dir "worktree fixture exists" "$ewt"
wt_log_before="$(wc -l < "$erepo_store/impact-events.log" | tr -d ' ')"
run_in "$ewt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" event guard secret-guard blocked
check_status "event from a worktree succeeds" 0 "$STATUS"
check_contains "worktree event appends to the MAIN checkout's store log" "$(wc -l < "$erepo_store/impact-events.log" | tr -d ' ')" "$((wt_log_before + 1))"
[ ! -d "$ewt/.keel" ] && pass "no stray worktree-local .keel/" || fail "no stray worktree-local .keel/" "worktree grew its own marker"
# the add also auto-ingests the pending guard event above FROM the main store log — proof the worktree
# session reads and writes the SAME store entry end-to-end (guard=1 ingested + fire=1 cited → 100)
run_in "$ewt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --fire "wt cite" --gap none
check_contains "add from a worktree ingests the MAIN store log and writes the MAIN store ledger" "$(cat "$erepo_store/ledger.md")" "| 100 | low | 1 | 0 | 1 | 0 | 0 | 0 | 0 |"
check_contains "add from a worktree archives to the MAIN store evidence trail" "$(cat "$erepo_store/evidence.md")" "- fire: wt cite"

# enable run FROM a worktree targets the main checkout's id (an in-worktree store entry would fork it)
wrepo="$(new_repo)"
run_in "$wrepo" git commit -qm seed --allow-empty
wrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$wrepo")"
wwt="$SANDBOX/wrepo-wt"
git -C "$wrepo" worktree add -q -b wt-enable "$wwt" >/dev/null 2>&1
run_in "$wwt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable .
check_status "enable from a worktree succeeds" 0 "$STATUS"
check_dir "enable from a worktree creates the store entry at the MAIN id" "$wrepo_store"
[ ! -d "$wwt/.keel" ] && pass "enable leaves no worktree-local marker" || fail "enable leaves no worktree-local marker" "marker created in the worktree"

# bare-main topology: the first worktree-list entry has no working tree — enable falls back to the
# worktree's own top for the id, same as the pre-store resolver always did
brepo="$SANDBOX/bare-main.git"
git clone -q --bare "$wrepo" "$brepo" 2>/dev/null    # reuse the seeded repo above for a HEAD to check out
bwt="$SANDBOX/bare-wt"
git -C "$brepo" worktree add -q -b wt-bare "$bwt" >/dev/null 2>&1
bwt_store="$KEEL_IMPACT_STORE/$(store_id_for "$bwt")"
run_in "$bwt" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable .
check_status "enable under a bare main succeeds" 0 "$STATUS"
check_dir "bare-main enable falls back to the worktree's own top" "$bwt_store"

# not-a-repo-yet: enable must fall back to the dir as-is (regression: the worktree-list probe exits 128
# outside a repo, and under set -euo pipefail an unguarded pipeline killed the whole script)
ngdir="$(mktemp -d "$SANDBOX/nogit.XXXXXX")"
ngdir_store="$KEEL_IMPACT_STORE/$(store_id_for "$ngdir")"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable "$ngdir"
check_status "enable on a not-yet-git dir still succeeds" 0 "$STATUS"
check_dir "not-yet-git enable creates the store entry keyed by the dir as-is" "$ngdir_store"

# --- add/rollup refuse on a never-enabled repo (dir #251 §3 — the OLD silent docs/keel-impact.md
# fallback is gone; a hard, named refusal replaces it) -----------------------------------------------
nrepo="$(new_repo)"
run_in "$nrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --fire "e" --gap none
check_status "add on a never-enabled repo refuses" 2 "$STATUS"
check_contains "add's refusal names the repo and the fix" "$OUT" "run keel-impact.sh enable"
run_in "$nrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "rollup on a never-enabled repo refuses" 2 "$STATUS"
# the OLD silent fallback (a not-enabled repo's add/rollup reading/writing Keel's own
# docs/keel-impact.md) must be structurally gone, not just untriggered by this one fixture
if grep -qE 'REPO_ROOT/docs/keel-impact' "$TOOL"; then
  fail "no resolver falls back to REPO_ROOT/docs/keel-impact*" "found a REPO_ROOT/docs/keel-impact reference in $TOOL"
else
  pass "no resolver falls back to REPO_ROOT/docs/keel-impact*"
fi

# a PARTIAL env override (only $KEEL_IMPACT_LEDGER, not $KEEL_IMPACT_EVIDENCE) on a genuinely
# never-enabled repo must fail CLEANLY, BEFORE anything is written — not crash on a bare `>> ""`
# redirect mid-write, and not half-complete (a scored ledger row with no evidence block, breaking
# evidence.md's own stated invariant). Found live by an operator-run max-depth review across two
# delta rounds: round 1 closed the crash (a refusal inside ensure_evidence, exit 1) but that still ran
# AFTER the ledger row was already appended; round 2 moved the check to the top of cmd_add, before any
# write, so it now shares _impact_require_enabled's own exit code (2).
perepo="$(new_repo)"
partial_ledger="$SANDBOX/partial-ledger.md"
run_in "$perepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_EVIDENCE KEEL_IMPACT_LEDGER="$partial_ledger" \
  bash "$TOOL" add --fire "e" --gap none
check_status "add with only \$KEEL_IMPACT_LEDGER set on a not-enabled repo fails cleanly" 2 "$STATUS"
check_contains "the failure names the tool, not a bare shell redirect error" "$OUT" "keel-impact:"
check_nofile "the ledger row is NOT half-written — nothing happens before the refusal" "$partial_ledger"
check_absent "the failure is not bash's own bare redirect syntax error" "$OUT" "No such file or directory"

# --- migrate: a legacy in-tree .keel/ marker gets swept into the store (explicit path, dir #251 §5) --
lrepo="$(new_repo)"
mkdir -p "$lrepo/.keel"
{
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|"
  printf '| 2026-01-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | e | none |\n'
} > "$lrepo/.keel/ledger.md"
printf '# Keel impact — per-event evidence\n\n## 2026-01-01 — score 100/100 (conf low)\n\n- guard: e\n' > "$lrepo/.keel/evidence.md"
printf '2026-01-01T00:00:00Z\tguard\tsecret-guard\tblocked\t%s\n' "$lrepo" > "$lrepo/.keel/impact-events.log"
lrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$lrepo")"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$lrepo"
check_status "migrate succeeds on a legacy in-tree marker" 0 "$STATUS"
check_dir "migrate creates the store entry" "$lrepo_store"
check_contains "migrate carries the ledger row into the store" "$(cat "$lrepo_store/ledger.md" 2>/dev/null)" "2026-01-01"
check_contains "migrate carries the evidence block into the store" "$(cat "$lrepo_store/evidence.md" 2>/dev/null)" "guard: e"
check_contains "migrate carries the event log into the store" "$(cat "$lrepo_store/impact-events.log" 2>/dev/null)" "secret-guard"
check_nofile "migrate removes the untracked source ledger" "$lrepo/.keel/ledger.md"
check_nodir "migrate rmdirs the now-empty legacy .keel/" "$lrepo/.keel"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$lrepo"
check_status "migrate is idempotent — a second run finds nothing left" 0 "$STATUS"
check_contains "the idempotent re-run says so" "$OUT" "nothing to move"

# --dry-run: prints the plan, writes nothing (verify BEFORE running the real thing, per the spec)
drepo="$(new_repo)"
mkdir -p "$drepo/.keel"
printf '2026-01-03T00:00:00Z\tguard\tsecret-guard\tblocked\t%s\n' "$drepo" > "$drepo/.keel/impact-events.log"
drepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$drepo")"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$drepo" --dry-run
check_status "migrate --dry-run succeeds" 0 "$STATUS"
check_contains "--dry-run names the plan" "$OUT" "would concatenate"
check_nodir "--dry-run creates no store entry" "$drepo_store"
check_file "--dry-run leaves the source untouched" "$drepo/.keel/impact-events.log"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$drepo" --dry-run
check_status "a second --dry-run is equally a no-op" 0 "$STATUS"
check_nodir "still no store entry after a second --dry-run" "$drepo_store"

# --dry-run run FROM INSIDE the project (default dir=".", the documented usage) must ALSO write
# nothing (found live by an operator-run max-depth review): _impact_auto_migrate used to run
# unconditionally at top-level BEFORE dispatch, keyed off the cwd rather than migrate's own `[dir]`
# argument — so `cd project && keel-impact.sh migrate --dry-run` silently did the REAL migration
# first, then cmd_migrate's own dry-run logic ran against an already-emptied .keel/ and reported
# "nothing to move", exactly backwards from the documented contract.
cdrepo="$(new_repo)"
mkdir -p "$cdrepo/.keel"
printf '2026-05-01T00:00:00Z\tguard\tsecret-guard\tblocked\t%s\n' "$cdrepo" > "$cdrepo/.keel/impact-events.log"
cdrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$cdrepo")"
run_in "$cdrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate --dry-run
check_status "migrate --dry-run from inside the project succeeds" 0 "$STATUS"
check_nodir "in-cwd --dry-run creates no store entry" "$cdrepo_store"
check_file "in-cwd --dry-run leaves the source untouched" "$cdrepo/.keel/impact-events.log"

# worktree sweep: migrate collects from the MAIN checkout AND every linked worktree (this is what also
# resolves KB.82's shape — rows stranded in a worktree's own .keel/, not just the main checkout's)
mrepo="$(new_repo)"
mkdir -p "$mrepo/.keel"
printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$mrepo/.keel/ledger.md"
printf '| 2026-02-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | main-row | none |\n' >> "$mrepo/.keel/ledger.md"
git -C "$mrepo" add -A -- ':!.keel'; git -C "$mrepo" commit -qm seed
mwt2="$SANDBOX/mrepo-migrate-wt"
git -C "$mrepo" worktree add -q -b wt-migrate "$mwt2" >/dev/null 2>&1
mkdir -p "$mwt2/.keel"
printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$mwt2/.keel/ledger.md"
printf '| 2026-02-02 | 50 | low | 0 | 0 | 0 | 0 | 1 | 0 | 0 | wt-row | none |\n' >> "$mwt2/.keel/ledger.md"
mrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$mrepo")"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$mrepo"
check_status "migrate with a linked worktree succeeds" 0 "$STATUS"
check_contains "migrate carries the MAIN checkout's row" "$(cat "$mrepo_store/ledger.md" 2>/dev/null)" "main-row"
check_contains "migrate ALSO carries the linked worktree's row" "$(cat "$mrepo_store/ledger.md" 2>/dev/null)" "wt-row"
check_nofile "the worktree's own source is removed too" "$mwt2/.keel/ledger.md"
check_nodir "the worktree's own now-empty .keel/ is rmdir'd too" "$mwt2/.keel"

# --- a merge WRITE FAILURE must never delete the source (found live by an operator-run max-depth
# review): _impact_merge_ledger's last statement used to be `rm -f` its own temp files, so a failed
# `cat ... > target.keelmerge.$$` (the redirect denied, e.g. a read-only store dir) left the temp-file
# cleanup as the function's own reported exit status — success — even though nothing was ever written.
# Callers gate `rm -f "$source"` on that status, so the bug would delete a legacy ledger while its rows
# were never durably saved anywhere. Root can write through any permission bits, so this only tests
# under a non-root reader — same guard this project's other chmod-based tests already use. -----------
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  wrepo="$(new_repo)"
  mkdir -p "$wrepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$wrepo/.keel/ledger.md"
  printf '| 2026-04-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | first-row | none |\n' >> "$wrepo/.keel/ledger.md"
  wrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$wrepo")"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$wrepo"
  check_status "setup: first migrate (creates the store, succeeds normally)" 0 "$STATUS"
  check_file "setup: the store's ledger now exists" "$wrepo_store/ledger.md"
  # A second legacy ledger appears (as if a fresh guardrail-tracked repo scored again before a second
  # migrate); make the STORE dir read-only so the merge's own temp-file write inside it fails.
  mkdir -p "$wrepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$wrepo/.keel/ledger.md"
  printf '| 2026-04-02 | 50 | low | 0 | 0 | 0 | 0 | 1 | 0 | 0 | second-row | none |\n' >> "$wrepo/.keel/ledger.md"
  before_ledger="$(cat "$wrepo_store/ledger.md")"
  chmod 555 "$wrepo_store"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$wrepo"
  chmod 755 "$wrepo_store"
  check_contains "a failed merge write leaves the legacy source UNDELETED" "$([ -f "$wrepo/.keel/ledger.md" ] && echo present)" "present"
  check_contains "the store's ledger is unchanged by the failed write (no partial/lost content)" "$(cat "$wrepo_store/ledger.md")" "$before_ledger"

  # An UNREADABLE (but untracked) source must never be merged-and-deleted either (found live by the
  # same review): an awk/cat that can't open one of several input files often just skips it silently
  # rather than failing, so "the merge reported success" would not mean "all the data survived" —
  # migrate must leave an unreadable source alone entirely rather than risk that.
  urepo="$(new_repo)"
  mkdir -p "$urepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$urepo/.keel/ledger.md"
  printf '| 2026-04-03 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | unreadable-row | none |\n' >> "$urepo/.keel/ledger.md"
  chmod 000 "$urepo/.keel/ledger.md"
  urepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$urepo")"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$urepo"
  chmod 644 "$urepo/.keel/ledger.md"
  check_status "migrate on an unreadable source still succeeds (leaves it be)" 0 "$STATUS"
  check_file "the unreadable source is left in place, not deleted" "$urepo/.keel/ledger.md"
  check_nofile "the unreadable source was never merged into the store" "$urepo_store/ledger.md"
fi

# a TRACKED legacy ledger is never touched automatically — printed as three options instead
trepo="$(new_repo)"
mkdir -p "$trepo/.keel"
printf 'tracked ledger content\n' > "$trepo/.keel/ledger.md"
git -C "$trepo" add .keel/ledger.md
git -C "$trepo" commit -qm "tracked ledger"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$trepo"
check_status "migrate on a tracked-only legacy repo still succeeds" 0 "$STATUS"
check_contains "migrate prints the three options for a tracked source" "$OUT" "git rm --cached"
check_file "the tracked source is left in place" "$trepo/.keel/ledger.md"
# a tracked legacy repo keeps working via its in-tree file — impact_ledger_path's own legacy fallback
run_in "$trepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "rollup on a tracked-legacy repo keeps working (never refuses)" 0 "$STATUS"

# --- PARTIAL migration regression (found live by an operator-run max-depth review): ledger.md +
# evidence.md TRACKED and left in place, impact-events.log UNTRACKED and migrated — the realistic
# adopter shape (the tool's own old `enable` advice: gitignore only the log, ledger/evidence stay
# trackable). Once the log moves, the store DIRECTORY exists — impact_ledger_path/evidence_path must
# NOT flip to it just because the store dir exists; they must keep resolving to the still-tracked
# legacy files specifically, or `add` silently starts a second, empty ledger in the store while the
# real tracked history never gets another row. ------------------------------------------------------
prepo="$(new_repo)"
mkdir -p "$prepo/.keel"
{
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|"
  printf '| 2026-03-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | tracked-row | none |\n'
} > "$prepo/.keel/ledger.md"
printf '# Keel impact — per-event evidence\n\n## 2026-03-01 — score 100/100 (conf low)\n\n- guard: tracked-row\n' > "$prepo/.keel/evidence.md"
printf '2026-03-02T00:00:00Z\tguard\tsecret-guard\tblocked\t%s\n' "$prepo" > "$prepo/.keel/impact-events.log"
git -C "$prepo" add .keel/ledger.md .keel/evidence.md
git -C "$prepo" commit -qm "tracked ledger+evidence"
prepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$prepo")"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$prepo"
check_status "partial migrate (log only) succeeds" 0 "$STATUS"
check_file "the untracked log moved into the store" "$prepo_store/impact-events.log"
check_file "the tracked ledger stays at its legacy path" "$prepo/.keel/ledger.md"
check_file "the tracked evidence stays at its legacy path" "$prepo/.keel/evidence.md"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash -c ". '$REPO_ROOT/tools/lib/impact-store.sh'; impact_ledger_path '$prepo'"
check_contains "impact_ledger_path still resolves to the TRACKED legacy file, not the store" "$OUT" "$prepo/.keel/ledger.md"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash -c ". '$REPO_ROOT/tools/lib/impact-store.sh'; impact_evidence_path '$prepo'"
check_contains "impact_evidence_path still resolves to the TRACKED legacy file, not the store" "$OUT" "$prepo/.keel/evidence.md"
run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash -c ". '$REPO_ROOT/tools/lib/impact-store.sh'; impact_log_path '$prepo'"
check_contains "impact_log_path resolves to the STORE (it was migrated)" "$OUT" "$prepo_store/impact-events.log"
run_in "$prepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" add --fire "second row" --gap none
check_status "add after a partial migrate succeeds" 0 "$STATUS"
check_contains "add's new row lands in the TRACKED legacy ledger" "$(cat "$prepo/.keel/ledger.md")" "second row"
check_absent "the store's ledger was never created (nothing to write there)" "$(ls "$prepo_store" 2>/dev/null)" "ledger.md"

# --- auto-migrate: an ALL-untracked legacy marker migrates silently on the next plain resolve --------
arepo="$(new_repo)"
mkdir -p "$arepo/.keel"
printf '2026-01-02T00:00:00Z\tguard\tsecret-guard\tblocked\t%s\n' "$arepo" > "$arepo/.keel/impact-events.log"
arepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$arepo")"
run_in "$arepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "a plain rollup on an all-untracked legacy repo auto-migrates and succeeds" 0 "$STATUS"
check_dir "auto-migrate created the store entry" "$arepo_store"
check_contains "auto-migrate carried the legacy log into the store" "$(cat "$arepo_store/impact-events.log" 2>/dev/null)" "secret-guard"
check_nofile "auto-migrate removed the legacy in-tree log" "$arepo/.keel/impact-events.log"

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

# dir #251 review finding: a project D4 deliberately leaves on its TRACKED legacy ledger (no store
# copy at all — the exact shape of the two real adopter repos this ticket is about) must still show
# up in the registry sweep, not silently read as "tracking off".
pd="$(new_repo)"
mkdir -p "$pd/.keel"
{
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|"
  printf '| 2026-06-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | tracked-row | none |\n'
} > "$pd/.keel/ledger.md"
git -C "$pd" add .keel/ledger.md
git -C "$pd" commit -qm "tracked ledger"
reg2="$SANDBOX/INSTANCE2.md"
{
  printf '## Projects\n\n| Name | Path | Tag |\n|------|------|-----|\n'
  printf '| pd | `%s` | x |\n' "$pd"
} > "$reg2"
run bash "$TOOL" rollup --registry "$reg2"
check_status "rollup --registry with a tracked-legacy project succeeds" 0 "$STATUS"
check_contains "the tracked-legacy project's mean shows up, not 'tracking off'" "$OUT" "mean 100.0/100 over 1 scored"

# --- dir #107: rollup and _ledger_stats must share ONE ledger-column parser, not re-derive it ------
# The file's own header comment (_ledger_table_header + _ledger_parse) says the column indices must stay in
# sync; pin that at the SOURCE level (dir #126: an output-level check can't tell "shares a parser"
# from "two parsers that happen to agree today"). Both callers should delegate to _ledger_parse, and
# no second awk block should independently match the ledger's date-column regex.
if grep -qE '_ledger_parse "\$LEDGER" "\$mode"' "$TOOL"; then
  pass "rollup delegates to _ledger_parse"
else
  fail "rollup delegates to _ledger_parse" "rollup no longer calls _ledger_parse — re-duplicated?"
fi
if grep -qE '_ledger_stats\(\) \{' "$TOOL" && sed -n '/^_ledger_stats() {/,/^}/p' "$TOOL" | grep -q '_ledger_parse'; then
  pass "_ledger_stats delegates to _ledger_parse"
else
  fail "_ledger_stats delegates to _ledger_parse" "_ledger_stats no longer calls _ledger_parse — re-duplicated?"
fi

# --- dir #151: the ledger's 12 columns must come from ONE ordered array (_LEDGER_COLS), not be
# hand-listed independently by the writer (cmd_add), the reader (_ledger_parse), and the header
# (_ledger_table_header). dir #107 unified the two READERS behind _ledger_parse; dir #131 then caught, but
# didn't prevent, the WRITER (cmd_add's row-printf) drifting from it — both still hand-indexed the
# same columns in their own syntax. This block replaces both dir #107's and dir #131's structural
# checks (which pinned the very hand-indexing this refactor removes — a literal `$5`/`$6`/`$9` or a
# fixed `printf '| %s | %s | ...'` no longer exists to match) with checks against the array itself.
#
# Extract the tool's actual _LEDGER_COLS definition (a plain array literal — safe to eval) rather than
# hardcoding the column list here. Most of the checks below (col-pos-vs-array consistency, cmd_add's
# per-column mapping coverage) are drift detectors that self-adjust to whatever the array currently
# holds — no edit needed here when a column is added. Two checks are a deliberate exception: the
# `n_cols -eq 12` count and `expect_pos`'s literal name:position pairs below PIN dir #151's actual
# column list and positions as of this ticket, on purpose — a real column addition/reorder SHOULD fail
# them until this file is updated to match, the same way it should fail any other spec-pinning test.
ledger_cols_line="$(grep -n '^_LEDGER_COLS=(' "$TOOL" | head -1 | cut -d: -f1)"
if [ -z "$ledger_cols_line" ]; then
  fail "_LEDGER_COLS array located" "no line matching \"_LEDGER_COLS=(\" found in $TOOL"
else
  eval "$(sed -n "${ledger_cols_line}p" "$TOOL")"
  n_cols="${#_LEDGER_COLS[@]}"

  if [ "$n_cols" -eq 12 ]; then
    pass "_LEDGER_COLS has the ledger's 12 columns"
  else
    fail "_LEDGER_COLS has the ledger's 12 columns" "found $n_cols: ${_LEDGER_COLS[*]:-<none>}"
  fi

  # _ledger_col_pos (the reader-side lookup) must actually answer from the array, not a parallel
  # hardcoded table — call the real function (sourcing the tool is unsafe, it dispatches a case
  # statement at the bottom, so extract+eval just this one function's body).
  pos_fn="$(sed -n '/^_ledger_col_pos() {/,/^}/p' "$TOOL")"
  eval "$pos_fn"
  pos_ok=1
  expect_pos=(date:2 score:3 conf:4 guard:5 hold:6 fire:7 hit:8 miss:9 fric:10 silent:11 evidence:12 gap:13)
  for pair in "${expect_pos[@]}"; do
    col="${pair%%:*}"; want="${pair#*:}"
    got="$(_ledger_col_pos "$col" 2>/dev/null || true)"
    if [ "$got" != "$want" ]; then
      pos_ok=0
      fail "_ledger_col_pos('$col') returns its documented position" "want $want, got ${got:-<empty>}"
    fi
  done
  [ "$pos_ok" -eq 1 ] && pass "_ledger_col_pos returns every column's documented table position"

  # _ledger_parse must read its field numbers from _ledger_col_pos (via -v vars), never a hardcoded
  # digit — the same "SOURCE level, not output level" reasoning as the old dir #107/#131 checks: an
  # output-level check on one row can't tell "derived from the array" from "coincidentally still 12
  # columns wide today". It loops `_ledger_col_pos "$_col"` over the 6 columns it actually needs
  # (date/score/conf/guard/hold/miss — the rest go unused by rollup's stats) rather than one call per
  # column, so check for the loop shape instead of six separate literal-string greps.
  parse_fn="$(sed -n '/^_ledger_parse() {/,/^}/p' "$TOOL")"
  if grep -qE 'for _col in date score conf guard hold miss;' <<<"$parse_fn" \
    && grep -q '_ledger_col_pos "\$_col"' <<<"$parse_fn"; then
    pass "_ledger_parse derives date/score/conf/guard/hold/miss positions via _ledger_col_pos"
  else
    fail "_ledger_parse derives date/score/conf/guard/hold/miss positions via _ledger_col_pos" \
      "no longer loops _ledger_col_pos over date/score/conf/guard/hold/miss — hardcoded again?"
  fi

  # dir #107's original whole-FILE scan (not just this one function) caught a second, independently
  # hand-rolled ledger-column reader appearing ANYWHERE else in the file, by matching a semantic
  # signature (all three of guard/hold/miss extracted the same way) rather than one literal spelling —
  # this refactor changed that signature (a hardcoded `$5`/`$6`/`$9` became `$guard_col`/`$hold_col`/
  # `$miss_col`, computed via _ledger_col_pos), so the check must be repointed to the NEW signature to
  # keep covering the same ground: a copy-pasted second reader would very likely keep these standing
  # variable names (guard/hold/miss are used throughout the file — see add_cite's _n_guard etc.)
  # regardless of how its own field-position derivation or statement layout was rewritten.
  sig_blocks="$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ { buf=""; in_fn=1; next }
    in_fn && /^\}[[:space:]]*$/ {
      gsub(/[ \t]/, "", buf)
      if (index(buf, "guard+=$guard_col+0") && index(buf, "hold+=$hold_col+0") && index(buf, "miss+=$miss_col+0")) hits++
      in_fn=0; next
    }
    in_fn { buf = buf $0 }
    END { print hits+0 }
  ' "$TOOL")"
  if [ "$sig_blocks" -eq 1 ]; then
    pass "ledger column-extraction signature (guard=\$guard_col,hold=\$hold_col,miss=\$miss_col) appears in exactly one function"
  else
    fail "ledger column-extraction signature (guard=\$guard_col,hold=\$hold_col,miss=\$miss_col) appears in exactly one function" \
      "found in $sig_blocks function(s) — a parser was re-duplicated"
  fi
  # Only the awk PROGRAM (the string after `awk -F'|' ...`) is at risk of a hardcoded field ref —
  # exclude the shell preamble above it, which legitimately reads bash's own $1/$2 positional args.
  awk_prog="$(sed -n "/^  awk -F/,\$p" <<<"$parse_fn")"
  if grep -qE '\$[0-9]' <<<"$awk_prog"; then
    fail "_ledger_parse's awk program has no leftover hardcoded numeric field refs" \
      "found a \$<digit> in: $(grep -oE '\$[0-9]+' <<<"$awk_prog" | tr '\n' ' ')"
  else
    pass "_ledger_parse's awk program has no leftover hardcoded numeric field refs"
  fi

  # cmd_add (the writer) must build its row by iterating _LEDGER_COLS, and every column the array
  # names must actually be mapped to a value — a column added to the array with no matching case arm
  # would otherwise fall through to the catch-all and only fail at RUN time, not at review time; this
  # test catches it structurally, matching the array's CURRENT contents (extracted above), so a
  # consumer that silently stopped reading the array — or stopped covering one of its columns — is
  # caught even if it still happens to produce a 12-column row today.
  # cmd_add is a big function; grab it precisely by matching the next top-level `}` at column 0.
  add_fn="$(awk '/^cmd_add\(\) \{/{f=1} f{print} f && /^\}$/{exit}' "$TOOL")"
  if grep -qE 'for _col in "\$\{_LEDGER_COLS\[@\]\}"' <<<"$add_fn"; then
    pass "cmd_add builds its row by iterating _LEDGER_COLS"
  else
    fail "cmd_add builds its row by iterating _LEDGER_COLS" "no \`for _col in \"\${_LEDGER_COLS[@]}\"\` found in cmd_add"
  fi
  map_ok=1
  for col in "${_LEDGER_COLS[@]}"; do
    if ! grep -qE "^ *${col}\)" <<<"$add_fn"; then
      map_ok=0
      fail "cmd_add maps ledger column '$col' to a row value" "no \`$col)\` case arm found in cmd_add"
    fi
  done
  [ "$map_ok" -eq 1 ] && pass "cmd_add maps every _LEDGER_COLS entry to a row value"
fi

summary
