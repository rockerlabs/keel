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
# The ledger/evidence/log triple lives OUTSIDE this repo's working tree (dir #251): an external store,
# $KEEL_HOME/.keel/impact/<project-id>/, keyed by this repo's main-checkout physical path — never inside
# the repo itself. KEEL_IMPACT_LEDGER / KEEL_IMPACT_EVIDENCE / KEEL_IMPACT_LOG each override their own
# file outright; KEEL_IMPACT_STORE overrides the store root. See tools/lib/impact-store.sh.
# The date is stamped from `date -u` so rows are ordered and reproducible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/nonneg-int.sh
. "$SCRIPT_DIR/lib/nonneg-int.sh"
# shellcheck source=tools/lib/impact-store.sh
. "$SCRIPT_DIR/lib/impact-store.sh"

# dir #251 D4's automatic half: a project with a legacy in-tree .keel/ marker and no store entry yet
# gets migrated the moment this script next resolves for it — main checkout only, no worktree sweep
# (that is cmd_migrate's job), and ONLY when every legacy file present is untracked. A repo with even
# one TRACKED legacy file (social-media/affiliate-lab's shape) is left entirely alone: impact_ledger_path
# et al.'s own legacy fallback keeps it fully functional via its old in-tree files, and doctor.sh's
# W-KEEL-LEGACY names the explicit `migrate` path for the operator to run. Best-effort and silent by
# design (called with `|| true`): any failure here just leaves the legacy file in place for `enable`/
# `migrate` to handle properly later, never worth aborting a plain `add`/`rollup`/`event` over.
_impact_auto_migrate() {
  local top store f any=0 all_untracked=1
  top="$(_impact_resolve_top .)"
  [ -n "$top" ] && [ -d "$top/.keel" ] || return 0
  store="$(impact_store_dir "$top")"
  [ -d "$store" ] && return 0   # already enabled — nothing to auto-migrate
  for f in $IMPACT_LEGACY_NAMES; do
    [ -f "$top/.keel/$f" ] || continue
    any=1
    if git -C "$top" ls-files --error-unmatch ".keel/$f" >/dev/null 2>&1; then
      all_untracked=0
    elif [ ! -r "$top/.keel/$f" ]; then
      # Unreadable but untracked: can't safely merge (a source awk/cat can't open silently drops its
      # content rather than failing, so "merged successfully" could mean "merged NONE of it" — found
      # live by an operator-run max-depth review). Treat it like a tracked file: block auto-migrate
      # entirely for this repo rather than risk deleting the one copy of unreadable data.
      all_untracked=0
    fi
  done
  { [ "$any" -eq 1 ] && [ "$all_untracked" -eq 1 ]; } || return 0
  mkdir -p "$store" || return 0
  printf '%s\n' "$top" > "$store/origin"
  if [ -f "$top/.keel/ledger.md" ]; then
    _impact_merge_ledger "$store/ledger.md" "$top/.keel/ledger.md" && rm -f "$top/.keel/ledger.md"
  fi
  if [ -f "$top/.keel/evidence.md" ]; then
    _impact_merge_evidence "$store/evidence.md" "$top/.keel/evidence.md" && rm -f "$top/.keel/evidence.md"
  fi
  if [ -f "$top/.keel/impact-events.log" ]; then
    cat "$top/.keel/impact-events.log" >> "$store/impact-events.log" && rm -f "$top/.keel/impact-events.log"
  fi
  rmdir "$top/.keel" 2>/dev/null || true   # only succeeds once role-3/4 files are gone too — expected to no-op
}
# NOTE: _impact_auto_migrate calls _impact_merge_ledger/_impact_merge_evidence, defined further down
# next to ensure_ledger/_ledger_col_pos — so the actual call (and the LEDGER/LOG/EVIDENCE resolution
# that depends on its result) is deferred to the bottom of this file, after every function it needs
# exists. Search "EVENT_TYPES=" below.
EVENT_TYPES="hold guard fire hit miss friction"

