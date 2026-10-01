#!/usr/bin/env bash
# tools/machine-watch.sh (dir #437 PR2, MW1-MW6): the machine-global watcher — fingerprints a defined set
# of machine-global paths and reports what changed around a tool call. Every case below runs in its own
# throwaway home under the suite sandbox; the hook's environment is set per case (the watched set is
# resolved in the HOOK's env, MW1).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

mw="$REPO_ROOT/tools/machine-watch.sh"
FIXED='This watcher cannot tell who made the change — another session, the operator, or a background process may have. Tell the operator what changed. Do not restore or revert it yourself unless you can show that your own last command made this exact change.'

if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — machine-watch hook tests skipped (hook mode needs jq to parse and emit JSON)"
  summary; exit $?
fi

# --- fixtures -------------------------------------------------------------------------------------
# mkcase NAME — a fresh case home under the sandbox with every watched kind present; sets $H (the
# case HOME), $HH (its harness home, KEEL_HOME), $HK (its effective core.hooksPath dir) and the array
# $ENVV (the hook's env: HOME, GIT_CONFIG_GLOBAL, KEEL_HOME, the sandboxed store override).
mkcase() {
  H="$SANDBOX/case-$1"; HH="$H/harness"; HK="$H/hooks"
  mkdir -p "$H/.ssh" "$HH/.keel" "$HK" "$H/.config/app" "$H/store"
  printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
  git config --file "$H/.gitconfig" core.hooksPath "$HK"
  printf '#!/bin/sh\nexit 0\n' > "$HK/pre-commit"; chmod 755 "$HK/pre-commit"
  printf 'Host example\n' > "$H/.ssh/config"
  printf 'example ssh-ed25519 AAAA\n' > "$H/.ssh/known_hosts"
  printf 'export A=1\n' > "$H/.zshrc"
  printf '{}\n' > "$HH/settings.json"
  printf '# memory\n' > "$HH/CLAUDE.md"
  printf 'k=v\n' > "$H/.config/app/conf"
  ENVV=("HOME=$H" "GIT_CONFIG_GLOBAL=$H/.gitconfig" "KEEL_HOME=$HH" "KEEL_MACHINE_WATCH_STORE=$H/store")
}
# mw ARGS… — run the tool in the case env (stdin closed, stderr merged), into $OUT/$STATUS.
mw() { run env "${ENVV[@]}" bash "$mw" "$@"; }
# hook EVENT [SESSION] — feed one hook payload to `machine-watch.sh hook`; stdout only into $OUT.
hook() {
  local ev="$1" sid="${2:-s1}"
  OUT="$(printf '{"session_id":"%s","hook_event_name":"%s","tool_name":"Bash"}' "$sid" "$ev" \
    | env "${ENVV[@]}" bash "$mw" hook 2>/dev/null)"
  STATUS=$?
}
jq_ok() { jq -e "$1" >/dev/null 2>&1 <<<"$OUT"; }
tick() { sleep 1; }   # a ctime tree scan needs the change strictly newer than the stamp (busybox: seconds)

# --- W1: nothing changed -> silent, in CLI and hook mode --------------------------------------------
mkcase w1
mw snapshot a;  check_status "W1 snapshot -> exit 0" 0 "$STATUS"
mw check a;     check_status "W1 check with nothing changed -> exit 0" 0 "$STATUS"
check_eq "W1 check with nothing changed prints nothing" "" "$OUT"
hook SessionStart; hook PostToolUse
check_status "W1 hook mode -> exit 0" 0 "$STATUS"
check_eq "W1 hook mode with nothing changed prints nothing" "" "$OUT"

# --- W2: a content change in the global git config ---------------------------------------------------
mkcase w2
mw snapshot a
printf '[user]\n\tname = Mallory\n' >> "$H/.gitconfig"
mw check a
check_status "W2 check after a content change -> exit 1" 1 "$STATUS"
check_contains "W2 names the changed file" "$OUT" "$H/.gitconfig: content changed"
mkcase w2h
hook SessionStart
printf '[user]\n\tname = Mallory\n' >> "$H/.gitconfig"
hook PostToolUse
check_status "W2 hook mode exits 0 even on a change" 0 "$STATUS"
jq_ok '.systemMessage and .hookSpecificOutput.additionalContext and .hookSpecificOutput.hookEventName=="PostToolUse"' \
  && pass "W2 hook mode emits systemMessage + additionalContext + hookEventName" \
  || fail "W2 hook mode emits systemMessage + additionalContext + hookEventName" "got: $OUT"
check_contains "W2 the header names the tool call" "$OUT" "machine-global state changed around this tool call:"

