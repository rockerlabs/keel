#!/usr/bin/env bash
# install-pre-pr-gate.sh — wires the /polish gate's 6 hooks into a project's (or the machine-global)
# Claude Code settings.json. dir #68: this is the opt-in step that makes the gate real for an adopter,
# separate from install.sh (which now ships polish.md unconditionally but never wires a hook itself).
# The 5th hook (SubagentStop/keel-polish-reviewer, dir #70, matcher moved by dir #413 slice 2) traces the
# independent-agent-review leg. The 6th
# hook (PostToolUse/AskUserQuestion, dir #88) traces step 5(a)'s MANDATORY review-reminder dialog —
# shares the PostToolUse event with the Skill matcher, so FIVE_EVENTS below still names 5 distinct event
# NAMES even though there are now 6 matcher entries across them.
#
# The installer edits settings.json with jq, so most of these tests need jq. The busybox/Alpine CI job
# installs it (dir #220), so this file runs for real there too, not skip-only. Without jq the installer
# degrades to printing a ready-to-paste snippet instead of writing anything (an explicit, documented,
# already-tested choice —
# see the "no jq" block below, which stays real coverage on the legs that DO have jq by hiding it via
# PATH regardless of what's actually installed).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

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
check_contains "SubagentStop matcher is keel-polish-reviewer (dir #413 slice 2)" "$sj" '"matcher": "keel-polish-reviewer"'
check_absent "A6(a): a fresh install wires no general-purpose matcher" "$sj" '"matcher": "general-purpose"'
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
tmp_perm="$(mktemp "$SANDBOX/settings.XXXXXX")"
jq '. + {permissions: {allow: ["Bash(ls:*)"]}}' "$repo/.claude/settings.json" > "$tmp_perm"
mv "$tmp_perm" "$repo/.claude/settings.json"
run "$installer" "$repo"
check_status "re-run over a settings.json with foreign keys -> exit 0" 0 "$STATUS"
check_contains "foreign top-level key survives" "$(cat "$repo/.claude/settings.json")" '"permissions"'

# --- (b) a foreign hook on the SAME event+matcher -> ours is APPENDED beside it (dir #468) -----------
# The refusal this replaced offered only --force (which deleted the incumbent) or hand-edited JSON.
frepo="$(new_repo)"
mkdir -p "$frepo/.claude"
cat > "$frepo/.claude/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo not-the-gate"}]}]}}
EOF
run "$installer" "$frepo"
check_status "foreign hook on the same event+matcher -> appended, no refusal (exit 0)" 0 "$STATUS"
check_contains "reports the append as APPENDED" "$OUT" "APPENDED"
check_contains "…naming the event/matcher" "$OUT" "PreToolUse/Bash"
check_absent "no backup announced — nothing was replaced" "$OUT" "backed up"
check_status "no backup file was written" 0 "$(find "$frepo/.claude" -name 'settings.json.*.bak' | grep -c . || true)"
sj="$(cat "$frepo/.claude/settings.json")"
check_contains "the incumbent hook is still wired" "$sj" "echo not-the-gate"
check_contains "the pre-pr-gate command is wired beside it" "$sj" "'$gate'"
check_status "the incumbent entry is byte-untouched (ours is a sibling entry)" \
  '{"matcher":"Bash","hooks":[{"type":"command","command":"echo not-the-gate"}]}' \
  "$(jq -c '.hooks.PreToolUse[0]' "$frepo/.claude/settings.json")"
run "$installer" "$frepo"
check_status "re-run after an append -> exit 0" 0 "$STATUS"
check_contains "re-run reports PreToolUse already wired" "$OUT" "=    PreToolUse/Bash"
check_status "re-run adds no further entry" 2 \
  "$(jq '.hooks.PreToolUse | map(select(.matcher == "Bash")) | length' "$frepo/.claude/settings.json")"
run "$installer" --uninstall "$frepo"
check_status "--uninstall after an append -> exit 0" 0 "$STATUS"
sj="$(cat "$frepo/.claude/settings.json")"
check_contains "--uninstall leaves the incumbent hook in place" "$sj" "echo not-the-gate"
check_absent "--uninstall removed pre-pr-gate's own command" "$sj" "'$gate'"

