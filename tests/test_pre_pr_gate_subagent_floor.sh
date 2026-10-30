#!/usr/bin/env bash
# test_pre_pr_gate_subagent_floor.sh — the subagent git floor in the gate's Bash hook (dir #675, spec 674-subagent-floor).
#
# tools/pre-pr-gate.sh denies, for a SUBAGENT only (an event carrying a non-empty agent_id), a git command that would
# change the session's own repository: a verb on the mutating list (B10) whose target — found from the payload cwd, the
# cd's before it, `-C`, `--git-dir`/`GIT_DIR` and `--work-tree`/`GIT_WORK_TREE` (B11) — shares the session repository's
# git common dir. Everything the reader cannot read (a non-literal path, a script, an alias) is ALLOWED, and the Z rows
# assert that, so a later widening is a deliberate change. The hook only decides: no row runs git against the fixture.
#
# Fixture (all under $SANDBOX): the session repo R with a dirty tracked file f and a subdirectory R/d; a second worktree R2
# of R; a scratch clone X with a subdirectory X/d; links ~/rr -> R and ~/xx -> X in the sandbox HOME. The hook runs with its OWN $PWD two levels
# deep, so a build that joins a relative path against $PWD instead of the payload cwd fails the Q rows. Paths named
# gone* never exist.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

gate="$REPO_ROOT/tools/pre-pr-gate.sh"
check_file "pre-pr-gate.sh exists" "$gate"
if ! command -v jq >/dev/null 2>&1; then
  pass "jq not available — subagent-floor tests skipped (gate requires jq to parse its event)"
  summary; exit $?
fi

S="$SANDBOX/sf"; mkdir -p "$S/u/v"
R="$S/R"; R2="$S/R2"; X="$S/X"; TMP="$S/tmp"; mkdir -p "$TMP"
mkdir -p "$R"
git -C "$R" init -q
printf 'base\n' > "$R/f"
git -C "$R" add f
git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm init
printf 'dirty\n' >> "$R/f"
git -C "$R" worktree add -q "$R2" -b sf-wt2
git clone -q "$R" "$X"
mkdir -p "$X/d" "$R/d"
mkdir -p "$HOME"
ln -s "$R" "$HOME/rr"; ln -s "$X" "$HOME/xx"
NOGIT="$S/notgit"; mkdir -p "$NOGIT"

# sf_hook CWD CMD AGENT [env…] — AGENT "NONE" leaves agent_id out of the event. Sets OUT (stdout+stderr) and STATUS.
sf_hook() {
  local cwd="$1" cmd="$2" agent="$3" json
  shift 3
  if [ "$agent" = NONE ]; then
    json="$(jq -n --arg c "$cmd" --arg d "$cwd" '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}')"
  else
    json="$(jq -n --arg c "$cmd" --arg d "$cwd" --arg a "$agent" '{tool_name:"Bash", cwd:$d, agent_id:$a, tool_input:{command:$c}}')"
  fi
  OUT="$(cd "$S/u/v" && printf '%s' "$json" | env "$@" bash "$gate" 2>&1)"
  STATUS=$?
}
needle='Keel subagent floor (dir #675)'
# sf_deny LABEL CMD [CWD] — a subagent's CMD is denied with the floor reason. sf_allow — empty stdout, exit 0.
sf_deny() {
  sf_hook "${3:-$R}" "$2" a1
  case "$OUT" in
    *'"permissionDecision":"deny"'*"$needle"*) pass "deny: $1" ;;
    *) fail "deny: $1" "expected the subagent-floor deny for: $2 — got: ${OUT:-<empty>}" ;;
  esac
}
sf_allow() {
  sf_hook "${3:-$R}" "$2" a1
  if [ -z "$OUT" ] && [ "$STATUS" = 0 ]; then pass "allow: $1"; else fail "allow: $1" "expected an empty allow for: $2 — got: $STATUS ${OUT:-<empty>}"; fi
}

