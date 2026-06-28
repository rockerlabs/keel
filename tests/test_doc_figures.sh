#!/usr/bin/env bash
# test_doc_figures.sh — the per-file token figures quoted in docs/loading-and-cost.md must stay close
# to the real file size by the doc's own ruler (~4 chars/token). A prior "doc nits" pass left
# FRAMEWORK.md understated (the file grew, the quoted figure didn't) — exactly the drift a methodology
# selling honest token accounting can't afford. This locks the big on-demand files to within ±10%.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/loading-and-cost.md"
check_file "loading-and-cost.md exists" "$doc"

# Assert the ~figure on FILE's table row in loading-and-cost.md is within ±10% of (chars / 4).
# The row begins "| `FILE` |"; the figure is the "~N,NNN" in its tokens cell.
assert_figure() {
  local label="$1" file="$2" path="$REPO_ROOT/$2"
  if [ ! -f "$path" ]; then fail "$label" "missing file: $path"; return; fi

  local chars actual row doc_fig lo hi
  chars="$(wc -c < "$path" | tr -d ' ')"
  actual=$(( chars / 4 ))

  row="$(grep -E "^\| \`${file//./\\.}\`" "$doc" | head -1)"
  doc_fig="$(printf '%s' "$row" | grep -oE '~[0-9,]+' | tail -1 | tr -d '~, ')"
  if [ -z "$doc_fig" ]; then
    fail "$label" "no ~figure found on the $file row of loading-and-cost.md"
    return
  fi

  lo=$(( actual * 9 / 10 )); hi=$(( actual * 11 / 10 ))
  if [ "$doc_fig" -ge "$lo" ] && [ "$doc_fig" -le "$hi" ]; then
    pass "$label (doc ~$doc_fig vs actual ~$actual)"
  else
    fail "$label" "doc says ~$doc_fig but actual is ~$actual tok (chars=$chars; allowed $lo..$hi)"
  fi
}

assert_figure "FRAMEWORK.md figure is within 10% of actual" FRAMEWORK.md
assert_figure "PRINCIPLES.md figure is within 10% of actual" PRINCIPLES.md

summary
