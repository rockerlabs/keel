# shellcheck shell=bash
# tools/lib/manifest.sh — the minimal key=value manifest reader (dir #125).
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
#
# NOT sourced by tools/lib/ledger.sh, deliberately (historical: true when uninstall.sh/tools/doctor.sh
# still hand-copied manifest_field/manifest_usable, and still the reason this stays its own file — see
# below for why that reasoning still holds even though both scripts are consumers now): uninstall.sh
# already sources tools/lib/ledger.sh for ledger_append/ledger_remove, and — at the time this file was
# split out — also defined its own local manifest_field/manifest_usable. Putting these two functions in
# ledger.sh (the first draft of this fix) would have made every one of those sourcing sites silently
# REDEFINE its own already-loaded function mid-run with this file's copy the moment ledger.sh's source
# line executed — same bodies then, so no behavioral change YET, but a future edit to either copy would
# silently stop applying at whichever call sites happen to source ledger.sh after the local definition
# (found by an operator-run /code-review high pass on this ticket, reproduced at uninstall.sh's own
# conditional `. "$root/tools/lib/ledger.sh"` inside its `manifests_left = 0` branch). A separate file
# with no other consumers avoids the collision entirely rather than papering over it with a comment —
# still true today: uninstall.sh's ledger.sh source line is untouched, so the same hazard would still
# apply if these two functions ever moved into it.
#
# Sourced by tools/pre-pr-gate.sh, and by all three of install.sh/uninstall.sh/tools/doctor.sh (dir
# #363 made the latter two consumers too — previously each hand-copied manifest_field/manifest_usable,
# verified output-identical to this file's own copy; found stale here by this ticket's own
# /code-review max pass, since this line used to say the opposite). install.sh's own consumption stays
# OPTIONAL (dir #323, sourcing only when tools/lib/manifest.sh exists — a minimal test-fixture checkout
# may not ship tools/ at all, and install.sh degrades to "provenance unavailable" rather than requiring
# it); uninstall.sh's and tools/doctor.sh's are REQUIRED (guarded, not bare — see each script's own
# sourcing-block comment for why).

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