# --- (c) the SAME hook at a different path (a stale install) -> refused; --force swaps just that command
# --force + backup stay for exactly this case: appending would fire the hook twice (old path + new).
crepo="$(new_repo)"
mkdir -p "$crepo/.claude"
cat > "$crepo/.claude/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo not-the-gate"},{"type":"command","command":"bash '/old/checkout/tools/pre-pr-gate.sh'"}]}]}}
EOF
before="$(cat "$crepo/.claude/settings.json")"
run "$installer" "$crepo"
check_status "the same hook at another path -> refused (exit 3)" 3 "$STATUS"
check_contains "refusal names the stale event/matcher" "$OUT" "PreToolUse/Bash"
check_contains "refusal points at --force" "$OUT" "--force"
check_status "settings.json is byte-for-byte untouched" "$before" "$(cat "$crepo/.claude/settings.json")"
run "$installer" --force "$crepo"
check_status "--force -> exit 0" 0 "$STATUS"
check_contains "announces the backup" "$OUT" "backed up your existing settings.json"
bak="$(find "$crepo/.claude" -name 'settings.json.*.bak' | head -n1)"
[ -n "$bak" ] && pass "a timestamped backup sibling exists" || fail "a timestamped backup sibling exists" "none found"
check_contains "backup preserves the stale command" "$(cat "${bak:-/dev/null}")" "/old/checkout/"
sj="$(cat "$crepo/.claude/settings.json")"
check_absent "the stale path is gone from the live file" "$sj" "/old/checkout/"
check_contains "the pre-pr-gate command at this checkout is wired instead" "$sj" "'$gate'"
check_contains "the unrelated sibling command in the same entry survives --force" "$sj" "echo not-the-gate"
run "$installer" --uninstall "$crepo"
check_status "--uninstall after a forced stale swap -> exit 0" 0 "$STATUS"
sj="$(cat "$crepo/.claude/settings.json")"
check_absent "--uninstall removes ours from the shared entry" "$sj" "$gate"
check_contains "--uninstall keeps the sibling command" "$sj" "echo not-the-gate"

# --- (c2) dir #92: our rollout-check already inside a MATCHER-LESS SessionStart entry (the felt shape:
# hand-merged beside the adopter's own hook) is SAME — --force used to add a second "startup" entry, and
# the hook then fired twice on every session start.
mrepo="$(new_repo)"
mkdir -p "$mrepo/.claude"
jq -n --arg c "bash '$gate' rollout-check" \
  '{hooks: {SessionStart: [{hooks: [{type: "command", command: "bash wrap-baseline.sh"}, {type: "command", command: $c}]}]}}' \
  > "$mrepo/.claude/settings.json"
run "$installer" --force "$mrepo"
check_status "--force over a matcher-less entry holding our rollout-check -> exit 0" 0 "$STATUS"
check_contains "reports SessionStart already wired" "$OUT" "=    SessionStart/startup"
check_status "rollout-check is wired exactly once (not duplicated)" 1 \
  "$(jq '[.hooks.SessionStart[].hooks[] | select(.command | endswith("rollout-check"))] | length' "$mrepo/.claude/settings.json")"
check_status "no second SessionStart entry was added" 1 "$(jq '.hooks.SessionStart | length' "$mrepo/.claude/settings.json")"
run "$installer" --uninstall "$mrepo"
check_status "--uninstall -> exit 0" 0 "$STATUS"
check_status "--uninstall takes rollout-check out of the matcher-less entry, the adopter's hook stays" \
  '[{"hooks":[{"type":"command","command":"bash wrap-baseline.sh"}]}]' \
  "$(jq -c '.hooks.SessionStart' "$mrepo/.claude/settings.json")"

# --- (c3) dir #600's live repro: --uninstall prunes only the arrays IT emptied. An already-empty
# SessionStart (one of our event names, holding nothing of ours) used to go too, leaving "hooks": {}.
prepo="$(new_repo)"
mkdir -p "$prepo/.claude"
jq -n --arg c "bash '$gate'" \
  '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c}]}], SessionStart: []}}' \
  > "$prepo/.claude/settings.json"
