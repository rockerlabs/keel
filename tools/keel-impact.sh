#!/usr/bin/env bash
# keel-impact — the deterministic half of the Keel impact score.
#
# The honesty inversion: the MODEL does NOT pick a number. It reports counted, cited EVENTS (see
# commands/keel-score.md) — guardrail fires, rule fires, retrieval hits/misses, friction — and THIS SCRIPT
# derives the 0-100 score from them by a fixed formula. So the marketing number is a pure function of the
# honest evaluation and cannot be inflated by vibe. Judgment (which events happened, with what citation)
# stays in the prompt; the arithmetic stays here (same split as `doctor`: model writes, script counts).
#
# Score formula (all inputs are non-negative event counts):
#   HELP  = 4*hold + 3*guard + 2*fire + 1*hit  # hold highest: keel caught the AGENT bypassing a constraint
#   COST  = 2*miss + 2*friction                # retrieval miss = promote pressure; friction = demote pressure
#   score = (HELP+COST == 0) ? "—" : round(100 * HELP / (HELP+COST))
#   conf  = evidence count E = hold+guard+fire+hit+miss+friction  → none(0) / low(<3) / med(<6) / high(>=6)
# `hold` is guard's higher-value sibling: a routine guard blocks bad *content*; a hold is keel restraining
# the agent's own attempt to weaken/bypass a rule or guardrail — its highest function, so it scores above guard.
# `silent` (always-loaded rules that did NOT fire — demote candidates) is recorded but deliberately NOT
# folded into the score: the headline number leans only on counted help/cost, while silent stays an
# actionable side-signal. A session with no events scores "—" (nothing to measure), never a fake 0.
#
# Auditable counts (thread A): the model does not pass bare counts — it passes ONE cited event per flag, so
# a count is literally the number of citations (no citation → no count, mechanically). Each cited event is
# archived to a durable per-event evidence file, so a score is a checkable trail, not a number to trust.
#
# Usage:
#   keel-impact.sh add [--guard "cite"]... --fire "cite"... --hit "cite"... --miss "cite"... \
#                      --friction "cite"... [--silent N] --gap "..."   derive+append a row, print the rollup
#   keel-impact.sh rollup                             recompute + print the trend and aggregates only
#   keel-impact.sh -h | --help
#
# The ledger file: KEEL_IMPACT_LEDGER wins, else docs/keel-impact.md under the repo root. The per-event
# evidence file: KEEL_IMPACT_EVIDENCE wins, else .keel/evidence.md (marker) / docs/keel-impact-evidence.md.
# The date is stamped from `date -u` so rows are ordered and reproducible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ledger + event log both live in the tracked repo's .keel/ (the same per-repo marker the guardrail hooks
# use), so the loop is out-of-the-box per project with no env. Resolution: an explicit env override wins;
# else, if the repo has a .keel/ marker, use it; else fall back (the ledger to Keel's own dogfooding copy,
# the log to a CWD-relative path). $KEEL_IMPACT_LEDGER / $KEEL_IMPACT_LOG override either.
# Worktree fallback: the marker is an UNTRACKED dir, so a linked worktree's top never carries it — when
# the current top has no .keel/, try the main checkout's top (first `git worktree list` entry; equals the
# current top in a plain repo). The awk reads its whole input on purpose: no early exit, no SIGPIPE.
_keel_main_top() {  # the main checkout's top; empty if not a repo or the main entry is BARE (no working tree)
  # `|| true`: outside a repo git exits 128 and pipefail would trip set -e (porcelain emits `bare` only
  # for the main entry, which is always listed first)
  git -C "${1:-.}" worktree list --porcelain 2>/dev/null |
    awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true
}
_keel_top() {  # memoized: invariant within a run, and the resolvers below all call it at startup
  if [ -z "${_KEEL_TOP_CACHE+x}" ]; then
    local top main
    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    _KEEL_CLAIM_CACHE="$top"  # dir #74: the raw pre-fallback value — _claim_key()'s answer too
    if [ -n "$top" ] && [ ! -d "$top/.keel" ]; then
      main="$(_keel_main_top)"
      if [ -n "$main" ] && [ -d "$main/.keel" ]; then top="$main"; fi
    fi
    _KEEL_TOP_CACHE="$top"
  fi
  printf '%s' "$_KEEL_TOP_CACHE"
}
_claim_key() {  # dir #74: this producer's OWN worktree top, BEFORE _keel_top's main-checkout fallback —
                 # that fallback only decides where the shared log FILE lives, not who fired the event.
                 # Reuses _keel_top's own memoized raw value instead of a second git rev-parse subprocess.
  _keel_top > /dev/null
  printf '%s' "$_KEEL_CLAIM_CACHE"
}
_resolve_ledger() {
  if [ -n "${KEEL_IMPACT_LEDGER:-}" ]; then printf '%s' "$KEEL_IMPACT_LEDGER"; return; fi
  local top; top="$(_keel_top)"
  if [ -n "$top" ] && [ -d "$top/.keel" ]; then printf '%s' "$top/.keel/ledger.md"; return; fi
  printf '%s' "$REPO_ROOT/docs/keel-impact.md"
}
_resolve_log() {
  if [ -n "${KEEL_IMPACT_LOG:-}" ]; then printf '%s' "$KEEL_IMPACT_LOG"; return; fi
  local top; top="$(_keel_top)"
  if [ -n "$top" ] && [ -d "$top/.keel" ]; then printf '%s' "$top/.keel/impact-events.log"; return; fi
  printf '%s' ".keel/impact-events.log"
}
# The durable per-event evidence file — the auditable trail behind each ledger row. Same resolution shape as
# the ledger (it is trackable too, unlike the ephemeral event log): explicit env override, else the .keel/
# marker, else Keel's own dogfooding copy under docs/.
_resolve_evidence() {
  if [ -n "${KEEL_IMPACT_EVIDENCE:-}" ]; then printf '%s' "$KEEL_IMPACT_EVIDENCE"; return; fi
  local top; top="$(_keel_top)"
  if [ -n "$top" ] && [ -d "$top/.keel" ]; then printf '%s' "$top/.keel/evidence.md"; return; fi
  printf '%s' "$REPO_ROOT/docs/keel-impact-evidence.md"
}
LEDGER="$(_resolve_ledger)"
LOG="$(_resolve_log)"
EVIDENCE="$(_resolve_evidence)"
EVENT_TYPES="hold guard fire hit miss friction"

