#!/usr/bin/env bash
# install manifest (dir #125, PR 1/3): install.sh/install-pre-pr-gate.sh write ONE recorded state
# under <home>/.keel/install-manifest.<mode|gate> instead of leaving uninstall/doctor to re-derive it
# heuristically at every site; a checkout-side ledger (<checkout>/.keel/installed-homes) indexes every
# recorded home. This PR is schema + writers + doctor's two new READ-ONLY findings — uninstall does not
# consume the manifest yet (PR 2). Covers acceptance tests A1-A6 + C's new-this-PR half (test 17), plus
# the gate manifest's own write/uninstall path. The ledger-append assertions below (dedup, ephemeral
# skip, prune-on-uninstall) exercise tools/lib/ledger.sh's ledger_append(), shared by both writers.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"
gate_installer="$REPO_ROOT/tools/install-pre-pr-gate.sh"

# manifest_field FILE KEY — the value of a top-level key=value line (first match).
manifest_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1; }

# --- A1: fresh install per mode x layout — manifest exists, fields correct, home= is the resolved
# target, no .keeltmp litter ------------------------------------------------------------------------
run "$install" --no-hooks
check_status "fresh copy install -> exit 0" 0 "$STATUS"
man="$HOME/.claude/.keel/install-manifest.claude"
check_file "copy mode writes install-manifest.claude" "$man"
check_status "manifest_version=1" "1" "$(manifest_field "$man" keel_manifest_version)"
check_status "mode=claude" "claude" "$(manifest_field "$man" mode)"
check_status "layout=copy" "copy" "$(manifest_field "$man" layout)"
check_status "home= is the resolved target" "$HOME/.claude" "$(manifest_field "$man" home)"
check_status "context_file=CLAUDE.md" "CLAUDE.md" "$(manifest_field "$man" context_file)"
check_status "context_created=1" "1" "$(manifest_field "$man" context_created)"
check_status "ephemeral=0 on a kept-checkout run" "0" "$(manifest_field "$man" ephemeral)"
check_contains "records the edit artifact (embedded core block)" "$(cat "$man")" "artifact=edit	CLAUDE.md	core-block"
check_contains "records FRAMEWORK.md with a cksum" "$(cat "$man")" "artifact=file	FRAMEWORK.md	cksum:"
run bash -c "find '$HOME/.claude' -name '*.keeltmp.*'"
check_status "no .keeltmp litter after a fresh install" "" "$OUT"

link_home="$SANDBOX/link-home"; mkdir -p "$link_home"
fresh_home_env "$link_home"
run env "${FRESH_HOME_ENV[@]}" "$install" --link --no-hooks
check_status "fresh link install -> exit 0" 0 "$STATUS"
lman="$link_home/.claude/.keel/install-manifest.claude"
check_status "linked layout=link" "link" "$(manifest_field "$lman" layout)"
check_contains "keel/CORE.md recorded as a symlink" "$(cat "$lman")" "artifact=symlink	keel/CORE.md	-"
check_contains "linked edit artifact is import-line" "$(cat "$lman")" "artifact=edit	CLAUDE.md	import-line"
run bash -c "find '$link_home' -name '*.keeltmp.*'"
check_status "no .keeltmp litter after a fresh link install" "" "$OUT"

# Regression (independent /code-review high pass): a home upgrading straight from a pre-dir-125
# install — keel/README.md already on disk, no manifest ever recorded before — must still get
# README.md into its first-ever manifest. record_placed() was previously only called inside the
# write-once "doesn't exist yet" guard, so it silently and permanently missed this artifact on any
# home where the file already existed at manifest-recording time.
readme_upgrade_home="$SANDBOX/readme-upgrade-home"; mkdir -p "$readme_upgrade_home/keel"
printf '# pre-existing README, not Keel-generated this run\n' > "$readme_upgrade_home/keel/README.md"
fresh_home_env "$readme_upgrade_home"
run env "${FRESH_HOME_ENV[@]}" "$install" --link --no-hooks
check_status "link install over a pre-existing keel/README.md -> exit 0" 0 "$STATUS"
rman="$readme_upgrade_home/.claude/.keel/install-manifest.claude"
check_contains "pre-existing keel/README.md still lands in the first manifest" "$(cat "$rman")" "artifact=file	keel/README.md	cksum:"

nogit_home="$SANDBOX/nogit-home"; mkdir -p "$nogit_home"
fresh_home_env "$nogit_home"
run env "${FRESH_HOME_ENV[@]}" "$install" --link --no-git --no-hooks
check_status "fresh link --no-git install -> exit 0" 0 "$STATUS"
ngman="$nogit_home/.claude/.keel/install-manifest.claude"
check_status "link-nogit layout recorded" "link-nogit" "$(manifest_field "$ngman" layout)"
check_contains "trimmed keel/CORE.md recorded as a file (not a symlink)" "$(cat "$ngman")" "artifact=file	keel/CORE.md	cksum:"

