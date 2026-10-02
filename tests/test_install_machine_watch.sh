#!/usr/bin/env bash
# install-machine-watch.sh (dir #437 PR2, MW7) — wires tools/machine-watch.sh's 4 hooks into a project's
# (or the machine-global) Claude Code settings.json. Same installer contract as install-read-trace.sh:
# additive merge, a foreign hook on the same slot is appended beside (dir #468), --force only for a stale
# path, --uninstall removes exactly its own entries.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

installer="$REPO_ROOT/tools/install-machine-watch.sh"
mw="$REPO_ROOT/tools/machine-watch.sh"
GATE_INSTALLER="$REPO_ROOT/tools/install-pre-pr-gate.sh"
RT_INSTALLER="$REPO_ROOT/tools/install-read-trace.sh"

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — install-machine-watch tests skipped (the installer requires jq to edit settings.json)"
  summary; exit $?
fi

# n_ours SETTINGS — how many hook commands in SETTINGS run machine-watch.sh.
n_ours() { jq '[.hooks[]?[]?.hooks[]? | select(.command | contains("machine-watch.sh"))] | length' "$1"; }

# --- --help / bad args ---------------------------------------------------------------------------------
run "$installer" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
# I4: the two trade-offs are stated, one line each
check_contains "I4 --help names project scope as the documented default" "$OUT" "project scope (the default)"
check_contains "I4 --help states project scope's trade-off" "$OUT" "covers only sessions started in that repo"
check_contains "I4 --help states --global's trade-off" "$OUT" "dies with ~/.claude"
check_contains "--help names the tool Claude-Code-only" "$OUT" "Claude Code"
run "$installer"
check_status "no args -> exit 2" 2 "$STATUS"
run "$installer" /no/such/dir
check_status "not a git repo -> exit 2" 2 "$STATUS"
run "$installer" --global /some/repo
check_status "--global + a repo path -> exit 2" 2 "$STATUS"
run "$installer" --uninstall --force "$SANDBOX"
check_status "--uninstall + --force -> exit 2" 2 "$STATUS"

# --- I1: project scope wires exactly the 4 specs, next to the gate's and read-trace's hooks -------------
repo="$(new_repo)"
"$GATE_INSTALLER" "$repo" >/dev/null 2>&1
"$RT_INSTALLER" "$repo" >/dev/null 2>&1
others_before="$(jq -c '[.hooks[][].hooks[].command]' "$repo/.claude/settings.json")"
run "$installer" "$repo"
check_status "I1 project scope install -> exit 0" 0 "$STATUS"
sj="$repo/.claude/settings.json"
check_status "I1 exactly 4 machine-watch hooks are wired" 4 "$(n_ours "$sj")"
check_eq "I1 SessionStart / any source" "1" \
  "$(jq '[.hooks.SessionStart[] | select(.matcher == "") | .hooks[] | select(.command | contains("machine-watch.sh") and contains(" hook"))] | length' "$sj")"
check_eq "I1 PostToolUse / Bash|Write|Edit|NotebookEdit" "1" \
  "$(jq '[.hooks.PostToolUse[] | select(.matcher == "Bash|Write|Edit|NotebookEdit") | .hooks[] | select(.command | contains("machine-watch.sh"))] | length' "$sj")"
check_eq "I1 PostToolUseFailure / Bash|Write|Edit|NotebookEdit" "1" \
  "$(jq '[.hooks.PostToolUseFailure[] | select(.matcher == "Bash|Write|Edit|NotebookEdit") | .hooks[] | select(.command | contains("machine-watch.sh"))] | length' "$sj")"
check_eq "I1 SessionEnd / any reason" "1" \
  "$(jq '[.hooks.SessionEnd[] | select(.matcher == "") | .hooks[] | select(.command | contains("machine-watch.sh"))] | length' "$sj")"
check_contains "I1 the command points at THIS checkout's tool by absolute path (no copy)" "$(cat "$sj")" "'$mw' hook"
others_after="$(jq -c '[.hooks[][].hooks[] | select(.command | contains("machine-watch.sh") | not) | .command]' "$sj")"
check_eq "I1 the gate's and read-trace's hooks are left untouched" "$others_before" "$others_after"
check_dir "I1 the baseline store dir is created at install time (MW5/MW7)" "$KEEL_MACHINE_WATCH_STORE"
check_absent "the install message does not carry the stale 'load only at session start' line" "$OUT" "hooks load only at session start"
if grep -q 'hooks load only at session start' "$installer"; then
  fail "the installer source does not copy the stale restart line" "tools/install-machine-watch.sh still says hooks load only at session start"
