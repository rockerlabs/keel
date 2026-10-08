# shellcheck shell=bash
# tools/lib/ledger.sh — the ONE append to the checkout-side install ledger
# (<checkout>/.keel/installed-homes), shared by install.sh and install-pre-pr-gate.sh (dir #125: both
# write a resolved home into the same discovery index). One function instead of two hand-copies behind
# a "keep in sync" comment nothing enforces — the shape dir #106 already fixed once for
# tools/lib/safe-emails.sh / tools/lib/leak-patterns.sh.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

# ledger_append LEDGER_FILE HOME_RESOLVED — append HOME_RESOLVED to LEDGER_FILE, deduped (a no-op if
# already the last-known entry for that home). Creates the ledger's parent dir. Every line this ever
# writes already ends in \n (this is the only writer of the file), so there is no
# no-trailing-newline-on-the-last-line risk to guard against, unlike an adopter-owned file such as
# .gitignore.
ledger_append() {
  local ledger="$1" home="$2"
  mkdir -p "$(dirname "$ledger")"
  if [ ! -f "$ledger" ] || ! grep -qxF "$home" "$ledger" 2>/dev/null; then
    printf '%s\n' "$home" >> "$ledger"
  fi
}

# ledger_remove LEDGER_FILE HOME_RESOLVED — the prune counterpart (dir #125): drop HOME_RESOLVED's
# line from LEDGER_FILE as an EDIT through tools/lib/safe-write.sh's keel_write_through (dir #679), so
# a mid-write crash never leaves a half-written ledger, a symlinked ledger stays a link and the file it
# names gets the change, and the file keeps its mode. A no-op, not an error, when the file or the line
# is already absent (`|| :` covers a grep that finds nothing to keep). Callers decide WHEN to prune
# (uninstall.sh and install-pre-pr-gate.sh --uninstall both do it only once no install-manifest.*
# remains at the home) — this function only knows how to remove one line safely, the same division
# ledger_append already draws for appends. This lib does not source safe-write.sh (each caller does,
# behind its own REQUIRED guard); a caller that did not load it gets one line and a 1, never a write
# of its own. Returns 1 when the write is refused (the caller exits: it cannot record what it did).
ledger_remove() {
  local ledger="$1" home="$2"
  [ -f "$ledger" ] || return 0
  if ! command -v keel_write_through >/dev/null 2>&1; then
    echo "ledger: tools/lib/safe-write.sh is not loaded — the caller must source it first; nothing was written." >&2
    return 1
  fi
  { grep -vxF "$home" "$ledger" 2>/dev/null || :; } | keel_write_through "$ledger"
}
