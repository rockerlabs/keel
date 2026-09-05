#!/usr/bin/env bash
# tools/read-trace.sh + tools/lib/read-trace.sh — dir #387's read-trace fuses. Covers: the lib's key/
# path resolution, the PostToolUse logging hook (including its ECONOMICS-mandated silence — a hook
# that prints anything is a red test per the ticket's own binding-test requirement), the docs-line
# shell helper, the wrap-done marker, the SessionEnd wrap-fuse classifier (wrapped vs no-wrap,
# including the same-second tie the tool's own comment names), its two exclusions (read-only,
# DELEGATION RUN), the SessionStart pickup/banner, and the tier-2 aggregate's pinned FORMAT (fed a
# synthetic log, per the ticket's own binding-test requirement).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

rt="$REPO_ROOT/tools/read-trace.sh"
lib="$REPO_ROOT/tools/lib/read-trace.sh"
check_file "tools/read-trace.sh exists" "$rt"
check_file "tools/lib/read-trace.sh exists" "$lib"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — read-trace hook tests skipped (log-tool/startup/session-end all need it)"
  summary; exit $?
fi

# fixture — a repo with docs/ and commands/ content, isolated TMPDIR (the ephemeral log lives there)
# and isolated KEEL_READ_TRACE_STORE (the persistent store) per case, so cases never see each other's
# state. mkrepo() prints the repo path; call rt_env() right after to point both stores at a matching
# throwaway pair.
mkrepo() {
  local d
  d="$(new_repo)"
  mkdir -p "$d/docs" "$d/commands"
  printf 'hello\n' > "$d/docs/foo.md"
  printf '# cmd\n' > "$d/commands/bar.md"
  printf 'src\n' > "$d/src.sh"
  git -C "$d" add -A
  git -C "$d" commit -q -m init
  printf '%s' "$d"
}
rt_env() {
  RT_TMPDIR="$SANDBOX/tmp.$1"; mkdir -p "$RT_TMPDIR"
  RT_STORE="$SANDBOX/store.$1"
}
read_json() { jq -n --arg cwd "$1" --arg tool "$2" --arg path "$3" '{hook_event_name:"PostToolUse", cwd:$cwd, tool_name:$tool, tool_input:{file_path:$path}}'; }
run_hook() { OUT="$(TMPDIR="$RT_TMPDIR" KEEL_READ_TRACE_STORE="$RT_STORE" bash "$rt" "$@" 2>&1)"; STATUS=$?; }
feed_hook() { local json="$1"; shift; OUT="$(printf '%s' "$json" | TMPDIR="$RT_TMPDIR" KEEL_READ_TRACE_STORE="$RT_STORE" bash "$rt" "$@" 2>&1)"; STATUS=$?; }
# session_log_of DIR — this case's ephemeral session-log path, resolved in the SAME $RT_TMPDIR the
# hooks above were fed (so the test reads exactly what the hook wrote, not the real machine's /tmp).
session_log_of() { TMPDIR="$RT_TMPDIR" bash -c ". '$lib'; _rt_session_log \"\$1\"" _ "$1"; }

# --- lib: _rt_normalize_path -------------------------------------------------------------------------
d="$(mkrepo)"; rt_env n1
run bash -c ". '$lib'; _rt_normalize_path '$d' '$d/docs/foo.md'"
check_contains "normalize: absolute path under repo -> repo-relative" "$OUT" "docs/foo.md"
run bash -c ". '$lib'; _rt_normalize_path '$d' '/somewhere/else/BACKLOG.md'"
check_contains "normalize: any BACKLOG.md path -> the literal canonical token" "$OUT" "BACKLOG.md"
check_status "normalize: BACKLOG.md token is exactly that (no path prefix leaks in)" "BACKLOG.md" "$OUT"

# --- lib: _rt_in_doc_scope ----------------------------------------------------------------------------
# A bare commands/<name>.md-shaped literal here would false-GAP tools/self/doctor.sh's own dead-
# reference scan (it reads it as a real top-level doc link, not a fixture) — built from two joined
# parts instead, same discipline this repo's own memory names for illustrative paths.
cmd_md_path="commands/""bar.md"
run bash -c ". '$lib'; _rt_in_doc_scope 'docs/foo.md'"; check_status "doc-scope: docs/* is in scope" 0 "$STATUS"
run bash -c ". '$lib'; _rt_in_doc_scope '$cmd_md_path'"; check_status "doc-scope: commands/*.md is in scope" 0 "$STATUS"
run bash -c ". '$lib'; _rt_in_doc_scope 'BACKLOG.md'"; check_status "doc-scope: BACKLOG.md is in scope" 0 "$STATUS"
run bash -c ". '$lib'; _rt_in_doc_scope 'src.sh'"; check_status "doc-scope: ordinary source is OUT of scope" 1 "$STATUS"

