#!/usr/bin/env bash
# test_doc_figures.sh — every per-file token figure quoted in docs/loading-and-cost.md (and the README's
# diagram) must stay close to the real file size by the doc's own ruler (~4 chars/token), plus the
# doc-coupling pins that keep prose references (droppable-section headings) in sync with the template.
# A methodology selling honest token accounting can't ship a stale number. This guards EVERY
# figure-bearing row, not a subset: a prior pass left FRAMEWORK.md understated, and a partial guard then
# let CHANGELOG.md drift the same way — so the lock has to cover all of them or it doesn't close the hole.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doc="$REPO_ROOT/docs/loading-and-cost.md"
check_file "loading-and-cost.md exists" "$doc"

# One ruler for every guard below: ~4 chars/token, the same estimate doctor.sh uses. One copy, so the
# guards can't diverge from each other (this idiom used to be pasted per-function).
tok_of() { local c; c="$(wc -c < "$1" | tr -d ' ')"; echo $(( c / 4 )); }

# Shared ±10% verdict: the quoted figure FIG (from SRCDESC) vs the file's ACTUAL token estimate.
# dir #73: a figure that still passes but has nearly drifted out of the band fails silently — the next
# edit to the same file (by anyone, for any reason) red-lights CI on a figure it never touched. Warn
# early instead: once the remaining margin (on the side being consumed) has shrunk to <~3% of actual —
# i.e. drift has eaten >~70% of the ±10% half-band — print a non-failing note so the PR that caused the
# drift is the one that restates the figure.
assert_band() {
  local label="$1" fig="$2" actual="$3" srcdesc="$4"
  local lo="" hi="" edge="" margin="" threshold=""   # init all (set -u safe on bash 3.2)
  lo=$(( actual * 9 / 10 )); hi=$(( actual * 11 / 10 ))
  if [ "$fig" -ge "$lo" ] && [ "$fig" -le "$hi" ]; then
    pass "$label ($srcdesc ~$fig vs actual ~$actual)"
    edge=$(( hi - fig )); margin=$(( fig - lo )); [ "$edge" -lt "$margin" ] && margin="$edge"
    threshold=$(( actual * 3 / 100 ))
    if [ "$margin" -lt "$threshold" ]; then
      printf '  note  %s: %s ~%s vs actual ~%s — only %s tok of headroom, restate the figure\n' \
        "$label" "$srcdesc" "$fig" "$actual" "$margin"
    fi
  else
    fail "$label" "$srcdesc says ~$fig but actual is ~$actual tok (allowed $lo..$hi)"
  fi
}

# table_row_for FILE — print FILE's own File-by-file table row in loading-and-cost.md, or nothing if
# no row mentions it. Factored out of assert_figure so assert_derived_quoted_sum below can reuse the
# SAME row-lookup instead of re-deriving it from the actual file (dir #167: the ~16.4K one-off line
# must track the TABLE's own quoted addends, so a mismatch is caught even when neither individual
# figure has drifted from its file).
table_row_for() { grep -E "^\|.*\`${1//./\\.}\`" "$doc" | head -1; }

# table_fig_for FILE — print the lone "~N,NNN" figure quoted on FILE's table row (digits only, no
# "~"/","), or nothing if no such row/figure exists.
table_fig_for() {
  local row; row="$(table_row_for "$1")"
  [ -z "$row" ] && return
  printf '%s' "$row" | grep -oE '~[0-9,]+' | tail -1 | tr -d '~, '
}

