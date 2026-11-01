#!/usr/bin/env bash
# test_command_descriptions.sh — dir #634: every commands/*.md opens with a frontmatter block carrying a
# non-empty one-line `description:`, so the harness lists each command with routing text, not its bare name.
# Reads ${KEEL_COMMANDS_DIR:-commands}; the mutation leg re-invokes THIS file against a scratch copy.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

cmd_dir="${KEEL_COMMANDS_DIR:-$REPO_ROOT/commands}"

# has_description FILE — frontmatter (first line `---`) holds a non-empty `description:` before its closing `---`.
has_description() {
  awk 'NR==1 { if ($0 != "---") exit 1; next }
       /^---[[:space:]]*$/ { exit found ? 0 : 1 }
       /^description:[[:space:]]*[^[:space:]]/ { found = 1 }
       END { if (!found) exit 1 }' "$1"
}

n=0
for f in "$cmd_dir"/*.md; do
  [ -f "$f" ] || continue
  n=$((n + 1))
  if has_description "$f"; then pass "$(basename "$f") has a frontmatter description"
  else fail "$(basename "$f") has a frontmatter description" "no non-empty description: in frontmatter of $f"; fi
done
[ "$n" -gt 0 ] && pass "found $n command files" || fail "found command files" "none in $cmd_dir"

if [ -z "${KEEL_COMMANDS_DIR:-}" ]; then
  m="$(mktemp -d "$SANDBOX/cmds.XXXXXX")"
  cp "$REPO_ROOT"/commands/*.md "$m"/
  sed '/^description:/d' "$m/keel-setup.md" > "$m/keel-setup.new" && mv "$m/keel-setup.new" "$m/keel-setup.md"
  run env KEEL_COMMANDS_DIR="$m" bash "$0"
  check_status "mutation: stripped description turns the pin red" 1 "$STATUS"
  check_contains "mutation: names the stripped file" "$OUT" "keel-setup.md has a frontmatter description"
fi

summary
