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
  # diff's output captured first, then head -20 applied to the capture — not `diff ... | head -20`
  # (dir #280: diff is a live writer a `head` pipe could SIGPIPE under load; capturing first means
  # diff always drains to EOF, same as everywhere else this ticket applies the fix).
  diff_out="$(diff <(printf '%s' "$core_block") <(printf '%s' "$wrapper_block"))"
  fail "wrapper embeds CORE.md block byte-for-byte" \
    "blocks differ — edit rails in CORE.md, then mirror the block into templates/CLAUDE.md:$(printf '\n')$(head -20 <<< "$diff_out")"
fi

# CORE.md is consumed live (imported/symlinked) — template artifacts in it would ride into every
# session of every linked consumer. Placeholders belong to the wrapper only. (A deliberate denylist,
# not a general <…> grep: the core legitimately contains `<project>/CLAUDE.md`.)
core_content="$(cat "$core")"
for probe in "<your preference>" "(TEMPLATE)" "Copy this to your harness"; do
  check_absent "CORE.md is placeholder-free: $probe" "$core_content" "$probe"
done

# The rails state rules generally; they never name one shipped command as the carrier of a rule. A
# named exception ("e.g. `/polish`'s final step") is a specific enumeration inside a general clause —
# it forces a new bolt-on for every future command/rail collision, and it ties the tool-independent
# core to one harness's command set. Derived from commands/ so a new command is covered automatically.
# Matched as a whole slash-command token, not a substring: a plain `*/go*` would also fire on an
# ordinary branch-name example (`claude/go-69-…`), which names no command at all.
# Case-insensitive, but the leading slash stays required: a bare word match would fire on ordinary
# English ("a final polish pass"). Counted at the end — an empty glob would otherwise assert nothing
# at all and still report green, i.e. the guard silently stops guarding if commands/ is ever renamed
# or nested.
cmds_checked=0
for cmd in "$REPO_ROOT"/commands/*.md; do
  [ -f "$cmd" ] || continue
  cmds_checked=$((cmds_checked + 1))
  name="$(basename "$cmd" .md)"
  if grep -qEi "(^|[^[:alnum:]_/-])/${name}([^[:alnum:]_-]|\$)" "$core"; then
    fail "CORE.md names no specific command: /$name" "the rails must carry the rule generally, unnamed"
  else
    pass "CORE.md names no specific command: /$name"
  fi
done
if [ "$cmds_checked" -ge 1 ]; then
  pass "the command-name guard actually ran ($cmds_checked command(s) checked)"
else
  fail "the command-name guard actually ran" "no commands/*.md matched — the guard asserted nothing"
fi

summary
