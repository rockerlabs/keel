#!/usr/bin/env bash
# test_sandbox_escapes.sh — dir #720 S10-3: the two demo scripts that promise to touch nothing on the
# machine (examples/tour.sh, docs/demo/record-demo.sh) must neutralize an exported impact-store override.
# Both redirect HOME into a throwaway sandbox, but tools/lib/impact-store.sh resolves KEEL_IMPACT_STORE /
# KEEL_IMPACT_LOG / KEEL_HOME BEFORE HOME, so an operator's exported value would send the demo's writes
# into their REAL store. Hand each script such overrides and assert nothing lands there.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

store="$SANDBOX/real-store"; log="$SANDBOX/real-log.tsv"; khome="$SANDBOX/real-keel-home"

run env KEEL_IMPACT_STORE="$store" KEEL_IMPACT_LOG="$log" KEEL_HOME="$khome" bash "$REPO_ROOT/examples/tour.sh"
check_status "tour.sh with ambient impact overrides → exit 0" 0 "$STATUS"
check_nodir "tour.sh leaves the ambient KEEL_IMPACT_STORE untouched" "$store"
check_nofile "tour.sh leaves the ambient KEEL_IMPACT_LOG untouched" "$log"
check_nodir "tour.sh leaves the ambient KEEL_HOME untouched" "$khome"

run env KEEL_IMPACT_STORE="$store" KEEL_IMPACT_LOG="$log" KEEL_HOME="$khome" bash "$REPO_ROOT/docs/demo/record-demo.sh" --scenes
check_nodir "record-demo.sh --scenes leaves the ambient KEEL_IMPACT_STORE untouched" "$store"
check_nofile "record-demo.sh --scenes leaves the ambient KEEL_IMPACT_LOG untouched" "$log"
check_nodir "record-demo.sh --scenes leaves the ambient KEEL_HOME untouched" "$khome"

# dir #725 made a set-but-missing SECRET_SCAN_PERSONAL_FILE fail the scanner closed (exit 2), also inside
# install-secret-guard.sh's selftest, so a stale ambient value in the operator's shell left the tour's guard
# uninstalled and its step 6 ended "commit succeeded — that should not happen". Both demos must neutralize it
# with the other isolation vars: with a missing path exported, the guard step must still end BLOCKED.
missing="$SANDBOX/no-such-personal-literals"
run env SECRET_SCAN_PERSONAL_FILE="$missing" bash "$REPO_ROOT/examples/tour.sh"
check_status "tour.sh with an ambient missing SECRET_SCAN_PERSONAL_FILE → exit 0" 0 "$STATUS"
check_contains "tour.sh with an ambient missing SECRET_SCAN_PERSONAL_FILE → the commit is still BLOCKED by the hook" "$OUT" "BLOCKED by the hook, exactly as intended"
check_absent "tour.sh with an ambient missing SECRET_SCAN_PERSONAL_FILE → never prints 'commit succeeded'" "$OUT" "commit succeeded"

run env SECRET_SCAN_PERSONAL_FILE="$missing" bash "$REPO_ROOT/docs/demo/record-demo.sh" --scenes
check_contains "record-demo.sh --scenes with an ambient missing SECRET_SCAN_PERSONAL_FILE → the commit is still BLOCKED" "$OUT" "BLOCKED"
check_absent "record-demo.sh --scenes with an ambient missing SECRET_SCAN_PERSONAL_FILE → no 'is not a regular file' scanner error" "$OUT" "not a regular file"


# --- dir #753 (the cases below are this ticket's; the KEEL_HOME/impact-store cases above are dir #720's) ----
# R2-4: HOME and GIT_CONFIG_GLOBAL are not the whole git-config surface. The GIT_CONFIG_COUNT/KEY_n/VALUE_n
# triple (command scope, beats every file) and GIT_CONFIG_SYSTEM (an alternate system file) both reach a demo
# that claims to touch nothing of the operator's, and one carrying core.hooksPath=/dev/null silently turns the
# guard step into "commit succeeded". Behavioural for tour.sh, and a `git` shim for BOTH demos that records the
# env each git call actually sees (a no-op shim would pass a demo that never reached git, so the log must be
# non-empty). The real git is resolved first: tests/lib.sh defines a git() function, so type -P.
real_git="$(type -P git)"
shim="$SANDBOX/git-shim"; mkdir -p "$shim"
cat > "$shim/git" <<SHIM
#!/bin/sh
echo CALL >> "\$GIT_ENV_LOG"
env | grep -E '^GIT_CONFIG_(COUNT|SYSTEM|KEY_[0-9]+|VALUE_[0-9]+)=' >> "\$GIT_ENV_LOG"
exec "$real_git" "\$@"
SHIM
chmod +x "$shim/git"
poison_sys="$SANDBOX/poison-system.gitconfig"
printf '[core]\n\thooksPath = /dev/null\n' > "$poison_sys"

