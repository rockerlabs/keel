#!/usr/bin/env bash
# install-secret-guard — wire the secret-guard hooks.
#
#   install-secret-guard.sh --global         set a machine-global core.hooksPath (covers every repo
#                                            without a local override; the default, zero per-repo work)
#   install-secret-guard.sh <repo-path>      vendor a self-contained copy into one repo (for a repo with
#                                            its own hooksPath, or protection that must travel off-machine)
#   install-secret-guard.sh --force …        overwrite a pre-existing NON-Keel hook / global hooksPath,
#                                            backing it up first (default: refuse and leave your data alone)
#
# Never clobbers your data silently: a pre-existing pre-commit/pre-push (or global core.hooksPath) that
# isn't Keel's own is treated as higher-precedence user data — the install refuses and says how to
# proceed unless you pass --force (which backs up to <hook>.pre-keel.bak first). Bypass a single
# commit/push deliberately with `git ... --no-verify`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/secret-guard"

# --force may sit anywhere on the line; strip it, keep the single subcommand/positional (busybox/bash-3.2
# safe — no arrays). At most one non-flag arg is expected (--global, --help, or a repo path).
force=0
rest=""
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    *) rest="$a" ;;
  esac
done
set -- ${rest:+"$rest"}

install_into() {
  local hooks_dir="$1" h t
  mkdir -p "$hooks_dir"
  # Never silently clobber the user's own hook. Ours carry a "Keel secret-guard" marker; a pre-commit /
  # pre-push without it is the user's data (higher precedence than our default), so refuse and explain.
  # --force backs it up to <hook>.pre-keel.bak, then replaces. (Closes SEC1's pre-commit clobber.)
  for h in pre-commit pre-push; do
    t="$hooks_dir/$h"
    if [ -e "$t" ] && ! grep -qi 'Keel secret-guard' "$t" 2>/dev/null; then
      if [ "$force" = 1 ]; then
        cp "$t" "$t.pre-keel.bak"
        echo "secret-guard: backed up your existing $h → $h.pre-keel.bak (--force)" >&2
      else
        echo "secret-guard: $t exists and is not a Keel hook — refusing to overwrite your data." >&2
        echo "  Re-run with --force to back it up (.pre-keel.bak) and replace, or call secret-scan.sh from" >&2
        echo "  your own hook by hand. Nothing was changed." >&2
        exit 3
      fi
    fi
  done
  cp "$src/secret-scan.sh" "$hooks_dir/secret-scan.sh"
  cp "$src/pre-commit"     "$hooks_dir/pre-commit"
  cp "$src/pre-push"       "$hooks_dir/pre-push"
  cp "$src/range-lib.sh"   "$hooks_dir/range-lib.sh"     # pre-push sources this next to itself
  chmod +x "$hooks_dir/secret-scan.sh" "$hooks_dir/pre-commit" "$hooks_dir/pre-push"
  # Verify the installed copy via selftest — a wired-but-broken gate must fail the install (set -e).
  "$hooks_dir/secret-scan.sh" --selftest | sed 's/^/  /'
}

case "${1:-}" in
  --global)
    dir="${HOME:?install-secret-guard: --global needs HOME set}/.config/git/keel-hooks"
    # Same rule for the machine-global slot: don't replace a hooksPath the user already set to something
    # of their own. (install.sh already guards this before delegating; this protects direct callers too.)
    existing="$(git config --global core.hooksPath 2>/dev/null || true)"
    if [ -n "$existing" ] && [ "$existing" != "$dir" ] && [ "$force" != 1 ]; then
      echo "secret-guard: a global core.hooksPath is already set to '$existing' — not clobbering it." >&2
      echo "  Re-run with --force to replace it, or vendor per-repo: install-secret-guard.sh <repo>" >&2
      exit 3
    fi
    install_into "$dir"
    git config --global core.hooksPath "$dir"
    echo "secret-guard: wired machine-global at $dir (git config --global core.hooksPath)"
    echo "Note: a repo with its own core.hooksPath overrides this — vendor into it directly."
    echo "Optional: block YOUR personal data (name/drives/emails) too — copy"
    echo "  $src/secret-scan-personal.example → ~/.claude/secret-scan-personal and fill it in."
    ;;
  -h|--help)
    cat <<'EOF'
install-secret-guard — wire the secret-guard hooks (block key-shaped secrets on commit/push).

Usage:
  install-secret-guard.sh --global       set a machine-global core.hooksPath (covers every repo)
  install-secret-guard.sh <repo-path>    vendor a self-contained copy into one repo
  install-secret-guard.sh --force …      replace a pre-existing non-Keel hook/hooksPath (backs it up)
  install-secret-guard.sh -h | --help
EOF
    exit 0 ;;
  "" )
    echo "usage: install-secret-guard.sh --global | <repo-path>" >&2; exit 2 ;;
  *)
    repo="$1"
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
    if hp="$(git -C "$repo" config --local core.hooksPath 2>/dev/null)" && [ -n "$hp" ]; then
      install_into "$repo/$hp"
    else
      # The real hooks dir — NOT $repo/.git/hooks: in a worktree/submodule .git is a file and hooks
      # live in the common dir. --git-path resolves it; make it absolute relative to $repo if needed.
      hooks="$(git -C "$repo" rev-parse --git-path hooks)"
      case "$hooks" in /*) ;; *) hooks="$repo/$hooks" ;; esac
      install_into "$hooks"
    fi
    seed="$repo/.secret-scan-allow"
    [ -f "$seed" ] || printf '# Keel secret-guard allowlist\n# <ERE> to drop a matched line; path:<glob> to exclude a path\n' > "$seed"
    echo "secret-guard: vendored into $repo"
    ;;
esac
