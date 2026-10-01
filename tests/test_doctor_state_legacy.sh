#!/usr/bin/env bash
# doctor.sh --install W-STATE-LEGACY (dir #637 B8 / A10): a durable store still living in the harness
# home — the old address, before tools/state-root-migrate.sh moved it — is a WARN, not silence, because
# losing that home would now take the store with it. Links left by the migration are NOT findings.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# a10_home NAME — a fresh HOME with a healthy default install; sets $h and FRESH_HOME_ENV.
a10_home() {
  h="$SANDBOX/a10-$1"; mkdir -p "$h"; fresh_home_env "$h"
  run env "${FRESH_HOME_ENV[@]}" "$install" --no-hooks
  [ "$STATUS" = 0 ] || fail "a10 fixture install ($1)" "exit $STATUS"
}
# a10_doctor [ARG…] — doctor --install under the case's HOME.
a10_doctor() { run env "${FRESH_HOME_ENV[@]}" "$doctor" --install "$@"; }

# --- a real legacy entry under the audited home → one WARN, exit 0 (a WARN never fails) -----------------
a10_home real
mkdir -p "$h/.claude/.keel/impact/-p-real"; printf 'row\n' > "$h/.claude/.keel/impact/-p-real/ledger.md"
a10_doctor "$h/.claude"
check_status "a real legacy entry → exit 0 (WARN only)" 0 "$STATUS"
check_contains "the finding is named" "$OUT" "[W-STATE-LEGACY]"
check_contains "it names the old store root" "$OUT" "$h/.claude/.keel/impact"
check_contains "it names the fix" "$OUT" "state-root-migrate.sh --from"
legacy_count="$(printf '%s\n' "$OUT" | grep -c 'W-STATE-LEGACY' || true)"
check_eq "ihome and the default root coincide → one WARN, not two" "1" "$legacy_count"

# --- links only (what a finished migration leaves) → no finding ------------------------------------------
a10_home links
mkdir -p "$h/.keel/impact/-p-moved" "$h/.claude/.keel/impact"
ln -s "$h/.keel/impact/-p-moved" "$h/.claude/.keel/impact/-p-moved"
a10_doctor "$h/.claude"
check_absent "links only → no W-STATE-LEGACY" "$OUT" "W-STATE-LEGACY"

# --- no legacy root at all → no finding -------------------------------------------------------------------
a10_home none
a10_doctor "$h/.claude"
check_absent "no legacy root → no W-STATE-LEGACY" "$OUT" "W-STATE-LEGACY"

# --- both stores, both reported ------------------------------------------------------------------------------
a10_home both
mkdir -p "$h/.claude/.keel/impact/-p-a" "$h/.claude/.keel/read-trace/-p-b"
a10_doctor "$h/.claude"
check_contains "an impact store root is reported" "$OUT" "$h/.claude/.keel/impact"
check_contains "a read-trace store root is reported" "$OUT" "$h/.claude/.keel/read-trace"

# --- --codex: the audited home is ~/.codex, but the stores of a codex adopter sit under the default
# harness home — the default root is audited too ------------------------------------------------------------
h="$SANDBOX/a10-codex"; mkdir -p "$h"; fresh_home_env "$h"
run env "${FRESH_HOME_ENV[@]}" "$install" --codex --home "$h/.codex" --no-hooks
mkdir -p "$h/.claude/.keel/impact/-p-cx"
run env "${FRESH_HOME_ENV[@]}" "$doctor" --install --codex "$h/.codex"
check_status "--codex: a legacy entry under the default harness home → exit 0" 0 "$STATUS"
check_contains "--codex: flagged via the default root" "$OUT" "$h/.claude/.keel/impact"

# --- accepted by bare ID -----------------------------------------------------------------------------------------------
a10_home accept
mkdir -p "$h/.claude/.keel/impact/-p-acc"
printf 'W-STATE-LEGACY\n' > "$h/.claude/.keel/doctor-accept"
a10_doctor "$h/.claude"
check_absent "doctor-accept mutes it" "$OUT" "W-STATE-LEGACY"

summary