run "$installer" --uninstall "$prepo"
check_status "--uninstall over our PreToolUse + an empty SessionStart -> exit 0" 0 "$STATUS"
check_status "our emptied PreToolUse is pruned; the already-empty SessionStart is not ours to delete" \
  '{"SessionStart":[]}' "$(jq -c '.hooks' "$prepo/.claude/settings.json")"

# --- (c4) dir #413 slice 2, A6: the SubagentStop matcher moved general-purpose -> keel-polish-reviewer, and
# the installer RETIRES the legacy slot (hook_install_remove on exactly our legacy {type, command}). ---------
legacy_cmd="bash '$gate' skill-trace"
foreign_cmd="echo foreign-subagent-hook"
nhooks() { jq '[.hooks[][] | .hooks[]] | length' "$1"; }
no_empty_hooks() { jq -e '[.hooks[][] | (.hooks // [] | length)] | all(. > 0)' "$1" >/dev/null 2>&1 && echo yes || echo no; }

# (a) fresh: the SubagentStop matchers are exactly ["keel-polish-reviewer"], 6 hook entries, no `retired` line.
a_repo="$(new_repo)"
run "$installer" "$a_repo"
check_status "A6(a): fresh install -> exit 0" 0 "$STATUS"
check_status "A6(a): SubagentStop matchers are exactly [keel-polish-reviewer]" '["keel-polish-reviewer"]' \
  "$(jq -c '[.hooks.SubagentStop[].matcher]' "$a_repo/.claude/settings.json")"
check_status "A6(a): 6 hook entries" 6 "$(nhooks "$a_repo/.claude/settings.json")"
check_absent "A6(a): a fresh install prints no retired line" "$OUT" "retired"

# (b1) legacy + a foreign hook INSIDE the same entry; (b2) the foreign hook in a SIBLING entry.
for shape in same-entry sibling-entry; do
  b_repo="$(new_repo)"; mkdir -p "$b_repo/.claude"
  if [ "$shape" = same-entry ]; then
    jq -n --arg l "$legacy_cmd" --arg f "$foreign_cmd" \
      '{hooks:{SubagentStop:[{matcher:"general-purpose",hooks:[{type:"command",command:$f},{type:"command",command:$l}]}]}}' > "$b_repo/.claude/settings.json"
  else
    jq -n --arg l "$legacy_cmd" --arg f "$foreign_cmd" \
      '{hooks:{SubagentStop:[{matcher:"general-purpose",hooks:[{type:"command",command:$l}]},{matcher:"general-purpose",hooks:[{type:"command",command:$f}]}]}}' > "$b_repo/.claude/settings.json"
  fi
  b_before="$(cat "$b_repo/.claude/settings.json")"
  run "$installer" "$b_repo"
  check_status "A6(b/$shape): legacy + foreign seeded -> exit 0" 0 "$STATUS"
  check_contains "A6(b/$shape): prints a retired line for the legacy slot" "$OUT" "SubagentStop/general-purpose retired"
  b_sj="$b_repo/.claude/settings.json"
  check_status "A6(b/$shape): our legacy command is gone from the legacy slot" 0 \
    "$(jq --arg l "$legacy_cmd" '[.hooks.SubagentStop[] | select(.matcher=="general-purpose") | .hooks[] | select(.command==$l)] | length' "$b_sj")"
  check_status "A6(b/$shape): the foreign hook stays" 1 \
    "$(jq --arg f "$foreign_cmd" '[.hooks.SubagentStop[].hooks[] | select(.command==$f)] | length' "$b_sj")"
  check_status "A6(b/$shape): the new slot exists" 1 \
    "$(jq '[.hooks.SubagentStop[] | select(.matcher=="keel-polish-reviewer")] | length' "$b_sj")"
  check_status "A6(b/$shape): no empty hooks array or entry remains" yes "$(no_empty_hooks "$b_sj")"
  b_bak="$(find "$b_repo/.claude" -name 'settings.json.*.bak' | head -n1)"
  [ -n "$b_bak" ] && pass "A6(b/$shape): a .bak was written" || fail "A6(b/$shape): a .bak was written" "none found"
  check_status "A6(b/$shape): the .bak is byte-equal to the settings BEFORE the run (it holds our legacy command)" \
    "$b_before" "$(cat "${b_bak:-/dev/null}")"
  # (c) already migrated: re-run -> SAME, no retired line, content unchanged, no second backup.
  b_after="$(cat "$b_sj")"
  b_nbak="$(find "$b_repo/.claude" -name 'settings.json.*.bak' | grep -c . || true)"
  run "$installer" "$b_repo"
  check_status "A6(c/$shape): re-run over a migrated settings -> exit 0" 0 "$STATUS"
  check_absent "A6(c/$shape): re-run prints no retired line" "$OUT" "retired"
  check_contains "A6(c/$shape): re-run reports the new slot already wired" "$OUT" "=    SubagentStop/keel-polish-reviewer"
  check_status "A6(c/$shape): settings content unchanged" "$b_after" "$(cat "$b_sj")"
  check_status "A6(c/$shape): no second backup" "$b_nbak" "$(find "$b_repo/.claude" -name 'settings.json.*.bak' | grep -c . || true)"
