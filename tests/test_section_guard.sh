#!/usr/bin/env bash
# test_section_guard.sh (dir #758) — tests/section-guard.sh is the line a draft test section (a scratch
# file a session writes and sources to try a fixture before it becomes a test file) sources right
# after its lib.sh line: it exits the shell before the draft's first git call unless tests/lib.sh's sandbox is loaded. The felt
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

# run_draft <draft-body> [lib|real|zsh]: writes the draft, runs it in a fresh shell (cwd = scratch). Default:
# bash with the recording shim first on PATH. "lib": the child sources the real lib.sh first (a plain shell
# does not) and runs on the real git, because lib.sh arms its ref guard through git config, which a shim
# defeats. "real": bash on the real git, no lib.sh — the only mode where an unguarded `git -C ""` really
# writes (into the scratch repo), so "nothing was written" is a binding assertion there. "zsh": the draft
# under zsh, which a Bash tool may run. Sets rc, log, errtxt.
n=0
run_draft() {
  n=$((n + 1))
  local body="$1" mode="${2:-}" draft="$SANDBOX/draft$n.sh"
  printf '%s\n' "$body" > "$draft"
  : > "$SANDBOX/git$n.log"
  err="$SANDBOX/err$n"
  case "$mode" in
    lib)  (cd "$scratch" && env -u SANDBOX bash -c '. "$1" || exit 1; . "$2"' _ "$lib" "$draft" >"$SANDBOX/out$n" 2>"$err") ;;
    real) (cd "$scratch" && env -u SANDBOX bash -c '. "$1"' _ "$draft" >"$SANDBOX/out$n" 2>"$err") ;;
    zsh)  (cd "$scratch" && env -u SANDBOX zsh -c '. "$1"' _ "$draft" >"$SANDBOX/out$n" 2>"$err") ;;
    *)    (cd "$scratch" && env -u SANDBOX SECTION_GIT_LOG="$SANDBOX/git$n.log" PATH="$shimdir:$PATH" \
            bash -c '. "$1"' _ "$draft" >"$SANDBOX/out$n" 2>"$err") ;;
  esac
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

# --- S5: on the REAL git (no shim), the unguarded write would land in the scratch repo — it must not -----
run_draft ". \"$guard\" || exit 1
git -C \"\" config diff.context abc" real
check_ne "S5: a draft without lib.sh, on real git, exits non-zero" "$rc" 0
if git -C "$scratch" config --get diff.context >/dev/null 2>&1; then
  fail "S5: ...and the scratch repo's config stayed untouched" "diff.context was written"
else
  pass "S5: ...and the scratch repo's config stayed untouched"
fi
# control: the same draft WITHOUT the guard line does write there, so the assertion above can fail
run_draft "git -C \"\" config diff.context abc" real
if git -C "$scratch" config --get diff.context >/dev/null 2>&1; then
  pass "S5 control: without the guard the same draft writes into the cwd repo"
else
  fail "S5 control: without the guard the same draft writes into the cwd repo" "diff.context was not written"
fi
git -C "$scratch" config --unset diff.context

# --- S6: lib.sh is bash; a shell that is not bash is refused even with the whole footprint faked --------
run_draft "SANDBOX=\"$scratch\"; HOME=\"$scratch/home\"
new_repo() { :; }; git() { :; }
unset BASH_VERSION
. \"$guard\"
echo S6-DRAFT-CONTINUED"
check_ne "S6: a non-bash shell is refused (BASH_VERSION unset)" "$rc" 0
case "$(cat "$SANDBOX/out$n")" in *S6-DRAFT-CONTINUED*) fail "S6: ...the draft body never ran" "it ran" ;; *) pass "S6: ...the draft body never ran" ;; esac
# S6a: the refusal text names the route for the case at hand (bash without lib.sh vs a non-bash shell)
check_contains "S6a: bash without lib.sh is told to source lib.sh first" "$(cat "$SANDBOX/err1")" 'Source "<checkout>/tests/lib.sh" || exit 1 before this guard'
check_contains "S6a: a non-bash shell is told to run the draft under bash" "$(cat "$err")" "run the draft as a file under bash"
# S6c: the guard's own syntax is POSIX — a plain sh (dash/busybox on the Linux legs) must parse it and refuse
(cd "$scratch" && env -u SANDBOX sh -c '. "$1"; echo SH-CONTINUED' _ "$guard" >"$SANDBOX/outsh" 2>"$SANDBOX/errsh")
check_ne "S6c: sh -c '. guard' refuses with no lib.sh" "$?" 0
case "$(cat "$SANDBOX/outsh")" in *SH-CONTINUED*) fail "S6c: ...and stops the shell" "continued" ;; *) pass "S6c: ...and stops the shell" ;; esac
case "$(cat "$SANDBOX/errsh")" in *"syntax error"*|*"not found"*) fail "S6c: ...by its own message, not a parse error" "$(cat "$SANDBOX/errsh")" ;; *) pass "S6c: ...by its own message, not a parse error" ;; esac
# S6b: the felt shape — a Bash tool that is zsh. lib.sh half-loads there and returns 0; the guard refuses.
if command -v zsh >/dev/null 2>&1; then
  run_draft ". \"$lib\"
. \"$guard\"
echo ZSH-DRAFT-CONTINUED" zsh
  check_ne "S6b: lib.sh half-loaded under zsh does not satisfy the guard" "$rc" 0
  case "$(cat "$SANDBOX/out$n")" in *ZSH-DRAFT-CONTINUED*) fail "S6b: ...the draft body never ran" "it ran" ;; *) pass "S6b: ...the draft body never ran" ;; esac
else
  echo "  skip  S6b: no zsh on this machine"
fi

# --- rail: written where workers read it ----------------------------------------------------------
pin "delegation.md carries the draft-section rail naming the guard" "$REPO_ROOT/docs/delegation.md" \
  'tests/section-guard.sh' "expected the rail to name the guard file a draft test section sources first"
pin "the rail names the copied-fragment residual" "$REPO_ROOT/docs/delegation.md" \
  'A section copied out of a test file arrives without the harness line' \
  "expected the rail to say a copied fragment loses the lib line"
pin "the rail says the guard refuses a non-bash shell" "$REPO_ROOT/docs/delegation.md" \
  'it refuses outright under any shell that is not bash' "expected the rail to state the bash-only refusal"
pin "the rail is written for any project, Keel's form marked" "$REPO_ROOT/docs/delegation.md" \
  "*In Keel's own repository* the harness is" "expected the Keel-specific form to be marked as such"
pin "the rail points live experiments at a throwaway repo" "$REPO_ROOT/docs/delegation.md" \
  'belongs in a throwaway `git init` directory' "expected the live-experiment rule"
pin "lib.sh's header points at the guard" "$lib" 'tests/section-guard.sh' \
  "expected lib.sh's header to name the guard for sections that never load lib.sh"

summary
