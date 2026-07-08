#!/usr/bin/env bash
# keel-impact — the deterministic half of the Keel impact score.
#
# The MODEL judges (see commands/keel-score.md); this script does only the arithmetic and bookkeeping the
# model should not do by hand: append one dated row to the ledger, and recompute a rolling trend so drift is
# visible without re-reading the whole file. Judgment stays in the prompt; counting stays here (mirrors how
# `doctor` audits structure while the model writes content).
#
# Usage:
#   keel-impact.sh add --score N --axes conv=..,retr=..,rework=..,guard=..,cmd=.. \
#                      --friction N --evidence "..." --gap "..."   append a scored row + print rollup
#   keel-impact.sh rollup                                          recompute + print the trend only
#   keel-impact.sh -h | --help
#
# The ledger file: KEEL_IMPACT_LEDGER wins, else docs/keel-impact.md under the repo root (the dir this
# script's parent lives in). The date is stamped from `date -u` so rows are ordered and reproducible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="${KEEL_IMPACT_LEDGER:-$REPO_ROOT/docs/keel-impact.md}"

usage() {
  cat <<'EOF'
keel-impact — append a scored session row to the impact ledger and print the rolling trend.

Usage:
  keel-impact.sh add --score N --axes conv=..,retr=..,rework=..,guard=..,cmd=.. \
                     --friction N --evidence "..." --gap "..."
  keel-impact.sh rollup
  keel-impact.sh -h | --help

  --score N       final 0-100 score (help - friction, clamped)
  --axes ...      five sub-scores: conv,retr,rework,guard,cmd (retr may be negative)
  --friction N    0-20 penalty already folded into --score (recorded for transparency)
  --evidence STR  one-line strongest citation
  --gap STR       one-line top demote/promote candidate (or "none")

Ledger file: $KEEL_IMPACT_LEDGER, else docs/keel-impact.md under the repo root.
EOF
}

# --- the table header, written once when the ledger is first created ------------------------------
LEDGER_HEADER='# Keel impact ledger

One row per scored session — the *quantified* form of the wrap-time promote/demote ritual
(`FRAMEWORK.md` → "retrieval miss = promote signal"). Rows are appended by `tools/keel-impact.sh`; the
scoring rubric and the honesty rules live in `commands/keel-score.md`. The number is only as good as the
`evidence` beside it — a row with a vague citation should be distrusted, not averaged in.

Axes (each 0-20 unless noted): **conv** convention adherence · **retr** retrieval hit − miss (may be
negative) · **rework** rework avoided · **guard** guardrails fired · **cmd** command leverage.
**fric** friction penalty already subtracted from **score**.

| date | score | conv | retr | rework | guard | cmd | fric | evidence | gap (demote/promote) |
|------|-------|------|------|--------|-------|-----|------|----------|----------------------|'

ensure_ledger() {
  if [ ! -f "$LEDGER" ]; then
    mkdir -p "$(dirname "$LEDGER")"
    printf '%s\n' "$LEDGER_HEADER" > "$LEDGER"
  fi
}

# --- rollup: read every data row, print count + mean + last-5 trend of the score column -----------
# A data row is a table line whose first cell is an ISO date (YYYY-MM-DD). We stay tolerant of the
# header/separator lines and of a hand-edited ledger by matching only well-formed date rows.
rollup() {
  ensure_ledger
  awk -F'|' '
    # cell 2 (after leading empty cell from the leading pipe) is the date; cell 3 is the score.
    # Explicit digit classes (not {n} intervals) so busybox awk matches this too.
    $2 ~ /^ *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] *$/ {
      n++
      sum += $3 + 0
      order[n] = $3 + 0
    }
    END {
      if (n == 0) { print "impact ledger: no scored sessions yet."; exit 0 }
      printf "impact ledger: %d session(s), mean score %.1f/100\n", n, sum / n
      # last up-to-5 scores, oldest→newest
      start = (n > 5 ? n - 4 : 1)
      line = "  recent: "
      for (i = start; i <= n; i++) line = line order[i] (i < n ? " → " : "")
      print line
    }
  ' "$LEDGER"
}

cmd_add() {
  local score="" axes="" friction="" evidence="" gap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --score)    score="${2:?}";    shift 2 ;;
      --axes)     axes="${2:?}";     shift 2 ;;
      --friction) friction="${2:?}"; shift 2 ;;
      --evidence) evidence="${2:?}"; shift 2 ;;
      --gap)      gap="${2:?}";      shift 2 ;;
      *) printf 'keel-impact: unknown flag %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [ -n "$score" ] || { printf 'keel-impact: --score is required\n' >&2; exit 2; }
  case "$score" in *[!0-9]*) printf 'keel-impact: --score must be an integer 0-100\n' >&2; exit 2 ;; esac
  [ "$score" -ge 0 ] && [ "$score" -le 100 ] || { printf 'keel-impact: --score out of range 0-100\n' >&2; exit 2; }

  # Parse the axes csv (conv,retr,rework,guard,cmd) into individual cells; blank → "-".
  local conv="-" retr="-" rework="-" guard="-" cmdl="-"
  local kv key val
  local IFS=,
  for kv in $axes; do
    key="${kv%%=*}"; val="${kv#*=}"
    case "$key" in
      conv)   conv="$val" ;;
      retr)   retr="$val" ;;
      rework) rework="$val" ;;
      guard)  guard="$val" ;;
      cmd)    cmdl="$val" ;;
    esac
  done
  unset IFS
  [ -n "$friction" ] || friction="-"

  # Sanitize free-text cells so a stray pipe/newline can't break the table.
  local ev="${evidence:-—}" gp="${gap:-—}"
  ev="${ev//|/\\|}"; ev="${ev//$'\n'/ }"
  gp="${gp//|/\\|}"; gp="${gp//$'\n'/ }"

  ensure_ledger
  local today; today="$(date -u +%Y-%m-%d)"
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$today" "$score" "$conv" "$retr" "$rework" "$guard" "$cmdl" "$friction" "$ev" "$gp" >> "$LEDGER"

  printf 'keel-impact: appended row (score %s/100) to %s\n' "$score" "$LEDGER"
  rollup
}

case "${1:-}" in
  add)            shift; cmd_add "$@" ;;
  rollup)         rollup ;;
  -h|--help|"")   usage ;;
  *) printf 'keel-impact: unknown command %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
