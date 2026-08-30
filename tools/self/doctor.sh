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
#   GAP   the core `@import` pattern hand-copied into install.sh/uninstall.sh/tools/doctor.sh has
#         drifted between them (present in some but not all, or byte-different where present)
#   GAP   an advised install/uninstall command in install.sh/uninstall.sh/keel/tools/doctor.sh/
#         tools/install-pre-pr-gate.sh can't reach the home it names (dir #98)
#   GAP   FRAMEWORK.md / PRINCIPLES.md contain a leaked host path or non-safe email (dir #114)
#   GAP   a tools/commands/templates path referenced in tracked docs/scripts doesn't exist on disk
#   GAP   a backticked `/name` slash-command reference in adopter-facing docs has no commands/<name>.md
#         (dir #129 — moved from tests/test_rails_honesty.sh so an adopter's own doctor.sh run is
#         covered too, not just Keel's own suite)
#   WARN  a tools/*.sh script (or the installed `keel` CLI) has no reference anywhere (commands/,
#         tests/, install.sh, docs/, CI)
#   GAP   a NEW tools/*.sh script (or the installed `keel` CLI) has zero test coverage in tests/ —
#         the coverage ratchet (dir #142)
#   WARN  a PRE-EXISTING such script listed in tools/self/legacy-untested.txt has zero test coverage
#         (soft debt, dir #142 — burned down deliberately, never a retroactive block)
#   WARN  CHANGELOG.md predates the most recent commands/, tools/, or install.sh change
#   WARN  BACKLOG.md: a `### dir #N` heading's own tag is stale (body already records closure)
#   WARN  BACKLOG.md: a `⏳`/`IN REVIEW` heading cites a PR that `gh` reports MERGED (dir #135)
#   GAP   CHANGELOG.md release sections and git release tags disagree (dir #139)
#   GAP   a release-in-preparation section was cut more than KEEL_PENDING_RELEASE_MAX_COMMITS commits
#         ago and is still untagged — the tag was forgotten, not merely pending (dir #156)
#   WARN  a `dir #N` referenced in a commit message since the previous release tag is absent from
#         CHANGELOG.md's own `[Unreleased]` section — per-TICKET, not per-file, so a PR that DOES
#         touch CHANGELOG.md (for a different ticket) still trips it (dir #237)
#
# Orchestrated checks (logic lives in the named file/job; this only runs it and reports):
#   GAP   tests/test_doc_figures.sh fails (docs token figures drifted from reality)
#   GAP   tests/test_core_wrapper_sync.sh fails (CORE.md / templates/CLAUDE.md embed diverged)
#   GAP   shellcheck -x --severity=warning fails on any tracked shell script (mirrors ci.yml)
#   GAP   tools/self/prose-drift.sh finds a dead relative markdown link
#   WARN  tools/self/prose-drift.sh finds a line running well past its own wrapped block's
#         neighbors (advisory lead, dir #169 — never fails this script on its own)
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

# --- 1d. FRAMEWORK.md / PRINCIPLES.md must not carry a leaked host/user identifier ---------------
# dir #114 (M4-1): FRAMEWORK.md's own reusability-boundary rule says these two files must never
# contain an absolute host path, a username, hardware, a model provider, or a project name — those
# belong in INSTANCE.md. Only two of those are pattern-detectable at all (the rest need a declared
# token, which is what public-audit.sh's --token/.public-audit path is for), so this check covers
# exactly that pair: the same HOME_RE/EMAIL_RE public-audit.sh uses for its own tree scan, run here
# too so the rule is enforced somewhere that's actually a CI gate (public-audit.sh is a tool you
# remember to run; this file already runs in ci.yml). Same safe-email allowlist as doctor.sh's
# advisory nudge, so a legitimate `noreply@…` co-author line doesn't false-GAP.
say ""
say "● FRAMEWORK.md / PRINCIPLES.md identifier leak"
# This checkout's OWN copies of these libs, not $repo_root's (the audited target — a synthetic
# sandbox in tests, which need not carry tools/lib/ at all) — same convention tools/doctor.sh uses
# for the same libs a few lines up (see its $tools_dir comment).
# shellcheck source=tools/lib/safe-emails.sh
. "$self_dir/../lib/safe-emails.sh"
# HOME_RE / EMAIL_RE: shared with public-audit.sh's own tree scan (tools/lib/leak-patterns.sh)
# shellcheck source=tools/lib/leak-patterns.sh
. "$self_dir/../lib/leak-patterns.sh"
id_leak=0
for f in FRAMEWORK.md PRINCIPLES.md; do
  [ -f "$repo_root/$f" ] || continue
  hit="$(grep -noE "$HOME_RE" "$repo_root/$f" 2>/dev/null | head -1 || true)"
  if [ -n "$hit" ]; then
    gap "$f:$hit — looks like a leaked host path (dir #114)"
    id_leak=$((id_leak + 1))
  fi
  hit="$(grep -noE "$EMAIL_RE" "$repo_root/$f" 2>/dev/null | grep -vE "$safe_email_re" | head -1 || true)"
  if [ -n "$hit" ]; then
    gap "$f:$hit — looks like a leaked personal/corporate email (dir #114)"
    id_leak=$((id_leak + 1))
  fi
done
[ "$id_leak" -eq 0 ] && say "  OK   no leaked host path or non-safe email in FRAMEWORK.md / PRINCIPLES.md"

