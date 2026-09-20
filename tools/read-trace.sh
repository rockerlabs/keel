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
#                                     exclusion logic (read-only sessions, DELEGATION RUN and WRAP
#                                     CENTRALIZED workers).
#   read-trace.sh docs-line [--wrap] [dir]  Shell helper for /wrap and /polish — the ONLY thing that
#                                     may enter a context: the short `docs read: ...` line, derived
#                                     from the ephemeral log (never the agent reading the raw log
#                                     itself). `--wrap` (dir #523), FIRST if given: also stamps this
#                                     (repo,branch)'s wrap completion as a side effect of this SAME
#                                     call — commands/wrap.md passes it from /wrap's own persist step;
#                                     /polish never does.
#   read-trace.sh wrap-done [dir]    Standalone fallback for the same stamp `docs-line --wrap` folds
#                                     in (dir #523's shape (c)) — a manual stamp, or a composing
#                                     wrapper that calls this directly instead. Marks this
#                                     (repo,branch)'s completion so `session-end` can tell "wrapped
#                                     after the last mutation" from "mutated, never wrapped".
#   read-trace.sh aggregate [dir]    Tier-2 aggregator TOOL — prints the small table (FORMAT below);
#                                     the raw log never crosses into any context, only this does.
#   read-trace.sh rotate [dir]       Release-boundary log rotation (manual, not auto-wired — run by the
#                                     NEXT groom at the close of its G0 retro, after it has read
#                                     `aggregate`; never at the tag — docs/grooming.md G0, dir #543):
#                                     archives the persistent logs so they don't grow unbounded.
#
# --- AGGREGATE FORMAT (pinned by tests/test_read_trace.sh) -----------------------------------------
# dir #386's /groom G0 cites this generically, by mechanism ("`read-trace.sh aggregate`'s dead-doc
# table"), never by column — this file owns the shape, per this ticket's own seam contract.
#   | doc | last read | reads | surface changes since |
#   | --- | --- | --- | --- |
#   | <repo-relative path, or literal BACKLOG.md> | <ISO date, or "never"> | <count> | <count> |
#   wrap-fuse: <N> of <M> mutating sessions this cycle ended with no /wrap (cycle since <date|n/a>)
#   <the two-line coverage/denominator disclosure — dir #430 + dir #431's one shared output contract,
#   see tools/lib/read-trace.sh's `_rt_coverage_note`>
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
  read-trace.sh docs-line [--wrap] [dir]  the "docs read: ..." line for /wrap and /polish; --wrap also
                                    stamps this (repo,branch)'s /wrap completion as a side effect
  read-trace.sh wrap-done [dir]    stamp this (repo,branch)'s /wrap completion (standalone fallback)
  read-trace.sh aggregate [dir]    the tier-2 small table (dir #386 /groom G0's input)
  read-trace.sh rotate [dir]       archive the persistent logs at a release boundary
  read-trace.sh -h | --help
EOF
}

