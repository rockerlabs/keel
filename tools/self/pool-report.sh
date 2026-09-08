#!/usr/bin/env bash
# tools/self/pool-report.sh — keel-self-maintenance (dir #360): nothing measured the `→ pool`
# lane, so "deliberate debt" and "quietly abandoned" were indistinguishable from inside
# BACKLOG.md. Reports pool size, the oldest entry's age, the R-level split, and the count
# excluding structurally-parked tickets — the four figures dir #360 names as the cheap,
# uncontroversial half. There is no consumer-facing counterpart and install.sh never ships this
# file (BACKLOG.md is keel-self-maintenance content); adopter doctor.sh never reads BACKLOG.md.
#
# Structurally-parked, BY RULE not by ticket name (dir #360's own two named shapes — the three
# tickets at its 2026-09-03 baseline are an instance of this rule, not the rule itself):
#   - a heading block carrying a `⛔` (blocked) marker, or
#   - a heading block naming an explicit unblocking condition ("explicit gate", "gate = ...").
#
# The two-consecutive-minors growth trigger (dir #360's own point of the ticket): fires when
# the pool size has strictly grown across the last two RECORDED releases and again into this
# run — a single reading is not a trend, the doctrine's own snowball argument is about
# direction over time. History storage per dir #360's FORK RESOLVED (b), 2026-09-06: beside
# BACKLOG.md, untracked (KB-snapshot-backed the same way BACKLOG.md itself is) — never in the
# tracked tree, so no backlog state leaks into the public repo.
#
# Usage:
#   tools/self/pool-report.sh [--record RELEASE] [--history PATH] [BACKLOG_PATH]
#   tools/self/pool-report.sh -h | --help
#
# --record RELEASE appends this run's pool size to the history file tagged with RELEASE,
# unless a row for that release already exists (idempotent re-runs). Without --record, the
# report is computed and printed but nothing is written — safe to run any number of times.
#
# BACKLOG_PATH defaults to the MAIN checkout's BACKLOG.md, resolved the same way
# tools/self/doctor.sh's check 5 does (dir #135). The history file defaults to
# POOL-HISTORY.jsonl next to that BACKLOG.md (i.e. the main checkout root) — override with
# --history for tests or a non-standard layout.
#
# Always exits 0 (advisory only); a missing/unreadable BACKLOG.md is a silent skip, not an
# error, matching every other keel-self-maintenance check that reads this gitignored file.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$self_dir/../.." && pwd)"

# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"
# shellcheck source=tools/lib/backlog-blocks.sh
. "$self_dir/../lib/backlog-blocks.sh"

record_release=""
history_arg=""
backlog_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --record)
      [ $# -ge 2 ] || { echo "pool-report: --record needs a release value" >&2; exit 2; }
      record_release="$2"; shift 2 ;;
    --record=*) record_release="${1#*=}"; shift ;;
    --history)
      [ $# -ge 2 ] || { echo "pool-report: --history needs a path" >&2; exit 2; }
      history_arg="$2"; shift 2 ;;
    --history=*) history_arg="${1#*=}"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: pool-report.sh [--record RELEASE] [--history PATH] [BACKLOG_PATH]

Reports the `→ pool` lane's size, oldest entry's age, R-level split, and the count
excluding structurally-parked tickets (dir #360). With --record RELEASE, appends this
run's pool size to the untracked history file (default: POOL-HISTORY.jsonl beside
BACKLOG.md) tagged with that release, unless a row for it already exists, and reports
whether the two-consecutive-minors growth trigger fires against recorded history.
EOF
      exit 0 ;;
    -*)
      echo "pool-report: unknown flag: $1" >&2
      exit 2 ;;
    *)
      backlog_arg="$1"; shift ;;
  esac
done

if [ -n "$backlog_arg" ]; then
  backlog_file="$backlog_arg"
else
  backlog_root="$(backlog_root_for "$repo_root")"
  backlog_file="$backlog_root/BACKLOG.md"
fi

# v0.9.0 RC audit, final fix round: this guard must run BEFORE the `cd` below — `cd` into a
# nonexistent directory fails under `set -e` and aborts with exit 1 plus raw stderr, breaking
# this script's own header promise ("Always exits 0 ... missing/unreadable = silent skip"). A
# single guard here (rather than one copy per branch) covers both: the `backlog_arg` branch's
# `cd` hasn't run yet, and the `backlog_root_for` branch never `cd`s at all.
if [ ! -f "$backlog_file" ] || [ ! -r "$backlog_file" ]; then
  echo "pool-report: no readable BACKLOG.md at $backlog_file — skipped, not a failure"
  exit 0
fi

[ -n "$backlog_arg" ] && backlog_root="$(cd "$(dirname "$backlog_file")" && pwd)"
history_file="${history_arg:-$backlog_root/POOL-HISTORY.jsonl}"

today_epoch="$(date -u +%s)"

