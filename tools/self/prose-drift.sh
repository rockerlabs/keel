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
#   GAP   dead relative markdown link — a `[text](target)` whose target does not resolve, OR whose
#         `#anchor` half names no heading in the resolved file. Resolution is sibling-relative to the
#         linking file ONLY, matching how GitHub itself resolves a relative link (dir #217 — an
#         earlier repo-root fallback made a link dead for a real reader while this signal still called
#         it green; dropped outright, so there is no second root to document). Almost zero legitimate
#         exceptions (a link either resolves, anchor included, or it doesn't), so this one is a hard
#         fail, unlike signal 1 — with ONE stated, narrow exception (dir #240 item 2): this signal's own
#         heading slugger is ASCII-only (see `_heading_slugs` below) and does not match GitHub's on a
#         heading containing a non-ASCII LETTER (an accented Latin character, a non-Latin script) —
#         non-ASCII punctuation such as an em dash is unaffected, since both sluggers strip it the same
#         way. An anchor that fails to resolve for that specific, narrow reason (the anchor text itself
#         carries a non-ASCII letter) downgrades to an advisory WARN instead of a GAP; every other dead
#         anchor or dead file target stays a hard GAP. No GitHub-compatible Unicode slugger is in scope
#         here — that would be a materially bigger change for a defect this tool cannot reach anyway
#         (keel-self-maintenance, never installed for an adopter).
#
# Usage:
#   tools/self/prose-drift.sh [REPO_DIR] [--quiet]
#   tools/self/prose-drift.sh -h | --help
#
# REPO_DIR defaults to the current directory, but must be a git checkout (dir #240 item 1): both
# signals enumerate tracked files via `git ls-files`, with no `|| true` on that call (dir #191's own
# comment below explains why), so a non-git REPO_DIR is rejected up front with a labeled exit-2 error
# instead of reaching git and aborting on its own raw, unlabeled "fatal: not a git repository" — the
# file's own test fixtures are all real git checkouts (mk_repo_with commits every one), so there is no
# non-git-fixture caller for a degrade path to serve; day-to-day this is invoked by
# tools/self/doctor.sh, which always passes its own resolved (git) repo root.
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
# dir #240 item 1: same shape as the -d check just above (a labeled, expected exit-2 for a bad input),
# not the raw `fatal: not a git repository` git itself would print once md_files's own `git ls-files`
# below runs uncaught. -C here is deliberate over a plain `cd`: it fails the same "not a git repository"
# way for a REPO_DIR that exists but was never checked out, without moving this script's own cwd.
# The OUTPUT is checked, not just the exit status (found live by /code-review medium on this ticket's
# own diff): `--is-inside-work-tree` exits 0 and prints "false" for a bare repo (verified live), which
# an exit-status-only check would have let straight through to a silent, empty `git ls-files` scan —
# this REPO_DIR check exists to reject exactly that kind of REPO_DIR that "isn't what this tool needs,"
# not only the git-refuses-outright case.
repo_check_out="$(git -C "$repo_dir" rev-parse --is-inside-work-tree 2>&1)" || true
if [ "$repo_check_out" != true ]; then
  case "$repo_check_out" in
    # A dubious-ownership fatal (this project's own documented Alpine/Docker CI trap, CLAUDE.md's
    # third trap, dir #191/#230/#249) is a DIFFERENT, already-catalogued failure from "not a git
    # repository at all" — collapsing it into this script's own generic message would send a session
    # investigating a real dubious-ownership case down the wrong path (found live by /code-review
    # medium: this exact regression was in the diff's first version). Let git's own diagnostic through
    # unmodified instead of overwriting it.
    *"dubious ownership"*) echo "prose-drift.sh: $repo_check_out" >&2 ;;
    *) echo "prose-drift.sh: not a git repository: $repo_dir" >&2 ;;
  esac
  exit 2
fi

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
  # real, if small, cost across 75 tracked shell scripts); md still needs blank_fenced_blocks' own
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

# No `|| true` here (dir #191): a container reading a bind-mounted repo it does not own used to make
# `git` itself fail outright ("detected dubious ownership", exit 128), felt live on this project's own
# alpine-busybox CI leg. That leg is now closed at the container level — `.github/workflows/ci.yml`'s
# alpine step runs `git config --system --add safe.directory '*'` before any test executes. `--system`,
# not `--global`: `tests/lib.sh` sandboxes every test file's `HOME`/`GIT_CONFIG_GLOBAL` to a fresh
# per-run path (dir #64), which shadows the global config scope outright, so a `--global` write made
# before that override becomes invisible to any git call the test suite itself makes afterward — system
# scope is a separate file (`/etc/gitconfig`) that override never touches, so it reaches every git call
# in the container, this one included. This assignment can therefore fail loudly on a real git failure
# instead of degrading silently to an empty file list, same as `sh_files` just below (its own `|| true`
# is unrelated — grep's zero-match exit, not a git guard).
md_files="$(git -C "$repo_dir" ls-files '*.md' | sort)"
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

