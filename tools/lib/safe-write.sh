# shellcheck shell=bash
# tools/lib/safe-write.sh — the ONE place an installer writes a file by temp-and-rename (dir #679, slice 1
# of docs/specs/685-symlink-policy.md; round 2's slice S5a, dir #755 and dir #756, added the STATE shape,
# the one-call backup, the derived checkout and the claimed temp name). install.sh, uninstall.sh,
# tools/register-project.sh, the hook installers (through tools/lib/hook-install.sh) and tools/lib/ledger.sh
# all write through here, so a symlink, a hard link, a file's mode and a backup's name are decided once,
# the same way everywhere.
#
# Sourced, not executed: no shebang, no set -e (inherits the caller's). Every function checks its own
# risky commands, because a caller that tests the return value (`if keel_write_through …`) suspends
# errexit for the whole body.
#
# REQUIRED by every executable consumer, the same contract as tools/lib/artifact-cksum.sh: each sources
# this file behind a `[ -s ] && bash -n` pre-check and refuses outright, with one message, when it is
# missing or corrupt. A degrade-and-continue fallback here would be the very detaching write this lib
# exists to remove. The sourced libs (hook-install.sh, ledger.sh) do not source it; their functions
# check for it at call time and fail loudly when a caller forgot to load it.
#
# The rule, by write shape (the full table, with every site, is the spec's):
#   EDIT    — keel_write_through: the new bytes depend on the file's current content (CLAUDE.md's rails,
#             settings.json, INSTANCE.md). It follows every symlink hop, so the link stays a link and the
#             file it names gets the new content, and it keeps that file's permission bits. It refuses,
#             with one line and nothing written: a loop; a target that is not a regular file; a target
#             with a second hard link (a rename would split it); a link into a directory that does not
#             exist; and a target inside the Keel checkout reached through a path that is not (a dotfiles
#             CLAUDE.md linked to the checkout's own template must never get its rails stripped).
#   STATE   — keel_write_state: an EDIT of one of Keel's OWN state files (the install manifest, the
#             foreign-core marker, the gate's manifest, the checkout ledger). The same rule, less the
#             hard-link refusal: the rename splits a hard link, so the other name keeps the old bytes —
#             what a snapshot or backup name wants. An adopter's file is never a STATE write.
#   EDIT with a backup — keel_backup_write_through: the EDIT's refusals are checked first, then the
#             backup is taken, then the write runs. A refusal claims no backup, and a write that fails
#             after the backup removes it (the file is unchanged), so a backup always means a change.
#   REPLACE — keel_write_replace / keel_link_replace: a whole file (or link) of Keel content. A temp
#             sibling of the path is renamed onto it, never `cp` or `>` into an existing file, so a hard
#             link's other name keeps its bytes. The new file gets the umask.
#   BACKUP  — keel_backup: a new file beside the path, claimed by an exclusive create, never an
#             overwrite of an earlier backup.
# Whether a path may be replaced at all (a symlink Keel did not make, a user's own file) is the caller's
# decision, made before it calls here.
#
# The temp name `<target>.keeltmp.<pid>` is Keel's own scratch name, CLAIMED before use, never followed:
# whatever is already there (a stale temp, or a link someone planted) is removed with `rm -f`, which never
# follows a link, and the name is claimed by a noclobber create that must leave a regular, non-link file.
# A real directory there (which `rm -f` cannot remove) refuses the write.
#
# KEEL_SAFE_WRITE_CHECKOUT is the Keel checkout, derived when this file is sourced: the physical path two
# levels above this lib's own directory (every hop resolved, so a lib reached through
# `~/.keel/engine -> <checkout>` names the checkout itself). An inherited value is never honoured. A
# caller (a test) may override it after sourcing. When it cannot be derived it is empty, and every EDIT or
# STATE write whose path is a link refuses, because the checkout clause cannot be decided.
#
# Every refusal is ONE line on stderr, printed by _keel_sw_refuse; a failing `cp`, `mv` or redirect
# carries its own first stderr line as "(cause: …)", and a failing CMD carries its exit status.
# Declined, on purpose (dir #755):
#   - CMD runs with errexit off. No form inside this lib makes `set -e` hold inside CMD while the caller
#     tests the lib's return, and every caller does (measured on bash 3.2 and 5.2). A CMD that writes in
#     several commands carries its own status (install.sh's manifest_body prints its whole body with one
#     printf).
#   - The temp is seeded by a `cp -p` of the whole file, only to carry its mode. A mode-only copy
#     (stat_portable_mode) depends on stat-portable.sh, which is OPTIONAL: without it the mode would fall
#     back to the umask silently. An EDIT target is a small text file.
#
# Names are `keel_`-prefixed (public) or `_keel_sw_`-prefixed (private): a bare name here would
# silently redefine a same-named function in a caller that sources this after its own
# (tools/lib/manifest.sh's header documents the lib-sourcing shadowing hazard).

