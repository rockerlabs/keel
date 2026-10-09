#!/usr/bin/env bash
# test_install_symlink_policy.sh — dir #685 (docs/specs/685-symlink-policy.md slice 3, B3 + B5 + B10 + B11):
# install.sh never puts Keel's file in place of a link Keel did not make — not with --force, not on a
# terminal "yes", not through the alias prompt (A12, A13, A14, A26) — while Keel's own stale link is still
# re-pointed (A15), an adopter's in-sync link is never recorded as Keel's (A25), a SEED leaves a dangling
# link alone (A18), and the rule is stated once for adopters (A23). A16 is the guard that a hard-linked
# regular file under --force is still backed up and replaced.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

# mk_ck NAME — a scratch Keel checkout under $SANDBOX (a copy of this tree, its own git repo); prints its path.
mk_ck() {
  local ck="$SANDBOX/$1"
  cp -R "$REPO_ROOT" "$ck" && rm -rf "$ck/.git"
  git -C "$ck" init -q
  git -C "$ck" add -A
  git -C "$ck" -c user.name=Alice -c user.email=alice@example.com commit -q -m fixture
  printf '%s' "$ck"
}
sum_of() { cksum < "$1"; }
bak_count() { find "$1" -name '*.bak' 2>/dev/null | wc -l | tr -d ' '; }
manifest_of() { printf '%s/.keel/install-manifest.claude' "$1"; }
# symlink_records H REL — how many `artifact=symlink` records the manifest holds for REL.
symlink_records() { grep -c -F "$(printf 'artifact=symlink\t%s\t' "$2")" "$(manifest_of "$1")" || true; }
# line_of OUT NEEDLE — the first line of OUT containing NEEDLE (one line, so a pin cannot span two).
line_of() { local o="$1"; grep -F -m1 -- "$2" <<<"$o" || true; }
# One checkout shared by every scenario that only READS it as an install source; A15 moves its checkout and
# A25 drifts its source, so those build their own.
ck_shared="$(mk_ck shared-ck)"
have_script=1; command -v script >/dev/null 2>&1 || have_script=0

# --- A12: T4 under --force — a link Keel did not make over a whole-file doc is declined -------------------
ck="$ck_shared"; h="$SANDBOX/a12-h"; dots="$SANDBOX/a12-dots"; mkdir -p "$h" "$dots"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A12 fixture install exits 0" 0 "$STATUS"
mv "$h/docs/delegation.md" "$dots/delegation.md"
printf '\n# MY DOTFILES EDIT\n' >> "$dots/delegation.md"
ln -s "$dots/delegation.md" "$h/docs/delegation.md"
before="$(sum_of "$dots/delegation.md")"
run "$ck/install.sh" --home "$h" --no-hooks --force
check_status "A12 --force over a link Keel did not make: exit 0 (a decline is not an error)" 0 "$STATUS"
check_link "A12 the adopter's link is still a link" "$h/docs/delegation.md"
check_eq "A12 …still pointing at the dotfiles file" "$dots/delegation.md" "$(readlink "$h/docs/delegation.md")"
check_eq "A12 the dotfiles file is byte-identical (a write THROUGH the link would change it)" "$before" "$(sum_of "$dots/delegation.md")"
check_eq "A12 …and still ends with the adopter's edit" "# MY DOTFILES EDIT" "$(tail -n 1 "$dots/delegation.md")"
check_eq "A12 no .bak was taken anywhere under the home" 0 "$(bak_count "$h")"
check_contains "A12 the output names the link's target" "$OUT" "$dots/delegation.md"
check_contains "A12 …and says what to do" "$OUT" "remove the link and re-run"