done

# (b3) our legacy command inside a MATCHER-LESS SubagentStop entry (hand-merged; the merge's `covers` reads it
# as SAME for the new matcher, so retiring AFTER the merge would strip the only copy): afterwards our command
# is wired exactly once, under the new matcher.
m_repo="$(new_repo)"; mkdir -p "$m_repo/.claude"
jq -n --arg l "$legacy_cmd" '{hooks:{SubagentStop:[{hooks:[{type:"command",command:$l}]}]}}' > "$m_repo/.claude/settings.json"
run "$installer" "$m_repo"
check_status "A6(b3): a legacy command in a matcher-less entry -> exit 0" 0 "$STATUS"
check_status "A6(b3): our SubagentStop command is wired exactly once" 1 \
  "$(jq --arg l "$legacy_cmd" '[.hooks.SubagentStop[].hooks[] | select(.command==$l)] | length' "$m_repo/.claude/settings.json")"
check_status "A6(b3): ...and it sits under the new matcher" '["keel-polish-reviewer"]' \
  "$(jq -c --arg l "$legacy_cmd" '[.hooks.SubagentStop[] | select(any(.hooks[]; .command==$l)) | .matcher]' "$m_repo/.claude/settings.json")"

# (d) --uninstall on a settings holding ONLY the legacy entry removes it and does not exit "nothing to remove".
u_repo="$(new_repo)"; mkdir -p "$u_repo/.claude"
jq -n --arg l "$legacy_cmd" '{hooks:{SubagentStop:[{matcher:"general-purpose",hooks:[{type:"command",command:$l}]}]}}' > "$u_repo/.claude/settings.json"
run "$installer" --uninstall "$u_repo"
check_status "A6(d): --uninstall over a legacy-only settings -> exit 0" 0 "$STATUS"
check_absent "A6(d): it does not say nothing-to-remove" "$OUT" "nothing to remove"
check_status "A6(d): the legacy entry is gone" "null" "$(jq -c '.hooks.SubagentStop' "$u_repo/.claude/settings.json")"
check_contains "A6(d): the counter counts current specs only (0 of 6)" "$OUT" "0 of 6 hook(s) removed"
# ...and with a foreign hook on the legacy slot the foreign hook survives --uninstall.
uf_repo="$(new_repo)"; mkdir -p "$uf_repo/.claude"
jq -n --arg l "$legacy_cmd" --arg f "$foreign_cmd" \
  '{hooks:{SubagentStop:[{matcher:"general-purpose",hooks:[{type:"command",command:$f},{type:"command",command:$l}]}]}}' > "$uf_repo/.claude/settings.json"
