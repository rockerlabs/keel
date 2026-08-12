#!/usr/bin/env bash
# tools/lib/manifest.sh — direct unit coverage for manifest_field/manifest_usable (dir #125 PR3).
# Split out of tools/lib/ledger.sh (found by an operator-run /code-review high pass: sharing them via
# ledger.sh would have silently shadowed uninstall.sh's own same-named local functions the moment its
# existing conditional `. tools/lib/ledger.sh` executed) — this file's only consumer today is
# tools/pre-pr-gate.sh, exercised indirectly by test_pre_pr_gate.sh's B2 cases, but self/doctor.sh's
# tool-wiring ratchet (dir #142) requires every shipped tools/*.sh to be BOTH referenced from and
# test-covered by tests/*.sh directly — this file is that direct coverage, not just a ratchet
# satisfier: manifest_field/manifest_usable are the shared primitive every dir #125 consumer's
# read-contract rests on, so their own edge cases (missing key, missing file, unreadable file, corrupt
# version) deserve a test that isn't buried inside a larger installer fixture.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/manifest.sh"
check_file "tools/lib/manifest.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

m="$SANDBOX/sample-manifest"
printf 'keel_manifest_version=1\nkind=gate\nsettings=/some/path/settings.json\nwired_at=2026-01-01T00:00:00Z\n' > "$m"

check_status "manifest_field: first match, plain key" "1" "$(manifest_field "$m" keel_manifest_version)"
check_status "manifest_field: a later field" "gate" "$(manifest_field "$m" kind)"
check_status "manifest_field: a value with slashes" "/some/path/settings.json" "$(manifest_field "$m" settings)"
check_status "manifest_field: absent key -> empty string, not an error" "" "$(manifest_field "$m" no_such_key)"
check_status "manifest_field: absent file -> empty string, not an error" "" "$(manifest_field "$SANDBOX/does-not-exist" kind)"

check_status "manifest_usable: version=1, file present -> usable" 0 "$(manifest_usable "$m"; echo $?)"
check_status "manifest_usable: missing file -> not usable" 1 "$(manifest_usable "$SANDBOX/does-not-exist"; echo $?)"

m_bad="$SANDBOX/bad-version-manifest"
printf 'keel_manifest_version=99\nkind=gate\n' > "$m_bad"
check_status "manifest_usable: unknown version -> not usable" 1 "$(manifest_usable "$m_bad"; echo $?)"

m_noversion="$SANDBOX/no-version-manifest"
printf 'kind=gate\n' > "$m_noversion"
check_status "manifest_usable: no version line at all -> not usable" 1 "$(manifest_usable "$m_noversion"; echo $?)"

# manifest_field must degrade to "" under an unreadable file, never abort a caller running under set -e
# (the versioning contract: an unreadable manifest is treated as absent, never a crash) — chmod 000 is a
# no-op for a root reader, so this half is skipped on the Alpine/root CI leg per the project's own
# documented trap.
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  chmod 000 "$m"
  out="$(set -e; manifest_field "$m" kind; true)"
  check_status "manifest_field: unreadable file degrades to empty, no crash under set -e" "" "$out"
  chmod 644 "$m"   # restore so cleanup can remove the sandbox
fi

summary