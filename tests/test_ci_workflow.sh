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
fx_out="$(job_timeouts "$fx")"
check_contains "A7 fixture: a job with no timeout-minutes reads MISSING" "$fx_out" "b MISSING"
check_contains "A7 fixture: a job that has one reads its value" "$fx_out" "a 5"
fx="$SANDBOX/ci-step-only.yml"
printf 'name: CI\non: [push]\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - name: s\n        timeout-minutes: 5\n        run: true\n' > "$fx"
check_eq "A7 fixture: a timeout-minutes only on a STEP does not count" "a MISSING" "$(job_timeouts "$fx")"

# --- the real workflow ------------------------------------------------------------------------------------
real="$(job_timeouts "$ci")"
check_absent "A7: every ci.yml job has a job-level timeout-minutes" "$real" "MISSING"
for want in "tests 20" "macos-shards 25" "macos 15" "alpine 20" "shellcheck 15" "secret-scan 15" "self-check 15"; do
  if grep -qxF -- "$want" <<< "$real"; then
    pass "A7: job ${want% *} times out at B9's ${want#* } minutes"
  else
    fail "A7: job ${want% *} times out at B9's ${want#* } minutes" "job_timeouts read: $(tr '\n' ';' <<< "$real")"
  fi
done
check_eq "A7: exactly the seven jobs B9 names (a new job needs its own value here)" "7" "$(grep -c . <<< "$real")"

# --- dir #744 B16/B25/B26 (A21): two macOS shards behind the stable required names, and the queue trigger ----
# job_block FILE JOB — the lines of one job (its key line excluded), up to the next job key.
job_block() {
  awk -v j="$2" '
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { exit }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { k = $1; sub(/:$/, "", k); on = (k == j); next }
    on { print }
  ' "$1"
}
# job_keys FILE — every job key under jobs:, one per line.
job_keys() {
  awk '/^jobs:[[:space:]]*$/ { in_jobs = 1; next } in_jobs && /^[^[:space:]#]/ { exit }
       in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { k = $1; sub(/:$/, "", k); print k }' "$1"
}
# job_field BLOCK KEY — a job-level (4-space) key's value from a job_block.
job_field() { awk -v k="$2" '$0 ~ "^    " k ":" { v = $0; sub("^    " k ":[[:space:]]*", "", v); print v; exit }' <<< "$1"; }
# job_names FILE — every check name the workflow produces: each job's `name:` with `${{ matrix.X }}` expanded
# over its one-line matrix list `X: [a, b]` (this workflow's only matrix shape); a job without `name:` reports
# its key, as GitHub does.
job_names() {
  local j blk name var vals v
  while IFS= read -r j; do
    blk="$(job_block "$1" "$j")"
    name="$(job_field "$blk" name)"
    [ -n "$name" ] || name="$j"
    case "$name" in
      *'${{ matrix.'*' }}'*)
        var="${name#*\$\{\{ matrix.}"; var="${var%% \}\}*}"
        vals="$(sed -n "s/^        $var: \\[\\(.*\\)\\]\$/\\1/p" <<< "$blk" | tr ',' '\n' | sed 's/^ *//; s/ *\$//')"
        while IFS= read -r v; do
          [ -n "$v" ] && printf '%s\n' "${name//\$\{\{ matrix.$var \}\}/$v}"
        done <<< "$vals"
        ;;
      *) printf '%s\n' "$name" ;;
    esac
  done < <(job_keys "$1")
}

names="$(job_names "$ci")"
for want in "tests (ubuntu-24.04)" "tests (macos-14)" "tests (alpine-busybox)" "shellcheck"; do
  check_eq "A21: the required check name '$want' is produced by exactly one job or matrix entry" "1" \
    "$(grep -cxF -- "$want" <<< "$names")"
done
for want in "tests (macos-14, shard 1/2)" "tests (macos-14, shard 2/2)"; do
  check_eq "A21: the shard check '$want' exists once" "1" "$(grep -cxF -- "$want" <<< "$names")"
done

agg="$(job_block "$ci" macos)"
check_eq "A21: the aggregator job is named exactly 'tests (macos-14)'" "tests (macos-14)" "$(job_field "$agg" name)"
check_eq "A21: the aggregator needs the shard job" "macos-shards" "$(job_field "$agg" needs)"
check_eq "A21: the aggregator runs even when a shard failed or was cancelled" "always()" "$(job_field "$agg" if)"
check_eq "A21: the aggregator runs on ubuntu, never taking a macOS slot" "ubuntu-24.04" "$(job_field "$agg" runs-on)"
shards="$(job_block "$ci" macos-shards)"
check_contains "A21: the shard matrix does not cancel its sibling on a failure" "$shards" "      fail-fast: false"
check_eq "A21: the shard job runs on macos-14" "macos-14" "$(job_field "$shards" runs-on)"

# No job but the shard job takes a macOS runner (the aggregator and the ubuntu leg must not).
mac_jobs=""
while IFS= read -r j; do
  case "$(job_field "$(job_block "$ci" "$j")" runs-on)" in *macos*) mac_jobs="$mac_jobs $j" ;; esac
done < <(job_keys "$ci")
check_eq "A21: only the shard job runs on macOS" " macos-shards" "$mac_jobs"

# KEEL_TEST_SHARD is set by the shard job's test step and by no other job.
shard_env_jobs=""
while IFS= read -r j; do
  grep -q 'KEEL_TEST_SHARD:' <<< "$(job_block "$ci" "$j")" && shard_env_jobs="$shard_env_jobs $j"
done < <(job_keys "$ci")
check_eq "A21: only the shard job sets KEEL_TEST_SHARD" " macos-shards" "$shard_env_jobs"
check_contains "A21: the shard step passes its own shard of 2" "$shards" 'KEEL_TEST_SHARD: ${{ matrix.shard }}/2'

# The aggregator's verdict, executed: its one step's `run:` block with the shard result substituted.
agg_run="$(awk '/^        run: \|[[:space:]]*$/ { on = 1; next } on && /^          / { sub(/^          /, ""); print; next } on { exit }' <<< "$agg")"
check_ne "A21: the aggregator's run: block was found" "" "$agg_run"
for pair in success:0 failure:1 cancelled:1 skipped:1; do
  res="${pair%%:*}"; want="${pair#*:}"
  run env SHARDS_RESULT="$res" bash -c "$agg_run"
  check_status "A21: the aggregator exits $want when the shards' result is $res" "$want" "$STATUS"
done
check_contains "A21: the aggregator reads needs.<shard job>.result" "$agg" 'SHARDS_RESULT: ${{ needs.macos-shards.result }}'

# The queue trigger (B25), with the existing triggers kept (B30).
on_block="$(awk '/^on:[[:space:]]*$/ { on = 1; next } on && /^[^[:space:]]/ { exit } on { print }' "$ci")"
check_contains "A21: on: has merge_group" "$on_block" "  merge_group:"
check_contains "A21: on: still has pull_request" "$on_block" "  pull_request:"
check_contains "A21: on: still pushes on main" "$on_block" "    branches: [main]"

# B26: on merge_group the secret scan gets the group's own sha and the payload's base sha.
scan="$(job_block "$ci" secret-scan)"
check_contains "B26: secret-scan's base sha falls back to merge_group.base_sha" "$scan" "github.event.merge_group.base_sha"
check_contains "B26: secret-scan's head sha is github.sha on merge_group" "$scan" "github.event_name == 'merge_group' && github.sha"

summary
