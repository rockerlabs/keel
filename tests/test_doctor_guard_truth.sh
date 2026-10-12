#!/usr/bin/env bash
# doctor — the guard checks tell the truth (dir #747), each pinned red-then-green:
#   D1-3  the guard is OK only when every hook Keel ships is there: Keel's pre-push absent or not executable beside a
#         working pre-commit used to read "OK" (a commit made with hooks bypassed then reached the remote); the same
#         for a secret-scan.sh ABSENT beside Keel's hooks. A user's own hooks dir keeps its old bar.
#   S3-1  the env-file floor's prune list (build out dist vendor target …) applies BELOW the audited root, never to it
#   S3-2  --install checks every lib install.sh / uninstall.sh REQUIRE, safe-write.sh and artifact-cksum.sh included
#   S3-5  an EMPTY core.hooksPath: the warning names it, and its advice clears it (the old advice was refused)
#   S3-6/S3-7  the header names what the code says; the "state unknown" arm is pinned by its own text
#   env   the floor's name set: <name>.env.<ext> backups and upper-case variants (and upper-case TEMPLATE words are
#         still templates) on a case-sensitive file system
#   hw    a half-wired guard's advice follows whose dir it is: Keel's own dir → --global, a vendored copy → re-vendor,
#         a user's global/system hooks dir → copy by hand
#   wt    a WORKTREE-scope hooksPath outranks --local, so the advice for it says --worktree
# Fixture file names that look like env files are written by this script, never typed in a command line.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doctor="$REPO_ROOT/tools/doctor.sh"
isg="$REPO_ROOT/tools/install-secret-guard.sh"
kh_rel=".config/git/keel-hooks"

mk_home() { H="$SANDBOX/fx-$1"; mkdir -p "$H/claude"; : > "$H/system.cfg"; }
genv() { env "HOME=$H" "GIT_CONFIG_GLOBAL=$H/.gitconfig" "GIT_CONFIG_SYSTEM=$H/system.cfg" "$@"; }
mk_repo() { local r; r="$(new_repo)"; mkdir -p "$r/.git/hooks"; printf '%s' "$r"; }
id_line() { printf '%s\n' "$OUT" | grep -F "[$1]" || true; }
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-placeholder}" > "$1"; }

# --- D1-3, machine-wide (--install) --------------------------------------------------------------------------------
mk_home d13m
run genv "$isg" --global
check_status "D1-3 setup: wire Keel's machine-global guard" 0 "$STATUS"
kdir="$H/$kh_rel"
run genv "$doctor" --install "$H/claude"
check_contains "D1-3 control: both hooks intact → the OK line" "$OUT" "OK   secret-guard: machine-global"
mv "$kdir/pre-push" "$kdir/pre-push.away"
run genv "$doctor" --install "$H/claude"
check_contains "D1-3: Keel's pre-push ABSENT beside a working pre-commit → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "D1-3: ...naming the pre-push" "$(id_line W-GUARD-UNWIRED)" "pre-push"
check_contains "D1-3: ...Keel's own dir is fixed by re-running --global" "$(id_line W-GUARD-UNWIRED)" "would reach the remote unscanned) — re-run install-secret-guard.sh --global"
check_absent "D1-3: ...and never the OK line" "$OUT" "OK   secret-guard: machine-global"
mv "$kdir/pre-push.away" "$kdir/pre-push"; chmod -x "$kdir/pre-push"
run genv "$doctor" --install "$H/claude"
check_contains "D1-3: Keel's pre-push NOT EXECUTABLE → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "D1-3: ...saying it is not executable" "$(id_line W-GUARD-UNWIRED)" "not executable"
chmod +x "$kdir/pre-push"
mv "$kdir/secret-scan.sh" "$kdir/secret-scan.sh.away"
run genv "$doctor" --install "$H/claude"
check_contains "D1-3: secret-scan.sh ABSENT beside Keel's hooks → W-GUARD-GLOBAL-STALE" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_contains "D1-3: ...naming the missing scanner" "$(id_line W-GUARD-GLOBAL-STALE)" "secret-scan.sh (missing"
mv "$kdir/secret-scan.sh.away" "$kdir/secret-scan.sh"
# a user's own hooks dir with its own pre-commit and no pre-push is the user's wiring: still OK
mk_home d13own; mkdir -p "$H/own-hooks"
printf '#!/bin/sh\nexit 0\n' > "$H/own-hooks/pre-commit"; chmod +x "$H/own-hooks/pre-commit"
printf '[core]\n\thooksPath = %s/own-hooks\n' "$H" > "$H/.gitconfig"
run genv "$doctor" --install "$H/claude"
check_contains "D1-3 control: a user's own hooks dir (no pre-push) is still wired" "$OUT" "OK   secret-guard: machine-global"

