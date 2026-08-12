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
