#!/usr/bin/env bash
# tools/drydock/inventory.sh — drydock phase 0: freeze the audit scope as code.
#
# Adopter-facing: run it on YOUR repo, in a clean tree at the commit you are auditing, and redirect
# stdout into your run's working directory. It measures what a drydock pass will read (every tracked
# markdown file whole; every tracked shell file's comment prose) and derives the per-auditor batches
# from that measurement, so the run's scope is a reproducible artifact instead of a hand-drawn list
# that quietly disagrees with the tree. Full procedure: docs/drydock.md. Flags: --help.
#
# The refusals are the point, not a formality. Drydock run 1's very first execution measured the
# WRONG TREE: it was launched with cwd = the main checkout, which happened to be sitting on a peer
# session's branch two commits off the baseline, and it reported those numbers without a murmur — a
# whole audit scoped against a commit nobody chose. So this script refuses unless HEAD is exactly the
# baseline commit and the working tree is clean, and there is deliberately no --force. The escape
# hatch is `--baseline <rev>`, which is not a bypass but the opposite: you name the commit you meant,
# it goes in the output header, and the run stays reproducible.
#
# Exit codes: 0 measured · 2 bad arguments · 3 refused to measure (not a repo / wrong HEAD / dirty).
#
# Tuning, for a repo whose shape differs from the defaults (all optional, all environment):
#   DRYDOCK_SCOPE_A              scope-A pathspecs, space-separated  (default: *.md)
#   DRYDOCK_SCOPE_B              scope-B pathspecs, space-separated. UNSET (the default) is not the
#                                same as passing '*.sh': the default also picks up tracked files
#                                whose shebang says shell but whose name doesn't (a CLI entry point,
#                                a git hook), via tools/self/shellcheck-targets.sh — the repo's
#                                canonical "which tracked files are shell scripts" selection. Setting
#                                this switches to a plain pathspec match, shebangs included only if a
#                                pathspec happens to catch them.
#   DRYDOCK_HISTORICAL           files under the historical-prose rule, always their own batch —
#                                EXACT repo-relative paths, not pathspecs (default: CHANGELOG.md;
#                                see docs/drydock.md, phase 1)
#   DRYDOCK_SCOPE_C              scope-C pathspecs, space-separated. Same UNSET-is-not-'*.sh' rule as
#                                DRYDOCK_SCOPE_B, and by default resolves through the SAME selector, so
#                                an unset scope B and an unset scope C name the identical file set —
#                                that is by design, not a coincidence two copies happen to agree on
#                                (see docs/drydock.md's scope-C section for why the overlap is fine).
#                                An empty value (`DRYDOCK_SCOPE_C=`) is UNSET too, same as scope B —
#                                to disable scope C, name a pathspec matching nothing, canonically
#                                `DRYDOCK_SCOPE_C=':!*'`.
#   DRYDOCK_INVARIANT_PATHS      code-invariant files that get a per-file marker in scope C's output —
#                                EXACT repo-relative paths, not pathspecs and not substrings (default:
#                                install.sh uninstall.sh keel tools/pre-pr-gate.sh
#                                tools/install-pre-pr-gate.sh tools/install-secret-guard.sh
#                                tools/secret-guard/secret-scan.sh tools/secret-guard/ci-scan.sh
#                                tools/secret-guard/range-lib.sh tools/secret-guard/pre-commit
#                                tools/secret-guard/pre-push). Marking is per file, not per batch: the
#                                orchestrator reads the marker and routes that file's whole batch to
#                                higher effort — see docs/drydock.md's Model lines.
#   DRYDOCK_SOLO_LINES           a scope-A file this long gets a session to itself (default: 500)
#   DRYDOCK_BATCH_LINES          scope-A lines per packed batch (default: 600)
#   DRYDOCK_COMMENT_BATCH_LINES  scope-B comment lines per packed batch (default: 1200 — comments
#                                are terser units than doc prose; run 1 raised this from 600 after
#                                measuring, and it is the one batching parameter a first run should
#                                expect to re-tune)
#   DRYDOCK_CODE_BATCH_LINES     scope-C lines per packed batch (default: 4500 — a guess to re-tune
#                                after the first code-scope run, the same honest framing
#                                DRYDOCK_COMMENT_BATCH_LINES's own header entry uses)
#
# A scope-B "comment line" is a line whose first non-blank character is `#` — shebang included, and
# an end-of-line comment after code NOT counted. That is a sizing heuristic, not a prose census. It
# is also shell-shaped: point DRYDOCK_SCOPE_B at a `//`- or `/* */`-comment language and every file
# measures 0 comment lines rather than erroring, which is a meaningless inventory, not a small one.
# Scope C measures the SAME files in total lines instead — whole-file code review, not a prose census
# — and inherits the identical shell-shaped caveat: point it at a `//`-language repo and the method
# (this script's batching; the auditor's shellcheck/spot-break technique) stays per-language, one
# honest sentence rather than a feature.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: inventory.sh [--baseline <rev>] [--prev <rev>]

