#!/usr/bin/env bash
# self/doctor.sh — structural self-audit of the KEEL REPO ITSELF (not a consumer project, not a
# consumer install — see tools/doctor.sh and tools/doctor.sh --install for those).
#
# Design: this is the single entry point for "is keel itself healthy", but it does NOT duplicate
# checks that already live elsewhere as tests — it ORCHESTRATES them (runs the existing test file,
# folds its pass/fail into this report) and adds only checks that exist nowhere else. Duplicating
# logic here would recreate the exact anti-pattern this tool exists to catch: two places holding the
# same rule that can silently drift apart (see check 1 below for a real, self-admitted example of
# that in install.sh / doctor.sh).
#
# A GAP fails the audit (exit 1); a WARN is advisory (exit stays 0 unless a GAP also fired).
#
# Native checks (logic lives only here):
#   GAP   install.sh's command ship-skip list disagrees with doctor.sh --install's mirror of it
#   GAP   a tools/commands/templates path referenced in tracked docs/scripts doesn't exist on disk
#   WARN  a tools/*.sh script has no reference anywhere (commands/, tests/, install.sh, docs/, CI)
#   WARN  a tools/*.sh script has no test coverage in tests/
#   WARN  CHANGELOG.md predates the most recent commands/, tools/, or install.sh change
#   WARN  BACKLOG.md: a `### dir #N` heading's own tag is stale (body already records closure)
#
# Orchestrated checks (logic lives in the named file/job; this only runs it and reports):
#   GAP   tests/test_doc_figures.sh fails (docs token figures drifted from reality)
#   GAP   tests/test_core_wrapper_sync.sh fails (CORE.md / templates/CLAUDE.md embed diverged)
#   GAP   shellcheck -x --severity=warning fails on any tracked shell script (mirrors ci.yml)
#
# Explicitly out of scope (not mechanizable — printed as a reminder, not silently dropped):
#   PRINCIPLES.md "does every tension still have a running enforcement" — needs judgment; run the
#   Principles pass in /global-review.
#
# Usage:
#   tools/self/doctor.sh [REPO_DIR] [--quiet]
#   tools/self/doctor.sh -h | --help
set -euo pipefail

QUIET=0
usage() {
  cat <<'EOF'
self/doctor.sh — audit the keel repo's own structural health (a GAP fails, a WARN advises).

Usage:
  tools/self/doctor.sh [REPO_DIR]  full report (default REPO_DIR: this checkout)
  tools/self/doctor.sh --quiet     print only GAP/WARN lines
  tools/self/doctor.sh -h | --help

REPO_DIR exists mainly for the test suite (audit a synthetic sandbox instead of this checkout);
day to day just run it with no arguments.

Not a consumer-project or consumer-install audit — see tools/doctor.sh / tools/doctor.sh --install.
EOF
}
REPO_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "self/doctor.sh: unknown flag '$1' (try --help)" >&2; exit 2 ;;
    *) REPO_ARG="$1" ;;
  esac
  shift
done

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "$REPO_ARG" ]; then
  [ -d "$REPO_ARG" ] || { echo "self/doctor.sh: not a directory: $REPO_ARG" >&2; exit 2; }
  repo_root="$(cd "$REPO_ARG" && pwd)"
else
  repo_root="$(cd "$self_dir/../.." && pwd)"
fi

exit_code=0
say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

say "● keel self-check ($repo_root)"