else
  pass "the installer source does not copy the stale restart line"
fi

# --- I2: idempotent; a foreign hook is appended beside; a stale path needs --force --------------------
run "$installer" "$repo"
check_status "I2 re-run -> exit 0" 0 "$STATUS"
check_contains "I2 re-run reports already wired" "$OUT" "=    SessionStart/"
check_status "I2 re-run adds no duplicate" 4 "$(n_ours "$sj")"
frepo="$(new_repo)"; mkdir -p "$frepo/.claude"
cat > "$frepo/.claude/settings.json" <<EOF
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo not-the-tool"}]}]}}
EOF
run "$installer" "$frepo"
check_status "I2 a foreign hook on the same event+matcher -> appended beside it (exit 0)" 0 "$STATUS"
check_contains "I2 reported as APPENDED" "$OUT" "APPENDED"
check_contains "I2 the incumbent survives" "$(cat "$frepo/.claude/settings.json")" "echo not-the-tool"
crepo="$(new_repo)"; mkdir -p "$crepo/.claude"
cat > "$crepo/.claude/settings.json" <<EOF
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash '/old/checkout/tools/machine-watch.sh' hook"}]}]}}
EOF
before="$(cat "$crepo/.claude/settings.json")"
run "$installer" "$crepo"
check_status "I2 the same hook at another path -> refused (exit 3)" 3 "$STATUS"
check_contains "I2 the refusal points at --force" "$OUT" "--force"
check_eq "I2 a refusal leaves settings.json byte-for-byte untouched" "$before" "$(cat "$crepo/.claude/settings.json")"
run "$installer" --force "$crepo"
check_status "I2 --force -> exit 0" 0 "$STATUS"
bak="$(find "$crepo/.claude" -name 'settings.json.*.bak' | head -n1)"
[ -n "$bak" ] && pass "I2 --force leaves a timestamped .bak" || fail "I2 --force leaves a timestamped .bak" "none found"
check_absent "I2 the stale path is gone after --force" "$(cat "$crepo/.claude/settings.json")" "/old/checkout/"

# --- I3: --uninstall removes exactly the 4 specs and nothing else --------------------------------------
run "$installer" --uninstall "$repo"
check_status "I3 --uninstall -> exit 0" 0 "$STATUS"
check_status "I3 no machine-watch hook is left" 0 "$(n_ours "$sj")"
check_eq "I3 everything else is untouched" "$others_before" "$(jq -c '[.hooks[][].hooks[].command]' "$sj")"
run "$installer" --uninstall "$repo"
check_status "I3 a second --uninstall -> exit 0" 0 "$STATUS"
check_contains "I3 …and says there is nothing to remove" "$OUT" "nothing to remove"

# --- scope flags: --global and --home DIR ---------------------------------------------------------------
ghome="$SANDBOX/ghome"; mkdir -p "$ghome"
run env "KEEL_HOME=$ghome" "$installer" --global
check_status "--global (KEEL_HOME) -> exit 0" 0 "$STATUS"
check_status "--global wires the 4 specs into KEEL_HOME/settings.json" 4 "$(n_ours "$ghome/settings.json")"
hhome="$SANDBOX/hhome"; mkdir -p "$hhome"
run "$installer" --home "$hhome"
check_status "--home DIR -> exit 0" 0 "$STATUS"
check_status "--home wires the 4 specs into DIR/settings.json" 4 "$(n_ours "$hhome/settings.json")"
run "$installer" --home "$SANDBOX/no-such-home"
check_status "--home a missing dir -> exit 2" 2 "$STATUS"

