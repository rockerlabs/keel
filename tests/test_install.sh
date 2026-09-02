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
# S8 (backlog dir #4): install's own Verify asserts the onboarding command it tells you to run next
# actually landed, instead of only doctor.sh --install catching a silently-skipped wiring bug.
check_contains "verify confirms keel-setup.md is wired" "$OUT" "OK   commands/keel-setup.md"
check_file "installs lifecycle commands as slash commands" "$HOME/.claude/commands/wrap.md"
# dir #68: /polish now ships unconditionally — its gate (tools/install-pre-pr-gate.sh) is a separate,
# opt-in step install.sh never runs by itself (a hook changes session behavior, so it needs an explicit yes).
check_file "installs /polish (its gate is a separate opt-in step)" "$HOME/.claude/commands/polish.md"
check_contains "summary points at the opt-in gate installer" "$OUT" "tools/install-pre-pr-gate.sh"
# dir #98: the gate installer has its own default home, so a RETARGETED install must name the
# matching --home flag — and a default-home install must not (it would be noise). Negative half here,
# positive half on the --home run further down.
check_absent "a default-home install carries no gate-retarget note" "$OUT" "install-pre-pr-gate.sh --home"
check_absent "no foreign-core nag when install created CLAUDE.md" "$OUT" "NOT merged in"
# a KEPT clone (this direct run) wires the CLI; the ephemeral-bootstrap case below must NOT
check_link "kept-clone install wires bin/keel" "$HOME/.claude/bin/keel"
check_contains "summary offers the CLI on a kept clone" "$OUT" "keel help"

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
# dir #323 Part 3 (reachability): the non-tty alias-creation branch used to print no remedy at all —
# it now names --force as the way to reclaim the name.
check_contains "alias-creation names --force as the reclaim remedy" "$OUT" "--force"
check_file "keel-go.md auto-installed alongside" "$HOME/.claude/commands/keel-go.md"
check_absent "no keel-keel-* alias" "$OUT" "keel-keel-setup"
check_contains "keel-setup drift still flagged" "$OUT" "keel-setup.md differs"
# (run overwrites $OUT — keep this content check after the output assertions above)
run cmp -s "$REPO_ROOT/commands/go.md" "$HOME/.claude/commands/keel-go.md"
check_status "keel-go.md content is Keel's shipped go.md" 0 "$STATUS"

# --no-hooks into a custom --home, run from a genuinely UNGUARDED environment so the same single
# install covers both the copy assertions and the summary-honesty one below (each extra installer run
# costs a full core copy + Verify pass on a 3-OS CI matrix).
# The closing summary must not tell an unguarded user they are guarded (2026-07-21 audit). dir #85
# (code audit, finding 22) split that assertion in two: it used to run against THIS sandbox HOME, where
# the first install above had already wired the guard — so it was pinning the mirror-image lie ("NOT
# wired" to a protected user). Both directions are covered now: an unguarded run must not claim
# protection (here), and a guarded --no-hooks run must not deny it (the finding-22 block near the end).
alt="$SANDBOX/alt-home"
unguarded="$SANDBOX/unguarded-home"; mkdir -p "$unguarded"
fresh_home_env "$unguarded"
run env "${FRESH_HOME_ENV[@]}" "$install" --home "$alt" --no-hooks
check_status "--no-hooks --home → exit 0" 0 "$STATUS"
check_file "custom home gets CLAUDE.md" "$alt/CLAUDE.md"
check_contains "secret-guard step skipped" "$OUT" "skipped"
case "$OUT" in
  *"secret-guard already guards"*) fail "--no-hooks summary must NOT claim the guard is active" "found the claim in output" ;;
  *) pass "--no-hooks summary does not claim the guard is active" ;;
esac
check_contains "--no-hooks summary says the guard is NOT wired" "$OUT" "secret-guard is NOT wired"
check_contains "--no-hooks Verify section explains WHY it isn't wired" "$OUT" "this run did not touch git hooks"

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
# dir #98, positive half (see the default-home run above): --home retargets this install without
# exporting KEEL_HOME, so the summary names the flag that makes the gate installer follow it.
check_contains "a --home install tells you the gate needs the same home" "$OUT" "install-pre-pr-gate.sh --home"

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
# Regression (first public audit, 2026-07-21): bootstrap's copy-mode clone is reaped on exit, so the
# run must NOT ship a bin/keel symlink into it (it would dangle) and the closing summary must not
# promise checkout-backed behaviour it can't keep (CLI on PATH, "KEEP this keel clone").
check_nolink "no bin/keel symlink from the reaped bootstrap clone" "$bhome/bin/keel"
check_nofile "no bin/keel file either" "$bhome/bin/keel"
check_contains "install announces the deliberate CLI skip" "$OUT" "keel CLI skipped"
check_absent "verify does not WARN about the skipped CLI" "$OUT" "WARN keel CLI"
check_absent "summary does not offer the CLI on the express path" "$OUT" "keel help"
check_absent "summary does not tell the user to keep a reaped clone" "$OUT" "KEEP this keel clone"
check_contains "summary points checkout-backed verbs at a kept checkout" "$OUT" "KEPT checkout"
check_file "bootstrap ships /polish even from a reaped clone (it's just a file)" "$bhome/commands/polish.md"
check_absent "ephemeral summary does not offer the gate installer as usable now" "$OUT" "opt in per project"
check_contains "ephemeral summary folds the gate installer into the kept-checkout list" "$OUT" "install-pre-pr-gate.sh"

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
farm="$SANDBOX/nogit-bin"; path_farm "$farm" git
t2home="$SANDBOX/nogit-home"
run env PATH="$farm" HOME="$HOME" KEEL_TARBALL="$tb" sh "$boot" --home "$t2home"
check_status "bootstrap without git → exit 0" 0 "$STATUS"
check_contains "no-git run announces prose-only" "$OUT" "prose rails"
check_file "no-git install still lands the core" "$t2home/CLAUDE.md"
check_file "no-git install still lands the commands" "$t2home/commands/wrap.md"

