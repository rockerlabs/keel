#!/usr/bin/env bash
# test_safe_write.sh — dir #679 (docs/specs/685-symlink-policy.md slice 1): tools/lib/safe-write.sh is
# the one place every installer's temp-and-rename write goes through. An EDIT writes through a symlink
# and keeps the file's mode, and refuses a hard link, a loop, a non-regular target, a link into a
# missing directory and a target that resolves into the Keel checkout. A REPLACE renames a temp sibling
# onto the path, so a hard link's other name keeps its bytes. A backup is an exclusive new file and
# never overwrites an earlier one. The lib is REQUIRED by every executable consumer.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/safe-write.sh"
install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"
# shellcheck source=tools/lib/stat-portable.sh
. "$REPO_ROOT/tools/lib/stat-portable.sh"

# keeltmp_count DIR... — leftover temp siblings under DIR.
keeltmp_count() { find "$@" -name '*.keeltmp.*' 2>/dev/null | grep -c . || true; }

# --- A1: every temp-and-rename write goes through the library ----------------------------------------
# (a) the temp token lives in exactly one tracked non-test file; (b) register-project's own temp suffix
# is gone; (c) the only `mv` left in the five installer files is take()'s REMOVE in uninstall.sh.
a1a="$(git -C "$REPO_ROOT" grep -l -F '.keeltmp.' -- ':!tests' ':!docs' ':!CHANGELOG.md' || true)"
check_eq "A1(a) the .keeltmp. token is in exactly one tracked non-test file, the lib" "tools/lib/safe-write.sh" "$a1a"
a1b="$(git -C "$REPO_ROOT" grep -n -F 'regtmp' -- ':!tests' || true)"
check_eq "A1(b) register-project.sh's own temp suffix is gone" "" "$a1b"
a1c="$(git -C "$REPO_ROOT" grep -n -E '(^|[^[:alnum:]_.-])mv ' -- install.sh uninstall.sh tools/lib/hook-install.sh \
  tools/lib/ledger.sh tools/register-project.sh || true)"
a1c="$(grep -v -E ':[0-9]+:[[:space:]]*#' <<<"$a1c" || true)"
check_status "A1(c) exactly one code-line mv in the five installer files" 1 "$(grep -c . <<<"$a1c" || true)"
check_contains "A1(c) …and it is take()'s REMOVE in uninstall.sh" "$a1c" 'uninstall.sh:'
check_contains "A1(c) …moving the recorded path itself" "$a1c" 'mv "$p" "$dest"'

# --- A6: ledger_remove on a symlinked 0600 ledger ---------------------------------------------------
w="$SANDBOX/a6"; mkdir -p "$w"
printf '/h1\n/h2\n' > "$w/real"; chmod 600 "$w/real"; ln -s "$w/real" "$w/ledger"
ino="$(inode_of "$w/real")"
run bash -c ". '$lib'; . '$REPO_ROOT/tools/lib/ledger.sh'; ledger_remove '$w/ledger' /h1"
check_status "A6 ledger_remove through a link → rc 0" 0 "$STATUS"
check_link "A6 …the ledger link is kept" "$w/ledger"
check_eq "A6 …the line is gone from the real file" /h2 "$(cat "$w/real")"
check_eq "A6 …mode 0600 kept" 600 "$(stat_portable_mode "$w/real")"
check_ne "A6 …the real file was renamed over (inode changed)" "$ino" "$(inode_of "$w/real")"
run bash -c ". '$REPO_ROOT/tools/lib/ledger.sh'; ledger_remove '$w/ledger' /h2"
check_status "A6 ledger_remove with no safe-write lib loaded → rc 1 (never falls back)" 1 "$STATUS"
check_eq "A6 …and writes nothing" /h2 "$(cat "$w/real")"

# --- A7: register-project.sh with KEEL_INSTANCE a symlink to a 0600 file -----------------------------
w="$SANDBOX/a7"; mkdir -p "$w/proj"
printf '| Project | Path | CLAUDE.md | Tag |\n|---|---|---|---|\n' > "$w/real.md"; chmod 600 "$w/real.md"
ln -s "$w/real.md" "$w/INSTANCE.md"
ino="$(inode_of "$w/real.md")"
run env KEEL_INSTANCE="$w/INSTANCE.md" "$REPO_ROOT/tools/register-project.sh" "$w/proj"
check_status "A7 register-project through a link → exit 0" 0 "$STATUS"
check_link "A7 …the INSTANCE.md link is kept" "$w/INSTANCE.md"
check_contains "A7 …the row is in the real file" "$(cat "$w/real.md")" "| proj | "
check_eq "A7 …mode 0600 kept" 600 "$(stat_portable_mode "$w/real.md")"
check_ne "A7 …the real file was renamed over (inode changed)" "$ino" "$(inode_of "$w/real.md")"
printf '| Project | Path | CLAUDE.md | Tag |\n' > "$w/hl.md"; ln "$w/hl.md" "$w/hl2.md"
run env KEEL_INSTANCE="$w/hl.md" "$REPO_ROOT/tools/register-project.sh" "$w/proj"
check_status "A7 a hard-linked INSTANCE.md → exit 1" 1 "$STATUS"
check_absent "A7 …and no row was written" "$(cat "$w/hl2.md")" "| proj | "

# --- A4: replace_core_block keeps the mode (copy install, chmod 600, then --link) --------------------
h="$SANDBOX/a4"
run "$install" --home "$h" --no-hooks
check_status "A4 fixture: copy install → exit 0" 0 "$STATUS"
chmod 600 "$h/CLAUDE.md"
run "$install" --link --home "$h" --no-hooks
check_status "A4 --link migration over a 0600 CLAUDE.md → exit 0" 0 "$STATUS"
check_eq "A4 …CLAUDE.md is still 0600" 600 "$(stat_portable_mode "$h/CLAUDE.md")"
check_status "A4 …and holds the import line" 1 "$(grep -c '@.*keel/CORE\.md' "$h/CLAUDE.md" || true)"