# --- W3/W4: the global hooks dir — mode, created, deleted -------------------------------------------
mkcase w3
mw snapshot a
chmod 700 "$HK/pre-commit"
mw check a
check_status "W3 chmod in the hooks dir -> exit 1" 1 "$STATUS"
check_contains "W3 reports the mode change" "$OUT" "pre-commit: mode 755→700"
mw snapshot a
: > "$HK/post-commit"
mw check a
check_contains "W4 a created hook file is reported" "$OUT" "post-commit: created"
rm -f "$HK/post-commit"
mw check a
check_contains "W4 a deleted hook file is reported" "$OUT" "post-commit: deleted"

# --- W5: the dir #627 shape, DEFAULT store location (under $HOME/.keel, outside the harness home) ----
mkcase w5
ENVV=("HOME=$H" "GIT_CONFIG_GLOBAL=$H/.gitconfig" "KEEL_HOME=$HH")
saved_store="$KEEL_MACHINE_WATCH_STORE"; unset KEEL_MACHINE_WATCH_STORE   # the DEFAULT location, under $HOME/.keel
hook SessionStart
rm -r "$HH"
hook PostToolUse
jq -e '.systemMessage | contains("harness: deleted")' >/dev/null 2>&1 <<<"$OUT" \
  && pass "W5 rm -r of the harness home -> a systemMessage naming it deleted" \
  || fail "W5 rm -r of the harness home -> a systemMessage naming it deleted" "got: $OUT"
check_nodir "W5 the watcher does not recreate the harness home" "$HH"
check_file "W5 the baseline sits outside the harness home and survived" "$H/.keel/machine-watch/s1.snap"
# W5d: the store itself removed (the whole state root went) -> the loss is reported, then re-recorded
mkcase w5d
ENVV=("HOME=$H" "GIT_CONFIG_GLOBAL=$H/.gitconfig" "KEEL_HOME=$HH")
unset KEEL_MACHINE_WATCH_STORE
hook SessionStart
rm -r "$H/.keel"
hook PostToolUse
jq -e '.systemMessage | contains("machine-watch: deleted") or contains("/.keel/machine-watch: deleted")' >/dev/null 2>&1 <<<"$OUT" \
  && pass "W5d store removed -> a systemMessage naming the store deleted" \
  || fail "W5d store removed -> a systemMessage naming the store deleted" "got: $OUT"
check_file "W5d the baseline is recreated" "$H/.keel/machine-watch/s1.snap"
export KEEL_MACHINE_WATCH_STORE="$saved_store"

# --- W5b/W5c: no baseline for this session ----------------------------------------------------------
mkcase w5b
hook SessionStart
rm -r "$H/store"
hook PostToolUse
jq -e '.systemMessage | contains("deleted")' >/dev/null 2>&1 <<<"$OUT" \
  && pass "W5b store removed (harness intact) -> a systemMessage naming it deleted" \
  || fail "W5b store removed (harness intact) -> a systemMessage naming it deleted" "got: $OUT"
check_file "W5b the baseline is recreated" "$H/store/s1.snap"
mkcase w5c
hook PostToolUse
check_contains "W5c wired mid-session: the notice" "$OUT" "wired mid-session"
check_absent "W5c wired mid-session: no deleted line" "$OUT" ": deleted"
check_file "W5c a baseline was recorded" "$H/store/s1.snap"

# --- W6: git var unavailable (Apple git 2.39 answers rc 129) -> the documented fallback --------------
mkcase w6
git_var_stub_dir "$SANDBOX/stub-w6"
run env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM "HOME=$H" "KEEL_HOME=$HH" \
  "KEEL_MACHINE_WATCH_STORE=$H/store" "PATH=$SANDBOX/stub-w6:$PATH" bash "$mw" paths
check_status "W6 paths with a failing git var -> exit 0" 0 "$STATUS"
check_contains "W6 fallback lists the XDG git config" "$OUT" "alert file $H/.config/git/config"
check_contains "W6 fallback lists ~/.gitconfig" "$OUT" "alert file $H/.gitconfig"
check_contains "W6 fallback lists /etc/gitconfig" "$OUT" "alert file /etc/gitconfig"

# --- W7: GIT_CONFIG_GLOBAL in the hook's env steers the set -----------------------------------------
mkcase w7
printf '[user]\n\tname = Bob\n' > "$H/elsewhere.cfg"
run env "${ENVV[@]}" "GIT_CONFIG_GLOBAL=$H/elsewhere.cfg" bash "$mw" paths
check_contains "W7 paths lists GIT_CONFIG_GLOBAL's file" "$OUT" "alert file $H/elsewhere.cfg"
check_absent "W7 paths does not list ~/.gitconfig" "$OUT" "file $H/.gitconfig"

