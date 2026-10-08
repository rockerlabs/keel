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
#   install-secret-guard.sh --where <repo>   read-only: print where a <repo> install writes (own), where git
#                                            reads this repo's hooks (effective), and the core.hooksPath
#                                            scope that decides it — the ONE resolver tools/doctor.sh,
#                                            install.sh and uninstall.sh read (dir #643, dir #688)
#   install-secret-guard.sh --where --global read-only: the machine-wide core.hooksPath as git resolves it
#
# Never clobbers your data silently: a pre-existing pre-commit/pre-push (or global core.hooksPath) that
# isn't Keel's own is treated as higher-precedence user data — the install refuses and says how to
# proceed unless you pass --force (which backs up to <hook>.pre-keel.bak first, and refuses — naming the
# saved file — if that backup already exists, so an earlier saved hook is never overwritten; for the
# global hooksPath it records the old value in `git config --global keel.displacedHooksPath`, under the
# same never-overwrite rule). A hook is Keel's only when its line 2 is exactly the shipped hook's
# marker line. A symlink at a hook or scanner file the install writes is refused, its target named,
# never written through (the hooks DIRECTORY itself is not checked: a linked or configured shared dir
# is written into, by design). Bypass a single commit/push deliberately with `git ... --no-verify`;
# a commit made that way is still scanned by pre-push, which scans every commit it sends.
set -euo pipefail
# dir #644: unconditional, at the top — before this script's first git call, whichever branch it
# turns out to be, not gated behind reaching the <repo> branch below. An inherited GIT_DIR /
# GIT_COMMON_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (or, since dir #661, an object-store or namespace variable)
# redirects `git -C "$repo"` — including the validity gate itself — into a DIFFERENT repository than
# the one named on the command line, so this can pass a non-git $repo as valid and vendor the hook write somewhere else entirely
# (docs/specs/318-test-ref-isolation.md E19(c)). Inlined rather than sourced from
# tools/lib/repo-arg-guard.sh: this script is designed to be copied standalone alongside only its
# sibling secret-guard/ dir (see the header and this file's own test fixtures in
# tests/test_secret_guard.sh, which run scratch copies that carry no tools/lib/) — that lib's own
# header explains why install-read-trace.sh and install-pre-pr-gate.sh share it instead.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
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
# dir #659 (S3-3): where --global --force records the core.hooksPath it displaces, for --uninstall to
# restore. A global git config key, not a file in the hooks dir: it sits beside the setting it backs
# up, survives the hooks dir being deleted, and `git config --global --list` shows it.
isg_displaced_key="keel.displacedHooksPath"
# Keel's machine-wide hooks dir, relative to $HOME — what --global writes and --where recognises.
isg_keel_hooks_rel=".config/git/keel-hooks"
# dir #717: how many conditional [includeIf] levels the walk follows before it calls itself incomplete.
isg_include_depth_max=10

# --force and --uninstall may sit anywhere on the line; strip them, keep the single subcommand/positional
# (busybox/bash-3.2 safe — no arrays). At most one non-flag arg is expected (--global, --help, or a repo path).
force=0
uninstall=0
where=0
rest=""
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
    --where) where=1 ;;
    *) if [ -n "$rest" ]; then
         echo "install-secret-guard.sh: unexpected extra argument '$a' — one repo path (or --global) per run" >&2
         exit 2
       fi
       rest="$a" ;;
  esac
done
set -- ${rest:+"$rest"}
# --where is a read-only question; it never combines with the flags that write.
if [ "$where" = 1 ] && { [ "$force" = 1 ] || [ "$uninstall" = 1 ]; }; then
  echo "install-secret-guard.sh: --where only reads — it doesn't combine with --force or --uninstall" >&2
  exit 2
fi
# --uninstall only unwires the GLOBAL guard and never overwrites anything, so --force has nothing to do
# there — reject the pair rather than ignore one flag, as the sibling installers do.
if [ "$uninstall" = 1 ]; then
  if [ "$force" = 1 ]; then
    echo "install-secret-guard.sh: --uninstall and --force don't combine (--uninstall never touches a hooksPath" >&2
    echo "  that isn't Keel's, with or without --force)" >&2
    exit 2
  fi
  case "${1:-}" in
    --global|-h|--help) ;;
    *) echo "install-secret-guard.sh: --uninstall works with --global only — to remove a vendored repo copy, delete" >&2
       echo "  its hook files, and move back any <hook>.pre-keel.bak a --force saved" >&2
       exit 2 ;;
  esac
fi

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

