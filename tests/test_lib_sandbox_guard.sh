#!/usr/bin/env bash
# test_lib_sandbox_guard.sh — dir #318 regression: tests/lib.sh's require_sandbox_path() must abort
# the WHOLE test-file process on a bad fixture path, not just the command-substitution subshell its
# only real callers (new_repo()/new_bare_origin(), invoked as `d="$(new_repo)"`) run it inside of. A
# bare `exit` there is a silent no-op on exactly the path it exists to close — reproduced live by
# /code-review high on this ticket's own diff, fixed by signaling the top-level pid (`kill -TERM $$`)
# instead of relying on `exit` alone. This file drives that failure path in a real subprocess (it must
# be observed from OUTSIDE the process under test — the guard's whole point is that the process dies)
# rather than sourcing lib.sh in-process, where a triggered abort would kill this test file too.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# A caller that reaches require_sandbox_path() through the SAME command-substitution shape every real
# caller uses (`d="$(new_repo)")` — that's the shape a bare `exit` fails to escape.
probe="$SANDBOX/guard-probe.sh"
cat > "$probe" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
fake_new_repo() {
  local d="/not/the/sandbox"
  require_sandbox_path "$d" fake_new_repo
  echo "$d"
}
d="$(fake_new_repo)"
echo "REACHED-AFTER-GUARD: d=[$d]"
EOF
mkdir -p "$SANDBOX/subdir"
mv "$probe" "$SANDBOX/subdir/guard-probe.sh"
cp "$TESTS_DIR/lib.sh" "$SANDBOX/lib.sh"
run bash "$SANDBOX/subdir/guard-probe.sh"

check_absent "guard aborts the whole process — caller line never runs" "$OUT" "REACHED-AFTER-GUARD"
check_contains "guard prints its refusal message" "$OUT" "refusing to touch it"
# 143 = 128 + SIGTERM(15), the expected signal-death exit code; a plain `exit 90` from inside the
# subshell alone would report 0 here (the parent's own next statement, not the guard, sets $?).
check_status "guard's signal reaches the top-level process (exit 143, not 0)" 143 "$STATUS"

summary
