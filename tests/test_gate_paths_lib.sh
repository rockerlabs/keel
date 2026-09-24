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

# --- dir #647 (S3 FINDING-S3-2): HOME set, non-empty, but NOT A DIRECTORY (e.g. a regular file) must
# fail gate_state_root the same way unset/empty does — before this fix, only `-n "$HOME"` was checked,
# so a HOME pointing at a regular file silently passed this gate and built a bogus path underneath a
# file instead of a directory. Mutation proof: remove the `-d "$HOME"` check below and this pair goes
# RED (gate_state_root wrongly succeeds); restore it and both go green.
home_as_file="$(mktemp "$SANDBOX/home-is-a-file.XXXXXX")"
if out="$(HOME="$home_as_file" gate_state_root 2>&1)"; then
  fail "gate_state_root: HOME is a regular file -> non-zero exit (fail closed, not a bogus path)" \
    "exited 0 with: $out"
else
  pass "gate_state_root: HOME is a regular file -> non-zero exit (fail closed, not a bogus path)"
fi
check_status "gate_state_root: HOME is a regular file -> prints nothing" "" \
  "$(HOME="$home_as_file" gate_state_root 2>/dev/null)"

# --- gate_home_diagnosis: the three-way phrase a caller's own fail-closed message embeds, matching
# gate_state_root's own three failure reasons exactly (so the two can never silently drift apart) ----
check_status "gate_home_diagnosis: HOME unset -> 'is unset'" "is unset" "$(env -u HOME bash -c '. "$1"; gate_home_diagnosis' _ "$lib")"
check_status "gate_home_diagnosis: HOME empty -> 'is empty'" "is empty" "$(HOME='' gate_home_diagnosis)"
check_status "gate_home_diagnosis: HOME=regular file -> 'is not a directory (<path>)'" \
  "is not a directory ($home_as_file)" "$(HOME="$home_as_file" gate_home_diagnosis)"
check_status "gate_home_diagnosis: HOME is a real directory -> no complaint (unused in practice, but correct)" \
  "is a directory (no problem)" "$(gate_home_diagnosis)"

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

# --- dir #398: the three key-to-path builders propagate gate_pre_pr_gate_root's own failure (return
# 1, print nothing) rather than silently building a bogus root-relative path like "/sentinel/<key>"
# when $HOME is unset/empty (found by this ticket's own /code-review high pass, angle A) ------------
out="$(gate_sentinel_path_for_key somekey)"
check_status "gate_sentinel_path_for_key: HOME set -> a real, HOME-rooted path" \
  "$HOME/.keel/tmp/pre-pr-gate/sentinel/somekey" "$out"
if out="$(HOME='' gate_sentinel_path_for_key somekey 2>&1)"; then
  fail "gate_sentinel_path_for_key: HOME unset -> non-zero exit, never a bogus /sentinel/<key>" \
    "exited 0 with: $out"
else
  pass "gate_sentinel_path_for_key: HOME unset -> non-zero exit, never a bogus /sentinel/<key>"
fi
check_status "gate_sentinel_path_for_key: HOME unset -> prints nothing" "" "$(HOME='' gate_sentinel_path_for_key somekey 2>/dev/null)"

if out="$(HOME='' gate_prev_sentinel_path_for_key somekey 2>&1)"; then
  fail "gate_prev_sentinel_path_for_key: HOME unset -> non-zero exit" "exited 0 with: $out"
else
  pass "gate_prev_sentinel_path_for_key: HOME unset -> non-zero exit"
fi
if out="$(HOME='' gate_trace_path_for_key somekey 2>&1)"; then
  fail "gate_trace_path_for_key: HOME unset -> non-zero exit" "exited 0 with: $out"
else
  pass "gate_trace_path_for_key: HOME unset -> non-zero exit"
fi

summary
