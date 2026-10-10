#!/usr/bin/env bash
# install-secret-guard.sh's WRITES (dir #684, spec 685 round 2, slice S3a) and its hooks-location answer
# (dir #748 S4-1, B27):
#   A27  a hard-linked hook (foreign under --force, or Keel's on a re-vendor) is replaced by rename, never
#        written into — the other name keeps its bytes
#   A28  --force's backup is claimed by a noclobber create (.pre-keel.bak, then .pre-keel.2.bak …), so a file
#        that appears between the pre-flight and the backup is never overwritten; a rollback restores each
#        hook from the name ITS run claimed, executable exactly as it was
#   A51/A52  a core.hooksPath set at any scope, the empty value included, is the user's wiring
#   A53/A54  the passengers: a stale comment, the doc paragraph naming the two exceptions this closes
# The standalone installer ships copy-standalone (no tools/lib/), so the race is staged through a scratch
# copy whose source secret-scan.sh --selftest plants the colliding file mid-run.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

isg="$REPO_ROOT/tools/install-secret-guard.sh"
shipped="$REPO_ROOT/tools/secret-guard"
install="$REPO_ROOT/install.sh"

# mk_foreign <hooks-dir> <name> <marker> [noexec] — a user's own hook (no Keel marker line).
mk_foreign() {
  mkdir -p "$1"
  printf '#!/bin/sh\n# %s\nexit 0\n' "$3" > "$1/$2"
  if [ "${4:-}" = noexec ]; then chmod -x "$1/$2"; else chmod +x "$1/$2"; fi
}
# lines <text> — how many lines the text holds.
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }
# mk_stub <label> <shebang> — a scratch copy of the installer whose source secret-scan.sh --selftest passes and,
# for each path in $ISG_RACE_FILES that is still free, plants RACE there (the mid-run appearance A28 stages).
# A shebang naming a missing interpreter passes the pre-copy `bash <file> --selftest` and fails the post-copy
# direct exec — the existing post-copy-only failure the rollback tests use.
mk_stub() {
  local d f
  d="$(mktemp -d "$SANDBOX/isg-$1.XXXXXX")"
  cp "$isg" "$d/install-secret-guard.sh"
  mkdir -p "$d/secret-guard"
  for f in pre-commit pre-push range-lib.sh; do
    cp "$shipped/$f" "$d/secret-guard/$f"
    chmod +x "$d/secret-guard/$f"
  done
  {
    printf '%s\n' "$2"
    printf '%s\n' 'if [ "${1:-}" = --selftest ]; then' \
      '  for t in ${ISG_RACE_FILES:-}; do [ -e "$t" ] || [ -L "$t" ] || printf "RACE\n" > "$t"; done' \
      '  echo "selftest: OK (stub)"' 'fi' 'exit 0'
  } > "$d/secret-guard/secret-scan.sh"
  chmod +x "$d/secret-guard/secret-scan.sh"
  printf '%s' "$d"
}
ok_stub="$(mk_stub ok '#!/usr/bin/env bash')"
bad_stub="$(mk_stub bad '#!/nonexistent/not-a-real-interpreter')"

# =============================================================================================================
# A27 — a hard-linked hook is replaced by rename; the other name keeps its bytes.
# =============================================================================================================
h27="$(new_repo)/.git/hooks"; r27="${h27%/.git/hooks}"
mk_foreign "$h27" pre-commit "foreign hook, hard-linked elsewhere"
out27="$SANDBOX/a27-outside"
ln "$h27/pre-commit" "$out27"
want27="$(cat "$out27")"
run bash "$ok_stub/install-secret-guard.sh" --force "$r27"
check_status "A27: --force over a hard-linked foreign hook → exit 0" 0 "$STATUS"
check_eq "A27: the outside name's bytes are unchanged" "$want27" "$(cat "$out27")"
if cmp -s "$shipped/pre-commit" "$h27/pre-commit"; then pass "A27: the hook is Keel's now (the shipped pre-commit, byte for byte)"
else fail "A27: the hook is Keel's now" "installed pre-commit differs from the shipped one"; fi
if [ "$h27/pre-commit" -ef "$out27" ]; then fail "A27: the hook is a new inode, not the shared one" "still the same inode"
else pass "A27: the hook is a new inode, not the shared one"; fi
check_contains "A27: the backup holds the foreign hook" "$(cat "$h27/pre-commit.pre-keel.bak")" "foreign hook, hard-linked elsewhere"