usage() {
  cat <<'EOF'
keel-impact — derive a session's impact score from counted, cited events and append it to the ledger.

Usage:
  keel-impact.sh add [--guard "cite"]... --fire "cite"... --hit "cite"... --miss "cite"... \
                     --friction "cite"... [--silent N] [--since ISO-TS] --gap "..."
  keel-impact.sh add ... --retro [--asof YYYY-MM-DD]   record a quarantined retrospective score (see below)
  keel-impact.sh event TYPE [source] [detail]   append one event to the log (for shell tools/hooks)
  keel-impact.sh enable [dir]                    opt a repo into tracking (create .keel/ marker + gitignore)
  keel-impact.sh rollup                          this repo's live trend + cumulative signals
  keel-impact.sh rollup --retro                  only the quarantined retrospective scores
  keel-impact.sh rollup --registry FILE          cross-project sweep of an INSTANCE.md Projects table
  keel-impact.sh -h | --help

`enable` turns a repo on: it creates the .keel/ marker the guardrail hooks look for. Once enabled, a
guardrail fire in that repo records an event with no env needed; `add` auto-ingests any logged events and
folds them into the counts — so objective events (e.g. a secret-guard block) reach the score
deterministically, at zero token cost, without the model counting them. $KEEL_IMPACT_LOG overrides the
default log path (.keel/impact-events.log); pass --no-ingest to skip ingestion. TYPE ∈ hold guard fire hit miss friction.

Auto-ingest only counts events younger than $KEEL_INGEST_MAX_AGE_HOURS hours (default 12) — an event a
session left unconsumed (no `add` ran) is stale past that: skipped from the counts, archived to the
evidence trail with a note instead of a citation, and never re-surfaced. Every counted/skipped event prints
to stdout (`ingested: ...` / `stale-skipped: ...`) so a false-fire guard DENY can be caught and re-cited
honestly (see commands/keel-score.md). --since ISO-TS overrides the cutoff explicitly.

Cited events (REPEAT a flag once per event; the count is the number of citations, never a bare integer — no
citation, no count). Each citation is archived to the evidence file so the score is a checkable trail:
  --hold "cite"      keel restrained the AGENT from weakening/bypassing a rule or guardrail (its highest function)
  --guard "cite"     guardrail blocked/caught bad content (usually auto-ingested; pass only for a log-missed fire)
  --fire "cite"      an always-loaded rule/convention was concretely applied (must pass the two-test fire bar in commands/keel-score.md)
  --hit "cite"       a needed fact was pre-loaded and used
  --miss "cite"      had to hunt for a fact that should have been always-loaded (promote pressure)
  --friction "cite"  a stale/noisy rule got in the way (demote pressure)
  --silent N         COUNT ONLY (no citation): always-loaded rules that did NOT fire (demote candidates; not scored)
  --gap S            one-line top demote/promote candidate (or "none")

The script derives score = round(100*HELP/(HELP+COST)), HELP=4*hold+3*guard+2*fire+hit, COST=2*miss+2*friction,
and a confidence tag from the total event count. No --score flag: the number is computed, never asserted.
The row's evidence cell is auto-filled with the strongest citation (hold > guard > fire > hit > miss > friction).

--retro records a retrospectively-scored PAST session (e.g. reconstructed from a chat transcript). It is
quarantined so it never inflates the live signal: it skips the live event log, its row is conf-tagged
`-retro` (and dropped one tier, since a retro estimate is weaker), and the live `rollup` excludes it —
`rollup --retro` shows only these. --asof YYYY-MM-DD backdates the row to the session's real date.

Ledger file: $KEEL_IMPACT_LEDGER, else docs/keel-impact.md. Evidence file: $KEEL_IMPACT_EVIDENCE, else
.keel/evidence.md (marker) / docs/keel-impact-evidence.md.
EOF
}

# --- the table header, written once when the ledger is first created ------------------------------
LEDGER_HEADER='# Keel impact ledger

One row per scored session. The score is **derived, not asserted**: `commands/keel-score.md` gathers counted,
cited events; `tools/keel-impact.sh` computes the 0-100 number from them by a fixed formula, so it is a pure
function of the evidence and cannot be inflated by vibe. This is the quantified form of the wrap-time
promote/demote ritual (`FRAMEWORK.md` → "retrieval miss = promote signal").

Columns: **score** = round(100·HELP/(HELP+COST)) where HELP=4·hold+3·guard+2·fire+hit, COST=2·miss+2·friction
(`—` = no events, nothing to measure). **conf** = evidence-count tier (none/low/med/high) — a score behind
few events is weaker; a `-retro` suffix marks a quarantined retrospective score. Event counts: **guard**
guardrail blocked bad content · **hold** keel restrained the agent from bypassing a rule (its highest
function; scores above guard) · **fire** rule applied · **hit** retrieval hit · **miss** retrieval miss
(promote pressure) · **fric** friction (demote pressure) · **silent** always-loaded rules that did not fire
(demote candidates; NOT folded into the score).

