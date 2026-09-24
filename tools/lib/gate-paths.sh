# shellcheck shell=bash
# tools/lib/gate-paths.sh (dir #182, extended by dir #398/#399) — the ONE shared answer to three
# questions: where does the /polish pre-PR gate's PROJECT-SCOPE settings.json live for a given repo
# top (`gate_project_settings_path`); where does keel's own ephemeral state — this gate's
# sentinel/trace/handoff/rollout rendezvous files, keel-check.sh's counters, pipeline-canary.sh's
# sandbox record — live on this machine (`gate_state_root`, `gate_pre_pr_gate_root`,
# `gate_sentinel_path_for_key`/`gate_prev_sentinel_path_for_key`/`gate_trace_path_for_key`); and how
# a caller makes one of those state directories exist, owner-only (`gate_ensure_owner_dir`).
#
# Before this file, the literal path family `<repo>/.claude/settings.json` was independently
# hardcoded in three places that must stay in lockstep and drifted only by convention, not by any
# shared source: `tools/install-pre-pr-gate.sh` (the write target), `tools/doctor.sh`'s
# `gate_hook_wired()` project-scope check, and `tools/pre-pr-gate.sh`'s `_dialog_leg_armed()` first
# candidate. That duplication class already caused two real bugs in this file's history (PR #165 —
# the armer's `$HOME/.claude/settings.json` vs. the installer's `${KEEL_HOME:-...}`; PR #179 — the
# armer's own header comment vs. its own code). This file gives all three one source instead.
#
# Deliberately NOT a manifest or a lookup: a dir #182 `/design` pass found the project-scope
# candidate is not a heuristic guess the way the (already dir #125-backstopped) global/home ones are
# — `$REPO` is the exact repo the caller is already working against, and project-scope install always
# writes to exactly `$REPO/.claude/settings.json` (`install-pre-pr-gate.sh`'s own project-scope branch
# writes no manifest, no ledger entry, by design). A manifest here would only add a new file without
# removing the need to re-read the live settings.json. `settings.local.json` stays a second,
# independent candidate in `_dialog_leg_armed` only — it is not part of this DRY fix.
#
# No validation of $REPO here on purpose: each of the three callers already validates (or doesn't)
# $REPO in the way that fits its own call site — the installer via `git rev-parse` on the CLI-supplied
# repo path, the armer's `$top` via `main_top_for` upstream, doctor.sh's `$d` via a plain directory-
# existence check in its own per-project loop — and this helper must not change any of that behavior.
#
# Sourced, not executed — no shebang requirement, no `set -e` (inherits the caller's).

# gate_project_settings_path REPO — prints the project-scope settings.json path for REPO, exactly as
# `"$REPO/.claude/settings.json"` (no `cd`/`pwd` resolution: REPO is used verbatim, so a caller passing
# a relative or already-resolved path gets back the same shape it passed in — matching what all three
# call sites did before this file existed).
gate_project_settings_path() {
  printf '%s' "${1:?gate_project_settings_path: repo path required}/.claude/settings.json"
}

# gate_state_root — dir #398/#399, dir #637 override (2026-09-23, BACKLOG.md): the keel-owned root
# every one of this gate's cross-process rendezvous files lives under, plus the sibling tools that
# model themselves on the exact same mechanism (keel-check.sh's per-check counters,
# pipeline-canary.sh's sandbox record — SPEC dir #399 §1a groups all three as one load-bearing class).
# $HOME/.keel/tmp — NOT $KEEL_HOME. The operator decided (dir #637) that keel's own state is
# harness-independent and lives at one root per machine, while KEEL_HOME keeps meaning the HARNESS
# home keel installs into (dir #399's own spec had conflated the two — dir #637 caught and resolved
# it before dir #398 shipped the wrong one). Extends dir #397's already-shipped alpine-clone precedent
# at this exact address. No new override variable: tests already redirect $HOME (dir #64), so this
# follows the sandbox for free — an override is added only if a real need is ever shown.
#
# Prints the root and returns 0; prints NOTHING and returns 1 when $HOME is unset/empty, so a caller
# building a path on top of this can fail closed instead of silently resolving the wrong "/.keel/tmp"
# (dir #398 brief lead #3). This function is pure and side-effect-free (no mkdir) — every caller that
# needs a hard stop on failure must call it the same "inline, never through a bare $(...) that would
# only kill the capturing subshell" way pre-pr-gate.sh's own _require_receipt_key documents for the
# identical hazard (bash `exit` inside a command substitution only kills that subshell); a caller that
# can tolerate skipping instead (keel-check-gate.sh's fail-open philosophy — it already fails open on
# a missing jq) checks the exit status and no-ops rather than denying.
gate_state_root() {
  [ -n "${HOME:-}" ] || return 1
  printf '%s/.keel/tmp' "$HOME"
}