# --- P1–P2, the parent: no agent_id (or an empty one) is exactly today's gate ----------------------------------------
sf_hook "$R" 'git checkout -- f' NONE
check_eq "P1: the parent's git checkout is untouched" "" "$OUT"
sf_hook "$R" 'git checkout -- f' ""
check_eq "P2: a present but EMPTY agent_id is the parent" "" "$OUT"

# P3–P4: only a non-empty STRING agent_id marks a subagent (a number or null is not one).
for aj in 7 null; do
  json="$(jq -n --arg c 'git checkout -- f' --arg d "$R" --argjson a "$aj" '{tool_name:"Bash", cwd:$d, agent_id:$a, tool_input:{command:$c}}')"
  OUT="$(cd "$S/u/v" && printf '%s' "$json" | bash "$gate" 2>&1)"
  check_eq "P3: an agent_id of $aj is not a subagent" "" "$OUT"
done

# --- R1–R8, reads in R ------------------------------------------------------------------------------------------------
n=0
for c in 'git status' 'git diff HEAD' 'git log -1' 'git show HEAD' 'git blame f' 'git fetch' 'git stash list' 'git stash show'; do
  n=$((n + 1)); sf_allow "R$n: $c" "$c"
done

# --- D1, every V-mut verb (B10) in R: one list, so a verb dropped from the build fails its own row ---------------------
VMUT=(checkout switch restore reset clean commit add rm mv rebase merge cherry-pick revert am pull push update-ref
      update-index read-tree checkout-index gc prune repack filter-branch filter-repo replace sparse-checkout
      maintenance stage merge-file fast-import pack-refs init)
for v in "${VMUT[@]}"; do
  sf_deny "D1: git $v" "git $v"
  [ "$v" = init ] || sf_deny "D1: git $v f" "git $v f"
done

# --- FT1–FT2, git fetch (dir #793): a refspec with a local :dst (not refs/remotes/*) writes a ref of the session repository ---
for c in 'git fetch origin +main:b' 'git fetch . a:b' 'git fetch --depth 1 origin a:b' 'git fetch -j 4 origin a:b' \
         'git fetch origin +refs/heads/*:refs/heads/*' 'git fetch --filter blob:none origin a:b' 'git fetch origin -- a:b' 'git fetch origin :b' \
         'git fetch --dep 1 origin a:b' 'git fetch --server-option x origin a:b'; do
  sf_deny "FT1: $c" "$c"
done
for c in 'git fetch' 'git fetch origin' 'git fetch origin main' 'git fetch origin refs/heads/*:refs/remotes/origin/*' 'git fetch git@example.com:r.git' \
         'git fetch origin --filter blob:none' 'git fetch --depth 1 origin main' 'git fetch --all' 'git fetch origin +main:refs/remotes/origin/main' \
         'git fetch --multiple git@example.com:a/x.git git@example.com:a/y.git' 'git fetch --dep 1 origin main'; do
  sf_allow "FT2: $c" "$c"
done

# --- SH1, a git older than 2.31 rejects --path-format: a shim stands in for it (exit 129) — the floor must still hold -------
SHIM="$S/shim"; mkdir -p "$SHIM"
REAL_GIT="$(type -P git)"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "--path-format=absolute" ] && exit 129; done\nexec "%s" "$@"\n' "$REAL_GIT" > "$SHIM/git"
chmod +x "$SHIM/git"
for c in 'git commit -m x' 'git push origin main' 'git stash'; do
  sf_hook "$R" "$c" a1 "PATH=$SHIM:$PATH"
  case "$OUT" in
    *'"permissionDecision":"deny"'*"$needle"*) pass "SH1: with a git that rejects --path-format, the floor denies: $c" ;;
    *) fail "SH1: with a git that rejects --path-format, the floor denies: $c" "got: ${OUT:-<empty>}" ;;
  esac
