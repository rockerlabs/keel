#!/usr/bin/env bash
# test_lib_git_c_guard.sh (dir #658) — tests/lib.sh's `git` function refuses an empty `-C` and any `-C`
# outside $SANDBOX/$REPO_ROOT before git runs, and summary() fails the file on a refusal whose own
# status was swallowed. Every case runs in a CHILD process sourcing the real lib.sh (the mutation run
# unsets the guard function there), observed from here: a deliberate refusal in THIS process would land
# in this file's own refused log and fail it. The child's cwd is always a throwaway repo under this
# file's $SANDBOX and its "outside" repo is too (outside the CHILD's sandbox, inside ours), so the
# mutant's unguarded writes land in fixtures, never in a real checkout — that is what makes it safe.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

probe="$SANDBOX/git-c-probe.sh"
cat > "$probe" <<'EOF'
#!/usr/bin/env bash
# $1 = the lib.sh to source, $2 = a repo outside this child's $SANDBOX, $3 = "unguarded" for the mutant.
# cwd = a throwaway repo.
. "$1" || exit 1
outer="$2"
[ "${3:-}" = unguarded ] && unset -f git
git -C "" config probe.empty yes 2>/dev/null; echo "rc-empty=$?"
git -C "$outer" config probe.outer yes 2>/dev/null; echo "rc-outer=$?"
git -C "$SANDBOX/.." rev-parse --git-dir >/dev/null 2>&1; echo "rc-dotdot=$?"
git -C "$REPO_ROOT/.." rev-parse --git-dir >/dev/null 2>&1; echo "rc-nontemp=$?"
GIT_C_GUARD_ALLOW_TMP=1 git -C "$SANDBOX/.." rev-parse --git-dir >/dev/null 2>&1; echo "rc-optin-root=$?"
GIT_C_GUARD_ALLOW_TMP=1 git -C "$outer" config probe.optin yes; echo "rc-optin=$?"
case "$(type -P git)" in /*) echo "type-P=path" ;; *) echo "type-P=other" ;; esac
new_bare_origin "" >/dev/null 2>&1
# Swallowed, the incident's shape: only summary() can still see it.
git -C "" config probe.swallowed yes >/dev/null 2>&1 || true
inner="$(new_repo)"
git -C "$inner" config probe.inner yes; echo "rc-inner=$?"
git -C "$(cd -P "$inner" && pwd -P)" rev-parse --git-dir >/dev/null; echo "rc-physical=$?"
git -C "$SANDBOX" -C "${inner##*/}" rev-parse --git-dir >/dev/null; echo "rc-relative=$?"
mkdir "$inner/x"; git -C "$inner/x/.." rev-parse --git-dir >/dev/null 2>&1; echo "rc-dotdot-inside=$?"
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null; echo "rc-repo-root=$?"
git -C "$inner" commit -q --allow-empty -m one && git -C "$inner" commit -q --allow-empty -C HEAD; echo "rc-commit-C=$?"
git >/dev/null 2>&1; echo "rc-noargs=$?"
git -C "$SANDBOX/../no-such-dir-658" status >/dev/null 2>&1; echo "rc-missing=$?"
summary >/dev/null; echo "summary-rc=$?"
EOF

# run_probe [unguarded] — a fresh cwd repo and outside repo per run; leaves them in $CWD_REPO/$OUTER_REPO.
run_probe() {
  CWD_REPO="$(new_repo)"
  OUTER_REPO="$(new_repo)"
  run_in "$CWD_REPO" bash "$probe" "$TESTS_DIR/lib.sh" "$OUTER_REPO" "${1:-}"
}