# Assert the ~figure on FILE's table row is within ±10% of (chars / 4). The table keys some rows by
# install location with the source file in parens (e.g. "(from `templates/CLAUDE.md`)"), so match any
# table row (starts with "|") that mentions the backticked path — not just rows that start with it.
# Each figure-bearing row carries exactly one "~N,NNN" cell, so the lone ~number is unambiguous.
assert_figure() {
  local label="$1" file="$2" path="$REPO_ROOT/$2"
  if [ ! -f "$path" ]; then fail "$label" "missing file: $path"; return; fi

  local actual="" row="" doc_fig=""   # init all (set -u safe on bash 3.2)
  actual="$(tok_of "$path")"

  row="$(table_row_for "$file")"
  if [ -z "$row" ]; then fail "$label" "no table row mentions \`$file\` in loading-and-cost.md"; return; fi
  doc_fig="$(printf '%s' "$row" | grep -oE '~[0-9,]+' | tail -1 | tr -d '~, ')"
  if [ -z "$doc_fig" ]; then fail "$label" "no ~figure on the $file row of loading-and-cost.md"; return; fi

  # A "~N,NNN+" figure is an open-ended FLOOR — for a monotonically-growing file (CHANGELOG), assert the
  # real size is AT LEAST the floor (never an overclaim) with no upper bound, so steady growth doesn't force
  # a figure bump on every PR. A plain "~N,NNN" is still held to ±10%.
  if printf '%s' "$row" | grep -qE '~[0-9,]+\+'; then
    if [ "$actual" -ge "$doc_fig" ]; then
      pass "$label (doc ~$doc_fig+ floor vs actual ~$actual)"
      # dir #105: an open floor has no failing upper bound BY DESIGN (raising it resets the clock
      # without closing the hole — CHANGELOG.md sat at a ~25,000+ floor while the real file reached
      # ~44,600, passing CI the whole time). Once actual has drifted to 25%+ above the floor, print a
      # non-failing note — same shape as assert_band's near-band note — so the drift becomes visible
      # without turning the floor back into a bump-every-PR ceiling.
      if [ "$actual" -gt "$(( doc_fig * 5 / 4 ))" ]; then
        # The computed percentage is (actual-floor)/floor — i.e. "actual exceeds the floor by X%",
        # not "the floor is X% below actual" (that would need actual, not the floor, as the
        # denominator — a different number; found in review). Word it to match what's computed.
        printf '  note  %s: actual ~%s is now %s%% above the doc floor ~%s+ — consider raising the floor\n' \
          "$label" "$actual" "$(( (actual - doc_fig) * 100 / doc_fig ))" "$doc_fig"
      fi
    else
      fail "$label" "doc floor ~$doc_fig+ but actual is only ~$actual tok — lower the floor"
    fi
    return
  fi

  assert_band "$label" "$doc_fig" "$actual" "doc"
}