# --- lib: _rt_project_id — with and without a pre-resolved TOP must agree ------------------------------
# Regression pin: an earlier draft cached _rt_resolve_top_cached's result in a process-global, which
# never actually cached anything (every real call goes through command substitution, forking a
# subshell whose writes never reach the parent) — replaced with an explicit optional TOP parameter
# instead. This pins that the explicit-TOP path produces the SAME id as the resolve-fresh path, so a
# caller threading a pre-resolved top through (log-tool's hot path) never diverges from one that doesn't.
d="$(mkrepo)"
run bash -c ". '$lib'; _rt_project_id '$d'"
default_id="$OUT"
run bash -c ". '$lib'; top=\"\$(_impact_resolve_top '$d')\"; _rt_project_id '$d' \"\$top\""
check_status "_rt_project_id with an explicit TOP agrees with resolve-fresh" "$default_id" "$OUT"

# --- log-tool: SILENCE (ECONOMICS requirement (1) — a printing hook is a red test) --------------------
d="$(mkrepo)"; rt_env silence
json="$(read_json "$d" Read "$d/docs/foo.md")"
feed_hook "$json" log-tool
check_status "log-tool(Read, in-scope) exits 0" 0 "$STATUS"
check_status "log-tool NEVER prints anything, even on a real logged read (ECONOMICS #1)" "" "$OUT"
json2="$(read_json "$d" Edit "$d/src.sh")"
feed_hook "$json2" log-tool
check_status "log-tool(Edit) exits 0" 0 "$STATUS"
check_status "log-tool(Edit) is also silent" "" "$OUT"
feed_hook "not valid json at all" log-tool
check_status "log-tool on unparseable stdin still exits 0 (never a false signal)" 0 "$STATUS"
check_status "log-tool on unparseable stdin is still silent" "" "$OUT"

# --- log-tool: doc-scope filtering on READ, no filtering on mutate -------------------------------------
d="$(mkrepo)"; rt_env scope
feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool
feed_hook "$(read_json "$d" Read "$d/src.sh")" log-tool
slog="$(session_log_of "$d")"
check_contains "in-scope Read (docs/foo.md) is logged" "$(cat "$slog" 2>/dev/null)" "docs/foo.md"
check_absent "out-of-scope Read (src.sh) is NOT logged" "$(cat "$slog" 2>/dev/null)" "src.sh"
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
check_contains "a mutate row IS logged regardless of doc-scope (src.sh)" "$(cat "$slog" 2>/dev/null)" $'mutate\tsrc.sh'

# --- log-tool: dedup at write time — one row per path, not per call -----------------------------------
d="$(mkrepo)"; rt_env dedup
for _ in 1 2 3; do feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool; done
n="$(grep -c . "$(session_log_of "$d")" 2>/dev/null || printf '0')"
check_status "3 identical reads -> exactly 1 row in the session log" 1 "$n"
n2="$(grep -c . "$RT_STORE"/*/reads.log 2>/dev/null || echo 0)"
check_status "3 identical reads -> exactly 1 row in the PERSISTENT reads.log too" 1 "$n2"

