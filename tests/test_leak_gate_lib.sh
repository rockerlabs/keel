#!/usr/bin/env bash
# test_leak_gate_lib.sh — tools/lib/leak-gate.sh's leak_gate_run() is the ONE shared "scan, then turn
# the exit status into a path-only BLOCKED report or a scanner-failure report" shape, promoted out of
# tools/audit-packet/export.sh and tools/vendor-review.sh (both had independently typed it out; see the
# lib's own header). It had zero dedicated coverage of its own — everything exercising it ran only
# through the two callers' end-to-end CLI tests (test_audit_packet_export.sh,
# test_vendor_review.sh), which is real coverage of the callers but never pinned leak_gate_run's own
# contract in isolation, the same gap test_nonneg_int_lib.sh closed for tools/lib/nonneg-int.sh
# (doctor.sh's dir #142 coverage ratchet). This file drives leak_gate_run directly against small,
# controllable fake "scanner" scripts, rather than the real tools/secret-guard/secret-scan.sh, so each
# exit-status/output shape (clean, BLOCKED, scanner-itself-failed) is exercised deterministically —
# matching secret-scan.sh's own real wire format (a "secret-scan: BLOCKED ..." header line on stderr,
# then one "  path:line:content" detail line per hit, verified against tools/secret-guard/secret-scan.sh
# itself around its `echo "  $rec" >&2` call site) without depending on the real scanner's own patterns
# or behavior.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/leak-gate.sh"
check_file "tools/lib/leak-gate.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- fake scanners, matching secret-scan.sh's own real wire format ----------------------------------
scan_clean="$SANDBOX/scan-clean.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$scan_clean"
chmod +x "$scan_clean"

scan_blocked="$SANDBOX/scan-blocked.sh"
cat > "$scan_blocked" <<'EOF'
#!/usr/bin/env bash
echo "secret-scan: BLOCKED — secret-shaped string(s) or personal data detected:" >&2
echo "  b/two.txt:5:more" >&2
echo "  a/one.txt:3:fixture content: not-a-real-secret-just-has-a-colon" >&2
echo "  a/one.txt:3:fixture content: not-a-real-secret-just-has-a-colon" >&2
exit 1
EOF
chmod +x "$scan_blocked"

scan_broken="$SANDBOX/scan-broken.sh"
cat > "$scan_broken" <<'EOF'
#!/usr/bin/env bash
echo "scan-broken.sh: simulated crash — no such config file" >&2
exit 2
EOF
chmod +x "$scan_broken"

# --- clean: returns 0, hit-paths global is empty, no scanner stderr leaks into LEAK_GATE_STDERR ------
if leak_gate_run "$scan_clean" "" "some/file.txt"; then
  pass "leak_gate_run: clean scan returns 0"
else
  fail "leak_gate_run: clean scan returns 0" "returned $?"
fi
check_status "leak_gate_run: clean scan leaves LEAK_GATE_HIT_PATHS empty" "" "$LEAK_GATE_HIT_PATHS"
check_status "leak_gate_run: clean scan leaves LEAK_GATE_STDERR empty" "" "$LEAK_GATE_STDERR"

# --- BLOCKED: returns 1, hit-paths carries only the offending PATHS, deduped and sorted --------------
leak_gate_run "$scan_blocked" "" "a/one.txt" "b/two.txt"
status=$?
check_status "leak_gate_run: BLOCKED scan returns 1" 1 "$status"
check_contains "leak_gate_run: BLOCKED hit-paths names a/one.txt" "$LEAK_GATE_HIT_PATHS" "a/one.txt"
check_contains "leak_gate_run: BLOCKED hit-paths names b/two.txt" "$LEAK_GATE_HIT_PATHS" "b/two.txt"
n_lines="$(printf '%s\n' "$LEAK_GATE_HIT_PATHS" | grep -c .)"
check_status "leak_gate_run: BLOCKED hit-paths dedupes a/one.txt's two identical hit lines" 2 "$n_lines"