run "$installer" --uninstall "$uf_repo"
check_status "A6(d): --uninstall with a foreign hook on the legacy slot -> exit 0" 0 "$STATUS"
check_status "A6(d): the foreign hook survives" 1 \
  "$(jq --arg f "$foreign_cmd" '[.hooks.SubagentStop[].hooks[] | select(.command==$f)] | length' "$uf_repo/.claude/settings.json")"
check_status "A6(d): our legacy command is gone" 0 \
  "$(jq --arg l "$legacy_cmd" '[.hooks.SubagentStop[].hooks[] | select(.command==$l)] | length' "$uf_repo/.claude/settings.json")"
# a full install then --uninstall still reports the numerator as 6 of 6, never more.
run "$installer" --uninstall "$a_repo"
check_contains "A6(d): a full uninstall reports 6 of 6" "$OUT" "6 of 6 hook(s) removed"

# --- (d) no jq on PATH -> snippet printed instead of a write, file untouched ------------------------
farm="$(mktemp -d "$SANDBOX/farm.XXXXXX")"; path_farm "$farm" jq
njrepo="$(new_repo)"
run env PATH="$farm" "$installer" "$njrepo"
check_status "no jq -> non-zero (nothing installed)" 1 "$STATUS"
check_contains "explains jq is required" "$OUT" "jq is required"
check_contains "prints a ready-to-paste snippet" "$OUT" "\"hooks\""
check_contains "snippet names the gate path" "$OUT" "$gate"
check_contains "A6(e): the no-jq snippet shows the new SubagentStop matcher" "$OUT" '"matcher": "keel-polish-reviewer"'
check_absent "A6(e): the no-jq snippet contains no general-purpose" "$OUT" '"general-purpose"'
check_nofile "no jq -> settings.json was never written" "$njrepo/.claude/settings.json"

# --- (d2) regression (dir #514): the no-jq snippet path has its OWN escaping (the jq `@sh` fix above
# never runs here — a heredoc can't call a jq filter), and it is untested by every other apostrophe
# check in this file, all of which exercise the jq-present write path. Found live by this ticket's own
# unit test for tools/lib/sh-quote.sh: a first version of the fix double-quoted the `${var//pat/repl}`
# expansion in the assignment (`gate_sh="${gate//\'/\'\\\'\'}"`), which bash parses differently than
# the identical expansion left unquoted — it silently OVER-escaped every apostrophe
# (`Alex's` -> `Alex\'\\'\'s`, not the intended `Alex'\''s`) and would have shipped a snippet just as
# broken as the bug this ticket exists to fix, just one layer further from any existing test. An
# apostrophe-bearing checkout, no jq on PATH: the printed snippet's own command must still round-trip.
apostrophe_fixture_checkout "no-jq checkout"; apnjck="$APOSTROPHE_CKDIR"
apnjrepo="$(new_repo)"
run env PATH="$farm" "$apnjck/tools/install-pre-pr-gate.sh" "$apnjrepo"
check_status "no jq, apostrophe checkout -> non-zero (nothing installed)" 1 "$STATUS"
# The snippet's own text is what an adopter copy-pastes into settings.json — it must be VALID JSON,
# not just a string a permissive sed regex can pull a "command" field out of (found by an independent
# /code-review medium pass: sh_quote's `'\''`-doubling introduces a literal backslash, and a bare `\'`
# is not one of JSON's own recognized escapes, so the FIRST version of this fix printed a snippet that
# was invalid JSON whenever the checkout path held an apostrophe — jq itself rejected it — even though
# the shell-level escaping was already correct; the bug had just moved up one layer, invisible to a
# regex-based extraction that never actually parses the snippet). Extract just the JSON body (first
# `{` to the matching final `}`) and prove `jq .` accepts it before trusting anything jq reads from it.
apnjjson="$(printf '%s\n' "$OUT" | sed -n '/^{$/,/^}$/p')"
run bash -c "printf '%s' \"\$1\" | jq ." -- "$apnjjson"
check_status "the printed snippet is itself valid JSON (not just command-shaped text)" 0 "$STATUS"
apnjcmd="$(printf '%s' "$apnjjson" | jq -r '.hooks.PreToolUse[0].hooks[0].command')"
apostrophe_cmd_argv "$apnjcmd"
check_status "no-jq snippet's argv resolves back to the real (unescaped) path" \
  "$apnjck/tools/pre-pr-gate.sh" "${APOSTROPHE_ARGV[1]}"

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