# --- bootstrap.sh error paths (S4, backlog dir #4): each must fail loudly with an actionable message,
# never hang or crash with a raw command-not-found trace, and never touch what it hasn't reached yet.

# E1: `--link` with git hidden → named-dependency error, not a bare clone failure (checked before the
# clone destination is even resolved, so this doesn't need --home/KEEL_DIR to be meaningful).
run env PATH="$farm" HOME="$HOME" sh "$boot" --link
check_status "--link without git → exit 1" 1 "$STATUS"
check_contains "--link without git → names the missing dependency" "$OUT" "--link needs git"

# E2: `--link` re-run over an existing directory that is NOT a Keel checkout → refuse rather than
# clobber (the dest lacks .git/install.sh/CORE.md, so it fails the "already a Keel checkout" test).
foreign_dir="$SANDBOX/foreign-keel-dir"; mkdir -p "$foreign_dir"
printf 'not keel\n' > "$foreign_dir/some-file"
run env KEEL_DIR="$foreign_dir" sh "$boot" --link --no-hooks
check_status "--link over a non-Keel dir → exit 2 (refuses to overwrite)" 2 "$STATUS"
check_contains "--link over a non-Keel dir → explains the refusal" "$OUT" "is not a Keel checkout"
check_contains "foreign dir content is left untouched" "$(cat "$foreign_dir/some-file")" "not keel"

# E3: no git AND no curl/wget → fetch() fails with a clear message instead of silently hanging or
# crashing with an unbound-variable trace. KEEL_TARBALL is a URL (not a local file), so the script
# reaches fetch() rather than erroring earlier on "can't derive a tarball URL".
farm_nonet="$SANDBOX/nonet-bin"; path_farm "$farm_nonet" git curl wget
run env PATH="$farm_nonet" HOME="$HOME" KEEL_TARBALL="https://example.invalid/keel.tar.gz" sh "$boot" --home "$SANDBOX/nonet-home"
check_status "no git, no curl/wget → exit 1" 1 "$STATUS"
check_contains "no git, no curl/wget → names the missing fetch tools" "$OUT" "need git, or curl/wget"

# E4: bash itself missing → the very first dependency check fails loudly (`need bash`), before
# anything else runs.
farm_nobash="$SANDBOX/nobash-bin"; path_farm "$farm_nobash" bash
run env PATH="$farm_nobash" HOME="$HOME" sh "$boot" --home "$SANDBOX/nobash-home"
check_status "bash missing → exit 1" 1 "$STATUS"
check_contains "bash missing → names bash as the missing dependency" "$OUT" "'bash' is required but not found"

# --- dir #85 (code audit, findings 23/25/22): install.sh's own usage + guard-summary honesty --------
# 23. Neither the -h/--help path nor the unknown-argument path was covered by ANY of the three
# install-test files, so a regression in usage() or in the exit-2 arm would reach a release unnoticed.
run "$install" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints the usage line" "$OUT" "install.sh"
check_contains "--help lists the flags" "$OUT" "--no-hooks"
run "$install" -h
check_status "-h → exit 0" 0 "$STATUS"
run "$install" --not-a-real-flag
check_status "unknown argument → exit 2" 2 "$STATUS"
check_contains "unknown argument names the offending flag" "$OUT" "--not-a-real-flag"
check_contains "unknown argument points at --help" "$OUT" "--help"

# 25. HOME unset WITH hooks enabled must fail with the written message, not a bare unbound-variable
# trace. Both pre-existing unset-HOME tests paired it with --no-hooks, so this guard had never fired
# under test at all.
run env -u HOME "$install" --home "$SANDBOX/nohome-withhooks"
check_status "HOME unset + hooks enabled → nonzero exit" 1 "$STATUS"
check_contains "HOME unset + hooks enabled names HOME as the reason" "$OUT" "wiring hooks needs HOME set"
check_contains "HOME unset + hooks enabled offers --no-hooks" "$OUT" "--no-hooks"

# 22. The closing guard sentence must reflect the guard's REAL state, not just whether THIS run wired
# it. A --no-hooks re-run over an ALREADY-guarded machine used to report "secret-guard is NOT wired
# (see Verify above)" to a protected user — false, and pointing at a Verify section that had said
# nothing about the guard at all. Wired here directly via install-secret-guard.sh rather than a second
# full install.sh run (each one costs a guard install + selftest across the 3-OS CI matrix).
guarded="$SANDBOX/guarded-home"; mkdir -p "$guarded"
fresh_home_env "$guarded"
run env "${FRESH_HOME_ENV[@]}" "$REPO_ROOT/tools/install-secret-guard.sh" --global
check_status "wiring the guard into a fresh home → exit 0" 0 "$STATUS"
run env "${FRESH_HOME_ENV[@]}" "$install" --home "$SANDBOX/alt-home-guarded" --no-hooks
check_status "--no-hooks over an already-guarded home → exit 0" 0 "$STATUS"
check_contains "--no-hooks still verifies the already-wired guard" "$OUT" "OK   secret-guard"
check_absent "--no-hooks does not claim the guard is NOT wired" "$OUT" "secret-guard is NOT wired"
check_contains "--no-hooks summary tells the protected user they are protected" "$OUT" "already guards your commits"

