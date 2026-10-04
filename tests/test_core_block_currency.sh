#!/usr/bin/env bash
# The block-currency ladder (dir #650 D9/D10): an existing copy-mode Claude CLAUDE.md — and a --codex
# AGENTS.md — gets its embedded KEEL-CORE block checked against the shipped CORE.md on every re-run:
# identical → "="; differs on a terminal → an offer (default no) to refresh ONLY the block, backed up
# first, a /keel-setup git-rails trim kept; differs with no terminal → a WARN carrying a route that
# reaches this install (mode + home flags), never a write. A hand-trimmed block that is otherwise
# current counts as current. tools/doctor.sh --install tells the truth about the same block
# (W-CORE-DRIFT instead of a drift check that never happened).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# alter_block FILE — change one line INSIDE the KEEL-CORE block (an older release, or an edit).
alter_block() { sed 's/## Precedence — when sources conflict/## Precedence — MY EDITED RAIL/' "$1" > "$1.new" && mv "$1.new" "$1"; }
# hand_trim FILE — what a /keel-setup no-git trim leaves: both droppable sections gone, no markers.
hand_trim() {
  awk '/KEEL-GIT-BEGIN/ { skip = 1; next } /KEEL-GIT-END/ { skip = 0; next } !skip' "$1" > "$1.new" && mv "$1.new" "$1"
}
# outside_block FILE — everything except the text between the KEEL-CORE markers (markers included).
outside_block() { awk '/KEEL-CORE-BEGIN/ { skip = 1 } !skip { print } /KEEL-CORE-END/ { skip = 0 }' "$1"; }
block_of() { sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$1" | sed '1d;$d'; }
core_block="$(block_of "$REPO_ROOT/CORE.md")"

# fresh_home NAME [--codex] — a fresh install into $SANDBOX/NAME; prints the home.
fresh_home() {
  local h="$SANDBOX/$1"; shift
  run "$install" "$@" --home "$h" --no-hooks
  [ "$STATUS" = 0 ] || echo "fixture install failed: $OUT" >&2
  printf '%s' "$h"
}

# --- (a) non-interactive re-run over a drifted block: file untouched, WARN with a route ----------------
h="$(fresh_home a-copy)"
alter_block "$h/CLAUDE.md"
before="$(cksum < "$h/CLAUDE.md")"
run "$install" --home "$h" --no-hooks
check_status "A13a: drifted copy-mode block, non-interactive → exit 0 (no hang)" 0 "$STATUS"
check_eq "A13a: the file is byte-identical after the run" "$before" "$(cksum < "$h/CLAUDE.md")"
check_contains "A13a: flags the drift" "$OUT" "CLAUDE.md embeds rails that differ from the shipped core"
w="$(match "$OUT" -E 'Refresh just the block')"
check_contains "A13a: the route names this checkout's install.sh" "$w" "install.sh"
check_contains "A13a: the route carries --home for a non-default home" "$w" "--home \"$h\""
check_contains "A13a: a copy-mode (Claude) route offers the linked migration too" "$w" "--link"

hx="$(fresh_home a-codex --codex)"
alter_block "$hx/AGENTS.md"
run "$install" --codex --home "$hx" --no-hooks
wx="$(match "$OUT" -E 'Refresh just the block')"
check_contains "A13a: a --codex route carries --codex" "$wx" "install.sh --codex"
check_contains "A13a: …and --home" "$wx" "--home \"$hx\""
check_absent "A13a: …and NEVER --link (--codex --link exits 2)" "$wx" "--link"

# The ephemeral bootstrap run's checkout is about to be reaped: the route is the two-step curl form
# that keeps a terminal on stdin, carrying the same flags.
alter_block "$h/CLAUDE.md"
run env KEEL_EPHEMERAL=1 "$install" --home "$h" --no-hooks
we="$(match "$OUT" -E 'Refresh just the block')"
check_contains "A13a: ephemeral route is the curl-to-file form" "$we" "curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh -o keel-bootstrap.sh"
check_contains "A13a: …then sh FILE with the home flag" "$we" "sh keel-bootstrap.sh --home \"$h\""
check_absent "A13a: never the piped form (stdin would not be a terminal)" "$we" "| sh"

# --- (a2) a hand-trimmed block that is otherwise current → "=", no WARN ---------------------------------
h="$(fresh_home a2-trim)"
hand_trim "$h/CLAUDE.md"
check_absent "A13a2 fixture: the trim removed the git section" "$(cat "$h/CLAUDE.md")" "## Git — mandatory rails"
run "$install" --home "$h" --no-hooks
check_status "A13a2: hand-trimmed current block → exit 0" 0 "$STATUS"
check_contains "A13a2: reads as up to date, trim kept" "$OUT" "CLAUDE.md (up to date — your git-rails trim kept)"
check_absent "A13a2: no drift WARN" "$OUT" "embeds rails that differ"

# --- (b) identical block → "=", file unchanged --------------------------------------------------------
h="$(fresh_home b-same)"
before="$(cksum < "$h/CLAUDE.md")"
run "$install" --home "$h" --no-hooks
check_contains "A13b: identical block → the up-to-date line" "$OUT" "CLAUDE.md (up to date)"
check_eq "A13b: file unchanged" "$before" "$(cksum < "$h/CLAUDE.md")"

# --- (c) a foreign CLAUDE.md → left untouched, as today ---------------------------------------------
h="$SANDBOX/c-foreign"; mkdir -p "$h"
printf '# My own notes\nnothing keel here\n' > "$h/CLAUDE.md"
run "$install" --home "$h" --no-hooks
check_contains "A13c: foreign file → left untouched" "$OUT" "CLAUDE.md exists (left untouched"
check_eq "A13c: foreign file content unchanged" "# My own notes
nothing keel here" "$(cat "$h/CLAUDE.md")"

# --- (e) the tty branch, answering y ------------------------------------------------------------------
# A pty is needed: install.sh's offer is behind `[ -t 0 ]`. Hold stdin open past the prompt — a bare
# `printf 'y\n' |` loses the answer at EOF; the hold is a process substitution nothing waits on, so a call
# returns as soon as install.sh exits. macOS `script -q /dev/null CMD…`; util-linux
# `script -qc "CMD" /dev/null`. Called directly, not through lib.sh's run() (it forces </dev/null).
# SKIPPED, with a printed reason, when `script` is absent (the alpine leg has neither script nor python).
tty_run() {   # tty_run ANSWER CMD… → OUT, STATUS (merged stdout, pty-echoed)
  local ans="$1"; shift
  case "$(uname -s)" in
    Darwin) OUT="$(script -q /dev/null "$@" < <(printf '%s\n' "$ans"; sleep 5) 2>&1)"; STATUS=$? ;;
    *)      OUT="$(script -qc "$*" /dev/null < <(printf '%s\n' "$ans"; sleep 5) 2>&1)"; STATUS=$? ;;
  esac
}
if ! command -v script >/dev/null 2>&1; then
  printf '  SKIP  A13e: no `script` binary on this host — the tty branch is not exercised here\n'
