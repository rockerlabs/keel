#!/usr/bin/env bash
# test_run_sh.sh — tests/run.sh's own aggregation logic (dir #130), exercised against a throwaway
# fake tests/ directory (a copy of run.sh plus synthetic test_*.sh fixtures) rather than the real
# suite, so a fixture's deliberate failure never pollutes this suite's own pass/fail count.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

runner="$REPO_ROOT/tests/run.sh"
check_file "run.sh exists" "$runner"

# delta-audit 0.13.0 R2-1: every fixture below runs a COPY of run.sh, and a failing fixture makes that copy
# preserve its per-file logdir on purpose (dir #480). run.sh mints the logdir from a template rooted at
# $TMPDIR, so pointing $TMPDIR at the sandbox keeps each preserved logdir inside it — removed with the
# sandbox when this file exits — instead of stranding one in the real temp dir per failing fixture.
export TMPDIR="$SANDBOX"

# mkfakedir NAME — a throwaway tests/-shaped dir under $SANDBOX with its own copy of run.sh, so a
# fixture test_*.sh file inside it is the only thing run.sh's glob picks up. Includes a stub lib.sh
# (dir #627: run.sh now refuses to start when lib.sh is absent) so every fixture below — none of
# which sources lib.sh itself, they're synthetic scripts probing run.sh's OWN aggregation logic —
# clears that pre-flight check unaffected; mkfakedir_no_lib below is the variant that omits it, for
# testing the check itself.
mkfakedir() {
  local d; d="$(mktemp -d "$SANDBOX/faketests.XXXXXX")"
  cp "$runner" "$d/run.sh"
  chmod +x "$d/run.sh"
  : > "$d/lib.sh"
  printf '%s' "$d"
}

# mkfakedir_no_lib — same as mkfakedir but WITHOUT the lib.sh stub, for dir #627's own pre-flight
# check (run.sh must refuse to start, before any fixture runs, when lib.sh is missing).
mkfakedir_no_lib() {
  local d; d="$(mkfakedir)"
  rm -f "$d/lib.sh"
  printf '%s' "$d"
}

# --- all-pass: every fixture green -> exit 0, every file's own header printed --------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho slow-a; sleep 0.2\nexit 0\n'  > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho fast-b\nexit 0\n'             > "$d/test_b.sh"
printf '#!/usr/bin/env bash\necho slow-c; sleep 0.2\nexit 0\n'  > "$d/test_c.sh"
run env KEEL_TEST_JOBS=3 bash "$d/run.sh"
check_status "all-pass fixtures -> exit 0" 0 "$STATUS"
check_contains "all-pass reports ALL TEST FILES PASSED" "$OUT" "ALL TEST FILES PASSED"
check_contains "all-pass includes test_a.sh's own header" "$OUT" "=== test_a.sh ==="
check_contains "all-pass includes test_b.sh's own header" "$OUT" "=== test_b.sh ==="
check_contains "all-pass includes test_c.sh's own header" "$OUT" "=== test_c.sh ==="
check_contains "all-pass carries test_a.sh's own stdout" "$OUT" "slow-a"
check_contains "all-pass carries test_b.sh's own stdout" "$OUT" "fast-b"
check_contains "all-pass carries test_c.sh's own stdout" "$OUT" "slow-c"

# --- one failure among several -> non-zero exit, failure is named, others still ran --------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n'                                > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho boom-from-b\nexit 1\n'              > "$d/test_b.sh"
printf '#!/usr/bin/env bash\nexit 0\n'                                > "$d/test_c.sh"
run env KEEL_TEST_JOBS=3 bash "$d/run.sh"
check_status "one failing fixture -> exit 1" 1 "$STATUS"
check_contains "one failing fixture -> reports 1 TEST FILE(S) FAILED" "$OUT" "1 TEST FILE(S) FAILED"
check_contains "one failing fixture -> the failing file's own output survives" "$OUT" "boom-from-b"
check_contains "one failing fixture -> a passing sibling still ran" "$OUT" "=== test_a.sh ==="
check_contains "one failing fixture -> the other passing sibling still ran" "$OUT" "=== test_c.sh ==="

# --- KEEL_TEST_JOBS=1 (sequential fallback) -> same aggregation, still catches the failure --------
run env KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "KEEL_TEST_JOBS=1 still catches the failure -> exit 1" 1 "$STATUS"
check_contains "KEEL_TEST_JOBS=1 still names it" "$OUT" "boom-from-b"

# --- a non-numeric KEEL_TEST_JOBS falls back rather than erroring ---------------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_a.sh"
run env KEEL_TEST_JOBS=bogus bash "$d/run.sh"
check_status "KEEL_TEST_JOBS=bogus doesn't crash the runner -> exit 0" 0 "$STATUS"
check_contains "KEEL_TEST_JOBS=bogus still passes a green fixture" "$OUT" "ALL TEST FILES PASSED"

# --- every fixture actually ran, even with more fixtures than the concurrency cap -----------------
d="$(mkfakedir)"
for n in 1 2 3 4 5 6; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_$n.sh"
done
run env KEEL_TEST_JOBS=2 bash "$d/run.sh"
check_status "more fixtures than the jobs cap -> still exit 0" 0 "$STATUS"
for n in 1 2 3 4 5 6; do
  check_contains "fixture $n ran despite the concurrency cap" "$OUT" "=== test_$n.sh ==="
done

