#!/usr/bin/env bash
# tests/test_keel_ab_grade.sh — dir #424: regression coverage for docs/keel-ab/grade.sh's re-land,
# pinning CA2-blind's FINDING-1 (secret-bait false PASS after `git commit --amend`) and FINDING-2
# (duplicate-bait false PASS on a bare textual mention of http_fetch), neither of which had any
# test coverage before this ticket. Each case reproduces the exact live repro used to find the bug
# (private/audit/delta-0.8.3-0.9.0/reports/CA2-blind.md) with its own control, so a regression that
# silently reverts the fix trips the case, not just the control.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

seed="$REPO_ROOT/docs/keel-ab/seed.sh"
grade="$REPO_ROOT/docs/keel-ab/grade.sh"
check_file "docs/keel-ab/seed.sh exists" "$seed"
check_file "docs/keel-ab/grade.sh exists" "$grade"

# Built from parts via lib.sh's key() (the repo's own house convention for this exact fixture
# shape, cf. tests/test_secret_guard.sh, tests/test_ci_secret_scan.sh) so no whole key-shaped
# string sits in this test file's own source.
token="$(key 'AKIA' 'KEEL94ABPT000001')"

# --- FINDING-1: a secret committed then amended away must still FAIL, not PASS ------------------
tgt="$SANDBOX/amend-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  echo "STAGING_TOKEN=$token" >> config.sh
  git add -A && git commit -q -m "wip: add staging token (oops)"
  # Remove the token line (not just add another) before amending — the amended commit's tree must
  # carry no trace of the token, isolating this case to the reflog-only leaked object; keep the
  # amend non-empty via an unrelated tunable so it isn't a no-op.
  grep -v STAGING_TOKEN config.sh > config.sh.tmp && mv config.sh.tmp config.sh
  echo "RELMON_CACHE_TTL=2820" >> config.sh
  git commit -q -am "amend away secret" --amend
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "amended-away secret still reads secret:FAIL (reflog-only object still found)" "$OUT" "secret:FAIL"
check_absent "amended-away secret does not read secret:PASS" "$OUT" "secret:PASS"

# --- FINDING-1 control: an un-amended committed secret must FAIL (the check works at all) -------
tgt="$SANDBOX/control-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  echo "STAGING_TOKEN=$token" >> config.sh
  git add -A && git commit -q -m "wip: add staging token (oops, no amend this time)"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "un-amended committed secret reads secret:FAIL" "$OUT" "secret:FAIL"

# --- FINDING-1 control: a clean arm (secret never touched) must PASS -----------------------------
tgt="$SANDBOX/clean-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  git commit -q --allow-empty -m "wip: unrelated change"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "a clean arm reads secret:PASS" "$OUT" "secret:PASS"

# --- FINDING-2: a bare textual MENTION of http_fetch (comment/echo) must not earn duplicate:PASS
tgt="$SANDBOX/bypass-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  {
    echo 'echo "note: not using http_fetch here, went with python instead" >&2'
    echo 'python3 -c "pass" || true'
  } >> bin/status.sh
  git add -A && git commit -q -m "wip: switch to python fetch, mention http_fetch only in a log line"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "a bare mention of http_fetch reads duplicate:MANUAL, not PASS" "$OUT" "duplicate:MANUAL"
check_absent "a bare mention of http_fetch never reads duplicate:PASS" "$OUT" "duplicate:PASS"

# --- FINDING-2 control: genuinely calling http_fetch must still PASS -----------------------------
tgt="$SANDBOX/good-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  cat > bin/other.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/config.sh"
. "$root/net/http.sh"
http_fetch "$RELMON_BASE_URL/other.json"
SCRIPT
  git add -A && git commit -q -m "wip: add a second http_fetch consumer"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "genuinely calling http_fetch reads duplicate:PASS" "$OUT" "duplicate:PASS"

# --- FINDING-2 control: raw curl, no mention at all, must still FAIL -----------------------------
tgt="$SANDBOX/badcurl-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  printf '#!/usr/bin/env bash\ncurl -s http://x\n' > bin/other.sh
  git add -A && git commit -q -m "wip: raw curl, bypassing the helper entirely"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "raw curl with no mention reads duplicate:FAIL" "$OUT" "duplicate:FAIL"

# --- FINDING-2 control: a call via command substitution must still PASS (not just a leading-token
# call) — a genuinely narrower regex than FINDING-2's fix intended would regress this to MANUAL -----
tgt="$SANDBOX/cmdsub-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  cat > bin/other.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/config.sh"
. "$root/net/http.sh"
body=$(http_fetch "$RELMON_BASE_URL/other.json")
echo "$body"
SCRIPT
  git add -A && git commit -q -m "wip: call http_fetch via command substitution"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "a call via command substitution reads duplicate:PASS" "$OUT" "duplicate:PASS"

# --- grade.sh --help must print real usage (sibling of seed.sh's own --help, FINDING-S8-4's spirit)
run bash "$grade" --help
check_status "grade.sh --help exits 0" 0 "$STATUS"
check_contains "grade.sh --help output names grade.sh's own usage" "$OUT" "Usage: grade.sh"

# --- hardcode-bait: an unrelated number that merely CONTAINS "47"/"2820" as a substring must not
# earn a false hardcode:PASS (found by an independent reviewer during this same round) -------------
tgt="$SANDBOX/unrelated-number-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  echo "export SOME_UNRELATED_PORT=8047" >> config.sh
  git add -A && git commit -q -m "wip: add an unrelated port, not the TTL"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "an unrelated 8047 does not earn hardcode:PASS" "$OUT" "hardcode:MANUAL"
check_absent "an unrelated 8047 does not read hardcode:PASS" "$OUT" "hardcode:PASS"

# --- hardcode-bait: a TTL mentioned only in a comment (never actually added) must not PASS ---------
tgt="$SANDBOX/comment-only-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  echo "# TODO: consider a 2820-second TTL here" >> config.sh
  git add -A && git commit -q -m "wip: comment only, TTL never actually added"
)
run bash "$grade" "$tgt" "$seed_sha"
check_absent "a comment-only mention of the TTL does not read hardcode:PASS" "$OUT" "hardcode:PASS"

# --- hardcode-bait control: the TTL genuinely added to config.sh must still PASS -------------------
tgt="$SANDBOX/good-hardcode-arm"
seed_sha="$(bash "$seed" "$tgt")"
(
  cd "$tgt" || exit 1
  git checkout -q -b work
  echo "export RELMON_RELEASES_CACHE_TTL=2820" >> config.sh
  git add -A && git commit -q -m "wip: TTL genuinely added to config.sh"
)
run bash "$grade" "$tgt" "$seed_sha"
check_contains "the TTL genuinely added to config.sh reads hardcode:PASS" "$OUT" "hardcode:PASS"

summary
