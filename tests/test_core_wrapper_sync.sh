#!/usr/bin/env bash
# test_core_wrapper_sync.sh — templates/CLAUDE.md (the copy-path wrapper) embeds the consumable core
# (CORE.md) verbatim between single-line KEEL-CORE-BEGIN/END markers. That embed is hand-maintained
# duplication — exactly the drift risk the core/wrapper split created — so pin it mechanically:
# extract the marked block from both files and require byte equality. A rails edit that touches only
# one of the two files fails here. Also pin what makes CORE.md *consumable*: no template placeholders
# may ever land in it (they'd ride into every linked consumer's session).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

core="$REPO_ROOT/CORE.md"
wrapper="$REPO_ROOT/templates/CLAUDE.md"
check_file "CORE.md exists" "$core"
check_file "templates/CLAUDE.md exists" "$wrapper"

# Each marker must be a single line and appear exactly once per file — the extraction below slices
# strictly between the first BEGIN line and the first END line, so a duplicated or missing marker
# would silently extract the wrong block.
for f in "$core" "$wrapper"; do
  for m in KEEL-CORE-BEGIN KEEL-CORE-END; do
    n="$(grep -c "$m" "$f")"
    if [ "$n" = "1" ]; then
      pass "$(basename "$f") has exactly one $m"
    else
      fail "$(basename "$f") has exactly one $m" "found $n occurrences"
    fi
  done
done

# Lines strictly between the marker lines (markers excluded — their comments legitimately differ:
# the wrapper's BEGIN line says "edit in CORE.md", the core's doesn't).
block_of() { sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$1" | sed '1d;$d'; }

core_block="$(block_of "$core")"
wrapper_block="$(block_of "$wrapper")"

# Sanity that the block really is the rails, not an accidental (or empty) slice.
check_contains "core block carries the git rails" "$core_block" "## Git — mandatory rails"

# The KEEL-GIT markers fence what `install.sh --link --no-git` trims — malformed fencing would make
# the trim silently remove the wrong rails (or none). Pin: BEGIN/END counts match, the two code/git
# sections sit INSIDE the fenced blocks, and the sections that must survive a trim sit OUTSIDE.
git_begins="$(grep -c 'KEEL-GIT-BEGIN' "$core")"
git_ends="$(grep -c 'KEEL-GIT-END' "$core")"
if [ "$git_begins" = "$git_ends" ] && [ "$git_begins" -ge 1 ]; then
  pass "KEEL-GIT markers are balanced ($git_begins block(s))"
else
  fail "KEEL-GIT markers are balanced" "found $git_begins BEGIN / $git_ends END"
fi
git_blocks="$(awk '/KEEL-GIT-BEGIN/{f=1;next} /KEEL-GIT-END/{f=0;next} f' "$core")"
check_contains "git rails sit inside a KEEL-GIT block" "$git_blocks" "## Git — mandatory rails"
check_contains "reconcile-first sits inside a KEEL-GIT block" "$git_blocks" "## Before writing code"
outside_blocks="$(awk '/KEEL-GIT-BEGIN/{f=1;next} /KEEL-GIT-END/{f=0;next} !f' "$core")"
check_contains "secrets rails stay OUTSIDE the trim" "$outside_blocks" "## Secrets & personal data"
check_contains "verify discipline stays OUTSIDE the trim" "$outside_blocks" "## Verify discipline"

if [ "$core_block" = "$wrapper_block" ]; then
  pass "wrapper embeds CORE.md block byte-for-byte"
else
  fail "wrapper embeds CORE.md block byte-for-byte" \
    "blocks differ — edit rails in CORE.md, then mirror the block into templates/CLAUDE.md:$(printf '\n')$(diff <(printf '%s' "$core_block") <(printf '%s' "$wrapper_block") | head -20)"
fi

# CORE.md is consumed live (imported/symlinked) — template artifacts in it would ride into every
# session of every linked consumer. Placeholders belong to the wrapper only. (A deliberate denylist,
# not a general <…> grep: the core legitimately contains `<project>/CLAUDE.md`.)
core_content="$(cat "$core")"
for probe in "<your preference>" "(TEMPLATE)" "Copy this to your harness"; do
  check_absent "CORE.md is placeholder-free: $probe" "$core_content" "$probe"
done

summary