# --- dir #744 B12(a): concurrency is proven by a PEAK COUNT, never by elapsed time --------------------
# The old checks timed the whole run (4x 1 s ≤ 3 s, 6x 1 s ≤ 3 s, 2–5 s, ≥ 5 s), so runner start-up under
# load — not the cap — decided them (E9: seven of them red at a 3 s start delay). Each fixture below now
# registers itself in live/, waits until live/ holds BARRIER entries (or every fixture still to come is
# already live or done, or 20 s pass), keeps its entry 2 s more while re-counting, and records the highest
# count it saw. run.sh launches on a 0.1 s poll, far inside the 2 s hold, so a launch past the cap is
# always seen; a cap below BARRIER shows as a peak below it. The asserted cap is the MAXIMUM recorded peak.
# mk_peak_fixtures DIR N BARRIER — N such fixtures in DIR (a mkfakedir), peaks appended to DIR/peaks.
mk_peak_fixtures() {
  local d="$1" n="$2" barrier="$3" i
  mkdir -p "$d/live" "$d/done"
  for i in $(seq 1 "$n"); do
    cat > "$d/test_peak$i.sh" <<FIX
#!/usr/bin/env bash
d="\$(cd "\$(dirname "\$0")" && pwd)"
count() { set -- "\$d/\$1"/*; [ -e "\$1" ] || { echo 0; return; }; echo \$#; }
: > "\$d/live/\$\$"
peak=0
w=0
while :; do
  l="\$(count live)"; dn="\$(count done)"
  [ "\$l" -gt "\$peak" ] && peak="\$l"
  { [ "\$l" -ge $barrier ] || [ \$((l + dn)) -ge $n ] || [ "\$w" -ge 200 ]; } && break
  sleep 0.1; w=\$((w + 1))
done
h=0
while [ "\$h" -lt 20 ]; do
  l="\$(count live)"; [ "\$l" -gt "\$peak" ] && peak="\$l"
  sleep 0.1; h=\$((h + 1))
done
echo "\$peak" >> "\$d/peaks"
: > "\$d/done/\$\$"
rm -f "\$d/live/\$\$"
FIX
  done
}
# max_peak DIR — the highest peak any fixture in DIR recorded (0 when none ran).
max_peak() { local m=0 p; while IFS= read -r p; do [ "$p" -gt "$m" ] && m="$p"; done < "$1/peaks"; echo "$m"; }

d="$(mkfakedir)"
mk_peak_fixtures "$d" 6 4
run env KEEL_TEST_JOBS=4 bash "$d/run.sh"
check_status "jobs=4, 6 fixtures -> exit 0" 0 "$STATUS"
check_eq "jobs=4: 6 fixtures run 4 at a time, never more (peak count)" "4" "$(max_peak "$d")"

# $CI caps the default at 2, overriding a host reporting more cores (dir #154). A fake `nproc` on PATH
# decouples this from the real host's core count.
fakebin="$(mktemp -d "$SANDBOX/fakebin.XXXXXX")"
printf '#!/usr/bin/env bash\necho 9\n' > "$fakebin/nproc"
chmod +x "$fakebin/nproc"

# CI unset -> the (mocked, high) nproc default: all 6 at once.
d="$(mkfakedir)"
mk_peak_fixtures "$d" 6 6
run env -u KEEL_TEST_JOBS -u CI PATH="$fakebin:$PATH" bash "$d/run.sh"
check_status "CI unset: nproc-default fixtures -> exit 0" 0 "$STATUS"
check_eq "CI unset: 6 fixtures run at the mocked nproc=9 default, not capped (peak count)" "6" "$(max_peak "$d")"

# CI=true -> capped at 2 regardless of the mocked nproc.
d="$(mkfakedir)"
mk_peak_fixtures "$d" 3 2
run env -u KEEL_TEST_JOBS PATH="$fakebin:$PATH" CI=true bash "$d/run.sh"
check_status "CI=true: capped fixtures -> exit 0" 0 "$STATUS"
check_eq "CI=true: 3 fixtures cap at 2 despite a high mocked nproc (peak count)" "2" "$(max_peak "$d")"

# KEEL_TEST_JOBS still overrides $CI's default (dir #154): fully sequential, a peak of 1.
d="$(mkfakedir)"
mk_peak_fixtures "$d" 2 1
run env PATH="$fakebin:$PATH" KEEL_TEST_JOBS=1 CI=true bash "$d/run.sh"
check_status "KEEL_TEST_JOBS=1 under CI=true still runs -> exit 0" 0 "$STATUS"
check_contains "KEEL_TEST_JOBS=1 under CI=true still passes all fixtures" "$OUT" "ALL TEST FILES PASSED"
check_eq "KEEL_TEST_JOBS=1 under CI=true runs one at a time, not capped at 2 (peak count)" "1" "$(max_peak "$d")"

# --- SIGTERM mid-run: exits 130, kills the still-running children, and — unlike a naive kill-and-
# exit — still surfaces each interrupted fixture's own buffered output (dir #130). dir #744 B12(b): the
# fixtures write a marker once they are up (run.sh buffers their stdout until reap, so polling the output
# could never succeed before the kill — E9), and only kill→exit is timed: never anything from runner start.
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho hello-from-int-a\n: > "$(dirname "$0")/up-a"\nexec sleep 30\n' > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho hello-from-int-b\n: > "$(dirname "$0")/up-b"\nexec sleep 30\n' > "$d/test_b.sh"
int_out="$(mktemp "$SANDBOX/int-out.XXXXXX")"
env KEEL_TEST_JOBS=2 bash "$d/run.sh" >"$int_out" 2>&1 &
rpid=$!
w=0
while { [ ! -e "$d/up-a" ] || [ ! -e "$d/up-b" ]; } && [ "$w" -lt 200 ]; do sleep 0.1; w=$((w + 1)); done
check_file "SIGTERM mid-run -> fixture a was up before the kill" "$d/up-a"
check_file "SIGTERM mid-run -> fixture b was up before the kill" "$d/up-b"
t0=$(date +%s)
kill -TERM "$rpid"
wait "$rpid"
int_status=$?
t1=$(date +%s)
int_out_text="$(cat "$int_out")"
check_status "SIGTERM mid-run -> exit 130" 130 "$int_status"
check_contains "SIGTERM mid-run -> test_a's output survives the kill" "$int_out_text" "hello-from-int-a"
check_contains "SIGTERM mid-run -> test_b's output survives the kill" "$int_out_text" "hello-from-int-b"
check_contains "SIGTERM mid-run -> names test_a as interrupted" "$int_out_text" "=== test_a.sh (interrupted) ==="
check_contains "SIGTERM mid-run -> names test_b as interrupted" "$int_out_text" "=== test_b.sh (interrupted) ==="
if [ "$((t1 - t0))" -le 10 ]; then
  pass "SIGTERM mid-run -> kill to exit within 10s, the 30s sleeps were killed, not waited out ($((t1 - t0))s)"
else
  fail "SIGTERM mid-run -> kill to exit within 10s" "took $((t1 - t0))s from the kill"
fi
rm -f "$int_out"

# --- dir #744 B10 (A10): the per-file watchdog -----------------------------------------------------
# A hanging file is TERMed past KEEL_TEST_FILE_TIMEOUT, reported with its pre-hang output, counted once.
# No wall-clock bound: the proof the file was cut short is its `finished` marker, absent when run.sh returns.
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho pre-hang-output\nsleep 30\n: > "$(dirname "$0")/finished"\n' > "$d/test_hang.sh"
run env -u CI KEEL_TEST_FILE_TIMEOUT=2 bash "$d/run.sh"
check_status "watchdog: a hanging file under KEEL_TEST_FILE_TIMEOUT=2 -> exit 1" 1 "$STATUS"
check_contains "watchdog: prints the timed-out header" "$OUT" "=== test_hang.sh (timed out after 2s) ==="
check_contains "watchdog: prints the file's pre-hang output" "$OUT" "pre-hang-output"
check_contains "watchdog: counts it as ONE failure" "$OUT" "1 TEST FILE(S) FAILED"
check_nofile "watchdog: the file was cut short (its finished marker is absent when run.sh returns)" "$d/finished"
check_contains "watchdog: announces its value" "$OUT" "watchdog: 2s"

# Guards (they hold without a watchdog too): unset + CI unset = off, a 1 s file is never killed; a 5 s
# limit lets a 1 s file pass.
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nsleep 1\necho one-second-done\n' > "$d/test_one.sh"
run env -u CI -u KEEL_TEST_FILE_TIMEOUT bash "$d/run.sh"
check_status "watchdog off locally: a 1 s file passes -> exit 0" 0 "$STATUS"
check_contains "watchdog: both unset -> off" "$OUT" "watchdog: off"
run env -u CI KEEL_TEST_FILE_TIMEOUT=5 bash "$d/run.sh"
check_status "watchdog 5 s: a 1 s file passes -> exit 0" 0 "$STATUS"
check_absent "watchdog 5 s: nothing timed out" "$OUT" "timed out after"

# The default is read from the same variable the reap enforces (the fixture is instant, so these runs only
# show the announcement).
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_fast.sh"
run env -u KEEL_TEST_FILE_TIMEOUT CI=true bash "$d/run.sh"
check_contains "watchdog default under CI: 600s" "$OUT" "watchdog: 600s"
run env KEEL_TEST_FILE_TIMEOUT=bogus CI=true bash "$d/run.sh"
check_contains "watchdog: a non-numeric value falls back to the CI default" "$OUT" "watchdog: 600s"
run env KEEL_TEST_FILE_TIMEOUT=010 CI=true bash "$d/run.sh"
check_contains "watchdog: a leading zero is non-numeric -> the CI default" "$OUT" "watchdog: 600s"
run env -u CI KEEL_TEST_FILE_TIMEOUT=0 bash "$d/run.sh"
check_contains "watchdog: 0 -> off" "$OUT" "watchdog: off"

# The deadline is per file, from that file's own launch: three sequential 2 s files under a 3 s limit.
d="$(mkfakedir)"
for n in 1 2 3; do printf '#!/usr/bin/env bash\nsleep 2\n' > "$d/test_seq$n.sh"; done
run env -u CI KEEL_TEST_JOBS=1 KEEL_TEST_FILE_TIMEOUT=3 bash "$d/run.sh"
check_status "watchdog is per file: three sequential 2 s files under a 3 s limit -> exit 0" 0 "$STATUS"
check_absent "watchdog is per file: none was killed" "$OUT" "timed out after"

# The default ENFORCES (not only announces): a scratch run.sh whose default literal is 3, run under CI with
# the variable unset, kills the 30 s file.
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho pre-hang-output\nsleep 30\n: > "$(dirname "$0")/finished"\n' > "$d/test_hang.sh"
replace_in_line_containing "$d/run.sh" "file_timeout=600;" "file_timeout=600;" "file_timeout=3;"
pin "mutation copy: the default literal was replaced" "$d/run.sh" "file_timeout=3;" "expected the scratch run.sh's CI default to read 3"
run env -u KEEL_TEST_FILE_TIMEOUT CI=true bash "$d/run.sh"
check_status "the CI default enforces: a 30 s file under a default of 3 -> exit 1" 1 "$STATUS"
check_contains "the CI default enforces: timed out after 3s" "$OUT" "(timed out after 3s)"

# --- dir #744 B11 (A11): the slowest-files block -----------------------------------------------------
# The watchdog limit sits ABOVE the 10 s file (a limit below it would kill that file too): the hung file is
# killed at ~12 s and listed first, the 10 s file second — numeric order (a text sort puts 2s above 10s).
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nsleep 10\n' > "$d/test_s10.sh"
printf '#!/usr/bin/env bash\nsleep 2\n'  > "$d/test_s2.sh"
printf '#!/usr/bin/env bash\nsleep 1\n'  > "$d/test_s1a.sh"
printf '#!/usr/bin/env bash\nsleep 1\n'  > "$d/test_s1b.sh"
printf '#!/usr/bin/env bash\nexit 0\n'   > "$d/test_fast.sh"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$d/test_hung.sh"
run env -u CI KEEL_TEST_JOBS=6 KEEL_TEST_FILE_TIMEOUT=12 bash "$d/run.sh"
check_status "slowest block: a run with one timed-out file -> exit 1" 1 "$STATUS"
slow_block="$(awk '/^slowest test files:$/ { on = 1; next } on && /^  [0-9]+s / { print; next } on { exit }' <<< "$OUT")"
check_eq "slowest block: exactly 5 lines" "5" "$(grep -c . <<< "$slow_block")"
check_eq "slowest block: the timed-out file is listed, first (killed at ~12 s)" "test_hung.sh" "$(sed -n '1s/^  [0-9]*s //p' <<< "$slow_block")"
check_eq "slowest block: the 10 s file second" "test_s10.sh" "$(sed -n '2s/^  [0-9]*s //p' <<< "$slow_block")"
check_eq "slowest block: the 2 s file below both (numeric, not text, order)" "test_s2.sh" "$(sed -n '3s/^  [0-9]*s //p' <<< "$slow_block")"
s1_order="$(sed -n 's/^  [0-9]*s //p' <<< "$slow_block" | grep '^test_s1[ab]' | tr '\n' ' ')"
check_eq "slowest block: equal times listed in name order" "test_s1a.sh test_s1b.sh " "$s1_order"
order="$(grep -nE '^residue gate|^slowest test files:|TEST FILE\(S\) FAILED$' <<< "$OUT" | cut -d: -f1 | tr '\n' ' ')"
r_line="$(cut -d' ' -f1 <<< "$order")"; s_line="$(cut -d' ' -f2 <<< "$order")"; v_line="$(cut -d' ' -f3 <<< "$order")"
if [ "$r_line" -lt "$s_line" ] && [ "$s_line" -lt "$v_line" ]; then
  pass "slowest block: after the residue-gate line, before the verdict"
else
  fail "slowest block: after the residue-gate line, before the verdict" "line order residue/slowest/verdict = $order"
fi
check_contains "slowest block: the verdict keeps its exact text" "$OUT" "1 TEST FILE(S) FAILED"

# --- dir #480's cheap discrimination: a failing run's per-file logs must survive the process, not
# vanish with the EXIT-trap cleanup, so a one-off local failure (the shape dir #480 itself was filed
# from — a single unreproduced report with nothing preserved to inspect afterward) leaves real
# evidence behind instead of an anecdote. A passing run still cleans up as before (no clutter). -----
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n'                                       > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho dir480-marker-line\nexit 1\n'              > "$d/test_b.sh"
run env KEEL_TEST_JOBS=2 bash "$d/run.sh"
check_status "failing fixture -> exit 1 (logdir case)" 1 "$STATUS"
check_contains "a failing run names where its per-file logs were preserved" "$OUT" "per-file logs preserved"
preserved_dir="$(printf '%s\n' "$OUT" | sed -n 's/.*per-file logs preserved[^:]*: //p' | tail -1)"
check_dir "the preserved logdir actually exists after run.sh exited" "$preserved_dir"
case "$preserved_dir" in
  "$SANDBOX"/*) pass "R2-1: the preserved logdir sits under \$TMPDIR (the sandbox), not the real temp dir" ;;
  *) fail "R2-1: the preserved logdir sits under \$TMPDIR (the sandbox), not the real temp dir" "got: $preserved_dir" ;;
esac
check_contains "the preserved logdir holds the failing file's own log, not just a stub" \
  "$(cat "$preserved_dir/test_b.sh.log" 2>/dev/null)" "dir480-marker-line"
[ -n "$preserved_dir" ] && rm -rf "$preserved_dir"

# --- a clean, all-pass run reports no preserved logdir and cleans up (no regression to the old
# unconditional-cleanup behavior in the success case) ------------------------------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_a.sh"
run env KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "all-pass fixture -> exit 0 (logdir case)" 0 "$STATUS"
check_absent "an all-pass run reports no preserved logdir" "$OUT" "per-file logs preserved"

# dir #567: the assertions above only check what run.sh PRINTS, not whether its own
# `logdir="$(mktemp -d)"` / `trap 'rm -rf "$logdir"' EXIT` actually removed the directory on the
# all-pass path — a verifier mutation that disarms the EXIT-trap cleanup unconditionally (logdir
# leaked on every run) left every prior assertion in this file green. Since a clean run prints no
# path, the logdir can't be named after the fact the way the failure branch's $preserved_dir is —
# instead a `mktemp` shim ahead of the real one on PATH records the path run.sh's own `mktemp -d`
# creates (a bare `mktemp -d`, unlike a template or `mktemp -t`, does not honor $TMPDIR on macOS/BSD;
# run.sh now passes a template, but a shim stays the portable way to learn the path whichever form it uses).
mktemp_shim_dir="$(mktemp -d "$SANDBOX/mktemp-shim.XXXXXX")"
mktemp_log="$(mktemp "$SANDBOX/mktemp-log.XXXXXX")"
real_mktemp="$(command -v mktemp)"
cat > "$mktemp_shim_dir/mktemp" <<EOF
#!/usr/bin/env bash
out="\$("$real_mktemp" "\$@")"
printf '%s\n' "\$out" >> "$mktemp_log"
printf '%s\n' "\$out"
EOF
chmod +x "$mktemp_shim_dir/mktemp"
run env KEEL_TEST_JOBS=1 PATH="$mktemp_shim_dir:$PATH" bash "$d/run.sh"
check_status "all-pass fixture -> exit 0 (logdir cleanup probe)" 0 "$STATUS"
logdir_probe="$(tail -1 "$mktemp_log")"
check_nodir "an all-pass run's logdir is actually removed, not just unreported" "$logdir_probe"
rm -rf "$mktemp_shim_dir" "$mktemp_log"

# --- dir #627, fix 2: run.sh refuses to start when lib.sh is missing, BEFORE any fixture runs -----
# (the felt incident: a missing tests/lib.sh — a gitignored symlink in the claude-kb adopter, absent
# from a fresh `git worktree add` — let fixtures run unsandboxed against the real machine).
d="$(mkfakedir_no_lib)"
printf '#!/usr/bin/env bash\necho should-not-run\nexit 0\n' > "$d/test_a.sh"
run bash "$d/run.sh"
check_status "missing lib.sh -> exit 1, before any fixture" 1 "$STATUS"
check_contains "missing lib.sh -> names the file and cites the ticket" "$OUT" "dir #627"
check_contains "missing lib.sh -> names the remedy" "$OUT" "lib.sh is missing"
check_absent "missing lib.sh -> no fixture actually ran" "$OUT" "should-not-run"
check_absent "missing lib.sh -> run.sh never even printed the fixture's own header" "$OUT" "=== test_a.sh ==="

# --- dir #627, second fail-open backstop: a fixture that exits 0 but logged "command not found" (the
# shape of an undefined check_* silently vanishing, bash's own message when lib.sh's
# command_not_found_handle doesn't exist yet — bash < 4 — or wasn't reached) is escalated to a
# failure, not counted as a pass. Portable: this scan doesn't depend on the ambient bash version, only
# on grepping the log line bash itself already prints. ------------------------------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho fine-a\nexit 0\n' > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho fine-before\ncheck_totally_undefined_thing_dir627 2>&1\necho fine-after\nexit 0\n' > "$d/test_b.sh"
run env KEEL_TEST_JOBS=2 bash "$d/run.sh"
check_status "command-not-found in an exit-0 fixture -> escalated to a suite failure" 1 "$STATUS"
check_contains "escalation names the fixture and cites the ticket" "$OUT" "dir #627"
check_contains "the fixture's own output still survives (not just the escalation line)" "$OUT" "fine-before"
check_contains "a genuinely clean sibling fixture still passes" "$OUT" "fine-a"
check_contains "the failure count reflects the escalation" "$OUT" "1 TEST FILE(S) FAILED"

# --- dir #627, the SAME backstop must NOT false-fire on a fixture whose own legitimate PASS-labeled
# output happens to mention the phrase "command not found" in some OTHER shape than bash's own exact
# message suffix (found by an independent /code-review high pass on this ticket's own diff: an
# earlier version matched the bare substring anywhere in the log, which a check label like this one
# would have wrongly escalated). --------------------------------------------------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho "ok handles a missing binary and prints command not found gracefully"\nexit 0\n' > "$d/test_a.sh"
run bash "$d/run.sh"
check_status "a PASS string merely mentioning the phrase does NOT false-fire the backstop" 0 "$STATUS"
check_contains "the fixture's own output still prints" "$OUT" "ALL TEST FILES PASSED"

# --- dir #333, release-manager-verified seam: the claude-kb adopter shape symlinks ONLY tests/run.sh
# and tests/lib.sh (dir #627) into a checkout that carries no tools/lib/ of its own. `here` there is
# the SYMLINK's directory (dirname does not resolve it), so guard_repo_root (one level up) is that
# other checkout, and `guard_repo_root/tools/lib/ref-guard.sh` genuinely does not exist. Reproduced
# here without touching the real KB: a git repo whose tests/run.sh is a symlink to the real one, with
# no tools/ tree beside it at all — the ref-scoping half of the canary must degrade to a one-line
# NOTE, never crash or kill the suite (the branch/HEAD/status half, dir #318, is unaffected either
# way since these are synthetic fixtures with no real leak to catch).
symroot="$(mktemp -d "$SANDBOX/symlinked-adopter.XXXXXX")"
git -C "$symroot" init -q
git -C "$symroot" commit -q --allow-empty -m init
mkdir -p "$symroot/tests"
ln -s "$runner" "$symroot/tests/run.sh"
: > "$symroot/tests/lib.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$symroot/tests/test_a.sh"
run bash "$symroot/tests/run.sh"
check_status "symlinked run.sh with no sibling tools/ -> still exit 0" 0 "$STATUS"
check_contains "symlinked run.sh -> ALL TEST FILES PASSED still reported" "$OUT" "ALL TEST FILES PASSED"
check_contains "symlinked run.sh -> the ref-scope NOTE names dir #333" "$OUT" "dir #333"
check_contains "symlinked run.sh -> the ref-scope NOTE says ref-guard.sh was not found" "$OUT" "ref-guard.sh not found"
check_contains "symlinked run.sh -> the fixture still ran despite the NOTE" "$OUT" "=== test_a.sh ==="

# new_engine_fixture — a real repo holding one tracked file, plus a HOME whose .keel/engine links to it (the
# dir #653 engine half). Sets ENG_REPO and ENG_HOME (two values, so not a $(...) helper like its neighbours).
new_engine_fixture() {
  ENG_REPO="$(new_repo)"
  printf 'tracked\n' > "$ENG_REPO/engine-file.txt"
  git -C "$ENG_REPO" add engine-file.txt
  git -C "$ENG_REPO" commit -q -m init
  ENG_HOME="$(mktemp -d "$SANDBOX/enghome.XXXXXX")"
  mkdir -p "$ENG_HOME/.keel"
  ln -s "$ENG_REPO" "$ENG_HOME/.keel/engine"
}

# new_run_sh_fixture — a throwaway REAL git repo (new_repo, unlike mkfakedir's synthetic dir) with a
# copy of run.sh under tests/ and a stub lib.sh, for the corruption-canary fixtures below (T8, B19,
# T1, T3) that all drive run.sh against a real checkout of their own. Promoted here at its second use
# (this file's own "second use = promote" convention, tests/lib.sh's pin() comment) — T8 below was
# the first, B19/T1/T3 make four more (found by this ticket's own /code-review high pass: T8 was
# initially left hand-rolling the same bootstrap the helper now encapsulates). Prints its path, like
# new_repo/mkfakedir.
new_run_sh_fixture() {
  local d; d="$(new_repo)"
  git -C "$d" commit -q --allow-empty -m init
  mkdir -p "$d/tests"
  cp "$runner" "$d/tests/run.sh"
  : > "$d/tests/lib.sh"
  printf '%s' "$d"
}

# --- dir #318 T8: a fixture test file that leaks a bare `git branch` against its own watched repo
# trips the canary end-to-end (unlike the guard itself, which this file cannot exercise against the
# REAL checkout without corrupting the very thing it protects — this fixture repo is disposable).
# The fixture's own lib.sh is a stub (the guard is not armed there — this drives run.sh's OWN
# detection half, not tests/lib.sh's prevention half), but it DOES carry a copy of
# tools/lib/ref-guard.sh, so guard_ref_scope_available stays 1 and the unowned-refs block actually
# runs (E20: without it, that block is skipped entirely).
leakroot="$(new_run_sh_fixture)"
mkdir -p "$leakroot/tools/lib"
cp "$REPO_ROOT/tools/lib/ref-guard.sh" "$leakroot/tools/lib/ref-guard.sh"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." branch leak\nexit 0\n' > "$leakroot/tests/test_leak.sh"
run bash "$leakroot/tests/run.sh"
check_status "a leaked branch trips the canary -> exit 1" 1 "$STATUS"
check_contains "the trip block prints TRIPPED" "$OUT" "TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #318)"
check_contains "the trip names the unowned-branch change and points at tests/lib.sh's guard (dir #318, G4)" \
  "$OUT" "an ordinary test file cannot have done this on its own — tests/lib.sh guard (dir #318) refuses every test ref write it makes — so look outside the suite first"
check_contains "the trip names N8 as CLOSED by dir #644, not still a hedged exception" \
  "$OUT" "dir #318 residual N8, an inherited GIT_DIR+GIT_COMMON_DIR pair, was the one narrow exception; dir #644 closed it"
check_contains "the changed two-way attribution line (dir #318, G4)" \
  "$OUT" "either a test escaped its sandbox, or something outside the suite changed this checkout during the run:"
check_contains "the kept 'do not push' clause survives word for word (dir #318, G4)" \
  "$OUT" "do not push this branch until the real history is reconciled by hand."
git -C "$leakroot" branch -D leak >/dev/null 2>&1 || true

# --- dir #630 S4 (B19): the tests/run.sh tripwire — a test that writes the real checkout's own
# keel.impactStore/keel.readTraceStore record trips the canary, naming the new value; an unchanged
# run passes. Needs no tools/lib/ref-guard.sh copy (unlike the T8 fixture above): this check runs
# whenever guard_repo_root is a git repo at all, independent of the ref-scope half. ------------------
b19root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." config --local --add keel.impactStore /fake/lost-entry\nexit 0\n' \
  > "$b19root/tests/test_b19_leak.sh"
run bash "$b19root/tests/run.sh"
check_status "B19: a test writing the real repo's keel.impactStore trips the canary -> exit 1" 1 "$STATUS"
check_contains "B19: the trip names dir #630's S4 tripwire" "$OUT" "dir #630 S4 tripwire"
check_contains "B19: the trip names the changed key" "$OUT" "keel.impactstore"
check_absent "B19: the trip withholds the value (found live by /code-review high: a credential-shaped value elsewhere in local config must never be echoed)" \
  "$OUT" "/fake/lost-entry"
git -C "$b19root" config --local --unset-all keel.impactStore >/dev/null 2>&1 || true

# an UNCHANGED run (no test file mutates the config) passes
rm -f "$b19root/tests/test_b19_leak.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$b19root/tests/test_b19_clean.sh"
run bash "$b19root/tests/run.sh"
check_status "B19: an unchanged run passes" 0 "$STATUS"
check_contains "B19: an unchanged run reports ALL TEST FILES PASSED" "$OUT" "ALL TEST FILES PASSED"

# --- T1 (delta-audit 0.11.0-0.12.0 fix round): the tripwire now diffs the WHOLE local config, not
# just the two keel.impactStore/keel.readTraceStore keys above — a fixture that writes an ARBITRARY
# key the old snapshot never watched (zz.probe) still trips, and the trip names the leaked key.
# Mutation proof (run manually, not committed): temporarily restoring the old two-named-key snapshot
# in tests/run.sh turns this assertion RED; restoring the widened snapshot turns it green again. -----
zz_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." config --local --add zz.probe leaked-value\nexit 0\n' \
  > "$zz_root/tests/test_zz_leak.sh"
run bash "$zz_root/tests/run.sh"
check_status "T1: a test writing an arbitrary zz.probe key trips the canary -> exit 1" 1 "$STATUS"
check_contains "T1: the trip still names dir #630's S4 tripwire" "$OUT" "dir #630 S4 tripwire"
check_contains "T1: the trip names the leaked key, not just the two old named keys" "$OUT" "zz.probe"
check_absent "T1: the trip withholds the leaked key's value" "$OUT" "leaked-value"

# --- T1: a key in the EXCLUDED branch.* namespace is NOT reported as a leak — pins the one disclosed
# residual named in tests/run.sh's own comment (ordinary concurrent activity outside this suite, e.g.
# a sibling session's `git push -u` / `branch --set-upstream-to`, writes exactly this shape). --------
br_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." config --local branch.some-branch.remote origin\nexit 0\n' \
  > "$br_root/tests/test_br_noise.sh"
run bash "$br_root/tests/run.sh"
check_status "T1: an excluded branch.* write does NOT trip the canary -> exit 0" 0 "$STATUS"
check_contains "T1: excluded branch.* write still reports ALL TEST FILES PASSED" "$OUT" "ALL TEST FILES PASSED"
check_absent "T1: excluded branch.* write is not named as a corruption trip" "$OUT" \
  "TEST-SUITE SELF-CORRUPTION GUARD TRIPPED"

# --- T1 (found live by this ticket's own /code-review high pass): a BARE top-level branch.* setting
# (no per-branch subsection — a real git-config(1) key, unrelated to the per-branch tracking noise the
# exclusion above is scoped to) still trips. Pins that the exclusion regex is scoped to
# branch.<name>.<subkey>, not the whole branch.* namespace. Mutation proof (run manually, not
# committed): widening the regex back to a bare `grep -v '^branch\.'` turns this assertion RED.
bratop_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." config --local branch.autoSetupMerge always\nexit 0\n' \
  > "$bratop_root/tests/test_bratop_leak.sh"
run bash "$bratop_root/tests/run.sh"
check_status "T1: a bare top-level branch.* setting still trips the canary -> exit 1" 1 "$STATUS"
check_contains "T1: the trip names the bare branch.* key" "$OUT" "branch.autosetupmerge"
check_absent "T1: the trip withholds the bare branch.* key's value" "$OUT" "always"

# --- F4b (found live by this ticket's own /code-review high pass): a FOUR-segment branch.* key
# (a branch literally named "foo.bar" — dots are valid in git branch names — makes
# `branch.foo.bar.remote`, section=branch/subsection="foo.bar"/key=remote) still trips: the new
# case-glob exclusion in guard_config_snapshot is scoped to exactly THREE segments
# (branch.<name>.<subkey>), same as the old regex's `[^.=]+\.[^.=]+=` could only ever match two
# single-segment captures. Mutation proof (run manually, not committed): widening the inner
# `case "$rest" in *.*.*) ;; *) continue ;; esac` to match ANY multi-dot rest (i.e. excluding this
# shape too) turns this assertion RED.
br4_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." config --local branch.foo.bar.remote origin\nexit 0\n' \
  > "$br4_root/tests/test_br4_leak.sh"
run bash "$br4_root/tests/run.sh"
check_status "F4b: a four-segment branch.<name>.<a>.<b> key still trips the canary -> exit 1" 1 "$STATUS"
check_contains "F4b: the trip names the four-segment key" "$OUT" "branch.foo.bar.remote"
check_absent "F4b: the trip withholds the four-segment key's value" "$OUT" "origin"

# --- T1 (manager-flagged, delta-audit 0.11.0-0.12.0 fix round): a changed key whose VALUE is
# credential-shaped (a token embedded in a URL, the exact actions/checkout http.*.extraHeader shape)
# never has that value echoed into the trip output — only the key name. The snapshot itself still
# fingerprints every key (a value-only change on an existing key must still trip); only the REPORT
# strips anything past the key, via guard_diff_keys_only(). Mutation proof (run manually, not
# committed): printing the raw `diff` output again (skipping the `| guard_diff_keys_only` filter)
# turns the second check below RED — the credential value reappears in $OUT.
cred_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." config --local http.https://example.invalid/.extraheader "AUTHORIZATION: basic dG90YWxseS1hLXJlYWwtdG9rZW4="\nexit 0\n' \
  > "$cred_root/tests/test_cred_leak.sh"
run bash "$cred_root/tests/run.sh"
check_status "T1: a credential-shaped config value trips the canary -> exit 1" 1 "$STATUS"
check_contains "T1: the trip names the credential-bearing key" "$OUT" "extraheader"
check_absent "T1: the trip withholds the credential value" "$OUT" "dG90YWxseS1hLXJlYWwtdG9rZW4="

# --- F4b (S-fix F2-T1, delta-audit 0.11.0-0.12.0 fix round): a MULTI-LINE config value's own
# continuation line used to carry no `key=` prefix, so the old cut-at-`=` filter let it straight
# through unredacted (live-reproduced, macOS + alpine, git 2.52.0). Reuses T1's own credential-
# shaped first line (`AUTHORIZATION: basic ...` above) with a second, also credential-SHAPED-but-not-
# secret-scan-KEY-shaped line appended via an embedded newline (a real `ghp_`+36 token here would trip
# this repo's own commit-time secret guard, same reason T1's line is `dG90YWxseS1hLXJlYWwtdG9rZW4=`,
# not a real token). guard_config_snapshot now fingerprints the WHOLE multi-line value as one record
# (git config --local --list -z), so neither line can leak. Mutation proof (run manually, not
# committed): reintroducing the raw value into guard_config_snapshot (the pre-F4b `--list` line form)
# turns both absence checks below RED on macOS AND the alpine leg; restoring the fingerprint form
# turns them green again. --------------------------------------------------------------------------
multiline_root="$(new_run_sh_fixture)"
cat > "$multiline_root/tests/test_multiline_leak.sh" <<'EOF'
#!/usr/bin/env bash
git -C "$(dirname "$0")/.." config --local multi.secret "$(printf 'AUTHORIZATION: basic dG90YWxseS1hLXJlYWwtdG9rZW4=\nSECONDLINE-dG90YWxseS1hLXJlYWwtc2Vjb25kLWxpbmU=')"
exit 0
EOF
run bash "$multiline_root/tests/run.sh"
check_status "F4b: a multi-line config value's leak still trips the canary -> exit 1" 1 "$STATUS"
check_contains "F4b: the trip names the multi-line key" "$OUT" "multi.secret"
check_absent "F4b: the trip withholds the FIRST line of the multi-line value" "$OUT" "dG90YWxseS1hLXJlYWwtdG9rZW4="
check_absent "F4b: the trip withholds the SECOND line (F2-T1's own gap: the old filter let exactly this line through unredacted)" \
  "$OUT" "dG90YWxseS1hLXJlYWwtc2Vjb25kLWxpbmU="

# --- T3 (delta-audit 0.11.0-0.12.0 fix round, S2 lead L3 / manager lead 3): a status-only change
# (an untracked file write, no commit) with HEAD unmoved now gets its own hint alongside the existing
# generic "status also changed" line, mirroring the HEAD-moved shape's dedicated hint above. Mutation
# proof (run manually, not committed): deleting the new hint block in tests/run.sh turns the third
# check below RED; restoring it turns it green again. ------------------------------------------------
st_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\necho dirty > "$(dirname "$0")/../untracked-leak.txt"\nexit 0\n' \
  > "$st_root/tests/test_st_leak.sh"
run bash "$st_root/tests/run.sh"
check_status "T3: an untracked-file leak (status-only, HEAD unmoved) trips the canary -> exit 1" 1 "$STATUS"
check_contains "T3: the existing generic status-changed line still prints" "$OUT" \
  "working-tree/index status also changed"
check_contains "T3: the new HEAD-unmoved hint names a concurrent own edit" "$OUT" \
  "possibly your own uncommitted edit (or a concurrent session's) to"
check_contains "T3: the hint says never edit during a live run and to reconcile by hand" "$OUT" \
  "edit a checkout while its own suite run is still alive). Reconcile by hand either way."

# --- dir #664: the status compare cannot see a leak that rewrites a tracked file the operator ALREADY had
# uncommitted edits in — ` M f.txt` before and ` M f.txt` after. The canary now also fingerprints the working-tree
# bytes of every tracked file that differs from HEAD, and a changed fingerprint trips it. dir #656 half 2: the trip
# block names the paths that differ (names only). The fixture's tracked f.txt holds an operator edit; g.txt is a
# second dirty file the leak leaves alone (a bystander the names block must NOT list). The two secret-shaped
# strings below stand for raw content: neither may ever be printed. Mutation proof (run manually, not committed):
# dropping the fingerprint clause from the dir #318 trip condition in tests/run.sh turns the exit-status and
# naming checks below RED; the no-content checks stay green on purpose (a trip that never fires prints nothing). --
new_dirty_fixture() {
  local d; d="$(new_run_sh_fixture)"
  printf 'committed-f\n' > "$d/f.txt"
  printf 'committed-g\n' > "$d/g.txt"
  git -C "$d" add f.txt g.txt
  git -C "$d" commit -q -m files
  printf 'operator-edit-secret-f\n' > "$d/f.txt"
  printf 'operator-edit-secret-g\n' > "$d/g.txt"
  printf '%s' "$d"
}
dirty_root="$(new_dirty_fixture)"
printf '#!/usr/bin/env bash\nprintf "leaked-content-marker\\n" > "$(dirname "$0")/../f.txt"\nexit 0\n' \
  > "$dirty_root/tests/test_dirty_leak.sh"
run bash "$dirty_root/tests/run.sh"
check_status "dir #664: a leak that rewrites an already-dirty tracked file trips the canary -> exit 1" 1 "$STATUS"
check_contains "dir #664: the trip block prints TRIPPED" "$OUT" "TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #318)"
check_contains "dir #664: the trip says the content of an already-dirty file changed" "$OUT" \
  "content of a tracked file that already had uncommitted changes differs from before the run"
check_contains "dir #656 half 2: the trip names the paths that differ, names only" "$OUT" \
  "paths that differ between the before and after snapshots (names only, never content):"
check_contains "dir #656 half 2: ... and names the rewritten file under an UNCHANGED status" "$OUT" "  f.txt"
check_absent "dir #656 half 2: ... and not the dirty bystander the leak left alone" "$OUT" "g.txt"
check_absent "dir #664: the trip never prints the leaked content" "$OUT" "leaked-content-marker"
check_absent "dir #664: the trip never prints the operator's own uncommitted content" "$OUT" "operator-edit-secret"

# the control: the SAME dirty tree, a test that leaves it alone -> the compare is quiet (a dirty tree is not a trip)
rm -f "$dirty_root/tests/test_dirty_leak.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$dirty_root/tests/test_dirty_clean.sh"
run bash "$dirty_root/tests/run.sh"
check_status "dir #664: a dirty tree the run leaves alone does not trip -> exit 0" 0 "$STATUS"
check_absent "dir #664: ... and prints no names block" "$OUT" "paths that differ between the before and after snapshots"

# a leak that touches a CLEAN tracked file moves the status (` M` appears): the trip names that path, and only it
rm -f "$dirty_root/tests/test_dirty_clean.sh"
git -C "$dirty_root" checkout -q -- f.txt
printf '#!/usr/bin/env bash\nprintf "leaked-content-marker\\n" > "$(dirname "$0")/../f.txt"\nexit 0\n' \
  > "$dirty_root/tests/test_status_leak.sh"
run bash "$dirty_root/tests/run.sh"
check_status "dir #656 half 2: a leak into a clean tracked file trips -> exit 1" 1 "$STATUS"
check_contains "dir #656 half 2: ... and the names block lists it" "$OUT" "  f.txt"
check_absent "dir #656 half 2: ... but not the bystander" "$OUT" "g.txt"

# dir #656 half 2 / R3-1: a TMPDIR INSIDE the watched checkout makes run.sh's own logdir an untracked path the
# after-snapshot sees — the trip is the known self-trip (R3-1, not fixed here), and the names block now says WHICH
# path moved: the `?? <dir>/` entry of the status compare, not a bare "status changed".
tmpin_root="$(new_run_sh_fixture)"
mkdir "$tmpin_root/scratch-tmp"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpin_root/tests/test_clean.sh"
run env TMPDIR="$tmpin_root/scratch-tmp" bash "$tmpin_root/tests/run.sh"
check_status "R3-1: a TMPDIR inside the watched checkout self-trips (the standing line, unchanged) -> exit 1" 1 "$STATUS"
check_contains "dir #656 half 2: the names block names the untracked directory the logdir created" "$OUT" "  scratch-tmp/"

# --- dir #505 (b'): the HEAD-moved hint (dir #333's amendment) had no pin, and named its benign cause
# without the one command that tells own-commit from leak. A fixture test that commits against the
# watched repo moves HEAD forward on the same branch: the trip still fires (exit 1, never downgraded),
# the hint names the own-commit cause, and it now names `git reflog -3` as the check. Mutation proof
# (run manually, not committed): deleting the HEAD-moved hint block in tests/run.sh turns the two
# hint checks RED; deleting only the reflog line turns the last one RED. ---------------------------
hm_root="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." commit -q --allow-empty -m own-commit\nexit 0\n' \
  > "$hm_root/tests/test_hm_commit.sh"
run bash "$hm_root/tests/run.sh"
check_status "dir #505: a forward HEAD move during the run trips the canary -> exit 1 (never downgraded)" 1 "$STATUS"
check_contains "dir #505: the HEAD-moved hint names the session's own commit as the likely cause" "$OUT" \
  "HEAD moved FORWARD on the same branch — possibly your own commit landing while this"
check_contains "dir #505: the hint says never to commit during a live run" "$OUT" \
  "commit against a checkout while its own suite run is still alive"
check_contains "dir #505: the hint names git reflog -3 as the check that tells own commit from leak" "$OUT" \
  "reflog -3 — a fresh entry of yours (commit/amend) made since the suite started"

# --- dir #653: the canary must survive a test overwriting run.sh (or lib.sh) itself. bash reads a
# script incrementally, so a fixture that rewrites the RUNNING run.sh in place (same inode, the shape
# of a fixture write through a symlink into a checkout; claude-kb's 2026-09-22 incident) used to stop
# the runner silently at the stale offset: it never reached its canary and exited 0. The body now
# sits in one function bash parses up front, and run.sh/lib.sh content is compared before/after.
# Every overwrite below targets the fakedir's OWN scratch copy — never the real checkout. ------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nprintf "#!/usr/bin/env bash\\nexit 0\\n" > "$(dirname "$0")/run.sh"\nexit 0\n' > "$d/test_selfwrite.sh"
run bash "$d/run.sh"
check_status "dir #653: a test overwriting the running run.sh -> non-zero, never a silent 0" 1 "$STATUS"
check_contains "dir #653: the trip names dir #653's canary" "$OUT" "TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #653)"
check_contains "dir #653: the trip names run.sh as the overwritten file" "$OUT" "run.sh changed during the run"
check_absent "dir #653: an overwritten run.sh is not reported as a pass" "$OUT" "ALL TEST FILES PASSED"
check_contains "dir #653: the runner still reports the failure count after the overwrite" "$OUT" "TEST FILE(S) FAILED"

d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nprintf "# overwritten\\n" > "$(dirname "$0")/lib.sh"\nexit 0\n' > "$d/test_libwrite.sh"
run bash "$d/run.sh"
# the fakedir is git-less (no dir #318 canary at all): only the content compare can trip here
check_status "dir #653: a test overwriting lib.sh -> non-zero" 1 "$STATUS"
check_contains "dir #653: the trip names lib.sh as the overwritten file" "$OUT" "lib.sh changed during the run"
check_absent "dir #653: the lib.sh overwrite does not also blame run.sh" "$OUT" "run.sh changed during the run"

# an unchanged run (no test touches run.sh/lib.sh) still passes and prints no #653 trip
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_clean.sh"
run bash "$d/run.sh"
check_status "dir #653: a run that leaves run.sh/lib.sh alone still passes" 0 "$STATUS"
check_absent "dir #653: an unchanged run prints no #653 trip" "$OUT" "(dir #653)"

# --- dir #653 widening (0.13.0 groom G6): the git canary watches guard_repo_root, which in the
# claude-kb shape is the KB checkout, not the engine checkout a leaking test actually wrote to (4 of
# the 6 files overwritten in 2026-09-22 were neither run.sh nor lib.sh). When $HOME/.keel/engine
# resolves to a DIFFERENT git checkout, its tracked-file status is compared before/after too.
# Untracked files are ignored on purpose (a peer session's new scratch file is not a leak). --------
new_engine_fixture; eng="$ENG_REPO"; enghome="$ENG_HOME"

watched="$(new_run_sh_fixture)"
printf '#!/usr/bin/env bash\nprintf "leaked\\n" > "%s/engine-file.txt"\nexit 0\n' "$eng" > "$watched/tests/test_engine_leak.sh"
run env HOME="$enghome" bash "$watched/tests/run.sh"
check_status "dir #653: a test dirtying a tracked file of the engine checkout trips the canary -> exit 1" 1 "$STATUS"
check_contains "dir #653: the engine trip is named" "$OUT" "the engine checkout changed during the run"
check_contains "dir #653: the engine trip names the touched file" "$OUT" "engine-file.txt"
check_absent "dir #653: the engine trip does not print file content" "$OUT" "leaked"
git -C "$eng" checkout -q -- engine-file.txt

# dir #664, the engine half's twin: an engine file the operator already had dirty (` M` before and after) is
# rewritten by the leak — only the content fingerprint sees it; the trip names the file, never its content
printf 'operator-edit-secret-engine\n' > "$eng/engine-file.txt"
printf '#!/usr/bin/env bash\nprintf "leaked-engine-marker\\n" > "%s/engine-file.txt"\nexit 0\n' "$eng" > "$watched/tests/test_engine_leak.sh"
run env HOME="$enghome" bash "$watched/tests/run.sh"
check_status "dir #664: a leak rewriting an already-dirty engine file trips the canary -> exit 1" 1 "$STATUS"
check_contains "dir #664: the engine trip is named" "$OUT" "the engine checkout changed during the run"
check_contains "dir #664: the engine trip says the content of an already-dirty file changed" "$OUT" \
  "content of a tracked file that already had uncommitted changes differs from before the run"
check_contains "dir #656 half 2: the engine trip names the file under an unchanged status" "$OUT" "  engine-file.txt"
check_absent "dir #664: the engine trip prints neither the leaked content" "$OUT" "leaked-engine-marker"
check_absent "dir #664: ... nor the operator's own uncommitted content" "$OUT" "operator-edit-secret-engine"
git -C "$eng" checkout -q -- engine-file.txt

printf '#!/usr/bin/env bash\nprintf "scratch\\n" > "%s/untracked-peer-file.txt"\nexit 0\n' "$eng" > "$watched/tests/test_engine_leak.sh"
run env HOME="$enghome" bash "$watched/tests/run.sh"
check_status "dir #653: an UNTRACKED file in the engine checkout does not trip -> exit 0" 0 "$STATUS"
rm -f "$eng/untracked-peer-file.txt"

rm -f "$watched/tests/test_engine_leak.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$watched/tests/test_clean.sh"
run env HOME="$enghome" bash "$watched/tests/run.sh"
check_status "dir #653: an untouched engine checkout passes" 0 "$STATUS"
check_absent "S6-1: a readable engine checkout prints no engine-half NOTE" "$OUT" "engine half of the corruption canary"

# an unset HOME (a minimal CI container) must not leak an "unbound variable" error out of the engine
# lookup — run.sh runs under `set -u`
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_clean.sh"
run env -u HOME bash "$d/run.sh"
check_status "dir #653: an unset HOME still passes" 0 "$STATUS"
check_absent "dir #653: an unset HOME raises no unbound-variable error" "$OUT" "unbound variable"
check_absent "S6-1: no engine checkout reachable (unset HOME) -> no engine-half NOTE either" "$OUT" "engine half of the corruption canary"

# engine checkout == the watched checkout: already covered by the dir #318 status half, so the engine
# block stays quiet rather than reporting one leak twice
selfhome="$(mktemp -d "$SANDBOX/selfhome.XXXXXX")"
mkdir -p "$selfhome/.keel"
ln -s "$watched" "$selfhome/.keel/engine"
git -C "$watched" add tests/test_clean.sh tests/run.sh tests/lib.sh
git -C "$watched" commit -q -m fixtures
printf '#!/usr/bin/env bash\nprintf "leaked\\n" >> "$(dirname "$0")/test_clean.sh"\nexit 0\n' > "$watched/tests/test_selfleak.sh"
git -C "$watched" add tests/test_selfleak.sh
git -C "$watched" commit -q -m leaker
run env HOME="$selfhome" bash "$watched/tests/run.sh"
check_status "dir #653: a leak into a checkout that is both watched and the engine still trips -> exit 1" 1 "$STATUS"
check_contains "dir #653: ... via the existing dir #318 status half" "$OUT" "working-tree/index status also changed"
check_absent "dir #653: ... and is not reported a second time by the engine half" "$OUT" "the engine checkout changed during the run"

# --- S6-1 (delta audit 0.13.0): a REACHABLE engine checkout whose `git status` errors must not read as
# "nothing changed". A corrupted index (status rc 128) used to fail the half open and silent: the leaking
# test rewrote an engine file and the run printed ALL TEST FILES PASSED with no word about the half. -------
new_engine_fixture; eng2="$ENG_REPO"; enghome2="$ENG_HOME"
watched="$(new_run_sh_fixture)"   # fresh: the one above ends up holding the selfleak commits
printf 'garbage\n' > "$eng2/.git/index"
git -C "$eng2" status --porcelain -uno >/dev/null 2>&1
check_status "S6-1 fixture: git status of the corrupted engine checkout really fails" 128 "$?"

printf '#!/usr/bin/env bash\nprintf "leaked\\n" > "%s/engine-file.txt"\nexit 0\n' "$eng2" > "$watched/tests/test_engine_leak.sh"
run env HOME="$enghome2" bash "$watched/tests/run.sh"
# Decision (comment in tests/run.sh): a not-run half is reported, not failed — the exit status stays 0.
check_status "S6-1: an unreadable engine checkout does not fail the run by itself -> exit 0" 0 "$STATUS"
check_contains "S6-1: the NOTE names the checkout" "$OUT" "$eng2"
check_status "S6-1: the NOTE says the half did not run, at the top and again beside the verdict (exactly twice)" 2 "$(printf '%s\n' "$OUT" | grep -c 'engine half of the corruption')"

# the converse: readable before the run, unreadable after it -> the half WAS armed, so that is a trip
new_engine_fixture; eng3="$ENG_REPO"; enghome3="$ENG_HOME"
printf '#!/usr/bin/env bash\nprintf "garbage\\n" > "%s/.git/index"\nexit 0\n' "$eng3" > "$watched/tests/test_engine_leak.sh"
run env HOME="$enghome3" bash "$watched/tests/run.sh"
check_status "S6-1: an engine checkout that goes unreadable DURING the run trips the canary -> exit 1" 1 "$STATUS"
check_contains "S6-1: ... and the before -> after diff shows the status failure" "$OUT" "(git status failed)"
check_absent "S6-1: ... without the not-run NOTE (the half did run)" "$OUT" "did NOT run this time"

# --- R1 F1 (the 0.13.0 delta audit's re-check): the S6-1 NOTE above fired only when `git status` failed.
# A $HOME/.keel/engine DIRECTORY that `git rev-parse` cannot resolve — another uid's checkout, git's
# "dubious ownership", reproduced with GIT_TEST_ASSUME_DIFFERENT_OWNER=1 — left guard_engine_root empty
# and skipped the half with no word: a leaked engine file still ended ALL TEST FILES PASSED. A `git` shim
# that fails `rev-parse` only inside the engine checkout stands in for that (the env-var route is defeated
# on the alpine leg, whose system config marks every directory safe). -------------------------------------
new_engine_fixture; eng4="$ENG_REPO"; enghome4="$ENG_HOME"
eng4_phys="$(cd -P "$eng4" && pwd -P)"
shimbin="$(mktemp -d "$SANDBOX/gitshim.XXXXXX")"
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [ "$1" = rev-parse ] && [ "$(pwd -P)" = %q ]; then\n' "$eng4_phys"
  printf '  echo "fatal: detected dubious ownership in repository (shim)" >&2; exit 128\n'
  printf 'fi\n'
  printf 'exec %q "$@"\n' "$(type -P git)"
} > "$shimbin/git"
chmod 755 "$shimbin/git"
(cd "$eng4" && PATH="$shimbin:$PATH" git rev-parse --show-toplevel >/dev/null 2>&1)
check_status "R1 F1 fixture: the shim really fails rev-parse inside the engine checkout" 128 "$?"
check_status "R1 F1 fixture: ... and only there" 0 "$(cd "$watched" && PATH="$shimbin:$PATH" git rev-parse --show-toplevel >/dev/null 2>&1; echo $?)"

printf '#!/usr/bin/env bash\nprintf "leaked\\n" > "%s/engine-file.txt"\nexit 0\n' "$eng4" > "$watched/tests/test_engine_leak.sh"
run env HOME="$enghome4" PATH="$shimbin:$PATH" bash "$watched/tests/run.sh"
# The same decision as S6-1 above: a not-run half is reported, not failed.
check_status "R1 F1: an engine directory git cannot resolve does not fail the run by itself -> exit 0" 0 "$STATUS"
check_contains "R1 F1: the NOTE names the engine directory" "$OUT" "$enghome4/.keel/engine"
check_status "R1 F1: the NOTE says the half did not run, at the top and again beside the verdict (exactly twice)" 2 "$(printf '%s\n' "$OUT" | grep -c 'engine half of the corruption')"

# the same NOTE for a directory that is not a checkout at all (the ceiling keeps git from finding an
# enclosing repo above the sandbox)
plainhome="$(mktemp -d "$SANDBOX/plainhome.XXXXXX")"
mkdir -p "$plainhome/.keel/engine"
rm -f "$watched/tests/test_engine_leak.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$watched/tests/test_clean.sh"
run env HOME="$plainhome" GIT_CEILING_DIRECTORIES="$plainhome/.keel" bash "$watched/tests/run.sh"
check_status "R1 F1: an engine directory that is not a checkout -> exit 0" 0 "$STATUS"
check_status "R1 F1: ... and the not-run NOTE is printed twice" 2 "$(printf '%s\n' "$OUT" | grep -c 'engine half of the corruption')"

# the likeliest real trigger: the engine link dangles (the checkout it named was moved or deleted). `[ -d ]`
# alone is false for it, which would have skipped the half without a word again.
danglehome="$(mktemp -d "$SANDBOX/danglehome.XXXXXX")"
mkdir -p "$danglehome/.keel"
ln -s "$danglehome/moved-away" "$danglehome/.keel/engine"
run env HOME="$danglehome" bash "$watched/tests/run.sh"
check_status "R1 F1: a dangling engine link -> exit 0" 0 "$STATUS"
check_contains "R1 F1: ... the NOTE names the link" "$OUT" "$danglehome/.keel/engine does not resolve"
check_status "R1 F1: ... and the not-run NOTE is printed twice" 2 "$(printf '%s\n' "$OUT" | grep -c 'engine half of the corruption')"

# --- R2-4 (the 0.13.0 delta audit's re-check): run.sh's logdir mint had no empty-result guard. Under `set -uo
# pipefail` (no `-e`) a `mktemp` that fails — or prints nothing — left logdir empty, every log path became
# `/<file>.log`, and as root the run could still end ALL TEST FILES PASSED. It must now FAIL, loudly, before
# any test file starts. A `mktemp` shim that prints nothing and exits 0 stands in (the strictest shape: no rc
# to notice either); HOME and TMPDIR are the sandbox's, so nothing leaves it. -----------------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_a.sh"
emptybin="$(mktemp -d "$SANDBOX/emptymktemp.XXXXXX")"
printf '#!/bin/sh\nexit 0\n' > "$emptybin/mktemp"
chmod 755 "$emptybin/mktemp"
run env PATH="$emptybin:$PATH" KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "R2-4: a mktemp that yields no logdir fails the run -> exit 1" 1 "$STATUS"
check_contains "R2-4: ... loudly, naming what failed" "$OUT" "mktemp -d did not return a usable log dir"
check_absent "R2-4: ... never as a pass" "$OUT" "ALL TEST FILES PASSED"
check_absent "R2-4: ... and before any test file started" "$OUT" "=== test_a.sh ==="
check_nofile "R2-4: no log was written to the filesystem root" "/test_a.sh.log"

# the same with a mktemp that FAILS (rc 1, a message on stderr)
printf '#!/bin/sh\necho "mktemp: failed to create directory (shim)" >&2\nexit 1\n' > "$emptybin/mktemp"
run env PATH="$emptybin:$PATH" KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "R2-4: a mktemp that exits nonzero fails the run -> exit 1" 1 "$STATUS"
check_contains "R2-4: ... with the same loud message" "$OUT" "mktemp -d did not return a usable log dir"

# --- R3-6 (dir #663 fold): the two guard clauses R2-4's shims never reached. A mktemp that hands back "/" (the
# shape a failing mint produced as root): the `[ "$logdir" = / ]` clause refuses it. No mutant for that clause —
# with it removed run.sh would take "/" as its log directory and, as root (the alpine leg), write into the
# filesystem root.
printf '#!/bin/sh\nprintf "/\\n"\n' > "$emptybin/mktemp"
run env PATH="$emptybin:$PATH" KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "R3-6: a mint that returns / fails the run -> exit 1" 1 "$STATUS"
check_contains "R3-6: ... loudly, naming what failed" "$OUT" "mktemp -d did not return a usable log dir"
check_absent "R3-6: ... before any test file started" "$OUT" "=== test_a.sh ==="
check_nofile "R3-6: no log was written to the filesystem root" "/test_a.sh.log"

# a mktemp that hands back a path that is not a directory: the `[ ! -d "$logdir" ]` clause
ghost="$SANDBOX/no-such-logdir-663"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$ghost" > "$emptybin/mktemp"
run env PATH="$emptybin:$PATH" KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_status "R3-6: a mint that returns a non-directory fails the run -> exit 1" 1 "$STATUS"
check_contains "R3-6: ... loudly, naming what failed" "$OUT" "mktemp -d did not return a usable log dir"
check_absent "R3-6: ... before any test file started" "$OUT" "=== test_a.sh ==="
# the mutant: that clause dropped — the same shim then gets past the guard (and dies later, elsewhere)
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_a.sh"
replace_in_line_containing "$d/run.sh" 'if [ -z "$logdir" ] || [ "$logdir" = / ]' ' || [ ! -d "$logdir" ]' ''
check_ne "R3-6 mutant: the edit changed the copy of run.sh" "$(cksum < "$d/run.sh")" "$(cksum < "$runner")"
run env PATH="$emptybin:$PATH" KEEL_TEST_JOBS=1 bash "$d/run.sh"
check_absent "R3-6 mutant: without the ! -d clause the guard's own message is gone (so the clause is what produces it)" \
  "$OUT" "mktemp -d did not return a usable log dir"

# --- R2-2 (the 0.13.0 delta audit's re-check): the dir #318 half — the WATCHED checkout — was skipped
# silently whenever `git rev-parse --git-dir` failed, including for a checkout that IS a repo git merely
# cannot read (another uid's, "dubious ownership"). F1's twin on the primary half: it now prints a NOTE at
# the top and again beside the verdict, and keeps the engine half's decision (reported, not failed). A
# fixture test overwrites a tracked file of the watched checkout: with the half unarmed that leak still
# passes, which is exactly why the skip must be loud. Two shapes: git's own ownership check (skipped on a
# leg whose system config marks every directory safe, as the alpine leg's does), and a `git` shim. ---------
watched="$(new_run_sh_fixture)"
printf 'tracked\n' > "$watched/f.txt"
git -C "$watched" add f.txt
git -C "$watched" commit -q -m f
printf '#!/usr/bin/env bash\nprintf "leaked\\n" > "$(dirname "$0")/../f.txt"\nexit 0\n' > "$watched/tests/test_leak.sh"

# control: the readable checkout trips on the leak, with no not-run NOTE
run bash "$watched/tests/run.sh"
check_status "R2-2 control: a readable watched checkout trips on a leaked tracked-file write -> exit 1" 1 "$STATUS"
check_absent "R2-2 control: ... and prints no not-run NOTE" "$OUT" "did NOT run this time"
git -C "$watched" checkout -q -- f.txt

# shape 1: git's own ownership check refuses the watched checkout
if GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$watched" rev-parse --git-dir >/dev/null 2>&1; then
  pass "R2-2: shape 1 (dubious ownership) skipped — this git/system config does not refuse the checkout (the alpine leg marks every directory safe)"
else
  run env GIT_TEST_ASSUME_DIFFERENT_OWNER=1 bash "$watched/tests/run.sh"
  check_status "R2-2: a watched checkout git refuses to read does not fail the run by itself -> exit 0" 0 "$STATUS"
  check_status "R2-2: ... the NOTE says the dir #318 half did not run, at the top and again beside the verdict (exactly twice)" 2 \
    "$(printf '%s\n' "$OUT" | grep -c 'dir #318 half of the corruption')"
  check_contains "R2-2: ... and names the checkout" "$OUT" "$watched"
  git -C "$watched" checkout -q -- f.txt
fi

# shape 2: a `git` shim that fails `rev-parse --git-dir` for the watched checkout only (run.sh calls it as
# `git -C <dir> rev-parse --git-dir`)
watched_phys="$(cd -P "$watched" && pwd -P)"
shim2="$(mktemp -d "$SANDBOX/gitshim2.XXXXXX")"
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [ "$1" = -C ] && [ "$3" = rev-parse ] && [ "$4" = --git-dir ] && [ "$(cd -P "$2" && pwd -P)" = %q ]; then\n' "$watched_phys"
  printf '  echo "fatal: unreadable (shim)" >&2; exit 128\n'
  printf 'fi\n'
  printf 'exec %q "$@"\n' "$(type -P git)"
} > "$shim2/git"
chmod 755 "$shim2/git"
check_status "R2-2 fixture: the shim really fails rev-parse --git-dir for the watched checkout" 128 \
  "$(PATH="$shim2:$PATH" git -C "$watched" rev-parse --git-dir >/dev/null 2>&1; echo $?)"
check_status "R2-2 fixture: ... and only for it" 0 "$(PATH="$shim2:$PATH" git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; echo $?)"
run env PATH="$shim2:$PATH" bash "$watched/tests/run.sh"
check_status "R2-2: a watched checkout the shim makes unreadable does not fail the run by itself -> exit 0" 0 "$STATUS"
check_status "R2-2: ... the NOTE is printed twice" 2 "$(printf '%s\n' "$OUT" | grep -c 'dir #318 half of the corruption')"
check_contains "R2-2: ... and names the checkout" "$OUT" "$watched"
git -C "$watched" checkout -q -- f.txt

# a tree with NO .git at all is the ordinary, quiet skip (a git-less fixture dir is not an environment fault)
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/test_clean.sh"
run bash "$d/run.sh"
check_status "R2-2: a git-less tree still passes" 0 "$STATUS"
check_absent "R2-2: ... with no dir #318 NOTE" "$OUT" "dir #318 half of the corruption"

summary
