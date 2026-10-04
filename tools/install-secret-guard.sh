#!/usr/bin/env bash
# install-secret-guard — wire the secret-guard hooks.
#
#   install-secret-guard.sh --global         set a machine-global core.hooksPath (covers every repo
#                                            without a local override; the default, zero per-repo work)
#   install-secret-guard.sh <repo-path>      vendor a self-contained copy into one repo (for a repo with
#                                            its own hooksPath, or protection that must travel off-machine)
#   install-secret-guard.sh --force …        overwrite a pre-existing NON-Keel hook (backed up first) or
#                                            global hooksPath (its old value recorded first)
#                                            (default: refuse and leave your data alone)
#   install-secret-guard.sh --global --uninstall
#                                            unwire the global guard: restore the hooksPath --force
#                                            displaced, or unset it (the hook files stay on disk)
#
# Never clobbers your data silently: a pre-existing pre-commit/pre-push (or global core.hooksPath) that
# isn't Keel's own is treated as higher-precedence user data — the install refuses and says how to
# proceed unless you pass --force (which backs up to <hook>.pre-keel.bak first, and refuses — naming the
# saved file — if that backup already exists, so an earlier saved hook is never overwritten; for the
# global hooksPath it records the old value in `git config --global keel.displacedHooksPath`, under the
# same never-overwrite rule). A hook is Keel's only when its line 2 is exactly the shipped hook's
# marker line; a symlink at any path the install writes is refused, never written through. Bypass a
# single commit/push deliberately with `git ... --no-verify`.
set -euo pipefail
# dir #644: unconditional, at the top — before this script's first git call, whichever branch it
# turns out to be, not gated behind reaching the <repo> branch below. An inherited GIT_DIR /
# GIT_COMMON_DIR / GIT_WORK_TREE / GIT_INDEX_FILE redirects `git -C "$repo"` — including the validity
# gate itself — into a DIFFERENT repository than the one named on the command line, so this can pass a
# non-git $repo as valid and vendor the hook write somewhere else entirely
# (docs/specs/318-test-ref-isolation.md E19(c)). Inlined rather than sourced from
# tools/lib/repo-arg-guard.sh: this script is designed to be copied standalone alongside only its
# sibling secret-guard/ dir (see the header and this file's own test fixtures in
# tests/test_secret_guard.sh, which run scratch copies that carry no tools/lib/) — that lib's own
# header explains why install-read-trace.sh and install-pre-pr-gate.sh share it instead.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/secret-guard"

# The two backup-suffix conventions, named once so every writer/restorer/message below references
# the same value instead of re-typing it (code-review finding: 7 independent literal occurrences
# risked drifting out of sync on a future rename — the RC-audit regression this file's own history
# closed was exactly this class of collision, one suffix shared by two writers that should never
# have touched the same path). isg_bak_force is --force's PERMANENT backup of a foreign hook;
# isg_bak_upgrade is a re-install's own RUN-SCOPED safety net for an existing Keel hook/scanner —
# see _isg_rollback's own comment for why they must never collide.
isg_bak_force="pre-keel.bak"
isg_bak_upgrade="keel-upgrade.bak"
# Every file install_into copies, named once: the copy loop and the symlink pre-flight (dir #659) read
# the same list, so a newly shipped file can't be copied without also being guarded.
isg_files="secret-scan.sh pre-commit pre-push range-lib.sh"  # pre-push sources range-lib.sh next to itself

