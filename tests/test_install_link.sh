#!/usr/bin/env bash
# install.sh --link + doctor.sh --install — linked mode wires Keel BY REFERENCE (symlinks + one
# @import line), never clobbers user content, migrates a copy-mode home losslessly, self-heals
# dangling links on a re-run, and the doctor closes the composition gap (`git pull` refreshes
# content, never composition). bootstrap.sh must refuse --link (its temp clone is reaped on exit).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# --- fresh linked install into the default-shaped home ($HOME/.claude → the ~-form import line) ----
run "$install" --link --home "$HOME/.claude" --no-hooks
check_status "fresh --link → exit 0" 0 "$STATUS"
# (run overwrites $OUT — assert on the install output BEFORE the file-state runs below)
check_contains "verify confirms the import line" "$OUT" "OK   CLAUDE.md imports keel/CORE.md"
# S8 (backlog dir #4): install's own Verify asserts the onboarding command it tells you to run next
# actually landed — linked mode too, not just the copy path.
check_contains "verify confirms keel-setup.md is wired" "$OUT" "OK   commands/keel-setup.md"
for f in CORE.md FRAMEWORK.md PRINCIPLES.md; do
  check_link "keel/$f is a symlink" "$HOME/.claude/keel/$f"
  run cmp -s "$HOME/.claude/keel/$f" "$REPO_ROOT/$f"
  check_status "keel/$f resolves to the shipped $f" 0 "$STATUS"
done
check_file "keel/README.md documents the consumption dir" "$HOME/.claude/keel/README.md"
gc="$(cat "$HOME/.claude/CLAUDE.md")"
check_contains "generated CLAUDE.md imports the core (~-form under \$HOME)" "$gc" "@~/.claude/keel/CORE.md"
check_absent  "generated CLAUDE.md has no embedded KEEL-CORE block" "$gc" "KEEL-CORE-BEGIN"
check_absent  "generated CLAUDE.md drops the (TEMPLATE) header tag" "$gc" "(TEMPLATE)"
check_absent  "generated CLAUDE.md drops the copy-me instruction" "$gc" "Copy this to your harness"
check_contains "generated map points at keel/FRAMEWORK.md" "$gc" '`keel/FRAMEWORK.md`'
# Coupling pins (same precedent as test_doc_figures' heading pins): the generator's sed targets these
# exact template strings — absence-only checks above go green the moment the template rewords, so pin
# the strings HERE to make a reword fail loudly instead of the sed silently no-oping.
tpl="$(cat "$REPO_ROOT/templates/CLAUDE.md")"
check_contains "template still carries the (TEMPLATE) tag the generator strips" "$tpl" "(TEMPLATE)"
check_contains "template still carries the copy-me line the generator strips" "$tpl" "> Copy this to your harness"
check_contains "template map names FRAMEWORK.md the way the re-pointer expects" "$tpl" '**`FRAMEWORK.md`**'
check_contains "template map names PRINCIPLES.md the way the re-pointer expects" "$tpl" '**`PRINCIPLES.md`**'
check_nolink "INSTANCE.md is a real file, never a symlink into the checkout" "$HOME/.claude/INSTANCE.md"
check_link "commands are wired as symlinks" "$HOME/.claude/commands/wrap.md"
# dir #68: /polish now ships like every other command — its gate is the separate opt-in step instead.
check_link "polish.md ships too (its gate is the opt-in step, not the command)" "$HOME/.claude/commands/polish.md"

# --- idempotent re-run: nothing re-created, the ONE import line never duplicates ------------------
run "$install" --link --home "$HOME/.claude" --no-hooks
check_status "linked re-run → exit 0" 0 "$STATUS"
check_contains "re-run sees links up to date" "$OUT" "CORE.md (up to date)"
n="$(grep -c '^@' "$HOME/.claude/CLAUDE.md")"
check_status "exactly one import line after a re-run" 1 "$n"

# dir #323 test 10 (linked-mode no-op): a linked Keel-owned file is manifested as `symlink -`, never a
# `cksum:` — keel_own_untouched's artifact=file lookup can never match it, so the provenance branch
# structurally never fires in linked mode; the drift behaviour above (byte-identical to before dir #323)
# is what it falls through to instead.
lman="$(cat "$HOME/.claude/.keel/install-manifest.claude")"
check_contains "linked FRAMEWORK.md is manifested as a symlink, not a cksum" "$lman" "$(printf 'artifact=symlink\tkeel/FRAMEWORK.md\t-')"
check_absent "no artifact=file line exists for it" "$lman" "$(printf 'artifact=file\tkeel/FRAMEWORK.md')"

