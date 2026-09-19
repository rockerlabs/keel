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

# blank_inline_code_spans — drop every INLINE `code span` (backticks included) from each line on
# stdin, so a link-shaped token quoted inside backticks (a doc illustrating link syntax, e.g.
# `` `[text](url)` ``) is not later mistaken for a real link by a caller that greps for `](...)`
# afterward (dir #240 item 3, tools/self/prose-drift.sh's signal 2). Per-LINE only, unlike
# blank_fenced_blocks' fence toggle above: an inline span's content is never itself the thing a caller
# here cares about (only whether a `](...)`-shaped token sits inside one), and a markdown link never
# spans lines, so there is nothing for a multi-line toggle to buy — an unclosed span (an odd number of
# backticks on one line) is simply left untouched, the same accepted-limitation shape as the fence
# toggle's own unclosed-fence case above. Reads stdin (an already fence-blanked stream, typically),
# not a filename — same shape as blank_fenced_blocks' own callers pipe INTO it, one stage later.
blank_inline_code_spans() {
  awk '{ gsub(/`[^`]*`/, ""); print }'
}