# --- 2. dead internal references ----------------------------------------------------------------
# Every tools/<x>.sh, commands/<x>.md, templates/<x> mentioned in CURRENT-state docs/scripts must
# resolve on disk. CHANGELOG.md is deliberately excluded — it documents history, and a renamed or
# removed file is expected to still be named there.
#
# adopter_docs is the base list check 2b (below) also scans — single-sourced so a new adopter-facing
# doc location (CORE.md/IDEAS.md joined it late, dir #129) only needs adding here once. Check 2 adds
# the implementation shell files on top (tests/*.sh, install.sh, tools/*.sh, tools/self/*.sh,
# bootstrap.sh) — check 2b deliberately does NOT scan those (see its own comment for why).
adopter_docs=(
  'README.md' 'ADAPTING.md' 'FRAMEWORK.md' 'PRINCIPLES.md' 'SECURITY.md' 'CORE.md' 'IDEAS.md'
  'docs/*.md' 'commands/*.md' 'templates/*.md'
)
say ""
say "● dead internal references"
dead=0
scan_files=()
while IFS= read -r f; do scan_files+=("$f"); done < <(
  git -C "$repo_root" ls-files -- \
    "${adopter_docs[@]}" 'tests/*.sh' 'install.sh' 'tools/*.sh' 'tools/self/*.sh' 'bootstrap.sh'
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

# --- 2b. slash-command references must resolve to a shipped command ------------------------------
# Same class as check 2 above, different referent (dir #129): every backticked `/name` reference in
# adopter-facing prose must resolve to commands/<name>.md. Moved here from tests/test_rails_honesty.sh
# (dir #110) — that test only ran in Keel's own suite, so an adopter's own CLAUDE.md/rails citing a
# command their install doesn't carry was never caught. Every adopter runs tools/doctor.sh, and this
# script is what it orchestrates (via its own dead-reference-class checks), so the fix belongs here,
# not in a second copy of the logic.
#
# Reuses adopter_docs (check 2, above) — deliberately WITHOUT check 2's extra shell files (tests/*.sh,
# install.sh, tools/*.sh) — those are full of backticked `/word` text that is not a slash-command
# citation at all: `/clear` (a Claude Code builtin, not a keel command), `/pulls` (a GitHub API path
# fragment inside tools/pre-pr-gate.sh), and `/design` inside this file's own prose (a citation-style
# example, not a real reference). Scoping to the adopter-facing docs is what the original test scanned
# and stays false-positive-free on today's tree (verified empirically while sizing dir #129);
# CHANGELOG.md is excluded on purpose, same reason as check 2 — it documents history, including
# wording since corrected.
#
# Two allowlists, deliberately SEPARATE arrays, never collapsed into one (dir #110/dir #129 watch-out):
# harness-provided commands, each of whose call sites already handles its absence explicitly, and
# names that are not commands at all (a filesystem path, or prose about a name an adopter may already
# have). Checked via a here-string into `grep -qxF`, the same exact-line-membership idiom checks 3
# and 6 already use in this file, rather than a hand-rolled space-padded `case` match.
say ""
say "● slash-command references"
dead_cmd=0
scan_files_cmd=()
# Filter to files that actually exist on disk, not just git-tracked (an unstaged deletion of a
# tracked file leaves it in `git ls-files` but absent from the working tree) — the single batched
# `grep -r` below fails its WHOLE run, silently blinding this check across every file it scans, if
# any one path in its file-operand list is unreadable; check 2's own per-file loop above only loses
# that ONE file's coverage on the same failure, since each of its grep calls is scoped to one path.
while IFS= read -r f; do [ -f "$repo_root/$f" ] && scan_files_cmd+=("$f"); done < <(
  git -C "$repo_root" ls-files -- "${adopter_docs[@]}"
)
harness_commands=(code-review simplify review)
not_commands=(tmp setup)
# Joined once into a plain string, then fed to grep via `<<<` (a here-string, not a pipe) — the
# fix shape dir #195 already established just below (see its comment on `cited_in`) and dir #280
# generalizes: a `printf ... | grep -q` pipe has printf as a live writer process that grep's own
# early stdin-close (on match) can SIGPIPE, and under `set -o pipefail` that flips a real match into
# a false "not found". A here-string has bash buffer the content up front, so there's no live writer
# on the other end of grep's stdin for grep to signal.
allow_list="$(printf '%s\n' "${harness_commands[@]}" "${not_commands[@]}")"
if [ "${#scan_files_cmd[@]}" -gt 0 ]; then
  # `|| true`: grep exits 1 on zero matches, which under `set -e` would otherwise abort this whole
  # script at the assignment (unlike the process-substitution loop above, a direct `var=$(cmd)`
  # DOES propagate a failing exit status through errexit).
  raw_hits="$(cd "$repo_root" && grep -rnoE '(^|[[:space:]("*/])`/[a-z][a-z0-9-]+[` ]' "${scan_files_cmd[@]}" 2>/dev/null || true)"
  refs="$(printf '%s\n' "$raw_hits" | cut -d: -f3- | tr -d '`/ ("*' | sort -u)"
  for name in $refs; do
    grep -qxF "$name" <<< "$allow_list" && continue
    if [ ! -f "$repo_root/commands/$name.md" ]; then
      # `grep -m 1`, not `| head -1` (dir #195, the same SIGPIPE-under-pipefail shape dir #156 fixed for
      # `_pending_release_intro_commit`'s `git log -S`, same fix shape too — `-n 1` there, `-m 1` here):
      # if `$raw_hits` grows large enough that grep's matching lines exceed the pipe buffer before
      # `head -1` reads its one line and closes, grep gets SIGPIPE and the whole doctor.sh run aborts
      # under `set -o pipefail`. Asking grep itself to stop after one match (verified present in GNU,
      # BSD/macOS, and busybox grep — this repo's whole CI matrix) has no such downstream pipe to break —
      # but `-m 1` alone just MOVES the same hazard one stage left: a `printf '%s\n' "$raw_hits" | grep`
      # feed still has printf as a live writer process that grep's own early stdin-close can SIGPIPE
      # (reproduced live: swapping the `printf | grep -m 1` form in still crashed this fixture at exit
      # 141). A `<<<` here-string has no such writer — bash buffers it via a temp file up front, so
      # there's no concurrent process on the other end of grep's stdin for grep to signal.
      cited_in="$(grep -m 1 -F "\`/$name" <<< "$raw_hits" | cut -d: -f1)"
      gap "slash-command reference '/$name' in ${cited_in:-an adopter-facing doc} has no commands/$name.md — ship it, word it generically, or allowlist it (dir #129, only if harness-provided AND every call site handles its absence)"
      dead_cmd=$((dead_cmd + 1))
    fi
  done
fi
[ "$dead_cmd" -eq 0 ] && say "  OK   no unshipped slash-command references"

# --- 3. tool wiring: referenced anywhere, and covered by a test ---------------------------------
# git ls-files, not a bash glob: a plain `tools/*.sh` glob does not cross '/', so a tool in a
# subdirectory (e.g. the real, tracked tools/secret-guard/secret-scan.sh) would silently never be
# iterated at all — invisible to this check regardless of its actual wiring. git's pathspec glob
# does cross '/', matching what the dead-reference scan above already (correctly) relies on.
say ""
say "● tool wiring (reference + test coverage)"
# 'keel' is added as one more pathspec below, alongside the tools/*.sh glob: the one executable
# install.sh itself INSTALLS (a symlink, via make_link) rather than a tools/*.sh glob match. dir #142
# defines "shipped executable" as install.sh's own installs plus tools/*.sh, so the ratchet further
# down must see it too. ls-files never lists an untracked file regardless of pathspec, so a REPO_ARG
# sandbox with a stray untracked file of that name is still correctly excluded, with one git
# invocation rather than a second, separate ls-files call.
tool_files=()
while IFS= read -r f; do tool_files+=("$f"); done < <(
  git -C "$repo_root" ls-files -- 'tools/*.sh' 'tools/self/*.sh' 'keel'
)
# tools/self/legacy-untested.txt — dir #142's soft-debt allowlist: shipped scripts with zero test
# coverage BEFORE the ratchet below existed. One relative path per line (matching the `rel` values
# this loop computes, e.g. `tools/branch-cleanup.sh` or `keel`); `#`-comments and blank lines are
# ignored. A script's AGE is not what exempts it — only that it predates this check — so this is a
# named list a human diff can review, never a heuristic (git blame / commit date) that would
# silently grandfather whatever happens to be old. Read from $repo_root (the audited checkout), not
# $self_dir, so a REPO_ARG sandbox in the test suite carries its own independent list.
legacy_file="$repo_root/tools/self/legacy-untested.txt"
legacy_list=()
if [ -f "$legacy_file" ] && [ -r "$legacy_file" ]; then
  while IFS= read -r ln || [ -n "$ln" ]; do
    ln="${ln%%#*}"
    # Parameter-expansion trim, not a printf|sed subshell: this loop already runs on every doctor.sh
    # invocation (CI + every /polish), and a per-line fork pair is wasted work a pure-bash trim skips.
    ln="${ln#"${ln%%[![:space:]]*}"}"
    ln="${ln%"${ln##*[![:space:]]}"}"
    [ -n "$ln" ] && legacy_list+=("$ln")
  done < "$legacy_file"
fi
# Joined once, fed via a here-string below (dir #280) — see allow_list above for why a plain
# `printf ... | grep -q` pipe is unsafe here (a real hit can SIGPIPE-flip into a false miss under
# load). Guarded on non-empty: `"${legacy_list[@]}"` on a 0-element array is an unbound-variable
# crash under this file's `set -u` on bash 3.2 (macOS's shipped bash) — the same reason the original
# call site below gated the expansion on `[ "${#legacy_list[@]}" -gt 0 ]` in the first place.
legacy_joined=""
[ "${#legacy_list[@]}" -gt 0 ] && legacy_joined="$(printf '%s\n' "${legacy_list[@]}")"
ref_files=()
while IFS= read -r f; do ref_files+=("$f"); done < <(
  git -C "$repo_root" ls-files -- \
    'commands/*.md' 'tests/*.sh' 'install.sh' 'docs/*.md' 'README.md' 'ADAPTING.md' \
    '.github/workflows/*.yml'
)
# Read each reference file's content once (parallel to ref_files, same order) so the per-tool loop
# below does zero subprocess spawns / disk re-reads — O(files) I/O total, not O(tools × files) grep
# calls (that used to be the shape even after ref_files itself was hoisted out of the loop). A SECOND,
# comment-stripped copy is precomputed here too, but ONLY for tests/*.sh entries (dir #242) — sparse,
# not a full parallel array, since it's only ever read for that subset: the ratchet's "test-covered"
# verdict must require the tool's path to appear in a tests/*.sh file OUTSIDE a comment (leading OR
# trailing), or a bare mention in an explanatory comment (found live: a comment at
# tests/test_install_pre_pr_gate.sh:309 naming tools/lib/nonneg-int.sh, with no actual test of it
# anywhere, made the ratchet report "referenced and test-covered") satisfies the check with zero real
# coverage. Precomputing it here, once per tests/*.sh file, rather than inside the per-tool loop below,
# matters: an earlier version called `sed` inside that loop, on demand — cheap-looking, but the loop
# is keyed by (tool × ref_file) pairs, so any tests/*.sh file whose content substring-matches MULTIPLE
# tool paths (the common case) got re-stripped by a fresh `sed` subprocess once per matching tool,
# quietly reintroducing the exact O(tools × files) subprocess-spawn shape this comment's first
# sentence claims doesn't happen (found by an operator-run `/code-review medium` pass, confirmed live:
# ~111 extra spawns on this repo's own tree). `ref_hit` (mere "referenced somewhere") keeps using the
# unstripped content — a comment is legitimate evidence of that weaker claim — only `test_hit` is
# tightened.
#
# KNOWN LIMITATION (found by the same `/code-review medium` pass, CONFIRMED mechanism but no live
# instance found in this repo's own tree): the strip is line-based, not shell/quote-aware, so a `#`
# preceded by whitespace INSIDE a quoted string constant (not a real shell comment) still gets
# stripped along with everything after it. A tests/*.sh line whose only mention of a tool's path sits
# after such a `#` (e.g. asserting on an error message that itself contains a literal `# tools/<x>.sh`
# as data) would false-GAP that tool as uncovered — the opposite failure mode from the one this ticket
# closes. A real fix needs shell-aware tokenization, which is disproportionate to a currently-latent
# risk; if a future GAP looks spurious, check here first.
ref_contents=()
ref_contents_stripped=()
if [ "${#ref_files[@]}" -gt 0 ]; then
  for f in "${ref_files[@]}"; do
    content="$(cat "$repo_root/$f" 2>/dev/null)"
    ref_contents+=("$content")
    case "$f" in
      tests/*) ref_contents_stripped+=("$(sed -E 's/(^|[[:space:]])#.*$//' <<< "$content")") ;;
      *) ref_contents_stripped+=("") ;;
    esac
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
            case "$f" in
              tests/*)
                case "${ref_contents_stripped[$i]}" in *"$rel"*) test_hit=1 ;; esac
                ;;
            esac
            ;;
        esac
        i=$((i + 1))
      done
    fi
    if [ "$ref_hit" -eq 1 ] && [ "$test_hit" -eq 1 ]; then
      say "  OK   $rel — referenced and test-covered"
    else
      [ "$ref_hit" -eq 1 ] || warn "orphan tool: no reference to $rel in commands/, tests/, install.sh, docs/, or CI"
      if [ "$test_hit" -eq 0 ]; then
        # The ratchet (dir #142): a script already listed in legacy-untested.txt is known, visible
        # debt — soft, WARN-only, burned down deliberately. Anything NOT on that list is either brand
        # new or slipped past whoever should have listed it — either way, a hard GAP, not a WARN a
        # release can quietly sail past the way dir #100's whole class did.
        # Exact-line membership test, same idiom check 6's tag/section cross-check already uses
        # (a here-string into grep, not a hand-rolled loop — see legacy_joined above for why not a
        # `printf | grep -qxF` pipe).
        legacy_hit=0
        if [ -n "$legacy_joined" ] && grep -qxF "$rel" <<< "$legacy_joined"; then
          legacy_hit=1
        fi
        if [ "$legacy_hit" -eq 1 ]; then
          warn "listed debt (dir #142, tools/self/legacy-untested.txt): $rel has no test coverage"
        else
          gap "ratchet (dir #142): $rel is a NEW shipped script with zero test coverage — add a tests/test_*.sh covering it, or list it in tools/self/legacy-untested.txt if this is pre-existing debt"
        fi
      fi
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

# A heading line already matched '^### dir #[0-9]+ ' — pull the id back out of it directly instead of
# a fresh grep subprocess. Shared by check 5's tag-staleness loop and check 5b's merged-PR loop below
# (both label a warn() with the ticket id). Regex kept in a variable, not inline, so the `#` can't be
# misread as a comment start by anything re-parsing this word.
heading_dir_id() {
  local re='dir #[0-9]+' line="$1"
  [[ "$line" =~ $re ]] && printf '%s' "${BASH_REMATCH[0]}" || printf '%s' "dir #?"
}

# Blank (not delete, so line numbers stay aligned) fenced ```/~~~ code-block regions of a file, so a
# `##`/`###`-shaped line living inside a fenced example must not be misread as a real heading/section.
# Needed by check 5's BACKLOG.md scan and check 6's CHANGELOG.md scan below, and by
# tools/self/prose-drift.sh's own md line-length signal — tools/lib/fence-blank.sh (dir #169) is the
# one shared copy, after this exact toggle was found duplicated verbatim between check 5 and check 6
# themselves by an earlier /code-review medium pass.
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

# --- 5. BACKLOG.md heading/status drift -----------------------------------------------------------
# `### dir #N` tickets carry their own status tag on the heading line itself (✅ DONE/CLOSED,
# ⏳ IN FLIGHT, or RETRACTED). Three real hits (dirs #81, #75, #74 — see dir #87) left that tag
# behind after the ticket's own body already recorded closure, caught only by a LATER session's
# wrap. BACKLOG.md is gitignored/personal (not every checkout — worktree or consumer — carries one),
# so a missing file is not itself a finding.
#
# BACKLOG.md lives ONLY at the MAIN checkout root (this project's own CLAUDE.md convention) — a
# linked worktree never carries its own copy. `repo_root` above is whatever checkout this script was
# INVOKED against, which in a worktree session is the worktree path itself, not the main checkout —
# so before dir #135, this check silently "skipped, no readable BACKLOG.md" in every worktree (i.e.
# where /polish's step-7 self-check actually runs) and stayed dark until someone ran self/doctor.sh
# by hand from the main checkout. Resolve the MAIN checkout the same way tools/doctor.sh's unit_top
# does (PR #176): the first `worktree <path>` line of `git worktree list --porcelain`, unless that
# entry is bare — a plain single-checkout repo's own porcelain output has exactly one such line
# naming itself, so this is a no-op there. This makes self/doctor.sh the 7th tool carrying its own
# copy of this same awk fragment (dir #26 — a tracked, deliberate "capture only, do not pre-build a
# shared lib" decision, since the six prior sites don't all want the same projection); bump that
# ticket's site count rather than extracting one here against its own recorded call. `|| true`: outside
# a repo (or a REPO_ARG sandbox dir the
# test suite points at a non-repo path) git exits non-zero, and pipefail must not abort the whole run
# over a check this file already treats as advisory-optional.
main_top="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
  | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
backlog_root="${main_top:-$repo_root}"
say ""
say "● BACKLOG.md heading/status drift"
backlog_file="$backlog_root/BACKLOG.md"
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
  fence_blanked="$(blank_fenced_blocks "$backlog_file")"
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
      if grep -qE '— (✅|⏳|RETRACTED\b)' <<< "$heading_line"; then
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
      if grep -qE '✅.*\b(CLOSED|DONE)\b|\bRETRACTED\b' <<< "$body"; then
        id="$(heading_dir_id "$heading_line")"
        # WARN, not GAP: the ticket this implements (dir #87) explicitly calls this bug class
        # "Low-severity (cosmetic ... nobody re-opened stale work)" — a hard exit-1 would fail
        # test_self_doctor.sh's real-checkout smoke test (and block /polish step 7) the moment
        # ANY dir-ticket heading anywhere goes stale, for reasons unrelated to whatever diff is
        # actually being polished. This now matters beyond this file too (found by /code-review
        # medium's cross-file pass): since dir #135 made this check resolve BACKLOG.md at the main
        # checkout even from a worktree, that smoke test genuinely reads the live, personal
        # BACKLOG.md now, whose content changes over time — safe today only because this check (and
        # 5b below) stays WARN-only. Promoting either to a hard GAP would make the smoke test flaky
        # against a file outside the test's own control.
        warn "BACKLOG.md:$start: $id's heading tag looks stale — body already records CLOSED/DONE/RETRACTED but the heading isn't ✅/⏳/RETRACTED-tagged"
        stale=$((stale + 1))
      fi
    done
  fi
  [ "$stale" -eq 0 ] && say "  OK   no stale dir # heading tags in BACKLOG.md"

  # --- 5b. a ⏳/IN REVIEW heading citing a MERGED PR is stale (dir #135) ---------------------------
  # The tag-staleness loop above only catches a MISSING tag — it deliberately trusts any EXISTING
  # tag (see its own comment: telling "still legitimately in flight" apart from "actually closed,
  # tag just never updated" needs comparing tag semantics, harder than presence). But a heading can
  # carry a perfectly well-formed tag that is itself now wrong: it names a PR as still under review,
  # and that PR has since merged, with nobody coming back to flip the heading. That's independent of
  # whether the BODY agrees — dir #96 is the live case this reopens: heading and body were stale
  # TOGETHER, so no body-vs-heading comparison could ever have caught it.
  # Same "— " tag-boundary convention as the staleness loop above, and it must be the SAME regex
  # shape, not just the same idea: an earlier draft used `— .*(⏳|IN REVIEW)`, which (unlike the
  # staleness loop's own `— (✅|⏳|RETRACTED\b)`) lets the `.*` bridge an unrelated "— " elsewhere in
  # the title to a ⏳/"IN REVIEW" occurring anywhere later — matching a heading discussing the
  # convention as prose ("### dir #50 — clarify whether ⏳ tickets citing PR #55 should auto-close —
  # R1") as if it carried a real tag. No wildcard, adjacency only, same as the staleness loop.
  # A bare `⏳` alone is NOT enough, unlike the staleness loop's own tag regex: this project's real
  # in-progress tag is `⏳ IN FLIGHT` (the /go claim marker), not "under review" — matching bare ⏳
  # would also fire on an IN FLIGHT heading that happens to mention a merged PR elsewhere in its tail
  # (e.g. "blocked by PR #99"), falsely calling it "⏳/IN REVIEW" (found by an independent reviewer's
  # own pass). Requires the literal word "IN REVIEW", with ⏳ only ever optional decoration on it.
  # Best-effort by design: `gh pr view` needs `gh` on PATH, network, and GitHub auth — any of those
  # being unavailable (no gh installed, offline, rate-limited) fails the command and this simply
  # `continue`s past that heading, no crash, no false WARN. That single `|| continue` is the whole
  # "degrade gracefully offline/no-gh" contract; there is deliberately no separate `command -v gh`
  # gate; `gh` missing hits the exact same fallback a live-but-unreachable `gh` does.
  say ""
  say "● BACKLOG.md ⏳/IN REVIEW heading vs. gh's live PR state"
  pr_stale=0
  if [ "${#heading_lines[@]}" -gt 0 ]; then
    tag_re='— (⏳ )?IN REVIEW'
    pr_re='PR #[0-9]+'
    for start in "${heading_lines[@]}"; do
      heading_line="${stripped_lines[$((start - 1))]}"
      [[ "$heading_line" =~ $tag_re ]] || continue
      # Only the text AFTER the matched tag: the real convention puts the cited PR right after the
      # tag ("— ⏳ IN REVIEW (PR #99)"), but `[[ =~ ]]` on the WHOLE line would instead grab the
      # LEFTMOST "PR #N" anywhere — including an earlier, unrelated PR the ticket's own TITLE
      # references (e.g. "follow-up to PR #12 — R2 — ⏳ IN REVIEW (PR #85)"), silently checking the
      # wrong PR (found by /code-review medium's own line-by-line pass).
      after_tag="${heading_line#*"${BASH_REMATCH[0]}"}"
      [[ "$after_tag" =~ $pr_re ]] || continue
      pr_num="${BASH_REMATCH[0]#PR #}"
      # `-C "$repo_root"`-equivalent for `gh`: unlike every `git` call in this file, `gh` has no `-C`
      # flag — it infers which GitHub repo to query from the process's OWN cwd (or $GH_REPO), not
      # from any path argument. A bare call here would query whatever repo the invoking shell
      # happens to sit in, not the one being audited (a REPO_ARG sandbox, or self/doctor.sh run from
      # elsewhere) — silently wrong or empty, and swallowed by the `|| continue` below with no sign
      # anything was off (found by /code-review medium's own line-by-line pass).
      pr_state="$(cd "$repo_root" && gh pr view "$pr_num" --json state -q .state 2>/dev/null)" || continue
      [ "$pr_state" = "MERGED" ] || continue
      id="$(heading_dir_id "$heading_line")"
      warn "BACKLOG.md:$start: $id's heading cites PR #$pr_num as ⏳/IN REVIEW but gh reports it MERGED — stale regardless of heading-vs-body agreement"
      pr_stale=$((pr_stale + 1))
    done
  fi
  [ "$pr_stale" -eq 0 ] && say "  OK   no BACKLOG.md heading cites a merged PR as still ⏳/IN REVIEW (best effort — needs gh)"
else
  say "  OK   no readable BACKLOG.md at $backlog_root — skipping heading/status check"
fi

# --- 6. CHANGELOG.md <-> git release-tag reconciliation (dir #139) -------------------------------
# v0.5.0's own section WAS cut at release, on time — then the very next commit (PR #118) accidentally
# clobbered the heading line, and that stayed invisible for THREE WEEKS until an unrelated audit
# tripped over it (dir #115). Discipline can't catch "the release commit was right and the next one
# broke it"; only a standing check that re-derives the fact from git's own tags — not from CHANGELOG.md
# agreeing with itself — can. Three invariants, all cheap: every release tag has its own
# `## [x.y.z]` section, every versioned section has its tag, and the section COUNT equals tag count +
# 1 (`[Unreleased]`) — the last one is what would have caught PR #118 directly (a section vanishing
# without its tag going anywhere leaves the count short by exactly one).
# _semver_gt A B — true iff semver A is strictly greater than semver B. Both are bare `x.y.z` strings
# (the anchored ERE below is what guarantees that shape for tags; CHANGELOG sections are matched by
# the same three-number pattern). Components compared as INTEGERS in pure bash — a string compare
# would rank 1.10.0 below 1.9.0, and `sort -V` isn't dependable on the alpine-busybox CI leg. Single
# consumer WITHIN THIS FILE (the pending-release allowance below), so it lives here rather than with
# the file's general helpers — but not this codebase's only copy: `tests/test_release_history.sh`
# mirrors it, v-prefix-stripping variant, for docs/release-history.md's own pending-release allowance
# (dir #299). Not shared (this file is documented elsewhere as non-sourceable, and that test file
# already sources tests/lib.sh instead), so a fix here doesn't propagate — check that file too.
_semver_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
  if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
  [ "$a3" -gt "$b3" ]
}

# _release_tag_versions REPO_ROOT — echoes every v-prefixed strict-semver tag (bare `x.y.z`, no `v`),
# one per line, unsorted-by-version (whatever order `git tag -l` gives). Pure (no shared mutable
# state), so check 7 below can call it to stand on its own — independent of whether check 6 ran first
# or its guard changed — without re-deriving the same tag-collection shape by hand (found by
# /simplify's own reuse pass on dir #237's diff, which shipped the collection loop byte-for-byte
# duplicated at first). Check 6 keeps its own inline scan rather than calling this: it folds the
# highest-tag pass together with its `missing_section` scan over the identical `$tags` stream in one
# loop (see the comment there), so calling this helper too would mean scanning `$tags` twice instead
# of once for no benefit.
_release_tag_versions() {
  git -C "$1" tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' || true
}

# _semver_max — reads bare `x.y.z` versions on stdin, one per line, echoes the highest (or empty for
# no input). A THIRD `git tag -l` scan for the max alone (on top of `_release_tag_versions` and check
# 6's own inline one) was flagged independently by three review passes (`/simplify`'s reuse,
# simplification, AND efficiency angles all named the same duplication) — folding the reduction into
# a pipe over an already-fetched list, rather than a second helper that re-fetches, removes it.
_semver_max() {
  local t highest=""
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ -z "$highest" ] || _semver_gt "$t" "$highest"; then highest="$t"; fi
  done
  printf '%s\n' "$highest"
}

# _extract_dir_tickets — reads text on stdin, echoes every `dir #N` ticket it references, one per
# line, deduped (dir #273 gap 2, dir #274). Promoted to tools/lib/dir-tickets.sh (dir #266, its
# second consumer: citation-resolvability.sh) — this is now a one-line wrapper so neither call site
# below nor this file's own 225 tests need to change. See that lib file for the full extraction
# logic (shorthand/range/backtick handling) and its comments; this file no longer keeps its own copy.
# shellcheck source=tools/lib/dir-tickets.sh
. "$self_dir/../lib/dir-tickets.sh"
_extract_dir_tickets() { extract_dir_tickets; }

# KEEL_PENDING_RELEASE_MAX_COMMITS (dir #156, env-overridable, default 40): how many commits past a
# release-in-preparation section's own introducing commit the pending-release allowance below stays
# exempt. `${VAR:-40}`, not a bare `$VAR` reference — `set -u` aborts on an unset bare reference. A
# non-numeric override is treated as unset rather than handed to the `-gt` comparison below: a garbage
# `$pending_max_commits` there wouldn't abort under `set -e` (a failed `[` inside an `if` is exempt),
# but it WOULD corrupt the comparison silently — `[ "$dist" -gt "$pending_max_commits" ]` errors
# "integer expression expected" and evaluates false, fail-opening every section regardless of its real
# distance (found by an operator-run `/code-review high` pass, reproduced live). The digit-shape guard
# alone doesn't catch this: an all-digit string can still overflow the shell's native integer range.
# `sanitize_nonneg_int` (dir #196/#242 — tools/lib/nonneg-int.sh, the one shared sanitizer for this
# class) caps the accepted value at 9 digits (its default 10-digit-or-more rejection), far above any
# sane bound and comfortably inside every shell's integer range (even a 32-bit signed `int`'s
# ~2.1 billion ceiling), so a legitimate override is never affected. Same class as the
# `-r`-not-just-`-f` fix already recorded in this check's own comments below.
# shellcheck source=tools/lib/nonneg-int.sh
. "$self_dir/../lib/nonneg-int.sh"
pending_max_commits="${KEEL_PENDING_RELEASE_MAX_COMMITS:-40}"
# No explicit empty-string handling here: `sanitize_nonneg_int` itself treats '' as invalid and
# returns the default, so `${VAR:-40}` above (unset -> default) and the sanitizer below (empty,
# non-digit-shaped, or overlong -> default) cover unset, empty, and garbage the same way (found by an
# operator-run `/code-review high` pass, reproduced live).
pending_max_commits="$(sanitize_nonneg_int "$pending_max_commits" 40)"

# _pending_release_intro_commit VERSION — print the SHA of the commit that most recently introduced
# the exact heading text "## [VERSION]" into CHANGELOG.md's TRACKED history, OUTSIDE any fenced code
# block — i.e. how long the section AS IT CURRENTLY STANDS has existed, which is what the
# pending-release allowance's commit-distance bound below needs. `git log -S` (the pickaxe) reports
# every commit where the exact occurrence COUNT changed (an add or a remove), newest first — so the
# FIRST entry is normally the commit that introduced today's occurrence (an earlier `tail -1` version
# of this function instead picked the OLDEST such commit ever, in ANY add/remove cycle — wrong when a
# version number is cut, reverted, and later genuinely re-cut with the SAME number).
#
# **Verify-after-the-fact (dir #194, candidate 1 — the operator's choice over "accept and document" for
# this fork):** the pickaxe itself has no concept of "inside a fence" — it matches the file's RAW
# historical content, so a candidate SHA can be a decoy: a commit that only added (or removed) a
# FENCED example elsewhere in CHANGELOG.md (this very file documents its own release-note conventions,
# and an illustrative snippet is a realistic future entry) whose literal text happens to contain a real
# `## [x.y.z]` heading, while the section's actual un-fenced heading was introduced at a DIFFERENT
# commit. A plain "does this commit's fence-blanked content contain the heading" check is not enough to
# tell the two apart — once the real section exists, its heading stays present (fence-blanked) at every
# later commit, decoy or not. What actually distinguishes them is whether THIS commit's own diff added
# the heading OUTSIDE a fence: fence-blank both this commit's content and its immediate PARENT's, and
# require the heading to be PRESENT now but ABSENT before — a targeted, per-candidate recheck (not the
# "reconstruct every historical revision's fence-blanked content and re-search" mechanism this ticket
# explicitly scoped out as too big). Candidates are walked newest first; the first one whose fence-blanked
# presence flips false→true is the real introducing commit — a decoy (present both before and after,
# because the real heading was already there, or the add was itself inside a fence) is skipped in favor
# of the next-newest match. A presence check, not an occurrence-COUNT comparison: a genuinely duplicated
# heading (a bad merge — the file's own separate section-count invariant elsewhere already flags that
# as its own drift) would make a later duplicate-adding commit look like a valid "count went up" event
# to a counting check, but presence alone correctly keeps resolving to the section's true original
# introduction regardless. Confirmed latent, not live: this repo's own CHANGELOG.md has never used a
# fenced `## [x.y.z]`-shaped example, so every real call so far returns on the first candidate — this
# only costs two extra `git show` + awk passes per candidate, and only for a heading with more than one
# pickaxe hit.
#
# Prints nothing if no candidate is found, or if every candidate turns out to be a fence-only add/remove
# — an untracked or freshly-added-but-uncommitted CHANGELOG.md, a history rewrite, or (the fenced case)
# a heading whose every occurrence-count change happened inside an example. The pending-release
# allowance's commit-distance bound below (dir #156) FAILS OPEN on that empty case rather than inventing
# drift from a measurement it couldn't make — see the comment there. Single consumer WITHIN THIS FILE
# (that bound), so — like `_semver_gt` just above — it lives here beside check 6 rather than with the
# file's general helpers. Mirrored (not shared — same reasoning as `_semver_gt` above), scanning
# docs/release-history.md instead of CHANGELOG.md, by `tests/test_release_history.sh`'s own
# pending-release allowance (dir #299) — check that file too when fixing this one.
_pending_release_intro_commit() {
  local heading="## [$1]" rel sha now before
  rel="${changelog_file#"$repo_root"/}"
  # dir #213 closes via SHAPE, not the trailing `|| true`: a process substitution's exit status is never
  # checked by the shell (verified live — `done < <(false)` does not trip `set -e`), so a failing `git
  # log` here could never have aborted the run either way. The actual dir #213 fix is that this function
  # no longer assigns the pickaxe's raw output to a bare `$( )` variable — THAT construct's failing exit
  # status DOES propagate through `set -e`, and this `while read < <(...)` loop structurally can't. The
  # `|| true` stays only because it matches the ticket's own named acceptance criterion, at zero cost.
  while IFS= read -r sha; do
    # Captured into variables, not piped straight into `grep -q` (dir #195's own class, reintroduced
    # here and caught live: `blank_fenced_blocks <(...) | grep -qF ...` SIGPIPEs the awk writer the
    # instant grep finds its match and exits, and under `set -o pipefail` that reads as "not present"
    # even when it plainly is — reproduced against this repo's own real CHANGELOG.md, 300KB+, where the
    # heading sits well before the point grep would need to keep reading). Capturing to `$now`/`$before`
    # first lets `blank_fenced_blocks` run to completion on its own, then a `<<<` here-string grep (no
    # live writer process on the other end) tests presence with nothing left to signal.
    now="$(blank_fenced_blocks <(git -C "$repo_root" show "$sha:$rel" 2>/dev/null) 2>/dev/null)"
    before="$(blank_fenced_blocks <(git -C "$repo_root" show "$sha^:$rel" 2>/dev/null) 2>/dev/null)"
    if grep -qF "$heading" <<< "$now" && ! grep -qF "$heading" <<< "$before"; then
      printf '%s\n' "$sha"
      return 0
    fi
  done < <(git -C "$repo_root" log -S"$heading" --format=%H -- "$changelog_file" 2>/dev/null || true)
}

say ""
say "● CHANGELOG.md <-> git release-tag reconciliation"
changelog_file="$repo_root/CHANGELOG.md"
# Tags are repo-wide, not main-checkout-only like BACKLOG.md — a linked worktree shares the same
# `.git` and sees every tag, so this reads $repo_root directly, no worktree redirection needed.
# A SHALLOW clone (CI's default checkout, or a contributor's `--depth 1`) has few or none of the
# tags this check needs even though the working tree itself is complete and correct — flagging that
# as drift would be a check lying about the repo's own state, so it degrades to a silent skip
# instead. `rev-parse --is-shallow-repository` prints "false" in a normal checkout and "true" in a
# shallow one; `|| true` covers a REPO_ARG sandbox dir that isn't a git repo at all (rev-parse then
# just fails, same treatment as "can't tell, skip" — this check is advisory, not a hard requirement
# to be inside a full git checkout).
# `-r`, not just `-f`: same reason check 5's BACKLOG.md read requires it — an unreadable file
# (e.g. a stray chmod) would otherwise fail the awk pass below and, under `set -euo pipefail`, abort
# the ENTIRE doctor.sh run rather than just this check (found by /code-review medium's own
# line-by-line pass: this condition had only inherited the `-f` half).
if [ -f "$changelog_file" ] && [ -r "$changelog_file" ] \
   && [ "$(git -C "$repo_root" rev-parse --is-shallow-repository 2>/dev/null || echo true)" = "false" ]; then
  # `git tag -l` takes a GLOB, not a regex — `*` matches ANY characters, so the naive glob
  # `v[0-9]*.[0-9]*.[0-9]*` also matches a suffixed pre-release tag like `v0.7.0-rc1` (verified: the
  # trailing `*` swallows `-rc1` too), which `sed 's/^v//' ` would then hand to the comparison below
  # as `0.7.0-rc1` — a string no CHANGELOG section (strictly `[0-9]+\.[0-9]+\.[0-9]+`) can ever match,
  # false-GAPing a healthy repo the day this project first cuts an RC tag (found by an independent
  # reviewer's own pass; no such tag exists yet, so this was latent, not yet triggered). Filtered
  # through a strict, anchored ERE instead of trusting the glob to be exact.
  # `git tag -l` itself always exits 0 (even with zero matches), but a CHANGELOG.md with no version
  # headings YET (a legitimate pre-release state — e.g. this very sandbox fixture) makes `grep`'s
  # no-match exit 1 ripple through `set -o pipefail` into an assignment's own exit status, which under
  # `set -e` would abort the whole doctor.sh run — `|| true` below on every such assignment, same
  # guard check 4's CHANGELOG-staleness timestamps already use.
  tags="$(git -C "$repo_root" tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -u || true)"
  # Same `blank_fenced_blocks` fence-blanking as check 5's BACKLOG.md scan, and for the identical
  # reason (found by /polish's own independent review — this check shipped without it at first): a
  # `## [x.y.z]`-shaped line living inside a fenced example — this very file documents its own
  # release-note conventions, and an illustrative snippet is a realistic future entry — must not be
  # misread as a real release section.
  changelog_blanked="$(blank_fenced_blocks "$changelog_file")"
  # Extracted ONCE, in file order, then projected two ways: `sections` (deduped, for the two
  # membership loops) and `newest_section` (first heading, for the pending-release allowance below).
  # Both projections must be derived from the same scan — the heading regex was briefly spelled a
  # third time here for `newest_section`, which made the allowance silently depend on two greps
  # staying byte-identical (caught by this diff's own /simplify pass, and the same class
  # `blank_fenced_blocks` above was extracted for one release earlier).
  sections_in_order="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' <<< "$changelog_blanked" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  sections="$(sort -u <<< "$sections_in_order")"
  newest_section="$(head -1 <<< "$sections_in_order")"
  unreleased_count="$(grep -cE '^## \[Unreleased\]' <<< "$changelog_blanked" || true)"
  # Only the two heading SHAPES this check actually understands — `[Unreleased]` and a bare semver
  # bracket — not a bare `grep -cE '^## \['`, which would also count any OTHER legitimate `## [...]`
  # heading a CHANGELOG.md might carry (found by an independent reviewer's own pass, empirically
  # reproduced: a lone `## [Deprecated]`-style heading false-GAPed an otherwise perfectly healthy
  # repo, since it inflates this count without a matching tag or an Unreleased bump to balance it).
  total_sections="$(grep -cE '^## (\[Unreleased\]|\[[0-9]+\.[0-9]+\.[0-9]+\])' <<< "$changelog_blanked" || true)"
  n_tags="$(printf '%s\n' "$tags" | grep -c . || true)"

  # One pass over $tags derives BOTH tag-side facts: which tags have no section, and the highest tag
  # (the pending-release allowance below needs it). Folded together rather than run as two separate
  # `while read` loops over the identical stream — the same don't-spell-the-same-scan-twice point the
  # `sections_in_order` note above makes, applied consistently.
  missing_section=""
  highest_tag=""
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ -z "$highest_tag" ] || _semver_gt "$t" "$highest_tag"; then highest_tag="$t"; fi
    grep -qxF "$t" <<< "$sections" || missing_section="$missing_section${missing_section:+, }$t"
  done <<< "$tags"

  # A release being PREPARED legitimately has exactly one version section with no tag yet:
  # docs/release-audit.md phase 7 cuts `## [x.y.z]` and lands it through the normal branch → PR flow,
  # and only THEN does the operator tag the merge commit (cutting the tag is theirs, per the git
  # rails' irreversible-action rule — the preparing session is required to stop before it). Without
  # an allowance, this check GAPs on that very PR and the `self-check` CI job reds the release prep
  # it exists to protect. Found live by dir #155's own RC pass — the first release cut after this
  # check shipped, v0.6.0's section having predated it by one PR.
  #
  # The allowance is deliberately narrow, so it can't absorb the drift this check is for. TWO
  # conditions, both required: the untagged section is the NEWEST heading (first `## [x.y.z]` in file
  # order, per Keep a Changelog's reverse-chronological ordering), AND its version genuinely sorts
  # above every existing tag. A second untagged section, or an untagged one sitting below a tagged
  # one, is still drift and still GAPs.
  #
  # **The version half is load-bearing, not belt-and-braces** — position alone was the first draft of
  # this fix and an independent high-depth review broke it, live: with tags v1.0.0/v1.1.0 and an
  # untagged `## [0.9.0]` at the top of the file, the position-only test exempted a section OLDER than
  # every tag and reported `release in preparation` about it, turning two GAPs into a clean run. That
  # is squarely inside this check's own founding incident (dir #115/PR #118 — git state and CHANGELOG
  # drifting apart) — but only ONE shape of it: a section whose version sorts BELOW some REMAINING tag
  # (a bad merge hoisting a stale section, a hand-written backport section, or a tag deleted while a
  # higher one still stands). It does NOT catch a deleted tag that was the TOPMOST section's own — the
  # commit-distance bound below (dir #156) exists to catch that instead; see its own comment for why.
  # On a linear release line — every release newer than the last, which is keel's own history 0.1.0 → 0.6.1
  # — a release in preparation is always NEWER than everything tagged, so requiring it costs nothing
  # real and closes the below-a-remaining-tag hole. **Where it
  # does cost something, it costs it LOUDLY** (the delta round of the same review named this, and it
  # is why the version test is still worth having): a backport cut below the newest tag — tags
  # v1.0.0/v1.1.0/v2.0.0 and a legitimate `## [1.0.1]` at the top, since Keep a Changelog orders by
  # DATE, not by version — fails this test and GAPs its own release-prep PR. That is a blocking,
  # instantly-diagnosed failure on a repo that starts backporting, not the silent hole position-only
  # left; fix it then, with a real case in hand, rather than pre-building for it now.
  #
  # `_semver_gt` compares the three components as integers in pure bash — no `sort -V` (absent on the
  # alpine-busybox CI leg), no fork. An earlier version of this comment claimed a portable compare
  # wasn't available at all and used that to justify position-only; it was wrong, and the review that
  # found the hole above found the overclaim with it.
  #
  # No tags at all (`$highest_tag` empty) exempts the newest section unconditionally: a repo cutting
  # its very first release has nothing to be newer than.
  #
  # It is announced, never silent: a section left untagged long after its release stays visible on
  # every non-`--quiet` run (it's an expected intermediate state, so an OK line — not a WARN, which
  # would cry wolf on every release PR).
  #
  # **Bounded by commit distance (dir #156).** The two conditions above make a genuinely forgotten tag
  # indistinguishable from one still pending — including this check's OWN founding incident (dir
  # #115/PR #118) recurring through the very door the allowance opened: delete a tag that was the
  # TOPMOST section's own, with no remaining tag above it, and position+version read it as a release
  # in preparation forever. A THIRD conjunct, ANDed onto the whole allowance (not nested inside the
  # version test), closes that: HEAD must also be no more than `$pending_max_commits` commits past the
  # commit that introduced the section's own `## [x.y.z]` heading (`_pending_release_intro_commit`
  # above). This is strictly NARROWING — every input that GAPs today still GAPs, and some that read OK
  # today now GAP instead — so it cannot open a new false-green path; the only risk it adds is a false
  # GAP, and that fires loud, names the section, and states the remedy. Boundary is `>`, not `>=`:
  # distance exactly at the bound stays exempt. A first-ever release (`$highest_tag` empty) is exempt
  # from the VERSION condition below but is NOT exempt from this bound — a first release cut and never
  # tagged is the same forgotten-tag shape as any other.
  #
  # Fails OPEN when the bound can't be computed at all (`_pending_release_intro_commit` returns
  # nothing — the heading text never appears in CHANGELOG.md's tracked history, e.g. an uncommitted
  # file): keep the allowance and say so in the announcement, rather than GAP on a check that could not
  # measure what it would be reporting on. Matches this check's own existing degradation style — the
  # shallow-clone guard above already downgrades to a silent skip instead of inventing drift.
  pending=""
  pending_dist=""
  missing_tag=""
  overbound_section=""
  overbound_dist=""
  # Guard-clause shaped (found by an operator-run `/code-review high` pass, reproduced live as
  # behavior-preserving): `continue` targets this `while`, so each non-candidate exits early rather
  # than nesting the whole remaining chain — the four mutually-exclusive outcomes (not-a-candidate /
  # bound-unresolvable-fail-open / over-bound / within-bound-pending) end up at one consistent depth.
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    grep -qxF "$s" <<< "$tags" && continue
    # `<<<` runs the loop in this same shell, so assignments here survive it (no subshell). Negating
    # the whole compound condition (rather than manually De Morgan-expanding it) keeps this guard
    # byte-identical in meaning to the version it replaces.
    if ! { [ "$s" = "$newest_section" ] && { [ -z "$highest_tag" ] || _semver_gt "$s" "$highest_tag"; }; }; then
      missing_tag="$missing_tag${missing_tag:+, }$s"
      continue
    fi
    intro_commit="$(_pending_release_intro_commit "$s")"
    if [ -z "$intro_commit" ]; then
      pending="$s"   # bound unresolvable -> fail open, per the comment above
      continue
    fi
    dist="$(git -C "$repo_root" rev-list --count "$intro_commit"..HEAD)"
    if [ "$dist" -gt "$pending_max_commits" ]; then
      overbound_section="$s"; overbound_dist="$dist"
      continue
    fi
    pending="$s"; pending_dist="$dist"
  done <<< "$sections"
  # $pending_count is derived, not tracked in parallel — $pending is the single source of truth for
  # whether a section is pending (found by an operator-run `/code-review high` pass: two duplicated
  # `pending_count=1` assignments alongside `pending="$s"` carried no independent information, unlike
  # the genuinely-independent overbound_section/overbound_dist pair, and risked drifting out of sync).
  pending_count=0
  [ -n "$pending" ] && pending_count=1

  changelog_bad=0
  if [ -n "$missing_section" ]; then
    gap "release tag(s) with no matching CHANGELOG.md '## [x.y.z]' section: $missing_section"
    changelog_bad=1
  fi
  if [ -n "$missing_tag" ]; then
    gap "CHANGELOG.md '## [x.y.z]' section(s) with no matching release tag: $missing_tag"
    changelog_bad=1
  fi
  # A dedicated GAP, distinct from the generic "no matching release tag" line above — the remedy here
  # ("tag the release") is different from that line's implication ("this section shouldn't exist").
  # Deliberately does NOT go into $missing_tag and $pending_count stays 0, so the section-count
  # invariant below also fires — two GAPs for one problem, but that is existing, accepted behaviour
  # (the two-untagged-sections fixture above already exhibits it), and the count GAP names no version,
  # so nothing is named twice.
  if [ -n "$overbound_section" ]; then
    gap "'## [$overbound_section]' was cut $overbound_dist commits ago and is still untagged (bound: $pending_max_commits) — tag the release, or the section is drift"
    changelog_bad=1
  fi
  # A DUPLICATED `[Unreleased]` heading evades the count invariant below entirely: both
  # `total_sections` and `unreleased_count` increment together on the extra copy, so the two sides
  # of the comparison stay balanced (found by an independent reviewer's own pass, empirically
  # reproduced — no GAP fired). Needs its own explicit check, not folded into the general invariant.
  # `-gt 1`, not `!= 1`: a CHANGELOG.md that never adopted the bracketed `[Unreleased]` convention at
  # all (0 matches — not this project's own file, but a legitimate state elsewhere, and the shape the
  # test suite's own minimal sandbox fixture uses) is a separate, softer question this check doesn't
  # take a position on; only a genuine DUPLICATE — the bug actually found — is unambiguous enough to
  # GAP on.
  if [ "$unreleased_count" -gt 1 ]; then
    gap "CHANGELOG.md has $unreleased_count '## [Unreleased]' headings, expected at most 1"
    changelog_bad=1
  fi
  # $pending_count is part of "expected" for the same reason it's exempt from the directional check
  # above — a release-in-preparation section is a real, intended heading, so it must not read as a
  # duplicated or refolded one here either.
  expected_sections=$((n_tags + unreleased_count + pending_count))
  if [ "$total_sections" != "$expected_sections" ]; then
    # The untagged-newest term is only spelled when it's actually 1 — appending a constant "+ 0"
    # to every ordinary drift report would be noise on the reading that matters most.
    gap "CHANGELOG.md section count ($total_sections) != tags ($n_tags) + Unreleased ($unreleased_count)${pending:+ + untagged-newest (1)} — a released section may be missing, duplicated, or folded back into [Unreleased]"
    changelog_bad=1
  fi
  if [ -n "$pending" ]; then
    pending_note="bound not computed"
    [ -n "$pending_dist" ] && pending_note="$pending_dist commit(s) since cut, bound $pending_max_commits"
    say "  OK   '## [$pending]' is cut but not tagged yet — release in preparation ($pending_note) (tag the merge commit to close it out)"
  fi
  [ "$changelog_bad" -eq 0 ] && say "  OK   every release tag has a CHANGELOG.md section and vice versa ($n_tags tags)"
else
  say "  OK   no CHANGELOG.md, or a shallow/non-git checkout — skipping tag reconciliation"
fi

# --- 7. commit dir #N tickets vs CHANGELOG.md [Unreleased] section (dir #237) ---------------------
# dir #237: five misses in the v0.7.1 wave (three undetected until the release audit) showed the
# "every user-visible change gets an [Unreleased] entry" convention is prose-only and gets dropped
# under load. Check 4 above (CHANGELOG staleness) is the nearest existing signal, but it is
# TIMESTAMP-shaped — it only compares the newest CHANGELOG.md commit against the newest
# commands/, tools/, or install.sh commit — so a miss with a LATER, unrelated CHANGELOG.md commit landing
# after it is structurally invisible to it (PR #244's own miss shape: two CHANGELOG.md commits landed
# after it and check 4 stayed clean). This check instead ENUMERATES: every `dir #N` referenced in a
# commit message since the previous release tag, diffed against every `dir #N` referenced inside
# CHANGELOG.md's own `[Unreleased]` section. The trigger is per-TICKET, not per-file, on purpose
# (dir #237's second refinement): PR #249 touched CHANGELOG.md — 19 real lines — but for a passenger
# ticket, not its own three, so a per-FILE "touches code but not CHANGELOG.md" trigger would have
# stayed silent on it. Advisory only (WARN, never GAP/deny): a genuinely user-invisible ticket
# (comment-only/test-only) has no entry to give, and that judgment stays human — this check only
# flags the candidates, per the ticket's own acceptance bar.
say ""
say "● commit dir #N tickets vs CHANGELOG.md [Unreleased] section (dir #237)"
if [ -f "$changelog_file" ] && [ -r "$changelog_file" ] \
   && [ "$(git -C "$repo_root" rev-parse --is-shallow-repository 2>/dev/null || echo true)" = "false" ]; then
  # Same tag-collecting shape as check 6 above (v-prefixed strict-semver tags only), via the shared
  # `_release_tag_versions` helper rather than check 6's own $tags — those only exist when check 6's
  # guard above passed, and this check must stand on its own if check 6 is ever reordered or its guard
  # tightened. The helper is pure (no shared state), so calling it costs one more `git tag` scan but no
  # coupling. Fetched ONCE here and reused below for both the highest-tag reduction and the awk
  # membership set — a second, MAX-only helper that re-scanned `git tag` again was flagged
  # independently by three review passes (dir #237) as the exact duplication `_release_tag_versions`
  # itself exists to avoid.
  ct_tag_list="$(_release_tag_versions "$repo_root")"
  ct_highest="$(_semver_max <<< "$ct_tag_list")"
  # `%B` (raw commit message body), `--no-merges` — the exact command dir #237's own body names as
  # what the release audit already used, so this check reproduces a proven-accurate extraction rather
  # than inventing a new one. No prior release tag (a repo's first-ever release) widens to the whole
  # history — there is nothing else to bound the range by yet.
  if [ -n "$ct_highest" ]; then
    ct_range="v$ct_highest..HEAD"
  else
    ct_range="HEAD"
  fi
  ct_commit_tickets="$(git -C "$repo_root" log "$ct_range" --no-merges --format=%B 2>/dev/null \
    | _extract_dir_tickets || true)"
  # The [Unreleased] section's body, PLUS any section(s) below it that are cut but not tagged yet —
  # not the whole file, or an already-released section's historical ticket citations would silently
  # vouch for a DIFFERENT, still-open ticket never actually re-entered under [Unreleased]. Reuses
  # check 6's own `blank_fenced_blocks` pass so a `## [x.y.z]`-shaped or `dir #N`-shaped fenced example
  # (this file documents its own conventions with illustrative snippets) isn't misread as a real
  # section boundary or a real ticket citation.
  # Recomputed independently rather than reused from check 6's own $changelog_blanked — same reason
  # $ct_highest above stands on its own (via the shared helper) instead of reusing check 6's
  # $highest_tag: this check's guard must not silently depend on check 6's internal state staying in
  # sync with it.
  #
  # A cross-model second-opinion review (dir #237) reproduced a real false-positive without this
  # widening: `/wrap`'s release cut moves every ticket out of [Unreleased] into a fresh `## [x.y.z]`
  # heading BEFORE the tag is placed (tagging is the operator's own action, per the git rails — check
  # 6's own "release in preparation" allowance above exists for exactly this window). Bounded to
  # `[Unreleased]` alone, this check would have reported every ticket in the whole release wave as
  # missing on the very PR that files them correctly — noise loud enough to train the reader to ignore
  # it. So the body extraction below keeps grabbing through consecutive `## [x.y.z]` headings as long as
  # each one's version is NOT among the actual git tags — i.e. through the pending, not-yet-tagged
  # section — and only stops at the first section that IS a real released tag.
  # Space-separated, not newline-separated: passed to awk via -v below, and this checkout's own
  # (BSD/one-true) awk rejects a -v value containing an embedded newline outright ("newline in
  # string") rather than just mis-splitting it — found live running this fixture locally, not by
  # either review pass, both of which ran in a container with gawk. Derived from the SAME
  # `$ct_tag_list` already fetched above, not a fresh `git tag` call — see the comment there.
  ct_tag_versions="$(tr '\n' ' ' <<< "$ct_tag_list")"
  ct_changelog_blanked="$(blank_fenced_blocks "$changelog_file")"
  # Heading-version parse: two anchored `sub()` calls, not a single `gsub(/^## \[|\]$/, ...)`. The
  # real heading shape is "## [x.y.z] -- DATE", so the closing bracket is never the LAST character of
  # the line and an end-anchored `\]$` never matches -- a bug that shipped and passed every fixture
  # (none of them cited the SAME ticket in both an already-released section and a later, un-entered
  # commit, so the stop condition silently never firing never changed an assertion outcome). Found
  # live by an operator-run /code-review medium pass. Strip the leading "## [" first, then discard
  # everything from the first "]" onward -- both anchored at a fixed end (start-of-line / first
  # match), so trailing date text after the bracket is irrelevant to either.
  ct_unreleased_body="$(awk -v tags="$ct_tag_versions" '
    BEGIN { n = split(tags, arr, " "); for (i = 1; i <= n; i++) tagged[arr[i]] = 1 }
    /^## \[Unreleased\]/ { grabbing=1; next }
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
      if (!grabbing) next
      ver=$0; sub(/^## \[/, "", ver); sub(/\].*/, "", ver)
      if (ver in tagged) { grabbing=0 }
      next
    }
    /^## / { grabbing=0 }
    grabbing { print }
  ' <<< "$ct_changelog_blanked")"
  ct_unreleased_tickets="$(_extract_dir_tickets <<< "$ct_unreleased_body" || true)"
  # Set difference via the same here-string-into-`grep -qxF` per-item membership idiom check 6's
  # pending-tag loop already uses above, not `comm` — `comm` needs no extra dependency here (it's
  # coreutils, not guaranteed on the alpine-busybox CI leg the way `grep`/`awk`/`sed` are), and this
  # idiom is already this file's own established style for a small set-membership test.
  ct_missing=""
  if [ -n "$ct_commit_tickets" ]; then
    while IFS= read -r ticket; do
      [ -n "$ticket" ] || continue
      if [ -z "$ct_unreleased_tickets" ] || ! grep -qxF "$ticket" <<< "$ct_unreleased_tickets"; then
        ct_missing="$ct_missing${ct_missing:+, }$ticket"
      fi
    done <<< "$ct_commit_tickets"
  fi
  ct_since="the repo's start"
  [ -n "$ct_highest" ] && ct_since="v$ct_highest"
  if [ -n "$ct_missing" ]; then
    warn "ticket(s) referenced in commits since $ct_since but absent from CHANGELOG.md's [Unreleased] section: $ct_missing — verify each is a legitimate no-entry case (comment/test-only) before releasing (dir #237)"
  else
    say "  OK   every dir #N referenced in commits since $ct_since appears in CHANGELOG.md's [Unreleased] section"
  fi