codex_home="$SANDBOX/codex-home"; mkdir -p "$codex_home"
fresh_home_env "$codex_home"
run env "${FRESH_HOME_ENV[@]}" "$install" --codex --no-hooks
check_status "fresh codex install -> exit 0" 0 "$STATUS"
cman="$codex_home/.codex/.keel/install-manifest.codex"
check_file "codex mode writes install-manifest.codex" "$cman"
check_status "codex mode=codex" "codex" "$(manifest_field "$cman" mode)"
check_status "codex context_file=AGENTS.md" "AGENTS.md" "$(manifest_field "$cman" context_file)"

# --- A2: re-run over an up-to-date install, and over a declined drift prompt — the artifact list
# stays COMPLETE (state, not action); a declined-drift file keeps its RECORDED cksum, not a re-derive
# from the now-edited disk bytes -----------------------------------------------------------------------
before_lines="$(grep -c '^artifact=' "$man")"
run "$install" --no-hooks
check_status "up-to-date re-run -> exit 0" 0 "$STATUS"
after_lines="$(grep -c '^artifact=' "$man")"
check_status "up-to-date re-run: artifact count unchanged" "$before_lines" "$after_lines"

old_cksum_line="$(grep '^artifact=file	FRAMEWORK\.md	' "$man")"
printf '\nUSER-EDIT\n' >> "$HOME/.claude/FRAMEWORK.md"
run "$install" --no-hooks </dev/null
check_status "declined-drift re-run -> exit 0" 0 "$STATUS"
check_contains "declined-drift re-run warns FRAMEWORK.md differs" "$OUT" "FRAMEWORK.md differs from Keel's shipped version"
new_cksum_line="$(grep '^artifact=file	FRAMEWORK\.md	' "$man")"
check_status "declined-drift: FRAMEWORK.md still listed, RECORDED cksum unchanged (not the user's edited bytes)" "$old_cksum_line" "$new_cksum_line"

# --- A3: a foreign (pre-existing, non-Keel) context file — context_created=0, no edit artifact --------
fhome="$SANDBOX/foreign-core"; mkdir -p "$fhome"
printf '# My own global notes\nnothing keel here\n' > "$fhome/CLAUDE.md"
run "$install" --home "$fhome" --no-hooks
check_status "foreign-core install -> exit 0" 0 "$STATUS"
fman="$fhome/.keel/install-manifest.claude"
check_file "foreign-core install still writes a manifest" "$fman"
check_status "foreign-core: context_created=0" "0" "$(manifest_field "$fman" context_created)"
check_absent "foreign-core: no edit artifact recorded" "$(cat "$fman")" "artifact=edit"

# --- A4: an ephemeral (bootstrap temp-clone) run — manifest carries ephemeral=1, NO ledger write ------
ehome="$SANDBOX/ephemeral-home"; mkdir -p "$ehome"
ledger="$KEEL_LEDGER_FILE"
ledger_before="$(cat "$ledger" 2>/dev/null || true)"
run env KEEL_EPHEMERAL=1 "$install" --home "$ehome" --no-hooks
check_status "ephemeral run -> exit 0" 0 "$STATUS"
eman="$ehome/.keel/install-manifest.claude"
check_status "ephemeral: manifest carries ephemeral=1" "1" "$(manifest_field "$eman" ephemeral)"
ledger_after="$(cat "$ledger" 2>/dev/null || true)"
check_status "ephemeral run does not append to the ledger" "$ledger_before" "$ledger_after"
check_absent "ephemeral run's home never reaches the ledger" "$ledger_after" "$ehome"

# --- A5: --home "" / a flag-shaped --home DIR are refused before any write ----------------------------
nohome_before="$(find "$HOME/.claude/.keel" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
run "$install" --home ""
check_status "--home '' -> nonzero exit, refused" 1 "$STATUS"
run "$install" --home -x
check_status "--home -x (flag-shaped) -> exit 2, refused" 2 "$STATUS"
check_contains "flag-shaped --home names the offending flag" "$OUT" "-x"
nohome_after="$(find "$HOME/.claude/.keel" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
check_status "refused --home writes nothing new to the default home's manifest dir" "$nohome_before" "$nohome_after"

# --- A6 / test 6: the checkout-side ledger is gitignored ------------------------------------------
# A fresh throwaway repo carrying a COPY of the real .gitignore — never the live checkout directly,
# which can carry its own local (untracked) .git/info/exclude on a dev machine and give a false read
# either way; this isolates the assertion to the TRACKED pattern (same idiom test_keel_impact.sh uses).
girepo="$(new_repo)"
cp "$REPO_ROOT/.gitignore" "$girepo/.gitignore"
mkdir -p "$girepo/.keel"
: > "$girepo/.keel/installed-homes"
: > "$girepo/.keel/ledger.md"
run git -C "$girepo" check-ignore -q .keel/installed-homes
check_status "git check-ignore: .keel/installed-homes is ignored" 0 "$STATUS"
run git -C "$girepo" check-ignore -q .keel/ledger.md
check_status "git check-ignore: .keel/ledger.md stays trackable (not ignored)" 1 "$STATUS"

