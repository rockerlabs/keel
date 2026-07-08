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
#   HELP  = 3*guard + 2*fire + 1*hit        # guard weighted highest: an objective block, not a judgement
#   COST  = 2*miss  + 2*friction            # retrieval miss = promote pressure; friction = demote pressure
#   score = (HELP+COST == 0) ? "—" : round(100 * HELP / (HELP+COST))
#   conf  = evidence count E = guard+fire+hit+miss+friction  → none(0) / low(<3) / med(<6) / high(>=6)
# `silent` (always-loaded rules that did NOT fire — demote candidates) is recorded but deliberately NOT
# folded into the score: the headline number leans only on counted help/cost, while silent stays an
# actionable side-signal. A session with no events scores "—" (nothing to measure), never a fake 0.
#
# Usage:
#   keel-impact.sh add --guard N --fire N --hit N --miss N --friction N [--silent N] \
#                      --evidence "..." --gap "..."   derive+append a row, print the rollup
#   keel-impact.sh rollup                             recompute + print the trend and aggregates only
#   keel-impact.sh -h | --help
#
# The ledger file: KEEL_IMPACT_LEDGER wins, else docs/keel-impact.md under the repo root. The date is
# stamped from `date -u` so rows are ordered and reproducible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="${KEEL_IMPACT_LEDGER:-$REPO_ROOT/docs/keel-impact.md}"

usage() {
  cat <<'EOF'
keel-impact — derive a session's impact score from counted, cited events and append it to the ledger.

Usage:
  keel-impact.sh add --guard N --fire N --hit N --miss N --friction N [--silent N] \
                     --evidence "..." --gap "..."
  keel-impact.sh rollup
  keel-impact.sh -h | --help

Event counts (non-negative integers; each MUST be backed by a citation you gathered per keel-score.md):
  --guard N     guardrail actually blocked/caught something (secret-guard, pre-pr-gate, public-audit)
  --fire N      an always-loaded rule/convention was concretely applied (cold session would not have)
  --hit N       a needed fact was pre-loaded and used
  --miss N      had to hunt for a fact that should have been always-loaded (promote pressure)
  --friction N  a stale/noisy rule got in the way (demote pressure)
  --silent N    always-loaded rules that did NOT fire this session (demote candidates; not scored)
  --evidence S  one-line strongest citation
  --gap S       one-line top demote/promote candidate (or "none")

The script derives score = round(100*HELP/(HELP+COST)), HELP=3*guard+2*fire+hit, COST=2*miss+2*friction,
and a confidence tag from the total event count. No --score flag: the number is computed, never asserted.

Ledger file: $KEEL_IMPACT_LEDGER, else docs/keel-impact.md under the repo root.
EOF
}

# --- the table header, written once when the ledger is first created ------------------------------
LEDGER_HEADER='# Keel impact ledger

One row per scored session. The score is **derived, not asserted**: `commands/keel-score.md` gathers counted,
cited events; `tools/keel-impact.sh` computes the 0-100 number from them by a fixed formula, so it is a pure
function of the evidence and cannot be inflated by vibe. This is the quantified form of the wrap-time
promote/demote ritual (`FRAMEWORK.md` → "retrieval miss = promote signal").

Columns: **score** = round(100·HELP/(HELP+COST)) where HELP=3·guard+2·fire+hit, COST=2·miss+2·friction
(`—` = no events, nothing to measure). **conf** = evidence-count tier (none/low/med/high) — a score behind
few events is weaker. Event counts: **guard** guardrail fired · **fire** rule applied · **hit** retrieval
hit · **miss** retrieval miss (promote pressure) · **fric** friction (demote pressure) · **silent**
always-loaded rules that did not fire (demote candidates; NOT folded into the score).

| date | score | conf | guard | fire | hit | miss | fric | silent | evidence | gap (demote/promote) |
|------|-------|------|-------|------|-----|------|------|--------|----------|----------------------|'

