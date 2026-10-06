#!/usr/bin/env bash
# dir #692 — a bare quoted `trap '…' EXIT` under `set -e`/`set -u` turned a top-level FATAL shell error
# into exit 0 on bash 3.2 (macOS /bin/bash), in five scripts: tools/delta-audit/derive.sh,
# tools/vendor-review/agy.sh, tools/changelog-section.sh, tools/keel-impact.sh and bootstrap.sh. `$?` is
# already 0 when the trap reads it for that failure class (a `set -u` unbound variable, a `.` of a missing
# file), so a cleanup trap that merely re-`exit`s `$?` still reports success. The fix is the dir #264
# completion-marker idiom already in tools/drydock/inventory.sh, tools/self/line-citations.sh,
# tools/audit-packet/export.sh and import.sh: a marker set only on the script's own legitimate exit-0
# path, so "we got there" is told apart from "something aborted" without trusting `$?`.
#
# The probe, per file: a COPY of the script with a fatal error injected right AFTER its EXIT trap is armed
# (a fault injected before the trap exists would pass vacuously — each anchor is pinned exactly once), run
# on the macOS /bin/bash 3.2 when the host has one besides the PATH bash. alpine's bash 5 may not
# reproduce the original masking — the macOS leg is the binding one — but the assertion (non-zero, and
# never the success output) holds on every bash.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

shells="bash"
[ -x /bin/bash ] && [ "$(command -v bash)" != /bin/bash ] && shells="bash /bin/bash"

# probe_copy LABEL SRC DEST ANCHOR TEXT — a copy of SRC at DEST with TEXT inserted before the (single) line
# containing ANCHOR. The anchor is a line AFTER the EXIT trap in both the bare and the marker shapes.
probe_copy() {
  local label="$1" src="$2" dest="$3" anchor="$4" text="$5"
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  pin_exact "$label: the injection anchor is unique in the script" "$src" "$anchor" "anchor not found exactly once"
  insert_before_line_containing "$dest" "$anchor" "$text"
  chmod +x "$dest"   # the helper rewrites through mv, which drops the exec bit on some platforms
  pin_exact "$label: the fatal-error probe is injected" "$dest" "$text" "injection missing"
}

# A scalar never set anywhere: an unbound-variable abort under `set -u` on every bash (an empty-array
# expansion stopped violating `set -u` at bash 4.4, so it would not reproduce there).
fatal=': "${pl692_never_set_scalar}"'

tree="$SANDBOX/pl692"
mkdir -p "$tree/tools/delta-audit" "$tree/tools/vendor-review"
ln -s "$REPO_ROOT/tools/lib" "$tree/tools/lib"   # derive.sh and keel-impact.sh source ../lib/ and lib/

# --- derive.sh ----------------------------------------------------------------------------------
# A repo with one merged PR, so the legitimate run reaches the closing `exit 0` (closure check passes).
drepo="$(new_repo)"
git -C "$drepo" commit -q --allow-empty -m init
git -C "$drepo" tag v0
git -C "$drepo" checkout -q -b feat
printf 'x\n' > "$drepo/a.txt"; git -C "$drepo" add a.txt; git -C "$drepo" commit -q -m "add a"
git -C "$drepo" checkout -q -
git -C "$drepo" merge -q --no-ff -m "Merge pull request #1 from someorg/feat" feat
derive="$tree/tools/delta-audit/derive.sh"
probe_copy "dir #692 derive.sh" "$REPO_ROOT/tools/delta-audit/derive.sh" "$derive" "# --- delta-files.txt" "$fatal"
for sh in $shells; do
  dout="$SANDBOX/pl692-derive-out-${sh//\//_}"
  run_in "$drepo" "$sh" "$derive" --out "$dout" v0 HEAD
  if [ "$STATUS" -ne 0 ]; then
    pass "dir #692 derive.sh under $sh: a top-level fatal error exits non-zero (status $STATUS)"
  else
    fail "dir #692 derive.sh under $sh: a top-level fatal error exits non-zero" "exit 0 (masked): $OUT"
  fi
  check_nofile "dir #692 derive.sh under $sh: no ledger is written after the fatal error" "$dout/ledger.md"
  # the legitimate path still exits 0 under the marker (an over-eager fix would fail every run)
  run_in "$drepo" "$sh" "$REPO_ROOT/tools/delta-audit/derive.sh" --out "$SANDBOX/pl692-derive-ok-${sh//\//_}" v0 HEAD
  check_status "dir #692 derive.sh under $sh: a real run still exits 0" 0 "$STATUS"
