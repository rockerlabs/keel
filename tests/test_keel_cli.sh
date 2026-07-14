#!/usr/bin/env bash
# keel — the thin dispatcher. These tests pin the CONTRACT, not the tools it forwards to: every verb
# reaches its own script with args intact, the child's exit code passes straight through, an unknown
# verb is usage+exit-2, and the checkout self-resolves through a PATH symlink from any cwd.
#
# The dispatch table is tested against a FAKE checkout of stub scripts (each echoes a marker + exits a
# chosen code), so a green run means "keel routed correctly", independent of what the real install.sh /
# tools/*.sh happen to do today.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# A fake checkout: a copy of the real `keel` beside stub scripts it dispatches to. Copied (not
# symlinked) so keel's self-resolution lands on THIS dir as the checkout.
fake="$SANDBOX/checkout"
mkdir -p "$fake/tools"
cp "$REPO_ROOT/keel" "$fake/keel"
chmod +x "$fake/keel"

# stub NAME EXIT — write $fake/NAME that echoes a marker (with its forwarded args) and exits EXIT.
stub() {
  local path="$fake/$1" code="$2"
  mkdir -p "$(dirname "$path")"
  printf '#!/bin/sh\necho "STUB %s args=[$*]"\nexit %s\n' "$1" "$code" > "$path"
  chmod +x "$path"
}
stub install.sh          0
stub uninstall.sh        0
stub tools/doctor.sh     0
stub tools/public-audit.sh 0
stub tools/init-project.sh 0
stub tools/keel-check.sh 7   # a non-zero, non-2 code proves genuine pass-through (not keel's own exit)

keel="$fake/keel"

# --- every verb reaches its own script, args forwarded ------------------------------------------
run "$keel" install --link
check_contains "install -> install.sh"        "$OUT" "STUB install.sh args=[--link]"
run "$keel" doctor --install
check_contains "doctor -> tools/doctor.sh"     "$OUT" "STUB tools/doctor.sh args=[--install]"
run "$keel" audit
check_contains "audit -> tools/public-audit.sh" "$OUT" "STUB tools/public-audit.sh args=[]"
run "$keel" init /some/dir
check_contains "init -> tools/init-project.sh" "$OUT" "STUB tools/init-project.sh args=[/some/dir]"
run "$keel" check make test
check_contains "check -> tools/keel-check.sh"  "$OUT" "STUB tools/keel-check.sh args=[make test]"
run "$keel" uninstall --dry-run
check_contains "uninstall -> uninstall.sh"     "$OUT" "STUB uninstall.sh args=[--dry-run]"

# --- child exit code passes straight through ----------------------------------------------------
run "$keel" check anything          # stub exits 7
check_status "check forwards the child's exit code" 7 "$STATUS"
run "$keel" install
check_status "install forwards a 0 exit code" 0 "$STATUS"

# --- usage / unknown verb -----------------------------------------------------------------------
run "$keel"
check_status "no args -> exit 2" 2 "$STATUS"
check_contains "no args prints usage" "$OUT" "Usage: keel"
run "$keel" bogus-verb
check_status "unknown verb -> exit 2" 2 "$STATUS"
check_contains "unknown verb names itself" "$OUT" "unknown command 'bogus-verb'"
run "$keel" help
check_status "help -> exit 0" 0 "$STATUS"
check_contains "help lists the verbs" "$OUT" "uninstall"

# --- version ------------------------------------------------------------------------------------
run "$keel" version
check_status "version -> exit 0" 0 "$STATUS"
check_contains "version prints a keel line" "$OUT" "keel "   # git-describe or 'unknown', both fine

# --- self-resolution: a PATH symlink from an unrelated cwd resolves the checkout ----------------
bindir="$SANDBOX/bin"; mkdir -p "$bindir"
ln -s "$fake/keel" "$bindir/keel"
run_in "$SANDBOX" "$bindir/keel" install --link
check_contains "resolves the checkout through a symlink, from another cwd" "$OUT" "STUB install.sh args=[--link]"

# invoked as a bare name found on PATH (no slash in $0) — the command -v branch
run_in "$SANDBOX" env PATH="$bindir:$PATH" keel doctor
check_contains "resolves when invoked as a bare PATH name" "$OUT" "STUB tools/doctor.sh"

# --- sanity guard: a keel with no sibling install.sh/tools errors, not a confusing ENOENT --------
orphan="$SANDBOX/orphan"; mkdir -p "$orphan"
cp "$REPO_ROOT/keel" "$orphan/keel"; chmod +x "$orphan/keel"
run "$orphan/keel" doctor
check_status "orphaned keel (no siblings) -> exit 1" 1 "$STATUS"
check_contains "orphaned keel explains itself" "$OUT" "cannot find the Keel checkout"

summary
