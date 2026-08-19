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

# --- dir #98: --home DIR follows install.sh --home DIR (the two installers agree on the home) --------
# install.sh --home retargets the whole install without exporting KEEL_HOME; before this flag the gate
# had no way to follow it and silently wired ~/.claude instead — two installers describing different
# machines, with nothing said at either install.
hhome="$SANDBOX/gate-home-flag"
mkdir -p "$hhome"   # --home names a home an install already created; it must exist (see the typo case below)
run "$installer" --home "$hhome"
check_status "--home DIR -> exit 0" 0 "$STATUS"
check_file "--home DIR wires DIR/settings.json" "$hhome/settings.json"
check_contains "the confirmation names the retargeted home" "$OUT" "$hhome/settings.json"
# A retargeted home is machine-global in blast radius, and the harness may not read it — say both.
check_contains "--home warns about the wider blast radius too" "$OUT" "EVERY repo"
check_contains "--home flags that Claude Code reads its own default home" "$OUT" "$HOME/.claude"

run "$installer" --home
check_status "--home with no DIR -> exit 2" 2 "$STATUS"
# An EMPTY DIR must refuse as loudly as a missing one — `--home "$KEEL_HOME"` with KEEL_HOME unset
# would otherwise fall through to $HOME/.claude, silently re-creating dir #98's split install (and
# skipping the NOTE, since the resolved dir then equals the default). Nothing may be written.
run "$installer" --home ""
check_status "--home with an EMPTY DIR -> exit 2" 2 "$STATUS"
check_contains "the empty-DIR refusal says what was missing" "$OUT" "got nothing"
check_nofile "empty --home wrote nothing to the default home" "$HOME/.claude/settings.json"
# A MISTYPED home must not be created. mkdir -p would happily accept `--home ~/.keel-hom`, write a
# complete settings.json into a directory nothing reads, print "wired into …" and exit 0 — leaving the
# adopter certain the gate is on while it is nowhere (operator-run /code-review, 4th pass).
typo="$SANDBOX/keel-hom-typo"
run "$installer" --home "$typo"
check_status "--home at a nonexistent DIR -> exit 2" 2 "$STATUS"
check_contains "the refusal says the DIR does not exist" "$OUT" "does not exist"
check_contains "and points at install.sh as the thing that creates a home" "$OUT" "install.sh --home"
if [ -e "$typo" ]; then fail "the mistyped home was not created" "it exists: $typo"; else pass "the mistyped home was not created"; fi
# A following flag is a swallowed argument, not a directory named "--force".
run "$installer" --home --force
check_status "--home swallowing a flag -> exit 2" 2 "$STATUS"
check_contains "the swallowed-flag refusal names it" "$OUT" "--force"
# --home + --global: --home is the more specific flag and decides the target, so it is also the one
# every message names — otherwise the banner blames a flag that isn't governing.
run "$installer" --home "$hhome" --global "$repo"
check_status "--home + --global + a repo path -> exit 2" 2 "$STATUS"
check_contains "the rejection names --home, the flag that governs" "$OUT" "--home doesn't take a repo path"
run "$installer" --home "$hhome" "$repo"
check_status "--home + a repo path -> exit 2 (rejected)" 2 "$STATUS"
check_contains "the --home+path rejection names the conflict" "$OUT" "doesn't take a repo path"
# The other half of dir #98 — install.sh naming this flag in its own summary — is asserted in
# tests/test_install.sh, on installs that file already runs (each extra install.sh run costs a full
# copy pass + verify across the CI matrix, and neither assertion involves this installer).

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
# dir #98: the advised flag has to be able to reach the home the finding just named. `--global`
# resolves ${KEEL_HOME:-$HOME/.claude}, so on a RETARGETED home it writes somewhere else entirely and
# the warning never clears however many times it is followed (operator-run /code-review, 4th pass).
check_contains "on a retargeted home the WARN advises --home, not --global" "$OUT" "--home \"$dh_unwired\""
check_absent "and does not advise --global there" "$OUT" "run --global"
# ...while on the default home --global is exactly right, and stays the advice.
run "$REPO_ROOT/install.sh" --home "$HOME/.claude" --no-hooks
run "$doctor" --install "$HOME/.claude"
check_contains "on the default home the WARN still advises --global" "$OUT" "run --global"
# ...and "default home" means whatever --global RESOLVES to, not $HOME/.claude literally: with
# KEEL_HOME pointing elsewhere, --global would wire KEEL_HOME and leave $HOME/.claude — the home this
# finding names — untouched, so the warning could never clear. Same defect as the retargeted case,
# mirrored (operator-run /code-review, 5th pass).
run env KEEL_HOME="$SANDBOX/elsewhere-home" "$doctor" --install "$HOME/.claude"
check_contains "with KEEL_HOME set elsewhere, the default home gets --home too" "$OUT" "--home \"$HOME/.claude\""
check_absent "and not --global, which would wire KEEL_HOME instead" "$OUT" "run --global"