done

# --- agy.sh -------------------------------------------------------------------------------------
# Its own header says its exit code is the proof of success, so a masked fatal is a false "verdict".
agy_stub="$SANDBOX/pl692-agy-stub"
{ printf '#!/usr/bin/env bash\n'; printf "printf '%%s' '{\"status\":\"SUCCESS\",\"response\":\"verdict-from-agy\"}'\n"; } > "$agy_stub"
chmod +x "$agy_stub"
agy_system="$SANDBOX/pl692-system.md"; printf 'system prompt\n' > "$agy_system"
agy_copy="$tree/tools/vendor-review/agy.sh"
probe_copy "dir #692 agy.sh" "$REPO_ROOT/tools/vendor-review/agy.sh" "$agy_copy" "agy_status=0" "$fatal"
for sh in $shells; do
  OUT="$(AGY_BIN="$agy_stub" "$sh" "$agy_copy" --system "$agy_system" 2>&1 <<< "hi")"; STATUS=$?
  if [ "$STATUS" -ne 0 ]; then
    pass "dir #692 agy.sh under $sh: a top-level fatal error exits non-zero (status $STATUS)"
  else
    fail "dir #692 agy.sh under $sh: a top-level fatal error exits non-zero" "exit 0 (masked): $OUT"
  fi
  check_absent "dir #692 agy.sh under $sh: never prints a verdict after the fatal error" "$OUT" "verdict-from-agy"
  OUT="$(AGY_BIN="$agy_stub" "$sh" "$REPO_ROOT/tools/vendor-review/agy.sh" --system "$agy_system" 2>&1 <<< "hi")"; STATUS=$?
  check_status "dir #692 agy.sh under $sh: a real run still exits 0" 0 "$STATUS"
  check_contains "dir #692 agy.sh under $sh: ...and prints the reply" "$OUT" "verdict-from-agy"
done

# --- vendor-review.sh (dir #662, B1) -------------------------------------------------------------
# The orchestrator creates a scratch dir for its leak gate and removes it in an EXIT handler, so it joins
# the same probe: a fatal error injected right after the handler is armed (before the client runs) must
# exit non-zero and never print a round path. A whole tools/ copy: the script resolves the scanner and
# its libs next to itself.
vr_tree="$SANDBOX/pl662-vr"; rm -rf "$vr_tree"; mkdir -p "$vr_tree"; cp -R "$REPO_ROOT/tools" "$vr_tree/tools"
vr_copy="$vr_tree/tools/vendor-review.sh"
probe_copy "dir #662 vendor-review.sh" "$REPO_ROOT/tools/vendor-review.sh" "$vr_copy" "client_status=0" "$fatal"
vr_client="$SANDBOX/pl662-client"; printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "verdict-from-client\\n"\n' > "$vr_client"; chmod +x "$vr_client"
printf 'bundle text\n' > "$SANDBOX/pl662-bundle.md"
for sh in $shells; do
  vout="$SANDBOX/pl662-out-${sh//\//_}"
  run "$sh" "$vr_copy" --client "$vr_client" --system "$agy_system" --bundle "$SANDBOX/pl662-bundle.md" --label probe --out "$vout"
  if [ "$STATUS" -ne 0 ]; then
    pass "dir #662 vendor-review.sh under $sh: a top-level fatal error exits non-zero (status $STATUS)"
  else
    fail "dir #662 vendor-review.sh under $sh: a top-level fatal error exits non-zero" "exit 0 (masked): $OUT"
  fi
  check_absent "dir #662 vendor-review.sh under $sh: never prints a round path after the fatal error" "$OUT" "round-"
  run "$sh" "$REPO_ROOT/tools/vendor-review.sh" --client "$vr_client" --system "$agy_system" --bundle "$SANDBOX/pl662-bundle.md" --label real --out "$vout-ok"
  check_status "dir #662 vendor-review.sh under $sh: a real run still exits 0" 0 "$STATUS"
  check_contains "dir #662 vendor-review.sh under $sh: ...and prints the round path" "$OUT" "round-"