# --- gate manifest: install-pre-pr-gate.sh --global/--home writes+removes install-manifest.gate,
# project scope writes neither, and the ledger is shared with install.sh's own -----------------------
if command -v jq >/dev/null 2>&1; then
  ghome="$SANDBOX/gate-home"; mkdir -p "$ghome"
  fresh_home_env "$ghome"
  run env "${FRESH_HOME_ENV[@]}" "$gate_installer" --global
  check_status "gate --global wire -> exit 0" 0 "$STATUS"
  gman="$ghome/.claude/.keel/install-manifest.gate"
  check_file "gate --global writes install-manifest.gate" "$gman"
  check_status "gate manifest kind=gate" "gate" "$(manifest_field "$gman" kind)"
  check_status "gate manifest settings= points at the wired settings.json" "$ghome/.claude/settings.json" "$(manifest_field "$gman" settings)"
  check_contains "gate ledger entry recorded" "$(cat "$ledger" 2>/dev/null)" "$ghome/.claude"

  repo="$(new_repo)"
  run "$gate_installer" "$repo"
  check_status "gate project-scope wire -> exit 0" 0 "$STATUS"
  check_nofile "project scope writes no gate manifest" "$repo/.keel/install-manifest.gate"

  run env "${FRESH_HOME_ENV[@]}" "$gate_installer" --global --uninstall
  check_status "gate --global uninstall -> exit 0" 0 "$STATUS"
  check_nofile "gate uninstall removes install-manifest.gate" "$gman"
  check_absent "gate uninstall prunes the ledger entry" "$(cat "$ledger" 2>/dev/null)" "$ghome/.claude"

  # --- acceptance test 19: --uninstall removes the gate manifest only when n_removed > 0 -------------
  # A hand-stripped settings.json (hooks already gone, e.g. removed by hand outside this installer)
  # leaves nothing for --uninstall to remove — the manifest must survive, since it wasn't THIS run that
  # took the hooks down.
  g2home="$SANDBOX/gate-home-2"; mkdir -p "$g2home"
  fresh_home_env "$g2home"
  run env "${FRESH_HOME_ENV[@]}" "$gate_installer" --global
  check_status "g2 gate --global wire -> exit 0" 0 "$STATUS"
  g2man="$g2home/.claude/.keel/install-manifest.gate"
  check_file "g2 gate manifest recorded" "$g2man"
  printf '{}' > "$g2home/.claude/settings.json"   # simulate hooks stripped by hand
  run env "${FRESH_HOME_ENV[@]}" "$gate_installer" --global --uninstall
  check_status "g2 uninstall with nothing to remove -> exit 0" 0 "$STATUS"
  check_contains "g2 uninstall reports nothing removed (n_removed=0)" "$OUT" "nothing to remove"
  check_file "g2 manifest survives an n_removed=0 uninstall" "$g2man"
else
  pass "jq not available — gate manifest tests skipped (installer requires jq)"
fi

# --- C17: doctor's two new read-only findings ----------------------------------------------------
dhome="$SANDBOX/doctor-home"; mkdir -p "$dhome"
run "$install" --home "$dhome" --no-hooks
check_status "doctor fixture install -> exit 0" 0 "$STATUS"

# C15 regression: a healthy manifested install is clean — no false W-MANIFEST-* noise.
run "$doctor" --install "$dhome"
check_absent "healthy manifested install: no W-MANIFEST-MISSING" "$OUT" "W-MANIFEST-MISSING"
check_absent "healthy manifested install: no W-MANIFEST-DRIFT" "$OUT" "W-MANIFEST-DRIFT"

# Regression (independent /code-review high pass): a cosmetic difference between the raw --install
# argument and the manifest's own canonical home= (a trailing slash is the ordinary trigger — shell
# tab-completion on a dir routinely appends one) must NOT false-fire W-MANIFEST-DRIFT.
run "$doctor" --install "$dhome/"
check_absent "trailing-slash home: no false W-MANIFEST-DRIFT" "$OUT" "W-MANIFEST-DRIFT"

dman="$dhome/.keel/install-manifest.claude"
mv "$dman" "$dman.aside"
run "$doctor" --install "$dhome"
check_contains "no manifest -> W-MANIFEST-MISSING" "$OUT" "W-MANIFEST-MISSING"
check_contains "W-MANIFEST-MISSING advice carries the home flag (self/doctor check 1c)" "$OUT" "--home \"$dhome\""
mv "$dman.aside" "$dman"

