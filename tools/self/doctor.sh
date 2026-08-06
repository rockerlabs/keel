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
#   GAP   BACKLOG.md: a `### dir #N` heading's own tag is stale (body already records closure)
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
if [ "$product_ts" -gt "$changelog_ts" ]; then
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
if [ -f "$backlog_file" ]; then
  stale=0
  # `|| [ -n "$ln" ]` on every loop below: plain `while read` silently drops a final line that has
  # no trailing newline — BACKLOG.md is a large, frequently hand/tool-edited file, so a future edit
  # landing without one is realistic, not contrived. Without the guard, a heading on that dropped
  # last line would either desync `stripped_lines` from `heading_lines` (an out-of-range array
  # index — an unbound-variable abort under `set -u` on bash 3.2) or, more generally, just vanish
  # from the content this check reads — a silent false negative on real staleness.
  heading_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do heading_lines+=("$ln"); done \
    < <(grep -nE '^### dir #[0-9]+ ' "$backlog_file" | cut -d: -f1)
  # Every ## or ### line, dir-heading or not — used to find where THIS heading's body ends (the
  # next section boundary of either level), so a body span never bleeds past a `## ` section
  # break (e.g. into the unrelated `## Recently closed` buffer that follows some dir tickets).
  boundary_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do boundary_lines+=("$ln"); done \
    < <(grep -nE '^#{2,3} ' "$backlog_file" | cut -d: -f1)
  # Strip inline-code spans ONCE for the whole file, not per heading (a several-thousand-line
  # BACKLOG.md with dozens of headings would otherwise re-scan the file's tail from every heading's
  # own sed call, O(headings x file length) instead of O(file length)). The stripped copy is what
  # both the heading-tag check and the body-content check read below — the ticket that documents
  # this very pattern (dir #87) quotes `✅ CLOSED (PR #…)` and `` `CLOSED`/`DONE`/`RETRACTED` `` as
  # prose examples, not a real status, so without stripping the check would flag its own ticket.
  stripped_lines=()
  while IFS= read -r ln || [ -n "$ln" ]; do stripped_lines+=("$ln"); done \
    < <(sed -E 's/`[^`]*`//g' "$backlog_file")
  # Derived from the same array the check actually reads, not `wc -l` (which undercounts a file
  # with no trailing newline the same way an unguarded `while read` would).
  total_lines="${#stripped_lines[@]}"
  if [ "${#heading_lines[@]}" -gt 0 ]; then
    for start in "${heading_lines[@]}"; do
      heading_line="${stripped_lines[$((start - 1))]}"
      # already carries its own status marker -> nothing to cross-check
      case "$heading_line" in
        *"✅"*|*"⏳"*|*RETRACTED*) continue ;;
      esac
      end="$total_lines"
      if [ "${#boundary_lines[@]}" -gt 0 ]; then
        for bl in "${boundary_lines[@]}"; do
          if [ "$bl" -gt "$start" ]; then
            end=$((bl - 1))
            break
          fi
        done
      fi
      body_start=$((start + 1))
      [ "$body_start" -gt "$end" ] && continue
      body=""
      for ((k = body_start; k <= end; k++)); do body+="${stripped_lines[$((k - 1))]}"$'\n'; done
      if printf '%s' "$body" | grep -qE '✅.*\b(CLOSED|DONE)\b|\bRETRACTED\b'; then
        # heading_line already matched '^### dir #[0-9]+ ' — pull the id back out of it directly
        # instead of a fresh grep subprocess. Regex kept in a variable, not inline, so the `#`
        # can't be misread as a comment start by anything re-parsing this word.
        id_re='dir #[0-9]+'
        id="dir #?"
        [[ "$heading_line" =~ $id_re ]] && id="${BASH_REMATCH[0]}"
        gap "BACKLOG.md:$start: $id's heading tag looks stale — body already records CLOSED/DONE/RETRACTED but the heading isn't ✅/⏳/RETRACTED-tagged"
        stale=$((stale + 1))
      fi
    done
  fi
  [ "$stale" -eq 0 ] && say "  OK   no stale dir # heading tags in BACKLOG.md"
else
  say "  OK   no BACKLOG.md at $repo_root — skipping heading/status check"
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