# --- W8: reported once -----------------------------------------------------------------------------
mkcase w8
mw snapshot a
printf 'x\n' >> "$H/.gitconfig"
mw check a;  check_status "W8 the change is reported" 1 "$STATUS"
mw check a;  check_status "W8 a second check is silent (the baseline was replaced)" 0 "$STATUS"
check_eq "W8 a second check prints nothing" "" "$OUT"

# --- W9: file content never stored or printed -------------------------------------------------------
mkcase w9
printf 'SECRET_TOKEN_8f3a9c\n' > "$H/.zshrc"
mw snapshot a
printf 'SECRET_TOKEN_8f3a9c more\n' > "$H/.zshrc"
mw check a
check_absent "W9 the token is not printed" "$OUT" "SECRET_TOKEN_8f3a9c"
if grep -rq 'SECRET_TOKEN_8f3a9c' "$H/store" 2>/dev/null; then fail "W9 the token is not stored" "found in $H/store"; else pass "W9 the token is not stored"; fi

# --- W10: PostToolUseFailure is handled like PostToolUse ---------------------------------------------
mkcase w10
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUseFailure
jq_ok '.systemMessage and .hookSpecificOutput.hookEventName=="PostToolUseFailure" and (.hookSpecificOutput.additionalContext | contains("around this tool call"))' \
  && pass "W10 PostToolUseFailure -> a report under that event name" \
  || fail "W10 PostToolUseFailure -> a report under that event name" "got: $OUT"

# --- W11: an unwritable store never fails the tool call ----------------------------------------------
mkcase w11
chmod 555 "$H/store"
hook SessionStart
check_status "W11 an unwritable store -> hook exits 0" 0 "$STATUS"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_contains "W11 an unwritable store -> a 'check failed' notice" "$OUT" "machine-watch: check failed:"
fi
chmod 755 "$H/store"

# --- W12: SessionEnd cleans up; SessionStart ages out crashed sessions -------------------------------
mkcase w12
hook SessionStart s1
check_file "W12 SessionStart wrote the baseline" "$H/store/s1.snap"
check_file "W12 SessionStart wrote the stamp" "$H/store/s1.stamp"
hook SessionEnd s1
check_nofile "W12 SessionEnd removed the baseline" "$H/store/s1.snap"
check_nofile "W12 SessionEnd removed the stamp" "$H/store/s1.stamp"
check_eq "W12 SessionEnd is silent" "" "$OUT"
hook SessionStart old
touch -t 202001010000 "$H/store/old.snap" "$H/store/old.stamp"
hook SessionStart fresh
check_nofile "W12 a baseline past the max age is removed at SessionStart" "$H/store/old.snap"
check_nofile "W12 its stamp goes too" "$H/store/old.stamp"
check_file "W12 the new session's baseline stays" "$H/store/fresh.snap"

# --- W13: a hostile session_id writes nothing outside the store --------------------------------------
mkcase w13
before="$(find "$SANDBOX" -path "$SANDBOX/case-*" -prune -o -type f -print | sort | cksum)"
hook SessionStart '../x'
check_status "W13 session_id ../x -> exit 0" 0 "$STATUS"
after="$(find "$SANDBOX" -path "$SANDBOX/case-*" -prune -o -type f -print | sort | cksum)"
check_eq "W13 nothing written outside the case home" "$before" "$after"
check_eq "W13 nothing written inside the store" "" "$(ls -A "$H/store")"
check_nofile "W13 no file escaped to the parent of the store" "$H/x.snap"

# --- W14: the extra-paths file ------------------------------------------------------------------------
mkcase w14
mkdir -p "$H/.keel" "$H/extradir"
printf 'a\n' > "$H/x1"; printf 'b\n' > "$H/x2"
printf '# my paths\n\nalert %s\nquiet %s\nquiet %s\n' "$H/x1" "$H/x2" "$H/extradir" > "$H/.keel/machine-watch.paths"
mw paths
check_contains "W14 an alert entry lands in the alert tier" "$OUT" "alert file $H/x1"
check_contains "W14 a quiet entry lands in the quiet tier" "$OUT" "quiet file $H/x2"
check_contains "W14 a directory entry is scanned as a tree" "$OUT" "quiet tree $H/extradir"
hook SessionStart
printf 'changed\n' > "$H/x1"
hook PostToolUse
jq_ok '.systemMessage and (.systemMessage | contains("x1: content changed"))' \
  && pass "W14 an alert extra path raises the banner" \
  || fail "W14 an alert extra path raises the banner" "got: $OUT"
