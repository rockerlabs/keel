#!/usr/bin/env bash
# install-secret-guard — wire the secret-guard hooks.
#
#   install-secret-guard.sh --global        set a machine-global core.hooksPath (covers every repo
#                                           without a local override; the default, zero per-repo work)
#   install-secret-guard.sh <repo-path>     vendor a self-contained copy into one repo (for a repo with
#                                           its own hooksPath, or protection that must travel off-machine)
#
# Bypass a single commit/push deliberately with `git ... --no-verify`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/secret-guard"

install_into() {
  local hooks_dir="$1"
  mkdir -p "$hooks_dir"
  cp "$src/secret-scan.sh" "$hooks_dir/secret-scan.sh"
  cp "$src/pre-commit"     "$hooks_dir/pre-commit"
  cp "$src/pre-push"       "$hooks_dir/pre-push"
  chmod +x "$hooks_dir/secret-scan.sh" "$hooks_dir/pre-commit" "$hooks_dir/pre-push"
}

case "${1:-}" in
  --global)
    dir="${HOME}/.config/git/keel-hooks"
    install_into "$dir"
    git config --global core.hooksPath "$dir"
    echo "secret-guard: wired machine-global at $dir (git config --global core.hooksPath)"
    echo "Note: a repo with its own core.hooksPath overrides this — vendor into it directly."
    ;;
  "" )
    echo "usage: install-secret-guard.sh --global | <repo-path>" >&2; exit 2 ;;
  *)
    repo="$1"
    [ -d "$repo/.git" ] || { echo "not a git repo: $repo" >&2; exit 2; }
    if hp="$(git -C "$repo" config --local core.hooksPath 2>/dev/null)" && [ -n "$hp" ]; then
      install_into "$repo/$hp"
    else
      install_into "$repo/.git/hooks"
    fi
    seed="$repo/.secret-scan-allow"
    [ -f "$seed" ] || printf '# Keel secret-guard allowlist\n# <ERE> to drop a matched line; path:<glob> to exclude a path\n' > "$seed"
    echo "secret-guard: vendored into $repo"
    ;;
esac
