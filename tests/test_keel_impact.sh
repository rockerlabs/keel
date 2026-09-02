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
# legacy_log_repo MARKER — a fresh repo carrying an UNTRACKED legacy in-tree event log, the fixture
# every auto-migrate case below needs. MARKER goes in the detail column so a test can assert which
# repo's line was carried. The timestamp is fixed and far past the 12h ingest cap on purpose: no case
# here wants the line ingested, only migrated. Prints the repo path; derive its store with
# store_id_for, which is why this doesn't try to return two values.
legacy_log_repo() {
  local d; d="$(new_repo)"; mkdir -p "$d/.keel"
  printf '2026-01-02T00:00:00Z\tguard\tsecret-guard\t%s\t%s\n' "$1" "$d" > "$d/.keel/impact-events.log"
  printf '%s' "$d"
}

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

  # --- cmd_migrate must also stay safe when the merge's READ (not its write) fails: a target that goes
  # unreadable slips past every existing pre-check (cmd_migrate's own scan only inspects the untracked
  # SOURCE's readability, exercised above — never the STORE's existing target). This is verified via
  # `migrate` for parity with the write-failure/unreadable-source tests above. dir #304: cmd_migrate's
  # own merge calls are now `&&`/`||`-gated the same way _impact_auto_migrate's always were (an explicit
  # `ok` variable, checked before the completion marker is written and before the function returns) —
  # before that fix this scenario's non-zero exit came from `set -e` catching the awk's own bare,
  # unguarded failure and aborting the whole script; now it comes from cmd_migrate's own explicit
  # `return 1`, and along the way `$store/origin` is no longer written on this failure either (pinned
  # below via the mgrepo fixture, which — unlike this one — starts from no prior origin at all).
  # Confirmed by re-running this exact scenario against the pre-dir-#304 code: identical outcome, same
  # exit status, same undeleted source — this pins cmd_migrate's overall behavior, not the new mechanism. ---
  rrepo="$(new_repo)"
  mkdir -p "$rrepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$rrepo/.keel/ledger.md"
  printf '| 2026-05-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | first-row | none |\n' >> "$rrepo/.keel/ledger.md"
  rrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$rrepo")"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$rrepo"
  check_status "setup: first migrate for the ledger read-failure case succeeds" 0 "$STATUS"
  before_target="$(cat "$rrepo_store/ledger.md")"
  mkdir -p "$rrepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$rrepo/.keel/ledger.md"
  printf '| 2026-05-02 | 50 | low | 0 | 0 | 0 | 0 | 1 | 0 | 0 | second-row | none |\n' >> "$rrepo/.keel/ledger.md"
  chmod 000 "$rrepo_store/ledger.md"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$rrepo"
  chmod 644 "$rrepo_store/ledger.md"
  check_contains "a failed ledger merge READ is reported non-zero, not silently 0" "$([ "$STATUS" != 0 ] && echo failed)" "failed"
  check_contains "a failed ledger merge READ leaves the legacy source UNDELETED" "$([ -f "$rrepo/.keel/ledger.md" ] && echo present)" "present"
  check_contains "the store's ledger is unchanged by the failed read (no partial/lost content)" "$(cat "$rrepo_store/ledger.md")" "$before_target"

  # Same READ-status blind spot in _impact_merge_evidence, same fix.
  vrepo="$(new_repo)"
  mkdir -p "$vrepo/.keel"
  printf '# Keel impact — per-event evidence\n\n## 2026-05-01 — score 100/100 (conf low)\n\n- guard: first-row\n' > "$vrepo/.keel/evidence.md"
  vrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$vrepo")"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$vrepo"
  check_status "setup: first migrate for the evidence read-failure case succeeds" 0 "$STATUS"
  before_evidence="$(cat "$vrepo_store/evidence.md")"
  mkdir -p "$vrepo/.keel"
  printf '# Keel impact — per-event evidence\n\n## 2026-05-02 — score 50/100 (conf low)\n\n- miss: second-row\n' > "$vrepo/.keel/evidence.md"
  chmod 000 "$vrepo_store/evidence.md"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$vrepo"
  chmod 644 "$vrepo_store/evidence.md"
  check_contains "a failed evidence merge READ leaves the legacy source UNDELETED" "$([ -f "$vrepo/.keel/evidence.md" ] && echo present)" "present"
  check_contains "the store's evidence is unchanged by the failed read" "$(cat "$vrepo_store/evidence.md")" "$before_evidence"

  # --- dir #289: a failed auto-migrate pass must retry on the NEXT resolve, not strand forever --------
  # the store's completion marker (`origin`) used to be written BEFORE the merges ran; a failure
  # between the two permanently satisfied the old `[ -d "$store" ]` idempotency guard, and no automatic
  # path (`add`/`event`/`rollup`) would ever try again — recoverable only by an explicit `migrate`,
  # which nothing prompts the operator to run. `origin` is now written only once every present legacy
  # file has actually been swept. Reproduce a failure (the store's own target unreadable, same shape as
  # above) via a PLAIN `rollup` — the AUTOMATIC path this ticket is actually about, not the explicit
  # `migrate` command — and confirm: (a) rollup itself still succeeds (auto-migrate is best-effort and
  # must never abort a plain add/rollup/event over this), (b) the legacy source survives untouched, (c)
  # the completion marker stays unwritten so a retry stays possible, and (d) once the target is
  # readable again, the VERY NEXT resolve completes the merge on its own, with no operator action. -----
  strepo="$(new_repo)"
  strepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$strepo")"
  mkdir -p "$strepo_store"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$strepo_store/ledger.md"
  printf '| 2026-05-30 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | already-in-store | none |\n' >> "$strepo_store/ledger.md"
  chmod 000 "$strepo_store/ledger.md"
  mkdir -p "$strepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$strepo/.keel/ledger.md"
  printf '| 2026-06-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | stranding-row | none |\n' >> "$strepo/.keel/ledger.md"
  run_in "$strepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  check_status "a plain rollup survives a failed auto-migrate attempt (best-effort, never fatal)" 0 "$STATUS"
  chmod 644 "$strepo_store/ledger.md"
  check_file "a failed auto-migrate attempt leaves the legacy source in place" "$strepo/.keel/ledger.md"
  check_nofile "a failed auto-migrate attempt never writes the completion marker" "$strepo_store/origin"
  check_contains "the store's own pre-existing row is unharmed by the failed attempt" "$(cat "$strepo_store/ledger.md")" "already-in-store"
  # now that the target is readable again, the very next resolve completes the merge on its own
  run_in "$strepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  check_status "the retry succeeds" 0 "$STATUS"
  check_file "the retry writes the completion marker" "$strepo_store/origin"
  check_nofile "the retry removes the now-merged legacy source" "$strepo/.keel/ledger.md"
  check_nodir "the retry rmdirs the now-empty .keel/" "$strepo/.keel"
  check_contains "the retry's merge carries the previously-stranded row" "$(cat "$strepo_store/ledger.md")" "stranding-row"
  check_contains "the retry's merge kept the pre-existing store row too" "$(cat "$strepo_store/ledger.md")" "already-in-store"

  # Same shape as strepo above, but for _impact_merge_evidence — the ledger case above goes through
  # _impact_auto_migrate's own `&&`/`||`-wrapped call, which is the ONLY context where this diff's own
  # read-status gating is actually reachable (a bare call, like cmd_migrate's, hits `set -e` before ever
  # reaching it — see the rrepo/vrepo comment above). Evidence needs its own instance of this test: the
  # two merge helpers are separate functions with separate awk programs, and nothing else in this file
  # exercises evidence's read-status capture through a reachable call path.
  sverepo="$(new_repo)"
  sverepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$sverepo")"
  mkdir -p "$sverepo_store"
  printf '# Keel impact — per-event evidence\n\n## 2026-05-30 — score 100/100 (conf low)\n\n- guard: already-in-store\n' > "$sverepo_store/evidence.md"
  chmod 000 "$sverepo_store/evidence.md"
  mkdir -p "$sverepo/.keel"
  printf '# Keel impact — per-event evidence\n\n## 2026-06-01 — score 100/100 (conf low)\n\n- guard: stranding-row\n' > "$sverepo/.keel/evidence.md"
  run_in "$sverepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  check_status "a plain rollup survives a failed evidence auto-migrate attempt" 0 "$STATUS"
  chmod 644 "$sverepo_store/evidence.md"
  check_file "the failed evidence attempt leaves the legacy source in place" "$sverepo/.keel/evidence.md"
  check_nofile "the failed evidence attempt never writes the completion marker" "$sverepo_store/origin"
  check_contains "the store's own pre-existing evidence block is unharmed" "$(cat "$sverepo_store/evidence.md")" "already-in-store"
  run_in "$sverepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  check_status "the evidence retry succeeds" 0 "$STATUS"
  check_file "the evidence retry writes the completion marker" "$sverepo_store/origin"
  check_nofile "the evidence retry removes the now-merged legacy source" "$sverepo/.keel/evidence.md"
  check_contains "the evidence retry carries the previously-stranded block" "$(cat "$sverepo_store/evidence.md")" "stranding-row"
  check_contains "the evidence retry kept the pre-existing store block too" "$(cat "$sverepo_store/evidence.md")" "already-in-store"

  # --- dir #304, scenario 1: an EXPLICIT `migrate` that fails mid-merge must not strand the
  # completion marker either — before this ticket cmd_migrate wrote `$store/origin` up front,
  # unconditionally, before ever attempting the merge (unlike _impact_auto_migrate, which already
  # gated it, dir #289). Same shape as strepo/sverepo above (a fresh store with a pre-existing
  # unreadable target ledger and a legacy source waiting to be merged), but driven through the
  # explicit `migrate` command itself, not an automatic resolve. ------------------------------------
  mgrepo="$(new_repo)"
  mgrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$mgrepo")"
  mkdir -p "$mgrepo_store"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$mgrepo_store/ledger.md"
  printf '| 2026-07-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | already-in-store | none |\n' >> "$mgrepo_store/ledger.md"
  chmod 000 "$mgrepo_store/ledger.md"
  mkdir -p "$mgrepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$mgrepo/.keel/ledger.md"
  printf '| 2026-07-02 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | migrate-stranding-row | none |\n' >> "$mgrepo/.keel/ledger.md"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$mgrepo"
  check_contains "an explicit migrate that fails mid-merge is reported non-zero" "$([ "$STATUS" != 0 ] && echo failed)" "failed"
  chmod 644 "$mgrepo_store/ledger.md"
  check_file "the failed explicit migrate leaves the legacy source in place" "$mgrepo/.keel/ledger.md"
  check_nofile "the failed explicit migrate never writes the completion marker" "$mgrepo_store/origin"
  check_contains "the store's own pre-existing row survives the failed migrate" "$(cat "$mgrepo_store/ledger.md")" "already-in-store"
  # once the target is readable again, re-running migrate completes it — no state to hand-repair first
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" migrate "$mgrepo"
  check_status "re-running the explicit migrate succeeds" 0 "$STATUS"
  check_file "the retried migrate writes the completion marker" "$mgrepo_store/origin"
  check_nofile "the retried migrate removes the now-merged legacy source" "$mgrepo/.keel/ledger.md"
  check_contains "the retried migrate carries the previously-stranded row" "$(cat "$mgrepo_store/ledger.md")" "migrate-stranding-row"
  check_contains "the retried migrate kept the pre-existing store row too" "$(cat "$mgrepo_store/ledger.md")" "already-in-store"

  # --- dir #304, scenario 2: `enable` must not have `impact_store_enable` write the completion
  # marker over a genuinely FAILED auto-migrate attempt either — before this ticket
  # impact_store_enable wrote `$store/origin` unconditionally, with no merge of its own to gate on,
  # so it would silently paper over a failure `_impact_begin`'s own auto-migrate just had (swallowed
  # via `|| true`, so `enable` itself always reports success) and permanently block the next
  # automatic retry. --------------------------------------------------------------------------------
  enfrepo="$(new_repo)"
  enfrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$enfrepo")"
  mkdir -p "$enfrepo_store"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$enfrepo_store/ledger.md"
  printf '| 2026-07-10 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | already-in-store | none |\n' >> "$enfrepo_store/ledger.md"
  chmod 000 "$enfrepo_store/ledger.md"
  mkdir -p "$enfrepo/.keel"
  printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$enfrepo/.keel/ledger.md"
  printf '| 2026-07-11 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | enable-stranding-row | none |\n' >> "$enfrepo/.keel/ledger.md"
  run_in "$enfrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable .
  check_status "enable succeeds even though its own auto-migrate attempt just failed" 0 "$STATUS"
  chmod 644 "$enfrepo_store/ledger.md"
  check_file "the failed auto-migrate attempt (via enable) leaves the legacy source in place" "$enfrepo/.keel/ledger.md"
  check_nofile "enable does not write the completion marker over a failed auto-migrate" "$enfrepo_store/origin"
  check_contains "the store's own pre-existing row survives the failed attempt" "$(cat "$enfrepo_store/ledger.md")" "already-in-store"
  # the failure is not permanently stranded: a later plain resolve still retries automatically
  run_in "$enfrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  check_status "a later resolve after the failed enable succeeds" 0 "$STATUS"
  check_file "the later resolve writes the completion marker" "$enfrepo_store/origin"
  check_nofile "the later resolve removes the now-merged legacy source" "$enfrepo/.keel/ledger.md"
  check_contains "the later resolve carries the previously-stranded row" "$(cat "$enfrepo_store/ledger.md")" "enable-stranding-row"