# --- D1-3, per repo --------------------------------------------------------------------------------------------------
mk_home d13r; r13="$(mk_repo)"
run genv "$isg" "$r13"
check_status "D1-3 setup: vendor into a repo" 0 "$STATUS"
run genv "$doctor" "$r13"
check_absent "D1-3 control: a complete vendored guard → no W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
mv "$r13/.git/hooks/pre-push" "$r13/.git/hooks/pre-push.away"
run genv "$doctor" "$r13"
check_contains "D1-3: a vendored guard with Keel's pre-push ABSENT → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "D1-3: ...naming the pre-push" "$(id_line W-GUARD-UNWIRED)" "pre-push"
check_contains "D1-3: ...a vendored copy is fixed by re-vendoring" "$(id_line W-GUARD-UNWIRED)" "re-vendor: install-secret-guard.sh"
mv "$r13/.git/hooks/pre-push.away" "$r13/.git/hooks/pre-push"; chmod -x "$r13/.git/hooks/pre-push"
run genv "$doctor" "$r13"
check_contains "D1-3: ...and with it NOT EXECUTABLE" "$(id_line W-GUARD-UNWIRED)" "not executable"
chmod +x "$r13/.git/hooks/pre-push"
mv "$r13/.git/hooks/secret-scan.sh" "$r13/.git/hooks/secret-scan.sh.away"
run genv "$doctor" "$r13"
check_contains "D1-3: a vendored guard with secret-scan.sh ABSENT → W-GUARD-STALE" "$(id_line W-GUARD-STALE)" "secret-scan.sh (missing"
mv "$r13/.git/hooks/secret-scan.sh.away" "$r13/.git/hooks/secret-scan.sh"

# a pre-push that is a DANGLING link is no hook at all (git skips it): half wired, not OK
mk_home dl; r_dl="$(mk_repo)"
run genv "$isg" "$r_dl"
check_status "D1-3 setup: vendor into a repo" 0 "$STATUS"
mv "$r_dl/.git/hooks/pre-push" "$r_dl/.git/hooks/pre-push.away"
ln -s "$SANDBOX/no-such-prepush-target" "$r_dl/.git/hooks/pre-push"
run genv "$doctor" "$r_dl"
check_contains "D1-3: a dangling pre-push link beside a working pre-commit → half wired" "$(id_line W-GUARD-UNWIRED)" "dangling link"
rm -f "$r_dl/.git/hooks/pre-push"
run genv "$isg" "$r_dl"
run genv "$doctor" "$r_dl"
check_absent "D1-3: ...removing the link and re-vendoring (the advice) clears the warning" "$OUT" "[W-GUARD-UNWIRED]"

# an empty hooksPath supplied by the ENVIRONMENT (git -c / GIT_CONFIG_COUNT) has no file line to remove
mk_home cmd; r_cmd="$(mk_repo)"
n_cfg=${GIT_CONFIG_COUNT:-0}   # tests/lib.sh arms entries (dir #318): append to the triple, never overwrite it
run genv "GIT_CONFIG_KEY_$n_cfg=core.hooksPath" "GIT_CONFIG_VALUE_$n_cfg=" "GIT_CONFIG_COUNT=$((n_cfg + 1))" "$doctor" "$r_cmd"
check_contains "S3-5: a command-scope empty hooksPath → W-GUARD-UNWIRED with environment advice" "$(id_line W-GUARD-UNWIRED)" "comes from this environment"