else
  # full block, answer y
  h="$(fresh_home e-full)"
  alter_block "$h/CLAUDE.md"
  printf '\nMY-OWN-NOTE below the rails\n' >> "$h/CLAUDE.md"
  outside_before="$(outside_block "$h/CLAUDE.md")"
  tty_run y "$install" --home "$h" --no-hooks
  check_contains "A13e: the offer is shown on a terminal" "$OUT" "Replace just the block with the current shipped rails?"
  check_eq "A13e: yes → the block now equals the shipped CORE.md block" "$core_block" "$(block_of "$h/CLAUDE.md")"
  check_eq "A13e: text outside the markers is byte-identical" "$outside_before" "$(outside_block "$h/CLAUDE.md")"
  nbak="$(find "$h" -maxdepth 1 -name 'CLAUDE.md.*.bak' | wc -l | tr -d ' ')"
  check_eq "A13e: exactly one CLAUDE.md backup was written" 1 "$nbak"
  bak="$(find "$h" -maxdepth 1 -name 'CLAUDE.md.*.bak' | head -1)"
  check_contains "A13e: the backup holds the pre-refresh (edited) block" "$(cat "$bak" 2>/dev/null)" "MY EDITED RAIL"

  # default is NO: an empty answer changes nothing
  h="$(fresh_home e-no)"
  alter_block "$h/CLAUDE.md"
  before="$(cksum < "$h/CLAUDE.md")"
  tty_run "" "$install" --home "$h" --no-hooks
  check_eq "A13e: an empty answer (default no) leaves the file untouched" "$before" "$(cksum < "$h/CLAUDE.md")"

  # a trimmed (and drifted) block answered y STAYS trimmed
  h="$(fresh_home e-trim)"
  hand_trim "$h/CLAUDE.md"
  alter_block "$h/CLAUDE.md"
  outside_before="$(outside_block "$h/CLAUDE.md")"
  tty_run y "$install" --home "$h" --no-hooks
  check_contains "A13e: a trimmed block gets the trim-keeping offer" "$OUT" "Refresh the block, keeping your git-rails trim?"
  check_absent "A13e: the trim survives the refresh (no git section back)" "$(cat "$h/CLAUDE.md")" "## Git — mandatory rails"
  check_absent "A13e: …and the edited rail is gone (the block was refreshed)" "$(cat "$h/CLAUDE.md")" "MY EDITED RAIL"
  check_eq "A13e: trimmed: text outside the markers is byte-identical" "$outside_before" "$(outside_block "$h/CLAUDE.md")"
  run "$install" --home "$h" --no-hooks
  check_contains "A13e: a later run recognizes the refreshed trim as current" "$OUT" "CLAUDE.md (up to date — your git-rails trim kept)"

  # --codex answers y too
  h="$(fresh_home e-codex --codex)"
  alter_block "$h/AGENTS.md"
  tty_run y "$install" --codex --home "$h" --no-hooks
  check_eq "A13e: --codex yes → the AGENTS.md block equals the shipped block" "$core_block" "$(block_of "$h/AGENTS.md")"
  check_eq "A13e: --codex yes → a backup of AGENTS.md exists" 1 "$(find "$h" -maxdepth 1 -name 'AGENTS.md.*.bak' | wc -l | tr -d ' ')"
