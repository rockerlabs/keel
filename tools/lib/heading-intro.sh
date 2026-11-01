# shellcheck shell=bash
# tools/lib/heading-intro.sh — keel-self-maintenance (dir #68): the one walk that finds the commit which
# introduced a markdown heading into a tracked file, shared by tools/self/doctor.sh (CHANGELOG.md's
# `## [x.y.z]`) and tests/test_release_history.sh (docs/release-history.md's `## vX.Y.Z`). Promoted out of
# those two parallel copies, which were kept in step by a comment alone and drifted apart live at the
# v0.9.0 cut (dir #428; dir #299's anchoring reached the test copy first). Same shape as
# tools/lib/fence-blank.sh, which this file sources.
#
# Sourced, not executed — no shebang, no `set -e` (inherits the caller's).

# shellcheck source=tools/lib/fence-blank.sh
. "$(dirname "${BASH_SOURCE[0]}")/fence-blank.sh"

# git_blob_text REPO VAR REV REL — dir #766: VAR = REL's text at REV, "" when REV or REL is absent there (a root commit's
# parent; a commit that has no such file), status 2 when git itself fails. Absence is asked of git by status
# (`rev-parse -q --verify` exits 1 for an unresolvable rev) and by listing (`ls-tree` prints nothing for an absent
# path), not inferred from any nonzero exit — so a git that errors reads as a failure. Limit: a parent object that
# is genuinely missing (a partial clone) still reads as an unresolvable rev, i.e. absent; a SHALLOW clone is
# skipped by the callers' own guards.
git_blob_text() {
  local repo="$1" var="$2" rev="$3" rel="$4" bt_rc=0 entry text
  git -C "$repo" rev-parse -q --verify "$rev^{commit}" >/dev/null 2>&1 || bt_rc=$?
  if [ "$bt_rc" -eq 1 ]; then printf -v "$var" ''; return 0; fi
  [ "$bt_rc" -eq 0 ] || return 2
  entry="$(git -C "$repo" ls-tree "$rev" -- "$rel")" || return 2
  if [ -z "$entry" ]; then printf -v "$var" ''; return 0; fi
  text="$(git -C "$repo" show "$rev:$rel")" || return 2
  printf -v "$var" '%s' "$text"
}

# heading_intro_commit REPO REL HEADING_RE — print the SHA of the commit that most recently introduced a line
# matching HEADING_RE (an ERE, which is also the dialect `git log -G` reads) into REL's TRACKED history in
# the git repo REPO, OUTSIDE any fenced code block — i.e. how long the section AS IT CURRENTLY STANDS has
# existed, which is what the pending-release allowance's commit-distance bound needs. The caller builds
# HEADING_RE (escape_bre_literal in regex-escape.sh builds the literal part) and owns every precondition of
# its own: doctor.sh's "HEAD has commits", the release-history test's shallow-clone bail.
#
# Status 0 with the SHA, or 0 with NOTHING printed when no candidate qualifies (the designed fail-open: the
# heading never appears in tracked history, or every candidate was a fence-only add/remove); status 2 when
# git itself failed (dir #766 — this runs inside `$( )`, where a gap() would be lost with the subshell, so
# the caller turns the status into its own verdict: doctor.sh GAPs, the test fails open).
#
# Why a newest-first walk with a per-candidate recheck (dir #156, #194, #299, #766):
# - `git log -G` (the regex pickaxe) lists every commit whose diff has an added or removed line matching
#   the heading, newest first, so the first qualifying entry is normally the commit that introduced today's
#   heading. -G, not -S: -S counts SUBSTRING occurrences, so a count-neutral commit (one that promotes an
#   inline-prose mention into the real heading, adding one and removing one) never enters the walk.
# - The pickaxe matches the file's RAW text, so a candidate can be a decoy: a commit that only added or
#   removed a FENCED example holding a literal heading. What tells them apart is whether THIS commit's own
#   diff added the heading OUTSIDE a fence: fence-blank the commit's content and its parent's, and require
#   the heading PRESENT now but ABSENT before. A presence check, not an occurrence count — a bad merge that
#   duplicated the heading would look like a "count went up" event to a counter.
# - The test is LINE-ANCHORED (the caller's HEADING_RE starts with `^`): prose has quoted a release heading
#   inline before, and an unanchored match counts that mention as the heading (dir #299, hit live at the
#   v0.9.0 cut).
# - Each blob is captured into a variable and tested with a `<<<` here-string grep, never piped into
#   `grep -q`: a pipe SIGPIPEs the writer the instant grep matches, which `pipefail` reads as "not present"
#   (dir #195's class).
# - The pickaxe also lists a commit that REMOVED a matching line (one that deleted or moved the file), so
#   the blob may be absent at $sha as well as at `$sha^`; git_blob_text tells absent from a failing git.
heading_intro_commit() {
  local repo="$1" rel="$2" heading_re="$3" intro_shas intro_rc=0 sha now before now_raw before_raw
  intro_shas="$(git -C "$repo" log -G"$heading_re" --format=%H -- "$rel" 2>/dev/null)" || intro_rc=$?
  [ "$intro_rc" -eq 0 ] || return 2
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    now_raw=""; before_raw=""   # set by git_blob_text's `printf -v` (declared for shellcheck SC2154)
    git_blob_text "$repo" now_raw "$sha" "$rel" || return 2
    git_blob_text "$repo" before_raw "$sha^" "$rel" || return 2
    now="$(blank_fenced_blocks /dev/stdin <<< "$now_raw")"
    before="$(blank_fenced_blocks /dev/stdin <<< "$before_raw")"
    if grep -qE "$heading_re" <<< "$now" && ! grep -qE "$heading_re" <<< "$before"; then
      printf '%s\n' "$sha"
      return 0
    fi
  done <<< "$intro_shas"
}