# --- CROSS-SESSION regression: the persistent log must NOT dedup across sessions ----------------------
# Confirmed live (manager review round, before this fix landed): _rt_record_read used to gate the
# PERSISTENT reads.log write with the same dedup helper as the ephemeral one, which checks "does this
# kind+path exist ANYWHERE in the file" — after the first-ever read of a path, every LATER session's
# fresh read of that same path was silently dropped, freezing tier-2's "last read" at the first date
# forever and "reads" at 1. The single-session dedup test above alone stays green under that bug (it
# never simulates a second session), which is exactly why this second case exists.
d="$(mkrepo)"; rt_env crosssession
feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool
first_ts="$(awk -F'\t' '{print $1}' "$RT_STORE"/*/reads.log 2>/dev/null)"
# Simulate the next session the same way the real SessionStart(startup) hook does: it resets THIS
# (repo,branch)'s ephemeral log, which is the dedup gate _rt_record_read reads.
feed_hook "$(jq -n --arg cwd "$d" '{hook_event_name:"SessionStart", cwd:$cwd}')" startup
feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool
n3="$(grep -c . "$RT_STORE"/*/reads.log 2>/dev/null || printf '0')"
check_status "the SAME path read in a SECOND session -> 2 rows total in the persistent log, not 1" 2 "$n3"
last_ts="$(awk -F'\t' 'END{print $1}' "$RT_STORE"/*/reads.log 2>/dev/null)"
# Not-strictly-less-than, not strictly-greater-than: the two writes can legitimately land in the same
# UTC second (1-second timestamp resolution) — same tie-tolerant comparison as read-trace.sh's own
# wrap-fuse classifier uses, for the same reason.
check_status "the second session's row is at or after the first (never earlier)" 1 "$( ! [[ "$last_ts" < "$first_ts" ]] && printf 1 || printf 0 )"
run_hook aggregate "$d"
check_contains "aggregate now reports reads=2 for the doc, not frozen at 1" "$OUT" "| docs/foo.md | $last_ts | 2 |"

# --- docs-line: format + "none" -------------------------------------------------------------------
d="$(mkrepo)"; rt_env docsline
run_hook docs-line "$d"
check_contains "docs-line on a fresh (no reads yet) repo says none" "$OUT" "docs read: none"
feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool
run_hook docs-line "$d"
check_contains "docs-line after one read names the path" "$OUT" "docs/foo.md"
check_contains "docs-line carries a count" "$OUT" "(1)"

# --- wrap-done: writes a marker naming this repo/branch's completion ----------------------------------
d="$(mkrepo)"; rt_env wrapdone
run_hook wrap-done "$d"
check_status "wrap-done exits 0" 0 "$STATUS"
check_contains "wrap-done confirms in its own output" "$OUT" "wrap completion recorded"

# --- session-end: read-only session (no mutate rows) -> no event, no flag -----------------------------
d="$(mkrepo)"; rt_env readonly
tp="$SANDBOX/transcript.readonly.jsonl"; printf 'nothing special\n' > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
check_status "session-end(read-only) exits 0" 0 "$STATUS"
check_status "session-end(read-only) is silent (SessionEnd stdout reaches nobody anyway)" "" "$OUT"
check_nofile "read-only session writes no wrap-fuse-events.log" "$RT_STORE"/*/wrap-fuse-events.log

# --- session-end: mutated, no wrap -> a no-wrap event + a pending flag --------------------------------
d="$(mkrepo)"; rt_env nowrap
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
tp="$SANDBOX/transcript.nowrap.jsonl"; printf 'ordinary session\n' > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
check_contains "mutated + never wrapped -> a no-wrap row" "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" "no-wrap"
check_file "mutated + never wrapped -> a pending flag file exists" "$(find "$RT_STORE" -name '*.flag' 2>/dev/null | head -n1)"

# --- session-end: mutated, THEN wrapped (even in the same second) -> wrapped, no flag ------------------
# Regression pin: an earlier draft compared wrap-done's timestamp to the last mutation with a STRICT
# `>`, so a wrap-done landing in the same UTC second as the mutation it covers (the ordinary case —
# these two calls run back-to-back) was misclassified as unwrapped. Fixed to not-less-than.
d="$(mkrepo)"; rt_env wrapped
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
run_hook wrap-done "$d"
tp="$SANDBOX/transcript.wrapped.jsonl"; printf 'ordinary session\n' > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
check_contains "mutated then wrapped -> a wrapped row, not no-wrap" "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" "wrapped"
check_absent "mutated then wrapped -> NOT classified no-wrap" "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" "no-wrap"
check_nofile "mutated then wrapped -> no pending flag" "$(find "$RT_STORE" -name '*.flag' 2>/dev/null | head -n1 || printf '/nonexistent')"

# --- session-end: DELEGATION RUN worker is excluded even though it mutated ------------------------------
d="$(mkrepo)"; rt_env delegation
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
tp="$SANDBOX/transcript.delegation.jsonl"
printf 'YOUR TICKET: dir #999\nDELEGATION RUN: wrap duties are centralized\n' > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
check_nofile "a DELEGATION RUN worker's mutation writes no wrap-fuse-events.log" "$RT_STORE"/*/wrap-fuse-events.log