Freeze a drydock run's scope. Measures the tracked prose surface at the baseline commit and derives
the per-auditor batches. Writes markdown to stdout; redirect it into your run's working directory.

  --baseline <rev>  the commit this run audits (default: origin/main). HEAD must equal it.
  --prev <rev>      a prior run's baseline; files changed since it are flagged CHANGED and the
                    derived batches cover only those files (incremental run).
  -h, --help        this message.

Refuses (exit 3) outside a git repository, on a dirty working tree, or when HEAD is not the
baseline. There is no bypass flag: name the commit with --baseline instead.

Tuning environment variables are documented in this file's header.
EOF
}

die_args() { printf 'drydock inventory: %s\n' "$1" >&2; exit 2; }
refuse()   { printf 'drydock inventory: %s\n' "$1" >&2; exit 3; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
baseline_rev="origin/main"
prev_rev=""
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) [ $# -ge 2 ] || die_args "--baseline needs a rev"; baseline_rev="$2"; shift 2 ;;
    --prev)     [ $# -ge 2 ] || die_args "--prev needs a rev";     prev_rev="$2";     shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die_args "unknown option '$1' (see --help)" ;;
    *)          die_args "unexpected argument '$1' — a prior run's baseline goes to --prev <rev>" ;;
  esac
done

# --- the guard ------------------------------------------------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || refuse "not a git repository (run this inside the tree you are auditing)"
# Measure the repo, not the cwd: a run launched from a subdirectory must still see the whole tree.
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

baseline="$(git rev-parse --verify --quiet "${baseline_rev}^{commit}" || true)"
[ -n "$baseline" ] || die_args "cannot resolve baseline '$baseline_rev' — fetch first (git fetch
  --prune), or name the commit yourself with --baseline <rev>. The default is origin/main; a repo
  whose default branch is not 'main', or one with no remote at all, has to pass --baseline."

prev=""
if [ -n "$prev_rev" ]; then
  prev="$(git rev-parse --verify --quiet "${prev_rev}^{commit}" || true)"
  [ -n "$prev" ] || die_args "cannot resolve --prev '$prev_rev' — it should be a PRIOR drydock run's
  baseline SHA, as recorded in that run's inventory header."
fi

head_sha="$(git rev-parse --verify --quiet HEAD || true)"
[ -n "$head_sha" ] || refuse "this repository has no commits yet (unborn HEAD) — there is nothing to
measure. Check out the baseline commit first."
if [ "$head_sha" != "$baseline" ]; then
  refuse "refusing to measure this tree — HEAD is not the baseline.
  HEAD     $head_sha ($(git rev-parse --abbrev-ref HEAD))
  baseline $baseline ($baseline_rev)
An inventory measured off the baseline scopes the whole audit against a commit nobody chose — run 1
did exactly this and did not notice. Measure in a worktree frozen at the baseline:
  git worktree add ../drydock-baseline $baseline