# --- doctor --install: complete → OK; missing command → WARN (exit 0); dangling link → GAP (exit 1)
run "$doctor" --install "$HOME/.claude"
check_status "doctor --install on a complete install → exit 0" 0 "$STATUS"
# deliberate change-detector: shipping (or skipping) another command MUST consciously bump this count
check_contains "doctor reports full command coverage" "$OUT" "commands: 9 of 9 shipped are wired"
check_contains "doctor sees the linked core" "$OUT" "core rails: linked"
# dir #68 pairing check: polish.md is wired but this install has no --no-hooks-skipped gate — WARN.
check_contains "doctor flags the shipped-but-unwired gate" "$OUT" "no machine-global gate is wired"
touch "$SANDBOX/empty-registry.md"
run "$doctor" --install "$HOME/.claude" --registry "$SANDBOX/empty-registry.md"
check_status "--install + --registry rejected → exit 2" 2 "$STATUS"
check_contains "rejection names the conflict" "$OUT" "don't combine"
rm "$HOME/.claude/commands/wrap.md"
run "$doctor" --install "$HOME/.claude"
check_status "a missing (declinable) command stays advisory → exit 0" 0 "$STATUS"
check_contains "doctor names the missing command" "$OUT" "wrap.md"
ln -sfn /nonexistent-keel-target "$HOME/.claude/commands/go.md"
run "$doctor" --install "$HOME/.claude"
check_status "a dangling symlink is a HARD failure → exit 1" 1 "$STATUS"
check_contains "doctor names the dangling link" "$OUT" "dangling symlink"
run "$doctor" --install "$SANDBOX/no-such-home"
check_status "no install at the given home → exit 1" 1 "$STATUS"

# --- re-run self-heals: the dangling go.md and the removed wrap.md are re-wired -------------------
run "$install" --link --home "$HOME/.claude" --no-hooks
check_status "healing re-run → exit 0" 0 "$STATUS"
run cmp -s "$HOME/.claude/commands/go.md" "$REPO_ROOT/commands/go.md"
check_status "dangling go.md re-pointed at the shipped command" 0 "$STATUS"
check_file "removed wrap.md re-wired" "$HOME/.claude/commands/wrap.md"

# --- a foreign (user's own) CLAUDE.md: append exactly ONE line, touch nothing else ----------------
fhome="$SANDBOX/link-foreign"; mkdir -p "$fhome"
printf '# My own global notes\nnothing keel here\n' > "$fhome/CLAUDE.md"
run "$install" --link --home "$fhome" --no-hooks
check_status "foreign CLAUDE.md + --link → exit 0" 0 "$STATUS"
check_contains "announces the appended import line" "$OUT" "appended the Keel core import line"
fc="$(cat "$fhome/CLAUDE.md")"
check_contains "user content preserved" "$fc" "My own global notes"
check_contains "absolute import path outside \$HOME" "$fc" "@$fhome/keel/CORE.md"
run "$install" --link --home "$fhome" --no-hooks
n="$(grep -c '^@' "$fhome/CLAUDE.md")"
check_status "re-run never appends a second line" 1 "$n"

# --- copy-mode home migrates losslessly: identical block → import line, identical copies → links --
mhome="$SANDBOX/link-migrate"
run "$install" --home "$mhome" --no-hooks
run "$install" --link --home "$mhome" --no-hooks
check_status "copy → linked migration → exit 0" 0 "$STATUS"
check_contains "identical embedded rails swapped for the import" "$OUT" "embedded rails swapped for the import line"
check_contains "identical command copies upgraded to symlinks" "$OUT" "upgraded to a symlink"
check_contains "stale root FRAMEWORK.md copy flagged, not deleted" "$OUT" "FRAMEWORK.md root copy remains"
check_absent  "no KEEL-CORE block remains" "$(cat "$mhome/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_file "root copy indeed left in place" "$mhome/FRAMEWORK.md"
run test -L "$mhome/commands/wrap.md"
check_status "wrap.md is a symlink after migration" 0 "$STATUS"

