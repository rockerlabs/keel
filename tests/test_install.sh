#!/usr/bin/env bash
# install.sh — one-command bootstrap: copy the core, wire the hook, idempotent, never clobber.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

install="$REPO_ROOT/install.sh"
core=(CLAUDE.md INSTANCE.md LEARNINGS.md FRAMEWORK.md PRINCIPLES.md)

# fresh install into the default home ($HOME/.claude, redirected into the sandbox)
run "$install"
check_status "fresh install → exit 0" 0 "$STATUS"
for f in "${core[@]}"; do check_file "copies $f" "$HOME/.claude/$f"; done
check_contains "wires secret-guard" "$OUT" "secret-guard"
hp="$(git config --global core.hooksPath || true)"
check_contains "sets global hooksPath to keel-hooks" "$hp" "keel-hooks"
check_contains "verify confirms Keel's secret-guard is wired" "$OUT" "OK   secret-guard"
check_file "installs lifecycle commands as slash commands" "$HOME/.claude/commands/wrap.md"
check_absent "no foreign-core nag when install created CLAUDE.md" "$OUT" "NOT merged in"

# idempotent re-run preserves a user edit and clobbers nothing
printf '\nMY-EDIT\n' >> "$HOME/.claude/CLAUDE.md"
run "$install"
check_status "re-run → exit 0" 0 "$STATUS"
check_contains "re-run preserves the user edit" "$(cat "$HOME/.claude/CLAUDE.md")" "MY-EDIT"
check_contains "re-run leaves files untouched" "$OUT" "left untouched"
check_absent "no foreign-core nag on a Keel-derived CLAUDE.md" "$OUT" "NOT merged in"

# --no-hooks into a custom --home
alt="$SANDBOX/alt-home"
run "$install" --home "$alt" --no-hooks
check_status "--no-hooks --home → exit 0" 0 "$STATUS"
check_file "custom home gets CLAUDE.md" "$alt/CLAUDE.md"
check_contains "secret-guard step skipped" "$OUT" "skipped"

# never clobbers a pre-existing foreign global hooksPath — and, with a real (foreign) pre-commit
# present there, must NOT then falsely report it as Keel's secret-guard (the old verify did).
mkdir -p "$SANDBOX/foreign-hooks"
printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/foreign-hooks/pre-commit"; chmod +x "$SANDBOX/foreign-hooks/pre-commit"
git config --global core.hooksPath "$SANDBOX/foreign-hooks"
run "$install"
check_status "foreign hooksPath present → exit 0" 0 "$STATUS"
check_contains "warns instead of clobbering" "$OUT" "not clobbering"
check_contains "verify flags the foreign hooksPath" "$OUT" "foreign global core.hooksPath"
check_absent "verify does NOT falsely claim secret-guard OK" "$OUT" "OK   secret-guard"
hp="$(git config --global core.hooksPath || true)"
check_status "foreign hooksPath is preserved" "$SANDBOX/foreign-hooks" "$hp"

# unset $HOME must not crash when the target is given explicitly and hooks are skipped — neither
# --home nor KEEL_HOME should ever need $HOME (regression for `set -u` on an eager $HOME default).
run env -u HOME bash "$install" --home "$SANDBOX/nohome-flag" --no-hooks
check_status "unset HOME + --home + --no-hooks → exit 0" 0 "$STATUS"
check_file "installs into --home with HOME unset" "$SANDBOX/nohome-flag/CLAUDE.md"

run env -u HOME KEEL_HOME="$SANDBOX/nohome-env" bash "$install" --no-hooks
check_status "unset HOME + KEEL_HOME + --no-hooks → exit 0" 0 "$STATUS"
check_file "installs into KEEL_HOME with HOME unset" "$SANDBOX/nohome-env/CLAUDE.md"

# a pre-existing NON-Keel CLAUDE.md: never clobbered, install loudly flags the un-merged rails, and
# still wires everything else (commands included) so onboarding isn't silently half-done.
fhome="$SANDBOX/foreign-core"; mkdir -p "$fhome"
printf '# My own global notes\nnothing keel here\n' > "$fhome/CLAUDE.md"
run "$install" --home "$fhome" --no-hooks
check_status "foreign CLAUDE.md → exit 0" 0 "$STATUS"
check_contains "flags that rails were not merged in" "$OUT" "NOT merged in"
check_contains "foreign CLAUDE.md left untouched" "$(cat "$fhome/CLAUDE.md")" "My own global notes"
check_file "still wires commands into a foreign home" "$fhome/commands/wrap.md"

# bootstrap.sh: the one-line install path — clone (here a local repo, no network) + run install.sh,
# into an isolated home. Verifies the curl|sh entry point wires the core + commands end to end.
boot="$REPO_ROOT/bootstrap.sh"
bhome="$SANDBOX/boot-home"
run env KEEL_REPO="$REPO_ROOT" sh "$boot" --home "$bhome" --no-hooks
check_status "bootstrap → exit 0" 0 "$STATUS"
check_file "bootstrap installs the core" "$bhome/CLAUDE.md"
check_file "bootstrap installs the slash commands" "$bhome/commands/wrap.md"

summary