or, if this tree really is the commit you meant to audit, say so:
  --baseline $head_sha"
fi

dirty="$(git status --porcelain)"
if [ -n "$dirty" ]; then
  refuse "refusing to measure a dirty working tree — the numbers would describe no commit at all.
$(printf '%s\n' "$dirty" | head -10 | sed 's/^/  /')
Commit, stash, or discard the above; if it is the audit run's own output, gitignore that directory
(ignored files are not dirt and are already excluded here)."
fi

# --- scope ----------------------------------------------------------------------------------------
read -r -a scope_a <<< "${DRYDOCK_SCOPE_A:-*.md}"
read -r -a scope_b <<< "${DRYDOCK_SCOPE_B:-}"   # no default here on purpose: an UNSET scope B is not
                                                # the `*.sh` pathspec, it is the selection below.
read -r -a scope_c <<< "${DRYDOCK_SCOPE_C:-}"   # same convention as scope B, same reason.
read -r -a historical <<< "${DRYDOCK_HISTORICAL:-CHANGELOG.md}"
read -r -a invariant_paths <<< "${DRYDOCK_INVARIANT_PATHS:-install.sh uninstall.sh keel \
  tools/pre-pr-gate.sh tools/install-pre-pr-gate.sh tools/install-secret-guard.sh \
  tools/secret-guard/secret-scan.sh tools/secret-guard/ci-scan.sh tools/secret-guard/range-lib.sh \
  tools/secret-guard/pre-commit tools/secret-guard/pre-push}"
solo_lines="${DRYDOCK_SOLO_LINES:-500}"
batch_lines="${DRYDOCK_BATCH_LINES:-600}"
comment_batch_lines="${DRYDOCK_COMMENT_BATCH_LINES:-1200}"
code_batch_lines="${DRYDOCK_CODE_BATCH_LINES:-4500}"

TAB="$(printf '\t')"
NL=$'\n'   # a literal, NOT "$(printf '\n')" — command substitution strips trailing newlines, so that
           # spelling silently yields the empty string and any delimiter built from it disappears.

# The changed set is fetched ONCE and matched in-shell: a `git diff` per file would be a fork per
# file for a fact one diff already knows. Wrapped in newlines — with the trailing one appended
# explicitly, since `$(...)` would have eaten it — so the membership test below cannot match a path
# that merely shares a prefix or suffix with a changed one.
changed_set=""   # built below, once the scratch dir exists — see "the changed set".

is_changed() {
  [ -n "$prev" ] || return 1
  case "$changed_set" in *"$NL$1$NL"*) return 0 ;; esac
  return 1
}

# Exact-match array membership, shared by is_historical() and is_invariant() below — both need "is
# this exact path in this list", differing only in which list.
array_contains() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

is_historical() { [ "${#historical[@]}" -gt 0 ] && array_contains "$1" "${historical[@]}"; }

# EXACT-path membership, deliberately not the substring match tools/delta-audit/derive.sh's own
# DELTA_INVARIANT_PATHS uses — that env's default entries are substrings by design, and would match
# zero files if compared exactly here; porting the shape without the semantics would silently mark
# nothing invariant.
is_invariant() { [ "${#invariant_paths[@]}" -gt 0 ] && array_contains "$1" "${invariant_paths[@]}"; }

