#!/usr/bin/env bash
# test_section_guard.sh (dir #758) — tests/section-guard.sh is the line a draft test section (a scratch
# file a session writes and sources to try a fixture before it becomes a test file) sources FIRST: it
# exits the shell before the draft's first git call unless tests/lib.sh's sandbox is loaded. The felt
# incident (0.15.0): `. t715.sh` ran a draft without lib.sh, `new_repo` was undefined, `r715=""`, and
# `git -C "" config diff.context abc` wrote a [diff] section into the MAIN checkout's shared .git/config —
# git died in every worktree for ten minutes. dir #658's `git()` guard only exists inside lib.sh, so a
# draft that never loaded lib.sh had no guard at all.
# Every case runs in a CHILD bash whose cwd is a throwaway repo under this file's $SANDBOX and whose PATH
# leads with a recording `git` shim, so the mutant (guard absent or inert) lands in a fixture, never in a
# real checkout. The shim logs every call; "exits before the first git call" is asserted as an EMPTY log.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

guard="$REPO_ROOT/tests/section-guard.sh"
lib="$REPO_ROOT/tests/lib.sh"

shimdir="$SANDBOX/section-shim"
mkdir -p "$shimdir"
cat > "$shimdir/git" <<'EOF'
#!/bin/sh
# Recording shim: logs the call and does NOT run git.
printf '%s\n' "$*" >> "$SECTION_GIT_LOG"
exit 0
EOF
chmod +x "$shimdir/git"

scratch="$(new_repo)"

# run_draft <draft-body> [lib]: writes the draft, runs it in a fresh bash (cwd = scratch) with the shim on
# PATH. With "lib" the child sources the real lib.sh first (a plain shell does not) and runs on the real
# git. Sets rc, log, errtxt.
n=0
run_draft() {
  n=$((n + 1))
  local body="$1" withlib="${2:-}" draft="$SANDBOX/draft$n.sh"
  printf '%s\n' "$body" > "$draft"
  : > "$SANDBOX/git$n.log"
  err="$SANDBOX/err$n"
  if [ "$withlib" = lib ]; then
    # real git here (no shim): lib.sh arms its ref guard through git config, which a recording shim would defeat
    (cd "$scratch" && env -u SANDBOX bash -c '. "$1" || exit 1; . "$2"' _ "$lib" "$draft" >"$SANDBOX/out$n" 2>"$err")
  else
    (cd "$scratch" && env -u SANDBOX SECTION_GIT_LOG="$SANDBOX/git$n.log" PATH="$shimdir:$PATH" \
      bash -c '. "$1"' _ "$draft" >"$SANDBOX/out$n" 2>"$err")
  fi
  rc=$?
  log="$(cat "$SANDBOX/git$n.log")"
  errtxt="$(cat "$err")"
}

check_file "tests/section-guard.sh exists" "$guard"

# --- S1: no lib.sh loaded -> the shell exits before the draft's first git call -------------------
run_draft ". \"$guard\" || exit 1
git -C \"\" config diff.context abc
echo DRAFT-CONTINUED"
check_ne "S1: a draft sourced without lib.sh exits non-zero" "$rc" 0
check_eq "S1: ...before its first git call (shim log empty)" "" "$log"
check_contains "S1: ...saying why, naming lib.sh" "$errtxt" "tests/lib.sh"
case "$(cat "$SANDBOX/out$n")" in *DRAFT-CONTINUED*) fail "S1: the draft body never ran" "DRAFT-CONTINUED was printed" ;; *) pass "S1: the draft body never ran" ;; esac

# --- S2: the guard exits the SHELL itself, so a draft that drops its `|| exit 1` is still stopped ---
run_draft ". \"$guard\"
git -C \"\" config diff.context abc"
check_ne "S2: a bare '. guard' (no || exit) still stops the draft" "$rc" 0
check_eq "S2: ...before its first git call" "" "$log"

# --- S3: a SANDBOX variable alone is not the sandbox (a draft that exports one by hand) -----------
run_draft "SANDBOX=/tmp/not-a-sandbox
. \"$guard\"
git -C \"\" config diff.context abc"
check_ne "S3: a hand-set SANDBOX without lib.sh's functions is refused" "$rc" 0
check_eq "S3: ...before its first git call" "" "$log"

# --- S3b-e: each footprint check bites on its own (a draft that fakes all but one piece is still refused) ----
run_draft "SANDBOX=\"$scratch\"; HOME=\"$scratch/home\"
git() { :; }
. \"$guard\"
git -C \"\" config diff.context abc"
check_ne "S3b: sandbox dir + HOME + git function but no new_repo is refused" "$rc" 0
check_eq "S3b: ...before its first git call" "" "$log"
run_draft "SANDBOX=/nonexistent-section-sandbox; HOME=/nonexistent-section-sandbox/home
new_repo() { :; }; git() { :; }
. \"$guard\"
git -C \"\" config diff.context abc"
check_ne "S3c: a SANDBOX naming no directory is refused" "$rc" 0
check_eq "S3c: ...before its first git call" "" "$log"
run_draft "SANDBOX=\"$scratch\"; HOME=/nonexistent-section-home
new_repo() { :; }; git() { :; }
. \"$guard\"
git -C \"\" config diff.context abc"
check_ne "S3d: a HOME outside the sandbox is refused" "$rc" 0
check_eq "S3d: ...before its first git call" "" "$log"
run_draft "SANDBOX=\"$scratch\"; HOME=\"$scratch/home\"
new_repo() { :; }
. \"$guard\"
git -C \"\" config diff.context abc"
check_ne "S3e: no git guard function (the bare binary) is refused" "$rc" 0
check_eq "S3e: ...before its first git call" "" "$log"

# --- S4: with lib.sh loaded the guard passes and the draft runs (the positive case) ---------------
run_draft ". \"$guard\" || exit 1
r=\"\$(new_repo)\"
git -C \"\$r\" config probe.ok yes
echo DRAFT-RAN" lib
check_eq "S4: a draft after lib.sh runs to the end" 0 "$rc"
case "$(cat "$SANDBOX/out$n")" in *DRAFT-RAN*) pass "S4: ...and its body executed" ;; *) fail "S4: ...and its body executed" "no DRAFT-RAN in $(cat "$SANDBOX/out$n") / $errtxt" ;; esac

# --- S5: nothing leaked into the scratch repo the cwd stood in --------------------------------------
if git -C "$scratch" config --get diff.context >/dev/null 2>&1; then
  fail "S5: the scratch repo's config stayed untouched" "diff.context was written"
else
  pass "S5: the scratch repo's config stayed untouched"
fi

# --- rail: written where workers read it ----------------------------------------------------------
pin "delegation.md carries the draft-section rail naming the guard" "$REPO_ROOT/docs/delegation.md" \
  'tests/section-guard.sh' "expected the rail to name the guard file a draft test section sources first"
pin "lib.sh's header points at the guard" "$lib" 'tests/section-guard.sh' \
  "expected lib.sh's header to name the guard for sections that never load lib.sh"

summary