# --- an EDITED embedded block is never swapped non-interactively --------------------------------
dhome="$SANDBOX/link-drifted"; mkdir -p "$dhome"
# a copy-mode CLAUDE.md is byte-identical to the template (copy_gap is a plain cp) — seed it directly
# instead of paying a full installer run; the edit must land INSIDE the KEEL-CORE block, which is
# exactly what the "your edits may live there" guard protects
sed 's/## Precedence — when sources conflict/## Precedence — MY EDITED RAIL/' "$REPO_ROOT/templates/CLAUDE.md" \
  > "$dhome/CLAUDE.md"
run "$install" --link --home "$dhome" --no-hooks
check_status "drifted block + --link → exit 0 (no hang, no clobber)" 0 "$STATUS"
check_contains "flags the drifted embedded rails" "$OUT" "embeds rails that differ from the shipped core"
check_contains "user's edited rail preserved" "$(cat "$dhome/CLAUDE.md")" "MY EDITED RAIL"
check_contains "verify explains the un-migrated state" "$OUT" "still embeds the rails as a copy"

# --- collision with the user's OWN command: alias lands as a symlink, theirs untouched ------------
chome="$SANDBOX/link-collision"; mkdir -p "$chome/commands"
printf '# my own go command\n' > "$chome/commands/go.md"
run "$install" --link --home "$chome" --no-hooks
check_status "own /go + --link → exit 0" 0 "$STATUS"
check_contains "own /go preserved" "$(cat "$chome/commands/go.md")" "my own go command"
run test -L "$chome/commands/keel-go.md"
check_status "keel-go.md alias is a symlink" 0 "$STATUS"
run cmp -s "$chome/commands/keel-go.md" "$REPO_ROOT/commands/go.md"
check_status "alias resolves to the shipped go.md" 0 "$STATUS"

# --- mode is sticky: a PLAIN re-run over a linked home stays linked (no stale root copies) --------
run "$install" --home "$HOME/.claude" --no-hooks
check_status "plain re-run on a linked home → exit 0" 0 "$STATUS"
check_contains "announces it stays in linked mode" "$OUT" "continuing in linked mode"
check_nofile "no root FRAMEWORK.md copy manufactured" "$HOME/.claude/FRAMEWORK.md"

# --- re-link through a different PATH SPELLING of the same checkout: in sync, no spurious aliases -
ln -s "$REPO_ROOT" "$SANDBOX/repo-alias"
run "$SANDBOX/repo-alias/install.sh" --link --home "$HOME/.claude" --no-hooks
check_status "re-link via an aliased path → exit 0" 0 "$STATUS"
check_absent "same physical file is in sync (no collision)" "$OUT" "is your own command"
check_absent "no stale-link warning for the same checkout" "$OUT" "symlink to a different target"
check_nofile "no spurious keel-wrap.md alias" "$HOME/.claude/commands/keel-wrap.md"

# --- a symlink to a genuinely different target is flagged, never forked into an alias -------------
ln -sfn "$REPO_ROOT/README.md" "$HOME/.claude/commands/go.md"
run "$install" --link --home "$HOME/.claude" --no-hooks
check_status "foreign-target symlink re-run → exit 0" 0 "$STATUS"
check_contains "flags the foreign-target symlink" "$OUT" "go.md is a symlink to a different target"
check_nofile "no keel-go.md alias forked from it" "$HOME/.claude/commands/keel-go.md"
run "$doctor" --install "$HOME/.claude"
check_status "doctor: foreign-resolving link is advisory → exit 0" 0 "$STATUS"
check_contains "doctor names the outside-checkout link" "$OUT" "resolves outside this checkout"
ln -sfn "$REPO_ROOT/commands/go.md" "$HOME/.claude/commands/go.md"   # restore for later sections

# --- a dotfiles-managed (symlinked) CLAUDE.md: migration edits THROUGH the link, never severs it --
shome="$SANDBOX/link-dotfiles"; mkdir -p "$shome" "$SANDBOX/dotfiles"
cp "$REPO_ROOT/templates/CLAUDE.md" "$SANDBOX/dotfiles/CLAUDE.md"
ln -s "$SANDBOX/dotfiles/CLAUDE.md" "$shome/CLAUDE.md"
run "$install" --link --home "$shome" --no-hooks
check_status "symlinked CLAUDE.md + --link → exit 0" 0 "$STATUS"
check_link "CLAUDE.md is still a symlink after migration" "$shome/CLAUDE.md"
check_contains "dotfiles file received the import line" "$(cat "$SANDBOX/dotfiles/CLAUDE.md")" "keel/CORE.md"
check_absent "dotfiles file lost the embedded block" "$(cat "$SANDBOX/dotfiles/CLAUDE.md")" "KEEL-CORE-BEGIN"