dh_wired="$SANDBOX/dh-wired"
run "$REPO_ROOT/install.sh" --home "$dh_wired" --no-hooks
run env KEEL_HOME="$dh_wired" "$installer" --global
check_status "wiring the freshly-installed home's own gate -> exit 0" 0 "$STATUS"
run "$doctor" --install "$dh_wired"
check_contains "wired gate -> OK" "$OUT" "OK   /polish gate: wired machine-global"

# --- acceptance test 19: W-GATE-UNWIRED/OK advice agrees with the gate manifest --------------------
# dh_wired's OK line above came from a REAL install-pre-pr-gate.sh --global run, so a gate manifest was
# recorded too — the OK line should say so.
check_contains "wired gate + recorded manifest -> OK names the manifest" "$OUT" "manifest confirms"

# Gate genuinely wired, but no manifest was ever recorded (e.g. a pre-dir-125 wire) — advisory nudge to
# re-run the installer, not the "unwired" WARN (the hooks really are there).
dh_wired_nomanifest="$SANDBOX/dh-wired-nomanifest"
run "$REPO_ROOT/install.sh" --home "$dh_wired_nomanifest" --no-hooks
run env KEEL_HOME="$dh_wired_nomanifest" "$installer" --global
check_status "wiring dh_wired_nomanifest's gate -> exit 0" 0 "$STATUS"
rm -f "$dh_wired_nomanifest/.keel/install-manifest.gate"
run "$doctor" --install "$dh_wired_nomanifest"
check_contains "wired gate, no manifest -> still OK (hooks really are there)" "$OUT" "OK   /polish gate: wired machine-global"
check_absent "...and does not falsely claim a manifest confirms it" "$OUT" "manifest confirms"
check_contains "wired gate, no manifest -> W-GATE-MANIFEST-MISSING nudge (dir #150: kept, deterministic default path)" "$OUT" "W-GATE-MANIFEST-MISSING"
check_contains "...naming the installer re-run" "$OUT" "install-pre-pr-gate.sh"

# A gate manifest recorded, but the hooks it claims are wired are gone (hand-edited/stripped settings.json
# outside this installer's own --uninstall) — its OWN id, W-GATE-MANIFEST-DRIFT, not a reuse of the
# install-manifest drift check's W-MANIFEST-DRIFT (an operator-run /code-review high pass found the
# reuse would let .keel/doctor-accept's bare-id matching silently swallow both findings on one accept),
# and not a silent OK or the plain-unwired WARN either.
dh_gate_drift="$SANDBOX/dh-gate-drift"
run "$REPO_ROOT/install.sh" --home "$dh_gate_drift" --no-hooks
run env KEEL_HOME="$dh_gate_drift" "$installer" --global
check_status "wiring dh_gate_drift's gate -> exit 0" 0 "$STATUS"
printf '{}' > "$dh_gate_drift/settings.json"
run "$doctor" --install "$dh_gate_drift"
check_contains "manifest says wired, hooks gone -> W-GATE-MANIFEST-DRIFT" "$OUT" "W-GATE-MANIFEST-DRIFT"
check_absent "...and NOT the install-manifest drift id (bare-id accept collision)" "$OUT" "W-MANIFEST-DRIFT"
check_contains "...naming the recorded settings path" "$OUT" "$dh_gate_drift/settings.json"

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