# --- measurement ----------------------------------------------------------------------------------
# Measured ONCE per file, into a stream both the listing and the batching read from — an earlier
# version measured every file twice (once to list it, once to size its batch), which is two forks and
# two code paths that can only agree by coincidence. One awk per file yields both counts: line count
# via NR (not `wc -l`, which counts newlines and so undercounts a file with no trailing newline, and
# pads its output with whitespace on some platforms) and comment lines in the same pass.
# Stream shape, one line per file: path <TAB> lines <TAB> comment-lines
#
# A file this cannot READ is a refusal, never a silent omission. An in-scope file that git lists but
# awk cannot open (a sparse checkout, a tracked broken symlink, a permissions oddity) would otherwise
# drop out of the artifact with the run still exiting 0 — an inventory quietly disagreeing with the
# tree, which is the entire failure class this script's guard exists to stop. BSD awk exits 0 on an
# unopenable file, and errexit does not fire inside a command substitution's assignment, so neither
# the status nor `set -e` would have caught it: the check has to be explicit.
measure() {
  [ "$#" -gt 0 ] || return 0
  local f
  for f in "$@"; do
    [ -r "$f" ] || refuse "cannot read '$f', which is in scope and tracked at this commit.
Refusing rather than omitting it: a partial inventory is indistinguishable from a small tree. If this
is a sparse checkout, widen it (git sparse-checkout disable) and measure the whole tree."
    # Two separate awk hazards, two separate defences, both about the PATH rather than the contents:
    #   1. The path goes through the ENVIRONMENT, not `-v F=…` — awk runs escape-sequence processing
    #      on a -v assignment, so a filename containing a literal backslash-t would arrive as a real
    #      tab, corrupting not just the path but this record's own tab-separated shape.
    #   2. The operand is `./$f`, never a bare `$f` — awk reads an operand shaped `name=value` as a
    #      variable assignment and an operand starting `-` as an option, so a top-level file called
    #      `a=b.md` was never opened at all: NR stayed 0 and it was listed as an EMPTY file at exit 0,
    #      with `[ -r ]` passing because the file is perfectly readable. A silent under-report that
    #      looks plausible is worse than the visible error it replaced. Paths are repo-relative and
    #      cwd is the repo root, so `./` always resolves, and ENVIRON["F"] still prints it unprefixed.
    F="$f" awk '/^[[:space:]]*#/ { c++ } END { printf "%s\t%d\t%d\n", ENVIRON["F"], NR, c }' "./$f"
  done
}

# Every enumeration below is NUL-delimited (`-z`), and that is a correctness requirement, not a
# style: git C-quotes any path it cannot print literally, and a quoted string is not a path anyone can
# open — so the file would trip measure()'s readability refusal above for a reason that is git's
# output format rather than anything wrong with the tree. `-c core.quotePath=false` fixes only the
# non-ASCII half; a backslash or a double quote is quoted regardless. `-z` is the whole fix.
scope_a_files() {
  [ "${#scope_a[@]}" -gt 0 ] || return 0
  git ls-files -z -- "${scope_a[@]}"
}

# Unset DRYDOCK_SCOPE_B means "every tracked shell script", which is NOT the same as the `*.sh`
# pathspec: a CLI entry point or a git hook is a shell script with no extension. That selection
# already has one canonical implementation in this repo — tools/self/shellcheck-targets.sh, which
# ci.yml and tools/self/doctor.sh both call rather than each keeping a copy — so this calls it too
# instead of minting a third. The inline fallback keeps the script standalone if it is ever copied
# out of a Keel checkout on its own.
# Every branch returns the STATUS OF ITS OWN ENUMERATION, never a blanket `return 0` — that would
# discard exactly the failure the caller's `|| refuse` is there to catch, leaving the guard dead and
# an empty scope reported at exit 0. The inline fallback needs the opposite care for the opposite
# reason: `git ls-files | while …` ends with the last iteration's status, so on a repo whose last
# tracked file is not a script the trailing `grep -q` would make a healthy enumeration look failed.
# So the fallback observes git's status explicitly and returns 0 for the loop.
#
# Shared by scope B and scope C: both default to this exact selection, and factoring it into one
# function makes that identity structural rather than two copies that happen to agree today and
# silently diverge the next time either one is edited.
default_shell_files() {
  local selector="$script_dir/../self/shellcheck-targets.sh"
  if [ -r "$selector" ]; then
    # The selector's own output is newline-delimited (its consumers require that), so convert. Its
    # paths are already unquoted — it reads `ls-files -z` internally — which is what makes this
    # conversion lossless for everything the format check below accepts.
    bash "$selector" "$repo_root" | tr '\n' '\0'
    return $?
  fi
  local f tracked
  tracked="$(git ls-files -z | tr '\0' '\n')" || return $?
  # `if … then … fi` for the same reason the selector uses it: a non-match is the ordinary outcome,
  # and as the loop body's last command it would become the `while`'s status. Here the trailing
  # `return 0` would in fact cover it — but relying on that is the reasoning that already failed one
  # directory over, so the loop is made structurally safe rather than contextually safe.
  printf '%s\n' "$tracked" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      *.sh) printf '%s\0' "$f" ;;
      *) if head -1 -- "$f" 2>/dev/null \
              | grep -qE '^#!.*[ /](ba|da|k)?sh([[:space:]]|$)'; then
           printf '%s\0' "$f"
         fi ;;
    esac
  done
  return 0
}