printf 'changed\n' > "$H/x2"
hook PostToolUse
jq_ok '(has("systemMessage") | not) and (.hookSpecificOutput.additionalContext | contains("expected writer: listed by you in machine-watch.paths"))' \
  && pass "W14 a quiet extra path is model-only and names its writer" \
  || fail "W14 a quiet extra path is model-only and names its writer" "got: $OUT"

# --- W15: the fixed paragraph, one line, verbatim ----------------------------------------------------
pin "W15 the fixed paragraph is pinned verbatim in the tool" "$mw" "$FIXED" \
  "expected tools/machine-watch.sh to carry MW4's fixed paragraph on ONE line, verbatim"
mkcase w15
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUse
if jq -e --arg f "$FIXED" '(.systemMessage | contains($f)) and (.hookSpecificOutput.additionalContext | contains($f))' >/dev/null 2>&1 <<<"$OUT"; then
  pass "W15 both channels carry the fixed paragraph"
else
  fail "W15 both channels carry the fixed paragraph" "got: $OUT"
fi

# --- W16: tier routing --------------------------------------------------------------------------------
mkcase w16
hook SessionStart
printf '{"a":1}\n' > "$HH/settings.json"
hook PostToolUse
jq_ok '(has("systemMessage") | not) and (.hookSpecificOutput.additionalContext | contains("quiet — expected writer:"))' \
  && pass "W16 a quiet-tier change is model-only and names its writer" \
  || fail "W16 a quiet-tier change is model-only and names its writer" "got: $OUT"
rm -f "$HH/settings.json"
hook PostToolUse
jq_ok '.systemMessage | contains("settings.json: deleted")' \
  && pass "W16 deleting a quiet-tier file is an alert" \
  || fail "W16 deleting a quiet-tier file is an alert" "got: $OUT"

# --- W17: the ctime tree scan -------------------------------------------------------------------------
mkcase w17
mw snapshot a
tick
printf 'n\n' > "$H/.config/app/new"
mw check a
check_status "W17 a new file under the tree -> exit 1" 1 "$STATUS"
check_contains "W17 the new file is reported as changed" "$OUT" "app/new: changed"
tick
: > "$H/.config/app/.DS_Store"
mw check a
check_status "W17 a .DS_Store created in the tree is not reported" 0 "$STATUS"
tick
rm -f "$H/.config/app/new"
mw check a
check_contains "W17 a removal reports the directory's entries changed" "$OUT" "app: entries changed"

# W17b: an alert file that sits INSIDE the quiet tree is reported once, as an alert — not again as a quiet tree hit
mkcase w17b
mkdir -p "$H/.config/git"; printf '[user]\n\tname = Alice\n' > "$H/.config/git/config"
ENVV=("HOME=$H" "GIT_CONFIG_GLOBAL=$H/.config/git/config" "KEEL_HOME=$HH" "KEEL_MACHINE_WATCH_STORE=$H/store")
mw snapshot a
tick
printf '[user]\n\tname = Mallory\n' > "$H/.config/git/config"
mw check a
check_contains "W17b the in-tree alert file is reported as an alert" "$OUT" "$H/.config/git/config: content changed"
check_eq "W17b …and exactly once (no second quiet line for it)" "1" "$(printf '%s\n' "$OUT" | grep -c "$H/.config/git/config:")"

# --- W18: shell rc -------------------------------------------------------------------------------------
mkcase w18
hook SessionStart
printf 'alias ls=rm\n' >> "$H/.zshrc"
hook PostToolUse
jq_ok '.systemMessage | contains(".zshrc: content changed")' \
  && pass "W18 a change to a shell rc file raises an alert systemMessage" \
  || fail "W18 a change to a shell rc file raises an alert systemMessage" "got: $OUT"

# --- W19: header per event ----------------------------------------------------------------------------
mkcase w19
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook SessionStart
check_contains "W19 a resume-time change uses the 'not running' header" "$OUT" "while this session was not running"
check_absent "W19 a resume-time change never says 'around this tool call'" "$OUT" "around this tool call"

# --- W20: CLI error paths -------------------------------------------------------------------------------
mkcase w20
mw check never-snapshotted
check_status "W20 check with no baseline -> exit 2" 2 "$STATUS"
mw snapshot '../x'
check_status "W20 a hostile name -> exit 2" 2 "$STATUS"
mw snapshot a; mw forget a
check_nofile "W20 forget removes the baseline" "$H/store/a.snap"
mw
check_status "W20 no subcommand -> exit 2" 2 "$STATUS"

# --- W21: never writes a deny rule (prevention is a documented recipe only, MW9) ---------------------
if grep -v '^[[:space:]]*#' "$mw" | grep -q 'permissions'; then
  fail "W21 the watcher never touches permissions" "tools/machine-watch.sh mentions permissions outside a comment"
else
  pass "W21 the watcher never touches permissions"
fi

summary
