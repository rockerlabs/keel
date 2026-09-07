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

  # One grep pass covering both the heading and boundary regexes (the heading regex is a
  # strict subset), then split in memory — a second full-file grep pass bought nothing since
  # every heading line is already among the boundary lines this pass finds.
  local boundary_raw=()
  while IFS= read -r ln || [ -n "$ln" ]; do boundary_raw+=("$ln"); done \
    < <(grep -nE '^### (dir #[0-9]+|[0-9]+\.) |^## ' <<< "$fence_blanked")

  local heading_lines=() boundary_lines=() entry lnum ltext
  # `[ -gt 0 ]` guard, not a bare `for ... in "${boundary_raw[@]}"`: bash 3.2 (macOS's stock
  # /bin/bash) throws "unbound variable" expanding an EMPTY array under `set -u` instead of
  # iterating zero times — the same trap this project's own memory already tracks (dir #204).
  # A BACKLOG.md with no matching heading/boundary line at all (a fresh or prose-only file) hits
  # this on every run without the guard.
  if [ "${#boundary_raw[@]}" -gt 0 ]; then
    for entry in "${boundary_raw[@]}"; do
      lnum="${entry%%:*}"
      ltext="${entry#*:}"
      boundary_lines+=("$lnum")
      if [[ "$ltext" =~ ^###\ (dir\ \#[0-9]+|[0-9]+\.)\  ]]; then
        heading_lines+=("$lnum")
      fi
    done
  fi

  [ "${#heading_lines[@]}" -gt 0 ] || return 0

  local bidx=0
  local nb="${#boundary_lines[@]}"
  local start end heading_line block_end probe block_scan_end heading_block closed flat
  local own_num hb_line cited_num

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
    own_num=""
    [[ "$heading_line" =~ ^###\ dir\ \#([0-9]+) ]] && own_num="${BASH_REMATCH[1]}"

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

    # F-04 (dir #267 fixer brief): a naive `grep -qE '— ✅ ...' <<< "$heading_block"` counts a
    # DIFFERENT ticket's own closure tag too, whenever body text absorbed into the block (no blank
    # line before it) cites a sibling ("superseding dir #901 — ✅ CLOSED as a duplicate").
    #
    # This fix went through several rejected iterations — block-extension stopping, then bare
    # em-dash-adjacency scoping, then a loose verb+gap form — each one caught only by running the
    # candidate against this project's OWN real, live BACKLOG.md rather than trusting the audit's
    # synthetic examples alone; each earlier form regressed at least one real, already-closed
    # ticket. That process is the same discipline `tools/self/doctor.sh` check 5 already documents
    # going through for a related ambiguity (its own comment: "a body line that cross-references a
    # DIFFERENT ticket's status... A same-line filter on 'dir #N' was tried... but real closure
    # notes routinely co-reference a sibling ticket they also closed").
    #
    # The shipped rule: a tag counts as a DIFFERENT ticket's own only when a recognised citation
    # verb sits directly against both that ticket's `dir #N` AND the tag itself — no gap wider
    # than whitespace/an optional "by" on either side. Verified against the real BACKLOG.md: the
    # function's `closed` output is BYTE-IDENTICAL to the pre-F-04 baseline over all 423 real
    # headings, outside the two shapes F-04 was written to fix.
    #
    # Known, accepted limitations (not chased further — a delta review round kept finding more
    # missing verbs, "⛔ BLOCKED by", "merged into" among them: the same shape recurring rather
    # than shrinking, which is this project's own signal to stop enumerating and document the gap
    # instead of layering on more special cases):
    #   - the verb list below is not exhaustive — "Supersedes"/"superseding"/"superseded (by)"/
    #     "duplicate of" (first letter only case-insensitive — a full-caps "SUPERSEDED" is not
    #     recognised; the real file DOES use that form, always as a ticket's own status marker
    #     like "❌ SUPERSEDED", never as a citation verb next to a `dir #N`, so this narrower gap
    #     does not currently misfire) — covers the audit's own two documented examples plus the
    #     dominant real usage (29 lines containing "superseded" vs. 8 containing "supersedes" in
    #     this project's own BACKLOG.md today, a per-line not per-occurrence count) — any other
    #     citation verb falls through to the generic tag check below, unrecognised, same as
    #     before this fix existed for that verb;
    #   - a citation separated from its own tag by a further em-dash-bounded clause ("Supersedes
    #     dir #N — because X — ✅ CLOSED") is not caught — the looser form that WOULD catch it is
    #     what caused a real regression during review (dir #299's own tag, unrelated to a later
    #     citation on the same giant line, was wrongly discarded);
    #   - the inverse regression (dir #420): a genuinely closed ticket whose OWN `— ✅ CLOSED`
    #     tag sits earlier on the same line than a citation to a different ticket's closure
    #     ("dir #N — ✅ CLOSED — superseded by dir #M — ✅ CLOSED") is over-discarded — the
    #     citation match still fires (cited_num=M != own_num=N) and `continue`s past the whole
    #     line, so the own tag that already matched earlier in that same line is never reached.
    #     Verified live: such a line reports closed=0 for a ticket that is in fact closed. The
    #     real cure is dir #354's metadata line, tracked separately; not chased here for the same
    #     reason as the two limitations above.
    #
    # `\b` is a GNU regex extension bash's own `[[ =~ ]]` engine does not support on macOS's
    # stock bash 3.2 (BSD regex) — confirmed live: even a bare ASCII `CLOSED\b` fails to match
    # there, while the same pattern via `grep -E` (a separate regex implementation) does match.
    # `([^a-zA-Z]|$)` is the portable word-boundary substitute this project already uses for the
    # identical reason in harvest.sh's F-01 fix.
    closed=0
    while IFS= read -r hb_line; do
      cited_num=""
      if [[ "$hb_line" =~ [Ss]upersed(es|ed|ing)([[:space:]]+by)?[[:space:]]+dir\ \#([0-9]+)[[:space:]]*—\ ✅\ (DONE|CLOSED) ]]; then
        cited_num="${BASH_REMATCH[3]}"
      elif [[ "$hb_line" =~ [Dd]uplicate\ of[[:space:]]+dir\ \#([0-9]+)[[:space:]]*—\ ✅\ (DONE|CLOSED) ]]; then
        cited_num="${BASH_REMATCH[1]}"
      fi
      if [ -n "$cited_num" ] && [ "$cited_num" != "$own_num" ]; then
        continue
      fi
      if [[ "$hb_line" =~ —\ ✅\ (DONE|CLOSED)([^a-zA-Z]|$) ]]; then
        closed=1
        break
      fi
    done <<< "$heading_block"

    flat="$(tr '\n\t' '  ' <<< "$heading_block")"
    printf '%s\t%s\t%s\t%s\n' "$start" "$end" "$closed" "$flat"
  done
}

# backlog_root_for REPO_ROOT — resolves BACKLOG.md's home the same way
# tools/self/doctor.sh's check 5 does (dir #135): the MAIN checkout, via the first
# `worktree <path>` line of `git worktree list --porcelain`, unless that entry is bare (a
# no-op in a plain single-checkout repo). Shared here so archive-sweep-check.sh and
# pool-report.sh don't each keep their own copy of this fragment — dir #26 already tracks
# its duplication elsewhere in the tree; this keeps these two callers from adding a third
# and fourth site of their own.
backlog_root_for() {
  local repo_root="$1" main_top
  main_top="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
  printf '%s' "${main_top:-$repo_root}"
}