scope_b_files() {
  if [ -n "${DRYDOCK_SCOPE_B:-}" ]; then
    [ "${#scope_b[@]}" -gt 0 ] || return 0
    git ls-files -z -- "${scope_b[@]}"
    return $?
  fi
  default_shell_files
}

# Same convention as scope B (unset or empty means the default shell-file selection, not the `*.sh`
# pathspec); default_shell_files() above is what makes the two selections identical by construction
# when both are left unset, per docs/drydock.md's scope-C section.
scope_c_files() {
  if [ -n "${DRYDOCK_SCOPE_C:-}" ]; then
    [ "${#scope_c[@]}" -gt 0 ] || return 0
    git ls-files -z -- "${scope_c[@]}"
    return $?
  fi
  default_shell_files
}

# Enumerated through a temporary FILE, not a variable and not `< <(…)`. Three constraints meet here:
# the list is NUL-delimited (a variable cannot hold NUL at all); the enumeration's exit status has to
# be observable (a process substitution's is not — a failing `git ls-files` or selector would leave
# the loop with zero iterations and report an empty tree at exit 0, the silent-omission class one
# level up from measure()'s); and the refusal has to run in THIS shell, since `refuse` calls `exit`
# and an `exit` inside a command substitution would only end a subshell. Writing to a file, checking
# the status, then reading it back is the one shape that satisfies all three. No `| sort`: git
# already emits index order, which is sorted, and the selector's own list comes from the same source.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

scope_a_files > "$scratch/a" \
  || refuse "could not enumerate scope A — git failed. Nothing was measured; fix that error rather
than trusting a short inventory."
scope_b_files > "$scratch/b" \
  || refuse "could not enumerate scope B — git, or the shell-script selector, failed. Nothing was
measured; fix that error rather than trusting a short inventory."
scope_c_files > "$scratch/c" \
  || refuse "could not enumerate scope C — git, or the shell-script selector, failed. Nothing was
measured; fix that error rather than trusting a short inventory."

# A tab or a newline inside a path would break this script's own `path<TAB>lines<TAB>comments` stream
# — the tab silently shifts every later field, the newline splits one record into two — so such a
# path is refused outright rather than measured into a corrupt artifact. Both are legal in git, and
# both are vanishingly rare; refusing is the honest floor until the whole pipeline is NUL-delimited.
assert_representable() {
  case "$1" in
    *"$TAB"*) refuse "the path '$1' contains a tab, which this inventory's own record format cannot
represent. Rename it, or narrow the scope to exclude it." ;;
    *"$NL"*) refuse "the path '$1' contains a newline, which this inventory's own record format
cannot represent. Rename it, or narrow the scope to exclude it." ;;
  esac
}

files_a=()
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  assert_representable "$f"
  files_a+=("$f")
done < "$scratch/a"
files_b=()
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  assert_representable "$f"
  files_b+=("$f")
done < "$scratch/b"
files_c=()
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  assert_representable "$f"
  files_c+=("$f")