# --- signal 2: dead relative markdown links and dead in-document anchors ---------------------------
# Reuses $md_files from signal 1 above rather than a second `git ls-files '*.md'` — same file set,
# no reason to ask git twice. Also reuses signal 1's blank_fenced_blocks() pre-pass, for the same
# reason signal 1 needs it: a fenced example illustrating link syntax (`[text](target)`) must not be
# parsed as a real link — a doc about drydock/prose-drift itself is exactly the place such an example
# would show up, and an illustrative target that doesn't resolve would otherwise read as a real dead
# link (a hard GAP), not a WARN. The link-extraction pipeline below additionally blanks INLINE code
# spans (dir #240 item 3, tools/lib/fence-blank.sh's blank_inline_code_spans) — a fenced block is not
# the only place a link-shaped token can be quoted rather than meant: a doc illustrating one inline,
# inside backticks, is the same false-positive shape one level down, found live while writing the
# `[0.7.1]` release note's own Known-issues paragraph.

# Slugs for FILE's own ATX headings (`#` through `######`), in document order, GitHub-flavored,
# de-duplicated as one stream (not per-heading) — a second heading slugging to the same value anchors
# at `#slug-1`, a third at `#slug-2`, and so on, same as GitHub's own collision suffix.
#
# _ascii_fold is factored out (dir #240 item 2) so the anchor-side causation check further below
# applies the IDENTICAL fold to an anchor, not a second hand-written copy that could drift from this
# one — the same "one shared toggle, not two copies" discipline blank_fenced_blocks/
# blank_inline_code_spans already follow in tools/lib/fence-blank.sh. It lowercases, drops everything
# but [a-z0-9 _-], then hyphenates each remaining space — GitHub does NOT collapse a run of spaces into
# one hyphen, it hyphenates each one (verified live against this tree's own docs/getting-started.md:
# "Linked install — recommended on Claude Code" slugs to `linked-install--recommended-on-claude-code`,
# the double hyphen is where the em dash's surrounding spaces both survived). `tr '\t' ' '` runs first
# so a literal tab hyphenates the same way a space does instead of being silently dropped by the
# character-class strip. `LC_ALL=C` makes that strip byte-wise rather than locale-dependent, so a
# multi-byte character is stripped as raw bytes — correct for a punctuation mark GitHub also strips (an
# em dash), but it means a non-ASCII LETTER is stripped too, where GitHub's own slugger keeps Unicode
# word characters. Every in-document anchor target in this tracked tree points at an ASCII plain-text
# heading, so this signal doesn't need real Unicode handling to do its job today.
_ascii_fold() {
  tr '\t' ' ' \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}
_heading_slugs() {
  local file="$1"
  [ -f "$file" ] || return 0
  # The 3rd substitution trims bare trailing whitespace left behind once the trailing-`#` strip runs
  # (a heading with no closing `#`s but a stray trailing space — an editor artifact, or markdown's own
  # two-space line-break convention) — without it, that space survives to _ascii_fold's `s/ /-/g` and
  # produces a slug with a spurious trailing hyphen that never matches a real link's anchor. No
  # DELIBERATE inline-markup stripping: backtick/asterisk `code`/**bold** markers happen to slug
  # correctly anyway, as a side effect of _ascii_fold's own punctuation strip, but a real markdown LINK
  # inside a heading (`[text](url)`) would leak the URL into the slug instead of using only the visible
  # text the way GitHub's own slugger does — out of scope here since no in-document anchor target in
  # this tracked tree points at a heading like that. blank_fenced_blocks keeps a heading-looking line
  # inside a fenced illustrative example from counting as a real heading, same as signal 1 and the link
  # scan below.
  blank_fenced_blocks "$file" \
    | grep -E '^#+[[:space:]]' \
    | sed -E 's/^#+[[:space:]]+//; s/[[:space:]]+#+[[:space:]]*$//; s/[[:space:]]+$//' \
    | _ascii_fold \
    | awk '{ if (seen[$0]++) print $0 "-" seen[$0]-1; else print $0 }'
}

