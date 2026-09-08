#!/usr/bin/env bash
# tools/token-report.sh — dir #314's FIRST SLICE: `keel tokens`, a read-only, human-after-the-fact
# report answering "where did my tokens go, and what should I do about it" for a project or a single
# session. It diagnoses three patterns (fan-out, cold resumes, repeated reads) rather than only
# totalling (SPEC §2-§3) — a number is not advice.
#
# Every actual parsing/dedup call routes through tools/lib/transcript-usage.sh (dir #313); this script
# never re-derives the requestId dedupe or the subagent-file discovery. SPEC §6's own words: "That
# split is right ... it exists so the dedupe bug cannot be reintroduced by a second implementation."
#
# Adapter, not core (SPEC §5): the transcript format is Claude-Code-specific. On a machine with no
# Claude Code transcripts at all, this just reports an empty corpus rather than failing — see R3 below.
#
# Seven refusals this tool holds to (SPEC §4), summarized here, spelled out in docs/token-economy.md:
#   R1 tokens, never USD — no API key exists on a subscription; the weighted column is a labelled RULER.
#   R2 no context-composition claim — the transcript carries no system prompt/tool defs/MCP schemas.
#   R3 Claude Code only — an empty/unavailable report elsewhere, never a silently-empty-looking success.
#   R4 needs a kept checkout — install.sh's own ephemeral-bootstrap disclaimer already says so (F9).
#   R5 never ranks a session as good or bad — patterns are named, never scored.
#   R6 the cold-resume line is a labelled HEURISTIC, not a fact (SPEC F6: a quarter of "cold" events
#      are compactions/`/clear`, not pauses) — the report prints the rule, not only a percentage.
#   R7 fan-out attribution stops at the session — it cannot say a subagent fan-out was "worth it".
#
# Usage:
#   token-report.sh                        this project (cwd -> repo top), every session on disk
#   token-report.sh --session UUID|FILE    one session (+ its own subagents)
#   token-report.sh --since YYYY-MM-DD     sessions with >=1 turn on/after DATE (whole sessions, not a
#                                           partial-session slice — a session straddling the cutoff is
#                                           counted in full)
#   token-report.sh --json                 machine-readable, combinable with the above (the
#                                           statusline's future entry point, SPEC §7.1 — deferred, not
#                                           built here)
#
# Env overrides (SPEC §5, matching KEEL_IMPACT_STORE's shape — required for test isolation so this
# tool's own test file never touches the real ~/.claude/projects/):
#   KEEL_TOKENS_PROJECTS_DIR   overrides WHERE this reads transcripts from (tu_projects_root's own
#                              root) — a one-function override of the lib's own seam, never a second
#                              parser: every actual read below still goes through the unmodified lib.
#   KEEL_TOKENS_WEIGHTS        "input,write,read" — overrides the default comparison vector
#                              1.0,2.0,0.1 (SPEC §3); a malformed value is ignored with a warning
#                              rather than silently corrupting every downstream figure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/transcript-usage.sh
. "$SCRIPT_DIR/lib/transcript-usage.sh"

if [ -n "${KEEL_TOKENS_PROJECTS_DIR:-}" ]; then
  tu_projects_root() { printf '%s' "$KEEL_TOKENS_PROJECTS_DIR"; }
fi

