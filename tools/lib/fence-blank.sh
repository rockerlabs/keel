# shellcheck shell=bash
# tools/lib/fence-blank.sh — adopter-usable (dir #68): markdown-noise-blanking helpers. Two scopes:
# blank_fenced_blocks() below is the ONE fenced-code-block toggle (a multi-line region; fence_marker_lines()
# beside it lists the lines that toggle reads), blank_inline_code_spans() further down is the ONE
# inline-code-span stripper (a single-line span) — both exist so a heading-, wrap-, or link-shaped line
# living inside a code example never reads as real content, while every other line's number stays
# aligned with the original file. doctor.sh's own comment on blank_fenced_blocks() records one prior
# instance of that exact toggle drifting apart between two checks in the SAME file before being
# consolidated here; a second file re-deriving either function from scratch is the same drift one file
# over — this file, not a caller, is where the next markdown-noise-blanking need should land too.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's). Accepted limitation, carried
# over unchanged: an ODD number of fence markers (a forgotten closing fence) leaves the toggle stuck
# "in fence" for the rest of the file, blanking everything after it.
#
# CALLERS (dir #917; tests/test_fence_blank_lib.sh greps `blank_fenced_blocks` over tools/ and commands/ and fails
# when a file it finds is not named below, so this list cannot go stale):
#   ADOPTER-FACING — read a file the ADOPTER owns, so the input is not under keel's control:
#     tools/cloud-brief.sh                 the adopter's BACKLOG.md (or CLAUDE.md), from their keel checkout; it
#                                          applies line numbers to the RAW file, so they must stay aligned
#     tools/lib/backlog-blocks.sh          the same BACKLOG.md; the /backlog command (commands/backlog.md) runs the
#                                          ticket-block scanner over the adopter's backlog, and cloud-brief.sh does
#     tools/delta-audit/harvest.sh         the adopter's delta-audit run reports (reports/*.md)
#   KEEL-SELF-MAINTENANCE — read only this repo's own tracked text, never installed (dir #68):
#     tools/self/accumulate.sh  tools/self/changelog-claims.sh  tools/self/changelog-cut.sh
#     tools/lib/heading-intro.sh  tools/self/changelog-fragments.sh  tools/self/citation-resolvability.sh
#     tools/self/cut-sim.sh
#     tools/self/doctor.sh  tools/self/line-citations.sh  tools/self/pool-report.sh  tools/self/prose-drift.sh
#     tools/self/value-claim-lint.sh
#   MENTION ONLY — name the function in a comment, do not call it:
#     tools/lib/dir-tickets.sh  tools/changelog-section.sh (keeps its own copy ON PURPOSE, copy-portable alone)
#
# NUL CONTRACT (dir #917, superseding dir #568's "no NUL-safety of its own"): awk's handling of a NUL byte differs
# per implementation — GNU awk and mawk keep it, one-true-awk (macOS) truncates the line at it, and
# busybox awk turns a NUL into a newline, which re-splits the line and shifts every later line number.
# That last one was measured (busybox v1.36 awk on `printf 'a\0b\nc\n'`: 3 lines, not 2). So
# blank_fenced_blocks() and fence_marker_lines() strip every NUL (`tr -d '\000'`) before awk sees the text: a NUL
# is dropped, never turned into a line break, so line N of the output is line N of the raw file under every awk,
# and a stray NUL in an adopter's backlog cannot shift the numbers cloud-brief.sh applies to the raw file.
# blank_inline_code_spans() reads stdin and adds no line, so it keeps no strip of its own: feed it the
# (already NUL-free) output of the functions above.
blank_fenced_blocks() {
  [ -r "$1" ] || { echo "fence-blank: cannot read $1" >&2; return 2; }  # the redirect below would hide it from the pipe
  tr -d '\000' < "$1" | awk '/^[[:space:]]*(```|~~~)/ { infence = !infence; print ""; next } infence { print ""; next } { print }'
}

# fence_marker_lines FILE — the line number of every line blank_fenced_blocks() above toggles on, one per line in
# file order: for a caller that needs the fence structure itself rather than the blanked text (dir #907, moved by
# dir #915: tools/lib/backlog-blocks.sh's bb_last_block_fence_end reads the markers after the last ticket's heading
# to tell a closed fence from an unclosed one).
# The pattern is blank_fenced_blocks()' own, byte for byte; tests/test_fence_blank_lib.sh pins that the two agree.
fence_marker_lines() {
  [ -r "$1" ] || { echo "fence-blank: cannot read $1" >&2; return 2; }
  tr -d '\000' < "$1" | awk '/^[[:space:]]*(```|~~~)/ { print NR }'
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
