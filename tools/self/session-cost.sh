#!/usr/bin/env bash
# tools/self/session-cost.sh — keel-self-maintenance (dir #313): "what does a unit of work on this
# project actually cost?" The method dir #313's design pass settled on (SPEC §1): cost per ticket,
# grouped by (R-tier, model) cell, on DEDUPED tokens, reporting the MEDIAN per cell (n is small — a
# single long session must not dominate a mean). Cost = deduped(cache_read_input_tokens) +
# deduped(output_tokens), summed over a ticket's PRIMARY-session records only (subagent fan-out is
# reported as its own separate figure, never folded in — folding it in would re-obscure exactly the
# "which stage costs it" breakdown this ticket's own body already extracted via `attributionSkill`).
# Denominated in tokens, not USD (SPEC §1 — this project runs on the same subscription model dir #314's
# adopter-facing tool does, so no API price applies to either).
#
# All parsing goes through tools/lib/transcript-usage.sh (dir #313 SPEC §3): this script is one of two
# callers of that shared reader, the other being dir #314's own adopter-facing report — neither
# re-derives the requestId dedupe or the subagent-enumeration logic.
#
# Ships nothing adopter-facing (dir #313 SPEC §3): this is a keel-self-maintenance tool that answers
# "what does OUR pipeline cost", never installed by install.sh. Per CLAUDE.md's commit-bar convention
# (dir #68), every tracked artifact names its own audience — this one is keel-self-maintenance.
#
# R-tier is NOT derivable from a transcript (it's a BACKLOG.md heading tag, per-project convention,
# not part of the harness's own data) — SPEC §4 item 2 leaves that lookup to the caller. This script
# takes (ticket, tier, model) as given, in a manifest the caller assembles by hand from their own
# backlog once per ticket, the same way a ledger citation is hand-supplied rather than auto-mined.
#
# Usage:
#   session-cost.sh session FILE                    one session's totals (primary + subagent), human-readable
#   session-cost.sh session --json FILE             ...as one JSON object
#   session-cost.sh selfcheck FILE...               tu_self_check for each file — the visible guard
#                                                    against a transcript format that moved silently
#   session-cost.sh ticket TIER MODEL FILE...        one ticket's cost across 1+ session files (a ticket
#                                                     can span a start/cancel/restart, dir #147's own
#                                                     three-session lifecycle) — primary cost_tokens plus
#                                                     the subagent total, reported separately
#   session-cost.sh table MANIFEST                   read a manifest (see below) and print the full
#                                                     per-ticket table plus the median per (tier, model) cell
#
# Manifest format (one ticket per line, tab-separated, '#'-prefixed comment lines and blank lines
# skipped): TICKET<TAB>TIER<TAB>MODEL<TAB>FILE1[,FILE2,...]
#   dir#298	R1	sonnet	/Users/x/.claude/projects/.../3a0efd0c....jsonl
# A ticket's FILEs are its own session transcripts (comma-joined, no spaces) — resolve them with
# tools/lib/transcript-usage.sh's tu_session_files against gitBranch, or by hand the way dir #313's own
# body did before gitBranch attribution was found (see that ticket's "Session-file mapping" table).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/transcript-usage.sh
. "$SCRIPT_DIR/../lib/transcript-usage.sh"