# Ours carry an exact marker LINE: line 2 of the installed hook equals line 2 of the shipped hook of the
# same name — never a substring, which let a user's hook that merely names the tool read as ours (dir
# #659, S3-1). Line 2 is unchanged in every shipped version, so older installs still match;
# tests/test_secret_guard.sh pins it, since rewording it orphans them all.
_isg_is_keel_hook() {
  local marker
  marker="$(sed -n 2p "$src/${1##*/}")"
  [ -n "$marker" ] && [ "$(sed -n 2p "$1" 2>/dev/null)" = "$marker" ]
}

install_into() {
  local hooks_dir="$1" h t f l
  # Every refusal below is a READ-ONLY pre-flight that runs before the source selftest and before any
  # write, so "Nothing was changed" is literally true and a refusal costs nothing (dir #659: the
  # ownership refusal used to run after the selftest AND after an earlier hook's .keel-upgrade.bak had
  # already been written, leaving that file behind).
  #
  # (a) dir #659, S3-2: every `cp` below follows a symlink at its destination, so a linked hook or
  # scanner file would have its TARGET rewritten — a dotfiles hook, or a hook file shared by other repos
  # (the 0.11.0 F1 class: a per-repo install mutating a machine-shared file). Refuse, with or without
  # --force, and name the target (resolved against the hooks dir when the link is relative) so the user
  # can decide what owns it.
  for f in $isg_files; do
    t="$hooks_dir/$f"
    if [ -L "$t" ]; then
      l="$(readlink "$t" 2>/dev/null || echo '?')"
      case "$l" in /*|'?') ;; *) l="$hooks_dir/$l" ;; esac
      echo "secret-guard: $t is a symlink (→ $l) — refusing to write through it: that would" >&2
      echo "  rewrite the file it points to. Replace the link with a regular file (or remove it), then" >&2
      echo "  re-run. Nothing was changed." >&2
      exit 3
    fi
    # The run-scoped backup path below is cleared with `rm -f`, which cannot remove a directory: refuse
    # up front rather than abort under `set -e` after an earlier hook's backup was already written.
    if [ -e "$t" ] && [ -d "$t.$isg_bak_upgrade" ] && [ ! -L "$t.$isg_bak_upgrade" ]; then
      echo "secret-guard: $t.$isg_bak_upgrade is a directory, where this run keeps a temporary backup — move" >&2
      echo "  it aside, then re-run. Nothing was changed." >&2
      exit 3
    fi
  done
  # (b) Never silently clobber the user's own hook. Ours carry the exact marker line (_isg_is_keel_hook);
  # a pre-commit / pre-push without it is the user's data (higher precedence than our default), so
  # refuse and explain. --force backs it up to <hook>.pre-keel.bak, then replaces. (Closes SEC1's
  # pre-commit clobber.)
  # (c) dir #625: --force's backup at .pre-keel.bak is PERMANENT, so it must never be overwritten. A
  # second --force over a DIFFERENT foreign hook (something external replaced the installed hook after
  # the first --force) would `cp` the new hook over the first one's backup — the earlier hook silently
  # gone. Name the saved file so the user can move it aside and re-run. `-L` too: a dangling symlink at
  # the backup path makes `-e` false, yet `cp` would write through it.
  for h in pre-commit pre-push; do
    t="$hooks_dir/$h"
    { [ -e "$t" ] && ! _isg_is_keel_hook "$t"; } || continue
    if [ "$force" != 1 ]; then
      echo "secret-guard: $t exists and is not a Keel hook — refusing to overwrite your data." >&2
      echo "  Re-run with --force to back it up (.$isg_bak_force) and replace, or call secret-scan.sh from" >&2
      echo "  your own hook by hand. Nothing was changed." >&2
      exit 3
    fi
    if [ -e "$t.$isg_bak_force" ] || [ -L "$t.$isg_bak_force" ]; then
      echo "secret-guard: $t is not a Keel hook, and a backup of an earlier one is already saved at" >&2
      echo "  $t.$isg_bak_force — --force would overwrite it. Move or delete that file, then re-run" >&2
      echo "  with --force. Nothing was changed." >&2
      exit 3
    fi
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

  # The pre-flight above already refused every foreign hook it could not back up, so from here a
  # pre-commit / pre-push is either ours (re-vendored) or foreign under --force (backed up, replaced).
  # A run-scoped .keel-upgrade.bak path is Keel's own scratch name: a leftover there (even a symlink) is
  # removed first, never followed — refusing instead would ask the user to put a file at a path the run
  # then overwrites and deletes (dir #659).
  for h in pre-commit pre-push; do
    t="$hooks_dir/$h"
    if [ -e "$t" ]; then
      if _isg_is_keel_hook "$t"; then
        # Already ours — re-vendoring over it needs no --force and no refuse-and-ask. But the cp
        # below is about to overwrite a WORKING hook, so it still needs a backup: without one, a
        # later failure in this same run (the next cp, chmod, or the post-copy verify) rolled back
        # by deleting the just-copied file and leaving NO hook at all — not "left as it was before
        # this run" as rollback claims, but a silent loss of the working guard (code review finding).
        # `.keel-upgrade.bak`, NOT `.pre-keel.bak` — this branch runs on every ordinary re-install,
        # including one right after a --force install, and must never touch the permanent backup
        # a --force run may have left at `.pre-keel.bak` (see the note above `local copied=`).
        rm -f "$t.$isg_bak_upgrade"
        cp "$t" "$t.$isg_bak_upgrade"
        upgraded="$upgraded $h"
      elif [ "$force" != 1 ]; then
        # Only reachable if the hook was swapped for a foreign one during the selftest, after the
        # pre-flight read it as ours: never replace it without --force — undo this run and stop.
        _isg_rollback "$hooks_dir" "$copied" "$backed_up" "$upgraded" "$t stopped being a Keel hook during this run"
      else
        cp "$t" "$t.$isg_bak_force"
        backed_up="$backed_up $h"
        echo "secret-guard: backed up your existing $h → $h.$isg_bak_force (--force)" >&2
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
  # two files have no foreign-hook clash, so they never touch `.pre-keel.bak`. Read off $isg_files, so a
  # newly shipped file gets the same safety net it gets copied and symlink-checked with.
  for f in $isg_files; do
    case "$f" in pre-commit|pre-push) continue ;; esac
    t="$hooks_dir/$f"
    if [ -e "$t" ]; then
      rm -f "$t.$isg_bak_upgrade"
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

# Is hooksPath value $1 the same directory as $2? Compared as paths, never as the raw strings git stored
# (dir #659): a literal leading ~/ is expanded (git returns it verbatim and expands it itself at use
# time; a portable dotfiles gitconfig writes it that way — the same expansion tools/doctor.sh's
# _expand_hookspath_tilde and tools/lib/git-global-paths.sh apply, inlined because this script ships
# standalone), one trailing slash is dropped, and two paths that both exist are compared with `-ef`
# (a symlinked HOME, `//`). Compared as strings, Keel's own dir spelled any other way read as foreign:
# --force then recorded Keel's own dir as the "displaced" value and --uninstall "restored" it, leaving
# the guard wired.
# shellcheck disable=SC2088  # matching a literal ~ on purpose
_isg_norm_path() {
  local p="$1"
  case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; esac
  [ "$p" = / ] || p="${p%/}"
  printf '%s' "$p"
}
_isg_same_dir() {
  local a b
  a="$(_isg_norm_path "$1")"; b="$(_isg_norm_path "$2")"
  [ "$a" = "$b" ] && return 0
  # `-ef` only between absolute paths: a relative hooksPath names a dir inside EACH repo, so resolving
  # it against this script's own cwd would make the answer depend on where the installer was run.
  case "$a" in /*) ;; *) return 1 ;; esac
  case "$b" in /*) ;; *) return 1 ;; esac
  [ -e "$a" ] && [ -e "$b" ] && [ "$a" -ef "$b" ]
}

# --- dir #643: ONE resolver for "which hooks dir, and does git read it" --------------------------------
# Three places used to answer that question three ways: this installer (--git-common-dir / a LOCAL
# hooksPath), tools/doctor.sh (`--git-path hooks`, which honours a hooksPath from ANY scope) and
# install.sh (`git config --global`, a scope selector that collapses to ONE file). They disagreed
# wherever a hooksPath arrived from somewhere the installer does not write: a copy vendored into the
# repo's own dir was reported — and advised — as wiring while git read a different dir, and a hooksPath
# in the XDG file behind an existing ~/.gitconfig, in an [include], or at SYSTEM scope was invisible to
# the `--global` read, so the installer overwrote it or reported "nothing to unwire". This script is
# the producer, so it is the definition; `--where` prints it for the two consumers (this file ships
# standalone and cannot source a lib, so a lib could never be shared with it).
#
# `--where <repo>` prints key=value lines (a key is omitted when it has no value):
#   own=        absolute dir a `<repo>` install writes (the LOCAL hooksPath, else the common dir's hooks)
#   effective=  absolute dir git actually reads this repo's hooks from (any scope: `--git-path hooks`)
#   scope=      none | local | worktree | global | system | command | unknown  — where core.hooksPath is set
#   value=      the raw setting          origin=  the config file it was read from
#   keel-dir=1  effective is Keel's machine-wide hooks dir
#   machine-dir=1  effective is the machine-wide hooksPath dir (what `--where --global` prints as `dir=`);
#               how a consumer decides "this repo's hooks ARE the machine-wide ones" without comparing paths
#               itself (dir #688)
#   pre-commit= / pre-push=  state of that hook in `effective`: absent | keel | foreign, `-link` suffixed
#               when it is a symlink — "keel" means the exact marker line, the same test an install uses
# `--where --global` prints the machine-wide view (value/scope/origin/dir/keel-dir/pre-commit/pre-push), plus
#   fallback=1  the machine-wide read took its narrow `git config --global` branch (no usable scratch dir)
#   conditional=<n>|unknown  n ≥ 1 conditional [includeIf] includes set a core.hooksPath that is empty,
#               valueless or not the same dir as value= (it may win in the trees they match); unknown = the
#               walk could not read them all (dir #717); omitted when n = 0
# When own and effective differ, a copy written to own is inert: git never reads it.

# One read of core.hooksPath as git sees it from directory $1: sets m_scope m_origin m_value (all empty
# when unset). `--show-scope` needs git 2.26; an older git still yields the value, scope "unknown".
_isg_cfg_read() {
  local out rest
  m_scope="" m_origin="" m_value=""
  if out="$(git -C "$1" config --show-scope --show-origin --get core.hooksPath 2>/dev/null)" && [ -n "$out" ]; then
    m_scope="${out%%$'\t'*}"; rest="${out#*$'\t'}"
    m_origin="${rest%%$'\t'*}"; m_value="${rest#*$'\t'}"
    m_origin="${m_origin#file:}"
  elif out="$(git -C "$1" config --get core.hooksPath 2>/dev/null)" && [ -n "$out" ]; then
    m_scope="unknown"; m_value="$out"
  fi
  [ -n "$m_value" ] || { m_scope=""; m_origin=""; }
  return 0
}

# The machine-wide hooksPath as git EFFECTIVELY resolves it — read from a fresh non-repo scratch dir so
# nothing at LOCAL scope can leak in, and with no --global restriction so the XDG file behind an
# existing ~/.gitconfig, an [include] and SYSTEM scope all count. If the scratch dir turns out to sit
# inside a repo (an odd TMPDIR) it falls back to the narrower `git config --global` read rather than
# risk reading that repo's local scope — and sets m_fallback=1, which `--where --global` prints, so no
# consumer reads the narrow answer as the full one. With `walk` as $1 it also runs the conditional-include
# walk (_isg_conditional_reads) from the same scratch dir, or — with no usable one — sets c_cause.
_isg_machine_read() {
  local probe
  m_fallback=0
  probe="$(mktemp -d 2>/dev/null)" || probe=""
  if [ -n "$probe" ] && ! git -C "$probe" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _isg_cfg_read "$probe"
    [ "${1:-}" != walk ] || _isg_conditional_reads "$probe"
  else
    m_fallback=1
    m_scope="" m_origin="" m_value="$(git config --global core.hooksPath 2>/dev/null || true)"
    [ -z "$m_value" ] || m_scope="global"
    if [ "${1:-}" = walk ]; then
      c_list=""
      if [ -n "$probe" ]; then
        c_cause="the scratch dir mktemp gives sits inside a repository (on Linux, set TMPDIR outside any repo; macOS mktemp ignores TMPDIR)"
      else
        c_cause="mktemp -d gave no scratch dir"
      fi
    fi
  fi
  [ -z "$probe" ] || { rm -f "$probe/.isg-list" "$probe/.isg-value"; rmdir "$probe" 2>/dev/null; } || true
}

# --- dir #717 (S5-1): the conditional [includeIf] includes ---------------------------------------------------
# A core.hooksPath that an [includeIf "gitdir:…"] (or onbranch:, hasconfig:…) include sets applies only in the
# trees its condition matches, so the scratch-dir read above never sees it — and `--global` used to append its
# own [core] hooksPath after it and silently take those trees over. The walk lists every conditional include
# git would consider and reads what each target sets, without evaluating any condition:
#   - listed from the scratch dir, so global, the XDG file, SYSTEM and unconditionally [include]d files all
#     count; only `file:` origins — a command-scope include (`git -c`, GIT_CONFIG_COUNT; tests/lib.sh arms one
#     for every test) applies to one command, not to the machine;
#   - a relative target resolves beside the file that names it (git's rule), a leading ~/ to $HOME; a
#     missing target is skipped, as git skips it, and so is a valueless `path` key; a `~user/` or
#     `%(prefix)/` target, which this walk does not resolve, an unreadable one and one under a dir that
#     cannot be searched make it incomplete;
#   - nested includeIfs inside a target are followed, their condition `<outer> and <inner>`; a target seen
#     before (compared with `-ef`, so `./work.cfg` or a symlink to it is work.cfg) is skipped — a conditional
#     self-include is complete — and depth stops at $isg_include_depth_max;
#   - "sets a hooksPath" is the read's EXIT CODE, not a non-empty value: an empty `hooksPath =` turns every
#     hook off in its trees, and a valueless `hooksPath` makes git fail there.
# Every `-z` read goes to a FILE in the scratch dir and is read back with `read -d ''`: bash 3.2 drops NUL
# bytes from a $(…) without a warning, and `< <(git …)` alone would lose the exit code the incomplete check
# needs. Output: c_list — one line per target that sets a hooksPath,
#   <kind> TAB <condition> TAB <file holding the include> TAB <target> TAB <value>   (kind v = valued, n = no value;
#   the value last, so an empty one is never collapsed by `read`'s IFS)
# and c_cause — non-empty when the walk could not see everything (the install then fails closed).
c_list="" c_cause="" c_next="" c_probe=""

# _isg_tab_nl_free S — 0 when S holds neither a TAB nor a newline (the c_list and queue field separators).
_isg_tab_nl_free() { case "$1" in *$'\t'*|*$'\n'*) return 1 ;; esac; return 0; }

# Queue onto c_next (one `<condition> TAB <origin> TAB <target>` line each) the includeIf entries git lists for
# the whole machine config ($2 empty) or for one target file ($2), each condition prefixed `$1 and `. Returns 1
# with c_cause set when the listing cannot be trusted.
_isg_cond_list() {
  local outer="$1" f="${2:-}" out="$c_probe/.isg-list" rc=0 origin kv key cond raw base x
  git -C "$c_probe" config ${f:+--file} ${f:+"$f"} ${f:+--includes} --show-origin -z \
    --get-regexp '^includeif\..+\.path$' > "$out" 2>/dev/null || rc=$?
  case "$rc" in
    0) ;;
    1) return 0 ;;   # no includeIf at all
    *) c_cause="git config failed on ${f:-the machine-wide config}"; return 1 ;;
  esac
  # A record is `origin NUL key LF value NUL`, or `origin NUL key NUL` for a valueless `path` key.
  while IFS= read -r -d '' origin && IFS= read -r -d '' kv; do
    case "$origin" in file:*) origin="${origin#file:}" ;; *) continue ;; esac
    case "$kv" in *$'\n'*) ;; *) continue ;; esac   # valueless `path`: git skips it
    key="${kv%%$'\n'*}"; raw="${kv#*$'\n'}"
    cond="${key#includeif.}"; cond="${cond%.path}"
    for x in "$origin" "$cond" "$raw"; do
      _isg_tab_nl_free "$x" || { c_cause="a path holding a TAB or newline: $x"; return 1; }
    done
    [ -n "$raw" ] || continue
    # shellcheck disable=SC2088  # matching a literal ~ on purpose
    case "$raw" in
      "~/"*) raw="$(_isg_norm_path "$raw")" ;;
      "~"[!/]*|"%(prefix)/"*) c_cause="an include path this walk cannot resolve: $raw"; return 1 ;;
      /*) ;;
      *) case "$origin" in */*) base="${origin%/*}" ;; *) base="." ;; esac
         raw="$base/$raw" ;;
    esac
    # git resolved a relative origin from the scratch dir it ran in, so a relative path is relative to it
    case "$raw" in /*) ;; *) raw="$c_probe/$raw" ;; esac
    [ -z "$outer" ] || cond="$outer and $cond"
    c_next="$c_next$cond"$'\t'"$origin"$'\t'"$raw"$'\n'
  done < "$out"
  return 0
}

# Is file $1 one of the newline-separated files in $2? Compared with `-ef`, so `./work.cfg`, a symlink to a file
# and the file itself are one (both exist: the caller tested $1).
_isg_seen() {
  local v
  while IFS= read -r v; do
    [ -n "$v" ] && [ "$v" -ef "$1" ] && return 0
  done <<< "$2"
  return 1
}

# 0 when absent path $1 is absent for certain: its deepest existing ancestor dir could be searched. A dir
# without search permission hides what is under it, and git fails reading an include there.
_isg_absent_for_sure() {
  local p="${1%/*}"
  while [ -n "$p" ] && [ ! -e "$p" ]; do p="${p%/*}"; done
  [ -z "$p" ] || [ -x "$p" ]
}

# The walk itself, from scratch dir $1 (fresh, not inside a repo). Sets c_list and c_cause (see above).
_isg_conditional_reads() {
  local depth=1 cur cond origin tgt rc kv kind val vout visited=""
  c_probe="$1" c_list="" c_cause="" c_next=""
  vout="$c_probe/.isg-value"
  _isg_cond_list "" || return 0
  while [ -n "$c_next" ]; do
    if [ "$depth" -gt "$isg_include_depth_max" ]; then c_cause="include depth over $isg_include_depth_max"; return 0; fi
    cur="$c_next" c_next=""
    while IFS=$'\t' read -r cond origin tgt; do
      [ -n "$tgt" ] || continue
      if [ ! -e "$tgt" ]; then
        # a missing include: git skips it — unless a dir on its path could not be searched, so "missing" is a guess
        _isg_absent_for_sure "$tgt" || { c_cause="git config failed on $tgt (a directory on its path cannot be searched)"; return 0; }
        continue
      fi
      # git reports an unreadable include as a warning and exit 1 — the same exit as "not set" — so test it here
      [ -r "$tgt" ] || { c_cause="git config failed on $tgt (unreadable)"; return 0; }
      _isg_seen "$tgt" "$visited" && continue
      visited="$visited$tgt"$'\n'
      rc=0
      git -C "$c_probe" config --file "$tgt" --includes -z --get-regexp '^core\.hookspath$' > "$vout" 2>/dev/null || rc=$?
      case "$rc" in
        0) # the last record is the value git ends up with; `key LF value NUL`, or `key NUL` when valueless
           kind="" val=""
           while IFS= read -r -d '' kv; do
             case "$kv" in *$'\n'*) kind=v val="${kv#*$'\n'}" ;; *) kind=n val="" ;; esac
           done < "$vout"
           _isg_tab_nl_free "$val" || { c_cause="a path holding a TAB or newline: $val"; return 0; }
           [ -z "$kind" ] || c_list="$c_list$kind"$'\t'"$cond"$'\t'"$origin"$'\t'"$tgt"$'\t'"$val"$'\n' ;;
        1) ;;   # sets no hooksPath
        *) c_cause="git config failed on $tgt"; return 0 ;;
      esac
      _isg_cond_list "$cond" "$tgt" || return 0
    done <<< "$cur"
    depth=$((depth + 1))
  done
}

# The c_list entries that may override hooksPath dir $1 in their trees — a value that is empty, valueless or
# not the same dir (an empty value is never the same dir, though `_isg_same_dir "" ""` would say so). Sets
# c_conf (c_list's line format) and c_n.
_isg_conditional_conflicts() {
  local ref="$1" kind cond origin tgt val
  c_conf="" c_n=0
  while IFS=$'\t' read -r kind cond origin tgt val; do
    [ -n "$kind" ] || continue
    if [ "$kind" = v ] && [ -n "$val" ] && _isg_same_dir "$val" "$ref"; then continue; fi
    c_conf="$c_conf$kind"$'\t'"$cond"$'\t'"$origin"$'\t'"$tgt"$'\t'"$val"$'\n'
    c_n=$((c_n + 1))
  done <<< "$c_list"
}

# How a conflict's setting reads in a message: kind $1, value $2.
_isg_cond_setting() {
  if [ "$1" = n ]; then
    echo "core.hooksPath (no value — git fails in those trees)"
  elif [ -z "$2" ]; then
    echo "core.hooksPath = '' (every hook off)"
  else
    echo "core.hooksPath = '$2'"
  fi
}

# One NOTE per c_conf entry, plus one for an incomplete walk — what a run that wires anyway must still say.
_isg_conditional_notes() {
  local kind cond origin tgt val
  while IFS=$'\t' read -r kind cond origin tgt val; do
    [ -n "$kind" ] || continue
    echo "secret-guard: NOTE — in trees matching $cond, $tgt sets $(_isg_cond_setting "$kind" "$val"); whether it or"
    echo "  Keel's wins there depends on its position in $origin: check with git -C <a repo there> config --show-origin core.hooksPath"
  done <<< "$c_conf"
  [ -z "$c_cause" ] || echo "secret-guard: NOTE — conditional [includeIf] includes could not all be read ($c_cause)"
}

# Where a `<repo>` install writes — the single definition both the install and `--where` use. A LOCAL
# hooksPath wins (absolute, or relative to the repo; a leading ~/ is git's to expand). Otherwise the
# repo's OWN git dir: --git-common-dir names it, worktree/submodule-safe, and never consults
# core.hooksPath at any scope (dir #617: `--git-path hooks` also honours GLOBAL/SYSTEM, so a repo with
# no LOCAL override could resolve straight into a machine-wide dir). Considered instead: keep
# --git-path hooks and refuse when its result lies outside $repo — rejected because a submodule's real
# hooks dir legitimately lives under the SUPERPROJECT's .git/modules/, outside $repo's own tree.
# Prints the dir; returns 1 (after saying why) when it cannot name one.
_isg_repo_own_dir() {
  local repo="$1" hp common_dir hooks
  if hp="$(git -C "$repo" config --local core.hooksPath 2>/dev/null)" && [ -n "$hp" ]; then
    # hooksPath may be absolute — joining it under $repo would vendor into a junk dir while the real
    # hooks dir stays empty (guard silently inactive).
    hp="$(_isg_norm_path "$hp")"
    case "$hp" in /*) printf '%s' "$hp" ;; *) printf '%s' "$repo/$hp" ;; esac
    return 0
  fi
  common_dir="$(git -C "$repo" rev-parse --git-common-dir)" || return 1
  # An exit-0-yet-empty result would otherwise concatenate straight into the literal "/hooks" below,
  # which the very next case reads as already-absolute — vendoring at the filesystem ROOT instead of
  # merely failing loud (code review finding, dir #617). Never observed live, but "never outside $repo"
  # is the one property that ticket exists to hold.
  [ -n "$common_dir" ] || {
    echo "install-secret-guard.sh: git -C $repo rev-parse --git-common-dir returned nothing — refusing to guess a hooks dir" >&2
    return 1
  }
  hooks="$common_dir/hooks"
  case "$hooks" in /*) ;; *) hooks="$repo/$hooks" ;; esac
  printf '%s' "$hooks"
}

# The dir git reads this repo's hooks from, at ANY scope, absolute — what `--where` calls `effective`.
# Returns 1 when git names none.
_isg_repo_effective_dir() {
  local eff
  eff="$(git -C "$1" rev-parse --git-path hooks 2>/dev/null)" && [ -n "$eff" ] || return 1
  eff="$(_isg_norm_path "$eff")"
  case "$eff" in /*) printf '%s' "$eff" ;; *) printf '%s' "$1/$eff" ;; esac
}

# absent | keel | foreign, `-link` appended when $2 in dir $1 is a symlink. Same marker test as an
# install (_isg_is_keel_hook), so no consumer carries its own, looser one.
_isg_hook_state() {
  local t="$1/$2" s
  if [ ! -e "$t" ] && [ ! -L "$t" ]; then echo absent; return 0; fi
  if [ -e "$t" ] && _isg_is_keel_hook "$t"; then s=keel; else s=foreign; fi
  [ -L "$t" ] && s="$s-link"
  echo "$s"
}

# The state lines shared by both --where forms, for hooks dir $1.
_isg_where_states() {
  local d="$1" keel_dir=""
  [ -z "${HOME:-}" ] || keel_dir="$HOME/$isg_keel_hooks_rel"
  [ -z "$keel_dir" ] || ! _isg_same_dir "$d" "$keel_dir" || echo "keel-dir=1"
  echo "pre-commit=$(_isg_hook_state "$d" pre-commit)"
  echo "pre-push=$(_isg_hook_state "$d" pre-push)"
}

# Is directory $1 the machine-wide absolute hooksPath dir (the `dir=` `--where --global` prints)? Prints
# nothing and returns 1 when no machine-wide absolute hooksPath is set (or HOME is). Reads through
# _isg_machine_read, so it clobbers the m_* variables.
_isg_is_machine_dir() {
  local d
  [ -n "${HOME:-}" ] || return 1
  _isg_machine_read
  d="$(_isg_norm_path "$m_value")"
  case "$d" in /*) _isg_same_dir "$1" "$d" ;; *) return 1 ;; esac
}

_isg_where_repo() {
  local repo="$1" own eff
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
  # `own` and `effective` are documented as absolute: a relative $repo (doctor's default is ".") would
  # otherwise print "./.git/hooks", which means something else to a consumer standing elsewhere.
  repo="$(cd "$repo" && pwd)" || exit 2
  own="$(_isg_repo_own_dir "$repo")" || exit 2
  eff="$(_isg_repo_effective_dir "$repo")" \
    || { echo "install-secret-guard.sh: git -C $repo rev-parse --git-path hooks returned nothing" >&2; exit 2; }
  _isg_cfg_read "$repo"
  echo "own=$own"
  echo "effective=$eff"
  echo "scope=${m_scope:-none}"
  [ -z "$m_value" ] || echo "value=$m_value"
  [ -z "$m_origin" ] || echo "origin=$m_origin"
  # machine-dir: the one place that decides "this repo's hooks are the machine-wide ones" (dir #688); a
  # consumer must not re-derive it with a path compare of its own (dir #659's class). A repo that no scope
  # sets a hooksPath for reads its own hooks dir, so the machine-wide read is skipped for it — nearly all of
  # them. (The test of m_scope comes first: _isg_is_machine_dir clobbers the m_* variables.)
  [ -z "$m_scope" ] || ! _isg_is_machine_dir "$eff" || echo "machine-dir=1"
  _isg_where_states "$eff"
}

_isg_where_machine() {
  local d
  [ -n "${HOME:-}" ] || { echo "scope=none"; return 0; }
  _isg_machine_read walk
  echo "scope=${m_scope:-none}"
  [ -z "$m_value" ] || echo "value=$m_value"
  [ -z "$m_origin" ] || echo "origin=$m_origin"
  [ "$m_fallback" != 1 ] || echo "fallback=1"
  _isg_conditional_conflicts "$m_value"
  if [ -n "$c_cause" ]; then echo "conditional=unknown"; elif [ "$c_n" -gt 0 ]; then echo "conditional=$c_n"; fi
  d="$(_isg_norm_path "$m_value")"
  case "$d" in /*) echo "dir=$d"; _isg_where_states "$d" ;; esac
}

# The advice a vendored copy needs when git does not read it (own != effective), one definition for the
# install's own note. tools/doctor.sh words the same two remedies for its finding; tests pin both.
_isg_inert_note() {  # repo own effective scope
  echo "secret-guard: NOTE — this copy is inert: core.hooksPath ($4 scope) sends git to $3 for this repo, not $2."
  echo "  Either replace the machine-wide setting (install-secret-guard.sh --global --force; the old value is"
  echo "  recorded and --uninstall restores it), or give this repo its own hooks dir:"
  echo "    git -C $1 config --local core.hooksPath $2   then re-run install-secret-guard.sh $1"
}

if [ "$where" = 1 ]; then
  case "${1:-}" in
    --global) _isg_where_machine ;;
    ""|-h|--help) echo "usage: install-secret-guard.sh --where <repo-path> | --where --global" >&2; exit 2 ;;
    *) _isg_where_repo "$1" ;;
  esac
  exit 0
fi

case "${1:-}" in
  --global)
    dir="${HOME:?install-secret-guard: --global needs HOME set}/$isg_keel_hooks_rel"
    # dir #643 (DT3): two reads, on purpose. existing_global is the file `git config --global` edits — what
    # --uninstall can unset and --force can replace. $existing is what git EFFECTIVELY resolves: it also
    # sees the XDG file behind an existing ~/.gitconfig, an [include], and SYSTEM scope, any of which
    # governs every commit while `--global` reports "unset" (so this used to overwrite it, or say
    # "nothing to unwire"). m_scope/m_origin name where $existing came from.
    existing_global="$(git config --global core.hooksPath 2>/dev/null || true)"
    # The install also walks the conditional [includeIf] includes (dir #717); --uninstall never reads or
    # writes one — its --unset gives a conditional setting its trees back on its own.
    if [ "$uninstall" = 1 ]; then _isg_machine_read; else _isg_machine_read walk; fi
    existing="$m_value"
    recorded="$(git config --global "$isg_displaced_key" 2>/dev/null || true)"
    # One record, one value: several (a dotfiles merge, a hand --add) would let the never-overwrite rule
    # below compare against just the last one and then --replace-all/--unset-all drop the others unseen.
    if [ "$( { git config --global --get-all "$isg_displaced_key" 2>/dev/null || true; } | wc -l | tr -d ' ')" -gt 1 ]; then
      echo "secret-guard: $isg_displaced_key holds several values (git config --global --get-all $isg_displaced_key);" >&2
      echo "  keep the one hooksPath to restore, then re-run. Nothing was changed." >&2
      exit 3
    fi
    is_ours=0
    [ -n "$existing" ] && _isg_same_dir "$existing" "$dir" && is_ours=1
    own_global=0
    [ -n "$existing_global" ] && _isg_same_dir "$existing_global" "$dir" && own_global=1
    # Where $existing was set, for a message: nothing for the file `--global` edits (the common case).
    src_note=""
    [ -z "$m_origin" ] || src_note=" ($m_scope scope, $m_origin)"
    if [ "$uninstall" = 1 ]; then
      # Unwire only what is Keel's: a hooksPath pointing anywhere else is the user's, left alone. The
      # hook files stay in $dir — inert once nothing points at them; deleting them is the user's call.
      if [ "$own_global" != 1 ] && [ "$is_ours" = 1 ]; then
        # Keel's dir, but set where `git config --global` cannot unset it (the XDG file, an include,
        # SYSTEM): unsetting would be a silent no-op reported as success.
        echo "secret-guard: the global core.hooksPath names Keel's dir ($dir), but it is set in $m_origin —" >&2
        echo "  not in the file \`git config --global\` edits, so --uninstall cannot unset it. Remove that line" >&2
        echo "  there yourself. Nothing was changed." >&2
        exit 3
      fi
      if [ "$own_global" != 1 ] && [ -z "$existing" ]; then
        echo "secret-guard: no global core.hooksPath is set — nothing to unwire."
        # A record with nothing wired describes a wiring that is already gone (hooksPath unset by
        # hand after a --force): name it, so the user can set it back, and drop it, so no later run
        # restores a path the user had already removed.
        if [ -n "$recorded" ]; then
          echo "  Dropping the stale record $isg_displaced_key='$recorded' (a hooksPath an earlier --force"
          echo "  displaced). Keel is not wired, so it is not restored — set it back by hand if you want it."
          git config --global --unset-all "$isg_displaced_key"
        fi
        exit 0
      fi
      if [ "$own_global" != 1 ]; then
        echo "secret-guard: the global core.hooksPath is '$existing'$src_note, not Keel's ($dir) — not touching it." >&2
        [ -n "$recorded" ] && echo "  ($isg_displaced_key still records '$recorded'.)" >&2
        echo "  Nothing was changed." >&2
        exit 3
      fi
      # A record that names Keel's own dir (however spelled) displaced nothing: restoring it would leave
      # the guard wired while reporting it unwired. Treat it as no record.
      if [ -n "$recorded" ] && _isg_same_dir "$recorded" "$dir"; then
        echo "secret-guard: $isg_displaced_key named Keel's own dir ('$recorded') — dropping it; nothing to restore."
        git config --global --unset-all "$isg_displaced_key"
        recorded=""
      fi
      if [ -n "$recorded" ]; then
        # A global hooksPath naming a missing dir makes git skip every repo's own hooks, silently —
        # never restore one. (A relative value names a dir per repo and can't be checked here.)
        r="$(_isg_norm_path "$recorded")"
        case "$r" in
          /*) if [ ! -d "$r" ]; then
                echo "secret-guard: the recorded hooksPath '$recorded' no longer exists — restoring it would point" >&2
                echo "  git at a missing dir and silently disable every repo's own hooks. Recreate it and re-run," >&2
                echo "  or clear the record (git config --global --unset-all $isg_displaced_key) and re-run to" >&2
                echo "  just unset Keel's. Nothing was changed." >&2
                exit 3
              fi ;;
        esac
        git config --global core.hooksPath "$recorded"
        git config --global --unset-all "$isg_displaced_key"
        echo "secret-guard: unwired — global core.hooksPath restored to '$recorded'."
        echo "  Keel's hook files are left in $dir; delete that directory if you no longer want them."
      else
        git config --global --unset core.hooksPath
        echo "secret-guard: unwired — global core.hooksPath unset (no displaced value was recorded)."
        echo "  Keel's hook files are left in $dir; delete that directory if you no longer want them."
        echo "  install.sh wires the guard again on its next run unless you pass it --no-hooks."
      fi
      exit 0
    fi
    # Same rule for the machine-global slot: don't replace a hooksPath the user already set to something
    # of their own. (install.sh already guards this before delegating; this protects direct callers too.)
    displaced=""
    if [ -n "$existing" ] && [ "$is_ours" != 1 ]; then
      displaced="$existing"
      if [ "$force" != 1 ]; then
        echo "secret-guard: a global core.hooksPath is already set to '$existing'$src_note — not clobbering it." >&2
        echo "  A copy vendored into a repo would be ignored while it stands. Re-run with --force to replace it" >&2
        echo "  (the old value is recorded; --uninstall restores it), or give one repo its own hooks dir:" >&2
        echo "    git -C <repo> config --local core.hooksPath <repo>/.git/hooks   then install-secret-guard.sh <repo>" >&2
        echo "  Nothing was changed." >&2
        exit 3
      fi
      # --force records what it displaces — and, like the hook backups (dir #625), never overwrites
      # an earlier record of a DIFFERENT path: that one is the only trace of what was there first.
      if [ -n "$recorded" ] && ! _isg_same_dir "$recorded" "$existing"; then
        echo "secret-guard: $isg_displaced_key already records an earlier displaced hooksPath, '$recorded';" >&2
        echo "  --force would replace that record with '$existing'. Restore or clear it" >&2
        echo "  (git config --global --unset-all $isg_displaced_key), then re-run with --force. Nothing was changed." >&2
        exit 3
      fi
    fi
    # dir #717 (S5-1): a conditional [includeIf] include that sets its own core.hooksPath. Writing Keel's
    # [core] hooksPath next to it decides, by position in the file, which of the two governs the trees it
    # matches — so refuse unless --force, the same never-clobber rule as the refusal above, which runs first.
    # An incomplete walk counts as a conflict (fail closed). Only when this run writes core.hooksPath: with
    # Keel already wired the NOTEs below are still printed, and nothing is refused. --force records nothing
    # in $isg_displaced_key — the conditional line is left as it is, not displaced.
    _isg_conditional_conflicts "$dir"
    if [ "$is_ours" != 1 ] && [ "$force" != 1 ] && { [ "$c_n" -gt 0 ] || [ -n "$c_cause" ]; }; then
      if [ "$c_n" -gt 0 ]; then
        echo "secret-guard: a conditional [includeIf] include sets its own core.hooksPath — in the trees it matches," >&2
        echo "  Keel's machine-wide one would either take it over or be overridden by it:" >&2
        while IFS=$'\t' read -r c_kind c_cond c_origin c_tgt c_val; do
          [ -n "$c_kind" ] || continue
          echo "    in trees matching $c_cond: $c_tgt (included from $c_origin) sets $(_isg_cond_setting "$c_kind" "$c_val")" >&2
        done <<< "$c_conf"
        echo "  Point that setting at Keel's dir ($dir) or remove it; or give a repo its own hooks dir" >&2
        echo "  (git -C <repo> config --local core.hooksPath <repo>/.git/hooks)." >&2
      fi
      if [ -n "$c_cause" ]; then
        echo "secret-guard: could not read every conditional [includeIf] include ($c_cause) — a hooksPath there may override this one. Nothing was changed." >&2
      else
        echo "  Nothing was changed." >&2
      fi
      echo "  Re-run with --force to wire anyway." >&2
      exit 3
    fi
    install_into "$dir"
    # The record goes in BEFORE core.hooksPath is repointed: if the repoint then fails, the record still
    # equals the live value, which a re-run accepts. A stale record (nothing displaced, Keel not wired
    # — see the --uninstall arm) is named before it is dropped, so a failed write never loses it unseen.
    if [ -n "$displaced" ]; then
      git config --global --replace-all "$isg_displaced_key" "$displaced"
    elif [ -z "$existing" ] && [ -n "$recorded" ]; then
      echo "secret-guard: dropping the stale record $isg_displaced_key='$recorded' — Keel was not wired, so"
      echo "  this install displaces nothing and a later --uninstall must not restore it."
      git config --global --unset-all "$isg_displaced_key"
    fi
    # Already Keel's, however spelled: leave the user's own spelling of it alone.
    [ "$is_ours" = 1 ] || git config --global core.hooksPath "$dir"
    # Wired is not the same as engaged: a setting git reads AFTER the global file's own key (an [include]
    # placed below it) still wins, and the guard would sit there inert behind a success message.
    if [ "$is_ours" != 1 ]; then
      _isg_machine_read
      if [ -z "$m_value" ] || ! _isg_same_dir "$m_value" "$dir"; then
        echo "secret-guard: set the global core.hooksPath to $dir, but git still resolves it to '$m_value' ($m_scope scope, $m_origin)" >&2
        echo "  — that setting wins, so the guard is NOT active. Remove or edit that line, then re-run. The old value" >&2
        echo "  (if --force displaced one) stays recorded in git config --global $isg_displaced_key." >&2
        exit 3
      fi
    fi
    if [ -n "$displaced" ]; then
      echo "secret-guard: replaced the global core.hooksPath '$displaced' (--force); the old value is"
      echo "  recorded in git config --global $isg_displaced_key — install-secret-guard.sh --global --uninstall restores it"
    fi
    echo "secret-guard: wired machine-global at $dir (git config --global core.hooksPath)"
    _isg_conditional_notes
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
  install-secret-guard.sh --where <repo-path> | --where --global
                                         read-only: which hooks dir an install writes, which one git reads
  install-secret-guard.sh -h | --help
EOF
    exit 0 ;;
  "" )
    echo "usage: install-secret-guard.sh --global | <repo-path>" >&2; exit 2 ;;
  *)
    repo="$1"
    # dir #644: GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE and the object-store and namespace
    # selectors are already unset (top of file) —
    # this validity gate, and every git -C "$repo" call below it, is trustworthy because of that, not
    # because of anything done here.
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 2; }
    # dir #643: the target comes from the one resolver (_isg_repo_own_dir) that `--where` prints too.
    hooks="$(_isg_repo_own_dir "$repo")" || exit 2
    install_into "$hooks"
    # A copy git does not read protects nothing: say so now, with the two ways out, rather than leave a
    # quiet success behind a guard that is not engaged.
    if eff="$(_isg_repo_effective_dir "$repo")" && ! _isg_same_dir "$eff" "$hooks"; then
      _isg_cfg_read "$repo"
      _isg_inert_note "$repo" "$hooks" "$eff" "${m_scope:-unknown}"
    fi
    seed="$repo/.secret-scan-allow"
    # Seed only when nothing is there at all: `-L` too, so a dangling link (for which `-e` is false) is
    # left alone instead of the write following it out of the repo (dir #659).
    [ -e "$seed" ] || [ -L "$seed" ] \
      || printf '# Keel secret-guard allowlist\n# <ERE> to drop a matched line; path:<glob> to exclude a path\n' > "$seed"
    echo "secret-guard: vendored into $repo"
    ;;
esac
