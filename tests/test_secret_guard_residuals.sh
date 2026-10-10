#!/usr/bin/env bash
# install-secret-guard.sh — the residuals of dir #717's conditional-include walk and the machine-wide reads (dir #743):
#   (2/10) a file reached under a second, independent condition is reported under BOTH conditions
#   (3)    a dangling symlink into an unsearchable dir is not "missing" (an edge fail-open, §4 condition 1)
#   (4)    a bare `path = ~` is git's $HOME, not a relative file
#   (6)    _isg_absent_for_sure terminates on a slash-less path
#   (7)    the "cannot tell whether" wording, where git did not run
#   (D1-6) a command-scope core.hooksPath (`git -c`, GIT_CONFIG_COUNT) is not the machine-wide setting, so it is
#          never recorded as the displaced one and never written into ~/.gitconfig by --uninstall
#   (M1)   a corrupt git config is refused, not read as "unset" behind `|| true`
#   (M2)   a core.hooksPath set twice in the global file is refused before any write (git exits 5 on the write)
# The include-path expansion (`~`, `~user`, `%(prefix)`) is git's own: one `git config --type=path --default` call.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

isg="$REPO_ROOT/tools/install-secret-guard.sh"
kh_rel=".config/git/keel-hooks"

# One isolated HOME per shape; GIT_CONFIG_SYSTEM points inside it (tests/test_guard_hooks_dir.sh's plumbing).
mk_home() { H="$SANDBOX/fx-$1"; mkdir -p "$H/work" "$H/work-hooks"; : > "$H/system.cfg"; }
genv() { env "HOME=$H" "GIT_CONFIG_GLOBAL=$H/.gitconfig" "GIT_CONFIG_SYSTEM=$H/system.cfg" "$@"; }
# run_bounded CMD… — `run`, in the background with a bounded wait: a loop fails here instead of hanging the suite.
run_bounded() {
  local out="$SANDBOX/bounded.out" pid waited=0
  "$@" >"$out" 2>&1 </dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 30 ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    STATUS=124; OUT="(still running after 30 s — killed)"; return 0
  fi
  STATUS=0; wait "$pid" || STATUS=$?
  OUT="$(cat "$out")"
}
incomplete="could not read every conditional [includeIf] include"
cfg_rc() { local rc=0; git config --file "$1" --get "$2" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }

# --- (2)/(10): an alias reached under a second, independent condition is reported under both ------------------
mk_home alias2
printf '[includeIf "gitdir:~/work/"]\n\tpath = work.cfg\n[includeIf "gitdir:~/other/"]\n\tpath = alias.cfg\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"
ln -s "$H/work.cfg" "$H/alias.cfg"
run genv "$isg" --where --global
check_contains "walk (2): the alias under a second condition counts: conditional=2" "$OUT" "conditional=2"
run genv "$isg" --global
check_status "walk (2): --global over it → refused (exit 3)" 3 "$STATUS"
check_contains "walk (2): the refusal names the first condition" "$OUT" "gitdir:~/work/"
check_contains "walk (2): ...and the second" "$OUT" "gitdir:~/other/"
run genv "$isg" --global --force
check_status "walk (2): --force wires anyway → exit 0" 0 "$STATUS"
check_contains "walk (2): the NOTE names the first condition" "$OUT" "NOTE — in trees matching gitdir:~/work/"
check_contains "walk (10): the NOTE names the second condition too" "$OUT" "NOTE — in trees matching gitdir:~/other/"

# the aliased file's own nested includes are walked under the second condition too
mk_home alias-nested
printf '[includeIf "gitdir:~/a/"]\n\tpath = f.cfg\n[includeIf "gitdir:~/b/"]\n\tpath = alias.cfg\n' > "$H/.gitconfig"
printf '[includeIf "gitdir:~/c/"]\n\tpath = g.cfg\n' > "$H/f.cfg"
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/g.cfg"
ln -s "$H/f.cfg" "$H/alias.cfg"
run genv "$isg" --where --global
check_contains "walk (2): a nested include under the aliased file counts under BOTH conditions: conditional=2" "$OUT" "conditional=2"
run genv "$isg" --global --force
check_contains "walk (2): ...the NOTE names the nested condition under the first route" "$OUT" "gitdir:~/a/ and gitdir:~/c/"
check_contains "walk (2): ...and under the second" "$OUT" "gitdir:~/b/ and gitdir:~/c/"

