#!/usr/bin/env bash
# test_stat_portable_lib.sh — dir #322: tools/lib/stat-portable.sh is the shared "detect the local
# stat flavor once, cache it" primitive extracted out of tools/branch-cleanup.sh's own STAT_FMT/
# epoch_mtime and tools/keel-impact.sh's own _impact_ensure_stat_fmt/_impact_file_mode (PR #314) — two
# independent copies of the identical pattern, one for mtimes and one for octal mode, found duplicated
# by two independent /code-review finder agents during PR #314's own review. Both callers are migrated
# onto this lib; tests/test_keel_impact.sh's own mode-probe mirror sources it directly too. Direct unit
# coverage for the lib itself, mirroring this repo's other shared-lib tests (test_nonneg_int_lib.sh,
# test_fence_blank_lib.sh): the coverage ratchet (dir #142, tools/self/doctor.sh) requires a real
# tests/*.sh reference outside a comment, not just a consumer that happens to source the file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/stat-portable.sh"
check_file "tools/lib/stat-portable.sh exists" "$lib"

# shellcheck source=/dev/null
. "$lib"

# --- _stat_portable_ensure_flavor: caches into one of the two known flavors ------------------------
_stat_portable_ensure_flavor
case "$_STAT_PORTABLE_FLAVOR" in
  c|f) pass "_stat_portable_ensure_flavor: caches a known flavor (c or f)" ;;
  *) fail "_stat_portable_ensure_flavor: caches a known flavor (c or f)" "got '$_STAT_PORTABLE_FLAVOR'" ;;
esac

# --- _stat_portable_ensure_flavor: a second call is a no-op (the whole point of the cache) — flip the
# cached value to a sentinel neither real probe would set, then confirm a second call leaves it alone
# instead of re-probing and overwriting it -----------------------------------------------------------
_STAT_PORTABLE_FLAVOR="sentinel"
_stat_portable_ensure_flavor
if [ "$_STAT_PORTABLE_FLAVOR" = "sentinel" ]; then
  pass "_stat_portable_ensure_flavor: a second call does not re-probe an already-cached flavor"
else
  fail "_stat_portable_ensure_flavor: a second call does not re-probe an already-cached flavor" \
    "flavor changed to '$_STAT_PORTABLE_FLAVOR'"
fi
_STAT_PORTABLE_FLAVOR=""
_stat_portable_ensure_flavor

# --- stat_portable_mtime/stat_portable_mode self-prime: a caller that never calls
# _stat_portable_ensure_flavor itself still gets a real answer (fail-safe, not a silent empty) --------
d="$(new_repo)"
printf 'hello\n' > "$d/unprimed.txt"
_STAT_PORTABLE_FLAVOR=""
m_unprimed="$(stat_portable_mtime "$d/unprimed.txt")"
case "$m_unprimed" in
  ''|*[!0-9]*)
    fail "stat_portable_mtime: self-primes when the caller never called _stat_portable_ensure_flavor" \
      "got '$m_unprimed'"
    ;;
  *) pass "stat_portable_mtime: self-primes when the caller never called _stat_portable_ensure_flavor" ;;
esac

# --- stat_portable_mtime: a freshly written file's mtime is a plausible epoch, close to "now" -------
d="$(new_repo)"
printf 'hello\n' > "$d/f.txt"
m="$(stat_portable_mtime "$d/f.txt")"
now="$(date +%s)"
case "$m" in
  ''|*[!0-9]*)
    fail "stat_portable_mtime: returns a numeric epoch" "got '$m'"
    ;;
  *)
    pass "stat_portable_mtime: returns a numeric epoch"
    diff=$(( now - m ))
    if [ "$diff" -ge -5 ] && [ "$diff" -le 300 ]; then
      pass "stat_portable_mtime: epoch is close to the current time (within 5 minutes)"
    else
      fail "stat_portable_mtime: epoch is close to the current time (within 5 minutes)" \
        "now=$now mtime=$m diff=${diff}s"
    fi
    ;;
esac

# --- stat_portable_mtime: a nonexistent file yields empty, not a crash ------------------------------
m_missing="$(stat_portable_mtime "$d/does-not-exist.txt")"
check_contains "stat_portable_mtime: a missing file yields empty output" "[$m_missing]" "[]"

# --- stat_portable_mode: round-trips a chmod'd file's octal mode ------------------------------------
printf 'hello\n' > "$d/mode.txt"
chmod 600 "$d/mode.txt"
mode600="$(stat_portable_mode "$d/mode.txt")"
check_contains "stat_portable_mode: chmod 600 reads back as 600" "$mode600" "600"