cp "$dman" "$dman.orig"
sed 's/^layout=copy/layout=link/' "$dman.orig" > "$dman"
mkdir -p "$dhome/keel"
printf 'not a symlink\n' > "$dhome/keel/CORE.md"
run "$doctor" --install "$dhome"
check_contains "layout says link but keel/CORE.md is a plain file -> W-MANIFEST-DRIFT" "$OUT" "W-MANIFEST-DRIFT"
check_contains "W-MANIFEST-DRIFT advice carries the home flag" "$OUT" "--home \"$dhome\""
rm -rf "$dhome/keel"
mv "$dman.orig" "$dman"

cp "$dman" "$dman.orig"
sed 's/^keel_manifest_version=1/keel_manifest_version=99/' "$dman.orig" > "$dman"
run "$doctor" --install "$dhome"
check_contains "unknown manifest version -> treated as absent (W-MANIFEST-MISSING)" "$OUT" "W-MANIFEST-MISSING"
mv "$dman.orig" "$dman"

# Regression (independent /code-review high pass): an EXISTING but unreadable manifest must degrade
# to "treated as absent" (a WARN + full summary), never abort the whole audit under set -euo
# pipefail and silently drop every finding already buffered for this unit. Skipped as root (chmod 000
# is a no-op for the root reader — the project's own documented Alpine trap).
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  chmod 000 "$dman"
  run "$doctor" --install "$dhome"
  chmod 644 "$dman"   # restore so cleanup can remove the sandbox
  check_contains "unreadable manifest degrades to absent, not a crash" "$OUT" "W-MANIFEST-MISSING"
  check_contains "unreadable manifest: the run still prints its summary line" "$OUT" "doctor:"
fi

# --- acceptance test 21 (gate side): corrupt/unknown-version/unreadable GATE manifest degrades to
# absent — named warning + legacy fallback, exit behavior unchanged, no set -euo pipefail crash --------
if command -v jq >/dev/null 2>&1; then
  g21home="$SANDBOX/gate-home-21/.claude"
  run "$install" --home "$g21home" --no-hooks
  check_status "g21 install -> exit 0" 0 "$STATUS"
  run env KEEL_HOME="$g21home" "$gate_installer" --global
  check_status "g21 gate wire -> exit 0" 0 "$STATUS"
  g21man="$g21home/.keel/install-manifest.gate"
  check_file "g21 gate manifest recorded" "$g21man"

  cp "$g21man" "$g21man.orig"
  sed 's/^keel_manifest_version=1/keel_manifest_version=99/' "$g21man.orig" > "$g21man"
  run "$doctor" --install "$g21home"
  check_contains "unknown gate-manifest version -> treated as absent, still OK (hooks really are there)" "$OUT" "OK   /polish gate: wired machine-global"
  check_contains "...and nudges a re-record (dir #150: kept, deterministic default path)" "$OUT" "W-GATE-MANIFEST-MISSING"
  mv "$g21man.orig" "$g21man"

  if [ "$(id -u 2>/dev/null)" != 0 ]; then
    chmod 000 "$g21man"
    run "$doctor" --install "$g21home"
    chmod 644 "$g21man"   # restore so cleanup can remove the sandbox
    check_contains "unreadable gate manifest degrades to absent, not a crash" "$OUT" "W-GATE-MANIFEST-MISSING"
    check_contains "unreadable gate manifest: the run still prints its summary line" "$OUT" "doctor:"
  fi
else
  pass "jq not available — gate manifest robustness tests skipped (installer requires jq)"
fi

# --- acceptance test 20: the KEEL-LEGACY-NOMANIFEST token is gone from every consumer dir #125 marked
# (dir #150, 0.7) — inverted from the old "must still carry it" check (which made the eventual removal
# sweep mechanical) into "must no longer carry it", now that the sweep has actually run. A deliberately
# KEPT fallback (tools/pre-pr-gate.sh's project-scope candidates, doctor.sh's/uninstall.sh's
# deterministic gate-settings default path — see their own dir #150 comments for why) is not tagged
# with this token any more either: it was never a multi-candidate guess in those cases, just mistakenly
# swept into the original "every consumer" list -------------------------------------------------------
legacy_sites="$REPO_ROOT/uninstall.sh $REPO_ROOT/tools/doctor.sh $REPO_ROOT/tools/pre-pr-gate.sh $REPO_ROOT/keel $REPO_ROOT/install.sh"
for site in $legacy_sites; do
  if grep -q 'KEEL-LEGACY-NOMANIFEST' "$site"; then
    fail "legacy sweep: $site no longer carries the KEEL-LEGACY-NOMANIFEST token" "still present"
  else
    pass "legacy sweep: $site no longer carries the KEEL-LEGACY-NOMANIFEST token"
  fi
done

summary