**guard** is collected deterministically: in a tracked repo (an enabled `.keel/` marker, or `$KEEL_IMPACT_LOG`)
the guardrail hooks (`secret-guard`, `pre-pr-gate`, `public-audit`) record each fire to a zero-token event
log that `add` auto-ingests — the objective signal never depends on the model counting it.

Each count equals the number of cited events behind it; the **evidence** cell shows only the single strongest
citation, and the full per-event trail (every event → its citation) lives in `evidence.md` next to this file.

| date | score | conf | guard | hold | fire | hit | miss | fric | silent | evidence | gap (demote/promote) |
|------|-------|------|-------|------|------|-----|------|------|--------|----------|----------------------|'

# --- the evidence file header, written once when it is first created ------------------------------
EVIDENCE_HEADER='# Keel impact — per-event evidence

The auditable trail behind each row in `ledger.md`. Every scored session appends one dated block listing
each counted event and the citation that backs it — so a score is a checkable record, not a number to
trust. A count in the ledger equals the number of citations here: no citation, no count. Guard citations
are captured from the guardrail hooks (`source | detail`); the rest are supplied at score time.'

ensure_ledger() {
  if [ ! -f "$LEDGER" ]; then
    mkdir -p "$(dirname "$LEDGER")"
    printf '%s\n' "$LEDGER_HEADER" > "$LEDGER"
  fi
}

ensure_evidence() {
  if [ ! -f "$EVIDENCE" ]; then
    mkdir -p "$(dirname "$EVIDENCE")"
    printf '%s\n' "$EVIDENCE_HEADER" > "$EVIDENCE"
  fi
}

# require a non-negative integer; empty defaults to 0
require_count() {
  local name="$1" val="$2"
  case "$val" in
    "" ) printf '0'; return ;;
    *[!0-9]* ) printf 'keel-impact: --%s must be a non-negative integer\n' "$name" >&2; exit 2 ;;
    * ) printf '%s' "$val" ;;
  esac
}

# is $1 one of the recognized event types?
is_event_type() {
  case " $EVENT_TYPES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# is $1 a well-formed ISO-UTC timestamp (YYYY-MM-DDTHH:MM:SSZ)? Shared by --since's validation and the
# per-event staleness check (backlog #59) so the shape is defined once, not copy-pasted at both call sites.
_is_iso_ts() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
    *) return 1 ;;
  esac
}

# Portable epoch(seconds)->ISO-UTC, for the auto-ingest age-cap cutoff (backlog #59). Same portability
# problem branch-cleanup.sh's epoch_mtime solves for mtimes; here the direction is reversed (epoch -> ISO,
# not file -> epoch), so it's a fallback chain of `date` invocations rather than one `stat` format. Three
# tiers, first one that succeeds wins: BSD/macOS `-r SECONDS`, GNU `-d @SECONDS`, busybox `-D %s -d SECONDS`
# (TO VERIFY on the alpine CI leg — some busybox builds accept GNU's `@` form directly, in which case this
# third branch never fires there). All three failing means an unrecognized `date` implementation; the
# caller fails OPEN rather than crash or silently drop events.
_epoch_to_iso() {
  local epoch="$1" out
  out="$(date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" && { printf '%s' "$out"; return 0; }
  out="$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" && { printf '%s' "$out"; return 0; }
  out="$(date -u -D '%s' -d "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" && { printf '%s' "$out"; return 0; }
  return 1
}

# Flatten a value to a single line (strip tabs + newlines). The "one event = one line" invariant is
# load-bearing for both the TSV event log and the evidence trail, so both sanitize through this one place.
_flatten() { local s="${1//$'\t'/ }"; printf '%s' "${s//$'\n'/ }"; }

# A citation flag needs a non-empty value (no citation → no count). Reject empty/missing with the tool's own
# clean exit 2, not bash's cryptic `${2:?}` abort (exit 1). $2 is the flag name, for the message.
_need_cite() { [ -n "$1" ] || { printf 'keel-impact: %s needs a non-empty citation\n' "$2" >&2; exit 2; }; }

# event TYPE [source] [detail] — append one deterministic event to the log. Producers (secret-guard et al.)
# can also append the TSV line directly; this subcommand is the friendly, validated entry point.
cmd_event() {
  local type="${1:-}" source="${2:-}" detail="${3:-}" key
  [ -n "$type" ] || { printf 'keel-impact: event needs a TYPE (%s)\n' "$EVENT_TYPES" >&2; exit 2 ; }
  is_event_type "$type" || { printf 'keel-impact: unknown event type %s (want: %s)\n' "$type" "$EVENT_TYPES" >&2; exit 2 ; }
  # strip tabs/newlines so one event is always exactly one well-formed TSV line
  source="$(_flatten "$source")"; detail="$(_flatten "$detail")"
  key="$(_claim_key)"
  mkdir -p "$(dirname "$LOG")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$type" "$source" "$detail" "$key" >> "$LOG"
  printf 'keel-impact: recorded %s event to %s\n' "$type" "$LOG"
}

