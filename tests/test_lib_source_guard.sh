#!/usr/bin/env bash
# test_lib_source_guard.sh — dir #627: tests/lib.sh is what redirects HOME into a disposable
# sandbox before any fixture runs, and every tests/test_*.sh sources it. The incident this file
# guards against: a missing lib.sh (a gitignored symlink in the claude-kb adopter, absent from a
# fresh `git worktree add`) let a test file's bare `. lib.sh` fail and CONTINUE — under `set -uo
# pipefail` with no `-e` — running its fixtures against the real machine, which deleted a live
# `~/.claude` harness home. Covers three independent layers dir #627 added: (1) every test file's own
# source line now fails closed; (2) lib.sh itself refuses to be sourced if its sandbox creation
# (`mktemp -d`) silently failed; (3) an unknown assertion (`check_eq` when only `check_ne` exists,
# say) must make the file RED via command_not_found_handle, not just thinner.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# --- layer 1: every real tests/test_*.sh sources lib.sh fail-closed, pinned as ONE regex since the
# fix is byte-uniform across all 82 files (BACKLOG.md dir #627's own coupling note) ----------------
# `grep -m1` takes the FIRST top-level match in each file: tests/test_lib_sandbox_guard.sh is the one
# file in the suite with a SECOND match, inside a single-quoted heredoc that builds a synthetic probe
# script for a different mechanism (dir #318's require_sandbox_path()) — that inner line is fixture
# content, not this file's own source line, and always sorts after the real one.
fail_closed_tail='|| { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }'
missing=()
total=0
checked=0
for t in "$REPO_ROOT"/tests/test_*.sh; do
  total=$((total + 1))
  line="$(grep -m1 -E '^\. ".*/lib\.sh"' "$t" || true)"
  [ -n "$line" ] || continue
  checked=$((checked + 1))
  case "$line" in
    *"$fail_closed_tail") ;;
    *) missing+=("$(basename "$t")") ;;
  esac
done
# The count itself is asserted too: a future test file whose source line takes a shape this regex
# doesn't recognize (e.g. `source` instead of `.`) would silently drop out of `missing`'s scope
# rather than fail it — this catches that the loop actually looked at everything the glob above
# would (82 at dir #627's own filing time; re-derive rather than trust a stale count going forward).
check_status "every tests/test_*.sh that sources lib.sh was actually checked" "$total" "$checked"
if [ "${#missing[@]}" -eq 0 ]; then
  pass "every tests/test_*.sh sources lib.sh fail-closed (|| exit on a missing lib.sh)"
else
  fail "every tests/test_*.sh sources lib.sh fail-closed" "missing the fail-closed tail: ${missing[*]}"
fi

# --- layer 1, felt-incident reproduction: a scratch copy of a real fixture, run BOTH directly and
# through run.sh, with lib.sh deliberately absent — proving both the fixed source line and run.sh's
# own pre-flight check stop the run before any fixture body executes, never under the real HOME -----
scratch_suite="$(mktemp -d "$SANDBOX/scratch-suite.XXXXXX")"
require_sandbox_path "$scratch_suite" test_lib_source_guard
mkdir -p "$scratch_suite/tests"
cp "$REPO_ROOT/tests/test_examples.sh" "$scratch_suite/tests/"
cp "$REPO_ROOT/tests/run.sh" "$scratch_suite/tests/"
# lib.sh deliberately NOT copied — this is the incident's own precondition.

run bash "$scratch_suite/tests/test_examples.sh"
check_status "felt-incident repro, DIRECT run with lib.sh missing -> nonzero exit" 1 "$STATUS"
check_contains "felt-incident repro, DIRECT run names the refusal" "$OUT" "lib.sh missing"

run bash "$scratch_suite/tests/run.sh"
check_status "felt-incident repro, via run.sh with lib.sh missing -> refuses before any fixture" 1 "$STATUS"
check_contains "felt-incident repro, run.sh names the remedy" "$OUT" "dir #627"
check_absent "felt-incident repro, run.sh never even started the fixture" "$OUT" "=== test_examples.sh ==="

