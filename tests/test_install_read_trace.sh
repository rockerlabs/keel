#!/usr/bin/env bash
# install-read-trace.sh — wires dir #387's read-trace fuses' 3 hooks into a project's (or the
# machine-global) Claude Code settings.json. Trimmed mirror of test_install_pre_pr_gate.sh's own
# coverage (same installer shape, 3 hooks instead of 6).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

installer="$REPO_ROOT/tools/install-read-trace.sh"
rt="$REPO_ROOT/tools/read-trace.sh"
THREE_EVENTS='PostToolUse SessionStart SessionEnd'

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — install-read-trace tests skipped (the installer requires jq to edit settings.json)"
  summary; exit $?
fi

# --- --help / bad args -----------------------------------------------------------------------------
run "$installer" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$installer"
check_status "no args -> exit 2" 2 "$STATUS"
run "$installer" /no/such/dir
check_status "not a git repo -> exit 2" 2 "$STATUS"
run "$installer" --global /some/repo
check_status "--global + a repo path -> exit 2 (rejected)" 2 "$STATUS"

# --- (a) fresh install: all 3 hooks land, pointing at THIS checkout's tool by absolute path ----------
repo="$(new_repo)"
run "$installer" "$repo"
check_status "fresh install -> exit 0" 0 "$STATUS"
check_file "settings.json created" "$repo/.claude/settings.json"
for ev in $THREE_EVENTS; do
  check_contains "wires $ev" "$OUT" "+    $ev"
done
sj="$(cat "$repo/.claude/settings.json")"
check_contains "PostToolUse hook points at read-trace.sh log-tool (no copy)" "$sj" "'$rt' log-tool"
check_contains "SessionStart hook is startup" "$sj" "'$rt' startup"
check_contains "SessionEnd hook is session-end" "$sj" "'$rt' session-end"
check_contains "PostToolUse matcher covers all four tools" "$sj" '"matcher": "Edit|Write|NotebookEdit|Read"'
check_contains "SessionStart matcher is startup" "$sj" '"matcher": "startup"'

# --- (a2) idempotent re-run: same content, reported as already-wired, no duplicate entries ----------
run "$installer" "$repo"
check_status "re-run -> exit 0" 0 "$STATUS"
for ev in $THREE_EVENTS; do
  check_contains "re-run reports $ev already wired" "$OUT" "=    $ev"
done
n="$(grep -c '"matcher": "startup"' "$repo/.claude/settings.json")"
check_status "re-run does not duplicate the SessionStart entry" 1 "$n"

# --- foreign content elsewhere in settings.json survives untouched ----------------------------------
tmp_perm="$(mktemp)"
jq '. + {permissions: {allow: ["Bash(ls:*)"]}}' "$repo/.claude/settings.json" > "$tmp_perm"
mv "$tmp_perm" "$repo/.claude/settings.json"
run "$installer" "$repo"
check_status "re-run over a settings.json with foreign keys -> exit 0" 0 "$STATUS"
check_contains "foreign top-level key survives" "$(cat "$repo/.claude/settings.json")" '"permissions"'

# --- (b) a foreign hook on the SAME event+matcher -> refusal, exit non-zero, file untouched ----------
frepo="$(new_repo)"
mkdir -p "$frepo/.claude"
cat > "$frepo/.claude/settings.json" <<EOF
{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo not-the-tool"}]}]}}
EOF
before="$(cat "$frepo/.claude/settings.json")"
run "$installer" "$frepo"
check_status "foreign hook on the same event+matcher -> refused (exit 3)" 3 "$STATUS"
check_contains "refusal names the conflicting event/matcher" "$OUT" "SessionStart/startup"
check_contains "refusal points at --force" "$OUT" "--force"
check_status "settings.json is byte-for-byte untouched" "$before" "$(cat "$frepo/.claude/settings.json")"

# --- (c) --force backs up settings.json then replaces just that matcher -----------------------------
run "$installer" --force "$frepo"
check_status "--force -> exit 0" 0 "$STATUS"
check_contains "announces the backup" "$OUT" "backed up your existing settings.json"
bak="$(find "$frepo/.claude" -name 'settings.json.*.bak' | head -n1)"
[ -n "$bak" ] && pass "a timestamped backup sibling exists" || fail "a timestamped backup sibling exists" "none found"
check_contains "backup preserves the original foreign command" "$(cat "${bak:-/dev/null}")" "not-the-tool"
check_absent "the foreign command is gone from the live file" "$(cat "$frepo/.claude/settings.json")" "not-the-tool"
check_contains "the read-trace command is now wired instead" "$(cat "$frepo/.claude/settings.json")" "$rt"

# --- (d) no jq on PATH -> snippet printed instead of a write, file untouched -------------------------
farm="$(mktemp -d)"; path_farm "$farm" jq
njrepo="$(new_repo)"
run env PATH="$farm" "$installer" "$njrepo"
check_status "no jq -> non-zero (nothing installed)" 1 "$STATUS"
check_contains "explains jq is required" "$OUT" "jq is required"
check_contains "prints a ready-to-paste snippet" "$OUT" "\"hooks\""
check_nofile "no jq -> settings.json was never written" "$njrepo/.claude/settings.json"

# --- --global wires the machine-global settings.json instead of a repo's -----------------------------
ghome="$SANDBOX/global-rt-home"
run env KEEL_HOME="$ghome" "$installer" --global
check_status "--global -> exit 0" 0 "$STATUS"
check_file "wires \$KEEL_HOME/settings.json" "$ghome/settings.json"
check_contains "warns about the wider blast radius" "$OUT" "EVERY repo"

# --- --uninstall removes exactly the 3 hooks this installer wired ------------------------------------
urepo="$(new_repo)"
run "$installer" "$urepo"
check_status "install before uninstall -> exit 0" 0 "$STATUS"
run "$installer" --uninstall "$urepo"
check_status "--uninstall -> exit 0" 0 "$STATUS"
for ev in $THREE_EVENTS; do
  check_contains "removes $ev" "$OUT" "-    $ev"
done
check_absent "the read-trace command is gone from settings.json" "$(cat "$urepo/.claude/settings.json")" "$rt"
run "$installer" --uninstall "$urepo"
check_status "second --uninstall -> nothing left to remove" 0 "$STATUS"
check_contains "second --uninstall says so" "$OUT" "nothing to remove"

# --- --uninstall must not silently delete an UNRELATED empty hook array ------------------------------
# Regression pin: the removal jq program used to prune EVERY empty array under .hooks after removing
# ours, not just the ones this installer's own specs name — so an unrelated event some other tool had
# wired as an empty array (e.g. a temporarily-disabled hook) vanished too, contradicting this file's
# own "everything else...left exactly as it was" claim. Fixed by scoping the post-removal prune to only
# the event names this installer's own hook_specs ever touches.
erepo="$(new_repo)"
mkdir -p "$erepo/.claude"
cat > "$erepo/.claude/settings.json" <<'EOF'
{"hooks":{"Notification":[]}}
EOF
run "$installer" "$erepo"
check_status "install over a settings.json with an unrelated empty hook array -> exit 0" 0 "$STATUS"
run "$installer" --uninstall "$erepo"
check_status "--uninstall -> exit 0" 0 "$STATUS"
check_contains "the unrelated empty Notification array survives uninstall" "$(cat "$erepo/.claude/settings.json")" '"Notification"'

summary