# --- --print: the hooks JSON, nothing written ----------------------------------------------------------
prepo="$(new_repo)"
run "$installer" --print "$prepo"
check_status "--print -> exit 0" 0 "$STATUS"
check_nofile "--print writes nothing" "$prepo/.claude/settings.json"
check_contains "--print shows the 4 events" "$OUT" "PostToolUseFailure"
check_contains "--print is the ready-to-paste hooks object" "$OUT" '"hooks"'
# the no-jq paste-in snippet is a second spelling of the 4 specs: it must name the same event+matcher pairs
# (and the same command) as what an install actually wires, or the fallback diverges silently
ours='[.hooks | to_entries[] | .key as $e | .value[] | select(.hooks[].command | contains("machine-watch.sh")) | [$e, .matcher, .hooks[0].command]] | sort'
qrepo="$(new_repo)"; "$installer" "$qrepo" >/dev/null 2>&1
check_eq "--print names the same event+matcher+command triples the install wires" \
  "$(jq -c "$ours" "$qrepo/.claude/settings.json" 2>/dev/null || true)" "$(jq -c "$ours" <<<"$OUT")"

# --- no jq: a snippet, nothing written -----------------------------------------------------------------
farm="$(mktemp -d)"; path_farm "$farm" jq
njrepo="$(new_repo)"
run env PATH="$farm" "$installer" "$njrepo"
check_status "no jq -> non-zero (nothing installed)" 1 "$STATUS"
check_contains "no jq -> explains jq is required" "$OUT" "jq is required"
check_nofile "no jq -> settings.json was never written" "$njrepo/.claude/settings.json"

# --- apostrophe checkout: the command stays valid shell (dir #514) --------------------------------------
apostrophe_fixture_checkout "mw checkout"; apck="$APOSTROPHE_CKDIR"
aprepo="$(new_repo)"
run "$apck/tools/install-machine-watch.sh" "$aprepo"
check_status "apostrophe checkout -> install exit 0" 0 "$STATUS"
apcmd="$(jq -r '.hooks.SessionEnd[] | .hooks[] | select(.command | contains("machine-watch.sh")) | .command' "$aprepo/.claude/settings.json")"
printf '%s\n' "$apcmd" > "$SANDBOX/apostrophe-mw-command.sh"
run bash -n "$SANDBOX/apostrophe-mw-command.sh"
check_status "the generated command parses (bash -n)" 0 "$STATUS"

# --- the installer never writes a deny rule (prevention is a documented recipe only, MW9) --------------
if grep -v '^[[:space:]]*#' "$installer" | grep -q 'permissions'; then
  fail "the installer never writes permissions.deny" "tools/install-machine-watch.sh mentions permissions outside a comment"
else
  pass "the installer never writes permissions.deny"
fi

# --- macOS: the one-time Script Editor step is named on install (dir #657 follow-up) --------------------
# Re-runs on the already-wired $repo (the note prints on every install run). The gate is osascript alone:
# the notify env vars belong to the hook's environment, which the installer cannot see (tests/lib.sh's
# suite-wide KEEL_MACHINE_WATCH_NOTIFY=0 is in force here, and must not suppress the note).
stub="$SANDBOX/osascript-stub"; mkdir -p "$stub"
printf '#!/bin/sh\nexit 0\n' > "$stub/osascript"; chmod +x "$stub/osascript"
run env PATH="$stub:$PATH" "$installer" "$repo"
check_status "with osascript on PATH -> install exit 0" 0 "$STATUS"
check_contains "with osascript on PATH the install names the Script Editor step" "$OUT" "open Script Editor, run"
check_contains "the note names the off switch it cannot see" "$OUT" "skip this if KEEL_MACHINE_WATCH_NOTIFY=0"
noosa="$SANDBOX/no-osascript-bin"; path_farm "$noosa" osascript
run env PATH="$noosa" "$installer" "$repo"
check_status "without osascript -> install exit 0" 0 "$STATUS"
check_absent "without osascript the install says nothing about Script Editor" "$OUT" "Script Editor"
for f in README.md docs/delegation.md; do
  pin "$f names the one-time Script Editor step" "$REPO_ROOT/$f" 'display notification "test" with title "keel"' \
    "expected $f to carry the Script Editor permission step (dir #657)"
done

# --- the docs name both tools wherever an adopter looks (README, ADAPTING, reference, delegation) ------
for f in README.md ADAPTING.md docs/reference.md docs/delegation.md; do
  pin "$f names machine-watch" "$REPO_ROOT/$f" "machine-watch" "expected $f to carry the watcher (dir #437 PR2)"
done

summary
