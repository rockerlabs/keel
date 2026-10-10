#!/usr/bin/env bash
# test_lib_ci_harness.sh — dir #744 slice 2's three tests/lib.sh changes, each driven end to end:
#   B13 (A12) git auto-maintenance is off in every test sandbox, APPENDED to the GIT_CONFIG_COUNT triple
#             (an inherited entry survives lib.sh), and survives fresh_home_env;
#   B14 (A13) the sandbox teardown names what survived and who held it, retries once, and leaves a path it
#             still cannot remove for the residue gate — driven by an `rm` shim, so it is deterministic and
#             runs as root on the alpine leg (no chmod);
#   B15 (A14) check_status_out fails like check_status and prints $OUT's first 40 lines on a mismatch only.
# The B14/B15 cases run a CHILD file that sources the real tests/lib.sh, exactly as a test file does.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib_path="$TESTS_DIR/lib.sh"

# --- B13 (A12): no detached `git maintenance run` from a commit in the sandbox ----------------------------
d="$(new_repo)"
trace="$SANDBOX/a12-trace"
GIT_TRACE=1 git -C "$d" commit -q --allow-empty -m probe 2> "$trace"
maint_lines="$(grep -c 'maintenance run' "$trace" || true)"
check_eq "A12: a commit in the sandbox spawns no git maintenance run" "0" "$maint_lines"
check_eq "A12: maintenance.auto is false" "false" "$(git -C "$d" config --get maintenance.auto)"
check_eq "A12: gc.auto is 0" "0" "$(git -C "$d" config --get gc.auto)"

# fresh_home_env replaces HOME and GIT_CONFIG_GLOBAL only: the command-scope entries survive it.
fh="$SANDBOX/a12-fresh-home"
mkdir -p "$fh"
fresh_home_env "$fh"
run env "${FRESH_HOME_ENV[@]}" "$(type -P git)" -C "$d" config --get maintenance.auto
check_eq "A12: maintenance.auto is still false under fresh_home_env" "false" "$OUT"
run env "${FRESH_HOME_ENV[@]}" "$(type -P git)" -C "$d" config --get gc.auto
check_eq "A12: gc.auto is still 0 under fresh_home_env" "0" "$OUT"

# An entry a parent exported survives lib.sh: lib appends, never overwrites (an overwriting build fails here).
child="$SANDBOX/child_a12.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf '. %q || exit 1\n' "$lib_path"
  printf 'printf "probe=%%s\\n" "$(git config --get x.probe)"\n'
  printf 'printf "count=%%s\\n" "$GIT_CONFIG_COUNT"\n'
} > "$child"
run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=x.probe GIT_CONFIG_VALUE_0=kept bash "$child"
check_contains "A12: an inherited GIT_CONFIG entry survives lib.sh" "$OUT" "probe=kept"
a12_count="$(sed -n 's/^count=//p' <<< "$OUT")"
if [ -n "$a12_count" ] && [ "$a12_count" -ge 3 ]; then
  pass "A12: lib.sh appended its entries after the inherited one (count $a12_count >= 3)"
else
  fail "A12: lib.sh appended its entries after the inherited one" "GIT_CONFIG_COUNT after lib.sh = '$a12_count'"
fi

# --- B14 (A13): the teardown NOTE, retry, and the residue hand-off -----------------------------------------
real_rm="$(type -P rm)"
shimdir="$SANDBOX/rmshim"
mkdir -p "$shimdir"
# The shim fails for the child's own $SANDBOX argument (the child writes it to $STATE/target first) — once,
# or always — and execs the real rm for everything else.
cat > "$shimdir/rm" <<'SHIM'
#!/bin/sh
target="$(cat "$STATE/target" 2>/dev/null)"
for a in "$@"; do
  if [ -n "$target" ] && [ "$a" = "$target" ]; then
    n="$(cat "$STATE/fails" 2>/dev/null || echo 0)"
    if [ "$SHIM_MODE" = always ] || [ "$n" -lt 1 ]; then
      echo $((n + 1)) > "$STATE/fails"
      echo "rm: cannot remove '$a': shimmed failure" >&2
      exit 1
    fi
  fi
done
exec "$REAL_RM" "$@"
SHIM
chmod +x "$shimdir/rm"

# mk_teardown_child FILE STATE — a child test file: sources lib.sh, records its sandbox, leaves a nested file
# in it, and starts a holder process whose command line names the sandbox (`; :` keeps sh from exec'ing
# sleep directly, which would drop the holder path from the process line).
mk_teardown_child() {
  {
    printf '#!/usr/bin/env bash\n'
    printf '. %q || exit 1\n' "$lib_path"
    printf 'printf "%%s" "$SANDBOX" > %q\n' "$2/target"
    printf 'mkdir -p "$SANDBOX/keep/deep" && : > "$SANDBOX/keep/deep/file"\n'
    printf 'sh -c %q "$SANDBOX/holder" &\n' 'sleep 30; :'
    printf 'printf "%%s" "$!" > %q\n' "$2/holderpid"
    printf 'exit 0\n'
  } > "$1"
}

