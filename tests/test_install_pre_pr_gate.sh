#!/usr/bin/env bash
# install-pre-pr-gate.sh — wires the /polish gate's 6 hooks into a project's (or the machine-global)
# Claude Code settings.json. dir #68: this is the opt-in step that makes the gate real for an adopter,
# separate from install.sh (which now ships polish.md unconditionally but never wires a hook itself).
# The 5th hook (SubagentStop/general-purpose, dir #70) traces the independent-agent-review leg. The 6th
# hook (PostToolUse/AskUserQuestion, dir #88) traces step 5(a)'s MANDATORY review-reminder dialog —
# shares the PostToolUse event with the Skill matcher, so FIVE_EVENTS below still names 5 distinct event
# NAMES even though there are now 6 matcher entries across them.
#
# The installer edits settings.json with jq, so most of these tests need jq. The busybox/Alpine CI job
# installs only bash+git (same convention as tests/test_pre_pr_gate.sh, tests/test_pipeline_canary.sh,
# tests/test_keel_check_gate.sh) — there, skip cleanly. Without jq the installer degrades to printing a
# ready-to-paste snippet instead of writing anything (an explicit, documented, already-tested choice —
# see the "no jq" block below, which stays real coverage on the legs that DO have jq by hiding it via
# PATH regardless of what's actually installed).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

installer="$REPO_ROOT/tools/install-pre-pr-gate.sh"
gate="$REPO_ROOT/tools/pre-pr-gate.sh"
FIVE_EVENTS='PreToolUse SessionStart PostToolUse UserPromptExpansion SubagentStop'

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — install-pre-pr-gate tests skipped (the installer requires jq to edit settings.json)"
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
check_contains "rejection names the conflict" "$OUT" "doesn't take a repo path"

# --- (a) fresh install: all 5 hooks land, pointing at THIS checkout's gate by absolute path ---------
repo="$(new_repo)"
run "$installer" "$repo"
check_status "fresh install -> exit 0" 0 "$STATUS"
check_file "settings.json created" "$repo/.claude/settings.json"
for ev in $FIVE_EVENTS; do
  check_contains "wires $ev" "$OUT" "+    $ev"
done
sj="$(cat "$repo/.claude/settings.json")"
# $gate is single-quoted WITHIN the command string (not just JSON-escaped) — a checkout path with a
# space must still reach the hook runner as one token, not split on the space (regression below).
check_contains "PreToolUse hook points at the gate (no copy)" "$sj" "\"command\": \"bash '$gate'\""
check_contains "SessionStart hook is rollout-check" "$sj" "'$gate' rollout-check"
check_contains "PostToolUse/UserPromptExpansion/SubagentStop hooks are skill-trace" "$sj" "'$gate' skill-trace"
check_contains "PreToolUse matcher is Bash" "$sj" '"matcher": "Bash"'
check_contains "SessionStart matcher is startup" "$sj" '"matcher": "startup"'
check_contains "PostToolUse matcher is Skill" "$sj" '"matcher": "Skill"'
check_contains "UserPromptExpansion matcher is code-review" "$sj" '"matcher": "code-review"'
check_contains "SubagentStop matcher is general-purpose" "$sj" '"matcher": "general-purpose"'
check_contains "PostToolUse matcher includes AskUserQuestion (dir #88)" "$sj" '"matcher": "AskUserQuestion"'
n_ptu="$(jq '[.hooks.PostToolUse[].matcher] | length' "$repo/.claude/settings.json")"
check_status "PostToolUse carries both matchers (Skill + AskUserQuestion), not a collision" 2 "$n_ptu"

# --- (a2) idempotent re-run: same content, reported as already-wired, no duplicate entries ----------
run "$installer" "$repo"
check_status "re-run -> exit 0" 0 "$STATUS"
for ev in $FIVE_EVENTS; do
  check_contains "re-run reports $ev already wired" "$OUT" "=    $ev"
done
n="$(grep -c '"matcher": "Bash"' "$repo/.claude/settings.json")"
check_status "re-run does not duplicate the PreToolUse/Bash entry" 1 "$n"

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
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo not-the-gate"}]}]}}
EOF
before="$(cat "$frepo/.claude/settings.json")"
run "$installer" "$frepo"
check_status "foreign hook on the same event+matcher -> refused (exit 3)" 3 "$STATUS"
check_contains "refusal names the conflicting event/matcher" "$OUT" "PreToolUse/Bash"
check_contains "refusal points at --force" "$OUT" "--force"
check_status "settings.json is byte-for-byte untouched" "$before" "$(cat "$frepo/.claude/settings.json")"

