#!/usr/bin/env bash
# tools/delta-audit/derive.sh — mechanically derive a delta audit's universe from git history.
#
# Adopter-facing: given a release's previous tag/sha and its RC sha, this emits the file list a delta
# audit must cover, a file→PR seam map, an empty-verdict ledger skeleton, and a run-record stub — so
# the audit's scope is a reproducible artifact instead of a hand-drawn list that quietly disagrees
# with the tree. Full procedure: docs/delta-audit.md. Flags: --help.
#
# Promotes private/audit/delta-0.7.0-0.7.1/derive.sh (dir #207's own prototype, run live for the
# v0.7.0->v0.7.1 tag) into a tested, adopter-facing script — the core git commands below are
# unchanged from it on purpose: two stored datasets (v0.7.0..84ef536 and v0.6.1..f6f81d8) exist only
# because that prototype produced them, and this script's test suite reproduces both byte-identically
# against the CORE logic, not a rewrite of it.
#
# Exit codes: 0 derived · 2 bad arguments · 3 refused.
#
# Refusals (exit 3): not a git repository; <prev-rev> or <head-rev> does not resolve; the output
# directory is absent or unwritable. Deliberately NOT a clean-tree / HEAD-equals-baseline refusal —
# tools/drydock/inventory.sh needs that because it MEASURES THE WORKING TREE, whereas this script
# reads only history (`git diff <a>..<b>`, `git log --merges`), so a dirty tree cannot change its
# output. TO VERIFY was closed empirically: tests/test_delta_audit_derive.sh's dirty-tree case proves
# the four output files are byte-identical to the clean-tree run.
#
# The closure check (below) is the headline feature, not a nicety: it is the guard against this
# derivation's one structural blind spot. The PR map comes from `git log --merges` plus a
# "Merge pull request #N" subject line, so a SQUASH-MERGED or REBASE-MERGED pr contributes zero rows
# and the map silently under-counts — exactly the failure the v0.7.0 run's S1 session caught by hand
# (24 vs 31 PRs) before this script existed. Keel merges with merge commits; an adopter's repo may
# not. When the union of every per-PR file list disagrees with the range diff, this prints both sides
# and exits 3 — same refusal code as the guards above, because an incomplete seam map is exactly as
# untrustworthy as a tree nobody chose.
#
# Class assignment (ledger.md) is MECHANICAL, first-match-wins, never judgment:
#   1. CHANGELOG.md, or a path in DELTA_HISTORICAL           -> prose-historical
#   2. a path containing a DELTA_INVARIANT_PATHS substring   -> code-invariant
#   3. a path starting with tests/                           -> test
#   4. a *.sh/*.yml/*.yaml path, or one executable at <head-rev> -> code
#   5. everything else (*.md and the rest)                   -> prose
#
# Emission ORDER in ledger.md is a pinned behaviour, not a formatting detail (docs/delta-audit.md's
# read-order rule, dir #207's own corollary): seams (>=2 PRs) and code-invariant files FIRST, the
# remaining code/test files next, prose and prose-historical LAST — never git diff --name-only's
# alphabetical order. "Suggested session" numbers pack that same read-ordered list into groups of
# DELTA_SESSION_FILES, starting at S2 (S1 is the mechanical baseline this script itself produces, and
# covers every row).
#
# Tuning, for a repo whose shape differs from the defaults (all optional, all environment):
#   DELTA_HISTORICAL       exact repo-relative paths always classed prose-historical (default:
#                           CHANGELOG.md)
#   DELTA_INVARIANT_PATHS  substrings marking behaviour-with-a-rail code (default: "pre-pr-gate
#                           secret-guard install.sh uninstall.sh .github/workflows/")
#   DELTA_SESSION_FILES    files packed into one suggested session (default: 12)
#
# Every sort in this script is LC_ALL=C: a locale-dependent collation would make the byte-identical
# reproduction this script exists for depend on the operator's machine, and BusyBox/GNU/macOS agree
# only in the C locale.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: derive.sh [--out <dir>] <prev-rev> <head-rev>

Derive a delta audit's universe from git history: the file list, the file->PR seam map, a ledger
skeleton, and a run-record stub. Writes into <dir> (default: .).

  --out <dir>   directory to write into (default: current directory). Created if it does not exist;
                refuses if it cannot be created or written to.
  -h, --help    this message.