# --- 1. install.sh <-> doctor.sh --install ship-skip list sync ---------------------------------
# Both files hand-maintain a "<name>.md) continue" exclusion (currently just polish.md) and each
# carries a comment promising to keep the other in sync. Verify the promise instead of trusting it.
# The first stage requires the WHOLE case-arm pattern (everything before ") continue") to itself be
# a list of .md names — not just "any line containing ') continue' that also happens to have a .md
# substring somewhere" — both files have OTHER, unrelated ") continue" arms (e.g. a markdown-table
# row parser, a worktree-list parser) that a looser match would also scan and could misfire on if
# either ever grows a case arm that coincidentally names a .md file. The second stage then pulls
# every name out of that arm, so a multi-name arm (polish.md|draft.md) continue) is captured in
# full, not truncated to its last name. `|| true`: grep exits 1 on zero matches (a file with NO
# ship-skip line at all is valid — an empty list), and under `set -o pipefail` that would otherwise
# kill this script outright with no diagnostic.
skip_arm_re='(^|[^A-Za-z0-9._-])([A-Za-z0-9._-]+\.md)(\|[A-Za-z0-9._-]+\.md)*\) continue'
install_skips="$(grep -ohE "$skip_arm_re" "$repo_root/install.sh" 2>/dev/null \
  | grep -ohE '[A-Za-z0-9._-]+\.md' | sort -u || true)"
doctor_skips="$(grep -ohE "$skip_arm_re" "$repo_root/tools/doctor.sh" 2>/dev/null \
  | grep -ohE '[A-Za-z0-9._-]+\.md' | sort -u || true)"
if [ "$install_skips" != "$doctor_skips" ]; then
  gap "install.sh ship-skip list ({$install_skips}) != doctor.sh --install's mirror ({$doctor_skips}) — keep them in sync"
else
  say "  OK   install.sh / doctor.sh --install ship-skip lists agree (${install_skips:-none})"
fi