pool_size=0
parked_count=0
r1=0; r2=0; r3=0; runmarked=0
oldest_age=-1
oldest_id="unlabeled"

while IFS=$'\t' read -r start end closed heading_block; do
  : "$start" "$end"  # body span unused here; block detection alone gives us the heading
  [ "$closed" = "1" ] && continue

  # FINDING-CA3-1 (v0.9.0 RC audit, CA3 round), now via the dir #426 shared helper: `—
  # RETRACTED\b` matched anywhere in the flattened heading_block, whole-block scoped, wrongly
  # dropped a live `→ pool` ticket whose OWN body cites a sibling's retraction ("Superseded by
  # dir #3 — RETRACTED for background") from the pool census — the same "whose tag is it" shape
  # tools/lib/backlog-blocks.sh's F-04 fix already solved for the closure tag. This used to be a
  # near-duplicate copy of that fix's strip-then-test loop, generalized for the `RETRACTED` tag
  # instead of a closure tag; dir #426 promoted the loop itself into
  # tools/lib/backlog-blocks.sh's `bb_strip_foreign_citations`, so this file now calls the same
  # code backlog-blocks.sh's own `closed` detection calls, parameterized on the tag it cares
  # about. See that function's own header for the full history (two independent review rounds:
  # the if/elif-shadowing gap, the glob-vs-literal quoting gap, and the single-strip-per-form
  # gap) — nothing here diverges from it any more.
  own_num="$(bb_own_ticket_num "$heading_block")"
  stripped="$(bb_strip_foreign_citations "$heading_block" "$own_num" 'RETRACTED')"
  [[ "$stripped" =~ —[[:space:]]*RETRACTED([^a-zA-Z]|$) ]] && continue

  # Last `→` token naming a release or the pool (BACKLOG.md's own G3 extraction rule) — a
  # heading carries prose arrows too ("→ ask", "→ a release of its own"); only these two
  # shapes are ever a real release tag.
  tag="$(grep -oE '→[[:space:]]*(pool\b|[0-9]+\.[0-9]+\.[0-9]+)' <<< "$heading_block" \
    | tail -1 | sed -E 's/^→[[:space:]]*//' || true)"
  [ "$tag" = "pool" ] || continue

  pool_size=$((pool_size + 1))

  rlvl="$(grep -oE '— R[0-9] —' <<< "$heading_block" | tail -1 | grep -oE 'R[0-9]' || true)"
  case "$rlvl" in
    R1) r1=$((r1 + 1)) ;;
    R2) r2=$((r2 + 1)) ;;
    R3) r3=$((r3 + 1)) ;;
    *) runmarked=$((runmarked + 1)) ;;
  esac

  parked=0
  # Bare `⛔` presence, EXCEPT the two shapes the glyph is also reused for live in this file to
  # mean the OPPOSITE ("⛔ UNBLOCKED ...", "GATE CLEARED, no longer ⛔") — narrowing to a single
  # positive shape like `⛔.*BLOCKED` instead would be wrong the other way: real parked headings
  # here also read "⛔ PARKED ..." or "⛔ tail BLOCKED ...", not just the legend's literal
  # `⛔ BLOCKED by <ref>`, so excluding the two known false-positive shapes (rather than
  # requiring one true-positive wording) is what actually matches the live convention.
  #
  # dir #425 (fixed here): the exclusion used to be whole-block scoped, so a heading stating BOTH
  # a current `⛔` block AND its own future-unblock clause in one line ("⛔ BLOCKED by X, no
  # longer ⛔ once X lands") matched the exclusion and was wrongly dropped from the parked census
  # (parked=0 where the single-state "⛔ BLOCKED by X" phrasing correctly counts parked=1). Fix:
  # split the block into CLAUSES (on `,`, `;`, or the convention's own ` — ` separator — pure
  # bash string substitution, no sed/awk regex-portability risk) and apply the exclusion per
  # clause, not to the whole block — a `⛔` in one clause is parked unless THAT SAME clause also
  # carries the unblock phrasing; an unblock phrase living in a different clause of the same
  # heading no longer cancels it out.
  #
  # v0.9.0 RC audit, final fix round: the exclusion pattern must name exactly the two documented
  # shapes above ("⛔ UNBLOCKED", "no longer ⛔") — a bare `⛔[[:space:]]*UN` prefix match is
  # broader than either shape and also swallows any OTHER ⛔-adjacent word starting "un" (unless,
  # unclear, under review, ...), wrongly excluding those as if they meant "unblocked". Still true
  # per-clause: this fix only narrows WHICH TEXT the exclusion pattern is tested against, not the
  # pattern itself.
  #
  # KNOWN LIMITATION (code-review high, altitude finding): splitting on a bare `,` is broader than
  # this project's own `— `-separated convention used everywhere else in this file's regexes — an
  # ordinary prose comma inside one logical clause (e.g. "no longer ⛔, since dir #5 merged, all
  # clear") could in principle separate an unblock phrase from the very `⛔` it qualifies, if the
  # comma falls between them. Not narrowed to `— ` only, because the ticket's own worked example
  # ("⛔ BLOCKED by X, no longer ⛔ once X lands") is itself comma-separated, not em-dash-separated
  # — dropping comma support would leave the shape dir #425 exists to fix uncaught. Checked live
  # against this project's own real BACKLOG.md: the parked count is unchanged before and after
  # this fix (no heading here currently has this shape either way), so this is a documented,
  # currently-inert residual risk, not a live defect.
  # code-review efficiency pass: gate the clause split behind a cheap whole-block presence check
  # first, same as the old whole-block `grep -qE '⛔'` did — most heading blocks carry no `⛔` at
  # all, and splitting+looping unconditionally would spend three string rewrites plus a per-clause
  # grep on every one of them for nothing.
  if [[ "$heading_block" == *⛔* ]]; then
    clause_split="${heading_block//;/,}"
    clause_split="${clause_split// — /,}"
    clause_split="${clause_split//,/$'\n'}"
    while IFS= read -r clause; do
      [[ "$clause" == *⛔* ]] || continue
      if ! grep -qiE '⛔[[:space:]]*UNBLOCKED|no longer[[:space:]]+⛔' <<< "$clause"; then
        parked=1
      fi
    done <<< "$clause_split"
  fi
  grep -qiE 'explicit gate|gate[[:space:]]*=' <<< "$heading_block" && parked=1
  [ "$parked" = "1" ] && parked_count=$((parked_count + 1))

  # Oldest entry: the first YYYY-MM-DD date in the heading block — the origination date every
  # ticket's own parenthetical carries ("captured ...", "found ...", "felt ...").
  date_str="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<< "$heading_block" | head -1 || true)"
  if [ -n "$date_str" ]; then
    ts="$(date -u -j -f '%Y-%m-%d' "$date_str" +%s 2>/dev/null \
      || date -u -d "$date_str" +%s 2>/dev/null || true)"
    if [ -n "$ts" ]; then
      age_days=$(( (today_epoch - ts) / 86400 ))
      if [ "$age_days" -gt "$oldest_age" ]; then
        oldest_age="$age_days"
        oldest_id="$(grep -oE 'dir #[0-9]+' <<< "$heading_block" | head -1 || true)"
        [ -n "$oldest_id" ] || oldest_id="unlabeled"
      fi
    fi
  fi
