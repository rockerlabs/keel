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

# --- lib: _rt_normalize_path in a WORKTREE (dir #430 regression) ---------------------------------------
# Regression pin: this used to thread the MAIN-checkout top through here, so a worktree session's own
# read of docs/foo.md normalized to ".claude/worktrees/<name>/docs/foo.md" — never matching the same
# doc's read from any other worktree (fragmenting per-doc counts) and never matching the tracked
# "docs/*" path a dead-doc report looks for. Fixed by resolving DIR's OWN top (keel_repo_own_top) for
# this call, separate from the main-checkout top the STORE KEY still uses (see the log-tool hook test
# below for the end-to-end version, including the key merge).
git -C "$d" commit --allow-empty -qm init
wt="$SANDBOX/rt-normalize-worktree"
git -C "$d" worktree add -q "$wt" -b rt-normalize-wt-branch
mkdir -p "$wt/docs"
printf 'hello\n' > "$wt/docs/foo.md"
run bash -c ". '$lib'; _rt_normalize_path '$wt' '$wt/docs/foo.md'"
check_status "normalize: a WORKTREE's own read -> repo-relative to ITS OWN top, not the main checkout" \
  "docs/foo.md" "$OUT"
check_absent "normalize: a worktree read never carries .claude/worktrees/<name>/ in the result" \
  "$OUT" ".claude/worktrees"

# --- lib: _rt_normalize_path, a worktree session reading the MAIN checkout's OWN path (secondary
# fallback, found by this ticket's own /code-review high pass) --------------------------------------
# A worktree session that reads a tracked doc via the MAIN checkout's own absolute path (rather than
# its own worktree's copy — e.g. deliberately checking the canonical committed state) used to
# normalize correctly under the pre-dir-#430 (main-top-only) behavior. The OWNTOP fix alone would
# silently regress that case to the raw absolute path, never matching (it's outside the worktree's own
# checkout) — the secondary maintop fallback below exists to keep this case working.
run bash -c ". '$lib'; _rt_normalize_path '$wt' '$d/docs/foo.md'"
check_status "normalize: a worktree session reading the MAIN checkout's own path still normalizes" \
  "docs/foo.md" "$OUT"

# --- lib: _rt_normalize_path, a SIBLING worktree's own file is NOT folded into a bare docs/* path
# (regression pin, found by a SECOND /code-review high pass on the secondary fallback above) ---------
# Every worktree of a repo physically nests under the main checkout's own top, at the real topology
# `.claude/worktrees/<name>/` — so a plain maintop prefix match also fires for a read of a DIFFERENT
# worktree's file (e.g. an orchestrator session inspecting a worker's own worktree). Stripping only
# the maintop prefix would leave `.claude/worktrees/<other-name>/docs/bar.md`, a path
# _rt_in_doc_scope never recognizes — silently dropping the read instead of tracking it, and (worse)
# risking collision with the reading worktree's own "docs/bar.md" if the sibling-worktree segment
# were ever stripped too. Nest the sibling worktree at the REAL topology (under $d/.claude/worktrees)
# so this reproduces the actual shape, not just an analogous one.
sibling_wt="$d/.claude/worktrees/rt-normalize-sibling"
mkdir -p "$(dirname "$sibling_wt")"
git -C "$d" worktree add -q "$sibling_wt" -b rt-normalize-sibling-wt-branch
mkdir -p "$sibling_wt/docs"
printf 'hello\n' > "$sibling_wt/docs/bar.md"
run bash -c ". '$lib'; _rt_normalize_path '$wt' '$sibling_wt/docs/bar.md'"
check_status "normalize: a sibling worktree's own file does NOT collapse to a bare docs/bar.md" \
  0 "$( [ "$OUT" = "docs/bar.md" ] && printf 1 || printf 0 )"
