#!/usr/bin/env bash
# test_safe_write_installers.sh — the installer-level half of tools/lib/safe-write.sh's second round
# (docs/specs/685-symlink-policy.md round 2, slice S5a; dir #756 (a)(c)(d), dir #755, dir #748 audit S5-1,
# S5-2, S6-3). tests/test_safe_write.sh covers the lib's own contract; this file drives the installers
# that call it:
#   - Keel's own state files (the install manifest, the foreign-core marker, the gate manifest, the
#     ledger) are STATE writes: a hard link is split, so the run records what it placed and exits 0;
#   - a backup and the write it guards are one call: a refused write leaves no orphan backup;
#   - an all-SAME hook run does not rewrite settings.json;
#   - the manifest body carries its own status;
#   - linked mode's import line is an EDIT: idempotent across cycles (its refusal into the checkout,
#     audit S5-2, runs in tests/test_safe_write.sh, beside the scratch checkout it needs).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"
# shellcheck source=tools/lib/stat-portable.sh
. "$REPO_ROOT/tools/lib/stat-portable.sh"

# bak_count DIR NAME — backups of NAME directly in DIR.
bak_count() { find "$1" -maxdepth 1 -name "$2.*.bak" 2>/dev/null | grep -c . || true; }

# --- A29: a hard-linked install manifest is split, not refused -----------------------------------------
h="$SANDBOX/a29/h"; out="$SANDBOX/a29/outside-manifest"
run "$install" --home "$h" --no-hooks
check_status "A29 fixture: install → exit 0" 0 "$STATUS"
ln "$h/.keel/install-manifest.claude" "$out"
old="$(cksum < "$out")"
rm -f "$h/docs/delegation.md"
run "$install" --home "$h" --no-hooks
check_status "A29 a re-run over a hard-linked manifest → exit 0" 0 "$STATUS"
check_contains "A29 …the removed doc is placed again" "$OUT" "delegation.md"
check_status "A29 …and recorded in the new manifest" 1 \
  "$(grep -c "	docs/delegation.md	" "$h/.keel/install-manifest.claude" || true)"
check_eq "A29 …the outside name still holds the old bytes" "$old" "$(cksum < "$out")"
run test "$h/.keel/install-manifest.claude" -ef "$out"
check_status "A29 …the hard link is split" 1 "$STATUS"
check_nodir "A29 …no lock is left" "$h/.install.lock"
run "$uninstall" --home "$h" --yes
check_status "A29 round trip: uninstall → exit 0" 0 "$STATUS"
run "$install" --home "$h" --no-hooks
check_status "A29 round trip: install again → exit 0" 0 "$STATUS"

# the foreign-core marker (copy mode, a foreign CLAUDE.md) — a FIFO there cannot tell STATE from a strict
# EDIT, so this row hard-links it.
h="$SANDBOX/a29m/h"; out="$SANDBOX/a29m/outside-marker"; mkdir -p "$h"
printf '# my own CLAUDE.md\n' > "$h/CLAUDE.md"
run "$install" --home "$h" --no-hooks
check_status "A29 marker fixture: copy install over a foreign CLAUDE.md → exit 0" 0 "$STATUS"
check_file "A29 marker fixture: the foreign-core marker is written" "$h/.keel/foreign-core.claude"
ln "$h/.keel/foreign-core.claude" "$out"
ino="$(inode_of "$out")"
run "$install" --home "$h" --no-hooks
check_status "A29 a re-run over a hard-linked foreign-core marker → exit 0" 0 "$STATUS"
check_eq "A29 …the outside name keeps its old inode" "$ino" "$(inode_of "$out")"
check_ne "A29 …the marker is a new file" "$ino" "$(inode_of "$h/.keel/foreign-core.claude")"
check_nodir "A29 …no lock is left" "$h/.install.lock"

# the ledger, pruned by uninstall (ledger_remove).
h="$SANDBOX/a29l/h"; led="$SANDBOX/a29l/ledger"; out="$SANDBOX/a29l/outside-ledger"
run env KEEL_LEDGER_FILE="$led" "$install" --home "$h" --no-hooks
check_status "A29 ledger fixture: install → exit 0" 0 "$STATUS"
check_eq "A29 ledger fixture: the ledger lists the home" 1 "$(grep -c . "$led" 2>/dev/null || true)"
ln "$led" "$out"
old="$(cksum < "$out")"
run env KEEL_LEDGER_FILE="$led" "$uninstall" --home "$h" --yes
check_status "A29 uninstall prunes a hard-linked ledger → exit 0" 0 "$STATUS"
check_eq "A29 …the ledger no longer lists the home" 0 "$(grep -c . "$led" 2>/dev/null || true)"
check_eq "A29 …the outside name still holds the old bytes" "$old" "$(cksum < "$out")"