# --- A13: T4 on a terminal — no overwrite prompt is offered for a link Keel did not make -----------------
if [ "$have_script" = 1 ]; then
  ck="$ck_shared"; h="$SANDBOX/a13-h"; dots="$SANDBOX/a13-dots"; mkdir -p "$h" "$dots"
  run "$ck/install.sh" --home "$h" --no-hooks
  mv "$h/docs/delegation.md" "$dots/delegation.md"
  printf '\n# MY DOTFILES EDIT\n' >> "$dots/delegation.md"
  ln -s "$dots/delegation.md" "$h/docs/delegation.md"
  before="$(sum_of "$dots/delegation.md")"
  tty_run y "$ck/install.sh" --home "$h" --no-hooks
  check_link "A13 the link is kept after a terminal 'y'" "$h/docs/delegation.md"
  check_eq "A13 the dotfiles file is byte-identical" "$before" "$(sum_of "$dots/delegation.md")"
  check_eq "A13 no .bak was taken" 0 "$(bak_count "$h")"
  check_absent "A13 no overwrite prompt was offered for the link" "$OUT" "Overwrite your copy"
  check_absent "A13 …and delegation.md was not 'updated'" "$OUT" "delegation.md updated"
else
  echo "  skip  A13 (script absent)"
fi

# --- A14: bin/keel T4 — an adopter's live link to their own program ---------------------------------------
ck="$ck_shared"; h="$SANDBOX/a14-h"; mine="$SANDBOX/a14-mine"; mkdir -p "$h/bin" "$mine"
printf '#!/bin/sh\necho mine\n' > "$mine/keel"; chmod +x "$mine/keel"
ln -s "$mine/keel" "$h/bin/keel"
before="$(sum_of "$mine/keel")"
for mode in plain force; do
  flag=""; [ "$mode" = force ] && flag="--force"
  run "$ck/install.sh" --home "$h" --no-hooks $flag
  out14="$OUT"
  check_status "A14 $mode: exit 0" 0 "$STATUS"
  run test "$h/bin/keel" -ef "$mine/keel"
  check_status "A14 $mode: the adopter's bin/keel link still resolves to their program" 0 "$STATUS"
  check_eq "A14 $mode: their program is byte-identical" "$before" "$(sum_of "$mine/keel")"
  check_contains "A14 $mode: the output names the link's target" "$out14" "$mine/keel"
  check_contains "A14 $mode: …and the remedy" "$out14" "remove the link and re-run"
  check_eq "A14 $mode: no backup" 0 "$(bak_count "$h/bin")"
done
check_eq "A14 bin/keel is not recorded as Keel's" 0 "$(symlink_records "$h" bin/keel)"
check_contains "A14 Verify says it is a link Keel did not make (no --force remedy)" "$out14" "it is a link Keel did not make"
# …and an older manifest's record of that link is dropped by the decline, so uninstall leaves it too.
printf 'artifact=symlink\tbin/keel\t%s\n' "$mine/keel" >> "$(manifest_of "$h")"
run "$ck/install.sh" --home "$h" --no-hooks
check_eq "A14 a legacy record of the adopter's bin/keel is dropped" 0 "$(symlink_records "$h" bin/keel)"

# --- A15: T3 — Keel's own stale links follow a moved checkout ---------------------------------------------
ckA="$(mk_ck a15-ckA)"; h="$SANDBOX/a15-h"; mkdir -p "$h"
run "$ckA/install.sh" --home "$h" --no-hooks --link
check_status "A15 fixture linked install exits 0" 0 "$STATUS"
ckB="$SANDBOX/a15-ckB"; mv "$ckA" "$ckB"
run "$ckB/install.sh" --home "$h" --no-hooks --link
check_status "A15 re-run from the moved checkout exits 0" 0 "$STATUS"
check_eq "A15 commands/wrap.md now points into the new checkout" "$ckB/commands/wrap.md" "$(readlink "$h/commands/wrap.md")"
check_eq "A15 bin/keel now points into the new checkout" "$ckB/keel" "$(readlink "$h/bin/keel")"
check_eq "A15 keel/docs/delegation.md now points into the new checkout" "$ckB/docs/delegation.md" "$(readlink "$h/keel/docs/delegation.md")"
check_absent "A15 no decline line for a link Keel made" "$OUT" "remove the link and re-run"
check_absent "A15 …and no 'your own command' line" "$OUT" "is your own command"

