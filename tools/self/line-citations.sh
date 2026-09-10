#!/usr/bin/env bash
# tools/self/line-citations.sh — keel-self-maintenance (dir #68 exemption, per
# tools/self/prose-drift.sh's header): forbids `<tracked-file>:<line>` citations in keel's own
# tracked files. There is no consumer-facing counterpart and install.sh never ships this file.
#
# Filed dir #382, 2026-09-04/05 (v0.8.2 delta audit), after five drifted citations surfaced in a
# 20-file universe — one of them broken INSIDE that release by a pure insertion (a PR widened a
# lib's header, and a citation of that lib's line range in another file went stale with nothing
# retired), which four separate whole-read legs read past. The sharpest instance was an audit brief
# ABOUT citation drift that cited a line which had drifted, in the same document: neither care nor
# awareness of the class prevents it.
#
# WHY FORBID RATHER THAN VERIFY, decided in-session per the ticket's own "do not build both" fork,
# on a measurement rather than on taste. The tree carried 32 in-scope citations at the time this
# shipped, verified by hand against their targets: **16 were already wrong**, and 13 of those 16
# were new — found by this measurement, not by the ticket, which had listed 5 (one already fixed by
# an unrelated PR, so 3 of the 16 match the ticket's own list). None of the 16 — zero — pointed at a
# blank line or past EOF, the only drift a cheap, bounded "does the target still look plausible"
# check could catch without guessing. Every one pointed at a real, non-blank, entirely
# plausible-looking line: a comment where code was expected, a template placeholder where a promise
# was expected, a fixture where a helper was expected, a UI-dialog test case where a git-remote
# helper was expected. A verify check would have passed all 16 green — 0% recall, not a ratchet.
# Forbidding the construct is 100%, because a citation that does not exist cannot drift.
#
# THE REPLACEMENT CONVENTION, which is what makes forbidding liveable — cite something the file
# itself carries, not a coordinate that any insertion above it invalidates:
#   a shell function   ->  `tools/lib/manifest.sh`'s manifest_field()
#   a doc section      ->  `docs/delegation.md`'s "Worker rails — verbatim, do not paraphrase"
#   a named identifier ->  `tools/doctor.sh`'s W-GUARD-STALE row
# Each survives every edit that does not rename the thing being pointed at, and a rename is exactly
# the moment a reader wants the pointer to break.
#
# SCOPE, and why it is drawn structurally rather than by a hand-maintained pattern list. A token is
# in scope only when the path it names resolves to a TRACKED file — exactly (repo-relative) or as a
# unique basename among tracked files. That single test separates real citations from everything
# else at no cost and with no judgement: measured over this repo it read 166 citation-SHAPED tokens
# and kept 32, dropping every URL port, clock time, sed range, and — the case that matters — every
# test fixture that asserts on a tool's own `path:LINE` output (`doc.md:5`, `scripts/ghost.sh:42`,
# `old.txt:1`). Those name files that do not exist here, so they cannot drift and are not citations.
# A citation into a file this repo does NOT track (`BACKLOG.md:1255`, or an adopter's own
# `~/kb/LEARNINGS.md:42`) is out of scope for the same structural reason: nothing here can resolve
# it. That is a real gap, stated rather than papered over.
#
# One consequence worth knowing before writing about this check: an ILLUSTRATION of the forbidden
# shape is indistinguishable from a citation whenever the path it names happens to be real, so every
# example in this file and in its test uses a path this repo does not track. All three of this
# script's own first self-hits were exactly that — prose examples, caught by the rule they describe.
#
# CHANGELOG.md is excluded, borrowing tools/self/citation-resolvability.sh's own precedent for the
# sibling class: each dated `## [x.y.z]` section is a frozen record of what that release's own commit
# actually said, and a `path:LINE` inside it describes the tree AS IT STOOD then — rewriting it to a
# current anchor would misrepresent history, not fix it. `docs/release-history.md` is NOT given the
# same exemption despite reading like a sibling genre: it is a living, re-edited digest — each entry
# gets reworded as later runs revise the narrative — so a stale line number there is a bug in current
# prose, not a preserved historical fact, exactly like every other file this check scans.
#
# A KNOWN GAP the exemption's own reasoning exposes (found by this ticket's own /code-review high
# pass, altitude angle): the exclusion above is file-wide, but its rationale only actually covers
# the DATED sections. `## [Unreleased]` at the top of CHANGELOG.md is, by the exact same test that
# scans release-history.md, a living, re-edited section — it accumulates and gets amended across an
# entire release cycle — so a `path:LINE` citation added there today is exactly the "current prose"
# case this check exists to catch, and it is not caught, now or after that section is later dated
# and genuinely frozen. `tools/self/doctor.sh` already has the section-splitting machinery (an awk
# range keyed on `/^## \[Unreleased\]/`) this would need to close properly; left as a follow-up
# rather than built here, to keep this ticket's own scope from growing mid-review.
#
# The allowlist file is excluded because it names forbidden tokens by construction — scanning it
# would make every entry re-fire from inside its own exemption.
#
# Usage:
#   tools/self/line-citations.sh [REPO_DIR] [--quiet]
#   tools/self/line-citations.sh -h | --help
#
# REPO_DIR defaults to the current directory and may be a worktree (a worktree's tracked files are
# real, git-synced copies).
#
# Env overrides (test isolation, same shape as KEEL_CITATION_ARCHIVE_FILE et al.):
#   KEEL_LINE_CITATIONS_ALLOW   full path to the allowlist; overrides the in-repo default
#
# Exit 0 unless a non-allowlisted citation is found.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

