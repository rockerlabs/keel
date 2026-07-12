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
# polish.md is maintainer dev-tooling (its pre-pr-gate hook is never wired) — install must NOT ship it.
check_nofile "does NOT install the maintainer-only /polish command" "$HOME/.claude/commands/polish.md"
check_absent "no foreign-core nag when install created CLAUDE.md" "$OUT" "NOT merged in"

# idempotent re-run preserves a user edit and clobbers nothing
printf '\nMY-EDIT\n' >> "$HOME/.claude/CLAUDE.md"
run "$install"
check_status "re-run → exit 0" 0 "$STATUS"
check_contains "re-run preserves the user edit" "$(cat "$HOME/.claude/CLAUDE.md")" "MY-EDIT"
check_contains "re-run leaves files untouched" "$OUT" "left untouched"
check_absent "no foreign-core nag on a Keel-derived CLAUDE.md" "$OUT" "NOT merged in"

# One non-interactive re-run covers three drift/collision scenarios at once (each extra installer run
# costs a full guard install + selftest on a 3-OS CI matrix):
#  - a DRIFTED Keel-owned file (FRAMEWORK): never overwritten without a yes, flagged loudly, no hang;
#  - the adopter's OWN /go under the generic name: their file untouched, and Keel's lands alongside as
#    keel-go.md AUTOMATICALLY (a brand-new file clobbers nothing; the curl|sh path would otherwise
#    re-warn forever and never deliver the command);
#  - a drifted keel-* command: plain drift handling only, never a keel-keel-* alias.
printf '\nDRIFTED-FRAMEWORK\n' >> "$HOME/.claude/FRAMEWORK.md"
printf '# my own go command\n' > "$HOME/.claude/commands/go.md"
printf '\nMY-EDIT\n' >> "$HOME/.claude/commands/keel-setup.md"
run "$install"
check_status "drift + collision re-run → exit 0 (no hang)" 0 "$STATUS"
check_contains "warns the installed FRAMEWORK differs" "$OUT" "FRAMEWORK.md differs from Keel's shipped version"
check_contains "preserves the drifted copy (no clobber without a yes)" "$(cat "$HOME/.claude/FRAMEWORK.md")" "DRIFTED-FRAMEWORK"
check_contains "own /go preserved" "$(cat "$HOME/.claude/commands/go.md")" "my own go command"
check_contains "collision announces the alongside install" "$OUT" "go.md is your own command"
check_file "keel-go.md auto-installed alongside" "$HOME/.claude/commands/keel-go.md"
check_absent "no keel-keel-* alias" "$OUT" "keel-keel-setup"
check_contains "keel-setup drift still flagged" "$OUT" "keel-setup.md differs"
# (run overwrites $OUT — keep this content check after the output assertions above)
run cmp -s "$REPO_ROOT/commands/go.md" "$HOME/.claude/commands/keel-go.md"
check_status "keel-go.md content is Keel's shipped go.md" 0 "$STATUS"

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
# … and this run doubles as the resolved-collision re-run (keel-go.md exists since the collision run):
# the user's own /go is recognized as theirs — no repeat prompt/WARN — and drift routes to the alias.
check_contains "resolved collision: own /go not re-nagged" "$OUT" "go.md left untouched (yours"
check_absent "no drift WARN for the user's own go.md" "$OUT" "!    go.md differs"
check_contains "drift check routed to the alias" "$OUT" "keel-go.md (up to date)"

# resolved state is absolute: with keel-go.md present, even deleting your own go.md does NOT re-create
# the unprefixed name (you kept the prefixed one on purpose) — and a drifted alias still gets drift
# handling instead of silently going stale.
rm "$HOME/.claude/commands/go.md"
printf '\nSTALE-ALIAS\n' >> "$HOME/.claude/commands/keel-go.md"
run "$install"
check_status "deleted own command re-run → exit 0" 0 "$STATUS"
check_nofile "unprefixed go.md not re-created while the alias exists" "$HOME/.claude/commands/go.md"
check_contains "drifted alias still gets drift handling" "$OUT" "keel-go.md differs"

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
# Mark REPO_ROOT safe: in a container (CI Alpine leg) the mounted repo is owned by a different uid than
# the runner, so git would refuse to clone it ("dubious ownership", exit 128). Written to the sandbox
# global config (lib.sh's GIT_CONFIG_GLOBAL), which the bootstrap's git clone inherits.
git config --global --add safe.directory '*'
run env KEEL_REPO="$REPO_ROOT" sh "$boot" --home "$bhome" --no-hooks
check_status "bootstrap → exit 0" 0 "$STATUS"
check_file "bootstrap installs the core" "$bhome/CLAUDE.md"
check_file "bootstrap installs the slash commands" "$bhome/commands/wrap.md"

# --- no-git copy install (2c): fetch a source tarball instead of cloning --------------------------
# A tarball of the committed tree; `git archive --prefix=keel/` gives the single top dir bootstrap unwraps.
tb="$SANDBOX/keel-src.tar.gz"
git -C "$REPO_ROOT" archive --format=tar.gz --prefix=keel/ HEAD -o "$tb"

# T1: explicit KEEL_TARBALL (git present) → tarball path, copy install works end to end
t1home="$SANDBOX/tar-home"
run env KEEL_TARBALL="$tb" sh "$boot" --home "$t1home" --no-hooks
check_status "KEEL_TARBALL install → exit 0" 0 "$STATUS"
check_file "tarball install lands the core" "$t1home/CLAUDE.md"
check_file "tarball install lands the commands" "$t1home/commands/wrap.md"

# T2: git hidden via a PATH farm (symlink every tool EXCEPT git) → no-git fallback fires:
# prose-only announced, --no-hooks auto-forced, install still lands from the tarball.
farm="$SANDBOX/nogit-bin"; mkdir -p "$farm"
IFS=:; for d in $PATH; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    [ "$n" = git ] && continue
    [ -e "$farm/$n" ] || ln -s "$f" "$farm/$n"
  done
done
unset IFS
t2home="$SANDBOX/nogit-home"
run env PATH="$farm" HOME="$HOME" KEEL_TARBALL="$tb" sh "$boot" --home "$t2home"
check_status "bootstrap without git → exit 0" 0 "$STATUS"
check_contains "no-git run announces prose-only" "$OUT" "prose rails"
check_file "no-git install still lands the core" "$t2home/CLAUDE.md"
check_file "no-git install still lands the commands" "$t2home/commands/wrap.md"

summary