# gate_pre_pr_gate_root — the gate's OWN subtree under the shared ephemera root, dir #398/#399: one
# more resolver derived from gate_state_root, so the "pre-pr-gate" subdirectory name has exactly ONE
# spelling. Before this, pipeline-canary.sh built `"$root/pre-pr-gate/canary-state"` with that segment
# hand-typed a second time — a silent-drift risk this ticket's own /simplify pass (altitude angle)
# flagged, the same class dir #182's header already warns against. Same failure contract as
# gate_state_root: prints nothing and returns 1 on an unset/empty $HOME.
gate_pre_pr_gate_root() {
  local root
  root="$(gate_state_root)" || return 1
  printf '%s/pre-pr-gate' "$root"
}

# gate_sentinel_path_for_key / gate_prev_sentinel_path_for_key / gate_trace_path_for_key — the three
# pure, key-to-path builders every caller of the gate's rendezvous files needs: pre-pr-gate.sh (which
# also builds handoff/rollout paths from its own already-resolved keys) and pipeline-canary.sh (which
# only ever needs these three, for keys it resolves via pre-pr-gate.sh's repo-key/receipt-key/keys
# subcommands). pipeline-canary.sh used to reach these by shelling out to a whole extra
# `bash tools/pre-pr-gate.sh sentinel-path <key>` process per lookup — a full reparse of that
# ~2900-line script just to print one string — instead of sourcing this lib directly the way it
# already does for gate_state_root (found by this ticket's own /simplify pass, efficiency + altitude
# angles). Moved here so every caller derives from ONE definition.
#
# Each propagates gate_pre_pr_gate_root's own failure (return 1, print nothing) rather than silently
# building a bogus root-relative path like "/sentinel/<key>" when $HOME is unset — the exact "fail
# closed, never silently resolve the wrong root" contract gate_state_root's own header states, which
# an earlier version of these three violated (found by this ticket's own /code-review high pass, angle
# A): pre-pr-gate.sh is safe regardless (it validates $HOME once at its own top level before any of
# these are reachable), but pipeline-canary.sh calls these directly and only re-validates $HOME when
# $KEEL_CANARY_STATE is NOT set — an operator setting that override explicitly while $HOME is also
# unset would previously have gotten a silently-wrong path instead of an empty one a caller's own
# `[ -f "$path" ]`/`[ -n "$path" ]` check can at least notice.
gate_sentinel_path_for_key() {
  local root; root="$(gate_pre_pr_gate_root)" || return 1
  printf '%s/sentinel/%s' "$root" "$1"
}
gate_prev_sentinel_path_for_key() {
  local root; root="$(gate_pre_pr_gate_root)" || return 1
  printf '%s/prev-sentinel/%s' "$root" "$1"
}
gate_trace_path_for_key() {
  local root; root="$(gate_pre_pr_gate_root)" || return 1
  printf '%s/trace/%s' "$root" "$1"
}

# gate_ensure_owner_dir DIR — mkdir -p DIR, then chmod it owner-only, both best-effort
# (2>/dev/null || true — a permissions/disk failure here degrades to "less private", never a crash).
# The shared "make this state directory exist, owner-only" idiom pre-pr-gate.sh, keel-check.sh and
# pipeline-canary.sh each independently hand-copied (found by this ticket's own /simplify pass, all
# four review angles): SC2174 means `mkdir -p -m` only applies its mode to the DEEPEST directory it
# creates, never one that already existed or any intermediate one, so a separate chmod is the
# always-correct way (and the one that keeps shellcheck clean) to land an owner-only leaf regardless
# of what already existed.
gate_ensure_owner_dir() {
  # A plain `[ -d ]` builtin test short-circuits both forks below on the overwhelming common case —
  # the directory already exists (found by this ticket's own /code-review high pass, efficiency
  # angle): several call sites run this on every single write (every trace append, every handoff,
  # every rollout-state write), long after the directory's first creation. A directory that already
  # existed before this diff shipped (default, non-owner-only permissions) stays that way rather than
  # being re-chmod'd on every call — a one-time, minor laxity accepted in exchange for not forking
  # mkdir+chmod on every write for the rest of that directory's life.
  [ -d "$1" ] && return 0
  mkdir -p "$1" 2>/dev/null || true
  chmod 700 "$1" 2>/dev/null || true
}
