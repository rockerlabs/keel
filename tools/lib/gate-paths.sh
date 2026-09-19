# shellcheck shell=bash
# tools/lib/gate-paths.sh (dir #182) — the ONE shared answer to "where does the /polish pre-PR gate's
# PROJECT-SCOPE settings.json live for a given repo top".
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