# --- S3-1: the prune list applies below the audited root -----------------------------------------------------------
for nm in build target; do   # the prune list is one name set, the fix is name-independent: two representatives
  d="$SANDBOX/proj-$nm/$nm"; mkdir -p "$d"; git init -q "$d"
  printf '# ctx\n' > "$d/CLAUDE.md"; printf '%s\n' 'CLAUDE.md' '.claude/' > "$d/.gitignore"
  put "$d/.env" "SENTINEL_S31=hunter2"
  run "$doctor" "$d"
  check_contains "S3-1: a project whose own root is named '$nm' is still scanned (untracked, unignored .env)" "$(id_line W-SECRETS-EXPOSED)" ".env"
  check_absent "S3-1: ...no file content in the output" "$OUT" "SENTINEL_S31"
done
# a pruned dir BELOW the root keeps being pruned (untracked files there stay unscanned, on purpose)
d="$SANDBOX/proj-below"; mkdir -p "$d"; git init -q "$d"; printf '# ctx\n' > "$d/CLAUDE.md"; printf '%s\n' 'CLAUDE.md' '.claude/' > "$d/.gitignore"
put "$d/build/.env"
run "$doctor" "$d"
check_absent "S3-1 control: an untracked .env under build/ below the root stays unscanned" "$OUT" "[W-SECRETS-EXPOSED]"

# --- the env-file name set -------------------------------------------------------------------------------------------
d="$SANDBOX/proj-names"; mkdir -p "$d"; git init -q "$d"; printf '# ctx\n' > "$d/CLAUDE.md"; printf '%s\n' 'CLAUDE.md' '.claude/' > "$d/.gitignore"
put "$d/prod.env.bak"; put "$d/STAGING.ENV"; put "$d/.envrc"
run "$doctor" "$d"
line="$(id_line W-SECRETS-EXPOSED)"
check_contains "env names: a <name>.env.<ext> backup is an env-shaped file" "$line" "prod.env.bak"
check_contains "env names: ...and an upper-case *.ENV" "$line" "STAGING.ENV"
check_absent "env names: ...but .envrc (direnv; committed by design, holds no values) is not" "$line" ".envrc"

# the template words are matched in any letter case too (the name set is): an upper-case template is not "exposed"
d="$SANDBOX/proj-tmpl"; mkdir -p "$d"; git init -q "$d"; printf '# ctx\n' > "$d/CLAUDE.md"; printf '%s\n' 'CLAUDE.md' '.claude/' > "$d/.gitignore"
put "$d/CONFIG.ENV.TEMPLATE"; put "$d/.Env.Sample"
run "$doctor" "$d"
check_absent "env names: an upper-case template (CONFIG.ENV.TEMPLATE, .Env.Sample) is not exposed" "$OUT" "[W-SECRETS-EXPOSED]"
put "$d/PROD.ENV"
run "$doctor" "$d"
check_contains "env names: ...while an upper-case non-template (PROD.ENV) beside them is" "$(id_line W-SECRETS-EXPOSED)" "PROD.ENV"
check_absent "env names: ...and the upper-case templates stay out of that same finding" "$(id_line W-SECRETS-EXPOSED)" "TEMPLATE"
check_absent "env names: ... (.Env.Sample too)" "$(id_line W-SECRETS-EXPOSED)" "Sample"

# --- half-wired advice follows whose dir it is ---------------------------------------------------------------------------
mk_home hw
mkdir -p "$H/own-hooks"
cp "$REPO_ROOT/tools/secret-guard/pre-commit" "$H/own-hooks/pre-commit"; chmod +x "$H/own-hooks/pre-commit"
cp "$REPO_ROOT/tools/secret-guard/secret-scan.sh" "$H/own-hooks/secret-scan.sh"; cp "$REPO_ROOT/tools/secret-guard/range-lib.sh" "$H/own-hooks/range-lib.sh"
printf '[core]\n\thooksPath = %s/own-hooks\n' "$H" > "$H/.gitconfig"
run genv "$doctor" --install "$H/claude"
check_contains "D1-3: a user's own global dir with a Keel pre-commit and no pre-push → half wired" "$(id_line W-GUARD-UNWIRED)" "half wired"
check_contains "D1-3: ...told to copy by hand — the installer writes Keel's dir, not theirs" "$(id_line W-GUARD-UNWIRED)" "by hand"
r_hw="$(mk_repo)"
run genv "$doctor" "$r_hw"
check_contains "D1-3: the per-repo audit gives the same by-hand advice for a global-scope dir" "$(id_line W-GUARD-UNWIRED)" "by hand"

