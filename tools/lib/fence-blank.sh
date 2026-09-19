# shellcheck shell=bash
# tools/lib/fence-blank.sh — keel-self-maintenance (dir #68): markdown-noise-blanking helpers shared by
# tools/self/doctor.sh (its BACKLOG.md/CHANGELOG.md heading scans) and tools/self/prose-drift.sh (its
# md line-length signal and its dead-link signal, dir #240) — both keel-self-maintenance tools with no
# consumer-facing counterpart; install.sh never ships either of them, so this lib never reaches an
# adopter's install either. Two functions, two different scopes: blank_fenced_blocks() below is the ONE
# fenced-code-block toggle (a multi-line region), blank_inline_code_spans() further down is the ONE
# inline-code-span stripper (a single-line span) — both exist so a heading-, wrap-, or link-shaped line
# living inside a code example never reads as real content, while every other line's number stays
# aligned with the original file. doctor.sh's own comment on blank_fenced_blocks() already records one
# prior instance of that exact toggle drifting apart between two checks in the SAME file before being
# consolidated here; a second file re-deriving either function from scratch is the same drift one file
# over — this file, not a caller, is where the next markdown-noise-blanking need should land too.
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
# spans lines, so there is nothing for a multi-line toggle to buy. Accepted limitation, same shape as
# the fence toggle's own unclosed-fence case above but a different effect: `gsub` pairs backticks
# strictly left-to-right, so a line with an ODD backtick count is not left untouched whole — it blanks
# whatever PAIRS it can find and leaves the unpaired backtick's own text dangling (verified live:
# `` Use ` at the start of `code`. `` blanks the first pair, leaving "Use code`." — the third backtick's
# own text survives, mis-paired rather than ignored). Reads stdin (an already fence-blanked stream,
# typically), not a filename — same shape as blank_fenced_blocks' own callers pipe INTO it, one stage
# later.
blank_inline_code_spans() {
  awk '{ gsub(/`[^`]*`/, ""); print }'
}
