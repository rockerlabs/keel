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
# /code-review max pass, since this line used to say the opposite). All three source it REQUIRED
# (guarded, not bare — see each script's own sourcing-block comment for why): install.sh's consumption
# was OPTIONAL until spec 685 round 2 (B20) gave it the link-record predicate below on every run.

# manifest_field FILE KEY — the value of a top-level `key=value` line in an install/gate manifest, first
# match, "" on any read failure. `|| true` at the end: an EXISTING but unreadable manifest
# (permission-denied) makes `sed` exit non-zero even with stderr silenced, and a caller running under
# `set -e` must not abort mid-run over a single unreadable manifest — the versioning contract says
# exactly this case degrades to "treated as absent", never a crash.
manifest_field() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1 || true
}

# manifest_symlink_extra FILE REL — the target the manifest recorded for the `symlink` artifact at REL (dir #369;
# `-` in a manifest older than that ticket); "" when there is no such record or the read fails. Shared by
# install.sh's keel_own_stale_link and doctor's dangling-link advice, so both read Keel's record the same way.
manifest_symlink_extra() {
  awk -F'\t' -v rel="$2" '$1 == "artifact=symlink" && $2 == rel { print $3; exit }' "$1" 2>/dev/null || true
}

# manifest_usable FILE — the versioning contract shared by every dir #125 manifest reader: present,
# readable, AND a keel_manifest_version this consumer understands (currently exactly "1").
manifest_usable() {
  [ -f "$1" ] && [ "$(manifest_field "$1" keel_manifest_version)" = "1" ]
}

# keel_path_inside PATH CHECKOUT — PATH is CHECKOUT or below it (B7's "inside": the checkout's path or a
# path under it, with the slash, so a sibling `<checkout>-dots` is not inside): on the strings, or — when
# PATH still resolves — on the physical paths, so a record that spells the checkout through another link
# (`~/.keel/engine/...` for `~/pet-projects/keel/...`) still counts. A PATH that no longer resolves
# (its checkout moved) is judged on the strings alone.
keel_path_inside() {
  local p="$1" ck="${2%/}" pd ckp
  [ -n "$ck" ] || return 1
  case "$p" in "$ck"|"$ck"/*) return 0 ;; esac
  [ -e "$p" ] || return 1
  pd="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
  ckp="$(cd -P "$ck" 2>/dev/null && pwd -P)" || return 1
  case "$pd/$(basename "$p")" in "$ckp"|"$ckp"/*) return 0 ;; esac
  return 1
}

# manifest_same_path A B — A and B name the same directory entry: the same text; or, for an absolute A, the
# same name in the same directory (`-ef` on the two parent directories, so a symlinked parent, /tmp vs
# /private/tmp and a case-only difference in a directory name on a case-insensitive file system all match).
# The entry's own name must match exactly: comparing the entries themselves would follow a link at A, so
# neither the end of a chain of links (`x -> ~/dots/x -> <checkout>/x`) nor a differently-named sibling
# (`<checkout>/ALIAS.md -> CORE.md`, a case-only `core.md` beside `CORE.md`, or a hard link) is "the same"
# as the file it leads to. The text half is what still answers once the directories are gone (a moved
# checkout). The one definition of "a link points where the record says" (manifest_link_is_keels below,
# uninstall.sh's symlink arm and its compatibility-link count).
manifest_same_path() {
  [ "$1" = "$2" ] && return 0
  case "$1" in /*) ;; *) return 1 ;; esac
  [ "${1##*/}" = "${2##*/}" ] && [ "${1%/*}/" -ef "${2%/*}/" ]
}

# manifest_link_is_keels MANIFEST REL LINK — the ONE test that a link a manifest recorded is provably Keel's
# (spec 685 round 2 B20): MANIFEST is usable and holds a `symlink` record for REL whose target is not the
# pre-dir-#369 `-`, LINK's own target IS that recorded target (manifest_same_path: the same text, or the
# same entry spelled through another directory) — and the target lies inside the checkout MANIFEST's
# `checkout=` header names (keel_path_inside — the checkout that WROTE the record, the old one after a
# move). An adopter's link that an older manifest recorded as Keel's fails the last test, so nothing that
# asks this moves or re-places it. A link that only ENDS at the recorded target through another link (a
# dotfiles manager's `~/.claude/x -> ~/dots/x -> <checkout>/x`) is not Keel's: the test compares where LINK
# itself points, never the end of its chain. install.sh's stale-link class, tools/doctor.sh's
# dangling-link advice and uninstall.sh's symlink arm all ask it; each keeps its own handling of a `-`
# record at the call site.
manifest_link_is_keels() {
  local man="$1" rel="$2" link="$3" rec cur ck
  manifest_usable "$man" || return 1
  rec="$(manifest_symlink_extra "$man" "$rel")"
  [ -n "$rec" ] && [ "$rec" != "-" ] || return 1
  cur="$(readlink "$link" 2>/dev/null)" || return 1
  manifest_same_path "$cur" "$rec" || return 1
  ck="$(manifest_field "$man" checkout)"
  keel_path_inside "$rec" "$ck"
}