# --- A16: T5 hard link under --force — backed up, renamed over, the other name keeps its bytes ------------
ck="$ck_shared"; h="$SANDBOX/a16-h"; dots="$SANDBOX/a16-dots"; mkdir -p "$h" "$dots"
run "$ck/install.sh" --home "$h" --no-hooks
mv "$h/docs/delegation.md" "$dots/delegation.md"
ln "$dots/delegation.md" "$h/docs/delegation.md"
printf '\n# MY HARD-LINKED EDIT\n' >> "$dots/delegation.md"
before="$(sum_of "$dots/delegation.md")"
run "$ck/install.sh" --home "$h" --no-hooks --force
check_status "A16 --force over a hard-linked foreign doc exits 0" 0 "$STATUS"
run test "$h/docs/delegation.md" -ef "$dots/delegation.md"
check_status "A16 the home name is no longer the same inode" 1 "$STATUS"
check_eq "A16 the other name keeps its bytes" "$before" "$(sum_of "$dots/delegation.md")"
check_eq "A16 a backup of the edited content was taken" 1 "$(find "$h/docs" -name 'delegation.md.*.bak' | wc -l | tr -d ' ')"

# --- A18: SEED — a dangling link is someone's wiring, left alone ------------------------------------------
ck="$ck_shared"
# (1) a dangling LEARNINGS.md in copy mode
h="$SANDBOX/a18-h1"; gone="$SANDBOX/a18-nowhere-1"; mkdir -p "$h"
ln -s "$gone" "$h/LEARNINGS.md"
run "$ck/install.sh" --home "$h" --no-hooks
check_eq "A18(1) it is still the same dangling link" "$gone" "$(readlink "$h/LEARNINGS.md")"
check_nofile "A18(1) its target was not created" "$gone"
check_contains "A18(1) one line names it" "$OUT" "LEARNINGS.md is a dangling link"
# (2) a dangling CLAUDE.md in linked mode must not reach the chain's `>>` append
h="$SANDBOX/a18-h2"; gone="$SANDBOX/a18-nowhere-2"; mkdir -p "$h"
ln -s "$gone" "$h/CLAUDE.md"
run "$ck/install.sh" --home "$h" --no-hooks --link
check_eq "A18(2) linked mode, dangling CLAUDE.md: it is still the same dangling link" "$gone" "$(readlink "$h/CLAUDE.md")"
check_nofile "A18(2) its target was not created (no import line was appended through it)" "$gone"
check_contains "A18(2) one line names it" "$OUT" "CLAUDE.md is a dangling link"
# (2b) the same for a copy-mode CLAUDE.md and for --codex's AGENTS.md
h="$SANDBOX/a18-h2b"; gone="$SANDBOX/a18-nowhere-2b"; mkdir -p "$h"
ln -s "$gone" "$h/CLAUDE.md"
run "$ck/install.sh" --home "$h" --no-hooks
check_eq "A18(2b) copy mode, dangling CLAUDE.md: still the same dangling link" "$gone" "$(readlink "$h/CLAUDE.md")"
check_nofile "A18(2b) its target was not created" "$gone"
h="$SANDBOX/a18-h2c"; gone="$SANDBOX/a18-nowhere-2c"; mkdir -p "$h"
ln -s "$gone" "$h/AGENTS.md"
run "$ck/install.sh" --home "$h" --no-hooks --codex
check_eq "A18(2c) --codex, dangling AGENTS.md: still the same dangling link" "$gone" "$(readlink "$h/AGENTS.md")"
check_nofile "A18(2c) its target was not created" "$gone"
# (2d) a dangling keel/README.md in linked mode
h="$SANDBOX/a18-h2d"; gone="$SANDBOX/a18-nowhere-2d"; mkdir -p "$h/keel"
ln -s "$gone" "$h/keel/README.md"
run "$ck/install.sh" --home "$h" --no-hooks --link
check_eq "A18(2d) linked mode, dangling keel/README.md: still the same dangling link" "$gone" "$(readlink "$h/keel/README.md")"
check_nofile "A18(2d) its target was not created" "$gone"
check_eq "A18(2d) it is not recorded as Keel's" 0 "$(symlink_records "$h" keel/README.md)"
# (3) tools/init-project.sh in a project whose CLAUDE.md is a dangling link pointing outside the project
proj="$SANDBOX/a18-proj"; gone="$SANDBOX/a18-nowhere-3"; mkdir -p "$proj"
ln -s "$gone" "$proj/CLAUDE.md"
run "$ck/tools/init-project.sh" --no-register --no-impact "$proj"
check_eq "A18(3) init-project: CLAUDE.md is still the same dangling link" "$gone" "$(readlink "$proj/CLAUDE.md")"
check_nofile "A18(3) its target outside the project was not created" "$gone"
check_contains "A18(3) one line names it" "$OUT" "CLAUDE.md is a dangling link"

