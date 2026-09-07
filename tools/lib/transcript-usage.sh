# shellcheck shell=bash
# tools/lib/transcript-usage.sh — keel-self-maintenance (dir #313): the ONE shared reader for this
# machine's Claude Code session transcripts. Built so dir #313's own tools/self/session-cost.sh and
# dir #314's adopter-facing token-economy report import the SAME parsing logic instead of each
# re-deriving it — the requestId dedupe bug this file fixes (see below) is exactly the kind of
# correctness defect a second, independent implementation would silently reintroduce (dir #314 SPEC §6:
# "That split is right ... it exists so the dedupe bug cannot be reintroduced by a second
# implementation").
#
# Sourced, not executed — no shebang, no `set -e` (inherits the caller's), same convention as
# tools/lib/dir-tickets.sh.
#
# Dependency: jq only. dir #314 SPEC §8.1 struck the inherited "jq/python3" precedent after verifying
# live that zero python3 exists in this tree — the one script cited as a precedent
# (tools/pre-pr-gate.sh) uses jq, not python3.
#
# --- Schema facts, verified live against this project's own transcripts (2026-09-06), not assumed ---
# This ticket has already produced two silent-wrong-number defects from assuming the transcript schema
# instead of reading it (the requestId dedupe miss — ~1.89x inflation — and the isSidechain fan-out
# miss — ~21.6% of spend invisible). Every fact below was confirmed with `jq` against real transcripts
# before being relied on:
#
# - A record's `type` decides everything; there is no fixed enumeration to filter against. One
#   project's own transcripts alone carry 15 distinct `.type` values (assistant/user/attachment/
#   last-prompt/atis-latch/bridge-session/queue-operation/custom-title/system/pr-link/mode/
#   worktree-state/relocated/file-history-snapshot/permission-mode) — already past the "4 to 8 record
#   types" this ticket's own manager correction named as the kind of drift to expect across harness
#   versions. Select POSITIVELY on `type == "assistant"` with a present `.message.usage` (dir #314 SPEC
#   §6.1); never enumerate the rest looking for what to exclude.
# - `requestId` repeats. One API response that carries a thinking block, a text block and a tool_use
#   block is logged as 2-3 SEPARATE JSONL lines sharing one `requestId`, each stamped with the SAME
#   cumulative `usage` object but a slightly different `timestamp` (verified live: three lines 0.001s
#   and 0.47s apart, byte-identical `cache_read_input_tokens`/`cache_creation_input_tokens`/
#   `output_tokens`). Summing `usage` naively multiplies it by the occurrence count — the exact
#   ~1.89x/47% inflation dir #313's spec found. Dedupe keeps the FIRST occurrence per `requestId`
#   (earliest timestamp — and, since the values are identical across duplicates, the correct sum
#   either way) for usage sums; `tool_use` blocks are NOT deduped — every occurrence is a genuinely
#   distinct tool call, which is the whole reason one requestId spans several lines (dir #314 SPEC §6.4).
# - Subagent spend lives in SIBLING FILES the parent transcript never references:
#   `<dir>/<session-uuid>/subagents/agent-*.jsonl`, one file per subagent invocation (a `.meta.json`
#   twin next to each carries `agentType`/`description`/`spawnDepth`, never usage). Verified live:
#   `isSidechain` is `false` on every record in a PRIMARY session file — never the fan-out
#   discriminator dir #313's own first draft assumed — but `true` throughout a SUBAGENT file. The fact
#   that separates primary from fan-out is which FILE a record lives in, not a field inside it (dir
#   #314 SPEC §6.2, §8.3).
# - The harness's own project-directory slug: an absolute path with every `/` AND every `.` replaced by
#   `-` (verified live: ".../keel/.claude/worktrees/X" -> "...keel--claude-worktrees-X" — the dot in
#   ".claude" becomes a dash too, producing the double-dash a naive "replace / only" slug would miss).
#   A repo's own checkout and every one of its worktrees each get a DIFFERENT slug from this same
#   transform, sharing only the prefix up to the repo's own path — session discovery must glob
#   `<repo-slug>` AND `<repo-slug>--claude-worktrees-*`, never just the one directory a naive reading of
#   "the project's transcripts" would open (this is the "worktree-prefix globbing" item folded into dir
#   #314's body from the old token-tracing ticket, #2235).
# - `tool_use.input.file_path` (Edit/Read/Write) is the session's own absolute path
#   (".../keel/.claude/worktrees/go-284-ba08e3/docs/reference.md"), which makes the SAME logical file
#   look like a different key from every worktree it was ever touched from. Each record's own `.cwd` is
#   that session's root, so stripping `.cwd` (when the path starts with it) yields the repo-relative
#   form ("docs/reference.md") uniformly whether the session ran in a worktree OR the main checkout — a
#   path outside the session's own `cwd` (a memory file, a KB doc) is left absolute (dir #314 SPEC §6.6).
#
# --- What this file does NOT read ------------------------------------------------------------------
# No tool definitions, no system prompt, no MCP schemas, no memory-file or skill content — dir #313's
# own body confirmed the transcripts never carry those. Context-composition questions ("83 MCP tools
# cost you 36.6k every turn") are not answerable from here; only the app's own context panel shows that.