run_probe
check_contains "G1 an empty -C is refused before git runs" "$OUT" "rc-empty=97"
check_eq "G1 nothing landed in the caller's cwd repo" "" "$(git -C "$CWD_REPO" config --get probe.empty)"
check_contains "G2 a -C outside \$SANDBOX/\$REPO_ROOT is refused" "$OUT" "rc-outer=97"
check_eq "G2 nothing landed in the outside repo" "" "$(git -C "$OUTER_REPO" config --get probe.outer)"
check_contains "G3 a -C whose .. climbs out of \$SANDBOX is refused" "$OUT" "rc-dotdot=97"
check_contains "G3 a -C outside both \$SANDBOX and the temp root is refused (\$REPO_ROOT/..)" "$OUT" "rc-nontemp=97"
check_contains "G6 the temp-dir opt-in never admits the temp root itself" "$OUT" "rc-optin-root=97"
check_contains "P8 GIT_C_GUARD_ALLOW_TMP=1 admits a temp dir outside \$SANDBOX" "$OUT" "rc-optin=0"
check_eq "P8 ... and the opted-in write really landed" "yes" "$(git -C "$OUTER_REPO" config --get probe.optin)"
check_contains "P9 type -P git still prints the binary's path with the function defined" "$OUT" "type-P=path"
check_eq "G4 a lib helper handed an empty repo path (new_bare_origin \"\") wires no remote into the cwd repo" "" "$(git -C "$CWD_REPO" config --get remote.origin.url)"
check_contains "G5 a swallowed refusal still fails the file at summary()" "$OUT" "summary-rc=1"
check_eq "G5 the swallowed write did not land" "" "$(git -C "$CWD_REPO" config --get probe.swallowed)"
check_contains "P1 a -C under \$SANDBOX passes" "$OUT" "rc-inner=0"
check_contains "P2 the physical spelling of a sandbox path passes (macOS /var vs /private/var)" "$OUT" "rc-physical=0"
check_contains "P3 repeated -C compose relative to each other, as git composes them" "$OUT" "rc-relative=0"
check_contains "P4 a .. that stays inside \$SANDBOX passes" "$OUT" "rc-dotdot-inside=0"
check_contains "P5 reading \$REPO_ROOT passes" "$OUT" "rc-repo-root=0"
check_contains "P6 the scan stops at the subcommand (commit -C <rev> is not a path)" "$OUT" "rc-commit-C=0"
check_contains "P7 a bare git with zero arguments does not crash the wrapper (bash 3.2, set -u)" "$OUT" "rc-noargs=1"
check_contains "P10 a -C that does not exist reaches git, which refuses it itself (128, not 97)" "$OUT" "rc-missing=128"

# Mutation proof: the same probe with the guard function unset must turn G1/G2/G4/G5 red — the writes
# reach the fixtures and nothing fails the file. Every write still lands under our $SANDBOX.
run_probe unguarded
check_eq "M1 without the guard, an empty -C writes into the caller's cwd repo" "yes" "$(git -C "$CWD_REPO" config --get probe.empty)"
check_eq "M2 without the guard, an outside -C writes into the outside repo" "yes" "$(git -C "$OUTER_REPO" config --get probe.outer)"
check_ne "M3 without the guard, the helper wires a remote into the cwd repo" "" "$(git -C "$CWD_REPO" config --get remote.origin.url)"
check_contains "M4 without the guard, summary() passes the file" "$OUT" "summary-rc=0"

# G7 (dir #721 S8-10): the empty-`-C` clause must be the ONLY thing refusing. In the probe above the
# child's cwd is outside the child's own $SANDBOX/$REPO_ROOT, so an empty `-C` (= the caller's cwd)
# falls to the "temp dir outside $SANDBOX" clause and is refused with 97 even with the empty clause
# deleted — G1 passes for the wrong clause. The felt incident stood INSIDE the allow-list (cwd =
# $REPO_ROOT), where the empty clause is all that stands. So: a stand-in checkout whose tests/lib.sh is a
# copy of the real one (REPO_ROOT derives from lib.sh's own location), a child with cwd = that stand-in,
# and a mutant copy with the clause deleted (sed on the copy only) as the positive control that this
# fixture can tell the clause from its neighbours. Every write still lands under our $SANDBOX.
standin="$(new_repo)"
mkdir -p "$standin/tests"
cp "$TESTS_DIR/lib.sh" "$standin/tests/lib.sh"
sed '/^[[:space:]]*\[ -n "\$_gc_a" \] || { _gc_bad="an empty -C/d' "$TESTS_DIR/lib.sh" > "$standin/tests/lib-mutant.sh"
check_ne "G7 setup: the mutant copy really lacks the empty-clause line" "$(wc -l < "$TESTS_DIR/lib.sh")" "$(wc -l < "$standin/tests/lib-mutant.sh")"
probe_inside="$SANDBOX/git-c-probe-inside.sh"
cat > "$probe_inside" <<'EOF'
#!/usr/bin/env bash
# $1 = the lib.sh to source (cwd = the stand-in checkout, inside that lib's own $REPO_ROOT).
. "$1" || exit 1
git -C "" config probe.inside yes 2>/dev/null; echo "rc-inside-empty=$?"
EOF
run_in "$standin" bash "$probe_inside" "$standin/tests/lib.sh"
check_contains "G7 an empty -C is refused with cwd INSIDE \$REPO_ROOT, where only the empty clause stands" "$OUT" "rc-inside-empty=97"
check_eq "G7 nothing landed in the stand-in checkout" "" "$(git -C "$standin" config --get probe.inside)"
run_in "$standin" bash "$probe_inside" "$standin/tests/lib-mutant.sh"
check_contains "M5 with the empty clause deleted, the same probe is NOT refused (control: G7 binds that clause)" "$OUT" "rc-inside-empty=0"
check_eq "M5 ... and the write really landed in the cwd repo" "yes" "$(git -C "$standin" config --get probe.inside)"