# --force may sit anywhere on the line; strip it, keep the single subcommand/positional (busybox/bash-3.2
# safe — no arrays). At most one non-flag arg is expected (--global, --help, or a repo path).
force=0
uninstall=0
rest=""
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
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
# each one: args are hooks_dir, the copied-files list, the two restore-from-backup lists (kept
# SEPARATE, not smuggled into one string — see the two-suffix note below), a one-line reason, and an
# optional detail block (e.g. a failed selftest's own output) to print indented under it. Every
# rm/mv below is individually best-effort (`|| { ok=0; ... }`, never a bare statement): `_isg_rollback`
# runs as the RIGHT-hand side of the `||` at each call site, so — unlike its OWN caller's failing
# command, which IS exempt from `set -e` as the left operand of `||` — nothing inside this function
# gets that exemption; a single failed rm/mv here would otherwise abort under `set -e` mid-loop,
# leaving every remaining file un-rolled-back and skipping the closing message and `exit 4` entirely
# (code review finding, verified live: reproduced the exact `cmd || fn` shape with a failing loop
# body and confirmed the abort). Best-effort means one bad restore doesn't stop the rest of the
# cleanup from at least being attempted.
_isg_rollback() {
  local hooks_dir="$1" copied="$2" backed_up="$3" upgraded="$4" reason="$5" detail="${6:-}" \
    f ok=1 pair list suffix
  echo "secret-guard: $reason — rolling back" >&2
  [ -n "$detail" ] && echo "$detail" | sed 's/^/  /' >&2
  for f in $copied; do
    rm -f "$hooks_dir/$f" || { ok=0; echo "secret-guard: could not remove $hooks_dir/$f — remove it by hand" >&2; }
  done
  # Restore ONLY files this run itself backed up — never something a different run or the user
  # placed. $backed_up (a FOREIGN hook, --force'd) restores from its PERMANENT .pre-keel.bak;
  # $upgraded (an existing KEEL hook/scanner this run re-vendored over) restores from its own
  # run-scoped .keel-upgrade.bak. Two suffixes, not one, so this can never mv a permanent --force
  # backup back over itself and then have the success path below delete it out from under a later
  # plain re-install (regression the RC audit caught: both writers used to share .pre-keel.bak, so
  # an ordinary re-vendor's cleanup deleted the user's --force backup). One list:suffix loop, not
  # two copy-pasted ones, so the restore/error-message logic has a single place to change.
  for pair in "$backed_up:$isg_bak_force" "$upgraded:$isg_bak_upgrade"; do
    list="${pair%%:*}" suffix="${pair#*:}"
    for f in $list; do
      mv -f "$hooks_dir/$f.$suffix" "$hooks_dir/$f" \
        || { ok=0; echo "secret-guard: could not restore $hooks_dir/$f from $hooks_dir/$f.$suffix — restore it by hand" >&2; }
    done
  done
  if [ "$ok" = 1 ]; then
    echo "secret-guard: rolled back — $hooks_dir left as it was before this run" >&2
  else
    echo "secret-guard: rollback INCOMPLETE — see the lines above for what to fix by hand in $hooks_dir" >&2
  fi
  exit 4
}

# Ours carry an exact marker LINE: line 2 of the installed <hook> equals line 2 of the shipped <hook>
# (args: the installed path, the hook's name) — never a substring, which let a user's hook that merely
# names the tool read as ours (dir #659, S3-1). Line 2 is unchanged in every shipped version, so older
# installs still match; tests/test_secret_guard.sh pins it, since rewording it orphans them all.
_isg_is_keel_hook() {
  local marker
  marker="$(sed -n 2p "$src/$2")"
  [ -n "$marker" ] && [ "$(sed -n 2p "$1" 2>/dev/null)" = "$marker" ]
}

