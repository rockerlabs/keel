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

# W3b: the same mode report under a single-byte locale — bash then reads `$var→` as one variable name
# (CI's macos-14 leg went red on exactly this); skipped where the host has no such locale.
l1=""
# `command -v locale` first: Alpine ships no `locale`, and tests/lib.sh's command_not_found_handle kills the whole
# file on a failed lookup (see pick_utf8_locale in lib.sh).
if command -v locale >/dev/null 2>&1; then
  avail_locales="$(locale -a 2>/dev/null)"
  for cand in en_US.ISO8859-1 en_US.ISO-8859-1 en_US.iso88591 en_US.ISO8859-15; do
    case "$avail_locales" in *"$cand"*) l1="$cand"; break ;; esac
  done
fi
if [ -n "$l1" ]; then
  mkcase w3b
  mw snapshot a
  chmod 700 "$HK/pre-commit"
  run env "${ENVV[@]}" "LC_ALL=$l1" bash "$mw" check a
  check_contains "W3b the mode report survives a single-byte locale ($l1)" "$OUT" "pre-commit: mode 755→700"
fi

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

# --- W22-W32: the operator's channel (dir #657) — a native OS notification for every alert-tier report ----
# The hook's systemMessage is not rendered by the Claude desktop app, so the alert tier also raises an OS
# notification (macOS `osascript`, Linux `notify-send`, a KEEL_MACHINE_WATCH_NOTIFIER command of your own).
# tests/lib.sh turns it OFF suite-wide (KEEL_MACHINE_WATCH_NOTIFY=0) so no test pops a real banner on the
# machine running it; every case below switches it on against a STUB that only logs its argv.
STUBS="$SANDBOX/stubbin"; MINBIN="$SANDBOX/minbin"
mkdir -p "$STUBS" "$MINBIN"
for _n in osascript notify-send; do
  cat > "$STUBS/$_n" <<'STUB'
#!/bin/sh
# Logs one CALL record: the tool's own name, then every argv element on its own ARG: line.
{ printf 'CALL %s\n' "${0##*/}"; for a in "$@"; do printf 'ARG:%s\n' "$a"; done; } >> "$STUB_LOG"
[ -z "${STUB_SLEEP:-}" ] || { sleep "$STUB_SLEEP"; printf 'DONE\n' >> "$STUB_LOG"; }
[ -z "${STUB_NOISE:-}" ] || { echo "stub stdout noise"; echo "stub stderr noise" >&2; }
exit "${STUB_RC:-0}"
STUB
  chmod 755 "$STUBS/$_n"
done
# MINBIN: the tools the hook needs, WITHOUT osascript — and the notify-send stub, so the Linux branch is
# reachable on a macOS box (where the real /usr/bin/osascript would otherwise always win the probe).
for _n in bash sh jq git awk find cksum stat mkdir mv rm touch cp cat sed tr uname dirname basename date id sleep \
  head cut grep sort wc ls readlink env dd rmdir xargs expr chmod ln tail cmp diff; do
  _p="$(type -P "$_n")" && ln -sf "$_p" "$MINBIN/$_n"
