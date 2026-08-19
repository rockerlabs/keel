# shellcheck shell=bash
# tools/lib/fence-blank.sh — keel-self-maintenance (dir #68): the ONE fenced-code-block toggle,
# shared by tools/self/doctor.sh (its BACKLOG.md/CHANGELOG.md heading scans) and
# tools/self/prose-drift.sh (its md line-length signal) — both keel-self-maintenance tools with no
# consumer-facing counterpart; install.sh never ships either of them, so this lib never reaches an
# adopter's install either. Both need the identical operation: replace every fenced ```/~~~ region
# with blank lines so a
# heading- or wrap-shaped line living inside a code example never reads as real content, while every
# other line's number stays aligned with the original file. doctor.sh's own comment on this function
# already records one prior instance of this exact toggle drifting apart between two checks in the
# SAME file before being consolidated here; a second file re-deriving it from scratch is the same
# drift one file over.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's). Accepted limitation, carried
# over unchanged: an ODD number of fence markers (a forgotten closing fence) leaves the toggle stuck
# "in fence" for the rest of the file, blanking everything after it.
blank_fenced_blocks() {
  awk '/^[[:space:]]*(```|~~~)/ { infence = !infence; print ""; next } infence { print ""; next } { print }' "$1"
}
