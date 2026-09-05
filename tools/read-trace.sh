#!/usr/bin/env bash
# tools/read-trace.sh — dir #387: read-trace fuses.
#
# The problem this closes: the operator almost never sees WHAT a session actually READ, so "built
# their own bicycle without opening the spec" surfaces a release or more later (dir #371, dir #375,
# the 2026-09-03 groom's own ticket-bodies-unread failure). This is a MECHANISM, never loaded into
# context and never read by the model — it sits in the shell, in `docs/loading-and-cost.md`'s third
# tier (the secret-guard/pre-pr-gate class). Ship at most a wiring-instructions stub as prose (the
# ticket's own words) — this header IS that stub; there is no separate docs/read-trace.md.
#
# The honest core, same honesty model as tools/pre-pr-gate.sh: a Read (or an Edit/Write/NotebookEdit)
# is an observable tool call. A PostToolUse hook logs it; the agent cannot claim a read it did not
# make — the trace either exists or it does not.
#
# Three tiers (docs/loading-and-cost.md's model), zero enforcement in tiers 1-2, DATA ONLY in tier 3
# (tools/read-trace-map.tsv, a separate file — the PreToolUse deny-hook that would consume it waits
# for a felt recurrence per surface, an operator decision, not an omission):
#   Tier 1 — visibility: `docs-line` feeds /wrap's report and /polish's PR body a `docs read:` line,
#            generated (never hand-typed) from this session's own ephemeral log.
#   Tier 2 — aggregation: `aggregate` reads the persistent cross-release store and emits a small
#            table — the groom's (dir #386 G0) dead-doc-report input.
#   Wrap fuse (operator amendment, same tiers) — `session-end`/`startup` flag a mutating session that
#            ended with no `/wrap`, non-blocking, surfaced once at the NEXT session's start.
#
# Usage:
#   read-trace.sh log-tool           PostToolUse(Read|Edit|Write|NotebookEdit) hook. SILENT: exit 0,
#                                     zero stdout, always — hook output can be injected into the
#                                     session as feedback, which would tax every logged tool call in
#                                     every session (ECONOMICS binding requirement (1); pinned by test).
#   read-trace.sh startup            SessionStart(startup) hook. Resets this (repo,branch)'s ephemeral
#                                     log for the new session, then — the ONE subcommand allowed to
#                                     print, mirroring tools/pre-pr-gate.sh's own rollout-check — emits
#                                     a `systemMessage` naming any branch(es) with a pending wrap-fuse
#                                     flag, then clears them. Silent (no output) when nothing is pending.
#   read-trace.sh session-end        SessionEnd hook (any end reason). Silent — SessionEnd's own stdout
#                                     is confirmed neither operator- nor model-visible, so this writes
#                                     state only: an outcome row to the persistent wrap-fuse-events log,
#                                     and (only on a genuine miss) a pending flag for `startup` to pick
#                                     up next session. See the wrap-fuse section below for the full
#                                     exclusion logic (read-only sessions, DELEGATION RUN workers).
#   read-trace.sh docs-line [dir]    Shell helper for /wrap and /polish — the ONLY thing that may enter
#                                     a context: the short `docs read: ...` line, derived from the
#                                     ephemeral log (never the agent reading the raw log itself).
#   read-trace.sh wrap-done [dir]    Called once, at the end of /wrap's own persist step
#                                     (commands/wrap.md) — stamps this (repo,branch)'s completion so
#                                     `session-end` can tell "wrapped after the last mutation" from
#                                     "mutated, never wrapped".
#   read-trace.sh aggregate [dir]    Tier-2 aggregator TOOL — prints the small table (FORMAT below);
#                                     the raw log never crosses into any context, only this does.
#   read-trace.sh rotate [dir]       Release-boundary log rotation (manual — the release manager's own
#                                     wrap-time chore, not auto-wired): archives the persistent logs so
#                                     they don't grow unbounded across releases.
#
# --- AGGREGATE FORMAT (pinned by tests/test_read_trace.sh) -----------------------------------------
# dir #386's /groom G0 cites this generically, by mechanism ("`read-trace.sh aggregate`'s dead-doc
# table"), never by column — this file owns the shape, per this ticket's own seam contract.
#   | doc | last read | reads | surface changes since |
#   | --- | --- | --- | --- |
#   | <repo-relative path, or literal BACKLOG.md> | <ISO date, or "never"> | <count> | <count> |
#   wrap-fuse: <N> of <M> mutating sessions this cycle ended with no /wrap (cycle since <date|n/a>)
#
# --- Portability (dir #367's R12) -------------------------------------------------------------------
# Claude-Code-only, named rather than silent: every subcommand above but docs-line/wrap-done/
# aggregate/rotate is a Claude Code hook (PostToolUse/SessionStart/SessionEnd, JSON-on-stdin, the
# `systemMessage` JSON-output convention). No equivalent ships for another harness yet.
#
# Wiring is opt-in, same discipline as tools/install-pre-pr-gate.sh (a hook changes what a session can
# do without asking each time) — see tools/install-read-trace.sh. Nothing above fires until that has
# been run once for a repo (or --global/--home).
set -u