# --- dir #413 slice 2, A13: W-GATE-REVIEW-MATCHER — the gate is wired but its SubagentStop slot still carries
# the LEGACY general-purpose matcher (a pull without re-running the gate installer): both halves. ----------
# bad sample: the RN2 shape (machine-global, a retargeted home so the advice must carry --home).
dh_legacy="$SANDBOX/dh-legacy-matcher"
run "$REPO_ROOT/install.sh" --home "$dh_legacy" --no-hooks
run env KEEL_HOME="$dh_legacy" "$installer" --global
jq '.hooks.SubagentStop[0].matcher = "general-purpose"' "$dh_legacy/settings.json" > "$dh_legacy/settings.json.tmp" \
  && mv "$dh_legacy/settings.json.tmp" "$dh_legacy/settings.json"
run "$doctor" --install "$dh_legacy"
check_contains "A13: gate wired with only the legacy SubagentStop matcher -> W-GATE-REVIEW-MATCHER" "$OUT" "W-GATE-REVIEW-MATCHER"
check_contains "A13: the advice names the installer with the --home flag when the home is retargeted" "$OUT" "install-pre-pr-gate.sh --home \"$dh_legacy\""
# good sample: the migrated settings (a real install) -> the finding is absent.
run "$doctor" --install "$dh_wired"
check_absent "A13: a migrated settings -> no W-GATE-REVIEW-MATCHER" "$OUT" "W-GATE-REVIEW-MATCHER"
# a matcher-less SubagentStop entry holding our command fires on every agent type, so it is as wired as the named one
dh_matchless="$SANDBOX/dh-matchless-matcher"
run "$REPO_ROOT/install.sh" --home "$dh_matchless" --no-hooks
run env KEEL_HOME="$dh_matchless" "$installer" --global
jq 'del(.hooks.SubagentStop[0].matcher)' "$dh_matchless/settings.json" > "$dh_matchless/settings.json.tmp" \
  && mv "$dh_matchless/settings.json.tmp" "$dh_matchless/settings.json"
run "$doctor" --install "$dh_matchless"
check_absent "A13: a matcher-less SubagentStop entry holding our command is not flagged" "$OUT" "W-GATE-REVIEW-MATCHER"
# without jq doctor cannot structurally back a finding, so it stays silent rather than guess (fail-open)
run env PATH="$farm" "$doctor" --install "$dh_legacy"
check_contains "A13: ...and doctor still ran its gate check without jq" "$OUT" "/polish gate: wired machine-global"
check_absent "A13: no jq -> no W-GATE-REVIEW-MATCHER guess" "$OUT" "W-GATE-REVIEW-MATCHER"
# the per-project half
legproj="$(new_repo)"; clean_baseline "$legproj"
run "$installer" "$legproj"
jq '.hooks.SubagentStop[0].matcher = "general-purpose"' "$legproj/.claude/settings.json" > "$legproj/.claude/settings.json.tmp" \
  && mv "$legproj/.claude/settings.json.tmp" "$legproj/.claude/settings.json"
run "$doctor" "$legproj"
check_status "A13: W-GATE-REVIEW-MATCHER is advisory only -> exit 0" 0 "$STATUS"
check_contains "A13: project scope, legacy matcher -> W-GATE-REVIEW-MATCHER" "$OUT" "W-GATE-REVIEW-MATCHER"
check_contains "A13: ...naming the project installer re-run" "$OUT" "install-pre-pr-gate.sh $legproj"
run "$doctor" "$fullgate"
check_absent "A13: project scope, migrated settings -> no W-GATE-REVIEW-MATCHER" "$OUT" "W-GATE-REVIEW-MATCHER"