install_into() {
  local hooks_dir="$1" h t f l
  # Pre-flight (dir #659, S3-2): every `cp` below follows a symlink at its destination, so a linked hook
  # path would have its TARGET rewritten — a dotfiles hook, or a hook file shared by other repos (the
  # 0.11.0 F1 class: a per-repo install mutating a machine-shared file). Refuse — with or without
  # --force, and before the selftest, so a refusal costs nothing — naming the target so the user can
  # decide what owns it. The run-scoped .keel-upgrade.bak is a `cp` destination too; --force's
  # .pre-keel.bak has its own check below (dir #625).
  for f in $isg_files; do
    for t in "$hooks_dir/$f" "$hooks_dir/$f.$isg_bak_upgrade"; do
      if [ -L "$t" ]; then
        l="$(readlink "$t" 2>/dev/null || echo '?')"
        echo "secret-guard: $t is a symlink (→ $l) — refusing to write through it: that would" >&2
        echo "  rewrite the file it points to. Replace the link with a regular file (or remove it), then" >&2
        echo "  re-run. Nothing was changed." >&2
        exit 3
      fi
    done
  done
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
  # <4.4 — keel memory, dir #235-adjacent). Two separate backup lists, AND two separate backup
  # SUFFIXES, because they differ in what happens to the .bak on SUCCESS: `backed_up` (a FOREIGN
  # hook, --force'd) writes to `.pre-keel.bak` and keeps it permanently, by design, so the user can
  # recover their original file; `upgraded` (an existing KEEL hook/scanner being re-vendored) writes
  # to the DIFFERENT `.keel-upgrade.bak`, is a purely internal safety net for THIS run's own
  # rollback, and is deleted once the new copy is confirmed working, below. Sharing one suffix
  # between the two used to let an ordinary re-install's cleanup delete the user's own --force
  # backup out from under them (RC audit finding, fixed here): --force a foreign hook → the hook is
  # Keel's now → the NEXT plain re-install took the `upgraded` branch and re-used `.pre-keel.bak` for
  # its OWN run-scoped safety net, which the success path below then deleted — destroying the
  # permanent backup along with it. Distinct suffixes mean the two can never collide on one path.
  local copied="" backed_up="" upgraded=""

  # Never silently clobber the user's own hook. Ours carry the exact marker line (_isg_is_keel_hook); a
  # pre-commit / pre-push without it is the user's data (higher precedence than our default), so refuse and explain.
  # --force backs it up to <hook>.pre-keel.bak, then replaces. (Closes SEC1's pre-commit clobber.)
  #
  # Pre-flight (dir #625): --force's backup at .pre-keel.bak is PERMANENT, so it must never be
  # overwritten. A second --force over a DIFFERENT foreign hook (something external replaced the
  # installed hook after the first --force) would `cp` the new hook over the first one's backup — the
  # earlier hook silently gone. Refuse BEFORE the loop below touches anything, so neither hook gets a
  # backup and nothing is left half-done; name the saved file so the user can move it aside and re-run.
  # `-L` too: a dangling symlink at the backup path makes `-e` false, yet `cp` would write through it.
  if [ "$force" = 1 ]; then
    for h in pre-commit pre-push; do
      t="$hooks_dir/$h"
      if [ -e "$t" ] && ! _isg_is_keel_hook "$t" "$h" \
          && { [ -e "$t.$isg_bak_force" ] || [ -L "$t.$isg_bak_force" ]; }; then
        echo "secret-guard: $t is not a Keel hook, and a backup of an earlier one is already saved at" >&2
        echo "  $t.$isg_bak_force — --force would overwrite it. Move or delete that file, then re-run" >&2
        echo "  with --force. Nothing was changed." >&2
        exit 3
      fi
    done
  fi
  for h in pre-commit pre-push; do
    t="$hooks_dir/$h"
    if [ -e "$t" ]; then
      if _isg_is_keel_hook "$t" "$h"; then
        # Already ours — re-vendoring over it needs no --force and no refuse-and-ask. But the cp
        # below is about to overwrite a WORKING hook, so it still needs a backup: without one, a
        # later failure in this same run (the next cp, chmod, or the post-copy verify) rolled back
        # by deleting the just-copied file and leaving NO hook at all — not "left as it was before
        # this run" as rollback claims, but a silent loss of the working guard (code review finding).
        # `.keel-upgrade.bak`, NOT `.pre-keel.bak` — this branch runs on every ordinary re-install,
        # including one right after a --force install, and must never touch the permanent backup
        # a --force run may have left at `.pre-keel.bak` (see the note above `local copied=`).
        cp "$t" "$t.$isg_bak_upgrade"
        upgraded="$upgraded $h"
      elif [ "$force" = 1 ]; then
        cp "$t" "$t.$isg_bak_force"
        backed_up="$backed_up $h"
        echo "secret-guard: backed up your existing $h → $h.$isg_bak_force (--force)" >&2
      else
        echo "secret-guard: $t exists and is not a Keel hook — refusing to overwrite your data." >&2
        echo "  Re-run with --force to back it up (.$isg_bak_force) and replace, or call secret-scan.sh from" >&2
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
  # caught live by this file's own new re-vendor-then-fail test). Always the `upgraded` suffix — these
  # two files have no foreign-hook clash, so they never touch `.pre-keel.bak`.
  for f in secret-scan.sh range-lib.sh; do
    t="$hooks_dir/$f"
    if [ -e "$t" ]; then
      cp "$t" "$t.$isg_bak_upgrade"
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
  for f in $isg_files; do
    copied="$copied $f"
    cp "$src/$f" "$hooks_dir/$f" || _isg_rollback "$hooks_dir" "$copied" "$backed_up" "$upgraded" "failed to copy $f into $hooks_dir"
  done
  chmod +x "$hooks_dir/secret-scan.sh" "$hooks_dir/pre-commit" "$hooks_dir/pre-push" || \
    _isg_rollback "$hooks_dir" "$copied" "$backed_up" "$upgraded" "failed to make the installed copy executable"

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
    _isg_rollback "$hooks_dir" "$copied" "$backed_up" "$upgraded" \
      "the INSTALLED copy at $hooks_dir failed its post-copy selftest" "$verify_err"
  fi

  # The install is confirmed working — the safety-net backup of an existing KEEL hook this run
  # re-vendored over is no longer needed. Unlike --force's own backup of a FOREIGN hook (kept
  # permanently, on purpose, so the user can recover it, at the DIFFERENT .pre-keel.bak path — left
  # untouched here), this one was only ever for THIS run's own rollback, so a successful run leaves
  # no stray .keel-upgrade.bak behind for it.
  for h in $upgraded; do rm -f "$hooks_dir/$h.$isg_bak_upgrade"; done
}

