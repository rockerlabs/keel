# shellcheck shell=bash
# tools/lib/dir-tickets.sh — extract_dir_tickets: reads text on stdin, echoes every `dir #N` ticket
# it references, one per line, deduped (dir #273 gap 2, dir #274).
#
# Promoted out of tools/self/doctor.sh's own `_extract_dir_tickets` (dir #266, its second consumer:
# tools/self/citation-resolvability.sh) — doctor.sh keeps a one-line wrapper of the same name so its
# own two call sites and its 225 existing tests need no change; this file is the one real
# implementation both now share, the same shape as tools/lib/fence-blank.sh's `blank_fenced_blocks`.
#
# Sourced, not executed — no shebang, no `set -e` (inherits the caller's).
#
# A bare `grep -oE 'dir #[0-9]+'` only matches a fully-spelled reference and silently drops every
# bare `#N` in a shorthand list like "dir #208, #211, #212" — the first commit hit by this exact
# shape (PR #267's own message) went undetected because #211/#212 were never even in the candidate
# set to look for, not merely uncredited (dir #273). First join a shorthand list wrapped across a
# line break back onto one line (grep is inherently line-based and can't see across a `\n`
# otherwise), then capture the whole run starting at a `dir #N` anchor — comma/semicolon/slash/
# whitespace/"and"-joined, and a `#N-M` range expanded to every ticket in it, not just its endpoints
# (dir #274; a range names every ticket between its bounds, so extracting only the two written
# numbers would silently lose the middle) — THEN pull every `#N`/`#N-M` out of that run and reattach
# the `dir ` prefix, expanding ranges last. "dir #208, #211, #212" and two fully-spelled references
# like "dir #208, dir #211" (where the run stops right after the first, because "dir " breaks the
# bare-`#N` continuation) both resolve to their complete ticket sets either way. Every one of the
# four extra shapes has real precedent in this repo's own history, not hypothetical: e.g. commit
# 1515d7a's own title, "...dir #208/#211/#212...", is a slash-separated instance; `f4109e72`/
# `21e984bfd9a` are real batch-close commits using the range shape, and docs/delegation.md's own
# "dir #201/#214" (found live by dir #266's own review) is a shipped slash-separated instance in
# tracked prose, not just commit history.
# The line-wrap join only fires when the PRECEDING line ends in a trailing comma AND the line it
# would join onto is made of NOTHING but ticket-list tokens — not a blanket newline-to-space join —
# so it can't stitch one line's trailing ticket onto unrelated content on the next line. Two distinct
# false-positive shapes this closes, both found live by an independent review pass (dir #274) against
# an earlier, looser version of this join that merged unconditionally on any trailing comma:
# - Cross-commit: `git log --format=%B` inserts a BLANK line between commit bodies (verified live, not
#   assumed) — but a buffered trailing-comma line that merely absorbs that blank line still ends in
#   ", " (comma-space) after the merge, which re-buffers instead of printing, so it would otherwise
#   ride straight through the blank separator and stitch onto the NEXT commit's leading token. A blank
#   line is therefore a hard flush point: whatever is buffered is printed before it, never merged with
#   it. Reproduced: a commit body ending "...dir #100," immediately followed (newest-first) by an
#   unrelated older commit starting with a bare "#102" fabricated a "dir #102" citation.
# - Within one paragraph/commit body (no blank line involved): a line ending "...dir #100, #105,"
#   directly followed by unrelated prose that happens to start with a bare number ("#110 unrelated
#   text") would, under an unconditional join, fabricate "dir #110" too. Reproduced the same way. The
#   fix requires the CONTINUATION line to be made of nothing but ticket tokens (`#N`, `#N-M`, joined
#   only by `,`/`;`/`/`/whitespace, with an optional trailing separator) before joining — a genuine
#   wrapped ticket list wraps onto a line that IS the rest of the list, never onto a line that mixes
#   list items with other prose. A line failing that shape check flushes the buffer as-is and is
#   itself processed as ordinary text, so "#110 unrelated text" is left alone (no leading "dir ", so
#   it was never a candidate on its own either).
# Every backtick-quoted inline code span is stripped before any of the above runs — found live by an
# independent review pass (dir #274): this very function's own doc comments and CHANGELOG entries
# quote illustrative examples like `` `"dir #104-107"` `` and `` `"dir #208/#211/#212"` ``, and without
# stripping, the range/slash support this diff adds makes those EXAMPLES parseable as if they were
# real citations — silently vouching for tickets nothing ever actually cited, which is a WORSE failure
# than a missed one (it can mask a genuinely missing entry, not just miss reporting one).
# Two malformed-range edge cases (found by a peer session's review), both handled loudly rather than
# by silently dropping a ticket the way the pre-dir-#274 helper did:
# - Reversed (e.g. "#107-104", a typo'd order): looping lo..hi would print nothing (lo > hi), which is
#   the exact silent-drop defect this whole chain exists to kill. Treated as two bare ticket
#   references instead of a range — both endpoints surface, neither is invented.
# - Absurdly wide (e.g. "#1-99999"): expanding it would either hang or flood the output; silently
#   truncating to one endpoint (an earlier draft's behavior) would look complete while dropping every
#   other ticket in the span, one layer deeper than dir #273's own gap. Capped at 500 tickets; past
#   the cap this emits a single, deliberately unmatchable marker line instead of a real ticket, so it
#   always shows up as "missing" in a consumer's own reconciliation — visible for a human to verify
#   manually, never silently scanned away. A consumer that needs strictly numeric `dir #N` lines
#   (citation-resolvability.sh, below) filters this marker line out at the call site rather than here,
#   since dropping it silently here would re-introduce the exact silent-loss failure this comment
#   describes for doctor.sh's own WARN-surfacing consumer.
# A hyphen that ISN'T a range (prose like "dir #208 - fixed the extraction", a spaced dash) never
# reaches either branch: the range suffix requires a digit immediately after the `-`, with no space,
# so the anchor below stops at "dir #208" and the loose dash is left alone.
extract_dir_tickets() {
  sed -E 's/`[^`]*`//g' \
    | awk '
    { line = $0
      if (line == "") { if (buf != "") { print buf; buf = "" }; next }
      if (buf != "") {
        if (line ~ /^[ \t]*#[0-9]+([,;\/[:space:]]+#[0-9]+)*[,;]?[ \t]*$/) { line = buf " " line }
        else { print buf }
        buf = ""
      }
      if (line ~ /,[ \t]*$/) { sub(/[ \t]*$/, "", line); buf = line }
      else { print line }
    }
    END { if (buf != "") print buf }
  ' \
    | grep -oE 'dir #[0-9]+(-[0-9]+)?([,;/[:space:]]+(and[[:space:]]+)?#[0-9]+(-[0-9]+)?)*' \
    | grep -oE '#[0-9]+(-[0-9]+)?' \
    | awk -F'[#-]' '
        /-/ { lo = $2 + 0; hi = $3 + 0
              if (hi < lo) { print "dir #" lo; print "dir #" hi; next }
              if (hi - lo >= 500) { print "dir #" lo "-" hi " (range too large to expand, dir #274)"; next }
              for (i = lo; i <= hi; i++) print "dir #" i
              next }
        { print "dir #" $2 }
      ' \
    | sort -u \
    || true
}