# --- (3)/(7): a dangling symlink into an unsearchable dir is not "missing" -------------------------------------
mk_home dangle; mkdir -p "$H/locked"
printf '[includeIf "gitdir:~/work/"]\n\tpath = link.cfg\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/locked/real.cfg"
ln -s "$H/locked/real.cfg" "$H/link.cfg"
chmod 000 "$H/locked"
run genv "$isg" --global
check_status "walk (3): a link into an unsearchable dir → refused (exit 3), not skipped as missing" 3 "$STATUS"
if [ "$(id -u 2>/dev/null)" != 0 ]; then   # root searches anything (CLAUDE.md Linux-leg trap 2)
  check_contains "walk (3): ...as an incomplete walk" "$OUT" "$incomplete"
  check_contains "walk (7): ...in words that do not blame a git that never ran" "$OUT" "cannot tell whether $H/link.cfg exists"
  check_absent "walk (7): ...no 'git config failed on' for a path git never read" "$OUT" "git config failed on $H/link.cfg (a directory"
fi
chmod 700 "$H/locked"
# control: a dangling link whose target is truly absent is skipped, as git skips it
mk_home dangle-ctl
printf '[includeIf "gitdir:~/work/"]\n\tpath = link.cfg\n' > "$H/.gitconfig"
ln -s "$H/nowhere.cfg" "$H/link.cfg"
run genv "$isg" --global
check_status "walk (3) control: a link to a truly absent file is skipped → exit 0" 0 "$STATUS"

# --- (4): a bare `path = ~` is git's $HOME ---------------------------------------------------------------------
mk_home tilde
printf '[includeIf "gitdir:~/work/"]\n\tpath = ~\n' > "$H/.gitconfig"
run genv "$isg" --global
check_status "walk (4): a bare 'path = ~' → refused (exit 3), not skipped as a missing relative file" 3 "$STATUS"
check_contains "walk (4): ...as an incomplete walk" "$OUT" "$incomplete"

# git expands the include path in isolation: a key of the same name in the ambient config must not steer it
mk_home isolated
printf '[includeIf "gitdir:~/work/"]\n\tpath = ~/work.cfg\n[isg "unset"]\n\tname = /nowhere/evil.cfg\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"
run genv "$isg" --global
check_status "walk (4): an ambient isg.unset.name does not steer the expansion → still refused (exit 3)" 3 "$STATUS"
check_contains "walk (4): ...naming the real target" "$OUT" "$H/work.cfg"

# --- (6): _isg_absent_for_sure terminates on a slash-less path ------------------------------------------------------
fn="$SANDBOX/absent-fn.sh"
sed -n '/^_isg_absent_for_sure() {/,/^}/p' "$isg" > "$fn"
check_ne "walk (6) setup: the function was extracted" "" "$(cat "$fn")"
run_bounded bash -c '. "$1"; _isg_absent_for_sure noslash' _ "$fn"
check_ne "walk (6): a slash-less path terminates (not the 30 s kill)" 124 "$STATUS"
check_eq "walk (6): ...and is not claimed absent for sure" 1 "$STATUS"