# the same for a KEEL hook and the scanner on a plain re-vendor (no --force)
r27b="$(new_repo)"; h27b="$r27b/.git/hooks"
run bash "$ok_stub/install-secret-guard.sh" "$r27b"
check_status "A27: first vendoring → exit 0" 0 "$STATUS"
for f in pre-commit secret-scan.sh; do
  printf '# stale tail of an older version\n' >> "$h27b/$f"
  ln "$h27b/$f" "$SANDBOX/a27b-outside-$f"
done
run "$isg" "$r27b"
check_status "A27: a plain re-vendor over hard-linked Keel files → exit 0" 0 "$STATUS"
for f in pre-commit secret-scan.sh; do
  check_contains "A27: the other name of a hard-linked Keel $f keeps its bytes" \
    "$(cat "$SANDBOX/a27b-outside-$f")" "stale tail of an older version"
  if cmp -s "$shipped/$f" "$h27b/$f"; then pass "A27: $f is the shipped file again"
  else fail "A27: $f is the shipped file again" "differs from the shipped file"; fi
  if [ -x "$h27b/$f" ]; then pass "A27: re-vendored $f keeps its execute bit"; else fail "A27: re-vendored $f keeps its execute bit" "not executable"; fi
done
leftover27="$(find "$h27b" "$h27" -name '*.isgtmp.*' 2>/dev/null)"
check_eq "A27: no staging file is left behind" "" "$leftover27"

# =============================================================================================================
# A28 — the mid-run race, staged; per-hook claimed names; rollback restores from them, executable as it was.
# =============================================================================================================
# (1) a free-looking .pre-keel.bak is taken by the selftest → the backup lands at .pre-keel.2.bak
r28="$(new_repo)"; h28="$r28/.git/hooks"
mk_foreign "$h28" pre-commit "foreign pre-commit A28"
run env "ISG_RACE_FILES=$h28/pre-commit.pre-keel.bak" bash "$ok_stub/install-secret-guard.sh" --force "$r28"
check_status "A28: the race, --force → exit 0" 0 "$STATUS"
check_eq "A28: the appeared file is untouched" "RACE" "$(cat "$h28/pre-commit.pre-keel.bak")"
check_contains "A28: .pre-keel.2.bak holds the foreign hook" "$(cat "$h28/pre-commit.pre-keel.2.bak")" "foreign pre-commit A28"
check_contains "A28: the backup line names .pre-keel.2.bak" "$OUT" "pre-commit.pre-keel.2.bak"
if [ -x "$h28/pre-commit.pre-keel.2.bak" ]; then pass "A28: the backup of an executable hook is executable"
else fail "A28: the backup of an executable hook is executable" "not executable"; fi

# (2) the same fixture with a forced post-copy failure → the foreign hook comes back from .pre-keel.2.bak, executable
r28b="$(new_repo)"; h28b="$r28b/.git/hooks"
mk_foreign "$h28b" pre-commit "foreign pre-commit A28b"
run env "ISG_RACE_FILES=$h28b/pre-commit.pre-keel.bak" bash "$bad_stub/install-secret-guard.sh" --force "$r28b"
check_status "A28: race + forced post-copy failure → exit 4" 4 "$STATUS"
check_contains "A28: the foreign hook is restored from the name this run claimed" \
  "$(cat "$h28b/pre-commit" 2>/dev/null)" "foreign pre-commit A28b"
if [ -x "$h28b/pre-commit" ]; then pass "A28: the restored foreign hook is executable"; else fail "A28: the restored foreign hook is executable" "not executable"; fi
check_eq "A28: RACE stays where it appeared" "RACE" "$(cat "$h28b/pre-commit.pre-keel.bak")"
check_nofile "A28: the claimed backup is consumed by the restore" "$h28b/pre-commit.pre-keel.2.bak"

# (3) a foreign hook with NO execute bit stays not executable after a rollback (git skips it; its owner disabled it)
r28c="$(new_repo)"; h28c="$r28c/.git/hooks"
mk_foreign "$h28c" pre-commit "foreign disabled pre-commit" noexec
run bash "$bad_stub/install-secret-guard.sh" --force "$r28c"
check_status "A28: non-executable foreign hook, forced post-copy failure → exit 4" 4 "$STATUS"
check_contains "A28: ...its bytes come back" "$(cat "$h28c/pre-commit" 2>/dev/null)" "foreign disabled pre-commit"
if [ -x "$h28c/pre-commit" ]; then fail "A28: ...and it is still not executable" "the rollback made it executable"
else pass "A28: ...and it is still not executable"; fi