fi

# --- v0.8.0 delta audit F-06: a failure in EITHER `sort` stage of _impact_merge_ledger's rows
# pipeline must be detected, not silently reported as success. The line used to read
# `rows_status="${PIPESTATUS[0]}"` — awk's exit status alone — discarding what `pipefail` (set
# file-wide at line 36) already computes correctly in a plain `$?` read right after the pipe. A
# masked failure here would let _impact_auto_migrate's caller `rm -f` the legacy
# source after writing nothing durable, losing the row entirely. No chmod/root-guard needed — this
# reproduces via a `sort` stub on $PATH that fails only the SECOND stage (the `-t'|' -k... -s`
# date-column sort), so it works identically under a root CI leg. Driven through the PRODUCTION
# call path — a plain automatic resolve on a legacy in-tree repo, i.e. _impact_auto_migrate's own
# `&&`/`||`-exempt call to _impact_merge_ledger — not a bare call: `set -e` is exempt for the
# whole nested call there, so unlike a bare invocation (which `pipefail`+`errexit` would abort
# immediately, before `rows_status` is even read) the pipeline's failure must actually be READ to be
# caught; that is exactly the gap `${PIPESTATUS[0]}` left open. Verified live before writing this
# test: the pre-fix line reports rows_status=0 (masked success) called this exact way; `$?` reports
# the real nonzero status. ----------------------------------------------------------------------
sfrepo="$(new_repo)"
mkdir -p "$sfrepo/.keel"
printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$sfrepo/.keel/ledger.md"
printf '| 2026-08-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | sort-fail-row | none |\n' >> "$sfrepo/.keel/ledger.md"
sfrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$sfrepo")"
sort_stub_bin="$SANDBOX/sort-stub-bin"; mkdir -p "$sort_stub_bin"
real_sort="$(command -v sort)"
{
  printf '#!/usr/bin/env bash\n'
  printf 'for a in "$@"; do case "$a" in -t*) exit 3 ;; esac; done\n'
  printf 'exec %q "$@"\n' "$real_sort"
} > "$sort_stub_bin/sort"
chmod +x "$sort_stub_bin/sort"
run_in "$sfrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE PATH="$sort_stub_bin:$PATH" bash "$TOOL" rollup
check_status "a plain rollup survives a sort-stage failure in auto-migrate's ledger merge (best-effort, never fatal)" 0 "$STATUS"
check_file "a sort-stage failure leaves the legacy ledger source UNDELETED (rm never fires on a masked failure)" "$sfrepo/.keel/ledger.md"
check_contains "the source's row survives — never silently lost" "$(cat "$sfrepo/.keel/ledger.md")" "sort-fail-row"
check_nofile "a sort-stage failure never writes the completion marker" "$sfrepo_store/origin"
# the failure is not permanently stranded: with a working sort, the very next resolve completes it
run_in "$sfrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "the retry (real sort) succeeds" 0 "$STATUS"
check_file "the retry writes the completion marker" "$sfrepo_store/origin"
check_nofile "the retry removes the now-merged legacy source" "$sfrepo/.keel/ledger.md"
check_contains "the retry carries the row that the sort failure had blocked" "$(cat "$sfrepo_store/ledger.md")" "sort-fail-row"

