#!/usr/bin/env bash
# test_core_capability_index.sh — dir #371: CORE.md's "Shipped docs — situation, not summary" section
# is the always-on trigger-condition index that lets a session reach a shipped `docs/*.md` procedure it
# was never told about. Two failure modes this pins against, neither caught elsewhere:
#   1. A `docs/*.md` file named in the index gets renamed or removed — the index then points nowhere,
#      silently. Not caught by tools/self/prose-drift.sh's dead-link sweep: these are bare backtick
#      mentions (`docs/foo.md`), not `[text](target)` markdown links, by design (this same text is
#      byte-mirrored into templates/CLAUDE.md at templates/, where a relative markdown link would
#      resolve to the wrong directory — see CORE.md's own file-map section for the same convention).
#   2. The section quietly grows back into the "summary, not trigger" shape dir #371 explicitly warns
#      against — every entry must stay a one-line "situation → doc" pointer, and the entry COUNT is
#      pinned so a future addition is a deliberate, re-measured decision (bump the count here, then
#      re-run tests/test_doc_figures.sh, which pins CORE.md's and templates/CLAUDE.md's token figures
#      in docs/loading-and-cost.md within +-10% of actual).
# Byte-identity with templates/CLAUDE.md is already pinned generically by test_core_wrapper_sync.sh
# (the whole KEEL-CORE block, this section included) — not re-checked here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

core="$REPO_ROOT/CORE.md"
check_file "CORE.md exists" "$core"

heading='## Shipped docs — situation, not summary'

# check_count (tests/lib.sh) for the occurrence check — a bare BRE, same contract as its 3
# pre-existing call sites (none of which escape their own pattern text either; interpolating $heading
# unescaped shares their exact accepted risk, not a new class of one — dir #371 /code-review high,
# removed-behavior finding: the ORIGINAL exact-string `awk '$0==h'` this replaced couldn't misfire on
# a metacharacter, but nothing in this codebase's own literal-heading-text patterns ever has one).
# section_body() (tests/lib.sh) slices the section body separately — promoted alongside check_count()
# once this became its 2nd call site (tests/test_doc_figures.sh:320 is the 1st), same "second use =
# promote" convention, left un-retrofitted there for the same reason check_count()'s 3 pre-existing
# sites were: it already pipes into its own tuned filter. A single awk pass that smuggled the count
# out via a sentinel line was tried and reverted (dir #371 /code-review high, efficiency +
# simplification findings): the unpacking code to strip the sentinel back out cost more than the
# second, sub-millisecond scan of a few-KB file it was avoiding.
check_count "CORE.md has exactly one '$heading' heading" "$core" "^$heading\$" 1
section="$(section_body "$heading" "$core")"

if [ -z "$section" ]; then
  fail "CORE.md capability-index section body is non-empty" "no lines found between the heading and the next '## ' heading"
fi

# Every trigger line is a top-level bullet of the shape "- <situation> -> \`docs/<file>.md\`". Extract
# the doc path from each bullet rather than hardcoding the list here, so a wording edit to the
# SITUATION half never needs a matching edit to this test — only a doc path rename/removal does.
# grep -oE, not a per-line `case` match (dir #371 /code-review high, correctness note): a bullet with
# TWO backticked docs/*.md mentions must still surface as a path-count mismatch below, and grep -oE
# is the one form that finds every non-overlapping match per line rather than only the first — folding
# this into the bullet loop below would trade one scan of the whole section for one grep spawn PER
# bullet line, the opposite of that loop's own win, so it stays its own pass on purpose.
# match(), tests/lib.sh's here-string wrapper, not a raw `<<<` (dir #371 /code-review high,
# reuse finding: the prior round's comment already claimed this idiom without actually calling it).
doc_paths="$(match "$section" -oE '`docs/[a-zA-Z0-9_-]+\.md`' | tr -d '`')"
n_paths="$(match "$doc_paths" -c .)"

# One pass counts bullets AND finds the longest one (merged with the length-cap loop below, dir #371
# /code-review high, efficiency + simplification findings — a separate `grep -c '^- '` call here was
# re-deriving "is this line a bullet" over the same $section text the loop below already walks for
# the same purpose).
bullets=0
max_len=0
too_long=""
while IFS= read -r line; do
  case "$line" in
    '- '*)
      bullets=$((bullets + 1))
      len="${#line}"
      [ "$len" -gt "$max_len" ] && max_len="$len"
      [ "$len" -gt 140 ] && too_long="${too_long}${too_long:+, }${len} ch"
      ;;
  esac
done <<< "$section"

# dir #371's own "trap" warning: an index that summarizes is bloat, one of trigger conditions may be
# affordable — pinned at the count this ticket shipped with. Growing it is a real, re-measured
# decision, not a silent drift, so bump this number by hand alongside a fresh token measurement.
expected_bullets=8
if [ "$bullets" = "$expected_bullets" ]; then
  pass "capability index has exactly $expected_bullets trigger bullets"
else
  fail "capability index has exactly $expected_bullets trigger bullets" \
    "found $bullets — if this is a deliberate addition, bump expected_bullets here and re-run tests/test_doc_figures.sh"
fi

if [ "$n_paths" = "$bullets" ]; then
  pass "every trigger bullet carries exactly one backticked docs/*.md path"
else
  fail "every trigger bullet carries exactly one backticked docs/*.md path" \
    "found $bullets bullet(s) but $n_paths doc path(s) — a bullet is missing its trigger target or has an extra one"
fi

# Every path the index points at must resolve to a real, tracked file — the dead-reference guard
# prose-drift.sh's markdown-link sweep does not reach (these are bare backtick mentions on purpose).
if [ -n "$doc_paths" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    check_file "capability index target exists: $p" "$REPO_ROOT/$p"
  done <<< "$doc_paths"
else
  fail "capability index names at least one docs/*.md target" "no backticked docs/*.md path found in the section"
fi

# Shape guard against summary creep (checked with the same loop that counted bullets above): a
# trigger line names a SITUATION and a target, never prose about what the target contains — a cheap
# proxy is "no bullet runs long enough to be a summary" (prose-drift already flags an outlier's
# LENGTH relative to its neighbors; this instead pins an absolute ceiling, since eight one-line
# bullets of similar length would never trip prose-drift's relative check even if every one of them
# crept out to paragraph size together).
if [ -z "$too_long" ]; then
  pass "every trigger bullet stays under 140 chars (longest: $max_len)"
else
  fail "every trigger bullet stays under 140 chars" "over the cap: $too_long"
fi

summary
