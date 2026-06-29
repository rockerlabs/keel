#!/usr/bin/env bash
# test_doc_figures.sh — every per-file token figure quoted in docs/loading-and-cost.md must stay close
# to the real file size by the doc's own ruler (~4 chars/token). A methodology selling honest token
# accounting can't ship a stale number. This guards EVERY figure-bearing row, not a subset: a prior
# pass left FRAMEWORK.md understated, and a partial guard then let CHANGELOG.md drift the same way —
# so the lock has to cover all of them or it doesn't close the hole.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/loading-and-cost.md"
check_file "loading-and-cost.md exists" "$doc"

# Assert the ~figure on FILE's table row is within ±10% of (chars / 4). The table keys some rows by
# install location with the source file in parens (e.g. "(from `templates/CLAUDE.md`)"), so match any
# table row (starts with "|") that mentions the backticked path — not just rows that start with it.
# Each figure-bearing row carries exactly one "~N,NNN" cell, so the lone ~number is unambiguous.
assert_figure() {
  local label="$1" file="$2" path="$REPO_ROOT/$2"
  if [ ! -f "$path" ]; then fail "$label" "missing file: $path"; return; fi

  local chars="" actual="" row="" doc_fig="" lo="" hi=""   # init all (set -u safe on bash 3.2)
  chars="$(wc -c < "$path" | tr -d ' ')"
  actual=$(( chars / 4 ))

  row="$(grep -E "^\|.*\`${file//./\\.}\`" "$doc" | head -1)"
  if [ -z "$row" ]; then fail "$label" "no table row mentions \`$file\` in loading-and-cost.md"; return; fi
  doc_fig="$(printf '%s' "$row" | grep -oE '~[0-9,]+' | tail -1 | tr -d '~, ')"
  if [ -z "$doc_fig" ]; then fail "$label" "no ~figure on the $file row of loading-and-cost.md"; return; fi

  lo=$(( actual * 9 / 10 )); hi=$(( actual * 11 / 10 ))
  if [ "$doc_fig" -ge "$lo" ] && [ "$doc_fig" -le "$hi" ]; then
    pass "$label (doc ~$doc_fig vs actual ~$actual)"
  else
    fail "$label" "doc says ~$doc_fig but actual is ~$actual tok (chars=$chars; allowed $lo..$hi)"
  fi
}

# The "commands/*.md ~LO–HI each" row quotes a range, not one figure: assert every command file's
# size falls inside the quoted [LO, HI] band, so this row can't drift unguarded either.
assert_commands_range() {
  local label="$1"
  local row="" lo="" hi="" f="" c="" tok="" bad=""   # init all (set -u safe on bash 3.2)
  row="$(grep -E '^\|.*`commands/\*' "$doc" | head -1)"
  if [ -z "$row" ]; then fail "$label" "no commands/*.md row in loading-and-cost.md"; return; fi
  # the figure cell is "~LO–HI each" (one tilde, an en-dash); read the last table cell, take its two
  # numbers as LO and HI.
  local cell; cell="$(printf '%s' "$row" | sed 's/.*|\([^|]*\)|[^|]*$/\1/')"
  lo="$(printf '%s' "$cell" | grep -oE '[0-9][0-9,]*' | head -1 | tr -d ', ')"
  hi="$(printf '%s' "$cell" | grep -oE '[0-9][0-9,]*' | tail -1 | tr -d ', ')"
  if [ -z "$lo" ] || [ -z "$hi" ] || [ "$lo" = "$hi" ]; then
    fail "$label" "couldn't parse a LO–HI range from: $row"; return
  fi
  for f in "$REPO_ROOT"/commands/*.md; do
    [ -f "$f" ] || continue
    c="$(wc -c < "$f" | tr -d ' ')"; tok=$(( c / 4 ))
    if [ "$tok" -lt "$lo" ] || [ "$tok" -gt "$hi" ]; then bad="$bad $(basename "$f")=$tok"; fi
  done
  if [ -z "$bad" ]; then pass "$label (all within ~$lo–$hi)"; else fail "$label" "outside ~$lo–$hi:$bad"; fi
}

# Every file with a quoted per-file figure in the table. Keep this list in sync with the table:
# a new figure-bearing row should get a line here (the table itself is the source of truth for sizes).
assert_figure "templates/CLAUDE.md figure within 10%"         templates/CLAUDE.md
assert_figure "templates/project-CLAUDE.md figure within 10%" templates/project-CLAUDE.md
assert_figure "FRAMEWORK.md figure within 10%"                FRAMEWORK.md
assert_figure "PRINCIPLES.md figure within 10%"               PRINCIPLES.md
assert_figure "templates/INSTANCE.md figure within 10%"       templates/INSTANCE.md
assert_figure "templates/LEARNINGS.md figure within 10%"      templates/LEARNINGS.md
assert_figure "ADAPTING.md figure within 10%"                 ADAPTING.md
assert_figure "CHANGELOG.md figure within 10%"                CHANGELOG.md
assert_commands_range "commands/*.md sizes fall inside the quoted range"

summary