# --- v0.8.0 delta audit F-17: the block above only fails the SECOND `sort` stage (its stub matches
# `-t*`, which only that stage's date-column sort passes) — the FIRST stage, `LC_ALL=C sort -u` with
# no `-t` flag, always passes through untouched. So that block alone does not prove `pipefail` (set
# file-wide at line 36) is actually load-bearing: `$?` read right after a pipe reflects the LAST
# stage's status even withOUT pipefail, so a stub that only ever fails the last stage would report
# the same `rows_status` either way. Reproduced live before writing this: with `pipefail` removed and
# only the SECOND stage failing, `$?` is still nonzero. The gap is a stub that fails an EARLIER stage
# while the LAST stage still succeeds (on whatever partial/empty input the earlier failure left it) —
# that is the one shape where plain `$?` (no pipefail) reports 0/masked-success and pipefail alone
# catches it. This stub fails the first `sort -u` (matches a bare `-u` arg, which only that call
# passes — the second sort's `-t'|' -k... -s` never does), leaving the downstream `sort -t...` to
# receive nothing and exit 0 on its own — exactly the shape that needs pipefail to be read as a
# failure. -------------------------------------------------------------------------------------------
pf2repo="$(new_repo)"
mkdir -p "$pf2repo/.keel"
printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|" > "$pf2repo/.keel/ledger.md"
printf '| 2026-08-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | pipefail-fail-row | none |\n' >> "$pf2repo/.keel/ledger.md"
pf2repo_store="$KEEL_IMPACT_STORE/$(store_id_for "$pf2repo")"
sort_stub_bin2="$SANDBOX/sort-stub-bin2"; mkdir -p "$sort_stub_bin2"
{
  printf '#!/usr/bin/env bash\n'
  printf 'for a in "$@"; do case "$a" in -u) exit 3 ;; esac; done\n'
  printf 'exec %q "$@"\n' "$real_sort"
} > "$sort_stub_bin2/sort"
chmod +x "$sort_stub_bin2/sort"
run_in "$pf2repo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE PATH="$sort_stub_bin2:$PATH" bash "$TOOL" rollup
check_status "a plain rollup survives a FIRST-stage sort failure in auto-migrate's ledger merge (best-effort, never fatal)" 0 "$STATUS"
check_file "a first-stage sort failure leaves the legacy ledger source UNDELETED (rm never fires on a masked failure)" "$pf2repo/.keel/ledger.md"
check_contains "the source's row survives — never silently lost" "$(cat "$pf2repo/.keel/ledger.md")" "pipefail-fail-row"
check_nofile "a first-stage sort failure never writes the completion marker" "$pf2repo_store/origin"
# not permanently stranded: with a working sort, the very next resolve completes it
run_in "$pf2repo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "the retry (real sort) succeeds" 0 "$STATUS"
check_file "the retry writes the completion marker" "$pf2repo_store/origin"
check_nofile "the retry removes the now-merged legacy source" "$pf2repo/.keel/ledger.md"
check_contains "the retry carries the row that the first-stage sort failure had blocked" "$(cat "$pf2repo_store/ledger.md")" "pipefail-fail-row"

