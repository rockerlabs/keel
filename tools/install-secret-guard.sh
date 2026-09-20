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

# dir #570: undo exactly what one install_into() run placed — never a hook a different run or the
# user left behind — and exit non-zero, so "either fully wired or untouched" holds no matter WHICH
# step in install_into's copy/verify span failed (a cp, a chmod, or the post-copy selftest). One
# shared helper, called from every failure point below, instead of duplicating the rollback loop at
# each one: args are hooks_dir, the copied-files list, the restore-from-backup list, a one-line
# reason, and an optional detail block (e.g. a failed selftest's own output) to print indented under
# it. Every rm/mv below is individually best-effort (`|| { ok=0; ... }`, never a bare statement):
# `_isg_rollback` runs as the RIGHT-hand side of the `||` at each call site, so — unlike its OWN
# caller's failing command, which IS exempt from `set -e` as the left operand of `||` — nothing
# inside this function gets that exemption; a single failed rm/mv here would otherwise abort under
# `set -e` mid-loop, leaving every remaining file un-rolled-back and skipping the closing message
# and `exit 4` entirely (code review finding, verified live: reproduced the exact `cmd || fn` shape
# with a failing loop body and confirmed the abort). Best-effort means one bad restore doesn't stop
# the rest of the cleanup from at least being attempted.
_isg_rollback() {
  local hooks_dir="$1" copied="$2" restore="$3" reason="$4" detail="${5:-}" f ok=1
  echo "secret-guard: $reason — rolling back" >&2
  [ -n "$detail" ] && echo "$detail" | sed 's/^/  /' >&2
  for f in $copied; do
    rm -f "$hooks_dir/$f" || { ok=0; echo "secret-guard: could not remove $hooks_dir/$f — remove it by hand" >&2; }
  done
  # Restore ONLY files this run itself backed up (hooks or the vendored scanner/lib alike) — never
  # something a different run or the user placed.
  for f in $restore; do
    mv -f "$hooks_dir/$f.pre-keel.bak" "$hooks_dir/$f" \
      || { ok=0; echo "secret-guard: could not restore $hooks_dir/$f from $hooks_dir/$f.pre-keel.bak — restore it by hand" >&2; }
  done
  if [ "$ok" = 1 ]; then
    echo "secret-guard: rolled back — $hooks_dir left as it was before this run" >&2
  else
    echo "secret-guard: rollback INCOMPLETE — see the lines above for what to fix by hand in $hooks_dir" >&2
  fi
  exit 4
}

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

  # Track exactly what THIS run places, so a failure anywhere below — a cp, a chmod, or the post-copy
  # verify — can roll back only what it put there, never a hook some earlier run (or the user) left
  # behind (dir #570, lead #1). Space-separated lists, not arrays: busybox/bash-3.2-safe under
  # `set -u`, matching the top-level arg-parsing above (an empty array expansion crashes on bash
  # <4.4 — keel memory, dir #235-adjacent). Two separate backup lists, not one, because they differ
  # in what happens to the .bak on SUCCESS: `backed_up` (a FOREIGN hook, --force'd) keeps its .bak
  # permanently, by design, so the user can recover their original file; `upgraded` (an existing
  # KEEL hook being re-vendored) is a purely internal safety net for THIS run's own rollback and is
  # deleted once the new copy is confirmed working, below.
  local copied="" backed_up="" upgraded=""

  # Never silently clobber the user's own hook. Ours carry a "Keel secret-guard" marker; a pre-commit /
  # pre-push without it is the user's data (higher precedence than our default), so refuse and explain.
  # --force backs it up to <hook>.pre-keel.bak, then replaces. (Closes SEC1's pre-commit clobber.)
  for h in pre-commit pre-push; do
    t="$hooks_dir/$h"
    if [ -e "$t" ]; then
      if grep -qi 'Keel secret-guard' "$t" 2>/dev/null; then
        # Already ours — re-vendoring over it needs no --force and no refuse-and-ask. But the cp
        # below is about to overwrite a WORKING hook, so it still needs a backup: without one, a
        # later failure in this same run (the next cp, chmod, or the post-copy verify) rolled back
        # by deleting the just-copied file and leaving NO hook at all — not "left as it was before
        # this run" as rollback claims, but a silent loss of the working guard (code review finding).
        cp "$t" "$t.pre-keel.bak"
        upgraded="$upgraded $h"
      elif [ "$force" = 1 ]; then
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
  # secret-scan.sh and range-lib.sh are always Keel's own — no clobber-refuse needed, unlike
  # pre-commit/pre-push above — but if either already exists (an earlier successful install), it
  # still needs the SAME safety-net backup as an "upgraded" pre-commit/pre-push: a later failure in
  # this run must restore the still-working prior version, not just delete it. Without this, restoring
  # pre-commit/pre-push above while secret-scan.sh/range-lib.sh stayed deleted left a restored hook
  # that sources/calls a now-missing file and crashes instead of blocking a push (code review finding,
  # caught live by this file's own new re-vendor-then-fail test).
  for f in secret-scan.sh range-lib.sh; do
    t="$hooks_dir/$f"
    if [ -e "$t" ]; then
      cp "$t" "$t.pre-keel.bak"
      upgraded="$upgraded $f"
    fi
  done

  # "Either fully wired or untouched" has to hold against a destination-specific failure ANYWHERE in
  # this span, not just the post-copy verify below (dir #570, altitude review) — a `cp`/`chmod` that
  # fails partway through (disk full, a permission/SELinux quirk on $hooks_dir itself) is the identical
  # half-wired shape dir #250 already closed for the pre-copy source check, so every step here is
  # checked and rolls back the same way on failure, via the one shared helper below. `copied` gains
  # each filename BEFORE its own `cp` runs, not after: a `cp` that fails partway through can still
  # leave a truncated file at the destination (the disk-full case named above), and that filename
  # has to be in the rollback's `rm -f` list even though ITS OWN copy never finished (code review
  # finding) — `rm -f` is a harmless no-op on a file that never got created at all.
  for f in secret-scan.sh pre-commit pre-push range-lib.sh; do  # pre-push sources range-lib.sh next to itself
    copied="$copied $f"
    cp "$src/$f" "$hooks_dir/$f" || _isg_rollback "$hooks_dir" "$copied" "$backed_up $upgraded" "failed to copy $f into $hooks_dir"
  done
  chmod +x "$hooks_dir/secret-scan.sh" "$hooks_dir/pre-commit" "$hooks_dir/pre-push" || \
    _isg_rollback "$hooks_dir" "$copied" "$backed_up $upgraded" "failed to make the installed copy executable"

  # Verify the INSTALLED copy too (dir #570): the source check above is a PROXY — it can pass while
  # the copy at $hooks_dir still fails for a reason specific to THAT destination (a noexec mount, a
  # permission/SELinux quirk). Deliberately NOT `bash "$hooks_dir/secret-scan.sh" --selftest` here —
  # that would re-run the same proxy check one directory over: `bash file` reads the file as a script
  # argument and never execs it, so it neither depends on the x bit nor on the filesystem permitting
  # exec, which is exactly what a noexec mount blocks. Git itself invokes an installed hook by DIRECT
  # exec (this file's own pre-commit/pre-push call `secret-scan.sh` the same way, not through `bash`),
  # so verifying the installed copy the same way — direct exec — is what actually reaches a noexec
  # mount or a lost/blocked execute bit; `bash`-mediated verification structurally cannot.
  local verify_err=""
  if ! verify_err="$("$hooks_dir/secret-scan.sh" --selftest 2>&1)"; then
    _isg_rollback "$hooks_dir" "$copied" "$backed_up $upgraded" \
      "the INSTALLED copy at $hooks_dir failed its post-copy selftest" "$verify_err"
  fi

  # The install is confirmed working — the safety-net backup of an existing KEEL hook this run
  # re-vendored over is no longer needed. Unlike --force's own backup of a FOREIGN hook (kept
  # permanently, on purpose, so the user can recover it), this one was only ever for THIS run's own
  # rollback, so a successful run leaves no stray .pre-keel.bak behind for it.
  for h in $upgraded; do rm -f "$hooks_dir/$h.pre-keel.bak"; done
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
