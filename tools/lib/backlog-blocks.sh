# shellcheck shell=bash
# tools/lib/backlog-blocks.sh — keel-self-maintenance (dir #359 + dir #360): the one shared
# BACKLOG.md ticket-block scanner both mechanisms need. dir #359's closed-ticket line-share
# check and dir #360's pool report independently need the same heading/body-span logic
# tools/self/doctor.sh's check 5 already worked out (dir #255/#352's wrapped-heading fix) —
# building it twice would drift the same way dir #169's fence-blank toggle did before that
# consolidation. Sourced, not executed; requires blank_fenced_blocks (tools/lib/fence-blank.sh)
# already sourced by the caller.
#
# Heading coverage is DELIBERATELY wider than doctor.sh's check 5: that check only watches
# `### dir #N` headings (dir #352's own "cleanly separate second half" — the legacy `### <n>.`
# headings in the Post-release backlog section predate the ✅/⏳/RETRACTED tag convention and
# were left out of ITS staleness scope on purpose, tracked as dir #403). A line-share count or
# a pool census has no such exemption — a legacy-numbered ticket still holds real lines and can
# still sit `→ pool` — so this scanner's heading regex matches both shapes.
#
# backlog_ticket_blocks <path>
#   Emits one line per ticket heading found, TAB-separated:
#     start_line  end_line  closed(0|1)  heading_block
#   heading_block is the heading's own text (the `### ...` line plus any wrapped continuation
#   lines up to the first blank line, dir #255) with internal newlines flattened to spaces so
#   the whole record stays one line — safe to read with `IFS=$'\t' read -r`. end_line is the
#   ticket's full body-span end (next ticket heading or a `## ` section break, whichever comes
#   first), the same boundary rule doctor.sh check 5 uses. closed=1 iff the heading block
#   carries a `— ✅ (DONE|CLOSED)` tag.
backlog_ticket_blocks() {
  local file="$1"
  [ -f "$file" ] && [ -r "$file" ] || return 0

  local fence_blanked
  fence_blanked="$(blank_fenced_blocks "$file")"

  local stripped_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do stripped_lines+=("$ln"); done \
    < <(sed -E 's/`[^`]*`//g' <<< "$fence_blanked")
  local total_lines="${#stripped_lines[@]}"

  local heading_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do heading_lines+=("$ln"); done \
    < <(grep -nE '^### (dir #[0-9]+|[0-9]+\.) ' <<< "$fence_blanked" | cut -d: -f1)

  local boundary_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do boundary_lines+=("$ln"); done \
    < <(grep -nE '^### (dir #[0-9]+|[0-9]+\.) |^## ' <<< "$fence_blanked" | cut -d: -f1)

  [ "${#heading_lines[@]}" -gt 0 ] || return 0

  local bidx=0
  local nb="${#boundary_lines[@]}"
  local start end heading_line block_end probe block_scan_end heading_block closed flat

  for start in "${heading_lines[@]}"; do
    while [ "$bidx" -lt "$nb" ] && [ "${boundary_lines[$bidx]}" -le "$start" ]; do
      bidx=$((bidx + 1))
    done
    end="$total_lines"
    [ "$bidx" -lt "$nb" ] && end=$(( boundary_lines[bidx] - 1 ))

    heading_line="${stripped_lines[$((start - 1))]}"

    # dir #255: a heading whose title text wraps across physical source lines can carry its
    # terminal tag on a continuation line, not the `### ...` line itself — build the whole
    # heading block (up to the first blank line, capped at 50 lines past start) and test that.
    block_end="$start"
    probe=$((start + 1))
    block_scan_end="$end"
    [ $((start + 50)) -lt "$end" ] && block_scan_end=$((start + 50))
    while [ "$probe" -le "$block_scan_end" ] && [ -n "${stripped_lines[$((probe - 1))]}" ]; do
      block_end="$probe"
      probe=$((probe + 1))
    done
    if [ "$block_end" -eq "$start" ]; then
      heading_block="$heading_line"
    else
      heading_block="$(printf '%s\n' "${stripped_lines[@]:$((start - 1)):$((block_end - start + 1))}")"
    fi

    closed=0
    grep -qE '— ✅ (DONE|CLOSED)\b' <<< "$heading_block" && closed=1

    flat="$(tr '\n\t' '  ' <<< "$heading_block")"
    printf '%s\t%s\t%s\t%s\n' "$start" "$end" "$closed" "$flat"
  done
}