# --- a `mv` failure AFTER a successful merge write must never leave an orphaned temp file behind:
# found by a /code-review delta pass on this same fix — the sibling _impact_merge_log's identical
# leak (mv failing after a successful sort — see its own "Unconditional, not just on the
# awk/write-failure branch above" comment) was fixed by moving its `rm -f "$tmp"` out of the
# else-branch-only cleanup to an unconditional trailing statement; _impact_merge_evidence had the
# SAME two-branch cleanup and the SAME gap, just guarding its own awk write instead of a sort. No
# data-loss risk either way (`write_status` was already correctly nonzero on a failed mv) — only a
# stray `evidence.md.keelmerge.$$` left in the store dir. Driven through the PRODUCTION call path (a
# plain automatic resolve, like sfrepo above) with a stubbed `mv` on $PATH that always fails; no
# chmod/root-guard needed. -----------------------------------------------------------------------
mvrepo="$(new_repo)"
mkdir -p "$mvrepo/.keel"
printf '# Keel impact — per-event evidence\n\n## 2026-08-02 — score 100/100 (conf low)\n\n- guard: mv-fail-row\n' > "$mvrepo/.keel/evidence.md"
mvrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$mvrepo")"
mv_stub_bin="$SANDBOX/mv-stub-bin"; mkdir -p "$mv_stub_bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$mv_stub_bin/mv"
chmod +x "$mv_stub_bin/mv"
run_in "$mvrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE PATH="$mv_stub_bin:$PATH" bash "$TOOL" rollup
check_status "a plain rollup survives a failed mv in auto-migrate's evidence merge (best-effort, never fatal)" 0 "$STATUS"
check_file "a failed mv leaves the legacy evidence source UNDELETED" "$mvrepo/.keel/evidence.md"
check_nofile "a failed mv never writes the completion marker" "$mvrepo_store/origin"
check_absent "a failed mv leaves NO orphaned merge temp file behind" "$(ls "$mvrepo_store" 2>/dev/null)" "evidence.md.keelmerge."
# the failure is not permanently stranded: with a working mv, the very next resolve completes it
run_in "$mvrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "the retry (real mv) succeeds" 0 "$STATUS"
check_file "the retry writes the completion marker" "$mvrepo_store/origin"
check_nofile "the retry removes the now-merged legacy source" "$mvrepo/.keel/evidence.md"
check_contains "the retry carries the block that the mv failure had blocked" "$(cat "$mvrepo_store/evidence.md")" "mv-fail-row"

