#!/usr/bin/env bash
# test_require_git_repo_lib.sh — dir #591: tools/lib/require-git-repo.sh is the ONE "is DIR a git checkout?"
# check. Before it, ten tools hand-rolled "assert the repo is a git checkout, exit with a labelled message", and
# dir #240's review found two shapes subtly wrong: an exit-status-only `--is-inside-work-tree` (exits 0 and
# prints "false" for a bare repository, so a bare repo passed) and an unguarded `out="$(git ...)"` assignment
# (a silent `set -e` abort before the labelled message). This pins the lib's two predicates and its hard gate
# (including `set -e` safety and the "dubious ownership" pass-through), each consumer's behaviour on a bare
# repository, and — at the source level — that no tool outside a short allowlist reverted to a hand-rolled copy.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/require-git-repo.sh"
check_file "tools/lib/require-git-repo.sh exists" "$lib"

# --- fixtures: a work tree, a subdirectory of it, a bare repo, a non-git dir, a path inside .git ---------
wt="$(new_repo)"
git -C "$wt" commit -q --allow-empty -m init
mkdir -p "$wt/sub"
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"
require_sandbox_path "$bare" bare
git init -q --bare "$bare"
nongit="$(mktemp -d "$SANDBOX/nongit.XXXXXX")"
require_sandbox_path "$nongit" nongit

# probe CALL… — run CALL in a fresh `set -euo pipefail` bash that sources the lib; prints "<rc>" via run().
probe() { run bash -c 'set -euo pipefail; . "$1"; shift; "$@"; echo "reached-after:$?"' _ "$lib" "$@"; }

# --- keel_is_git_work_tree --------------------------------------------------------------------------
probe keel_is_git_work_tree "$wt";            check_contains "work tree -> true"                     "$OUT" "reached-after:0"
probe keel_is_git_work_tree "$wt/sub";        check_contains "a subdirectory of a work tree -> true" "$OUT" "reached-after:0"
run bash -c 'set -u; . "$1"; keel_is_git_work_tree "$2"' _ "$lib" "$nongit"
check_status "a non-git dir -> 1" 1 "$STATUS"
run bash -c 'set -u; . "$1"; keel_is_git_work_tree "$2"' _ "$lib" "$bare"
check_status "a BARE repo -> 1 (git exits 0 printing false: the exit status alone passed it)" 1 "$STATUS"
run bash -c 'set -u; . "$1"; keel_is_git_work_tree "$2"' _ "$lib" "$wt/.git"
check_status "a path inside .git -> 1 (also exits 0 printing false)" 1 "$STATUS"
run bash -c 'set -u; . "$1"; keel_is_git_work_tree "$2"' _ "$lib" "$nongit/does-not-exist"
check_status "a missing dir -> 1" 1 "$STATUS"
run_in "$wt/sub" bash -c 'set -u; . "$1"; keel_is_git_work_tree' _ "$lib"
check_status "no argument -> the current directory (work tree)" 0 "$STATUS"
# set -e safety, the dir #240 class: a failing git inside the predicate must not abort the caller silently.
run bash -c 'set -euo pipefail; . "$1"; keel_is_git_work_tree "$2" || echo handled-by-caller; echo survived' _ "$lib" "$nongit"
check_contains "set -e: the caller's || branch runs on a non-git dir" "$OUT" "handled-by-caller"
check_contains "set -e: the caller survives the failing check" "$OUT" "survived"
run bash -c 'set -euo pipefail; . "$1"; if ! keel_is_git_work_tree "$2"; then echo negated-branch; fi' _ "$lib" "$bare"
check_contains "set -e: an if-negated check on a bare repo takes the negated branch" "$OUT" "negated-branch"

# --- keel_is_git_repo (any repository, bare included) ---------------------------------------------------
run bash -c 'set -u; . "$1"; keel_is_git_repo "$2"' _ "$lib" "$bare"
check_status "keel_is_git_repo: a bare repo -> 0" 0 "$STATUS"
run bash -c 'set -u; . "$1"; keel_is_git_repo "$2"' _ "$lib" "$wt"
check_status "keel_is_git_repo: a work tree -> 0" 0 "$STATUS"
run bash -c 'set -u; . "$1"; keel_is_git_repo "$2"' _ "$lib" "$nongit"
check_status "keel_is_git_repo: a non-git dir -> 1" 1 "$STATUS"