QUIET=0
usage() {
  cat <<'EOF'
tools/self/line-citations.sh — a citation naming a tracked file AND a line number is forbidden;
cite a stable anchor (a function name, a section heading, a named identifier) instead.

Usage:
  tools/self/line-citations.sh [REPO_DIR]   scan REPO_DIR (default: current directory)
  tools/self/line-citations.sh --quiet      print only FORBIDDEN lines
  tools/self/line-citations.sh -h | --help

Exit 0 unless a non-allowlisted citation is found.
EOF
}

REPO_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "line-citations.sh: unknown flag '$1' (try --help)" >&2; exit 2 ;;
    *) REPO_ARG="$1" ;;
  esac
  shift
done
repo_dir="${REPO_ARG:-.}"
[ -d "$repo_dir" ] || { echo "line-citations.sh: not a directory: $repo_dir" >&2; exit 2; }
repo_dir="$(cd "$repo_dir" && pwd)"

say() { [ "$QUIET" = 1 ] || echo "$@"; }
say "● file:line citations ($repo_dir)"

ALLOW_REL="tools/self/line-citations-allow.txt"
allow_file="${KEEL_LINE_CITATIONS_ALLOW:-$repo_dir/$ALLOW_REL}"

work="$(mktemp -d)"
# A completion marker, not a bare `rc=$?; rm -rf …; exit "$rc"` trap: `tools/drydock/inventory.sh`'s own
# dir #264 finding, mutation-tested live on this repo's target bash (3.2.57), is that `$?` is ALREADY
# wrong by the time an EXIT trap sees it for a `set -u` unbound-variable abort — both forms exit 0 on a
# genuine crash, which is exactly the failure a checker whose only signal is its exit code cannot
# afford. `ok` set only on this script's own last line is what tells "we got there" apart from
# "something aborted before we got there" without trusting `$?` for that one class.
ok=""
cleanup() {
  citations_rc=$?
  [ -n "$ok" ] || [ "$citations_rc" -ne 0 ] || citations_rc=1
  rm -rf "$work"
  exit "$citations_rc"
}
trap cleanup EXIT
tracked="$work/tracked"; basemap="$work/basemap"; allow="$work/allow"

# `-z`, not plain `ls-files`: git C-quotes any path it cannot print literally (dir #170), the
# same trap tools/self/shellcheck-targets.sh already guards against. `tr` back to newlines (the
# `$tracked`/`$basemap` consumers below are all newline-delimited) rather than a read-loop, matching
# tools/drydock/inventory.sh's own `-z | tr '\0' '\n'` idiom for the identical conversion.
git -C "$repo_dir" ls-files -z | tr '\0' '\n' > "$tracked"
# basename<0x1f>path, one row per tracked file — 0x1f (ASCII unit separator) can't appear in a git
# path, so it splits cleanly. resolve_tracked's basename fallback counts matching rows in one pass
# rather than keeping a separate unique-basename set and re-deriving the path from it afterward.
awk -F/ '{ print $NF "\037" $0 }' "$tracked" > "$basemap"