# --- the historical bug this lib's header documents: a from-the-end colon strip once leaked a content
# fragment on a record whose OWN matched content contains a colon ("leaked token: ghp_..."). The
# first-colon-only split must isolate exactly the path, never any word from the content half ----------
check_absent "leak_gate_run: BLOCKED hit-paths never repeats the matched content's own text" \
  "$LEAK_GATE_HIT_PATHS" "not-a-real-secret-just-has-a-colon"
check_absent "leak_gate_run: BLOCKED hit-paths never leaks the 'fixture content' content fragment" \
  "$LEAK_GATE_HIT_PATHS" "fixture content"

# --- scanner itself failed to run (exit status other than 0/1): LEAK_GATE_STDERR carries its stderr,
# LEAK_GATE_HIT_PATHS stays empty (this was never a finding) -------------------------------------------
leak_gate_run "$scan_broken" "" "whatever.txt"
status=$?
check_status "leak_gate_run: a broken scanner's own exit status is returned verbatim" 2 "$status"
check_contains "leak_gate_run: a broken scanner's stderr lands in LEAK_GATE_STDERR" \
  "$LEAK_GATE_STDERR" "simulated crash"
check_status "leak_gate_run: a broken scanner leaves LEAK_GATE_HIT_PATHS empty" "" "$LEAK_GATE_HIT_PATHS"

# --- output globals don't leak a stale value from a prior call into the next one ----------------------
leak_gate_run "$scan_clean" "" "some/file.txt"
check_status "leak_gate_run: a later clean call clears LEAK_GATE_HIT_PATHS from an earlier BLOCKED call" \
  "" "$LEAK_GATE_HIT_PATHS"
check_status "leak_gate_run: a later clean call clears LEAK_GATE_STDERR from an earlier broken call" \
  "" "$LEAK_GATE_STDERR"

# --- RELABEL_FN: applied once per raw hit path, BEFORE dedup/sort, so two distinct raw paths that
# relabel to the SAME name collapse into one entry ------------------------------------------------------
_test_relabel_to_same_name() { printf '%s' "relabeled"; }
leak_gate_run "$scan_blocked" "_test_relabel_to_same_name" "a/one.txt" "b/two.txt"
status=$?
check_status "leak_gate_run: RELABEL_FN still returns 1 on BLOCKED" 1 "$status"
check_status "leak_gate_run: RELABEL_FN's replacement replaces the raw path" "relabeled" "$LEAK_GATE_HIT_PATHS"

_test_relabel_passthrough() {
  case "$1" in
    "a/one.txt") printf '%s' "--some-flag text" ;;
    *)           printf '%s' "$1" ;;
  esac
}
leak_gate_run "$scan_blocked" "_test_relabel_passthrough" "a/one.txt" "b/two.txt"
check_contains "leak_gate_run: RELABEL_FN relabels the path it matches" "$LEAK_GATE_HIT_PATHS" "--some-flag text"
check_contains "leak_gate_run: RELABEL_FN leaves a non-matching path unchanged" "$LEAK_GATE_HIT_PATHS" "b/two.txt"
check_absent "leak_gate_run: RELABEL_FN's relabeled path no longer appears raw" "$LEAK_GATE_HIT_PATHS" "a/one.txt"

# --- both known callers source the shared lib, not a private inline copy of this shape ---------------
check_contains "tools/audit-packet/export.sh sources tools/lib/leak-gate.sh" \
  "$(cat "$REPO_ROOT/tools/audit-packet/export.sh")" 'lib/leak-gate.sh'
check_contains "tools/audit-packet/export.sh's run_leak_gate calls leak_gate_run" \
  "$(cat "$REPO_ROOT/tools/audit-packet/export.sh")" 'leak_gate_run "$scan_script"'
check_contains "tools/vendor-review.sh sources tools/lib/leak-gate.sh" \
  "$(cat "$REPO_ROOT/tools/vendor-review.sh")" 'lib/leak-gate.sh'
check_contains "tools/vendor-review.sh calls leak_gate_run" \
  "$(cat "$REPO_ROOT/tools/vendor-review.sh")" 'leak_gate_run "$scan_script"'

summary