# --- v0.8.0 delta audit CA-01: the orphaned-temp-file fix above (commit 2575500, `_impact_merge_log`)
# got a mirrored regression test at `_impact_merge_evidence` (mvrepo, above — PR #310) but never one of
# its own. Proved missing by mutation before writing this: reintroducing the two-branch cleanup in
# `_impact_merge_log` (moving its `rm -f "$tmp"` back inside the `if` so a `mv` failure after a
# successful sort leaks `$tmp`) still passed the full suite. Same shape as mvrepo above, same stubbed
# `mv` on $PATH, driven through the PRODUCTION call path — just a log source instead of an evidence
# one. ---------------------------------------------------------------------------------------------
mlrepo="$(legacy_log_repo mv-fail-log-row)"
mlrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$mlrepo")"
run_in "$mlrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE PATH="$mv_stub_bin:$PATH" bash "$TOOL" rollup
check_status "a plain rollup survives a failed mv in auto-migrate's log merge (best-effort, never fatal)" 0 "$STATUS"
check_file "a failed mv leaves the legacy log source UNDELETED" "$mlrepo/.keel/impact-events.log"
check_nofile "a failed mv never writes the completion marker" "$mlrepo_store/origin"
check_absent "a failed mv leaves NO orphaned merge temp file behind" "$(ls "$mlrepo_store" 2>/dev/null)" "impact-events.log.keelmerge."
# the failure is not permanently stranded: with a working mv, the very next resolve completes it
run_in "$mlrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "the retry (real mv) succeeds" 0 "$STATUS"
check_file "the retry writes the completion marker" "$mlrepo_store/origin"
check_nofile "the retry removes the now-merged legacy source" "$mlrepo/.keel/impact-events.log"
check_contains "the retry carries the line that the mv failure had blocked" "$(cat "$mlrepo_store/impact-events.log")" "mv-fail-log-row"

# --- v0.8.0 delta audit F-16: the temp-file+`mv` shape all three merge helpers use gives TARGET the
# TEMP file's mode, not the mode TARGET already had — `mv` inside the same filesystem is a rename, and
# a rename keeps the DESTINATION inode's old permissions only when there's no destination yet; when one
# already exists, `mv -f` still replaces its CONTENT via the source inode, and that source (the temp
# file) was created under the ambient umask, same as any other redirect. Reproduced live before this
# fix: a store log at 600, re-merged via `_impact_merge_log`, came back at 644. Driven through the
# PRODUCTION call path — an explicit `migrate` re-run against an EXISTING store target, the same shape
# as the wrepo second-legacy-ledger scenario above — with the ambient umask DELIBERATELY DIFFERENT
# between the two merges (022 for the first, 000 for the second): a mode test that holds the umask
# fixed proves less than it looks (the same trap F-17 above is about), so this varies it rather than
# assume one value generalizes. -----------------------------------------------------------------------
# Portable octal-mode probe for this assertion only (mirrors keel-impact.sh's own _impact_file_mode
# probe — not sourced from the tool itself, which dispatches a command on load rather than staying
# inert as a library).
_test_stat_fmt=c
stat -c '%a' "$TOOL" >/dev/null 2>&1 || _test_stat_fmt=f
_test_file_mode() {
  case "$_test_stat_fmt" in
    c) stat -c '%a' "$1" 2>/dev/null ;;
    f) stat -f '%Lp' "$1" 2>/dev/null ;;
  esac
}
mmrepo="$(legacy_log_repo mode-first-row)"
mmrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$mmrepo")"
run bash -c 'umask 022; exec env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$1" migrate "$2"' _ "$TOOL" "$mmrepo"
check_status "setup: first migrate (umask 022) creates the store log" 0 "$STATUS"
check_file "setup: the store log exists" "$mmrepo_store/impact-events.log"
first_mode="$(_test_file_mode "$mmrepo_store/impact-events.log")"
check_contains "a first-ever create keeps ordinary umask behaviour (022 -> 644), not a hard-coded mode" "$first_mode" "644"
chmod 600 "$mmrepo_store/impact-events.log"
mkdir -p "$mmrepo/.keel"
printf '2026-06-02T00:00:00Z\tguard\tsecret-guard\t%s\t%s\n' "mode-second-row" "$mmrepo" > "$mmrepo/.keel/impact-events.log"
run bash -c 'umask 000; exec env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$1" migrate "$2"' _ "$TOOL" "$mmrepo"
check_status "the second migrate (umask 000, deliberately different) succeeds" 0 "$STATUS"
check_contains "the second migrate still carries the first row" "$(cat "$mmrepo_store/impact-events.log")" "mode-first-row"
check_contains "the second migrate carries the new row too" "$(cat "$mmrepo_store/impact-events.log")" "mode-second-row"
second_mode="$(_test_file_mode "$mmrepo_store/impact-events.log")"
check_contains "the pre-existing target's mode SURVIVES the merge — 600, not umask-000's 666" "$second_mode" "600"

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
arepo="$(legacy_log_repo blocked)"
arepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$arepo")"
run_in "$arepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "a plain rollup on an all-untracked legacy repo auto-migrates and succeeds" 0 "$STATUS"
check_dir "auto-migrate created the store entry" "$arepo_store"
check_contains "auto-migrate carried the legacy log into the store" "$(cat "$arepo_store/impact-events.log" 2>/dev/null)" "secret-guard"
check_nofile "auto-migrate removed the legacy in-tree log" "$arepo/.keel/impact-events.log"