# dir #659 (S3-3): where --global --force records the core.hooksPath it displaces, for --uninstall to
# restore. A global git config key, not a file in the hooks dir: it sits beside the setting it backs
# up, survives the hooks dir being deleted, and `git config --global --list` shows it.
isg_displaced_key="keel.displacedHooksPath"

if [ "$uninstall" = 1 ] && [ "${1:-}" != --global ]; then
  echo "install-secret-guard.sh: --uninstall works with --global only — a vendored repo copy is removed by deleting its hook files" >&2
  exit 2
fi

case "${1:-}" in
  --global)
    dir="${HOME:?install-secret-guard: --global needs HOME set}/.config/git/keel-hooks"
    existing="$(git config --global core.hooksPath 2>/dev/null || true)"
    recorded="$(git config --global "$isg_displaced_key" 2>/dev/null || true)"
    if [ "$uninstall" = 1 ]; then
      # Unwire only what is Keel's: a hooksPath pointing anywhere else is the user's, left alone. The
      # hook files stay in $dir — inert once nothing points at them; deleting them is the user's call.
      if [ -z "$existing" ]; then
        echo "secret-guard: no global core.hooksPath is set — nothing to unwire."
        exit 0
      fi
      if [ "$existing" != "$dir" ]; then
        echo "secret-guard: the global core.hooksPath is '$existing', not Keel's ($dir) — not touching it." >&2
        [ -n "$recorded" ] && echo "  ($isg_displaced_key still records '$recorded'.)" >&2
        echo "  Nothing was changed." >&2
        exit 3
      fi
      if [ -n "$recorded" ]; then
        git config --global core.hooksPath "$recorded"
        git config --global --unset "$isg_displaced_key"
        echo "secret-guard: unwired — global core.hooksPath restored to '$recorded'."
      else
        git config --global --unset core.hooksPath
        echo "secret-guard: unwired — global core.hooksPath unset (none was set before Keel's)."
      fi
      echo "  Keel's hook files are left in $dir; delete that directory if you no longer want them."
      exit 0
    fi
    # Same rule for the machine-global slot: don't replace a hooksPath the user already set to something
    # of their own. (install.sh already guards this before delegating; this protects direct callers too.)
    displaced=""
    if [ -n "$existing" ] && [ "$existing" != "$dir" ]; then
      displaced="$existing"
      if [ "$force" != 1 ]; then
        echo "secret-guard: a global core.hooksPath is already set to '$existing' — not clobbering it." >&2
        echo "  Re-run with --force to replace it, or vendor per-repo: install-secret-guard.sh <repo>" >&2
        exit 3
      fi
      # --force records what it displaces — and, like the hook backups (dir #625), never overwrites
      # an earlier record of a DIFFERENT path: that one is the only trace of what was there first.
      if [ -n "$recorded" ] && [ "$recorded" != "$existing" ]; then
        echo "secret-guard: $isg_displaced_key already records an earlier displaced hooksPath, '$recorded';" >&2
        echo "  --force would replace that record with '$existing'. Restore or clear it" >&2
        echo "  (git config --global --unset $isg_displaced_key), then re-run with --force. Nothing was changed." >&2
        exit 3
      fi
    fi
    install_into "$dir"
    if [ -n "$displaced" ]; then
      git config --global "$isg_displaced_key" "$displaced"
      echo "secret-guard: replaced the global core.hooksPath '$displaced' (--force); the old value is"
      echo "  recorded in git config --global $isg_displaced_key — install-secret-guard.sh --global --uninstall restores it"
    fi
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
  install-secret-guard.sh --force …      replace a pre-existing non-Keel hook (backs it up) or global
                                         hooksPath (records the old value in keel.displacedHooksPath)
  install-secret-guard.sh --global --uninstall
                                         unwire the global guard: restore the displaced hooksPath, or unset it
  install-secret-guard.sh -h | --help