# --- half-done manual migration (import line + leftover identical block): block auto-removed ------
hhome="$SANDBOX/link-halfdone"; mkdir -p "$hhome"
{ cat "$REPO_ROOT/templates/CLAUDE.md"; printf '\n@%s/keel/CORE.md\n' "$hhome"; } > "$hhome/CLAUDE.md"
run "$install" --link --home "$hhome" --no-hooks
check_status "import + leftover block → exit 0" 0 "$STATUS"
check_contains "identical leftover block removed (was loading twice)" "$OUT" "removed the embedded rails block"
check_absent "no KEEL-CORE block remains" "$(cat "$hhome/CLAUDE.md")" "KEEL-CORE-BEGIN"

# --- bootstrap --link (2b): clone into a PERMANENT dir, then wire the linked install --------------
# Mark REPO_ROOT safe so the bootstrap's `git clone`/`fetch` don't trip "dubious ownership" (exit 128)
# on the CI Alpine leg, where the mounted repo is owned by a different uid than the runner (same guard
# test_install.sh uses; written to lib.sh's sandbox GIT_CONFIG_GLOBAL, inherited by the child git).
git config --global --add safe.directory '*'
blink_dir="$SANDBOX/kept-keel"; blink_home="$SANDBOX/boot-link-home"
run env KEEL_REPO="$REPO_ROOT" KEEL_DIR="$blink_dir" sh "$REPO_ROOT/bootstrap.sh" --link --home "$blink_home" --no-hooks
check_status "bootstrap --link → exit 0" 0 "$STATUS"
check_dir  "bootstrap --link keeps the permanent checkout (not a reaped temp clone)" "$blink_dir"
check_file "the kept checkout carries install.sh" "$blink_dir/install.sh"
check_link "linked install wired keel/CORE.md as a symlink" "$blink_home/keel/CORE.md"
check_contains "generated CLAUDE.md imports the linked core" "$(cat "$blink_home/CLAUDE.md")" "keel/CORE.md"

# re-running the one-liner over the kept checkout updates it in place (git pull), still exit 0
run env KEEL_REPO="$REPO_ROOT" KEEL_DIR="$blink_dir" sh "$REPO_ROOT/bootstrap.sh" --link --home "$blink_home" --no-hooks
check_status "bootstrap --link re-run over the kept checkout → exit 0" 0 "$STATUS"
check_contains "re-run updates the existing checkout in place" "$OUT" "updating the existing checkout"

# a re-run that names KEEL_REF takes the ref path (fetch + checkout), not a bare pull → still exit 0
run env KEEL_REPO="$REPO_ROOT" KEEL_DIR="$blink_dir" KEEL_REF=HEAD sh "$REPO_ROOT/bootstrap.sh" --link --home "$blink_home" --no-hooks
check_status "bootstrap --link re-run with KEEL_REF → exit 0 (honors the ref)" 0 "$STATUS"

# a non-Keel dir already occupying KEEL_DIR is user data — refuse, never clobber
occupied="$SANDBOX/occupied-dir"; mkdir -p "$occupied"; printf 'mine\n' > "$occupied/my-file"
run env KEEL_REPO="$REPO_ROOT" KEEL_DIR="$occupied" sh "$REPO_ROOT/bootstrap.sh" --link --home "$blink_home" --no-hooks
check_status "bootstrap --link over a foreign dir → exit 2" 2 "$STATUS"
check_contains "refusal names the not-a-checkout reason" "$OUT" "not a Keel checkout"
check_file "the foreign dir's own file is left untouched" "$occupied/my-file"