# dir #415: tu_repo_top (below) delegates to tools/lib/repo-top.sh's keel_repo_top instead of carrying
# its own copy of the main-checkout-resolution chain — see that function's own comment for why.
# shellcheck source=tools/lib/repo-top.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repo-top.sh"

# tu_projects_root — where this machine keeps Claude Code transcripts. Reuses $KEEL_HOME exactly the
# way tools/lib/impact-store.sh's impact_store_root already does for "$HOME/.claude" resolution,
# instead of inventing a second override for the same thing — a caller running under tests/lib.sh's
# sandboxed $HOME never touches the operator's real transcripts without needing a THIRD env var for it.
tu_projects_root() {
  printf '%s/projects' "${KEEL_HOME:-${HOME:?transcript-usage: set HOME, or export KEEL_HOME}/.claude}"
}

# tu_project_slug DIR — DIR's absolute path with every '/' and '.' replaced by '-', matching the
# harness's own transcript-directory naming (verified live, see header). Empty output and non-zero
# status if DIR does not resolve — a caller must check, never assume a slug for a bad path.
tu_project_slug() {
  local dir="$1" abs
  abs="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  printf '%s' "$abs" | tr '/.' '--'
}

# tu_repo_top [DIR] — the project's main-checkout top for DIR (default cwd), folding worktrees into
# one project. Every caller of tu_session_files needs exactly this resolution for its REPO_TOP
# argument. Delegates to keel_repo_top, sourced above (dir #415) — this function used to carry its own
# copy of that chain (promoted from a near-verbatim duplicate first written independently in dir
# #314's own token-report.sh, itself mirroring tools/lib/impact-store.sh's
# _impact_main_top/_impact_resolve_top chain), which was itself exactly the "second implementation can
# silently diverge" risk dir #314's own promotion had just closed for token-report.sh, one file over.
tu_repo_top() {
  keel_repo_top "${1:-.}"
}