# --- (c) --force backs up settings.json (timestamped sibling) then replaces just that matcher -------
run "$installer" --force "$frepo"
check_status "--force -> exit 0" 0 "$STATUS"
check_contains "announces the backup" "$OUT" "backed up your existing settings.json"
bak="$(find "$frepo/.claude" -name 'settings.json.*.bak' | head -n1)"
[ -n "$bak" ] && pass "a timestamped backup sibling exists" || fail "a timestamped backup sibling exists" "none found"
check_contains "backup preserves the original foreign command" "$(cat "${bak:-/dev/null}")" "not-the-gate"
check_absent "the foreign command is gone from the live file" "$(cat "$frepo/.claude/settings.json")" "not-the-gate"
check_contains "the gate command is now wired instead" "$(cat "$frepo/.claude/settings.json")" "$gate"

# --- (d) no jq on PATH -> snippet printed instead of a write, file untouched ------------------------
farm="$(mktemp -d)"; path_farm "$farm" jq
njrepo="$(new_repo)"
run env PATH="$farm" "$installer" "$njrepo"
check_status "no jq -> non-zero (nothing installed)" 1 "$STATUS"
check_contains "explains jq is required" "$OUT" "jq is required"
check_contains "prints a ready-to-paste snippet" "$OUT" "\"hooks\""
check_contains "snippet names the gate path" "$OUT" "$gate"
check_nofile "no jq -> settings.json was never written" "$njrepo/.claude/settings.json"

# --- --global wires the machine-global settings.json instead of a repo's ----------------------------
ghome="$SANDBOX/global-gate-home"
run env KEEL_HOME="$ghome" "$installer" --global
check_status "--global -> exit 0" 0 "$STATUS"
check_file "wires \$KEEL_HOME/settings.json" "$ghome/settings.json"
check_contains "warns about the wider blast radius" "$OUT" "EVERY repo"

# --- a temp bootstrap-shaped clone refuses to wire (hooks would point at a path about to vanish) ----
btmp="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
mkdir -p "$btmp/keel/tools"
cp "$installer" "$btmp/keel/tools/install-pre-pr-gate.sh"
cp "$gate" "$btmp/keel/tools/pre-pr-gate.sh"
ephrepo="$(new_repo)"
run "$btmp/keel/tools/install-pre-pr-gate.sh" "$ephrepo"
check_status "run from a bootstrap-shaped temp clone -> exit 2 (refused)" 2 "$STATUS"
check_contains "names the reason (temp clone, not a kept checkout)" "$OUT" "kept checkout"
check_nofile "nothing was wired" "$ephrepo/.claude/settings.json"
rm -rf "$btmp"

# --- settings.json is not valid JSON -> refuse loudly, don't silently discard it --------------------
brepo="$(new_repo)"
mkdir -p "$brepo/.claude"
printf 'not json at all' > "$brepo/.claude/settings.json"
run "$installer" "$brepo"
check_status "invalid JSON settings.json -> exit 2" 2 "$STATUS"
check_contains "names the file as invalid" "$OUT" "not valid JSON"
check_contains "invalid settings.json left untouched" "$(cat "$brepo/.claude/settings.json")" "not json at all"

# --- valid JSON but the wrong SHAPE (e.g. a hand-edit) -> clean refusal, not a raw jq crash -----------
shrepo="$(new_repo)"
mkdir -p "$shrepo/.claude"
printf '{"hooks":{"PreToolUse":"not-an-array"}}' > "$shrepo/.claude/settings.json"
run "$installer" "$shrepo"
check_status "unexpected hooks shape -> exit 2 (not a jq crash)" 2 "$STATUS"
check_contains "names the shape problem" "$OUT" "unexpected shape"
check_contains "malformed-shape settings.json left untouched" "$(cat "$shrepo/.claude/settings.json")" "not-an-array"

# --- doctor.sh --install pairing check: shipped polish.md + wired gate -> OK; unwired -> WARN --------
doctor="$REPO_ROOT/tools/doctor.sh"
dh_unwired="$SANDBOX/dh-unwired"
run "$REPO_ROOT/install.sh" --home "$dh_unwired" --no-hooks
run "$doctor" --install "$dh_unwired"
check_contains "unwired gate -> WARN, names the opt-in installer" "$OUT" "no machine-global gate is wired"
check_contains "unwired gate WARN points at the installer" "$OUT" "install-pre-pr-gate.sh"

