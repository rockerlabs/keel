# shellcheck shell=bash
# tools/lib/git-global-paths.sh — which files git itself reads as machine-global config, and which
# directory its machine-wide `core.hooksPath` names (dir #437 PR2, MW1 a-c). One definition for the
# machine-global watcher (tools/machine-watch.sh). `git_global_hooks_dir` is a named twin of
# `tools/install-secret-guard.sh --where --global`'s `dir=` (that script ships standalone and cannot
# source this file): the watcher keeps the twin for its hot path (one scratch-dir read per watched tool
# call), and `tests/test_git_global_paths.sh` pins the two to the same answer for every shape a hooksPath
# can arrive in. Two more named copies of the `~/` expansion (dir #659): install.sh's `keel_hooks_is` and
# tools/install-secret-guard.sh's `_isg_norm_path` — the last ships standalone and can never source this
# file.
#
# Sourced, not executed: no shebang, no set -e (inherits the caller's), no set -u assumption.
#
# Every function resolves in the CALLER's environment, on purpose: the watcher runs as a hook, in the
# harness's own env, so a command's sandbox variables (GIT_CONFIG_GLOBAL, HOME) cannot hide the real
# machine from its watcher. Every function prints one path per line and nothing else; a failure to
# resolve prints nothing.
#
# `git var GIT_CONFIG_GLOBAL` / `GIT_CONFIG_SYSTEM` is git's own answer, but not on every git: Apple's
# /usr/bin/git 2.39 answers `usage: git var (-l | <variable>)` with rc 129. Each function therefore
# falls back to the documented resolution rules when `git var` fails or prints nothing.
#
# Names are all `git_global_`-prefixed (tools/lib/manifest.sh's header documents the lib-sourcing
# shadowing hazard).

# git_global_expand_tilde VALUE — a LITERAL leading `~/` a user wrote into git config, which git returns
# verbatim rather than expanding itself.
# shellcheck disable=SC2088  # matching a LITERAL ~ a user wrote into git config (git returns it verbatim)
git_global_expand_tilde() {
  case "$1" in "~/"*) printf '%s' "${HOME:-}/${1#\~/}" ;; *) printf '%s' "$1" ;; esac
}

# git_global_config_files — the machine-global (user-level) git config files, MW1(a): `git var
# GIT_CONFIG_GLOBAL`'s lines; if `git var` fails, $GIT_CONFIG_GLOBAL when set (it REPLACES the other
# two), else the XDG file and ~/.gitconfig.
git_global_config_files() {
  local out
  if out="$(git var GIT_CONFIG_GLOBAL 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then
    printf '%s\n' "$GIT_CONFIG_GLOBAL"
    return 0
  fi
  [ -n "${HOME:-}" ] || return 0
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" "$HOME/.gitconfig"
}

# git_global_system_config_file — the system-level git config file, MW1(b): `git var GIT_CONFIG_SYSTEM`;
# if that fails, $GIT_CONFIG_SYSTEM when set, nothing when GIT_CONFIG_NOSYSTEM is true, else
# /etc/gitconfig. (`git var` itself exits 1 under GIT_CONFIG_NOSYSTEM, so a real answer and the
# fallback agree.)
git_global_system_config_file() {
  local out
  if out="$(git var GIT_CONFIG_SYSTEM 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  if [ -n "${GIT_CONFIG_SYSTEM:-}" ]; then
    printf '%s\n' "$GIT_CONFIG_SYSTEM"
    return 0
  fi
  case "${GIT_CONFIG_NOSYSTEM:-}" in 1|true|yes|on) return 0 ;; esac
  printf '%s\n' /etc/gitconfig
}

# git_global_hooks_dir — the effective machine-wide `core.hooksPath` directory, MW1(c): read WITHOUT a
# --global restriction (git's own effective resolution merges the XDG file in behind an existing
# ~/.gitconfig; `--global` collapses to one file) from a fresh non-repo scratch dir, so nothing at LOCAL
# scope — a repo the hook happens to run in — can leak into what must be a machine-wide read. `~/` is
# expanded and one trailing slash dropped (`/` stays `/`), as the installer's `_isg_norm_path` does. Prints
# nothing when unset or RELATIVE (a relative path names a different directory in every
# repo, so it is no machine-global location). If the scratch dir turns out to sit inside a repo (an odd
# TMPDIR), falls back to the narrower `git config --global` read rather than risk reading that repo's
# local scope.
git_global_hooks_dir() {
  local probe val
  probe="$(mktemp -d 2>/dev/null)" || probe=""
  if [ -n "$probe" ] && ! git -C "$probe" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    val="$(git -C "$probe" config core.hooksPath 2>/dev/null || true)"
  else
    val="$(git config --global core.hooksPath 2>/dev/null || true)"
  fi
  [ -z "$probe" ] || rmdir "$probe" 2>/dev/null || true
  val="$(git_global_expand_tilde "$val")"
  [ "$val" = / ] || val="${val%/}"
  case "$val" in /*) printf '%s\n' "$val" ;; esac
}