else
  say "  OK   no CHANGELOG.md, or a shallow/non-git checkout — skipping commit-ticket reconciliation"
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

# Streamed directly rather than through run_check(): run_check only shows a tool's output when it
# FAILS, but prose-drift.sh's line-length signal is advisory (WARN) by design and must stay visible
# on every run, not just a failing one — only its dead-link signal (GAP) affects this exit code.
say ""
if [ -f "$self_dir/prose-drift.sh" ]; then
  pd_args=("$repo_root")
  [ "$QUIET" = 1 ] && pd_args+=(--quiet)
  bash "$self_dir/prose-drift.sh" "${pd_args[@]}" || exit_code=1
else
  # Same reporting shape as every other check here (a structured GAP line), not the raw, unlabeled
  # "No such file or directory" bash itself would print for a bare `bash <missing path>` call — a
  # future rename/move of prose-drift.sh should fail loud AND diagnosable, not just loud.
  gap "tools/self/prose-drift.sh missing — dead-link and line-length checks skipped"
fi

say ""
say "  MANUAL  PRINCIPLES.md tension-enforcement isn't mechanizable (needs judgment) — run the Principles pass in /global-review"

say ""
[ "$exit_code" = 0 ] && say "self/doctor: keel repo structural self-check OK"
exit "$exit_code"
