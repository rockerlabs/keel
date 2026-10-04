#!/usr/bin/env bash
# test_residue_gate.sh — the residue gate in tests/run.sh (dir #663 (b)). run.sh puts a recording `mktemp`
# shim ahead on PATH and, after the last test file, fails the run when a path that mktemp minted still
# exists. This file drives COPIES of run.sh over fake tests/ directories (the way test_run_sh.sh does) and
# proves, per mechanism, that a leak turns the run red, a clean run stays green, and each clause of the
# gate binds (a mutated copy of run.sh goes blind or fails closed, as named).
#
# Every leak below lands in a pretend "real temp dir" inside $SANDBOX: a `mktemp` on PATH sends each BARE
# call there. On macOS a bare `mktemp` ignores $TMPDIR, and a leak mutant here would otherwise strand real
# entries in the machine's temp dir that this session cannot remove.
#
# (The two logdir-guard clauses dir #663 also folds in, R3-6, are pinned in test_run_sh.sh beside R2-4's.)
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "test-suite residue gate (dir #663 (b))"

runner="$REPO_ROOT/tests/run.sh"
check_file "run.sh exists" "$runner"

export TMPDIR="$SANDBOX"
real_mktemp="$(type -P mktemp)"
realtmp="$SANDBOX/real-tmp"
redir="$SANDBOX/redir-bin"
mkdir -p "$realtmp" "$redir"
# A template argument (any non-option word) is honoured as given; a bare call gets one under $realtmp.
cat > "$redir/mktemp" <<EOF
#!/bin/sh
for a in "\$@"; do case "\$a" in -*) ;; *) exec "$real_mktemp" "\$@" ;; esac; done
exec "$real_mktemp" "\$@" "$realtmp/tmp.XXXXXXXX"
EOF
chmod 755 "$redir/mktemp"