done

# --- changelog-section.sh -----------------------------------------------------------------------
# --edit is the one path that arms the trap (a scratch file for $EDITOR); its normal end is `exit 0`.
csdir="$SANDBOX/pl692-cs"
mkdir -p "$csdir/tools" "$csdir/bin"
cat > "$csdir/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] — 2026-01-01

Real release.

### Added
- the real thing
EOF
printf '#!/bin/sh\nexit 0\n' > "$csdir/bin/editor-noop.sh"; chmod +x "$csdir/bin/editor-noop.sh"
probe_copy "dir #692 changelog-section.sh" "$REPO_ROOT/tools/changelog-section.sh" "$csdir/tools/changelog-section.sh" \
  "A nonzero editor exit doesn't necessarily mean nothing was typed" "$fatal"
cp "$REPO_ROOT/tools/changelog-section.sh" "$csdir/tools/changelog-section-real.sh"
for sh in $shells; do
  notes="$SANDBOX/pl692-notes-${sh//\//_}.md"
  run env "EDITOR=$csdir/bin/editor-noop.sh" "$sh" "$csdir/tools/changelog-section.sh" --edit 1.0.0 "$notes"
  if [ "$STATUS" -ne 0 ]; then
    pass "dir #692 changelog-section.sh under $sh: a top-level fatal error exits non-zero (status $STATUS)"
  else
    fail "dir #692 changelog-section.sh under $sh: a top-level fatal error exits non-zero" "exit 0 (masked): $OUT"
  fi
  check_nofile "dir #692 changelog-section.sh under $sh: no notes file after the fatal error" "$notes"
  run env "EDITOR=$csdir/bin/editor-noop.sh" "$sh" "$csdir/tools/changelog-section-real.sh" --edit 1.0.0 "$notes"
  check_status "dir #692 changelog-section.sh under $sh: a real --edit run still exits 0" 0 "$STATUS"
  check_file "dir #692 changelog-section.sh under $sh: ...and writes the notes file" "$notes"
done

# --- keel-impact.sh -----------------------------------------------------------------------------
# The trap is armed inside _impact_merge_ledger_produce (a function-scoped scratch pair) and cleared by
# its own `trap - EXIT` on the normal path — so the trap FIRING at all means the function did not
# complete. `migrate` of a legacy in-tree ledger is the explicit path into it.
ki_copy="$tree/tools/keel-impact.sh"
probe_copy "dir #692 keel-impact.sh" "$REPO_ROOT/tools/keel-impact.sh" "$ki_copy" 'rows_tmp="$(mktemp)"' "$fatal"
cp "$REPO_ROOT/tools/keel-impact.sh" "$tree/tools/keel-impact-real.sh"
mk_legacy() {
  local d; d="$(new_repo)"; mkdir -p "$d/.keel"
  {
    printf '%s\n%s\n' "# Keel impact ledger" "|date|score|conf|guard|hold|fire|hit|miss|fric|silent|evidence|gap|"
    printf '| 2026-01-01 | 100 | low | 1 | 0 | 0 | 0 | 0 | 0 | 0 | e | none |\n'
  } > "$d/.keel/ledger.md"
  printf '%s' "$d"
}
for sh in $shells; do
  KEEL_IMPACT_STORE="$SANDBOX/pl692-ki-store-${sh//\//_}"; export KEEL_IMPACT_STORE
  lrepo="$(mk_legacy)"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE "$sh" "$ki_copy" migrate "$lrepo"
  if [ "$STATUS" -ne 0 ]; then
    pass "dir #692 keel-impact.sh under $sh: a fatal error inside the armed window exits non-zero (status $STATUS)"
  else
    fail "dir #692 keel-impact.sh under $sh: a fatal error inside the armed window exits non-zero" "exit 0 (masked): $OUT"
  fi
  check_file "dir #692 keel-impact.sh under $sh: the legacy ledger is NOT swept after the fatal error" "$lrepo/.keel/ledger.md"
  lrepo="$(mk_legacy)"
  run env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE "$sh" "$tree/tools/keel-impact-real.sh" migrate "$lrepo"
  check_status "dir #692 keel-impact.sh under $sh: a real migrate still exits 0" 0 "$STATUS"
  check_nofile "dir #692 keel-impact.sh under $sh: ...and sweeps the legacy ledger" "$lrepo/.keel/ledger.md"