# A FOREIGN global hooksPath is the reason the guard isn't wired on ANY run — install.sh refuses to
# clobber it — so Verify must say so even under --no-hooks, rather than blaming the flag and implying a
# re-run without it would help. Ordering regression guard (operator-run /code-review high, dir #85).
foreign_home="$SANDBOX/foreign-hp-home"; mkdir -p "$foreign_home"
fresh_home_env "$foreign_home"
mkdir -p "$SANDBOX/someone-elses-hooks"
env "${FRESH_HOME_ENV[@]}" git config --global core.hooksPath "$SANDBOX/someone-elses-hooks"
run env "${FRESH_HOME_ENV[@]}" "$install" --home "$SANDBOX/alt-home-foreign" --no-hooks
check_status "--no-hooks over a foreign hooksPath → exit 0" 0 "$STATUS"
check_contains "--no-hooks still names the foreign hooksPath as the reason" "$OUT" "foreign global core.hooksPath"
check_contains "…and names the path itself" "$OUT" "$SANDBOX/someone-elses-hooks"
check_absent "…instead of blaming --no-hooks for it" "$OUT" "this run did not touch git hooks"

# --- dir #323/#324: provenance auto-refresh + --force ------------------------------------------------
# A disposable copy of the checkout (never the real $REPO_ROOT) so we can edit its shipped
# commands/polish.md to simulate a newer release without touching the actual repo. .git is stripped:
# these tests need no git functionality from the fixture, and dropping it avoids any risk of touching
# the real worktree's shared .git state (a worktree's .git is a small file pointing back at it).
ckdir="$SANDBOX/force-checkout"
cp -r "$REPO_ROOT" "$ckdir"
rm -rf "$ckdir/.git"
fhome="$SANDBOX/force-home"; mkdir -p "$fhome"
fresh_home_env "$fhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks
check_status "force-fixture: initial install → exit 0" 0 "$STATUS"
check_file "force-fixture: polish.md installed" "$fhome/commands/polish.md"

# T1 — the headline regression, shown red-first against unfixed code (dir #323's own done-criterion):
# bump the shipped polish.md (an unedited older Keel copy is now installed) and re-run non-interactively.
# It must refresh in place, with NO keel-polish.md alias created.
printf '\nNEWER-RELEASE\n' >> "$ckdir/commands/polish.md"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks
check_status "T1 provenance refresh re-run → exit 0" 0 "$STATUS"
check_contains "T1 polish.md refreshed to the newer release" "$(cat "$fhome/commands/polish.md")" "NEWER-RELEASE"
check_nofile "T1 no keel-polish.md alias created" "$fhome/commands/keel-polish.md"
check_contains "T1 announces the provenance refresh" "$OUT" "polish.md refreshed (Keel's own copy, unedited)"

# T2 — the negative that must keep working: an ADOPTER edit to the installed file still forks the alias,
# exactly as before dir #323.
printf '\nADOPTER-EDIT\n' >> "$fhome/commands/polish.md"
t2_before="$(cat "$fhome/commands/polish.md")"
printf '\nEVEN-NEWER-RELEASE\n' >> "$ckdir/commands/polish.md"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks
check_status "T2 re-run over an adopter edit → exit 0" 0 "$STATUS"
check_contains "T2 polish.md byte-unchanged (adopter edit preserved)" "$(cat "$fhome/commands/polish.md")" "$t2_before"
check_file "T2 keel-polish.md created alongside" "$fhome/commands/keel-polish.md"
# (first time the alias is created — the non-tty alias-creation branch fires, not resolved-collision;
# T3 below re-runs into the NOW-resolved state and exercises resolved-collision's own --force text.)
check_contains "T2 alias-creation names --force as the reclaim remedy" "$OUT" "reclaim the name later"

# T2b — a plain (non-force) re-run now that the alias exists: exercises resolved-collision's own
# non-force message, the OTHER previously hint-less branch (dir #323 Part 3).
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks
check_status "T2b resolved-collision re-run → exit 0" 0 "$STATUS"
check_contains "T2b resolved-collision names --force as the reclaim remedy" "$OUT" "Reclaim it:"
check_contains "T2b polish.md still left untouched" "$(cat "$fhome/commands/polish.md")" "$t2_before"

# T3 — --force from the resolved-alias state: reclaims polish.md for Keel, backs up the adopter's
# edited bytes, and never deletes the alias.
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks --force
check_status "T3 --force re-run → exit 0" 0 "$STATUS"
run cmp -s "$ckdir/commands/polish.md" "$fhome/commands/polish.md"
check_status "T3 polish.md now equals shipped" 0 "$STATUS"
t3_bak="$(ls "$fhome"/commands/polish.md.*.bak 2>/dev/null | head -1)"
check_contains "T3 a .bak file was created" "$t3_bak" ".bak"
check_contains "T3 backup holds the adopter's edited bytes" "$(cat "$t3_bak" 2>/dev/null)" "ADOPTER-EDIT"
check_file "T3 keel-polish.md still exists (never deleted)" "$fhome/commands/keel-polish.md"

# T4 — --force idempotence: a second --force on an already-converged home writes nothing new — the
# obvious wrong implementation backs up on every forced run regardless of whether anything changed.
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks --force
check_status "T4 second --force → exit 0" 0 "$STATUS"
t4_bak_count="$(ls "$fhome"/commands/polish.md.*.bak 2>/dev/null | wc -l | tr -d ' ')"
check_status "T4 .bak count still exactly 1" 1 "$t4_bak_count"