# --- regression: a checkout path containing a space still produces a working (single-token) command --
sp_root="$(mktemp -d "$SANDBOX/space.XXXXXX")/space checkout"
mkdir -p "$sp_root/tools"
cp "$installer" "$sp_root/tools/install-pre-pr-gate.sh"
cp "$gate" "$sp_root/tools/pre-pr-gate.sh"
# pre-pr-gate.sh sources tools/lib/nonneg-int.sh (dir #196) at startup, unconditionally — a real
# checkout always carries tools/lib/ alongside it (nothing is copied OUT of the checkout in normal
# use), so this fixture's own space-path copy needs to too, or the space-path regression it's actually
# testing gets masked by an unrelated "lib file not found" failure.
cp -r "$REPO_ROOT/tools/lib" "$sp_root/tools/lib"
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
tmp_foreign="$(mktemp "$SANDBOX/settings.XXXXXX")"
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
tmp_perm2="$(mktemp "$SANDBOX/settings.XXXXXX")"
jq '. + {permissions: {allow: ["Bash(ls:*)"]}}' "$prepo/.claude/settings.json" > "$tmp_perm2"
mv "$tmp_perm2" "$prepo/.claude/settings.json"
run "$installer" --uninstall "$prepo"
check_status "--uninstall over settings.json with foreign top-level keys -> exit 0" 0 "$STATUS"
check_contains "the foreign key survives" "$(cat "$prepo/.claude/settings.json")" '"permissions"'

# --- (e2) --uninstall must not silently delete an UNRELATED empty hook array (dir #564) --------------
# Regression pin: the removal jq program used to prune EVERY empty array under .hooks after removing
# ours, not just the events this installer's own hook_specs ever touches — so an unrelated event some
# other tool had wired as an empty array (e.g. a temporarily-disabled hook) vanished too, contradicting
# this file's own "everything else...left exactly as it was" claim (sync-twin drift with
# install-read-trace.sh, which already carried the scoped fix). Fixed by scoping the post-removal prune
# to only the event names this installer's own hook_specs ever name.
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
farm2="$(mktemp -d "$SANDBOX/farm.XXXXXX")"; path_farm "$farm2" jq
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

# --- (i) regression (dir #514): a checkout path containing an apostrophe must still produce a hook
# command the shell can parse and run. Before the fix, $gate was spliced into `"bash '" + $gate + "'"`
# by hand — a checkout at `~/Alex's checkout/keel` produced `bash 'Alex's checkout/…'`, an unterminated
# quote ("unexpected EOF while looking for matching quote"), and every wired hook silently broke. A
# disposable copy of the checkout (never $REPO_ROOT itself) under an apostrophe-bearing dir name,
# scoped to `tools/` only (shared helper, tests/lib.sh — see its own comment for why).
apostrophe_fixture_checkout "checkout"; apck="$APOSTROPHE_CKDIR"
aprepo="$(new_repo)"
run "$apck/tools/install-pre-pr-gate.sh" "$aprepo"
check_status "install from an apostrophe-bearing checkout path -> exit 0" 0 "$STATUS"
apcmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$aprepo/.claude/settings.json")"
# The apostrophe is escaped (`'\''`), so the raw path never appears as one contiguous substring in
# $apcmd — let the shell that will actually run this command do the unescaping (the real proof: not
# a hand-rolled unescaper, the same word-splitting the hook runner itself performs), and compare its
# argv[1] against the real, unescaped path.
apostrophe_cmd_argv "$apcmd"
check_status "the escaped command's argv resolves back to the real (unescaped) path" \
  "$apck/tools/pre-pr-gate.sh" "${APOSTROPHE_ARGV[1]}"
printf '%s\n' "$apcmd" > "$SANDBOX/apostrophe-command.sh"
run bash -n "$SANDBOX/apostrophe-command.sh"
check_status "the generated command parses (bash -n)" 0 "$STATUS"
# The "hook fires" half, not just "parses": actually run it, the way Claude Code's hook runner would —
# rollout-check reads a JSON blob on stdin and exits 0 (jq present, see the file-top jq guard above).
run bash -c "printf '{}' | $apcmd"
check_status "the generated command actually runs (the hook fires)" 0 "$STATUS"

summary
