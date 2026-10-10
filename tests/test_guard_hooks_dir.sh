#!/usr/bin/env bash
# dir #643 — one resolver for "which hooks dir does this repo's secret-guard live in, and does git read
# it": tools/install-secret-guard.sh --where. The installer, tools/doctor.sh and install.sh's Verify all
# read it, so they agree on the dir across the repo / worktree / submodule shapes and across every
# config scope a core.hooksPath can arrive from (local, global, SYSTEM, the XDG file behind an existing
# ~/.gitconfig, an [include]); and the advice each prints per scope is pinned here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

isg="$REPO_ROOT/tools/install-secret-guard.sh"
doctor="$REPO_ROOT/tools/doctor.sh"
install="$REPO_ROOT/install.sh"
shipped="$REPO_ROOT/tools/secret-guard"

# --- fixture plumbing ---------------------------------------------------------------------------------
# One isolated HOME per shape. GIT_CONFIG_SYSTEM points at a file inside it, so the machine's own system
# config can never reach a case (and a SYSTEM-scope case has a file to put its setting in).
# genv: ~/.gitconfig is the global file (GIT_CONFIG_GLOBAL set, as lib.sh sets it everywhere).
# xenv: GIT_CONFIG_GLOBAL unset, so git reads ~/.gitconfig AND the XDG file behind it — the shape
#       `git config --global` cannot see into.
mk_home() { H="$SANDBOX/fx-$1"; mkdir -p "$H/xdg/git"; : > "$H/system.cfg"; }
genv() { env "HOME=$H" "GIT_CONFIG_GLOBAL=$H/.gitconfig" "GIT_CONFIG_SYSTEM=$H/system.cfg" "$@"; }
xenv() { env -u GIT_CONFIG_GLOBAL "HOME=$H" "XDG_CONFIG_HOME=$H/xdg" "GIT_CONFIG_SYSTEM=$H/system.cfg" "$@"; }

# wkey KEY — the value of a `key=value` line of $OUT (empty when the key is absent).
wkey() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | tail -1; }
same_dir() { [ -n "$1" ] && [ -n "$2" ] && { [ "$1" = "$2" ] || { [ -e "$1" ] && [ -e "$2" ] && [ "$1" -ef "$2" ]; }; }; }
check_same_dir() { if same_dir "$2" "$3"; then pass "$1"; else fail "$1" "'$2' is not the same dir as '$3'"; fi; }
check_not_same_dir() { if same_dir "$2" "$3"; then fail "$1" "'$2' should differ from '$3'"; else pass "$1"; fi; }

# A repo whose own hooks dir exists (git init makes it, but a template-less git does not).
mk_repo() { local r; r="$(new_repo)"; mkdir -p "$r/.git/hooks"; printf '%s' "$r"; }

# =================================================================================================
# 1. The resolver, repo side: `--where <repo>` → own (where the installer writes), effective (where git
#    reads), scope, value, origin. One fixture per topology and per scope.
# =================================================================================================

# --- topology axis (no hooksPath anywhere): own == effective, scope none ----------------------------
mk_home topo
trepo="$(mk_repo)"
run genv "$isg" --where "$trepo"
check_status "--where <plain repo> → exit 0" 0 "$STATUS"
check_same_dir "plain repo: own is the repo's .git/hooks" "$(wkey own)" "$trepo/.git/hooks"
check_same_dir "plain repo: effective == own (git reads where the installer writes)" "$(wkey effective)" "$(wkey own)"
check_eq "plain repo: scope none" "none" "$(wkey scope)"
check_eq "plain repo: no value= line" "" "$(wkey value)"

