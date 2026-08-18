# shellcheck shell=bash
# tools/lib/fence-blank.sh — the ONE fenced-code-block toggle, shared by tools/self/doctor.sh (its
# BACKLOG.md/CHANGELOG.md heading scans) and tools/self/prose-drift.sh (its md line-length signal).
# Both need the identical operation: replace every fenced ```/~~~ region with blank lines so a
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