usage() {
  cat <<'EOF'
keel-impact — derive a session's impact score from counted, cited events and append it to the ledger.

Usage:
  keel-impact.sh add [--guard "cite"]... --fire "cite"... --hit "cite"... --miss "cite"... \
                     --friction "cite"... [--silent N] [--since ISO-TS] --gap "..."
  keel-impact.sh add ... --retro [--asof YYYY-MM-DD]   record a quarantined retrospective score (see below)
  keel-impact.sh event TYPE [source] [detail]   append one event to the log (for shell tools/hooks)
  keel-impact.sh enable [dir]                    opt a repo into tracking (creates an external store entry)
  keel-impact.sh migrate [dir] [--dry-run]       sweep a legacy in-tree .keel/ marker into the store
  keel-impact.sh rollup                          this repo's live trend + cumulative signals
  keel-impact.sh rollup --retro                  only the quarantined retrospective scores
  keel-impact.sh rollup --registry FILE          cross-project sweep of an INSTANCE.md Projects table
  keel-impact.sh -h | --help

`enable` turns a repo on: it creates an entry in the external impact store (nothing is written inside
the repo's own working tree — dir #251). Once enabled, a guardrail fire in that repo records an event
with no env needed; `add` auto-ingests any logged events and folds them into the counts — so objective
events (e.g. a secret-guard block) reach the score deterministically, at zero token cost, without the
model counting them. $KEEL_IMPACT_LOG overrides the log path outright; pass --no-ingest to skip
ingestion. TYPE ∈ hold guard fire hit miss friction.

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

Ledger/evidence/log files live in an external store, $KEEL_HOME/.keel/impact/<project-id>/, never inside
this repo's own tree; $KEEL_IMPACT_LEDGER / $KEEL_IMPACT_EVIDENCE / $KEEL_IMPACT_LOG each override their
own file outright, $KEEL_IMPACT_STORE overrides the store root. `add`/`rollup` refuse on a repo that has
never been enabled (no store entry, no legacy marker either) — run `enable` first.
EOF
}

# --- the ledger's column list: the ONE ordered source of truth for the table's shape (dir #151) ----
# cmd_add's row-printf (the WRITER), _ledger_parse (the READER), and the table header below all derive
# their column positions/order from this single array instead of each hand-listing the same 12 columns.
# Position in the array is the invariant: table field N = array-index + 2 (field 1 is the empty cell
# before the table's leading "|"; array indices are 0-based, so "date" at index 0 is field 2, "guard"
# at index 3 is field 5, etc — the same numbering _ledger_parse's old header comment already documented).
_LEDGER_COLS=(date score conf guard hold fire hit miss fric silent evidence gap)

# table field number (1-based, counting the empty pre-leading-pipe cell as field 1) for column $1 —
# the single place that turns a column NAME into a table POSITION. Every reader/writer of ledger rows
# goes through this instead of hand-indexing.
_ledger_col_pos() {
  local name="$1" i
  for i in "${!_LEDGER_COLS[@]}"; do
    if [ "${_LEDGER_COLS[$i]}" = "$name" ]; then printf '%d' "$((i + 2))"; return 0; fi
  done
  return 1
}

# the two markdown table-header lines (column names + separator dashes), generated from _LEDGER_COLS
# so the header is never hand-typed independently of the array. "gap" is the one column whose header
# label differs from its bare name (spelling out what the free-text cell is for); every other column
# uses its own name as the label, so a second near-duplicate array isn't needed just for that one case.
_ledger_table_header() {
  local hdr="|" sep="|" col label dashes
  for col in "${_LEDGER_COLS[@]}"; do
    label="$col"; [ "$col" = "gap" ] && label="gap (demote/promote)"
    hdr="$hdr $label |"
    # cell width = label + its two surrounding spaces (" $label |"), so the separator's dash run
    # matches the header cell it sits under, not just the bare label length. tests/lib.sh's rep()
    # does the same printf+tr dash-repeat idiom, but it's a test-harness helper — tools/keel-impact.sh
    # is production code and shouldn't depend on tests/, so the one-line idiom stays inline here
    # rather than pulling a cross-layer dependency for it.
    dashes="$(printf '%*s' "$((${#label} + 2))" '' | tr ' ' '-')"
    sep="$sep$dashes|"
  done
  printf '%s\n%s' "$hdr" "$sep"
}

# --- the table header, written once when the ledger is first created ------------------------------
# The trailing table rows are NOT appended here: _ledger_table_header() forks a handful of subshells
# (one printf+tr pair per column) to build them, and this file's top level runs unconditionally on
# EVERY invocation (add, rollup, event, enable, ...) regardless of whether a ledger even needs
# creating. Building the full header (prose + table) is deferred to ensure_ledger, the one place that
# actually writes it — a brand-new file is the rare case, not the common one.
LEDGER_HEADER_PROSE='# Keel impact ledger

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

**guard** is collected deterministically: in a tracked repo (an enabled external store entry, or
`$KEEL_IMPACT_LOG`) the guardrail hooks (`secret-guard`, `pre-pr-gate`, `public-audit`) record each fire
to a zero-token event log that `add` auto-ingests — the objective signal never depends on the model
counting it.

Each count equals the number of cited events behind it; the **evidence** cell shows only the single strongest
citation, and the full per-event trail (every event → its citation) lives in `evidence.md` next to this file.
'

# --- the evidence file header, written once when it is first created ------------------------------
EVIDENCE_HEADER='# Keel impact — per-event evidence

The auditable trail behind each row in `ledger.md`. Every scored session appends one dated block listing
each counted event and the citation that backs it — so a score is a checkable record, not a number to
trust. A count in the ledger equals the number of citations here: no citation, no count. Guard citations
are captured from the guardrail hooks (`source | detail`); the rest are supplied at score time.'

ensure_ledger() {
  if [ ! -f "$LEDGER" ]; then
    mkdir -p "$(dirname "$LEDGER")"
    printf '%s\n%s\n' "$LEDGER_HEADER_PROSE" "$(_ledger_table_header)" > "$LEDGER"
  fi
}

ensure_evidence() {
  # $EVIDENCE is guaranteed non-empty by the time this runs — cmd_add (this function's only caller)
  # refuses at its own top, before any write, on an empty $EVIDENCE (a partial env override on a
  # never-enabled repo: found live by an operator-run max-depth review). No redundant check here.
  if [ ! -f "$EVIDENCE" ]; then
    mkdir -p "$(dirname "$EVIDENCE")"
    printf '%s\n' "$EVIDENCE_HEADER" > "$EVIDENCE"
  fi
}

# --- dir #251: merge helpers shared by cmd_migrate and _impact_auto_migrate -----------------------
# _impact_merge_ledger TARGET SRC... — merge TARGET's existing data rows (if any) plus each SRC
# ledger.md's data rows into TARGET (created with the standard header first if it doesn't exist yet):
# sorted by the date column, byte-identical duplicate rows dropped. A no-op when there is nothing to
# merge. `LEDGER="$target" ensure_ledger`: a bash variable-assignment prefix on a function call is
# scoped to that one call only (restores the script's own $LEDGER afterward) — reuses the real header
# writer instead of a second hand-copy of LEDGER_HEADER_PROSE/_ledger_table_header.
_impact_merge_ledger() {
  local target="$1"; shift
  local date_col; date_col="$(_ledger_col_pos date)" || return 1
  local inputs=()
  local s; for s in "$@"; do [ -f "$s" ] && inputs+=("$s"); done
  [ "${#inputs[@]}" -gt 0 ] || return 0
  LEDGER="$target" ensure_ledger
  local header_tmp rows_tmp
  header_tmp="$(mktemp)"; rows_tmp="$(mktemp)"
  awk -F'|' -v date_col="$date_col" '
    $date_col ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ { exit }
    { print }
  ' "$target" > "$header_tmp"
  awk -F'|' -v date_col="$date_col" '
    $date_col ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ { print }
  ' "$target" "${inputs[@]}" | LC_ALL=C sort -u | LC_ALL=C sort -t'|' -k"${date_col},${date_col}" -s > "$rows_tmp"
  # Capture the write's own exit status explicitly — a bare `cmd1 && cmd2` as this function's LAST
  # statement would otherwise report whatever the following `rm -f` cleanup returns (almost always 0),
  # silently masking a real write failure (disk-full, a transiently unwritable store dir, a concurrent-
  # process race) from every caller that gates a source-file deletion on this function's return status
  # (`_impact_merge_ledger ... && rm -f "$legacy_source"`) — found live by an operator-run max-depth
  # review: a masked failure here would delete the legacy ledger while never having durably written its
  # rows anywhere.
  local write_status
  cat "$header_tmp" "$rows_tmp" > "$target.keelmerge.$$" && mv -f "$target.keelmerge.$$" "$target"
  write_status=$?
  rm -f "$header_tmp" "$rows_tmp" "$target.keelmerge.$$"
  return "$write_status"
}

# _impact_merge_evidence TARGET SRC... — merge TARGET's existing blocks (if any) plus each SRC
# evidence.md's blocks (a block = a `## YYYY-MM-DD ...` line through the next such line or EOF, the
# shared EVIDENCE_HEADER text counting as one no-date block) into TARGET, sorted by block date,
# byte-identical duplicate blocks dropped (so the header, appearing verbatim in every source, survives
# as exactly one copy — its empty date key sorts first). A no-op when there is nothing to merge.
_impact_merge_evidence() {
  local target="$1"; shift
  local inputs=()
  [ -f "$target" ] && inputs+=("$target")
  local s; for s in "$@"; do [ -f "$s" ] && inputs+=("$s"); done
  [ "${#inputs[@]}" -gt 0 ] || return 0
  # Same-directory temp name, not a bare `mktemp` (dir #251 review — matches _impact_merge_ledger's own
  # discipline above): `$TMPDIR`/`/tmp` is not guaranteed to share a filesystem with $target's directory
  # (the external store, or a legacy in-tree path), and `mv` across filesystems degrades to copy-then-
  # unlink — no longer the single atomic rename() a same-filesystem `mv` gets for free.
  local tmp="$target.keelmerge.$$"
  awk '
    function flush_block() { if (block != "") { n++; blocks[n] = block; dates[n] = date } }
    FNR==1 { flush_block(); block=""; date="" }
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { flush_block(); block=$0 "\n"; date=substr($0,4,10); next }
    { block = block $0 "\n" }
    END {
      flush_block()
      for (i=2;i<=n;i++) {
        kd=dates[i]; kb=blocks[i]; j=i-1
        while (j>=1 && dates[j] > kd) { dates[j+1]=dates[j]; blocks[j+1]=blocks[j]; j-- }
        dates[j+1]=kd; blocks[j+1]=kb
      }
      seen_n=0
      for (i=1;i<=n;i++) {
        dup=0
        for (k=1;k<=seen_n;k++) if (seen[k]==blocks[i]) { dup=1; break }
        if (!dup) { seen_n++; seen[seen_n]=blocks[i]; printf "%s", blocks[i] }
      }
    }
  ' "${inputs[@]}" > "$tmp"
  mv -f "$tmp" "$target"
}

# require a non-negative integer; empty defaults to 0. Digit-shape AND magnitude checked via
# tools/lib/nonneg-int.sh's shared `_nonneg_int_valid` (dir #196/#242) — the old inline `*[!0-9]*`
# guard rejected non-digit input but accepted an arbitrarily long all-digit string, which could
# overflow the shell's native integer range in a later numeric comparison and silently defeat the
# bound it was meant to guard. A 10+ digit `--<flag>` value that used to pass now exits 2 here; that is
# the fix, not a regression.
require_count() {
  local name="$1" val="$2"
  case "$val" in
    "" ) printf '0'; return ;;
  esac
  if _nonneg_int_valid "$val"; then
    printf '%s' "$val"
  else
    printf 'keel-impact: --%s must be a non-negative integer\n' "$name" >&2
    exit 2
  fi
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
# can also append the TSV line directly; this subcommand is the friendly, validated entry point. A
# guardrail fire in a not-enabled repo simply records nothing (matches every other producer's own
# silent no-op) — never a hard error, since a hook's own behaviour must not change either way.
cmd_event() {
  local type="${1:-}" source="${2:-}" detail="${3:-}" key
  [ -n "$type" ] || { printf 'keel-impact: event needs a TYPE (%s)\n' "$EVENT_TYPES" >&2; exit 2 ; }
  is_event_type "$type" || { printf 'keel-impact: unknown event type %s (want: %s)\n' "$type" "$EVENT_TYPES" >&2; exit 2 ; }
  if [ -z "$LOG" ]; then
    printf 'keel-impact: impact tracking not enabled — %s event not recorded (run "keel-impact.sh enable")\n' "$type" >&2
    return 0
  fi
  # strip tabs/newlines so one event is always exactly one well-formed TSV line
  source="$(_flatten "$source")"; detail="$(_flatten "$detail")"
  key="$(impact_claim_key)"
  mkdir -p "$(dirname "$LOG")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$type" "$source" "$detail" "$key" >> "$LOG"
  printf 'keel-impact: recorded %s event to %s\n' "$type" "$LOG"
}

# enable [dir] — opt a repo into impact tracking: create its external store entry (dir #251 — NOTHING is
# written inside the project's own working tree anymore: no marker, no gitignore line). Idempotent. Run
# once per project; the AI-session flow then works with no env: guardrail hooks record events straight
# into the store, `add` auto-ingests them.
cmd_enable() {
  local dir="${1:-.}" top already=0
  top="$(_impact_resolve_top "$dir")"
  impact_enabled "$dir" && already=1
  # The store's own absolute path is an internal implementation detail (never inside the project's own
  # tree, never something an adopter browses directly) — deliberately NOT echoed here, unlike the old
  # in-tree marker message: that path was actionable ("here's the file to `git add`"), this one isn't.
  impact_store_enable "$dir" >/dev/null
  if [ "$already" -eq 1 ]; then
    printf 'keel-impact: impact tracking already enabled for %s\n' "$top"
  else
    printf 'keel-impact: impact tracking enabled for %s\n' "$top"
    printf '  guardrail fires now record events with no env needed; run /keel-score to score.\n'
  fi
}

# --- shared ledger parser: the ONE place that indexes the table's columns -------------------------
# dir #107: rollup and the cross-project _ledger_stats used to re-derive these column indices and
# regexes independently, against a "keep all three in sync" warning that used to sit at cmd_add's
# hand-typed printf, since replaced by dir #151's array-driven version below. Both now delegate here
# instead. dir #151: the field numbers this awk block reads are no longer
# hand-typed either — they're looked up from _LEDGER_COLS via _ledger_col_pos and passed in as -v
# variables, so awk's own `$date_col` etc. always tracks the array regardless of column reordering.
# A data row is a table line whose first cell is an ISO date. Explicit digit classes (not {n}
# intervals) so busybox awk matches this too. A "—" score row still counts as a session but is
# skipped from the mean. mode: "live" excludes quarantined retro rows (conf tagged `-retro`);
# "retro" shows only them.
#
# Emits ONE line: "sessions scored sum guard hold miss recent" — recent is a comma-joined list of the
# last up-to-5 numeric scores in ledger order ("-" if none), used only by rollup's trend line.
_ledger_parse() {
  local file="$1" mode="${2:-live}"
  # Fail loudly on a lookup miss (e.g. _LEDGER_COLS renamed a column this function still names by its
  # old string) rather than let an empty $*_col silently turn `$score_col` into awk's `$0` (the whole
  # record) — the same explicit-catch discipline cmd_add's `*)` case arm applies on the writer side.
  local date_col score_col conf_col guard_col hold_col miss_col
  local _col _pos
  for _col in date score conf guard hold miss; do
    _pos="$(_ledger_col_pos "$_col")" || {
      printf 'keel-impact: internal error — no table position for ledger column %s\n' "$_col" >&2
      exit 1
    }
    printf -v "${_col}_col" '%s' "$_pos"
  done
  awk -F'|' -v mode="$mode" -v date_col="$date_col" -v score_col="$score_col" -v conf_col="$conf_col" \
    -v guard_col="$guard_col" -v hold_col="$hold_col" -v miss_col="$miss_col" '
    $date_col ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ {
      is_retro = ($conf_col ~ /retro/)
      if (mode == "retro" && !is_retro) next
      if (mode != "retro" && is_retro) next
      sessions++
      guard += $guard_col + 0; hold += $hold_col + 0; miss += $miss_col + 0
      s = $score_col; gsub(/ /, "", s)
      if (s ~ /^[0-9]+$/) { n++; sum += s + 0; order[n] = s + 0 }
    }
    END {
      recent = ""
      if (n > 0) {
        start = (n > 5 ? n - 4 : 1)
        for (i = start; i <= n; i++) recent = recent (i > start ? "," : "") order[i]
      }
      printf "%d %d %d %d %d %d %s\n", sessions+0, n+0, sum+0, guard+0, hold+0, miss+0, (recent == "" ? "-" : recent)
    }
  ' "$file"
  # No stderr suppression: both callers already gate existence (rollup via ensure_ledger,
  # rollup_registry via its own `[ -f "$ledger" ]` before calling _ledger_stats) — an existing-but-
  # unreadable ledger should surface awk's error and this function's non-zero exit, not be silently
  # reported as "0 sessions" (a real regression this refactor introduced: rollup() used to run this
  # awk with no stderr redirect at all).
}

# dir #251 §3: the OLD fallback (a not-enabled repo's add/rollup silently reading/writing Keel's own
# docs/keel-impact.md) is gone — a hard, named refusal replaces it. $LEDGER empty means neither an
# explicit env override nor a store entry nor even a legacy in-tree marker resolved (impact_ledger_path's
# own fallback chain already covers the legacy case) — i.e. this project was genuinely never enabled.
_impact_require_enabled() {
  [ -n "$LEDGER" ] && return 0
  printf 'keel-impact: impact tracking is not enabled for %s — run keel-impact.sh enable\n' "$(_impact_resolve_top .)" >&2
  return 1
}

# --- rollup: score trend + the honest cumulative signals (guardrail fires, agent-holds, retrieval misses) --
rollup() {
  local mode="${1:-live}"
  _impact_require_enabled || return 2
  ensure_ledger
  # A heredoc always supplies a trailing newline, so `read <<EOF $(cmd) EOF` reads an empty line
  # and "succeeds" even when cmd failed and printed nothing — the command substitution's own exit
  # status is invisible to it. Capture into a variable instead: `parsed="$(cmd)" || ...` DOES carry
  # the real exit status, so a failed ledger read surfaces here instead of masquerading as 0 sessions.
  local parsed=""
  if ! parsed="$(_ledger_parse "$LEDGER" "$mode")"; then
    printf 'keel-impact: failed to read ledger: %s\n' "$LEDGER" >&2
    return 1
  fi
  local sessions n sum guard hold miss recent
  read -r sessions n sum guard hold miss recent <<<"$parsed"
  local label="impact ledger"; [ "$mode" = "retro" ] && label="retro impact ledger"
  if [ "$sessions" -eq 0 ]; then
    local what="scored"; [ "$mode" = "retro" ] && what="retrospective"
    printf '%s: no %s sessions yet.\n' "$label" "$what"
    return
  fi
  if [ "$n" -gt 0 ]; then
    awk -v label="$label" -v sessions="$sessions" -v sum="$sum" -v n="$n" \
      'BEGIN{ printf "%s: %d session(s), mean score %.1f/100 over %d scored\n", label, sessions, sum/n, n }'
    printf '  recent: %s\n' "$(printf '%s' "$recent" | sed 's/,/ → /g')"
  else
    printf '%s: %d session(s), no numeric scores yet (all inert)\n' "$label" "$sessions"
  fi
  # the honest cumulative signals, straight from counted events (not judged)
  printf '  cumulative: %d guardrail fire(s), %d agent-hold(s), %d retrieval miss(es) — the standing promote pressure\n' \
    "$guard" "$hold" "$miss"
}

# Emit "sessions scored sum guard hold miss" for one ledger file (all zeros if absent/empty). The single
# source of the per-ledger tally, shared by the cross-project rollup. Quarantined retro rows are excluded —
# the cross-project view is the live usefulness signal. Thin wrapper over _ledger_parse, dropping its
# trailing "recent" field that only rollup's trend line needs.
_ledger_stats() {
  _ledger_parse "$1" live | cut -d' ' -f1-6
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
    # Deliberately NOT impact_ledger_path (which honours $KEEL_IMPACT_LEDGER): an env override must
    # not leak across every project in this sweep and point them all at the SAME file — each row
    # reads its own $STORE/<id>/ledger.md, exactly as the old code read its own $path/.keel/ledger.md.
    # Legacy fallback (dir #251 review): a project D4 deliberately leaves on its TRACKED in-tree ledger
    # (the two real adopter repos this ticket is about) has no store copy at all — without this, the
    # sweep would report them as "tracking off", silently dropping the exact projects the ticket names.
    # `|| true` (dir #251 review, a side effect of impact_store_dir's own fail-closed fix above): this
    # sweep must keep going even for a row whose store path can't resolve (e.g. no store entry at all,
    # or — same root cause as elsewhere in this file — a stripped HOME) — the very next line's legacy
    # fallback, and the whole design of this loop (one broken row must not abort the rest, per the
    # unreadable-ledger comment below), already assume that.
    ledger="$(impact_store_dir "$path" || true)/ledger.md"
    [ -f "$ledger" ] || ledger="$path/.keel/ledger.md"
    if [ ! -f "$ledger" ]; then
      printf '  %-28s —  (tracking off or no sessions scored)\n' "$(basename "$path")"
      continue
    fi
    local sess scored sum g ho m stats=""
    # Same class of bug rollup() had (dir #107 review, round 2): a heredoc always supplies a
    # trailing newline, so `read <<EOF $(cmd) EOF` "succeeds" on an empty line even when cmd failed
    # and printed nothing. Capture into a variable instead so a genuinely unreadable ledger (exists,
    # but e.g. permission-denied) is reported honestly rather than silently counted as 0 sessions —
    # skip just this one project and keep sweeping the rest, since one broken ledger shouldn't abort
    # the whole cross-project report.
    if ! stats="$(_ledger_stats "$ledger")"; then
      printf '  %-28s !  (failed to read ledger — check permissions)\n' "$(basename "$path")"
      continue
    fi
    read -r sess scored sum g ho m <<<"$stats"
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
  _impact_require_enabled || exit 2
  # $EVIDENCE can resolve empty independently of $LEDGER (a partial env override — only
  # $KEEL_IMPACT_LEDGER set, not $KEEL_IMPACT_EVIDENCE — on a never-enabled repo), so
  # _impact_require_enabled's own $LEDGER-only check isn't sufficient here (rollup shares that check
  # and never touches $EVIDENCE, so broadening it there would wrongly refuse a legitimate rollup).
  # Caught HERE, before anything is written — not inside ensure_evidence, which only runs partway
  # through this function's OWN write sequence, after the ledger row is already appended (found live
  # by an operator-run max-depth review's delta pass: the earlier, narrower fix left `add` able to
  # half-complete — a scored row with no evidence block, breaking evidence.md's own stated invariant,
  # "a count in the ledger equals the number of citations here").
  [ -n "$EVIDENCE" ] || { printf 'keel-impact: no evidence path resolved (a partial env override?) — run keel-impact.sh enable\n' >&2; exit 2; }
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
  # Sanitized (dir #196 — see tools/lib/nonneg-int.sh): a non-numeric OR overflowing override falls
  # back to 12 rather than crashing the later arithmetic/date math.
  local max_age_h; max_age_h="$(sanitize_nonneg_int "${KEEL_INGEST_MAX_AGE_HOURS:-12}" 12)"
  if [ "$ingest" -eq 1 ] && [ -f "$LOG" ]; then
    own_key="$(impact_claim_key)"
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
    # receipt-pass rows deliberately embed an extra one, see its own log_event comment) round-trips
    # byte-for-byte through a rewrite instead of being silently truncated to 5 fields.
    if _awk_out="$(awk -F'\t' -v SEP=$'\x1f' '{print $1 SEP $2 SEP $3 SEP $4 SEP $5 SEP $0}' "$LOG")"; then
      # `|| [ -n "$_ty" ]` is belt-and-braces, not the thing that makes an unterminated final $LOG line work:
      # the awk pre-pass above always terminates every record it prints (awk's `print` appends a newline
      # regardless of the input line), and that output round-trips through `$(...)` (strips trailing
      # newlines) and back through `<<<` (appends exactly one) — so `read` here never actually hits EOF
      # mid-record on this path. The guard stays as a second line of defense in case that pre-pass ever
      # changes shape.
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
  # Row values, index-aligned with _LEDGER_COLS (dir #151): built from the array instead of a
  # hand-typed printf, so the writer can't silently drift from _ledger_parse's column order. The
  # format string depends only on the column COUNT (one "%s |" per column), not on any column's
  # identity, so it's built once here rather than inside the value-mapping loop below.
  local -a _row_vals=()
  local _col _fmt="|"
  for _col in "${_LEDGER_COLS[@]}"; do _fmt="$_fmt %s |"; done
  for _col in "${_LEDGER_COLS[@]}"; do
    case "$_col" in
      date)     _row_vals+=("$today") ;;
      score)    _row_vals+=("$score") ;;
      conf)     _row_vals+=("$conf") ;;
      guard)    _row_vals+=("$_n_guard") ;;
      hold)     _row_vals+=("$_n_hold") ;;
      fire)     _row_vals+=("$_n_fire") ;;
      hit)      _row_vals+=("$_n_hit") ;;
      miss)     _row_vals+=("$_n_miss") ;;
      fric)     _row_vals+=("$_n_friction") ;;
      silent)   _row_vals+=("$silent") ;;
      evidence) _row_vals+=("$ev") ;;
      gap)      _row_vals+=("$gp") ;;
      *) printf 'keel-impact: internal error — no value mapped for ledger column %s\n' "$_col" >&2; exit 1 ;;
    esac
  done
  printf "$_fmt\n" "${_row_vals[@]}" >> "$LEDGER"

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
  # rollup can now fail (a genuinely unreadable ledger — round-2 review fix above), but the row this
  # command exists to write is already appended and the success message above is already printed by
  # this point; rollup here is only a trailing trend display, and under `set -e` letting IT fail
  # would turn an already-successful `add` into a nonzero exit (found in review). `|| true` keeps
  # rollup's own stderr message visible (it prints one before returning 1) without masking the add's
  # own success.
  if [ "$retro" -eq 1 ]; then rollup retro || true; else rollup || true; fi
}

