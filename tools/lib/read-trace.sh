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

# _rt_branch [DIR] — DIR's current branch name, slug-safe ('/' -> '-'), or "detached" for a detached
# HEAD (never legitimate on a /polish-style flow, but a read-trace fuse must still degrade to SOME
# key rather than crash a hook silently expected to never fail).
_rt_branch() {
  local dir="${1:-.}" b
  b="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$b" ] && [ "$b" != "HEAD" ] || b="detached"
  printf '%s' "$b" | tr '/' '-'
}

# _rt_key [DIR] — the (repo, branch) key every path below is built from: <project-id>__<branch-slug>.
_rt_key() { printf '%s__%s' "$(impact_project_id "${1:-.}")" "$(_rt_branch "${1:-.}")"; }

# --- ephemeral, per-(repo,branch), $TMPDIR-resident ------------------------------------------------
_rt_session_log() { printf '%s/keel-read-trace-%s.log' "$(_rt_tmpdir)" "$(_rt_key "${1:-.}")"; }
_rt_wrapdone_path() { printf '%s/keel-read-trace-wrapdone-%s' "$(_rt_tmpdir)" "$(_rt_key "${1:-.}")"; }

# --- persistent external store ----------------------------------------------------------------------
# KEEL_READ_TRACE_STORE overrides the root outright (test isolation, same convention as
# KEEL_IMPACT_STORE); else $KEEL_HOME/.keel/read-trace (mirrors impact_store_root's own fallback).
read_trace_store_root() {
  if [ -n "${KEEL_READ_TRACE_STORE:-}" ]; then printf '%s' "$KEEL_READ_TRACE_STORE"; return; fi
  printf '%s/.keel/read-trace' "${KEEL_HOME:-${HOME:?read-trace: set HOME, or export KEEL_HOME}/.claude}"
}
_rt_store_dir() { printf '%s/%s' "$(read_trace_store_root)" "$(impact_project_id "${1:-.}")"; }
_rt_reads_log() { printf '%s/reads.log' "$(_rt_store_dir "${1:-.}")"; }
_rt_wrapfuse_log() { printf '%s/wrap-fuse-events.log' "$(_rt_store_dir "${1:-.}")"; }
_rt_wrapfuse_flag_dir() { printf '%s/wrap-fuse' "$(_rt_store_dir "${1:-.}")"; }
_rt_wrapfuse_flag() { printf '%s/%s.flag' "$(_rt_wrapfuse_flag_dir "${1:-.}")" "$(_rt_branch "${1:-.}")"; }

# _rt_normalize_path DIR RAW — a repo-relative path for logging, or the literal token "BACKLOG.md" for
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
  local dir="$1" raw="$2" top base raw_dir raw_phys
  base="$(basename -- "$raw" 2>/dev/null)"
  if [ "$base" = "BACKLOG.md" ]; then printf 'BACKLOG.md'; return; fi
  top="$(_impact_resolve_top "$dir")"
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

# _rt_dedup_append FILE KIND PATH — append "<ts>\t<KIND>\t<PATH>" unless that exact KIND+PATH pair is
# already a row in FILE. Returns 0 when it wrote a new row, 1 when the row was already present — the
# ECONOMICS block's "dedups at write time, one row per path" requirement, and the gate every other
# writer below composes with to decide whether to ALSO write elsewhere (see _rt_record_read).
_rt_dedup_append() {
  local file="$1" kind="$2" path="$3"
  if [ -f "$file" ] && awk -F'\t' -v k="$kind" -v p="$path" '$2==k && $3==p{f=1} END{exit !f}' "$file" 2>/dev/null; then
    return 1
  fi
  mkdir -p "$(dirname "$file")"
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$kind" "$path" >> "$file"
}

# _rt_record_read DIR PATH — the session-scoped dedup gate is the EPHEMERAL log: a path already seen
# this session is not re-appended to either log, so the persistent cross-release log gets exactly one
# fresh row per path per session (not one per Read call) — a doc opened 50 times in one session still
# contributes one row to its own cross-release history.
_rt_record_read() {
  local dir="$1" path="$2"
  _rt_dedup_append "$(_rt_session_log "$dir")" read "$path" || return 0
  _rt_dedup_append "$(_rt_reads_log "$dir")" read "$path" >/dev/null
}

# _rt_record_mutate DIR PATH — ephemeral-only: feeds the wrap-fuse's "did this session mutate" check.
# Not written to the persistent store — the tier-2 aggregate's per-doc table is about READS; the
# wrap-fuse's own tier-2 signal (mutating sessions that ended without a wrap) is a separate counter,
# fed by `read-trace.sh session-end`, not by this per-path log.
_rt_record_mutate() { _rt_dedup_append "$(_rt_session_log "$1")" mutate "$2" >/dev/null; }
