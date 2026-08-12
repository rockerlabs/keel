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
# line from LEDGER_FILE, atomically (temp-sibling + rename, matching install.sh's own atomic_write
# discipline — a mid-write crash must never leave a half-written ledger). A no-op, not an error, when
# the file or the line is already absent (`|| : > "$tmp"` covers both a missing ledger and a grep that
# finds nothing to keep). Callers decide WHEN to prune (uninstall.sh and install-pre-pr-gate.sh
# --uninstall both do it only once no install-manifest.* remains at the home) — this function only
# knows how to remove one line safely, the same division ledger_append already draws for appends.
ledger_remove() {
  local ledger="$1" home="$2" tmp
  [ -f "$ledger" ] || return 0
  tmp="$ledger.keeltmp.$$"
  grep -vxF "$home" "$ledger" > "$tmp" 2>/dev/null || : > "$tmp"
  mv -f "$tmp" "$ledger"
}

# manifest_field FILE KEY — the value of a top-level `key=value` line in an install/gate manifest (dir
# #125), first match, "" on any read failure. dir #125 PR3 (found by an independent /simplify pass,
# converging across all four review angles): tools/doctor.sh and uninstall.sh each already carried their
# own hand-copy of this identical one-liner ("no established cross-sourcing convention... yet", per
# uninstall.sh's own comment on its copy) — a third hand-copy in tools/pre-pr-gate.sh would have made it
# three. This is the first shared home for it; doctor.sh/uninstall.sh keep their own copies for now
# (out of this PR's scope — they predate it and are independently tested), but any NEW manifest reader
# should source this instead of hand-copying a fourth time. `|| true` at the end: an EXISTING but
# unreadable manifest (permission-denied) makes `sed` exit non-zero even with stderr silenced, and a
# caller running under `set -e` must not abort mid-run over a single unreadable manifest — the
# versioning contract says exactly this case degrades to "treated as absent", never a crash.
manifest_field() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1 || true
}

# manifest_usable FILE — the versioning contract shared by every dir #125 manifest reader: present,
# readable, AND a keel_manifest_version this consumer understands (currently exactly "1"). Mirrors
# uninstall.sh's own manifest_usable (kept there, not yet migrated here, same out-of-scope reasoning as
# manifest_field above) — the first shared instance of the predicate rather than a fourth hand-copy.
manifest_usable() {
  [ -f "$1" ] && [ "$(manifest_field "$1" keel_manifest_version)" = "1" ]
}
