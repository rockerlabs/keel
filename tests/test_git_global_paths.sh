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

summary