Outputs, into <dir>:
  delta-files.txt   git diff --name-only <prev>..<head>, sorted — the universe
  file-pr-map.tsv   file <TAB> <n PRs> <TAB> <PR list> — one row per file touched by a merge PR
  ledger.md         one row per file: file, class, PRs, suggested session, empty verdict column
  run-record.md     a stub of the cross-run row for private/audit/RUNS.md

Exit codes: 0 derived · 2 bad arguments · 3 refused (not a repo / a rev does not resolve / the output
directory is unusable). There is no clean-tree or HEAD guard: this script reads only history, so a
dirty working tree cannot change its output. Tuning environment variables are documented in this
file's header.
EOF
}

err()      { printf 'derive.sh: %s\n' "$1" >&2; exit "$2"; }
die_args() { err "$1" 2; }
refuse()   { err "$1" 3; }

# Captured before any `cd` below, same reasoning as tools/drydock/inventory.sh's own script_dir: $0
# may be a relative path, resolved against the ORIGINAL cwd, not repo_root.
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tools/lib/nonneg-int.sh
. "$script_dir/../lib/nonneg-int.sh"

out_dir="."
prev_rev=""
head_rev=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)     [ $# -ge 2 ] || die_args "--out needs a directory"; out_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        die_args "unknown option '$1' (see --help)" ;;
    *)
      if [ -z "$prev_rev" ]; then prev_rev="$1"
      elif [ -z "$head_rev" ]; then head_rev="$1"
      else die_args "unexpected argument '$1' — derive.sh takes exactly two revisions"
      fi
      shift ;;
  esac
done
[ -n "$prev_rev" ] || die_args "missing <prev-rev> (see --help)"
[ -n "$head_rev" ] || die_args "missing <head-rev> (see --help)"

# --- the guard --------------------------------------------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || refuse "not a git repository (run this inside the repo whose range you are deriving)"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

prev="$(git rev-parse --verify --quiet "${prev_rev}^{commit}" || true)"
[ -n "$prev" ] || refuse "cannot resolve <prev-rev> '$prev_rev' — fetch first (git fetch --prune), or
check the spelling."
head_sha="$(git rev-parse --verify --quiet "${head_rev}^{commit}" || true)"
[ -n "$head_sha" ] || refuse "cannot resolve <head-rev> '$head_rev' — fetch first (git fetch --prune),
or check the spelling."

mkdir -p "$out_dir" 2>/dev/null || refuse "cannot create output directory '$out_dir'"
[ -w "$out_dir" ] || refuse "output directory '$out_dir' is not writable"
out_dir="$(cd "$out_dir" && pwd)"

# KNOWN LIMITATION (found by an operator-run /simplify altitude pass, no live instance found in
# this repo's own two reference datasets): every git enumeration below is newline-delimited, not
# NUL-delimited (`-z`), unlike tools/drydock/inventory.sh's own enumerations. A tracked path git
# cannot print literally (a backslash, a double quote, non-ASCII) comes back C-quoted, which would
# silently break a classify() prefix/suffix match; a path containing a literal tab or newline byte
# would corrupt a TSV/ledger row outright, the same way inventory.sh's own now-fixed incident did.
# Retrofitting inventory.sh's `-z` + assert_representable discipline here needs restructuring the
# nested git-log/git-diff extraction below (file-pr-map.tsv's per-merge loop is two levels deep),
# which is a real rewrite, not a local fix — judged not worth the regression risk against this
# script's two byte-identical reference datasets for what both cited incidents so far have been:
# purely hypothetical for this class of tracked path. Left as a follow-up if a real repo ever hits it.

# One scratch dir for every intermediate file below, cleaned unconditionally on exit — including a
# refusal/error partway through — rather than each stage's own `mktemp`+inline-`rm -f` pair, which
# leaks its file if anything between the two fails under `set -e` (tools/drydock/inventory.sh
# established this exact pattern for the same reason; this script had drifted from it).
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# --- delta-files.txt ----------------------------------------------------------------------------
git diff --name-only "$prev..$head_sha" | LC_ALL=C sort > "$out_dir/delta-files.txt"