done
sf_hook "$R" "git --git-dir=$R2/.git --work-tree=$X checkout -- f" a1 "PATH=$SHIM:$PATH"
check_contains "SH1: ...the --git-dir form too (a linked worktree's .git file)" "$OUT" "$needle"
mkdir -p "$S/cdp/.git"
sf_hook "$R" "git -C $R2 checkout -- f" a1 "PATH=$SHIM:$PATH" "CDPATH=$S/cdp"
check_contains "SH1: ...with CDPATH set (the relative common dir must not be searched through it): a second worktree is still the session repository" "$OUT" "$needle"
sf_hook "$NOGIT" 'git commit -m x' a1 "PATH=$SHIM:$PATH"
check_eq "SH2: ...and a payload cwd that is no repository stays allowed under the same git" "" "$OUT"

# --- D2–D14, V-sub write forms in R, each paired with its read form -----------------------------------------------------
for c in 'git stash' 'git stash -u' 'git stash push -- f' 'git stash pop' "git worktree add ../w" "git worktree remove --force $R2" \
         'git branch new' 'git branch --unset-upstream' 'git tag t' 'git tag -d t' 'git notes add -m x' 'git bisect reset' \
         'git submodule update --force' "git apply $TMP/p.diff" "git apply --stat --apply $TMP/p.diff" 'git config --unset core.bare' \
         'git config core.x y' 'git symbolic-ref HEAD refs/heads/t' 'git reflog expire --expire=now --all' \
         'git remote add o https://example.com/r.git' "git merge-file f $TMP/b $TMP/o" 'git branch -D x' 'git branch -dr x' \
         'git tag -a t -m x' 'git remote rename a b' 'git reflog delete HEAD@{0}'; do
  sf_deny "D2: $c" "$c"
done
for c in 'git stash list' 'git worktree list' 'git branch --merged HEAD' 'git branch --contains HEAD' 'git branch' 'git branch -a' 'git branch -vv' \
         'git tag -l' 'git tag' 'git tag --sort version:refname' 'git tag --contains HEAD' 'git notes' 'git notes show' 'git bisect log' \
         'git submodule status' 'git submodule' "git apply --check $TMP/p.diff" 'git config get core.bare' \
         'git config --type bool core.bare' 'git config core.bare' 'git config --get-all core.x' 'git config --list' \
         'git symbolic-ref HEAD' 'git reflog HEAD' 'git reflog' 'git remote -v' 'git remote show origin' 'git remote get-url origin' 'git remote'; do
  sf_allow "D2 read: $c" "$c"
done

# --- T1–T14, deny through a target --------------------------------------------------------------------------------------
sf_deny "T1: git -C <other worktree of the same repo>" "git -C $R2 checkout -- f"
sf_deny "T2: cd X && cd R && git stash" "cd $X && cd $R && git stash"
sf_deny "T3: global options before the verb" 'git --no-pager -c x=y checkout -- f'
sf_deny "T4: /usr/bin/git" '/usr/bin/git checkout -- f'
sf_deny "T5: command git" 'command git checkout -- f'
sf_deny "T6: env git" 'env git stash'
sf_deny "T7: a quoted verb" 'git "stash"'
sf_deny "T8: a quoted -C" "git \"-C\" $R2 checkout -- f"
sf_deny "T9: an unlisted global option is one word" 'git --attr-source=HEAD checkout -- f'
sf_deny "T10: the -C chain applies in order" "git -C $S -C $R checkout -- f"
sf_deny "T11: an absolute -C resolves under an UNKNOWN directory set" 'cd "$S" && git -C '"$R"' checkout -- f'
sf_deny "T12: a group's cd does not leak out of it (literal)" "(cd $X && git init); git checkout -- f"
sf_deny "T13: a group's UNKNOWN cd does not leak out of it" '(cd "$S"); git checkout -- f'
sf_deny "T14: pushd moves the directory set" "cd $X && pushd $R && git checkout -- f"