# enable [dir] — opt a repo into impact tracking: create its .keel/ marker (which the guardrail hooks look
# for before recording a fire) and gitignore the ephemeral event log. Idempotent. Run once per project; the
# AI-session flow then works with no env: hooks write events into .keel/, `add` auto-ingests them. Only the
# event log is ignored — .keel/ledger.md (the durable score history) and .keel/evidence.md (the per-event
# audit trail) stay trackable, so `git add` them to keep a shareable, cross-clone record.
cmd_enable() {
  local dir="${1:-.}" top
  # always target the MAIN checkout's top: a marker created in a linked worktree would be ephemeral and
  # invisible to every other worktree (untracked dirs aren't shared); the .gitignore line IS tracked, so
  # it reaches the worktrees from the main checkout anyway
  top="$(_keel_main_top "$dir")"
  [ -n "$top" ] || top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"  # bare main: this worktree's top
  [ -n "$top" ] || top="$dir"                 # not a git repo yet: fall back to the dir as-is
  local already=0
  [ -d "$top/.keel" ] && already=1
  mkdir -p "$top/.keel"
  local gi="$top/.gitignore"
  if ! { [ -f "$gi" ] && grep -qxF '/.keel/impact-events.log' "$gi"; }; then
    # dir #85 (code audit, finding 5): a .gitignore whose last line has no trailing newline would
    # otherwise get our rule GLUED onto it — `node_modules` + `/.keel/impact-events.log` becomes the
    # single pattern `node_modules/.keel/impact-events.log`, silently breaking the adopter's existing
    # ignore AND ours. `tail -c1` is the portable "does it end in a newline" test (an empty read means
    # the file is empty or ended in one); the missing newline is written first, never in place of ours.
    if [ -s "$gi" ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ]; then printf '\n' >> "$gi"; fi
    printf '/.keel/impact-events.log\n' >> "$gi"
    printf 'keel-impact: gitignored /.keel/impact-events.log in %s\n' "$gi"
  fi
  if [ "$already" -eq 1 ]; then
    printf 'keel-impact: impact tracking already enabled for %s (marker: %s/.keel/)\n' "$top" "$top"
  else
    printf 'keel-impact: impact tracking enabled for %s (marker: %s/.keel/)\n' "$top" "$top"
    printf '  guardrail fires now record events; run /keel-score to score. Commit .keel/ledger.md and .keel/evidence.md to keep the history + audit trail.\n'
  fi
}

# --- rollup: score trend + the honest cumulative signals (guardrail fires, agent-holds, retrieval misses) --
# A data row is a table line whose first cell is an ISO date. Explicit digit classes (not {n} intervals)
# so busybox awk matches this too. A "—" score row still counts as a session but is skipped from the mean.
# mode: "live" (default) skips quarantined retro rows; "retro" shows only them (a conf cell tagged `-retro`).
rollup() {
  local mode="${1:-live}"
  ensure_ledger
  awk -F'|' -v mode="$mode" '
    $2 ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ {
      is_retro = ($4 ~ /retro/)                  # cols: date=2 score=3 conf=4 guard=5 hold=6 fire=7 hit=8 miss=9
      if (mode == "retro" && !is_retro) next
      if (mode != "retro" && is_retro) next
      sessions++
      guard += $5 + 0; hold += $6 + 0; miss += $9 + 0
      s = $3; gsub(/ /, "", s)
      if (s ~ /^[0-9]+$/) { n++; sum += s + 0; order[n] = s + 0 }
    }
    END {
      label = (mode == "retro" ? "retro impact ledger" : "impact ledger")
      if (sessions == 0) {
        if (mode == "retro") print "retro impact ledger: no retrospective sessions yet."
        else                 print "impact ledger: no scored sessions yet."
        exit 0
      }
      if (n > 0) printf "%s: %d session(s), mean score %.1f/100 over %d scored\n", label, sessions, sum / n, n
      else       printf "%s: %d session(s), no numeric scores yet (all inert)\n", label, sessions
      if (n > 0) {
        start = (n > 5 ? n - 4 : 1)
        line = "  recent: "
        for (i = start; i <= n; i++) line = line order[i] (i < n ? " → " : "")
        print line
      }
      # the honest cumulative signals, straight from counted events (not judged)
      printf "  cumulative: %d guardrail fire(s), %d agent-hold(s), %d retrieval miss(es) — the standing promote pressure\n", guard, hold, miss
    }
  ' "$LEDGER"
}

# Emit "sessions scored sum guard hold miss" for one ledger file (all zeros if absent/empty). The single
# source of the per-ledger tally, shared by the cross-project rollup. Quarantined retro rows are excluded —
# the cross-project view is the live usefulness signal.
_ledger_stats() {
  # cols: date=2 score=3 conf=4 guard=5 hold=6 fire=7 hit=8 miss=9 (keep in sync with LEDGER_HEADER + cmd_add's printf)
  awk -F'|' '
    $2 ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ {
      if ($4 ~ /retro/) next
      sess++; g += $5 + 0; ho += $6 + 0; m += $9 + 0
      s = $3; gsub(/ /, "", s)
      if (s ~ /^[0-9]+$/) { nsc++; sum += s + 0 }
    }
    END { printf "%d %d %d %d %d %d", sess+0, nsc+0, sum+0, g+0, ho+0, m+0 }
  ' "$1" 2>/dev/null
}

# rollup --registry FILE — sweep every project in an INSTANCE.md Projects table (same parser as doctor) and
# report each one's impact from its own .keel/ledger.md, plus a grand total. This is the cross-project
# "usefulness of Keel" view; it lives here, in the impact tool, NOT in doctor (which audits baseline only).
rollup_registry() {
  local reg="$1"
  [ -f "$reg" ] || { printf 'keel-impact: registry not found: %s\n' "$reg" >&2; exit 2; }
  printf 'Keel impact — cross-project rollup (%s)\n' "$reg"
  local t_sess=0 t_scored=0 t_sum=0 t_guard=0 t_hold=0 t_miss=0 shown=0 path ledger
  local _lead _col1 col_path _rest
  while IFS='|' read -r _lead _col1 col_path _rest; do
    path="$(printf '%s' "$col_path" | tr -d '`' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$path" in ""|Path|*"<"*) continue ;; esac          # header / blank / placeholder row
    path="${path/#\~/$HOME}"
    shown=$(( shown + 1 ))
    ledger="$path/.keel/ledger.md"
    if [ ! -f "$ledger" ]; then
      printf '  %-28s —  (tracking off or no sessions scored)\n' "$(basename "$path")"
      continue
    fi
    local sess scored sum g ho m
    read -r sess scored sum g ho m <<EOF