# migrate [dir] [--dry-run] — dir #251 D4's EXPLICIT half: sweep a legacy in-tree .keel/ marker — the
# main checkout AND every linked worktree (git worktree list --porcelain; this is what also resolves
# KB.82's rows stranded in a worktree's own .keel/) — into the external store. Untracked source files
# are moved (merged, dedup'd); a TRACKED source (social-media/affiliate-lab's shape) is never touched
# automatically — printed as three options instead, the operator's call. Idempotent: a second run finds
# nothing left to move. `--dry-run` prints the plan and writes nothing.
cmd_migrate() {
  local dir="." dry_run=0 a
  for a in "$@"; do
    case "$a" in
      --dry-run) dry_run=1 ;;
      *) dir="$a" ;;
    esac
  done
  local top; top="$(_impact_resolve_top "$dir")"
  [ -n "$top" ] && [ -d "$top" ] || { printf 'keel-impact: migrate: not a directory: %s\n' "$dir" >&2; exit 2; }
  local store; store="$(impact_store_dir "$top")"

  # --- collect: main checkout + every linked worktree ---------------------------------------------
  local dirs=("$top") wt_line wt
  while IFS= read -r wt_line; do
    case "$wt_line" in "worktree "*) wt="${wt_line#worktree }" ;; *) continue ;; esac
    [ "$wt" = "$top" ] && continue
    [ -d "$wt/.keel" ] && dirs+=("$wt")
  done < <(git -C "$top" worktree list --porcelain 2>/dev/null || true)

  local f name ledger_srcs=() evidence_srcs=() log_srcs=() tracked_left=()
  local any_untracked=0
  for name in $IMPACT_LEGACY_NAMES; do
    for f in "${dirs[@]}"; do
      [ -f "$f/.keel/$name" ] || continue
      if git -C "$f" ls-files --error-unmatch ".keel/$name" >/dev/null 2>&1; then
        tracked_left+=("$f/.keel/$name")
        continue
      fi
      # Unreadable but untracked: same reasoning as _impact_auto_migrate's own guard — a source awk/cat
      # can't open silently drops its content instead of failing loudly, so leave it untouched (never
      # merged, never removed) rather than risk losing the one copy of data nothing could actually read.
      if [ ! -r "$f/.keel/$name" ]; then
        tracked_left+=("$f/.keel/$name")
        continue
      fi
      any_untracked=1
      case "$name" in
        ledger.md) ledger_srcs+=("$f/.keel/$name") ;;
        evidence.md) evidence_srcs+=("$f/.keel/$name") ;;
        impact-events.log) log_srcs+=("$f/.keel/$name") ;;
      esac
    done
  done

  if [ "$any_untracked" -eq 0 ] && [ "${#tracked_left[@]}" -eq 0 ]; then
    printf 'keel-impact: migrate: nothing to move for %s (already migrated, or never enabled)\n' "$top"
    return 0
  fi

  if [ "$dry_run" -eq 1 ]; then
    printf 'keel-impact: migrate --dry-run for %s (store: %s)\n' "$top" "$store"
    [ "${#ledger_srcs[@]}" -gt 0 ] && printf '  would merge ledger.md from: %s\n' "${ledger_srcs[*]}"
    [ "${#evidence_srcs[@]}" -gt 0 ] && printf '  would merge evidence.md from: %s\n' "${evidence_srcs[*]}"
    [ "${#log_srcs[@]}" -gt 0 ] && printf '  would concatenate impact-events.log from: %s\n' "${log_srcs[*]}"
    [ "${#tracked_left[@]}" -gt 0 ] && printf '  would LEAVE (tracked): %s\n' "${tracked_left[*]}"
    return 0
  fi

  if [ "$any_untracked" -eq 1 ]; then
    mkdir -p "$store"
    printf '%s\n' "$top" > "$store/origin"
    if [ "${#ledger_srcs[@]}" -gt 0 ]; then
      _impact_merge_ledger "$store/ledger.md" "${ledger_srcs[@]}"
      rm -f "${ledger_srcs[@]}"
    fi
    if [ "${#evidence_srcs[@]}" -gt 0 ]; then
      _impact_merge_evidence "$store/evidence.md" "${evidence_srcs[@]}"
      rm -f "${evidence_srcs[@]}"
    fi
    if [ "${#log_srcs[@]}" -gt 0 ]; then
      # Same-directory temp name (dir #251 review, same reasoning as _impact_merge_evidence above): a
      # bare `mktemp` defaults into $TMPDIR, not necessarily $store's own filesystem.
      local log_tmp="$store/impact-events.log.keelmerge.$$"
      touch "$store/impact-events.log"
      LC_ALL=C sort -u "$store/impact-events.log" "${log_srcs[@]}" > "$log_tmp"
      mv -f "$log_tmp" "$store/impact-events.log"
      rm -f "${log_srcs[@]}"
    fi
    printf 'keel-impact: migrated into %s\n' "$store"
    for f in "${dirs[@]}"; do rmdir "$f/.keel" 2>/dev/null || true; done
  fi

  if [ "${#tracked_left[@]}" -gt 0 ]; then
    printf 'keel-impact: %d tracked legacy file(s) left in place (never moved automatically):\n' "${#tracked_left[@]}"
    printf '  %s\n' "${tracked_left[@]}"
    printf '  This project keeps working via these files until you choose one:\n'
    printf '    1. leave them (no action — the tracked history stays exactly where it is)\n'
    printf '    2. git rm --cached them, then commit, so future runs stop tracking them\n'
    printf '    3. rewrite history to remove them entirely (a separate, deliberate operation)\n'
  fi
}

# Deferred from just after sourcing tools/lib/impact-store.sh (search "EVENT_TYPES=" above): every
# function _impact_auto_migrate calls now exists, so resolve here, once, before dispatch.
#
# NEVER for `migrate` itself (dir #251 review finding): _impact_auto_migrate is keyed off the CWD's
# main checkout, unconditionally — but `migrate` has its own explicit `[dir]` argument and its own
# `--dry-run` contract ("prints the plan and writes nothing"). Running auto-migrate first would
# silently migrate the CWD's project (real files moved and removed) before cmd_migrate's own dry-run
# logic ever ran, then report "nothing to move" — turning a preview into the real thing. `migrate`
# resolves everything it needs itself; it never reads $LEDGER/$LOG/$EVIDENCE.
if [ "${1:-}" != "migrate" ]; then
  _impact_auto_migrate || true
  LEDGER="$(impact_ledger_path)"
  LOG="$(impact_log_path)"
  EVIDENCE="$(impact_evidence_path)"
fi

case "${1:-}" in
  add)            shift; cmd_add "$@" ;;
  event)          shift; cmd_event "$@" ;;
  enable)         shift; cmd_enable "$@" ;;
  migrate)        shift; cmd_migrate "$@" ;;
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
