#!/usr/bin/env bash
# test_install_never_clobber.sh — the never-clobber residuals of docs/specs/685-symlink-policy.md round 2,
# slice S5c (dir #748, dir #754):
#   - B19: a home that is the Keel checkout, or lies inside it, is refused by install.sh and uninstall.sh
#     (exit 2) before anything is created;
#   - B20: one link-record predicate (tools/lib/manifest.sh manifest_link_is_keels) decides that a recorded
#     link is Keel's — its target lies inside the checkout that wrote the record — so uninstall never moves
#     an adopter's link that an older manifest recorded;
#   - B23: a `y` at "Overwrite your copy" and a `[u]` at the alias prompt back the file up first;
#   - the passengers: the Verify test hook never deletes, linked mode's docs/ advice skips a docs/ inside
#     the checkout, and three reworded lines.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"

# linked_then_relinked LABEL INSTALL TARGET — the fixture the A40 link rows share: a linked install by
# INSTALL into "$h" (its exit 0 checked under LABEL), then keel/CORE.md re-pointed at TARGET.
linked_then_relinked() {
  run "$2" --link --home "$h" --no-hooks
  check_status "$1 fixture: linked install → exit 0" 0 "$STATUS"
  rm -f "$h/keel/CORE.md"; ln -s "$3" "$h/keel/CORE.md"
}

# --- scratch checkout: a committed copy of this tree, so `git status` can tell -----------------------
ck="$SANDBOX/ck"
tracked_tree_copy "$ck" || exit 1
git -C "$ck" init -q
git -C "$ck" add -A
git -C "$ck" commit -qm base

# --- A39 / B19: a home inside the checkout is refused, by both tools, before anything is created -------
mkdir -p "$SANDBOX/a39-parent"; ln -s "$ck" "$SANDBOX/a39-parent/ck-link"
for row in "install copy|$ck/install.sh --no-hooks|$ck" \
           "install --link|$ck/install.sh --link --no-hooks|$ck" \
           "install into docs/|$ck/install.sh --no-hooks|$ck/docs" \
           "install into a home still to be made|$ck/install.sh --no-hooks|$ck/not-yet" \
           "install through a symlinked parent|$ck/install.sh --no-hooks|$SANDBOX/a39-parent/ck-link/docs" \
           "install into a home still to be made that climbs back with ..|$ck/install.sh --no-hooks|$SANDBOX/a39-nx/../ck/dd" \
           "uninstall|$ck/uninstall.sh --yes|$ck"; do
  label="${row%%|*}"; rest="${row#*|}"; cmd="${rest%%|*}"; home="${rest#*|}"
  before="$(find "$home" -mindepth 1 2>/dev/null | sort)"
  # shellcheck disable=SC2086  # $cmd is the tool plus its flags, split on purpose
  run $cmd --home "$home"
  check_status "A39 $label → exit 2" 2 "$STATUS"
  check_contains "A39 $label …B19's line names the home" "$OUT" "$home"
  check_contains "A39 $label …and the checkout" "$OUT" "lies inside the Keel checkout"
  check_eq "A39 $label …nothing created under the home" "$before" "$(find "$home" -mindepth 1 2>/dev/null | sort)"
  check_nodir "A39 $label …no run lock" "$home/.install.lock"
  check_eq "A39 $label …git status of the checkout is clean" "" "$(git -C "$ck" status --porcelain)"
