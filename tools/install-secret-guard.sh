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
    *) if [ -n "$rest" ]; then
         echo "install-secret-guard.sh: unexpected extra argument '$a' — one repo path (or --global) per run" >&2
         exit 2
       fi
       rest="$a" ;;
  esac
done
set -- ${rest:+"$rest"}

install_into() {
  local hooks_dir="$1" h t
  # Verify the SOURCE before touching $hooks_dir at all (dir #250, "second defect" — see CHANGELOG.md
  # for the felt incident this closed): the selftest used to run LAST here, after the cp's, so a
  # failure left the destination half-wired (files present, but the caller's core.hooksPath write /
  # .secret-scan-allow seed / confirmation never ran). Testing $src (byte-identical to what gets
  # copied below) means a failure now exits BEFORE any cp — $hooks_dir is left exactly as it was.
  # Via `bash`, not a direct exec: $src is tracked executable (100755) in a normal git checkout, but
  # a `bash` invocation doesn't depend on that bit surviving whatever got this file onto disk (a
  # non-mode-preserving archive extraction, e.g.) — the OLD code never had this dependency either,
  # since it ran the selftest against the DESTINATION only after `chmod +x`ing it (code review, dir #250).
  # This checks $src, not the eventual $hooks_dir copy, so on its own it can't catch a destination-
  # specific failure (a noexec mount, a permission/SELinux quirk unique to $hooks_dir) — dir #570 below
  # closes that residual with its own, differently-shaped check on the installed copy.
  bash "$src/secret-scan.sh" --selftest | sed 's/^/  /'
  mkdir -p "$hooks_dir"

  # Track exactly what THIS run places, so a post-copy verification failure below can roll back only
  # what it put there — never a hook some earlier run (or the user) left behind (dir #570, lead #1).
  # Space-separated lists, not arrays: busybox/bash-3.2-safe under `set -u`, matching the top-level
  # arg-parsing above (an empty array expansion crashes on bash <4.4 — keel memory, dir #235-adjacent).
  local copied="" backed_up=""

  # Never silently clobber the user's own hook. Ours carry a "Keel secret-guard" marker; a pre-commit /
  # pre-push without it is the user's data (higher precedence than our default), so refuse and explain.
  # --force backs it up to <hook>.pre-keel.bak, then replaces. (Closes SEC1's pre-commit clobber.)
  for h in pre-commit pre-push; do
    t="$hooks_dir/$h"
    if [ -e "$t" ] && ! grep -qi 'Keel secret-guard' "$t" 2>/dev/null; then
      if [ "$force" = 1 ]; then
        cp "$t" "$t.pre-keel.bak"
        backed_up="$backed_up $h"
        echo "secret-guard: backed up your existing $h → $h.pre-keel.bak (--force)" >&2
      else
        echo "secret-guard: $t exists and is not a Keel hook — refusing to overwrite your data." >&2
        echo "  Re-run with --force to back it up (.pre-keel.bak) and replace, or call secret-scan.sh from" >&2
        echo "  your own hook by hand. Nothing was changed." >&2
        exit 3
      fi
    fi
  done
  cp "$src/secret-scan.sh" "$hooks_dir/secret-scan.sh"; copied="$copied secret-scan.sh"
  cp "$src/pre-commit"     "$hooks_dir/pre-commit";     copied="$copied pre-commit"
  cp "$src/pre-push"       "$hooks_dir/pre-push";       copied="$copied pre-push"
  cp "$src/range-lib.sh"   "$hooks_dir/range-lib.sh";   copied="$copied range-lib.sh"  # pre-push sources this next to itself
  chmod +x "$hooks_dir/secret-scan.sh" "$hooks_dir/pre-commit" "$hooks_dir/pre-push"

  # Verify the INSTALLED copy too (dir #570): the source check above is a PROXY — it can pass while
  # the copy at $hooks_dir still fails for a reason specific to THAT destination (a noexec mount, a
  # permission/SELinux quirk). Deliberately NOT `bash "$hooks_dir/secret-scan.sh" --selftest` here —
  # that would re-run the same proxy check one directory over: `bash file` reads the file as a script
  # argument and never execs it, so it neither depends on the x bit nor on the filesystem permitting
  # exec, which is exactly what a noexec mount blocks. Git itself invokes an installed hook by DIRECT
  # exec (this file's own pre-commit/pre-push call `secret-scan.sh` the same way, not through `bash`),
  # so verifying the installed copy the same way — direct exec — is what actually reaches a noexec
  # mount or a lost/blocked execute bit; `bash`-mediated verification structurally cannot.
  local verify_err="" verify_ok=0
  verify_err="$("$hooks_dir/secret-scan.sh" --selftest 2>&1)" && verify_ok=1 || verify_ok=0
  if [ "$verify_ok" != 1 ]; then
    echo "secret-guard: the INSTALLED copy at $hooks_dir failed its post-copy selftest — rolling back" >&2
    [ -n "$verify_err" ] && echo "$verify_err" | sed 's/^/  /' >&2
    for h in $copied; do rm -f "$hooks_dir/$h"; done
    # Restore ONLY hooks this run itself backed up — never a hook a different run or the user placed.
    for h in $backed_up; do mv -f "$hooks_dir/$h.pre-keel.bak" "$hooks_dir/$h"; done
    echo "secret-guard: rolled back — $hooks_dir left as it was before this run" >&2
    exit 4
  fi
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
      # hooksPath may be absolute — joining it under $repo would vendor into a junk dir while the
      # real hooks dir stays empty (guard silently inactive). Mirror doctor.sh's handling.
      case "$hp" in /*) hpd="$hp" ;; *) hpd="$repo/$hp" ;; esac
      install_into "$hpd"
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