# --- S3-2: every lib install.sh / uninstall.sh REQUIRE ------------------------------------------------------------------
cp_root="$SANDBOX/doctor-copy-w23"; mkdir -p "$cp_root"
for part in tools agents commands docs; do [ -e "$REPO_ROOT/$part" ] && cp -R "$REPO_ROOT/$part" "$cp_root/$part"; done
cdoc="$cp_root/tools/doctor.sh"
dah="$SANDBOX/doctor-copy-w23-home/.claude"
run "$REPO_ROOT/install.sh" --home "$dah" --no-hooks
check_status "S3-2 fixture: copy install → exit 0" 0 "$STATUS"
run "$cdoc" --install "$dah"
check_absent "S3-2 control: intact libs → no G-REQUIRED-LIB" "$OUT" "[G-REQUIRED-LIB]"
for lib in safe-write.sh artifact-cksum.sh; do
  mv "$cp_root/tools/lib/$lib" "$cp_root/tools/lib/$lib.away"
  run "$cdoc" --install "$dah"
  check_contains "S3-2: a missing tools/lib/$lib → G-REQUIRED-LIB" "$OUT" "[G-REQUIRED-LIB]"
  check_contains "S3-2: ...naming it" "$(id_line G-REQUIRED-LIB)" "$lib"
  check_eq "S3-2: ...a GAP (exit 1), not a quiet OK" 1 "$STATUS"
  mv "$cp_root/tools/lib/$lib.away" "$cp_root/tools/lib/$lib"
done
printf 'safe_write_x() {\n' > "$cp_root/tools/lib/safe-write.sh.corrupt"
cp "$cp_root/tools/lib/safe-write.sh" "$cp_root/tools/lib/safe-write.sh.orig"
cp "$cp_root/tools/lib/safe-write.sh.corrupt" "$cp_root/tools/lib/safe-write.sh"
run "$cdoc" --install "$dah"
check_contains "S3-2: a CORRUPT tools/lib/safe-write.sh → G-REQUIRED-LIB too" "$(id_line G-REQUIRED-LIB)" "safe-write.sh"
cp "$cp_root/tools/lib/safe-write.sh.orig" "$cp_root/tools/lib/safe-write.sh"

# --- S3-5: an EMPTY core.hooksPath ------------------------------------------------------------------------------------
mk_home s35m
printf '[core]\n\thooksPath =\n' > "$H/.gitconfig"
run genv "$doctor" --install "$H/claude"
check_contains "S3-5: --install over an empty global hooksPath → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "S3-5: ...naming the EMPTY value" "$(id_line W-GUARD-UNWIRED)" "EMPTY"
check_contains "S3-5: ...with advice that works (--force records the empty value)" "$(id_line W-GUARD-UNWIRED)" "--global --force"
run genv "$isg" --global --force
check_status "S3-5: following the advice (--global --force) → exit 0" 0 "$STATUS"
run genv "$doctor" --install "$H/claude"
check_absent "S3-5: ...and the warning is gone" "$OUT" "[W-GUARD-UNWIRED]"
mk_home s35r; r35="$(mk_repo)"
printf '[core]\n\thooksPath =\n' > "$H/.gitconfig"
run genv "$doctor" "$r35"
check_contains "S3-5: the per-repo audit over an empty global hooksPath names the EMPTY value" "$(id_line W-GUARD-UNWIRED)" "EMPTY"
check_absent "S3-5: ...and does not advise vendoring into the repo (inert while the empty value stands)" "$(id_line W-GUARD-UNWIRED)" "or vendor"
mk_home s35l; r35l="$(mk_repo)"
run genv "$isg" --global
git -C "$r35l" config --local core.hooksPath ""
run genv "$doctor" "$r35l"
check_contains "S3-5: an empty LOCAL hooksPath is named too" "$(id_line W-GUARD-UNWIRED)" "EMPTY"
check_contains "S3-5: ...with the unset command that clears it" "$(id_line W-GUARD-UNWIRED)" "--local --unset core.hooksPath"
git -C "$r35l" config --local --unset core.hooksPath
run genv "$doctor" "$r35l"
check_absent "S3-5: ...and following it clears the warning" "$OUT" "[W-GUARD-UNWIRED]"

