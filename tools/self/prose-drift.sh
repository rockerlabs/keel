#!/usr/bin/env bash
# tools/self/prose-drift.sh — keel-self-maintenance (dir #68): audits the KEEL REPO'S OWN tracked
# prose, not an adopter's install — there is no consumer-facing counterpart, and install.sh never
# ships this file. Invoked by tools/self/doctor.sh's orchestrated checks and by this file's own test;
# named from adopter-facing prose at exactly one place, docs/drydock.md's phase-0 mechanical-sweeps
# paragraph, under docs/reference.md's generic tools/self/ maintainer-only exemption.
#
# Promotes drydock run 1's throwaway mechanical sweep (private/audit/bin/sweep.sh, dir #165) into a
# standing check. Two signals, deliberately different severities:
#
#   WARN  anomalous line length inside a wrapped block — a md prose line or sh comment line that
#         sits notably longer than the OTHER lines in its own block (a paragraph, a wrapped list
#         item, a comment run), never a flat global threshold. This is the drydock trigger class: an
#         unfinished edit can leave one line running dramatically past the rest of a hand-wrapped
#         paragraph, and that shape — one outlier among consistently-wrapped neighbors — is what
#         actually distinguishes a truncated edit from an ordinary long sentence. A flat >110-char
#         threshold does not distinguish them: it produced 194 leads on this very tree (dir #169),
#         almost all of them ordinary table rows, fenced examples, and plain sentences that just run
#         a little long — not defects. So a line only counts here relative to its own block, and
#         fenced code, GFM tables, YAML frontmatter, standalone link/image lines, and any line
#         embedding a URL are excluded outright (none of those are wrapped prose to begin with).
#         Advisory only, per sweep.sh's own framing ("leads, not verdicts"): a WARN never fails this
#         script, because the block-relative heuristic still can't tell a genuine truncation from an
#         ordinary sentence that simply runs a bit long (an inline command kept on one line, two
#         short clauses sharing a line) — both look identical to a mechanical length comparison. A
#         WARN says "a human may want to glance here," nothing stronger.
#   GAP   dead relative markdown link — a `[text](target)` whose target does not resolve on disk.
#         Zero legitimate exceptions (a link either resolves or it doesn't), so this one is a hard
#         fail, unlike signal 1.
#
# Usage:
#   tools/self/prose-drift.sh [REPO_DIR] [--quiet]
#   tools/self/prose-drift.sh -h | --help
#
# REPO_DIR defaults to the current directory (test-sandbox friendly, like shellcheck-targets.sh);
# day-to-day this is invoked by tools/self/doctor.sh, which passes its own resolved repo root.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"

QUIET=0
usage() {
  cat <<'EOF'
tools/self/prose-drift.sh — anomalous-line-length + dead-relative-link sweep over tracked prose.

Usage:
  tools/self/prose-drift.sh [REPO_DIR]   scan REPO_DIR (default: current directory)
  tools/self/prose-drift.sh --quiet      print only WARN/GAP lines
  tools/self/prose-drift.sh -h | --help

Exit 0 unless a dead relative link is found (a line-length WARN never fails this script).
EOF
}
REPO_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "prose-drift.sh: unknown flag '$1' (try --help)" >&2; exit 2 ;;
    *) REPO_ARG="$1" ;;
  esac
  shift
done
repo_dir="${REPO_ARG:-.}"
[ -d "$repo_dir" ] || { echo "prose-drift.sh: not a directory: $repo_dir" >&2; exit 2; }

exit_code=0
say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

say "● prose drift ($repo_dir)"

# --- signal 1: anomalous line length inside a wrapped block ---------------------------------------
# WRAP_MAX: a line at or below this is "normal wrapped prose" and can anchor a block's baseline.
# MARGIN: how far past the block's own baseline a line must run before it counts as an outlier.
# MIN_BLOCK: a block needs at least this many lines before "relative to its neighbors" means
# anything — a 2-line paragraph's trailing line is routinely a bit longer or shorter than its first
# for no reason at all (verified empirically against this tree: excluding 2-line blocks removed
# several genuine false positives without losing the real trigger-class shape, which needs at least
# one anomalous line AND at least two normal ones to compare it against).
WRAP_MAX=115
MARGIN=18
MIN_BLOCK=3