# the gate's manifest (install-pre-pr-gate.sh --home).
if command -v jq >/dev/null 2>&1; then
  h="$SANDBOX/a29g/h"; out="$SANDBOX/a29g/outside-gate"; mkdir -p "$h"
  run "$REPO_ROOT/tools/install-pre-pr-gate.sh" --home "$h"
  check_status "A29 gate fixture: wire --home → exit 0" 0 "$STATUS"
  ln "$h/.keel/install-manifest.gate" "$out"
  old="$(cksum < "$out")"
  run "$REPO_ROOT/tools/install-pre-pr-gate.sh" --home "$h"
  check_status "A29 a gate re-run over a hard-linked gate manifest → exit 0" 0 "$STATUS"
  check_eq "A29 …the outside name still holds the old bytes" "$old" "$(cksum < "$out")"
  run test "$h/.keel/install-manifest.gate" -ef "$out"
  check_status "A29 …the hard link is split" 1 "$STATUS"
fi

# --- A30: a symlinked 0600 manifest is written through (a guard) ---------------------------------------
h="$SANDBOX/a30/h"; dots="$SANDBOX/a30/dots"; mkdir -p "$dots"
run "$install" --home "$h" --no-hooks
check_status "A30 fixture: install → exit 0" 0 "$STATUS"
mv "$h/.keel/install-manifest.claude" "$dots/manifest"; chmod 600 "$dots/manifest"
ln -s "$dots/manifest" "$h/.keel/install-manifest.claude"
rm -f "$h/docs/delegation.md"
run "$install" --home "$h" --no-hooks
check_status "A30 a re-run over a symlinked 0600 manifest → exit 0" 0 "$STATUS"
check_link "A30 …the manifest link is kept" "$h/.keel/install-manifest.claude"
check_eq "A30 …the file it names is still 0600" 600 "$(stat_portable_mode "$dots/manifest")"
check_status "A30 …and holds this run's records" 1 "$(grep -c "	docs/delegation.md	" "$dots/manifest" || true)"

# --- A36: a block refresh answered y over a hard-linked target takes no backup --------------------------
if command -v script >/dev/null 2>&1; then
  h="$SANDBOX/a36/h"; dots="$SANDBOX/a36/dots"; mkdir -p "$dots"
  run "$install" --home "$h" --no-hooks
  check_status "A36 fixture: install → exit 0" 0 "$STATUS"
  mv "$h/CLAUDE.md" "$dots/CLAUDE.md"
  sed 's/## Precedence — when sources conflict/## Precedence — MY EDITED RAIL/' "$dots/CLAUDE.md" > "$dots/c.new"
  mv "$dots/c.new" "$dots/CLAUDE.md"
  ln "$dots/CLAUDE.md" "$dots/CLAUDE.other.md"
  ln -s "$dots/CLAUDE.md" "$h/CLAUDE.md"
  tty_run y "$install" --home "$h" --no-hooks
  check_status "A36 a refresh answered y over a hard-linked target → exit 0" 0 "$STATUS"
  check_contains "A36 …left untouched" "$OUT" "left untouched"
  check_eq "A36 …no CLAUDE.md backup beside the link" 0 "$(bak_count "$h" CLAUDE.md)"
  check_eq "A36 …and none beside its target" 0 "$(bak_count "$dots" CLAUDE.md)"
  check_absent "A36 …no backup is announced" "$OUT" "backed up"
else
  pass "A36 skipped — no \`script\` on this platform"
fi

