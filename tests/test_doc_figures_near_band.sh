#!/usr/bin/env bash
# test_doc_figures_near_band.sh — dir #73: test_doc_figures.sh's assert_band now prints a non-failing
# "note" line once a figure's remaining margin has shrunk to <~3% of actual (drift has eaten >~70% of
# the ±10% half-band). Pin BOTH directions on a real run of the guard itself: (a) a figure nudged into
# the warn zone (still inside ±10%, so still a pass) prints the note; (b) an untouched tree stays
# note-free. Works on a plain `cp -R` COPY of the repo, not a git clone — no git object touched, so the
# Alpine `safe.directory` trap (CLAUDE.md) does not apply here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

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

# --- leg (a): a figure nudged into the warn zone (still inside ±10%) prints the note --------------
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

run bash "$warn_copy/tests/test_doc_figures.sh"
check_status "warn copy: test_doc_figures.sh still exits 0 (still inside ±10%)" 0 "$STATUS"
check_contains "warn copy: prints a near-band note" "$OUT" "  note  "
check_contains "warn copy: note names the nudged file's label" "$OUT" "$doc_row_file"

summary