run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null bash "$REPO_ROOT/examples/tour.sh"
check_status "dir #753: tour.sh with an ambient GIT_CONFIG_COUNT hooksPath triple → exit 0" 0 "$STATUS"
check_contains "dir #753: ...the key-shaped commit is still BLOCKED by the hook" "$OUT" "BLOCKED by the hook, exactly as intended"
check_absent "dir #753: ...never prints 'commit succeeded'" "$OUT" "commit succeeded"

run env GIT_CONFIG_SYSTEM="$poison_sys" bash "$REPO_ROOT/examples/tour.sh"
check_status "dir #753: tour.sh with an ambient GIT_CONFIG_SYSTEM hooksPath file → exit 0" 0 "$STATUS"
check_contains "dir #753: ...the key-shaped commit is still BLOCKED by the hook" "$OUT" "BLOCKED by the hook, exactly as intended"
check_absent "dir #753: ...never prints 'commit succeeded'" "$OUT" "commit succeeded"

for demo in "examples/tour.sh" "docs/demo/record-demo.sh --scenes"; do
  genv_log="$SANDBOX/git-env-$(printf '%s' "${demo%% *}" | tr '/.' '--').log"; : > "$genv_log"
  # shellcheck disable=SC2086  # $demo is "script [--scenes]" on purpose
  run env PATH="$shim:$PATH" GIT_ENV_LOG="$genv_log" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath \
    GIT_CONFIG_VALUE_0=/dev/null GIT_CONFIG_SYSTEM="$poison_sys" bash "$REPO_ROOT"/$demo
  seen="$(cat "$genv_log")"
  check_contains "dir #753: the git shim saw ${demo%% *}'s git calls (the absence checks below are not vacuous)" "$seen" "CALL"
  check_absent "dir #753: no git call in ${demo%% *} sees GIT_CONFIG_COUNT/KEY_n/VALUE_n" "$seen" "GIT_CONFIG_COUNT"
  check_absent "dir #753: no git call in ${demo%% *} sees GIT_CONFIG_SYSTEM" "$seen" "GIT_CONFIG_SYSTEM"
done

# R1-10: the emptiness guard must sit IMMEDIATELY after mktemp, before the first write (export HOME /
# mkdir / trap). Neither script runs under -e, so a failed mktemp leaves $sandbox empty and, unguarded,
# "$sandbox/home" is "/home" — a write outside any sandbox. Pinned by line order (running the red case
# for real would write at the filesystem root of a root-owned CI container).
for demo in examples/tour.sh docs/demo/record-demo.sh; do
  f="$REPO_ROOT/$demo"
  mk="$(grep -n '^sandbox="$(mktemp -d' "$f" | head -1 | cut -d: -f1)"
  gd="$(grep -n '^\[ -n "\$sandbox" \] || exit 1' "$f" | head -1 | cut -d: -f1)"
  wr="$(grep -nE '^(export HOME=|trap |mkdir |cd )' "$f" | head -1 | cut -d: -f1)"
  if [ -n "$mk" ] && [ -n "$gd" ] && [ "$gd" -eq $((mk + 1)) ] && [ "$gd" -lt "${wr:-999999}" ]; then
    pass "dir #753: $demo guards \$sandbox on the line right after mktemp, before its first write"
  else
    fail "dir #753: $demo guards \$sandbox on the line right after mktemp, before its first write" \
      "mktemp line=${mk:-none} guard line=${gd:-none} first write line=${wr:-none}"
  fi
done

summary
