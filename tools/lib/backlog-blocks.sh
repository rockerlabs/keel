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
#   carries its OWN closure tag — `(✅|❌) (DONE|CLOSED|ABSORBED|EXECUTED|SUPERSEDED|DUPLICATE|
#   BUILT)`, an em-dash before it optional (dir #432's widened, honestly-enumerated vocabulary —
#   see the function body's own header comment for the shapes measured live and the ones
#   deliberately excluded). A tag reached only via a recognised citation to a DIFFERENT ticket
#   does not count as this heading's own (dir #420/dir #426, via bb_strip_foreign_citations
#   below).
# bb_strip_foreign_citations <block> <own_num> <tag_pattern>
#   dir #426: the one shared "whose tag is it" helper — this exact strip-then-test loop shipped
#   TWICE independently before this ticket consolidated it here: once in this file's own `closed`
#   detection (the F-04 fix, dir #267) and once, near-identically, in
#   tools/self/pool-report.sh's RETRACTED exclusion (FINDING-CA3-1). Both existed to answer the
#   same question — does a `— <tag>` reached inside this heading block belong to THIS ticket
#   (own_num) or to a DIFFERENT one a recognised citation verb names? — for two different tags
#   (a closure tag here, `— RETRACTED` there).
#
#   Repeatedly strips citation clauses naming a DIFFERENT `dir #<N>` (own_num) via one of the two
#   recognised verb forms (Supersedes/Superseded/Superseding [by] dir #N, or Duplicate of dir #N)
#   followed by `— ` and tag_pattern (an ERE fragment with no surrounding anchors, e.g.
#   '(✅|❌)[[:space:]]*(DONE|CLOSED)' or 'RETRACTED') out of a COPY of block, so the caller can
#   test what remains for a bare tag without a foreign citation elsewhere in the block shadowing
#   an own tag (dir #420's own over-discard) or being wrongly counted as this ticket's own.
#
#   Loops each verb form to a fixed point rather than stopping after one match — a block citing
#   TWO different foreign tickets, whether via the same verb form twice or one of each, must have
#   both citation clauses stripped; a single `if` per form only ever strips the first (each gap a
#   real review round already found and fixed once in pool-report.sh's own prior copy of this
#   logic). `${stripped/"${BASH_REMATCH[0]}"/}` quotes the matched clause so it is treated as a
#   literal string to remove, not a glob pattern — an unquoted `${var/$pattern/}` would let a `*`
#   or `?` inside the matched clause (e.g. markdown emphasis right after a verb) strip past the
#   intended span, or not at all.
#
#   `\b` is a GNU regex extension bash's own `[[ =~ ]]` engine (BSD regex on macOS's stock bash
#   3.2) does not support; `([^a-zA-Z]|$)` is this project's established portable substitute.
#   Echoes the stripped block; the input block is untouched (a local copy is mutated).
bb_strip_foreign_citations() {
  local own_num="$2" tag_pattern="$3" stripped="$1"
  # code-review high (dir #432 delta finding, reproduced live): dir #432 made the em-dash
  # OPTIONAL in the bare-tag test a caller runs on what this function returns (a legacy heading
  # can carry its own tag with no separator at all). But these two citation regexes still
  # REQUIRED a mandatory `—` between `dir #N` and the tag — so a foreign citation that itself
  # omits the em-dash ("Duplicate of dir #9 ✅ CLOSED, no dash here") was never recognised as a
  # citation, never stripped, and the now-dash-optional bare-tag test then matched its tag as if
  # it were THIS heading's own. Reproduced: an open ticket citing a closed sibling with no dash
  # read closed=1. Fix: the separator is optional here too, so any foreign citation — dashed or
  # not — is stripped before the bare-tag test ever sees it, closing the gap the two functions'
  # optionality had drifted out of sync on.
  #
  # code-review high, a second delta finding (also reproduced live): every gap INSIDE a
  # citation match below is `[[:blank:]]` (space/tab only), not `[[:space:]]` — deliberately
  # excluding a literal newline. The pre-dir-#420 code scanned one physical LINE at a time, so a
  # citation's verb, `dir #N`, and tag could only ever be on the SAME line by construction;
  # switching to a whole-block scan (dir #420, so an own tag isn't shadowed by a LATER citation
  # elsewhere in the block) accidentally let `[[:space:]]` match the newline BETWEEN two lines
  # too, so a genuinely own, wrapped closure tag on the line right after a line that happens to
  # end in a recognised citation verb + a DIFFERENT `dir #N` ("Supersedes dir #5\n— ✅ CLOSED")
  # was misread as a citation to that different ticket and wrongly stripped — the exact "own tag"
  # this whole function exists to protect, undone by the same block-wide scan that fixes dir
  # #420. No citation in this project's own real BACKLOG.md, nor in the F-04/dir #420 test
  # suites, has ever needed to span a line break internally, so restricting these gaps to
  # same-line whitespace only closes this hole — it does not narrow anything real. The bare-tag
  # test the caller runs afterward is UNCHANGED and still scans the whole block, since THAT scan
  # is what dir #255's wrapped-heading feature and dir #420's own fix both depend on.
  #
  # A delta review round found an earlier form of this fix used `[\ \t]` — bash's own
  # quote-removal strips the backslashes from an unquoted `[[ =~ ]]` operand before the regex
  # engine ever sees them, so that class was actually just `{space, t}`: it does not match a real
  # tab byte, and it wrongly matches a stray literal `t` character. `[[:blank:]]` is the portable
  # POSIX class that means exactly "space or tab, never newline".
  while [[ "$stripped" =~ [Ss]upersed(es|ed|ing)([[:blank:]]+by)?[[:blank:]]+dir\ \#([0-9]+)[[:blank:]]*(—[[:blank:]]*)?${tag_pattern}([^a-zA-Z]|$) ]] \
    && [ "${BASH_REMATCH[3]}" != "$own_num" ]; do
    stripped="${stripped/"${BASH_REMATCH[0]}"/}"
  done
  while [[ "$stripped" =~ [Dd]uplicate\ of[[:blank:]]+dir\ \#([0-9]+)[[:blank:]]*(—[[:blank:]]*)?${tag_pattern}([^a-zA-Z]|$) ]] \
    && [ "${BASH_REMATCH[1]}" != "$own_num" ]; do
    stripped="${stripped/"${BASH_REMATCH[0]}"/}"
  done
  printf '%s' "$stripped"
}

# dir #426 (simplify pass): the closure-tag vocabulary is one fact (dir #432's honestly-enumerated
# verb list) shared by every site that needs to recognise a closure tag — this file's own `closed`
# detection, and tools/self/archive-sweep-check.sh's dated-closure check. One constant here, not a
# copy-pasted ERE literal per site, so the next vocabulary widening dir #432's own comment predicts
# is a one-line change instead of a multi-file hunt that can silently miss a site.
BB_CLOSURE_TAG_PATTERN='(✅|❌)[[:space:]]*(DONE|CLOSED|ABSORBED|EXECUTED|SUPERSEDED|DUPLICATE|BUILT)'

# bb_own_ticket_num <heading_line_or_block>
#   dir #426 (simplify pass): the "extract this heading's own `dir #N`" one-liner was copy-pasted
#   into tools/self/pool-report.sh and tools/self/archive-sweep-check.sh right after this ticket
#   consolidated the bigger strip-then-test loop into bb_strip_foreign_citations above — closing
#   the small duplicate the same way. Matches only the FIRST line's own heading (`^###\ dir\
#   \#N`), same as this file's own prior inline use; a legacy `### <n>.` heading has no `dir #N`
#   of its own and correctly returns empty (see bb_strip_foreign_citations' own_num semantics: an
#   empty own_num can never equal a cited number, so every citation in the block is still treated
#   as foreign for a legacy heading — the existing, deliberate behaviour, unchanged by this
#   extraction).
bb_own_ticket_num() {
  local text="$1" num=""
  [[ "$text" =~ ^###\ dir\ \#([0-9]+) ]] && num="${BASH_REMATCH[1]}"
  printf '%s' "$num"
}

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
  local own_num stripped_block

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
    own_num="$(bb_own_ticket_num "$heading_line")"

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
    # than whitespace/an optional "by" on either side.
    #
    # dir #420's inverse regression, now fixed by construction rather than by ordering: the
    # original shape tested one LINE at a time and `continue`d past the WHOLE line the instant a
    # foreign citation matched anywhere on it — so "dir #N — ✅ CLOSED — superseded by dir #M —
    # ✅ CLOSED" over-discarded dir #N's own, earlier tag on that same line (cited_num=M !=
    # own_num=N fired the `continue` before the own tag was ever tested). dir #426 replaces the
    # per-line scan with `bb_strip_foreign_citations`: it STRIPS only the matched foreign-citation
    # clause (any number of them) out of the WHOLE flattened block first, then tests what remains
    # for the own tag — an own tag anywhere else in the block, same line or not, survives. This is
    # the same strip-then-test shape `tools/self/pool-report.sh`'s RETRACTED exclusion already
    # shipped once (FINDING-CA3-1) before this ticket promoted it into the one shared helper both
    # now call.
    #
    # dir #432: the recognised closure vocabulary was `(DONE|CLOSED)` only, always after `— `.
    # Measured live against this project's own real BACKLOG.md: 49 closed heading blocks used a
    # different real shape and read as OPEN — `✅ ABSORBED`, `✅ EXECUTED`, `❌ SUPERSEDED`,
    # `❌ DUPLICATE`, `❌ ABSORBED`, plus `✅ DONE`/`✅ CLOSED`/`✅ BUILT` reached with NO `— `
    # separator at all (legacy `### <n>.` headings predating the convention, and a couple of
    # `### dir #N` ones). Contract decision (dir #419's own standing objection weighed against
    # dir #432's evidence): NOT the structural "any ✅/❌ in the block" test — measured live and
    # rejected, because it also fires on sub-status markers that are not the ticket's own
    # closure ("✅ RUN 1 EXECUTED" describing one run of a still-open ticket; "✅ PARTIAL, gap 2
    # only" with the ticket's own body saying gap 1 is still open) — those are real, adjacent
    # shapes on this project's own live file and a bare-glyph test cannot tell them apart from a
    # genuine close. So: the vocabulary stays enumerated, honestly widened to the seven verbs
    # actually observed live (DONE, CLOSED, ABSORBED, EXECUTED, SUPERSEDED, DUPLICATE, BUILT), and
    # the `— ` separator is made optional rather than dropped — a citation clause is still only
    # ever stripped via the two recognised verb forms below, so widening the vocabulary here only
    # grows what STRIPPING can recognise as a foreign citation's tag too, not what counts as a
    # bare own-tag hit on its own.
    #
    # Known, accepted limitations (not chased further — a delta review round kept finding more
    # missing verbs, "⛔ BLOCKED by", "merged into" among them: the same shape recurring rather
    # than shrinking, which is this project's own signal to stop enumerating and document the gap
    # instead of layering on more special cases):
    #   - the citation-verb list is not exhaustive — "Supersedes"/"superseding"/"superseded (by)"/
    #     "duplicate of" (first letter only case-insensitive — a full-caps "SUPERSEDED" is not
    #     recognised as a CITATION verb; the real file DOES use that form, but always as a
    #     ticket's own status marker like "❌ SUPERSEDED", never as a citation verb next to a
    #     `dir #N`, so this narrower gap does not currently misfire) — any other citation verb
    #     falls through to the generic tag check below, unrecognised, same as before this fix
    #     existed for that verb;
    #   - the CLOSURE-verb list (DONE/CLOSED/ABSORBED/EXECUTED/SUPERSEDED/DUPLICATE/BUILT) is also
    #     not exhaustive — a real terminal shape using a verb outside this list still reads OPEN,
    #     same false-negative direction as before this fix, just a smaller vocabulary gap;
    #   - a citation separated from its own tag by a further em-dash-bounded clause ("Supersedes
    #     dir #N — because X — ✅ CLOSED") is not caught — the looser form that WOULD catch it is
    #     what caused a real regression during review (dir #299's own tag, unrelated to a later
    #     citation on the same giant line, was wrongly discarded);
    #   - deliberately excluded from the closure vocabulary, having been checked live and found to
    #     be sub-status markers rather than whole-ticket closures: "✅ PHASE N DONE" (phase 1 of a
    #     multi-phase ticket), "✅ DECIDED" (a decision recorded, not necessarily executed), and
    #     "⏳ IN FLIGHT" (this project's own in-progress marker, the opposite of closed);
    #   - the real cure for the whole citation/own-tag ambiguity is dir #354's metadata line,
    #     tracked separately as the same subsumption family (dir #354/#403/#419/#420/#425/#426) —
    #     not chased here;
    #   - making the `— ` separator optional (dir #432, for the legacy no-separator shapes) is a
    #     block-wide relaxation, not scoped to only the blocks that actually lack a separator — a
    #     still-open ticket whose body happens to contain a glyph immediately adjacent to a
    #     recognised verb with NO separator and NO recognised citation verb in front of it (not
    #     the `RUN N EXECUTED`/`PHASE N DONE` shapes above, which the vocabulary already excludes,
    #     but a bare `✅ DONE` sitting in ordinary prose) would still misread as this ticket's own
    #     closure. Checked live against this project's own real BACKLOG.md (code-review high,
    #     altitude finding) and no such shape exists there today; not chased further for the same
    #     reason the structural "any closure glyph" alternative was rejected — a scoped-down
    #     version of that same test would only re-narrow the vocabulary problem this ticket
    #     already solved a different way.
    #
    # `\b` is a GNU regex extension bash's own `[[ =~ ]]` engine does not support on macOS's
    # stock bash 3.2 (BSD regex) — confirmed live: even a bare ASCII `CLOSED\b` fails to match
    # there, while the same pattern via `grep -E` (a separate regex implementation) does match.
    # `([^a-zA-Z]|$)` is the portable word-boundary substitute this project already uses for the
    # identical reason in harvest.sh's F-01 fix.
    closed=0
    stripped_block="$(bb_strip_foreign_citations "$heading_block" "$own_num" "$BB_CLOSURE_TAG_PATTERN")"
    if [[ "$stripped_block" =~ (—[[:space:]]*)?${BB_CLOSURE_TAG_PATTERN}([^a-zA-Z]|$) ]]; then
      closed=1
    fi

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
#
# dir #415 built a ready, dependency-free home for exactly the awk fragment above —
# tools/lib/repo-top.sh's keel_repo_main_top — for the two sites (tools/lib/impact-store.sh,
# tools/lib/transcript-usage.sh) that needed the identical FULL 3-step chain byte-for-byte, not for
# this fragment's dir #26 count in general (whose sites deliberately differ in what they do around
# it — see doctor.sh's own dir #26 comment). If this function is ever pointed at it, use
# keel_repo_main_top ALONE, never keel_repo_top: this function's own fallback (line below) stops at
# the raw $repo_root when not a worktree at all, while keel_repo_top additionally tries
# `rev-parse --show-toplevel` then `pwd -P` — a silent behavior change, not a pure rename.
backlog_root_for() {
  local repo_root="$1" main_top
  main_top="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
  printf '%s' "${main_top:-$repo_root}"
}
