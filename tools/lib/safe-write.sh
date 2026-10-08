# shellcheck shell=bash
# tools/lib/safe-write.sh — the ONE place an installer writes a file by temp-and-rename (dir #679, slice 1
# of docs/specs/685-symlink-policy.md). install.sh, uninstall.sh, tools/register-project.sh, the hook
# installers (through tools/lib/hook-install.sh) and tools/lib/ledger.sh all write through here, so a
# symlink, a hard link, a file's mode and a backup's name are decided once, the same way everywhere.
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
#             settings.json, the ledger, INSTANCE.md, the manifest). It follows every symlink hop, so
#             the link stays a link and the file it names gets the new content, and it keeps that file's
#             permission bits. It refuses, with one line and nothing written: a loop; a target that is
#             not a regular file; a target with a second hard link (a rename would split it); a link
#             into a directory that does not exist; and a target inside the Keel checkout reached
#             through a path that is not (a dotfiles CLAUDE.md linked to the checkout's own template
#             must never get its rails stripped).
#   REPLACE — keel_write_replace / keel_link_replace: a whole file (or link) of Keel content. A temp
#             sibling of the path is renamed onto it, never `cp` or `>` into an existing file, so a hard
#             link's other name keeps its bytes. The new file gets the umask.
#   BACKUP  — keel_backup: a new file beside the path, claimed by an exclusive create, never an
#             overwrite of an earlier backup.
# Whether a path may be replaced at all (a symlink Keel did not make, a user's own file) is the caller's
# decision, made before it calls here.
#
# Every caller names its Keel checkout in KEEL_SAFE_WRITE_CHECKOUT before writing (a shell variable it
# sets itself, not one read from the caller's environment). Unset, the checkout clause is skipped.
#
# Names are `keel_`-prefixed (public) or `_keel_sw_`-prefixed (private): a bare name here would
# silently redefine a same-named function in a caller that sources this after its own
# (tools/lib/manifest.sh's header documents the lib-sourcing shadowing hazard).