# --- S3-7: the --install 'state unknown' arm is pinned by its own text ------------------------------------------------------
# A resolver that answers nothing: a scratch copy of the tools whose install-secret-guard.sh prints nothing.
sc="$SANDBOX/doctor-copy-w23/tools"
cp "$sc/install-secret-guard.sh" "$sc/install-secret-guard.sh.real"
printf '#!/bin/sh\nexit 0\n' > "$sc/install-secret-guard.sh"; chmod +x "$sc/install-secret-guard.sh"
mk_home s37
run genv "$cdoc" --install "$dah"
check_contains "S3-7: a silent resolver → the W-GUARD-UNWIRED line says so" "$(id_line W-GUARD-UNWIRED)" "secret-guard state unknown: the hooks-dir resolver"
cp "$sc/install-secret-guard.sh.real" "$sc/install-secret-guard.sh"; chmod +x "$sc/install-secret-guard.sh"

# --- worktree-scope advice ----------------------------------------------------------------------------------------------
mk_home wt; rwt="$(mk_repo)"; mkdir -p "$H/wh"
git -C "$rwt" config extensions.worktreeConfig true
git -C "$rwt" config --worktree core.hooksPath "$H/wh"
run genv "$doctor" "$rwt"
check_contains "wt: a worktree-scope hooksPath without a pre-commit → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "wt: ...the advice says --worktree (a --local setting is outranked by it)" "$(id_line W-GUARD-UNWIRED)" "config --worktree"
run genv "$isg" "$rwt"
check_contains "wt: the installer's inert note says --worktree too" "$OUT" "config --worktree"

# --- S6-1 (0.16.0 delta audit): an EDITED Keel hook is refused by the body-exact installer (dir #683), so every advice --
# --- arm that points at the installer names --force there; each fixture RUNS the advised command as doctor printed it --
# advised ID — the installer command (path and flags, from "install-secret-guard.sh" to its "--force") warning ID advises
advised() { printf '%s\n' "$(id_line "$1")" | grep -oE 'install-secret-guard\.sh ((\\ |[^ ])+) --force' | head -1; }
run_advised() {  # run_advised ID — run what doctor advised for warning ID against the sandbox home; sets STATUS/OUT
  local cmd; cmd="$(advised "$1")"
  if [ -z "$cmd" ]; then STATUS="no --force command advised for [$1]"; OUT="$(id_line "$1")"; return 0; fi
  eval "set -- ${cmd#install-secret-guard.sh }"   # as a shell reads the printed words: a quoted path stays one word
  run genv "$isg" "$@"
}
edit_hook() { printf '\n# my edit\n' >> "$1"; }

mk_home s61g
run genv "$isg" --global
check_status "S6-1 setup: wire the machine-global guard" 0 "$STATUS"
kd61="$H/$kh_rel"
edit_hook "$kd61/pre-commit"
run genv "$doctor" --install "$H/claude"
check_contains "S6-1: an edited Keel pre-commit (marker kept) → W-GUARD-GLOBAL-STALE" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_contains "S6-1: ...its advice names --force and the backup" "$(id_line W-GUARD-GLOBAL-STALE)" "install-secret-guard.sh --global --force"
check_contains "S6-1: ...and says why a plain re-run is refused" "$(id_line W-GUARD-GLOBAL-STALE)" "pre-keel.bak"
run_advised W-GUARD-GLOBAL-STALE
check_status "S6-1: the advised command, run as printed, succeeds (a plain re-run exits 3)" 0 "$STATUS"
check_file "S6-1: ...and saved the edited hook" "$kd61/pre-commit.pre-keel.bak"
run genv "$doctor" --install "$H/claude"
check_absent "S6-1: ...after it doctor no longer flags the stale guard" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_absent "S6-1: ...nor a half-wired one" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "S6-1: ...and reads OK" "$OUT" "OK   secret-guard: machine-global"