ensure_ledger() {
  if [ ! -f "$LEDGER" ]; then
    mkdir -p "$(dirname "$LEDGER")"
    printf '%s\n' "$LEDGER_HEADER" > "$LEDGER"
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

# --- rollup: score trend + the honest cumulative signals (guardrail fires, retrieval misses) ------
# A data row is a table line whose first cell is an ISO date. Explicit digit classes (not {n} intervals)
# so busybox awk matches this too. A "—" score row still counts as a session but is skipped from the mean.
rollup() {
  ensure_ledger
  awk -F'|' '
    $2 ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ {
      sessions++
      guard += $5 + 0; miss += $8 + 0            # cols: date=2 score=3 conf=4 guard=5 fire=6 hit=7 miss=8
      s = $3; gsub(/ /, "", s)
      if (s ~ /^[0-9]+$/) { n++; sum += s + 0; order[n] = s + 0 }
    }
    END {
      if (sessions == 0) { print "impact ledger: no scored sessions yet."; exit 0 }
      if (n > 0) printf "impact ledger: %d session(s), mean score %.1f/100 over %d scored\n", sessions, sum / n, n
      else       printf "impact ledger: %d session(s), no numeric scores yet (all inert)\n", sessions
      if (n > 0) {
        start = (n > 5 ? n - 4 : 1)
        line = "  recent: "
        for (i = start; i <= n; i++) line = line order[i] (i < n ? " → " : "")
        print line
      }
      # the honest cumulative signals, straight from counted events (not judged)
      printf "  cumulative: %d guardrail fire(s), %d retrieval miss(es) — the standing promote pressure\n", guard, miss
    }
  ' "$LEDGER"
}

cmd_add() {
  local guard="" fire="" hit="" miss="" friction="" silent="" evidence="" gap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --guard)    guard="${2:?}";    shift 2 ;;
      --fire)     fire="${2:?}";     shift 2 ;;
      --hit)      hit="${2:?}";      shift 2 ;;
      --miss)     miss="${2:?}";     shift 2 ;;
      --friction) friction="${2:?}"; shift 2 ;;
      --silent)   silent="${2:?}";   shift 2 ;;
      --evidence) evidence="${2:?}"; shift 2 ;;
      --gap)      gap="${2:?}";      shift 2 ;;
      *) printf 'keel-impact: unknown flag %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done

  guard="$(require_count guard "$guard")"
  fire="$(require_count fire "$fire")"
  hit="$(require_count hit "$hit")"
  miss="$(require_count miss "$miss")"
  friction="$(require_count friction "$friction")"
  silent="$(require_count silent "$silent")"

  # --- derive the score from the events (the whole point: computed, never asserted) ---------------
  local help cost denom score ev_count conf
  help=$(( 3 * guard + 2 * fire + hit ))
  cost=$(( 2 * miss + 2 * friction ))
  denom=$(( help + cost ))
  if [ "$denom" -eq 0 ]; then
    score="—"
  else
    score=$(( (100 * help + denom / 2) / denom ))   # integer round-half-up
  fi
  ev_count=$(( guard + fire + hit + miss + friction ))
  if   [ "$ev_count" -eq 0 ]; then conf="none"
  elif [ "$ev_count" -lt 3 ]; then conf="low"
  elif [ "$ev_count" -lt 6 ]; then conf="med"
  else                             conf="high"
  fi

  # Sanitize free-text cells so a stray pipe/newline can't break the table.
  local ev="${evidence:-—}" gp="${gap:-—}"
  ev="${ev//|/\\|}"; ev="${ev//$'\n'/ }"
  gp="${gp//|/\\|}"; gp="${gp//$'\n'/ }"

  ensure_ledger
  local today; today="$(date -u +%Y-%m-%d)"
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$today" "$score" "$conf" "$guard" "$fire" "$hit" "$miss" "$friction" "$silent" "$ev" "$gp" >> "$LEDGER"

  printf 'keel-impact: derived score %s/100 (conf %s) from %d event(s) — HELP=%d COST=%d; appended to %s\n' \
    "$score" "$conf" "$ev_count" "$help" "$cost" "$LEDGER"
  rollup
}

case "${1:-}" in
  add)            shift; cmd_add "$@" ;;
  rollup)         rollup ;;
  -h|--help|"")   usage ;;
  *) printf 'keel-impact: unknown command %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