# --- A37 + A46: the three hook installers over a hard-linked settings.json ------------------------------
if command -v jq >/dev/null 2>&1; then
  for inst in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
    tool="$REPO_ROOT/tools/$inst"
    h="$SANDBOX/a37-$inst/h"; mkdir -p "$h"
    run "$tool" --home "$h"
    check_status "A37 $inst fixture: wire --home → exit 0" 0 "$STATUS"
    s="$h/settings.json"
    ln "$s" "$h/settings.other"
    ino="$(inode_of "$s")"; old="$(cksum < "$s")"

    # A46: a no-op re-run writes nothing.
    run "$tool" --home "$h"
    check_status "A46 $inst no-op re-run over a hard-linked settings.json → exit 0" 0 "$STATUS"
    check_contains "A46 …still prints its already-wired lines" "$OUT" "already wired"
    check_eq "A46 …settings.json keeps its inode" "$ino" "$(inode_of "$s")"
    check_eq "A46 …and its bytes" "$old" "$(cksum < "$s")"
    check_eq "A46 …no backup is taken" 0 "$(bak_count "$h" settings.json)"

    # A37 (2): a merge run that has something to write — --force over a STALE path.
    stale="$(sed "s|$REPO_ROOT/tools/|/moved/keel/tools/|g" "$s")"
    printf '%s\n' "$stale" > "$s"   # `>` keeps the inode: the hard link survives the edit
    run "$tool" --home "$h" --force
    check_status "A37 $inst --force over a STALE path, hard-linked → exit 1" 1 "$STATUS"
    check_contains "A37 …the lib's one line names the hard link" "$OUT" "hard link"
    check_eq "A37 …no orphan backup" 0 "$(bak_count "$h" settings.json)"
    check_absent "A37 …no backup is announced" "$OUT" "backed up"
  done

  # A37 (1): --uninstall on a wired, hard-linked settings.json (the STALE edit above left nothing of ours
  # to remove, and a run with nothing to remove exits 0 before any write).
  for inst in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
    tool="$REPO_ROOT/tools/$inst"
    h="$SANDBOX/a37u-$inst/h"; mkdir -p "$h"
    run "$tool" --home "$h"
    check_status "A37 $inst --uninstall fixture: wire → exit 0" 0 "$STATUS"
    ln "$h/settings.json" "$h/settings.other"
    run "$tool" --home "$h" --uninstall
    check_status "A37 $inst --uninstall over a hard-linked settings.json → exit 1" 1 "$STATUS"
    check_contains "A37 …the lib's one line names the hard link" "$OUT" "hard link"
    check_eq "A37 …no orphan backup" 0 "$(bak_count "$h" settings.json)"
    check_absent "A37 …no backup is announced" "$OUT" "backed up"
  done

  # A46 sub-case: the all-SAME re-run still writes the gate manifest.
  h="$SANDBOX/a46g/h"; mkdir -p "$h"
  run "$REPO_ROOT/tools/install-pre-pr-gate.sh" --home "$h"
  check_status "A46 gate fixture: wire --home → exit 0" 0 "$STATUS"
  rm -f "$h/.keel/install-manifest.gate"
  run "$REPO_ROOT/tools/install-pre-pr-gate.sh" --home "$h"
  check_status "A46 an all-SAME gate re-run → exit 0" 0 "$STATUS"
  check_file "A46 …the gate manifest is back" "$h/.keel/install-manifest.gate"
else
  pass "A37/A46 skipped — no jq (the hook installers need it to edit settings.json)"
fi

# A37 structural: no two-call backup-then-write is left in the three installers.
a37="$(git -C "$REPO_ROOT" grep -n 'hook_install_backup "' -- tools/install-read-trace.sh \
  tools/install-pre-pr-gate.sh tools/install-machine-watch.sh || true)"
check_eq "A37 no hook_install_backup call remains in the three installers" "" "$a37"

# --- A45: manifest_body carries its own status ----------------------------------------------------------
body="$(awk '/^manifest_body\(\) \{/,/^\}/' "$install")"
check_ne "A45 fixture: manifest_body is extracted from install.sh" "" "$body"
run bash -c "
  $body
  _n_echo=0; _n_printf=0
  echo()   { _n_echo=\$((_n_echo + 1));     [ \"\$_n_echo\" -gt 1 ]   && builtin echo \"\$@\"; }
  printf() { _n_printf=\$((_n_printf + 1)); [ \"\$_n_printf\" -gt 1 ] && builtin printf \"\$@\"; }
  manifest_mode=claude manifest_layout=copy home_resolved=/h CONTEXT_FILE=CLAUDE.md context_created=1
  root=/ck EPHEMERAL=0 keel_version=v0 installed_at=now edit_kind=edit edit_extra=core-block
  manifest_artifact_lines=('artifact=file	docs/x.md	1 2')
  manifest_body >/dev/null
"
check_ne "A45 manifest_body whose first output call fails → non-zero" 0 "$STATUS"

# --- A47: the import line is an EDIT ---------------------------------------------------------------------
h="$SANDBOX/a47/h"; mkdir -p "$h"
printf '# mine\nline\n' > "$h/CLAUDE.md"
sizes=""
for cycle in 1 2 3; do
  run "$install" --link --home "$h" --no-hooks
  check_status "A47 cycle $cycle: linked install → exit 0" 0 "$STATUS"
  run "$uninstall" --home "$h" --yes
  check_status "A47 cycle $cycle: uninstall → exit 0" 0 "$STATUS"
  [ "$cycle" = 1 ] && after1="$(cksum < "$h/CLAUDE.md")"
  sizes="$sizes $(wc -c < "$h/CLAUDE.md" | tr -d ' ')"
done
check_eq "A47 three link-mode cycles leave CLAUDE.md as cycle 1 left it (bytes:$sizes)" "$after1" "$(cksum < "$h/CLAUDE.md")"
# K42a: no final newline — a newline first, then the import on a line of its own.
h="$SANDBOX/a47k/h"; mkdir -p "$h"
printf '# mine\nline' > "$h/CLAUDE.md"
run "$install" --link --home "$h" --no-hooks
check_status "A47/K42a linked install over a CLAUDE.md with no final newline → exit 0" 0 "$STATUS"
check_eq "A47/K42a …the user's last line is intact" line "$(sed -n 2p "$h/CLAUDE.md")"
check_eq "A47/K42a …the import is on a line of its own" 1 "$(grep -c '^@.*keel/CORE\.md$' "$h/CLAUDE.md" || true)"

summary