# One awk program, MODE-switched, rather than two near-identical copies (md's table/heading/bullet
# handling vs sh's bare-comment-run handling) — the anomaly math in END is shared verbatim and must
# stay that way; a second hand-maintained copy is exactly the drift class this project's own
# doctor.sh check 1/1b exist to catch elsewhere. Reads the file body on STDIN, not as a filename
# argument: the md caller below pre-blanks fenced code through the shared blank_fenced_blocks() — a
# fence toggle re-derived here instead would be a second copy of that exact drift, one file over —
# so this program itself never needs to know about fences at all. Emits TSV (line, length,
# block-baseline) per hit.
scan_line_length() {   # scan_line_length MODE(md|sh)   (reads the file body on stdin)
  awk -v WRAP_MAX="$WRAP_MAX" -v MARGIN="$MARGIN" -v MIN_BLOCK="$MIN_BLOCK" -v MODE="$1" '
    function is_bullet(l)  { return (l ~ /^[-*+][ \t]/) || (l ~ /^[0-9]+\.[ \t]/) }
    function is_heading(l) { return l ~ /^#{1,6}[ \t]/ }
    function is_table(l)   { return l ~ /^[ \t]*\|.*\|[ \t]*$/ }
    function is_linkline(l){ return (l ~ /^[ \t]*\[.*\]\(.*\)/) || (l ~ /^[ \t]*\[[^]]*\]:/) }
    function has_url(l)    { return l ~ /https?:\/\// }
    function record() {
      len = length(raw)
      n[block]++
      bl[block, n[block]] = len
      ln[block, n[block]] = NR
      urlf[block, n[block]] = has_url(raw)
    }
    BEGIN { block = 0; prev_blank = 1; in_front = 0; prev_comment = 0 }
    MODE == "md" {
      raw = $0
      # A leading `---`/`---` pair is YAML frontmatter (commands/*.md), not prose — blank it like a
      # fence. Only recognized at the very top of the file, the one place frontmatter is valid.
      if (NR == 1 && raw == "---") { in_front = 1; prev_blank = 1; next }
      if (in_front) { if (raw == "---") in_front = 0; prev_blank = 1; next }
      if (raw ~ /^[ \t]*$/) { prev_blank = 1; next }
      if (is_heading(raw) || is_table(raw) || is_linkline(raw)) { prev_blank = 1; next }
      # A top-level bullet/numbered-item marker always starts a FRESH block, even with no blank line
      # before it — each list item is its own unit, not a continuation of the previous one; only an
      # indented continuation line (no marker) joins the bullet that opened the block.
      if (is_bullet(raw) || prev_blank) block++
      prev_blank = 0
      record()
      next
    }
    MODE == "sh" {
      raw = $0
      if (raw !~ /^[ \t]*#/)        { prev_comment = 0; next }   # code or blank line -> break
      if (raw ~ /^[ \t]*#!/)        { prev_comment = 0; next }   # shebang is not prose
      if (raw ~ /^[ \t]*#[ \t]*$/)  { prev_comment = 0; next }   # bare "#" is a blank-line-in-comment separator
      if (!prev_comment) block++
      prev_comment = 1
      record()
      next
    }
    END {
      for (b = 1; b <= block; b++) {
        cnt = n[b]; if (cnt < MIN_BLOCK) continue
        # This block wrap baseline is the same for every candidate line in it — a line only ever
        # qualifies as a candidate once its own length already exceeds WRAP_MAX (the `continue`
        # below), so it can never itself contribute to the baseline max regardless of which
        # candidate is being checked; a per-candidate re-scan excluding it would just recompute the
        # identical value. One pass over the block up front, not one pass per candidate.
        maxother = 0
        for (j = 1; j <= cnt; j++) {
          lj = bl[b, j]
          if (lj <= WRAP_MAX && lj > maxother) maxother = lj
        }
        for (i = 1; i <= cnt; i++) {
          if (urlf[b, i]) continue                # a line carrying a literal URL is data, not prose
          li = bl[b, i]
          if (li <= WRAP_MAX) continue
          if (maxother > 0 && (li - maxother) >= MARGIN)
            printf "%d\t%d\t%d\n", ln[b, i], li, maxother
        }
      }
    }
  '
}

# report_hits MODE FILES — FILES is a newline-separated list (already resolved by the caller, so a
# list shared with another signal — see md_files below — is computed by git only once). Empty FILES
# is a legitimate case (e.g. a repo with no tracked shell scripts) and returns with no output, rather
# than looping once over an empty line.
report_hits() {
  local mode="$1" files="$2" f
  [ -n "$files" ] || return 0
  # sh reads its file directly via redirection rather than through `cat` — scan_line_length is
  # stdin-based, so a `cat |` here would spawn a process purely to move bytes for every sh file (a
  # real, if small, cost across ~69 tracked shell scripts); md still needs blank_fenced_blocks' own
  # awk pass first, so it keeps the pipe. The mode check itself stays per-file (cheap, no
  # subprocess) rather than hoisted above the loop — a hoisted variable would have to carry two
  # DIFFERENT pipeline shapes (one command vs. two piped together), which reads as more indirection
  # than the plain per-file branch it would replace.
  while IFS= read -r f; do
    while IFS=$'\t' read -r ln len base; do
      warn "$f:$ln ($len ch, block wrap ~$base ch) — runs well past its wrapped neighbors"
      ll_hits=$((ll_hits + 1))
    done < <(
      if [ "$mode" = md ]; then
        blank_fenced_blocks "$repo_dir/$f" | scan_line_length "$mode"
      else
        scan_line_length "$mode" < "$repo_dir/$f"
      fi
    )
  done <<< "$files"
}

# `|| true`: an unusual environment can make `git` itself fail outright here (e.g. a container
# reading a bind-mounted repo it does not own emits "detected dubious ownership" and exits 128,
# felt live on this project's own alpine-busybox CI leg) — under `set -o pipefail` that would
# otherwise abort this whole script at the assignment. doctor.sh's own git-backed checks already
# degrade the same way rather than crash; this keeps prose-drift.sh consistent with that rather
# than being the one check that takes doctor.sh down with it via its own `|| exit_code=1`.
md_files="$(git -C "$repo_dir" ls-files '*.md' | sort || true)"
# Reuses tools/self/shellcheck-targets.sh's own enumeration rather than a hand-rolled `*.sh` glob —
# that script exists specifically because a plain pathspec misses shebang-only, extensionless
# scripts (e.g. tools/secret-guard/pre-commit and pre-push both slipped through a bare glob here
# until this fix). Filtered to tools/ and tests/ to keep sweep.sh's original scope (a top-level
# installer/entry-point script like install.sh or bootstrap.sh is a different kind of prose than the
# tools/ tree this signal targets, and was never in scope even before this fix).
# `|| true`: grep exits 1 on zero matches (a repo/sandbox with no tools/ or tests/ shell scripts at
# all is legitimate — the earlier `git ls-files` calls never needed this guard since ls-files itself
# exits 0 on an empty match set, but grep does not), and under `set -o pipefail` that would otherwise
# abort this whole script at the assignment, unlike an empty result from the loop below.
sh_files="$(bash "$self_dir/shellcheck-targets.sh" "$repo_dir" | grep -E '^(tools|tests)/' | sort || true)"

say ""
say "● signal 1 — anomalous line length inside a wrapped block (advisory)"
ll_hits=0
report_hits md "$md_files"
report_hits sh "$sh_files"
[ "$ll_hits" -eq 0 ] && say "  OK   no anomalous line length inside a wrapped block"

# --- signal 2: dead relative markdown links --------------------------------------------------------
# Reuses $md_files from signal 1 above rather than a second `git ls-files '*.md'` — same file set,
# no reason to ask git twice. Also reuses signal 1's blank_fenced_blocks() pre-pass, for the same
# reason signal 1 needs it: a fenced example illustrating link syntax (`[text](target)`) must not be
# parsed as a real link — a doc about drydock/prose-drift itself is exactly the place such an example
# would show up, and an illustrative target that doesn't resolve would otherwise read as a real dead
# link (a hard GAP), not a WARN.
say ""
say "● signal 2 — dead relative markdown links"
dead=0
# Same empty-list guard as report_hits()'s `[ -n "$files" ] || return 0` above — an `<<<` herestring
# on an empty variable feeds one spurious empty-string iteration rather than zero. Shaped as an `if`
# here instead of an early return because this is top-level script body, not a function: `return`
# is only valid inside one.
if [ -n "$md_files" ]; then
  while IFS= read -r f; do
    dir=$(dirname "$f")
    while IFS=: read -r ln target; do
      t="${target%%#*}"                                   # strip anchor
      case "$t" in http*|mailto:*|"") continue ;; esac
      if [ ! -e "$repo_dir/$dir/$t" ] && [ ! -e "$repo_dir/$t" ]; then
        gap "$f:$ln → \`$target\` does not resolve"
        dead=$((dead + 1))
      fi
    done < <(blank_fenced_blocks "$repo_dir/$f" | grep -onE '\]\(([^)]+)\)' | sed -E 's/:\]\(/:/; s/\)$//')
  done <<< "$md_files"
fi
[ "$dead" -eq 0 ] && say "  OK   no dead relative markdown links"

say ""
[ "$exit_code" = 0 ] && say "prose-drift: OK ($ll_hits line-length lead(s), advisory only)"
exit "$exit_code"