# --- A5: the uninstall strip writes through a symlinked 0600 CLAUDE.md (the EDIT round-trip) ---------
h="$SANDBOX/a5/h"; dots="$SANDBOX/a5/dots"; mkdir -p "$dots"
run "$install" --home "$h" --no-hooks
check_status "A5 fixture: install → exit 0" 0 "$STATUS"
mv "$h/CLAUDE.md" "$dots/CLAUDE.md"; chmod 600 "$dots/CLAUDE.md"; ln -s "$dots/CLAUDE.md" "$h/CLAUDE.md"
run "$uninstall" --home "$h" --yes
check_status "A5 uninstall over a symlinked CLAUDE.md → exit 0" 0 "$STATUS"
check_link "A5 …<home>/CLAUDE.md is still a link" "$h/CLAUDE.md"
check_status "A5 …the dotfiles file no longer holds the block" 0 "$(grep -c 'KEEL-CORE-BEGIN' "$dots/CLAUDE.md" || true)"
check_eq "A5 …and is still 0600" 600 "$(stat_portable_mode "$dots/CLAUDE.md")"
check_eq "A5 …a backup of it exists" 1 "$(find "$h" -path '*/.keel-uninstall-*' -name CLAUDE.md | grep -c . || true)"
check_eq "A5 …no temp is left in either dir" 0 "$(keeltmp_count "$h" "$dots")"

# --- A10: force_backup never overwrites a backup ----------------------------------------------------
h="$SANDBOX/a10"
run "$install" --home "$h" --no-hooks
check_status "A10 fixture: install → exit 0" 0 "$STATUS"
ts=20260102T030405Z
printf 'OLD-BACKUP\n' > "$h/docs/delegation.md.$ts.bak"
printf '\nMY DRIFT\n' >> "$h/docs/delegation.md"
run env KEEL_TEST_NOW="$ts" "$install" --home "$h" --no-hooks --force
check_status "A10 --force over a drifted doc → exit 0" 0 "$STATUS"
check_eq "A10 …the pre-existing backup still holds OLD-BACKUP" OLD-BACKUP "$(cat "$h/docs/delegation.md.$ts.bak")"
check_contains "A10 …the drifted content went to the next name" "$(cat "$h/docs/delegation.md.$ts.2.bak" 2>/dev/null)" "MY DRIFT"
check_contains "A10 …and the output names it" "$OUT" "delegation.md.$ts.2.bak"

# --- scratch checkout for A11 / A24: a copy of this tree, committed, so `git status` can tell -------
# Only the tracked top-level entries are copied (uncommitted edits to them included): a run from the
# main checkout would otherwise drag its .git/, private/ and nested worktrees along.
ck="$SANDBOX/ck"; mkdir -p "$ck"
tops="$(git -C "$REPO_ROOT" ls-files | cut -d/ -f1 | sort -u)"
while IFS= read -r e; do
  [ -e "$REPO_ROOT/$e" ] && cp -R "$REPO_ROOT/$e" "$ck/"
done <<<"$tops"
git -C "$ck" init -q
git -C "$ck" add -A
git -C "$ck" commit -qm base

# --- A35: the lib derives the checkout from its own path (round 2 B15) -------------------------------
ck_phys="$(cd -P "$ck" && pwd -P)"
run bash -c ". '$ck/tools/lib/safe-write.sh'; printf '%s' \"\$KEEL_SAFE_WRITE_CHECKOUT\""
check_eq "A35 sourced from a scratch clone → the clone's physical path" "$ck_phys" "$OUT"
mkdir -p "$SANDBOX/a35"; ln -s "$ck" "$SANDBOX/a35/engine"
run bash -c ". '$SANDBOX/a35/engine/tools/lib/safe-write.sh'; printf '%s' \"\$KEEL_SAFE_WRITE_CHECKOUT\""
check_eq "A35 sourced through a link to the clone → the same physical path" "$ck_phys" "$OUT"
run env KEEL_SAFE_WRITE_CHECKOUT=/nonexistent bash -c ". '$ck/tools/lib/safe-write.sh'; printf '%s' \"\$KEEL_SAFE_WRITE_CHECKOUT\""
check_eq "A35 an inherited value is never honoured" "$ck_phys" "$OUT"
mkdir -p "$SANDBOX/a35/w"; printf 'x\n' > "$SANDBOX/a35/w/real"; ln -s real "$SANDBOX/a35/w/link"
run bash -c ". '$ck/tools/lib/safe-write.sh'; KEEL_SAFE_WRITE_CHECKOUT=; printf 'y\n' | keel_write_through '$SANDBOX/a35/w/link'"
check_status "A35/K33 an empty checkout → an EDIT through a link returns 1" 1 "$STATUS"
check_eq "A35/K33 …in one line" 1 "$(grep -c . <<<"$OUT" || true)"
check_contains "A35/K33 …naming the lib" "$OUT" "tools/lib/safe-write.sh"
check_eq "A35/K33 …and nothing was written" x "$(cat "$SANDBOX/a35/w/real")"
a35="$(git -C "$REPO_ROOT" grep -n 'KEEL_SAFE_WRITE_CHECKOUT=' -- install.sh uninstall.sh tools/install-machine-watch.sh \
  tools/install-pre-pr-gate.sh tools/install-read-trace.sh tools/register-project.sh || true)"
check_eq "A35 none of the six consumers assigns KEEL_SAFE_WRITE_CHECKOUT" "" "$a35"
check_eq "A35 the lib holds exactly one line deriving it with cd -P" 1 \
  "$(grep 'KEEL_SAFE_WRITE_CHECKOUT=' "$lib" | grep -c 'cd -P' || true)"

