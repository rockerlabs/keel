#!/usr/bin/env bash
# tools/lib/git-global-paths.sh (dir #437 PR2, MW1 a-c): which files git reads as machine-global config and
# which directory its machine-wide core.hooksPath names — each with the documented fallback when `git var`
# is unavailable (Apple's /usr/bin/git 2.39 answers rc 129). Every case runs in a throwaway HOME.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }
# dir #658: tools/lib/git-global-paths.sh, sourced below, runs `git -C` in its own `mktemp -d` probe dir
# (outside $SANDBOX); tests/lib.sh's `git -C` guard admits such temp dirs only on this opt-in.
GIT_C_GUARD_ALLOW_TMP=1

lib="$REPO_ROOT/tools/lib/git-global-paths.sh"
# shellcheck source=tools/lib/git-global-paths.sh
. "$lib"

stub="$SANDBOX/stub-nogitvar"
git_var_stub_dir "$stub"

# --- git_global_expand_tilde ---------------------------------------------------------------------------
h="$SANDBOX/g1"; mkdir -p "$h"
# shellcheck disable=SC2088  # the point is a LITERAL ~ a user wrote into git config
check_eq "expand_tilde: a literal leading ~/ expands to HOME" "$h/hooks" "$(HOME="$h" git_global_expand_tilde '~/hooks')"
check_eq "expand_tilde: an absolute path is untouched" "/x/y" "$(HOME="$h" git_global_expand_tilde '/x/y')"
check_eq "expand_tilde: a relative path is untouched" "hooks" "$(HOME="$h" git_global_expand_tilde 'hooks')"

# --- git_global_config_files ---------------------------------------------------------------------------
check_eq "config_files: GIT_CONFIG_GLOBAL replaces the other two (git var)" "$h/only.cfg" \
  "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/only.cfg" git_global_config_files)"
check_eq "config_files: git var failing, GIT_CONFIG_GLOBAL still wins (fallback)" "$h/only.cfg" \
  "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/only.cfg" PATH="$stub:$PATH" git_global_config_files)"
out="$(unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME; HOME="$h" PATH="$stub:$PATH" git_global_config_files)"
check_eq "config_files: git var failing, nothing set -> the XDG file then ~/.gitconfig" \
  "$h/.config/git/config
$h/.gitconfig" "$out"
out="$(unset GIT_CONFIG_GLOBAL; HOME="$h" XDG_CONFIG_HOME="$h/xdg" PATH="$stub:$PATH" git_global_config_files)"
check_eq "config_files: XDG_CONFIG_HOME steers the fallback" "$h/xdg/git/config
$h/.gitconfig" "$out"

# --- git_global_system_config_file ---------------------------------------------------------------------
check_eq "system: git var failing, GIT_CONFIG_SYSTEM set -> it" "$h/sys.cfg" \
  "$(GIT_CONFIG_SYSTEM="$h/sys.cfg" PATH="$stub:$PATH" git_global_system_config_file)"
check_eq "system: git var failing, GIT_CONFIG_NOSYSTEM true -> nothing" "" \
  "$(unset GIT_CONFIG_SYSTEM; GIT_CONFIG_NOSYSTEM=1 PATH="$stub:$PATH" git_global_system_config_file)"
check_eq "system: git var failing, nothing set -> /etc/gitconfig" "/etc/gitconfig" \
  "$(unset GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM; PATH="$stub:$PATH" git_global_system_config_file)"
check_eq "system: real git var under GIT_CONFIG_NOSYSTEM -> nothing" "" \
  "$(unset GIT_CONFIG_SYSTEM; GIT_CONFIG_NOSYSTEM=1 git_global_system_config_file)"

# --- git_global_hooks_dir ------------------------------------------------------------------------------
mkdir -p "$h/hooks"
git config --file "$h/cfg" core.hooksPath "$h/hooks"
check_eq "hooks_dir: an absolute core.hooksPath -> that dir" "$h/hooks" \
  "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/cfg" git_global_hooks_dir)"
# shellcheck disable=SC2088  # same: a literal ~/ as git stores it
git config --file "$h/cfg" core.hooksPath '~/hooks'
check_eq "hooks_dir: a literal ~/ is expanded" "$h/hooks" \
  "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/cfg" git_global_hooks_dir)"