# --- layer 2: lib.sh refuses to be sourced when mktemp -d fails, BEFORE the git config / mkdir
# calls that would otherwise run against a bogus HOME (SANDBOX="" -> HOME="/home") -------------------
badmktemp_dir="$(mktemp -d "$SANDBOX/badmktemp.XXXXXX")"
require_sandbox_path "$badmktemp_dir" test_lib_source_guard
cat > "$badmktemp_dir/mktemp" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$badmktemp_dir/mktemp"
probe="$SANDBOX/mktempfail-probe.sh"
cat > "$probe" << EOF
#!/usr/bin/env bash
set -uo pipefail
. "$TESTS_DIR/lib.sh"
echo REACHED-AFTER-LIBSH-SOURCE
EOF
run env PATH="$badmktemp_dir:$PATH" bash "$probe"
check_status "lib.sh refuses when mktemp -d fails -> nonzero exit" 1 "$STATUS"
check_contains "lib.sh names the refusal (dir #627)" "$OUT" "dir #627"
check_absent "lib.sh's refusal stops the file before anything after the source line runs" \
  "$OUT" "REACHED-AFTER-LIBSH-SOURCE"

# --- layer 3: an undefined assertion is caught by command_not_found_handle, which must stop the
# WHOLE test-file process, not just its own forked execution environment ----------------------------
# bash dispatches command_not_found_handle in a separate execution environment (its own $BASHPID) —
# the same shape require_sandbox_path() above already documents for `$(...)`-subshell callers — so a
# bare `exit` inside it is a no-op on exactly the path it exists to close (verified live on this
# ticket's own alpine/bash-5 image before the `kill -TERM $$` fix landed: without it, the undefined
# call's own exit status was silently absorbed and the file kept running). command_not_found_handle
# is a bash >= 4.0 feature: this project's own dev machine ships /bin/bash 3.2.57, where it never
# fires at all — skip there rather than report a false red or a false green; CI's Linux legs run
# bash >= 4 and exercise this for real. tests/run.sh's own "command not found" log scan (dir #627,
# see test_run_sh.sh) is the portable backstop for bash 3.2, but that only covers a run THROUGH
# run.sh — this is the one case that covers a DIRECT run on bash >= 4.
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
  handler_probe="$SANDBOX/handler-probe.sh"
  cat > "$handler_probe" << EOF
#!/usr/bin/env bash
. "$TESTS_DIR/lib.sh"
echo BEFORE-UNDEFINED-CALL
check_totally_undefined_thing_dir627 foo bar
echo REACHED-AFTER-UNDEFINED-CALL
EOF
  run bash "$handler_probe"
  check_status "command_not_found_handle stops the whole file (bash >= 4), signal-death" 143 "$STATUS"
  check_contains "command_not_found_handle names the offending call" "$OUT" "check_totally_undefined_thing_dir627"
  check_contains "the call happened before the guard fired" "$OUT" "BEFORE-UNDEFINED-CALL"
  check_absent "command_not_found_handle actually stops execution" "$OUT" "REACHED-AFTER-UNDEFINED-CALL"
else
  pass "command_not_found_handle live check skipped — ambient bash $BASH_VERSION is < 4.0 (dir #627: Linux-only protection; CI's legs cover it)"
fi

# --- layer 3, felt regression (found live by an independent /code-review high pass on this ticket's
# own diff, reproduced on the alpine CI image): command_not_found_handle's reach is BLANKET, not
# scoped to assertion calls — any EXISTING lib.sh helper that calls an external command without first
# checking it exists is now killed outright by an absent binary instead of degrading the way it always
# documented. pick_utf8_locale() did exactly this (`locale -a` with no guard); CI's alpine leg ships
# no `locale` binary at all, so a call to it there used to kill the whole test file instead of
# returning 1 as its own two real callers (test_public_audit.sh, test_secret_guard.sh) expect. Fixed
# with an explicit `command -v locale` guard, now UNCONDITIONAL inside pick_utf8_locale() — not gated
# on command_not_found_handle at all, so this exercises the fix on any bash version, including this
# project's own bash 3.2 dev machine. path_farm() (below) is the established idiom other test files
# already use to hide one binary from PATH. -----------------------------------------------------------
nolocale_farm="$(mktemp -d "$SANDBOX/nolocale-farm.XXXXXX")"
require_sandbox_path "$nolocale_farm" test_lib_source_guard
path_farm "$nolocale_farm" locale
nolocale_probe="$SANDBOX/nolocale-probe.sh"
cat > "$nolocale_probe" << EOF
#!/usr/bin/env bash
. "$TESTS_DIR/lib.sh"
utf8_locale="\$(pick_utf8_locale)" || utf8_locale=""
echo "RESULT:[\$utf8_locale]"
EOF
run env PATH="$nolocale_farm" bash "$nolocale_probe"
check_status "pick_utf8_locale degrades gracefully with no locale binary on PATH -> exit 0, no kill" 0 "$STATUS"
check_contains "pick_utf8_locale returns empty rather than crashing the file" "$OUT" "RESULT:[]"

summary
