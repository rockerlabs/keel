#!/usr/bin/env bash
# test_sandbox_escapes.sh — dir #720 S10-3: the two demo scripts that promise to touch nothing on the
# machine (examples/tour.sh, docs/demo/record-demo.sh) must neutralize an exported impact-store override.
# Both redirect HOME into a throwaway sandbox, but tools/lib/impact-store.sh resolves KEEL_IMPACT_STORE /
# KEEL_IMPACT_LOG / KEEL_HOME BEFORE HOME, so an operator's exported value would send the demo's writes
# into their REAL store. Hand each script such overrides and assert nothing lands there.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# dir #749 S9-7: ONE override per run, each on its own fresh path. The first version exported all three at once
# and shared the paths between the two scripts, so (1) KEEL_HOME could never fail — the resolvers consult
# KEEL_IMPACT_STORE / KEEL_IMPACT_LOG before it, and the demos make no other impact write — (2) the record-demo
# STORE assertion was masked by tour.sh's leftover directory, and (3) one script's leftovers fed the next one's
# assertions. KEEL_HOME is only read when it already holds a store (`<KEEL_HOME>/.keel/impact`, the legacy
# address), so its fixture plants one, and a control proves the resolver really does take it: without the plant
# the assertion would pass against a demo that leaks.
khome_fixture() {   # khome_fixture PATH — a harness home that already holds an impact store
  mkdir -p "$1/.keel/impact"
  printf 'sentinel\n' > "$1/.keel/impact/sentinel"
}
tree_sum() { (cd "$1" && find . | LC_ALL=C sort | cksum); }
# tests/lib.sh exports a harness value for six of the seven isolation variables into every test's environment, and
# the resolvers read those before KEEL_HOME — which is the real reason the old KEEL_HOME rows could not fail.
# only_env VAR VALUE CMD… — run CMD with every isolation variable removed except VAR=VALUE.
# The list is read in a subshell: sourcing the library here would define its functions for the rest of the file.
isolation_vars="$(. "$REPO_ROOT/tools/lib/impact-store.sh"; printf '%s' "$IMPACT_ISOLATION_VARS")"
[ -n "$isolation_vars" ] || { fail "S9-7: the isolation-variable list was read from tools/lib/impact-store.sh" "IMPACT_ISOLATION_VARS is empty or unreadable"; summary; exit 1; }
only_env() {
  local keep="$1" val="$2" v unsets=()
  shift 2
  for v in $isolation_vars; do [ "$v" = "$keep" ] || unsets+=(-u "$v"); done
  run env "${unsets[@]}" "$keep=$val" "$@"
}
kh_ctl="$SANDBOX/esc-ctl-khome"; khome_fixture "$kh_ctl"
only_env KEEL_HOME "$kh_ctl" bash -c '. "$1/tools/lib/impact-store.sh"; impact_store_root' _ "$REPO_ROOT"
check_eq "S9-7 control: with only KEEL_HOME exported and a store under it, the resolver DOES pick KEEL_HOME's store (so the KEEL_HOME rows can fail)" \
  "$kh_ctl/.keel/impact" "$OUT"
for demo in "examples/tour.sh" "docs/demo/record-demo.sh --scenes"; do
  dn="$(printf '%s' "${demo%% *}" | tr '/.' '--')"
  # record-demo.sh's inner mode never writes to a store: its project is a bare `git init`, and a store is only
  # written for a project that already has one (tour.sh runs init-project, which enables it), so the only
  # override whose leak it can show is the inline scanner's KEEL_IMPACT_LOG. Measured with its unset removed: STORE
  # and KEEL_HOME stay untouched there. Its STORE / KEEL_HOME rows would pass whatever the script did, so they are
  # structural (below) and only the tour carries the behavioural ones.
  if [ "$dn" = examples-tour-sh ]; then
    # shellcheck disable=SC2086  # $demo is "script [--scenes]" on purpose
    only_env KEEL_IMPACT_STORE "$SANDBOX/esc-store-$dn" bash "$REPO_ROOT"/$demo
    check_status "S9-7: ${demo%% *} with only an ambient KEEL_IMPACT_STORE → exit 0" 0 "$STATUS"
    check_nodir "${demo%% *} leaves the ambient KEEL_IMPACT_STORE untouched" "$SANDBOX/esc-store-$dn"
  fi
  # shellcheck disable=SC2086
  only_env KEEL_IMPACT_LOG "$SANDBOX/esc-log-$dn.tsv" bash "$REPO_ROOT"/$demo
  check_status "S9-7: ${demo%% *} with only an ambient KEEL_IMPACT_LOG → exit 0" 0 "$STATUS"
  check_nofile "${demo%% *} leaves the ambient KEEL_IMPACT_LOG untouched" "$SANDBOX/esc-log-$dn.tsv"
  if [ "$dn" = examples-tour-sh ]; then
    kh="$SANDBOX/esc-khome-$dn"; khome_fixture "$kh"; kh_before="$(tree_sum "$kh")"
    # shellcheck disable=SC2086
    only_env KEEL_HOME "$kh" bash "$REPO_ROOT"/$demo
    check_status "S9-7: ${demo%% *} with only an ambient KEEL_HOME holding a store → exit 0" 0 "$STATUS"
    check_eq "${demo%% *} leaves the ambient KEEL_HOME's store byte-for-byte untouched" "$kh_before" "$(tree_sum "$kh")"
  fi
