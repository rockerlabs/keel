# shellcheck shell=bash
# tools/lib/read-trace.sh — path/key resolution and log helpers for dir #387's read-trace fuses.
# Sourced by tools/read-trace.sh (and its tests) — no shebang requirement, no `set -e` (inherits the
# caller's), same convention as tools/lib/impact-store.sh.
#
# Reuses tools/lib/impact-store.sh's ALREADY-GENERIC `_impact_resolve_top`/`impact_project_id` for the
# project-id slug instead of a third copy of that idiom (dir #26 already tracks 5 duplicates of the
# main-checkout-resolution walk across this repo's tools/ — not adding a 6th here).
#
# Two storage tiers, deliberately different lifetimes:
#   - EPHEMERAL, per (repo, branch), under $TMPDIR — one work session's own read/mutate log, reset at
#     SessionStart(startup) (`read-trace.sh startup`). Keyed by (repo, branch), not session_id: a
#     session's own Bash calls (what /wrap and /polish use to read this back) never see session_id —
#     it exists only in a hook's JSON stdin, confirmed against code.claude.com/docs/en/hooks.md at
#     this ticket's implementation — so this reuses the same (repo, branch) keying
#     tools/pre-pr-gate.sh's dir #80 sentinel already established, for the same reason: the receipt
#     writer and the receipt reader must resolve the same key from an ordinary Bash call, with no
#     hook-only field to lean on. Same accepted limitation as that sentinel: two sessions on the SAME
#     branch of the same repo share one log.
#   - PERSISTENT, external store at $KEEL_HOME/.keel/read-trace/<project-id>/ (dir #251's own
#     external-store discipline — nothing written inside a project's own working tree), accumulating
#     across sessions and releases: the tier-2 aggregator's raw material. Deliberately NOT
#     tools/keel-impact.sh's own event log — that log's EVENT_TYPES taxonomy (hold/guard/fire/hit/
#     miss/friction) is the keel-score mechanism's; read-trace rows are path-keyed, not
#     event-type-keyed, and folding one into the other would corrupt that taxonomy for no shared
#     benefit (dir #387's own resolved TO VERIFY).

# shellcheck source=tools/lib/impact-store.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/impact-store.sh"

# _rt_tmpdir — $TMPDIR with any trailing slash stripped (macOS sets it WITH one; a bare `pwd`/path
# join never emits a double slash, so an unstripped candidate would silently never match downstream
# comparisons — same fix install-pre-pr-gate.sh already applies to its own bootstrap-clone guard).
_rt_tmpdir() { local t="${TMPDIR:-/tmp}"; printf '%s' "${t%/}"; }

# _rt_project_id [DIR] [TOP] — impact_project_id's own one-line transform (physical top, '/' -> '-').
# When TOP is already known (a caller that resolved it once for another reason), pass it to skip a
# second `_impact_resolve_top` fork instead of resolving again.
#
# NOT a memoizing cache — an earlier draft of this file tried exactly that (a pair of process-global
# `_RT_TOP_CACHE_*` variables written inside a helper), and it was dead on arrival: every real call
# site here reaches this through command substitution (`x="$(...)"`), which forks a SUBSHELL, so a
# write to a global inside it never reaches the parent — the "cache" silently never hit, on every
# call, while its own comment claimed the opposite (confirmed live, /code-review high pass; this is
# the exact "dead on arrival" anti-pattern tools/lib/impact-store.sh's own header already documents
# once for `_impact_resolve_top` itself — reintroduced here one file over, ironically while explicitly
# citing that history). A cache cannot survive this file's own call shape; an explicit parameter can —
# see `log-tool` in tools/read-trace.sh, which resolves `top` exactly once per hook invocation and
# threads it through every call below instead.
_rt_project_id() {
  local dir="${1:-.}" top="${2:-}"
  [ -n "$top" ] || top="$(_impact_resolve_top "$dir")"
  printf '%s' "$top" | tr '/' '-'
}

