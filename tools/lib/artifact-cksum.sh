# shellcheck shell=bash
# tools/lib/artifact-cksum.sh — the shared artifact-checksum helper (dir #362, split from dir #278).
#
# Sourced, not executed — no shebang as the first line's contract, no set -e (inherits the caller's).
#
# Extracted from install.sh's own artifact_cksum/CKSUM_UNREADABLE (previously also hand-copied,
# output-identical, inside uninstall.sh). One definition, two consumers: install.sh writes this value
# into a manifest `file` record at placement time; uninstall.sh later reads that record back and
# compares it against a live re-cksum to decide whether a file is still Keel's own unedited copy.
#
# REQUIRED, not optional, by both callers — this is why this file does NOT follow manifest.sh's/
# stat-portable.sh's "missing → degrade and continue" contract. Those two guard an optional refinement
# with a safe slower path behind it. This one guards a value written unconditionally into a manifest
# record that uninstall.sh later trusts for a destructive (removal) decision: a same-shape fallback
# stub here would make every artifact_cksum call answer the sentinel — indistinguishable, in the
# manifest, from a genuinely-unreadable file's record, for every artifact, not just the rare
# truly-unreadable one. dir #347 has since closed uninstall.sh's own comparison's sentinel guard at its
# call site (uninstall.sh:882), but that guards uninstall.sh's REMOVAL decision, not the manifest
# record itself, which a stubbed fallback here would still corrupt. Both install.sh and uninstall.sh
# source this file behind a `[ -s ] && bash -n` pre-check and refuse outright (one actionable message,
# exit 1) rather than sourcing unguarded or degrading — see each call site's own comment for why.

# CKSUM_UNREADABLE — what artifact_cksum yields when it cannot read the file at all. Named because
# keel_own_untouched (install.sh) has to RECOGNISE it, not merely produce it: a self-equal error
# sentinel on a never-clobber rail fails OPEN (an unreadable dest would compare equal to a manifest
# that ever recorded the same sentinel, and the predicate would answer "Keel's own unedited copy,
# refresh it without asking" for a file it could not read a single byte of). uninstall.sh's own
# comparison at its call site gained that same guard this release (dir #347, uninstall.sh:882).
CKSUM_UNREADABLE='cksum:0:0'

# artifact_cksum FILE — "cksum:<sum>:<size>", POSIX cksum's first two fields (portable across
# coreutils/busybox — both are POSIX cksum implementations; the filename field is dropped since a
# home-relative path is already the record's own key). $CKSUM_UNREADABLE when FILE can't be read —
# never equal to any real digest as far as a caller's own sentinel guard is concerned.
# `[ -f "$1" ]` guard (dir #351): a FIFO/char-device FILE blocks `cksum` forever, the same hang this
# batch already fixed for `cmp` — reject by type before the fork instead of hanging in it. A no-op for
# both current callers (install.sh's own call is upstream-guarded by keel_own_untouched's own `[ -f ]`
# clause; uninstall.sh's is upstream-guarded by its own `[ -f "$apath" ]`), and correct regardless of
# who calls it next.
artifact_cksum() {
  local sum size
  [ -f "$1" ] || { printf '%s' "$CKSUM_UNREADABLE"; return; }
  read -r sum size _ < <(cksum "$1" 2>/dev/null) || { printf '%s' "$CKSUM_UNREADABLE"; return; }
  printf 'cksum:%s:%s' "$sum" "$size"
}