# tu_session_files REPO_TOP — every PRIMARY session transcript (`<uuid>.jsonl`, never a subagent
# sibling) belonging to REPO_TOP: its own checkout's project directory plus every worktree's
# (`<slug>--claude-worktrees-*`, see header). One absolute path per line, no particular order, nothing
# printed for a project that has never run a session (empty output, not an error).
tu_session_files() {
  local repo_top="$1" root slug d f
  root="$(tu_projects_root)"
  slug="$(tu_project_slug "$repo_top")" || return 1
  for d in "$root/$slug" "$root/$slug"--claude-worktrees-*; do
    [ -d "$d" ] || continue
    for f in "$d"/*.jsonl; do
      [ -f "$f" ] || continue
      printf '%s\n' "$f"
    done
  done
}

# tu_subagent_files SESSION_JSONL_FILE — every subagent sibling of one primary session file (dir #313
# manager correction / dir #314 SPEC §6.2): `<same-dir>/<uuid>/subagents/agent-*.jsonl`. Empty output,
# not an error, for a session that spawned no subagents (the common case).
tu_subagent_files() {
  local session_file="$1" dir uuid f
  dir="$(dirname "$session_file")"
  uuid="$(basename "$session_file" .jsonl)"
  for f in "$dir/$uuid/subagents/agent-"*.jsonl; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done
}

# tu_require_jq — the one dependency check every entry point below calls first (dir #314 SPEC §8.1:
# jq only, no python3 fallback).
tu_require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf 'transcript-usage: jq is required and was not found on PATH\n' >&2
    return 1
  }
}

# The known non-assistant record types this project's own transcripts carry (verified live, 2026-09-06,
# across every keel session file on this machine — 15 distinct non-"assistant" types, ~106k records
# scanned). Used ONLY by tu_self_check's "unrecognized" counter below — never to gate tu_turns'
# selection, which is a positive match on `type == "assistant"` (see the header note on why a type
# enumeration is the wrong filter to build the actual reader on).
_TU_KNOWN_OTHER_TYPES='["user","attachment","last-prompt","atis-latch","bridge-session","queue-operation","custom-title","system","pr-link","mode","worktree-state","relocated","file-history-snapshot","permission-mode"]'

# tu_turns KIND FILE — deduped per-turn usage records from one transcript file (primary or subagent),
# one compact JSON object per line, in original file order. KIND is a caller-supplied tag
# ("primary"/"subagent") stamped onto every record so a caller can keep the two totals separate (dir
# #314 SPEC §6.2) without re-deriving which file a record came from.
#
# Fields: file, kind, sessionId, agentId, requestId, timestamp, model, gitBranch, effort,
# attributionSkill, attributionAgent, isSidechain, input_tokens, cache_creation_input_tokens,
# cache_read_input_tokens, output_tokens, thinking_tokens, cache_creation_1h, cache_creation_5m.
#
# Dedup: first occurrence per requestId, in ORIGINAL file order — a `reduce` over the slurped array,
# not `group_by`/`unique_by`: both of those SORT by the key first, which would silently reorder turns
# and defeat "first" for a field (timestamp) that genuinely differs across duplicates (see header).
# A record with no requestId is NEVER deduped against anything — it always survives. An earlier
# version coerced a missing requestId to a fixed `// ""` fallback, which collided every
# requestId-less record onto ONE shared key and silently dropped every one after the first
# (reproduced live: two genuinely distinct turns with no requestId deduped down to one, losing the
# second turn's tokens entirely). A later attempt fixed that by falling back to the record's own
# array index instead ("noreqid:" + index) — safe against every real transcript, but still, in
# principle, a STRING that a sufficiently adversarial `requestId` value could equal (dir #313 review:
# flagged as a live-reproducible, if practically negligible, edge case). Skipping the dedup step
# entirely for a requestId-less record removes the possibility outright, at zero cost: there is no
# identity to dedupe by in the first place, so "always keep it" is both simpler and provably correct.
tu_turns() {
  local kind="$1" file="$2"
  tu_require_jq || return 1
  jq -c -s --arg file "$file" --arg kind "$kind" '
    [ .[] | select(.type == "assistant" and (.message.usage != null)) ] as $recs
    | (reduce $recs[] as $r ({seen: {}, out: []};
        if ($r.requestId == null) then (.out += [$r])
        else
          ($r.requestId) as $rid
          | if (.seen[$rid] // false) then .
            else (.seen[$rid] = true) | (.out += [$r])
            end
        end)
      ).out[]
    | {
        file: $file,
        kind: $kind,
        sessionId: (.sessionId // null),
        agentId: (.agentId // null),
        requestId: .requestId,
        timestamp: .timestamp,
        model: .message.model,
        gitBranch: (.gitBranch // null),
        effort: (.effort // null),
        attributionSkill: (.attributionSkill // null),
        attributionAgent: (.attributionAgent // null),
        isSidechain: (.isSidechain // false),
        input_tokens: (.message.usage.input_tokens // 0),
        cache_creation_input_tokens: (.message.usage.cache_creation_input_tokens // 0),
        cache_read_input_tokens: (.message.usage.cache_read_input_tokens // 0),
        output_tokens: (.message.usage.output_tokens // 0),
        thinking_tokens: (.message.usage.output_tokens_details.thinking_tokens // 0),
        cache_creation_1h: (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0),
        cache_creation_5m: (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0)
      }
  ' "$file"
}

# tu_tool_calls KIND FILE — every tool_use content block from one transcript file, ONE line per
# occurrence, never deduped (dir #314 SPEC §6.4: the dedupe applies to usage sums, not tool calls —
# that repeat-per-requestId pattern is exactly how several distinct tool calls in one response get
# logged). `file_path` is normalized to repo-relative form when the record's own `.cwd` is a prefix of
# it (dir #314 SPEC §6.6); left absolute otherwise (a memory file, a KB doc — outside any repo this
# session's cwd names).
tu_tool_calls() {
  local kind="$1" file="$2"
  tu_require_jq || return 1
  jq -c -s --arg file "$file" --arg kind "$kind" '
    .[] | select(.type == "assistant") as $rec
    | ($rec.message.content // [])[]
    | select(.type == "tool_use")
    | (.input.file_path // .input.path // .input.notebook_path // null) as $fp
    | {
        file: $file,
        kind: $kind,
        requestId: $rec.requestId,
        timestamp: $rec.timestamp,
        name: .name,
        file_path: (
          if ($fp != null and $rec.cwd != null and ($fp | startswith($rec.cwd + "/")))
          then ($fp | ltrimstr($rec.cwd + "/"))
          else $fp
          end
        )
      }
  ' "$file"
}

# tu_self_check FILE — the visible guard dir #314 SPEC §6.5 requires: how many lines are
# assistant-with-usage (what tu_turns reads), how many are assistant-WITHOUT-usage (a malformed or
# incomplete record — should be zero; a warning sign, never silently dropped), how many are one of the
# known non-usage-bearing types (_TU_KNOWN_OTHER_TYPES above), and — the actual guard — which types
# this lib has never seen before, named explicitly so a future harness format change is visible rather
# than silently absorbed into "known_other". Emits one JSON object.
#
# INVARIANT a caller may rely on: total/assistant_usage/assistant_no_usage/known_other/
# unrecognized_types partition every record in the file EXACTLY (no gap, no overlap) — the four
# `select`s above are pairwise exclusive by construction (assistant-with-usage vs
# assistant-without-usage vs non-assistant-known vs non-assistant-unrecognized) and jointly exhaustive
# over every possible `.type`. dir #314's token-report.sh relies on this to derive the true
# unrecognized RECORD count arithmetically (`total - assistant_usage - assistant_no_usage -
# known_other`) rather than `unrecognized_types | length`, which is a distinct-NAME count after the
# `unique`. Keep this partition exact if this function's filters ever change.
tu_self_check() {
  local file="$1"
  tu_require_jq || return 1
  jq -c -s --arg file "$file" --argjson known "$_TU_KNOWN_OTHER_TYPES" '
    {
      file: $file,
      total: length,
      assistant_usage: ([.[] | select(.type == "assistant" and (.message.usage != null))] | length),
      assistant_no_usage: ([.[] | select(.type == "assistant" and (.message.usage == null))] | length),
      known_other: ([.[] | select(.type != "assistant") | .type as $t | select($known | index($t) != null)] | length),
      unrecognized_types: ([.[] | select(.type != "assistant") | .type as $t | select($known | index($t) == null) | $t] | unique)
    }
  ' "$file"
}

# tu_session_totals SESSION_JSONL_FILE — one session's full accounting: the primary file's turns
# deduped and summed, EVERY subagent sibling's turns deduped (per-file) and summed separately (dir #314
# SPEC §6.2 — primary and fan-out are reported, never folded into one number), each as its own JSON
# object under "primary"/"subagent" (the latter key absent when the session spawned no subagents).
# Emits one JSON object, e.g. {"primary":{...}} or {"primary":{...},"subagent":{...}}.
tu_session_totals() {
  local session_file="$1" tmp f
  # dir #313 review: named _tu_bad, not "status" — zsh treats `status` as a special read-only
  # variable, and a sourced lib must not assume the caller's shell tolerates that name even though
  # this project's own scripts run under bash.
  local _tu_bad=0
  tu_require_jq || return 1
  tmp="$(mktemp)" || return 1
  {
    tu_turns primary "$session_file" || _tu_bad=1
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      tu_turns subagent "$f" || _tu_bad=1
    done < <(tu_subagent_files "$session_file")
  } > "$tmp"
  if [ "$_tu_bad" -ne 0 ]; then rm -f "$tmp"; return 1; fi
  # dir #313 review (a code-review pass found this live, reproduced by stubbing jq to fail): a
  # trailing bare `jq ...; rm -f "$tmp"` made rm's own exit status — not jq's — this function's
  # return value, so a failing final jq call silently reported success. A `trap ... RETURN` was
  # tried here and reverted: bash RETURN traps are NOT scoped to the function that sets them (they
  # are a single global handler that fires on every SUBSEQUENT function return too) — reproduced
  # live, it crashed a caller two frames up with "tmp: unbound variable" once THIS function's own
  # $tmp had gone out of scope. Capture-then-cleanup-then-return, in that literal order, is what
  # this file's sibling tools/keel-impact.sh already does everywhere it faces the same hazard
  # (search that file for "must stay the VERY NEXT statement") — `out`/`status` here is the same
  # discipline, not a new one.
  local out status
  out="$(jq -c -s '
    def sumf(f): map(f) | add // 0;
    group_by(.kind)
    | map({ (.[0].kind): {
        files: ([.[].file] | unique | length),
        turns: length,
        input_tokens: sumf(.input_tokens),
        cache_creation_input_tokens: sumf(.cache_creation_input_tokens),
        cache_read_input_tokens: sumf(.cache_read_input_tokens),
        output_tokens: sumf(.output_tokens),
        thinking_tokens: sumf(.thinking_tokens),
        models: ([.[].model] | unique)
      }})
    | add // {}
  ' "$tmp")"
  status=$?
  rm -f "$tmp"
  [ "$status" -eq 0 ] || return "$status"
  printf '%s\n' "$out"
}