done
# …and the structural half for record-demo.sh: it sources the one list of isolation variables and unsets ALL of it,
# not a hand-picked pair (the mutant that kept KEEL_HOME exported passed every behavioural row above).
pin "S9-7: record-demo.sh sources tools/lib/impact-store.sh for the isolation list" "$REPO_ROOT/docs/demo/record-demo.sh" \
  '. "$root/tools/lib/impact-store.sh"' "expected record-demo.sh to source the library that names every isolation variable"
pin "S9-7: record-demo.sh unsets that whole list" "$REPO_ROOT/docs/demo/record-demo.sh" \
  'unset $IMPACT_ISOLATION_VARS' "expected record-demo.sh to unset every impact-store override, not a hand-picked subset"

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
# HOME and GIT_CONFIG_GLOBAL are not the whole git-config surface. The GIT_CONFIG_COUNT/KEY_n/VALUE_n triple
# (command scope, beats every file), GIT_CONFIG_PARAMETERS (what a parent `git -c k=v` exports) and
# GIT_CONFIG_SYSTEM (an alternate system file) all reach a demo
# that claims to touch nothing of the operator's, and one carrying core.hooksPath=/dev/null silently turns the
# guard step into "commit succeeded". Behavioural for tour.sh, and a `git` shim for BOTH demos that records the
# env each git call actually sees (a no-op shim would pass a demo that never reached git, so the log must be
# non-empty). The real git is resolved first: tests/lib.sh defines a git() function, so type -P.
real_git="$(type -P git)"
shim="$SANDBOX/git-shim"; mkdir -p "$shim"
cat > "$shim/git" <<SHIM
#!/bin/sh
echo CALL >> "\$GIT_ENV_LOG"
env | grep -E '^GIT_CONFIG_(COUNT|PARAMETERS|SYSTEM|KEY_[0-9]+|VALUE_[0-9]+)=' >> "\$GIT_ENV_LOG"
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

run env GIT_CONFIG_PARAMETERS="'core.hooksPath=/dev/null'" bash "$REPO_ROOT/examples/tour.sh"
check_status "dir #753: tour.sh with an ambient GIT_CONFIG_PARAMETERS hooksPath → exit 0" 0 "$STATUS"
check_contains "dir #753: ...the key-shaped commit is still BLOCKED by the hook" "$OUT" "BLOCKED by the hook, exactly as intended"
check_absent "dir #753: ...never prints 'commit succeeded'" "$OUT" "commit succeeded"

for demo in "examples/tour.sh" "docs/demo/record-demo.sh --scenes"; do
  genv_log="$SANDBOX/git-env-$(printf '%s' "${demo%% *}" | tr '/.' '--').log"; : > "$genv_log"
  # shellcheck disable=SC2086  # $demo is "script [--scenes]" on purpose
  run env PATH="$shim:$PATH" GIT_ENV_LOG="$genv_log" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath \
    GIT_CONFIG_VALUE_0=/dev/null GIT_CONFIG_SYSTEM="$poison_sys" GIT_CONFIG_PARAMETERS="'core.hooksPath=/dev/null'" \
    bash "$REPO_ROOT"/$demo
  check_status "dir #753: ${demo%% *} under all three ambient routes runs to exit 0 (so the shim saw its whole run)" 0 "$STATUS"
  seen="$(cat "$genv_log")"
  check_contains "dir #753: the git shim saw ${demo%% *}'s git calls (the absence checks below are not vacuous)" "$seen" "CALL"
  check_absent "dir #753: no git call in ${demo%% *} sees GIT_CONFIG_COUNT/KEY_n/VALUE_n" "$seen" "GIT_CONFIG_COUNT"
  check_absent "dir #753: no git call in ${demo%% *} sees GIT_CONFIG_SYSTEM" "$seen" "GIT_CONFIG_SYSTEM"
  check_absent "dir #753: no git call in ${demo%% *} sees GIT_CONFIG_PARAMETERS" "$seen" "GIT_CONFIG_PARAMETERS"
done

# The emptiness guard must sit IMMEDIATELY after mktemp, before the first write (export HOME /
# mkdir / trap). Neither script runs under -e, so a failed mktemp leaves $sandbox empty and, unguarded,
# "$sandbox/home" is "/home" — a write outside any sandbox. Pinned by line order (running the red case
# for real would write at the filesystem root of a root-owned CI container).
# record-demo.sh's outer mode needs asciinema and agg, so no behavioural case reaches its $castdir guard: pin it.
pin "dir #753: record-demo.sh guards \$castdir right after its mktemp" "$REPO_ROOT/docs/demo/record-demo.sh" \
  '[ -n "$castdir" ] || {' \
  "expected the outer mode to refuse an empty \$castdir (an unguarded one aims asciinema at /demo.cast)"
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