dh_wired="$SANDBOX/dh-wired"
run "$REPO_ROOT/install.sh" --home "$dh_wired" --no-hooks
run env KEEL_HOME="$dh_wired" "$installer" --global
check_status "wiring the freshly-installed home's own gate -> exit 0" 0 "$STATUS"
run "$doctor" --install "$dh_wired"
check_contains "wired gate -> OK" "$OUT" "OK   /polish gate: wired machine-global"

# --- regression: doctor's gate check is structural, not a bare substring match ----------------------
# A settings.json that only mentions pre-pr-gate.sh via an unrelated hook (no PreToolUse/Bash entry at
# all — the one that actually blocks gh pr create) must NOT read as "wired".
dh_fake="$SANDBOX/dh-fake-wired"
run "$REPO_ROOT/install.sh" --home "$dh_fake" --no-hooks
mkdir -p "$dh_fake"
cat > "$dh_fake/settings.json" <<EOF
{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"bash $gate rollout-check"}]}]}}
EOF
run "$doctor" --install "$dh_fake"
check_contains "a mention with no PreToolUse/Bash hook is still WARN, not a false OK" "$OUT" "no machine-global gate is wired"

# --- doctor.sh project-scope pairing check (dir #68 follow-up): --install mode only ever sees the
# machine-global settings.json, so an adopter who correctly wired PROJECT scope (the documented
# default) got a false "no gate wired" WARN on every run with no way to confirm they'd actually done
# it right. The gate is opt-in per project, so plain absence must stay SILENT here (no finding at any
# tier — most projects legitimately never wire it) — only a project that already touched pre-pr-gate.sh
# wiring but left the load-bearing hook out gets flagged, same "looks wired but isn't" shape as the
# secret-guard W-GUARD-BYPASSED check.
clean_baseline() { printf '# ctx\n' > "$1/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$1/.gitignore"; }

noagate="$(new_repo)"; clean_baseline "$noagate"
run "$doctor" "$noagate"
check_status "clean project, no gate wiring -> exit 0" 0 "$STATUS"
check_absent "no .claude/settings.json at all -> no gate finding of any kind" "$OUT" "polish gate"

fullgate="$(new_repo)"; clean_baseline "$fullgate"
run "$installer" "$fullgate"
check_status "wiring the project's own gate -> exit 0" 0 "$STATUS"
run "$doctor" "$fullgate"
check_status "fully wired at project scope -> still exit 0" 0 "$STATUS"
check_contains "fully wired at project scope -> OK" "$OUT" "OK   /polish gate: wired (project scope"

partgate="$(new_repo)"; clean_baseline "$partgate"
mkdir -p "$partgate/.claude"
cat > "$partgate/.claude/settings.json" <<EOF
{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"bash $gate rollout-check"}]}]}}
EOF
run "$doctor" "$partgate"
check_status "W-GATE-PARTIAL is advisory only -> exit 0" 0 "$STATUS"
check_contains "referenced but load-bearing hook missing -> WARN W-GATE-PARTIAL" "$OUT" "W-GATE-PARTIAL"

# --- regression: a checkout path containing a space still produces a working (single-token) command --
sp_root="$(mktemp -d)/space checkout"
mkdir -p "$sp_root/tools"
cp "$installer" "$sp_root/tools/install-pre-pr-gate.sh"
cp "$gate" "$sp_root/tools/pre-pr-gate.sh"
sp_repo="$(new_repo)"
run "$sp_root/tools/install-pre-pr-gate.sh" "$sp_repo"
check_status "install from a space-containing checkout path -> exit 0" 0 "$STATUS"
# repo-key: a real, side-effect-free, stdin-free subcommand — safe to invoke directly in a test (unlike
# hook mode, which blocks reading stdin for the tool-call JSON it expects when given no subcommand). The
# argument must be concatenated INTO the command string (sh -c CMD ARGS sets $0/$1.., it does not append
# to CMD) so it reaches pre-pr-gate.sh's own arg parsing, not the wrapping shell's positional params.
sp_cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$sp_repo/.claude/settings.json")"
run sh -c "$sp_cmd repo-key"
check_status "the generated command runs as ONE token despite the space" 0 "$STATUS"
check_absent "no 'file not found' from the path splitting on the space" "$OUT" "No such file or directory"

summary