# --- dir #98 as a CLASS: end-to-end, on the output an adopter actually sees -----------------------
# The exhaustive half of this lives in tools/self/doctor.sh check 1c, which reads the SOURCE — most of
# doctor's advice sits in findings that only fire on a broken install, so no output sweep can reach
# them (an earlier output-only version of this check was vacuous for doctor entirely). What is worth
# asserting HERE is the other half: that the mechanism actually renders, in a real retargeted run,
# rather than merely being present in the source.
sweep_home="$SANDBOX/advice-sweep"
run "$REPO_ROOT/install.sh" --home "$sweep_home" --no-hooks
check_status "retargeted install for the advice sweep -> exit 0" 0 "$STATUS"
check_contains "the summary's uninstall advice names the home" "$OUT" "keel uninstall --home \"$sweep_home\""
check_absent "and no literal, unexpanded flag variable leaked into the text" "$OUT" '$home_flag'
# The health-check and pull-then-rewire lines live in the LINKED summary, so assert them there.
link_home="$SANDBOX/advice-sweep-link"
run "$REPO_ROOT/install.sh" --link --home "$link_home" --no-hooks
check_status "retargeted linked install -> exit 0" 0 "$STATUS"
check_contains "the health-check advice names the home" "$OUT" "doctor.sh --install \"$link_home\""
check_contains "the pull-then-rewire advice names the home" "$OUT" "./install.sh --link --home \"$link_home\""
check_absent "no unexpanded doctor arg" "$OUT" '$doctor_arg'
# The generated keel/README is advice too — it is read long after the install, in the home itself.
check_contains "the generated keel/README names the home" "$(cat "$link_home/keel/README.md")" "--home \"$link_home\""
check_absent "and its backticks survived as markdown, not command substitution" "$(cat "$link_home/keel/README.md")" "no such file"
check_contains "README markdown intact" "$(cat "$link_home/keel/README.md")" '`readlink CORE.md`'
# A --codex install needs --codex on its advice even at the DEFAULT home, where the home flag is
# correctly empty: a bare re-run is Claude copy mode and would land in ~/.claude.
cx_home="$SANDBOX/advice-codex/.codex"
run "$REPO_ROOT/install.sh" --codex --home "$cx_home" --no-hooks
check_status "retargeted codex install -> exit 0" 0 "$STATUS"
check_contains "codex advice carries the mode as well as the home" "$OUT" "install.sh --codex --home \"$cx_home\""
# The mode half alone, at the DEFAULT codex home — where the home flag is correctly empty and only
# --codex stands between the advice and a re-run that lands in ~/.claude.
cx_default="$SANDBOX/codex-default-home"; mkdir -p "$cx_default"
fresh_home_env "$cx_default"
run env "${FRESH_HOME_ENV[@]}" "$REPO_ROOT/install.sh" --codex --no-hooks
check_status "default-home codex install -> exit 0" 0 "$STATUS"
check_contains "its advice still carries --codex" "$OUT" "install.sh --codex"
check_absent "and no home flag, which would be noise there" "$OUT" "--codex --home"
# ...and the ordinary install keeps the short, friendly form — the flag appears only where it earns it.
run "$REPO_ROOT/install.sh" --home "$HOME/.claude" --no-hooks
check_contains "a default-home install still advises the bare command" "$OUT" "keel uninstall  (reverses"

# =================================================================================================
# dir #136: --uninstall — the reverse operation uninstall.sh's own summary now points adopters at.
# Never clobbers your data: only a hook byte-identical to what THIS installer would wire comes out; a
# foreign hook on the same event+matcher, or any other settings.json content, is left exactly alone.
# =================================================================================================
run "$installer" --help
check_contains "--help documents --uninstall" "$OUT" "--uninstall"

# --- (a) nothing wired yet -> nothing to do, exit 0, no file created --------------------------------
urepo="$(new_repo)"
run "$installer" --uninstall "$urepo"
check_status "--uninstall with nothing wired -> exit 0" 0 "$STATUS"
check_contains "says there's nothing to remove" "$OUT" "nothing to remove"
check_nofile "no settings.json was created by an uninstall run" "$urepo/.claude/settings.json"

# --- (b) a full install, then --uninstall removes exactly the 6 hooks it wired ----------------------
run "$installer" "$urepo"
check_status "wiring the fixture -> exit 0" 0 "$STATUS"
run "$installer" --uninstall "$urepo"
check_status "--uninstall over a full install -> exit 0" 0 "$STATUS"
for ev in $FIVE_EVENTS; do
  check_contains "removes $ev" "$OUT" "-    $ev"