done < "$scratch/c"

# The changed set — the THIRD enumeration, and it gets the same treatment as the two above, for the
# same reason: a `git diff` whose failure went unchecked would yield an empty set, which is
# indistinguishable from "nothing changed" and would make an incremental run silently audit nothing.
# `-z` here too, so a path matches the ones enumerated above byte for byte.
if [ -n "$prev" ]; then
  git diff --name-only -z "$prev" "$baseline" > "$scratch/changed" \
    || refuse "could not diff $prev..$baseline — the incremental scope is unknown. Nothing was
measured; an empty changed set would read as 'nothing drifted', which is not what happened."
  while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    changed_set="$changed_set$f$NL"
  done < "$scratch/changed"
  changed_set="$NL$changed_set"
fi

# `|| exit $?` is load-bearing for the same reason: measure()'s readability refusal fires inside this
# command substitution, so its exit ends only the subshell — this propagates the status outward.
stream_a=""
[ "${#files_a[@]}" -gt 0 ] && { stream_a="$(measure "${files_a[@]}")" || exit $?; }
stream_b=""
[ "${#files_b[@]}" -gt 0 ] && { stream_b="$(measure "${files_b[@]}")" || exit $?; }
stream_c=""
[ "${#files_c[@]}" -gt 0 ] && { stream_c="$(measure "${files_c[@]}")" || exit $?; }

# --- output -----------------------------------------------------------------------------------
printf '# drydock inventory @ %s\n' "$baseline"
printf 'baseline rev: %s | generated by tools/drydock/inventory.sh\n' "$baseline_rev"
[ -n "$prev" ] && printf 'previous baseline: %s\n' "$prev"

# render STREAM FIELD UNIT [mark_invariant] — list one scope and set the reply variables below. The
# counters come back in globals rather than on stdout because the listing itself is what goes to
# stdout. The optional 4th argument is scope C's own: every other caller leaves it unset, so is_
# invariant() is never even consulted for scope A or B, which have no such marker.
render_files=0 render_total=0 render_changed=0 render_invariant=0
render() {
  local path lines comments n flag
  render_files=0; render_total=0; render_changed=0; render_invariant=0
  [ -n "$1" ] || return 0
  while IFS="$TAB" read -r path lines comments; do
    [ -n "$path" ] || continue
    if [ "$2" = lines ]; then n="$lines"; else n="$comments"; fi
    flag=""
    if is_changed "$path"; then flag="$flag CHANGED"; render_changed=$((render_changed + 1)); fi
    if [ "${4:-}" = mark_invariant ] && is_invariant "$path"; then
      flag="$flag INVARIANT"; render_invariant=$((render_invariant + 1))
    fi
    printf -- '- %s%s%s %s%s\n' "$path" "$TAB" "$n" "$3" "$flag"
    render_files=$((render_files + 1)); render_total=$((render_total + n))
  done <<< "$1"
}

printf '\n## scope A — tracked markdown (audited whole-file)\n\n'
render "$stream_a" lines ln
printf '\nscope A total: %s files, %s lines' "$render_files" "$render_total"
[ -n "$prev" ] && printf ' (%s changed since the previous baseline)' "$render_changed"
printf '\n'

printf '\n## scope B — shell comment prose (audited comment blocks only)\n\n'
render "$stream_b" comments comment-ln
printf '\nscope B total: %s files, %s comment lines' "$render_files" "$render_total"
[ -n "$prev" ] && printf ' (%s changed since the previous baseline)' "$render_changed"
printf '\n'

printf '\n## scope C — shell code (audited whole-file)\n\n'
render "$stream_c" lines ln mark_invariant
printf '\nscope C total: %s files, %s lines' "$render_files" "$render_total"
[ -n "$prev" ] && printf ' (%s changed since the previous baseline)' "$render_changed"
printf ' (%s invariant)' "$render_invariant"
printf '\n'