# C1: with the function defined, `$(command -v git)` yields the word "git", not a path — a symlink farm
# or a shim's `exec` built from it breaks (felt while measuring this ticket: test_self_doctor.sh linked a
# dangling `git`; git_var_stub_dir()'s stub would `exec git` back through PATH into itself). This file
# names the shape, so it is skipped.
check_eq "C1 no test captures \$(command -v git) — use \$(type -P git)" "" \
  "$(grep -nE '\$\(command -v git[) ]' "$TESTS_DIR"/*.sh | grep -v '/test_lib_git_c_guard\.sh:')"

# C2 (dir #721 S6-12): `type -P git` is for a symlink farm or a shim's `exec` — the binary's PATH — never
# a command for fixture writes. A variable assigned from it and then used as `"$var" -C <repo> …` steps
# around the guard above (tests/test_doctor_secrets.sh once routed 16 writes that way; an empty `$d` there
# would have written into whatever repository the suite stood in). Structural, per file: collect every
# `NAME="$(type -P git)"` and flag a `$NAME -C` use. A `$NAME config --global …` under a redirected HOME
# (no -C) is a different, legitimate shape and is not matched.
# type_p_bypass FILE — `file:line` of every `-C` use of a variable assigned from `$(type -P git)` in FILE
# (also behind `local`/`export`, unquoted, braced, or after other flags such as `-c k=v`).
type_p_bypass() {
  local tf="$1" tvars tv
  tvars="$(grep -oE '(^|[[:space:];])(local |export |readonly )?[A-Za-z_][A-Za-z_0-9]*=("?)\$\(type -P git\)' "$tf" | sed -E 's/^[[:space:];]*(local |export |readonly )?([A-Za-z_0-9]+)=.*/\2/' || true)"
  for tv in $tvars; do
    grep -nE "(\\\$\\{$tv\\}|\\\$$tv([^A-Za-z0-9_]|\$))[^|;&]*[[:space:]]-C([^[:alpha:]]|\$)" "$tf" | sed "s|^|${tf##*/} ($tv): |" || true
  done
}
# The checker must be able to fail: planted files in each bypass shape are flagged, a `config --global`
# use (no -C) is not. A grep dialect that matched nothing would otherwise leave C2 green on an empty scan.
planted="$SANDBOX/c2-planted"; mkdir -p "$planted"
printf '%s\n' 'gitt="$(type -P git)"' '"$gitt" -C "$d" add f' > "$planted/plain.sh"
printf '%s\n' 'f() { local g=$(type -P git); "${g}" -c k=v -C "$1" commit; }' > "$planted/local-flags.sh"
printf '%s\n' 'export GB="$(type -P git)"' 'env X=1 "$GB" -C "$d" status' > "$planted/export.sh"
printf '%s\n' 'gitt="$(type -P git)"' 'env H=1 "$gitt" config --global core.hooksPath "$d"' > "$planted/no-C.sh"
printf '%s\n' 'g="$(type -P git)"' 'grep -n "$gitt" -C 3 f; "$gh" -C "$d" x' > "$planted/prefix.sh"
printf '%s\n' 'gitt="$(type -P git)"' '"$gitt" -C"$d" add f' > "$planted/glued.sh"
printf '%s\n' 'gitt="$(type -P git)"' 'env H=1 "$gitt" -C' '  "$d" add f' > "$planted/eol.sh"
for pf in plain local-flags export glued eol; do
  check_ne "C2 control: the checker flags the $pf bypass shape" "" "$(type_p_bypass "$planted/$pf.sh")"
done
check_eq "C2 control: a \$(type -P git) variable without -C is not flagged" "" "$(type_p_bypass "$planted/no-C.sh")"
check_eq "C2 control: a longer or different variable name (\$gitt, \$gh) is not mistaken for the short one" "" "$(type_p_bypass "$planted/prefix.sh")"
bypass=""
for tf in "$TESTS_DIR"/test_*.sh; do
  [ "$tf" = "$TESTS_DIR/test_lib_git_c_guard.sh" ] && continue
  hits="$(type_p_bypass "$tf")"
  [ -z "$hits" ] || bypass="${bypass}${hits}"$'\n'
done
check_eq "C2 no test runs git writes through a \$(type -P git) variable with -C (the guard-bypass shape)" "" "$bypass"

summary