# The vulnerable (pre-fix) shape was the MAINTOP-STRIPPED relative form — falling through to the RAW
# absolute path instead (which legitimately contains ".claude/worktrees/" as real, on-disk structure)
# is the correct, safe outcome; only the stripped relative form is the regression to guard against.
check_status "normalize: a sibling worktree's own file does NOT normalize to the maintop-stripped relative form" \
  0 "$( [ "$OUT" = ".claude/worktrees/rt-normalize-sibling/docs/bar.md" ] && printf 1 || printf 0 )"
run bash -c ". '$lib'; _rt_in_doc_scope '$OUT'"
check_status "normalize: whatever the sibling-worktree read normalizes to, it reads as OUT of doc-scope (never silently tracked wrong)" \
  1 "$STATUS"

# --- lib: _rt_normalize_path, the SAME sibling-worktree guard applied when the READING session's own
# dir IS the main checkout (regression pin, found by a THIRD /code-review high pass) ------------------
# Whenever DIR's own top already equals the main-checkout top (a session running directly in the main
# checkout, not inside any worktree — the orchestrator topology dir #431's own R13 examples describe),
# a sibling worktree's file matches the PRIMARY owntop branch before the guarded fallback ever runs —
# the guard above only protected the fallback branch, missing this door entirely. Reproduces the exact
# live repro the reviewing pass used: reading DIR is $d itself (the main checkout), not a worktree.
run bash -c ". '$lib'; _rt_normalize_path '$d' '$sibling_wt/docs/bar.md'"
check_status "normalize: a MAIN-CHECKOUT session reading a sibling worktree's file does NOT collapse to a bare docs/bar.md" \
  0 "$( [ "$OUT" = "docs/bar.md" ] && printf 1 || printf 0 )"
check_status "normalize: a MAIN-CHECKOUT session reading a sibling worktree's file does NOT normalize to the stripped relative form" \
  0 "$( [ "$OUT" = ".claude/worktrees/rt-normalize-sibling/docs/bar.md" ] && printf 1 || printf 0 )"
run bash -c ". '$lib'; _rt_in_doc_scope '$OUT'"
check_status "normalize: a MAIN-CHECKOUT session's sibling-worktree read also reads as OUT of doc-scope" \
  1 "$STATUS"

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

# noenv_bash CMD... — the three-flag `env -u` prefix every "nothing resolves" case below needs,
# factored out once rather than repeated verbatim at each call site (found by this ticket's own
# /code-review high pass).
noenv_bash() { env -u HOME -u KEEL_HOME -u KEEL_READ_TRACE_STORE "$@"; }

# --- lib: read_trace_store_root degrades silently when NOTHING resolves -------------------------------
# Regression pin (delta-audit V3): this used to be `${HOME:?read-trace: set HOME, or export
# KEEL_HOME}`, which expands inside a command-substitution chain and so only killed the SUBSHELL —
# three stderr lines leaked out (breaking log-tool's own SILENT contract) and, on a writable-root
# platform, the empty root that still reached a downstream `mkdir -p` created a junk directory at
# filesystem root. This is the one env-axis the rest of this suite never exercises on its own — every
# other case sets KEEL_READ_TRACE_STORE via rt_env(), so the unset-everything branch was never entered.
noenv="$(noenv_bash bash -c ". '$lib'; read_trace_store_root" 2>"$SANDBOX/noenv.stderr")"
noenv_status=$?
check_status "read_trace_store_root with nothing set: empty stdout" "" "$noenv"
check_status "read_trace_store_root with nothing set: exit 1 (a real failure, never a fabricated path)" 1 "$noenv_status"
check_status "read_trace_store_root with nothing set: zero stderr (never a printed line)" "" "$(cat "$SANDBOX/noenv.stderr" 2>/dev/null)"