# (4) a Keel hook re-vendored then a failure: the restored Keel hook is executable (twin of test_secret_guard.sh's
#     "re-vendoring over an ALREADY-INSTALLED Keel hook" rollback row)
r28d="$(new_repo)"
run bash "$ok_stub/install-secret-guard.sh" "$r28d"
check_status "A28: genuine first install → exit 0" 0 "$STATUS"
run bash "$bad_stub/install-secret-guard.sh" "$r28d"
check_status "A28: re-vendor + forced post-copy failure → exit 4" 4 "$STATUS"
for f in pre-commit pre-push secret-scan.sh; do
  if [ -x "$r28d/.git/hooks/$f" ]; then pass "A28: the restored Keel $f is executable"; else fail "A28: the restored Keel $f is executable" "not executable"; fi
done

# (5) both hooks foreign, the race on one: each restored hook has its OWN original bytes (per-hook names)
r28e="$(new_repo)"; h28e="$r28e/.git/hooks"
mk_foreign "$h28e" pre-commit "foreign commit E"
mk_foreign "$h28e" pre-push "foreign push E"
run env "ISG_RACE_FILES=$h28e/pre-commit.pre-keel.bak" bash "$ok_stub/install-secret-guard.sh" --force "$r28e"
check_status "A28: both foreign, race on pre-commit, --force → exit 0" 0 "$STATUS"
check_contains "A28: pre-commit's backup is .pre-keel.2.bak" "$OUT" "pre-commit.pre-keel.2.bak"
check_contains "A28: pre-push's backup is .pre-keel.bak" "$OUT" "pre-push.pre-keel.bak"
check_contains "A28: pre-push.pre-keel.bak holds the foreign push" "$(cat "$h28e/pre-push.pre-keel.bak")" "foreign push E"
r28f="$(new_repo)"; h28f="$r28f/.git/hooks"
mk_foreign "$h28f" pre-commit "foreign commit F"
mk_foreign "$h28f" pre-push "foreign push F"
run env "ISG_RACE_FILES=$h28f/pre-commit.pre-keel.bak" bash "$bad_stub/install-secret-guard.sh" --force "$r28f"
check_status "A28: both foreign, race, forced failure → exit 4" 4 "$STATUS"
check_contains "A28: pre-commit is restored with its OWN bytes" "$(cat "$h28f/pre-commit" 2>/dev/null)" "foreign commit F"
check_contains "A28: pre-push is restored with its OWN bytes" "$(cat "$h28f/pre-push" 2>/dev/null)" "foreign push F"
check_eq "A28: RACE stays" "RACE" "$(cat "$h28f/pre-commit.pre-keel.bak")"

# (6) a dangling link at .pre-keel.2.bak → the backup lands at .3.bak, the link's target is never created
r28g="$(new_repo)"; h28g="$r28g/.git/hooks"
mk_foreign "$h28g" pre-commit "foreign commit G"
dang="$SANDBOX/a28-dangling-target"; rm -f "$dang"
ln -s "$dang" "$h28g/pre-commit.pre-keel.2.bak"
run env "ISG_RACE_FILES=$h28g/pre-commit.pre-keel.bak" bash "$ok_stub/install-secret-guard.sh" --force "$r28g"
check_status "A28: a dangling link at .pre-keel.2.bak → exit 0" 0 "$STATUS"
check_contains "A28: the backup lands at .pre-keel.3.bak" "$(cat "$h28g/pre-commit.pre-keel.3.bak" 2>/dev/null)" "foreign commit G"
check_nofile "A28: the link's target is never created" "$dang"
check_link "A28: the dangling link itself is untouched" "$h28g/pre-commit.pre-keel.2.bak"

# (7) a directory where the installer places a file → exit 3, ONE line, nothing written
for f in pre-commit pre-push secret-scan.sh range-lib.sh; do
  rd="$(new_repo)"; hd="$rd/.git/hooks"; mkdir -p "$hd/$f"
  before="$(ls -A "$hd" | sort | tr '\n' ' ')"
  run "$isg" --force "$rd"
  check_status "A28: a directory at $f, --force → exit 3" 3 "$STATUS"
  check_eq "A28: ...one line" 1 "$(lines "$OUT")"
  check_contains "A28: ...naming the directory" "$OUT" "$hd/$f"
  check_eq "A28: ...nothing written into the hooks dir" "$before" "$(ls -A "$hd" | sort | tr '\n' ' ')"
  check_nofile "A28: ...no allowlist seed written" "$rd/.secret-scan-allow"