# --- session-end: an ORDINARY session that later mentions "DELEGATION RUN" (e.g. editing/discussing
# this very file) is NOT misclassified as a delegation worker ------------------------------------------
# Regression pin: an earlier draft grepped the WHOLE transcript, so any session whose later turns
# happen to contain the literal marker string (this file's own source, or a chat about this ticket)
# would be silently excluded from the fuse whose entire job is catching a forgotten /wrap. Fixed by
# scoping the match to the transcript's opening turn (where a genuine worker brief actually lives).
d="$(mkrepo)"; rt_env notdelegation
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
tp="$SANDBOX/transcript.notdelegation.jsonl"
{
  printf 'ordinary session, no delegation brief\n'
  # Pad well past the hook's own head-c byte window (8000) before the marker appears, so this
  # actually exercises the byte-bound scoping rather than trivially fitting inside it.
  yes 'padding line to push the marker past the scoped byte window' | head -n 200
  printf 'later turn: discussing read-trace.sh, which greps for the string DELEGATION RUN\n'
} > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
check_contains "an ordinary session mentioning the marker LATE is still tracked as no-wrap" \
  "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" "no-wrap"

# --- startup: resets the session log and banners+clears a pending flag ---------------------------------
d="$(mkrepo)"; rt_env startup
feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
tp="$SANDBOX/transcript.startup.jsonl"; printf 'ordinary\n' > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
feed_hook "$(jq -n --arg cwd "$d" '{hook_event_name:"SessionStart", cwd:$cwd}')" startup
check_status "startup exits 0" 0 "$STATUS"
check_contains "startup banners the pending wrap-fuse flag via systemMessage" "$OUT" "systemMessage"
check_contains "startup's banner names dir #387" "$OUT" "dir #387"
check_nofile "startup clears the flag it banners" "$(find "$RT_STORE" -name '*.flag' 2>/dev/null | head -n1 || printf '/nonexistent')"
run_hook docs-line "$d"
check_contains "startup reset the session log — docs-line is back to none" "$OUT" "docs read: none"
# a second startup with nothing pending is fully silent
feed_hook "$(jq -n --arg cwd "$d" '{hook_event_name:"SessionStart", cwd:$cwd}')" startup
check_status "startup with nothing pending is silent" "" "$OUT"

# --- aggregate: FORMAT, fed a synthetic log (this ticket's own binding-test requirement) ----------------
d="$(mkrepo)"; rt_env aggregate
mkdir -p "$RT_STORE"
agdir="$(KEEL_READ_TRACE_STORE="$RT_STORE" bash -c ". '$lib'; _rt_store_dir '$d'")"
mkdir -p "$agdir"
printf '2026-08-01T00:00:00Z\tread\tdocs/never-changes.md\n2026-08-15T00:00:00Z\tread\tdocs/foo.md\n' > "$agdir/reads.log"
printf '2026-08-01T00:00:00Z\tno-wrap\tp1\n2026-08-05T00:00:00Z\twrapped\tp1\n2026-08-10T00:00:00Z\tno-wrap\tp2\n' > "$agdir/wrap-fuse-events.log"
run_hook aggregate "$d"
check_contains "aggregate: pinned table header" "$OUT" "| doc | last read | reads | surface changes since |"
check_contains "aggregate: a row for each logged doc" "$OUT" "docs/foo.md"
check_contains "aggregate: a row for the other logged doc too" "$OUT" "docs/never-changes.md"
check_contains "aggregate: the wrap-fuse summary line, counts derived from the synthetic log (2 of 3)" "$OUT" "wrap-fuse: 2 of 3 mutating sessions this cycle ended with no /wrap"

# --- tier-3 map: DATA ONLY, every row resolves in the live tree ----------------------------------------
map="$REPO_ROOT/tools/read-trace-map.tsv"
check_file "tools/read-trace-map.tsv exists" "$map"
bad=0
# shellcheck disable=SC2034  # note is read for column-shape completeness, not used in this check
while IFS=$'\t' read -r surface doc note; do
  case "$surface" in ""|"#"*) continue ;; esac
  [ "$doc" = "BACKLOG.md" ] && continue
  [ -f "$REPO_ROOT/$doc" ] || { bad=$((bad + 1)); echo "  bad row: $surface -> $doc" >&2; }
done < "$map"
check_status "every non-BACKLOG.md required_doc in read-trace-map.tsv resolves in this repo" 0 "$bad"

summary