# --- 1b. the core-@import definition, hand-copied into three standalone scripts -------------------
# install.sh (has_core_import), uninstall.sh (core_import_re) and tools/doctor.sh --install each
# carry the same boundary-anchored pattern, and each promises in a comment to keep the others in
# sync. Same shape as check 1, and the same answer: verify the promise. The anchoring is
# load-bearing — the bare-substring version uninstall.sh used to carry deleted a user's own prose
# line that merely mentioned the path (dir #108) — so a silent widening in any one copy re-opens a
# data-loss bug, not a cosmetic drift. These three scripts source no shared lib on purpose (each
# must run standalone: bootstrap installs from a tarball, install-secret-guard vendors copies into
# foreign repos), so a mechanized check is the alternative to extraction, not a step toward it.
# Absence is graded the same way check 1 grades an empty ship-skip list: a repo where NONE of the
# three carry the pattern simply doesn't have this rule (valid — that's the state before dir #108),
# but a repo where SOME do and some don't has lost a copy, which is the drift itself.
import_re_files=(install.sh uninstall.sh tools/doctor.sh)
import_re_found=""
import_re_missing=""
for f in "${import_re_files[@]}"; do
  # The pattern as it appears in source, from the opening (^| up to the closing quote.
  hit="$(grep -ohE "\(\^\|\[\[:space:\]\]\)@\[\^\[:space:\]\]\*keel/CORE[^']*" "$repo_root/$f" 2>/dev/null | sort -u || true)"
  if [ -z "$hit" ]; then
    import_re_missing="$import_re_missing${import_re_missing:+, }$f"
  else
    import_re_found="$import_re_found$hit"$'\n'
  fi
done
n_unique="$(printf '%s' "$import_re_found" | sort -u | grep -c . || true)"
if [ -z "$import_re_found" ]; then
  :   # none of the three define it — no rule to keep in sync here
elif [ -n "$import_re_missing" ]; then
  gap "the core-@import pattern is defined in some of install.sh / uninstall.sh / tools/doctor.sh but missing from: $import_re_missing"
elif [ "$n_unique" != 1 ]; then
  gap "the core-@import pattern differs across install.sh / uninstall.sh / tools/doctor.sh ($n_unique variants) — keep them byte-identical"
else
  say "  OK   core-@import pattern identical in install.sh / uninstall.sh / doctor.sh"
fi

# --- 1c. advised commands must be able to reach the home they are about --------------------------
# dir #98's defect class: a tool prints "run install.sh" / "keel uninstall" / "doctor.sh --install"
# while talking about a home that is NOT where a bare re-run lands, so following the advice cannot fix
# what the message just described. Seven sites shipped it, each found only after the previous was
# fixed. Each tool now derives its own suffix once (install.sh: $home_flag / $mode_flag /
# $advise_install / $advise_uninstall / $doctor_arg; doctor.sh: $ihome_flag), so the rule this check
# enforces is simply: any user-facing line naming one of those commands must carry one of those
# markers, or an explicit --home.
#
# Checked at the SOURCE, not by running the tools: most of doctor's advice lives in findings that only
# fire on a broken install, so an output sweep cannot reach them (an earlier output-based version of
# this check was vacuous for doctor entirely, and its phrase list pinned today's wording rather than
# the class — found by this ticket's own review).
#
# Scope: an actual output CALL (echo/say/warn/gap/hint) or a summary bullet ("  - "). Structural, not
# a phrase list, so usage/help text, prose and variable assignments stay out — for assignments the
# marker is legitimately added at the print site instead.
#
# `[^a-z]install\.sh` so `uninstall.sh` doesn't match as a substring and get reported as advice about
# the wrong command — note the character before `install.sh` inside `uninstall.sh` is `n`, so an
# earlier `[^u]` spelling of this excluded nothing at all. Three things this deliberately does NOT
# cover, named rather than silently missed:
#   - the --no-git breadcrumb generated into the core (a constant string on purpose, so doctor's
#     staleness comparison stays stable);
#   - CONTINUATION lines inside the summary heredocs — a bullet that wraps puts its command on an
#     unindented-by-"- " line. Widening the scope to all indented text was tried and swallowed the
#     usage blocks and prose wholesale, so the choice is a narrow check plus this note over a broad
#     one plus a growing allowlist. The wrapped sites that exist today were routed through the
#     variables by hand, and the end-to-end test in tests/test_install_pre_pr_gate.sh covers them;
#   - any tool not in the list below.
advice_re='(^|[^a-z])install\.sh|keel uninstall|doctor\.sh --install'
marker_re='home_flag|ihome_flag|doctor_arg|advise_install|advise_uninstall|--home'
advice_bad=""
for f in install.sh uninstall.sh keel tools/doctor.sh tools/install-pre-pr-gate.sh; do
  [ -f "$repo_root/$f" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    advice_bad="$advice_bad
    $f:$hit"
  done < <(grep -nE '^ *(echo|say|warn|gap|hint) |^ *- ' "$repo_root/$f" 2>/dev/null \
             | grep -E "$advice_re" \
             | grep -vE "$marker_re" || true)
done
if [ -n "$advice_bad" ]; then
  gap "advised command(s) cannot reach a retargeted home — add the tool's own home marker (dir #98):$advice_bad"
else
  say "  OK   advised commands all carry the home they are about"
fi

# --- 2. dead internal references ----------------------------------------------------------------
# Every tools/<x>.sh, commands/<x>.md, templates/<x> mentioned in CURRENT-state docs/scripts must
# resolve on disk. CHANGELOG.md is deliberately excluded — it documents history, and a renamed or
# removed file is expected to still be named there.
say ""
say "● dead internal references"
dead=0
scan_files=()
while IFS= read -r f; do scan_files+=("$f"); done < <(
  git -C "$repo_root" ls-files -- \
    'README.md' 'ADAPTING.md' 'FRAMEWORK.md' 'PRINCIPLES.md' 'SECURITY.md' \
    'docs/*.md' 'commands/*.md' 'tests/*.sh' 'install.sh' 'tools/*.sh' 'tools/self/*.sh' \
    'bootstrap.sh'
)
# "${arr[@]}" on a zero-element array is an unbound-variable error under `set -u` on bash < 4.4
# (macOS ships bash 3.2 by default) — guard the length before expanding, every time, everywhere
# this pattern appears below.
if [ "${#scan_files[@]}" -gt 0 ]; then
  for f in "${scan_files[@]}"; do
    # An optional literal '/' right before the keyword decides nested-vs-bare PER OCCURRENCE, not
    # per unique ref per file — a file that mentions the same path both nested (e.g. a test's
    # sandbox install target "$HOME/.claude/commands/keel-go.md") and bare (a genuine dead top-level
    # reference) must still catch the bare one instead of one occurrence vouching for the other. When
    # '/?' matches a '/', that slash is the whole capture — no boundary char to strip off elsewhere.
    while IFS= read -r hit; do
      case "$hit" in
        /*) continue ;;    # a '/' was captured — nested, not repo-root-relative
        *)  ref="$hit" ;;  # no '/' captured — already exactly the candidate reference
      esac
      [ -e "$repo_root/$ref" ] || { gap "dead reference '$ref' in $f"; dead=$((dead + 1)); }
    done < <(grep -ohE '/?(tools|commands|templates)/[A-Za-z0-9._/-]+\.(sh|md)' "$repo_root/$f" 2>/dev/null | sort -u)
  done
fi
[ "$dead" -eq 0 ] && say "  OK   no dead tools/commands/templates references"

# --- 3. tool wiring: referenced anywhere, and covered by a test ---------------------------------
# git ls-files, not a bash glob: a plain `tools/*.sh` glob does not cross '/', so a tool in a
# subdirectory (e.g. the real, tracked tools/secret-guard/secret-scan.sh) would silently never be
# iterated at all — invisible to this check regardless of its actual wiring. git's pathspec glob
# does cross '/', matching what the dead-reference scan above already (correctly) relies on.
say ""
say "● tool wiring (reference + test coverage)"
tool_files=()
while IFS= read -r f; do tool_files+=("$f"); done < <(
  git -C "$repo_root" ls-files -- 'tools/*.sh' 'tools/self/*.sh'
)
ref_files=()
while IFS= read -r f; do ref_files+=("$f"); done < <(
  git -C "$repo_root" ls-files -- \
    'commands/*.md' 'tests/*.sh' 'install.sh' 'docs/*.md' 'README.md' 'ADAPTING.md' \
    '.github/workflows/*.yml'
)
# Read each reference file's content once (parallel to ref_files, same order) so the per-tool loop
# below does zero subprocess spawns / disk re-reads — O(files) I/O total, not O(tools × files) grep
# calls (that used to be the shape even after ref_files itself was hoisted out of the loop).
ref_contents=()
if [ "${#ref_files[@]}" -gt 0 ]; then
  for f in "${ref_files[@]}"; do
    ref_contents+=("$(cat "$repo_root/$f" 2>/dev/null)")
  done
fi
if [ "${#tool_files[@]}" -gt 0 ]; then
  for rel in "${tool_files[@]}"; do
    # the relative path, not the bare basename: tools/doctor.sh and tools/self/doctor.sh share a
    # basename by design (the "doctor / self-doctor" pairing) — matching on basename alone would let
    # either one's references silently vouch for the other, exactly the blind spot this check exists
    # to catch.
    ref_hit=0; test_hit=0
    if [ "${#ref_files[@]}" -gt 0 ]; then
      i=0
      for f in "${ref_files[@]}"; do
        case "${ref_contents[$i]}" in
          *"$rel"*)
            ref_hit=1
            case "$f" in tests/*) test_hit=1 ;; esac
            ;;
        esac
        i=$((i + 1))
      done
    fi
    if [ "$ref_hit" -eq 1 ] && [ "$test_hit" -eq 1 ]; then
      say "  OK   $rel — referenced and test-covered"
    else
      [ "$ref_hit" -eq 1 ] || warn "orphan tool: no reference to $rel in commands/, tests/, install.sh, docs/, or CI"
      [ "$test_hit" -eq 1 ] || warn "no test coverage: $rel isn't mentioned in any tests/*.sh"
    fi
  done
fi

# --- 4. CHANGELOG staleness ----------------------------------------------------------------------
say ""
changelog_ts="$(git -C "$repo_root" log -1 --format=%ct -- CHANGELOG.md 2>/dev/null || echo 0)"
product_ts="$(git -C "$repo_root" log -1 --format=%ct -- commands tools install.sh 2>/dev/null || echo 0)"
# `git log -1` exits 0 with EMPTY stdout (not an error) when no commit ever touched the pathspec —
# the `|| echo 0` above only catches a nonzero exit, so an untouched path needs this fallback too.
if [ "${product_ts:-0}" -gt "${changelog_ts:-0}" ]; then
  warn "CHANGELOG.md predates the most recent commands/, tools/, or install.sh change — verify [Unreleased] covers it"
else
  say "  OK   CHANGELOG.md is at least as recent as the last commands/, tools/, or install.sh change"
fi

# --- 5. BACKLOG.md heading/status drift -----------------------------------------------------------
# `### dir #N` tickets carry their own status tag on the heading line itself (✅ DONE/CLOSED,
# ⏳ IN FLIGHT, or RETRACTED). Three real hits (dirs #81, #75, #74 — see dir #87) left that tag
# behind after the ticket's own body already recorded closure, caught only by a LATER session's
# wrap. BACKLOG.md is gitignored/personal (not every checkout — worktree or consumer — carries one),
# so a missing file is not itself a finding.
say ""
say "● BACKLOG.md heading/status drift"
backlog_file="$repo_root/BACKLOG.md"
# `-r`, not just `-f`: an unreadable file (e.g. a stray chmod) would otherwise fail the awk pass
# below and, under `set -euo pipefail`, abort the ENTIRE doctor.sh run rather than just this check.
if [ -f "$backlog_file" ] && [ -r "$backlog_file" ]; then
  stale=0
  # `|| [ -n "$ln" ]` on every loop below: plain `while read` silently drops a final line that has
  # no trailing newline — BACKLOG.md is a large, frequently hand/tool-edited file, so a future edit
  # landing without one is realistic, not contrived. Without the guard, a heading on that dropped
  # last line would either desync `stripped_lines` from `heading_lines` (an out-of-range array
  # index — an unbound-variable abort under `set -u` on bash 3.2) or, more generally, just vanish
  # from the content this check reads — a silent false negative on real staleness.
  # Blank fenced code blocks ONCE, before anything else scans the file — not just before the
  # backtick-strip below. A `##`/`###`-prefixed line living inside a fenced example (a bash
  # comment, a markdown snippet) would otherwise still read as a real heading/section boundary to
  # a scan over the RAW file, corrupting body-span detection for whatever real heading follows it.
  # Blanked, not deleted, so line numbers stay aligned with the original file throughout. Fence
  # marker regex matches the existing `^[[:space:]]*(```|~~~)` pattern tools/doctor.sh already uses
  # 3x (indented AND tilde-style fences, not just column-0 backticks) — that pattern only needs to
  # DROP fenced lines for its own callers, this one BLANKS them instead to keep line numbers intact.
  # Accepted limitation, matching tools/doctor.sh's own identical toggle: an ODD number of fence
  # markers (a forgotten closing fence — plausible in a large, hand-edited file) leaves the toggle
  # stuck "in fence" for the rest of the file, blanking everything after it and missing whatever
  # real staleness follows. Not fixed here — a WARN-only heuristic already trades recall for
  # simplicity, and a malformed fence is a self-evident authoring mistake, unlike the silent drift
  # this check exists to catch.
  fence_blanked="$(awk '/^[[:space:]]*(```|~~~)/ { infence = !infence; print ""; next } infence { print ""; next } { print }' "$backlog_file")"
  heading_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do heading_lines+=("$ln"); done \
    < <(grep -nE '^### dir #[0-9]+ ' <<< "$fence_blanked" | cut -d: -f1)
  # Every ## or ### line, dir-heading or not — used to find where THIS heading's body ends (the
  # next section boundary of either level), so a body span never bleeds past a `## ` section
  # break (e.g. into the unrelated `## Recently closed` buffer that follows some dir tickets).
  boundary_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do boundary_lines+=("$ln"); done \
    < <(grep -nE '^#{2,3} ' <<< "$fence_blanked" | cut -d: -f1)
  # Strip single-backtick inline-code spans ONCE for the whole file, not per heading (a
  # several-thousand-line BACKLOG.md with dozens of headings would otherwise re-scan the file's
  # tail from every heading's own sed call, O(headings x file length) instead of O(file length)).
  # The stripped copy is what both the heading-tag check and the body-content check read below —
  # the ticket that documents this very pattern (dir #87) quotes `✅ CLOSED (PR #…)`, ``
  # `CLOSED`/`DONE`/`RETRACTED` ``, and a fenced example of the whole convention as prose, not a
  # real status, so without stripping BOTH forms the check would flag its own ticket.
  stripped_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do stripped_lines+=("$ln"); done \
    < <(sed -E 's/`[^`]*`//g' <<< "$fence_blanked")
  # Derived from the same array the check actually reads, not `wc -l` (which undercounts a file
  # with no trailing newline the same way an unguarded `while read` would).
  total_lines="${#stripped_lines[@]}"
  # A single cursor into boundary_lines, advanced forward only, never reset — both heading_lines
  # and boundary_lines are sorted ascending (heading_lines is a strict subset of boundary_lines),
  # so re-scanning boundary_lines from the start for every heading is pure re-work: O(headings x
  # boundaries) instead of O(headings + boundaries). Measured at realistic accumulated scale
  # (a few thousand tickets — this project's own numbering already runs past #90): the O(n^2) form
  # goes from sub-second to tens of seconds, inside a check that runs on every /polish invocation.
  bidx=0
  nb="${#boundary_lines[@]}"
  if [ "${#heading_lines[@]}" -gt 0 ]; then
    for start in "${heading_lines[@]}"; do
      while [ "$bidx" -lt "$nb" ] && [ "${boundary_lines[$bidx]}" -le "$start" ]; do
        bidx=$((bidx + 1))
      done
      end="$total_lines"
      [ "$bidx" -lt "$nb" ] && end=$(( boundary_lines[bidx] - 1 ))
      heading_line="${stripped_lines[$((start - 1))]}"
      # Scope, per the ticket this implements (dir #87): a MISSING tag (no ✅/⏳/RETRACTED at all)
      # vs. a body that already records closure — not a WRONG tag (e.g. heading stuck on
      # ⏳ IN FLIGHT while the body says ✅ CLOSED). Any existing tag short-circuits below,
      # deliberately: telling "still legitimately in flight" apart from "actually closed, tag just
      # never got updated" needs comparing tag semantics, not just presence — a materially harder
      # problem than the stale-heading-tag pattern this check exists to catch.
      # already carries its own status marker -> nothing to cross-check. Every marker (✅, ⏳,
      # RETRACTED) only counts as a TAG when it follows the "— " separator every real tag does
      # (`— ✅ CLOSED`, `— ⏳ IN FLIGHT`, `— RETRACTED (date, reason)`) — a bare match on any of
      # them would also fire on the glyph/word showing up as plain prose inside a heading's own
      # title (a ticket titled "...whether the RETRACTED ticket process needs revisiting..." or
      # "decide on ✅ emoji conventions"), wrongly treating it as already-tagged. Verified against
      # the real BACKLOG.md: no genuine tag there lacks the "— " prefix.
      if printf '%s' "$heading_line" | grep -qE '— (✅|⏳|RETRACTED\b)'; then
        continue
      fi
      body_start=$((start + 1))
      [ "$body_start" -gt "$end" ] && continue
      body="$(printf '%s\n' "${stripped_lines[@]:$((body_start - 1)):$((end - body_start + 1))}")"
      # Accepted gap, tried and reverted once already: a body line that cross-references a
      # DIFFERENT ticket's status ("blocked by dir #62 (✅ CLOSED)") can false-positive here, same
      # as bare prose discussing retraction with no ticket reference at all ("we discussed whether
      # this should be RETRACTED"). A same-line filter on "dir #N" was tried to catch the first
      # case, but real closure notes routinely co-reference a sibling ticket they also closed
      # ("✅ CLOSED ... also closes dir #79" — a genuine, already-used convention), so the filter
      # dropped exactly the closure lines this check exists to find — and under `set -euo
      # pipefail`, a body with EVERY line filtered out made `grep -v`'s exit 1 abort the entire
      # doctor.sh run. Both are worse than the false positive it was meant to fix. Same accepted
      # class: a negated status word ("NOT DONE yet", "explicitly NOT RETRACTED") still matches —
      # this is a cheap heuristic on free-form prose, not a parser, and the check is a WARN, not a
      # GAP.
      if printf '%s' "$body" | grep -qE '✅.*\b(CLOSED|DONE)\b|\bRETRACTED\b'; then
        # heading_line already matched '^### dir #[0-9]+ ' — pull the id back out of it directly
        # instead of a fresh grep subprocess. Regex kept in a variable, not inline, so the `#`
        # can't be misread as a comment start by anything re-parsing this word.
        id_re='dir #[0-9]+'
        id="dir #?"
        [[ "$heading_line" =~ $id_re ]] && id="${BASH_REMATCH[0]}"
        # WARN, not GAP: the ticket this implements (dir #87) explicitly calls this bug class
        # "Low-severity (cosmetic ... nobody re-opened stale work)" — a hard exit-1 would fail
        # test_self_doctor.sh's real-checkout smoke test (and block /polish step 7) the moment
        # ANY dir-ticket heading anywhere goes stale, for reasons unrelated to whatever diff is
        # actually being polished.
        warn "BACKLOG.md:$start: $id's heading tag looks stale — body already records CLOSED/DONE/RETRACTED but the heading isn't ✅/⏳/RETRACTED-tagged"
        stale=$((stale + 1))
      fi
    done
  fi
  [ "$stale" -eq 0 ] && say "  OK   no stale dir # heading tags in BACKLOG.md"
else
  say "  OK   no readable BACKLOG.md at $repo_root — skipping heading/status check"
fi

# --- orchestrated checks: run existing tests/CI jobs, fold their result in, never re-implement ---
run_check() {
  local label="$1"; shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    say "  OK   $label"
  else
    gap "$label — run: $*"
    [ "$QUIET" = 1 ] || printf '%s\n' "$out" | tail -8 | sed 's/^/       /'
  fi
}

say ""
say "● orchestrated checks (logic lives in these files; not duplicated here)"
run_check "docs token figures accurate (tests/test_doc_figures.sh)" bash "$repo_root/tests/test_doc_figures.sh"
run_check "CORE.md / wrapper embed in sync (tests/test_core_wrapper_sync.sh)" bash "$repo_root/tests/test_core_wrapper_sync.sh"

if command -v shellcheck >/dev/null 2>&1; then
  sc_files=()
  # This checkout's own copy, not $repo_root's — $repo_root is the AUDITED target (a sandbox in
  # tests, or possibly a different checkout entirely) and may not ship the selector script at all.
  while IFS= read -r f; do sc_files+=("$repo_root/$f"); done \
    < <(bash "$self_dir/shellcheck-targets.sh" "$repo_root")
  if [ "${#sc_files[@]}" -gt 0 ]; then
    run_check "shellcheck clean (${#sc_files[@]} tracked scripts, mirrors ci.yml)" \
      shellcheck -x --severity=warning "${sc_files[@]}"
  else
    say "  OK   shellcheck: no tracked shell scripts to check"
  fi
else
  warn "shellcheck not installed locally — skipped here (CI still enforces it)"
fi

say ""
say "  MANUAL  PRINCIPLES.md tension-enforcement isn't mechanizable (needs judgment) — run the Principles pass in /global-review"

say ""
[ "$exit_code" = 0 ] && say "self/doctor: keel repo structural self-check OK"
exit "$exit_code"