done
unset _n _p
# delta-audit 0.13.0 S2-6: tools/lib/git-global-paths.sh probes with a bare `mktemp -d` and removes the probe
# with `rmdir`; a MINBIN without rmdir left 5 empty dirs per run in the REAL temp dir (macOS's bare `mktemp -d`
# ignores $TMPDIR, so that leak cannot be observed by redirecting it). `mktemp` in MINBIN is therefore a shim:
# with PROBE_SCRATCH set it makes the dir THERE, so a leftover is checkable under the case's own scratch.
_real_mktemp="$(command -v mktemp)"
cat > "$MINBIN/mktemp" <<SHIM
#!/bin/sh
[ -z "\${PROBE_SCRATCH:-}" ] || { mkdir -p "\$PROBE_SCRATCH" && exec "$_real_mktemp" -d "\$PROBE_SCRATCH/probe.XXXXXX"; }
exec "$_real_mktemp" "\$@"
SHIM
chmod 755 "$MINBIN/mktemp"
unset _real_mktemp
# notify_case NAME — a fresh case whose hook env switches the notification on, with the stub log in $NLOG.
notify_case() {
  mkcase "$1"
  NLOG="$H/notif.log"; : > "$NLOG"
  ENVV+=("KEEL_MACHINE_WATCH_NOTIFY=1" "STUB_LOG=$NLOG" "PATH=$STUBS:$PATH")
}
# wait_log PATTERN — the notification is raised in the background; poll up to 5 s for the log to carry PATTERN.
wait_log() {
  local i=0
  while [ "$i" -lt 50 ]; do
    grep -q -- "$1" "$NLOG" 2>/dev/null && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

# W22: an alert-tier change raises ONE notification carrying the alert line — not the fixed paragraph.
notify_case w22
hook SessionStart
printf '[user]\n\tname = Mallory\n' >> "$H/.gitconfig"
hook PostToolUse
wait_log CALL; check_status "W22 an alert-tier change calls the OS notifier" 0 "$?"
check_contains "W22 macOS: the notifier is osascript" "$(cat "$NLOG")" "CALL osascript"
check_contains "W22 the notification names the changed file and the change" "$(cat "$NLOG")" "$H/.gitconfig: content changed"
check_contains "W22 the notification names the watcher" "$(cat "$NLOG")" "machine-watch"
check_absent "W22 the notification is short — it does not carry the fixed paragraph" "$(cat "$NLOG")" "cannot tell who made the change"
check_count "W22 exactly one notification for the one tool call" "$NLOG" '^CALL' 1
jq_ok '.systemMessage and .hookSpecificOutput.additionalContext' \
  && pass "W22 the harness JSON is unchanged — the notification is an addition, not a replacement" \
  || fail "W22 the harness JSON is unchanged — the notification is an addition, not a replacement" "got: $OUT"

# W23: a quiet-tier change tells only the model — no notification.
notify_case w23
hook SessionStart
printf '{"a":1}\n' > "$HH/settings.json"
hook PostToolUse
sleep 0.5
check_eq "W23 a quiet-tier change raises no notification" "" "$(cat "$NLOG")"

# W24: nothing changed -> nothing raised.
notify_case w24
hook SessionStart; hook PostToolUse
sleep 0.5
check_eq "W24 an unchanged machine raises no notification" "" "$(cat "$NLOG")"

# W25: KEEL_MACHINE_WATCH_NOTIFY=0 is the off switch, and the JSON is still emitted.
notify_case w25
ENVV+=("KEEL_MACHINE_WATCH_NOTIFY=0")
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUse
sleep 0.5
check_eq "W25 KEEL_MACHINE_WATCH_NOTIFY=0 raises no notification" "" "$(cat "$NLOG")"
jq_ok '.systemMessage' && pass "W25 …and the banner JSON is still emitted" || fail "W25 …and the banner JSON is still emitted" "got: $OUT"

# W26: a resume-time change (SessionStart's check) is an alert-tier report too.
notify_case w26
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook SessionStart
wait_log CALL; check_status "W26 a resume-time alert change raises a notification" 0 "$?"

# W27: Linux — no osascript on the path, notify-send present -> notify-send; neither -> silent, no error.
notify_case w27
ENVV+=("PATH=$MINBIN" "PROBE_SCRATCH=$H/probes")
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUse
rm -f "$MINBIN/notify-send"; ln -sf "$STUBS/notify-send" "$MINBIN/notify-send"
printf 'y\n' >> "$H/.gitconfig"
hook PostToolUse
wait_log 'CALL notify-send'; check_status "W27 no osascript, notify-send present -> notify-send" 0 "$?"
check_contains "W27 notify-send carries the alert line" "$(cat "$NLOG")" "$H/.gitconfig: content changed"
check_eq "W27 S2-6: the hook's probe dirs are removed under the minimal PATH (rmdir present)" "" "$(ls -A "$H/probes" 2>/dev/null)"
check_dir "W27 S2-6 fixture: the probe was actually made under the scratch (the shim is live)" "$H/probes"
notify_case w27b
ENVV+=("PATH=$MINBIN" "PROBE_SCRATCH=$H/probes")
rm -f "$MINBIN/notify-send"
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUse
check_status "W27b neither notifier present -> the hook still exits 0" 0 "$STATUS"
jq_ok '.systemMessage and .hookSpecificOutput.additionalContext' \
  && pass "W27b neither notifier present -> the harness JSON is intact, nothing else on stdout" \
  || fail "W27b neither notifier present -> the harness JSON is intact, nothing else on stdout" "got: $OUT"
sleep 0.5
check_eq "W27b neither notifier present -> nothing logged" "" "$(cat "$NLOG")"
check_eq "W27b S2-6: no probe dir left under the minimal PATH" "" "$(ls -A "$H/probes" 2>/dev/null)"

# W28: a notifier that fails, writes noise or hangs never changes the hook's result and never delays it.
notify_case w28
ENVV+=("STUB_RC=1" "STUB_NOISE=1" "STUB_SLEEP=2")
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUse
check_status "W28 a failing, noisy notifier -> the hook still exits 0" 0 "$STATUS"
jq_ok '.systemMessage and .hookSpecificOutput.additionalContext' \
  && pass "W28 …its noise never reaches the hook's stdout (the JSON parses)" \
  || fail "W28 …its noise never reaches the hook's stdout (the JSON parses)" "got: $OUT"
if grep -q '^DONE' "$NLOG"; then
  fail "W28 the hook does not wait for the notifier" "the 2 s stub had finished before the hook returned"
else
  pass "W28 the hook does not wait for the notifier"
fi
wait_log DONE   # let the background stub finish before the case home goes away

# W29: KEEL_MACHINE_WATCH_NOTIFIER — your own command, called as NOTIFIER TITLE BODY, wins over the OS probe.
notify_case w29
cat > "$H/mynotify" <<'MY'
#!/bin/sh
printf 'MINE\nTITLE:%s\nBODY:%s\n' "$1" "$2" >> "$STUB_LOG"
MY
chmod 755 "$H/mynotify"
ENVV+=("KEEL_MACHINE_WATCH_NOTIFIER=$H/mynotify")
hook SessionStart
printf 'x\n' >> "$H/.gitconfig"
hook PostToolUse
wait_log MINE; check_status "W29 the override command is called" 0 "$?"
check_contains "W29 …as NOTIFIER TITLE BODY" "$(cat "$NLOG")" "BODY:$H/.gitconfig: content changed"
check_absent "W29 …and the OS notifier is not also called" "$(cat "$NLOG")" "CALL osascript"

# W30: the message is DATA — a path with quotes reaches the notifier as one argument, never inside a script.
notify_case w30
mkdir -p "$H/.keel"
WEIRD="$H/we\"ird'name"
printf 'v\n' > "$WEIRD"
printf 'alert %s\n' "$WEIRD" > "$H/.keel/machine-watch.paths"
hook SessionStart
printf 'w\n' > "$WEIRD"
hook PostToolUse
wait_log CALL; check_status "W30 a quote-bearing path still raises the notification" 0 "$?"
check_contains "W30 the path arrives verbatim" "$(cat "$NLOG")" "$WEIRD: content changed"
if grep -E '^ARG:(on run|display notification|end run)' "$NLOG" | grep -qF "ird'name"; then
  fail "W30 the fixed script text never embeds the message" "a path fragment leaked into an osascript -e line"
else
  pass "W30 the fixed script text never embeds the message"
fi

# W31: a long report is capped — the notification carries the first lines and a count, never the whole list.
notify_case w31
mkdir -p "$H/bigtree" "$H/.keel"
printf 'alert %s\n' "$H/bigtree" > "$H/.keel/machine-watch.paths"
hook SessionStart
tick
i=0; while [ "$i" -lt 25 ]; do printf 'n\n' > "$H/bigtree/f$i"; i=$((i + 1)); done
hook PostToolUse
wait_log more; check_status "W31 a bulk change raises a notification" 0 "$?"
check_contains "W31 the capped notification says how many more there are" "$(cat "$NLOG")" "more"
check_count "W31 the body is capped — the first 5 report lines, not all 21" "$NLOG" 'bigtree' 5

# W32: hook mode only — the CLI's `check` prints to the operator's own terminal and raises nothing.
notify_case w32
mw snapshot a
printf 'x\n' >> "$H/.gitconfig"
mw check a
check_status "W32 CLI check still reports the change" 1 "$STATUS"
sleep 0.5
check_eq "W32 the CLI raises no notification" "" "$(cat "$NLOG")"

# W33 (delta-audit 0.13.0 S2-1): the harness must not inherit the operator's notifier. lib.sh is sourced in a CHILD
# that starts with the variables exported — as the installer's own note tells an operator to do — and reports what
# is left once it has run. A state check, not a behavioural one: mw_notify reads exactly that variable first, so a
# value that survives the harness is the whole defect (13 cases red, 13 calls carrying test paths when found).
run env KEEL_MACHINE_WATCH_NOTIFIER=/operator/own-notifier KEEL_MACHINE_WATCH_MAX_AGE_DAYS=9 \
  KEEL_MACHINE_WATCH_STORE=/decoy-store bash -c \
  '. "$1/tests/lib.sh" || exit 1
   printf "notifier=%s\nmaxage=%s\nstore=%s\nsandbox=%s\n" "${KEEL_MACHINE_WATCH_NOTIFIER-unset}" \
     "${KEEL_MACHINE_WATCH_MAX_AGE_DAYS-unset}" "$KEEL_MACHINE_WATCH_STORE" "$SANDBOX"' _ "$REPO_ROOT"
check_status "W33 the harness sources cleanly with an operator's machine-watch variables exported" 0 "$STATUS"
check_contains "W33 an exported KEEL_MACHINE_WATCH_NOTIFIER is unset by the harness" "$OUT" "notifier=unset"
check_contains "W33 an exported KEEL_MACHINE_WATCH_MAX_AGE_DAYS is unset by the harness" "$OUT" "maxage=unset"
w33_sb="$(printf '%s\n' "$OUT" | sed -n 's/^sandbox=//p')"
check_contains "W33 the store override is redirected into the child's sandbox, not inherited" "$OUT" "store=$w33_sb/"

summary
