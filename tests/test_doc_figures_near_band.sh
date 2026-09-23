#!/usr/bin/env bash
# test_doc_figures_near_band.sh — dir #73: test_doc_figures.sh's assert_band now prints a non-failing
# "note" line once a figure's remaining margin has shrunk to <~3% of actual (drift has eaten >~70% of
# the ±10% half-band). Pin BOTH directions on a real run of the guard itself: (a) a figure nudged into
# the warn zone (still inside ±10%, so still a pass) prints the note; (b) an untouched tree stays
# note-free. Works on a plain `cp -R` COPY of the repo, not a git clone — no git object touched, so the
# Alpine `safe.directory` trap (CLAUDE.md) does not apply here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# A plain tree copy (tar avoids cp's non-portable exclude flags across BSD/GNU cp); .git is skipped —
# this test never runs git and a full history copy would only slow the sandbox down.
copy_tree() {
  local dest="$1"
  mkdir -p "$dest"
  tar -C "$REPO_ROOT" --exclude=.git -cf - . | tar -C "$dest" -xf -
}

doc_row_file="templates/LEARNINGS.md"   # small, single-figure row — cheap to nudge and to re-check

# --- leg (b): untouched copy stays note-free -----------------------------------------------------
clean_copy="$SANDBOX/near-band-clean"
copy_tree "$clean_copy"
run bash "$clean_copy/tests/test_doc_figures.sh"
check_status "clean copy: test_doc_figures.sh exits 0" 0 "$STATUS"
check_absent "clean copy: no near-band note" "$OUT" "  note  "

# --- leg (a) + leg (c): two independent near-band mutations on ONE copy, one run ------------------
# leg (a): a figure nudged into the warn zone (still inside ±10%) prints the note.
# leg (c) (dir #245): the commands/*.md OPEN-CEILING range row gets the same 25%-style note as the
# open-floor rows, once the largest ordinary command has drifted 25%+ above the quoted HI. A
# SYNTHETIC near-ceiling fixture (shrink the row's own quoted HI in the copy), not a real command
# pushed toward it — the real tree's own largest command changes size over time and this test must
# not depend on today's exact figure.
# Combined into one `copy_tree` + one guard run (found in review — they touch different ROWS of the
# same doc and neither depends on the other's mutation, so two separate tree copies + two separate
# full runs were pure duplicated I/O for no isolation benefit).
warn_copy="$SANDBOX/near-band-warn"
copy_tree "$warn_copy"

target="$warn_copy/$doc_row_file"
doc="$warn_copy/docs/loading-and-cost.md"
actual="$(( $(wc -c < "$target" | tr -d ' ') / 4 ))"
hi=$(( actual * 11 / 10 ))
# One tok of margin under the ceiling: always < the assert_band threshold (actual*3/100) for any
# file big enough to have a nonzero threshold, so the note reliably fires regardless of
# doc_row_file's exact current size.
warn_fig=$(( hi - 1 ))

# Rewrite the row's own "~N" figure (the ONLY "~number" cell format assert_figure parses) to warn_fig,
# leaving the rest of the row (including its "*(as filled)*"-style annotations, if any) untouched.
awk -v file="$doc_row_file" -v fig="$warn_fig" '
  BEGIN { pat = "`" file "`" }
  index($0, pat) && /^\|/ {
    sub(/~[0-9,]+/, "~" fig)
  }
  { print }
' "$doc" > "$doc.tmp" && mv "$doc.tmp" "$doc"

# The real largest ORDINARY command (excl. polish.md), by the same ~4-chars/token estimate the guard
# itself uses — this is what the shrunk HI below has to sit 25%+ under.
max_cmd_tok=0
for f in "$warn_copy"/commands/*.md; do
  [ -f "$f" ] || continue
  [ "$(basename "$f")" = "polish.md" ] && continue
  c="$(wc -c < "$f" | tr -d ' ')"
  t=$(( c / 4 ))
  [ "$t" -gt "$max_cmd_tok" ] && max_cmd_tok="$t"
done
# new_hi*5/4 must be strictly below max_cmd_tok — new_hi = max_cmd_tok*4/5 - 1 guarantees that with
# integer division (round-down on the *4/5 already errs low; the -1 covers the exact-multiple case).
new_hi=$(( (max_cmd_tok * 4 / 5) - 1 ))

# Rewrite the row's own "~LO–HI+ each" cell, keeping LO and the open "+" — only HI shrinks. The
# LO/HI separator is an EN DASH (U+2013), not a hyphen (found live: a hyphen-anchored sub() silently
# never matched) — target the digit run immediately before the "+" instead, which is unambiguous
# either way (only the HI figure in this row carries a trailing "+").
awk -v newhi="$new_hi" '
  /^\|.*`commands\/\*/ {
    sub(/[0-9][0-9,]*\+/, newhi "+")
  }
  { print }
' "$doc" > "$doc.tmp" && mv "$doc.tmp" "$doc"

run bash "$warn_copy/tests/test_doc_figures.sh"
check_status "warn+ceiling copy: test_doc_figures.sh still exits 0 (both are non-failing notes)" 0 "$STATUS"
check_contains "warn copy: prints a near-band note" "$OUT" "  note  "
check_contains "warn copy: note names the nudged file's label" "$OUT" "$doc_row_file"
check_contains "ceiling copy: note names the commands/*.md range label" "$OUT" \
  "commands/*.md (excl. polish.md) sizes fall inside the quoted range"
check_contains "ceiling copy: note cites the shrunk ceiling" "$OUT" "ceiling ~$new_hi+"

summary