# T5 — --force never reaches the files an adopter owns.
printf '# my own global notes\n' > "$fhome/CLAUDE.md"
printf 'my own instance data\n' > "$fhome/INSTANCE.md"
t5_claude_before="$(cat "$fhome/CLAUDE.md")"; t5_instance_before="$(cat "$fhome/INSTANCE.md")"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks --force
check_status "T5 --force over custom CLAUDE.md/INSTANCE.md → exit 0" 0 "$STATUS"
check_contains "T5 CLAUDE.md byte-unchanged" "$(cat "$fhome/CLAUDE.md")" "$t5_claude_before"
check_contains "T5 INSTANCE.md byte-unchanged" "$(cat "$fhome/INSTANCE.md")" "$t5_instance_before"
t5_bak_count="$(ls "$fhome"/{CLAUDE.md,INSTANCE.md}.*.bak 2>/dev/null | wc -l | tr -d ' ')"
check_status "T5 no backup created for either" 0 "$t5_bak_count"

# T6 — bin/keel (dir #324): a real file there is left untouched by a plain run (refusal names
# --force), and --force takes it over, backed up first.
rm -f "$fhome/bin/keel"; mkdir -p "$fhome/bin"
printf '#!/bin/sh\necho fake\n' > "$fhome/bin/keel"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks
check_status "T6 plain run over a real bin/keel → exit 0" 0 "$STATUS"
check_nolink "T6 bin/keel still a real file (not wired)" "$fhome/bin/keel"
check_contains "T6 refusal names --force" "$OUT" "--force"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fhome" --no-hooks --force
check_status "T6 --force takeover → exit 0" 0 "$STATUS"
check_link "T6 bin/keel now a symlink" "$fhome/bin/keel"
run test "$fhome/bin/keel" -ef "$ckdir/keel"
check_status "T6 bin/keel resolves into the checkout" 0 "$STATUS"
t6_bak_count="$(ls "$fhome"/bin/keel.*.bak 2>/dev/null | wc -l | tr -d ' ')"
check_status "T6 a bin/keel backup was created" 1 "$t6_bak_count"

# T7 — manifest hygiene: no artifact= line ever references a .bak path (backups are adopter data;
# uninstall.sh removes by manifest, so a recorded .bak would make uninstall delete a backup).
check_absent "T7 manifest never records a .bak artifact" "$(cat "$fhome/.keel/install-manifest.claude")" ".bak"

# T8 — dir #323 (found by this ticket's own /code-review high pass): --force on a VIRGIN alias-eligible
# collision must NOT overwrite the adopter's own same-named command. The collision here was never a
# refusal — the alias fork already resolves it safely and non-destructively — so --force has nothing to
# override on a name Keel has never seen before; it only reclaims once the collision is ALREADY
# resolved (as T3 above does, from the state T2 sets up).
t8home="$SANDBOX/force-virgin-home"; mkdir -p "$t8home/commands"
printf '# my own go command, never touched by Keel\n' > "$t8home/commands/go.md"
fresh_home_env "$t8home"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$t8home" --no-hooks --force
check_status "T8 --force on a virgin collision → exit 0" 0 "$STATUS"
check_contains "T8 adopter's own go.md is untouched" "$(cat "$t8home/commands/go.md")" "never touched by Keel"
check_file "T8 keel-go.md forked alongside, not an overwrite" "$t8home/commands/keel-go.md"
t8_bak_count="$(ls "$t8home"/commands/go.md.*.bak 2>/dev/null | wc -l | tr -d ' ')"
check_status "T8 no backup was created (nothing was overwritten)" 0 "$t8_bak_count"

# T9 — dir #323 (found by this ticket's own /code-review high pass): a PRESENT but CORRUPTED
# tools/lib/manifest.sh must degrade to "provenance unavailable", never abort the whole install — the
# comment above the sourcing site promises exactly that, but only a missing-file guard was there to
# back it; a syntax error inside a sourced file aborts the whole script under `set -e` regardless of any
# if/&& wrapped around the `.` command itself (verified live), so the fix pre-checks with `bash -n`.
t9ck="$SANDBOX/force-checkout-corrupt"
cp -r "$ckdir" "$t9ck"
printf 'this is not valid bash (\n' > "$t9ck/tools/lib/manifest.sh"
t9home="$SANDBOX/force-corrupt-manifest-home"; mkdir -p "$t9home"
fresh_home_env "$t9home"
run env "${FRESH_HOME_ENV[@]}" "$t9ck/install.sh" --home "$t9home" --no-hooks
check_status "T9 corrupted tools/lib/manifest.sh → still exit 0" 0 "$STATUS"
check_file "T9 install still lands the core despite the corruption" "$t9home/FRAMEWORK.md"
check_file "T9 install still lands commands" "$t9home/commands/wrap.md"

# --- v0.8.1 RC audit: the never-clobber rail, the manifest snapshot, and the retargeting suffix -----