# --- self-link guard: a --home whose keel/ IS the checkout is refused, nothing corrupted ------------
# Reproduces the near-zero but silently-destructive case (--home "$HOME" while the checkout sits at
# $HOME/keel): link_dir -ef root, so sync_product would "upgrade" the checkout's own core files into
# symlinks pointing at themselves. Run a DISPOSABLE copy of the checkout as $root (install.sh + the
# three core files) so a guard regression can only corrupt the copy, never the real REPO_ROOT the
# suite runs from; symlinking its keel/ back at that copy recreates link_dir -ef root portably.
slroot="$SANDBOX/selflink-checkout"; mkdir -p "$slroot"
cp "$REPO_ROOT/install.sh" "$slroot/install.sh"
for f in CORE.md FRAMEWORK.md PRINCIPLES.md; do cp "$REPO_ROOT/$f" "$slroot/$f"; done
slhome="$SANDBOX/selflink-home"; mkdir -p "$slhome"
ln -s "$slroot" "$slhome/keel"                       # link_dir ($slhome/keel) -ef root ($slroot)
run bash "$slroot/install.sh" --link --home "$slhome" --no-hooks
check_status "--link where keel/ IS the checkout → refused (exit 2)" 2 "$STATUS"
check_contains "refusal names the self-link reason" "$OUT" "is the Keel checkout itself"
check_nolink "checkout's own CORE.md untouched (not self-symlinked)" "$slroot/CORE.md"
check_file "checkout CORE.md is still a real file" "$slroot/CORE.md"

# --- --no-git: the always-on core lands as a GENERATED trimmed copy, not the CORE.md symlink ------
nghome="$SANDBOX/link-nogit"
run "$install" --link --no-git --home "$nghome" --no-hooks
check_status "fresh --link --no-git → exit 0" 0 "$STATUS"
check_contains "verify announces the trimmed core" "$OUT" "trimmed --no-git core"
check_nolink "keel/CORE.md is not a symlink" "$nghome/keel/CORE.md"
check_file   "keel/CORE.md is a real generated file" "$nghome/keel/CORE.md"
ngc="$(cat "$nghome/keel/CORE.md")"
check_absent   "git rails trimmed out" "$ngc" "## Git — mandatory rails"
check_absent   "reconcile-first trimmed out" "$ngc" "## Before writing code"
check_absent   "no KEEL-GIT marker survives the trim" "$ngc" "KEEL-GIT-BEGIN"
check_contains "breadcrumb marks the trim as deliberate" "$ngc" "KEEL-NOGIT"
check_contains "breadcrumb tells the assistant how to restore" "$ngc" "install.sh --link --with-git"
check_contains "secrets rails survive the trim" "$ngc" "## Secrets & personal data"
check_contains "verify discipline survives the trim" "$ngc" "## Verify discipline"
check_contains "delivery is still the one import line" "$(cat "$nghome/CLAUDE.md")" "keel/CORE.md"
check_link "FRAMEWORK.md stays a symlink" "$nghome/keel/FRAMEWORK.md"

# doctor: a fresh trim is healthy and named as trimmed
run "$doctor" --install "$nghome"
check_status "doctor --install on a fresh trim → exit 0" 0 "$STATUS"
check_contains "doctor names the trimmed state" "$OUT" "trimmed (--no-git"
check_absent "no staleness warning on a fresh trim" "$OUT" "stale against this checkout"

# a STALE trim (generated from an older CORE.md) → doctor WARNs; a PLAIN re-run keeps + heals it
printf 'STALE-MARKER-LINE\n' >> "$nghome/keel/CORE.md"
run "$doctor" --install "$nghome"
check_status "stale trim stays advisory → exit 0" 0 "$STATUS"
check_contains "doctor flags the stale trim" "$OUT" "stale against this checkout"
run "$install" --home "$nghome" --no-hooks          # plain re-run: neither --link nor --no-git
check_status "plain re-run over a --no-git home → exit 0" 0 "$STATUS"
check_contains "re-run announces it keeps the trim" "$OUT" "keeping the trim"
ngc="$(cat "$nghome/keel/CORE.md")"
check_absent "healed trim dropped the stale line" "$ngc" "STALE-MARKER-LINE"
check_absent "healed trim still carries no git rails" "$ngc" "## Git — mandatory rails"
check_nolink "re-run did NOT silently restore the symlink" "$nghome/keel/CORE.md"

# git evidence: a registered project with a .git under a trimmed core → doctor says restore
mkdir -p "$SANDBOX/ng-proj/.git"
printf '| Project | Path | CLAUDE.md | Tag |\n|---------|------|-----------|-----|\n| p | %s | - | sh |\n' \
  "$SANDBOX/ng-proj" > "$nghome/INSTANCE.md"
run "$doctor" --install "$nghome"
check_status "git evidence stays advisory → exit 0" 0 "$STATUS"
check_contains "doctor flags git projects under a trimmed core" "$OUT" "live in git"
check_contains "doctor names the restore command" "$OUT" "--with-git"