done
check_nodir "A39 the home still to be made was never created" "$ck/not-yet"
check_nodir "A39 the climbing home made no directory on its way" "$SANDBOX/a39-nx"
check_nodir "A39 …nor its target inside the checkout" "$ck/dd"
# …and a home still to be made that climbs back OUT of the checkout with .. lies outside it: installed.
h="$ck/nx/../../a39-out/h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A39 a home still to be made that climbs out of the checkout with .. → exit 0" 0 "$STATUS"
check_file "A39 …landing outside the checkout" "$SANDBOX/a39-out/h/FRAMEWORK.md"
check_eq "A39 …and the checkout's git status stays clean" "" "$(git -C "$ck" status --porcelain)"
# round trip: an ordinary home outside the checkout still installs, uninstalls and installs.
h="$SANDBOX/a39-ok/h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A39 round trip: a home outside the checkout installs → exit 0" 0 "$STATUS"
run "$ck/uninstall.sh" --home "$h" --yes
check_status "A39 round trip: …uninstalls → exit 0" 0 "$STATUS"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A39 round trip: …installs again → exit 0" 0 "$STATUS"

# --- A40 / B20 / S6-4: an adopter's link an older manifest recorded is never moved by uninstall -------
h="$SANDBOX/a40/h"; dots="$SANDBOX/a40/dots"; mkdir -p "$dots"
run "$install" --home "$h" --no-hooks
check_status "A40 fixture: install → exit 0" 0 "$STATUS"
cp "$h/commands/go.md" "$dots/go.md"
rm -f "$h/commands/go.md"; ln -s "$dots/go.md" "$h/commands/go.md"
m="$h/.keel/install-manifest.claude"
awk -F'\t' -v OFS='\t' -v t="$dots/go.md" \
  '$1 ~ /^artifact=/ && $2 == "commands/go.md" { print "artifact=symlink", "commands/go.md", t; next } { print }' \
  "$m" > "$m.new" && mv "$m.new" "$m"
check_count "A40 fixture: the manifest records the adopter's link as a symlink" "$m" \
  "^artifact=symlink	commands/go.md	$dots/go.md\$" 1
before="$(cksum < "$dots/go.md")"
run "$uninstall" --home "$h" --yes
check_status "A40 uninstall → exit 0" 0 "$STATUS"
check_link "A40 …the adopter's link stays" "$h/commands/go.md"
check_eq "A40 …its target is unchanged" "$before" "$(cksum < "$dots/go.md")"
check_eq "A40 …one \"not provably Keel's — kept\" line" 1 \
  "$(grep -c "commands/go.md.*not provably Keel's — kept" <<<"$OUT" || true)"