case "${1:-}" in
  -h|--help)
    usage; exit 0 ;;
  "")
    usage >&2; exit 2 ;;

  log-tool)
    # PostToolUse(Read|Edit|Write|NotebookEdit) — MUST stay silent (ECONOMICS requirement (1), pinned
    # by test): any parse failure, missing jq, or unrecognized shape is a silent no-op, same discipline
    # as tools/pre-pr-gate.sh's own skill-trace — a missed row is a residual limit, never a false
    # signal, and never a printed line.
    command -v jq >/dev/null 2>&1 || exit 0
    # \x1f, not tab (same reasoning as pre-pr-gate.sh's skill-trace): a NotebookEdit event has no
    # .tool_input.file_path, and a Read/Edit/Write event has no .tool_input.notebook_path — both empty
    # fields sitting between populated ones, which `read` under IFS=tab would collapse. jq reads the
    # hook's JSON straight off this process's own stdin (no intermediate cat/variable — one fewer
    # fork on a hook that fires on every logged tool call; found by this ticket's own /simplify
    # efficiency pass).
    IFS=$'\x1f' read -r lt_cwd lt_tool lt_path lt_nbpath <<<"$(jq -r '
      def str: if . == null then "" elif type == "string" then . else tostring end;
      [(.cwd|str), (.tool_name|str), (.tool_input.file_path|str), (.tool_input.notebook_path|str)]
      | join("")' 2>/dev/null)"
    [ -n "$lt_cwd" ] || lt_cwd="$PWD"
    lt_raw="$lt_path"; [ -n "$lt_raw" ] || lt_raw="$lt_nbpath"
    [ -n "$lt_raw" ] || exit 0
    # Resolved ONCE here, threaded through every call below — NOT a cache (see
    # tools/lib/read-trace.sh's own _rt_project_id comment for why a global cache is dead on arrival
    # given this file's command-substitution call shape; a plain parameter survives it fine).
    #
    # TWO different tops, deliberately (dir #430): lt_top is the MAIN-checkout top, threaded into
    # _rt_record_read/_rt_record_mutate below for the STORE KEY, so every worktree of this repo
    # accumulates onto one project id. lt_owntop is THIS checkout's own top (a worktree's own root),
    # threaded into _rt_normalize_path instead, so a worktree session's path normalizes relative to
    # where it actually read the file, not relative to a repo it may never have checked out at all.
    # Conflating the two (the original bug — both used to be lt_top) left a worktree read logged as
    # `.claude/worktrees/<name>/docs/foo.md`: correct for nothing. See _rt_normalize_path's own header
    # comment in tools/lib/read-trace.sh for the full reasoning.
    lt_top="$(_impact_resolve_top "$lt_cwd")"
    lt_owntop="$(keel_repo_own_top "$lt_cwd")"
    lt_norm="$(_rt_normalize_path "$lt_cwd" "$lt_raw" "$lt_owntop")"
    case "$lt_tool" in
      Read)
        _rt_in_doc_scope "$lt_norm" && _rt_record_read "$lt_cwd" "$lt_norm" "$lt_top"
        ;;
      Edit|Write|NotebookEdit)
        _rt_record_mutate "$lt_cwd" "$lt_norm" "$lt_top"
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
    if [ -n "$st_names" ]; then
      # jq's own presence is already established by this case's own top-of-block guard — no need to
      # re-check it here (found by this ticket's own /simplify simplification pass).
      jq -cn --arg m "read-trace (dir #387): session(s) ended with changes and no /wrap on: $st_names" \
        '{systemMessage:$m}'
    fi
    exit 0
    ;;

  session-end)
    # SessionEnd (any end reason) — silent by construction (see `startup`'s own comment on why: this
    # event's stdout reaches nobody). Writes state only.
    command -v jq >/dev/null 2>&1 || exit 0
    # One jq call for all fields, reading stdin directly (same one-call-per-field-set discipline as
    # log-tool and pre-pr-gate.sh's own skill-trace — this used to be two separate jq invocations,
    # found by this ticket's own /simplify efficiency pass). session_id (dir #523): the hook's stdin
    # JSON carries it snake_case, same convention as every other field this file reads off that JSON
    # (cwd, tool_name, transcript_path) — confirmed against this session's own live hook traffic, not
    # just the docs, per this ticket's own lead #3.
    IFS=$'\x1f' read -r se_cwd se_transcript se_session_id <<<"$(jq -r '[(.cwd // ""), (.transcript_path // ""), (.session_id // "")] | join("")' 2>/dev/null)"
    [ -n "$se_cwd" ] || se_cwd="$PWD"
    # RESIDUAL LIMITATION (found by an operator-run `/code-review high` pass on this ticket, kept as an
    # out-of-scope, honestly-named gap rather than silently claimed fixed): this session_id ONLY labels
    # the row below — the SIGNAL that row reports (se_last_mutate from $se_slog, se_wrapped from
    # $se_wd, both resolved a few lines down) is still read from state keyed by (repo,branch), not by
    # this session's own id, because an ORDINARY Bash call (docs-line/wrap-done, which write that
    # state) never sees its own session_id at all — only a hook's JSON stdin carries it (see this
    # file's own header comment). Two genuinely concurrent sessions sharing one worktree/branch can
    # still read/write each other's mutate log and wrap-done stamp, so one session's `/wrap` can, in a
    # narrow timing window, make a DIFFERENT session's row on this SAME worktree read `wrapped` under
    # its own now-distinct session id. This ticket narrows a real, measured defect (the ambiguous
    # LABEL/miscount dir #523 was filed for) — it does not close this deeper, pre-existing
    # (repo,branch)-sharing limitation, which would need session_id threaded into the ephemeral state
    # itself, not just this row.
    # Sanitize BEFORE the emptiness check that decides the fallback (found by a delta-round
    # `/code-review high` pass on the original ordering, which sanitized AFTER: a session_id made
    # entirely of tabs/newlines passed the emptiness check as "present", skipped the `_rt_key`
    # fallback, and then got stripped down to an EMPTY key — silently vanishing from the count instead
    # of degrading to the intended (repo,branch) fallback). Strip any tab/newline a future/alternate
    # harness's session_id might carry (a real Claude Code session_id is a plain UUID, never observed
    # with either — this is defensive insurance, not a reproduced bug): a stray tab would otherwise
    # shift this row's tab-delimited fields when `aggregate` reads it back positionally.
    se_key="$(printf '%s' "$se_session_id" | tr -d '\t\n')"
    [ -n "$se_key" ] || se_key="$(_rt_key "$se_cwd")"
    se_slog="$(_rt_session_log "$se_cwd")"
    # Exclusion 1 — read-only session: no mutating row at all means nothing for the fuse to flag.
    se_last_mutate="$( [ -f "$se_slog" ] && awk -F'\t' '$2=="mutate"{t=$1} END{print t}' "$se_slog" 2>/dev/null )"
    [ -n "$se_last_mutate" ] || exit 0
    # Exclusion 2 — a session FORBIDDEN to wrap by its own brief ("wrap duties are centralized"); no
    # dedicated hook field names this (confirmed against the docs — a hook gets no prompt/system-prompt
    # field), so this greps the session's own transcript for one of TWO literal markers, either of
    # which excludes it: `DELEGATION RUN` (a stateless subagent, docs/delegation.md's own line — which
    # also forbids ANY log/backlog/memory write) or `WRAP CENTRALIZED` (a real, gated managed-release
    # worker, docs/release-management.md R13 — centralized wrap ONLY, no write prohibition: R8 already
    # sanctions a worker's own pre-brief BACKLOG.md write). dir #431 found the fuse had ONLY the first
    # marker, so 18 of 18 managed-release workers in the v0.9.0 cycle — forbidden to wrap by R13, but
    # carrying no marker their brief ever emitted — were flagged `no-wrap`, a 100% false-positive rate
    # on the one cycle this ran. Reusing `DELEGATION RUN` verbatim for R13 was considered and rejected:
    # its write prohibition does not hold for R13 workers, so stretching one marker to cover both
    # conventions would misrepresent the weaker one. Both are repo-wide, test-pinned conventions, not
    # bespoke strings invented for this file — a future rewording of either worker-brief template would
    # silently break its own exclusion with no shared constant to catch it (same risk named for
    # `DELEGATION RUN` at this ticket's own original implementation, now doubled).
    # Scoped to the transcript's OPENING TURNS, NOT the whole file (found by this ticket's own
    # /code-review high pass): a bare whole-transcript grep would misclassify any ordinary session
    # that later reads/edits/discusses this very file (its own source and this comment literally
    # contain both marker strings), silently excluding it from the fuse whose entire job is catching
    # exactly a mutating session that forgot to wrap. Restricting the match to the opening turns keeps
    # the same text-convention reliance while closing the false-positive surface a later, unrelated
    # mention would otherwise open.
    #
    # dir #523 — a chip-launched worker's DENOMINATOR DEFECT: the byte-bound this used to be
    # (`head -c 8000`) assumed the marker sits in the opening bytes, but a chip-launched worker's own brief
    # (this session's own shape: a short chip prompt, then a Read/`cat` of a brief FILE whose content
    # only enters the transcript once the tool result returns) can push the marker well past any small
    # byte budget — reproduced live against THIS session's own transcript at implementation time: its
    # SECOND user-role turn (the brief's full content, returned as a tool_result) does not start until
    # ~258,000 bytes in, over 32x the old 8000-byte window, because Claude-Code-internal bookkeeping
    # records (queue-operations, hook-status attachments) sit between turns and are individually large.
    # A bigger byte budget doesn't fix this in principle — nothing bounds how much bookkeeping noise
    # can sit between two turns — so this switches the unit entirely: count TURNS (JSONL records with
    # `.type=="user"`, which covers both literal chat turns and tool-result turns — a brief-file read
    # returns as one), not bytes. se_marker_turns caps how many such turns are scanned (N=5, this
    # ticket's own lead: the chip prompt, the brief read, and the worker's first report, with margin);
    # se_marker_bytecap is the one remaining outer ceiling, read before the turn scan even starts (an
    # earlier draft ALSO capped raw LINES read — found redundant with this byte cap by an operator-run
    # `/code-review high` pass and dropped: bytes alone already bound total work regardless of line
    # count, and a separate line cap only added a second place the scan could give up too early).
    #
    # ONE JQ CALL PER LINE, not one jq call over the whole capped prefix (found live by that same
    # `/code-review high` pass, reproduced with `jq`'s own stream semantics): jq aborts its ENTIRE
    # stream — discarding output it already produced for earlier, valid lines — on the FIRST malformed
    # or truncated JSON line it meets (confirmed live: `jq -r 'select(...)' ` fed
    # `{valid}\nnot json\n{valid, marker here}` prints only the first line's result, exits 5, and NEVER
    # reaches the third line, marker included). A single-call pipeline over many lines is one bad line
    # away from silently defeating this whole exclusion — exactly the class of bug this ticket exists to
    # close, just moved to a new trigger: any race reading a still-flushing transcript, or the byte cap
    # above itself truncating mid-object on its own last line. Feeding one line at a time means a bad
    # line's parse failure is contained to that one line (empty output, skipped) and never poisons any
    # other line's result — the byte cap's own truncated tail line degrades the same safe way.
    # `.message.content | tojson`, not `.text`/`.content` field-picking: a turn's content can be a
    # plain string (an ordinary chat turn) or an array of blocks (a tool-result turn, `{type,
    # tool_use_id, content}` in this session's own transcript) — serializing whichever shape back to
    # text preserves the marker substring either way without hand-modeling both block shapes.
    #
    # A CHEAP `grep` PRE-FILTER, not a bare per-line jq loop over the whole byte-capped prefix (found
    # live by a delta-round `/code-review high` pass, on the per-line loop this ticket's OWN prior
    # round introduced to fix the jq-fail-fast bug above): forking one `jq` process per RAW line is
    # only cheap when few raw lines precede the 5th user turn — this session's own transcript needed
    # ~33. A transcript with many small non-`user` bookkeeping records between turns (queue-operations,
    # hook-status attachments — the exact shape this file's own comments already name) pays one fork
    # per such record. Reproduced live, twice, independently: a synthetic 20,000-line noise transcript
    # (~1.1MB, comfortably under the byte cap) took 89-112 SECONDS through a bare per-line loop, vs.
    # 0.039 seconds once pre-filtered first — a SessionEnd hook blocking that long is indistinguishable
    # from the hang dir #523 exists to stop, just relocated to a new trigger. `grep -F '"type":"user"'`
    # is one single pass over the whole byte-capped prefix (no per-line fork) that shrinks the candidate
    # set down to lines that COULD be a user turn before any `jq` runs at all; genuine Claude Code JSONL
    # is compact (no space after `:`, confirmed against this session's own live transcript), so this
    # literal substring match is exact for a real `"type":"user"` field regardless of where it sits
    # among a record's other fields. A false-positive match (the substring appearing inside a turn's own
    # CONTENT rather than as the record's own type field — e.g. a turn quoting this very file) still
    # gets filtered correctly by the `jq` call that follows; it only costs one wasted fork, not a wrong
    # exclusion. A transcript in some future, non-compact serialization would silently lose this
    # pre-filter's benefit (falling back to scanning every line again) rather than crash — a residual
    # limit, not a new failure mode, and named here rather than left implicit.
    se_marker_turns=5
    se_marker_bytecap=2000000
    se_marker_hit=0
    if [ -n "$se_transcript" ] && [ -f "$se_transcript" ]; then
      se_marker_seen=0
      while [ "$se_marker_seen" -lt "$se_marker_turns" ] && IFS= read -r se_marker_line; do
        se_marker_content="$(printf '%s' "$se_marker_line" | jq -r 'select(.type=="user") | .message.content | tojson' 2>/dev/null)"
        [ -n "$se_marker_content" ] || continue
        se_marker_seen=$((se_marker_seen + 1))
        if printf '%s' "$se_marker_content" | grep -qE "DELEGATION RUN|WRAP CENTRALIZED"; then
          se_marker_hit=1
          break
        fi
      done < <(head -c "$se_marker_bytecap" "$se_transcript" 2>/dev/null | grep -F '"type":"user"')
    fi
    if [ "$se_marker_hit" -eq 1 ]; then
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
    # se_wlog is empty when no persistent-store root resolves (no HOME/KEEL_HOME/
    # KEEL_READ_TRACE_STORE) — a silent skip of the whole persistent-tier write, never a fallback mkdir
    # at "." or a write to an empty filename (dir #387 V3: the latter is an ambiguous-redirect error,
    # which breaks this hook's SILENT contract same as the junk mkdir does). A guard clause, matching
    # this case's own earlier exclusion checks, rather than wrapping the rest of the branch in an `if`
    # (found by this ticket's own /simplify pass).
    se_wlog="$(_rt_wrapfuse_log "$se_cwd")"
    [ -n "$se_wlog" ] || exit 0
    mkdir -p "$(dirname "$se_wlog")"
    # _rt_wrapfuse_flag already resolves its own dir via _rt_wrapfuse_flag_dir internally and fails
    # exactly when that resolve fails, so checking se_flag alone covers the same empty-root case
    # without a redundant separate resolve of the same directory — resolved ONCE here rather than once
    # per branch, since both branches need the identical value (found by this ticket's own
    # /code-review high pass).
    se_flag="$(_rt_wrapfuse_flag "$se_cwd")"
    se_status=wrapped; [ "$se_wrapped" -eq 1 ] || se_status=no-wrap
    # dir #523: the row's identifying column is the SESSION id, not `_rt_key` (repo,branch) — a
    # worktree/branch reused across two DIFFERENT sessions used to write the SAME label for both,
    # reading (to a human, or to any future by-key grouping) as one session flagged twice rather than
    # two sessions each flagged once. Fallback to `_rt_key` only when the hook payload carries no
    # session_id at all (an older Claude Code build, or a synthetic/manual invocation) — the best
    # available degrade, matching the pre-#523 behavior for exactly that case. A PLAIN append, same as
    # before: `aggregate` (below) is where the dedup-by-key actually happens, at READ time against a
    # static snapshot — not here, which would need a read-modify-write race this concurrently-written
    # store cannot safely take (see aggregate's own comment).
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$se_status" "$se_key" >> "$se_wlog" 2>/dev/null
    if [ "$se_wrapped" -eq 1 ]; then
      [ -n "$se_flag" ] && rm -f "$se_flag" 2>/dev/null
    elif [ -n "$se_flag" ]; then
      mkdir -p "$(dirname "$se_flag")"
      printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$se_cwd" > "$se_flag" 2>/dev/null
    fi
    exit 0
    ;;

  docs-line)
    # Shell helper (dir #387 ECONOMICS requirement (2)): /wrap and /polish call this instead of
    # reading tools/read-trace.sh's own log — its short output is the only part of the log that may
    # ever enter a context.
    #
    # --wrap (dir #523), FIRST if given (`docs-line --wrap [dir]` — commands/wrap.md's only call shape
    # is `docs-line --wrap`, no dir; an earlier draft parsed either position, but nothing calls it that
    # way — /simplify found the flag-last support and its dedicated test existed for no real caller):
    # stamps the wrap-completion marker as a SIDE EFFECT of this same call, before printing the report
    # line. commands/wrap.md's own persist step already calls docs-line for its report line — folding
    # the stamp into that SAME call removes the separate `wrap-done` step this ticket's own evidence
    # found gets dropped (the wrap-fuse read 0-2 `wrapped` rows across cycles that demonstrably
    # persisted): there is no longer a second, model-remembered instruction to skip. Gated on this flag
    # rather than firing unconditionally — /polish calls plain `docs-line` (no --wrap) for its PR body,
    # and must never stamp a wrap that didn't happen.
    # --wrap must come FIRST (`docs-line --wrap [dir]`), matching commands/wrap.md's own only call
    # shape (`docs-line --wrap`, no dir) — /simplify found the original either-position parser had no
    # real caller for the flag-last shape, just a test exercising flexibility nothing shipped needs.
    if [ "${2:-}" = "--wrap" ]; then dl_dir="${3:-.}"; _rt_stamp_wrap_done "$dl_dir"; else dl_dir="${2:-.}"; fi
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
    # Standalone fallback (dir #523's shape (c)): commands/wrap.md no longer calls this directly (it
    # folds the same stamp into `docs-line --wrap`, above), but this subcommand stays for a manual
    # stamp or a composing wrapper that hasn't picked up the fold yet.
    wd_dir="${2:-.}"
    _rt_stamp_wrap_done "$wd_dir"
    printf 'read-trace: wrap completion recorded for %s\n' "$(_rt_key "$wd_dir")"
    exit 0
    ;;

  aggregate)
    ag_dir="${2:-.}"
    ag_rlog="$(_rt_reads_log "$ag_dir")"
    printf '| doc | last read | reads | surface changes since |\n'
    printf '| --- | --- | --- | --- |\n'
    if [ -f "$ag_rlog" ]; then
      # Resolved ONCE, not once per doc row (it never varies across paths in the same $ag_dir) —
      # found by this ticket's own /simplify efficiency pass.
      ag_is_repo=0
      git -C "$ag_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ag_is_repo=1
      # ONE awk pass builds last-read-date + count per path (was: an enumerate-paths scan, then 2 more
      # full-file scans PER path) — found by this ticket's own /code-review high pass.
      ag_summary="$(awk -F'\t' '$2=="read"{last[$3]=$1; cnt[$3]++} END{for (p in last) printf "%s\t%s\t%s\n", p, last[p], cnt[p]}' "$ag_rlog" 2>/dev/null | LC_ALL=C sort)"
      while IFS=$'\t' read -r ag_p ag_last ag_cnt; do
        [ -n "$ag_p" ] || continue
        ag_chg="-"
        if [ "$ag_p" != "BACKLOG.md" ] && [ "$ag_is_repo" -eq 1 ]; then
          ag_since="${ag_last%%T*}"
          ag_chg="$(git -C "$ag_dir" log --oneline --since="$ag_since" -- "$ag_p" 2>/dev/null | grep -c .)"
        fi
        printf '| %s | %s | %s | %s |\n' "$ag_p" "${ag_last:-never}" "$ag_cnt" "$ag_chg"
      done <<<"$ag_summary"
    fi
    ag_wlog="$(_rt_wrapfuse_log "$ag_dir")"
    if [ -f "$ag_wlog" ]; then
      # dir #523: M and N count DISTINCT rows-by-key (session id, since session-end above now keys
      # each row that way), not raw lines — keeping only the LAST status seen for a given key, since
      # the log is append-only and chronological. This is where the actual dedup happens, not the
      # write side: a static read-time pass over an already-written snapshot carries no
      # concurrent-writer race, unlike a read-modify-write at session-end would (see that hook's own
      # comment). Without this, a session whose SessionEnd fires more than once (a known hook-firing
      # quirk) inflates M past the number of sessions that actually ran.
      #
      # LEGACY-KEY ESCAPE HATCH (found live by an operator-run `/code-review high` pass — a real,
      # present concern, not hypothetical: this machine's OWN store already holds rows written before
      # this ticket): a row written by the pre-#523 code is keyed by `_rt_key` (repo,branch) — a
      # format hard-coded as `<project-id>__<branch-slug>`, ALWAYS containing a literal `__`. Every
      # real session on that (repo,branch) wrote that exact SAME key before this ticket, so
      # deduping those rows by key the same way a real per-session id is deduped would silently
      # collapse an entire pre-#523 history of distinct sessions down to just its LAST recorded status
      # — not a migration nicety, a live undercounting bug on the very first `aggregate` run after this
      # ships (and `rotate` is manual, never auto-run — this file's own header — so old rows are not
      # cleared away first). A `__`-shaped key is therefore counted as a RAW ROW (old behavior,
      # preserved exactly), never deduped. session-end's own fallback (no `session_id` in the hook
      # payload — an older Claude Code build, or a synthetic call) resolves `se_key` to that SAME
      # `_rt_key` shape, so it ALSO lands on the `__`-shaped, raw-row path — never wrongly collapsed
      # with a genuinely different session that also lacked a `session_id`, the ambiguity a real
      # (non-`__`) session id key exists to remove. Only a real, non-`__` session id key dedupes.
      # `NF>=3 && $3!=""` also drops a blank/malformed row (a race with a concurrent `rotate`, or any
      # non-atomic partial append) rather than counting it as a phantom session with an empty key.
      IFS=$'\t' read -r ag_nowrap ag_total <<<"$(awk -F'\t' '
        NF>=3 && $3!="" {
          if ($3 ~ /__/) { total++; if ($2=="no-wrap") nowrap++ }
          else { last[$3]=$2 }
        }
        END {
          for (k in last) { total++; if (last[k]=="no-wrap") nowrap++ }
          print (nowrap+0)"\t"(total+0)
        }' "$ag_wlog" 2>/dev/null)"
      ag_since="$(awk -F'\t' 'NR==1{print $1}' "$ag_wlog" 2>/dev/null)"
      printf 'wrap-fuse: %s of %s mutating sessions this cycle ended with no /wrap (cycle since %s)\n' \
        "${ag_nowrap:-0}" "${ag_total:-0}" "${ag_since:-n/a}"
    else
      printf 'wrap-fuse: 0 of 0 mutating sessions this cycle ended with no /wrap (cycle since n/a)\n'
    fi
    # The one canonical coverage/denominator disclosure (dir #430 + dir #431) — printed always, not
    # only when a table row or wrap-fuse event exists, so a fresh/empty aggregate reads as "coverage
    # is limited" rather than as an unqualified "nothing happened" (dir #430's own finding: 36 of 42
    # tracked docs showed a zero read count this cycle, which is exactly the reading this line exists
    # to correct).
    _rt_coverage_note
    exit 0
    ;;

  rotate)
    ro_dir="${2:-.}"
    # Same empty-root guard as session-end's persistent-tier writes (dir #387 V3) — without it, an
    # unresolved store root reaches `$ro_store/$ro_f` as a bare "/reads.log"-shaped path at filesystem
    # root (found by this ticket's own /simplify altitude pass: every OTHER _rt_store_dir-derived call
    # site in this file already guards this, `rotate` was the one left over). Unlike the silent hooks,
    # `rotate` is an operator-invoked CLI, so it reports the failure instead of silently no-op'ing.
    ro_store="$(_rt_store_dir "$ro_dir")" || {
      printf 'read-trace: no persistent store resolves (set HOME, KEEL_HOME, or KEEL_READ_TRACE_STORE) — nothing to rotate\n' >&2
      exit 1
    }
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
