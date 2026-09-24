#!/usr/bin/env bash
# test_run_sh.sh — tests/run.sh's own aggregation logic (dir #130), exercised against a throwaway
# fake tests/ directory (a copy of run.sh plus synthetic test_*.sh fixtures) rather than the real
# suite, so a fixture's deliberate failure never pollutes this suite's own pass/fail count.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

runner="$REPO_ROOT/tests/run.sh"
check_file "run.sh exists" "$runner"

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

# --- fixtures actually overlap in wall clock under concurrency, not just "all eventually ran" ------
# (found by the /polish high-depth review agent: the assertions above would still pass a regression
# to a sequential-only implementation, since none of them measure wall clock.) Four 1s-sleep fixtures
# serially cost >=4s; under KEEL_TEST_JOBS=4 they should overlap and finish well under that.
d="$(mkfakedir)"
for n in 1 2 3 4; do
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/test_$n.sh"
done
t0=$(date +%s)
run env KEEL_TEST_JOBS=4 bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "timing: 4x 1s fixtures, jobs=4 -> exit 0" 0 "$STATUS"
if [ "$elapsed" -le 3 ]; then
  pass "timing: 4x 1s fixtures overlap under jobs=4 (${elapsed}s, serial would be >=4s)"
else
  fail "timing: 4x 1s fixtures overlap under jobs=4" "took ${elapsed}s, expected <=3s if truly concurrent"
fi

# --- SIGTERM mid-run: exits 130, kills the still-running children, and — unlike a naive kill-and-
# exit — still surfaces each interrupted fixture's own buffered output rather than silently
# dropping it (found by an operator-run /code-review high pass, dir #130: the old sequential
# runner streamed output live, so an interrupt never lost anything; the new concurrent one buffers
# per-file until reap time, which needed its own interrupt-time flush). ------------------------
d="$(mkfakedir)"
printf '#!/usr/bin/env bash\necho hello-from-int-a\nsleep 5\nexit 0\n' > "$d/test_a.sh"
printf '#!/usr/bin/env bash\necho hello-from-int-b\nsleep 5\nexit 0\n' > "$d/test_b.sh"
int_out="$(mktemp)"
t0=$(date +%s)
env KEEL_TEST_JOBS=2 bash "$d/run.sh" >"$int_out" 2>&1 &
rpid=$!
# Poll for both fixtures' own echo instead of a fixed sleep, so the SIGTERM lands reliably once
# both children are actually up rather than racing a guessed delay.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if grep -q "hello-from-int-a" "$int_out" 2>/dev/null && grep -q "hello-from-int-b" "$int_out" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
kill -TERM "$rpid"
wait "$rpid"
int_status=$?
t1=$(date +%s)
int_out_text="$(cat "$int_out")"
check_status "SIGTERM mid-run -> exit 130" 130 "$int_status"
check_contains "SIGTERM mid-run -> test_a's output survives the kill" "$int_out_text" "hello-from-int-a"
check_contains "SIGTERM mid-run -> test_b's output survives the kill" "$int_out_text" "hello-from-int-b"
check_contains "SIGTERM mid-run -> names the interrupted files" "$int_out_text" "(interrupted)"
if [ "$((t1 - t0))" -le 3 ]; then
  pass "SIGTERM mid-run -> the 5s sleeps were actually killed, not waited out ($((t1 - t0))s)"
else
  fail "SIGTERM mid-run -> the 5s sleeps were actually killed, not waited out" "took $((t1 - t0))s, expected <=3s"
fi
rm -f "$int_out"

# --- $CI caps the default at 2, overriding a host reporting more cores (dir #154) -----------------
# tests/run.sh's own default now checks $CI before falling back to nproc/sysctl — the new branch had
# no coverage at all (found by an operator-run /code-review medium pass): every case above pins
# KEEL_TEST_JOBS explicitly, so a regression in the $CI branch itself would pass silently. A fake
# `nproc` on PATH decouples this from the real host's core count on purpose — this suite exists to
# fight resource-contention flakiness, so a timing assertion tied to the ACTUAL host's CPU count
# would risk reintroducing exactly that class of flake.
d="$(mkfakedir)"
for n in 1 2 3 4 5 6; do
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/test_$n.sh"
done
fakebin="$(mktemp -d "$SANDBOX/fakebin.XXXXXX")"
printf '#!/usr/bin/env bash\necho 9\n' > "$fakebin/nproc"
chmod +x "$fakebin/nproc"

# CI unset -> falls through to the (mocked, high) nproc default, all 6 overlap -> well under serial 6s
t0=$(date +%s)
run env -u KEEL_TEST_JOBS -u CI PATH="$fakebin:$PATH" bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "CI unset: nproc-default fixtures -> exit 0" 0 "$STATUS"
# <=3s, matching the file's own established margin for this shape of assertion (the "timing: 4x 1s
# fixtures overlap under jobs=4" case above uses the same +2s slack over ~1s of unconstrained work) —
# a tighter bound here would risk reintroducing the exact contention-flake class this suite exists to
# fight (found on a delta review pass).
if [ "$elapsed" -le 3 ]; then
  pass "CI unset: 6x 1s fixtures run at the mocked nproc=9 default, not capped (${elapsed}s)"