fi

# --- A14 doctor (D10) ------------------------------------------------------------------------------
h="$(fresh_home d-copy)"
run "$doctor" --install "$h"
check_contains "A14: identical block → the matches-this-checkout OK line" "$OUT" "OK   core rails: embedded copy (matches this checkout's CORE.md)"
check_absent "A14: no W-CORE-DRIFT on an identical block" "$OUT" "W-CORE-DRIFT"
check_absent "A14: the old unverified claim is gone" "$OUT" "a re-run checks for drift"

hand_trim "$h/CLAUDE.md"
run "$doctor" --install "$h"
check_contains "A14: hand-trimmed current block → the trimmed OK line" "$OUT" "matches this checkout's CORE.md, trimmed)"
check_absent "A14: a trimmed-and-current home never fires W-CORE-DRIFT" "$OUT" "W-CORE-DRIFT"

alter_block "$h/CLAUDE.md"
run "$doctor" --install "$h"
check_contains "A14: one altered line → W-CORE-DRIFT" "$OUT" "W-CORE-DRIFT"
check_contains "A14: …its advice names the doctor-accept escape and its side effect" "$OUT" "FUTURE release drift"
mkdir -p "$h/.keel"; printf 'W-CORE-DRIFT\n' > "$h/.keel/doctor-accept"
run "$doctor" --install "$h"
check_absent "A14: listed in <home>/.keel/doctor-accept → suppressed" "$OUT" "W-CORE-DRIFT"

hx="$(fresh_home d-codex --codex)"
run "$doctor" --install --codex "$hx"
check_contains "A14: --codex identical block → the OK line" "$OUT" "core rails: embedded copy (matches this checkout's CORE.md)"
alter_block "$hx/AGENTS.md"
run "$doctor" --install --codex "$hx"
check_contains "A14: --codex altered block → W-CORE-DRIFT" "$OUT" "W-CORE-DRIFT"
wl="$(match "$OUT" -E 'W-CORE-DRIFT')"
check_contains "A14: under --codex the advice carries --codex" "$wl" "--codex"

summary