# mkfake NAME — a throwaway tests/ dir with a copy of run.sh and a stub lib.sh (it only has to exist, run.sh
# refuses to start without one); the fixtures here do not source it.
mkfake() {
  local d; d="$(mktemp -d "$SANDBOX/fake-$1.XXXXXX")"
  cp "$runner" "$d/run.sh"; chmod +x "$d/run.sh"; : > "$d/lib.sh"
  printf '%s' "$d"
}
# fixture DIR NAME BODY — write DIR/test_NAME.sh
fixture() { printf '#!/usr/bin/env bash\n%s\nexit 0\n' "$3" > "$1/test_$2.sh"; }
# runfake DIR — run DIR/run.sh with the redirecting mktemp first on PATH
runfake() { run env KEEL_TEST_JOBS=2 PATH="$redir:$PATH" bash "$1/run.sh"; }
left_in_realtmp() { find "$realtmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' '; }
clear_realtmp() { find "$realtmp" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; }
# assert_mutated LABEL FILE — the mutation really changed the copy of run.sh (a refactor of run.sh that
# moves the anchor text would otherwise leave a no-op "mutant" that proves nothing)
assert_mutated() { check_ne "$1: the edit changed the copy of run.sh" "$(cksum < "$2")" "$(cksum < "$runner")"; }

# --- clean: scratch removed by every common shape -> green, the traced count is exact --------------------------
d="$(mkfake clean)"
fixture "$d" a 'x="$(mktemp -d)"; rm -rf "$x"
f="$(mktemp)"; rm -f "$f"
t="$(mktemp -d)"; trap '"'"'rm -rf "$t"'"'"' EXIT'
runfake "$d"
check_status "clean fixtures -> exit 0" 0 "$STATUS"
check_contains "clean: ALL TEST FILES PASSED" "$OUT" "ALL TEST FILES PASSED"
check_contains "clean: the gate reports the three paths it traced and none left" "$OUT" \
  "residue gate (dir #663): 3 mktemp-minted path(s) traced, 0 left behind"
check_absent "clean: the gate does not trip" "$OUT" "RESIDUE GATE TRIPPED"
check_eq "clean: nothing is left in the pretend temp dir" 0 "$(left_in_realtmp)"

# --- the shim is invisible: -u makes nothing and is not traced; a failing mktemp still fails -----------------------
d="$(mkfake passthru)"
fixture "$d" a 'u="$(mktemp -u)"; [ -n "$u" ] && [ ! -e "$u" ] || exit 1
if mktemp "/no-such-dir-663/x.XXXXXX" >/dev/null 2>&1; then exit 2; fi'
runfake "$d"
check_status "passthrough: -u is silent and a failing mktemp keeps its nonzero status" 0 "$STATUS"
check_contains "passthrough: a dry run is not counted as a minted path" "$OUT" \
  "0 mktemp-minted path(s) traced, 0 left behind"

# --- each leak mechanism turns the run red, names the path, and leaves it on disk as evidence -------------------
leak_case() {   # leak_case LABEL BODY
  local label="$1" body="$2" dd n
  dd="$(mkfake leak)"
  fixture "$dd" a "$body"
  runfake "$dd"
  check_status "$label: exit 1" 1 "$STATUS"
  check_contains "$label: the gate trips" "$OUT" "RESIDUE GATE TRIPPED (dir #663)"
  check_contains "$label: names a leaked path in the (pretend) temp dir" "$OUT" "  $realtmp/tmp."
  check_absent "$label: never a pass" "$OUT" "ALL TEST FILES PASSED"
  check_contains "$label: counted as a failure" "$OUT" "1 TEST FILE(S) FAILED"
  check_contains "$label: the trace path is named" "$OUT" "mktemp.trace"
  n="$(left_in_realtmp)"
  check_ne "$label: the leaked entry is still on disk (the gate reports it, never deletes it)" "$n" 0
  clear_realtmp
}
leak_case "a bare mktemp -d never removed"        'x="$(mktemp -d)"'
leak_case "a bare mktemp file never removed"      'f="$(mktemp)"'
leak_case "a cleared cleanup trap (trap - EXIT)"  'x="$(mktemp -d)"; trap '"'"'rm -rf "$x"'"'"' EXIT; trap - EXIT'
leak_case "a grandchild process's mktemp"         'bash -c '"'"'mktemp -d >/dev/null'"'"
leak_case "a scratch file a tool keeps on failure" 'printf '"'"'#!/bin/sh\ns="$(mktemp)"\necho kept "$s" >&2\nexit 3\n'"'"' > "$0.tool"; sh "$0.tool" 2>/dev/null; rm -f "$0.tool"'

# a relative template is recorded as the absolute path it made
d="$(mkfake rel)"
mkdir -p "$SANDBOX/relcwd"
fixture "$d" a "cd \"$SANDBOX/relcwd\" && mktemp ./leak.XXXXXX >/dev/null"
runfake "$d"
check_status "a relative template: the leak is found, exit 1" 1 "$STATUS"
check_contains "a relative template: recorded under its absolute directory" "$OUT" "  $SANDBOX/relcwd/./leak."

# --- the gate fails closed: it never reports a clean run it could not watch -----------------------------------------
d="$(mkfake m-nopath)"
fixture "$d" a 'echo should-not-run'
delete_line_containing "$d/run.sh" 'PATH="$resid_dir:$PATH"'
assert_mutated "no shim on PATH" "$d/run.sh"
runfake "$d"
check_status "no shim on PATH: run.sh refuses to run -> exit 1" 1 "$STATUS"
check_contains "no shim on PATH: it says the gate could not be armed" "$OUT" "residue gate (dir #663) could not be armed: the shim is not first on PATH"
check_absent "no shim on PATH: before any test file started" "$OUT" "=== test_a.sh ==="

d="$(mkfake m-noprobe)"
fixture "$d" a 'echo should-not-run'
replace_in_line_containing "$d/run.sh" '>> "$trace"' '>> "$trace"' '>> /dev/null'
assert_mutated "a shim that records nothing" "$d/run.sh"
runfake "$d"
check_status "a shim that records nothing: the probe catches it -> exit 1" 1 "$STATUS"
check_contains "a shim that records nothing: names the probe" "$OUT" "the shim did not record a probe path"
check_absent "a shim that records nothing: before any test file started" "$OUT" "=== test_a.sh ==="

# --- each clause binds: a mutated run.sh goes blind where the real one trips -----------------------------------------
d="$(mkfake m-noverdict)"
fixture "$d" a 'x="$(mktemp -d)"'
delete_line_containing "$d/run.sh" '# residue gate verdict'
assert_mutated "no verdict increment" "$d/run.sh"
runfake "$d"
check_status "no verdict increment: the SAME leaking fixture now passes (so the increment is what turns it red)" 0 "$STATUS"
check_contains "no verdict increment: the gate still printed its trip text, then passed" "$OUT" "RESIDUE GATE TRIPPED (dir #663)"
clear_realtmp

d="$(mkfake m-notrace)"
fixture "$d" a 'x="$(mktemp -d)"'
replace_in_line_containing "$d/run.sh" 'sort -u "$resid_trace"' 'sort -u "$resid_trace"' 'sort -u /dev/null'
assert_mutated "verdict reads no trace" "$d/run.sh"
runfake "$d"
check_status "verdict reads no trace: the SAME leaking fixture now passes (so reading the trace is what finds it)" 0 "$STATUS"
clear_realtmp

summary