# --- log-tool: full hook stays SILENT end-to-end with no HOME/KEEL_HOME/KEEL_READ_TRACE_STORE ----------
# The mandated assertion point per the finding: the EPHEMERAL (TMPDIR) tier must keep working
# (unaffected by HOME) while the PERSISTENT tier degrades to a silent no-op — never stderr, never a
# write outside its own store.
d="$(mkrepo)"
rt_tmp_noenv="$SANDBOX/tmp.noenv"; mkdir -p "$rt_tmp_noenv"
noenv_hook_out="$(noenv_bash TMPDIR="$rt_tmp_noenv" bash -c '
  printf "%s" "$1" | bash "$2" log-tool
' _ "$(read_json "$d" Read "$d/docs/foo.md")" "$rt" 2>&1)"
noenv_hook_status=$?
check_status "log-tool with no HOME/KEEL_HOME/KEEL_READ_TRACE_STORE: exit 0" 0 "$noenv_hook_status"
check_status "log-tool with no HOME/KEEL_HOME/KEEL_READ_TRACE_STORE: stays silent (no stderr leak)" "" "$noenv_hook_out"
slog_noenv="$(TMPDIR="$rt_tmp_noenv" bash -c ". '$lib'; _rt_session_log \"\$1\"" _ "$d")"
check_contains "ephemeral session log still records the read (TMPDIR tier unaffected by HOME)" "$(cat "$slog_noenv" 2>/dev/null)" "docs/foo.md"

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

# --- log-tool END-TO-END in a WORKTREE (dir #430 regression, the measured root cause) ------------------
# The bug as filed: a worktree session's Read of docs/foo.md landed in the persistent store keyed
# under ".claude/worktrees/<name>/docs/foo.md" instead of "docs/foo.md" — fragmenting per-doc counts
# per worktree AND missing the tracked path a dead-doc report looks for. This drives the REAL hook
# (log-tool) with a worktree cwd/file_path, the same shape a live session would produce, and checks
# both halves the fix has to get right together: the STORE KEY still merges (one project id, same as
# the main checkout — dir #430's own keying decision, unchanged), while the LOGGED PATH is now
# worktree-relative.
d="$(mkrepo)"; rt_env worktree
git -C "$d" commit --allow-empty -qm init
wt="$SANDBOX/rt-logtool-worktree"
git -C "$d" worktree add -q "$wt" -b rt-logtool-wt-branch
mkdir -p "$wt/docs"
printf 'hello\n' > "$wt/docs/foo.md"
feed_hook "$(read_json "$wt" Read "$wt/docs/foo.md")" log-tool
check_contains "worktree read logs as repo-relative (docs/foo.md), not .claude/worktrees/.../docs/foo.md" \
  "$(cat "$RT_STORE"/*/reads.log 2>/dev/null)" $'\tread\tdocs/foo.md'
check_absent "worktree read never carries its own worktree subpath in the persistent log" \
  "$(cat "$RT_STORE"/*/reads.log 2>/dev/null)" ".claude/worktrees"
# The store key: a read from the WORKTREE and a read from the MAIN checkout must land in the SAME
# store directory (one project id per repo, not one per worktree) — confirms the keying decision
# (merge worktrees onto the main-repo path) held even though path normalization changed. Counting
# distinct project-id directories under the store (rather than comparing two `find | head -n1` picks,
# which would silently pass even if a second directory existed) is the real assertion here.
feed_hook "$(read_json "$d" Read "$d/docs/foo.md")" log-tool
n_store_dirs="$(find "$RT_STORE" -mindepth 1 -maxdepth 1 -type d | grep -c .)"
check_status "a worktree read and its main-checkout's own read share ONE store directory (merged key)" \
  1 "$n_store_dirs"

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