# --- W1–W6, through the git dir / work tree -------------------------------------------------------------------------------
sf_deny "W1: --work-tree=X in the session repo (the discovered git dir)" "git --work-tree=$X reset --hard"
sf_deny "W2: a scratch git dir with the session repo as work tree" "git --git-dir=$X/.git --work-tree=$R checkout -- f"
sf_deny "W3: GIT_DIR=R/.git" "GIT_DIR=$R/.git git reset --hard"
sf_deny "W4: GIT_DIR after a cd elsewhere" "cd $X && GIT_DIR=$R/.git git reset --hard"
sf_deny "W5: GIT_DIR=X/.git GIT_WORK_TREE=R" "GIT_DIR=$X/.git GIT_WORK_TREE=$R git checkout -- f"
sf_deny "W6: --git-dir as a separate word" "git --git-dir $R/.git checkout -- f"

# --- N1–N8, found by review: a git dir with no work tree, a gitfile, a separate-word option value, builtin cd, read forms ---
sf_deny "N1: --git-dir=<scratch> with no work tree named leaves the work tree at the cwd (the session repo)" "git --git-dir=$X/.git reset --hard"
sf_deny "N2: ...the same through GIT_DIR=<scratch>" "GIT_DIR=$X/.git git clean -fd"
sf_allow "N3: ...but a scratch git dir used where the cwd is no repository is nothing to protect" "git --git-dir=$X/.git reset --hard" "$NOGIT"
sf_deny "N4: a linked worktree's .git is a FILE, and --git-dir accepts it (the work tree named elsewhere)" "git --git-dir=$R2/.git --work-tree=$X checkout -- f"
sf_deny "N5: --attr-source takes its value as a separate word" 'git --attr-source HEAD checkout -- f'
sf_allow "N6: builtin cd is a cd" "builtin cd $X && git commit --allow-empty -m x"
sf_allow "N7: git tag -v is a read" 'git tag -v v1'
sf_allow "N8: git config --comment takes a value (it is not a second positional)" 'git config --comment c user.name'

# --- F1–F2, config -f -----------------------------------------------------------------------------------------------------
sf_deny "F1: config -f into the session repo's own config" "git -C $X config -f $R/.git/config core.hooksPath /dev/null"
sf_allow "F2: config -f to a file outside any repository" "git config -f $TMP/x.cfg a.b c"

# --- M1–M5, missing cd targets (the dir #669 shape) -----------------------------------------------------------------------
sf_deny "M1: cd <missing>; git checkout" "cd $S/gone; git checkout -- f"
sf_deny "M2: cd <missing> && git checkout" "cd $S/gone && git checkout -- f"
sf_deny "M3: the kept member lasts past the next segment" "cd $S/gone; echo x; git checkout -- f"
sf_deny "M4: two missing cds make a set, not two variables" "cd $S/gone; cd $S/gone2; git checkout -- f"
sf_deny "M5a: mkdir X && cd X && git init (the accepted cost)" "mkdir $S/n && cd $S/n && git init"
sf_deny "M5b: git clone R <tmp>/c && cd <tmp>/c && git commit (the accepted cost)" "git clone $R $S/n2 && cd $S/n2 && git commit --allow-empty -m x"