# --- A47 (audit S5-2): linked mode's import-line append is an EDIT, refused into the checkout -----------
h="$SANDBOX/a47s/h"; mkdir -p "$h"
ln -s "$ck/README.md" "$h/CLAUDE.md"
before="$(cksum < "$ck/README.md")"
run "$ck/install.sh" --link --home "$h" --no-hooks
check_status "A47/S5-2 linked install, CLAUDE.md linked to a tracked checkout file → exit 0" 0 "$STATUS"
check_eq "A47/S5-2 …README.md is byte-identical" "$before" "$(cksum < "$ck/README.md")"
check_eq "A47/S5-2 …git status of the checkout is clean" "" "$(git -C "$ck" status --porcelain)"
check_eq "A47/S5-2 …one line names the refusal" 1 "$(grep -c 'inside the Keel checkout' <<<"$OUT" || true)"
check_contains "A47/S5-2 …Verify's rails WARN" "$OUT" "will NOT load"

# --- A24: B1's checkout clause at uninstall ---------------------------------------------------------
h="$SANDBOX/a24/h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A24 fixture: install from the scratch checkout → exit 0" 0 "$STATUS"
mv "$h/CLAUDE.md" "$h/CLAUDE.md.mine"
ln -s "$ck/templates/CLAUDE.md" "$h/CLAUDE.md"
before="$(cksum < "$ck/templates/CLAUDE.md")"
run "$ck/uninstall.sh" --home "$h" --yes
check_status "A24 uninstall over a CLAUDE.md linked into the checkout → exit 0" 0 "$STATUS"
check_link "A24 …the link is kept" "$h/CLAUDE.md"
check_eq "A24 …the template is byte-identical" "$before" "$(cksum < "$ck/templates/CLAUDE.md")"
check_eq "A24 …git status of the checkout is clean" "" "$(git -C "$ck" status --porcelain)"
check_eq "A24 …one line names the refusal" 1 "$(grep -c 'inside the Keel checkout' <<<"$OUT" || true)"

