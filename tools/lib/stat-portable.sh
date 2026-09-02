# shellcheck shell=bash
# tools/lib/stat-portable.sh (dir #322) — the ONE portable-`stat`-flavor cache, for every tool that
# needs an epoch mtime or an octal mode: GNU/busybox `stat` takes `-c '%Y'`/`-c '%a'`, BSD/macOS `stat`
# takes `-f '%m'`/`-f '%Lp'`. tools/branch-cleanup.sh's `STAT_FMT`/`epoch_mtime` and PR #314's
# tools/keel-impact.sh `_impact_ensure_stat_fmt`/`_impact_file_mode` independently reimplemented this
# probe-once-cache pattern, one for mtimes and one for octal mode. Found duplicated by two independent
# /code-review finder agents during PR #314's own review — consolidated here, both callers migrated,
# instead of a third copy drifting apart the way tools/lib/fence-blank.sh's own header describes for
# its class.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
#
# Probed against THIS FILE's own path (`${BASH_SOURCE[0]}`), not the caller's `$0` — a library is
# always sourced via a real path (`. ".../lib/stat-portable.sh"`), so probing itself sidesteps the
# caveat tools/branch-cleanup.sh's predecessor code carried: a caller invoked via stdin (not by path)
# would make ITS `$0` unstat-able and silently pin the probe to the BSD form.
#
# Both probe functions below self-prime (call `_stat_portable_ensure_flavor` as their own first
# statement) — safe to do even when invoked via a subshell-forking `$(...)`, since the guard is a
# plain, non-subshelled statement inside the same function body. For a HOT LOOP, still call
# `_stat_portable_ensure_flavor` yourself once, eagerly, before the loop (see
# tools/branch-cleanup.sh): a parent-shell cache is inherited by every subshell a later `$(...)` call
# forks, so priming up front costs one `stat` fork total. Skipping that costs one extra `stat` fork
# PER CALL instead (self-priming fresh in each call's own short-lived subshell, then discarding it) —
# correct, just needlessly slower for anything called in a loop.
_STAT_PORTABLE_FLAVOR=""
_stat_portable_ensure_flavor() {
  [ -n "$_STAT_PORTABLE_FLAVOR" ] && return 0
  _STAT_PORTABLE_FLAVOR=c
  stat -c '%Y' "${BASH_SOURCE[0]}" >/dev/null 2>&1 || _STAT_PORTABLE_FLAVOR=f
}

# `stat_portable_mtime FILE` — epoch seconds, or empty (stderr suppressed) if FILE is unreadable.
stat_portable_mtime() {
  _stat_portable_ensure_flavor
  case "$_STAT_PORTABLE_FLAVOR" in
    c) stat -c '%Y' "$1" 2>/dev/null ;;
    f) stat -f '%m' "$1" 2>/dev/null ;;
  esac
}

# `stat_portable_mode FILE` — octal permission bits (e.g. "600"), or empty if FILE is unreadable.
stat_portable_mode() {
  _stat_portable_ensure_flavor
  case "$_STAT_PORTABLE_FLAVOR" in
    c) stat -c '%a' "$1" 2>/dev/null ;;
    f) stat -f '%Lp' "$1" 2>/dev/null ;;
  esac
}

# `stat_portable_nlink FILE` — FILE's hard-link count ("1" for an ordinary file, ">1" when something
# else names the same inode), or empty if FILE is unstattable.
# Measured on both flavors rather than assumed: BusyBox v1.37.0 (the alpine-busybox CI leg's own image)
# answers `stat -c '%h'` with 2 for a hard-linked file and 1 for a plain one, exit 0; macOS's BSD stat
# answers `stat -f '%l'` identically.
# Two things a caller must not assume, both measured rather than reasoned:
#   - It does NOT follow symlinks. Given a link to a 2-link target it answers 1 — the LINK's own inode.
#     None of the three functions here pass `-L`, so this matches stat_portable_mode, which likewise
#     reports a symlink's own bits (755) rather than its target's (600). A caller that must reason
#     about the target has to resolve the path first. This matters in the under-reporting direction:
#     a symlink reads as "1", i.e. indistinguishable from an ordinary file.
#   - Callers that must fail CLOSED have to treat an EMPTY answer as "unknown", not as "1" — an
#     unstattable file is exactly the case where guessing is unsafe.
stat_portable_nlink() {
  _stat_portable_ensure_flavor
  case "$_STAT_PORTABLE_FLAVOR" in
    c) stat -c '%h' "$1" 2>/dev/null ;;
    f) stat -f '%l' "$1" 2>/dev/null ;;
  esac
}