# _rt_branch [DIR] — DIR's current branch name, slug-safe ('/' -> '-'), or "detached" for a detached
# HEAD (never legitimate on a /polish-style flow, but a read-trace fuse must still degrade to SOME
# key rather than crash a hook silently expected to never fail).
_rt_branch() {
  local dir="${1:-.}" b
  b="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$b" ] && [ "$b" != "HEAD" ] || b="detached"
  printf '%s' "$b" | tr '/' '-'
}

# _rt_key [DIR] [TOP] — the (repo, branch) key every path below is built from: <project-id>__<branch-slug>.
_rt_key() { printf '%s__%s' "$(_rt_project_id "${1:-.}" "${2:-}")" "$(_rt_branch "${1:-.}")"; }

# --- ephemeral, per-(repo,branch), $TMPDIR-resident ------------------------------------------------
_rt_session_log() { printf '%s/keel-read-trace-%s.log' "$(_rt_tmpdir)" "$(_rt_key "${1:-.}" "${2:-}")"; }
_rt_wrapdone_path() { printf '%s/keel-read-trace-wrapdone-%s' "$(_rt_tmpdir)" "$(_rt_key "${1:-.}" "${2:-}")"; }

# --- persistent external store ----------------------------------------------------------------------
# KEEL_READ_TRACE_STORE overrides the root outright (test isolation, same convention as
# KEEL_IMPACT_STORE); else $KEEL_HOME/.keel/read-trace, else $HOME/.claude/.keel/read-trace (mirrors
# impact_store_root's own fallback).
#
# Returns 1 with NO stdout when none of the three resolve — never `${HOME:?...}`. That form used to
# live here, but it expands inside a command-substitution chain (every caller below), so the `:?`
# killed only the subshell: three stderr lines leaked out (breaking this whole mechanism's SILENT
# contract — tools/read-trace.sh's own header) and, on a writable-root platform, the empty root that
# still reached `mkdir -p` downstream created a junk directory at filesystem root (found live,
# delta-audit V3, reproduced on both macOS — read-only `/`, three stderr lines, persistent row lost —
# and alpine:3.21 — writable `/`, one stderr line, row silently written to `/reads.log` instead of the
# real store). A hook whose headline contract is "silent no-op on any failure" must degrade instead:
# callers that funnel every write through _rt_plain_append (below) already no-op on an empty file
# argument, so a failed resolve here quietly drops the persistent-tier write and nothing else.
read_trace_store_root() {
  if [ -n "${KEEL_READ_TRACE_STORE:-}" ]; then printf '%s' "$KEEL_READ_TRACE_STORE"; return 0; fi
  if [ -n "${KEEL_HOME:-}" ]; then printf '%s/.keel/read-trace' "$KEEL_HOME"; return 0; fi
  if [ -n "${HOME:-}" ]; then printf '%s/.claude/.keel/read-trace' "$HOME"; return 0; fi
  return 1
}
_rt_store_dir() {
  local root
  root="$(read_trace_store_root)" || return 1
  printf '%s/%s' "$root" "$(_rt_project_id "${1:-.}" "${2:-}")"
}
# _rt_store_path DIR TOP NAME — _rt_store_dir plus a NAME suffix, propagating an unresolved store root
# as an EMPTY string (never a bare "/reads.log"-shaped path) — a plain `"$(_rt_store_dir ...)"`
# concatenation would silently keep the leading "/" from an empty substitution even though the inner
# call failed, since a failing subshell's exit status is invisible to the string it produced (dir #387
# V3: this is exactly how a junk directory got created at filesystem root). `local d; d="$(...)" ||
# return 1` makes the failure visible before it's built into a path — shared here once rather than
# repeated at each of the three call sites below (found by this ticket's own /simplify pass).
_rt_store_path() { local d; d="$(_rt_store_dir "${1:-.}" "${2:-}")" || return 1; printf '%s/%s' "$d" "$3"; }
_rt_reads_log() { _rt_store_path "${1:-.}" "${2:-}" reads.log; }
_rt_wrapfuse_log() { _rt_store_path "${1:-.}" "${2:-}" wrap-fuse-events.log; }
_rt_wrapfuse_flag_dir() { _rt_store_path "${1:-.}" "${2:-}" wrap-fuse; }
_rt_wrapfuse_flag() { local d; d="$(_rt_wrapfuse_flag_dir "${1:-.}" "${2:-}")" || return 1; printf '%s/%s.flag' "$d" "$(_rt_branch "${1:-.}")"; }