# T10 — the RC audit's headline blocker, a regression against v0.8.0 that needed NO --force at all.
# record_placed is symlink-aware (`symlink -` for a link, a `cksum:` only for a regular file);
# keel_own_untouched was not — it required the RECORDED kind to be `file` but never checked the dest's
# CURRENT kind, and `cksum` reads straight THROUGH a symlink. So an adopter who moves a Keel-placed
# command into a dotfiles repo and symlinks it back (byte-identical by construction) still satisfied
# the predicate, and place() → atomic_copy's `mv -f` replaced the SYMLINK ITSELF — no backup (that
# branch skips force_backup on the strength of the predicate) and a message asserting the file was
# "unedited". No content is destroyed, but the adopter's wiring is severed silently and their dotfiles
# repo is left holding an orphan the harness no longer reads.
symhome="$SANDBOX/symlink-dest-home"; mkdir -p "$symhome"
symdots="$SANDBOX/symlink-dest-dotfiles"; mkdir -p "$symdots"
fresh_home_env "$symhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$symhome" --no-hooks
check_status "T10 copy install into the symlink fixture → exit 0" 0 "$STATUS"
check_file "T10 backlog.md installed" "$symhome/commands/backlog.md"
# The dotfiles move: same bytes, different form. Nothing here edits the content.
mv "$symhome/commands/backlog.md" "$symdots/backlog.md"
ln -s "$symdots/backlog.md" "$symhome/commands/backlog.md"
printf '\nSYMLINK-DEST-RELEASE\n' >> "$ckdir/commands/backlog.md"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$symhome" --no-hooks
check_status "T10 plain re-run over a symlinked dest → exit 0" 0 "$STATUS"
check_link "T10 the adopter's symlink survives (never-clobber holds with no --force)" "$symhome/commands/backlog.md"
# These two do NOT bind the kind check — measured: both stay green when it is removed, because
# `mv -f` replaces the LINK, so the dotfiles target keeps its old bytes, and taking no backup IS the
# defect. They guard a different implementation class (a fix that wrote THROUGH the link, or that
# backed up and then clobbered). The three that bind are the check_link, the "unedited" absence, and
# the decline message below.
check_absent "T10 the linked-to file was not rewritten either" "$(cat "$symdots/backlog.md")" "SYMLINK-DEST-RELEASE"
check_absent "T10 no bogus 'Keel's own copy, unedited' claim about it" "$OUT" "backlog.md refreshed (Keel's own copy, unedited)"
t10_bak_count="$(ls "$symhome"/commands/backlog.md.*.bak 2>/dev/null | wc -l | tr -d ' ')"
check_status "T10 no backup was needed (nothing was overwritten)" 0 "$t10_bak_count"
check_contains "T10 the decline is still actionable" "$OUT" "backlog.md is your own command"

# T10b — the same never-clobber rail, in LINKED mode. The first draft of T10's fix exempted linked
# mode (`[ "$LINK" = 1 ] || [ ! -L "$dest" ]`) on the reasoning that place() makes a symlink there
# anyway, so nothing is severed. Reproduced live, that is false: the resulting form being a symlink is
# not the same thing as no wiring having been destroyed — the run re-pointed the adopter's dotfiles
# link at the checkout, took no backup, and printed the same "unedited" message. The dest here is a
# symlink with a copy-mode `file` record, which is exactly the case such an exemption would admit.
symlinkhome="$SANDBOX/symlink-dest-linked-home"; mkdir -p "$symlinkhome"
symlinkdots="$SANDBOX/symlink-dest-linked-dotfiles"; mkdir -p "$symlinkdots"
fresh_home_env "$symlinkhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$symlinkhome" --no-hooks
check_status "T10b copy install into the linked-mode symlink fixture → exit 0" 0 "$STATUS"
mv "$symlinkhome/commands/wrap.md" "$symlinkdots/wrap.md"
ln -s "$symlinkdots/wrap.md" "$symlinkhome/commands/wrap.md"
printf '\nLINKED-SYMLINK-RELEASE\n' >> "$ckdir/commands/wrap.md"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$symlinkhome" --no-hooks --link
check_status "T10b --link re-run over a symlinked dest → exit 0" 0 "$STATUS"
check_absent "T10b no bogus 'Keel's own copy, unedited' claim in linked mode either" "$OUT" "wrap.md refreshed (Keel's own copy, unedited)"
check_contains "T10b …the linked-mode symlink branch declines it by name instead" "$OUT" "wrap.md is a symlink to a different target"
check_link "T10b the adopter's symlink survives" "$symlinkhome/commands/wrap.md"
check_file "T10b the dotfiles copy is still there" "$symlinkdots/wrap.md"
# -ef, not a readlink string compare: same reason in_sync gives for its own (install.sh) — the same
# file is reachable through different path spellings (/tmp vs /private/tmp on macOS). Asserting that
# a symlink merely SURVIVES is not enough here: place() makes a symlink in linked mode too, so the
# broken behaviour also leaves one — it just points at the checkout. Identity is what binds.
run test "$symlinkhome/commands/wrap.md" -ef "$symlinkdots/wrap.md"
check_status "T10b …still resolving to their own dotfiles copy, not re-pointed at the checkout" 0 "$STATUS"

# T11 — the behaviour T10's fix must NOT break: the copy→linked migration still runs, and it needs no
# $LINK exemption in the predicate because its dest is a regular FILE, not a link (see T10b).
# `commands/<name>.md` has the same home-relative key in both modes and both modes read the same
# manifest file (manifest_mode keys on $CODEX, not on $LINK), so a `file` + `cksum:` record written by
# an earlier COPY-mode run IS visible to a later `--link` run and DOES drive the provenance branch.
# That is the intended copy→linked migration of a DRIFTED command (v0.8.0 left a stale copy shadowing
# the link forever) — a $LINK-blind "reject every symlinked dest" fix would have silently killed it.
mighome="$SANDBOX/copy-to-link-home"; mkdir -p "$mighome"
fresh_home_env "$mighome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$mighome" --no-hooks
check_status "T11 copy install → exit 0" 0 "$STATUS"
check_nolink "T11 polish.md starts as a regular copy" "$mighome/commands/polish.md"
printf '\nMIGRATION-RELEASE\n' >> "$ckdir/commands/polish.md"   # the installed copy is now drifted
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$mighome" --no-hooks --link
check_status "T11 --link over the copy-mode home → exit 0" 0 "$STATUS"
check_contains "T11 …via the provenance branch, not a decline" "$OUT" "polish.md refreshed (Keel's own copy, unedited)"
check_link "T11 the drifted copy became the canonical symlink" "$mighome/commands/polish.md"
run test "$mighome/commands/polish.md" -ef "$ckdir/commands/polish.md"   # clobbers $OUT — assert on it last
check_status "T11 …resolving into the checkout" 0 "$STATUS"