case "${BASH_SOURCE[0]}" in
  */*) _keel_sw_libdir="${BASH_SOURCE[0]%/*}" ;;
  *)   _keel_sw_libdir=. ;;
esac
if ! KEEL_SAFE_WRITE_CHECKOUT="$(cd -P "$_keel_sw_libdir/../.." 2>/dev/null && pwd -P)"; then
  KEEL_SAFE_WRITE_CHECKOUT=""
fi

# stat-portable answers the hard-link count. OPTIONAL, as install.sh has always treated it: when it is
# missing or corrupt the count reads empty, and keel_write_through skips only its hard-link check — the
# write proceeds as it did before this lib. The decision lives here so every caller makes it the same
# way. A caller that already loaded it (install.sh primes its flavor cache for a hot loop) is left
# alone: re-sourcing would reset that cache.
if ! declare -F stat_portable_nlink >/dev/null 2>&1; then
  if [ -s "$_keel_sw_libdir/stat-portable.sh" ] && bash -n "$_keel_sw_libdir/stat-portable.sh" 2>/dev/null; then
    # shellcheck source=tools/lib/stat-portable.sh
    . "$_keel_sw_libdir/stat-portable.sh"
    # Probe the stat flavor once, here: keel_write_through reads the count inside a `$( )`, where a
    # lazily-probed flavor would be cached in a subshell that dies (stat-portable.sh's header).
    _stat_portable_ensure_flavor
  else
    stat_portable_nlink() { :; }
  fi
fi
unset _keel_sw_libdir

# _keel_sw_refuse MSG [TAIL] — the lib's one refusal line on stderr, "safe-write: MSG — TAIL." (TAIL
# defaults to "nothing was written"); returns 1.
_keel_sw_refuse() {
  echo "safe-write: $1 — ${2:-nothing was written}." >&2
  return 1
}

# _keel_sw_cause TEXT — " (cause: <TEXT's first line>)" for a failed command's captured stderr, or
# nothing when it printed none.
_keel_sw_cause() {
  local nl=$'\n'
  [ -n "$1" ] || return 0
  printf ' (cause: %s)' "${1%%"$nl"*}"
}

# _keel_sw_fail TMP MSG — the one refusal path after this run claimed TMP: remove TMP, print MSG as the
# lib's one line, return 1.
_keel_sw_fail() {
  rm -f "$1" 2>/dev/null || :
  _keel_sw_refuse "$2"
}

# _keel_sw_resolve PATH — prints PATH with every symlink hop followed (one `readlink` per hop, the
# portable form: no `-f`, which BSD readlink lacks before macOS 12.3). Returns 1 on a loop (more than
# 40 hops). A path that is not a link prints as given.
_keel_sw_resolve() {
  local p="$1" l n=0
  while [ -L "$p" ]; do
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
    l="$(readlink "$p")" || return 1
    case "$l" in
      /*) p="$l" ;;
      *) case "$p" in */*) p="${p%/*}/$l" ;; *) p="$l" ;; esac ;;
    esac
  done
  printf '%s\n' "$p"
}