# --- Q1–Q8, relative and ~ paths ---------------------------------------------------------------------------------------
sf_deny "Q1: git -C ../R2" 'git -C ../R2 checkout -- f'
sf_deny "Q2: cd ../R2" 'cd ../R2 && git stash'
# The protected repository is the one the PAYLOAD cwd belongs to (B9), so these rows use a payload cwd inside R, two levels
# below the sandbox like X/d (the spec text puts it in X/d, which would make X the session repository).
sf_deny "Q3: payload cwd R/d, cd ../../R2" 'cd ../../R2 && git stash' "$R/d"
sf_deny "Q4: payload cwd R/d, git -C ../../R2" 'git -C ../../R2 checkout -- f' "$R/d"
sf_deny "Q5: payload cwd R/d, git -C .. (the cwd's parent is R; the hook's own PWD is not a repository)" 'git -C .. checkout -- f' "$R/d"
sf_deny "S1: the session repository follows the payload cwd: cwd X/d protects X" 'git -C .. stash' "$X/d"
sf_allow "S2: ...so R is just another repository then" "git -C $R stash" "$X/d"
sf_deny "Q6: cd ~/rr" "cd $X && cd ~/rr && git stash"
sf_deny "Q7: a QUOTED tilde is a plain character (R stays a member)" 'cd "~/xx" && git checkout -- f'
rm -f "$S/PWNED2"
sf_hook "$R" "git -C ~/'\$(touch $S/PWNED2)' checkout -- f" a1
check_nofile "Q8: a command substitution inside a tilde path is never run (no eval)" "$S/PWNED2"

# --- Y1–Y11, one row per matcher clause the mutation list (tests/mutants/pre-pr-gate-subagent.tsv, dir #790) found unpinned ---------
sf_allow "Y1: GIT_DIR and GIT_WORK_TREE both name the scratch clone (the work tree is the assignment's, not the cwd's)" "GIT_DIR=$X/.git GIT_WORK_TREE=$X git commit --allow-empty -m x"
sf_allow "Y2: every -C joins the chain: -C X -C d is X/d" "git -C $X -C d commit --allow-empty -m x"
sf_deny "Y3: --config-env takes its value as a separate word" 'git --config-env foo=BAR checkout -- f'
sf_deny "Y4: --work-tree as a separate word" "git --work-tree $X reset --hard"
sf_allow "Y5: a glob in a cd target is unknown, not a missing literal" "cd $S/X*; git stash"
sf_deny "Y6: a bare ~ is the home directory" 'cd ~ && git -C rr stash'
sf_allow "Y7: cd - is unknown" 'cd -; git stash'
sf_allow "Y8: pushd +N is unknown" 'pushd +1 && git stash'
sf_allow "Y9: cd -P <dir> skips the option" "cd -P $X && git stash"
sf_deny "Y10: a directory init names does not outlive its segment" "git init $TMP/n5; git commit --allow-empty -m x"
sf_allow "Y11: a command word with an expansion is not read as git (its path is unknown)" 'H=/usr/bin; $H/git checkout -- f'

# --- G1–G2, the PR rule is untouched ---------------------------------------------------------------------------------------
sf_hook "$R" 'gh pr create --fill' a1
check_contains "G1: a subagent's gh pr create is denied by today's PR rule" "$OUT" 'Pre-PR gate'
check_absent "G1: ...not by the floor" "$OUT" "$needle"
sf_hook "$R" 'gh pr create --fill' a1 KEEL_SUBAGENT_GIT_FLOOR=off
check_contains "G2: the kill switch reaches only the floor — the PR deny stays" "$OUT" 'Pre-PR gate'

# --- O1–O11, allowed outside the session repository ------------------------------------------------------------------------
sf_allow "O1: git -C X commit" "git -C $X commit --allow-empty -m x"
sf_allow "O2: cd X && git stash" "cd $X && git stash"
sf_allow "O3: a brace group's cd carries on" "{ cd $X; }; git stash"
sf_allow "O4: git clone" "git clone $R $TMP/c"
sf_allow "O5: machine-global config is out of scope" 'git config --global user.name x'
sf_allow "O6: git init <tmp dir>" "git init $TMP/n3"
sf_allow "O7: a scratch git dir and work tree" "git --git-dir=$X/.git --work-tree=$X commit --allow-empty -m x"
sf_allow "O8: mkdir n4 && git -C n4 init" "mkdir $S/n4 && git -C $S/n4 init"
sf_allow "O9: cd X && cd ~/xx" "cd $X && cd ~/xx && git stash"
sf_allow "O10: payload cwd R/d, git -C ../../X stash (a scratch clone)" 'git -C ../../X stash' "$R/d"
sf_allow "O11: cd X/d && cd .. && git stash" "cd $X/d && cd .. && git stash"