# The "commands/*.md ~LO-HI each" row quotes a range, not one figure: assert every command file's
# size falls inside the quoted [LO, HI] band, so this row can't drift unguarded either.
# A trailing "+" on HI ("~LO-HI+ each") makes the upper bound an open floor — the same growth-tolerant
# semantics assert_figure gives the monotonic CHANGELOG row. Commands only grow (procedures accrete
# steps), so a command nudging past HI shouldn't force a doc bump on every PR; understating your own
# ceiling behind an explicit "+" is never an overclaim of cheapness. The LO bound stays enforced so the
# quoted floor can't drift above the smallest command.
assert_commands_range() {
  local label="$1"
  local row="" lo="" hi="" f="" tok="" bad="" open_upper=""   # init all (set -u safe on bash 3.2)
  row="$(grep -E '^\|.*`commands/\*' "$doc" | head -1)"
  if [ -z "$row" ]; then fail "$label" "no commands/*.md row in loading-and-cost.md"; return; fi
  # the figure cell is "~LO-HI each" (one tilde, an en-dash); read the last table cell, take its two
  # numbers as LO and HI.
  local cell; cell="$(printf '%s' "$row" | sed 's/.*|\([^|]*\)|[^|]*$/\1/')"
  lo="$(printf '%s' "$cell" | grep -oE '[0-9][0-9,]*' | head -1 | tr -d ', ')"
  hi="$(printf '%s' "$cell" | grep -oE '[0-9][0-9,]*' | tail -1 | tr -d ', ')"
  if [ -z "$lo" ] || [ -z "$hi" ] || [ "$lo" = "$hi" ]; then
    fail "$label" "couldn't parse a LO-HI range from: $row"; return
  fi
  # HI carries a trailing "+" → open ceiling: enforce only the LO floor per file.
  if printf '%s' "$cell" | grep -qE '[0-9][0-9,]*\+'; then open_upper=1; fi
  for f in "$REPO_ROOT"/commands/*.md; do
    [ -f "$f" ] || continue
    tok="$(tok_of "$f")"
    if [ "$tok" -lt "$lo" ]; then bad="$bad $(basename "$f")=$tok"; continue; fi
    if [ -z "$open_upper" ] && [ "$tok" -gt "$hi" ]; then bad="$bad $(basename "$f")=$tok"; fi
  done
  local rangedesc="~$lo-$hi"; [ -n "$open_upper" ] && rangedesc="~$lo-$hi+ (open upper)"
  if [ -z "$bad" ]; then pass "$label (all within $rangedesc)"; else fail "$label" "outside $rangedesc:$bad"; fi
}

# README.md's mermaid "How it works" diagram quotes its own rounded ~N.NK figures for the same files —
# a separate line from loading-and-cost.md's table, so assert_figure's table-row grep never reaches it.
# That's exactly how FRAMEWORK.md's figure went stale (~4.2K in README vs ~5.0K real) while the
# loading-and-cost.md row stayed guarded — close the same hole here.
assert_readme_figure() {
  local label="$1" file="$2" pattern="$3" path="$REPO_ROOT/$2" readme="$REPO_ROOT/README.md"
  if [ ! -f "$path" ]; then fail "$label" "missing file: $path"; return; fi

  local actual="" line="" fig_raw="" fig=""   # init all (set -u safe on bash 3.2)
  actual="$(tok_of "$path")"

  line="$(grep -E "$pattern" "$readme" | head -1)"
  if [ -z "$line" ]; then fail "$label" "no line matching /$pattern/ in README.md"; return; fi
  fig_raw="$(printf '%s' "$line" | grep -oE '~[0-9]+(\.[0-9]+)?K' | tail -1)"
  if [ -z "$fig_raw" ]; then fail "$label" "no ~N[.N]K figure on the matched README.md line: $line"; return; fi
  # LC_ALL=C: awk parses "1.8" by locale — a comma-decimal locale would read it as 1 and false-fail.
  fig="$(printf '%s' "$fig_raw" | tr -d '~K' | LC_ALL=C awk '{printf "%d", $1*1000}')"

  assert_band "$label" "$fig" "$actual" "README"
}

# dir #105 (2nd instance): docs/loading-and-cost.md DERIVES two prose figures from its own quoted
# "Globally, any session" core figure rather than from a file — "~50 sessions ... ~110K input tokens
# total" (50x the core) and "~200K-token context window means the core is ~1.1%" (core / 200K). The
# guards above check quoted-vs-actual for FILE SIZES and know nothing about a derivation, so if the
# core figure is ever bumped, both sentences go stale silently (drift is bounded — the core row is
# itself guarded at +-10% — but not zero). Pin the derivation itself: read the SAME quoted core figure
# the prose is computed from, recompute, and assert the printed figures still track it.
assert_derived_core_figures() {
  local core_line="" core_fig=""   # init all (set -u safe on bash 3.2)
  core_line="$(grep -E 'Globally, any session:' "$doc" | head -1)"
  if [ -z "$core_line" ]; then
    fail "loading-and-cost.md derived figures" "no 'Globally, any session:' line to derive from"
    return
  fi
  core_fig="$(printf '%s' "$core_line" | grep -oE '~[0-9,]+' | head -1 | tr -d '~, ')"
  if [ -z "$core_fig" ]; then
    fail "loading-and-cost.md derived figures" "no ~figure on the 'Globally, any session' line"
    return
  fi

  # ~N sessions x core -> ~NNNK input tokens total
  local sess_line="" n_sessions="" fig_raw="" fig="" expected=""
  sess_line="$(grep -E 'always-loaded core is ~[0-9]+(\.[0-9]+)?K input tokens total' "$doc" | head -1)"
  if [ -z "$sess_line" ]; then
    fail "loading-and-cost.md ~N-sessions total tracks the core figure" "no '~NK input tokens total' line found"
  else
    n_sessions="$(printf '%s' "$sess_line" | grep -oE '~[0-9]+ sessions' | grep -oE '[0-9]+')"
    fig_raw="$(printf '%s' "$sess_line" | grep -oE '~[0-9]+(\.[0-9]+)?K input tokens total' | grep -oE '~[0-9]+(\.[0-9]+)?K')"
    fig="$(printf '%s' "$fig_raw" | tr -d '~K' | LC_ALL=C awk '{printf "%d", $1*1000}')"
    if [ -z "$n_sessions" ] || [ -z "$fig" ]; then
      fail "loading-and-cost.md ~N-sessions total tracks the core figure" "couldn't parse: $sess_line"
    else
      expected=$(( core_fig * n_sessions ))
      assert_band "loading-and-cost.md ~$n_sessions-sessions total tracks ~$core_fig x $n_sessions" "$fig" "$expected" "doc"
    fi
  fi

  # core / 200K window -> ~N.N% (compared in permille so the check stays integer-only)
  local win_line="" window_tokens="" pct_raw="" pct_permille="" expected_permille=""
  win_line="$(grep -E 'context window means the core is' "$doc" | head -1)"
  if [ -z "$win_line" ]; then
    fail "loading-and-cost.md window-% tracks the core figure" "no 'context window means the core is' line found"
  else
    window_tokens="$(printf '%s' "$win_line" | grep -oE '~[0-9]+K-token' | grep -oE '[0-9]+')"
    pct_raw="$(printf '%s' "$win_line" | grep -oE '~[0-9]+(\.[0-9]+)?%' | tr -d '~%')"
    if [ -z "$window_tokens" ] || [ -z "$pct_raw" ]; then
      fail "loading-and-cost.md window-% tracks the core figure" "couldn't parse: $win_line"
    else
      pct_permille="$(printf '%s' "$pct_raw" | LC_ALL=C awk '{printf "%d", $1*10 + 0.5}')"
      # permille = core_fig*1000 / (window_tokens*1000); window_tokens is already in K (parsed from
      # "~200K-token"), so the two *1000s cancel algebraically to plain division — written that way,
      # not as the no-op-looking multiply/divide, so it doesn't read as a scaling step that matters.
      expected_permille=$(( core_fig / window_tokens ))
      assert_band "loading-and-cost.md ~$pct_raw% tracks ~$core_fig / ~${window_tokens}K" \
        "$pct_permille" "$expected_permille" "doc (permille)"
    fi
  fi
}
assert_derived_core_figures

# dir #167: "Even if you do open FRAMEWORK + PRINCIPLES together (rare), that's a one-off ~16.4K for
# one decision" is arithmetic, not a file-size figure — assert_figure above pins each addend against
# its OWN file, but nothing ever re-derives the SUM from those addends. A prior version of this line
# said "~12K" against the same table's own ~10,500 + ~5,950 (= ~16,450); PR #211 fixed the printed
# figure by hand, but the arithmetic itself stayed unguarded, so the same drift can recur silently. Sum
# the TABLE's own quoted figures for the two files (not their actual on-disk sizes — table_fig_for, not
# tok_of) and assert the one-off line still tracks that sum within the usual ±10% band.
assert_derived_quoted_sum() {
  local label="loading-and-cost.md ~16.4K FRAMEWORK+PRINCIPLES sum tracks its own quoted addends"
  local fw_fig="" pr_fig="" line="" fig_raw="" fig="" expected=""   # init all (set -u safe on bash 3.2)
  fw_fig="$(table_fig_for FRAMEWORK.md)"
  pr_fig="$(table_fig_for PRINCIPLES.md)"
  if [ -z "$fw_fig" ] || [ -z "$pr_fig" ]; then
    fail "$label" "couldn't read both quoted addends (FRAMEWORK.md=$fw_fig PRINCIPLES.md=$pr_fig)"
    return
  fi
  line="$(grep -E 'open .?FRAMEWORK.? \+ .?PRINCIPLES.? together' "$doc" | head -1)"
  if [ -z "$line" ]; then
    fail "$label" "no 'open FRAMEWORK + PRINCIPLES together' line found"
    return
  fi
  fig_raw="$(printf '%s' "$line" | grep -oE '~[0-9]+(\.[0-9]+)?K' | tail -1)"
  if [ -z "$fig_raw" ]; then
    fail "$label" "no ~N[.N]K figure on the matched line: $line"
    return
  fi
  fig="$(printf '%s' "$fig_raw" | tr -d '~K' | LC_ALL=C awk '{printf "%d", $1*1000}')"
  expected=$(( fw_fig + pr_fig ))
  assert_band "$label" "$fig" "$expected" "doc: ~$fw_fig + ~$pr_fig"
}
assert_derived_quoted_sum

# Every file with a quoted per-file figure in the table. Keep this list in sync with the table:
# a new figure-bearing row should get a line here (the table itself is the source of truth for sizes).
assert_figure "templates/CLAUDE.md figure within 10%"         templates/CLAUDE.md
assert_figure "CORE.md figure within 10%"                     CORE.md
assert_figure "templates/project-CLAUDE.md figure within 10%" templates/project-CLAUDE.md
assert_figure "FRAMEWORK.md figure within 10%"                FRAMEWORK.md
assert_figure "PRINCIPLES.md figure within 10%"               PRINCIPLES.md
assert_figure "templates/INSTANCE.md figure within 10%"       templates/INSTANCE.md
assert_figure "templates/LEARNINGS.md figure within 10%"      templates/LEARNINGS.md
assert_figure "templates/IDEAS.md figure within 10%"          templates/IDEAS.md
assert_figure "ADAPTING.md figure within 10%"                 ADAPTING.md
assert_figure "CHANGELOG.md figure within 10%"                CHANGELOG.md
assert_commands_range "commands/*.md sizes fall inside the quoted range"

assert_readme_figure "README FRAMEWORK.md figure within 10%"       FRAMEWORK.md         'FRAMEWORK\.md \(~[0-9.]+K\)'
assert_readme_figure "README PRINCIPLES.md figure within 10%"      PRINCIPLES.md        'PRINCIPLES\.md \(~[0-9.]+K\)'
assert_readme_figure "README always-loaded core figure within 10%" templates/CLAUDE.md 'Always loaded.*~[0-9.]+K tokens'
assert_readme_figure "README Economy bullet core figure within 10%" templates/CLAUDE.md 'Economy\.\*\* A thin, stable core \(~[0-9.]+K tokens\)'

# /keel-setup step 3 and ADAPTING.md tell a no-git adopter which two template sections to drop BY NAME —
# a heading rename in templates/CLAUDE.md would strand those instructions silently. Pin BOTH legs of the
# coupling: the heading must exist in the template AND still be quoted by the trim instruction (the
# keel-setup quote may be line-wrapped, so whitespace is normalized before matching). ADAPTING.md
# paraphrases rather than quotes, so it can't be pinned mechanically.
for h in "Git — mandatory rails" "Before writing code — reconcile first"; do
  if grep -q "^## $h" "$REPO_ROOT/templates/CLAUDE.md"; then
    pass "template has droppable heading: $h"
  else
    fail "template has droppable heading: $h" "renamed in templates/CLAUDE.md? update commands/keel-setup.md + ADAPTING.md + this list"
  fi
  if tr -s '[:space:]' ' ' < "$REPO_ROOT/commands/keel-setup.md" | grep -qF "$h"; then
    pass "keel-setup trim quotes the heading: $h"
  else
    fail "keel-setup trim quotes the heading: $h" "the trim instruction no longer names this section"
  fi
done

# dir #167 / P6-2: docs/getting-started.md's "What just got set up" table (the config-folder files an
# install leaves behind) and loading-and-cost.md's "File by file" table both enumerate on-demand config
# files, but nothing ever checked they name the SAME set — a same-batch fix (PR #211) added an
# `IDEAS.md` row to getting-started.md's table without adding the matching row here, and no test caught
# it. Read every backticked `*.md` filename out of getting-started.md's "What just got set up" table
# (the section between its own heading and the next `##`) and assert each one has a matching row
# (backticked, any path prefix) in loading-and-cost.md's File-by-file table — the direction that matters,
# since loading-and-cost.md is the comprehensive page and legitimately covers files (CORE.md,
# `<project>/CLAUDE.md`, ADAPTING.md, CHANGELOG.md, commands/*.md) that getting-started.md's narrower
# "what got installed" table has no reason to repeat.
gs_doc="$REPO_ROOT/docs/getting-started.md"
check_file "getting-started.md exists" "$gs_doc"

setup_table="$(awk '/^## 2\. What just got set up/{f=1; next} /^## /{f=0} f && /^\|/' "$gs_doc")"
if [ -z "$setup_table" ]; then
  fail "getting-started.md 'What just got set up' table found" "no '## 2. What just got set up' section"
else
  pass "getting-started.md 'What just got set up' table found"
  gs_files="$(printf '%s' "$setup_table" | grep -oE '`[A-Za-z0-9_.-]+\.md`' | tr -d '`' | sort -u)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if grep -qE "^\|.*\`([^\`]*/)?${f//./\\.}\`" "$doc"; then
      pass "loading-and-cost.md File-by-file table has a row for $f (getting-started.md parity)"
    else
      fail "loading-and-cost.md File-by-file table has a row for $f (getting-started.md parity)" \
        "getting-started.md's setup table lists \`$f\` but no loading-and-cost.md row mentions it"
    fi
  done <<< "$gs_files"
fi

summary