# Allowlist: one `<citing-path> <cited-token>` pair per line. Deliberately NOT keyed by the citing
# line number — a line number in an exemption would drift under exactly the edits this check exists
# to survive, which is the defect wearing the checker's own uniform.
: > "$allow"
if [ -r "$allow_file" ]; then
  awk '{ sub(/#.*/, "") } NF == 2 { print $1, $2 }' "$allow_file" > "$allow"
  say "  allowlist: ${allow_file#"$repo_dir"/} ($(wc -l < "$allow" | tr -d '[:space:]') entry/entries)"
else
  say "  allowlist: absent ($allow_file) — every citation is a hard failure"
fi

# A path-shaped token followed by `:` and a line number, optionally `~`-approximate and optionally a
# range. One extraction pattern, shared by the prefilter, the scan, and the resolution below.
TOKEN_RE='[A-Za-z0-9_][A-Za-z0-9_./-]*:~?[0-9]+(-[0-9]+)?'

# Suffix-matched with awk on plain STRING equality, never `grep -E … | head -n1`. Two reasons, both
# found by this repo's own checks rather than by inspection: that pipeline is a SIGPIPE race under
# `pipefail` (dir #280 — `head` closes early, `grep` dies of SIGPIPE, and the pipeline's non-zero
# status aborts the whole run under `set -e`), and building a regex out of a path means escaping every
# metacharacter a filename may legally contain, where one omission silently mis-resolves instead of
# failing loudly. String comparison has neither problem.
resolve_tracked() {   # resolve_tracked PATH — prints the tracked path it names, or nothing
  if grep -qxF -- "$1" "$tracked"; then printf '%s' "$1"; return 0; fi
  case "$1" in */*) return 0 ;; esac          # a directory-bearing path only ever matches exactly
  awk -F'\037' -v b="$1" '$1 == b { n++; p = $2 } END { if (n == 1) print p }' "$basemap"
}

scanned=0; forbidden=0

while IFS= read -r f; do
  case "$repo_dir/$f" in "$repo_dir/CHANGELOG.md"|"$repo_dir/$ALLOW_REL"|"$allow_file") continue ;; esac
  [ -r "$repo_dir/$f" ] || continue
  # A cheap prefilter before the fence-blanking pass below: most tracked files (including any binary
  # asset) contain no candidate token at all, and skipping them here avoids running
  # `blank_fenced_blocks`'s awk pass — the pricier of the two — over content that can only ever come
  # back empty. Safe by construction: fence-blanking only ever REMOVES matches (it blanks fenced
  # regions), so a file this misses could never have matched after blanking either.
  grep -qE "$TOKEN_RE" -- "$repo_dir/$f" 2>/dev/null || continue
  # Fence-blanked (tools/lib/fence-blank.sh, dir #169), same as both sibling self-checks: a
  # `path:LINE` inside a fenced example — a pasted `grep -n` transcript, an illustration of this
  # very rule — is an example, not a live citation. `grep -noE` numbers each match directly, one
  # extraction pass instead of a `grep -nE` selection followed by a second `grep -oE` re-extraction
  # of the same text.
  while IFS=: read -r lno tok; do
    target="$(resolve_tracked "${tok%%:*}")"
    [ -n "$target" ] || continue
    scanned=$((scanned + 1))
    if grep -qxF -- "$f $tok" "$allow"; then
      continue
    fi
    echo "  FORBIDDEN $f:$lno cites $tok — cite a stable anchor in $target instead"
    forbidden=$((forbidden + 1))
  done < <(blank_fenced_blocks "$repo_dir/$f" | grep -noE "$TOKEN_RE" || true)
done < "$tracked"

say "  $scanned citation(s) in scope, $((scanned - forbidden)) allowlisted, $forbidden forbidden"
ok=1
exit $(( forbidden > 0 ))