done
usj="$(cat "$urepo/.claude/settings.json")"
check_absent "the gate command is gone from PreToolUse/Bash" "$usj" "\"command\": \"bash '$gate'\""
check_absent "the gate command is gone everywhere" "$usj" "$gate"

# --- (c) idempotent: a second --uninstall finds nothing left to remove ------------------------------
run "$installer" --uninstall "$urepo"
check_status "second --uninstall -> exit 0" 0 "$STATUS"
check_contains "second run reports nothing to remove" "$OUT" "nothing to remove"

# --- (d) a foreign hook on the same event+matcher is NEVER removed — only an exact match is ours ----
frepo2="$(new_repo)"
run "$installer" "$frepo2"
check_status "wiring the foreign-hook fixture -> exit 0" 0 "$STATUS"
tmp_foreign="$(mktemp)"
jq '.hooks.PreToolUse[0].hooks[0].command = "echo not-the-gate-anymore"' \
  "$frepo2/.claude/settings.json" > "$tmp_foreign"
mv "$tmp_foreign" "$frepo2/.claude/settings.json"
run "$installer" --uninstall "$frepo2"
check_status "--uninstall over a partly-foreign settings.json -> exit 0" 0 "$STATUS"
check_contains "the foreign PreToolUse/Bash hook is reported as kept, not removed" "$OUT" "PreToolUse/Bash"
check_contains "the still-wired command survives" "$(cat "$frepo2/.claude/settings.json")" "not-the-gate-anymore"
# The other 5, untouched by the foreign edit, ARE exact matches and do come out.
check_absent "the untouched SessionStart hook is still removed" "$(cat "$frepo2/.claude/settings.json")" "rollout-check"

# --- (e) foreign top-level content (e.g. permissions) survives untouched ----------------------------
prepo="$(new_repo)"
run "$installer" "$prepo"
tmp_perm2="$(mktemp)"
jq '. + {permissions: {allow: ["Bash(ls:*)"]}}' "$prepo/.claude/settings.json" > "$tmp_perm2"
mv "$tmp_perm2" "$prepo/.claude/settings.json"
run "$installer" --uninstall "$prepo"
check_status "--uninstall over settings.json with foreign top-level keys -> exit 0" 0 "$STATUS"
check_contains "the foreign key survives" "$(cat "$prepo/.claude/settings.json")" '"permissions"'

# --- (f) --global / --home target the same way --uninstall does the same way install does ----------
ughome="$SANDBOX/uninstall-global-gate-home"
run env KEEL_HOME="$ughome" "$installer" --global
run env KEEL_HOME="$ughome" "$installer" --uninstall --global
check_status "--uninstall --global -> exit 0" 0 "$STATUS"
check_absent "the machine-global settings.json no longer carries the gate" "$(cat "$ughome/settings.json")" "$gate"

uhhome="$SANDBOX/uninstall-home-flag"; mkdir -p "$uhhome"
run "$installer" --home "$uhhome"
run "$installer" --uninstall --home "$uhhome"
check_status "--uninstall --home DIR -> exit 0" 0 "$STATUS"
check_absent "the retargeted settings.json no longer carries the gate" "$(cat "$uhhome/settings.json")" "$gate"

# --- (g) no jq -> instructions printed, nothing changed ----------------------------------------------
farm2="$(mktemp -d)"; path_farm "$farm2" jq
njrepo2="$(new_repo)"
run "$installer" "$njrepo2"
before_nj="$(cat "$njrepo2/.claude/settings.json")"
run env PATH="$farm2" "$installer" --uninstall "$njrepo2"
check_status "no jq -> non-zero (nothing removed)" 1 "$STATUS"
check_contains "explains jq is required" "$OUT" "jq is required"
check_status "settings.json is untouched without jq" "$before_nj" "$(cat "$njrepo2/.claude/settings.json")"

# --- (h) --uninstall + --force don't combine — different, unrelated operations ----------------------
run "$installer" --uninstall --force "$urepo"
check_status "--uninstall + --force -> exit 2 (rejected)" 2 "$STATUS"

summary