# --- v0.8.0 delta audit F-05: a failed `rm` on an already-merged legacy LOG must not double it on
# retry. _impact_auto_migrate's log sweep used to be a bare `cat >>` (append, not merge): if the
# append durably landed in the store but the source's own `rm` then failed (a read-only project dir,
# an immutable file), `ok` went to 0, the completion marker stayed unwritten, and the VERY NEXT
# resolve re-appended the SAME lines again — and again on every retry after that, once per call, for
# as long as the `rm` kept failing. Root can write through any permission bits (a read-only .keel/
# dir wouldn't block root's own rm), so this only tests under a non-root reader — same guard this
# project's other chmod-based tests already use. Reproduce with a read-only .keel/ dir: the source
# file stays readable (the dir keeps r-x) but `rm -f` on a file inside it fails (the dir lacks w) —
# verified live before writing this test. -----------------------------------------------------------
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  drepo="$(legacy_log_repo doubling-check)"
  drepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$drepo")"
  chmod 555 "$drepo/.keel"
  run_in "$drepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  chmod 755 "$drepo/.keel"
  check_status "a plain rollup survives a failed auto-migrate rm (best-effort, never fatal)" 0 "$STATUS"
  check_file "the legacy source survives the failed rm (still readable, still there)" "$drepo/.keel/impact-events.log"
  check_nofile "a failed rm never writes the completion marker" "$drepo_store/origin"
  first_count="$(grep -c doubling-check "$drepo_store/impact-events.log" 2>/dev/null || true)"
  check_contains "the first sweep's merge already landed the row durably, exactly once" "${first_count:-0}" "1"
  # the source is writable again: the very next resolve retries the sweep on the SAME un-removed line
  run_in "$drepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
  check_status "the retry succeeds" 0 "$STATUS"
  check_file "the retry writes the completion marker" "$drepo_store/origin"
  check_nofile "the retry removes the now-merged legacy source" "$drepo/.keel/impact-events.log"
  second_count="$(grep -c doubling-check "$drepo_store/impact-events.log" 2>/dev/null || true)"
  check_contains "the retry's re-merge does NOT double the row — still exactly one copy" "${second_count:-0}" "1"
fi

# --- `enable` must auto-migrate BEFORE it creates the store entry (the ordering invariant) --------
# impact_store_enable() unconditionally `mkdir -p`s the store, and _impact_auto_migrate's own
# idempotency guard is `[ -d "$store" ] && return 0`. So if `enable` ever ran without auto-migrate
# having gone first, that mkdir would permanently satisfy the guard and no AUTOMATIC path — `enable`,
# `add`, `event`, `rollup` — would ever sweep the legacy in-tree marker in again: an adopter's pre-keel
# history left behind silently, with the rest of this suite still green. (Recoverable by an explicit
# `migrate`, never automatically — see the note below the assertions; the harm is the missing signal.)
# The invariant is stated at keel-impact.sh's _impact_begin, near the top of that file (this batch
# removed the dispatch block it used to sit at); before this block nothing
# executed it, which is exactly why fix-queue BATCH 3 ordered this pin ahead of its reorder.
enrepo="$(legacy_log_repo carried-by-enable)"
enrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$enrepo")"
run_in "$enrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable .
check_status "enable on a legacy in-tree project succeeds" 0 "$STATUS"
check_dir "enable created the store entry" "$enrepo_store"
# dir #287: this is the project's genuinely FIRST enable — auto-migrate's side effect (creating the
# store to carry the legacy marker in) must not make the printed message claim it was already enabled,
# and skip the /keel-score onboarding line, for exactly the population upgrading from a pre-0.7.2 install.
check_contains "enable on a legacy in-tree project reports NEWLY enabled, not already" "$OUT" "impact tracking enabled"
check_absent "enable on a legacy in-tree project does not claim already-enabled" "$OUT" "already enabled"
check_contains "enable on a legacy in-tree project still prints the /keel-score onboarding line" "$OUT" "/keel-score"
check_contains "enable CARRIED the legacy log into the store, not stranded" \
  "$(cat "$enrepo_store/impact-events.log" 2>/dev/null)" "carried-by-enable"
check_nofile "enable removed the now-migrated legacy in-tree log" "$enrepo/.keel/impact-events.log"
# ...and the same pin with _IMPACT_BEGUN inherited from the caller's environment. _impact_begin tests
# that flag with `${_IMPACT_BEGUN:-}`, so before it was initialised at top level an ambient value made
# the whole function a no-op — `enable` then created the store WITHOUT auto-migrating first and left
# the marker behind, defeating this very invariant while the pin above stayed green because it runs in
# a clean environment. Found by an operator-run /code-review high; this is the accept direction under
# a hostile environment, which is the half a clean-env pin cannot see.
envrepo="$(legacy_log_repo carried-despite-env)"
envrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$envrepo")"
run_in "$envrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE \
  _IMPACT_BEGUN=1 bash "$TOOL" enable .
check_status "enable succeeds with _IMPACT_BEGUN set in the environment" 0 "$STATUS"
check_contains "an inherited _IMPACT_BEGUN does NOT suppress the carry" \
  "$(cat "$envrepo_store/impact-events.log" 2>/dev/null)" "carried-despite-env"