# --- session-end: SAME PATH mutated twice, straddling wrap-done -> no-wrap + flag -----------------------
# Regression pin (delta-audit V2): _rt_record_mutate used to route through the presence-keyed
# _rt_dedup_append (kind+path), so a re-edit of an already-logged path appended NOTHING — session-end's
# se_last_mutate then compared wrap-done against the FIRST edit's timestamp and silently classified the
# session as wrapped, even though the real last edit came after wrap-done. Explicit `sleep 1`s force the
# three events into distinct UTC seconds (the fuse's own timestamp resolution) so this pins the true
# ordering rather than an accidental same-second tie either fix or bug would classify identically.
d="$(mkrepo)"; rt_env straddle
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
sleep 1
run_hook wrap-done "$d"
sleep 1
feed_hook "$(read_json "$d" Edit "$d/src.sh")" log-tool
tp="$SANDBOX/transcript.straddle.jsonl"; printf 'ordinary session\n' > "$tp"
feed_hook "$(jq -n --arg cwd "$d" --arg tp "$tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
check_contains "same path re-edited AFTER wrap-done -> a no-wrap row, not wrapped" "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" "no-wrap"
check_absent "same path re-edited AFTER wrap-done -> NOT classified wrapped" "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" $'\twrapped\t'
check_file "same path re-edited AFTER wrap-done -> a pending flag file exists" "$(find "$RT_STORE" -name '*.flag' 2>/dev/null | head -n1)"

# --- session-end: the two centralized-wrap exclusion markers, parameterized (dir #431 added the
# second) --------------------------------------------------------------------------------------------
# assert_marker_excludes MARKER TAG LABEL — a mutating session whose transcript opens with MARKER
# (within the hook's own byte window) writes no wrap-fuse-events.log at all.
assert_marker_excludes() {
  local marker="$1" tag="$2" label="$3" ame_d ame_tp
  ame_d="$(mkrepo)"; rt_env "$tag"
  feed_hook "$(read_json "$ame_d" Edit "$ame_d/src.sh")" log-tool
  ame_tp="$SANDBOX/transcript.$tag.jsonl"
  printf 'YOUR TICKET: dir #999\n%s\n' "$marker" > "$ame_tp"
  feed_hook "$(jq -n --arg cwd "$ame_d" --arg tp "$ame_tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
  check_nofile "$label" "$RT_STORE"/*/wrap-fuse-events.log
}
# assert_marker_not_matched_late MARKER TAG LABEL — regression pin: an earlier draft grepped the
# WHOLE transcript, so any session whose LATER turns happen to mention the literal marker string
# (this file's own source, or a chat about this ticket) would be silently excluded from the fuse
# whose entire job is catching a forgotten /wrap. Fixed by scoping the match to the transcript's
# opening turn — this pads well past the hook's own head-c byte window (8000) before the marker
# appears, so it actually exercises the byte-bound scoping rather than trivially fitting inside it.
assert_marker_not_matched_late() {
  local marker="$1" tag="$2" label="$3" amnl_d amnl_tp
  amnl_d="$(mkrepo)"; rt_env "$tag"
  feed_hook "$(read_json "$amnl_d" Edit "$amnl_d/src.sh")" log-tool
  amnl_tp="$SANDBOX/transcript.$tag.jsonl"
  {
    printf 'ordinary session, no brief\n'
    yes 'padding line to push the marker past the scoped byte window' | head -n 200
    printf 'later turn: discussing read-trace.sh, which greps for the string %s\n' "$marker"
  } > "$amnl_tp"
  feed_hook "$(jq -n --arg cwd "$amnl_d" --arg tp "$amnl_tp" '{hook_event_name:"SessionEnd", cwd:$cwd, transcript_path:$tp}')" session-end
  check_contains "$label" "$(cat "$RT_STORE"/*/wrap-fuse-events.log 2>/dev/null)" "no-wrap"
}

assert_marker_excludes "DELEGATION RUN: wrap duties are centralized" delegation \
  "a DELEGATION RUN worker's mutation writes no wrap-fuse-events.log"
assert_marker_not_matched_late "DELEGATION RUN" notdelegation \
  "an ordinary session mentioning the marker LATE is still tracked as no-wrap"

