# shellcheck shell=bash
# tools/lib/repo-arg-guard.sh (dir #644): sourcing this file unsets GIT_DIR / GIT_COMMON_DIR /
# GIT_WORK_TREE / GIT_INDEX_FILE, unconditionally, for the rest of the sourcing process and anything
# it spawns. An inherited value for any of these redirects EVERY `git -C "$X"` call the process makes
# — including a validity gate — into a different repository than the one named on the command line: a
# foreign GIT_DIR alone binds to whatever it points at (git prefers it over -C's path resolution for
# the repo it operates on), and a foreign GIT_DIR paired with a GIT_COMMON_DIR that happens to equal a
# REAL repo's common dir is the sharper case (dir #318 residual N8, measured live in E19(c) of
# docs/specs/318-test-ref-isolation.md): `includeIf.gitdir` patterns key off GIT_DIR, not
# GIT_COMMON_DIR, so that combination is not caught by a git-config-based guard either, and the write
# lands in the real repo even when the path named on the command line is not a git repository at all.
#
# Unconditional at SOURCE time, not inside a function a caller has to remember to invoke at exactly
# the right call site (altitude finding, dir #644's own /simplify pass): a guard gated behind "did
# something call keel_repo_arg_guard yet" is only as strong as every future edit's memory to do so at
# every git-touching branch — the same shape of gap that let dir #318's N8 go unnoticed the first
# time. tests/lib.sh already gets this right (its own unset is the first thing that runs after `set
# -uo pipefail`, load-bearing for every git call the file goes on to make, not just some of them); this
# file gives every OTHER script that sources it the same structural guarantee, for free, by the act of
# sourcing alone.
#
# Resolver census (0.12.0 release manager, `git grep -n 'git -C "\$repo"' -- tools`): all four of
# tools/pipeline-canary.sh, tools/install-secret-guard.sh, tools/install-read-trace.sh and
# tools/install-pre-pr-gate.sh resolve a `$repo` this way — and the vulnerability is about the
# PROCESS'S environment being unsanitized, not about where `$repo`'s value came from, so all four
# source this file (pipeline-canary.sh needs nothing beyond the source line itself: it never takes a
# caller-named repo, but its own fixture-creation calls are exactly as exposed to an inherited
# GIT_DIR/GIT_COMMON_DIR as any resolver this ticket fixes). tools/install-secret-guard.sh is the one
# exception, for an unrelated reason: it is designed to be copied standalone alongside only its
# sibling secret-guard/ dir (its own tests run scratch copies that carry no tools/lib/), so it inlines
# the same unset instead of gaining a new tools/lib/ dependency — see its own comment at the call site.
#
# Also sourced (dir #647 fix round, S3 FINDING-S3-1): tools/keel-check.sh's `$PWD`-relative
# `repo_top` resolution and tools/keel-check-gate.sh's `$cwd`-relative one — both were in the "NOT a
# complete census" list below and are now fixed and moved up here, six consumers total. keel-check.sh's
# unset is process-wide, per the source-time contract above, and so also reaches the operator's
# declared check command it spawns — see keel-check.sh's own call-site comment for why that's accepted
# rather than scoped down to just the resolver call.
#
# NOT a complete census of the vulnerability class (found by this ticket's own /code-review max pass,
# after the fix above shipped): the grep pattern was anchored to the literal variable name `repo`, so
# it structurally cannot see the identical `git -C "$X"` shape under any other name. tools/doctor.sh
# ($d), tools/public-audit.sh ($DIR), tools/pre-pr-gate.sh ($cwd — the actual /polish enforcement
# gate), the tools/self/*.sh family, tools/keel-impact.sh ($dir/$top via tools/lib/repo-top.sh),
# tools/lib/impact-store.sh's `impact_claim_key` (dir #74's own worktree-top resolver, `git -C
# "${1:-.}"` — F1's dir #647 fix round guarded that file's two new S4 functions only, not this
# pre-existing one), and others all resolve a caller-named or cwd-derived repo path via unsourced
# `git -C` the same way this file's consumers used to. Flagged for a follow-up ticket (see this PR's
# body for the full list and a candidate deeper fix) rather than fixed here — it would have meant
# auditing and testing several more files, some of them security-sensitive production gates
# (tools/pre-pr-gate.sh among them), well past this ticket's own scope and review budget.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's). keel_repo_arg_guard's `exit 2`
# on failure does NOT depend on the caller's `set -e` (correction, /code-review max, two independent
# passes): it fires unconditionally as the explicit right-hand side of `||`, the same way the inline
# check it replaces did — identical behavior whether or not the caller has `set -e`, and even from
# inside an `if`/`&&`/`||` (a `set -e`-exempted context, the exact trap class this project's own
# `install-secret-guard.sh:_isg_rollback` comment names for a sibling function). Do not "simplify" this
# to a `return` on the theory that the caller's `set -e` will catch it — a `return` value consumed
# inside any of those exempted contexts would silently swallow the failure instead.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE

# keel_repo_arg_guard REPO — exit 2 with "not a git repo: REPO" (unchanged wording — the exact message
# every caller printed before this file existed) if REPO is not a git repository. The env sanitizing
# that makes this check trustworthy already happened above, at source time, not here.
keel_repo_arg_guard() {
  local repo="$1"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
}