# One auditor session per batch. Packing is by directory affinity (adjacent files share context, so
# one reader re-derives less), size-descending within a directory so the big file anchors its batch.
if [ -n "$prev" ]; then
  printf '\n## derived batches — CHANGED files only (incremental scope since %s)\n' "$prev"
else
  printf '\n## derived batches — every file in scope (full run)\n'
fi
printf 'rules: historical-prose files always solo; scope-A file >%s ln solo; else pack by directory\n' "$solo_lines"
printf 'to <=%s ln per session; scope B packs to <=%s comment-ln per session; scope C packs to\n' \
  "$batch_lines" "$comment_batch_lines"
printf '<=%s ln per session, invariant files marked per-file, never solo.\n\n' "$code_batch_lines"

# batch_stream STREAM FIELD MODE [mark_invariant] — re-shape a measured stream into
# dir<TAB>size<TAB>path<TAB>flag for pack(), dropping anything out of this run's scope. MODE
# `ordinary` drops the historical files (they are emitted as their own SPECIAL batches by
# `historical_batches` below, from this same stream — never by a second git query, which could
# otherwise name a file no scope actually listed). The trailing flag field is scope C's own — every
# other caller leaves the 4th argument unset, so it always prints empty and pack() below is a no-op
# for that column on scope A/B.
batch_stream() {
  local path lines comments n dir flag
  [ -n "$1" ] || return 0
  while IFS="$TAB" read -r path lines comments; do
    [ -n "$path" ] || continue
    [ -z "$prev" ] || is_changed "$path" || continue
    [ "$3" = ordinary ] && is_historical "$path" && continue
    if [ "$2" = lines ]; then n="$lines"; else n="$comments"; fi
    dir="${path%/*}"; [ "$dir" = "$path" ] && dir="."
    flag=""
    [ "${4:-}" = mark_invariant ] && is_invariant "$path" && flag="INVARIANT"
    printf '%s%s%s%s%s%s%s\n' "$dir" "$TAB" "$n" "$TAB" "$path" "$TAB" "$flag"
  done <<< "$1"
}

historical_batches() {
  local path lines comments
  [ -n "$1" ] || return 0
  while IFS="$TAB" read -r path lines comments; do
    [ -n "$path" ] || continue
    [ -z "$prev" ] || is_changed "$path" || continue
    is_historical "$path" || continue
    printf 'batch: %s SPECIAL (historical-prose rule)\n' "$path"
  done <<< "$1"
}

# $1 = prefix, $2 = solo threshold (0 = never solo), $3 = cap, $4 = unit label. Reads
# dir<TAB>size<TAB>path<TAB>flag records; the flag prints as a trailing " INVARIANT" when batch_stream
# set one, empty otherwise — scope A/B's records always carry an empty 4th field, so their output is
# byte-for-byte unchanged from before this column existed.
pack() {
  sort -t"$TAB" -k1,1 -k2,2rn | awk -F"$TAB" \
    -v prefix="$1" -v solo="$2" -v cap="$3" -v unit="$4" '
    BEGIN { bn = 0; acc = 0; cur = "" }
    { dir = $1; n = $2 + 0; f = $3; suffix = ($4 != "" ? " " $4 : "") }
    solo > 0 && n > solo { printf "batch: %s SOLO (%d %s)%s\n", f, n, unit, suffix; next }
    dir != cur || acc + n > cap { cur = dir; acc = 0; bn++ }
    { acc += n; printf "batch %s%d: %s (%d %s)%s\n", prefix, bn, f, n, unit, suffix }
  '
}

batch_stream "$stream_a" lines ordinary | pack "" "$solo_lines" "$batch_lines" ln
historical_batches "$stream_a"
printf '\n'
batch_stream "$stream_b" comments all | pack B 0 "$comment_batch_lines" comment-ln
printf '\n'
batch_stream "$stream_c" lines all mark_invariant | pack C 0 "$code_batch_lines" ln
