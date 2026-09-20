# shellcheck shell=bash
# tools/lib/fence-blank.sh — keel-self-maintenance (dir #68): markdown-noise-blanking helpers shared
# across keel-self-maintenance tools with no consumer-facing counterpart (install.sh never ships any of
# them, so this lib never reaches an adopter's install either) — among them tools/self/doctor.sh (its
# BACKLOG.md/CHANGELOG.md heading scans), tools/self/prose-drift.sh (its md line-length signal and its
# dead-link signal, dir #240), and tools/self/line-citations.sh (its fenced-example exclusion); NOT an
# exhaustive list of callers (a prior header version named only these three as if it were — corrected by
# this ticket's own `/code-review high` pass, cross-file angle — grep this repo for
# `blank_fenced_blocks`/`blank_inline_code_spans` for the current, real set, which also includes
# tools/self/citation-resolvability.sh, tools/self/pool-report.sh, tools/lib/backlog-blocks.sh, and
# tools/delta-audit/harvest.sh). Two functions, two different scopes: blank_fenced_blocks() below is the
# ONE fenced-code-block toggle (a multi-line region), blank_inline_code_spans() further down is the ONE
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
#
# IMPLICIT CONTRACT (dir #568's own altitude review): awk's handling of a NUL byte in its input is NOT
# consistent across platforms — GNU/mawk keeps it, busybox awk turns it into a newline (silently
# re-splitting the blob), one-true-awk (macOS) truncates at the first one. blank_fenced_blocks() has no
# NUL-safety of its own; every caller today satisfies this by construction, never by checking it — the
# doctor.sh/pool-report.sh/backlog-blocks.sh callers only ever feed it known BACKLOG/CHANGELOG text
# files, citation-resolvability.sh/harvest.sh/prose-drift.sh's md signal only ever walk a `*.md`-globbed
# list (a binary file can't plausibly carry that extension in this tree), and line-citations.sh's own
# unfiltered `git ls-files` walk (the one caller with no such filter) instead excludes a binary tracked
# file at its own prefilter, via `git grep -I`, before it ever reaches here — though that exclusion is
# itself bounded to git's own binary-detection prefix (see line-citations.sh's own comment). A future
# caller that walks tracked files without a text/extension filter needs the same kind of exclusion at
# ITS OWN boundary — this function does not provide it, and nothing here enforces that a future caller
# remembers to add one.
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