_rt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/read-trace.sh
. "$_rt_dir/lib/read-trace.sh"
unset _rt_dir

usage() {
  cat <<'EOF'
read-trace — dir #387's read-trace fuses. See this file's own header for the full subcommand list,
the aggregate's pinned FORMAT, and the portability boundary.

Usage:
  read-trace.sh log-tool           PostToolUse(Read|Edit|Write|NotebookEdit) hook (silent)
  read-trace.sh startup            SessionStart(startup) hook (silent unless a wrap-fuse flag is pending)
  read-trace.sh session-end        SessionEnd hook (silent)
  read-trace.sh docs-line [dir]    the "docs read: ..." line for /wrap and /polish
  read-trace.sh wrap-done [dir]    stamp this (repo,branch)'s /wrap completion
  read-trace.sh aggregate [dir]    the tier-2 small table (dir #386 /groom G0's input)
  read-trace.sh rotate [dir]       archive the persistent logs at a release boundary
  read-trace.sh -h | --help
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") usage >&2; exit 2 ;;
esac

case "$1" in
  log-tool)
    # PostToolUse(Read|Edit|Write|NotebookEdit) — MUST stay silent (ECONOMICS requirement (1), pinned
    # by test): any parse failure, missing jq, or unrecognized shape is a silent no-op, same discipline
    # as tools/pre-pr-gate.sh's own skill-trace — a missed row is a residual limit, never a false
    # signal, and never a printed line.
    command -v jq >/dev/null 2>&1 || exit 0
    lt_input=$(cat 2>/dev/null)
    # \x1f, not tab (same reasoning as pre-pr-gate.sh's skill-trace): a NotebookEdit event has no
    # .tool_input.file_path, and a Read/Edit/Write event has no .tool_input.notebook_path — both empty
    # fields sitting between populated ones, which `read` under IFS=tab would collapse.
    IFS=$'\x1f' read -r lt_cwd lt_tool lt_path lt_nbpath <<<"$(printf '%s' "$lt_input" | jq -r '
      def str: if . == null then "" elif type == "string" then . else tostring end;
      [(.cwd|str), (.tool_name|str), (.tool_input.file_path|str), (.tool_input.notebook_path|str)]
      | join("")' 2>/dev/null)"
    [ -n "$lt_cwd" ] || lt_cwd="$PWD"
    lt_raw="$lt_path"; [ -n "$lt_raw" ] || lt_raw="$lt_nbpath"
    [ -n "$lt_raw" ] || exit 0
    lt_norm="$(_rt_normalize_path "$lt_cwd" "$lt_raw")"
    case "$lt_tool" in
      Read)
        _rt_in_doc_scope "$lt_norm" && _rt_record_read "$lt_cwd" "$lt_norm"
        ;;
      Edit|Write|NotebookEdit)
        _rt_record_mutate "$lt_cwd" "$lt_norm"
        ;;
    esac
    exit 0
    ;;

  startup)
    # SessionStart(startup) — resets the ephemeral log for a genuinely NEW session (deliberately not
    # wired to "resume"/"clear" — a resumed session keeps accumulating onto what it already logged;
    # named as a simplifying choice, not verified against a live resume event this ticket's own
    # budget). Then: the wrap-fuse pickup. SessionEnd/Stop stdout is confirmed neither operator- nor
    # model-visible (verified against code.claude.com/docs/en/hooks.md at this ticket's
    # implementation) — nobody is watching at session-end time by construction — so a pending flag is
    # only ever surfaced HERE, at the next session's start, via the one JSON-output channel
    # SessionStart is confirmed to support (`systemMessage`, the same channel
    # tools/pre-pr-gate.sh's own rollout-check uses).
    command -v jq >/dev/null 2>&1 || exit 0
    st_input=$(cat 2>/dev/null)
    st_cwd="$(printf '%s' "$st_input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -n "$st_cwd" ] || st_cwd="$PWD"
    rm -f "$(_rt_session_log "$st_cwd")"
    st_flagdir="$(_rt_wrapfuse_flag_dir "$st_cwd")"
    st_names=""
    if [ -d "$st_flagdir" ]; then
      for st_f in "$st_flagdir"/*.flag; do
        [ -f "$st_f" ] || continue
        st_names="${st_names:+$st_names, }$(basename "$st_f" .flag)"
        rm -f "$st_f"
      done
    fi
    if [ -n "$st_names" ] && command -v jq >/dev/null 2>&1; then
      jq -cn --arg m "read-trace (dir #387): session(s) ended with changes and no /wrap on: $st_names" \
        '{systemMessage:$m}'
    fi
    exit 0
    ;;

  session-end)
    # SessionEnd (any end reason) — silent by construction (see `startup`'s own comment on why: this
    # event's stdout reaches nobody). Writes state only.
    command -v jq >/dev/null 2>&1 || exit 0
    se_input=$(cat 2>/dev/null)
    se_cwd="$(printf '%s' "$se_input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -n "$se_cwd" ] || se_cwd="$PWD"
    se_transcript="$(printf '%s' "$se_input" | jq -r '.transcript_path // empty' 2>/dev/null)"
    se_slog="$(_rt_session_log "$se_cwd")"
    # Exclusion 1 — read-only session: no mutating row at all means nothing for the fuse to flag.
    se_last_mutate="$( [ -f "$se_slog" ] && awk -F'\t' '$2=="mutate"{t=$1} END{print t}' "$se_slog" 2>/dev/null )"
    [ -n "$se_last_mutate" ] || exit 0
    # Exclusion 2 — a DELEGATION RUN worker is FORBIDDEN to wrap by its own brief ("wrap duties are
    # centralized"); no dedicated hook field names this (confirmed against the docs — a hook gets no
    # prompt/system-prompt field), so this greps the session's own transcript for the literal marker
    # every such worker's brief carries verbatim (dir #387's own resolved TO VERIFY).
    if [ -n "$se_transcript" ] && [ -f "$se_transcript" ] && grep -q "DELEGATION RUN" "$se_transcript" 2>/dev/null; then
      exit 0
    fi
    se_wd="$(_rt_wrapdone_path "$se_cwd")"
    se_wrapped=0
    if [ -f "$se_wd" ]; then
      se_wrap_ts="$(awk -F'\t' '{print $1}' "$se_wd" 2>/dev/null)"
      # ISO-8601 UTC timestamps sort lexicographically by instant — a plain string compare is exact
      # and needs no epoch-parsing dependency. Not-less-than, not strictly-greater-than: a wrap and its
      # last-covered mutation can legitimately land in the same second (reproduced live — a fast
      # wrap-done-then-session-end pair), and a strict `>` would misclassify that tie as unwrapped.
      if [ -n "$se_wrap_ts" ] && ! [[ "$se_wrap_ts" < "$se_last_mutate" ]]; then se_wrapped=1; fi
    fi
    se_wlog="$(_rt_wrapfuse_log "$se_cwd")"
    mkdir -p "$(dirname "$se_wlog")"
    if [ "$se_wrapped" -eq 1 ]; then
      printf '%s\twrapped\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(_rt_key "$se_cwd")" >> "$se_wlog" 2>/dev/null
      rm -f "$(_rt_wrapfuse_flag "$se_cwd")" 2>/dev/null
    else
      printf '%s\tno-wrap\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(_rt_key "$se_cwd")" >> "$se_wlog" 2>/dev/null
      mkdir -p "$(_rt_wrapfuse_flag_dir "$se_cwd")"
      printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$se_cwd" > "$(_rt_wrapfuse_flag "$se_cwd")" 2>/dev/null
    fi
    exit 0
    ;;

  docs-line)
    # Shell helper (dir #387 ECONOMICS requirement (2)): /wrap and /polish call this instead of
    # reading tools/read-trace.sh's own log — its short output is the only part of the log that may
    # ever enter a context.
    dl_dir="${2:-.}"
    dl_slog="$(_rt_session_log "$dl_dir")"
    dl_rows=""
    [ -f "$dl_slog" ] && dl_rows="$(awk -F'\t' '$2=="read"{print $3}' "$dl_slog" 2>/dev/null | LC_ALL=C sort -u)"
    if [ -z "$dl_rows" ]; then
      printf 'docs read: none\n'
    else
      dl_n="$(printf '%s\n' "$dl_rows" | grep -c .)"
      dl_list="$(printf '%s\n' "$dl_rows" | paste -sd',' - | sed 's/,/, /g')"
      printf 'docs read: %s (%s)\n' "$dl_list" "$dl_n"
    fi
    exit 0
    ;;

  wrap-done)
    wd_dir="${2:-.}"
    wd_path="$(_rt_wrapdone_path "$wd_dir")"
    wd_sha="$(git -C "$wd_dir" rev-parse HEAD 2>/dev/null)"
    mkdir -p "$(dirname "$wd_path")"
    printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${wd_sha:-unknown}" > "$wd_path"
    printf 'read-trace: wrap completion recorded for %s\n' "$(_rt_key "$wd_dir")"
    exit 0
    ;;

  aggregate)
    ag_dir="${2:-.}"
    ag_rlog="$(_rt_reads_log "$ag_dir")"
    printf '| doc | last read | reads | surface changes since |\n'
    printf '| --- | --- | --- | --- |\n'
    if [ -f "$ag_rlog" ]; then
      ag_paths="$(awk -F'\t' '$2=="read"{print $3}' "$ag_rlog" 2>/dev/null | LC_ALL=C sort -u)"
      while IFS= read -r ag_p; do
        [ -n "$ag_p" ] || continue
        ag_last="$(awk -F'\t' -v p="$ag_p" '$2=="read" && $3==p{d=$1} END{print d}' "$ag_rlog")"
        ag_cnt="$(awk -F'\t' -v p="$ag_p" '$2=="read" && $3==p' "$ag_rlog" | grep -c .)"
        ag_chg="-"
        if [ "$ag_p" != "BACKLOG.md" ] && git -C "$ag_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          ag_since="${ag_last%%T*}"
          ag_chg="$(git -C "$ag_dir" log --oneline --since="$ag_since" -- "$ag_p" 2>/dev/null | grep -c .)"
        fi
        printf '| %s | %s | %s | %s |\n' "$ag_p" "${ag_last:-never}" "$ag_cnt" "$ag_chg"
      done <<<"$ag_paths"
    fi
    ag_wlog="$(_rt_wrapfuse_log "$ag_dir")"
    if [ -f "$ag_wlog" ]; then
      ag_total="$(grep -c . "$ag_wlog" 2>/dev/null || printf '0')"
      ag_nowrap="$(awk -F'\t' '$2=="no-wrap"' "$ag_wlog" 2>/dev/null | grep -c .)"
      ag_since="$(awk -F'\t' 'NR==1{print $1}' "$ag_wlog" 2>/dev/null)"
      printf 'wrap-fuse: %s of %s mutating sessions this cycle ended with no /wrap (cycle since %s)\n' \
        "$ag_nowrap" "$ag_total" "${ag_since:-n/a}"
    else
      printf 'wrap-fuse: 0 of 0 mutating sessions this cycle ended with no /wrap (cycle since n/a)\n'
    fi
    exit 0
    ;;

  rotate)
    ro_dir="${2:-.}"
    ro_store="$(_rt_store_dir "$ro_dir")"
    ro_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    ro_any=0
    for ro_f in reads.log wrap-fuse-events.log; do
      if [ -f "$ro_store/$ro_f" ]; then
        mv "$ro_store/$ro_f" "$ro_store/$ro_f.$ro_stamp.archive"
        ro_any=1
      fi
    done
    if [ "$ro_any" -eq 1 ]; then
      printf 'read-trace: rotated logs in %s (archived with suffix %s)\n' "$ro_store" "$ro_stamp"
    else
      printf 'read-trace: nothing to rotate in %s\n' "$ro_store"
    fi
    exit 0
    ;;

  *)
    printf 'read-trace: unknown subcommand %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