chmod 755 "$d/mode.txt"
mode755="$(stat_portable_mode "$d/mode.txt")"
check_contains "stat_portable_mode: chmod 755 reads back as 755" "$mode755" "755"

# --- stat_portable_mode: a nonexistent file yields empty, not a crash -------------------------------
mode_missing="$(stat_portable_mode "$d/does-not-exist.txt")"
check_contains "stat_portable_mode: a missing file yields empty output" "[$mode_missing]" "[]"

# --- stat_portable_nlink: an ordinary file is 1, a hard-linked one is >1 ----------------------------
# install.sh's never-clobber predicate keys on exactly this: a hard link is a regular file, so it is
# the only thing distinguishing "Keel's own copy" from "a name the adopter also reaches another way".
printf 'hello\n' > "$d/nlink.txt"
nlink_plain="$(stat_portable_nlink "$d/nlink.txt")"
check_status "stat_portable_nlink: an ordinary file reads back as 1" "1" "$nlink_plain"

ln "$d/nlink.txt" "$d/nlink-hard.txt"
nlink_hard="$(stat_portable_nlink "$d/nlink.txt")"
check_status "stat_portable_nlink: a hard-linked file reads back as 2" "2" "$nlink_hard"
check_status "stat_portable_nlink: …from either name" "2" "$(stat_portable_nlink "$d/nlink-hard.txt")"

# It does NOT follow symlinks: given a link to a target that HAS 2 links, it answers 1 — the link's own
# inode. Pinned in the discriminating shape, with the hard link still in place: an earlier version of
# this test removed the hard link first, which dropped the target to 1 and made "follows" and "does not
# follow" both answer 1, so it could not fail either way. install.sh is safe regardless (it rejects
# symlinks on an earlier clause), but the contract is what the next caller reads, and the error is in
# the under-reporting direction — a symlink looks exactly like an ordinary file.
ln -s "$d/nlink.txt" "$d/nlink-sym.txt"
check_status "stat_portable_nlink: a symlink reports its OWN count, not the 2-link target's" "1" "$(stat_portable_nlink "$d/nlink-sym.txt")"
check_status "stat_portable_nlink: …while the target itself still reads 2" "2" "$(stat_portable_nlink "$d/nlink.txt")"
# The sibling behaves the same way, which is why the docstring no longer claims either follows.
chmod 600 "$d/nlink.txt"
check_absent "stat_portable_mode: a symlink likewise reports its own bits, not the target's 600" \
  "[$(stat_portable_mode "$d/nlink-sym.txt")]" "[600]"
rm -f "$d/nlink-hard.txt"

# --- stat_portable_nlink: a nonexistent file yields empty, not a crash ------------------------------
# The caller (install.sh's keel_own_untouched) treats empty as UNKNOWN and refuses, so this empty is
# load-bearing in the fail-closed direction, not merely tidy.
nlink_missing="$(stat_portable_nlink "$d/does-not-exist.txt")"
check_contains "stat_portable_nlink: a missing file yields empty output" "[$nlink_missing]" "[]"

# --- the known consumer sources the shared lib, not a private inline copy of the probe ---------------
check_contains "tools/branch-cleanup.sh sources tools/lib/stat-portable.sh" \
  "$(cat "$REPO_ROOT/tools/branch-cleanup.sh")" 'lib/stat-portable.sh'
check_contains "tools/branch-cleanup.sh calls _stat_portable_ensure_flavor" \
  "$(cat "$REPO_ROOT/tools/branch-cleanup.sh")" '_stat_portable_ensure_flavor'
check_contains "tools/branch-cleanup.sh calls stat_portable_mtime" \
  "$(cat "$REPO_ROOT/tools/branch-cleanup.sh")" 'stat_portable_mtime "$f"'
check_absent "tools/branch-cleanup.sh no longer defines its own epoch_mtime" \
  "$(cat "$REPO_ROOT/tools/branch-cleanup.sh")" 'epoch_mtime()'

check_contains "tools/keel-impact.sh sources tools/lib/stat-portable.sh" \
  "$(cat "$REPO_ROOT/tools/keel-impact.sh")" 'lib/stat-portable.sh'
check_contains "tools/keel-impact.sh calls stat_portable_mode" \
  "$(cat "$REPO_ROOT/tools/keel-impact.sh")" 'stat_portable_mode "$target"'
check_absent "tools/keel-impact.sh no longer defines its own _impact_file_mode" \
  "$(cat "$REPO_ROOT/tools/keel-impact.sh")" '_impact_file_mode()'

summary
