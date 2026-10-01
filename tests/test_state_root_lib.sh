#!/usr/bin/env bash
# tools/lib/state-root.sh — direct unit coverage for dir #637's state-root resolver: keel_state_root
# (B1), keel_store_root with its transition rung (B2), and keel_legacy_store_root (the one spelling of
# the retired address). Spec: docs/specs/637-state-root-home-keel.md A1, A2.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/state-root.sh"
check_file "tools/lib/state-root.sh exists" "$lib"

# sr_run HOME_VALUE|-u SNIPPET [ENV…] — runs SNIPPET in a fresh bash that sources the lib, with HOME
# set (or unset for `-u`) and KEEL_HOME unset unless the caller passes it as an env argument.
sr() {
  local home="$1" snippet="$2"; shift 2
  if [ "$home" = "-u" ]; then
    run env -u HOME -u KEEL_HOME "$@" bash -c ". '$lib'; $snippet"
  else
    run env -u KEEL_HOME HOME="$home" "$@" bash -c ". '$lib'; $snippet"
  fi
}

# --- A1: keel_state_root -------------------------------------------------------------------------
sr /x 'keel_state_root'
check_status "A1: HOME=/x → rc 0" 0 "$STATUS"
check_eq "A1: HOME=/x → /x/.keel, no trailing newline" "/x/.keel" "$OUT"

sr -u 'keel_state_root'
check_status "A1: HOME unset → rc 1" 1 "$STATUS"
check_eq "A1: HOME unset → empty stdout" "" "$OUT"

sr "" 'keel_state_root'
check_status "A1: HOME empty → rc 1" 1 "$STATUS"
check_eq "A1: HOME empty → empty stdout" "" "$OUT"

# --- A2: keel_store_root, every rung ---------------------------------------------------------------
for name in impact read-trace; do
  h="$SANDBOX/a2-$name-a"; mkdir -p "$h"
  sr "$h" "keel_store_root $name"
  check_status "A2(a/$name): no root → rc 0" 0 "$STATUS"
  check_eq "A2(a/$name): no root at all → the new address" "$h/.keel/$name" "$OUT"

  h="$SANDBOX/a2-$name-b"; mkdir -p "$h/.claude/.keel/$name"
  sr "$h" "keel_store_root $name"
  check_eq "A2(b/$name): legacy only → the legacy address (transition rung)" "$h/.claude/.keel/$name" "$OUT"

  h="$SANDBOX/a2-$name-c"; mkdir -p "$h/.claude/.keel/$name" "$h/.keel/$name"
  sr "$h" "keel_store_root $name"
  check_eq "A2(c/$name): both → the new address" "$h/.keel/$name" "$OUT"

  h="$SANDBOX/a2-$name-d"; mkdir -p "$h/real-target" "$h/.keel" "$h/.claude/.keel/$name"
  ln -s "$h/real-target" "$h/.keel/$name"
  sr "$h" "keel_store_root $name"
  check_eq "A2(d/$name): the new root a symlink to a directory → the new address" "$h/.keel/$name" "$OUT"

  h="$SANDBOX/a2-$name-e"; mkdir -p "$h/.claude/.keel"
  ln -s "$h/does-not-exist" "$h/.claude/.keel/$name"
  sr "$h" "keel_store_root $name"
  check_eq "A2(e/$name): a dangling legacy symlink → the new address" "$h/.keel/$name" "$OUT"

  h="$SANDBOX/a2-$name-f"; k="$SANDBOX/a2-$name-f-harness"; mkdir -p "$h" "$k/.keel/$name"
  sr "$h" "keel_store_root $name" KEEL_HOME="$k"
  check_eq "A2(f/$name): KEEL_HOME=\$k with \$k/.keel/$name present → it" "$k/.keel/$name" "$OUT"

  h="$SANDBOX/a2-$name-g"; mkdir -p "$h/.keel/tmp" "$h/.claude/.keel/$name"
  sr "$h" "keel_store_root $name"
  check_eq "A2(g/$name): \$HOME/.keel holds only tmp, legacy present → legacy (the test is per store)" \
    "$h/.claude/.keel/$name" "$OUT"
done

sr "$SANDBOX/a2-h" 'keel_legacy_store_root impact /h'
check_eq "A2(h): keel_legacy_store_root impact /h → /h/.keel/impact" "/h/.keel/impact" "$OUT"

sr "$SANDBOX/a2-h" 'keel_legacy_store_root read-trace'
check_eq "A2(h): default harness home → \$HOME/.claude" "$SANDBOX/a2-h/.claude/.keel/read-trace" "$OUT"

sr "$SANDBOX/a2-h" 'keel_legacy_store_root impact' KEEL_HOME=/k
check_eq "A2(h): KEEL_HOME is the next default" "/k/.keel/impact" "$OUT"

# --- keel_legacy_store_entries: the one definition of "an entry still to move" (dir #637 PR2) -----------
h="$SANDBOX/a2-entries"; mkdir -p "$h/.claude/.keel/impact/-p-one" "$h/.claude/.keel/impact/.dotted" "$h/elsewhere"
printf 'f\n' > "$h/.claude/.keel/impact/stray-file"
ln -s "$h/elsewhere" "$h/.claude/.keel/impact/moved-link"
sr "$h" 'keel_legacy_store_entries impact'
check_status "entries: rc 0" 0 "$STATUS"
check_eq "entries: real directories only, dot-names included, files and links skipped" \
  "$(printf '%s\n%s' "$h/.claude/.keel/impact/-p-one" "$h/.claude/.keel/impact/.dotted")" "$OUT"
sr "$h" 'keel_legacy_store_entries read-trace'
check_eq "entries: an absent store root prints nothing" "" "$OUT"
sr "$h" 'keel_legacy_store_entries impact /nowhere'
check_eq "entries: an explicit harness home that holds nothing prints nothing" "" "$OUT"
sr -u 'keel_legacy_store_entries impact'
check_status "entries: no HOME and no home argument → rc 0, nothing" 0 "$STATUS"
check_eq "entries: ...and no output" "" "$OUT"

sr -u 'keel_store_root impact'
check_status "B2 rung 1: no HOME → rc 1" 1 "$STATUS"
check_eq "B2 rung 1: no HOME → empty stdout" "" "$OUT"

summary
