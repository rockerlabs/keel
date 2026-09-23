#!/usr/bin/env bash
# test_gate_paths_lib.sh — dir #182: tools/lib/gate-paths.sh's `gate_project_settings_path` is the ONE
# shared answer to "where does the /polish pre-PR gate's project-scope settings.json live for REPO",
# replacing three independent `<repo>/.claude/settings.json` literals in
# tools/install-pre-pr-gate.sh, tools/doctor.sh, and tools/pre-pr-gate.sh's `_dialog_leg_armed`. This
# pins the function itself and, source-level, that all three consumers now derive from it instead of
# retyping the literal — the exact duplication class that already caused PR #165 and PR #179.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/gate-paths.sh"
check_file "tools/lib/gate-paths.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- gate_project_settings_path: basic shape, verbatim concatenation, no cd/pwd resolution ----------
out="$(gate_project_settings_path "/tmp/some-repo")"
check_status "gate_project_settings_path: absolute repo -> <repo>/.claude/settings.json" \
  "/tmp/some-repo/.claude/settings.json" "$out"

out="$(gate_project_settings_path "relative/repo")"
check_status "gate_project_settings_path: a relative REPO is used verbatim (no resolution)" \
  "relative/repo/.claude/settings.json" "$out"

out="$(gate_project_settings_path ".")"
check_status "gate_project_settings_path: '.' is used verbatim" "./.claude/settings.json" "$out"

# --- gate_project_settings_path: missing arg is a hard error, not a silent empty/wrong path ----------
if out="$(gate_project_settings_path 2>&1)"; then
  fail "gate_project_settings_path: no REPO arg -> non-zero exit" "exited 0 with: $out"
else
  pass "gate_project_settings_path: no REPO arg -> non-zero exit"
fi

# --- all three consumers derive from the shared function, not an independent literal ----------------
check_contains "tools/install-pre-pr-gate.sh sources tools/lib/gate-paths.sh" \
  "$(cat "$REPO_ROOT/tools/install-pre-pr-gate.sh")" 'lib/gate-paths.sh'
check_contains "tools/install-pre-pr-gate.sh's project-scope branch calls gate_project_settings_path" \
  "$(cat "$REPO_ROOT/tools/install-pre-pr-gate.sh")" 'settings="$(gate_project_settings_path "$repo")"'

check_contains "tools/doctor.sh sources tools/lib/gate-paths.sh" \
  "$(cat "$REPO_ROOT/tools/doctor.sh")" 'lib/gate-paths.sh'
check_contains "tools/doctor.sh's proj_settings calls gate_project_settings_path" \
  "$(cat "$REPO_ROOT/tools/doctor.sh")" 'proj_settings="$(gate_project_settings_path "$d")"'

check_contains "tools/pre-pr-gate.sh sources tools/lib/gate-paths.sh" \
  "$(cat "$REPO_ROOT/tools/pre-pr-gate.sh")" 'lib/gate-paths.sh'
check_contains "tools/pre-pr-gate.sh's _dialog_leg_armed calls gate_project_settings_path" \
  "$(cat "$REPO_ROOT/tools/pre-pr-gate.sh")" 'gate_project_settings_path "$top"'

# --- settings.local.json stays its own, independent candidate in the armer only (not part of the DRY
# fix, not read by gate_project_settings_path or doctor.sh at all) -----------------------------------
check_contains "tools/pre-pr-gate.sh still probes settings.local.json as its own candidate" \
  "$(cat "$REPO_ROOT/tools/pre-pr-gate.sh")" '"$top/.claude/settings.local.json"'
if grep -q 'settings.local.json' "$REPO_ROOT/tools/doctor.sh"; then
  fail "tools/doctor.sh does not check settings.local.json (unchanged scope, dir #182 out of scope)" \
    "found a settings.local.json reference"
else
  pass "tools/doctor.sh does not check settings.local.json (unchanged scope, dir #182 out of scope)"
fi

# --- dir #398/#399/#637: gate_state_root — the ONE resolver the gate's five rendezvous-file paths,
# keel-check.sh, keel-check-gate.sh and pipeline-canary.sh all build on ------------------------------
out="$(gate_state_root)"
check_status "gate_state_root: \$HOME/.keel/tmp, extending dir #397's own alpine-clone precedent" \
  "$HOME/.keel/tmp" "$out"

if out="$(HOME='' gate_state_root 2>&1)"; then
  fail "gate_state_root: HOME unset/empty -> non-zero exit (fail closed, never a bare \"/.keel/tmp\")" \
    "exited 0 with: $out"
else
  pass "gate_state_root: HOME unset/empty -> non-zero exit (fail closed, never a bare \"/.keel/tmp\")"
fi
check_status "gate_state_root: HOME unset/empty -> prints nothing" "" "$(HOME='' gate_state_root 2>/dev/null)"

check_contains "tools/pre-pr-gate.sh sources gate-paths.sh for gate_state_root too" \
  "$(cat "$REPO_ROOT/tools/pre-pr-gate.sh")" 'lib/gate-paths.sh'
check_contains "tools/pre-pr-gate.sh fails closed at top level on gate_state_root" \
  "$(cat "$REPO_ROOT/tools/pre-pr-gate.sh")" 'gate_state_root >/dev/null ||'
check_contains "tools/keel-check.sh sources gate-paths.sh" \
  "$(cat "$REPO_ROOT/tools/keel-check.sh")" 'lib/gate-paths.sh'
check_contains "tools/keel-check-gate.sh sources gate-paths.sh" \
  "$(cat "$REPO_ROOT/tools/keel-check-gate.sh")" 'lib/gate-paths.sh'
check_contains "tools/pipeline-canary.sh sources gate-paths.sh" \
  "$(cat "$REPO_ROOT/tools/pipeline-canary.sh")" 'lib/gate-paths.sh'

summary