# T12 — the manifest snapshot's own read must not be able to kill the run. The `cp` that takes it sat
# in an `if` BODY at top level under `set -euo pipefail`, upstream of the degradation logic in
# manifest_field/manifest_usable that the versioning contract points at — so a manifest that EXISTS
# but cannot be READ aborted the whole install before a single file was placed (a regression against
# v0.8.0, which completed the install and failed only on trailing bookkeeping).
#
# The unconditional half is "the install completes": it converges across readers, since a root reader
# (CI's alpine-busybox leg, where chmod 000 is a no-op) simply reads the manifest and installs anyway.
# Coverage map, stated so "alpine green" is not misread as evidence: the permission-dependent halves
# here and in T12b/T13/T14d bind ONLY on the non-root matrix legs (ubuntu-24.04, macos-14). On the
# alpine-busybox leg those guards skip, and a regression in finding 2, finding 7 or T14d's own target
# would ship green there — measured by forcing the guards false, which drops 12 assertions.
# The exit STATUS does not converge — non-root still exits non-zero on the trailing manifest-merge
# bookkeeping, exactly as v0.8.0 did — so it is deliberately not asserted here; what the fix owes is
# placement, not that pre-existing wart.
umhome="$SANDBOX/unreadable-manifest-home"; mkdir -p "$umhome/.keel"
printf 'keel_manifest_version=1\n' > "$umhome/.keel/install-manifest.claude"
if [ "$(id -u 2>/dev/null)" != 0 ]; then chmod 000 "$umhome/.keel/install-manifest.claude"; fi
fresh_home_env "$umhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$umhome" --no-hooks
if [ "$(id -u 2>/dev/null)" != 0 ]; then chmod 644 "$umhome/.keel/install-manifest.claude"; fi
check_file "T12 an unreadable manifest still lands the core" "$umhome/FRAMEWORK.md"
check_file "T12 …and the commands" "$umhome/commands/wrap.md"
check_contains "T12 …and the run reaches its Verify block" "$OUT" "Verify:"

# Scratch hygiene, pinned on T12's own fixture rather than a new one: surviving the snapshot read is
# what first made the merge step's `.artifacts.<pid>` reachable on an abort, so the sweep that reaps it
# is this batch's own addition. The contract is BOUNDED litter — at most the previous run's leftover —
# not zero, and it converges across readers: a root reader reads the manifest fine and leaves 0, a
# non-root one aborts at the merge and leaves exactly 1, which the NEXT run reaps.
um_scratch_a="$(find "$umhome/.keel" -name '.artifacts.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$(id -u 2>/dev/null)" != 0 ]; then chmod 000 "$umhome/.keel/install-manifest.claude"; fi
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$umhome" --no-hooks
if [ "$(id -u 2>/dev/null)" != 0 ]; then chmod 644 "$umhome/.keel/install-manifest.claude"; fi
um_scratch_b="$(find "$umhome/.keel" -name '.artifacts.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$um_scratch_a" -le 1 ] && [ "$um_scratch_b" -le 1 ]; then
  pass "T12 merge scratch stays bounded at one leftover, never accumulating"
else
  fail "T12 merge scratch stays bounded at one leftover, never accumulating" "run1=$um_scratch_a run2=$um_scratch_b"
fi

# T12b — the other half of the contract: provenance DEGRADES to unavailable rather than misfiring.
# Root-guarded on its own, and for the opposite reason to T12's: a root reader gets a perfectly
# readable manifest here, so the provenance branch legitimately fires for it and this assertion would
# be false for a correct run.
# The whole fixture — baseline install included — sits inside the guard: on the root leg every
# assertion below is skipped, so an unguarded baseline would spend a full install.sh run (and mutate
# the shared fixture checkout) for a claim T10/T11/T12 each already make there.
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  umdrift="$SANDBOX/unreadable-manifest-drift-home"; mkdir -p "$umdrift"
  fresh_home_env "$umdrift"
  run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$umdrift" --no-hooks
  check_status "T12b baseline install → exit 0" 0 "$STATUS"
  printf '\nUNREADABLE-MANIFEST-RELEASE\n' >> "$ckdir/commands/wrap.md"   # would refresh if provenance worked
  chmod 000 "$umdrift/.keel/install-manifest.claude"
  run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$umdrift" --no-hooks
  chmod 644 "$umdrift/.keel/install-manifest.claude"   # restore so cleanup can remove the sandbox
  check_absent "T12b provenance degrades to unavailable, never a misfire" "$OUT" "wrap.md refreshed (Keel's own copy, unedited)"
  check_file "T12b …the drifted command routes to the never-clobber path instead" "$umdrift/commands/keel-wrap.md"
  check_contains "T12b …the install still placed the core that run" "$OUT" "Verify:"
fi