mk_home s61h
run genv "$isg" --global
kd61="$H/$kh_rel"
edit_hook "$kd61/pre-commit"; mv "$kd61/pre-push" "$kd61/pre-push.away"
run genv "$doctor" --install "$H/claude"
check_contains "S6-1: edited pre-commit + pre-push absent → W-GUARD-UNWIRED (half wired)" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "S6-1: ...its advice names --global --force" "$(id_line W-GUARD-UNWIRED)" "install-secret-guard.sh --global --force"
run_advised W-GUARD-UNWIRED
check_status "S6-1: the advised command succeeds" 0 "$STATUS"
run genv "$doctor" --install "$H/claude"
check_absent "S6-1: ...and clears the half-wired warning" "$OUT" "[W-GUARD-UNWIRED]"
check_absent "S6-1: ...and the stale one" "$OUT" "[W-GUARD-GLOBAL-STALE]"

mk_home s61r; r61="$(mk_repo)"
run genv "$isg" "$r61"
check_status "S6-1 setup: vendor into a repo" 0 "$STATUS"
edit_hook "$r61/.git/hooks/pre-commit"; mv "$r61/.git/hooks/pre-push" "$r61/.git/hooks/pre-push.away"
run genv "$doctor" "$r61"
check_contains "S6-1: a vendored edited pre-commit with no pre-push → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "S6-1: ...its re-vendor advice names this repo and --force" "$(id_line W-GUARD-UNWIRED)" "install-secret-guard.sh $r61 --force"
check_contains "S6-1: ...and so does the stale warning" "$(id_line W-GUARD-STALE)" "install-secret-guard.sh $r61 --force"
run_advised W-GUARD-UNWIRED
check_status "S6-1: the advised re-vendor succeeds" 0 "$STATUS"
run genv "$doctor" "$r61"
check_absent "S6-1: ...and clears the half-wired warning" "$OUT" "[W-GUARD-UNWIRED]"
check_absent "S6-1: ...and the stale one" "$OUT" "[W-GUARD-STALE]"

mk_home s61s; r61s="$(mk_repo)"
run genv "$isg" "$r61s"
edit_hook "$r61s/.git/hooks/pre-push"
run genv "$doctor" "$r61s"
check_contains "S6-1: a vendored edited pre-push alone → W-GUARD-STALE naming --force" "$(id_line W-GUARD-STALE)" "install-secret-guard.sh $r61s --force"
run_advised W-GUARD-STALE
check_status "S6-1: ...and its advised command succeeds" 0 "$STATUS"
run genv "$doctor" "$r61s"
check_absent "S6-1: ...and clears the stale warning" "$OUT" "[W-GUARD-STALE]"

# control: a drifted scanner with both hooks UNEDITED is re-vendored by a plain run — no --force in that advice
mk_home s61c; r61c="$(mk_repo)"
run genv "$isg" "$r61c"
edit_hook "$r61c/.git/hooks/secret-scan.sh"
run genv "$doctor" "$r61c"
check_contains "S6-1 control: a drifted scanner alone → W-GUARD-STALE" "$OUT" "[W-GUARD-STALE]"
check_absent "S6-1 control: ...its advice stays a plain re-vendor (nothing is refused)" "$(id_line W-GUARD-STALE)" "--force"
plain61="$(printf '%s\n' "$(id_line W-GUARD-STALE)" | grep -oE 'install-secret-guard\.sh [^ ]+' | head -1)"
run genv "$isg" "${plain61#install-secret-guard.sh }"
check_status "S6-1 control: ...and the plain command succeeds (doctor and installer agree both ways)" 0 "$STATUS"
run genv "$doctor" "$r61c"
check_absent "S6-1 control: ...and clears the warning" "$OUT" "[W-GUARD-STALE]"

# a LINKED edited hook: --force cannot replace it, so the advice must not promise a backup (the link notes own that state)
mk_home s61l
run genv "$isg" --global
kd61="$H/$kh_rel"
cp "$kd61/pre-commit" "$H/pc-real"; edit_hook "$H/pc-real"; chmod +x "$H/pc-real"
rm -f "$kd61/pre-commit"; ln -s "$H/pc-real" "$kd61/pre-commit"
run genv "$doctor" --install "$H/claude"
check_contains "S6-1: a linked, edited pre-commit still reads as a stale guard" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_absent "S6-1: ...whose advice does not promise a --force backup (the installer refuses links either way)" "$(id_line W-GUARD-GLOBAL-STALE)" "--force"

