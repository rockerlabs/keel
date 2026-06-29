#!/usr/bin/env bash
# register-project — appends project rows to the INSTANCE.md Projects table; idempotent; the rows it
# writes are what `doctor --registry` reads back.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

reg="$REPO_ROOT/tools/register-project.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# a fresh INSTANCE.md from the template, and two project dirs (one GAP-free so doctor can sweep it)
inst="$SANDBOX/INSTANCE.md"; cp "$REPO_ROOT/templates/INSTANCE.md" "$inst"
p1="$(mktemp -d "$SANDBOX/projA.XXXXXX")"; git -C "$p1" init -q
printf '# ctx\n' > "$p1/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$p1/.gitignore"
p2="$(mktemp -d "$SANDBOX/projB.XXXXXX")"

# --help / no-arg / missing-instance contracts
run env KEEL_INSTANCE="$inst" "$reg" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run env KEEL_INSTANCE="$inst" "$reg"
check_status "no args → exit 2" 2 "$STATUS"
run env KEEL_INSTANCE="$SANDBOX/nope.md" "$reg" "$p1"
check_status "missing INSTANCE.md → exit 2" 2 "$STATUS"

# register two projects
run env KEEL_INSTANCE="$inst" "$reg" "$p1" "$p2"
check_status "register two → exit 0" 0 "$STATUS"
check_contains "reports what was added" "$OUT" "registered"
check_contains "row for p1 (abs path) written" "$(cat "$inst")" "| $p1 |"
check_contains "row for p2 (abs path) written" "$(cat "$inst")" "| $p2 |"
check_contains "row keyed by basename" "$(cat "$inst")" "$(basename "$p1")"

# idempotent: re-registering p1 adds no duplicate row
before="$(grep -cF "| $p1 |" "$inst")"
run env KEEL_INSTANCE="$inst" "$reg" "$p1"
check_contains "re-register reports already-registered" "$OUT" "already registered"
after="$(grep -cF "| $p1 |" "$inst")"
check_status "no duplicate row on re-register" "$before" "$after"

# a non-directory arg is skipped, not fatal
run env KEEL_INSTANCE="$inst" "$reg" "$SANDBOX/does-not-exist"
check_status "non-dir arg → still exit 0 (skipped)" 0 "$STATUS"

# the rows register wrote are consumed by doctor --registry (p1 is GAP-free → clean sweep over it)
run env KEEL_INSTANCE="$inst" "$doctor" --registry "$inst"
check_contains "doctor --registry sees the registered project" "$OUT" "$(basename "$p1")"

summary
