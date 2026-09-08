# shellcheck shell=bash
# tools/lib/repo-top.sh — the ONE shared answer to "what is DIR's git main-checkout top" (dir #415).
#
# Before this file, two libs answered this question independently: tools/lib/impact-store.sh's
# _impact_main_top/_impact_resolve_top, and tools/lib/transcript-usage.sh's tu_repo_top (itself
# promoted out of tools/token-report.sh in dir #314 as a near-verbatim copy of the impact-store.sh
# chain). Two independent copies of the same non-trivial fallback chain is exactly the "second
# implementation can silently diverge" risk dir #314's own promotion existed to close — just one file
# over. Consolidating impact-store.sh onto transcript-usage.sh (or vice versa) would have made a
# broadly-consumed, security-adjacent lib (impact-store.sh: doctor.sh, pre-pr-gate.sh, keel-impact.sh,
# public-audit.sh, pipeline-canary.sh, secret-guard's sibling tooling, citation-resolvability.sh,
# read-trace.sh) depend on a narrow, newer, jq-oriented one built for token-economy reporting (or the
# reverse) — a real layering smell independent reviewers on this ticket flagged (dir #415 review:
# efficiency and altitude passes). This file gives both libs a single, dependency-free home instead:
# no jq, no git-lib dependency, nothing but the chain itself.
#
# dir #415 review, efficiency pass, round 2 — measured, not assumed: the dominant per-source cost
# here is NOT this file's own size (sourcing the old, larger transcript-usage.sh directly measured
# statistically indistinguishable from sourcing this file, live A/B, both well under 1ms apart) — it's
# the `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` idiom's own subshell fork + external `dirname`
# exec, live-measured at several ms per invocation, paid once per file that sources this one. That
# idiom is this codebase's established, deliberately robust convention for cross-lib sourcing (~15
# sites, unchanged by this ticket) specifically because it resolves correctly regardless of the
# sourcing caller's cwd or whether it was invoked with a relative path; a cheaper `${BASH_SOURCE[0]%/*}`
# alternative was considered and rejected — verified live to silently return the ORIGINAL string
# unchanged (not `.`) when `BASH_SOURCE[0]` has no `/` in it at all (e.g. sourced by bare filename from
# the same directory), a real correctness trap for a hypothetical future caller, for a few ms of
# savings on a path this ticket doesn't need to be faster than the ~15 other sites already accept.
#
# Sourced, not executed — no shebang requirement, no `set -e` (inherits the caller's).

# keel_repo_main_top [DIR] — the MAIN checkout's top for DIR (default cwd): the first `git worktree
# list` entry, empty if DIR is not a repo or that entry is bare (no working tree). Equals DIR's own
# top in a plain (non-worktree) repo. `|| true`: outside a repo git exits 128, which would trip the
# caller's `set -e` if this ran unguarded; the awk reads its whole input on purpose (no early exit, no
# SIGPIPE).
keel_repo_main_top() {
  git -C "${1:-.}" worktree list --porcelain 2>/dev/null |
    awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true
}

# keel_repo_own_top [DIR] — DIR's OWN toplevel, never folded back to a main checkout: DIR's own git
# toplevel (a worktree's own root, not the repo it was branched from); else (DIR is not a git repo
# yet) DIR's own physical path. Split out of keel_repo_top (dir #430) — that function's "prefer the
# main checkout" answer is correct for a STORE KEY (grouping every worktree's activity under one
# project id), but wrong for resolving what a raw file path is RELATIVE TO: a worktree session's own
# files live under its own root, not under the main checkout's, and a caller that strips the main-
# checkout prefix off a worktree-relative path is left with the worktree's own subpath inside
# `.claude/worktrees/<name>/...` still attached (found live, dir #430 — see
# tools/lib/read-trace.sh's `_rt_normalize_path`, the caller this was extracted for).
#
# NOT memoized — same reasoning as keel_repo_top below (command substitution forks a subshell; a
# process-global cache written inside one never reaches the caller).
keel_repo_own_top() {
  local dir="${1:-.}" top
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || top="$(cd "$dir" 2>/dev/null && pwd -P)" || top="$dir"
  printf '%s' "$top"
}

# keel_repo_top [DIR] — DIR's resolved top: the main checkout's top; else (a bare-main topology)
# DIR's own toplevel; else (DIR is not a git repo yet) DIR's own physical path.
#
# NOT memoized, on purpose (an earlier version of this chain, in tools/lib/impact-store.sh, tried a
# single-slot cache here and it was dead on arrival — found live by an operator-run max-depth review,
# empirically verified): every call site invokes this via `top="$(keel_repo_top "$dir")"`, and command
# substitution forks a subshell — any cache variable this function writes lives only in that throwaway
# child and vanishes when it exits, so the parent's "cache" never actually gets populated. A real fix
# needs the caller to avoid command substitution entirely (an output-variable convention, rewriting
# every call site across every consumer) — a bigger, separate change, not a quick fix.
keel_repo_top() {
  local dir="${1:-.}" top
  top="$(keel_repo_main_top "$dir")"
  [ -n "$top" ] || top="$(keel_repo_own_top "$dir")"
  printf '%s' "$top"
}