git config --file "$h/cfg" core.hooksPath 'relative/hooks'
check_eq "hooks_dir: a RELATIVE path names a different dir per repo -> nothing" "" \
  "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/cfg" git_global_hooks_dir)"
: > "$h/empty.cfg"
check_eq "hooks_dir: unset -> nothing" "" "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/empty.cfg" git_global_hooks_dir)"
# the probe runs from a non-repo scratch dir: a LOCAL core.hooksPath of the caller's cwd must not leak in
repo="$(new_repo)"; git -C "$repo" config core.hooksPath "$repo/local-hooks"
check_eq "hooks_dir: a repo's LOCAL core.hooksPath does not leak into the machine-wide read" "" \
  "$(cd "$repo" && HOME="$h" GIT_CONFIG_GLOBAL="$h/empty.cfg" git_global_hooks_dir)"

# dir #748 S4-3 (spec 685 A53): the root directory is the one path whose trailing slash is not a slash to drop —
# `[ "$val" = / ] || val="${val%/}"` keeps it, and without the guard `/` collapses to "" and reads as unset.
printf '[core]\n\thooksPath = /\n' > "$h/root.cfg"
check_eq "hooks_dir: a global core.hooksPath of / stays /" "/" \
  "$(HOME="$h" GIT_CONFIG_GLOBAL="$h/root.cfg" git_global_hooks_dir)"

# --- A7: parity with the producer — dir #688 -------------------------------------------------------------
# tools/lib/git-global-paths.sh's git_global_hooks_dir is a NAMED TWIN of `install-secret-guard.sh --where
# --global`'s dir= (that script ships standalone and cannot source this file). The watcher keeps the twin
# for its hot path (a 57 ms vs 99 ms call), so a test — not a shared definition — holds the two to the same
# answer: for every shape a hooksPath can arrive in, the strings are equal (both empty when unset or relative).
isg="$REPO_ROOT/tools/install-secret-guard.sh"
parity() {  # parity <label> <env assignments / -u flags…> — both resolvers under the SAME environment
  local label="$1"; shift
  local lib_out where_out
  lib_out="$(env "$@" bash -c '. "$1"; git_global_hooks_dir' _ "$lib" 2>/dev/null)"
  where_out="$(env "$@" "$isg" --where --global 2>/dev/null | sed -n 's/^dir=//p')"
  check_eq "parity ($label): git_global_hooks_dir == --where --global's dir=" "$where_out" "$lib_out"
}
pw="$SANDBOX/par"; mkdir -p "$pw/hooks" "$pw/xdg/git"; : > "$pw/sys.cfg"
pbase=("HOME=$pw" "GIT_CONFIG_SYSTEM=$pw/sys.cfg")
: > "$pw/g.cfg"
parity "unset" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
printf '[core]\n\thooksPath = %s/hooks\n' "$pw" > "$pw/g.cfg"
parity "absolute" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
printf '[core]\n\thooksPath = ~/hooks\n' > "$pw/g.cfg"
parity "tilde" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
printf '[core]\n\thooksPath = %s/hooks/\n' "$pw" > "$pw/g.cfg"
parity "trailing slash" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
check_eq "parity: the trailing slash is dropped (the twin's own answer)" "$pw/hooks" \
  "$(env "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg" bash -c '. "$1"; git_global_hooks_dir' _ "$lib")"
printf '[core]\n\thooksPath = relative/hooks\n' > "$pw/g.cfg"
parity "relative" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
printf '[include]\n\tpath = %s/inc.cfg\n' "$pw" > "$pw/g.cfg"
printf '[core]\n\thooksPath = %s/hooks\n' "$pw" > "$pw/inc.cfg"
parity "[include]" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
: > "$pw/g.cfg"
printf '[core]\n\thooksPath = %s/hooks\n' "$pw" > "$pw/sys.cfg"
parity "SYSTEM" "${pbase[@]}" "GIT_CONFIG_GLOBAL=$pw/g.cfg"
: > "$pw/sys.cfg"
printf '[user]\n\tname = Alice\n' > "$pw/.gitconfig"
printf '[core]\n\thooksPath = %s/hooks\n' "$pw" > "$pw/xdg/git/config"
parity "XDG behind ~/.gitconfig" -u GIT_CONFIG_GLOBAL "${pbase[@]}" "XDG_CONFIG_HOME=$pw/xdg"

summary