done < <(backlog_ticket_blocks "$backlog_file")

# Read whatever history already exists BEFORE any --record append below, so the trigger
# check below compares this run's size against PRIOR runs only, never against itself.
prev_sizes=()
if [ -f "$history_file" ]; then
  while IFS= read -r sz; do prev_sizes+=("$sz"); done \
    < <(grep -oE '"pool_size":[0-9]+' "$history_file" 2>/dev/null | grep -oE '[0-9]+$' || true)
fi

echo "pool-report: $backlog_file"
echo "  pool size:                     $pool_size"
if [ "$oldest_age" -ge 0 ]; then
  echo "  oldest entry:                   ${oldest_age}d ($oldest_id)"
else
  echo "  oldest entry:                   no dated entry found"
fi
echo "  R-level split:                  R1=$r1 R2=$r2 R3=$r3 unmarked=$runmarked"
echo "  excluding structurally-parked:  $((pool_size - parked_count)) (of $pool_size; $parked_count parked by rule: blocked or explicit-gate)"

n="${#prev_sizes[@]}"
trigger_fired=0
if [ "$n" -ge 2 ]; then
  p2="${prev_sizes[$((n - 2))]}"
  p1="${prev_sizes[$((n - 1))]}"
  if [ "$p2" -lt "$p1" ] && [ "$p1" -lt "$pool_size" ]; then
    trigger_fired=1
  fi
fi

if [ "$trigger_fired" = "1" ]; then
  echo "WARN: the pool has grown across the last two recorded releases and again this run ($p2 -> $p1 -> $pool_size) — schedule a drain release (dir #360)." >&2
elif [ "$n" -lt 2 ]; then
  echo "  growth trigger:                 not enough recorded history yet ($n prior run(s); needs 2)"
else
  echo "  growth trigger:                 not firing"
fi

if [ -n "$record_release" ]; then
  if [ -f "$history_file" ] && grep -qF "\"release\":\"$record_release\"" "$history_file" 2>/dev/null; then
    echo "  history:                        $record_release already recorded in $history_file — not re-appended"
  else
    mkdir -p "$(dirname "$history_file")" 2>/dev/null || true
    printf '{"release":"%s","date":"%s","pool_size":%s}\n' \
      "$record_release" "$(date -u +%Y-%m-%d)" "$pool_size" >> "$history_file"
    echo "  history:                        appended ($history_file)"
  fi
fi

exit 0