done
unset KEEL_IMPACT_STORE

# --- bootstrap.sh -------------------------------------------------------------------------------
# `#!/bin/sh`, so it runs as `sh` (a POSIX-mode bash 3.2 on macOS). The fatal goes in right after the
# copy-mode temp dir is armed, before any clone; its normal end is the install.sh subshell, covered
# end to end by tests/test_install.sh's bootstrap case (exit 0 + files installed).
boot_copy="$tree/bootstrap.sh"
probe_copy "dir #692 bootstrap.sh" "$REPO_ROOT/bootstrap.sh" "$boot_copy" 'src="$tmp/keel"' "$fatal"
sh="sh"   # one shell: bootstrap.sh is a `#!/bin/sh` script, so `sh` is the interpreter that matters (POSIX-mode bash 3.2 on macOS)
run env KEEL_REPO="$REPO_ROOT" "$sh" "$boot_copy" --home "$SANDBOX/pl692-boot-home" --no-hooks
if [ "$STATUS" -ne 0 ]; then
  pass "dir #692 bootstrap.sh under $sh: a top-level fatal error exits non-zero (status $STATUS)"
else
  fail "dir #692 bootstrap.sh under $sh: a top-level fatal error exits non-zero" "exit 0 (masked): $OUT"
fi
check_nofile "dir #692 bootstrap.sh under $sh: nothing was installed after the fatal error" "$SANDBOX/pl692-boot-home/CLAUDE.md"
# the legitimate path still exits 0 under the marker; safe.directory as tests/test_install.sh does (the CI
# alpine leg mounts the repo under another uid, and bootstrap's `git clone` of it would refuse)
git config --global --add safe.directory '*'
run env KEEL_REPO="$REPO_ROOT" "$sh" "$REPO_ROOT/bootstrap.sh" --home "$SANDBOX/pl692-boot-home-ok" --no-hooks
check_status "dir #692 bootstrap.sh under $sh: a real run still exits 0" 0 "$STATUS"
check_file "dir #692 bootstrap.sh under $sh: ...and installs" "$SANDBOX/pl692-boot-home-ok/CLAUDE.md"

# --- the audit: no bare quoted-command EXIT trap is left in the five (only a named handler) -----------
bare="$(grep -nE "^[[:space:]]*trap ['\"].*['\"][[:space:]]+EXIT" \
  "$REPO_ROOT/tools/delta-audit/derive.sh" "$REPO_ROOT/tools/vendor-review/agy.sh" \
  "$REPO_ROOT/tools/changelog-section.sh" "$REPO_ROOT/tools/keel-impact.sh" "$REPO_ROOT/bootstrap.sh" || true)"
check_eq "dir #692: no bare quoted-command EXIT trap in the five scripts" "" "$bare"
bare_vr="$(grep -nE "^[[:space:]]*trap ['\"].*['\"][[:space:]]+EXIT" "$REPO_ROOT/tools/vendor-review.sh" || true)"
check_eq "dir #662: no bare quoted-command EXIT trap in vendor-review.sh" "" "$bare_vr"

summary