# Percent-decode a link target before touching the filesystem (dir #224): `%20` and friends are
# CommonMark-legal and GitHub renders them as the literal character, so an encoded-but-otherwise-valid
# target must not read as dead just because the raw percent-escape doesn't exist as a path on disk.
# Only a genuine `%XX` hex pair is turned into `\xHH` for `printf '%b'` to decode — a bare `%` with no
# following hex pair (a real target can legitimately contain one, e.g. `100%.md`) is left as a literal
# character instead of being blindly rewritten to `\x`, which `printf %b` would then reject outright
# ("missing hex digit for \x") rather than pass through. Any backslash ALREADY in the target (a real,
# if unusual, path fragment) is escaped to `\\` first — `printf %b` reinterprets its ENTIRE argument,
# not just the `\xHH` sequences this function itself injects, so a literal `\n`/`\t`/etc. in the raw
# target would otherwise be silently turned into a control character before the existence check runs.
_url_decode() {
  printf '%b' "$(printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/%([0-9A-Fa-f]{2})/\\x\1/g')"
}

# True if STRING contains a raw byte >= 0x80 — a cheap first filter, not itself the WARN-vs-GAP
# decision (see _anchor_fails_only_on_nonascii_letters below, which is). `$'[\x80-\xff]'` under
# LC_ALL=C is the same shape of idiom (a bash ANSI-C-quoted `$'[\xNN-\xNN]'` byte range fed to grep,
# with LC_ALL=C keeping grep comparing raw bytes instead of decoding multi-byte UTF-8 under the shell's
# own locale) already proven cross-platform (GNU/BSD/busybox) by tools/public-audit.sh and
# tools/secret-guard/secret-scan.sh's own Cyrillic-detection passes — narrower ranges there
# (`[\xd0-\xd3][\x80-\xbf]`, a specific two-byte UTF-8 lead/continuation pair), not this exact range.
_has_nonascii_byte() {   # _has_nonascii_byte STRING
  LC_ALL=C grep -q $'[\x80-\xff]' <<< "$1"
}

# dir #240 item 2 (tightened by /code-review medium — three independent angles converged on the same
# gap): true only when applying `_ascii_fold`'s IDENTICAL transform to ANCHOR would make it match a
# REAL heading slug in FILE — i.e. the ONLY reason the raw anchor failed `_heading_slugs`' own match is
# a non-ASCII byte the fold strips from a heading but GitHub's own slugger keeps (a genuine non-ASCII
# LETTER). A raw byte-PRESENCE check alone (this function's first version) downgraded ANY anchor
# containing a non-ASCII byte for ANY reason, including one that is ALSO wrong for an unrelated,
# ordinary reason — found live, independently, by three review angles: `#käytä-typo` against a real
# `## Käytä` heading (an ordinary ASCII typo riding along on a genuine non-ASCII anchor) and
# `#background—details` (a literal em dash typed into the anchor in place of a hyphen, not derived from
# a real heading) both downgraded to an advisory WARN under the presence-only check, though neither is
# a slugger-Unicode-gap case — both are ordinary dead links a hard GAP should still catch. Folding the
# anchor the identical way and checking it against a REAL heading's slug closes both: neither folded
# anchor above matches any real heading (`kyt-typo` and `backgrounddetails` respectively — the second
# has no hyphen at all, since folding a literal em dash strips it as a raw byte with no adjacent space
# to hyphenate, unlike a real heading's ASCII hyphen), so both correctly stay a hard GAP.
_anchor_fails_only_on_nonascii_letters() {   # _anchor_fails_only_on_nonascii_letters FILE ANCHOR
  local file="$1" anchor="$2"
  _has_nonascii_byte "$anchor" || return 1
  _heading_slugs "$file" | grep -xF -- "$(printf '%s' "$anchor" | _ascii_fold)" >/dev/null
}