# a LINKED sibling hook: the installer stops on it with or without --force, so an edited pre-commit beside it gets no --force promise
mk_home s61m
run genv "$isg" --global
kd61="$H/$kh_rel"
edit_hook "$kd61/pre-commit"
cp "$kd61/pre-push" "$H/pp-real"; rm -f "$kd61/pre-push"; ln -s "$H/pp-real" "$kd61/pre-push"
run genv "$doctor" --install "$H/claude"
check_contains "S6-1: an edited pre-commit beside a linked pre-push → W-GUARD-GLOBAL-STALE" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_absent "S6-1: ...whose advice makes no --force promise (the link stops the installer)" "$(id_line W-GUARD-GLOBAL-STALE)" "--force"

# a user's OWN global hooks dir holding edited, Keel-marked copies: --force would displace their hooksPath, so the advice stays plain
mk_home s61u
mkdir -p "$H/own-hooks"
for f in pre-commit pre-push secret-scan.sh range-lib.sh; do cp "$REPO_ROOT/tools/secret-guard/$f" "$H/own-hooks/$f"; done
chmod +x "$H/own-hooks/pre-commit" "$H/own-hooks/pre-push"; edit_hook "$H/own-hooks/pre-commit"
printf '[core]\n\thooksPath = %s/own-hooks\n' "$H" > "$H/.gitconfig"
run genv "$doctor" --install "$H/claude"
check_contains "S6-1: edited Keel-marked copies in the user's own global dir → W-GUARD-GLOBAL-STALE" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_absent "S6-1: ...whose advice never offers --force (it would replace their hooksPath)" "$(id_line W-GUARD-GLOBAL-STALE)" "--force"

# an earlier --force backup waiting at <hook>.pre-keel.bak stops the installer even with --force: the advice says to run --force after moving it aside
mk_home s61w
run genv "$isg" --global
kd61="$H/$kh_rel"
edit_hook "$kd61/pre-commit"
run genv "$isg" --global --force
check_status "S6-1 setup: a first --force run leaves pre-commit.pre-keel.bak" 0 "$STATUS"
edit_hook "$kd61/pre-commit"
run genv "$doctor" --install "$H/claude"
check_contains "S6-1: ...an edit after it → the advice says to move the waiting backup aside" "$(id_line W-GUARD-GLOBAL-STALE)" "after moving $kd61/pre-commit.pre-keel.bak aside"
run_advised W-GUARD-GLOBAL-STALE
check_status "S6-1: ...following the advice's command without moving it is refused (exit 3)" 3 "$STATUS"
mv "$kd61/pre-commit.pre-keel.bak" "$H/old-backup"
run genv "$doctor" --install "$H/claude"
check_absent "S6-1: ...with the backup moved aside the advice is the plain --force one" "$(id_line W-GUARD-GLOBAL-STALE)" "after moving"
run_advised W-GUARD-GLOBAL-STALE
check_status "S6-1: ...and with the backup moved aside it succeeds" 0 "$STATUS"
run genv "$doctor" --install "$H/claude"
check_absent "S6-1: ...clearing the warning" "$OUT" "[W-GUARD-GLOBAL-STALE]"

# a repo path with a space: the printed command is quoted so it pastes as one word
mk_home s61p; r61p="$SANDBOX/fx s61p repo"; mkdir -p "$r61p"; git -C "$r61p" init -q
run genv "$isg" "$r61p"
check_status "S6-1 setup: vendor into a repo whose path has a space" 0 "$STATUS"
edit_hook "$r61p/.git/hooks/pre-commit"
run genv "$doctor" "$r61p"
check_contains "S6-1: the stale advice quotes the path" "$(id_line W-GUARD-STALE)" "fx\\ s61p\\ repo --force"
run_advised W-GUARD-STALE
check_status "S6-1: ...and the printed command runs as one word" 0 "$STATUS"
run genv "$doctor" "$r61p"
check_absent "S6-1: ...clearing the warning" "$OUT" "[W-GUARD-STALE]"

summary