EOF
    exit 0 ;;
  "" )
    echo "usage: install-secret-guard.sh --global | <repo-path>" >&2; exit 2 ;;
  *)
    repo="$1"
    # dir #644: GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE are already unset (top of file) —
    # this validity gate, and every git -C "$repo" call below it, is trustworthy because of that, not
    # because of anything done here.
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
    if hp="$(git -C "$repo" config --local core.hooksPath 2>/dev/null)" && [ -n "$hp" ]; then
      # hooksPath may be absolute — joining it under $repo would vendor into a junk dir while the
      # real hooks dir stays empty (guard silently inactive). Mirror doctor.sh's handling.
      case "$hp" in /*) hpd="$hp" ;; *) hpd="$repo/$hp" ;; esac
      install_into "$hpd"
    else
      # The real hooks dir — NOT $repo/.git/hooks: in a worktree/submodule .git is a file and hooks
      # live in the common dir. dir #617: `--git-path hooks` (the old resolution here) also honors
      # GLOBAL/SYSTEM core.hooksPath, so a repo with no LOCAL override could resolve straight into a
      # machine-wide hooks dir instead of its own. --git-common-dir names the repo's own git
      # directory and never consults core.hooksPath at any scope — still worktree/submodule-safe like
      # the old call, just without the global-hooksPath leak. Considered instead: keep --git-path
      # hooks and refuse when its result lies outside $repo — rejected because a submodule's real
      # hooks dir legitimately lives under the SUPERPROJECT's .git/modules/, outside $repo's own
      # tree, so an "under $repo" containment check would misfire there. (Full incident history:
      # CHANGELOG.md and tests/test_secret_guard.sh's dir #617(a) block.)
      common_dir="$(git -C "$repo" rev-parse --git-common-dir)"
      # An exit-0-yet-empty result would otherwise concatenate straight into the literal "/hooks"
      # below, which the very next case guard reads as already-absolute — vendoring at the
      # filesystem ROOT instead of merely failing loud (code review finding, dir #617: the old
      # call's own empty-output case degraded no worse than "$repo/", still contained). Never
      # observed live, but "never outside $repo" is the one property this ticket exists to hold.
      [ -n "$common_dir" ] || { echo "install-secret-guard.sh: git -C $repo rev-parse --git-common-dir returned nothing — refusing to guess a hooks dir" >&2; exit 2; }
      hooks="$common_dir/hooks"
      case "$hooks" in /*) ;; *) hooks="$repo/$hooks" ;; esac
      install_into "$hooks"
    fi
    seed="$repo/.secret-scan-allow"
    [ -f "$seed" ] || printf '# Keel secret-guard allowlist\n# <ERE> to drop a matched line; path:<glob> to exclude a path\n' > "$seed"
    echo "secret-guard: vendored into $repo"
    ;;
esac
