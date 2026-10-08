#!/usr/bin/env bash
# test_core_marker_anchor.sh — dir #716 (docs/specs/685-symlink-policy.md slice 2, B12): the in-file Keel
# region has ONE anchored definition (tools/lib/core-ownership.sh) for every reader, writer and presence
# check. A BEGIN line starts at column 0 with `<!-- KEEL-CORE-BEGIN` and ends with `-->`; the END line is
# `<!-- KEEL-CORE-END -->`. A user's prose line that merely MENTIONS the marker is not a marker: the
# uninstall strip and the refresh used to delete every user line after it (S5-4). A file with two blocks,
# or a BEGIN without an END, is left byte-identical by every write that touches the block (A22).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# fresh_home NAME [install args…] — a fresh install into $SANDBOX/NAME; prints the home.
fresh_home() {
  local h="$SANDBOX/$1"; shift
  run "$install" "$@" --home "$h" --no-hooks
  [ "$STATUS" = 0 ] || echo "fixture install failed: $OUT" >&2
  printf '%s' "$h"
}
# alter_block FILE — change one line INSIDE the KEEL-CORE block (an older release, or an edit).
alter_block() { sed 's/## Precedence — when sources conflict/## Precedence — MY EDITED RAIL/' "$1" > "$1.new" && mv "$1.new" "$1"; }
# real_markers FILE — count of anchored marker lines (BEGIN or END) in FILE.
real_markers() { grep -c -E '^<!-- KEEL-CORE-(BEGIN.*-->|END -->)[[:space:]]*$' "$1" || true; }

prose='Note to self: never hand-edit anything between the KEEL-CORE-BEGIN and KEEL-CORE-END markers.'

# --- A21: uninstall keeps every user line after a prose mention, strips only the real block -------------
h="$(fresh_home a21-uninstall)"
printf '\n%s\nUSER-LINE-AFTER-PROSE\n' "$prose" >> "$h/CLAUDE.md"
run "$uninstall" --home "$h" --yes
check_status "A21 uninstall: exits 0" 0 "$STATUS"
check_contains "A21 uninstall: the prose mention survives" "$(cat "$h/CLAUDE.md")" "$prose"
check_contains "A21 uninstall: the user line AFTER the prose mention survives" "$(cat "$h/CLAUDE.md")" "USER-LINE-AFTER-PROSE"
check_eq "A21 uninstall: the real block is gone (no anchored marker line left)" 0 "$(real_markers "$h/CLAUDE.md")"
check_absent "A21 uninstall: …and so is its content" "$(cat "$h/CLAUDE.md")" "Precedence"

# A prose mention ABOVE the real block, with user lines between — the strip must start at the real BEGIN.
h="$(fresh_home a21-uninstall-above)"
{ printf '%s\nUSER-BETWEEN-ABOVE\n\n' "$prose"; cat "$h/CLAUDE.md"; } > "$h/CLAUDE.md.new" && mv "$h/CLAUDE.md.new" "$h/CLAUDE.md"
run "$uninstall" --home "$h" --yes
check_contains "A21 uninstall (prose above): the prose line survives" "$(cat "$h/CLAUDE.md")" "$prose"
check_contains "A21 uninstall (prose above): the lines between the prose and the block survive" "$(cat "$h/CLAUDE.md")" "USER-BETWEEN-ABOVE"
check_eq "A21 uninstall (prose above): the real block is gone" 0 "$(real_markers "$h/CLAUDE.md")"

# --- A21: a refresh `y` keeps the prose line and the lines between, refreshes only the real block -------
tty_run() {   # tty_run ANSWER CMD… → OUT, STATUS (merged stdout, pty-echoed)
  local ans="$1"; shift
  case "$(uname -s)" in
    Darwin) OUT="$(script -q /dev/null "$@" < <(printf '%s\n' "$ans"; sleep 5) 2>&1)"; STATUS=$? ;;
    *)      OUT="$(script -qc "$*" /dev/null < <(printf '%s\n' "$ans"; sleep 5) 2>&1)"; STATUS=$? ;;
  esac
}
if ! command -v script >/dev/null 2>&1; then
  printf '  SKIP  A21 refresh: no `script` binary on this host — the tty branch is not exercised here\n'
else
  h="$(fresh_home a21-refresh)"
  alter_block "$h/CLAUDE.md"
  { printf '%s\nUSER-BETWEEN-REFRESH\n\n' "$prose"; cat "$h/CLAUDE.md"; } > "$h/CLAUDE.md.new" && mv "$h/CLAUDE.md.new" "$h/CLAUDE.md"
  tty_run y "$install" --home "$h" --no-hooks
  check_contains "A21 refresh: the offer was shown and answered" "$OUT" "core block refreshed"
  check_contains "A21 refresh: the prose line survives" "$(cat "$h/CLAUDE.md")" "$prose"
  check_contains "A21 refresh: the user line between survives" "$(cat "$h/CLAUDE.md")" "USER-BETWEEN-REFRESH"
  check_absent "A21 refresh: the edited rail is gone (the real block was refreshed)" "$(cat "$h/CLAUDE.md")" "MY EDITED RAIL"
  check_eq "A21 refresh: exactly one BEGIN and one END marker line remain" 2 "$(real_markers "$h/CLAUDE.md")"
