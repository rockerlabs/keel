#!/usr/bin/env bash
# test_ci_workflow.sh — dir #744 B9 (A7): every job in .github/workflows/ci.yml sets a job-level
# `timeout-minutes`, so a hung job is killed at a bound sized to its own leg instead of holding the
# required check for GitHub's 360-minute default. The value per job is pinned to B9's rule
# (max(2 x the leg's p90, p90 + 10 min), rounded up to 5 min): changing one is a deliberate edit here too.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

ci="$REPO_ROOT/.github/workflows/ci.yml"
check_file "ci.yml exists" "$ci"

# job_timeouts FILE — one `<job> <value>` line per job under `jobs:` (a 2-space-indented key), the value of
# its JOB-LEVEL `timeout-minutes` (indented 4 spaces, as the job's `runs-on:`), or MISSING. A
# `timeout-minutes` under `steps:` (deeper indent) does not count.
job_timeouts() {
  awk '
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
    !in_jobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if (job != "") print job, (val == "" ? "MISSING" : val)
      job = $1; sub(/:$/, "", job); val = ""; next
    }
    /^    timeout-minutes:/ { v = $0; sub(/^    timeout-minutes:[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v); val = v }
    END { if (job != "") print job, (val == "" ? "MISSING" : val) }
  ' "$1"
}

# --- the parser itself: two wrong fixtures must read as MISSING -------------------------------------------
fx="$SANDBOX/ci-missing.yml"
printf 'name: CI\non: [push]\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    timeout-minutes: 5\n    steps:\n      - run: true\n  b:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: true\n' > "$fx"
check_contains "A7 fixture: a job with no timeout-minutes reads MISSING" "$(job_timeouts "$fx")" "b MISSING"
check_contains "A7 fixture: a job that has one reads its value" "$(job_timeouts "$fx")" "a 5"
fx="$SANDBOX/ci-step-only.yml"
printf 'name: CI\non: [push]\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - name: s\n        timeout-minutes: 5\n        run: true\n' > "$fx"
check_eq "A7 fixture: a timeout-minutes only on a STEP does not count" "a MISSING" "$(job_timeouts "$fx")"

# --- the real workflow ------------------------------------------------------------------------------------
real="$(job_timeouts "$ci")"
check_absent "A7: every ci.yml job has a job-level timeout-minutes" "$real" "MISSING"
for want in "tests 25" "alpine 20" "shellcheck 15" "secret-scan 15" "self-check 15"; do
  if grep -qxF -- "$want" <<< "$real"; then
    pass "A7: job ${want% *} times out at B9's ${want#* } minutes"
  else
    fail "A7: job ${want% *} times out at B9's ${want#* } minutes" "job_timeouts read: $(tr '\n' ';' <<< "$real")"
  fi
done
check_eq "A7: exactly the five jobs B9 names (a new job needs its own value here)" "5" "$(grep -c . <<< "$real")"

summary