# --- Z1–Z9, the stated blind spots (B13): ALLOW, asserted so a later widening is a deliberate change ---------------------
sf_allow "Z1: a non-literal -C" 'git -C "$X" checkout -- f'
sf_allow "Z2: sh -c" "sh -c 'git stash'"
sf_allow "Z3: rm" 'rm f.bak'
sf_allow "Z4: an alias" 'git co -- f'
sf_allow "Z5: a non-literal cd" 'cd "$R" && git stash'
sf_allow "Z6: a glob path" 'git -C R* checkout -- f'
sf_allow "Z7: timeout is not a wrapper the reader skips" 'timeout 5 git stash'
sf_allow "Z8: cd -" "cd $X; cd -; git stash"
sf_allow "Z10: a cd that may not run (&&, ||, &) is replayed as if it ran (B13)" "false && cd $X; git stash"
sf_allow "Z11: a remote-targeted write: the push runs in X, its target R is a plain argument (B13)" "git -C $X push $R main"
sf_allow "Z9: a script file that runs git (residual, B13)" "bash $TMP/probe.sh"

# --- H1–H2, the matcher adds a deny and changes nothing else ---------------------------------------------------------------
n=0
for c in 'gh pr create --fill' 'gh pr view 1' 'gh api repos/o/r/pulls -f title=t -f head=h' 'gh issue list' 'git status' 'git push origin main' \
         'git log -1; gh pr create --head feat --fill' 'echo hi && gh pr create --fill'; do
  n=$((n + 1))
  sf_hook "$R" "$c" NONE; parent_out="$OUT"
  sf_hook "$R" "$c" a1 KEEL_SUBAGENT_GIT_FLOOR=off; off_out="$OUT"
  check_eq "H1.$n: the kill switch makes a subagent's event read exactly as the parent's: $c" "$parent_out" "$off_out"
done
sf_hook "$R" 'git push --no-verify origin main' a1
check_contains "H2: a subagent's git push --no-verify in R gets the floor deny" "$OUT" "$needle"
sf_hook "$R" 'git push --no-verify origin main' NONE
check_contains "H2: the same push without agent_id keeps today's push-bypass deny" "$OUT" 'secret-guard'
check_absent "H2: ...and not the floor's" "$OUT" "$needle"

# --- J1, command text is never executed ------------------------------------------------------------------------------------
rm -f "$S/PWNED"
sf_hook "$R" "git -C '\$(touch $S/PWNED)' checkout -- f" a1
check_nofile "J1: a command substitution in a -C path is never run" "$S/PWNED"

# --- E1–E2 ---------------------------------------------------------------------------------------------------------------------
sf_hook "$R" 'git checkout -- f' a1 KEEL_SUBAGENT_GIT_FLOOR=off
check_eq "E1: KEEL_SUBAGENT_GIT_FLOOR=off allows" "" "$OUT"
sf_allow "E2: a payload cwd that is not a repository" 'git checkout -- f' "$NOGIT"

# --- the deny itself: reason, the log event, and nothing run ---------------------------------------------------------------
sf_hook "$R" 'git -C '"$R2"' stash pop' a1
check_contains "the deny names the verb and its subcommand" "$OUT" "'git stash pop'"
check_contains "the deny names the session repository" "$OUT" "$(cd "$R" && pwd -P)/.git"
check_contains "the deny tells a subagent what to do instead" "$OUT" "work only through 'git -C <your clone>'"
check_eq "the fixture's dirty file is untouched (the hook only decides)" "dirty" "$(tail -n 1 "$R/f")"

summary