# --- A23: B10 — the rule is stated once, for adopters ------------------------------------------------------
gs="$REPO_ROOT/docs/getting-started.md"
check_eq "A23 getting-started.md has one line reading 'a link Keel did not make' together with '--force'" 1 \
  "$(grep -F 'a link Keel did not make' "$gs" | grep -c -F -- '`--force`' || true)"
check_contains "A23 docs/reference.md's install.sh row carries the pointer clause" "$(cat "$REPO_ROOT/docs/reference.md")" "a symlink Keel did not make is never replaced"

# --- A25: T3a and the T3 checkout= test ---------------------------------------------------------------------
# Copy mode. An unedited REAL copy of a Keel doc goes to dotfiles and is linked back.
ck="$(mk_ck a25-ck-copy)"; h="$SANDBOX/a25-h-copy"; dots="$SANDBOX/a25-dots-copy"; mkdir -p "$h" "$dots"
run "$ck/install.sh" --home "$h" --no-hooks
mv "$h/docs/delegation.md" "$dots/delegation.md"
ln -s "$dots/delegation.md" "$h/docs/delegation.md"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A25 copy: re-run over an in-sync adopter link exits 0" 0 "$STATUS"
check_contains "A25 copy: the output says 'your link'" "$(line_of "$OUT" delegation.md)" "your link"
check_eq "A25 copy: the manifest has no symlink record for it" 0 "$(symlink_records "$h" docs/delegation.md)"
# …then a manifest written by the baseline (it recorded that link as Keel's) and a drifted source.
printf 'artifact=symlink\tdocs/delegation.md\t%s\n' "$dots/delegation.md" >> "$(manifest_of "$h")"
printf '\n# NEXT RELEASE\n' >> "$ck/docs/delegation.md"
before="$(sum_of "$dots/delegation.md")"
for mode in plain force; do
  flag=""; [ "$mode" = force ] && flag="--force"
  run "$ck/install.sh" --home "$h" --no-hooks $flag
  check_status "A25 copy $mode: exit 0" 0 "$STATUS"
  check_link "A25 copy $mode: the link is kept" "$h/docs/delegation.md"
  check_eq "A25 copy $mode: the dotfiles bytes are unchanged" "$before" "$(sum_of "$dots/delegation.md")"
  check_eq "A25 copy $mode: no backup" 0 "$(bak_count "$h")"
  check_contains "A25 copy $mode: declined (T4)" "$OUT" "remove the link and re-run"
  check_eq "A25 copy $mode: the older manifest's record of the adopter's link is dropped" 0 "$(symlink_records "$h" docs/delegation.md)"