# (i) the removal fails exactly once: the NOTE names a survivor and the holder, the retry succeeds.
st1="$SANDBOX/a13-once"
mkdir -p "$st1"
mk_teardown_child "$SANDBOX/child_a13_once.sh" "$st1"
run env PATH="$shimdir:$PATH" STATE="$st1" SHIM_MODE=once REAL_RM="$real_rm" bash "$SANDBOX/child_a13_once.sh"
t1="$(cat "$st1/target" 2>/dev/null)"
check_ne "A13 (once): the child recorded its sandbox" "" "$t1"
check_contains "A13 (once): NOTE that the teardown failed once" "$OUT" "NOTE: sandbox teardown failed once: $t1"
check_contains "A13 (once): ...naming a surviving path" "$OUT" "$t1/keep/deep/file"
check_contains "A13 (once): ...and the holder's process line" "$OUT" "$t1/holder"
check_contains "A13 (once): NOTE that the retry succeeded" "$OUT" "NOTE: sandbox teardown needed a retry"
check_nodir "A13 (once): nothing left behind" "$t1"
[ -s "$st1/holderpid" ] && kill "$(cat "$st1/holderpid")" 2>/dev/null

# (ii) the removal always fails: the NOTE, no retry-success line, the path left for the residue gate.
st2="$SANDBOX/a13-always"
mkdir -p "$st2"
mk_teardown_child "$SANDBOX/child_a13_always.sh" "$st2"
run env PATH="$shimdir:$PATH" STATE="$st2" SHIM_MODE=always REAL_RM="$real_rm" bash "$SANDBOX/child_a13_always.sh"
t2="$(cat "$st2/target" 2>/dev/null)"
check_contains "A13 (always): NOTE that the teardown failed once" "$OUT" "NOTE: sandbox teardown failed once: $t2"
check_absent "A13 (always): no retry-success line" "$OUT" "needed a retry"
check_dir "A13 (always): the path is left for the residue gate" "$t2"
[ -s "$st2/holderpid" ] && kill "$(cat "$st2/holderpid")" 2>/dev/null
# This file removes it, by the path the NOTE printed (the child's sandbox lives outside ours).
case "$t2" in
  /*/tmp.*) "$real_rm" -rf "$t2" ;;
esac

# --- B15 (A14): check_status_out ---------------------------------------------------------------------------
child="$SANDBOX/child_a14_mismatch.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf '. %q || exit 1\n' "$lib_path"
  printf 'STATUS=1\nOUT="$(i=1; while [ "$i" -le 60 ]; do echo "outline$i"; i=$((i + 1)); done)"\n'
  printf 'check_status_out "a mismatched status" 0\n'
  printf 'summary\n'
} > "$child"
run bash "$child"
check_ne "A14: a mismatch fails the file (non-zero exit)" "0" "$STATUS"
check_contains "A14: a mismatch reads 0 passed, 1 failed" "$OUT" "0 passed, 1 failed"
check_contains "A14: a mismatch prints \$OUT" "$OUT" "outline1"
check_eq "A14: exactly 40 indented \$OUT lines on a 60-line \$OUT" "40" "$(grep -c '^          outline' <<< "$OUT")"
check_absent "A14: line 41 is not printed" "$OUT" "outline41"

child="$SANDBOX/child_a14_match.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf '. %q || exit 1\n' "$lib_path"
  printf 'STATUS=0\nOUT="must-not-print"\n'
  printf 'check_status_out "a matched status" 0\n'
  printf 'summary\n'
} > "$child"
run bash "$child"
check_status "A14: a match passes the file" 0 "$STATUS"
check_contains "A14: a match reads 1 passed, 0 failed" "$OUT" "1 passed, 0 failed"
check_absent "A14: a match prints nothing extra" "$OUT" "must-not-print"

# Both B15 call sites use it.
pin "A14: the self-doctor smoke uses check_status_out" "$REPO_ROOT/tests/test_self_doctor.sh" \
  'check_status_out "the real keel checkout is clean (no GAP)" 0' "expected the doctor smoke to print doctor's output on a mismatch"
pin "A14: the token-report --since case uses check_status_out" "$REPO_ROOT/tests/test_token_report.sh" \
  'check_status_out "--since far in the future exits 0, not an error" "0"' "expected the --since case to print the tool's output on a mismatch"

summary