done

# (8) the dir #625 pre-flight stays, reworded: --force would no longer overwrite the earlier backup
r28h="$(new_repo)"; h28h="$r28h/.git/hooks"
mk_foreign "$h28h" pre-commit "foreign commit H"
printf 'an earlier saved hook\n' > "$h28h/pre-commit.pre-keel.bak"
run "$isg" --force "$r28h"
check_status "A28: an existing .pre-keel.bak still refuses → exit 3" 3 "$STATUS"
check_contains "A28: the refusal names the earlier backup" "$OUT" "pre-commit.pre-keel.bak"
check_contains "A28: ...in the reworded reason" "$OUT" "an earlier backup of a hook is waiting at"
check_contains "A28: ...saying what to do" "$OUT" "restore or move it first"
check_absent "A28: ...no longer claiming --force would overwrite it" "$OUT" "would overwrite"
check_eq "A28: the earlier backup is untouched" "an earlier saved hook" "$(cat "$h28h/pre-commit.pre-keel.bak")"

# (9) --uninstall's advice for a vendored copy names the newest numbered backup
run "$isg" --uninstall "$r28h"
check_status "A28: --uninstall <repo> → exit 2" 2 "$STATUS"
check_contains "A28: the advice names the newest backup" "$OUT" "pre-keel*.bak"