done
run "$ck/uninstall.sh" --home "$h" --yes
check_link "A25 copy: uninstall leaves the adopter's link where it is" "$h/docs/delegation.md"
# Linked mode. The home entry is itself a link into the checkout, so the adopter makes a real copy first.
ck="$(mk_ck a25-ck-link)"; h="$SANDBOX/a25-h-link"; dots="$SANDBOX/a25-dots-link"; mkdir -p "$h" "$dots"
run "$ck/install.sh" --home "$h" --no-hooks --link
check_status "A25 linked: fixture install exits 0" 0 "$STATUS"
check_eq "A25 linked: the fixture manifest records Keel's own link" 1 "$(symlink_records "$h" keel/docs/delegation.md)"
cp -L "$h/keel/docs/delegation.md" "$dots/delegation.md"
rm -f "$h/keel/docs/delegation.md"
ln -s "$dots/delegation.md" "$h/keel/docs/delegation.md"
run "$ck/install.sh" --home "$h" --no-hooks --link
check_status "A25 linked: re-run over an in-sync adopter link exits 0" 0 "$STATUS"
check_eq "A25 linked: the link is still the adopter's" "$dots/delegation.md" "$(readlink "$h/keel/docs/delegation.md")"
check_contains "A25 linked: the output says 'your link'" "$(line_of "$OUT" delegation.md)" "your link"
check_eq "A25 linked: the manifest no longer holds a symlink record for it" 0 "$(symlink_records "$h" keel/docs/delegation.md)"
printf 'artifact=symlink\tkeel/docs/delegation.md\t%s\n' "$dots/delegation.md" >> "$(manifest_of "$h")"
printf '\n# NEXT RELEASE\n' >> "$ck/docs/delegation.md"
before="$(sum_of "$dots/delegation.md")"
for mode in plain force; do
  flag=""; [ "$mode" = force ] && flag="--force"
  run "$ck/install.sh" --home "$h" --no-hooks --link $flag
  check_link "A25 linked $mode: the link is kept" "$h/keel/docs/delegation.md"
  check_eq "A25 linked $mode: still pointing at the dotfiles copy" "$dots/delegation.md" "$(readlink "$h/keel/docs/delegation.md")"
  check_eq "A25 linked $mode: the dotfiles bytes are unchanged" "$before" "$(sum_of "$dots/delegation.md")"
  check_eq "A25 linked $mode: no backup" 0 "$(bak_count "$h")"
  check_contains "A25 linked $mode: declined (T4)" "$OUT" "remove the link and re-run"
  check_eq "A25 linked $mode: the older manifest's record of the adopter's link is dropped" 0 "$(symlink_records "$h" keel/docs/delegation.md)"
done

# --- A26: T4 runs before the alias branch and the prompts ----------------------------------------------------
# (1) an alias already exists, then --force
ck="$ck_shared"; h="$SANDBOX/a26-h1"; dots="$SANDBOX/a26-dots1"; mkdir -p "$h" "$dots"
run "$ck/install.sh" --home "$h" --no-hooks
mv "$h/commands/wrap.md" "$dots/wrap.md"
printf '\n# MY OWN WRAP\n' >> "$dots/wrap.md"
ln -s "$dots/wrap.md" "$h/commands/wrap.md"
run "$ck/install.sh" --home "$h" --no-hooks
check_file "A26(1) fixture: the plain run created the keel-wrap.md alias" "$h/commands/keel-wrap.md"
before="$(sum_of "$dots/wrap.md")"
run "$ck/install.sh" --home "$h" --no-hooks --force
check_status "A26(1) --force with the alias present: exit 0" 0 "$STATUS"
check_link "A26(1) the link is kept" "$h/commands/wrap.md"
check_eq "A26(1) the dotfiles file is byte-identical" "$before" "$(sum_of "$dots/wrap.md")"
check_eq "A26(1) no backup" 0 "$(bak_count "$h")"
ln1="$(line_of "$OUT" "wrap.md is your own command")"
check_contains "A26(1) the decline says 'remove the link and re-run'" "$ln1" "remove the link and re-run"
check_absent "A26(1) …with no --force remedy in it" "$ln1" "--force"
check_absent "A26(1) …and no 'Reclaim it' line for the name" "$OUT" "wrap.md left untouched (yours"
# (2) no alias yet, a terminal answers 'u' to the alias prompt
if [ "$have_script" = 1 ]; then
  ck="$ck_shared"; h="$SANDBOX/a26-h2"; dots="$SANDBOX/a26-dots2"; mkdir -p "$h" "$dots"
  run "$ck/install.sh" --home "$h" --no-hooks
  mv "$h/commands/wrap.md" "$dots/wrap.md"
  printf '\n# MY OWN WRAP\n' >> "$dots/wrap.md"
  ln -s "$dots/wrap.md" "$h/commands/wrap.md"
  before="$(sum_of "$dots/wrap.md")"
  tty_run u "$ck/install.sh" --home "$h" --no-hooks
  check_link "A26(2) the link is kept after a terminal 'u'" "$h/commands/wrap.md"
  check_eq "A26(2) the dotfiles file is byte-identical" "$before" "$(sum_of "$dots/wrap.md")"
  check_eq "A26(2) no backup" 0 "$(bak_count "$h")"
  check_absent "A26(2) no [u]pdate offer for the link" "$OUT" "[u]pdate"
  ln2="$(line_of "$OUT" "wrap.md is your own command")"
  check_contains "A26(2) the decline says 'remove the link and re-run'" "$ln2" "remove the link and re-run"