# --with-git restores the canonical symlink
run "$install" --link --with-git --home "$nghome" --no-hooks
check_status "--with-git restore → exit 0" 0 "$STATUS"
check_contains "restore announces itself" "$OUT" "git rails restored"
check_link "keel/CORE.md is a symlink again" "$nghome/keel/CORE.md"
run cmp -s "$nghome/keel/CORE.md" "$REPO_ROOT/CORE.md"
check_status "restored CORE.md resolves to the shipped rails" 0 "$STATUS"

# flag validation: the trim is a linked-mode verb; contradictory flags are refused
run "$install" --no-git --home "$SANDBOX/ng-copy" --no-hooks
check_status "--no-git without --link → exit 2" 2 "$STATUS"
check_contains "rejection points at the copy-path trim" "$OUT" "keel-setup"
run "$install" --link --no-git --with-git --home "$SANDBOX/ng-both" --no-hooks
check_status "--no-git + --with-git → exit 2" 2 "$STATUS"

# --- doctor --install: the remaining findings dir #100 found untested (mutation standard — each
# fires only when the check it guards is genuinely broken, not merely "the suite is still green") --
# Each mutation starts from its OWN fresh linked home (a literal name, same convention as fhome/mhome/
# dhome above) so one test's damage can't bleed into the next, then asserts via one shared helper.
assert_doctor_warn() {  # $1 = finding ID, $2 = scenario description (for the exit-0 assertion)
  run "$doctor" --install "$h"
  check_status "$2 → exit 0 (WARN)" 0 "$STATUS"
  check_contains "doctor flags it" "$OUT" "[$1]"
}

# W-CORE-UNLINKED: keel/CORE.md replaced by a plain-copy regular file (no KEEL-NOGIT breadcrumb) —
# the import line still resolves, but the target is no longer a live link into the checkout.
h="$SANDBOX/w-core-unlinked"; run "$install" --link --home "$h" --no-hooks
rm "$h/keel/CORE.md"
cp "$REPO_ROOT/CORE.md" "$h/keel/CORE.md"
assert_doctor_warn W-CORE-UNLINKED "keel/CORE.md as a plain copy"

# W-RAILS-DOUBLE: the import line AND a leftover embedded KEEL-CORE block both present — rails load twice.
h="$SANDBOX/w-rails-double"; run "$install" --link --home "$h" --no-hooks
printf '\n<!-- KEEL-CORE-BEGIN -->\nstray leftover block\n<!-- KEEL-CORE-END -->\n' >> "$h/CLAUDE.md"
assert_doctor_warn W-RAILS-DOUBLE "import line + embedded block"

# W-RAILS-UNWIRED: neither the @import line nor the embedded block survives — rails not wired at all.
h="$SANDBOX/w-rails-unwired"; run "$install" --link --home "$h" --no-hooks
grep -v '^@' "$h/CLAUDE.md" > "$h/CLAUDE.md.tmp" && mv "$h/CLAUDE.md.tmp" "$h/CLAUDE.md"
assert_doctor_warn W-RAILS-UNWIRED "no import, no embedded block"

# W-TIER-MISSING: FRAMEWORK.md reachable neither at keel/FRAMEWORK.md nor as a root copy.
h="$SANDBOX/w-tier-missing"; run "$install" --link --home "$h" --no-hooks
rm "$h/keel/FRAMEWORK.md"
assert_doctor_warn W-TIER-MISSING "FRAMEWORK.md missing from both locations"

# W-TIER-SHADOW: FRAMEWORK.md linked AND a stale root copy left beside it.
h="$SANDBOX/w-tier-shadow"; run "$install" --link --home "$h" --no-hooks
cp "$REPO_ROOT/FRAMEWORK.md" "$h/FRAMEWORK.md"
assert_doctor_warn W-TIER-SHADOW "linked + stale root copy"

# W-CLI-FOREIGN: bin/keel resolves to something other than this checkout's keel CLI.
h="$SANDBOX/w-cli-foreign"; run "$install" --link --home "$h" --no-hooks
ln -sfn "$REPO_ROOT/README.md" "$h/bin/keel"
assert_doctor_warn W-CLI-FOREIGN "bin/keel points outside this checkout"

# W-CLI-UNWIRED: bin/keel not wired at all.
h="$SANDBOX/w-cli-unwired"; run "$install" --link --home "$h" --no-hooks
rm "$h/bin/keel"
assert_doctor_warn W-CLI-UNWIRED "bin/keel missing"

summary