run "$install" --home "$h" --no-hooks
check_status "A40 round trip: install again → exit 0" 0 "$STATUS"
check_link "A40 round trip: …the link is still the adopter's" "$h/commands/go.md"
run test "$h/commands/go.md" -ef "$dots/go.md"
check_status "A40 round trip: …pointing at the dotfiles copy" 0 "$STATUS"
# …and a Keel link whose text spells its recorded target another way (a symlinked parent; /tmp vs
# /private/tmp) is still Keel's: the same entry, reached through another spelling of its directory.
h="$SANDBOX/a40s/h"; ln -s "$REPO_ROOT" "$SANDBOX/a40s-alias"
linked_then_relinked "A40 respelled" "$install" "$SANDBOX/a40s-alias/CORE.md"
run "$uninstall" --home "$h" --yes
check_status "A40 respelled: uninstall → exit 0" 0 "$STATUS"
check_nolink "A40 respelled: …Keel's respelled link is removed" "$h/keel/CORE.md"
check_absent "A40 respelled: …never reported as not provably Keel's" "$OUT" "keel/CORE.md: a link not provably"
# …and on a case-insensitive file system (macOS's default), a directory name that differs only in case is
# the same directory: the checkout's own directory name upper-cased. Run only where that spelling really is
# the checkout (probed beside it, not assumed); a file name must match exactly (see the alias row below).
ck_case="${REPO_ROOT%/*}/$(printf '%s' "${REPO_ROOT##*/}" | tr '[:lower:]' '[:upper:]')"
if [ "$ck_case" = "$REPO_ROOT" ]; then
  pass "A40 case-only directory row not applicable — the checkout's directory name has no lower-case letter"
elif [ -d "$ck_case" ] && [ "$ck_case" -ef "$REPO_ROOT" ]; then
  h="$SANDBOX/a40i/h"
  linked_then_relinked "A40 case-only directory" "$install" "$ck_case/CORE.md"
  run "$uninstall" --home "$h" --yes
  check_status "A40 case-only directory: uninstall → exit 0" 0 "$STATUS"
  check_nolink "A40 case-only directory: …Keel's link, its directory spelled in another case, is removed" "$h/keel/CORE.md"
else
  pass "A40 case-only directory row not applicable — the checkout's file system tells names apart by case"
fi
# …but a differently-named sibling in the recorded target's own directory (`<checkout>/ALIAS.md -> CORE.md`)
# is not the recorded entry. Three ways in, all in the scratch checkout (the alias is removed afterwards):
ln -s CORE.md "$ck/ALIAS.md"
# (a) uninstall's own arm: the record names CORE.md, the live link names ALIAS.md — kept, with the reason.
h="$SANDBOX/a40a/h"
linked_then_relinked "A40 sibling-alias" "$ck/install.sh" "$ck/ALIAS.md"
run "$ck/uninstall.sh" --home "$h" --yes
check_status "A40 sibling-alias: uninstall → exit 0" 0 "$STATUS"
check_link "A40 sibling-alias: …the adopter's link to the alias stays" "$h/keel/CORE.md"
check_contains "A40 sibling-alias: …named as pointing where Keel did not wire it" "$OUT" \
  "keel/CORE.md: symlink no longer points where Keel would have wired it"
# (b) a re-install over the adopter's alias link (it ends at CORE.md, so a chain-following "in sync" test
# would record it) records nothing for that path, and the link stays the adopter's.
h="$SANDBOX/a40b/h"
linked_then_relinked "A40 sibling-alias (b)" "$ck/install.sh" "$ck/ALIAS.md"
run "$ck/install.sh" --link --home "$h" --no-hooks
check_status "A40 sibling-alias: a re-install over the adopter's alias link → exit 0" 0 "$STATUS"
check_count "A40 sibling-alias: …records no symlink for keel/CORE.md at all" "$h/.keel/install-manifest.claude" \
  "^artifact=symlink	keel/CORE.md	" 0
check_eq "A40 sibling-alias: …and the link is still the adopter's" "$ck/ALIAS.md" "$(readlink "$h/keel/CORE.md")"
# (c) the upgrade path: a manifest written before this slice recorded the alias link as Keel's (its "in
# sync" test followed the chain). A recorded target that is itself a symlink is not Keel's (its tracked tree
# holds none — pinned below), so neither a re-install re-points the link nor an uninstall removes it.
for step in reinstall uninstall; do
  h="$SANDBOX/a40u-$step/h"
  linked_then_relinked "A40 upgrade ($step)" "$ck/install.sh" "$ck/ALIAS.md"
  m="$h/.keel/install-manifest.claude"
  awk -F'\t' -v OFS='\t' -v t="$ck/ALIAS.md" \
    '$1 == "artifact=symlink" && $2 == "keel/CORE.md" { print $1, $2, t; next } { print }' "$m" > "$m.new" && mv "$m.new" "$m"
  check_count "A40 upgrade ($step) fixture: the old manifest records the alias as Keel's" "$m" \
    "^artifact=symlink	keel/CORE.md	$ck/ALIAS.md\$" 1
  if [ "$step" = reinstall ]; then
    run "$ck/install.sh" --link --home "$h" --no-hooks
    check_status "A40 upgrade: a re-install over that record → exit 0" 0 "$STATUS"
    check_absent "A40 upgrade: …the alias is not called Keel's own stale link" "$OUT" "CORE.md re-pointed"
    check_count "A40 upgrade: …and its old record is dropped" "$m" \
      "^artifact=symlink	keel/CORE.md	" 0
  else
    run "$ck/uninstall.sh" --home "$h" --yes
    check_status "A40 upgrade: an uninstall over that record → exit 0" 0 "$STATUS"
    check_contains "A40 upgrade: …the alias is kept as not provably Keel's" "$OUT" "keel/CORE.md: a link not provably Keel's — kept"
  fi
  check_eq "A40 upgrade ($step): …the adopter's alias link is untouched" "$ck/ALIAS.md" "$(readlink "$h/keel/CORE.md")"
done
rm -f "$ck/ALIAS.md"
# The rule above leans on one fact about the product: Keel's tracked tree holds no symlinks.
check_eq "A40 this checkout's tracked tree holds no symlinks (manifest_link_is_keels assumes no release ever shipped one)" 0 \
  "$(git -C "$REPO_ROOT" ls-files -s | grep -c '^120000' || true)"
# …while Keel's own links into an old checkout NESTED inside the new one (a worktree at
# `<main>/.claude/worktrees/x`, then an install from `<main>`) are still its own links gone stale (T3):
# re-pointed into the new checkout and kept on record. (A real `git worktree` of the scratch checkout, under
# its git-ignored .claude/, removed afterwards.)
nested="$ck/.claude/worktrees/x"
git -C "$ck" worktree add -q "$nested" || exit 1
h="$SANDBOX/a40w/h"
run "$nested/install.sh" --link --home "$h" --no-hooks
check_status "A40 nested checkout fixture: linked install from the nested checkout → exit 0" 0 "$STATUS"
run "$ck/install.sh" --link --home "$h" --no-hooks
check_status "A40 nested checkout: a linked install from the outer checkout → exit 0" 0 "$STATUS"
check_contains "A40 nested checkout: …Keel's links are re-pointed" "$OUT" "CORE.md re-pointed"
check_eq "A40 nested checkout: …into the outer checkout" "$ck/CORE.md" "$(readlink "$h/keel/CORE.md")"
check_count "A40 nested checkout: …and stay on record" "$h/.keel/install-manifest.claude" \
  "^artifact=symlink	keel/CORE.md	$ck/CORE.md\$" 1
git -C "$ck" worktree remove --force "$nested" || exit 1
check_nodir "A40 nested checkout: the worktree is gone again" "$nested"
check_eq "A40 nested checkout: the scratch checkout is clean again" "" "$(git -C "$ck" status --porcelain)"
# …and a dotfiles chain at keel/CORE.md is the adopter's at install too: --link --no-git declines it rather
# than replacing it with the trimmed copy.
h="$SANDBOX/a40n/h"; dots="$SANDBOX/a40n/dots"; mkdir -p "$dots"
ln -s "$REPO_ROOT/CORE.md" "$dots/CORE.md"
linked_then_relinked "A40 chained --no-git" "$install" "$dots/CORE.md"
run "$install" --link --no-git --home "$h" --no-hooks
check_status "A40 chained --no-git: install → exit 0" 0 "$STATUS"
check_eq "A40 chained --no-git: …the adopter's chain is left in place" "$dots/CORE.md" "$(readlink "$h/keel/CORE.md")"
check_contains "A40 chained --no-git: …declined as the adopter's own wiring" "$OUT" "your own wiring; left untouched"
check_count "A40 chained --no-git: …and no longer on record as Keel's" "$h/.keel/install-manifest.claude" \
  "^artifact=symlink	keel/CORE.md	" 0
# …and on a case-insensitive file system a case-only FILE name (`<checkout>/core.md`) is likewise not taken:
# the link is kept (the safe direction — a separate `core.md` on a case-sensitive one must never pass).
if [ -e "$REPO_ROOT/core.md" ] && [ "$REPO_ROOT/core.md" -ef "$REPO_ROOT/CORE.md" ]; then
  h="$SANDBOX/a40f/h"
  linked_then_relinked "A40 case-only file name" "$install" "$REPO_ROOT/core.md"
  run "$uninstall" --home "$h" --yes
  check_status "A40 case-only file name: uninstall → exit 0" 0 "$STATUS"
  check_link "A40 case-only file name: …the link is kept" "$h/keel/CORE.md"
  check_contains "A40 case-only file name: …named as pointing where Keel did not wire it" "$OUT" \
    "keel/CORE.md: symlink no longer points where Keel would have wired it"
else
  pass "A40 case-only file name row not applicable — the checkout's file system tells names apart by case"
fi
# …but a link that only ENDS at the recorded target through another link (a dotfiles manager's
# `<home>/keel/CORE.md -> dots/CORE.md -> <checkout>/CORE.md`) is the adopter's: kept, not moved.
h="$SANDBOX/a40c/h"; dots="$SANDBOX/a40c/dots"; mkdir -p "$dots"
ln -s "$REPO_ROOT/CORE.md" "$dots/CORE.md"
linked_then_relinked "A40 chained" "$install" "$dots/CORE.md"
run "$uninstall" --home "$h" --yes
check_status "A40 chained: uninstall → exit 0" 0 "$STATUS"
check_link "A40 chained: …the adopter's chained link stays" "$h/keel/CORE.md"
check_eq "A40 chained: …still pointing at the dotfiles link" "$dots/CORE.md" "$(readlink "$h/keel/CORE.md")"
check_contains "A40 chained: …named as pointing where Keel did not wire it" "$OUT" \
  "keel/CORE.md: symlink no longer points where Keel would have wired it — left in place"
check_absent "A40 chained: …never blamed on the recorded target's checkout" "$OUT" "keel/CORE.md: a link not provably"
# doctor and install ask the same predicate (one definition).
body="$(awk '/doctor_link_is_keels_own\(\) \{/,/^  \}/' "$REPO_ROOT/tools/doctor.sh")"
check_contains "A40 doctor_link_is_keels_own calls manifest_link_is_keels" "$body" "manifest_link_is_keels"
body="$(awk '/^keel_own_stale_link\(\) \{/,/^\}/' "$install")"
check_contains "A40 install's keel_own_stale_link calls manifest_link_is_keels" "$body" "manifest_link_is_keels"
check_eq "A40 manifest_link_is_keels is defined once, in tools/lib/manifest.sh" "tools/lib/manifest.sh" \
  "$(git -C "$REPO_ROOT" grep -lE '^[[:space:]]*manifest_link_is_keels\(\)' -- '*.sh' ':!tests' || true)"
check_contains "A40 tools/self/doctor.sh keeps it to one definition" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" "single_def_check manifest_link_is_keels"

# --- A49 / B23: a y, and a [u], back the file up first ------------------------------------------------
if command -v script >/dev/null 2>&1; then
  h="$SANDBOX/a49/h"
  run "$install" --home "$h" --no-hooks
  check_status "A49 fixture: install → exit 0" 0 "$STATUS"
  printf '\nMY EDIT\n' >> "$h/docs/delegation.md"
  edited="$(cksum < "$h/docs/delegation.md")"
  tty_run y "$install" --home "$h" --no-hooks
  check_contains "A49 y at \"Overwrite your copy\" → exit 0: the run reached its \"Done\" line" "$OUT" "Done"
  if [ "$(uname -s)" = Darwin ]; then
    check_status "A49 y at \"Overwrite your copy\" → exit 0" 0 "$STATUS"
  else
    echo "  skip  A49 y at \"Overwrite your copy\" → exit 0 (tty_run's STATUS is trustworthy on macOS only)"
  fi
  check_contains "A49 …the prompt was shown" "$OUT" "Overwrite your copy"
  baks="$(find "$h/docs" -maxdepth 1 -name 'delegation.md.*.bak')"
  check_eq "A49 …exactly one new backup" 1 "$(grep -c . <<<"$baks" || true)"
  check_eq "A49 …holding the edited bytes" "$edited" "$(cksum < "$baks" 2>/dev/null)"
  run cmp -s "$REPO_ROOT/docs/delegation.md" "$h/docs/delegation.md"
  check_status "A49 …and the doc is Keel's again" 0 "$STATUS"
  printf '\nMY COMMAND EDIT\n' >> "$h/commands/go.md"
  edited="$(cksum < "$h/commands/go.md")"
  tty_run u "$install" --home "$h" --no-hooks
  check_contains "A49 [u] at the alias prompt → exit 0: the run reached its \"Done\" line" "$OUT" "Done"
  if [ "$(uname -s)" = Darwin ]; then
    check_status "A49 [u] at the alias prompt → exit 0" 0 "$STATUS"
  else
    echo "  skip  A49 [u] at the alias prompt → exit 0 (tty_run's STATUS is trustworthy on macOS only)"
  fi
  check_contains "A49 …the alias prompt was shown" "$OUT" "[u]pdate it with Keel's version"
  baks="$(find "$h/commands" -maxdepth 1 -name 'go.md.*.bak')"
  check_eq "A49 …exactly one new backup of commands/go.md" 1 "$(grep -c . <<<"$baks" || true)"
  check_eq "A49 …holding the edited bytes" "$edited" "$(cksum < "$baks" 2>/dev/null)"
  run "$uninstall" --home "$h" --yes
  check_status "A49 round trip: uninstall → exit 0" 0 "$STATUS"
  check_eq "A49 round trip: …the backups survive the uninstall" 2 \
    "$(find "$h/docs" "$h/commands" -maxdepth 1 -name '*.bak' 2>/dev/null | grep -c . || true)"
  run "$install" --home "$h" --no-hooks
  check_status "A49 round trip: install again → exit 0" 0 "$STATUS"
  # no backup name can be claimed: the doc is left as it was, one line, and the run goes on.
  h="$SANDBOX/a49n/h"; ts=20260102T030405Z
  run "$install" --home "$h" --no-hooks
  printf '\nMY EDIT\n' >> "$h/docs/delegation.md"
  edited="$(cksum < "$h/docs/delegation.md")"
  : > "$h/docs/delegation.md.$ts.bak"
  for n in $(seq 2 99); do : > "$h/docs/delegation.md.$ts.$n.bak"; done
  tty_run y env KEEL_TEST_NOW="$ts" "$install" --home "$h" --no-hooks
  check_contains "A49 y with no free backup name → the run still exits 0: the run reached its \"Done\" line" "$OUT" "Done"
  if [ "$(uname -s)" = Darwin ]; then
    check_status "A49 y with no free backup name → the run still exits 0" 0 "$STATUS"
  else
    echo "  skip  A49 y with no free backup name → the run still exits 0 (tty_run's STATUS is trustworthy on macOS only)"
  fi
  check_eq "A49 …the doc is unchanged" "$edited" "$(cksum < "$h/docs/delegation.md")"
  check_eq "A49 …one line says it was left untouched" 1 \
    "$(grep -c 'delegation.md: backup failed — left untouched' <<<"$OUT" || true)"
else
  pass "A49 skipped — no \`script\` on this platform"
fi

# --- A50: the passengers ------------------------------------------------------------------------------
# (1) the Verify test hook reports a path missing without deleting it.
h="$SANDBOX/a50-1/h"
run env KEEL_TEST_REMOVE_BEFORE_VERIFY=INSTANCE.md "$install" --home "$h" --no-hooks
check_status "A50(1) KEEL_TEST_REMOVE_BEFORE_VERIFY=INSTANCE.md → Verify still exits 1" 1 "$STATUS"
check_contains "A50(1) …reporting it missing" "$OUT" "MISS INSTANCE.md"
check_file "A50(1) …and the file is still on disk" "$h/INSTANCE.md"
# (2) linked mode: a <home>/docs that is a link into the checkout is not "docs/ copies remain".
h="$SANDBOX/a50-2/h"; mkdir -p "$h"; ln -s "$ck/docs" "$h/docs"
run "$ck/install.sh" --link --home "$h" --no-hooks
check_status "A50(2) linked install with <home>/docs linked into the checkout → exit 0" 0 "$STATUS"
check_absent "A50(2) …prints no \"docs/ copies remain\" advice" "$OUT" "docs/ copies remain"
check_eq "A50(2) …and the checkout is untouched" "" "$(git -C "$ck" status --porcelain)"
# (3) the hook installers' "present" line counts hook entries.
if command -v jq >/dev/null 2>&1; then
  for inst in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
    h="$SANDBOX/a50-3-$inst/h"; mkdir -p "$h"
    run "$REPO_ROOT/tools/$inst" --home "$h"
    s="$h/settings.json"
    printf '%s\n' "$(sed "s|$REPO_ROOT/tools/|/elsewhere/keel/tools/|g" "$s")" > "$s"
    run "$REPO_ROOT/tools/$inst" --home "$h" --uninstall
    check_status "A50(3) $inst --uninstall with only differing entries → exit 0" 0 "$STATUS"
    check_contains "A50(3) …the line says hook entries" "$OUT" "hook entries present"
  done
fi
# (4) uninstall names the compatibility links Keel left under .keel, instead of blaming rmdir.
# (the store move, tools/state-root-migrate.sh, leaves one compatibility link per moved entry)
h="$SANDBOX/a50-4/h"; mkdir -p "$h/.keel/impact/-p-a50"; printf 'row\n' > "$h/.keel/impact/-p-a50/data"
run "$install" --home "$h" --no-hooks
check_status "A50(4) fixture: install (moves the impact entry out, leaves a link) → exit 0" 0 "$STATUS"
check_link "A50(4) fixture: .keel/impact/-p-a50 is now a compatibility link" "$h/.keel/impact/-p-a50"
run "$uninstall" --home "$h" --yes
check_status "A50(4) uninstall → exit 0" 0 "$STATUS"
check_contains "A50(4) …the kept-.keel line names Keel's compatibility links" "$OUT" "compatibility links Keel left"
# …a compatibility link spelled through the physical form of $HOME (macOS's /var → /private/var) still
# counts — the same entry, another spelling of its directory.
h="$SANDBOX/a50-4p/h"; mkdir -p "$h/.keel/impact" "$HOME/.keel/impact/-p-phys"
home_phys="$(cd -P "$HOME" && pwd -P)"
ln -s "$home_phys/.keel/impact/-p-phys" "$h/.keel/impact/-p-phys"
run "$install" --home "$h" --no-hooks
check_status "A50(4) respelled fixture: install → exit 0" 0 "$STATUS"
run "$uninstall" --home "$h" --yes
check_status "A50(4) a respelled compatibility link: uninstall → exit 0" 0 "$STATUS"
check_contains "A50(4) …still named as a compatibility link Keel left" "$OUT" "compatibility links Keel left"
# …and a link there of some other shape is not counted as one of Keel's.
h="$SANDBOX/a50-4n/h"
run "$install" --home "$h" --no-hooks
mkdir -p "$h/.keel/impact"; ln -s "$SANDBOX/elsewhere/old/impact/-p-mine" "$h/.keel/impact/-p-mine"
run "$uninstall" --home "$h" --yes
check_status "A50(4) a foreign link under .keel/impact: uninstall → exit 0" 0 "$STATUS"
check_absent "A50(4) …is not called a compatibility link Keel left" "$OUT" "compatibility links Keel left"
check_contains "A50(4) …the generic kept line is printed" "$OUT" "could not remove; it still contains (if anything)"
# (5) copy mode, a foreign CLAUDE.md after an uninstall: the WARN says it carries no rails block.
h="$SANDBOX/a50-5/h"
run "$install" --home "$h" --no-hooks
run "$uninstall" --home "$h" --yes
printf '# my own notes\n' > "$h/CLAUDE.md"
run "$install" --home "$h" --no-hooks
check_status "A50(5) copy install over a CLAUDE.md with no rails → exit 0" 0 "$STATUS"
check_contains "A50(5) …the WARN says it carries no Keel rails block" "$OUT" "carries no Keel rails block"

summary