# _rt_normalize_path DIR RAW [TOP] — a repo-relative path for logging, or the literal token "BACKLOG.md" for
# a main-checkout ticket-body read: that file is gitignored and main-checkout-only, so "repo-relative"
# is undefined for exactly that surface (dir #387's own note) — a canonical single token stands in for
# whichever physical path a worktree session read it through, so the same doc reads the same across
# every worktree of the repo. Falls back to RAW unchanged (minus a leading "./") when it resolves
# outside the repo's main-checkout top — an out-of-scope read the caller filters, not this function.
#
# macOS symlink trap (reproduced live at this ticket's implementation): `_impact_resolve_top` walks
# through `git worktree list --porcelain`, which reports the PHYSICAL path (`/private/var/...` on
# macOS) — but a hook's own `cwd`/`tool_input.file_path` fields reflect whatever form the session's
# own cwd took, typically the SYMLINKED form (`/var/...`, since `/var` -> `/private/var` on macOS). A
# plain `"$top"/*` prefix match against the raw path then silently never matches there, and every read
# under it reads as "outside the repo" — reproduced live, not a hypothetical. Fixed by re-resolving
# RAW's own directory to ITS physical form (`cd ... && pwd -P`) before retrying the prefix match once.
_rt_normalize_path() {
  local dir="$1" raw="$2" top="${3:-}" base raw_dir raw_phys
  base="$(basename -- "$raw" 2>/dev/null)"
  if [ "$base" = "BACKLOG.md" ]; then printf 'BACKLOG.md'; return; fi
  [ -n "$top" ] || top="$(_impact_resolve_top "$dir")"
  case "$raw" in
    "$top"/*) printf '%s' "${raw#"$top"/}"; return ;;
  esac
  raw_dir="$(dirname -- "$raw" 2>/dev/null)"
  if [ -n "$raw_dir" ] && [ -d "$raw_dir" ]; then
    raw_phys="$(cd "$raw_dir" 2>/dev/null && pwd -P)/$base"
    case "$raw_phys" in
      "$top"/*) printf '%s' "${raw_phys#"$top"/}"; return ;;
    esac
  fi
  printf '%s' "${raw#./}"
}

# _rt_in_doc_scope PATH — tier-1/2 READ tracking is scoped to docs/*, commands/*.md, and BACKLOG.md
# (dir #387's own text) — a Read of ordinary source is out of scope for "docs read:" visibility, and
# stays untouched by this mechanism. Mutating-call tracking (the wrap-fuse's own signal) is NOT scoped
# this way — see cmd_log_tool, which calls this only for Read, never for Edit/Write/NotebookEdit.
_rt_in_doc_scope() {
  case "$1" in
    docs/*|commands/*.md|BACKLOG.md) return 0 ;;
    *) return 1 ;;
  esac
}

# _rt_plain_append FILE KIND PATH — unconditional append, no dedup against FILE's own content. The
# persistent reads.log's writer: it must accumulate one row per SESSION across its whole cross-release
# lifetime, so gating it on "does this kind+path already exist ANYWHERE in FILE" (what
# _rt_dedup_append below used to do directly) would cap a path's history at its first-ever read
# forever — every later session's fresh read of the same doc silently dropped, freezing tier-2's "last
# read" at that first date and its "reads" count at 1 (confirmed live, review round: a doc read every
# day would eventually read as dead — a false positive on the one signal this mechanism exists to
# produce). The session-scoped dedup already happened at the EPHEMERAL gate in _rt_record_read below;
# this call only ever runs once that gate has already confirmed "not yet seen this session".
_rt_plain_append() {
  local file="$1" kind="$2" path="$3" dir
  # An empty FILE means an upstream resolve failed silently (read_trace_store_root's own no-HOME
  # case) — a silent no-op here, never a fallback path: dirname("") is ".", and appending there would
  # be exactly the junk-write this guard exists to prevent (dir #387 V3).
  [ -n "$file" ] || return 0
  dir="$(dirname "$file")"
  # -d first, mkdir only on a genuine miss: this runs on every dedup-miss in log-tool's hot path (the
  # first Read of each doc, every distinct mutated path per session), and the target directory already
  # exists on every call but the very first — a `-d` test is a builtin, `dirname`+`mkdir` are forks
  # (found by this ticket's own /code-review high pass).
  [ -d "$dir" ] || mkdir -p "$dir"
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$kind" "$path" >> "$file"
}

# _rt_dedup_append FILE KIND PATH — _rt_plain_append, but only when that exact KIND+PATH pair is NOT
# already a row in FILE. Returns 0 when it wrote a new row, 1 when the row was already present — the
# ECONOMICS block's "dedups at write time, one row per path" requirement, and the gate every other
# writer below composes with to decide whether to ALSO write elsewhere (see _rt_record_read). This is
# an EPHEMERAL-log-only helper: a file that must accumulate one row per SESSION over its whole
# lifetime (the persistent reads.log) must never be deduped against its own full history this way —
# see _rt_plain_append's own comment for the incident this split fixes.
_rt_dedup_append() {
  local file="$1" kind="$2" path="$3"
  if [ -f "$file" ] && awk -F'\t' -v k="$kind" -v p="$path" '$2==k && $3==p{f=1} END{exit !f}' "$file" 2>/dev/null; then
    return 1
  fi
  _rt_plain_append "$file" "$kind" "$path"
}

# _rt_record_read DIR PATH [TOP] — the session-scoped dedup gate is the EPHEMERAL log: a path already
# seen this session is not re-appended to either log, so the persistent cross-release log gets exactly
# one fresh row per path per session (not one per Read call) — a doc opened 50 times in one session
# still contributes one row to its own cross-release history. The persistent write is a PLAIN append,
# not a dedup one — see _rt_plain_append's own comment for the cross-session data-loss bug that
# distinction fixes (confirmed live, review round, prior to this fix landing). TOP, when the caller
# already resolved it, is threaded through to _rt_session_log/_rt_reads_log to avoid a second
# `_impact_resolve_top` fork — see _rt_project_id's own comment for why a cache can't do this instead.
_rt_record_read() {
  local dir="$1" path="$2" top="${3:-}"
  _rt_dedup_append "$(_rt_session_log "$dir" "$top")" read "$path" || return 0
  _rt_plain_append "$(_rt_reads_log "$dir" "$top")" read "$path"
}

# _rt_record_mutate DIR PATH [TOP] — ephemeral-only: feeds the wrap-fuse's "did this session mutate"
# check. Not written to the persistent store — the tier-2 aggregate's per-doc table is about READS;
# the wrap-fuse's own tier-2 signal (mutating sessions that ended without a wrap) is a separate
# counter, fed by `read-trace.sh session-end`, not by this per-path log.
#
# UNCONDITIONAL append, not a dedup one — session-end's `se_last_mutate` (tools/read-trace.sh) takes
# the LAST mutate row's timestamp to decide whether wrap-done postdates it. A presence-keyed dedup
# (this used to route through _rt_dedup_append, keyed on kind+path) writes only a path's FIRST mutate
# in a session: a re-edit of an already-touched path after wrap-done then appends nothing, so
# session-end's comparison silently runs against the stale first-edit timestamp and misclassifies the
# session as wrapped (found live, delta-audit V2). Mutate rows are ephemeral, per-session, and read
# only for this timestamp — there is no reader that needs one row per distinct path, so there is
# nothing dedup was protecting here.
_rt_record_mutate() { _rt_plain_append "$(_rt_session_log "$1" "$3")" mutate "$2"; }