check_nofile "an inherited _IMPACT_BEGUN does NOT strand the legacy log" "$envrepo/.keel/impact-events.log"
# and the loss is not merely deferred: a later plain resolve hits the same already-enabled guard, so
# if the carry above had not happened no AUTOMATIC path would ever retry it. (An explicit `migrate`
# still would — reproduced — which is why the harm here is silence rather than data loss.)
run_in "$enrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" rollup
check_status "a rollup after enable still succeeds" 0 "$STATUS"
check_contains "the carried event is still the store's, after enable already ran" \
  "$(cat "$enrepo_store/impact-events.log" 2>/dev/null)" "carried-by-enable"

# --- `enable DIR` from elsewhere must carry the TARGET's legacy marker, not the caller's cwd's
# (dir #251 delta finding 5a) -------------------------------------------------------------------
# _impact_auto_migrate used to hardcode _impact_resolve_top ".", so `enable DIR` run from a DIFFERENT
# cwd inspected the CALLER's cwd instead of the target — the target's store then got mkdir'd empty,
# its own idempotency guard permanently blocked any later auto-migrate for it, and the legacy marker
# was stranded with no signal to the operator. install.sh's post-install output and
# docs/reference.md's tool table both steer an adopter with an EXISTING, pre-keel repo at exactly
# this form, which is exactly the shape most likely to carry a legacy marker.
dtrepo="$(legacy_log_repo carried-by-enable-dir)"
dtrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$dtrepo")"
elsewhere="$(new_repo)"
elsewhere_store="$KEEL_IMPACT_STORE/$(store_id_for "$elsewhere")"
run_in "$elsewhere" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" enable "$dtrepo"
check_status "enable DIR from elsewhere succeeds" 0 "$STATUS"
check_dir "enable DIR from elsewhere created the TARGET's store entry" "$dtrepo_store"
# dir #287: same wrong-message bug, the `enable DIR` variant.
check_contains "enable DIR from elsewhere reports NEWLY enabled, not already" "$OUT" "impact tracking enabled"
check_absent "enable DIR from elsewhere does not claim already-enabled" "$OUT" "already enabled"
check_contains "enable DIR from elsewhere CARRIED the target's legacy log into the store" \
  "$(cat "$dtrepo_store/impact-events.log" 2>/dev/null)" "carried-by-enable-dir"
check_nofile "enable DIR from elsewhere removed the target's legacy in-tree log" "$dtrepo/.keel/impact-events.log"
check_nodir "enable DIR from elsewhere did not create a store for the caller's own cwd" "$elsewhere_store"

# --- -h/--help/no-args are read-only: must NOT trigger auto-migrate (found live, delta audit A2a-1) ---
# _impact_auto_migrate used to run unconditionally at top-level for anything but `migrate` — so a plain
# `--help` on a legacy in-tree project silently migrated it (real files moved, .keel/ removed) before
# usage ever printed. Usage is read-only by contract; it must leave the project exactly as found.
hrepo="$(legacy_log_repo blocked)"
hrepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$hrepo")"
for flag in --help -h ""; do
  label="${flag:-bare no-arg}"
  run_in "$hrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" $flag
  check_status "$label usage succeeds on a legacy in-tree project" 0 "$STATUS"
  check_contains "$label still prints usage" "$OUT" "Usage:"
  check_nodir "$label does NOT create a store entry" "$hrepo_store"
  check_file "$label leaves the legacy log in place" "$hrepo/.keel/impact-events.log"
done

# an unrecognized command (a plausible alias, a typo, or a future verb neither list yet knows) is
# read-only too — it's about to exit 2 without touching project state, so it must not auto-migrate
# first either. Found live by the operator on PR #282: the guard above used to be a DENYLIST of exempt
# commands, which covered `-h`/`--help`/no-args by name but missed everything it hadn't named.
for cmd in bogus help --hepl --version; do
  run_in "$hrepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" "$cmd"
  check_status "unknown command '$cmd' exits 2" 2 "$STATUS"
  check_contains "unknown command '$cmd' reports itself" "$OUT" "unknown command $cmd"
  check_nodir "unknown command '$cmd' does NOT create a store entry" "$hrepo_store"
  check_file "unknown command '$cmd' leaves the legacy log in place" "$hrepo/.keel/impact-events.log"
done

# --- the same class one layer in: a verb that IS state-touching, invoked invalidly ----------------
# The two guards above sit at the dispatch, so they can only see the command WORD. But argument
# validation lives inside cmd_add/cmd_event, after the dispatch — so `add --guard` (a flag with no
# citation) and a bare `event` (no TYPE) both used to migrate the project's real files and only then
# exit 2 on a usage error. Verified live by the v0.7.1->v0.7.2 delta audit's verifier, on the fixed
# state of the two guards above. The fix is structural, not a third list: auto-migrate now runs from
# inside each command, at the point where it knows it will do its work. So this loop is not just the
# two reported cases: every row is a way one of these verbs refuses with the tool's OWN exit 2, which
# is precisely what the loop asserts below — the guard now covers them by construction rather than by
# enumeration. Deliberately not every possible non-zero exit: a flag given with no value at all
# (`add --gap`, `add --silent`, `add --asof`, `add --since`) dies on bash's `${2:?}` expansion with
# exit 1, not 2, so it is no row here — verified separately that those migrate nothing either, the
# expansion being inside the parse loop and so before _impact_begin.
irepo="$(legacy_log_repo blocked)"
irepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$irepo")"
# One fixture for the whole loop on purpose: since no case may migrate, the legacy marker surviving
# ALL of them is a stronger assertion than a fresh repo per case would be.
while IFS= read -r inv; do
  [ -n "$inv" ] || continue
  # shellcheck disable=SC2086  # deliberate: $inv is a whole invocation, word-split into arguments
  run_in "$irepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE bash "$TOOL" $inv
  check_status "rejected '$inv' exits 2" 2 "$STATUS"
  check_nodir "rejected '$inv' does NOT create a store entry" "$irepo_store"
  check_file "rejected '$inv' leaves the legacy log in place" "$irepo/.keel/impact-events.log"