# --- keel_require_git_work_tree -------------------------------------------------------------------------
run bash -c 'set -euo pipefail; . "$1"; keel_require_git_work_tree "$2" lbl "msg"; echo passed' _ "$lib" "$wt"
check_status "require: a work tree returns" 0 "$STATUS"
check_contains "require: a work tree falls through" "$OUT" "passed"
run bash -c 'set -euo pipefail; . "$1"; keel_require_git_work_tree "$2" lbl "msg here"; echo NOT-REACHED' _ "$lib" "$nongit"
check_status "require: a non-git dir exits 2 by default (labelled, under set -e)" 2 "$STATUS"
check_eq "require: the line is 'LABEL: MESSAGE'" "lbl: msg here" "$OUT"
run bash -c 'set -euo pipefail; . "$1"; keel_require_git_work_tree "$2" "" "bare msg"; echo NOT-REACHED' _ "$lib" "$nongit"
check_eq "require: an empty label prints the bare message" "bare msg" "$OUT"
run bash -c 'set -euo pipefail; . "$1"; keel_require_git_work_tree "$2" lbl "msg" 3; echo NOT-REACHED' _ "$lib" "$bare"
check_status "require: a bare repo exits with the caller's code (3)" 3 "$STATUS"
check_eq "require: a bare repo gets the plain message, not git's 'false'" "lbl: msg" "$OUT"
# Without set -e, and from inside an `if`/`||` context (a set -e-exempt one): still exits, never returns.
run bash -c '. "$1"; if keel_require_git_work_tree "$2" lbl "msg"; then echo NOT-REACHED; fi; echo NOT-REACHED-EITHER' _ "$lib" "$nongit"
check_status "require: exits from inside an if-condition too (an explicit exit, not a return)" 2 "$STATUS"
check_absent "require: nothing runs after the refusal" "$OUT" "NOT-REACHED"

# "dubious ownership" is a different failure from "not a git repository": git's own diagnostic goes through.
stub="$SANDBOX/dubious-stub"
mkdir -p "$stub"
real_git="$(type -P git)"
printf '#!/bin/sh\ncase "$*" in *is-inside-work-tree*) echo "fatal: detected dubious ownership in repository at '"'"'x'"'"'" >&2; exit 128 ;; esac\nexec "%s" "$@"\n' "$real_git" > "$stub/git"
chmod 755 "$stub/git"
run env PATH="$stub:$PATH" bash -c 'set -euo pipefail; . "$1"; keel_require_git_work_tree "$2" lbl "generic msg"' _ "$lib" "$wt"
check_status "dubious ownership: exits 2" 2 "$STATUS"
check_contains "dubious ownership: git's own diagnostic is passed through" "$OUT" "dubious ownership"
check_absent "dubious ownership: not relabelled as the generic message" "$OUT" "generic msg"
check_contains "dubious ownership: still carries the label" "$OUT" "lbl: fatal:"

# --- the shared arg guard now rejects a bare repo (it used to pass on the exit status) -----------------
run bash -c 'set -euo pipefail; . "$1"; keel_repo_arg_guard "$2"' _ "$REPO_ROOT/tools/lib/repo-arg-guard.sh" "$bare"
check_status "keel_repo_arg_guard: a bare repo exits 2" 2 "$STATUS"
check_eq "keel_repo_arg_guard: the wording is unchanged" "not a git repo: $bare" "$OUT"

# --- consumers, each on a BARE repo: a labelled refusal, never a silent pass ------------------------------
run bash "$REPO_ROOT/tools/install-secret-guard.sh" --where "$bare"
check_status "install-secret-guard --where <bare> exits 2" 2 "$STATUS"
check_eq "install-secret-guard --where <bare>: unchanged wording" "not a git repo: $bare" "$OUT"
run bash "$REPO_ROOT/tools/install-secret-guard.sh" --where "$nongit"
check_status "install-secret-guard --where <non-git> exits 2" 2 "$STATUS"
run bash "$REPO_ROOT/tools/install-secret-guard.sh" "$bare"
check_status "install-secret-guard <bare> (install mode) exits 2" 2 "$STATUS"
check_eq "install-secret-guard <bare> (install mode): unchanged wording" "not a git repo: $bare" "$OUT"
check_nodir "install-secret-guard <bare>: nothing written into the bare repo's hooks dir" "$bare/hooks/pre-commit.d"
check_nofile "install-secret-guard <bare>: no pre-commit hook installed" "$bare/hooks/pre-commit"

run bash "$REPO_ROOT/tools/install-read-trace.sh" "$bare"
check_status "install-read-trace <bare> exits 2" 2 "$STATUS"
check_contains "install-read-trace <bare>: names it" "$OUT" "not a git repo: $bare"
run bash "$REPO_ROOT/tools/install-pre-pr-gate.sh" "$bare"
check_status "install-pre-pr-gate <bare> exits 2" 2 "$STATUS"
check_contains "install-pre-pr-gate <bare>: names it" "$OUT" "not a git repo: $bare"