$(_ledger_stats "$ledger")
EOF
    t_sess=$(( t_sess + sess )); t_scored=$(( t_scored + scored )); t_sum=$(( t_sum + sum ))
    t_guard=$(( t_guard + g )); t_hold=$(( t_hold + ho )); t_miss=$(( t_miss + m ))
    if [ "$scored" -gt 0 ]; then
      awk -v n="$(basename "$path")" -v s="$sess" -v sc="$scored" -v su="$sum" -v g="$g" -v ho="$ho" \
        'BEGIN{ printf "  %-28s mean %.1f/100 over %d scored (%d session(s), %d guard fire(s), %d hold(s))\n", n, su/sc, sc, s, g, ho }'
    else
      printf '  %-28s —  (%d session(s), none scored yet)\n' "$(basename "$path")" "$sess"
    fi
  done < <(awk 'BEGIN{f=0} /^[[:space:]]*(```|~~~)/{f=!f;next} !f' "$reg" \
            | grep -E '^[[:space:]]*\|' | grep -vE '^[[:space:]]*\|[-:| ]+\|?[[:space:]]*$')
  printf '  %s\n' '----'
  if [ "$t_scored" -gt 0 ]; then
    awk -v p="$shown" -v s="$t_sess" -v sc="$t_scored" -v su="$t_sum" -v g="$t_guard" -v ho="$t_hold" -v m="$t_miss" \
      'BEGIN{ printf "  ALL: %d project(s), mean %.1f/100 over %d scored session(s); %d guard fire(s), %d hold(s), %d miss(es)\n", p, su/sc, sc, s, g, ho, m }'
  else
    printf '  ALL: %d project(s), no scored sessions yet\n' "$shown"
  fi
}

# Per-event citation accumulators. Counts are derived from the number of citations (thread A: no bare
# integer flags — a count is exactly how many cited events back it). Portable string accumulation, not
# arrays, so this stays safe under bash 3.2 / busybox (no empty-array-under-`set -u` pitfall).
_n_hold=0; _n_guard=0; _n_fire=0; _n_hit=0; _n_miss=0; _n_friction=0
_ev_hold=""; _ev_guard=""; _ev_fire=""; _ev_hit=""; _ev_miss=""; _ev_friction=""   # accumulated "- TYPE: cite\n" lines
_first_hold=""; _first_guard=""; _first_fire=""; _first_hit=""; _first_miss=""; _first_friction=""  # first raw cite per type

# add_cite TYPE CITATION — count one cited event of TYPE and stash its citation (newline/tab-flattened so one
# event stays exactly one evidence line). Explicit `if`, never a `test && assign` chain, to dodge the set -e trap.
add_cite() {
  local ty="$1" c; c="$(_flatten "$2")"
  case "$ty" in
    hold)     _n_hold=$(( _n_hold + 1 ));         _ev_hold="${_ev_hold}- hold: ${c}"$'\n'
              if [ -z "$_first_hold" ];     then _first_hold="$c";     fi ;;
    guard)    _n_guard=$(( _n_guard + 1 ));       _ev_guard="${_ev_guard}- guard: ${c}"$'\n'
              if [ -z "$_first_guard" ];    then _first_guard="$c";    fi ;;
    fire)     _n_fire=$(( _n_fire + 1 ));         _ev_fire="${_ev_fire}- fire: ${c}"$'\n'
              if [ -z "$_first_fire" ];     then _first_fire="$c";     fi ;;
    hit)      _n_hit=$(( _n_hit + 1 ));           _ev_hit="${_ev_hit}- hit: ${c}"$'\n'
              if [ -z "$_first_hit" ];      then _first_hit="$c";      fi ;;
    miss)     _n_miss=$(( _n_miss + 1 ));         _ev_miss="${_ev_miss}- miss: ${c}"$'\n'
              if [ -z "$_first_miss" ];     then _first_miss="$c";     fi ;;
    friction) _n_friction=$(( _n_friction + 1 )); _ev_friction="${_ev_friction}- friction: ${c}"$'\n'
              if [ -z "$_first_friction" ]; then _first_friction="$c"; fi ;;
  esac
}