fi

# --- A21 presence: linked mode, a CLAUDE.md whose only mention of the marker is prose -------------------
h="$SANDBOX/a21-presence"; mkdir -p "$h"
printf '# My notes\n%s\nUSER-LINE-PRESENCE\n' "$prose" > "$h/CLAUDE.md"
run "$install" --link --home "$h" --no-hooks
check_status "A21 presence: linked install exits 0" 0 "$STATUS"
check_contains "A21 presence: the import line is appended" "$OUT" "appended the Keel core import line"
check_contains "A21 presence: …and is in the file" "$(cat "$h/CLAUDE.md")" "keel/CORE.md"
check_absent "A21 presence: no migration prompt or 'differs' warning for a prose mention" "$OUT" "embeds rails that differ"
check_contains "A21 presence: the user's prose survives" "$(cat "$h/CLAUDE.md")" "USER-LINE-PRESENCE"
# …and doctor's presence check uses the same definition: a linked home (import line present) whose file
# also carries a prose mention is NOT a double-loaded rails block.
h="$(fresh_home a21-doctor --link)"
printf '\n%s\n' "$prose" >> "$h/CLAUDE.md"
run "$doctor" --install "$h"
check_absent "A21 presence: doctor gives no W-RAILS-DOUBLE for a prose mention" "$OUT" "W-RAILS-DOUBLE"

# --- A22: two blocks, or a BEGIN without an END — every block write refuses, the file is untouched -------
cksum_of() { cksum < "$1"; }
# dup_block FILE — append a second copy of FILE's block (via a temp: sed must not read what it appends).
dup_block() { sed -n '/^<!-- KEEL-CORE-BEGIN/,/^<!-- KEEL-CORE-END -->/p' "$1" > "$1.dup" && cat "$1.dup" >> "$1" && rm -f "$1.dup"; }

# (a) two blocks
h="$(fresh_home a22-two)"
alter_block "$h/CLAUDE.md"
dup_block "$h/CLAUDE.md"
before="$(cksum_of "$h/CLAUDE.md")"
run "$uninstall" --home "$h" --yes
check_eq "A22 two blocks: uninstall leaves the file byte-identical" "$before" "$(cksum_of "$h/CLAUDE.md")"
check_contains "A22 two blocks: uninstall prints one line saying why" "$OUT" "not exactly one BEGIN"
if command -v script >/dev/null 2>&1; then
  h="$(fresh_home a22-two-refresh)"
  alter_block "$h/CLAUDE.md"
  dup_block "$h/CLAUDE.md"
  before="$(cksum_of "$h/CLAUDE.md")"
  tty_run y "$install" --home "$h" --no-hooks
  check_eq "A22 two blocks: a refresh 'y' leaves the file byte-identical" "$before" "$(cksum_of "$h/CLAUDE.md")"
  check_contains "A22 two blocks: …and says it left the file untouched" "$OUT" "left untouched"
fi

# (b) BEGIN without END
h="$(fresh_home a22-noend)"
alter_block "$h/CLAUDE.md"
grep -v -E '^<!-- KEEL-CORE-END -->[[:space:]]*$' "$h/CLAUDE.md" > "$h/CLAUDE.md.new" && mv "$h/CLAUDE.md.new" "$h/CLAUDE.md"
before="$(cksum_of "$h/CLAUDE.md")"
run "$uninstall" --home "$h" --yes
check_eq "A22 BEGIN without END: uninstall leaves the file byte-identical" "$before" "$(cksum_of "$h/CLAUDE.md")"
check_contains "A22 BEGIN without END: …and says why" "$OUT" "not exactly one BEGIN"
if command -v script >/dev/null 2>&1; then
  h="$(fresh_home a22-noend-refresh)"
  alter_block "$h/CLAUDE.md"
  grep -v -E '^<!-- KEEL-CORE-END -->[[:space:]]*$' "$h/CLAUDE.md" > "$h/CLAUDE.md.new" && mv "$h/CLAUDE.md.new" "$h/CLAUDE.md"
  before="$(cksum_of "$h/CLAUDE.md")"
  tty_run y "$install" --home "$h" --no-hooks
  check_eq "A22 BEGIN without END: a refresh 'y' leaves the file byte-identical" "$before" "$(cksum_of "$h/CLAUDE.md")"
fi

# --- B12: the inline core-ownership fallback in install.sh is gone; the lib is REQUIRED ---------------------
inline="$(grep -c -E '^[[:space:]]*keel_core_is_link\(\)' "$install" || true)"
check_eq "B12: install.sh no longer defines keel_core_is_link inline (one definition, in the lib)" 0 "$inline"
ck="$SANDBOX/b12-ck"; cp -R "$REPO_ROOT" "$ck"; rm -rf "$ck/.git"
rm -f "$ck/tools/lib/core-ownership.sh"
h="$SANDBOX/b12-home"; mkdir -p "$h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "B12: install.sh with core-ownership.sh missing refuses (exit 1)" 1 "$STATUS"
check_contains "B12: …naming the library" "$OUT" "core-ownership.sh"
check_nofile "B12: …and writes no manifest" "$h/.keel/install-manifest.claude"

summary