# A relative repo argument (doctor's default is ".") must not leak a relative own/effective.
run_in "$trepo" genv "$isg" --where .
check_status "--where . from inside a repo → exit 0" 0 "$STATUS"
case "$(wkey own)" in /*) pass "--where .: own is absolute" ;; *) fail "--where .: own is absolute" "got '$(wkey own)'" ;; esac
case "$(wkey effective)" in /*) pass "--where .: effective is absolute" ;; *) fail "--where .: effective is absolute" "got '$(wkey effective)'" ;; esac

twbase="$(mk_repo)"; git -C "$twbase" commit -qm seed --allow-empty
twt="$SANDBOX/fx-topo-wt"
git -C "$twbase" worktree add -q -b wt-643 "$twt"
run genv "$isg" --where "$twt"
check_status "--where <linked worktree> → exit 0" 0 "$STATUS"
check_same_dir "worktree: own is the MAIN checkout's hooks dir" "$(wkey own)" "$twbase/.git/hooks"
check_same_dir "worktree: effective == own" "$(wkey effective)" "$(wkey own)"

tsuper="$(mk_repo)"; git -C "$tsuper" commit -qm seed --allow-empty
tsubsrc="$(mk_repo)"; git -C "$tsubsrc" commit -qm seed --allow-empty
run git -c protocol.file.allow=always -C "$tsuper" submodule add -q "$tsubsrc" sub
check_status "setup: submodule add succeeds" 0 "$STATUS"
run genv "$isg" --where "$tsuper/sub"
check_status "--where <submodule> → exit 0" 0 "$STATUS"
check_same_dir "submodule: own is the SUPERPROJECT's .git/modules/sub/hooks" "$(wkey own)" "$tsuper/.git/modules/sub/hooks"
check_same_dir "submodule: effective == own" "$(wkey effective)" "$(wkey own)"

run genv "$isg" --where "$SANDBOX/not-a-repo-643"
check_status "--where <not a repo> → exit 2" 2 "$STATUS"
check_contains "--where <not a repo> says so" "$OUT" "not a git repo"
run genv "$isg" --where
check_status "--where with no target → exit 2" 2 "$STATUS"
run genv "$isg" --where --force "$trepo"
check_status "--where does not combine with --force → exit 2" 2 "$STATUS"

# --- scope axis -------------------------------------------------------------------------------------
# local, absolute: the installer writes where git reads.
mk_home sc-local; lrepo="$(mk_repo)"; mkdir -p "$H/lh"
git -C "$lrepo" config --local core.hooksPath "$H/lh"
run genv "$isg" --where "$lrepo"
check_eq "local absolute: scope local" "local" "$(wkey scope)"
check_same_dir "local absolute: own is the configured dir" "$(wkey own)" "$H/lh"
check_same_dir "local absolute: effective == own" "$(wkey effective)" "$(wkey own)"

# local, relative: resolved against the repo, by git and by the installer alike.
mk_home sc-rel; rrepo="$(mk_repo)"; mkdir -p "$rrepo/.githooks"
git -C "$rrepo" config --local core.hooksPath .githooks
run genv "$isg" --where "$rrepo"
check_eq "local relative: scope local" "local" "$(wkey scope)"
check_same_dir "local relative: own is <repo>/.githooks" "$(wkey own)" "$rrepo/.githooks"
check_same_dir "local relative: effective == own" "$(wkey effective)" "$(wkey own)"

# The four machine-wide arrivals. In each, git reads a dir that is NOT the repo's own hooks dir — so a
# copy vendored into own is inert. effective must name the live dir, own the installer's target.
mk_home sc-global; grepo="$(mk_repo)"; mkdir -p "$H/gh"
genv git config --global core.hooksPath "$H/gh"
run genv "$isg" --where "$grepo"
check_eq "GLOBAL: scope global" "global" "$(wkey scope)"
check_same_dir "GLOBAL: effective is the global dir" "$(wkey effective)" "$H/gh"
check_same_dir "GLOBAL: own is still the repo's own hooks dir" "$(wkey own)" "$grepo/.git/hooks"
check_not_same_dir "GLOBAL: own != effective" "$(wkey own)" "$(wkey effective)"
check_eq "GLOBAL: value is the raw setting" "$H/gh" "$(wkey value)"

mk_home sc-system; srepo="$(mk_repo)"; mkdir -p "$H/sh"
printf '[core]\n\thooksPath = %s\n' "$H/sh" > "$H/system.cfg"
run genv "$isg" --where "$srepo"
check_eq "SYSTEM: scope system" "system" "$(wkey scope)"
check_same_dir "SYSTEM: effective is the system dir" "$(wkey effective)" "$H/sh"
check_same_dir "SYSTEM: own is the repo's own hooks dir" "$(wkey own)" "$srepo/.git/hooks"

# XDG file behind an EXISTING ~/.gitconfig: `git config --global` cannot see it, git commits through it.
mk_home sc-xdg; xrepo="$(mk_repo)"; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
run xenv "$isg" --where "$xrepo"
check_eq "XDG behind ~/.gitconfig: scope global" "global" "$(wkey scope)"
check_same_dir "XDG behind ~/.gitconfig: effective is the XDG dir" "$(wkey effective)" "$H/xh"
check_contains "XDG behind ~/.gitconfig: origin names the XDG file" "$(wkey origin)" "$H/xdg/git/config"

# [include] in ~/.gitconfig: again invisible to --global, and the ~/ in the value is git's to expand.
mk_home sc-inc; irepo="$(mk_repo)"; mkdir -p "$H/inc-hooks"
printf '[include]\n\tpath = %s/inc.cfg\n' "$H" > "$H/.gitconfig"
printf '[core]\n\thooksPath = ~/inc-hooks\n' > "$H/inc.cfg"
run xenv "$isg" --where "$irepo"
check_eq "include: scope global" "global" "$(wkey scope)"
check_same_dir "include: effective is the included dir, ~ expanded" "$(wkey effective)" "$H/inc-hooks"
check_contains "include: origin names the included file" "$(wkey origin)" "$H/inc.cfg"
check_not_same_dir "include: own != effective" "$(wkey own)" "$(wkey effective)"

# --- hook state of the effective dir: one marker verdict for everyone ------------------------------
mk_home st; strepo="$(mk_repo)"; mkdir -p "$H/stdir"
genv git config --global core.hooksPath "$H/stdir"
run genv "$isg" --where "$strepo"
check_eq "empty effective dir: pre-commit absent" "absent" "$(wkey pre-commit)"
cp "$shipped/pre-commit" "$H/stdir/pre-commit"
printf '#!/bin/sh\n# my own wrapper that mentions Keel secret-guard\nexit 0\n' > "$H/stdir/pre-push"
run genv "$isg" --where "$strepo"
check_eq "a hook carrying Keel's marker line: keel" "keel" "$(wkey pre-commit)"
check_eq "a user's hook that only names the tool: foreign" "foreign" "$(wkey pre-push)"
mv "$H/stdir/pre-commit" "$H/stdir/real-pre-commit"; ln -s "$H/stdir/real-pre-commit" "$H/stdir/pre-commit"
run genv "$isg" --where "$strepo"
check_eq "a symlinked Keel hook: keel-link" "keel-link" "$(wkey pre-commit)"

# =================================================================================================
# 2. The resolver, machine side: `--where --global` — git's EFFECTIVE machine-wide hooksPath, which a
#    plain `git config --global` read misses (XDG behind ~/.gitconfig, [include], SYSTEM). DT3.
# =================================================================================================
mk_home mw-none
run genv "$isg" --where --global
check_status "--where --global, nothing set → exit 0" 0 "$STATUS"
check_eq "nothing set: no value" "" "$(wkey value)"
check_eq "nothing set: scope none" "none" "$(wkey scope)"

mk_home mw-xdg; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
run xenv "$isg" --where --global
check_eq "machine side sees the XDG file behind ~/.gitconfig" "$H/xh" "$(wkey value)"
check_same_dir "machine side: dir is the XDG dir" "$(wkey dir)" "$H/xh"
check_contains "machine side: origin names the XDG file" "$(wkey origin)" "$H/xdg/git/config"

mk_home mw-inc; mkdir -p "$H/inc-hooks"
printf '[include]\n\tpath = %s/inc.cfg\n' "$H" > "$H/.gitconfig"
printf '[core]\n\thooksPath = ~/inc-hooks\n' > "$H/inc.cfg"
run xenv "$isg" --where --global
check_same_dir "machine side sees an [include]d hooksPath, ~ expanded" "$(wkey dir)" "$H/inc-hooks"

mk_home mw-sys; mkdir -p "$H/sh"
printf '[core]\n\thooksPath = %s\n' "$H/sh" > "$H/system.cfg"
run genv "$isg" --where --global
check_eq "machine side sees a SYSTEM hooksPath" "$H/sh" "$(wkey value)"
check_eq "machine side: SYSTEM scope named" "system" "$(wkey scope)"

mk_home mw-keel
run genv "$isg" --global
check_status "setup: install-secret-guard --global wires Keel's dir" 0 "$STATUS"
run genv "$isg" --where --global
check_eq "Keel's own dir is flagged keel-dir=1" "1" "$(wkey keel-dir)"
check_eq "Keel's own pre-commit reads as keel" "keel" "$(wkey pre-commit)"
check_eq "Keel's own pre-push reads as keel" "keel" "$(wkey pre-push)"

# =================================================================================================
# 3. The installer's own advice, per scope. A copy vendored into a repo is inert whenever a hooksPath
#    from ANY other scope governs it — the installer says so instead of reporting a quiet success.
# =================================================================================================
mk_home adv; arepo="$(mk_repo)"; mkdir -p "$H/gh"
run genv "$isg" "$arepo"
check_status "vendor into a plain repo → exit 0" 0 "$STATUS"
check_absent "plain repo: no inert-copy note" "$OUT" "this copy is inert"

genv git config --global core.hooksPath "$H/gh"
arepo2="$(mk_repo)"
run genv "$isg" "$arepo2"
check_status "vendor into a repo under a GLOBAL hooksPath → still exit 0" 0 "$STATUS"
check_contains "GLOBAL: the installer says its copy is inert" "$OUT" "this copy is inert"
check_contains "GLOBAL: ...names where git actually reads" "$OUT" "$H/gh"
check_contains "GLOBAL: ...and the repo-local remedy, with the installer's own dir" "$OUT" "--local core.hooksPath $arepo2/.git/hooks"
check_contains "GLOBAL: ...and the machine-wide remedy" "$OUT" "install-secret-guard.sh --global --force"

mk_home adv-sys; asrepo="$(mk_repo)"; mkdir -p "$H/sh"
printf '[core]\n\thooksPath = %s\n' "$H/sh" > "$H/system.cfg"
run genv "$isg" "$asrepo"
check_status "vendor under a SYSTEM hooksPath → still exit 0" 0 "$STATUS"
check_contains "SYSTEM: the installer says its copy is inert" "$OUT" "this copy is inert"
check_contains "SYSTEM: ...and names the scope" "$OUT" "system"

mk_home adv-xdg; axrepo="$(mk_repo)"; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
run xenv "$isg" "$axrepo"
check_contains "XDG behind ~/.gitconfig: the installer says its copy is inert" "$OUT" "this copy is inert"

mk_home adv-loc; alrepo="$(mk_repo)"; mkdir -p "$H/lh"
git -C "$alrepo" config --local core.hooksPath "$H/lh"
run genv "$isg" "$alrepo"
check_status "vendor under a LOCAL hooksPath → exit 0" 0 "$STATUS"
check_file "LOCAL: the copy lands in the configured dir" "$H/lh/secret-scan.sh"
check_absent "LOCAL: no inert-copy note (git reads where the installer wrote)" "$OUT" "this copy is inert"

# =================================================================================================
# 4. DT3 — the installer's --global reads. A hooksPath set in the XDG file behind an existing
#    ~/.gitconfig, in an [include], or at SYSTEM scope is a hooksPath the user set: not clobbered, and
#    never reported as "nothing to unwire".
# =================================================================================================
mk_home g-xdg; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
run xenv "$isg" --global
check_status "--global over a hooksPath set in the XDG file → refuses (exit 3)" 3 "$STATUS"
check_contains "...names it as already set" "$OUT" "already set"
check_contains "...and names the file it was read from" "$OUT" "$H/xdg/git/config"
check_eq "...~/.gitconfig gained no core.hooksPath" "" "$(xenv git config --file "$H/.gitconfig" --get core.hooksPath || true)"
check_nodir "...and no Keel hooks dir was written" "$H/.config/git/keel-hooks"
check_contains "...with the honest per-repo remedy, not 'vendor per-repo'" "$OUT" "--local core.hooksPath"
check_absent "...never the pre-#643 'vendor per-repo' line" "$OUT" "or vendor per-repo"

mk_home g-inc; mkdir -p "$H/inc-hooks"
printf '[include]\n\tpath = %s/inc.cfg\n' "$H" > "$H/.gitconfig"
printf '[core]\n\thooksPath = ~/inc-hooks\n' > "$H/inc.cfg"
run xenv "$isg" --global
check_status "--global over an [include]d hooksPath → refuses (exit 3)" 3 "$STATUS"
check_contains "...names the included file" "$OUT" "$H/inc.cfg"
check_nodir "...nothing written" "$H/.config/git/keel-hooks"

mk_home g-sys; mkdir -p "$H/sh"
printf '[core]\n\thooksPath = %s\n' "$H/sh" > "$H/system.cfg"
run genv "$isg" --global
check_status "--global over a SYSTEM hooksPath → refuses (exit 3)" 3 "$STATUS"
check_nodir "...nothing written" "$H/.config/git/keel-hooks"

# --force over an XDG-set foreign value: wired at global scope, the old value recorded.
mk_home g-force; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
run xenv "$isg" --global --force
check_status "--global --force over an XDG-set hooksPath → wires (exit 0)" 0 "$STATUS"
check_eq "...~/.gitconfig now names Keel's dir" "$H/.config/git/keel-hooks" "$(xenv git config --file "$H/.gitconfig" --get core.hooksPath || true)"
check_eq "...and the displaced XDG value is recorded" "$H/xh" "$(xenv git config --file "$H/.gitconfig" --get keel.displacedHooksPath || true)"

# --force where a LATER [include] still wins over the global key it just wrote: wired, yet not active.
# The installer must say so (exit 3) instead of printing "wired".
mk_home g-shadow; mkdir -p "$H/inc-hooks"
printf '[core]\n\tpager = cat\n[include]\n\tpath = %s/inc.cfg\n' "$H" > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/inc-hooks\n' "$H" > "$H/inc.cfg"
run xenv "$isg" --global --force
check_status "--global --force shadowed by a later [include] → exit 3, not a quiet success" 3 "$STATUS"
check_contains "...says the guard is NOT active" "$OUT" "NOT active"
check_contains "...and names what wins" "$OUT" "$H/inc.cfg"

# Already Keel's, via the XDG file: nothing to clobber, nothing written into ~/.gitconfig.
mk_home g-ours; mkdir -p "$H/.config/git"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/.config/git/keel-hooks\n' "$H" > "$H/xdg/git/config"
run xenv "$isg" --global
check_status "--global when Keel's dir is already set via the XDG file → exit 0" 0 "$STATUS"
check_eq "...~/.gitconfig gained no core.hooksPath" "" "$(xenv git config --file "$H/.gitconfig" --get core.hooksPath || true)"
check_file "...the hooks were still installed" "$H/.config/git/keel-hooks/pre-commit"

# --uninstall: Keel's dir named only in the XDG file is NOT the file `git config --global` edits.
run xenv "$isg" --global --uninstall
check_status "--uninstall when Keel is wired only via the XDG file → refuses (exit 3)" 3 "$STATUS"
check_contains "...says where it is set instead of 'nothing to unwire'" "$OUT" "$H/xdg/git/config"
check_absent "...never claims there is nothing to unwire" "$OUT" "nothing to unwire"
mk_home g-unf; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
run xenv "$isg" --global --uninstall
check_status "--uninstall over a foreign XDG-set hooksPath → refuses, never 'nothing to unwire'" 3 "$STATUS"
check_absent "...no 'nothing to unwire' claim" "$OUT" "nothing to unwire"

# =================================================================================================
# 5. doctor reads the same resolver: the per-scope verdict and advice line are pinned, and a vendored
#    copy git does not read is never counted as wiring.
# =================================================================================================
doc_run() {  # doc_run <env-fn> <repo> — doctor over one repo, in the current fixture's HOME
  run "$1" "$doctor" "$2"
}

# Plain repo, nothing wired anywhere → both remedies work, and the line still offers both.
mk_home d-none; drepo="$(mk_repo)"
doc_run genv "$drepo"
check_contains "doctor: nothing wired → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "doctor: nothing wired → both remedies offered" "$OUT" "install-secret-guard.sh --global, or vendor into this repo"
check_absent "doctor: nothing wired → no inert-copy advice" "$OUT" "would be ignored"
run genv "$isg" "$drepo"
doc_run genv "$drepo"
check_absent "doctor: a copy vendored where git reads it counts as wired" "$OUT" "[W-GUARD-UNWIRED]"

# Each machine-wide arrival, hookless dir: the advice must not tell the reader to vendor into a repo
# whose own hooks dir git is not reading.
check_unwired_scope() {  # label env-fn repo scope-word
  local label="$1" envfn="$2" repo="$3" scope="$4" own
  run "$envfn" "$isg" --where "$repo"; own="$(wkey own)"
  doc_run "$envfn" "$repo"
  check_contains "doctor, $label: W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
  check_contains "doctor, $label: names the scope" "$OUT" "$scope scope"
  check_contains "doctor, $label: says a vendored copy would be ignored" "$OUT" "would be ignored"
  check_contains "doctor, $label: the repo-local remedy carries the installer's own dir" "$OUT" "--local core.hooksPath $own"
  check_contains "doctor, $label: the machine-wide remedy" "$OUT" "install-secret-guard.sh --global --force"
  check_absent "doctor, $label: never 'or vendor into this repo'" "$OUT" "or vendor into this repo"
}
mk_home d-global; dgrepo="$(mk_repo)"; mkdir -p "$H/gh"
genv git config --global core.hooksPath "$H/gh"
check_unwired_scope "GLOBAL" genv "$dgrepo" "global"
run genv "$isg" "$dgrepo"   # vendoring into own is inert — doctor must keep saying so
check_unwired_scope "GLOBAL, after a (inert) vendor" genv "$dgrepo" "global"

mk_home d-system; dsrepo="$(mk_repo)"; mkdir -p "$H/sh"
printf '[core]\n\thooksPath = %s\n' "$H/sh" > "$H/system.cfg"
check_unwired_scope "SYSTEM" genv "$dsrepo" "system"

mk_home d-xdg; dxrepo="$(mk_repo)"; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
check_unwired_scope "XDG behind ~/.gitconfig" xenv "$dxrepo" "global"
check_contains "doctor, XDG: names the file the setting came from" "$OUT" "$H/xdg/git/config"

mk_home d-inc; direpo="$(mk_repo)"; mkdir -p "$H/inc-hooks"
printf '[include]\n\tpath = %s/inc.cfg\n' "$H" > "$H/.gitconfig"
printf '[core]\n\thooksPath = ~/inc-hooks\n' > "$H/inc.cfg"
check_unwired_scope "[include]" xenv "$direpo" "global"

# A wired guard in the XDG/include dir is wired — no finding (the scopes are about advice, not verdict).
printf '#!/bin/sh\nexit 0\n' > "$H/inc-hooks/pre-commit"; chmod +x "$H/inc-hooks/pre-commit"
doc_run xenv "$direpo"
check_absent "doctor, [include]: an executable pre-commit in the live dir → wired" "$OUT" "[W-GUARD-UNWIRED]"

# A LOCAL hooksPath: unchanged — the installer writes where git reads, and the remedy is re-vendoring.
mk_home d-local; dlrepo="$(mk_repo)"; mkdir -p "$H/lh"
git -C "$dlrepo" config --local core.hooksPath "$H/lh"
doc_run genv "$dlrepo"
check_contains "doctor, LOCAL, no pre-commit: W-GUARD-BYPASSED (unchanged)" "$OUT" "[W-GUARD-BYPASSED]"
run genv "$isg" "$dlrepo"
doc_run genv "$dlrepo"
check_absent "doctor, LOCAL, vendored by the installer: wired (installer and doctor agree on the dir)" "$OUT" "[W-GUARD-BYPASSED]"
printf '\n# drifted\n' >> "$H/lh/secret-scan.sh"
doc_run genv "$dlrepo"
check_contains "doctor, LOCAL drift: W-GUARD-STALE" "$OUT" "[W-GUARD-STALE]"
check_contains "doctor, LOCAL drift: re-vendoring IS the fix here" "$OUT" "re-vendor: install-secret-guard.sh"

# Worktree and submodule: the installer's vendor target IS the dir doctor judges.
for shape in "worktree|$twt" "submodule|$tsuper/sub"; do
  IFS='|' read -r label target <<< "$shape"
  mk_home "d-$label"
  run genv "$isg" "$target"
  check_status "setup: vendor into a $label" 0 "$STATUS"
  doc_run genv "$target"
  check_absent "doctor, $label: the installer's copy counts as wired" "$OUT" "[W-GUARD-UNWIRED]"
done

# --- DT4: one health verdict for Keel's own machine hooks dir ---------------------------------------
mk_home d-keel; dkrepo="$(mk_repo)"
run genv "$isg" --global
check_status "setup: wire Keel's machine-global guard" 0 "$STATUS"
doc_run genv "$dkrepo"
check_absent "doctor: Keel's own wired dir → no W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
kdir="$H/.config/git/keel-hooks"
mv "$kdir/pre-commit" "$kdir/pre-commit.keel"
printf '#!/bin/sh\n# a wrapper that runs lint and mentions Keel secret-guard\nexit 0\n' > "$kdir/pre-commit"; chmod +x "$kdir/pre-commit"
doc_run genv "$dkrepo"
check_contains "doctor: a non-Keel pre-commit IN Keel's dir is not 'wired' (Verify says the same)" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "doctor: ...and says why" "$OUT" "not Keel's"
rm -f "$kdir/pre-commit"; ln -s "$kdir/pre-commit.keel" "$kdir/pre-commit"
doc_run genv "$dkrepo"
check_absent "doctor: a symlinked Keel pre-commit still guards commits → not flagged unwired" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "doctor: ...but discloses that the installer will not update a symlink" "$OUT" "symlink"
# Verify and the installer treat a foreign hook of EITHER name in Keel's dir as "not Keel's" — so does doctor.
rm -f "$kdir/pre-commit"; mv "$kdir/pre-commit.keel" "$kdir/pre-commit"
printf '#!/bin/sh\n# my own pre-push that mentions Keel secret-guard\nexit 0\n' > "$kdir/pre-push"
doc_run genv "$dkrepo"
check_contains "doctor: a non-Keel pre-push in Keel's dir is not 'wired' either" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "doctor: ...and says why" "$OUT" "not Keel's"
# A user's own hooks dir keeps the old bar: an executable pre-commit is wired (no marker required).
mk_home d-ownhooks; dohrepo="$(mk_repo)"; mkdir -p "$H/own-hooks"
printf '#!/bin/sh\nexit 0\n' > "$H/own-hooks/pre-commit"; chmod +x "$H/own-hooks/pre-commit"
genv git config --global core.hooksPath "$H/own-hooks"
doc_run genv "$dohrepo"
check_absent "doctor: a foreign hooks dir with its own pre-commit is not held to Keel's marker" "$OUT" "not Keel's"
check_absent "doctor: ...and is wired" "$OUT" "[W-GUARD-UNWIRED]"

# =================================================================================================
# 6. install.sh: the same advice and the same reads (DT3), and Verify agrees with doctor on a linked hook.
# =================================================================================================
inst_run() {  # inst_run <env-fn> <flags…> — install.sh into a throwaway --home, in the current fixture's HOME
  local envfn="$1"; shift
  run "$envfn" "$install" --home "$H/claude-home" "$@"
}
mk_home i-foreign; mkdir -p "$H/foreign-hooks"
genv git config --global core.hooksPath "$H/foreign-hooks"
inst_run genv
check_contains "install.sh: a foreign global hooksPath is not clobbered" "$OUT" "not clobbering it"
check_contains "install.sh: ...advice says a vendored copy would be ignored" "$OUT" "would be ignored"
check_contains "install.sh: ...and offers the machine-wide remedy" "$OUT" "install-secret-guard.sh --global --force"
check_contains "install.sh: ...and the per-repo remedy" "$OUT" "--local core.hooksPath"
check_absent "install.sh: never the pre-#643 'vendor instead' line" "$OUT" "To protect a repo, vendor instead"
check_absent "install.sh: never the pre-#643 Verify 'Vendor per-repo instead' line" "$OUT" "Vendor per-repo instead"
check_eq "install.sh: the foreign hooksPath survives" "$H/foreign-hooks" "$(genv git config --global core.hooksPath || true)"

mk_home i-xdg; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
inst_run xenv
check_contains "install.sh: a hooksPath only in the XDG file is not clobbered either" "$OUT" "not clobbering it"
check_contains "install.sh: ...and names the file" "$OUT" "$H/xdg/git/config"
check_eq "install.sh: ~/.gitconfig gained no core.hooksPath" "" "$(xenv git config --file "$H/.gitconfig" --get core.hooksPath || true)"
check_nodir "install.sh: no Keel hooks dir written over it" "$H/.config/git/keel-hooks"

# Keel's own dir named only in the XDG file: Verify recognises it (the same path rule, one read).
mk_home i-xours; mkdir -p "$H/.config/git"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/.config/git/keel-hooks\n' "$H" > "$H/xdg/git/config"
run xenv "$isg" --global
inst_run xenv --no-hooks
check_contains "install.sh Verify: Keel's dir wired via the XDG file is Keel's guard" "$OUT" "OK   secret-guard"
check_absent "install.sh Verify: ...not a foreign hooksPath" "$OUT" "foreign global core.hooksPath"

# A symlinked Keel pre-commit: Verify no longer says a bare OK over a hook the installer refuses.
mk_home i-link
run genv "$isg" --global
kd="$H/.config/git/keel-hooks"
mv "$kd/pre-commit" "$kd/pre-commit.keel"; ln -s "$kd/pre-commit.keel" "$kd/pre-commit"
inst_run genv --no-hooks
check_contains "install.sh Verify: a symlinked Keel pre-commit is disclosed" "$OUT" "symlink"
check_contains "install.sh Verify: ...the guard itself still reads as wired (it runs)" "$OUT" "OK   secret-guard"

# =================================================================================================
# 7. dir #688 / dir #717 S5-2 — doctor's machine-wide reads go through the producer (`--where --global`),
#    and the producer says what doctor used to compare by hand: `machine-dir=1` (the dir #122 dedup) and
#    `fallback=1` (the narrow-read branch).
# =================================================================================================

# --- A1 (S5-2): the `--install` twin of DT4 — a foreign hook in Keel's own machine dir is not "wired" ----
mk_home a1; mkdir -p "$H/claude"
run genv "$isg" --global
check_status "A1 setup: wire Keel's machine-global guard" 0 "$STATUS"
a1dir="$H/.config/git/keel-hooks"
run genv "$doctor" --install "$H/claude"
check_contains "A1 control: an intact Keel dir → OK" "$OUT" "OK   secret-guard: machine-global ($a1dir)"
check_absent "A1 control: ...and no W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
mv "$a1dir/pre-commit" "$a1dir/pre-commit.keel"
printf '#!/bin/sh\n# a wrapper that runs lint and mentions Keel secret-guard\nexit 0\n' > "$a1dir/pre-commit"; chmod +x "$a1dir/pre-commit"
run genv "$doctor" --install "$H/claude"
check_contains "A1: --install over a non-Keel pre-commit in Keel's dir → W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "A1: ...and says why" "$OUT" "not Keel's"
check_absent "A1: ...never the OK line over it" "$OUT" "OK   secret-guard: machine-global"
rm -f "$a1dir/pre-commit"; mv "$a1dir/pre-commit.keel" "$a1dir/pre-commit"
printf '#!/bin/sh\n# my own pre-push that mentions Keel secret-guard\nexit 0\n' > "$a1dir/pre-push"
run genv "$doctor" --install "$H/claude"
check_contains "A1: a foreign PRE-PUSH in Keel's dir → W-GUARD-UNWIRED too" "$OUT" "[W-GUARD-UNWIRED]"
check_contains "A1: ...and says why" "$OUT" "not Keel's"
check_absent "A1: ...never the OK line over it" "$OUT" "OK   secret-guard: machine-global"
cp "$shipped/pre-push" "$a1dir/pre-push"
mv "$a1dir/pre-commit" "$a1dir/pre-commit.keel"; ln -s "$a1dir/pre-commit.keel" "$a1dir/pre-commit"
run genv "$doctor" --install "$H/claude"
check_contains "A1: a symlinked Keel pre-commit → still the OK line" "$OUT" "OK   secret-guard: machine-global ($a1dir)"
check_contains "A1: ...plus the symlink disclosure" "$OUT" "secret-guard: the pre-commit at $a1dir is a symlink"
check_absent "A1: ...and no W-GUARD-UNWIRED" "$OUT" "[W-GUARD-UNWIRED]"
# a user's own hooks dir (not Keel's) holding an executable plain pre-commit: the per-repo bar — no marker test
mk_home a1-own; mkdir -p "$H/claude" "$H/own-hooks"
printf '#!/bin/sh\nexit 0\n' > "$H/own-hooks/pre-commit"; chmod +x "$H/own-hooks/pre-commit"
genv git config --global core.hooksPath "$H/own-hooks"
run genv "$doctor" --install "$H/claude"
check_contains "A1: a user's own hooks dir with an executable pre-commit → OK" "$OUT" "OK   secret-guard: machine-global ($H/own-hooks)"
check_absent "A1: ...held to no marker" "$OUT" "not Keel's"

# --- A4: `--where <repo>` prints machine-dir=1 when it resolves to the machine-wide dir -------------------
mk_home a4; a4repo="$(mk_repo)"; mkdir -p "$H/mh" "$H/other"
genv git config --global core.hooksPath "$H/mh"
git -C "$a4repo" config --local core.hooksPath "$H/mh"
run genv "$isg" --where "$a4repo"
check_eq "A4: a local hooksPath equal to the global dir → machine-dir=1" "1" "$(wkey machine-dir)"
check_eq "A4: ...the scope is still local (machine-dir is not a scope)" "local" "$(wkey scope)"
git -C "$a4repo" config --local core.hooksPath "$H/other"
run genv "$isg" --where "$a4repo"
check_eq "A4: a different local dir → no machine-dir key" "" "$(wkey machine-dir)"
# a tilde spelling on either side, and a trailing slash
# shellcheck disable=SC2088  # the point is a LITERAL ~/ as a user writes it into git config
genv git config --global core.hooksPath '~/mh'
git -C "$a4repo" config --local core.hooksPath "$H/mh"
run genv "$isg" --where "$a4repo"
check_eq "A4: global spelled ~/mh, local absolute → machine-dir=1" "1" "$(wkey machine-dir)"
genv git config --global core.hooksPath "$H/mh/"
git -C "$a4repo" config --local core.hooksPath "$H/mh"
run genv "$isg" --where "$a4repo"
check_eq "A4: global spelled with a trailing slash → machine-dir=1" "1" "$(wkey machine-dir)"
genv git config --global core.hooksPath "$H/mh"
git -C "$a4repo" config --local core.hooksPath "$H/mh/"
run genv "$isg" --where "$a4repo"
check_eq "A4: local spelled with a trailing slash → machine-dir=1" "1" "$(wkey machine-dir)"
# a repo with no local override, under the global one: effective IS the machine-wide dir
a4plain="$(mk_repo)"
run genv "$isg" --where "$a4plain"
check_eq "A4: no local override, global governs → machine-dir=1" "1" "$(wkey machine-dir)"
# nothing machine-wide set: never
mk_home a4-none; a4nrepo="$(mk_repo)"
run genv "$isg" --where "$a4nrepo"
check_eq "A4: no machine-wide hooksPath → no machine-dir key" "" "$(wkey machine-dir)"
# the XDG variant: the machine-wide value set ONLY in the XDG file behind an existing ~/.gitconfig
mk_home a4-xdg; a4xrepo="$(mk_repo)"; mkdir -p "$H/xh"
printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$H/xh" > "$H/xdg/git/config"
git -C "$a4xrepo" config --local core.hooksPath "$H/xh"
run xenv "$isg" --where "$a4xrepo"
check_eq "A4: machine-wide dir only in the XDG file, local pins the same dir → machine-dir=1" "1" "$(wkey machine-dir)"

# --- A5: `fallback=1` — the scratch probe sat inside a repo, so the narrow read ran -------------------------
mk_home a5; a5repo="$(mk_repo)"; mkdir -p "$H/claude" "$H/shim" "$H/gh"
printf '#!/bin/sh\nmkdir -p "%s/probe" && printf "%%s\\n" "%s/probe"\n' "$a5repo" "$a5repo" > "$H/shim/mktemp"; chmod +x "$H/shim/mktemp"
genv git config --global core.hooksPath "$H/gh"
run genv "$isg" --where --global
check_eq "A5 control: a normal probe → no fallback key" "" "$(wkey fallback)"
run genv "PATH=$H/shim:$PATH" "$isg" --where --global
check_eq "A5: the probe inside a repo → fallback=1" "1" "$(wkey fallback)"
check_eq "A5: ...the narrow read still answers" "$H/gh" "$(wkey value)"
run genv "$doctor" --install "$H/claude"
check_absent "A5 control: doctor without the shim → no degraded line" "$OUT" "effective core.hooksPath probe unavailable"
run genv "PATH=$H/shim:$PATH" "$doctor" --install "$H/claude"
check_contains "A5: doctor discloses the degraded read" "$OUT" "effective core.hooksPath probe unavailable"

# --- A3 (static): doctor and uninstall keep no machine-scope hooksPath read of their own ---------------------
check_eq "A3: no \$(git … config … core.hooksPath) read left in doctor.sh / uninstall.sh" "0" \
  "$(grep -cE '\$\(git[^)]*config[^)]*core\.hooksPath' "$REPO_ROOT/tools/doctor.sh" "$REPO_ROOT/uninstall.sh" | awk -F: '{n+=$NF} END{print n+0}')"
check_eq "A3: doctor.sh has no _expand_hookspath_tilde" "0" "$(grep -c _expand_hookspath_tilde "$REPO_ROOT/tools/doctor.sh" || true)"
check_eq "A3: doctor.sh keeps no -ef bridge against a machine-wide value" "0" \
  "$(grep -cE -- '-ef "\$(global_hooks_eff|g_dir)"' "$REPO_ROOT/tools/doctor.sh" || true)"

# =================================================================================================
# 8. dir #717 S5-1 — a core.hooksPath delivered by a conditional [includeIf] include. `--global` used to
#    append its own [core] hooksPath after it and silently take over every tree the condition matched.
#    The installer now walks the conditional includes (file origins only), refuses a foreign or empty
#    one unless --force, and refuses an incomplete walk (spec 717 B6–B8, A10–A16).
# =================================================================================================
kh_rel=".config/git/keel-hooks"
# s2_home NAME — mk_home plus a repo under ~/work/, the tree `gitdir:~/work/` matches.
s2_home() { mk_home "$1"; mkdir -p "$H/work" "$H/work-hooks"; git init -q "$H/work/proj"; }
s2_inc() { printf '[includeIf "gitdir:~/work/"]\n\tpath = work.cfg\n' >> "$H/.gitconfig"; }
tree_hp() { genv git -C "$H/work/proj" config core.hooksPath || true; }
# run_bounded CMD… — `run`, in the background with a bounded wait: a walk that loops on a self-include
# fails here instead of hanging the suite (`timeout` is absent on macOS; tests/test_install.sh's T14f).
run_bounded() {
  local out="$SANDBOX/bounded.out" pid waited=0
  "$@" >"$out" 2>&1 </dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "${KEEL_TEST_HANG_BOUND:-120}" ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    STATUS=124; OUT="(still running after ${waited} s — killed)"; return 0
  fi
  STATUS=0; wait "$pid" || STATUS=$?
  OUT="$(cat "$out")"
}
# s2_shim — a PATH dir ($s2_shim) whose FIRST bare `mktemp -d` after s2_shim_arm hands out a dir inside a
# repo (A5's shim, made one-shot): that call is the install's machine read; every later mktemp goes to the
# real one, so the install's own selftest (which makes temp dirs of its own) still runs.
s2_shim() {
  local r; r="$(mk_repo)"; s2_shim="$H/shim"; s2_shim_repo="$r"; mkdir -p "$s2_shim"
  printf '#!/bin/sh\nif [ "$*" = -d ] && [ ! -e "%s/used" ]; then : > "%s/used"; mkdir -p "%s/probe" && printf "%%s\\n" "%s/probe"; else exec "%s" "$@"; fi\n' \
    "$s2_shim" "$s2_shim" "$r" "$r" "$(type -P mktemp)" > "$s2_shim/mktemp"
  chmod +x "$s2_shim/mktemp"
}
s2_shim_arm() { rm -f "$s2_shim/used"; }

# --- A10: a foreign conditional hooksPath → refused, nothing written ----------------------------------------
s2_home a10; s2_inc
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"
check_eq "A10 setup: the includeIf governs the work tree" "$H/work-hooks" "$(tree_hp)"
cp "$H/.gitconfig" "$H/gitconfig.before"
run genv "$isg" --global
check_status "A10: --global over a foreign conditional hooksPath → refused (exit 3)" 3 "$STATUS"
a10err="$(genv "$isg" --global 2>&1 >/dev/null || true)"
check_contains "A10: stderr names the condition" "$a10err" "gitdir:~/work/"
check_contains "A10: ...the file holding the includeIf" "$a10err" "$H/.gitconfig"
check_contains "A10: ...the target file" "$a10err" "$H/work.cfg"
check_contains "A10: ...and the value" "$a10err" "$H/work-hooks"
if cmp -s "$H/.gitconfig" "$H/gitconfig.before"; then pass "A10: ~/.gitconfig unchanged"; else fail "A10: ~/.gitconfig unchanged" "it was written"; fi
check_nodir "A10: no keel-hooks dir created" "$H/$kh_rel"
check_eq "A10: the work tree's hooksPath is unchanged" "$H/work-hooks" "$(tree_hp)"
mk_home a10-ctl; printf '[user]\n\tname = Alice\n' > "$H/.gitconfig"
run genv "$isg" --global
check_status "A10 control: the same home without the includeIf → exit 0" 0 "$STATUS"

# --- A11: --force wires anyway, with a NOTE and no record; --uninstall gives the tree its value back --------
H="$SANDBOX/fx-a10"
cp "$H/work.cfg" "$H/work.cfg.before"
run genv "$isg" --global --force
check_status "A11: --global --force over a conditional conflict → exit 0" 0 "$STATUS"
check_contains "A11: ...prints a NOTE naming the condition" "$OUT" "NOTE — in trees matching gitdir:~/work/"
check_eq "A11: ...and records nothing (the conditional line is not displaced)" "" "$(genv git config --global keel.displacedHooksPath || true)"
run genv "$isg" --global --uninstall
check_status "A11: --uninstall afterwards → exit 0" 0 "$STATUS"
check_eq "A11: ...the work tree's hooksPath is back to its own" "$H/work-hooks" "$(tree_hp)"
if cmp -s "$H/work.cfg" "$H/work.cfg.before"; then pass "A11: work.cfg never written"; else fail "A11: work.cfg never written" "it changed"; fi

# --- A12: no false conflict --------------------------------------------------------------------------------
for sp in tilde slash; do   # Keel's dir spelled ~/… (a literal ~, git's to expand), then with a trailing slash
  s2_home "a12a-$sp"; s2_inc
  # shellcheck disable=SC2088  # a LITERAL ~/ as a user writes it into git config
  if [ "$sp" = tilde ]; then v="~/$kh_rel"; else v="$H/$kh_rel/"; fi
  printf '[core]\n\thooksPath = %s\n' "$v" > "$H/work.cfg"
  run genv "$isg" --global
  check_status "A12(a): a conditional hooksPath naming Keel's dir as '$v' → exit 0" 0 "$STATUS"
  check_absent "A12(a): ...and no NOTE" "$OUT" "in trees matching"
done
mk_home a12b; mkdir -p "$H/work"
printf '[core]\n\thooksPath = %s/foreign\n' "$H" > "$H/foreign.cfg"
n=${GIT_CONFIG_COUNT:-0}
run genv "GIT_CONFIG_KEY_$n=includeIf.gitdir:$H/work/.path" "GIT_CONFIG_VALUE_$n=$H/foreign.cfg" "GIT_CONFIG_COUNT=$((n + 1))" "$isg" --global
check_status "A12(b): a command-scope includeIf (tests/lib.sh's shape) is ignored → exit 0" 0 "$STATUS"
s2_home a12c
run genv "$isg" --global
check_status "A12(c) setup: Keel wired" 0 "$STATUS"
s2_inc; printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"
run genv "$isg" --global
check_status "A12(c): a re-run with Keel wired plus a conditional conflict → exit 0, no refusal" 0 "$STATUS"
check_contains "A12(c): ...prints the NOTE" "$OUT" "NOTE — in trees matching gitdir:~/work/"
s2_shim
s2_shim_arm; run genv "PATH=$s2_shim:$PATH" "$isg" --global
check_status "A12(c): a re-run with an incomplete walk → exit 0" 0 "$STATUS"
check_contains "A12(c): ...one NOTE naming the cause" "$OUT" "NOTE — conditional [includeIf] includes could not all be read (the scratch dir mktemp gives sits inside a repository"

# --- A13: the walk's shapes ----------------------------------------------------------------------------------
s2_refused() {  # label needle [runner] — `--global` in $H: exit 3, the needle named, nothing written
  "${3:-run}" genv "$isg" --global
  check_status "A13 $1 → refused (exit 3)" 3 "$STATUS"
  check_contains "A13 $1: ...named" "$OUT" "$2"
  check_nodir "A13 $1: ...nothing written" "$H/$kh_rel"
}
s2_home a13-nest; s2_inc
printf '[includeIf "onbranch:rel"]\n\tpath = nested.cfg\n' > "$H/work.cfg"
printf '[core]\n\thooksPath = %s/nested-hooks\n' "$H" > "$H/nested.cfg"
s2_refused "nested onbranch: inside the target" "gitdir:~/work/ and onbranch:rel"
mk_home a13-sys
printf '[includeIf "gitdir:/srv/"]\n\tpath = srv.cfg\n' > "$H/system.cfg"
printf '[core]\n\thooksPath = %s/srv-hooks\n' "$H" > "$H/srv.cfg"
s2_refused "an includeIf in the SYSTEM file" "$H/srv.cfg"
mk_home a13-incd; mkdir -p "$H/sub"
printf '[include]\n\tpath = sub/extra.cfg\n' > "$H/.gitconfig"
printf '[includeIf "gitdir:~/x/"]\n\tpath = hc.cfg\n' > "$H/sub/extra.cfg"
printf '[core]\n\thooksPath = %s/hc-hooks\n' "$H" > "$H/sub/hc.cfg"
s2_refused "an includeIf inside an [include]d file, relative target resolved beside that file" "$H/sub/hc.cfg"
s2_home a13-empty; s2_inc; printf '[core]\n\thooksPath =\n' > "$H/work.cfg"
s2_refused "an EMPTY conditional hooksPath" "core.hooksPath = '' (every hook off)"
s2_home a13-novalue; s2_inc; printf '[core]\n\thooksPath\n' > "$H/work.cfg"
s2_refused "a VALUELESS conditional hooksPath" "(no value — git fails in those trees)"
s2_home a13-both
printf '[core]\n\thooksPath = %s/mine\n' "$H" > "$H/.gitconfig"; mkdir -p "$H/mine"; s2_inc
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"
s2_refused "a foreign machine-wide hooksPath AND a conditional conflict: the existing refusal first" "already set to '$H/mine'"
check_absent "A13 both: ...the conditional check is not reached" "$OUT" "in trees matching"
run genv "$isg" --global --force
check_status "A13 both, --force → exit 0" 0 "$STATUS"
check_eq "A13 both, --force: the displaced value is recorded" "$H/mine" "$(genv git config --global keel.displacedHooksPath || true)"
check_contains "A13 both, --force: ...and the NOTE printed" "$OUT" "NOTE — in trees matching gitdir:~/work/"

s2_home a13-nopath; printf '[includeIf "gitdir:~/work/"]\n\tpath\n' > "$H/.gitconfig"
run genv "$isg" --global
check_status "A13: a valueless includeIf path key is skipped, as git skips it → exit 0" 0 "$STATUS"
s2_home a13-missing; s2_inc
run genv "$isg" --global
check_status "A13: a missing target is skipped, as git skips it → exit 0" 0 "$STATUS"
s2_home a13-selfc; s2_inc
printf '[core]\n\thooksPath = ~/%s\n[includeIf "onbranch:x"]\n\tpath = work.cfg\n' "$kh_rel" > "$H/work.cfg"
run_bounded genv "$isg" --global
check_status "A13: a conditional self-include whose value is Keel's dir → complete, exit 0" 0 "$STATUS"

incomplete="could not read every conditional [includeIf] include"
s2_home a13-selfu; s2_inc; printf '[include]\n\tpath = work.cfg\n' > "$H/work.cfg"
s2_refused "an unconditional self-[include] in a target (git's own depth error)" "$incomplete (git config failed on $H/work.cfg)" run_bounded
run_bounded genv "$isg" --global --force
check_status "A13 unconditional self-[include], --force → proceeds (exit 0)" 0 "$STATUS"
s2_chain() {  # depth — ~/.gitconfig → c1.cfg → … → c<depth>.cfg, each a conditional include of the next
  local i=1
  printf '[includeIf "gitdir:~/c0/"]\n\tpath = c1.cfg\n' > "$H/.gitconfig"
  while [ "$i" -lt "$1" ]; do
    printf '[includeIf "gitdir:~/c%s/"]\n\tpath = c%s.cfg\n' "$i" "$((i + 1))" > "$H/c$i.cfg"; i=$((i + 1))
  done
  : > "$H/c$1.cfg"
}
mk_home a13-d10; s2_chain 10
run genv "$isg" --global
check_status "A13: a chain 10 deep → complete, exit 0" 0 "$STATUS"
mk_home a13-d11; s2_chain 11
s2_refused "a chain 11 deep" "$incomplete (include depth over 10)"
run genv "$isg" --global --force
check_status "A13 chain 11 deep, --force → proceeds (exit 0)" 0 "$STATUS"
mk_home a13-tab; printf '[includeIf "gitdir:~/work/"]\n\tpath = "a\\tb.cfg"\n' > "$H/.gitconfig"
s2_refused "a target path holding a TAB" "$incomplete (a path holding a TAB or newline:"
run genv "$isg" --global --force
check_status "A13 TAB path, --force → proceeds (exit 0)" 0 "$STATUS"
mk_home a13-shim; s2_shim
s2_shim_arm; run genv "PATH=$s2_shim:$PATH" "$isg" --global
check_status "A13: the scratch probe inside a repo → refused (exit 3)" 3 "$STATUS"
check_contains "A13 scratch probe inside a repo: ...named" "$OUT" "$incomplete (the scratch dir mktemp gives sits inside a repository"
check_nodir "A13 scratch probe inside a repo: ...nothing written" "$H/$kh_rel"
check_nodir "A13 scratch probe inside a repo: ...and the scratch dir mktemp gave is removed, not left in the repo" "$s2_shim_repo/probe"
s2_shim_arm; run genv "PATH=$s2_shim:$PATH" "$isg" --global --force
check_status "A13 scratch probe inside a repo, --force → proceeds (exit 0)" 0 "$STATUS"

# Review findings (polish step 5): shapes the walk must not pass as clean, or refuse needlessly.
# An unreadable target: git warns and exits 1 — the same exit as "not set". It carries a foreign value, so a
# root run (chmod 000 is a no-op for root, CLAUDE.md Linux-leg trap 2) refuses too, as a plain conflict.
s2_home a13-unread; s2_inc
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"; chmod 000 "$H/work.cfg"
run genv "$isg" --global
check_status "A13: an unreadable conditional target → refused (exit 3)" 3 "$STATUS"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_contains "A13 unreadable target: ...as an incomplete walk" "$OUT" "$incomplete (git config failed on $H/work.cfg (unreadable))"
fi
chmod 600 "$H/work.cfg"
# `./work.cfg` names the same file as work.cfg: a self-include spelled that way is complete, not depth 11.
s2_home a13-dotself; s2_inc
printf '[core]\n\thooksPath = ~/%s\n[includeIf "onbranch:x"]\n\tpath = ./work.cfg\n' "$kh_rel" > "$H/work.cfg"
run_bounded genv "$isg" --global
check_status "A13: a conditional self-include spelled ./work.cfg → complete, exit 0" 0 "$STATUS"
# A `~user/` target is one the walk does not resolve: incomplete, never skipped as missing.
s2_home a13-tildeuser; printf '[includeIf "gitdir:~/work/"]\n\tpath = ~alice/work.cfg\n' > "$H/.gitconfig"
s2_refused "a ~user/ target" "$incomplete (an include path this walk cannot resolve: ~alice/work.cfg)"
# A target under a dir that cannot be searched: `-e` is false, but it is not known to be missing (git fails
# there). Foreign-valued, so a root run (which searches anything) refuses too, as a plain conflict.
s2_home a13-locked; mkdir -p "$H/locked"
printf '[includeIf "gitdir:~/work/"]\n\tpath = locked/work.cfg\n' > "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/locked/work.cfg"; chmod 000 "$H/locked"
run genv "$isg" --global
check_status "A13: a target under an unsearchable dir → refused (exit 3)" 3 "$STATUS"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_contains "A13 unsearchable dir: ...as an incomplete walk" "$OUT" "$incomplete (git config failed on $H/locked/work.cfg (a directory on its path cannot be searched))"
fi
chmod 700 "$H/locked"
# A symlink to a target already read is that target: counted once, never a depth step.
s2_home a14-alias; s2_inc
printf '[core]\n\thooksPath = %s/work-hooks\n[includeIf "onbranch:x"]\n\tpath = alias.cfg\n' "$H" > "$H/work.cfg"
ln -s "$H/work.cfg" "$H/alias.cfg"
run genv "$isg" --where --global
check_eq "A14: a symlinked self-include is counted once" "1" "$(wkey conditional)"
# install.sh's Verify: after a refusal over a conditional include, its advice says why a plain re-run would be
# refused again; under --no-hooks it blames the flag, as before.
s2_home a13-verify; s2_inc
printf '[core]\n\thooksPath = %s/work-hooks\n' "$H" > "$H/work.cfg"
run genv "$install" --home "$H/claude-home"
check_contains "A13 install.sh Verify: names the conditional include as the likely refusal" "$OUT" "If it refused over a conditional [includeIf] include that sets its own core.hooksPath"
run genv "$install" --home "$H/claude-home" --no-hooks
check_contains "A13 install.sh Verify --no-hooks: blames the flag" "$OUT" "secret-guard not wired (--no-hooks"
check_absent "A13 install.sh Verify --no-hooks: ...not the conditional include" "$OUT" "If it refused over a conditional"

# --- A14: `conditional=` and doctor's disclosure ----------------------------------------------------------------
s2_home a14; mkdir -p "$H/claude"; s2_inc
printf '[include]\n\tpath = ~/extra.cfg\n' >> "$H/.gitconfig"
printf '[core]\n\thooksPath = %s/work-hooks\n[includeIf "onbranch:rel"]\n\tpath = nested.cfg\n' "$H" > "$H/work.cfg"
printf '[core]\n\thooksPath = %s/nested-hooks\n' "$H" > "$H/nested.cfg"
printf '[includeIf "hasconfig:remote.*.url:https://example.com/**"]\n\tpath = hc.cfg\n' > "$H/extra.cfg"
printf '[core]\n\thooksPath = %s/hc-hooks\n' "$H" > "$H/hc.cfg"
run genv "$isg" --where --global
check_eq "A14: --where --global counts three conditional hooksPath settings" "3" "$(wkey conditional)"
a14line="3 conditional [includeIf] core.hooksPath setting(s) may apply instead of the machine-wide one"
run genv "$doctor" --install "$H/claude"
check_eq "A14: doctor --install discloses them once" "1" "$(grep -cF "$a14line" <<< "$OUT" || true)"
run genv "$doctor" "$H/work/proj"
check_eq "A14: doctor <repo> discloses them once" "1" "$(grep -cF "$a14line" <<< "$OUT" || true)"
s2_shim
s2_shim_arm; run genv "PATH=$s2_shim:$PATH" "$isg" --where --global
check_eq "A14: an incomplete walk → conditional=unknown" "unknown" "$(wkey conditional)"
s2_shim_arm; run genv "PATH=$s2_shim:$PATH" "$doctor" --install "$H/claude"
check_contains "A14: ...and doctor says so" "$OUT" "(conditional [includeIf] includes could not all be read — tools/doctor.sh <repo> judges each repo)"
mk_home a14-none; mkdir -p "$H/claude"
run genv "$isg" --where --global
check_eq "A14 control: no conditional include → no key" "" "$(wkey conditional)"
run genv "$doctor" --install "$H/claude"
check_absent "A14 control: ...and no doctor line" "$OUT" "conditional [includeIf]"

# --- A15 / A16: the prose ------------------------------------------------------------------------------------
check_eq "A15: README no longer says a pull 'refreshes what is already wired'" "0" \
  "$(grep -c 'refreshes what is already wired' "$REPO_ROOT/README.md" || true)"
check_eq "A15: README says the secret-guard hook is a copy (one line)" "1" \
  "$(grep -cF 'the secret-guard hook is a copy' "$REPO_ROOT/README.md" || true)"
check_eq "A16: docs/reference.md names the conditional-include refusal (one line)" "1" \
  "$(grep -cF 'a conditional `[includeIf]` include sets elsewhere' "$REPO_ROOT/docs/reference.md" || true)"

summary