# dir #431: a managed-release worker (docs/release-management.md R13) is forbidden to wrap by its own
# brief, exactly like a DELEGATION RUN subagent, but must NOT be matched by that marker — its write
# prohibition does not hold for an R13 worker (R8 sanctions a worker's own pre-brief BACKLOG.md
# write). This is the SECOND, weaker exclusion.
assert_marker_excludes "WRAP CENTRALIZED (R13): wrap is owned by the release manager — do not run /wrap." wrapcentralized \
  "a WRAP CENTRALIZED worker's mutation writes no wrap-fuse-events.log"
assert_marker_not_matched_late "WRAP CENTRALIZED" notwrapcentralized \
  "an ordinary session mentioning the new marker LATE is still tracked as no-wrap"

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

# --- aggregate: the coverage/denominator disclosure (dir #430 + dir #431's one output contract) --------
# Printed always (not gated on a non-empty table or wrap-fuse log), and pins the specific claims a
# reader needs: that a zero-read row is not evidence of "never opened" (dir #430's structural blind
# spot), that `reads` counts SESSIONS rather than raw Read tool calls (the resolution of the 25-vs-75
# discrepancy — the two figures measure different things, neither is wrong), and that the wrap-fuse
# denominator excludes DELEGATION RUN/WRAP CENTRALIZED sessions by design (dir #431).
check_contains "aggregate: states doc-read coverage (injected/shell surfaces never appear)" "$OUT" "coverage:"
check_contains "aggregate: names the injected-surface blind spot explicitly" "$OUT" "harness-injected surface"
check_contains "aggregate: states the reads column is SESSIONS, not raw tool calls (the 25-vs-75 resolution)" \
  "$OUT" "counts SESSIONS that read a doc at least once, not raw Read tool calls"
check_contains "aggregate: states the wrap-fuse denominator excludes centralized-wrap sessions" \
  "$OUT" "wrap-fuse denominator:"
check_contains "aggregate: names both exclusion markers in the denominator statement" "$OUT" "DELEGATION RUN"
check_contains "aggregate: names the second exclusion marker too" "$OUT" "WRAP CENTRALIZED"

# --- aggregate: the disclosure prints even with NOTHING logged (empty table, no wrap-fuse log) ---------
# A fresh/unpopulated aggregate is exactly where the "zero row = never opened" misreading bites
# hardest — the disclosure must not be conditioned on there being any data to disclose about.
d="$(mkrepo)"; rt_env aggregate_empty
run_hook aggregate "$d"
check_contains "aggregate: coverage note prints even on a totally empty aggregate" "$OUT" "coverage:"

# --- tier-3 map: DATA ONLY, every row resolves in the live tree ----------------------------------------
map="$REPO_ROOT/tools/read-trace-map.tsv"
check_file "tools/read-trace-map.tsv exists" "$map"
bad=0
bad_surface=0
# shellcheck disable=SC2034  # note is read for column-shape completeness, not used in this check
while IFS=$'\t' read -r surface doc note; do
  case "$surface" in ""|"#"*) continue ;; esac
  # BACKLOG.md exempts only the required_doc check (that literal token means "read the ticket's own
  # body", not a resolvable path) — it must NOT also skip the surface check below via the same
  # `continue`, or a future BACKLOG.md-doc row with a typo'd bare-path surface would pass silently
  # (found by this ticket's own /code-review high pass).
  if [ "$doc" != "BACKLOG.md" ]; then
    [ -f "$REPO_ROOT/$doc" ] || { bad=$((bad + 1)); echo "  bad row: $surface -> $doc" >&2; }
  fi
  # a cell containing ':' is a ticket:<STATUS> or path:label pseudo-surface, not a bare path — exempt
  case "$surface" in *:*) continue ;; esac
  [ -f "$REPO_ROOT/$surface" ] || { bad_surface=$((bad_surface + 1)); echo "  bad surface: $surface" >&2; }
done < "$map"
check_status "every non-BACKLOG.md required_doc in read-trace-map.tsv resolves in this repo" 0 "$bad"
check_status "every bare-path surface in read-trace-map.tsv resolves in this repo" 0 "$bad_surface"

summary
