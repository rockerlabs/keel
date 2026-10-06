# shellcheck shell=bash
# tools/lib/agent-floor.sh (dir #413) — the ONE reader of a Claude Code agent file's frontmatter, for the
# structural-floor checks on agents/keel-polish-reviewer.md: tests/test_review_agent.sh pins the shipped
# file with it and tools/doctor.sh's W-REVIEW-AGENT-FLOOR audits an installed copy with it, so the test's
# reader and the doctor's cannot drift apart.
#
# Only the FRONTMATTER is read: the block between the file's first line (`---`) and the next `---`. A
# `tools:` line in the body is prose, never the allowlist. Sourced, not executed — no set -e.

# agent_fm_lines FILE — the frontmatter lines (without the fences); empty when FILE has none.
agent_fm_lines() {
  awk 'NR == 1 { if ($0 != "---") exit; next } /^---[[:space:]]*$/ { exit } { print }' "$1" 2>/dev/null
}

# agent_fm_keys FILE — every top-level key of the frontmatter, one per line, duplicates kept.
agent_fm_keys() {
  agent_fm_lines "$1" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_-]*\):.*/\1/p'
}

# agent_fm_value FILE KEY — the value of the FIRST `KEY:` line, trimmed; empty when absent.
agent_fm_value() {
  agent_fm_lines "$1" | awk -v k="$2" '
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit }'
}

# _agent_tool_set VALUE — a comma list normalised to a sorted, space-free, one-per-line set.
_agent_tool_set() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | sort
}

# agent_floor_problem FILE SHIPPED_TOOLS — prints ONE line naming why FILE's tool floor is not the
# shipped one, nothing when it holds. A floor is: the file exists; exactly one `tools:` line; the plain
# comma form (a flow list `[Read, Grep, Glob]` is not it); the same tool SET as SHIPPED_TOOLS; and none of
# Bash/Write/Edit/NotebookEdit/Agent (named explicitly so an edit of the shipped set itself still cannot
# hand them back). An unset `tools:` grants every tool, so a missing line is a failure.
agent_floor_problem() {
  local f="$1" shipped="$2" n val t
  [ -f "$f" ] || { echo "file is missing"; return 0; }
  n="$(agent_fm_keys "$f" | grep -cx tools || true)"
  if [ "$n" = 0 ]; then echo "no tools: line in the frontmatter (an unset tools: grants every tool)"; return 0; fi
  if [ "$n" != 1 ]; then echo "$n tools: lines in the frontmatter (exactly one is allowed)"; return 0; fi
  val="$(agent_fm_value "$f" tools)"
  case "$val" in
    *'['*|*']'*|*'"'*|*"'"*) echo "tools: is not the plain one-line comma form ($val)"; return 0 ;;
  esac
  for t in Bash Write Edit NotebookEdit Agent; do
    if _agent_tool_set "$val" | grep -qx "$t"; then echo "tools: grants $t ($val)"; return 0; fi
  done
  if [ "$(_agent_tool_set "$val")" != "$(_agent_tool_set "$shipped")" ]; then
    echo "tools: is '$val', not the shipped '$shipped'"; return 0
  fi
  return 0
}