_TR_W_INPUT=1.0
_TR_W_WRITE=2.0
_TR_W_READ=0.1
if [ -n "${KEEL_TOKENS_WEIGHTS:-}" ]; then
  IFS=',' read -r _tr_wi _tr_ww _tr_wr <<<"$KEEL_TOKENS_WEIGHTS"
  if [[ "$_tr_wi" =~ ^[0-9]+(\.[0-9]+)?$ && "$_tr_ww" =~ ^[0-9]+(\.[0-9]+)?$ && "$_tr_wr" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    _TR_W_INPUT="$_tr_wi"; _TR_W_WRITE="$_tr_ww"; _TR_W_READ="$_tr_wr"
  else
    printf 'token-report.sh: KEEL_TOKENS_WEIGHTS malformed (want input,write,read numbers) — using defaults 1.0,2.0,0.1\n' >&2
  fi
fi

usage() {
  cat <<'EOF'
token-report.sh — where your tokens went, and what to do about it (dir #314). Dispatched as `keel tokens`.

Usage:
  token-report.sh                        this project, every session on disk
  token-report.sh --session UUID|FILE    one session (+ its own subagents)
  token-report.sh --since YYYY-MM-DD     sessions with a turn on/after DATE
  token-report.sh --json                 machine-readable (combinable with the above)
  token-report.sh -h | --help
EOF
}

# _tr_resolve_session ARG — ARG is a real file (used as-is), else a bare session UUID searched for
# under the (possibly overridden) transcript root: <root>/*/ARG.jsonl (worktree sessions live one
# level down — see tools/lib/transcript-usage.sh's header note on project-directory slugs). Empty
# output and non-zero status if nothing matches.
_tr_resolve_session() {
  local arg="$1" root hit
  if [ -f "$arg" ]; then printf '%s' "$arg"; return 0; fi
  root="$(tu_projects_root)"
  hit="$(find "$root" -mindepth 2 -maxdepth 2 -type f -name "$arg.jsonl" 2>/dev/null | head -1)"
  [ -n "$hit" ] || return 1
  printf '%s' "$hit"
}

# _tr_build_report FILE... — FILE... are primary session transcript paths, already resolved/filtered
# by the caller. Emits one JSON object: raw + weighted accounting, and the three diagnosed patterns
# (SPEC §3, §6). This function only aggregates what tools/lib/transcript-usage.sh already extracted —
# it never re-parses a transcript record itself.
_tr_build_report() {
  local -a files=("$@")
  local tmp_totals tmp_turns tmp_calls tmp_sc
  tmp_totals="$(mktemp)" || return 1
  tmp_turns="$(mktemp)" || { rm -f "$tmp_totals"; return 1; }
  tmp_calls="$(mktemp)" || { rm -f "$tmp_totals" "$tmp_turns"; return 1; }
  tmp_sc="$(mktemp)" || { rm -f "$tmp_totals" "$tmp_turns" "$tmp_calls"; return 1; }

  # dir #422: once all four temp files exist, every remaining exit from this function (any `return`,
  # or falling off the end) goes through this ONE cleanup instead of a rm -f repeated at each return
  # site. This alone is not sufficient (proved with a minimal harness): under `set -euo pipefail`, a
  # BARE `out="$(cmd)"` failing would abort the function via errexit WITHOUT a normal return — a
  # RETURN trap never fires on that path. In THIS script the failure is, in fact, caught today: this
  # function's only call site wraps it as `report="$(_tr_build_report ...)" || exit 1` (bottom of
  # file), and that `||` suspends errexit for this whole function's execution (POSIX/bash: a command
  # tested by && / || is exempt) — so `status=$?` below was reachable all along in the live script,
  # not dead code, contra how this ticket was filed (its own harness likely called this function
  # bare, not through that wrapped call site — the same trap this project's own memory names:
  # "a shared helper's exemption depends on whether ITS caller is &&/||-exempt"). The if-capture
  # below is kept anyway: it makes this function's own cleanup correct on its own terms, independent
  # of how any future caller happens to invoke it, rather than silently relying on that one `||`.
  trap 'rm -f "$tmp_totals" "$tmp_turns" "$tmp_calls" "$tmp_sc"' RETURN

  # Every read below is guarded rather than a bare command — the corpus is LIVE
  # (docs/token-economy.md: a self-referential run reads a session transcript it is still writing), so
  # a file changing mid-read is the ORDINARY case, not a rare one. Under this script's own
  # `set -euo pipefail`, an unguarded command failing here would abort the WHOLE multi-session report
  # (losing every already-processed session) instead of skipping the one file that changed underneath
  # it, and would skip the trailing `rm -f` cleanup, leaking the four mktemp files (code-review high
  # pass). Non-capturing guards use this function's own `CMD || { warn; continue; }` idiom (already
  # established above for the mktemp chain); `tu_session_totals` alone needs `if/else` since it
  # captures a value for its success branch.
  local f totals sf
  for f in "${files[@]:-}"; do
    [ -f "$f" ] || continue

    if totals="$(tu_session_totals "$f")"; then
      printf '%s\n' "$totals" | jq -c --arg f "$f" '. + {sessionFile:$f}' >> "$tmp_totals"
    else
      printf 'token-report.sh: could not read %s — skipped\n' "$f" >&2
      continue
    fi

    tu_turns primary "$f" | jq -c --arg f "$f" '. + {sessionFile:$f}' >> "$tmp_turns" || {
      printf 'token-report.sh: could not read turns for %s — skipped\n' "$f" >&2
      continue
    }
    tu_tool_calls primary "$f" >> "$tmp_calls" || {
      printf 'token-report.sh: could not read tool calls for %s — skipped\n' "$f" >&2
      continue
    }
    tu_self_check "$f" >> "$tmp_sc" || {
      printf 'token-report.sh: could not read self-check for %s — skipped\n' "$f" >&2
      continue
    }

    while IFS= read -r sf; do
      [ -n "$sf" ] || continue
      tu_tool_calls subagent "$sf" >> "$tmp_calls" || {
        printf 'token-report.sh: could not read tool calls for subagent %s — skipped\n' "$sf" >&2
        continue
      }
      tu_self_check "$sf" >> "$tmp_sc" || {
        printf 'token-report.sh: could not read self-check for subagent %s — skipped\n' "$sf" >&2
        continue
      }
    done < <(tu_subagent_files "$f")
  done

  local read_at out status
  read_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # dir #422: the if-capture form (not a bare `out="$(...)"` followed by `status=$?`) makes this
  # function correct standing alone, not only when called the one way it happens to be called today
  # (see the trap comment above for why the bare form was NOT actually dead in the live script — its
  # one caller's `|| exit 1` already suspended errexit here). Testing the assignment as an `if`
  # condition is the one context `set -e` exempts on its own terms, so a jq failure lands in the
  # `else` below as a genuine function return — which is what lets the RETURN trap above actually run.
  if out="$(jq -nc \
    --slurpfile T "$tmp_totals" --slurpfile TURNS "$tmp_turns" \
    --slurpfile CALLS "$tmp_calls" --slurpfile SC "$tmp_sc" \
    --argjson w_input "$_TR_W_INPUT" --argjson w_write "$_TR_W_WRITE" --argjson w_read "$_TR_W_READ" \
    --arg readAt "$read_at" '
    def sumfield(f):
      ([ $T[] | (.primary[f] // 0) ] | add // 0) + ([ $T[] | (.subagent[f] // 0) ] | add // 0);

    # turnw(o) — the weighted input-side contribution of one {input_tokens, cache_creation_input_tokens,
    # cache_read_input_tokens} object (a primary or subagent kind-total from tu_session_totals). Output
    # tokens carry no weight (R1: not a price — nothing here converts output to an input-side unit).
    def turnw(o):
      (o.input_tokens // 0) * $w_input
      + (o.cache_creation_input_tokens // 0) * $w_write
      + (o.cache_read_input_tokens // 0) * $w_read;

    # The weighted column is a labelled RULER (R1: not a price) — round it to whole pseudo-tokens for
    # display. Unrounded, a *0.1 read weight over a real multi-hundred-million-token corpus lands on an
    # un-clean float (reproduced live: 1312353102.9), which reads as a display bug even though the
    # underlying comparison is exact; nothing downstream depends on sub-token precision.
    def rnd: round;

    # sessionName — a session transcript path down to its bare uuid, for display. Defined once,
    # applied at both call sites below (fan-out worst-session, repeated-reads worst-session) instead
    # of restating the same two `sub()` calls twice.
    def sessionName: sub(".*/";"") | sub("\\.jsonl$";"");

    # pct(a; b) — a%-share, 0 when the denominator is empty (never a division by zero). Defined once,
    # applied at every share computation below (fan-out per-session, fan-out corpus-wide, cold-resume
    # corpus-wide) instead of restating the same guarded-division three times.
    def pct(a; b): if b > 0 then 100*a/b else 0 end;

    # safe_epoch — F-03 (dir #314 live-corpus premise, extended to this aggregation): the whole
    # `jq -nc` program below is ONE expression, so an unguarded `fromdateiso8601` on any single
    # turn timestamp aborts the entire report — every other session number lost with it, on an
    # input this project already decided is ordinary (commits 01977a8/a3b94f9: a transcript is
    # live, a partially-written final record is not corruption). try/catch null degrades that ONE
    # turn instead of the whole run; a non-string or non-ISO timestamp yields null, filtered out of
    # the cold-resume gap computation below rather than crashing it.
    def safe_epoch:
      if type == "string" then (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null)
      else null end;

    (sumfield("input_tokens")) as $newinput
    | (sumfield("cache_creation_input_tokens")) as $writes
    | (sumfield("cache_read_input_tokens")) as $reads
    | (sumfield("output_tokens")) as $output
    | (($newinput*$w_input) + ($writes*$w_write) + ($reads*$w_read)) as $inputSideTotal
    | (
        [ $T[] | select(.subagent != null) ]
        | map({
            sessionFile: .sessionFile,
            session: (.sessionFile | sessionName),
            agents: .subagent.files,
            subW: turnw(.subagent),
            primW: turnw(.primary)
          })
        | map(. + { sharePct: pct(.subW; .subW+.primW) })
      ) as $fanoutRows
    | ( [$fanoutRows[].subW] | add // 0 ) as $totalSubW
    | ( $fanoutRows | sort_by(-.sharePct) | first ) as $worstFanout
    | (
        # Cold-resume detection (SPEC F5/F6): PRIMARY turns only, grouped by session, sorted by
        # timestamp. A turn is "cold" iff the gap since the PREVIOUS turn in the same session is
        # >=55 minutes (F5s empirical cliff: 55-65min jumps from 11% to 82% classified cold) AND
        # this turns cache_creation exceeds its cache_read (F5s signature: a pause that outlived the
        # cache rewrites the whole context instead of reading it). R6: this is a labelled heuristic —
        # F6 found a quarter of events matching the gap alone are compactions/`/clear`, not pauses;
        # the cache_creation>cache_read clause is what the report actually gates on, not the gap alone.
        # F-03: a turn either side of a gap whose timestamp does not parse (safe_epoch -> null)
        # contributes no gap at all (`empty`, not a crash) — that one turn is excluded from cold-
        # resume detection instead of aborting every session report.
        [ $TURNS[] ]
        | group_by(.sessionFile)
        | map(
            sort_by(.timestamp) as $arr
            | [ range(1; ($arr|length))
                | ($arr[.-1].timestamp | safe_epoch) as $prev
                | ($arr[.].timestamp   | safe_epoch) as $cur
                | if $prev == null or $cur == null then empty
                  else $arr[.] + { gapMinutes: (($cur-$prev)/60) }
                  end
              ]
            | map(select(.gapMinutes >= 55 and .cache_creation_input_tokens > .cache_read_input_tokens))
          )
        | flatten
      ) as $coldEvents
    | ( [$coldEvents[].cache_creation_input_tokens] | add // 0 ) as $coldRawTokens
    | ( $coldRawTokens * $w_write ) as $coldWeighted
    | ( [$coldEvents[] | select(.gapMinutes <= 90)] | length ) as $coldBand5590
    # F-03: surfaced rather than silently absorbed — a turn whose own timestamp does not parse at
    # all (missing, or not ISO-8601) is invisible to the gap computation above (it can be neither a
    # $prev nor a $cur), so this counts it separately for the selfCheck note below.
    | ( [ $TURNS[] | select((.timestamp | safe_epoch) == null) ] | length ) as $malformedTimestamps
    # F-05: ride the F-03 degrade-per-record path — an assistant record excluded from every total
    # above because it carries no usage object (tu_self_check own comment: "should be zero; a
    # warning sign, never silently dropped") gets the same visible signal here as a malformed
    # timestamp.
    | ( [$SC[].assistant_no_usage] | add // 0 ) as $assistantNoUsage
    | (
        # Repeated-reads (SPEC F7): Read tool calls only. file_path is already normalized to
        # repo-relative form by tools/lib/transcript-usage.sh (dir #314 SPEC §6.6) — never re-derived
        # here. Corpus-wide top file counts BOTH primary and subagent reads (fan-out re-reading the
        # same file is real waste too); "worst single session" is scoped to PRIMARY calls only, since
        # a subagent tool call cannot be attributed back to one parent session file without a second
        # join this slice does not build (R7: fan-out attribution stops at the session).
        [ $CALLS[] | select(.name == "Read" and .file_path != null) ]
      ) as $reads_all
    | ( $reads_all | group_by(.file_path) | map({file: .[0].file_path, count: length}) | sort_by(-.count) ) as $topFiles
    | (
        [ $CALLS[] | select(.kind == "primary" and .name == "Read" and .file_path != null) ]
        | group_by([.file, .file_path])
        | map({
            sessionFile: .[0].file,
            session: (.[0].file | sessionName),
            file: .[0].file_path,
            count: length
          })
        | sort_by(-.count)
      ) as $worstReadRows
    | {
        readAt: $readAt,
        sessions: ($T | length),
        window: {
          start: ( [$TURNS[].timestamp] | sort | (if length>0 then first else null end) ),
          end:   ( [$TURNS[].timestamp] | sort | (if length>0 then last else null end) )
        },
        accounting: {
          new_input: $newinput,
          cache_writes: $writes,
          cache_reads: $reads,
          output: $output,
          weighted: {
            new_input: (($newinput*$w_input) | rnd),
            cache_writes: (($writes*$w_write) | rnd),
            cache_reads: (($reads*$w_read) | rnd)
          },
          input_side_total: ($inputSideTotal | rnd),
          weights: {input: $w_input, write: $w_write, read: $w_read}
        },
        patterns: {
          fanout: {
            sessionsWithFanout: ($fanoutRows | length),
            totalAgents: ( [$fanoutRows[].agents] | add // 0 ),
            sharePct: pct($totalSubW; $inputSideTotal),
            worst: $worstFanout
          },
          coldResumes: {
            events: ($coldEvents | length),
            tokens: $coldRawTokens,
            sharePct: pct($coldWeighted; $inputSideTotal),
            band55to90: $coldBand5590
          },
          repeatedReads: {
            topFile: ( $topFiles[0].file // null ),
            topCount: ( $topFiles[0].count // 0 ),
            worstSession: ( $worstReadRows[0] // null )
          }
        },
        selfCheck: {
          filesScanned: ($SC | length),
          # tu_self_check unrecognized_types is a unique-deduped list of TYPE NAMES per file (named
          # explicitly so a moved format is visible, per the lib own header) — its length is the
          # count of distinct names, not of unrecognized RECORDS. Every record in a file is exactly
          # one of assistant-with-usage / assistant-without-usage / a known other type / an
          # unrecognized type, so the true per-file unrecognized-record count is derivable
          # arithmetically from the other three counters tu_self_check already emits, with no lib
          # change needed (code-review high pass: summing unrecognized_types length undercounted a
          # file carrying many records of ONE unrecognized type down to 1).
          unrecognizedTypeRecords: (
            [$SC[] | (.total - .assistant_usage - .assistant_no_usage - .known_other)] | add // 0
          ),
          # F-03: a turn whose own timestamp could not be parsed at all — excluded from cold-resume
          # detection above rather than aborting the whole report.
          malformedTimestamps: $malformedTimestamps,
          # F-05: assistant records correctly excluded from every total above because they carry no
          # usage object, surfaced here per tu_self_check own stated invariant rather than left
          # silently invisible in both the JSON and human output.
          assistantNoUsage: $assistantNoUsage
        }
      }
  ')"; then
    printf '%s\n' "$out"
  else
    status=$?
    return "$status"
  fi
}

# _tr_print_human REPORT_JSON [LABEL] — the report shape from SPEC §3's illustrative sample: an
# accounting block, then "WHAT DRIVES IT" naming the three patterns (R5: named, never ranked
# good/bad), then a footer stating the weight vector and its ruler-not-price status (R1) plus the
# read-moment stamp (SPEC §9.5).
_tr_print_human() {
  local report="$1" label="$2"
  # jqr QUERY — every jq call below reads the same already-computed report JSON; a local function
  # (fed via a here-string, not `printf | jq`) says that once instead of restating
  # `printf '%s' "$report" | jq -r` at each of the six call sites. `round1` is prepended to every
  # query so the two call sites that need it (fan-out, cold-resumes) share one definition instead of
  # each restating it (code-review high pass).
  jqr() { jq -r "def round1: (.*10|round)/10; $1" <<<"$report"; }

  # Numbers print as plain integers, no thousands separators — locale-dependent grouping would be a
  # portability trap for no real gain here (see this project's own memory on shell/date/awk locale
  # gotchas across macOS/GNU/busybox).
  local sessions win_start win_end read_at
  IFS=$'\t' read -r sessions win_start win_end read_at < <(
    jqr '[.sessions, (.window.start // "—"), (.window.end // "—"), .readAt] | @tsv'
  )

  printf 'keel tokens — %s        %s session(s) · %s … %s (read %s)\n\n' \
    "$label" "$sessions" "$win_start" "$win_end" "$read_at"

  if [ "$sessions" -eq 0 ]; then
    printf '  no session transcripts found. keel tokens only reads Claude Code transcripts (R3) — if\n'
    printf '  you use a different harness, or have not run a session here yet, there is nothing to report.\n\n'
    return 0
  fi

  jqr '
    .accounting as $a
    | "  WHERE THE TOKENS WENT                        tokens      weighted*",
      "    new input                                 \($a.new_input)         \($a.weighted.new_input)",
      "    cache writes                          \($a.cache_writes)     \($a.weighted.cache_writes)",
      "    cache reads                        \($a.cache_reads)   \($a.weighted.cache_reads)",
      "    output                                 \($a.output)               —",
      "    ------------------------------------------------------------------",
      "    input-side total                                    \($a.input_side_total)"
  '
  printf '\n  WHAT DRIVES IT — 3 patterns\n'

  jqr '
    .patterns.fanout as $f
    | if $f.sessionsWithFanout > 0 then
        "    fan-out          \($f.sharePct | round1)% of your spend is subagent work (\($f.totalAgents) agents",
        "                     across \($f.sessionsWithFanout) session(s)). Your session transcript does not",
        "                     show this; it lives in <session>/subagents/.",
        (if $f.worst then
          "                     Worst: \($f.worst.session) — \($f.worst.agents) agent(s), \($f.worst.sharePct | round1)% of that session."
        else empty end),
        "                     (R7: this cannot say whether the fan-out was worth it — only its size.)"
      else
        "    fan-out          none of these sessions spawned a subagent."
      end
  '
  printf '\n'
  jqr '
    .patterns.coldResumes as $c
    | if $c.events > 0 then
        "    cold resumes     \($c.events) pause(s) outlived the prompt cache and re-paid for the",
        "                     whole context: \($c.tokens) tokens, \($c.sharePct | round1)% of the input-side bill.",
        "                     \($c.band55to90) of them were in the 55-90 min band — minutes, not hours,",
        "                     past the line.",
        "                     (R6: heuristic — a gap >=55min whose next turn rewrites more than it",
        "                     reads. A compaction or /clear can look the same; this cannot tell them",
        "                     apart on its own.)"
      else
        "    cold resumes     none detected (no gap >=55min followed by a context rewrite)."
      end
  '
  printf '\n'
  jqr '
    .patterns.repeatedReads as $r
    | if $r.topFile then
        "    repeated reads   \($r.topFile) was read \($r.topCount) time(s) across these sessions.",
        (if $r.worstSession then
          "                     Worst single session: \($r.worstSession.count) reads of \($r.worstSession.file)."
        else empty end)
      else
        "    repeated reads   no file was read more than once."
      end
  '
  printf '\n'
  jqr '
    .accounting.weights as $w
    | "  * weighted = a fixed comparison vector (new input \($w.input), cache write \($w.write), cache",
      "    read \($w.read)). It is NOT a price. The read ratio matches the cache-hit figure in",
      "    docs/loading-and-cost.md; the write ratio is an assumption of this tool, not independently",
      "    vendor-confirmed (SPEC §9.2). Keel reports tokens; your bill belongs to your vendor. See",
      "    docs/token-economy.md, \"What this report is, and what it is not\"."
  '
  local unrec
  unrec="$(jqr '.selfCheck.unrecognizedTypeRecords')"
  if [ "$unrec" -gt 0 ]; then
    printf '\n  note: %s record(s) across the scanned files carried a type this tool does not recognize —\n' "$unrec"
    printf '  the transcript format may have moved; figures above may undercount.\n'
  fi
  # F-03: a malformed timestamp used to abort the whole report with zero output; now it degrades
  # per-record, so say so here rather than leaving the drop invisible.
  local bad_ts
  bad_ts="$(jqr '.selfCheck.malformedTimestamps')"
  if [ "$bad_ts" -gt 0 ]; then
    printf '\n  note: %s turn(s) had a missing or non-ISO-8601 timestamp — excluded from cold-resume\n' "$bad_ts"
    printf '  detection above rather than aborting the report.\n'
  fi
  # F-05: correctly excluded from every total above (no usage object), but tu_self_check's own
  # invariant says this "should be zero; a warning sign, never silently dropped" — surface it.
  local no_usage
  no_usage="$(jqr '.selfCheck.assistantNoUsage')"
  if [ "$no_usage" -gt 0 ]; then
    printf '\n  note: %s assistant record(s) carried no usage object — excluded from the totals above.\n' "$no_usage"
  fi
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'unavailable: keel tokens needs jq\n' >&2
    exit 1
  fi

  local mode="project" session_arg="" since_arg="" as_json=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session)
        [ "$#" -ge 2 ] || { printf 'token-report.sh: --session needs a UUID or FILE\n' >&2; exit 2; }
        mode="session"; session_arg="$2"; shift 2 ;;
      --since)
        [ "$#" -ge 2 ] || { printf 'token-report.sh: --since needs a YYYY-MM-DD date\n' >&2; exit 2; }
        since_arg="$2"; shift 2 ;;
      --json) as_json=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) printf 'token-report.sh: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done

  local -a files=()
  local label

  if [ "$mode" = "session" ]; then
    local resolved
    if ! resolved="$(_tr_resolve_session "$session_arg")"; then
      printf 'token-report.sh: no session found for %s\n' "$session_arg" >&2
      exit 2
    fi
    files=("$resolved")
    label="session $(basename "$resolved" .jsonl)"
  else
    local repo_top; repo_top="$(tu_repo_top ".")"
    label="$(basename "$repo_top")"
    local sf
    while IFS= read -r sf; do
      [ -n "$sf" ] || continue
      if [ -n "$since_arg" ]; then
        # Whole-session filtering (not a partial-session slice): a session with at least one primary
        # turn on/after DATE is included in full. ISO-8601 timestamps sort lexically, so a plain
        # string prefix-compare against "YYYY-MM-DD" is exact — no date arithmetic, no portability
        # trap (this project's own memory: macOS/GNU/busybox `date` flags all disagree).
        if tu_turns primary "$sf" | jq -e --arg since "$since_arg" 'select(.timestamp >= $since)' >/dev/null 2>&1; then
          files+=("$sf")
        fi
      else
        files+=("$sf")
      fi
    done < <(tu_session_files "$repo_top")
    if [ -n "$since_arg" ]; then label="$label since $since_arg"; fi
  fi

  local report
  report="$(_tr_build_report "${files[@]:-}")" || exit 1

  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$report"
  else
    _tr_print_human "$report" "$label"
  fi
}

main "$@"