else
  echo "  skip  A26(2) (script absent)"
fi

# --- B3 at the --no-git trimmed copy of keel/CORE.md: a link that is not Keel's is declined too -------------
ck="$ck_shared"; h="$SANDBOX/core-h"; dots="$SANDBOX/core-dots"; mkdir -p "$h" "$dots"
run "$ck/install.sh" --home "$h" --no-hooks --link
cp -L "$h/keel/CORE.md" "$dots/CORE.md"; rm -f "$h/keel/CORE.md"; ln -s "$dots/CORE.md" "$h/keel/CORE.md"
before="$(sum_of "$dots/CORE.md")"
run "$ck/install.sh" --home "$h" --no-hooks --link --no-git
check_absent "CORE.md: Verify does not report the trimmed core it did not place" "$OUT" "keel/CORE.md is the trimmed --no-git core"
check_link "CORE.md: the adopter's link survives --no-git" "$h/keel/CORE.md"
check_eq "CORE.md: the dotfiles file is byte-identical" "$before" "$(sum_of "$dots/CORE.md")"
check_contains "CORE.md: declined, with the remedy" "$OUT" "remove the link and re-run"

# --- B5: a seed path holding something that is not a regular file never aborts the run --------------------
h="$SANDBOX/seed-dir-h"; mkdir -p "$h" "$SANDBOX/seed-dir-target"
ln -s "$SANDBOX/seed-dir-target" "$h/LEARNINGS.md"
run "$ck_shared/install.sh" --home "$h" --no-hooks
check_link "B5: a link to a directory at a seed path is untouched" "$h/LEARNINGS.md"
check_contains "B5: …with one line naming it" "$OUT" "LEARNINGS.md is not a regular file"
check_contains "B5: …and Verify reports it as yours, not MISS (a decline is not a failed install — dir #685 FIX-1)" "$OUT" "LEARNINGS.md is yours"
check_status "B5: …the run exits 0" 0 "$STATUS"
check_file "B5: …and writes its manifest" "$(manifest_of "$h")"
check_absent "B5: …no safe-write refusal aborted the run" "$OUT" "safe-write:"

# --- init-project: a CLAUDE.md that is a directory is left alone, named honestly -------------------------------
proj="$SANDBOX/b5-proj-dir"; mkdir -p "$proj/CLAUDE.md"
run "$ck_shared/tools/init-project.sh" --no-register --no-impact "$proj"
check_dir "B5 init-project: a directory at CLAUDE.md is untouched" "$proj/CLAUDE.md"
check_contains "B5 init-project: …named as not a regular file" "$OUT" "CLAUDE.md is not a regular file"

# --- doctor: the three remedy lines tell the adopter to remove a link Keel did not make first ----------------
doc="$(cat "$REPO_ROOT/tools/doctor.sh")"
for code in W-LINK-FOREIGN W-REVIEW-AGENT-FLOOR W-CLI-FOREIGN; do
  check_eq "doctor $code remedy mentions removing a link Keel did not make" 1 \
    "$(grep -F "warn $code" <<<"$doc" | grep -c -F 'a link Keel did not make' || true)"
done

summary