say ""
say "● signal 2 — dead relative markdown links and anchors"
dead=0
anchor_warns=0
# Same empty-list guard as report_hits()'s `[ -n "$files" ] || return 0` above — an `<<<` herestring
# on an empty variable feeds one spurious empty-string iteration rather than zero. Shaped as an `if`
# here instead of an early return because this is top-level script body, not a function: `return`
# is only valid inside one.
if [ -n "$md_files" ]; then
  while IFS= read -r f; do
    dir=$(dirname "$f")
    while IFS=: read -r ln target; do
      case "$target" in
        *'#'*) file_part="${target%%#*}"; anchor="${target#*#}" ;;
        *)     file_part="$target"; anchor="" ;;
      esac
      # Anchored scheme match (dir #224's own review round): a bare `http*`/`mailto*` glob also matches
      # a real relative filename that merely happens to START with those letters (`http-notes.md`,
      # `mailto-list.md`) — anchoring on the scheme's own `://`/`:` terminator excludes those.
      case "$file_part" in http://*|https://*|mailto:*) continue ;; esac
      anchor="$(_url_decode "$anchor")"
      t="$(_url_decode "$file_part")"
      # Sibling-relative to the linking file (dir #217) is the DEFAULT — no bare repo-root fallback for
      # an otherwise-ambiguous target; a target that only "resolved" via that removed fallback was dead
      # for a real reader while this signal still called it green. A LEADING-SLASH target is a distinct,
      # unambiguous case, not that fallback: GitHub itself resolves `[x](/CHANGELOG.md)` against the
      # REPO ROOT, by the target's own explicit syntax, regardless of which file it's linked from — so
      # it gets its own resolution rule rather than being swept into "no second root" along with the
      # bare-relative case dir #217 actually fixed. An empty $t (a bare "#anchor" target) skips the
      # existence check below and resolves to THIS SAME file instead.
      case "$t" in
        /*) resolved="$repo_dir$t" ;;
        *)  resolved="$repo_dir/$dir/$t" ;;
      esac
      [ -z "$t" ] && resolved="$repo_dir/$f"
      if [ -n "$t" ] && [ ! -e "$resolved" ]; then
        gap "$f:$ln → \`$target\` does not resolve"
        dead=$((dead + 1))
        continue
      fi
      # Anchor validation only applies when the RESOLVED target is itself markdown — GitHub's ATX
      # heading anchors are a markdown-rendering feature, not a general file-viewer one, so a link
      # into a non-md file's own `#fragment` (e.g. a GitHub line anchor into a tracked `.sh` file) is
      # out of scope here, not a dead anchor. An empty $t (bare "#anchor", resolved to THIS file) is
      # always markdown, since this whole loop only ever runs over $md_files.
      case "$resolved" in *.md|*.markdown) is_md=1 ;; *) is_md=0 ;; esac
      # No `-q` on the grep below: under `set -o pipefail`, `-q` closes its read end the instant it
      # sees a match, and if that match isn't the LAST heading `_heading_slugs` emits, its still-
      # writing internal pipeline (awk feeding the final stage) gets SIGPIPE'd — a nonzero exit from
      # an EARLIER pipe stage that pipefail then reports as this pipeline's own status, even though
      # the match was genuinely found. Redirecting `grep`'s normal (non-`-q`) output to `/dev/null`
      # keeps the same found/not-found exit code without ever closing the pipe early. No per-file
      # cache of this pipeline's output either — bash 3.2 (this project's own macOS CI leg, and macOS's
      # own system `/usr/bin/env bash`) has no associative arrays to key one by resolved path, and a
      # linear-scan substitute would trade a straightforward re-read for indirection this signal's
      # existing per-line subshell cost doesn't otherwise need.
      # `--` before $anchor: a heading whose own text starts with `-` (rare, but legal markdown) slugs
      # to a leading-hyphen anchor, and grep would otherwise parse it as an option string and error.
      if [ -n "$anchor" ] && [ "$is_md" = 1 ] && ! _heading_slugs "$resolved" | grep -xF -- "$anchor" >/dev/null; then
        # dir #240 item 2, narrowed contract: a non-ASCII LETTER in the anchor is outside this signal's
        # stated ASCII-only slug contract (header, signal 2) — downgrade to an advisory WARN rather than
        # a hard GAP; every other dead anchor (a genuinely missing heading, a typo, or a non-ASCII anchor
        # that is ALSO wrong for an unrelated ordinary reason) stays a GAP —
        # _anchor_fails_only_on_nonascii_letters, not a bare byte-presence check, is what scopes this
        # correctly (see its own comment).
        if _anchor_fails_only_on_nonascii_letters "$resolved" "$anchor"; then
          warn "$f:$ln → \`$target\` anchor does not resolve (non-ASCII letters are outside signal 2's ASCII-only slug contract — advisory only)"
          anchor_warns=$((anchor_warns + 1))
        else
          gap "$f:$ln → \`$target\` anchor does not resolve"
          dead=$((dead + 1))
        fi
      fi
    done < <(blank_fenced_blocks "$repo_dir/$f" \
      | blank_inline_code_spans \
      | grep -onE '\]\(([^()]|\([^()]*\))*\)' \
      | sed -E 's/:\]\(/:/; s/\)$//')
  done <<< "$md_files"
fi
# dir #240 item 2 fix (found by /code-review medium): gate the "OK" line on BOTH counters, not just
# $dead — signal 1's own ll_hits already does this (below); before this fix, a WARN-only run (an
# anchor downgraded under the narrowed contract, zero real GAPs) still printed "OK no dead relative
# markdown links or anchors" directly under the WARN line it contradicts, which read as the WARN being
# decorative noise rather than an actual, if advisory, finding.
if [ "$dead" -eq 0 ] && [ "$anchor_warns" -eq 0 ]; then
  say "  OK   no dead relative markdown links or anchors"
elif [ "$dead" -eq 0 ]; then
  say "  OK   no dead relative markdown links or anchors ($anchor_warns non-ASCII-anchor WARN(s) above, advisory only)"
fi

say ""
[ "$exit_code" = 0 ] && say "prose-drift: OK ($ll_hits line-length lead(s), $anchor_warns anchor WARN(s), advisory only)"
exit "$exit_code"