# stat-portable answers the hard-link count. OPTIONAL, as install.sh has always treated it: when it is
# missing or corrupt the count reads empty, and keel_write_through skips only its hard-link check — the
# write proceeds as it did before this lib. The decision lives here so every caller makes it the same
# way. A caller that already loaded it (install.sh primes its flavor cache for a hot loop) is left
# alone: re-sourcing would reset that cache.
if ! declare -F stat_portable_nlink >/dev/null 2>&1; then
  case "${BASH_SOURCE[0]}" in
    */*) _keel_sw_libdir="${BASH_SOURCE[0]%/*}" ;;
    *)   _keel_sw_libdir=. ;;
  esac
  if [ -s "$_keel_sw_libdir/stat-portable.sh" ] && bash -n "$_keel_sw_libdir/stat-portable.sh" 2>/dev/null; then
    # shellcheck source=tools/lib/stat-portable.sh
    . "$_keel_sw_libdir/stat-portable.sh"
  else
    stat_portable_nlink() { :; }
  fi
  unset _keel_sw_libdir
fi

# keel_resolve_path PATH — prints PATH with every symlink hop followed (one `readlink` per hop, the
# portable form: no `-f`, which BSD readlink lacks before macOS 12.3). Returns 1 on a loop (more than
# 40 hops). A path that is not a link prints as given.
keel_resolve_path() {
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
# resolved, or when no checkout was named.
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

# keel_write_through FILE — stdin → FILE, as an EDIT (header). Returns 1, with one line on stderr and
# nothing written, on any refusal or a failed write.
keel_write_through() {
  local file="$1" target="$1" tdir nl tmp
  if [ -L "$file" ] && ! target="$(keel_resolve_path "$file")"; then
    echo "safe-write: $file is a symlink loop — nothing was written." >&2
    return 1
  fi
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    echo "safe-write: $target is not a regular file — nothing was written." >&2
    return 1
  fi
  tdir="$(_keel_sw_dir_of "$target")"
  if [ ! -d "$tdir" ]; then
    echo "safe-write: could not write $target (its directory is missing) — nothing was written." >&2
    return 1
  fi
  if [ -f "$target" ]; then
    nl="$(stat_portable_nlink "$target")"
    case "$nl" in
      ''|*[!0-9]*) ;;   # unknown: only this check is skipped
      *)
        if [ "$nl" -gt 1 ]; then
          echo "safe-write: $target is a hard link ($nl names for one file) — a rewrite would split it, so nothing was written." >&2
          return 1
        fi ;;
    esac
  fi
  if [ "$target" != "$file" ] && _keel_sw_inside "$tdir" && ! _keel_sw_inside "$(_keel_sw_dir_of "$file")"; then
    echo "safe-write: $file resolves to $target, inside the Keel checkout — nothing was written." >&2
    return 1
  fi
  tmp="$target.keeltmp.$$"
  # The temp starts as a `cp -p` of the target, and `>` onto an existing file keeps its mode, so the
  # rename carries the target's permission bits. A read-only target (its mode now on the temp too)
  # fails here, as it should.
  if ! { { [ ! -f "$target" ] || cp -p "$target" "$tmp"; } && cat > "$tmp" && mv -f "$tmp" "$target"; } 2>/dev/null; then
    rm -f "$tmp"
    echo "safe-write: could not write $target (read-only, or its directory is not writable) — nothing was written." >&2
    return 1
  fi
}

# keel_write_replace PATH — stdin → PATH, as a REPLACE (header): a temp sibling of PATH (never of a
# link's target) renamed onto it. A directory at PATH is refused: a rename onto one would nest the temp
# inside it and report success.
keel_write_replace() {
  local p="$1" tmp="$1.keeltmp.$$"
  if [ -d "$p" ]; then
    echo "safe-write: $p is a directory — nothing was written." >&2
    return 1
  fi
  if ! { cat > "$tmp" && mv -f "$tmp" "$p"; } 2>/dev/null; then
    rm -f "$tmp"
    echo "safe-write: could not write $p (its directory is missing or not writable) — nothing was written." >&2
    return 1
  fi
}

# keel_link_replace TARGET PATH — a symlink to TARGET at PATH, by the same rename (`ln -s` to a temp
# name, then `mv -f`), so PATH is replaced, never left missing mid-write.
keel_link_replace() {
  local p="$2" tmp="$2.keeltmp.$$"
  if [ -d "$p" ]; then
    echo "safe-write: $p is a directory — nothing was written." >&2
    return 1
  fi
  if ! { ln -s "$1" "$tmp" && mv -f "$tmp" "$p"; } 2>/dev/null; then
    rm -f "$tmp"
    echo "safe-write: could not link $p (its directory is missing or not writable) — nothing was written." >&2
    return 1
  fi
}

# keel_backup PATH — a copy of what PATH shows (read through a link) to a NEW file beside it:
# `<path>.<UTC %Y%m%dT%H%M%SZ>.bak`, then `<path>.<ts>.2.bak` … `.99.bak` when that is taken. Sets
# $KEEL_BACKUP to the claimed name. The name is CLAIMED by a noclobber `>` under umask 077, so two runs
# in one second still get two names, and a backup is 0600 (cp keeps an existing destination's mode).
# noclobber is not exclusive for a link at the name that resolves to an existing non-regular file
# (`/dev/null`), so a claim also has to leave a regular, non-link file behind, or the next name is
# tried. Returns 1, with one line and nothing claimed left behind, when no name can be claimed or the
# copy fails. KEEL_TEST_NOW (tests only) fixes the timestamp, so a collision can be staged.
keel_backup() {
  local base n=1
  base="$1.${KEEL_TEST_NOW:-$(date -u +%Y%m%dT%H%M%SZ)}"
  KEEL_BACKUP="$base.bak"
  until (set -C; umask 077; : > "$KEEL_BACKUP") 2>/dev/null && [ -f "$KEEL_BACKUP" ] && [ ! -L "$KEEL_BACKUP" ]; do
    if [ ! -e "$KEEL_BACKUP" ] && [ ! -L "$KEEL_BACKUP" ]; then
      echo "safe-write: cannot create a backup beside $1 (is its directory writable?) — nothing was written." >&2
      KEEL_BACKUP=""
      return 1
    fi
    n=$((n + 1))
    if [ "$n" -gt 99 ]; then
      echo "safe-write: no free backup name beside $1 (.bak through .99.bak are taken) — nothing was written." >&2
      KEEL_BACKUP=""
      return 1
    fi
    KEEL_BACKUP="$base.$n.bak"
  done
  if ! cp "$1" "$KEEL_BACKUP" 2>/dev/null; then
    rm -f "$KEEL_BACKUP"
    echo "safe-write: could not copy $1 to its backup — nothing was written." >&2
    KEEL_BACKUP=""
    return 1
  fi
}