# =============================================================================================================
# A51 / A52 — B27: a hooksPath set at any scope, the empty value included, is the user's wiring.
# =============================================================================================================
mk_b() { B="$SANDBOX/b27-$1"; mkdir -p "$B"; : > "$B/system.cfg"; }
benv() { env "HOME=$B" "GIT_CONFIG_GLOBAL=$B/.gitconfig" "GIT_CONFIG_SYSTEM=$B/system.cfg" "$@"; }
# cfg_rc <file> <key> — the exit status of reading <key> from <file> (git config --file, never --global).
cfg_rc() { local rc=0; git config --file "$1" --get "$2" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
cfg_val() { git config --file "$1" --get "$2" 2>/dev/null || true; }

mk_b empty
printf '[core]\n\thooksPath =\n' > "$B/.gitconfig"
cp "$B/.gitconfig" "$B/.gitconfig.before"
run benv "$isg" --global
check_status "A51: an empty global hooksPath, --global → exit 3" 3 "$STATUS"
check_contains "A51: the refusal names the empty value" "$OUT" "empty"
check_eq "A51: nothing was written to the config" "$(cat "$B/.gitconfig.before")" "$(cat "$B/.gitconfig")"
check_nodir "A51: no Keel hooks dir was created" "$B/.config/git/keel-hooks"

# the same through _isg_machine_read's narrow branch (a PATH shim mktemp that fails → fallback=1)
mkdir -p "$SANDBOX/shim-mktemp"
printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/shim-mktemp/mktemp"; chmod +x "$SANDBOX/shim-mktemp/mktemp"
run benv "PATH=$SANDBOX/shim-mktemp:$PATH" "$isg" --global
check_status "A51: ...through the narrow branch → exit 3" 3 "$STATUS"
check_contains "A51: ...also names the empty value" "$OUT" "empty"
check_nodir "A51: ...and writes nothing" "$B/.config/git/keel-hooks"

# --where: set= is decided by the exit status; scope= is no longer none for an empty value
run benv "$isg" --where --global
check_contains "A51: --where --global over an empty hooksPath prints set=1" "$OUT" "set=1"
check_absent "A51: ...and a scope other than none" "$OUT" "scope=none"
rw51="$(new_repo)"
run benv "$isg" --where "$rw51"
check_contains "A51: --where <repo> over an empty hooksPath prints set=1" "$OUT" "set=1"
check_absent "A51: ...and a scope other than none" "$OUT" "scope=none"
run benv "PATH=$SANDBOX/shim-mktemp:$PATH" "$isg" --where --global
check_contains "A51: the narrow branch prints set=1 as well" "$OUT" "set=1"
check_contains "A51: ...with fallback=1" "$OUT" "fallback=1"
mk_b unset
: > "$B/.gitconfig"
run benv "$isg" --where --global
check_contains "A51: --where --global with no hooksPath prints set=0" "$OUT" "set=0"
check_contains "A51: ...and scope=none" "$OUT" "scope=none"

# a default install.sh over the same config takes its "not clobbering" branch
mk_b inst
printf '[core]\n\thooksPath =\n' > "$B/.gitconfig"
run benv "$install" --home "$B/claude-home"
check_contains "A51: install.sh over an empty hooksPath prints its not-clobbering line" "$OUT" "not clobbering it"
check_absent "A51: ...and not 'secret-guard wiring failed'" "$OUT" "secret-guard wiring failed"
check_nodir "A51: ...with no Keel hooks dir written" "$B/.config/git/keel-hooks"

# K43a: a valueless hooksPath is refused even with --force, in one line
mk_b valueless
printf '[core]\n\thooksPath\n' > "$B/.gitconfig"
run benv "$isg" --global --force
check_status "A51 (K43a): a valueless hooksPath, --global --force → exit 3" 3 "$STATUS"
check_eq "A51 (K43a): ...one line" 1 "$(lines "$OUT")"
check_contains "A51 (K43a): ...saying it has no value" "$OUT" "has no value"
check_nodir "A51 (K43a): ...nothing written" "$B/.config/git/keel-hooks"

# A52: the same with --force → the empty value is recorded, and --uninstall restores EMPTY (not unset)
mk_b force
printf '[core]\n\thooksPath =\n' > "$B/.gitconfig"
run benv "$isg" --global --force
check_status "A52: an empty hooksPath, --global --force → exit 0" 0 "$STATUS"
check_eq "A52: core.hooksPath is Keel's dir" "$B/.config/git/keel-hooks" "$(cfg_val "$B/.gitconfig" core.hooksPath)"
check_eq "A52: the record is read with rc 0 ..." 0 "$(cfg_rc "$B/.gitconfig" keel.displacedHooksPath)"
check_eq "A52: ... and an empty value" "" "$(cfg_val "$B/.gitconfig" keel.displacedHooksPath)"
run benv "$isg" --global
check_status "A52: a plain re-install keeps the empty record → exit 0" 0 "$STATUS"
check_eq "A52: ...the record still exists" 0 "$(cfg_rc "$B/.gitconfig" keel.displacedHooksPath)"
run benv "$isg" --global --uninstall
check_status "A52: --uninstall → exit 0" 0 "$STATUS"
check_eq "A52: core.hooksPath is read with rc 0 (restored, not unset)" 0 "$(cfg_rc "$B/.gitconfig" core.hooksPath)"
check_eq "A52: ... and is empty" "" "$(cfg_val "$B/.gitconfig" core.hooksPath)"
check_eq "A52: the record is dropped once restored" 1 "$(cfg_rc "$B/.gitconfig" keel.displacedHooksPath)"

# a bare `displacedHooksPath` line (no `=`) records nothing: --uninstall unsets Keel's hooksPath, never restores ""
mk_b barerec
printf '[core]\n\thooksPath = %s/.config/git/keel-hooks\n[keel]\n\tdisplacedHooksPath\n' "$B" > "$B/.gitconfig"
run benv "$isg" --global --uninstall
check_status "A52: --uninstall with a bare displacedHooksPath line → exit 0" 0 "$STATUS"
check_eq "A52: ...unsets core.hooksPath (a bare record restores nothing)" 1 "$(cfg_rc "$B/.gitconfig" core.hooksPath)"

# =============================================================================================================
# A53 / A54 — passengers.
# =============================================================================================================
check_eq "A53: the installer no longer names the deleted _expand_hookspath_tilde" 0 \
  "$(grep -c '_expand_hookspath_tilde' "$isg" || true)"
if grep -q 'git_global_expand_tilde' "$isg"; then pass "A53: ...it names git_global_expand_tilde, which exists"
else fail "A53: ...it names git_global_expand_tilde, which exists" "not named in $isg"; fi
check_eq "A53: git_global_expand_tilde has a definition" 1 \
  "$(grep -c '^git_global_expand_tilde()' "$REPO_ROOT/tools/lib/git-global-paths.sh" || true)"
check_eq "A54: getting-started.md no longer lists the two secret-guard exceptions" 0 \
  "$(grep -c 'Two exceptions are known' "$REPO_ROOT/docs/getting-started.md" || true)"

summary