# --- file-pr-map.tsv ------------------------------------------------------------------------------
# Per-merge file lists -> file->PR map. A merge vs its first parent is that PR's net contribution.
# Plain "Merge branch main into ..." commits (no PR subject) are skipped, not counted as PR #0.
tmp="$scratch/pr-pairs"
git log "$prev..$head_sha" --merges --format='%H %s' | while read -r sha subj; do
  pr="$(printf '%s\n' "$subj" | sed -n 's/^Merge pull request #\([0-9]*\) .*/#\1/p')"
  [ -n "$pr" ] || continue
  git diff --name-only "$sha^1" "$sha" | while IFS= read -r f; do
    printf '%s\t%s\n' "$f" "$pr"
  done
done | LC_ALL=C sort -u > "$tmp"
LC_ALL=C awk -F'\t' '{ prs[$1] = prs[$1] " " $2; n[$1]++ }
  END { for (f in prs) printf "%s\t%d\t%s\n", f, n[f], substr(prs[f], 2) }' "$tmp" \
  | LC_ALL=C sort > "$out_dir/file-pr-map.tsv"

# --- the closure check --------------------------------------------------------------------------
# Symmetric difference between the union of per-PR file lists and delta-files.txt. `comm -3` needs
# both inputs sorted in the same collation, which the LC_ALL=C sort above already guarantees.
only_in_delta="$(comm -23 "$out_dir/delta-files.txt" <(cut -f1 "$out_dir/file-pr-map.tsv"))"
only_in_map="$(comm -13 "$out_dir/delta-files.txt" <(cut -f1 "$out_dir/file-pr-map.tsv"))"
closure_ok=1
if [ -n "$only_in_delta" ] || [ -n "$only_in_map" ]; then
  closure_ok=0
  {
    printf 'derive.sh: the universe does not close — the PR map disagrees with the range diff.\n'
    printf 'This usually means a squash-merged or rebase-merged PR: it changed files but left no\n'
    printf '"Merge pull request #N" commit for this script to find, so its files silently drop out\n'
    printf 'of the seam map. If this repo does not merge with merge commits, the map is unreliable.\n'
    if [ -n "$only_in_delta" ]; then
      printf '\nin the range diff but attributed to no PR:\n'
      printf '%s\n' "$only_in_delta" | sed 's/^/  /'
    fi
    if [ -n "$only_in_map" ]; then
      printf '\nattributed to a PR but outside the range diff:\n'
      printf '%s\n' "$only_in_map" | sed 's/^/  /'
    fi
  } >&2
fi

# --- ledger.md ------------------------------------------------------------------------------------
TAB="$(printf '\t')"
read -r -a historical <<< "${DELTA_HISTORICAL:-CHANGELOG.md}"
read -r -a invariant <<< "${DELTA_INVARIANT_PATHS:-pre-pr-gate secret-guard install.sh uninstall.sh .github/workflows/}"
# `sanitize_nonneg_int` accepts 0 (it means "non-negative", not "positive"), which this divisor
# below cannot: DELTA_SESSION_FILES=0 used to divide-by-zero inside the `idx / session_cap`
# expression, which under `set -e` aborts only the current loop iteration's `printf` rather than the
# whole script, so the run reported exit 0 with every ledger data row silently missing. Falls back
# to the default the same way every other invalid override does in this codebase (never a refusal
# for a tuning knob, per tools/self/doctor.sh's own `pending_max_commits` precedent).
session_cap="$(sanitize_nonneg_int "${DELTA_SESSION_FILES:-12}" 12)"
[ "$session_cap" -gt 0 ] || session_cap=12

