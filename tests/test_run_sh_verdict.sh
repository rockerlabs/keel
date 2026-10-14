#!/usr/bin/env bash
# test_run_sh_verdict.sh — dir #772: tests/run.sh judges a test file by its OWN summary line, not only by its
# exit status. A file that sources tests/lib.sh and exits 0 without printing `<file>: N passed, M failed`
# (it never called `summary`, or its EXIT trap was replaced, or it `exit 0`'d early) used to count as passed
# even with FAIL lines in its log — the 0.16.0 alpine leg shipped three red checks green that way. The fixtures
# run a COPY of run.sh against a throwaway fake tests/ dir, like tests/test_run_sh.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

runner="$REPO_ROOT/tests/run.sh"
# The fixtures' nested run.sh mints its per-file logdir under $TMPDIR; keep a preserved one inside the sandbox.
export TMPDIR="$SANDBOX"

# mkfake — a fake tests/ dir with a copy of run.sh and a stub lib.sh whose `summary` prints the real line shape.
mkfake() {
  local d; d="$(mktemp -d "$SANDBOX/verdict.XXXXXX")"
  cp "$runner" "$d/run.sh"
  chmod +x "$d/run.sh"
  cat > "$d/lib.sh" <<'LIB'
_fail=0; _pass=0
fail() { _fail=$((_fail + 1)); printf '  FAIL  %s\n' "$1"; }
pass() { _pass=$((_pass + 1)); printf '  ok    %s\n' "$1"; }
summary() { printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$_pass" "$_fail"; [ "$_fail" -eq 0 ]; }
LIB
  printf '%s' "$d"
}
SRC='. "$(dirname "$0")/lib.sh" || exit 1'

# --- the ticket's done-criterion: FAIL printed, exit 0, no summary -> the run reports the file failed ------
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\nfail "a red check"\nexit 0\n' "$SRC" > "$d/test_nosummary.sh"
run bash "$d/run.sh"
check_status "FAIL line + exit 0 + no summary -> the run exits 1" 1 "$STATUS"
check_contains "... naming the file and the missing summary line" "$OUT" "test_nosummary.sh exited 0 but its log has no"
check_contains "... citing the ticket" "$OUT" "dir #772"
check_contains "... the failure count reflects it" "$OUT" "1 TEST FILE(S) FAILED"

# --- a green-looking file that forgot summary is the same class (no FAIL line, still no verdict) --------------
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\npass "all fine"\nexit 0\n' "$SRC" > "$d/test_forgot.sh"
run bash "$d/run.sh"
check_status "all-pass output + exit 0 + no summary -> still the run exits 1" 1 "$STATUS"

# --- a file with its own EXIT trap that replaces lib.sh's (the case an EXIT-trap fix would miss) -----------
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\ntrap "echo own-trap" EXIT\nfail "red"\nexit 0\n' "$SRC" > "$d/test_trapped.sh"
run bash "$d/run.sh"
check_status "a replaced EXIT trap does not hide the missing summary" 1 "$STATUS"

# --- the healthy shapes stay green ------------------------------------------------------------------------
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\npass "ok"\nsummary\n' "$SRC" > "$d/test_good.sh"
run bash "$d/run.sh"
check_status "a file that calls summary and passes -> exit 0" 0 "$STATUS"
check_contains "... ALL TEST FILES PASSED" "$OUT" "ALL TEST FILES PASSED"

d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\nfail "red"\nsummary\n' "$SRC" > "$d/test_red.sh"
run bash "$d/run.sh"
check_status "a file that calls summary and has a FAIL -> exit 1 (its own verdict, unchanged)" 1 "$STATUS"
check_absent "... and not blamed for a missing summary" "$OUT" "log has no"

# A summary line printed WITHOUT a trailing newline (last line of the log) still counts.
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\nprintf "test_tail.sh: 1 passed, 0 failed"\nexit 0\n' "$SRC" > "$d/test_tail.sh"
run bash "$d/run.sh"
check_status "a final summary line with no trailing newline is accepted" 0 "$STATUS"

# A look-alike line for ANOTHER file does not satisfy this file's verdict.
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\necho "test_other.sh: 3 passed, 0 failed"\nexit 0\n' "$SRC" > "$d/test_liar.sh"
run bash "$d/run.sh"
check_status "another file's summary line does not count" 1 "$STATUS"

# The verdict line must START its line: the same words embedded mid-line (quoted output) are not a verdict.
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\necho "see test_embed.sh: 1 passed, 0 failed"\nexit 0\n' "$SRC" > "$d/test_embed.sh"
run bash "$d/run.sh"
check_status "a summary-shaped phrase embedded mid-line does not count" 1 "$STATUS"

# A file that never sources lib.sh has no summary to owe (the synthetic fixtures of tests/test_run_sh.sh).
d="$(mkfake)"
printf '#!/usr/bin/env bash\necho no-lib\nexit 0\n' > "$d/test_nolib.sh"
run bash "$d/run.sh"
check_status "a file that does not source lib.sh is not held to a summary line" 0 "$STATUS"

# --- semantics with the watchdog (W5's region): a timed-out file reads as timed out, never "no summary" ----
d="$(mkfake)"
printf '#!/usr/bin/env bash\n%s\nsleep 30\n' "$SRC" > "$d/test_hang.sh"
run env KEEL_TEST_FILE_TIMEOUT=1 bash "$d/run.sh"
check_status "a watchdog-killed lib-sourcing file fails the run" 1 "$STATUS"
check_contains "... reported as timed out" "$OUT" "(timed out after 1s)"
check_absent "... not as a missing summary" "$OUT" "log has no"

# --- the contract the gate relies on: every real test file sources lib.sh at top level and calls summary ----
bad=""
for f in "$REPO_ROOT"/tests/test_*.sh; do
  grep -qE '^(\.|source)[[:space:]]+[^#]*lib\.sh' "$f" || bad="$bad $(basename "$f")(no-lib)"
  grep -qE '^[[:space:]]*summary([[:space:]]|$)' "$f" || bad="$bad $(basename "$f")(no-summary)"
done
check_eq "every tests/test_*.sh sources lib.sh and calls summary" "" "$bad"

summary