# --- D1-6: a command-scope core.hooksPath is not the machine-wide one --------------------------------------------
mk_home cmdscope
n=${GIT_CONFIG_COUNT:-0}
cmd_env=("GIT_CONFIG_KEY_$n=core.hooksPath" "GIT_CONFIG_VALUE_$n=$H/cmd-hooks" "GIT_CONFIG_COUNT=$((n + 1))")
run genv "${cmd_env[@]}" "$isg" --where --global
check_contains "D1-6: --where --global ignores a command-scope hooksPath (set=0)" "$OUT" "set=0"
run genv "${cmd_env[@]}" "$isg" --global
check_status "D1-6: --global with a command-scope hooksPath set → exit 0 (nothing machine-wide to clobber)" 0 "$STATUS"
check_eq "D1-6: ...nothing recorded as displaced" 1 "$(cfg_rc "$H/.gitconfig" keel.displacedHooksPath)"
check_eq "D1-6: ...core.hooksPath is Keel's dir" "$H/$kh_rel" "$(git config --file "$H/.gitconfig" --get core.hooksPath || true)"
mk_home cmdscope2
run genv "${cmd_env[@]}" "$isg" --global --force
check_eq "D1-6: --force records nothing either" 1 "$(cfg_rc "$H/.gitconfig" keel.displacedHooksPath)"
run genv "${cmd_env[@]}" "$isg" --global --uninstall
check_status "D1-6: --uninstall → exit 0" 0 "$STATUS"
check_eq "D1-6: ...unsets core.hooksPath (never writes the command-scope value into ~/.gitconfig)" 1 "$(cfg_rc "$H/.gitconfig" core.hooksPath)"

# --- M1: a corrupt git config is refused, not read as "unset" ----------------------------------------------------
mk_home corrupt
printf '[core\n\thooksPath = x\n' > "$H/.gitconfig"
cp "$H/.gitconfig" "$H/gitconfig.before"
for fl in "" "--force"; do
  run genv "$isg" --global ${fl:+"$fl"}
  check_status "M1: --global ${fl} over a corrupt ~/.gitconfig → refused (exit 3)" 3 "$STATUS"
  check_contains "M1: ...naming the unreadable config (not a side effect of the include walk)" "$OUT" "git could not read the machine-wide config"
  check_nodir "M1: ...nothing written (no Keel hooks dir)" "$H/$kh_rel"
  check_eq "M1: ...the config is untouched" "$(cat "$H/gitconfig.before")" "$(cat "$H/.gitconfig")"
done
run genv "$isg" --global --uninstall
check_status "M1: --global --uninstall over a corrupt config → refused (exit 3)" 3 "$STATUS"
run genv "$isg" --where --global
check_contains "M1: --where --global reports the unreadable config" "$OUT" "read-error=1"

# --- M2: a core.hooksPath set twice in the global file ------------------------------------------------------------
mk_home multi
printf '[core]\n\thooksPath = %s/a\n\thooksPath = %s/b\n' "$H" "$H" > "$H/.gitconfig"
cp "$H/.gitconfig" "$H/gitconfig.before"
run genv "$isg" --global --force
check_status "M2: --force over a hooksPath set twice → refused (exit 3), not git's exit 5 after hooks were placed" 3 "$STATUS"
check_contains "M2: ...in words, not git's generic message" "$OUT" "more than once"
check_nodir "M2: ...nothing written" "$H/$kh_rel"
check_eq "M2: ...the config is untouched" "$(cat "$H/gitconfig.before")" "$(cat "$H/.gitconfig")"
printf '[core]\n\thooksPath = %s/a\n\thooksPath = %s/%s\n' "$H" "$H" "$kh_rel" > "$H/.gitconfig"
run genv "$isg" --global --uninstall
check_status "M2: --uninstall over a hooksPath set twice → refused (exit 3)" 3 "$STATUS"
check_contains "M2: ...in words" "$OUT" "more than once"

# a hooksPath set once in ~/.gitconfig and once in the XDG file is no multi-value problem: a write goes to ONE file
mk_home twofiles
mkdir -p "$H/xdg/git"; printf '[core]\n\thooksPath = %s/b\n' "$H" > "$H/xdg/git/config"; printf '[core]\n\thooksPath = %s/a\n' "$H" > "$H/.gitconfig"
run env -u GIT_CONFIG_GLOBAL "HOME=$H" "XDG_CONFIG_HOME=$H/xdg" "GIT_CONFIG_SYSTEM=$H/system.cfg" "$isg" --global --force
check_absent "M2: one value in each of two config files is not 'more than once'" "$OUT" "more than once"

summary
