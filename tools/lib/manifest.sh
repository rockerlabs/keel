# shellcheck shell=bash
# tools/lib/manifest.sh — the minimal key=value manifest reader (dir #125).
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
#
# NOT sourced by tools/lib/ledger.sh, and not shared with install.sh/uninstall.sh/tools/doctor.sh's own
# independent copies of manifest_field/manifest_usable, deliberately: those three already source
# tools/lib/ledger.sh for ledger_append/ledger_remove, and each ALSO defines its own local
# manifest_field/manifest_usable. Putting these two functions in ledger.sh (the first draft of this
# fix) would have made every one of those sourcing sites silently REDEFINE its own already-loaded
# function mid-run with this file's copy the moment ledger.sh's source line executed — same bodies
# today, so no behavioral change YET, but a future edit to either copy would silently stop applying at
# whichever call sites happen to source ledger.sh after the local definition (found by an operator-run
# /code-review high pass on this ticket, reproduced at uninstall.sh's own conditional
# `. "$root/tools/lib/ledger.sh"` inside its `manifests_left = 0` branch). A separate file with no other
# consumers avoids the collision entirely rather than papering over it with a comment. Only
# tools/pre-pr-gate.sh sources this today; doctor.sh/uninstall.sh keep their own independently-tested
# copies out of this PR's scope.

# manifest_field FILE KEY — the value of a top-level `key=value` line in an install/gate manifest, first
# match, "" on any read failure. `|| true` at the end: an EXISTING but unreadable manifest
# (permission-denied) makes `sed` exit non-zero even with stderr silenced, and a caller running under
# `set -e` must not abort mid-run over a single unreadable manifest — the versioning contract says
# exactly this case degrades to "treated as absent", never a crash.
manifest_field() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1 || true
}

# manifest_usable FILE — the versioning contract shared by every dir #125 manifest reader: present,
# readable, AND a keel_manifest_version this consumer understands (currently exactly "1").
manifest_usable() {
  [ -f "$1" ] && [ "$(manifest_field "$1" keel_manifest_version)" = "1" ]
}