cmd_add() {
  local silent="" gap="" ingest=1 retro=0 asof="" since=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --hold)      _need_cite "${2:-}" --hold;     add_cite hold     "$2"; shift 2 ;;
      --guard)     _need_cite "${2:-}" --guard;    add_cite guard    "$2"; shift 2 ;;
      --fire)      _need_cite "${2:-}" --fire;     add_cite fire     "$2"; shift 2 ;;
      --hit)       _need_cite "${2:-}" --hit;      add_cite hit      "$2"; shift 2 ;;
      --miss)      _need_cite "${2:-}" --miss;     add_cite miss     "$2"; shift 2 ;;
      --friction)  _need_cite "${2:-}" --friction; add_cite friction "$2"; shift 2 ;;
      --silent)    silent="${2:?}";                shift 2 ;;
      --gap)       gap="${2:?}";               shift 2 ;;
      --no-ingest) ingest=0;                   shift 1 ;;
      --retro)     retro=1;                    shift 1 ;;
      --asof)      asof="${2:?}";              shift 2 ;;
      --since)     since="${2:?}";              shift 2 ;;
      *) printf 'keel-impact: unknown flag %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done
  silent="$(require_count silent "$silent")"
  # Retro (thread C): a retrospectively-scored past session. Quarantined — it never touches the live event
  # log (force --no-ingest, since a past session's guard fires are not in this repo's log) and its row is
  # tagged so the live rollup excludes it. --asof backdates the row to the session's real date.
  if [ "$retro" -eq 1 ]; then ingest=0; fi
  if [ -n "$asof" ]; then
    case "$asof" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
      *) printf 'keel-impact: --asof must be a YYYY-MM-DD date\n' >&2; exit 2 ;;
    esac
  fi
  if [ -n "$since" ] && ! _is_iso_ts "$since"; then
    printf 'keel-impact: --since must be an ISO-UTC timestamp (YYYY-MM-DDTHH:MM:SSZ)\n' >&2; exit 2
  fi

  # --- auto-ingest deterministic events the shell layer recorded (zero-token, portable) -----------
  # Each logged event becomes a cited event too: its `source | detail` is the citation, so the objective
  # signal is auditable exactly like the model's. Consumed (log rewritten, dir #74) only after the row
  # lands, so a failed write never double-counts or loses events.
  #
  # dir #82: the rewrite below is SUBTRACTIVE — it re-reads the CURRENT log at rewrite time and writes
  # back current content minus exactly the CONSUMED lines (collected into $consumed_raws as the loop
  # below decides ingested/stale), not a snapshot of what looked like "everything else" at T0. The old
  # approach (`kept_lines`, accumulated during this loop from the T0 read) silently lost any line a
  # concurrent producer appended between the T0 read and the eventual `mv` — invisible to the T0
  # snapshot, so writing back "the survivors of what I saw" clobbered it. See the rewrite block's own
  # comment (search `dir #82` below) for why subtractive-not-snapshot closes that. Consequence here:
  # foreign-kept and unrecognized-type lines no longer need their own accumulator (kept_lines is gone)
  # — they were never going to be removed, so under a subtractive rewrite they simply survive by NOT
  # being in the consumed set, with no bookkeeping required.
  #
  # Age cap (backlog #59): a session that never calls `add` leaves its events unconsumed in the log, where
  # they'd otherwise mis-attribute to whichever session's row lands next. Anything strictly older than the
  # cutoff is stale: not counted, archived to the evidence trail with a note instead of a citation, and the
  # log is still rewritten (stale lines removed) so it never resurfaces on the next `add`. `--since` overrides the cutoff
  # explicitly. Malformed/empty timestamps are treated as stale too — false credit is the harm here, so err
  # toward NOT counting (the mirror of pre-pr-gate's err-toward-catching). If the portable epoch->ISO
  # conversion fails outright, fail OPEN: ingest everything uncapped (today's behavior) rather than crash or
  # silently drop events — the cap is a precision improvement, never a new way to lose data.
  # dir #74: a fresh event with a claim key that ≠ our own is a foreign session's, stamped into this
  # shared log by a different worktree — not ours to count. Never added to $consumed_raws (below) so
  # the subtractive rewrite leaves it in place for the session that DOES own it to ingest later; only a
  # foreign event past the age cap is unattributable either way, so it stays on dir #59's
  # stale-archive-and-REMOVE path regardless of key. A line whose type isn't in EVENT_TYPES
  # (pre-pr-gate.sh's own housekeeping lines — receipt-pass, receipt-deny, pipeline-drift) is never
  # ours to score either, and is likewise never added to $consumed_raws — it survives the rewrite by
  # construction, the same way a foreign-keyed line does, needing no dedicated accumulator either.
  local ingested=0 stale=0 kept=0 _ts _ty _src _det _key _raw _cite cutoff_iso="" stale_lines="" consumed_raws="" _awk_out
  local own_key=""
  local max_age_h="${KEEL_INGEST_MAX_AGE_HOURS:-12}"
  case "$max_age_h" in ''|*[!0-9]*) max_age_h=12 ;; esac
  if [ "$ingest" -eq 1 ] && [ -f "$LOG" ]; then
    own_key="$(_claim_key)"
    if [ -n "$since" ]; then
      cutoff_iso="$since"
    elif ! cutoff_iso="$(_epoch_to_iso "$(( $(date +%s) - max_age_h * 3600 ))")"; then
      printf 'keel-impact: could not convert the ingest age-cap cutoff on this date implementation — ingesting all pending events uncapped this run\n' >&2
    fi
    # \x1f (NOT tab) re-joins the fields first: bash `read` collapses an EMPTY field sitting between two tab
    # delimiters regardless of IFS (a genuinely reachable shape here — $_det can be empty on a 5-field
    # line), the same trap fixed elsewhere in pre-pr-gate.sh — awk doesn't have that bug, so it does the split.
    # Reading via `$(...)` (not `< <(awk ...)`) lets us check awk's own exit status: a bare process
    # substitution is invisible to both `set -e` and `pipefail`, so a mid-run read failure on this shared,
    # multi-worktree-written file (permission race, the file replaced, a concurrent rewrite) would
    # otherwise silently look like "nothing to ingest" instead of the read failure it actually was.
    # $0 (the untouched original line, appended as a 6th field) is what a KEPT line writes back —
    # never the 5 split fields reassembled — so a line with more than 5 real tab fields (pre-pr-gate.sh's
    # receipt-pass rows deliberately embed an extra one, see its own log_event/_claim_key comment) round-
    # trips byte-for-byte through a rewrite instead of being silently truncated to 5 fields.
    if _awk_out="$(awk -F'\t' -v SEP=$'\x1f' '{print $1 SEP $2 SEP $3 SEP $4 SEP $5 SEP $0}' "$LOG")"; then
      # `|| [ -n "$_ty" ]` processes a final line with no trailing newline (read returns non-zero at EOF but
      # still populates the vars) — otherwise that event would be dropped, then lost when the log is rewritten.
      while IFS=$'\x1f' read -r _ts _ty _src _det _key _raw || [ -n "$_ty" ]; do
        # never consumed — survives the subtractive rewrite by not being in $consumed_raws
        is_event_type "$_ty" || continue
        _cite="$_src"
        if [ -n "$_det" ]; then _cite="$_src | $_det"; fi
        if [ -n "$cutoff_iso" ] && { ! _is_iso_ts "$_ts" || [[ "$_ts" < "$cutoff_iso" ]]; }; then
          stale=$(( stale + 1 ))
          stale_lines="${stale_lines}- ${_ts}"$'\t'"${_ty}"$'\t'"${_src}"$'\t'"${_det}"$'\n'
          consumed_raws="${consumed_raws}${_raw}"$'\n'
          printf 'stale-skipped: %s %s %s\n' "$_ts" "$_ty" "$_cite"
          continue
        fi
        if [ -n "$_key" ] && [ "$_key" != "$own_key" ]; then
          kept=$(( kept + 1 ))
          printf 'foreign-kept: %s %s %s\n' "$_ts" "$_ty" "$_cite"
          continue
        fi
        add_cite "$_ty" "$_cite"
        ingested=$(( ingested + 1 ))
        consumed_raws="${consumed_raws}${_raw}"$'\n'
        printf 'ingested: %s %s %s\n' "$_ts" "$_ty" "$_cite"
      done <<< "$_awk_out"
    else
      printf 'keel-impact: could not read %s for ingest this run — leaving it untouched (nothing lost, nothing counted)\n' "$LOG" >&2
    fi
  fi

  # --- derive the score from the counted, cited events (computed, never asserted) -----------------
  local help cost denom score ev_count conf
  help=$(( 4 * _n_hold + 3 * _n_guard + 2 * _n_fire + _n_hit ))
  cost=$(( 2 * _n_miss + 2 * _n_friction ))
  denom=$(( help + cost ))
  if [ "$denom" -eq 0 ]; then
    score="—"
  else
    score=$(( (100 * help + denom / 2) / denom ))   # integer round-half-up
  fi
  ev_count=$(( _n_hold + _n_guard + _n_fire + _n_hit + _n_miss + _n_friction ))
  if   [ "$ev_count" -eq 0 ]; then conf="none"
  elif [ "$ev_count" -lt 3 ]; then conf="low"
  elif [ "$ev_count" -lt 6 ]; then conf="med"
  else                             conf="high"
  fi
  # A retro estimate is weaker than a live one: drop one confidence tier and tag it so the live rollup can
  # quarantine it (the `-retro` marker is what rollup's filter keys on).
  if [ "$retro" -eq 1 ]; then
    case "$conf" in
      high) conf="med" ;;
      med)  conf="low" ;;
    esac
    conf="${conf}-retro"
  fi

  # The row's evidence cell = the single strongest citation (hold > guard > fire > hit > miss > friction); the
  # full per-event trail goes to the evidence file. Sanitize free-text so a stray pipe/newline can't break the table.
  local raw_ev="" cand
  for cand in "$_first_hold" "$_first_guard" "$_first_fire" "$_first_hit" "$_first_miss" "$_first_friction"; do
    if [ -n "$cand" ]; then raw_ev="$cand"; break; fi
  done
  local ev="${raw_ev:-—}" gp="${gap:-—}"
  ev="${ev//|/\\|}"; ev="${ev//$'\n'/ }"
  gp="${gp//|/\\|}"; gp="${gp//$'\n'/ }"

  ensure_ledger
  local today; today="${asof:-$(date -u +%Y-%m-%d)}"
  # cols: date score conf guard hold fire hit miss fric silent evidence gap — this ordering is the source of
  # truth the awk readers (rollup, _ledger_stats) index by position; keep all three + LEDGER_HEADER in sync.
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$today" "$score" "$conf" "$_n_guard" "$_n_hold" "$_n_fire" "$_n_hit" "$_n_miss" "$_n_friction" "$silent" "$ev" "$gp" >> "$LEDGER"

  # Archive the per-event citations — the auditable trail. Only when there was something to cite; an inert
  # ("—") session leaves no block, mirroring "no evidence, nothing to record".
  if [ "$ev_count" -gt 0 ]; then
    ensure_evidence
    { printf '\n## %s — score %s/100 (conf %s)\n\n' "$today" "$score" "$conf"
      printf '%s' "${_ev_hold}${_ev_guard}${_ev_fire}${_ev_hit}${_ev_miss}${_ev_friction}"
    } >> "$EVIDENCE"
  fi

  # Stale ingest-cap skips get their own dated block — never silently dropped, and NOT mixed into the
  # scored evidence above (they earned no citation, so they must not read as one). Reuses $today (the
  # row's own date) rather than a fresh `date` call: they're always the same run, and this keeps the
  # stale note's date in sync with the row even when --asof backdates it.
  if [ "$stale" -gt 0 ]; then
    ensure_evidence
    { printf '\n## %s — stale, unattributed — skipped by the %sh ingest cap\n\n' "$today" "$max_age_h"
      # dir #85 (code audit, finding 6): '%s', never '%b'. $stale_lines carries third-party event text
      # (a source/detail field the session wrote), and _flatten only strips literal tab/newline BYTES —
      # a two-character `\c` or `\n` sequence survives it verbatim. Under '%b' those get INTERPRETED:
      # `\c` truncates the rest of the output outright, silently swallowing the remaining stale rows and
      # undermining the exact "no citation → no count" honesty this block exists to record. The row
      # separators are real newline bytes already built into the string, so '%s' needs no escapes.
      printf '%s' "$stale_lines"
      printf '(re-cite explicitly via flags if genuinely this session'"'"'s)\n'
    } >> "$EVIDENCE"
  fi

  # Safe now that the row and any evidence blocks are durably appended. Only fires when something
  # actually needs REMOVING (ingested or stale) — a kept/preserved-only run changes nothing the file
  # doesn't already contain, so skipping the rewrite there is a pure win: one less write, and one less
  # window for a concurrent producer's append to land inside.
  #
  # dir #82: SUBTRACTIVE, not a snapshot write-back. The read-decide loop above ran against a
  # SNAPSHOT of $LOG taken at the top of this function (T0) — between then and now, a concurrent
  # producer (a guardrail hook in another session on this repo) may have appended a fresh event via
  # plain `>>`. The old approach wrote back `kept_lines` — the T0 snapshot's survivors — which is
  # blind to anything appended after T0: a `mv` over the CURRENT file would silently discard that
  # fresh append along with the intentionally-removed ingested/stale lines. Fix: re-read the log FRESH
  # right here, and remove ONLY the specific lines this run actually consumed ($consumed_raws, one
  # raw line per ingested or stale event, collected in the loop above) — a per-line COUNT map (not a
  # blanket "any line matching a consumed line's text"), so N byte-identical consumed lines remove
  # exactly N occurrences, never more: a fresh, unrelated 3rd copy appended after T0 (never seen by
  # this run, so never in $consumed_raws) is not in the count and survives. Consumed lines are fed to
  # awk through a FILE (`getline < consumed`), not `-v` — `-v` mangles embedded backslashes/newlines
  # and has command-line length limits a busy log could hit; a file has neither problem.
  #
  # This narrows the race window from the WHOLE ingest loop (T0 read through this mv — can span
  # however long citation-matching/age-cap logic takes) down to just the fresh-read-here through mv
  # gap, microseconds wide. Accepted residuals, not fixed by this (found by this ticket's own
  # independent review pass): (a) an append landing inside THAT narrower gap can still be lost —
  # revisit only if ever actually felt, not speculatively; (b) TWO CONCURRENT `add` invocations
  # (any keys, not only the same one) racing their OWN fresh-read-then-mv against each other — dir
  # #74's claim keys prevent cross-session MISATTRIBUTION (session B never scores session A's
  # own-key events as its own), but they do NOT make this file's mutation safe under two independent
  # rewrites: if B's fresh read happens before A's mv lands, B's own subtraction is computed against
  # a log that still contains the lines A is about to remove; if B's mv then lands AFTER A's, it
  # resurrects those already-consumed lines (a later `add`, by anyone, re-ingests them as new —
  # genuine double-counting into a second ledger row, not just a scoring mixup). This is the
  # "dominant part of add-vs-add" the resolved design (BACKLOG.md dir #82) already flagged as
  # narrowed-not-closed by the subtractive approach alone; a real fix needs mutual exclusion around
  # the whole read-decide-rewrite sequence (the lockdir option the design explicitly deferred, for
  # the reasons given there) — out of scope for this ticket, revisit if ever actually felt.
  # Test-only injection point (tests/test_keel_impact.sh): when set, append its value verbatim as one
  # log line immediately before the rewrite's fresh read — simulating a concurrent producer's plain
  # `>>` append landing in the T0-read-to-mv window this ticket exists to protect. Appended literally,
  # never eval'd (house precedent: KEEL_INGEST_MAX_AGE_HOURS, KEEL_IMPACT_LOG — env knobs, not code).
  if [ -n "${KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE:-}" ]; then
    printf '%s\n' "$KEEL_IMPACT_TEST_INJECT_BEFORE_REWRITE" >> "$LOG"
  fi

  if [ "$ingested" -gt 0 ] || [ "$stale" -gt 0 ]; then
    # `if A && B && C` (not a bare statement): under `set -e`, a command that is not the LAST element
    # of an AND-OR list is exempt from triggering errexit (POSIX), so any bare step here failing
    # silently would let this run's ledger row (already appended above) claim events that are still
    # sitting, unremoved, in $LOG for the next `add` to double-count. Fail loud instead: on failure,
    # nothing was consumed, so say so and stop.
    local consumed_file="${LOG}.consumed.$$"
    if ! { printf '%s' "$consumed_raws" > "$consumed_file" &&
           awk -F'\t' -v consumed="$consumed_file" '
             BEGIN { while ((getline line < consumed) > 0) need[line]++; close(consumed) }
             { if (($0 in need) && need[$0] > 0) { need[$0]--; next } print }
           ' "$LOG" > "${LOG}.tmp.$$" &&
           mv "${LOG}.tmp.$$" "$LOG"; }; then
      rm -f "$consumed_file" "${LOG}.tmp.$$"
      printf 'keel-impact: failed to rewrite %s — this run'"'"'s ingested/stale-skipped events are still in it and will be reprocessed on the next add\n' "$LOG" >&2
      exit 1
    fi
    rm -f "$consumed_file"
  fi

  printf 'keel-impact: derived score %s/100 (conf %s) from %d event(s)' "$score" "$conf" "$ev_count"
  if [ "$ingested" -gt 0 ]; then printf ' (%d auto-ingested from %s)' "$ingested" "$LOG"; fi
  if [ "$stale" -gt 0 ]; then printf ' (%d stale-skipped)' "$stale"; fi
  if [ "$kept" -gt 0 ]; then printf ' (%d foreign-kept)' "$kept"; fi
  printf ' — HELP=%d COST=%d; appended to %s\n' "$help" "$cost" "$LEDGER"
  if [ "$retro" -eq 1 ]; then rollup retro; else rollup; fi
}

case "${1:-}" in
  add)            shift; cmd_add "$@" ;;
  event)          shift; cmd_event "$@" ;;
  enable)         shift; cmd_enable "$@" ;;
  rollup)
    shift
    if [ "${1:-}" = "--registry" ]; then
      rollup_registry "${2:?keel-impact: --registry needs an INSTANCE.md FILE}"
    elif [ "${1:-}" = "--retro" ]; then
      rollup retro
    else
      rollup
    fi ;;
  -h|--help|"")   usage ;;
  *) printf 'keel-impact: unknown command %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