else
  fail "CI unset: 6x 1s fixtures run at the nproc default" "took ${elapsed}s, expected <=3s under the mocked nproc=9"
fi

# CI=true -> caps at 2 regardless of the (mocked, high) nproc value -> 3 batches of 2, ~3s
t0=$(date +%s)
run env -u KEEL_TEST_JOBS PATH="$fakebin:$PATH" CI=true bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "CI=true: capped fixtures -> exit 0" 0 "$STATUS"
if [ "$elapsed" -ge 2 ] && [ "$elapsed" -le 5 ]; then
  pass "CI=true: 6x 1s fixtures cap at 2 despite a high mocked nproc (${elapsed}s, ~3 batches)"
else
  fail "CI=true: 6x 1s fixtures cap at 2" "took ${elapsed}s, expected roughly 3 batches (2-5s)"
fi

# --- KEEL_TEST_JOBS still overrides $CI's default (dir #154) ---------------------------------------
# A bare exit-0 + "ALL TEST FILES PASSED" check can't tell jobs_cap=1 (override honored) apart from
# jobs_cap=2 or 9 (override silently lost to the CI default or the mocked nproc) — all three produce
# identical output for these trivial fixtures. Only a timing check that proves fully SEQUENTIAL
# execution (6 batches of 1, ~6s) actually distinguishes them (found on a delta review pass).
t0=$(date +%s)
run env PATH="$fakebin:$PATH" KEEL_TEST_JOBS=1 CI=true bash "$d/run.sh"
t1=$(date +%s)
elapsed=$((t1 - t0))
check_status "KEEL_TEST_JOBS=1 under CI=true still runs -> exit 0" 0 "$STATUS"
check_contains "KEEL_TEST_JOBS=1 under CI=true still passes all fixtures" "$OUT" "ALL TEST FILES PASSED"
if [ "$elapsed" -ge 5 ]; then
  pass "KEEL_TEST_JOBS=1 under CI=true actually ran sequentially, not capped at 2 (${elapsed}s, ~6 batches)"
else
  fail "KEEL_TEST_JOBS=1 under CI=true ran sequentially" "took ${elapsed}s, expected >=5s for 6 fully-serial 1s fixtures — the override may have lost to the CI default"
fi

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
# creates (bare `mktemp -d`, unlike `mktemp -t`, does not honor $TMPDIR on macOS/BSD, so redirecting
# via TMPDIR alone is not portable enough to trust here).
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

# --- dir #318 T8: a fixture test file that leaks a bare `git branch` against its own watched repo
# trips the canary end-to-end (unlike the guard itself, which this file cannot exercise against the
# REAL checkout without corrupting the very thing it protects — this fixture repo is disposable).
# The fixture's own lib.sh is a stub (the guard is not armed there — this drives run.sh's OWN
# detection half, not tests/lib.sh's prevention half), but it DOES carry a copy of
# tools/lib/ref-guard.sh, so guard_ref_scope_available stays 1 and the unowned-refs block actually
# runs (E20: without it, that block is skipped entirely).
leakroot="$(new_repo)"
git -C "$leakroot" commit -q --allow-empty -m init
mkdir -p "$leakroot/tests" "$leakroot/tools/lib"
cp "$runner" "$leakroot/tests/run.sh"
: > "$leakroot/tests/lib.sh"
cp "$REPO_ROOT/tools/lib/ref-guard.sh" "$leakroot/tools/lib/ref-guard.sh"
printf '#!/usr/bin/env bash\ngit -C "$(dirname "$0")/.." branch leak\nexit 0\n' > "$leakroot/tests/test_leak.sh"
run bash "$leakroot/tests/run.sh"
check_status "a leaked branch trips the canary -> exit 1" 1 "$STATUS"
check_contains "the trip block prints TRIPPED" "$OUT" "TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #318)"
check_contains "the trip names the unowned-branch change and points at tests/lib.sh's guard (dir #318, G4)" \
  "$OUT" "an ordinary test file cannot have done this on its own — tests/lib.sh guard (dir #318) refuses every test ref write it makes — so look outside the suite first"
check_contains "the trip hedges for the named N8 residual (dir #644 closes it), not a blanket claim" \
  "$OUT" "dir #318 residual N8, closed by dir #644"
check_contains "the changed two-way attribution line (dir #318, G4)" \
  "$OUT" "either a test escaped its sandbox, or something outside the suite changed this checkout during the run:"
check_contains "the kept 'do not push' clause survives word for word (dir #318, G4)" \
  "$OUT" "do not push this branch until the real history is reconciled by hand."
git -C "$leakroot" branch -D leak >/dev/null 2>&1 || true

summary