# --- A11: the lib is REQUIRED; stat-portable stays OPTIONAL ------------------------------------------
: > "$ck/tools/lib/safe-write.sh"
h="$SANDBOX/a11/h"; mkdir -p "$h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A11 install with a 0-byte safe-write.sh → exit 1" 1 "$STATUS"
check_contains "A11 …one message naming the lib" "$OUT" "tools/lib/safe-write.sh (the safe-write lib) is missing or corrupted"
# install.sh makes .keel/ and takes its run lock (.install.lock) before any lib guard; nothing else.
check_eq "A11 …nothing created under --home but .keel/ and the run lock" "" \
  "$(find "$h" -mindepth 1 -not -path "$h/.keel" -not -path "$h/.keel/*" -not -path "$h/.install.lock" -not -path "$h/.install.lock/*")"
run "$ck/uninstall.sh" --home "$h" --dry-run
check_status "A11 uninstall --dry-run → exit 1" 1 "$STATUS"
check_contains "A11 …naming the lib" "$OUT" "tools/lib/safe-write.sh (the safe-write lib) is missing or corrupted"
mkdir -p "$SANDBOX/a11/proj"
printf '| Project | Path | CLAUDE.md | Tag |\n' > "$SANDBOX/a11/INSTANCE.md"
run env KEEL_INSTANCE="$SANDBOX/a11/INSTANCE.md" "$ck/tools/register-project.sh" "$SANDBOX/a11/proj"
check_status "A11 register-project.sh → exit 1" 1 "$STATUS"
check_contains "A11 …naming the lib" "$OUT" "tools/lib/safe-write.sh (the safe-write lib) is missing or corrupted"
check_absent "A11 …and no row was written" "$(cat "$SANDBOX/a11/INSTANCE.md")" "| proj | "
for inst in install-pre-pr-gate.sh install-read-trace.sh install-machine-watch.sh; do
  # The lib guards run before argument parsing, so one repo argument serves all three installers.
  r="$SANDBOX/a11/repo-$inst"; mkdir -p "$r"; git -C "$r" init -q
  run "$ck/tools/$inst" "$r"
  check_status "A11 $inst → exit 1" 1 "$STATUS"
  check_contains "A11 …$inst names the lib" "$OUT" "tools/lib/safe-write.sh (the safe-write lib) is missing or corrupted"
done
mv "$ck/tools/lib/hook-install.sh" "$SANDBOX/a11/hook-install.sh.away"
run "$ck/tools/install-pre-pr-gate.sh" "$SANDBOX/a11/repo-install-pre-pr-gate.sh"
check_contains "A11 both libs missing → the hook-install lib is named first" "$OUT" "tools/lib/hook-install (the settings-merge lib) is missing or corrupted"
check_absent "A11 …and the safe-write line does not fire before it" "$OUT" "safe-write lib"
mv "$SANDBOX/a11/hook-install.sh.away" "$ck/tools/lib/hook-install.sh"
git -C "$ck" checkout -q -- tools/lib/safe-write.sh

# K23: stat-portable missing → install still exits 0 (T9b), and an EDIT through a link still writes through.
rm -f "$ck/tools/lib/stat-portable.sh"
h="$SANDBOX/a11k/h"; dots="$SANDBOX/a11k/dots"; mkdir -p "$dots"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A11/K23 stat-portable.sh missing → install exit 0" 0 "$STATUS"
mv "$h/CLAUDE.md" "$dots/CLAUDE.md"; ln -s "$dots/CLAUDE.md" "$h/CLAUDE.md"
run "$ck/uninstall.sh" --home "$h" --yes
check_status "A11/K23 …uninstall exit 0" 0 "$STATUS"
check_link "A11/K23 …the EDIT kept the link" "$h/CLAUDE.md"
check_status "A11/K23 …and wrote through it" 0 "$(grep -c 'KEEL-CORE-BEGIN' "$dots/CLAUDE.md" || true)"

# --- the library itself (last, so the installer-level checks above run even before it exists) ------
check_file "tools/lib/safe-write.sh exists" "$lib"
if [ ! -f "$lib" ]; then summary; exit 1; fi
run bash -n "$lib"
check_status "safe-write.sh parses (bash -n)" 0 "$STATUS"
# shellcheck source=tools/lib/safe-write.sh
. "$lib"

# --- A2: the library's own contract -----------------------------------------------------------------
w="$SANDBOX/a2"; mkdir -p "$w/dots" "$w/proj"
# keel_write_through through a 2-hop link: both links stay links, the target gets the content, 0600 kept.
printf 'old\n' > "$w/dots/real"; chmod 600 "$w/dots/real"
ln -s ../dots/real "$w/proj/hop1"; ln -s "$w/proj/hop1" "$w/hop2"
ino="$(inode_of "$w/dots/real")"
run bash -c ". '$lib'; printf 'new\n' | keel_write_through '$w/hop2'"
check_status "A2 write_through a 2-hop link → rc 0" 0 "$STATUS"
check_link "A2 …the first hop is still a link" "$w/hop2"
check_link "A2 …the second hop is still a link" "$w/proj/hop1"
check_eq "A2 …the target holds the new content" new "$(cat "$w/dots/real")"
check_eq "A2 …the target's 0600 is kept" 600 "$(stat_portable_mode "$w/dots/real")"
check_ne "A2 …written by a rename (the inode changed)" "$ino" "$(inode_of "$w/dots/real")"
# a plain 0600 file stays 0600; a new file gets the umask.
printf 'x\n' > "$w/plain"; chmod 600 "$w/plain"
printf 'y\n' | keel_write_through "$w/plain"
check_eq "A2 a plain 0600 file stays 0600" 600 "$(stat_portable_mode "$w/plain")"
( umask 022; printf 'z\n' | keel_write_through "$w/fresh" )
check_eq "A2 a new file is created with the umask's mode" 644 "$(stat_portable_mode "$w/fresh")"
# a hard-linked target → rc 1, both names unchanged, the refusal names the hard link.
printf 'shared\n' > "$w/hl-a"; ln "$w/hl-a" "$w/hl-b"
run bash -c ". '$lib'; printf 'new\n' | keel_write_through '$w/hl-a'"
check_status "A2 a hard-linked target → rc 1" 1 "$STATUS"
check_contains "A2 …the refusal names the hard link" "$OUT" "hard link"
check_eq "A2 …the name written to keeps its bytes" shared "$(cat "$w/hl-a")"
check_eq "A2 …the other name keeps its bytes" shared "$(cat "$w/hl-b")"
run test "$w/hl-a" -ef "$w/hl-b"
check_status "A2 …the hard link is not split" 0 "$STATUS"
# a symlink to a hard-linked file is refused too (the count is read on the resolved target).
ln -s hl-a "$w/hl-link"
run bash -c ". '$lib'; printf 'new\n' | keel_write_through '$w/hl-link'"
check_status "A2 a link to a hard-linked target → rc 1" 1 "$STATUS"
# a loop → rc 1, the loop left as is.
ln -s loopb "$w/loopa"; ln -s loopa "$w/loopb"
run bash -c ". '$lib'; printf 'x\n' | keel_write_through '$w/loopa'"
check_status "A2 a symlink loop → rc 1" 1 "$STATUS"
check_contains "A2 …named as a loop" "$OUT" "symlink loop"
check_link "A2 …the loop is not replaced by a file" "$w/loopa"
# a directory, and a link to one → rc 1, nothing nested inside.
mkdir -p "$w/adir"; ln -s adir "$w/dirlink"
for t in adir dirlink; do
  run bash -c ". '$lib'; printf 'x\n' | keel_write_through '$w/$t'"
  check_status "A2 $t (a directory) → rc 1" 1 "$STATUS"
  check_contains "A2 …$t refused as not a regular file" "$OUT" "is not a regular file"
done
check_eq "A2 …and nothing was nested inside the directory" 0 "$(find "$w/adir" -type f | grep -c . || true)"
# a link dangling into an existing directory → the file is created there; into a missing one → rc 1.
mkdir -p "$w/later"; ln -s later/made "$w/dangle-ok"
printf 'made\n' | keel_write_through "$w/dangle-ok"
check_link "A2 a link dangling into an existing dir stays a link" "$w/dangle-ok"
check_eq "A2 …and the file is created at its target" made "$(cat "$w/later/made" 2>/dev/null)"
ln -s "$w/no-such-dir/f" "$w/dangle-bad"
run bash -c ". '$lib'; printf 'x\n' | keel_write_through '$w/dangle-bad'"
check_status "A2 a link dangling into a missing dir → rc 1" 1 "$STATUS"
check_link "A2 …the link is left as it was" "$w/dangle-bad"
check_eq "A2 no *.keeltmp.* is left after any refusal" 0 "$(keeltmp_count "$w")"
# B1's checkout clause: a link from outside into the checkout is refused; a path inside it is not.
mkdir -p "$w/ck/templates" "$w/ck/.keel" "$w/h"
printf 'tracked\n' > "$w/ck/templates/T.md"; ln -s "$w/ck/templates/T.md" "$w/h/T.md"
run bash -c ". '$lib'; KEEL_SAFE_WRITE_CHECKOUT='$w/ck'; printf 'x\n' | keel_write_through '$w/h/T.md'"
check_status "A2 a link resolving into the checkout → rc 1" 1 "$STATUS"
check_contains "A2 …named as inside the Keel checkout" "$OUT" "inside the Keel checkout"
check_eq "A2 …the checkout file is untouched" tracked "$(cat "$w/ck/templates/T.md")"
printf '/h1\n' > "$w/ck/.keel/ledger"
run bash -c ". '$lib'; KEEL_SAFE_WRITE_CHECKOUT='$w/ck'; printf '/h2\n' | keel_write_through '$w/ck/.keel/ledger'"
check_status "A2 a path given inside the checkout is written (its own ledger)" 0 "$STATUS"
mkdir -p "$w/ck-dots"; printf 'sib\n' > "$w/ck-dots/S.md"; ln -s "$w/ck-dots/S.md" "$w/h/S.md"
run bash -c ". '$lib'; KEEL_SAFE_WRITE_CHECKOUT='$w/ck'; printf 'x\n' | keel_write_through '$w/h/S.md'"
check_status "A2 a sibling dir sharing the checkout's name prefix is not inside it" 0 "$STATUS"
# the command form: CMD's stdout is the content, and a CMD that fails leaves the file untouched (a pipe
# would hide the producer's exit and rename its partial output onto the file).
printf 'whole\nfile\n' > "$w/cmd"; chmod 600 "$w/cmd"
run bash -c ". '$lib'; keel_write_through '$w/cmd' sh -c 'echo partial; exit 3'"
check_status "A2 write_through CMD: a failing CMD → rc 1" 1 "$STATUS"
check_contains "A2 …named as content that could not be produced" "$OUT" "could not be produced"
check_eq "A2 …the file is untouched" "$(printf 'whole\nfile')" "$(cat "$w/cmd")"
check_eq "A2 …and no temp is left" 0 "$(keeltmp_count "$w")"
keel_write_through "$w/cmd" sed 's/whole/edited/' "$w/cmd" </dev/null
# a read-only target is reported as read-only — never blamed on CMD — in ONE line (no raw shell error),
# and a CMD that calls `exit` stays a failed CMD instead of ending the caller. Root writes through 0444,
# so the read-only rows are guarded (CLAUDE.md "Linux-leg traps" 2).
printf 'ro\n' > "$w/ro"; chmod 444 "$w/ro"
run bash -c ". '$lib'; keel_write_through '$w/ro' sed s/ro/rw/ '$w/ro'"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_status "A2 write_through CMD on a read-only target → rc 1" 1 "$STATUS"
  check_contains "A2 …reported as read-only" "$OUT" "read-only"
  check_absent "A2 …never blamed on CMD" "$OUT" "could not be produced"
  check_eq "A2 …in exactly one stderr line" 1 "$(grep -c . <<<"$OUT" || true)"
fi
check_eq "A2 …no temp is left beside it" 0 "$(keeltmp_count "$w")"
run bash -c "set -u; . '$lib'; exits() { exit 7; }; keel_write_through '$w/cmd' exits; echo caller-continued rc=\$?"
check_contains "A2 write_through CMD: an exit inside CMD does not end the caller" "$OUT" "caller-continued rc=1"
check_eq "A2 …and the file is untouched" "$(printf 'edited\nfile')" "$(cat "$w/cmd")"
check_eq "A2 write_through CMD: a succeeding CMD's output lands" "$(printf 'edited\nfile')" "$(cat "$w/cmd")"
check_eq "A2 …mode 0600 kept" 600 "$(stat_portable_mode "$w/cmd")"
# keel_write_replace over a hard link: rc 0, the other name keeps its bytes.
printf 'orig\n' > "$w/r-a"; ln "$w/r-a" "$w/r-b"
run bash -c ". '$lib'; printf 'placed\n' | keel_write_replace '$w/r-a'"
check_status "A2 write_replace over a hard link → rc 0" 0 "$STATUS"
check_eq "A2 …the path holds the new content" placed "$(cat "$w/r-a")"
check_eq "A2 …the other name keeps its bytes" orig "$(cat "$w/r-b")"
# keel_link_replace: a link at the path, by a rename.
printf 'src\n' > "$w/src"; printf 'was\n' > "$w/lnk"
keel_link_replace "$w/src" "$w/lnk"
check_link "A2 link_replace leaves a link at the path" "$w/lnk"
run test "$w/lnk" -ef "$w/src"
check_status "A2 …pointing at the target" 0 "$STATUS"
# keel_backup: two calls in one second → .bak and .2.bak, both 0600, neither overwritten.
printf 'first\n' > "$w/b"; chmod 644 "$w/b"
KEEL_TEST_NOW=20260101T000000Z keel_backup "$w/b"; b1="$KEEL_BACKUP"
printf 'second\n' > "$w/b"
KEEL_TEST_NOW=20260101T000000Z keel_backup "$w/b"; b2="$KEEL_BACKUP"
check_eq "A2 backup: the first is <path>.<ts>.bak" "$w/b.20260101T000000Z.bak" "$b1"
check_eq "A2 backup: the second in the same second is <path>.<ts>.2.bak" "$w/b.20260101T000000Z.2.bak" "$b2"
check_eq "A2 backup: …the first still holds the first content" first "$(cat "$b1")"
check_eq "A2 backup: …the second holds the second" second "$(cat "$b2")"
check_eq "A2 backup: the first is 0600" 600 "$(stat_portable_mode "$b1")"
check_eq "A2 backup: the second is 0600" 600 "$(stat_portable_mode "$b2")"
# a dangling link pre-placed at the .bak name → claimed as .2.bak, the link's target never written.
printf 'c\n' > "$w/d"; ln -s "$w/d-target" "$w/d.20260101T000000Z.bak"
KEEL_TEST_NOW=20260101T000000Z keel_backup "$w/d"
check_eq "A2 backup: a dangling link at the name → .2.bak" "$w/d.20260101T000000Z.2.bak" "$KEEL_BACKUP"
check_nofile "A2 backup: …the dangling link's target was never written" "$w/d-target"
# a link to /dev/null pre-placed at the .bak name → also .2.bak (noclobber is not exclusive there, K24).
printf 'n\n' > "$w/n"; ln -s /dev/null "$w/n.20260101T000000Z.bak"
KEEL_TEST_NOW=20260101T000000Z keel_backup "$w/n"
check_eq "A2 backup: a link to /dev/null at the name → .2.bak" "$w/n.20260101T000000Z.2.bak" "$KEEL_BACKUP"
check_eq "A2 backup: …holding the content" n "$(cat "$KEEL_BACKUP")"
# a link to a FIFO nobody reads, pre-placed at the .bak name, is skipped before any claim (opening it
# for the claim would block forever) → .2.bak. Backgrounded with a bounded wait, so a regression fails
# instead of hanging the suite.
if command -v mkfifo >/dev/null 2>&1 && mkfifo "$w/nobody-reads" 2>/dev/null; then
  printf 'q\n' > "$w/q"; ln -s "$w/nobody-reads" "$w/q.20260101T000000Z.bak"
  ( KEEL_TEST_NOW=20260101T000000Z keel_backup "$w/q" && printf '%s' "$KEEL_BACKUP" > "$w/q.result" ) &
  qpid=$!; qwait=0
  while kill -0 "$qpid" 2>/dev/null && [ "$qwait" -lt 10 ]; do sleep 1; qwait=$((qwait + 1)); done
  if kill -0 "$qpid" 2>/dev/null; then
    # A READER releases the claim blocked in open() (a second writer would block too); the claim then
    # runs to its end, so no process is left orphaned in open() for the rest of the suite.
    cat "$w/nobody-reads" > /dev/null 2>&1 &
    qrel=$!
    # A48: the release itself is bounded too — a pure-bash watchdog (no perl on the alpine image, no
    # timeout on stock macOS) kills the row's pid if the reader did not free it; cancelled on completion.
    # The trap takes the watchdog's own sleep down with it, so cancelling it leaves no stray process.
    ( trap 'kill "${s:-}" 2>/dev/null; exit 0' TERM; sleep 20 & s=$!; wait "$s"; kill "$qpid" ) > /dev/null 2>&1 &
    qdog=$!
    wait "$qpid" 2>/dev/null || true
    kill "$qdog" 2>/dev/null || true; wait "$qdog" 2>/dev/null || true
    kill "$qrel" 2>/dev/null || true; wait "$qrel" 2>/dev/null || true
    fail "A2 backup: a link to an unread FIFO at the name does not hang" "still blocked after ${qwait}s"
  else
    wait "$qpid" 2>/dev/null || true
    check_eq "A2 backup: a link to an unread FIFO at the name → .2.bak, no hang" \
      "$w/q.20260101T000000Z.2.bak" "$(cat "$w/q.result" 2>/dev/null)"
  fi
  rm -f "$w/nobody-reads" "$w/q.20260101T000000Z.bak"
fi
# a non-regular path (a FIFO would block the copy forever) is refused before any name is claimed.
if command -v mkfifo >/dev/null 2>&1 && mkfifo "$w/fifo" 2>/dev/null; then
  run bash -c ". '$lib'; keel_backup '$w/fifo'"
  check_status "A2 backup: a FIFO → rc 1, no hang" 1 "$STATUS"
  check_eq "A2 backup: …and no name was claimed" 0 "$(find "$w" -maxdepth 1 -name 'fifo.*' | grep -c . || true)"
  rm -f "$w/fifo"
fi
run bash -c ". '$lib'; keel_backup '$w/no-such'"
check_status "A2 backup: a failed copy → rc 1" 1 "$STATUS"
check_eq "A2 backup: …and leaves no claimed .bak behind" 0 "$(find "$w" -maxdepth 1 -name 'no-such.*' | grep -c . || true)"

# --- A29 (lib): keel_write_state splits a hard link and refuses the rest as an EDIT does -------------
w="$SANDBOX/a29"; mkdir -p "$w/dots" "$w/ck/templates" "$w/h"
printf 'old\n' > "$w/s-a"; chmod 600 "$w/s-a"; ln "$w/s-a" "$w/s-b"
run bash -c ". '$lib'; printf 'new\n' | keel_write_state '$w/s-a'"
check_status "A29 write_state over a hard link → rc 0" 0 "$STATUS"
check_eq "A29 …the path holds the new content" new "$(cat "$w/s-a")"
check_eq "A29 …the other name keeps the old bytes" old "$(cat "$w/s-b")"
check_eq "A29 …the mode is kept" 600 "$(stat_portable_mode "$w/s-a")"
printf 'old\n' > "$w/dots/real"; ln "$w/dots/real" "$w/dots/other"; ln -s "$w/dots/real" "$w/s-link"
run bash -c ". '$lib'; keel_write_state '$w/s-link' printf 'new\n'"
check_status "A29 write_state through a link to a hard-linked file → rc 0" 0 "$STATUS"
check_link "A29 …the link is kept" "$w/s-link"
check_eq "A29 …its target holds the new content" new "$(cat "$w/dots/real")"
check_eq "A29 …the target's other name keeps the old bytes" old "$(cat "$w/dots/other")"
ln -s s-loopb "$w/s-loopa"; ln -s s-loopa "$w/s-loopb"
run bash -c ". '$lib'; printf 'x\n' | keel_write_state '$w/s-loopa'"
check_status "A29 write_state: a symlink loop → rc 1" 1 "$STATUS"
ln -s "$w/no-such-dir/f" "$w/s-dangle"
run bash -c ". '$lib'; printf 'x\n' | keel_write_state '$w/s-dangle'"
check_status "A29 write_state: a link into a missing directory → rc 1" 1 "$STATUS"
mkdir -p "$w/s-dir"
run bash -c ". '$lib'; printf 'x\n' | keel_write_state '$w/s-dir'"
check_status "A29 write_state: a directory → rc 1" 1 "$STATUS"
printf 'tracked\n' > "$w/ck/templates/T.md"; ln -s "$w/ck/templates/T.md" "$w/h/T.md"
run bash -c ". '$lib'; KEEL_SAFE_WRITE_CHECKOUT='$w/ck'; printf 'x\n' | keel_write_state '$w/h/T.md'"
check_status "A29 write_state: a link resolving into the checkout → rc 1" 1 "$STATUS"
check_eq "A29 …the checkout file is untouched" tracked "$(cat "$w/ck/templates/T.md")"
check_eq "A29 no *.keeltmp.* is left after any write_state refusal" 0 "$(keeltmp_count "$w")"

# --- A37 (lib): one call backs up, then writes; a failed write keeps no backup -----------------------
w="$SANDBOX/a37"; mkdir -p "$w"
printf 'keep\n' > "$w/F"
run bash -c ". '$lib'; keel_backup_write_through '$w/F' false; echo \"rc=\$? backup=[\$KEEL_BACKUP]\""
check_contains "A37 backup_write_through F false → rc 1, \$KEEL_BACKUP empty" "$OUT" "rc=1 backup=[]"
check_eq "A37 …no F.*.bak is left" 0 "$(find "$w" -maxdepth 1 -name 'F.*.bak' | grep -c . || true)"
check_eq "A37 …F is unchanged" keep "$(cat "$w/F")"
printf 'shared\n' > "$w/H"; ln "$w/H" "$w/H2"
run bash -c ". '$lib'; printf 'new\n' | keel_backup_write_through '$w/H'"
check_status "A37 backup_write_through over a hard link → rc 1 (refused first)" 1 "$STATUS"
check_eq "A37 …no backup was claimed" 0 "$(find "$w" -maxdepth 1 -name 'H.*.bak' | grep -c . || true)"
run bash -c ". '$lib'; KEEL_TEST_NOW=20260101T000000Z keel_backup_write_through '$w/F' printf 'new\n'; echo \"rc=\$? backup=[\$KEEL_BACKUP]\""
check_contains "A37 backup_write_through success → rc 0, \$KEEL_BACKUP names the backup" "$OUT" "rc=0 backup=[$w/F.20260101T000000Z.bak]"
check_eq "A37 …F holds the new content" new "$(cat "$w/F")"
check_eq "A37 …the backup holds the old" keep "$(cat "$w/F.20260101T000000Z.bak" 2>/dev/null)"

# --- A38: the temp name is claimed, never followed (round 2 B16) ------------------------------------
w="$SANDBOX/a38"; mkdir -p "$w/elsewhere" "$w/pdir"
printf 'src\n' > "$w/SRC"
for wr in through replace state; do
  printf 'old\n' > "$w/T-$wr"; printf 'planted\n' > "$w/elsewhere/P-$wr"
  run bash -c ". '$lib'; ln -s '$w/elsewhere/P-$wr' \"$w/T-$wr.keeltmp.\$\$\"; printf 'new\n' | keel_write_$wr '$w/T-$wr'"
  check_status "A38 write_$wr with a link planted at the temp name → rc 0" 0 "$STATUS"
  check_nolink "A38 …T is not turned into a link" "$w/T-$wr"
  check_eq "A38 …T holds the new content" new "$(cat "$w/T-$wr")"
  check_eq "A38 …the planted link's target is unchanged" planted "$(cat "$w/elsewhere/P-$wr")"
done
run bash -c ". '$lib'; ln -s '$w/pdir' \"$w/P.keeltmp.\$\$\"; keel_link_replace '$w/SRC' '$w/P'"
check_status "A38 link_replace with a link to a directory planted at the temp name → rc 0" 0 "$STATUS"
check_link "A38 …P is a link" "$w/P"
run test "$w/P" -ef "$w/SRC"
check_status "A38 …to SRC" 0 "$STATUS"
check_eq "A38 …and the planted directory holds no new entry" 0 "$(find "$w/pdir" -mindepth 1 | grep -c . || true)"
# K35a: a real directory at the temp name — rm -f cannot remove it; each writer refuses in one line.
for wr in through replace state link; do
  case "$wr" in
    link) call="keel_link_replace '$w/SRC' '$w/K-$wr'" ;;
    *)    call="printf 'x\n' | keel_write_$wr '$w/K-$wr'" ;;
  esac
  run bash -c ". '$lib'; d=\"$w/K-$wr.keeltmp.\$\$\"; mkdir \"\$d\"; $call; rc=\$?; echo \"rc=\$rc entries=\$(ls -A \"\$d\" | wc -l | tr -d ' ')\""
  check_contains "A38/K35a $wr: a directory at the temp name → rc 1, the directory stays empty" "$OUT" "rc=1 entries=0"
  check_eq "A38/K35a …$wr refuses in one line" 1 "$(grep -c '^safe-write:' <<<"$OUT" || true)"
done
# The race half: an `rm` that re-plants the link right after the lib removes it. Each writer must refuse
# or claim fresh — never follow.
for wr in through replace state link; do
  printf 'old\n' > "$w/R-$wr"; printf 'planted\n' > "$w/elsewhere/RP-$wr"; mkdir -p "$w/rdir-$wr"
  case "$wr" in
    link) plant="$w/rdir-$wr"; call="keel_link_replace '$w/SRC' '$w/R-$wr'" ;;
    *)    plant="$w/elsewhere/RP-$wr"; call="printf 'new\n' | keel_write_$wr '$w/R-$wr'" ;;
  esac
  run bash -c ". '$lib'; tmp=\"$w/R-$wr.keeltmp.\$\$\"
    rm() { local s=0; command rm \"\$@\" || s=\$?; ln -s '$plant' \"\$tmp\" 2>/dev/null; return \"\$s\"; }
    ln -s '$plant' \"\$tmp\"; $call"
  check_eq "A38 race $wr: the planted target is unchanged" planted "$(cat "$w/elsewhere/RP-$wr")"
  check_eq "A38 race $wr: …the planted directory holds no new entry" 0 "$(find "$w/rdir-$wr" -mindepth 1 | grep -c . || true)"
  if [ "$wr" = link ]; then
    run test "$w/R-$wr" -ef "$w/rdir-$wr"
    check_status "A38 race link: …the path does not point at the planted directory" 1 "$STATUS"
  else
    check_nolink "A38 race $wr: …the path is not turned into a link" "$w/R-$wr"
  fi
done
# …a link to /dev/null re-planted: noclobber opens it, so only the claim's [ -f ] && [ ! -L ] check stops it.
for wr in through replace state; do
  printf 'old\n' > "$w/N-$wr"
  run bash -c ". '$lib'; tmp=\"$w/N-$wr.keeltmp.\$\$\"
    rm() { local s=0; command rm \"\$@\" || s=\$?; ln -s /dev/null \"\$tmp\" 2>/dev/null; return \"\$s\"; }
    printf 'new\n' | keel_write_$wr '$w/N-$wr'"
  check_nolink "A38 race $wr, a link to /dev/null re-planted: the path is not turned into a link" "$w/N-$wr"
done
# keel_link_replace's two later checks, each staged by an `ln` that races the lib: a link to a directory
# planted just BEFORE the lib's ln (only `ln -n` keeps the link out of that directory), and the lib's own
# link swapped for one to the directory just AFTER it (only the readlink check catches the swap).
for when in before after; do
  mkdir -p "$w/ldir-$when"; printf 'old\n' > "$w/L-$when"
  case "$when" in
    before) lnfn="ln() { command ln -s '$w/ldir-$when' \"\$tmp\"; command ln \"\$@\"; }" ;;
    after)  lnfn="ln() { command ln \"\$@\" || return; command rm -f \"\$tmp\"; command ln -s '$w/ldir-$when' \"\$tmp\"; }" ;;
  esac
  run bash -c ". '$lib'; tmp=\"$w/L-$when.keeltmp.\$\$\"; $lnfn; keel_link_replace '$w/SRC' '$w/L-$when'"
  check_eq "A38 race link, a link planted $when the lib's ln: the planted directory holds no new entry" 0 \
    "$(find "$w/ldir-$when" -mindepth 1 | grep -c . || true)"
  run test "$w/L-$when" -ef "$w/ldir-$when"
  check_status "A38 race link, $when: …the path does not point at the planted directory" 1 "$STATUS"
done

# --- review round 1: the temp is never more open than the target, and a caller's set -C is no refusal --
w="$SANDBOX/r1"; mkdir -p "$w"
printf 'secret\n' > "$w/p"; chmod 600 "$w/p"
run bash -c "umask 022; . '$lib'
  cp() { ls -l \"\$3\" | cut -c1-10 > '$w/seen'; command cp \"\$@\"; }
  printf 'new\n' | keel_write_through '$w/p'"
check_status "r1 write_through over a 0600 file under umask 022 → rc 0" 0 "$STATUS"
check_eq "r1 …the temp is 0600 while cp -p fills it" "-rw-------" "$(cat "$w/seen" 2>/dev/null)"
check_eq "r1 …and the file stays 0600" 600 "$(stat_portable_mode "$w/p")"
# the mode now reaches the result only through cp -p, so a target MORE open than the claim must keep it.
for m in 644 755; do
  printf 'x\n' > "$w/m$m"; chmod "$m" "$w/m$m"
  ( umask 022; printf 'y\n' | keel_write_through "$w/m$m" )
  check_eq "r2 a $m target keeps $m (the 077 claim does not narrow it)" "$m" "$(stat_portable_mode "$w/m$m")"
  ( umask 022; printf 'z\n' | keel_write_state "$w/m$m" )
  check_eq "r2 …and through a STATE write" "$m" "$(stat_portable_mode "$w/m$m")"
done
printf 'old\n' > "$w/c"
run bash -c "set -C; . '$lib'; printf 'n\n' | keel_write_replace '$w/g' && printf 'n\n' | keel_write_through '$w/fresh' \
  && keel_backup_write_through '$w/c' printf 'new\n' && keel_write_state '$w/c' printf 'state\n'"
check_status "r1 a caller under set -C: replace, a new-file EDIT, a backup-write and a STATE write → rc 0" 0 "$STATUS"
check_eq "r1 …the backup holds the old content" 1 "$(grep -lx old "$w"/c.*.bak 2>/dev/null | grep -c . || true)"

# --- A44: the lib's refusal carries the cause and CMD's status (round 2 B17) -------------------------
w="$SANDBOX/a44"; mkdir -p "$w"
printf 'whole\n' > "$w/c"
run bash -c ". '$lib'; keel_write_through '$w/c' sh -c 'echo partial; exit 3'"
check_status "A44 a CMD exiting 3 → rc 1" 1 "$STATUS"
check_contains "A44 …the lib line names CMD's status" "$OUT" "exited 3"
check_eq "A44/A48 …no *.keeltmp.* is left" 0 "$(keeltmp_count "$w")"
mkdir -p "$w/rodir"; chmod 555 "$w/rodir"
run bash -c ". '$lib'; printf 'x\n' | keel_write_through '$w/rodir/f'"
# Root writes into a 0555 directory (CLAUDE.md "Linux-leg traps" 2), so on the alpine leg even the status
# differs: the whole row is guarded.
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_status "A44 an unwritable directory → rc 1" 1 "$STATUS"
  check_eq "A44 …the lib line carries the cause: '(cause: ' then the system's message" 1 \
    "$(grep -c '(cause: [^)]' <<<"$OUT" || true)"
  check_eq "A44 …in one line" 1 "$(grep -c . <<<"$OUT" || true)"
fi
chmod 755 "$w/rodir"

summary