# T13 — the self-equal error sentinel. artifact_cksum yields $CKSUM_UNREADABLE ("cksum:0:0") for a file
# it cannot read, and keel_own_untouched decides provenance by STRING EQUALITY — so a manifest that
# ever recorded that sentinel compared EQUAL to any currently-unreadable dest, and the predicate
# answered "Keel's own unedited copy, refresh it without asking" for a file it could not read one byte
# of: failing OPEN on the rail whose whole job is to fail closed. Root-guarded (chmod 000 is a no-op
# for root, so the dest would simply be readable and the sentinel never produced).
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  senthome="$SANDBOX/cksum-sentinel-home"; mkdir -p "$senthome"
  fresh_home_env "$senthome"
  run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$senthome" --no-hooks
  check_status "T13 baseline install → exit 0" 0 "$STATUS"
  sentman="$senthome/.keel/install-manifest.claude"
  # Plant the sentinel on the PRIOR side — the only construction that makes both sides equal.
  sed 's|^artifact=file	commands/go.md	cksum:.*|artifact=file	commands/go.md	cksum:0:0|' "$sentman" > "$sentman.tmp"
  mv "$sentman.tmp" "$sentman"
  check_contains "T13 the sentinel is planted in the prior manifest" "$(cat "$sentman")" "artifact=file	commands/go.md	cksum:0:0"
  printf '\nSENTINEL-RELEASE\n' >> "$ckdir/commands/go.md"
  sent_before="$(cat "$senthome/commands/go.md")"
  chmod 000 "$senthome/commands/go.md"
  run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$senthome" --no-hooks
  chmod 644 "$senthome/commands/go.md" 2>/dev/null || true
  sent_after="$(cat "$senthome/commands/go.md")"
  # Liveness FIRST: every other assertion here is a check_absent or a content check that holds
  # trivially on a run that died before placing anything, so without this anchor a change making an
  # unreadable dest abort under `set -euo pipefail` — the very defect class finding 2 fixes, on the
  # very path this test walks — would ship with T13 green (proved by injecting an early exit).
  check_contains "T13 the run completed rather than dying on the unreadable dest" "$OUT" "Verify:"
  check_absent "T13 an unreadable dest is never judged Keel's own unedited copy" "$OUT" "go.md refreshed (Keel's own copy, unedited)"
  # Exact equality, NOT check_contains: the "newer release" is $sent_before plus an appended marker,
  # so a fully clobbered dest still CONTAINS $sent_before — a substring check passes under the exact
  # defect it names (proved: it stayed green while its siblings went red under mutation).
  # "content", not "byte for byte": both sides come from $(cat …), which strips trailing newlines, so
  # a trailing-newline-only difference would slip through. The paired SENTINEL-RELEASE absence below
  # covers the real clobber; this pins that nothing else changed.
  check_status "T13 …and its content is left alone, exactly" "$sent_before" "$sent_after"
  check_absent "T13 …so the newer release was not written over it" "$sent_after" "SENTINEL-RELEASE"
fi

# T14 — the retargeting suffix on the linked --force advice. `keel sync` forwards its args verbatim
# and adds nothing (keel:128), so a bare `keel sync --force` becomes `install.sh --force`, whose home
# re-resolves to ${KEEL_HOME:-$HOME/.claude}: following the advised remedy from a `--link --home DIR`
# install built a SECOND Keel at the default home and left the file the message was about untouched.
# Both siblings (advise_install/advise_uninstall) already carried the suffix.
ladvhome="$SANDBOX/link-advice-home"; mkdir -p "$ladvhome/commands"
printf '# my own polish command, never touched by Keel\n' > "$ladvhome/commands/polish.md"
fresh_home_env "$ladvhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --link --home "$ladvhome" --no-hooks
check_status "T14 linked retargeted install → exit 0" 0 "$STATUS"
check_contains "T14 the linked --force advice carries the --home suffix" "$OUT" "keel sync --home \"$ladvhome\" --force"

# T14b — the EPHEMERAL half of the same fix, which had no pin at all: a bootstrap run's checkout is a
# temp clone reaped on exit, so the piped bootstrap form is the adopter's ONLY remaining remedy — the
# mode where an un-retargeted advice string costs the most. KEEL_EPHEMERAL is the env signal
# bootstrap.sh sets (install.sh's header documents it as exactly that internal signal).
eadvhome="$SANDBOX/ephemeral-advice-home"; mkdir -p "$eadvhome/commands"
printf '# my own polish command, never touched by Keel\n' > "$eadvhome/commands/polish.md"
fresh_home_env "$eadvhome"
run env "${FRESH_HOME_ENV[@]}" KEEL_EPHEMERAL=1 "$ckdir/install.sh" --home "$eadvhome" --no-hooks
check_status "T14b ephemeral retargeted install → exit 0" 0 "$STATUS"
check_contains "T14b the ephemeral --force advice carries the --home suffix too" "$OUT" "sh -s -- --home \"$eadvhome\" --force"

# T14c — the Verify WARN for an unwired bin/keel (finding 6) had no test anywhere in the tree: proved
# by mutation that reverting it to the bare-re-run wording left the whole file green. T6 above covers
# the REFUSAL line; this covers the WARN, which is a separate line in the same run — the pair being
# contradictory was the finding. Both must name --force, and neither may advise `keel sync`, which
# dispatches through the very bin/keel both lines report is not wired.
warnhome="$SANDBOX/cli-warn-home"; mkdir -p "$warnhome/bin"
printf '#!/bin/sh\necho not-keel\n' > "$warnhome/bin/keel"
fresh_home_env "$warnhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --link --home "$warnhome" --no-hooks
check_status "T14c linked install over a real-file bin/keel → exit 0" 0 "$STATUS"
check_contains "T14c the Verify WARN fires for the unwired CLI" "$OUT" "keel CLI not wired"
check_contains "T14c …and advises install.sh, reachable without bin/keel" "$OUT" "re-run 'install.sh --home \"$warnhome\"' (add --force"
# The needle carries the CONDITIONAL wording, not just the line's identity: mutation-proved that a
# needle of "is not a Keel symlink" alone leaves a flat `--force` regression green, and a flat --force
# is what aborts the run at force_backup's `cp` when a DIRECTORY sits there.
check_contains "T14c the refusal line names --force conditionally, carving out a directory" "$OUT" "with --force if a real file, not a symlink or a directory, sits there"
# Scoped to the bin/keel lines, NOT the whole output: `keel sync` is the documented linked-mode verb
# (README.md names it), so a whole-output needle would go red the day anyone aligns the linked closing
# summary with that — a failure with nothing to do with this invariant, which the next session would
# have to re-derive. What must hold is narrower: neither line this run prints ABOUT bin/keel may
# advise a command that dispatches through the bin/keel they report is missing.
warn_lines="$(printf '%s\n' "$OUT" | grep -E 'bin/keel|keel CLI not wired' || true)"
check_contains "T14c the scoped needle actually caught both lines" "$warn_lines" "is not a Keel symlink"
check_absent "T14c neither line advises keel sync, which needs the bin/keel they say is missing" "$warn_lines" "keel sync"

