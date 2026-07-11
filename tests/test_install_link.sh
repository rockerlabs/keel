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
check_nofile "maintainer-only /polish is still not shipped" "$HOME/.claude/commands/polish.md"

# --- idempotent re-run: nothing re-created, the ONE import line never duplicates ------------------
run "$install" --link --home "$HOME/.claude" --no-hooks
check_status "linked re-run → exit 0" 0 "$STATUS"
check_contains "re-run sees links up to date" "$OUT" "CORE.md (up to date)"
n="$(grep -c '^@' "$HOME/.claude/CLAUDE.md")"
check_status "exactly one import line after a re-run" 1 "$n"

# --- doctor --install: complete → OK; missing command → WARN (exit 0); dangling link → GAP (exit 1)
run "$doctor" --install "$HOME/.claude"
check_status "doctor --install on a complete install → exit 0" 0 "$STATUS"
# deliberate change-detector: shipping (or skipping) another command MUST consciously bump this count
check_contains "doctor reports full command coverage" "$OUT" "commands: 8 of 8 shipped are wired"
check_contains "doctor sees the linked core" "$OUT" "core rails: linked"
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

# --- bootstrap refuses --link: its temp clone is deleted on exit --------------------------------
run sh "$REPO_ROOT/bootstrap.sh" --link
check_status "bootstrap --link → exit 2" 2 "$STATUS"
check_contains "explains the kept-clone requirement" "$OUT" "clone you keep"

summary