is_historical() {
  local h
  for h in "${historical[@]}"; do [ "$h" = "$1" ] && return 0; done
  return 1
}
is_invariant() {
  local pat
  for pat in "${invariant[@]}"; do
    case "$1" in *"$pat"*) return 0 ;; esac
  done
  return 1
}
is_test() { case "$1" in tests/*) return 0 ;; esac; return 1; }
# $2 is the executable flag (0/1) the join below already resolved — no `git ls-tree` call here.
is_code() {
  case "$1" in
    *.sh|*.yml|*.yaml) return 0 ;;
  esac
  [ "$2" = 1 ]
}
classify() {
  if is_historical "$1"; then printf 'prose-historical'
  elif is_invariant "$1"; then printf 'code-invariant'
  elif is_test "$1"; then printf 'test'
  elif is_code "$1" "$2"; then printf 'code'
  else printf 'prose'
  fi
}

# One tree listing at EACH endpoint, not a `git ls-tree` fork per file: an executable bit is looked
# up from these two precomputed maps, mirroring the file-pr-map.tsv join's own "measured ONCE" idiom
# instead of the per-file re-fork it had originally been written with (found by /code-review medium).
# BOTH endpoints, not just head: a file DELETED within the range has no entry in head's tree at all,
# so a head-only lookup silently misclassified a removed executable as prose — the mirror image of
# the added-executable case this script's own tests already pinned. Falling back to prev's mode when
# a path is absent from head's tree closes that gap.
git ls-tree -r --full-tree --format='%(objectmode)%x09%(path)' "$head_sha" > "$scratch/head-modes"
git ls-tree -r --full-tree --format='%(objectmode)%x09%(path)' "$prev" > "$scratch/prev-modes"

# One join, not a per-file re-scan: file-pr-map.tsv and the two mode listings above are fully known
# by this point, so look every file's PR count/list AND executable status up ONCE (mirroring
# tools/drydock/inventory.sh's own "measured ONCE into a stream" idiom). Plain awk, not a bash
# associative array: this repo's own /bin/bash is 3.2 on stock macOS, which has no `declare -A`.
joined="$scratch/joined"
# `FILENAME == ...`, not the usual bare `NR == FNR`: when file-pr-map.tsv (or either mode listing)
# is EMPTY, the classic NR==FNR idiom breaks — zero iterations happen while "processing" an empty
# file, so NR never advances, and the first line of whichever file comes next then also satisfies
# NR==FNR and gets silently swallowed into an array-building branch instead of reaching the emit
# branch. Comparing FILENAME instead is immune regardless of which input files are empty. Found live
# by this script's own test suite (a single non-merge-commit fixture, empty file-pr-map.tsv).
awk -F'\t' -v prmap="$out_dir/file-pr-map.tsv" \
           -v headmodes="$scratch/head-modes" -v prevmodes="$scratch/prev-modes" '
  FILENAME == prmap     { n[$1] = $2; prs[$1] = $3; next }
  FILENAME == headmodes { hmode[$2] = $1; next }
  FILENAME == prevmodes { pmode[$2] = $1; next }
  {
    exe = 0
    if ($1 in hmode)      { if (hmode[$1] == "100755") exe = 1 }
    else if ($1 in pmode) { if (pmode[$1] == "100755") exe = 1 }
    # prs LAST, not before exe: bash "read" with IFS set to a tab still treats tab as IFS
    # whitespace and collapses or skips an EMPTY field wherever it falls in the MIDDLE of a
    # record; only the record own trailing field is exempt, since read hands it whatever
    # remains verbatim, even empty. prs[$1] is empty for any file with zero PR attribution, so
    # it must stay last in every record this script emits, or a later empty PR list silently
    # shifts every field after it. Found live: this exact bug shipped once, misreading an
    # executable own exe=1 flag as its own prs column while leaving prs empty in the same record.
    print $1 "\t" (($1 in n) ? n[$1] : 0) "\t" exe "\t" prs[$1]
  }
' "$out_dir/file-pr-map.tsv" "$scratch/head-modes" "$scratch/prev-modes" "$out_dir/delta-files.txt" \
  > "$joined"

# Bucket into the pinned read order: (1) seams (>=2 PRs) + code-invariant, (2) remaining code/test,
# (3) prose + prose-historical — never git diff --name-only's alphabetical order. Plain indexed
# arrays, not temp files: bash 3.2 (this repo's own /bin/bash on stock macOS) has them, and each
# array preserves delta-files.txt's own (already sorted) insertion order, same as a file would.
bucket1=(); bucket2=(); bucket3=()
while IFS="$TAB" read -r f n exe prs; do
  [ -n "$f" ] || continue
  class="$(classify "$f" "$exe")"
  row="$f$TAB$class$TAB$n$TAB$prs"
  # prose-historical is checked FIRST, even ahead of the seam test: CHANGELOG.md is a seam on
  # nearly every real run (every PR that ships user-visible change touches it), and the read-order
  # rule names it explicitly as belonging in the LAST bucket regardless — drydock's own historical-
  # prose rule makes the same exception for the same file, for the same reason.
  if [ "$class" = prose-historical ] || [ "$class" = prose ]; then
    bucket3+=("$row")
  elif [ "$n" -ge 2 ] || [ "$class" = code-invariant ]; then
    bucket1+=("$row")
  else
    bucket2+=("$row")
  fi
done < "$joined"

# `[ "${#bucketN[@]}" -gt 0 ] &&`, not a bare `"${bucketN[@]}"` expansion: under `set -u`, expanding
# an EMPTY array is a hard error on bash < 4.4 (this repo's own stock-macOS bash is 3.2) — the length
# check short-circuits the expansion via `&&` so it never runs on an empty array. idx is deliberately
# a global `emit_bucket` mutates directly (no `local idx`), so numbering continues across all three
# calls instead of restarting each bucket at S2.
idx=0
emit_bucket() {
  local row f class n prs session
  for row in "$@"; do
    IFS="$TAB" read -r f class n prs <<< "$row"
    session="S$((2 + idx / session_cap))"
    printf '| %s | %s | %s | %s | %s | |\n' "$f" "$class" "$n" "$prs" "$session"
    idx=$((idx + 1))
  done
}
{
  printf '# Ledger — %s..%s\n\n' "$prev_rev" "$head_rev"
  printf 'Generated mechanically by `tools/delta-audit/derive.sh` from `git diff --name-only\n'
  printf '%s..%s` and the per-merge PR map. Fill the verdict column per docs/delta-audit.md.\n\n' \
    "$prev" "$head_sha"
  printf 'Read order: seams and code-invariant files first, remaining code/test next, prose and\n'
  printf 'prose-historical last (docs/delta-audit.md read-order rule) — S1 is the mechanical\n'
  printf 'baseline and covers every row; suggested sessions below start at S2.\n\n'
  printf '| file | class | #PRs | PRs | suggested session | verdict |\n'
  printf '|---|---|---|---|---|---|\n'
  [ "${#bucket1[@]}" -gt 0 ] && emit_bucket "${bucket1[@]}"
  [ "${#bucket2[@]}" -gt 0 ] && emit_bucket "${bucket2[@]}"
  [ "${#bucket3[@]}" -gt 0 ] && emit_bucket "${bucket3[@]}"
} > "$out_dir/ledger.md"

# --- run-record.md stub ---------------------------------------------------------------------------
file_count="$(LC_ALL=C wc -l < "$out_dir/delta-files.txt" | tr -d ' ')"
pr_count="$(cut -f3 "$out_dir/file-pr-map.tsv" | tr ' ' '\n' | LC_ALL=C sort -u | grep -c '^#' || true)"
{
  printf '# Run record — %s..%s\n\n' "$prev_rev" "$head_rev"
  printf 'Stub emitted by `tools/delta-audit/derive.sh`. Fill in at verdict time and append this row\n'
  printf 'to private/audit/RUNS.md (dir #249 owns the append step; this script owns only the stub).\n\n'
  printf '| | |\n|---|---|\n'
  printf '| scope | %s files, %s PRs |\n' "$file_count" "$pr_count"
  printf '| method | |\n'
  printf '| coverage | |\n'
  printf '| findings | |\n'
  printf '| behavioural defects in shipped code | |\n'
  printf '| diversity result | |\n'
  printf '| records | |\n'
} > "$out_dir/run-record.md"

# Deliberate departure from tools/drydock/inventory.sh's refusal philosophy ("refuse" there means
# nothing is written at all): ledger.md and run-record.md are written even when the closure check
# just declared the PR map untrustworthy, because the FILE LIST itself (delta-files.txt) is still
# correct — only the seam attribution is short — and an operator diagnosing a squash-merge gap needs
# something to inspect, not just a bare stderr message. tests/test_delta_audit_derive.sh's own
# closure-failure fixture asserts this on purpose.
[ "$closure_ok" -eq 1 ] || exit 3
exit 0