usage() {
  cat <<'EOF'
session-cost.sh — cost per ticket, by (R-tier, model) cell, on deduped tokens (dir #313).

Usage:
  session-cost.sh session [--json] FILE
  session-cost.sh selfcheck FILE...
  session-cost.sh ticket TIER MODEL FILE...
  session-cost.sh table MANIFEST
  session-cost.sh -h | --help
EOF
}

# _sc_ticket_cost TIER MODEL TICKET FILE... — one ticket's summed totals across its session file(s).
# Emits one JSON object: {tier, model, files, primary:{turns,cache_read_input_tokens,output_tokens,
# cost_tokens,models,...}, subagent:{...}} — "subagent" key absent when none of the ticket's sessions
# spawned any.
#
# TICKET is optional (pass "" from a caller with no ticket id, e.g. cmd_ticket below) — when non-empty
# it is stamped onto the result directly, so a caller building a manifest row (cmd_table) never needs a
# second jq pass just to bolt the id on afterward.
_sc_ticket_cost() {
  local tier="$1" model="$2" ticket="$3"; shift 3
  local tmp; tmp="$(mktemp)" || return 1
  local f
  for f in "$@"; do
    tu_session_totals "$f" >> "$tmp" || { rm -f "$tmp"; return 1; }
  done
  # dir #313 review: capture-then-cleanup-then-return, not a trailing `jq ...; rm -f "$tmp"` (that
  # made rm's exit status this function's own, masking a failing jq) and not a `trap ... RETURN`
  # either — tried and reverted: bash RETURN traps are a single GLOBAL handler, not scoped to the
  # function that sets one, and reproduced live crashing a caller two frames up ("tmp: unbound
  # variable") once this function's own $tmp had gone out of scope. See tu_session_totals's own
  # comment (tools/lib/transcript-usage.sh) for the same fix, same reasoning, in its sibling function.
  local result status
  result="$(jq -c -s --arg tier "$tier" --arg model "$model" --arg ticket "$ticket" --argjson nfiles "$#" '
    def sum_kind($xs): {
      turns: ([$xs[].turns] | add // 0),
      cache_read_input_tokens: ([$xs[].cache_read_input_tokens] | add // 0),
      cache_creation_input_tokens: ([$xs[].cache_creation_input_tokens] | add // 0),
      output_tokens: ([$xs[].output_tokens] | add // 0),
      thinking_tokens: ([$xs[].thinking_tokens] | add // 0),
      models: ([$xs[].models[]?] | unique)
    };
    {
      tier: $tier,
      model: $model,
      files: $nfiles,
      primary: ([.[].primary] | sum_kind(.) | . + { cost_tokens: (.cache_read_input_tokens + .output_tokens) }),
      subagent: (
        [.[].subagent // empty] as $ss
        | if ($ss | length) == 0 then null else sum_kind($ss) end
      )
    }
    | if .subagent == null then del(.subagent) else . end
    | if $ticket == "" then . else . + {ticket: $ticket} end
  ' "$tmp")"
  status=$?
  rm -f "$tmp"
  [ "$status" -eq 0 ] || return "$status"
  # dir #313 review: `model` was already parsed per-turn (tu_turns) and per-session
  # (tu_session_totals) before this check existed — a caller-supplied --model/manifest MODEL column
  # had nothing to catch a mistyped value against, even though the ground truth was sitting in the
  # data one function earlier. A mismatch is a warning, not a hard failure: a ticket that genuinely
  # changed model mid-lifecycle is real and should still produce a row, just a flagged one.
  # Substring match, not equality: the transcript's own `.message.model` is the full API model id
  # (e.g. "claude-sonnet-5"), while a caller naturally types the shorthand this project's own R-tier
  # convention uses ("sonnet") — an equality check would warn on every correct call, training the
  # operator to ignore the warning exactly when it matters.
  local observed
  observed="$(printf '%s' "$result" | jq -r '(.primary.models // []) | join(",")')"
  if [ -n "$observed" ] && [[ "$observed" != *"$model"* ]]; then
    printf 'session-cost.sh: warning — ticket %s: --model %s does not match model(s) recorded in the transcripts: %s\n' \
      "${ticket:-<none>}" "$model" "$observed" >&2
  fi
  printf '%s\n' "$result"
}

cmd_session() {
  local as_json=0
  if [ "${1:-}" = "--json" ]; then as_json=1; shift; fi
  local file="${1:-}"
  [ -n "$file" ] || { printf 'session-cost.sh: session needs a FILE\n' >&2; exit 2; }
  [ -f "$file" ] || { printf 'session-cost.sh: no such file: %s\n' "$file" >&2; exit 2; }
  local totals; totals="$(tu_session_totals "$file")"
  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$totals"
    return 0
  fi
  printf '%s\n' "$totals" | jq -r '
    "primary:  turns=\(.primary.turns)  output=\(.primary.output_tokens)  cache_read=\(.primary.cache_read_input_tokens)  cache_creation=\(.primary.cache_creation_input_tokens)",
    (if .subagent then
      "subagent: turns=\(.subagent.turns)  output=\(.subagent.output_tokens)  cache_read=\(.subagent.cache_read_input_tokens)  cache_creation=\(.subagent.cache_creation_input_tokens)"
     else
      "subagent: none"
     end)
  '
}

cmd_selfcheck() {
  [ "$#" -gt 0 ] || { printf 'session-cost.sh: selfcheck needs at least one FILE\n' >&2; exit 2; }
  local f rc=0
  for f in "$@"; do
    # dir #313 review: `rc=N` on its own (not `[ "$rc" -lt N ] && rc=N`) is last-write-wins, not
    # worst-of — a missing file (2) followed by an unrecognized-type file (1) used to report exit 1,
    # silently downgrading the more severe condition depending on argument order (reproduced live:
    # the same two files in the two possible orders exited 1 and 2 respectively for identical inputs).
    if [ ! -f "$f" ]; then
      printf 'session-cost.sh: no such file: %s\n' "$f" >&2
      [ "$rc" -lt 2 ] && rc=2
      continue
    fi
    local sc; sc="$(tu_self_check "$f")"
    printf '%s\n' "$sc"
    local unrec; unrec="$(printf '%s' "$sc" | jq -r '.unrecognized_types | length')"
    if [ "$unrec" -gt 0 ]; then
      printf 'session-cost.sh: %s carries %s unrecognized record type(s) — the transcript format may have moved\n' \
        "$f" "$unrec" >&2
      [ "$rc" -lt 1 ] && rc=1
    fi
  done
  return "$rc"
}

cmd_ticket() {
  [ "$#" -ge 3 ] || { printf 'session-cost.sh: ticket needs TIER MODEL FILE...\n' >&2; exit 2; }
  local tier="$1" model="$2"; shift 2
  _sc_ticket_cost "$tier" "$model" "" "$@"
}

# cmd_table MANIFEST — the cross-ticket view: one row per ticket (from _sc_ticket_cost), then one row
# per (tier, model) cell with the MEDIAN cost_tokens across its tickets (SPEC §1: median, not mean — n
# is small and a single long session must not dominate a cell).
cmd_table() {
  local manifest="${1:-}"
  [ -n "$manifest" ] || { printf 'session-cost.sh: table needs a MANIFEST file\n' >&2; exit 2; }
  [ -f "$manifest" ] || { printf 'session-cost.sh: no such manifest: %s\n' "$manifest" >&2; exit 2; }

  local tmp; tmp="$(mktemp)" || exit 1
  # dir #313 review: every error path below cleans up "$tmp" explicitly before exiting, rather than a
  # `trap ... EXIT` — tried and reverted (see _sc_ticket_cost's own comment, tools/self/session-cost.sh,
  # and tu_session_totals', tools/lib/transcript-usage.sh): bash RETURN traps proved to be a single
  # GLOBAL handler rather than scoped to the function that sets one, and while an EXIT trap fires only
  # once (at real process exit, not per function return) and did not reproduce that same failure in
  # testing, this file now sticks to ONE cleanup idiom everywhere rather than trusting a second,
  # less-exercised one under time pressure.
  local ticket tier model files_csv
  while IFS=$'\t' read -r ticket tier model files_csv || [ -n "$ticket" ]; do
    case "$ticket" in ''|'#'*) continue ;; esac
    [ -n "$tier" ] && [ -n "$model" ] && [ -n "$files_csv" ] || {
      printf 'session-cost.sh: malformed manifest line (want TICKET\\tTIER\\tMODEL\\tFILE1,FILE2,...): %s\\t%s\\t%s\\t%s\n' \
        "$ticket" "$tier" "$model" "$files_csv" >&2
      rm -f "$tmp"; exit 2
    }
    # dir #313 review: dedupe the FILE list before summing — a manifest line that (by a plausible
    # hand-editing slip) repeats one session file counts that session's tokens twice, a silent 2x
    # inflation moved one layer up from the dedupe bug this whole ticket exists to fix. Portable
    # first-occurrence dedupe (`awk '!seen[$0]++'`), not a bash associative array — this codebase
    # avoids `declare -A` for bash 3.2 compatibility (see citation-resolvability.sh's own note).
    local -a files=()
    while IFS= read -r ff; do
      [ -n "$ff" ] && files+=("$ff")
    done < <(printf '%s' "$files_csv" | tr ',' '\n' | awk '!seen[$0]++')
    local row; row="$(_sc_ticket_cost "$tier" "$model" "$ticket" "${files[@]}")" || {
      printf 'session-cost.sh: failed to read %s (ticket %s)\n' "$files_csv" "$ticket" >&2
      rm -f "$tmp"; exit 1
    }
    printf '%s\n' "$row" >> "$tmp"
  done < "$manifest"

  if [ ! -s "$tmp" ]; then
    printf 'session-cost.sh: manifest carried no ticket rows: %s\n' "$manifest" >&2
    rm -f "$tmp"; exit 2
  fi

  # dir #313 review: one format string per table, used for both its header and its data rows, so the
  # two can never silently drift out of column alignment the way two hand-typed copies could.
  local detail_fmt='%-10s %-6s %-8s %6s %9s %11s %8s   %s\n'
  # shellcheck disable=SC2059  # $detail_fmt is a fixed local format, not user input
  printf "$detail_fmt" ticket tier model msgs output cache_read ctx/msg 'subagent(turns/output/cache_read)'
  jq -r '
    "\(.ticket)|\(.tier)|\(.model)|\(.primary.turns)|\(.primary.output_tokens)|\(.primary.cache_read_input_tokens)|" +
    (if .primary.turns > 0 then (.primary.cache_read_input_tokens / .primary.turns | floor | tostring) else "-" end) + "|" +
    (if .subagent then "\(.subagent.turns)/\(.subagent.output_tokens)/\(.subagent.cache_read_input_tokens)" else "-" end)
  ' "$tmp" | while IFS='|' read -r t tier model msgs output cache_read ctxmsg sub; do
    # shellcheck disable=SC2059
    printf "$detail_fmt" "$t" "$tier" "$model" "$msgs" "$output" "$cache_read" "$ctxmsg" "$sub"
  done

  local median_fmt='%-6s %-8s %4s %s\n'
  printf '\n'
  # shellcheck disable=SC2059
  printf "$median_fmt" tier model n median_cost_tokens
  jq -s -r '
    group_by([.tier, .model])
    | map({
        tier: .[0].tier,
        model: .[0].model,
        n: length,
        costs: ([.[].primary.cost_tokens] | sort)
      })
    | .[]
    | . as $cell
    | ($cell.costs | length) as $n
    | (if $n % 2 == 1 then $cell.costs[($n - 1) / 2]
       else (($cell.costs[$n/2 - 1] + $cell.costs[$n/2]) / 2)
       end) as $median
    | "\($cell.tier)|\($cell.model)|\($cell.n)|\($median)"
  ' "$tmp" | while IFS='|' read -r tier model n median; do
    # shellcheck disable=SC2059
    printf "$median_fmt" "$tier" "$model" "$n" "$median"
  done
  rm -f "$tmp"
}

main() {
  tu_require_jq || exit 1
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    session)   cmd_session "$@" ;;
    selfcheck) cmd_selfcheck "$@" ;;
    ticket)    cmd_ticket "$@" ;;
    table)     cmd_table "$@" ;;
    -h|--help|'') usage ;;
    *) printf 'session-cost.sh: unknown command %s\n' "$cmd" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