# T14e — the DIRECTORY case, which three comments now cite as the whole reason the --force advice is
# CONDITIONAL and which nothing planted until now. force_backup is a plain `cp`: handed a directory it
# fails, and it is called from an `if` body under `set -euo pipefail`, so a flat --force here aborts
# the run mid-sync with the commands already placed. The carve-out is the only thing standing between
# an adopter and that, so it gets a fixture, not just a string match.
dirhome="$SANDBOX/dir-bin-keel-home"; mkdir -p "$dirhome/bin/keel"
printf 'not keel\n' > "$dirhome/bin/keel/something"
fresh_home_env "$dirhome"
run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$dirhome" --no-hooks
check_status "T14e a directory at bin/keel → the plain run still completes" 0 "$STATUS"
check_dir "T14e …the adopter's directory is left untouched" "$dirhome/bin/keel"
check_file "T14e …with its contents intact" "$dirhome/bin/keel/something"
check_contains "T14e …and the advice carves a directory out of --force" "$OUT" "not a symlink or a directory"

# T14d — finding 2's other half, unpinned until now: the degradation must NOT swallow a genuinely
# unwritable \$manifest_dir. That is the deliberate asymmetry of the fix — `cp` sits in the condition
# so an unreadable manifest degrades, while `: > "\$prior_manifest"` stays in the body so a directory
# that cannot be written to still aborts loudly. Without this pin, a later "consistency" cleanup adding
# `|| true` to the second half would silently install over a snapshot that was never created, making
# every Keel-owned file read as foreign. Root-guarded: chmod is a no-op for root.
# The binding assertion is the check_nofile, NOT the exit status: under that exact mutation the run
# still exits 1, because it reaches the merge step and dies writing into the same unwritable dir. So
# the exit code cannot tell the intended abort from the incidental one — do not trim the check_nofile
# as redundant, it is the half that discriminates (measured, not assumed).
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  wrhome="$SANDBOX/unwritable-manifest-dir-home"; mkdir -p "$wrhome/.keel"
  chmod 500 "$wrhome/.keel"
  fresh_home_env "$wrhome"
  run env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$wrhome" --no-hooks
  chmod 700 "$wrhome/.keel"   # restore so cleanup can remove the sandbox
  # Labelled for what it actually binds. The exit status alone does NOT discriminate — under the
  # `|| true` mutation the run still exits 1, later, on the trailing manifest write into the same
  # unwritable dir (measured). The two below are the discriminators: nothing placed, and the run never
  # reached its Verify block, i.e. it died at the snapshot, not at the end.
  check_status "T14d an unwritable .keel dir fails, rather than installing over a missing snapshot" 1 "$STATUS"
  check_nofile "T14d …having placed nothing" "$wrhome/FRAMEWORK.md"
  check_absent "T14d …and having aborted before Verify, i.e. at the snapshot" "$OUT" "Verify:"
fi

# T14f — the `[ -f "$manifest_file" ]` inside that same condition, which is load-bearing and was
# unpinned: it is what confines the snapshot read to a REGULAR file. Without it a FIFO there makes `cp`
# block forever in open(), hanging the installer with nothing placed — a worse failure than the bug the
# condition was introduced to fix, and one a "the cp failure already covers it" simplification would
# reintroduce. Run in the BACKGROUND with a bounded wait on purpose: the suite ships no timeout helper
# and `timeout` is absent on macOS, so a naive foreground version would hang CI instead of failing it.
# The wait is only ever paid in full when the defect is present; the healthy path exits in about a second.
if command -v mkfifo >/dev/null 2>&1; then
  fifohome="$SANDBOX/fifo-manifest-home"; mkdir -p "$fifohome/.keel"
  mkfifo "$fifohome/.keel/install-manifest.claude"
  fresh_home_env "$fifohome"
  env "${FRESH_HOME_ENV[@]}" "$ckdir/install.sh" --home "$fifohome" --no-hooks >/dev/null 2>&1 </dev/null &
  fifo_pid=$!
  fifo_waited=0
  while kill -0 "$fifo_pid" 2>/dev/null && [ "$fifo_waited" -lt 30 ]; do
    sleep 1; fifo_waited=$((fifo_waited + 1))
  done
  if kill -0 "$fifo_pid" 2>/dev/null; then
    kill -9 "$fifo_pid" 2>/dev/null || true
    fail "T14f a FIFO at the manifest path must not hang the install" "still running after ${fifo_waited}s"
  else
    wait "$fifo_pid"; fifo_st=$?
    check_status "T14f a FIFO at the manifest path does not hang the install" 0 "$fifo_st"
    check_file "T14f …and the core is still placed" "$fifohome/FRAMEWORK.md"
  fi
  rm -f "$fifohome/.keel/install-manifest.claude"
else
  pass "T14f mkfifo unavailable — FIFO manifest guard not exercised here"
fi

summary