done <<'INVALID'
add --guard
add --bogus-flag
add --asof not-a-date --guard c
add --since not-a-timestamp --guard c
add --silent not-an-int --guard c
event
event bogustype
INVALID

# `rollup --registry` belongs to the same class but is protected by a DIFFERENT mechanism, so it gets
# its own block rather than a row in the loop above: those seven are covered by "validation precedes
# _impact_begin INSIDE the command", whereas rollup_registry never calls _impact_begin at all — it
# sweeps other projects by explicit path and never reads the invoking repo's own store. Folding it into
# the loop would make a future regression here read as a usage-validation bug rather than the scope
# change it would actually be. Both directions are pinned: the sweep must leave the marker alone when
# it REFUSES, and equally when it genuinely RUNS (the case with no reported finding behind it, and so
# the one most likely to regress unnoticed).
run_in "$irepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE \
  bash "$TOOL" rollup --registry /no/such/registry
check_status "a refused registry sweep exits 2" 2 "$STATUS"
check_nodir "a refused registry sweep does NOT create a store entry" "$irepo_store"
check_file "a refused registry sweep leaves the legacy log in place" "$irepo/.keel/impact-events.log"

# `rollup --registryy` (one transposed character) is the FLAG layer of the same mutate-before-reject
# class (dir #251 delta finding 5b): an unrecognized rollup flag used to fall through to a bare
# `else` and run a plain rollup instead of reporting the typo — migrating the cwd's legacy marker
# along the way and saying nothing about the bad flag. The fix is an explicit `*)` arm in the rollup
# dispatch that rejects before any of rollup()/rollup_registry() ever runs, so — like the unrecognized-
# command case above, and unlike the loop above it — this never reaches _impact_begin at all.
run_in "$irepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE \
  bash "$TOOL" rollup --registryy /no/such/registry
check_status "an unknown rollup flag exits 2" 2 "$STATUS"
check_contains "the rejection names the bad flag" "$OUT" "--registryy"
check_nodir "an unknown rollup flag does NOT create a store entry" "$irepo_store"
check_file "an unknown rollup flag leaves the legacy log in place" "$irepo/.keel/impact-events.log"

sweepreg="$SANDBOX/INSTANCE-sweep.md"
{
  printf '## Projects\n\n| Name | Path | Tag |\n|------|------|-----|\n'
  printf '| other | `%s` | x |\n' "$(new_repo)"
} > "$sweepreg"
run_in "$irepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE \
  bash "$TOOL" rollup --registry "$sweepreg"
check_status "a real registry sweep succeeds from a legacy in-tree repo" 0 "$STATUS"
check_nodir "a real registry sweep does NOT migrate the INVOKING repo" "$irepo_store"
check_file "a real registry sweep leaves the invoking repo's legacy log in place" \
  "$irepo/.keel/impact-events.log"

# ...and the ACCEPT direction, which is what actually keeps the reorder honest: an assertion that a
# rejected run does NOT migrate passes just as happily on code where auto-migrate was deleted outright.
# `rollup` (above) and `enable` (below) already pin their own; these two pin the reordered verbs, whose
# _impact_begin call moved from the dispatch into the command body and could have been dropped there.
# `add` runs --no-ingest: without it, `add` would consume the migrated event out of the store log again
# (it is older than the 12h ingest cap, so it would be stale-skipped AND removed) and the assertion
# below would read an empty log and fail for a reason that has nothing to do with the migration.
varepo="$(legacy_log_repo valid-add-still-migrates)"
varepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$varepo")"
run_in "$varepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE \
  bash "$TOOL" add --guard "a real citation" --gap none --no-ingest
check_status "a VALID add succeeds on a legacy in-tree project" 0 "$STATUS"
check_contains "a VALID add still auto-migrates the legacy log into the store" \
  "$(cat "$varepo_store/impact-events.log" 2>/dev/null)" "valid-add-still-migrates"
check_nofile "a VALID add removed the legacy in-tree log" "$varepo/.keel/impact-events.log"

verepo="$(legacy_log_repo valid-event-still-migrates)"
verepo_store="$KEEL_IMPACT_STORE/$(store_id_for "$verepo")"
run_in "$verepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE \
  bash "$TOOL" event guard some-source some-detail
check_status "a VALID event succeeds on a legacy in-tree project" 0 "$STATUS"
check_contains "a VALID event still auto-migrates the legacy log into the store" \
  "$(cat "$verepo_store/impact-events.log" 2>/dev/null)" "valid-event-still-migrates"
check_contains "the VALID event's own line landed in the store log too" \
  "$(cat "$verepo_store/impact-events.log" 2>/dev/null)" "some-source"
check_nofile "a VALID event removed the legacy in-tree log" "$verepo/.keel/impact-events.log"

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
# The sed capture is a plain $(...) (always drains to EOF, no early exit) fed to match() via a
# here-string, not `sed ... | grep -q` — the same live-writer-vs-early-exit SIGPIPE shape dir #280
# fixed for printf/echo producers applies to any producer, sed included.
if grep -qE '_ledger_stats\(\) \{' "$TOOL" && match "$(sed -n '/^_ledger_stats() {/,/^}/p' "$TOOL")" -q '_ledger_parse'; then
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