run bash "$REPO_ROOT/tools/self/prose-drift.sh" "$bare"
check_status "prose-drift <bare> exits 2" 2 "$STATUS"
check_eq "prose-drift <bare>: unchanged wording" "prose-drift.sh: not a git repository: $bare" "$OUT"

run_in "$bare" bash "$REPO_ROOT/tools/drydock/inventory.sh"
check_status "drydock inventory in a bare repo exits 3" 3 "$STATUS"
check_contains "drydock inventory in a bare repo: unchanged wording" "$OUT" "drydock inventory: not a git repository (run this inside the tree you are auditing)"
run_in "$bare" bash "$REPO_ROOT/tools/delta-audit/derive.sh" a b
check_status "delta-audit derive in a bare repo exits 3" 3 "$STATUS"
check_contains "delta-audit derive in a bare repo: unchanged wording" "$OUT" "not a git repository (run this inside the repo whose range you are deriving)"
run_in "$bare" bash "$REPO_ROOT/tools/audit-packet/export.sh" --vendor v --files /dev/null
check_status "audit-packet export in a bare repo exits 3" 3 "$STATUS"
check_contains "audit-packet export in a bare repo: unchanged wording" "$OUT" "not a git repository (run this inside the tree you are exporting from)"

run_in "$nongit" bash "$REPO_ROOT/tools/branch-cleanup.sh"
check_status "branch-cleanup outside any repo exits 2" 2 "$STATUS"
check_contains "branch-cleanup outside any repo: unchanged wording" "$OUT" "branch-cleanup: not a git repository"
run_in "$bare" bash "$REPO_ROOT/tools/branch-cleanup.sh"
check_absent "branch-cleanup in a bare repo is NOT refused (it works from the git dir; unchanged)" "$OUT" "not a git repository"

run bash "$REPO_ROOT/tools/doctor.sh" "$bare"
check_contains "doctor on a bare repo reports G-GIT-MISSING (no work tree)" "$OUT" "G-GIT-MISSING"
run bash "$REPO_ROOT/tools/doctor.sh" "$wt"
check_absent "doctor on a work tree does not" "$OUT" "G-GIT-MISSING"

# --- source level: every tool that gates on a checkout goes through the lib ---------------------------------
for t in tools/lib/repo-arg-guard.sh tools/branch-cleanup.sh tools/doctor.sh tools/audit-packet/export.sh \
         tools/delta-audit/derive.sh tools/drydock/inventory.sh tools/self/prose-drift.sh; do
  pin "$t sources tools/lib/require-git-repo.sh" "$REPO_ROOT/$t" 'require-git-repo.sh"' \
    "$t must source tools/lib/require-git-repo.sh, not re-derive the checkout check"
done
# No tool re-grows an exit-status-only `rev-parse --is-inside-work-tree` gate. The allowlist is the lib itself
# (the one reader of git's output) and tools/install-secret-guard.sh, which ships standalone: its inline copy
# (_isg_require_work_tree) is pinned below, and its machine-read probe asks "does git find ANY enclosing
# repository" on purpose. Everything else under tools/ named in dir #591 must be free of the pattern.
stray=""
for t in tools/branch-cleanup.sh tools/doctor.sh tools/audit-packet/export.sh tools/delta-audit/derive.sh \
         tools/drydock/inventory.sh tools/self/prose-drift.sh tools/install-read-trace.sh \
         tools/install-pre-pr-gate.sh tools/lib/repo-arg-guard.sh; do
  # a variable, not a pipe: `grep -q` closing early would SIGPIPE its producer under pipefail (dir #280)
  code="$(grep -v '^[[:space:]]*#' "$REPO_ROOT/$t" || true)"
  if grep -q 'rev-parse --is-inside-work-tree' <<< "$code"; then stray="$stray $t"; fi
done
if [ -z "$stray" ]; then pass "no named tool hand-rolls an exit-status-only --is-inside-work-tree gate"
else fail "no named tool hand-rolls an exit-status-only --is-inside-work-tree gate" "still present in:$stray"; fi
isg="$REPO_ROOT/tools/install-secret-guard.sh"
check_eq "install-secret-guard: both gates call the inline helper" 2 "$(grep -c '^ *_isg_require_work_tree "' "$isg")"
check_eq "install-secret-guard: the helper reads git's output, not just the exit status" 1 \
  "$(grep -c 'out="\$(git -C "\$1" rev-parse --is-inside-work-tree 2>/dev/null)" || out=""' "$isg")"

summary