# _keel_sw_dir_of PATH — PATH's directory part ("." for a bare name).
_keel_sw_dir_of() {
  case "$1" in
    */*) printf '%s\n' "${1%/*}" ;;
    *)   printf '.\n' ;;
  esac
}

# _keel_sw_inside DIR — true when DIR's physical path is the checkout's physical path, or below it
# (with the slash: a sibling such as `<checkout>-dots` is not inside). False when either cannot be
# resolved, or when the checkout is empty.
_keel_sw_inside() {
  local d ck
  [ -n "${KEEL_SAFE_WRITE_CHECKOUT:-}" ] || return 1
  ck="$(cd -P "$KEEL_SAFE_WRITE_CHECKOUT" 2>/dev/null && pwd -P)" || return 1
  d="$(cd -P "$1" 2>/dev/null && pwd -P)" || return 1
  case "$d" in
    "$ck"|"$ck"/*) return 0 ;;
  esac
  return 1
}

# keel_dir_is_checkouts_own DIR HOME — true when DIR is really the Keel checkout's own directory (B7 and
# B8 of the spec): its physical path is the checkout's, or below it, while HOME's is not (a home that
# itself lies inside the checkout is excluded from the rule). install.sh's product-directory helper and
# uninstall.sh's take() ask it, so the whole decision lives here, once.
keel_dir_is_checkouts_own() {
  _keel_sw_inside "$1" && ! _keel_sw_inside "$2"
}

# _keel_sw_check FILE strict|state — the refusals shared by the EDIT and STATE writes, decided before
# anything is written or claimed. On success sets $_keel_sw_target to FILE with every link hop followed.
# `strict` (an EDIT) also refuses a hard-linked target; `state` lets the rename split it.
_keel_sw_check() {
  local file="$1" target="$1" tdir nl
  if [ -L "$file" ] && ! target="$(_keel_sw_resolve "$file")"; then
    _keel_sw_refuse "$file is a symlink loop"
    return 1
  fi
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    _keel_sw_refuse "$target is not a regular file"
    return 1
  fi
  tdir="$(_keel_sw_dir_of "$target")"
  if [ ! -d "$tdir" ]; then
    _keel_sw_refuse "could not write $target (its directory is missing)"
    return 1
  fi
  if [ "$2" = strict ] && [ -f "$target" ]; then
    nl="$(stat_portable_nlink "$target")"
    case "$nl" in
      ''|*[!0-9]*) ;;   # unknown: only this check is skipped
      *)
        if [ "$nl" -gt 1 ]; then
          _keel_sw_refuse "$target is a hard link ($nl names for one file), and a rewrite would split it"
          return 1
        fi ;;
    esac
  fi
  if [ "$target" != "$file" ]; then
    if [ -z "${KEEL_SAFE_WRITE_CHECKOUT:-}" ]; then
      _keel_sw_refuse "$file is a link, and the Keel checkout is unknown (tools/lib/safe-write.sh could not resolve its own directory), so where it leads cannot be judged"
      return 1
    fi
    if _keel_sw_inside "$tdir" && ! _keel_sw_inside "$(_keel_sw_dir_of "$file")"; then
      _keel_sw_refuse "$file resolves to $target, inside the Keel checkout"
      return 1
    fi
  fi
  _keel_sw_target="$target"
}

# _keel_sw_claim TMP WHAT — claim Keel's scratch name TMP for writing WHAT (header): `rm -f` whatever is
# there, then a noclobber create under the caller's umask, which must leave a regular, non-link file.
# Returns 1 with the lib's one line when the claim fails (a directory at TMP, something re-planted in the
# instant between, an unwritable directory); nothing found at TMP is removed after that.
_keel_sw_claim() {
  local err=""
  rm -f "$1" 2>/dev/null || :
  if ! err="$( (set -C; : > "$1") 2>&1 )" || [ ! -f "$1" ] || [ -L "$1" ]; then
    _keel_sw_refuse "could not write $2: its temp name $1 could not be claimed$(_keel_sw_cause "$err")"
    return 1
  fi
}

# _keel_sw_write TARGET [CMD ARGS...] — the rename every EDIT and STATE write ends in, once _keel_sw_check
# has passed: TARGET is the resolved path. The temp starts as a `cp -p` of the target, and `>` onto an
# existing file keeps its mode, so the rename carries the target's permission bits. The temp is opened for
# writing on its own first, so a read-only target (its mode now on the temp too) is reported as that,
# never blamed on CMD.
_keel_sw_write() {
  local target="$1" tmp="$1.keeltmp.$$" err="" rc=0
  shift
  _keel_sw_claim "$tmp" "$target" || return 1
  if [ -f "$target" ] && ! err="$(cp -p "$target" "$tmp" 2>&1)"; then
    _keel_sw_fail "$tmp" "could not write $target (it cannot be read, or its directory is not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
  if ! err="$( { : > "$tmp"; } 2>&1 )"; then
    _keel_sw_fail "$tmp" "could not write $target (read-only, or its directory is not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
  if [ "$#" -gt 0 ]; then
    # In a subshell: an `exit` or a `set -u` abort inside a shell-function CMD stays a failed CMD
    # instead of ending the caller with a temp left beside the file. CMD's own stderr stays visible.
    ( "$@" ) > "$tmp" || rc=$?
    if [ "$rc" != 0 ]; then
      _keel_sw_fail "$tmp" "the new content for $target could not be produced (CMD exited $rc)"
      return 1
    fi
  elif ! err="$( { cat > "$tmp"; } 2>&1 )"; then
    _keel_sw_fail "$tmp" "could not write $target (read-only, or its directory is not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
  if ! err="$(mv -f "$tmp" "$target" 2>&1)"; then
    _keel_sw_fail "$tmp" "could not write $target (read-only, or its directory is not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
}

# keel_write_through FILE [CMD ARGS...] — the new content → FILE, as an EDIT (header). The content is
# CMD's stdout when a command is given, else stdin. Prefer the command form whenever the content is
# computed (an awk or grep over the file): a pipe hides its producer's exit status from the function, so
# a producer that dies halfway would get its partial output renamed onto FILE, while a failing CMD
# leaves FILE untouched. Returns 1, with one line on stderr and nothing written, on any refusal, a
# failing CMD or a failed write.
keel_write_through() {
  _keel_sw_check "$1" strict || return 1
  shift
  _keel_sw_write "$_keel_sw_target" "$@"
}

# keel_write_state FILE [CMD ARGS...] — keel_write_through for Keel's own state files (header): a
# hard-linked FILE is split, not refused; everything else is the same.
keel_write_state() {
  _keel_sw_check "$1" state || return 1
  shift
  _keel_sw_write "$_keel_sw_target" "$@"
}

# keel_backup_write_through FILE [CMD ARGS...] — keel_write_through with keel_backup FILE taken in
# between its checks and its write (header). Sets $KEEL_BACKUP to the backup's name on success only; on
# any refusal or failure it is empty and no backup is left behind.
keel_backup_write_through() {
  local file="$1" target b
  KEEL_BACKUP=""
  _keel_sw_check "$file" strict || return 1
  target="$_keel_sw_target"
  shift
  keel_backup "$file" || return 1
  b="$KEEL_BACKUP"
  KEEL_BACKUP=""
  if ! _keel_sw_write "$target" "$@"; then
    rm -f "$b" 2>/dev/null || :
    return 1
  fi
  # shellcheck disable=SC2034  # read by the caller right after this call (header)
  KEEL_BACKUP="$b"
}

# keel_write_replace PATH — stdin → PATH, as a REPLACE (header): a claimed temp sibling of PATH (never of
# a link's target) renamed onto it. A directory at PATH is refused: a rename onto one would nest the temp
# inside it and report success.
keel_write_replace() {
  local p="$1" tmp="$1.keeltmp.$$" err=""
  if [ -d "$p" ]; then
    _keel_sw_refuse "$p is a directory"
    return 1
  fi
  _keel_sw_claim "$tmp" "$p" || return 1
  if ! err="$( { cat > "$tmp"; } 2>&1 )" || ! err="$(mv -f "$tmp" "$p" 2>&1)"; then
    _keel_sw_fail "$tmp" "could not write $p (its directory is missing or not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
}

# keel_link_replace TARGET PATH — a symlink to TARGET at PATH, by the same rename (a link at the temp
# name, then `mv -f`), so PATH is replaced, never left missing mid-write. A link has no regular file to
# claim, so the temp name is cleared and must then be empty; `ln -n` never descends into a link to a
# directory that reappears there, and the link made is checked to be ours before the rename.
keel_link_replace() {
  local p="$2" tmp="$2.keeltmp.$$" err=""
  if [ -d "$p" ]; then
    _keel_sw_refuse "$p is a directory"
    return 1
  fi
  rm -f "$tmp" 2>/dev/null || :
  if [ -e "$tmp" ] || [ -L "$tmp" ]; then
    _keel_sw_refuse "could not link $p: its temp name $tmp is taken and could not be cleared"
    return 1
  fi
  if ! err="$(ln -sn "$1" "$tmp" 2>&1)"; then
    _keel_sw_refuse "could not link $p (its directory is missing or not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
  if [ ! -L "$tmp" ] || [ "$(readlink "$tmp" 2>/dev/null)" != "$1" ]; then
    _keel_sw_refuse "could not link $p: its temp name $tmp changed under it"
    return 1
  fi
  if ! err="$(mv -f "$tmp" "$p" 2>&1)"; then
    _keel_sw_fail "$tmp" "could not link $p (its directory is not writable)$(_keel_sw_cause "$err")"
    return 1
  fi
}

# keel_backup PATH — a copy of what PATH shows (read through a link) to a NEW file beside it:
# `<path>.<UTC %Y%m%dT%H%M%SZ>.bak`, then `<path>.<ts>.2.bak` … `.99.bak` when that is taken. Sets
# $KEEL_BACKUP to the claimed name. The name is CLAIMED by a noclobber `>` under umask 077, so two runs
# in one second still get two names, and a backup is 0600: the content goes in by `cat >`, which keeps
# the claimed file's mode everywhere (busybox `cp` onto an existing file gives it the source's mode).
# noclobber is not exclusive for a link at the name that resolves to an existing non-regular file
# (`/dev/null`), so a claim also has to leave a regular, non-link file behind, or the next name is
# tried. A PATH that exists but is not a regular file (a FIFO would block the copy forever) is refused
# before any name is claimed. Returns 1, with one line and nothing claimed left behind, when the path is
# refused, no name can be claimed or the copy fails; $KEEL_BACKUP is set only on success. KEEL_TEST_NOW
# (tests only) fixes the timestamp, so a collision can be staged.
keel_backup() {
  local base b n=1 err=""
  KEEL_BACKUP=""
  if [ -e "$1" ] && [ ! -f "$1" ]; then
    _keel_sw_refuse "$1 is not a regular file" "no backup was taken"
    return 1
  fi
  base="$1.${KEEL_TEST_NOW:-$(date -u +%Y%m%dT%H%M%SZ)}"
  b="$base.bak"
  while :; do
    # A name that is already taken is skipped before any claim: a claim opens the name for writing, and
    # opening a link to a FIFO nobody reads would block forever. The checks after the claim catch an
    # ordinary file or link that appears in between; a link to an unread FIFO planted in that instant
    # can still block the claim — a residual race, named here, not handled (no lock: the spec's K19).
    if [ ! -e "$b" ] && [ ! -L "$b" ]; then
      if err="$( (set -C; umask 077; : > "$b") 2>&1 )" && [ -f "$b" ] && [ ! -L "$b" ]; then
        break
      fi
      if [ ! -e "$b" ] && [ ! -L "$b" ]; then
        _keel_sw_refuse "cannot create a backup beside $1 (is its directory writable?)$(_keel_sw_cause "$err")"
        return 1
      fi
    fi
    n=$((n + 1))
    if [ "$n" -gt 99 ]; then
      _keel_sw_refuse "no free backup name beside $1 (.bak through .99.bak are taken)"
      return 1
    fi
    b="$base.$n.bak"
  done
  if ! err="$(cat "$1" 2>&1 > "$b")"; then
    rm -f "$b" 2>/dev/null || :
    _keel_sw_refuse "could not copy $1 to its backup$(_keel_sw_cause "$err")"
    return 1
  fi
  # shellcheck disable=SC2034  # read by the caller right after this call (header)
  KEEL_BACKUP="$b"
}
